#Requires -Modules VCF.PowerCLI

<#
.SYNOPSIS
    Gracefully shutdown all VMs and ESXi hosts in a vCenter cluster using VCF PowerCLI
    
.DESCRIPTION
    This script connects to vCenter Server and performs the following actions:
    1. Shuts down all VMs in the cluster (starting with pivotal-ops-manager, excluding vCLS VMs)
    2. Puts all hosts into maintenance mode
    3. Gracefully shuts down all ESXi hosts
    
    Note: vSphere Cluster Services (vCLS) VMs are automatically excluded from shutdown
    
.NOTES
    Author: Lab Administrator
    Requires: VCF PowerCLI module
    Compatible with: ESXi 8.0, vCenter Server, VMware Cloud Foundation
#>

$env:TANZU_SECRETS = Join-Path $HOME "\.sekrits\tanzu-env.json"
. ./Load-Env.ps1

1# Function to wait for VM shutdown
function Wait-ForVMShutdown {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VMs,
        [int]$TimeoutSeconds = 300
    )
    
    $startTime = Get-Date
    $vmNames = $VMs | ForEach-Object { $_.Name }
    
    $loop_counter = 0
    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        # Refresh VM status by getting fresh VM objects from vCenter
        $runningVMs = @()
        foreach ($vmName in $vmNames) {
            try {
                $refreshedVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
                if ($refreshedVM -and $refreshedVM.PowerState -eq "PoweredOn") {
                    $runningVMs += $refreshedVM
                }
            }
            catch {
                # VM might have been deleted or is in an invalid state, skip it
                Write-ColorOutput "    Warning: Could not refresh status for VM $vmName" "Yellow"
            }
        }
        
        if ($runningVMs.Count -eq 0) {
            Write-ColorOutput "  All VMs have been shutdown successfully" "Green"
            return $true
        }
        
        Write-ColorOutput "($loop_counter)  Waiting for $($runningVMs.Count) VMs to shutdown..." "Yellow"
        Start-Sleep -Seconds 10
        $loop_counter++
    }
    
    # Final check - return the still running VMs for force shutdown
    $stillRunningVMs = @()
    foreach ($vmName in $vmNames) {
        try {
            $refreshedVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($refreshedVM -and $refreshedVM.PowerState -eq "PoweredOn") {
                $stillRunningVMs += $refreshedVM
            }
        }
        catch {
            # VM might have been deleted or is in an invalid state, skip it
        }
    }
    
    if ($stillRunningVMs.Count -gt 0) {
        Write-ColorOutput "  Warning: $($stillRunningVMs.Count) VMs are still running after timeout" "Red"
        foreach ($vm in $stillRunningVMs) {
            Write-ColorOutput "    - $($vm.Name)" "Red"
        }
    }
    
    return $false
}

