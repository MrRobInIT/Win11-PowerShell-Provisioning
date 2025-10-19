[CmdletBinding()]
param(
    [int]$EfiSizeMB = 300,
    [int]$MsrSizeMB = 16,
    [int]$RecoverySizeMB = 1024,
    [string]$ImageName = "Win11-GOLD",
    [int]$WimIndex = 1
)

$ErrorActionPreference = 'Stop'
$log = "X:\Apply-Win11.log"
"[$(Get-Date -Format s)] Apply-Win11 start" | Out-File $log -Encoding utf8
function Log($m) { "[$(Get-Date -Format s)] $m" | Out-File $log -Append -Encoding utf8 }

# Locate USB root with Images\*.swm
$usbRoot = $null
foreach ($dl in 'C'..'Z') {
    if (Test-Path "$dl`:\Deploy\Images") {
        if (Get-ChildItem -Path "$dl`:\Deploy\Images" -Filter *.swm -ErrorAction SilentlyContinue) { $usbRoot = "$dl`:"; break }
    }
}
if (-not $usbRoot) { Log "ERROR: Deploy root not found"; throw "Deploy root not found" }
Log "USB root: $usbRoot"

$imagesDir  = Join-Path $usbRoot "Deploy\Images"
$scriptsDir = Join-Path $usbRoot "Deploy\Scripts"
$postOobeSrc= Join-Path $usbRoot "Deploy\PostOOBE"
$driversSrc = Join-Path $usbRoot "Deploy\Drivers"
$biosSrc    = Join-Path $usbRoot "Deploy\BIOS"
$unattendSrc= Join-Path $usbRoot "Deploy\Unattend\Unattend.xml"

$firstSwm = Get-ChildItem -Path $imagesDir -Filter *.swm | Sort-Object Name | Select-Object -First 1
if (-not $firstSwm) { throw "No .swm in $imagesDir" }
$swmPattern = Join-Path $imagesDir ($firstSwm.BaseName + "*.swm")
Log "Using SWM set: $($firstSwm.FullName)"

# Partition disk 0
Log "Partitioning disk 0 (EFI=$EfiSizeMB, MSR=$MsrSizeMB, Recovery=$RecoverySizeMB)"
$disk = Get-Disk -Number 0
if ($disk.PartitionStyle -ne 'RAW') {
    Log "Cleaning disk 0"
    $disk | Set-Disk -IsReadOnly $false -ErrorAction SilentlyContinue
    Clear-Disk -Number 0 -RemoveData -Confirm:$false
}
Initialize-Disk -Number 0 -PartitionStyle GPT

# EFI
$efi = New-Partition -DiskNumber 0 -GptType "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}" -Size ($EfiSizeMB*1MB) -AssignDriveLetter
Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel "SYSTEM" -Confirm:$false
$S = ($efi | Get-Volume).DriveLetter + ":"
# MSR
$null = New-Partition -DiskNumber 0 -GptType "{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}" -Size ($MsrSizeMB*1MB)

# Windows size = total - EFI - MSR - Recovery
$disk = Get-Disk -Number 0
$totalMB = [math]::Floor(($disk.Size) / 1MB)
$windowsMB = $totalMB - $EfiSizeMB - $MsrSizeMB - [math]::Max($RecoverySizeMB,0)
if ($windowsMB -lt 20480) { throw "Windows partition too small: $windowsMB MB" }

# Windows
$win = New-Partition -DiskNumber 0 -Size ($windowsMB*1MB) -AssignDriveLetter -GptType "{EBD0A0A2-B9E5-4433-87C0-68B6B72699C7}"
Format-Volume -Partition $win -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false
$W = ($win | Get-Volume).DriveLetter + ":"

