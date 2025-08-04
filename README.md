# vCenter Host Shutdown Scripts

This repository contains two scripts for gracefully shutting down VMware vCenter clusters:

1. **Python Script** (`vcenter_host_shutdown.py`) - Uses the vSphere API via pyvmomi
2. **PowerShell Script** (`Shutdown-vCenterCluster.ps1`) - Uses VMware PowerCLI

Both scripts are designed for small computer labs running ESXi 8.0 and vCenter.

## Script Comparison

| Feature | Python Script | PowerShell Script |
|---------|---------------|-------------------|
| **VM Shutdown** | Puts hosts in maintenance mode (VMs migrate/shutdown automatically) | **Explicitly shuts down all VMs first** |
| **Priority VM** | Not supported | **Shuts down pivotal-ops-manager first** |
| **Maintenance Mode** | Enters before host shutdown | Enters after VM shutdown |
| **Dependencies** | pyvmomi library | VMware PowerCLI |
| **Platform** | Cross-platform (Windows/Linux/Mac) | Windows PowerShell |
| **Output** | Basic text output | **Colored console output** |

**Recommendation**: Use the **PowerShell script** if you need explicit VM shutdown control and are running on Windows. Use the Python script for cross-platform compatibility.

## Python Script Features

- Connects to vCenter Server using the vSphere API
- Automatically puts hosts into maintenance mode before shutdown
- Gracefully shuts down all hosts in a specified cluster
- Provides detailed logging and progress updates
- Includes safety confirmation prompt
- Handles SSL certificate verification for self-signed certificates

## PowerShell Script Features

- **Explicit VM shutdown sequence** (starting with pivotal-ops-manager)
- **Colored console output** for better readability
- **Three-phase shutdown process**:
  1. Shutdown all VMs (priority VM first)
  2. Put hosts in maintenance mode
  3. Shutdown ESXi hosts
- Comprehensive error handling and timeout management
- Force shutdown fallback for unresponsive VMs
- Detailed progress reporting for each phase

## Prerequisites

### For Python Script:
- Python 3.6 or higher
- Network access to your vCenter Server
- Valid vCenter credentials

### For PowerShell Script:
- Windows PowerShell 5.1 or higher
- VMware PowerCLI module
- Network access to your vCenter Server
- Valid vCenter credentials

### Required vCenter Privileges (Both Scripts):
- Host.Config.Maintenance
- Host.Config.Power
- Resource.AssignVMToPool (for VM migration)
- System.Read (for cluster access)
- VirtualMachine.Interact.PowerOff (for VM shutdown - PowerShell script)

## Installation

### Python Script Setup:
1. Clone or download these scripts to your local machine
2. Install the required Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```
   Or run the setup batch file:
   ```cmd
   .\setup.bat
   ```

### PowerShell Script Setup:
1. **Run as Administrator** and execute the PowerCLI setup script:
   ```powershell
   .\Setup-PowerCLI.ps1
   ```
   This will install VMware PowerCLI and configure it for lab use.

2. If you encounter execution policy errors, run:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Configuration

### Python Script Configuration:
Update the configuration variables at the top of `vcenter_host_shutdown.py`:

```python
# Configuration - Update these values for your environment
VCENTER_HOST = "your-vcenter-server.domain.com"      # Your vCenter server FQDN or IP
VCENTER_USER = "administrator@vsphere.local"         # Your vCenter username
VCENTER_PASSWORD = "your-password"                   # Your vCenter password
CLUSTER_NAME = "your-cluster-name"                   # Name of the cluster to shutdown
VCENTER_PORT = 443                                   # vCenter port (usually 443)
```

### PowerShell Script Configuration:
Update the configuration variables at the top of `Shutdown-vCenterCluster.ps1`:

```powershell
# Configuration - Update these values for your environment
$vCenterServer = "your-vcenter-server.domain.com"
$Username = "administrator@vsphere.local"
$Password = "your-password"
$ClusterName = "your-cluster-name"