# Function to shutdown VMs by category in reverse order
function Shutdown-ClusterVMs {
    param(
        [string]$ClusterName
    )
    
    Write-ColorOutput "`n=== VM Shutdown Phase ===" "Cyan"
    
    # Get all VMs in the cluster (excluding vCLS VMs)
    $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
    $allClusterVMs = $cluster | Get-VM | Where-Object { $_.PowerState -eq "PoweredOn" }
    $vclsVMs = $allClusterVMs | Where-Object { $_.Name -like "vCLS-*" }
    $allVMs = $allClusterVMs | Where-Object { $_.Name -notlike "vCLS-*" }
    
    if ($vclsVMs.Count -gt 0) {
        Write-ColorOutput "Excluding $($vclsVMs.Count) vCLS VMs from shutdown (these are managed by vSphere):" "Yellow"
        foreach ($vclsVM in $vclsVMs) {
            Write-ColorOutput "  - $($vclsVM.Name)" "Yellow"
        }
    }
    
    if ($allVMs.Count -eq 0) {
        Write-ColorOutput "No powered-on VMs found in cluster $ClusterName (excluding vCLS VMs)" "Green"
        return $true
    }
    
    # Filter VMs by category (same logic as Cluster-State.ps1)
    $cfVMs = $allVMs | Where-Object { $_.CustomFields["director"] -eq $CFVMDirectorTag }
    $boshVMs = $allVMs | Where-Object { $_.CustomFields["director"] -eq $BOSHVMDirectorTag }
    $startupVMs = $allVMs | Where-Object { $_.Name -in $VMsToStart }
    $otherVMs = $allVMs | Where-Object { 
        $_.CustomFields["director"] -ne $CFVMDirectorTag -and 
        $_.CustomFields["director"] -ne $BOSHVMDirectorTag -and 
        $_.Name -notin $VMsToStart 
    }
    
    Write-ColorOutput "Found $($allVMs.Count) powered-on VMs in cluster $ClusterName (excluding vCLS VMs)" "White"
    Write-ColorOutput "Shutdown order: BOSH -> CF -> vms_to_start -> Others" "White"
    Write-ColorOutput "BOSH VMs to shutdown: $($boshVMs.Count)" "Yellow"
    Write-ColorOutput "CF VMs to shutdown: $($cfVMs.Count)" "Cyan" 
    Write-ColorOutput "Startup VMs to shutdown: $($startupVMs.Count)" "Magenta"
    Write-ColorOutput "Other VMs to shutdown: $($otherVMs.Count)" "Gray"
    
    $overallSuccess = $true
    
    # Phase 1: Shutdown BOSH VMs first
    if ($boshVMs.Count -gt 0) {
        Write-ColorOutput "`n--- Phase 1: Shutting down BOSH VMs ---" "Yellow"
        $success = Shutdown-VMGroup -VMs $boshVMs -GroupName "BOSH" -Color "Yellow"
        if (-not $success) { $overallSuccess = $false }
    }
    
    # Phase 2: Shutdown CF VMs
    if ($cfVMs.Count -gt 0) {
        Write-ColorOutput "`n--- Phase 2: Shutting down CF VMs ---" "Cyan"
        $success = Shutdown-VMGroup -VMs $cfVMs -GroupName "CF" -Color "Cyan"
        if (-not $success) { $overallSuccess = $false }
    }
    
    # Phase 3: Shutdown startup VMs
    if ($startupVMs.Count -gt 0) {
        Write-ColorOutput "`n--- Phase 3: Shutting down Startup VMs ---" "Magenta"
        $success = Shutdown-VMGroup -VMs $startupVMs -GroupName "Startup" -Color "Magenta"
        if (-not $success) { $overallSuccess = $false }
    }
    
    # Phase 4: Shutdown other VMs
    if ($otherVMs.Count -gt 0) {
        Write-ColorOutput "`n--- Phase 4: Shutting down Other VMs ---" "Gray"
        $success = Shutdown-VMGroup -VMs $otherVMs -GroupName "Other" -Color "Gray"
        if (-not $success) { $overallSuccess = $false }
    }
    
    # Final verification
    $finalCheck = $cluster | Get-VM | Where-Object { $_.PowerState -eq "PoweredOn" -and $_.Name -notlike "vCLS-*" }
    if ($finalCheck.Count -eq 0) {
        Write-ColorOutput "`nAll VMs in cluster have been shutdown successfully!" "Green"
        return $true
    } else {
        Write-ColorOutput "`nWarning: $($finalCheck.Count) VMs are still running:" "Red"
        foreach ($vm in $finalCheck) {
            Write-ColorOutput "  - $($vm.Name)" "Red"
        }
        return $false
    }
}

