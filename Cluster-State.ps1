#Requires -Modules VCF.PowerCLI

<#
.SYNOPSIS
    Display the connection status and state of all ESXi hosts in a vCenter cluster using VCF PowerCLI
    
.DESCRIPTION
    This script connects to vCenter Server and performs the following actions:
    1. Validates access to vCenter with a 60-second timeout
    2. Retrieves cluster information
    3. Displays ConnectionStatus and Status for each host in the cluster
    4. Provides a summary of host states
    
.NOTES
    Author: Lab Administrator
    Requires: VCF PowerCLI module
    Compatible with: ESXi 8.0, vCenter Server, VMware Cloud Foundation
#>

# Set to location of tanzu-env.json
$env:TANZU_SECRETS = Join-Path $HOME "\.sekrits\tanzu-env.json"
. ./Load-Env.ps1

# Extract configuration values
# $vCenterServer = $config.vcenter.server
# $Username = $config.vcenter.username
# $Password = $config.vcenter.password
# $ClusterName = $config.vcenter.cluster_name

# # Connection configuration
# $vCenterConnectionTimeout = $config.timeouts.vcenter_connection_timeout

# Function to validate vCenter access with timeout

# Function to get and display cluster host status
function Get-ClusterHostStatus {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]]$Hosts,
        [string]$ClusterName
    )
    
    Write-ColorOutput "`n=== Cluster Host Status ===" "Cyan"
    
    try {
        Write-ColorOutput "Cluster: $ClusterName" "Green"
        Write-ColorOutput "Total Hosts: $($Hosts.Count)" "White"
        
        # Create arrays for different host states
        $connectedHosts = @()
        $maintenanceHosts = @()
        $disconnectedHosts = @()
        $notRespondingHosts = @()
        
        # Display detailed host information
        Write-ColorOutput "`n=== Host Details ===" "White"
        $statusHeader = (Format-PadRight "Host Name" 25) + (Format-PadRight "Connection Status" 20) + (Format-PadRight "Status" 15) + "Power State"
        Write-ColorOutput  $statusHeader "Gray"
        Write-ColorOutput "--------------------------------------------------------------------------------------------" "Gray"
        
        foreach ($vmhost in $Hosts) {
            # Determine status color based on connection state and status
            $connectionColor = switch ($vmhost.ConnectionState) {
                "Connected" { "Green" }
                "Disconnected" { "Red" }
                "NotResponding" { "Magenta" }
                default { "Yellow" }
            }
            
            $statusColor = switch ($vmhost.State) {
                "Connected" { "Green" }
                "Maintenance" { "Yellow" }
                "Disconnected" { "Red" }
                "NotResponding" { "Magenta" }
                default { "White" }
            }
            
            # Format the output line
            $hostLine = (Format-PadRight $vmhost.Name 25) + 
                       (Format-PadRight $vmhost.ConnectionState 20) + 
                       (Format-PadRight $vmhost.State 15) + 
                       $vmhost.PowerState
            
            # Use the most critical color (Red > Magenta > Yellow > Green)
            $displayColor = if ($vmhost.ConnectionState -eq "Disconnected" -or $vmhost.State -eq "Disconnected") { "Red" }
                           elseif ($vmhost.ConnectionState -eq "NotResponding" -or $vmhost.State -eq "NotResponding") { "Magenta" }
                           elseif ($vmhost.State -eq "Maintenance") { "Yellow" }
                           else { "Green" }
            
            Write-ColorOutput $hostLine $displayColor
            
            # Categorize hosts for summary
            switch ($vmhost.ConnectionState) {
                "Connected" { 
                    if ($vmhost.State -eq "Maintenance") {
                        $maintenanceHosts += $vmhost
                    } else {
                        $connectedHosts += $vmhost
                    }
                }
                "Disconnected" { $disconnectedHosts += $vmhost }
                "NotResponding" { $notRespondingHosts += $vmhost }
            }
        }
        
        # Display summary
        Write-ColorOutput "`n=== Host Status Summary ===" "Cyan"
        Write-ColorOutput "Connected and Available: $($connectedHosts.Count)" "Green"
        Write-ColorOutput "In Maintenance Mode: $($maintenanceHosts.Count)" "Yellow"
        Write-ColorOutput "Disconnected: $($disconnectedHosts.Count)" "Red"
        Write-ColorOutput "Not Responding: $($notRespondingHosts.Count)" "Magenta"
        
        # Show detailed lists if there are issues
        if ($maintenanceHosts.Count -gt 0) {
            Write-ColorOutput "`nHosts in Maintenance Mode:" "Yellow"
            foreach ($vmhost in $maintenanceHosts) {
                Write-ColorOutput "  - $($vmhost.Name)" "Yellow"
            }
        }
        
        if ($disconnectedHosts.Count -gt 0) {
            Write-ColorOutput "`nDisconnected Hosts:" "Red"
            foreach ($vmhost in $disconnectedHosts) {
                Write-ColorOutput "  - $($vmhost.Name)" "Red"
            }
        }
        
        if ($notRespondingHosts.Count -gt 0) {
            Write-ColorOutput "`nNot Responding Hosts:" "Magenta"
            foreach ($vmhost in $notRespondingHosts) {
                Write-ColorOutput "  - $($vmhost.Name)" "Magenta"
            }
        }
        
        # Overall cluster health assessment
        Write-ColorOutput "`n=== Cluster Health Assessment ===" "Cyan"
        if ($disconnectedHosts.Count -eq 0 -and $notRespondingHosts.Count -eq 0) {
            if ($maintenanceHosts.Count -eq 0) {
                Write-ColorOutput "Cluster Status: HEALTHY - All hosts are connected and available" "Green"
            } else {
                Write-ColorOutput "Cluster Status: CAUTION - Some hosts are in maintenance mode" "Yellow"
            }
        } else {
            Write-ColorOutput "Cluster Status: WARNING - Some hosts are disconnected or not responding" "Red"
        }
        
        return @{
            Hosts = $Hosts
            ConnectedHosts = $connectedHosts
            MaintenanceHosts = $maintenanceHosts
            DisconnectedHosts = $disconnectedHosts
            NotRespondingHosts = $notRespondingHosts
        }
    }
    catch {
        Write-ColorOutput "Error retrieving cluster host status: $($_.Exception.Message)" "Red"
        throw
    }
}