# VM shutdown configuration
$PriorityVM = "pivotal-ops-manager"  # VM to shutdown first
$VMShutdownTimeout = 300             # Timeout in seconds for VM shutdown
$HostMaintenanceTimeout = 600        # Timeout in seconds for maintenance mode
```

### Example Configuration:
```powershell
$vCenterServer = "vcenter.lab.local"
$Username = "administrator@vsphere.local"
$Password = "VMware123!"
$ClusterName = "Lab-Cluster"
$PriorityVM = "pivotal-ops-manager"
```

## Usage

### Python Script:
1. Update the configuration variables in `vcenter_host_shutdown.py`
2. Run the script:
   ```bash
   python vcenter_host_shutdown.py
   ```
3. Review the cluster and host information displayed
4. Type `yes` when prompted to confirm the shutdown operation

### PowerShell Script:
1. Update the configuration variables in `Shutdown-vCenterCluster.ps1`
2. Run the script:
   ```powershell
   .\Shutdown-vCenterCluster.ps1
   ```
3. Review the cluster, host, and VM information displayed
4. Type `yes` when prompted to confirm the shutdown operation

## What the Scripts Do

### Python Script Process:
1. **Connects to vCenter**: Establishes a secure connection to your vCenter Server
2. **Finds the Cluster**: Locates the specified cluster by name
3. **Lists Hosts**: Displays all hosts in the cluster and their current power state
4. **Confirmation**: Asks for user confirmation before proceeding
5. **For Each Host**:
   - Checks if already in maintenance mode
   - Enters maintenance mode (evacuates VMs if needed)
   - Initiates graceful shutdown
   - Waits for completion and reports status

### PowerShell Script Process:
1. **Connects to vCenter**: Establishes a secure connection using PowerCLI
2. **Finds the Cluster**: Locates the specified cluster and displays summary
3. **Lists Resources**: Shows hosts, VMs, and their current states
4. **Confirmation**: Asks for user confirmation before proceeding
5. **Phase 1 - VM Shutdown**:
   - Shuts down priority VM (pivotal-ops-manager) first
   - Shuts down all remaining VMs gracefully
   - Force stops any VMs that don't respond to graceful shutdown
6. **Phase 2 - Maintenance Mode**:
   - Puts all hosts into maintenance mode
   - Waits for completion with timeout handling
7. **Phase 3 - Host Shutdown**:
   - Gracefully shuts down all ESXi hosts
   - Reports completion status

## Safety Features

### Both Scripts:
- **Confirmation Prompt**: Requires explicit user confirmation before shutdown
- **Graceful Shutdown**: Uses proper vSphere API calls for clean shutdown
- **Error Handling**: Comprehensive error handling and reporting
- **Status Checking**: Skips resources that are already in desired state

### Python Script Specific:
- **Maintenance Mode**: Automatically enters maintenance mode to safely migrate VMs

### PowerShell Script Specific:
- **VM Priority Shutdown**: Ensures critical VMs (pivotal-ops-manager) shutdown first
- **Timeout Management**: Configurable timeouts with fallback to force operations
- **Force Shutdown Fallback**: Automatically force-stops unresponsive VMs
- **Three-Phase Process**: Separates VM shutdown, maintenance mode, and host shutdown
- **Colored Output**: Easy-to-read status updates with color coding

## Important Notes

### Both Scripts:
- **These scripts will shutdown ALL hosts in the specified cluster**
- SSL certificate verification is disabled for self-signed certificates
- Make sure you have console/iLO access to hosts in case of issues
- Test in a non-production environment first

### Python Script Specific:
- Virtual machines will be migrated or shutdown as part of the maintenance mode process
- The script uses graceful shutdown (not forced) - hosts with issues may not shutdown

### PowerShell Script Specific:
- **ALL VMs will be explicitly shutdown before host maintenance**
- The pivotal-ops-manager VM will be shutdown first
- VMs that don't respond to graceful shutdown will be force-stopped
- Hosts enter maintenance mode after all VMs are shutdown

## Troubleshooting

### Common Issues:

#### Python Script:
1. **Connection Failed**: Check network connectivity and vCenter credentials
2. **Cluster Not Found**: Verify the cluster name is correct and case-sensitive
3. **Permission Denied**: Ensure the user account has sufficient privileges
4. **Maintenance Mode Failed**: Check for VMs that cannot be migrated
5. **Module Import Error**: Run `pip install -r requirements.txt`

#### PowerShell Script:
1. **PowerCLI Not Found**: Run `.\Setup-PowerCLI.ps1` as Administrator
2. **Execution Policy Error**: Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
3. **VM Shutdown Timeout**: Increase `$VMShutdownTimeout` value in script
4. **Maintenance Mode Timeout**: Increase `$HostMaintenanceTimeout` value in script
5. **Connection Failed**: Check network connectivity and vCenter credentials

### Required vCenter Privileges:

The user account needs the following privileges:
- Host.Config.Maintenance
Connecting to vCenter: vcenter.lab.local
Successfully connected to vCenter
Looking for cluster: Lab-Cluster
Found cluster: Lab-Cluster
Found 3 hosts in cluster:
  - esxi01.lab.local (Status: poweredOn)
  - esxi02.lab.local (Status: poweredOn)
  - esxi03.lab.local (Status: poweredOn)

WARNING: This will gracefully shutdown all hosts in the cluster!
This action will:
1. Put each host in maintenance mode
2. Migrate or shutdown VMs as needed
3. Shutdown each host

Do you want to continue? (yes/no): yes

Starting graceful shutdown of 3 hosts...

[1/3] Processing host: esxi01.lab.local
Initiating graceful shutdown of host: esxi01.lab.local
  Entering maintenance mode for esxi01.lab.local...
  esxi01.lab.local is now in maintenance mode
  Shutting down esxi01.lab.local...
  esxi01.lab.local shutdown initiated successfully

[2/3] Processing host: esxi02.lab.local
...

Shutdown process completed!
Successfully processed: 3/3 hosts
All hosts have been gracefully shutdown.

Script completed successfully!
```
- Host.Config.Power
- Resource.AssignVMToPool (for VM migration)
- System.Read (for cluster access)
- VirtualMachine.Interact.PowerOff (for PowerShell script VM shutdown)

