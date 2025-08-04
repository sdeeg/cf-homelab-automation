#Requires -Modules VCF.PowerCLI

<#
.SYNOPSIS
    Gracefully startup all ESXi hosts and VMs in a vCenter cluster using VCF PowerCLI
    
.DESCRIPTION
    This script connects to vCenter Server and performs the following actions:
    1. Validates access to vCenter with a 60-second timeout
    2. Inventories the cluster and host status
    3. Takes hosts out of maintenance mode if they are in it
    4. Validates the state of and starts VMs if necessary (starting with pivotal-ops-manager)
    
    Note: vSphere Cluster Services (vCLS) VMs are automatically managed by vSphere
    
.NOTES
    Author: Lab Administrator
    Requires: VCF PowerCLI module
    Compatible with: ESXi 8.0, vCenter Server, VMware Cloud Foundation
#>

# Load configuration from external file
$env:TANZU_SECRETS = Join-Path $HOME "\.sekrits\tanzu-env.json"
. ./Load-Env.ps1


# Function to inventory cluster and hosts
function Get-ClusterInventory {
    param(
        [string]$ClusterName
    )
    
    Write-ColorOutput "`n=== Cluster Inventory ===" "Cyan"
    
    try {
        # Get cluster information
        $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
        $hosts = $cluster | Get-VMHost
        $vms = $cluster | Get-VM
        
        Write-ColorOutput "Cluster: $($cluster.Name)" "Green"
        Write-ColorOutput "Total Hosts: $($hosts.Count)" "White"
        Write-ColorOutput "Total VMs: $($vms.Count)" "White"
        
        # Analyze host states
        $connectedHosts = $hosts | Where-Object { $_.ConnectionState -eq "Connected" }
        $maintenanceHosts = $hosts | Where-Object { $_.State -eq "Maintenance" }
        $disconnectedHosts = $hosts | Where-Object { $_.ConnectionState -eq "Disconnected" }
        
        Write-ColorOutput "`nHost Status Summary:" "White"
        Write-ColorOutput "  Connected: $($connectedHosts.Count)" "Green"
        Write-ColorOutput "  In Maintenance Mode: $($maintenanceHosts.Count)" "Yellow"
        Write-ColorOutput "  Disconnected: $($disconnectedHosts.Count)" "Red"
        
        # Display detailed host information
        Write-ColorOutput "`nDetailed Host Status:" "White"
        foreach ($vmhost in $hosts) {
            $status = "$($vmhost.ConnectionState)"
            if ($vmhost.State -eq "Maintenance") {
                $status += " (Maintenance Mode)"
            }
            $color = switch ($vmhost.ConnectionState) {
                "Connected" { if ($vmhost.State -eq "Maintenance") { "Yellow" } else { "Green" } }
                "Disconnected" { "Red" }
                default { "White" }
            }
            Write-ColorOutput "  - $($vmhost.Name): $status" $color
        }
        
        # Analyze VM states for target VMs
        $targetVMs = @()
        $targetVMsStatus = @()
        
        foreach ($vmName in $VMsToStart) {
            $vm = $vms | Where-Object { $_.Name -eq $vmName }
            if ($vm) {
                $targetVMs += $vm
                $status = if ($vm.PowerState -eq "PoweredOn") { "Running" } else { "Stopped" }
                $color = if ($vm.PowerState -eq "PoweredOn") { "Green" } else { "Yellow" }
                $targetVMsStatus += [PSCustomObject]@{
                    Name = $vmName
                    PowerState = $vm.PowerState
                    Status = $status
                    Color = $color
                }
            } else {
                $targetVMsStatus += [PSCustomObject]@{
                    Name = $vmName
                    PowerState = "NotFound"
                    Status = "Not Found"
                    Color = "Red"
                }
            }
        }
        
        $poweredOnVMs = $vms | Where-Object { $_.PowerState -eq "PoweredOn" }
        $poweredOffVMs = $vms | Where-Object { $_.PowerState -eq "PoweredOff" }
        $vclsVMs = $vms | Where-Object { $_.Name -like "vCLS-*" }
        $targetPoweredOffVMs = $targetVMs | Where-Object { $_.PowerState -eq "PoweredOff" }
        
        Write-ColorOutput "`nVM Status Summary:" "White"
        Write-ColorOutput "  Total VMs: $($vms.Count)" "White"
        Write-ColorOutput "  vCLS VMs: $($vclsVMs.Count)" "Gray"
        Write-ColorOutput "  All Powered On: $($poweredOnVMs.Count)" "Green"
        Write-ColorOutput "  All Powered Off: $($poweredOffVMs.Count)" "Yellow"
        
        Write-ColorOutput "`nTarget VMs Status:" "White"
        foreach ($vmStatus in $targetVMsStatus) {
            Write-ColorOutput "  - $($vmStatus.Name): $($vmStatus.Status)" $vmStatus.Color
        }
        
        return @{
            Cluster = $cluster
            Hosts = $hosts
            VMs = $vms
            MaintenanceHosts = $maintenanceHosts
            DisconnectedHosts = $disconnectedHosts
            TargetVMs = $targetVMs
            TargetPoweredOffVMs = $targetPoweredOffVMs
            TargetVMsStatus = $targetVMsStatus
        }
    }
    catch {
        Write-ColorOutput "Error inventorying cluster: $($_.Exception.Message)" "Red"
        throw
    }
}

