# VMware Cloud Foundation Homelab Automation

This repository contains PowerShell automation scripts for managing VMware vCenter clusters in a lab environment. The scripts focus on graceful shutdown/startup operations and cluster status monitoring for ESXi 8.0 and vCenter Server systems using VCF PowerCLI.

## Scripts Overview

### Core Operations
- **`Shutdown-vCenterCluster.ps1`** - Gracefully shutdown all VMs and ESXi hosts in a cluster
- **`Startup-Tanzu.ps1`** - Start up ESXi hosts and VMs in proper sequence
- **`Cluster-State.ps1`** - Display current status of cluster hosts and VMs

### Utility Scripts
- **`Setup-PowerCLI.ps1`** - Install and configure VCF PowerCLI module
- **`Load-Env.ps1`** - Environment configuration loader and vCenter connection manager

### Configuration
- **`config/tanzu-env.json`** - Template for environment configuration

## Prerequisites

- Windows PowerShell 5.1 or higher
- VCF PowerCLI module (VMware Cloud Foundation PowerCLI)
- VMware PowerCLI Core module
- Network access to vCenter Server
- Valid vCenter credentials with appropriate privileges

### Required vCenter Privileges
The service account needs these minimum privileges:
- `Host.Config.Maintenance` - For maintenance mode operations
- `Host.Config.Power` - For host shutdown/startup
- `Resource.AssignVMToPool` - For VM migration during maintenance
- `System.Read` - For cluster access
- `VirtualMachine.Interact.PowerOff` - For VM shutdown operations

## Initial Setup

### 1. Install VCF PowerCLI
Run the setup script as Administrator to install and configure VCF PowerCLI:
```powershell
.\Setup-PowerCLI.ps1
```

If you encounter execution policy errors, run:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 2. Configure Environment
1. Set the `$env:TANZU_SECRETS` environment variable to point to your `tanzu-env.json` configuration file
2. Default location: `$HOME\.sekrits\tanzu-env.json`
3. Use the template in `config\tanzu-env.json` as a starting point

## Configuration

All scripts use a centralized JSON configuration file (`tanzu-env.json`) containing:

```json
{
  "vcenter": {
    "server": "vcenter.mydomain",
    "username": "administrator@mydomain",
    "password": "password",
    "cluster_name": "vcenter-cluster"
  },
  "ops_manager": {
    "url": "https://opsmanager.mydomain",
    "username": "tanzu",
    "password": "Tanzu1!"
  },
  "vm_configuration": {
    "vms_to_start": [
      "pivotal-ops-manager",
      "tanzu-admin"
    ],
    "cf_vm_director_tag": "p-bosh",
    "bosh_vm_director_tag": "bosh-init"
  },
  "timeouts": {
    "vm_startup_timeout": 300,
    "vm_shutdown_timeout": 300,
    "host_maintenance_timeout": 600,
    "vcenter_connection_timeout": 60
  }
}
```

### Configuration Details
- **vCenter connection details**: server, username, password, cluster name
- **VM configuration**: startup order, priority VMs, target VMs list
- **Timeouts**: VM startup/shutdown, host maintenance, vCenter connection
- **Operations Manager settings**: URL, credentials

## Usage

### Shutdown Cluster
```powershell
.\Shutdown-vCenterCluster.ps1
```
Gracefully shuts down all VMs and ESXi hosts in the cluster using a three-phase process.

### Startup Cluster  
```powershell
.\Startup-Tanzu.ps1
```
Starts up ESXi hosts and VMs in the proper sequence.

### Check Cluster Status
```powershell
.\Cluster-State.ps1
```
Displays current connection status and state of all hosts and VMs in the cluster.

All scripts will:
1. Load configuration from `tanzu-env.json`
2. Connect to vCenter Server
3. Display current cluster status
4. Ask for confirmation before making changes

## Architecture

### Configuration Management
- `Load-Env.ps1` handles environment loading and vCenter connection establishment
- Configuration is loaded from JSON and made available as PowerShell variables
- Connection pooling ensures single vCenter session across script operations

