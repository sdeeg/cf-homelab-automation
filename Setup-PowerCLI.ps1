<#
.SYNOPSIS
    Setup script to install VCF PowerCLI for the vCenter cluster shutdown script
    
.DESCRIPTION
    This script installs the VCF PowerCLI module required for the cluster shutdown script.
    It also configures PowerCLI with appropriate settings for lab environments.
    Can be run as Administrator (installs for all users) or as regular user (installs for current user only).
    
.NOTES
    Author: Lab Administrator
    Requires: PowerShell 5.1 or higher
    Optional: Administrator privileges (for system-wide installation)
#>

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "VCF PowerCLI Setup Script" "Cyan"
Write-ColorOutput ("=" * 40) "Cyan"

# Check PowerShell version
$psVersion = $PSVersionTable.PSVersion
Write-ColorOutput "`nPowerShell Version: $($psVersion.Major).$($psVersion.Minor)" "White"

if ($psVersion.Major -lt 5) {
    Write-ColorOutput "ERROR: PowerShell 5.1 or higher is required!" "Red"
    Write-ColorOutput "Please upgrade PowerShell and try again." "Yellow"
    exit 1
}

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-ColorOutput "WARNING: Not running as Administrator" "Yellow"
    Write-ColorOutput "Installing PowerCLI for current user only..." "Yellow"
    $scope = "CurrentUser"
} else {
    Write-ColorOutput "Running as Administrator" "Green"
    $scope = "AllUsers"
}

try {
    # Check if PowerCLI is already installed
    Write-ColorOutput "`nChecking for existing PowerCLI installation..." "White"
    $existingModule = Get-Module -ListAvailable -Name VCF.PowerCLI
    
    if ($existingModule) {
        Write-ColorOutput "PowerCLI is already installed:" "Green"
        foreach ($module in $existingModule) {
            Write-ColorOutput "  Version: $($module.Version) - Path: $($module.ModuleBase)" "White"
        }
        
        $update = Read-Host "`nDo you want to update to the latest version? (y/n)"
        if ($update.ToLower() -eq 'y' -or $update.ToLower() -eq 'yes') {
            Write-ColorOutput "Updating PowerCLI..." "Yellow"
            Update-Module -Name VCF.PowerCLI -Scope $scope -Force
            Write-ColorOutput "PowerCLI updated successfully!" "Green"
        }
    } else {
        # Install PowerCLI
        Write-ColorOutput "PowerCLI not found. Installing..." "Yellow"
        
        # Set TLS 1.2 for PowerShell Gallery
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Install NuGet provider if needed
        Write-ColorOutput "Checking NuGet provider..." "White"
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Write-ColorOutput "Installing NuGet provider..." "Yellow"
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope $scope
        }
        
        # Trust PowerShell Gallery
        Write-ColorOutput "Configuring PowerShell Gallery..." "White"
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        
        # Install PowerCLI
        Write-ColorOutput "Installing VCF PowerCLI (this may take several minutes)..." "Yellow"
        Install-Module -Name VCF.PowerCLI -Scope $scope -Force -AllowClobber
        
        Write-ColorOutput "PowerCLI installed successfully!" "Green"
    }
    
    # Import and configure PowerCLI
    Write-ColorOutput "`nConfiguring PowerCLI..." "White"
    Import-Module VCF.PowerCLI -Force
    
    # Configure PowerCLI settings for lab environment
    Write-ColorOutput "Setting PowerCLI configuration..." "White"
    
    # Disable certificate warnings (common in lab environments)
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    
    # Disable CEIP (Customer Experience Improvement Program)
    Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false | Out-Null
    
    # Set default VIServer mode to multiple (allows multiple connections)
    Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false | Out-Null
    
    Write-ColorOutput "PowerCLI configuration completed!" "Green"
    
    # Display PowerCLI information
    Write-ColorOutput "`nPowerCLI Installation Summary:" "Cyan"
    $powercliVersion = (Get-Module VCF.PowerCLI).Version
    Write-ColorOutput "  Version: $powercliVersion" "White"
    Write-ColorOutput "  Installation Scope: $scope" "White"
    
    # List key PowerCLI modules
    Write-ColorOutput "`nInstalled PowerCLI Modules:" "White"
    $coreModules = @('VCF.VimAutomation.Core', 'VCF.VimAutomation.Common', 'VCF.VimAutomation.Cis.Core')
    foreach ($moduleName in $coreModules) {
        $module = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1
        if ($module) {
            Write-ColorOutput "  ✓ $($module.Name) - $($module.Version)" "Green"
        } else {
            Write-ColorOutput "  ✗ $moduleName - Not found" "Red"
        }
    }
    
    Write-ColorOutput "`nSetup completed successfully!" "Green"
    Write-ColorOutput "`nNext steps:" "Yellow"
    Write-ColorOutput "1. Edit Shutdown-vCenterCluster.ps1 and update the configuration variables" "White"
    Write-ColorOutput "2. Run the script: .\Shutdown-vCenterCluster.ps1" "White"
    Write-ColorOutput "`nNote: You may need to set execution policy if you encounter script execution errors:" "Yellow"
    Write-ColorOutput "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" "White"
    
} catch {
    Write-ColorOutput "`nERROR: $($_.Exception.Message)" "Red"
    Write-ColorOutput "`nSetup failed! Please check the error above and try again." "Red"
    exit 1
}

Write-ColorOutput "`nPress any key to exit..." "White"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