# Helper function to shutdown a group of VMs
function Shutdown-VMGroup {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VMs,
        [string]$GroupName,
        [string]$Color
    )
    
    $success = $true
    
    # Send shutdown commands to all VMs in the group
    foreach ($vm in $VMs) {
        Write-ColorOutput "  Shutting down $GroupName VM: $($vm.Name)" $Color
        try {
            $vm | Shutdown-VMGuest -Confirm:$false
            Write-ColorOutput "    Shutdown command sent to $($vm.Name)" "Green"
        }
        catch {
            Write-ColorOutput "    Error sending shutdown command to $($vm.Name): $($_.Exception.Message)" "Red"
            $success = $false
        }
    }
    
    # Wait for all VMs in the group to shutdown
    if ($VMs.Count -gt 0) {
        Write-ColorOutput "`nWaiting for $GroupName VMs to shutdown..." "Yellow"
        $allShutdown = Wait-ForVMShutdown -VMs $VMs -TimeoutSeconds $VMShutdownTimeout
        
        if (-not $allShutdown) {
            Write-ColorOutput "Some $GroupName VMs did not shutdown gracefully. Forcing shutdown..." "Red"
            # Get fresh VM objects to check current power state
            $stillRunning = @()
            foreach ($vm in $VMs) {
                try {
                    $refreshedVM = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
                    if ($refreshedVM -and $refreshedVM.PowerState -eq "PoweredOn") {
                        $stillRunning += $refreshedVM
                    }
                }
                catch {
                    # VM might have been deleted or is in an invalid state, skip it
                }
            }
            
            foreach ($vm in $stillRunning) {
                Write-ColorOutput "  Force stopping $GroupName VM: $($vm.Name)" "Red"
                try {
                    Stop-VM -VM $vm -Confirm:$false
                    Write-ColorOutput "    Force stop command sent to $($vm.Name)" "Green"
                }
                catch {
                    Write-ColorOutput "    Error force stopping $($vm.Name): $($_.Exception.Message)" "Red"
                    $success = $false
                }
            }
            
            if ($stillRunning.Count -eq 0) {
                Write-ColorOutput "  All $GroupName VMs have already shutdown, no force action needed" "Green"
            }
        }
    }
    
    return $success
}

# Function to put hosts in maintenance mode
function Set-HostsMaintenanceMode {
    param(
        [string]$ClusterName
    )
    
    Write-ColorOutput "`n=== Maintenance Mode Phase ===" "Cyan"
    
    $cluster = Get-Cluster -Name $ClusterName
    $hosts = $cluster | Get-VMHost | Where-Object { $_.ConnectionState -eq "Connected" }
    
    Write-ColorOutput "Putting $($hosts.Count) hosts into maintenance mode..." "White"
    
    foreach ($vmhost in $hosts) {
        try {
            Write-ColorOutput "  Entering maintenance mode: $($vmhost.Name)" "Yellow"
            
            if ($vmhost.State -eq "Maintenance") {
                Write-ColorOutput "    $($vmhost.Name) is already in maintenance mode" "Green"
                continue
            }
            
            # Enter maintenance mode
            $task = Set-VMHost -VMHost $vmhost -State Maintenance -VsanDataMigrationMode EnsureAccessibility -Confirm:$false -RunAsync
            
            # Wait for maintenance mode
            $timeout = $HostMaintenanceTimeout
            $elapsed = 0
            do {
                Start-Sleep -Seconds 15
                $elapsed += 15
                $hostStatus = Get-VMHost -Name $vmhost.Name
                Write-ColorOutput "    Waiting for maintenance mode... ($elapsed/$timeout seconds)" "Yellow"
            } while ($hostStatus.State -ne "Maintenance" -and $elapsed -lt $timeout)
            
            if ($hostStatus.State -eq "Maintenance") {
                Write-ColorOutput "    $($vmhost.Name) is now in maintenance mode" "Green"
            } else {
                Write-ColorOutput "    Warning: $($vmhost.Name) did not enter maintenance mode within timeout" "Red"
            }
        }
        catch {
            Write-ColorOutput "    Error putting $($vmhost.Name) in maintenance mode: $($_.Exception.Message)" "Red"
        }
    }
}

# Function to shutdown hosts
function Shutdown-ClusterHosts {
    param(
        [string]$ClusterName
    )
    
    Write-ColorOutput "`n=== Host Shutdown Phase ===" "Cyan"
    
    $cluster = Get-Cluster -Name $ClusterName
    $hosts = $cluster | Get-VMHost | Where-Object { $_.ConnectionState -eq "Maintenance" }
    
    Write-ColorOutput "Shutting down $($hosts.Count) hosts..." "White"
    
    foreach ($vmhost in $hosts) {
        try {
            Write-ColorOutput "  Shutting down host: $($vmhost.Name)" "Yellow"
            
            # Shutdown the host
            Stop-VMHost -VMHost $vmhost -Force -Confirm:$false
            Write-ColorOutput "    Shutdown command sent to $($vmhost.Name)" "Green"
        }
        catch {
            Write-ColorOutput "    Error shutting down $($vmhost.Name): $($_.Exception.Message)" "Red"
        }
    }
}