# Recovery (optional)
$R = $null
if ($RecoverySizeMB -gt 0) {
    $rec = New-Partition -DiskNumber 0 -UseMaximumSize -AssignDriveLetter -GptType "{DE94BBA4-06D1-4D40-A16A-BFD50179D6AC}"
    Format-Volume -Partition $rec -FileSystem NTFS -NewFileSystemLabel "Recovery" -Confirm:$false
    $recNum = ($rec | Get-Partition).PartitionNumber
    $dp = @"
select disk 0
select partition $recNum
gpt attributes=0x8000000000000001
exit
"@
    $dpPath = "X:\_rec_attr.txt"
    $dp | Out-File -Encoding ascii $dpPath
    Start-Process diskpart -ArgumentList "/s `"$dpPath`"" -Wait
    $R = ($rec | Get-Volume).DriveLetter + ":"
}

# Apply image
Log "Applying image to $W ..."
$proc = Start-Process -FilePath dism.exe -ArgumentList "/Apply-Image","/WimFile:$($firstSwm.FullName)","/SWMFile:$swmPattern","/Index:$WimIndex","/ApplyDir:$W\" -PassThru -Wait
if ($proc.ExitCode -ne 0) { throw "DISM Apply failed: $($proc.ExitCode)" }
Log "Image applied."

# Configure WinRE to Recovery partition if present; else enable default
try {
    if ($R) {
        $winreSrc = Join-Path $W "Windows\System32\Recovery\winre.wim"
        $winreDest = Join-Path $R "Recovery\WindowsRE"
        New-Item -ItemType Directory -Force -Path $winreDest | Out-Null
        if (Test-Path $winreSrc) {
            Copy-Item $winreSrc (Join-Path $winreDest "winre.wim") -Force
            Start-Process reagentc.exe -ArgumentList "/disable" -WorkingDirectory $W -Wait
            Start-Process reagentc.exe -ArgumentList "/setreimage","/path",$winreDest -WorkingDirectory $W -Wait
            Start-Process reagentc.exe -ArgumentList "/enable" -WorkingDirectory $W -Wait
            Log "WinRE enabled on Recovery partition."
        } else {
            Log "winre.wim not found; enabling default."
            Start-Process reagentc.exe -ArgumentList "/enable" -WorkingDirectory $W -Wait
        }
    } else {
        Start-Process reagentc.exe -ArgumentList "/enable" -WorkingDirectory $W -Wait
        Log "WinRE enabled (default in-OS)."
    }
} catch { Log "WinRE config error: $($_.Exception.Message)" }

# Create boot files
$bc = Start-Process bcdboot.exe -ArgumentList "$W`Windows","/s",$S,"/f","UEFI" -PassThru -Wait
if ($bc.ExitCode -ne 0) { throw "bcdboot failed: $($bc.ExitCode)" }
Log "Boot files created."

# Stage content
New-Item -ItemType Directory -Force -Path "$W\PostOOBE" | Out-Null
if (Test-Path $postOobeSrc) { robocopy $postOobeSrc "$W\PostOOBE" /E | Out-Null; Log "PostOOBE staged." }
if (Test-Path $driversSrc)  { robocopy $driversSrc  "$W\Drivers"  /E | Out-Null; Log "Drivers staged." }
if (Test-Path $biosSrc)     { robocopy $biosSrc     "$W\BIOS"     /E | Out-Null; Log "BIOS staged." }

New-Item -ItemType Directory -Force -Path "$W\Windows\Setup\Scripts" | Out-Null
Copy-Item (Join-Path $scriptsDir "SetupComplete.cmd") "$W\Windows\Setup\Scripts\" -Force
Copy-Item (Join-Path $scriptsDir "SetupComplete.ps1") "$W\Windows\Setup\Scripts\" -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $scriptsDir "Apply-DellDrivers.ps1") "$W\Windows\Setup\Scripts\" -Force
Copy-Item (Join-Path $scriptsDir "PostDeploy-Validate.ps1") "$W\Windows\Setup\Scripts\" -Force -ErrorAction SilentlyContinue

if (Test-Path $unattendSrc) {
    $panther = "$W\Windows\Panther\Unattend"
    New-Item -ItemType Directory -Force -Path $panther | Out-Null
    Copy-Item $unattendSrc $panther -Force
    Log "Unattend.xml injected."
}

# Persist log
Copy-Item $log "$W\PostOOBE\Apply-Win11.log" -Force
Log "Apply-Win11 complete. Rebooting..."
Start-Process wpeutil.exe -ArgumentList "reboot" -Wait
