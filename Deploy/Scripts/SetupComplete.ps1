[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$LogPath = "C:\PostOOBE\SetupComplete.ps1.log"
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
function Log($m) { "[$(Get-Date -Format s)] $m" | Out-File $LogPath -Append -Encoding utf8 }
"[$(Get-Date -Format s)] SetupComplete.ps1 start" | Out-File $LogPath -Encoding utf8

try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force

    # Drivers
    $drv = "C:\Windows\Setup\Scripts\Apply-DellDrivers.ps1"
    if (Test-Path $drv) { Log "Apply-DellDrivers"; & powershell -NoP -File $drv 2>&1 | Tee-Object -FilePath $LogPath -Append | Out-Null } else { Log "No Apply-DellDrivers.ps1" }

    # Model/BIOS
    $model = (Get-CimInstance Win32_ComputerSystem).Model
    $curBios = (Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion
    Log "Model=$model BIOS=$curBios"
    $biosRoot = "C:\BIOS\Dell\$model"
    if (Test-Path $biosRoot) {
        $biosExe = Get-ChildItem -Path $biosRoot -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $targetTxt = Join-Path $biosRoot "BIOS_version.txt"
        $targetVer = if (Test-Path $targetTxt) { (Get-Content $targetTxt -TotalCount 1).Trim() } else { $null }
        $onAC = $true
        try {
            $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            if ($bat) { $onAC = ($bat.BatteryStatus -eq 2) }
        } catch { $onAC = $true }

        if ($biosExe -and $onAC) {
            if ($targetVer -and ($curBios -eq $targetVer)) {
                Log "BIOS at target; skip flash."
            } else {
                Log "Flashing BIOS: $($biosExe.Name) Target=$targetVer"
                $p = Start-Process -FilePath $biosExe.FullName -ArgumentList "/s","/f","/l=$LogPath" -PassThru -Wait
                Log "BIOS exit=$($p.ExitCode)"
            }
        } else {
            Log "No BIOS EXE or not on AC; skipping BIOS."
        }
    } else { Log "BIOS folder not found; skipping." }

    # DCU optional
    $dcuSetup = "C:\PostOOBE\DCU\Setup.exe"
    if (Test-Path $dcuSetup) {
        Log "Installing DCU..."
        $p = Start-Process -FilePath $dcuSetup -ArgumentList "/S" -PassThru -Wait
        Log "DCU installer exit=$($p.ExitCode)"
        $dcu = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
        if (Test-Path $dcu) {
            $repo = "C:\PostOOBE\DCU\Repository"
            if (Test-Path $repo) { Log "Config DCU repo"; & $dcu /configureSettings -repositoryLocation="$repo" -userConsent=disable -silent | Out-Null }
            Log "DCU scan/apply (no reboot)"
            & $dcu /scan | Tee-Object -FilePath $LogPath -Append | Out-Null
            & $dcu /applyUpdates -reboot=disable | Tee-Object -FilePath $LogPath -Append | Out-Null
        } else { Log "dcu-cli.exe not found after install" }
    } else { Log "DCU installer absent; skipping." }

    # Provisioning package (idempotent)
    $ppkg = "C:\PostOOBE\PPKG\CompanyConfig.ppkg"
    $marker = "C:\PostOOBE\.ppkg_done"
    if (Test-Path $ppkg) {
        if (-not (Test-Path $marker)) {
            Log "Applying PPKG..."
            $p = Start-Process -FilePath "$env:SystemRoot\System32\Provisioning\Cmdlets\ProvisioningUtil.exe" -ArgumentList "/PackagePath","$ppkg","/Quiet","/NoRestart" -PassThru -Wait
            Log "PPKG exit=$($p.ExitCode)"
            "done" | Out-File $marker -Encoding ascii
        } else { Log "PPKG already applied" }
    } else { Log "No PPKG" }

    # Ensure WinRE enabled (safe even if done in WinPE)
    try { Start-Process reagentc.exe -ArgumentList "/enable" -Wait; Log "WinRE enabled" } catch { Log "reagentc error: $($_.Exception.Message)" }

    # Post-deploy validation (optional but recommended)
    $val = "C:\Windows\Setup\Scripts\PostDeploy-Validate.ps1"
    if (Test-Path $val) {
        Log "Running validation..."
        & powershell -NoP -File $val 2>&1 | Tee-Object -FilePath $LogPath -Append | Out-Null
        Log "Validation done."
    }

} catch {
    Log "ERROR: $($_.Exception.Message)"
    throw
} finally {
    Log "SetupComplete.ps1 end"
}