# Main script execution
try {
    Write-ColorOutput "vCenter Cluster Shutdown Script (VCF PowerCLI)" "Cyan"
    Write-ColorOutput "=================================================" "Cyan"

    # Get connection from function in Load-Env.ps1.  Connection is already there, but this makes it explicit
    $connection = Get-VCenter-Connection
    Write-ColorOutput "Successfully connected to vCenter" "Green"
    
    # Verify cluster exists
    Write-ColorOutput "`nLooking for cluster: $ClusterName" "White"
    $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
    Write-ColorOutput "Found cluster: $($cluster.Name)" "Green"
    
    # Get cluster information
    $hosts = $cluster | Get-VMHost
    $vms = $cluster | Get-VM
    
    Write-ColorOutput "`nCluster Information:" "White"
    Write-ColorOutput "  Hosts: $($hosts.Count)" "White"
    Write-ColorOutput "  Total VMs: $($vms.Count)" "White"
    Write-ColorOutput "  Powered-on VMs: $(($vms | Where-Object { $_.PowerState -eq 'PoweredOn' }).Count)" "White"
    
    # Display hosts
    Write-ColorOutput "`nHosts in cluster:" "White"
    foreach ($vmhost in $hosts) {
        $status = if ($vmhost.State -eq "Maintenance") { "Maintenance" } else { $vmhost.ConnectionState }
        Write-ColorOutput "  - $($vmhost.Name) (Status: $status)" "White"
    }
    
    # Confirmation prompt
    Write-ColorOutput "`nWARNING: This will perform the following actions:" "Red"
    Write-ColorOutput "1. Shutdown ALL VMs in the cluster (BOSH -> CF -> vms_to_start -> Others)" "Red"
    Write-ColorOutput "2. Put all hosts into maintenance mode" "Red"
    Write-ColorOutput "3. Shutdown all ESXi hosts" "Red"
    Write-ColorOutput "`nThis action cannot be undone remotely!" "Red"
    
    $confirmation = Read-Host "`nDo you want to continue? (yes/no)"
    if ($confirmation.ToLower() -ne "yes") {
        Write-ColorOutput "Operation cancelled by user" "Yellow"
        Disconnect-VIServer -Server $connection -Confirm:$false
        exit 0
    }
    
    # Execute shutdown sequence
    Write-ColorOutput "`nStarting cluster shutdown sequence..." "Cyan"
    
    # Phase 1: Shutdown VMs by category
    $vmShutdownSuccess = Shutdown-ClusterVMs -ClusterName $ClusterName
    
    # Phase 2: Maintenance mode
    Set-HostsMaintenanceMode -ClusterName $ClusterName
    
    # Phase 3: Shutdown hosts
    Shutdown-ClusterHosts -ClusterName $ClusterName
    
    Write-ColorOutput "`n=== Shutdown Sequence Complete ===" "Cyan"
    Write-ColorOutput "All shutdown commands have been sent." "Green"
    Write-ColorOutput "Hosts will shutdown gracefully over the next few minutes." "Green"
    Write-ColorOutput "Monitor host status through iLO/iDRAC or physical console." "Yellow"
    
    # Disconnect from vCenter
    Disconnect-VIServer -Server $connection -Confirm:$false
    Write-ColorOutput "`nDisconnected from vCenter" "White"
    
    Write-ColorOutput "`nScript completed successfully!" "Green"
}
catch {
    Write-ColorOutput "`nERROR: $($_.Exception.Message)" "Red"
    
    # Disconnect if connected
    if ($connection) {
        Disconnect-VIServer -Server $connection -Confirm:$false
    }
    
    Write-ColorOutput "`nScript completed with errors!" "Red"
    exit 1
}
