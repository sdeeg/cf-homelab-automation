# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Format-PadRight {
    param(
        [string]$Text,
        [int]$Width
    )
    if ($Text.Length -ge $Width) {
        return $Text
    }
    return $Text + (' ' * ($Width - $Text.Length))
}


# Function to find tanzu-env.json on PATH
function Find-TanzuEnvOnPath {
    $pathDirs = $env:PATH -split ';'
    foreach ($dir in $pathDirs) {
        if (Test-Path $dir) {
            $tanzuEnvPath = Join-Path $dir "tanzu-env.json"
            if (Test-Path $tanzuEnvPath -PathType Leaf) {
                return $tanzuEnvPath
            }
        }
    }
    return $null
}

function Load-Env {
    param(
        [string]$defaultPath = $null
    )
    if([string]::IsNullOrEmpty($defaultPath)) {
        $defaultPath = Join-Path $PSScriptRoot "config\tanzu-env.json"
    }

    $tanzuSecrets = $env:TANZU_SECRETS

    if ([string]::IsNullOrEmpty($tanzuSecrets)) {
        Write-Host "WARN: TANZU_SECRETS environment variable is not set or is empty." -ForegroundColor Yellow
        
        # Find default value (tanzu-env.json on PATH)
        Write-ColorOutput "Looking for default env file on PATH" "Yellow"
        $envOnPath = Find-TanzuEnvOnPath
        
        if ($envOnPath) {
            $tanzuSecrets = $envOnPath
            Write-Host "SUCCESS: Set tanzuSecrets to env file found on PATH" -ForegroundColor Green
        } else {
            $tanzuSecrets = $defaultPath
            Write-Warning "Could not find tanzu-env.json on PATH. Looking on dev path"
            if (Test-Path $tanzuSecrets -PathType Leaf) {
                Write-Host "SUCCESS: tanzuSecrets points to valid file" -ForegroundColor Green
            } else {
                Write-ColorOutput "ERROR: Could not find tanzu-env.json file" "Red"
                exit 1
            }
        }
    } else {
        # Variable exists and has a value, test if it's a valid file
        if (Test-Path $tanzuSecrets -PathType Leaf) {
            Write-Host "SUCCESS: tanzuSecrets points to valid file" -ForegroundColor Green
        } else {
            Write-Warning "tanzuSecrets is not a valid file path.  Attempting to find tanzu-env.json on PATH"
            
            # Use default value
            $envPath = Find-TanzuEnvOnPath
            
            if ($envPath) {
                $tanzuSecrets = $envPath
                Write-Host "SUCCESS: Set tanzuSecrets to env file found on PATH" -ForegroundColor Green
            } else {
                Write-Warning "Could not find tanzu-env.json on PATH. Looking on dev path."
                $tanzuSecrets = $defaultPath
                if (Test-Path $tanzuSecrets -PathType Leaf) {
                    Write-Host "SUCCESS: tanzuSecrets points to valid file" -ForegroundColor Green
                } else {
                    Write-ColorOutput "ERROR: Could not find configuration file" "Red"
                    exit 1
                }
            }
        }
    }

    # Load configuration from external file
    if (-not (Test-Path $tanzuSecrets)) {
        Write-ColorOutput "ERROR: Configuration file not found: $tanzuSecrets" "Red"
        Write-ColorOutput "Please copy tanzu-env.template to tanzu-env.json and update the values for your environment" "Yellow"
        exit 1
    }

    try {
        $config = Get-Content $tanzuSecrets -Raw | ConvertFrom-Json
    } catch {
        Write-ColorOutput "ERROR: Failed to parse configuration file: $($_.Exception.Message)" "Red"
        exit 1
    }

    return $config
}