# Function to exit maintenance mode
function Exit-HostsMaintenanceMode {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]]$MaintenanceHosts
    )
    
    if ($MaintenanceHosts.Count -eq 0) {
        Write-ColorOutput "`nNo hosts are in maintenance mode" "Green"
        return $true
    }
    
    Write-ColorOutput "`n=== Exiting Maintenance Mode ===" "Cyan"
    Write-ColorOutput "Taking $($MaintenanceHosts.Count) hosts out of maintenance mode..." "White"
    
    $success = $true
    
    foreach ($vmhost in $MaintenanceHosts) {
        try {
            Write-ColorOutput "  Exiting maintenance mode: $($vmhost.Name)" "Yellow"
            
            # Exit maintenance mode
            Set-VMHost -VMHost $vmhost -State Connected -Confirm:$false | Out-Null
            
            # Wait for host to exit maintenance mode
            $timeout = $HostMaintenanceTimeout
            $elapsed = 0
            do {
                Start-Sleep -Seconds 15
                $elapsed += 15
                $hostStatus = Get-VMHost -Name $vmhost.Name
                Write-ColorOutput "    Waiting for host to exit maintenance mode... ($elapsed/$timeout seconds)" "Yellow"
            } while ($hostStatus.State -eq "Maintenance" -and $elapsed -lt $timeout)
            
            if ($hostStatus.State -ne "Maintenance") {
                Write-ColorOutput "    $($vmhost.Name) has exited maintenance mode" "Green"
            } else {
                Write-ColorOutput "    Warning: $($vmhost.Name) did not exit maintenance mode within timeout" "Red"
                $success = $false
            }
        }
        catch {
            Write-ColorOutput "    Error taking $($vmhost.Name) out of maintenance mode: $($_.Exception.Message)" "Red"
            $success = $false
        }
    }
    
    return $success
}

