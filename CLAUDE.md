# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains PowerShell automation scripts for managing VMware vCenter clusters in a lab environment. The scripts focus on graceful shutdown/startup operations and cluster status monitoring for ESXi 8.0 and vCenter Server systems.

## Prerequisites

- Windows PowerShell 5.1 or higher
- VCF PowerCLI module (VMware Cloud Foundation PowerCLI)
- VMware PowerCLI Core module
- Network access to vCenter Server
- Valid vCenter credentials with appropriate privileges

## Initial Setup

1. **Install VCF PowerCLI**: Run `.\Setup-PowerCLI.ps1` as Administrator to install and configure VCF PowerCLI
2. **Configure Environment**: 
   - Set `$env:TANZU_SECRETS` to point to your `tanzu-env.json` configuration file
   - Default location: `$HOME\.sekrits\tanzu-env.json`
   - Template available in `config\tanzu-env.json`

## Core Scripts

### Main Operations
- `Shutdown-vCenterCluster.ps1` - Gracefully shutdown all VMs and ESXi hosts in a cluster
- `Startup-Tanzu.ps1` - Start up ESXi hosts and VMs in proper sequence
- `Cluster-State.ps1` - Display current status of cluster hosts and VMs

### Utility Scripts
- `Setup-PowerCLI.ps1` - Install and configure VCF PowerCLI module
- `Load-Env.ps1` - Environment configuration loader and vCenter connection manager
- `opsman.ps1` - Operations Manager specific automation

## Configuration

All scripts use a centralized JSON configuration file (`tanzu-env.json`) containing:

- **vCenter connection details**: server, username, password, cluster name
- **VM configuration**: startup order, priority VMs, target VMs list
- **Timeouts**: VM startup/shutdown, host maintenance, vCenter connection
- **Operations Manager settings**: URL, credentials

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

## Required vCenter Privileges

The service account needs these minimum privileges:
- `Host.Config.Maintenance` - For maintenance mode operations
- `Host.Config.Power` - For host shutdown/startup
- `Resource.AssignVMToPool` - For VM migration during maintenance
- `System.Read` - For cluster access
- `VirtualMachine.Interact.PowerOff` - For VM shutdown operations

## Safety Features

- **Confirmation prompts** before destructive operations
- **Graceful operations** using proper vSphere API calls
- **Status validation** before proceeding with operations
- **vCLS VM exclusion** (vSphere Cluster Services VMs are automatically managed)
- **Priority VM handling** for critical infrastructure components