function Test-vCenterConnection {
    param(
        [string]$Server,
        [string]$Username,
        [string]$Password,
        [int]$TimeoutSeconds = 60
    )
    
    Write-ColorOutput "`n=== vCenter Connection Validation ===" "Cyan"
    Write-ColorOutput "Testing connection to vCenter: $Server" "White"
    Write-ColorOutput "Timeout: $TimeoutSeconds seconds" "White"
    
    $startTime = Get-Date
    $connected = $false
    $connection = $null
    
    try {
        # Attempt connection with timeout
        $job = Start-Job -ScriptBlock {
            param($Server, $Username, $Password)
            # Try to import VCF.PowerCLI if available, otherwise use standard PowerCLI
            if (Get-Module -ListAvailable -Name VCF.PowerCLI) {
                Import-Module VCF.PowerCLI -ErrorAction Stop
            }
            Import-Module VMware.VimAutomation.Core -ErrorAction Stop
            Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
            Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false | Out-Null
            Connect-VIServer -Server $Server -User $Username -Password $Password -ErrorAction Stop
        } -ArgumentList $Server, $Username, $Password
        
        # Wait for job completion or timeout
        $job | Wait-Job -Timeout $TimeoutSeconds | Out-Null
        
        if ($job.State -eq "Completed") {
            $connection = Receive-Job -Job $job
            $connected = $true
            $elapsed = ((Get-Date) - $startTime).TotalSeconds
            Write-ColorOutput "Successfully connected to vCenter in $([math]::Round($elapsed, 1)) seconds" "Green"
        } else {
            Write-ColorOutput "Connection attempt timed out after $TimeoutSeconds seconds" "Red"
            $job | Stop-Job
        }
        
        $job | Remove-Job -Force
        
    } catch {
        Write-ColorOutput "Connection failed: $($_.Exception.Message)" "Red"
    }
    
    return @{
        Connected = $connected
        Connection = $connection
    }
}

#Create the main configuration variable

function Get-VCenter-Connection { return $connection }

try {
    Write-ColorOutput "Load vCenter Script Env" "Cyan"
    
    # Check if VCF PowerCLI is installed
    if (-not (Get-Module -ListAvailable -Name VCF.PowerCLI)) {
        Write-ColorOutput "ERROR: VCF PowerCLI module is not installed!" "Red"
        Write-ColorOutput "Install it using: Install-Module -Name VCF.PowerCLI -Scope CurrentUser" "Yellow"
        Write-ColorOutput "Or run the Setup-PowerCLI.ps1 script to install and configure VCF PowerCLI" "Yellow"
        exit 1
    }
    
    # Check if VMware PowerCLI Core is installed
    if (-not (Get-Module -ListAvailable -Name VMware.VimAutomation.Core)) {
        Write-ColorOutput "ERROR: VMware PowerCLI Core module is not installed!" "Red"
        Write-ColorOutput "Install it using: Install-Module -Name VMware.PowerCLI -Scope CurrentUser" "Yellow"
        Write-ColorOutput "Or run the Setup-PowerCLI.ps1 script to install and configure PowerCLI" "Yellow"
        exit 1
    }
    
    # Import VCF PowerCLI modules
    Write-ColorOutput "Loading VCF PowerCLI modules..." "White"
    Import-Module VCF.PowerCLI -ErrorAction Stop
    
    # Import VMware PowerCLI Core module for Get-VM and other cmdlets
    Write-ColorOutput "Loading VMware PowerCLI Core modules..." "White"
    Import-Module VMware.VimAutomation.Core -ErrorAction Stop
    
    # Disable certificate warnings for self-signed certificates
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false | Out-Null

    $config = Load-Env

    # Connection configuration
    $vCenterServer = $config.vcenter.server
    $Username = $config.vcenter.username
    $Password = $config.vcenter.password
    $ClusterName = $config.vcenter.cluster_name

    $vCenterConnectionTimeout = $config.timeouts.vcenter_connection_timeout

    # VM startup configuration
    $VMsToStart = $config.vm_configuration.vms_to_start
    $VMStartupTimeout = $config.timeouts.vm_startup_timeout
    $HostMaintenanceTimeout = $config.timeouts.host_maintenance_timeout
    $VMShutdownTimeout = $config.timeouts.vm_shutdown_timeout
    $vCenterConnectionTimeout = $config.timeouts.vcenter_connection_timeout
    $PriorityVM = $config.vm_configuration.priority_vm
    
    # Director tag configuration
    $CFVMDirectorTag = $config.vm_configuration.cf_vm_director_tag
    $BOSHVMDirectorTag = $config.vm_configuration.bosh_vm_director_tag

    # Establish connection for operations
    $connection = Connect-VIServer -Server $vCenterServer -User $Username -Password $Password -ErrorAction Stop
    Write-ColorOutput "Load-Env: Successfully connected to vCenter" "Green"
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