# Function to wait for VM startup
function Wait-ForVMStartup {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VMs,
        [int]$TimeoutSeconds = 300
    )
    
    $startTime = Get-Date
    $vmNames = $VMs | ForEach-Object { $_.Name }
    
    $loop_counter = 0
    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        # Refresh VM status by getting fresh VM objects from vCenter
        $stoppedVMs = @()
        foreach ($vmName in $vmNames) {
            try {
                $refreshedVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
                if ($refreshedVM -and $refreshedVM.PowerState -eq "PoweredOff") {
                    $stoppedVMs += $refreshedVM
                }
            }
            catch {
                # VM might have been deleted or is in an invalid state, skip it
                Write-ColorOutput "    Warning: Could not refresh status for VM $vmName" "Yellow"
            }
        }
        
        if ($stoppedVMs.Count -eq 0) {
            Write-ColorOutput "  All VMs have started successfully" "Green"
            return $true
        }
        
        Write-ColorOutput "($loop_counter)  Waiting for $($stoppedVMs.Count) VMs to start..." "Yellow"
        Start-Sleep -Seconds 10
        $loop_counter++
    }
    
    # Final check - get current status for reporting
    $stillStoppedVMs = @()
    foreach ($vmName in $vmNames) {
        try {
            $refreshedVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($refreshedVM -and $refreshedVM.PowerState -eq "PoweredOff") {
                $stillStoppedVMs += $refreshedVM
            }
        }
        catch {
            # VM might have been deleted or is in an invalid state, skip it
        }
    }
    
    if ($stillStoppedVMs.Count -gt 0) {
        Write-ColorOutput "  Warning: $($stillStoppedVMs.Count) VMs are still stopped after timeout" "Red"
        foreach ($vm in $stillStoppedVMs) {
            Write-ColorOutput "    - $($vm.Name)" "Red"
        }
    }
    
    return $false
}

# Function to start VMs by category in order
function Start-VMsByCategory {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$AllVMs
    )
    
    Write-ColorOutput "`n=== VM Startup Phase ===" "Cyan"
    
    # Filter VMs by category (same logic as Cluster-State.ps1)
    $cfVMs = $AllVMs | Where-Object { $_.CustomFields["director"] -eq $CFVMDirectorTag -and $_.PowerState -eq "PoweredOff" }
    $boshVMs = $AllVMs | Where-Object { $_.CustomFields["director"] -eq $BOSHVMDirectorTag -and $_.PowerState -eq "PoweredOff" }
    $startupVMs = $AllVMs | Where-Object { $_.Name -in $VMsToStart -and $_.PowerState -eq "PoweredOff" }
    
    Write-ColorOutput "Startup order: vms_to_start -> CF -> BOSH" "White"
    Write-ColorOutput "Startup VMs to start: $($startupVMs.Count)" "Magenta"
    Write-ColorOutput "CF VMs to start: $($cfVMs.Count)" "Cyan"
    Write-ColorOutput "BOSH VMs to start: $($boshVMs.Count)" "Yellow"
    
    $overallSuccess = $true
    
    # Phase 1: Start vms_to_start VMs first
    if ($startupVMs.Count -gt 0) {
        Write-ColorOutput "`n--- Phase 1: Starting Startup VMs ---" "Magenta"
        $success = Start-VMGroup -VMs $startupVMs -GroupName "Startup" -Color "Magenta" -ExtraBootTime 60
        if (-not $success) { $overallSuccess = $false }
    }
    
    # Phase 2: Start CF VMs
    if ($cfVMs.Count -gt 0) {
        Write-ColorOutput "`n--- Phase 2: Starting CF VMs ---" "Cyan"
        $success = Start-VMGroup -VMs $cfVMs -GroupName "CF" -Color "Cyan" -ExtraBootTime 30
        if (-not $success) { $overallSuccess = $false }
    }
    
    # Phase 3: Start BOSH VMs
    if ($boshVMs.Count -gt 0) {
        Write-ColorOutput "`n--- Phase 3: Starting BOSH VMs ---" "Yellow"
        $success = Start-VMGroup -VMs $boshVMs -GroupName "BOSH" -Color "Yellow" -ExtraBootTime 30
        if (-not $success) { $overallSuccess = $false }
    }
    
    if ($startupVMs.Count -eq 0 -and $cfVMs.Count -eq 0 -and $boshVMs.Count -eq 0) {
        Write-ColorOutput "All target VMs are already powered on" "Green"
        return $true
    }
    
    return $overallSuccess
}

