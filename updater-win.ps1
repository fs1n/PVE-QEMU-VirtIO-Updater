<#
.SYNOPSIS
    PowerShell script to update virtio-win drivers on Windows by downloading the latest MSI from Fedora People Archive. Works on Windows systems with PowerShell 7 Installed.
.DESCRIPTION
    This script accesses the Fedora People Archive to find and download the latest version of the virtio-win drivers for Windows.
.NOTES
#>

if ($env:OS -ne "Windows_NT") {
    Write-Host "Dieses Script läuft nur auf Windows!" -ForegroundColor Red
    Write-Host "Aktuelles System: $($PSVersionTable.OS)" -ForegroundColor Yellow
    exit 1
}

# Region Variables

# Define Variables
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$FedoraPeopleArchiveRootURL = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/"


# Initialize log file path
$script:LogFilePath = "$PSScriptRoot\script_log_$(Get-Date -Format 'yyyy-MM-dd').log"

# EndRegion

# Region Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes log messages to a file with timestamp and severity level. 
    
    .DESCRIPTION
        Logs script events with Info, Warning, or Error levels using European date/time format (dd. MM.yyyy HH:mm:ss).
    
    .PARAMETER Message
        The message to log. 
    
    .PARAMETER Level
        The severity level:  Info, Warning, or Error.  Default is Info.
    
    .EXAMPLE
        Write-Log -Message "Script started" -Level Info
        Write-Log -Message "Configuration file not found" -Level Warning
        Write-Log -Message "Database connection failed" -Level Error
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    # European date/time format: dd.MM.yyyy HH:mm:ss
    $timestamp = Get-Date -Format "dd.MM.yyyy HH:mm:ss"
    
    # Format the log entry
    $logEntry = "$timestamp [$Level] $Message"
    
    # Ensure log file exists
    if (-not (Test-Path -Path $script:LogFilePath)) {
        New-Item -Path $script:LogFilePath -ItemType File -Force | Out-Null
        Add-Content -Path $script:LogFilePath -Value "=== Log initialized on $(Get-Date -Format 'dd.MM.yyyy HH: mm:ss') ==="
    }
    
    # Write to log file
    Add-Content -Path $script:LogFilePath -Value $logEntry
    
    # Also output to console with color coding
    switch ($Level) {
        "Info"    { Write-Host $logEntry -ForegroundColor Green }
        "Warning" { Write-Host $logEntry -ForegroundColor Yellow }
        "Error"   { Write-Host $logEntry -ForegroundColor Red }
    }
}

# EndRegion

# Region Script

$confirm = Read-Host "Should the virtIO-Drivers be updated? (J/N)"
if ($confirm -notmatch "^[JjYy]") {
    Write-Host "Script Canceled." -ForegroundColor Yellow
    exit 0
}

$FedoraPeopleArchiveRootSite = Invoke-WebRequest -Uri $FedoraPeopleArchiveRootURL -UseBasicParsing

if ($FedoraPeopleArchiveRootSite.StatusCode -eq 200) {
    Write-Log -Message "Successfully accessed Fedora People Archive at $FedoraPeopleArchiveRootURL" -Level "Info"
} else {
    Write-Log -Message "Failed to access Fedora People Archive at $FedoraPeopleArchiveRootURL. Status Code: $($FedoraPeopleArchiveRootSite.StatusCode)" -Level "Error"
    exit 1
}

$directoryLinks = $FedoraPeopleArchiveRootSite.Links |
    Where-Object { $_.href -match 'virtio-win-[\d\.]+-\d+/?$' } |
    ForEach-Object {
        $ver = [regex]::Match($_.href, 'virtio-win-([\d\.]+-\d+)').Groups[1].Value
        [PSCustomObject]@{ Href = $_.href; Version = $ver }
    }

$latest = $directoryLinks | 
    Sort-Object { [version]($_.Version -replace '-', '.') } -Descending | 
    Select-Object -First 1

# Open Latest Directory
$latestURL = $FedoraPeopleArchiveRootURL + $latest.Href
$latestSite = Invoke-WebRequest -Uri $latestURL -UseBasicParsing
if ($latestSite.StatusCode -eq 200) {
    Write-Log -Message "Successfully accessed latest virtio-win directory at $latestURL" -Level "Info"
} else {
    Write-Log -Message "Failed to access latest virtio-win directory at $latestURL. Status Code: $($latestSite.StatusCode)" -Level "Error"
    exit 1
}

# Download the MSI File 64-bit
$msiFileName = "virtio-win-gt-x64.msi"
$msiLink = $latestSite.Links | Where-Object { $_.href -eq $msiFileName } | Select-Object -First 1

if ($null -eq $msiLink) {
    Write-Log -Message "Could not find $msiFileName in the latest directory." -Level "Error"
    exit 1
}

# Construct the full download URL
$downloadURL = $latestURL + $msiFileName
Write-Log -Message "Download URL: $downloadURL" -Level "Info"

# Start download
$outputPath = Join-Path $ScriptRoot $msiFileName
Write-Log -Message "Starting download to: $outputPath" -Level "Info"

try {
    Invoke-WebRequest -Uri $downloadURL -OutFile $outputPath -UseBasicParsing
    Write-Log -Message "Successfully downloaded $msiFileName" -Level "Info"
} catch {
    Write-Log -Message "Failed to download $msiFileName. Error: $_" -Level "Error"
    exit 1
}

# Install the MSI
Write-Log -Message "Starting installation of $msiFileName" -Level "Info"
try {
    $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$outputPath`" /qn /norestart" -Wait -PassThru
    if ($installProcess.ExitCode -eq 0) {
        Write-Log -Message "Successfully installed $msiFileName" -Level "Info"
    } else {
        Write-Log -Message "Installation of $msiFileName failed with exit code $($installProcess.ExitCode)" -Level "Error"
        exit 1
    }
} catch {
    Write-Log -Message "Failed to install $msiFileName. Error: $_" -Level "Error"
    exit 1
}

# EndRegion