function Get-VMStatus {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VMs
    )
    Write-ColorOutput "`n=== VM Status ===" "Cyan"

    Write-ColorOutput "Total VMs=$($VMs.Count)" "Gray"

    # Filter VMs by director custom fields and vms_to_start names
    $cfVMs = $VMs | Where-Object { $_.CustomFields["director"] -eq $CFVMDirectorTag }
    $boshVMs = $VMs | Where-Object { $_.CustomFields["director"] -eq $BOSHVMDirectorTag }
    $startupVMs = $VMs | Where-Object { $_.Name -in $VMsToStart }
    $otherVMs = $VMs | Where-Object { 
        $_.CustomFields["director"] -ne $CFVMDirectorTag -and 
        $_.CustomFields["director"] -ne $BOSHVMDirectorTag -and 
        $_.Name -notin $VMsToStart 
    }

    Write-ColorOutput "CF VMs (director=$CFVMDirectorTag): $($cfVMs.Count)" "Cyan"
    Write-ColorOutput "BOSH VMs (director=$BOSHVMDirectorTag): $($boshVMs.Count)" "Yellow"
    Write-ColorOutput "Startup VMs (vms_to_start): $($startupVMs.Count)" "Magenta"
    Write-ColorOutput "Other VMs: $($otherVMs.Count)" "Gray"
    Write-ColorOutput ""

    # Display detailed VM information
    $vmStatusHeader = (Format-PadRight "VM Name" 30) + (Format-PadRight "Power Status" 20) + (Format-PadRight "Host" 25) + "Director"
    Write-ColorOutput  $vmStatusHeader "Gray"
    Write-ColorOutput "--------------------------------------------------------------------------------------------" "Gray"
    
    # Display CF VMs first
    if ($cfVMs.Count -gt 0) {
        Write-ColorOutput "CF VMs:" "Cyan"
        foreach ($vm in $cfVMs) {
            $vmNameTruncated = $vm.Name.Length -gt 25 ? $vm.Name.Substring(0, 25)+"..." : $vm.Name
            $vmLine = (Format-PadRight $vmNameTruncated 30) + 
                        (Format-PadRight $vm.PowerState 20) + 
                        (Format-PadRight $vm.VMHost 25) + 
                        $vm.CustomFields["director"]
            Write-ColorOutput $vmLine "Cyan"
        }
    }

    # Display BOSH VMs
    if ($boshVMs.Count -gt 0) {
        Write-ColorOutput "BOSH VMs:" "Yellow"
        foreach ($vm in $boshVMs) {
            $vmNameTruncated = $vm.Name.Length -gt 25 ? $vm.Name.Substring(0, 25)+"..." : $vm.Name
            $vmLine = (Format-PadRight $vmNameTruncated 30) + 
                        (Format-PadRight $vm.PowerState 20) + 
                        (Format-PadRight $vm.VMHost 25) + 
                        $vm.CustomFields["director"]
            Write-ColorOutput $vmLine "Yellow"
        }
    }

    # Display Startup VMs
    if ($startupVMs.Count -gt 0) {
        Write-ColorOutput "Startup VMs:" "Magenta"
        foreach ($vm in $startupVMs) {
            $vmNameTruncated = $vm.Name.Length -gt 25 ? $vm.Name.Substring(0, 25)+"..." : $vm.Name
            $vmLine = (Format-PadRight $vmNameTruncated 30) + 
                        (Format-PadRight $vm.PowerState 20) + 
                        (Format-PadRight $vm.VMHost 25) + 
                        $vm.CustomFields["director"]
            Write-ColorOutput $vmLine "Magenta"
        }
    }

    # Display other VMs
    if ($otherVMs.Count -gt 0) {
        Write-ColorOutput "Other VMs:" "Gray"
        foreach ($vm in $otherVMs) {
            $vmNameTruncated = $vm.Name.Length -gt 25 ? $vm.Name.Substring(0, 25)+"..." : $vm.Name
            $vmLine = (Format-PadRight $vmNameTruncated 30) + 
                        (Format-PadRight $vm.PowerState 20) + 
                        (Format-PadRight $vm.VMHost 25) + 
                        $vm.CustomFields["director"]
            Write-ColorOutput $vmLine "Gray"
        }
    }
    
    # Create arrays for different VM power states
    $poweredOnVMs = $VMs | Where-Object { $_.PowerState -eq "PoweredOn" }
    $poweredOffVMs = $VMs | Where-Object { $_.PowerState -eq "PoweredOff" }
    $suspendedVMs = $VMs | Where-Object { $_.PowerState -eq "Suspended" }
    
    # Display VM summary
    Write-ColorOutput "`n=== VM Power State Summary ===" "Cyan"
    Write-ColorOutput "Powered On: $($poweredOnVMs.Count)" "Green"
    Write-ColorOutput "Powered Off: $($poweredOffVMs.Count)" "Red"
    Write-ColorOutput "Suspended: $($suspendedVMs.Count)" "Yellow"

    # Display director tag and startup VM summary
    Write-ColorOutput "`n=== VM Category Summary ===" "Cyan"
    Write-ColorOutput "CF VMs ($CFVMDirectorTag): $($cfVMs.Count)" "Cyan"
    Write-ColorOutput "  - Powered On: $(($cfVMs | Where-Object { $_.PowerState -eq 'PoweredOn' }).Count)" "Green"
    Write-ColorOutput "  - Powered Off: $(($cfVMs | Where-Object { $_.PowerState -eq 'PoweredOff' }).Count)" "Red"
    
    Write-ColorOutput "BOSH VMs ($BOSHVMDirectorTag): $($boshVMs.Count)" "Yellow"
    Write-ColorOutput "  - Powered On: $(($boshVMs | Where-Object { $_.PowerState -eq 'PoweredOn' }).Count)" "Green"
    Write-ColorOutput "  - Powered Off: $(($boshVMs | Where-Object { $_.PowerState -eq 'PoweredOff' }).Count)" "Red"
    
    Write-ColorOutput "Startup VMs (vms_to_start): $($startupVMs.Count)" "Magenta"
    Write-ColorOutput "  - Powered On: $(($startupVMs | Where-Object { $_.PowerState -eq 'PoweredOn' }).Count)" "Green"
    Write-ColorOutput "  - Powered Off: $(($startupVMs | Where-Object { $_.PowerState -eq 'PoweredOff' }).Count)" "Red"
    
    # Overall VM health assessment
    Write-ColorOutput "`n=== VM Health Assessment ===" "Cyan"
    if ($suspendedVMs.Count -eq 0) {
        Write-ColorOutput "VM Status: NORMAL - No suspended VMs detected" "Green"
    } else {
        Write-ColorOutput "VM Status: CAUTION - Some VMs are suspended" "Yellow"
        foreach ($vm in $suspendedVMs) {
            Write-ColorOutput "  - $($vm.Name)" "Yellow"
        }
    }

}