# Helper function to start a group of VMs in parallel
function Start-VMGroup {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VMs,
        [string]$GroupName,
        [string]$Color,
        [int]$ExtraBootTime = 30
    )
    
    if ($VMs.Count -eq 0) {
        return $true
    }
    
    Write-ColorOutput "`nStarting $GroupName VMs in parallel ($($VMs.Count) VMs)..." $Color
    
    $success = $true
    $startupJobs = @()
    
    # Phase 1: Send start commands to all VMs in parallel
    foreach ($vm in $VMs) {
        Write-ColorOutput "  Sending start command to $GroupName VM: $($vm.Name)" $Color
        try {
            # Start VM asynchronously
            $task = Start-VM -VM $vm -Confirm:$false -RunAsync
            $startupJobs += [PSCustomObject]@{
                VMName = $vm.Name
                Task = $task
                StartTime = Get-Date
            }
            Write-ColorOutput "    Start command sent to $($vm.Name)" "Green"
        }
        catch {
            Write-ColorOutput "    Error starting $($vm.Name): $($_.Exception.Message)" "Red"
            $success = $false
        }
    }
    
    # Phase 2: Monitor startup tasks
    if ($startupJobs.Count -gt 0) {
        Write-ColorOutput "`nMonitoring $GroupName VM startup tasks..." "Yellow"
        
        $timeout = 120
        $completed = @()
        $failed = @()
        
        while ($startupJobs.Count -gt 0) {
            $stillRunning = @()
            
            foreach ($job in $startupJobs) {
                try {
                    $elapsed = ((Get-Date) - $job.StartTime).TotalSeconds
                    
                    if ($job.Task.State -eq "Success") {
                        Write-ColorOutput "    $($job.VMName) startup task completed successfully" "Green"
                        $completed += $job.VMName
                    }
                    elseif ($job.Task.State -eq "Error") {
                        Write-ColorOutput "    $($job.VMName) startup task failed: $($job.Task.ExtensionData.Info.Error.LocalizedMessage)" "Red"
                        $failed += $job.VMName
                        $success = $false
                    }
                    elseif ($elapsed -gt $timeout) {
                        Write-ColorOutput "    $($job.VMName) startup task timed out after $timeout seconds" "Red"
                        $failed += $job.VMName
                        $success = $false
                    }
                    else {
                        $stillRunning += $job
                    }
                }
                catch {
                    Write-ColorOutput "    Error monitoring $($job.VMName): $($_.Exception.Message)" "Red"
                    $failed += $job.VMName
                    $success = $false
                }
            }
            
            $startupJobs = $stillRunning
            
            if ($startupJobs.Count -gt 0) {
                Write-ColorOutput "    Still waiting for $($startupJobs.Count) $GroupName VMs to complete startup..." "Yellow"
                Start-Sleep -Seconds 5
            }
        }
        
        Write-ColorOutput "`n$GroupName VM startup summary:" "White"
        Write-ColorOutput "  Completed: $($completed.Count)" "Green"
        Write-ColorOutput "  Failed: $($failed.Count)" "Red"
    }
    
    # Phase 3: Wait for all VMs in group to be powered on and allow boot time
    if ($success -or $completed.Count -gt 0) {
        Write-ColorOutput "`nWaiting for all $GroupName VMs to be fully powered on..." "Yellow"
        $groupStartupSuccess = Wait-ForVMStartup -VMs $VMs -TimeoutSeconds 180
        
        if ($groupStartupSuccess) {
            Write-ColorOutput "All $GroupName VMs are now powered on" "Green"
            
            # Additional wait for VMs to fully boot
            if ($ExtraBootTime -gt 0) {
                Write-ColorOutput "Waiting additional $ExtraBootTime seconds for $GroupName VMs to fully boot..." "Yellow"
                Start-Sleep -Seconds $ExtraBootTime
            }
        } else {
            Write-ColorOutput "Warning: Some $GroupName VMs did not start within the timeout period" "Red"
            $success = $false
        }
    }
    
    return $success
}

