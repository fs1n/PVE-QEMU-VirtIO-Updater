<#
.SYNOPSIS
    PowerShell script to update virtio-win drivers on Windows by downloading the latest MSI from Fedora People Archive. Works on Windows systems with PowerShell 7 Installed.
.DESCRIPTION
    This script accesses the Fedora People Archive to find and download the latest version of the virtio-win drivers for Windows.
.NOTES
#>

if ($env:OS -ne "Windows_NT") {
    Write-Host "This script is only intended to run on Windows systems!" -ForegroundColor Red
    Write-Host "Current system: $($PSVersionTable.OS)" -ForegroundColor Yellow
    exit 1
}

# Check if run as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run with administrator privileges!" -ForegroundColor Red
    exit 1
}

if ($PSVersionTable.PSVersion.Major -le 5) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

#Region Variables

# Define Variables
# FPA Is used as the alias for Fedora People Archive in the script
$FPARootURL = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads"
$ArchiveVirtIOURL = "$FPARootURL/archive-virtio/"
$ArchiveQemuGAURL = "$FPARootURL/archive-qemu-ga/"

$UninstallRegistryPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$VirtIODisplayNamePattern = "*virtio*installer*"
$VirtIOmsiFileName = "virtio-win-gt-x64.msi"

$ScriptTempDirName = "Qemu-VirtIO-Update-Temp"
$ScriptTempPath = Join-Path -Path $env:TEMP -ChildPath $ScriptTempDirName
if (-not (Test-Path -Path $ScriptTempPath)) {
    New-Item -Path $ScriptTempPath -ItemType Directory | Out-Null
}
$script:LogFilePath = Join-Path -Path $ScriptTempPath -ChildPath "log_$(Get-Date -Format 'yyyy-MM-dd').log"

[xml]$drivers = pnputil /enum-drivers /format xml

#EndRegion

#Region Functions

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
        Add-Content -Path $script:LogFilePath -Value "=== Log initialized on $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss') ==="
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

#EndRegion

#Region Script

$confirm = Read-Host "Should the virtIO-Drivers and the QEMU Guest Agent be updated? (y/N)"
if ($confirm -notmatch "^[Yy]") {
    Write-Host "Script Canceled." -ForegroundColor Yellow
    exit 0
}

# Test if VirtIO Drivers are installed and get the current version
# Needed to then compare with latest version -> Override option to force reinstall will be added at some point. (ToDo)
try {
    $VirtIOCurrentVersion = Get-ItemProperty -Path $UninstallRegistryPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -like $VirtIODisplayNamePattern } |
        Select-Object -ExpandProperty DisplayVersion -First 1

    if ([string]::IsNullOrWhiteSpace($VirtIOCurrentVersion)) {
        Write-Log -Message "VirtIO not installed (no matching registry entry found)." -Level "Warning"
    } else {
        Write-Log -Message "Detected VirtIO version: $VirtIOCurrentVersion" -Level "Info"
    }
}
catch {
    Write-Log -Message "Unable to retrieve VirtIO version: $_" -Level "Warning"
}