### VM Shutdown Process (3-Phase)
1. **VM Shutdown**: Graceful shutdown starting with priority VM (typically ops-manager)
2. **Maintenance Mode**: Put all hosts into maintenance mode with VSAN data migration
3. **Host Shutdown**: Gracefully shutdown ESXi hosts

### VM Startup Process
1. **Exit Maintenance Mode**: Take hosts out of maintenance mode
2. **VM Startup**: Start VMs in configured order with boot delays
3. **Health Validation**: Verify final state of cluster and VMs

### Error Handling
- Comprehensive timeout management for all operations
- Graceful fallback to force operations when timeouts occur
- Colored console output for operation status visibility
- Connection cleanup on script exit

## Safety Features

- **Confirmation prompts** before destructive operations
- **Graceful operations** using proper vSphere API calls
- **Status validation** before proceeding with operations
- **vCLS VM exclusion** (vSphere Cluster Services VMs are automatically managed)
- **Priority VM handling** for critical infrastructure components
- **Timeout management** with configurable timeouts and fallback operations
- **Colored console output** for clear operation status visibility

## Important Notes

- **These scripts will shutdown ALL hosts in the specified cluster**
- SSL certificate verification is disabled for self-signed certificates  
- Make sure you have console/iLO access to hosts in case of issues
- Test in a non-production environment first
- **ALL VMs will be explicitly shutdown before host maintenance**
- The priority VM (typically ops-manager) will be shutdown first
- VMs that don't respond to graceful shutdown will be force-stopped
- Hosts enter maintenance mode after all VMs are shutdown

## Troubleshooting

### Common Issues

1. **PowerCLI Not Found**: Run `.\Setup-PowerCLI.ps1` as Administrator
2. **Execution Policy Error**: Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
3. **Connection Failed**: Check network connectivity and vCenter credentials
4. **Cluster Not Found**: Verify the cluster name is correct and case-sensitive
5. **Permission Denied**: Ensure the user account has sufficient privileges
6. **VM Shutdown Timeout**: Increase timeout values in `tanzu-env.json`
7. **Maintenance Mode Timeout**: Increase `host_maintenance_timeout` in configuration
8. **Configuration Not Found**: Ensure `$env:TANZU_SECRETS` points to valid `tanzu-env.json`

## Common Development Tasks

### Running Scripts
- Always run from the repository root directory
- Scripts automatically source `Load-Env.ps1` for configuration
- Use colored output functions (`Write-ColorOutput`) for consistent messaging

### Adding New Operations
- Follow the three-phase pattern for cluster operations
- Use configuration variables from `Load-Env.ps1`
- Implement timeout handling with user-configurable values
- Include proper error handling and cleanup

### Debugging
- Scripts include detailed stack trace output on errors
- Connection status is validated before operations
- VM and host status is displayed before and after operations

## Example Output

### Shutdown Script Output:
```
vCenter Cluster Shutdown Script (PowerCLI)
Loading configuration from: C:\Users\user\.sekrits\tanzu-env.json
Connecting to vCenter: vcenter.mydomain
Successfully connected to vCenter

Found cluster: vcenter-cluster
Cluster Information:
  Hosts: 3
  Total VMs: 8
  Powered-on VMs: 6

WARNING: This will perform the following actions:
1. Shutdown ALL VMs in the cluster (starting with pivotal-ops-manager)
2. Put all hosts into maintenance mode  
3. Shutdown all ESXi hosts

Do you want to continue? (yes/no): yes

=== VM Shutdown Phase ===
Shutting down priority VM: pivotal-ops-manager
All VMs shutdown successfully!

=== Maintenance Mode Phase ===
All hosts entered maintenance mode successfully!

=== Host Shutdown Phase ===
All hosts shutdown successfully!

Script completed successfully!
```

## License

This script is provided as-is for educational and lab use. Use at your own risk.