# Main script execution
try {
    Write-ColorOutput "vCenter Cluster State Check Script (VCF PowerCLI)" "Cyan"
    Write-ColorOutput "=================================================" "Cyan"
    Write-ColorOutput "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "Gray"
    
    # Get connection from function in Load-Env.ps1
    $connection = Get-VCenter-Connection
    Write-ColorOutput "Successfully connected to vCenter" "Green"
    
    # Get cluster information
    Write-ColorOutput "`nLooking for cluster: $ClusterName" "White"
    $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
    $hosts = $cluster | Get-VMHost | Sort-Object Name
    Write-ColorOutput "Found cluster: $($cluster.Name)" "Green"
    
    # Get and display cluster host status
    $hostStatus = Get-ClusterHostStatus -Hosts $hosts -ClusterName $ClusterName

    $allClusterVMs = $cluster | Get-VM # | Where-Object { $_.PowerState -eq "PoweredOn" }
    if ($allClusterVMs.Count -eq 0) {
        Write-ColorOutput "No VMs found in cluster $ClusterName" "Yellow"
    } else {
        Get-VMStatus($allClusterVMs)
    }
    
    # Display additional cluster information
    # Write-ColorOutput "`n=== Additional Cluster Information ===" "Cyan"
    
    # Write-ColorOutput "Cluster Name: $($cluster.Name)" "White"
    # Write-ColorOutput "DRS Enabled: $($cluster.DrsEnabled)" "White"
    # Write-ColorOutput "HA Enabled: $($cluster.HAEnabled)" "White"
    # Write-ColorOutput "vSAN Enabled: $($cluster.VsanEnabled)" "White"
    
    # Disconnect from vCenter
    Disconnect-VIServer -Server $connection -Confirm:$false
    Write-ColorOutput "`nDisconnected from vCenter" "White"
    
    Write-ColorOutput "`nCluster state check completed successfully!" "Green"
    Write-ColorOutput "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "Gray"
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