# Main script execution
try {
    Write-ColorOutput "vCenter Cluster Startup Script (VCF PowerCLI)" "Cyan"
    Write-ColorOutput "===============================================" "Cyan"

    # Get connection from function in Load-Env.ps1.  Connection is already there, but this makes it explicit
    $connection = Get-VCenter-Connection
    Write-ColorOutput "Successfully connected to vCenter" "Green"
    
    # $connection = $connectionResult.Connection
    
    # Inventory the cluster
    $inventory = Get-ClusterInventory -ClusterName $ClusterName
    
    # Check if any action is needed
    $needsAction = $false
    $actionSummary = @()
    
    if ($inventory.MaintenanceHosts.Count -gt 0) {
        $needsAction = $true
        $actionSummary += "Take $($inventory.MaintenanceHosts.Count) hosts out of maintenance mode"
    }
    
    if ($inventory.TargetPoweredOffVMs.Count -gt 0) {
        $needsAction = $true
        $actionSummary += "Start $($inventory.TargetPoweredOffVMs.Count) target VMs that are powered off"
    }
    
    if (-not $needsAction) {
        Write-ColorOutput "`nCluster is already in the desired state:" "Green"
        Write-ColorOutput "  - All hosts are connected and not in maintenance mode" "Green"
        Write-ColorOutput "  - All VMs are powered on" "Green"
        Write-ColorOutput "`nNo action required!" "Green"
    } else {
        # Display planned actions
        Write-ColorOutput "`nPlanned Actions:" "Yellow"
        foreach ($action in $actionSummary) {
            Write-ColorOutput "  - $action" "Yellow"
        }
        
        # Confirmation prompt
        $confirmation = Read-Host "`nDo you want to proceed with the startup sequence? (yes/no)"
        if ($confirmation.ToLower() -ne "yes") {
            Write-ColorOutput "Operation cancelled by user" "Yellow"
            Disconnect-VIServer -Server $connection -Confirm:$false
            exit 0
        }
        
        # Execute startup sequence
        Write-ColorOutput "`nStarting cluster startup sequence..." "Cyan"
        
        # Phase 1: Exit maintenance mode
        if ($inventory.MaintenanceHosts.Count -gt 0) {
            $maintenanceSuccess = Exit-HostsMaintenanceMode -MaintenanceHosts $inventory.MaintenanceHosts
            if (-not $maintenanceSuccess) {
                Write-ColorOutput "Warning: Some hosts may still be in maintenance mode" "Yellow"
            }
        }
        
        # Phase 2: Start VMs by category in correct order
        $cluster = Get-Cluster -Name $ClusterName
        $allVMs = $cluster | Get-VM
        $vmStartSuccess = Start-VMsByCategory -AllVMs $allVMs
        
        Write-ColorOutput "`n=== Startup Sequence Complete ===" "Cyan"
        Write-ColorOutput "Cluster startup operations have been completed." "Green"
    }
    
    # Final status check
    Write-ColorOutput "`n=== Final Status ===" "Cyan"
    $finalInventory = Get-ClusterInventory -ClusterName $ClusterName
    
    # Disconnect from vCenter
    Disconnect-VIServer -Server $connection -Confirm:$false
    Write-ColorOutput "`nDisconnected from vCenter" "White"
    
    Write-ColorOutput "`nScript completed successfully!" "Green"
}
catch {
    Write-ColorOutput "`nERROR: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" "Red"
    
    # Disconnect if connected
    if ($connection) {
        try {
            Disconnect-VIServer -Server $connection -Confirm:$false
        } catch {
            # Ignore disconnect errors
        }
    }
    
    Write-ColorOutput "`nScript completed with errors!" "Red"
    exit 1
}
