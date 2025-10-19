[CmdletBinding()]
param(
    [string]$OutDir = "C:\PostOOBE",
    [string]$OutBaseName = "PostDeploy_Validation"
)
$ErrorActionPreference = 'Stop'
$dt = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$jsonPath = Join-Path $OutDir ($OutBaseName + "_" + $dt + ".json")
$txtPath  = Join-Path $OutDir ($OutBaseName + "_" + $dt + ".txt")
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function TryGet($s) { try { & $s } catch { $null } }

$cs   = TryGet { Get-CimInstance Win32_ComputerSystem }
$bios = TryGet { Get-CimInstance Win32_BIOS }
$os   = TryGet { Get-CimInstance Win32_OperatingSystem }
$parts= TryGet { Get-Partition }
$vols = TryGet { Get-Volume }
$reInfo = TryGet { & reagentc.exe /info | Out-String }
$bl    = TryGet { manage-bde -status C: | Out-String }
$dcuCli= Test-Path "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"

$badPnP = TryGet {
    Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne "OK" } |
    Select-Object Class, FriendlyName, InstanceId, Status
}

$model = $cs?.Model
$biosFolder = "C:\BIOS\Dell\$model"
$biosExe = if (Test-Path $biosFolder) { Get-ChildItem $biosFolder -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
$biosTargetTxt = if (Test-Path $biosFolder) { Join-Path $biosFolder "BIOS_version.txt" } else { $null }
$biosTarget = if ($biosTargetTxt -and (Test-Path $biosTargetTxt)) { (Get-Content $biosTargetTxt -TotalCount 1).Trim() } else { $null }

$partSummary = @()
if ($parts -and $vols) {
    foreach ($p in $parts | Sort-Object DiskNumber, PartitionNumber) {
        $vol = $vols | Where-Object { $_.DriveLetter -and ($_.DriveLetter + ":") -in $p.AccessPaths }
        $partSummary += [pscustomobject]@{
            Disk       = $p.DiskNumber
            Part       = $p.PartitionNumber
            Type       = $p.GptType
            DriveLetter= if ($vol) { "$($vol.DriveLetter):" } else { "" }
            FileSystem = $vol?.FileSystem
            SizeMB     = [math]::Round(($p.Size/1MB),0)
        }
    }
}

$logs = @{}
$logFiles = @("C:\PostOOBE\Apply-Win11.log","C:\PostOOBE\SetupComplete_Bootstrap.log","C:\PostOOBE\SetupComplete.ps1.log","C:\PostOOBE\DriverInstall.log")
foreach ($lf in $logFiles) { if (Test-Path $lf) { $logs[(Split-Path $lf -Leaf)] = (Get-Content $lf -Tail 50) -join "`n" } }

$result = [pscustomobject]@{
    Timestamp         = (Get-Date).ToString("s")
    ComputerName      = $env:COMPUTERNAME
    Model             = $cs?.Model
    Manufacturer      = $cs?.Manufacturer
    BIOSVersion       = $bios?.SMBIOSBIOSVersion
    BIOSReleaseDate   = $bios?.ReleaseDate
    TargetBIOS        = $biosTarget
    OSBuild           = $os?.Version
    OSEdition         = $os?.Caption
    DCUInstalled      = $dcuCli
    WinREInfoRaw      = $reInfo
    BitLockerC        = $bl
    DriversWithIssues = $badPnP
    Partitions        = $partSummary
    LogsTail          = $logs
}
$result | ConvertTo-Json -Depth 6 | Out-File -FilePath $jsonPath -Encoding utf8

$hr = @()
$hr += "Post-Deploy Validation Summary"
$hr += "Timestamp: $($result.Timestamp)"
$hr += "Computer: $($result.ComputerName)"
$hr += "Model: $($result.Model) ($($result.Manufacturer))"
$hr += "BIOS: $($result.BIOSVersion)  Target: $($result.TargetBIOS)"
$hr += "OS: $($result.OSEdition) (Build $($result.OSBuild))"
$hr += "DCU Installed: $($result.DCUInstalled)"
$hr += ""
$hr += "WinRE (reagentc /info):"
$hr += $result.WinREInfoRaw
$hr += ""
$hr += "BitLocker (C:):"
$hr += $result.BitLockerC
$hr += ""
$hr += "Drivers with issues:"
if ($result.DriversWithIssues -and $result.DriversWithIssues.Count -gt 0) {
    $result.DriversWithIssues | ForEach-Object { $hr += " - [$($_.Class)] $($_.FriendlyName)  Status=$($_.Status)" }
} else { $hr += " - None" }
$hr += ""
$hr += "Partition Map (Disk,Part,Type,DL,FS,SizeMB):"
foreach ($p in $result.Partitions) { $hr += " - $($p.Disk),$($p.Part),$($p.Type),$($p.DriveLetter),$($p.FileSystem),$($p.SizeMB)" }
$hr += ""
$hr += "Log tails (last 50 lines):"
foreach ($k in $result.LogsTail.Keys) { $hr += "----- $k -----"; $hr += $result.LogsTail[$k] }
$hr -join "`r`n" | Out-File -FilePath $txtPath -Encoding utf8
Write-Host "Validation artifacts:"
Write-Host $jsonPath
Write-Host $txtPath