## Example Output

### Python Script Output:
```
vCenter Host Shutdown Script
Connecting to vCenter: vcenter.lab.local
Successfully connected to vCenter
Looking for cluster: Lab-Cluster
Found cluster: Lab-Cluster
Found 3 hosts in cluster:
  - esxi01.lab.local (Status: poweredOn)
  - esxi02.lab.local (Status: poweredOn)
  - esxi03.lab.local (Status: poweredOn)

WARNING: This will gracefully shutdown all hosts in the cluster!
Do you want to continue? (yes/no): yes

Starting graceful shutdown of 3 hosts...
[1/3] Processing host: esxi01.lab.local
  Entering maintenance mode for esxi01.lab.local...
  esxi01.lab.local is now in maintenance mode
  Shutting down esxi01.lab.local...

Script completed successfully!
```

### PowerShell Script Output:
```
vCenter Cluster Shutdown Script (PowerCLI)
Loading PowerCLI modules...
Connecting to vCenter: vcenter.lab.local
Successfully connected to vCenter
Looking for cluster: Lab-Cluster
Found cluster: Lab-Cluster

Cluster Information:
  Hosts: 3
  Total VMs: 12
  Powered-on VMs: 8

Hosts in cluster:
  - esxi01.lab.local (Status: Connected)
  - esxi02.lab.local (Status: Connected)
  - esxi03.lab.local (Status: Connected)

WARNING: This will perform the following actions:
1. Shutdown ALL VMs in the cluster (starting with pivotal-ops-manager)
2. Put all hosts into maintenance mode
3. Shutdown all ESXi hosts

Do you want to continue? (yes/no): yes

=== VM Shutdown Phase ===
Found 8 powered-on VMs in cluster Lab-Cluster

Shutting down priority VM: pivotal-ops-manager
  Shutdown command sent to pivotal-ops-manager
  pivotal-ops-manager shutdown successfully

Shutting down remaining 7 VMs...
  Shutting down: web-server-01
  Shutting down: database-01
  ...
All VMs in cluster have been shutdown successfully!

=== Maintenance Mode Phase ===
Putting 3 hosts into maintenance mode...
  Entering maintenance mode: esxi01.lab.local
    esxi01.lab.local is now in maintenance mode
  ...

=== Host Shutdown Phase ===
Shutting down 3 hosts...
  Shutting down host: esxi01.lab.local
    Shutdown command sent to esxi01.lab.local
  ...

=== Shutdown Sequence Complete ===
All shutdown commands have been sent.
Script completed successfully!
```
========================================
Connecting to vCenter: vcenter.lab.local
Successfully connected to vCenter
Looking for cluster: Lab-Cluster
Found cluster: Lab-Cluster
Found 3 hosts in cluster:
  - esxi01.lab.local (Status: poweredOn)
  - esxi02.lab.local (Status: poweredOn)
  - esxi03.lab.local (Status: poweredOn)

WARNING: This will gracefully shutdown all hosts in the cluster!
This action will:
1. Put each host in maintenance mode
2. Migrate or shutdown VMs as needed
3. Shutdown each host

Do you want to continue? (yes/no): yes

Starting graceful shutdown of 3 hosts...

[1/3] Processing host: esxi01.lab.local
Initiating graceful shutdown of host: esxi01.lab.local
  Entering maintenance mode for esxi01.lab.local...
  esxi01.lab.local is now in maintenance mode
  Shutting down esxi01.lab.local...
  esxi01.lab.local shutdown initiated successfully

[2/3] Processing host: esxi02.lab.local
...

Shutdown process completed!
Successfully processed: 3/3 hosts
All hosts have been gracefully shutdown.

Script completed successfully!
```

## License

This script is provided as-is for educational and lab use. Use at your own risk.