# Test if QEMU Guest Agent is installed and get current version
try {
    $QemuGACurrentVersion = $null
    $qemuPaths = @(
        'C:\Program Files\Qemu-ga\qemu-ga.exe',
        'C:\Program Files (x86)\Qemu-ga\qemu-ga.exe'
    )

    foreach ($path in $qemuPaths) {
        if (Test-Path -Path $path) {
            $QemuGACurrentVersion = (Get-Item -Path $path -ErrorAction Stop).VersionInfo.FileVersion
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($QemuGACurrentVersion)) {
        Write-Log -Message "QEMU Guest Agent not installed (qemu-ga.exe not found)." -Level "Warning"
    } else {
        Write-Log -Message "Detected QEMU Guest Agent version: $QemuGACurrentVersion" -Level "Info"
    }
}
catch {
    Write-Log -Message "Unable to retrieve QEMU Guest Agent version: $_" -Level "Warning"
}

# Access the Fedora People Archive to find the latest virtio-win version

$FPAVirtIORootSite = Invoke-WebRequest -Uri $ArchiveVirtIOURL -useBasicParsing
if ($FPAVirtIORootSite.StatusCode -ne 200) {
    Write-Log -Message "Failed to access Fedora People Archive at $ArchiveVirtIOURL. Status Code: $($FPAVirtIORootSite.StatusCode)" -Level "Error"
    exit 1
}
Write-Log -Message "Successfully accessed Fedora People Archive at $ArchiveVirtIOURL" -Level "Info"

$FPAVirtIOdirectoryLinks = $FPAVirtIORootSite.Links |
    Where-Object { $_.href -match 'virtio-win-[\d\.]+-\d+/?$' } |
    ForEach-Object {
        $ver = [regex]::Match($_.href, 'virtio-win-([\d\.]+-\d+)').Groups[1].Value
        [PSCustomObject]@{ Href = $_.href; Version = $ver }
    }

$latest = $FPAVirtIOdirectoryLinks |
    Sort-Object { [version]($_.Version -replace '-', '.') } -Descending |
    Select-Object -First 1

if ($null -eq $latest) {
    Write-Log -Message "No matching virtio-win version folders found in $ArchiveVirtIOURL" -Level "Error"
    exit 1
}

$FPAVirtIOlatestSite = Invoke-WebRequest -Uri $FPAVirtIOlatestURL -UseBasicParsing
$VirtIOmsiDownloadURL = $FPAVirtIOlatestURL + $VirtIOmsiFileName
$VirtIOmsiLocalPath = Join-Path -Path $ScriptTempPath -ChildPath $VirtIOmsiFileName 

$VirtIOmsiLink = $FPAVirtIORootSite | Where-Object { $_.href -eq $VirtIOmsiFileName } | Select-Object -First 1

if ($null -eq $VirtIOmsiLink) {
    Write-Log -Message "Could not find $VirtIOmsiFileName in the latest directory." -Level "Error"
    exit 1
}

# Construct the full download URL
$VirtIOmsiDownloadURL = $FPAVirtIOlatestURL + $VirtIOmsiFileName
Write-Log -Message "Download URL: $VirtIOmsiDownloadURL" -Level "Info"

# Start download
Write-Log -Message "Starting download to: $ScriptTempPath" -Level "Info"

try {
    Invoke-WebRequest -Uri $VirtIOmsiDownloadURL -OutFile $VirtIOmsiLocalPath -UseBasicParsing
    Write-Log -Message "Successfully downloaded $VirtIOmsiFileName" -Level "Info"
} catch {
    Write-Log -Message "Failed to download $VirtIOmsiFileName. Error: $_" -Level "Error"
    exit 1
}

# Install the MSI
Write-Log -Message "Starting installation of $VirtIOmsiFileName" -Level "Info"
try {
    $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$VirtIOmsiLocalPath`" /qn /norestart" -Wait -PassThru
    if ($installProcess.ExitCode -eq 0) {
        Write-Log -Message "Successfully installed $VirtIOmsiFileName" -Level "Info"
    } else {
        Write-Log -Message "Installation of $VirtIOmsiFileName failed with exit code $($installProcess.ExitCode)" -Level "Error"
        exit 1
    }
} catch {
    Write-Log -Message "Failed to install $VirtIOmsiFileName. Error: $_" -Level "Error"
    exit 1
}

$CleanupConfirm = Read-Host "Should the downloaded MSI file be deleted? (y/N)"
if ($CleanupConfirm -match "^[Yy]") {
    try {
        Remove-Item -Path $VirtIOmsiLocalPath -Force
        Write-Log -Message "Deleted downloaded MSI file: $VirtIOmsiLocalPath" -Level "Info"
    } catch {
        Write-Log -Message "Failed to delete downloaded MSI file: $VirtIOmsiLocalPath. Error: $_" -Level "Warning"
    }
} else {
    Write-Log -Message "Downloaded MSI file retained at: $VirtIOmsiLocalPath" -Level "Info"
}

#EndRegion