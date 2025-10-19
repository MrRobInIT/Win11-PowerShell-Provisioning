[CmdletBinding()]
param()
$Log = "C:\PostOOBE\DriverInstall.log"
New-Item -ItemType Directory -Force -Path (Split-Path $Log) | Out-Null
"[$(Get-Date -Format s)] Driver install start" | Out-File $Log -Encoding utf8

try {
    $model = (Get-CimInstance Win32_ComputerSystem).Model.Trim()
} catch { $model = $null }
"Model: $model" | Out-File $Log -Append

$roots = @("C:\Drivers\Dell", "D:\Drivers\Dell", "E:\Drivers\Dell", "F:\Drivers\Dell")
$driverPath = $null
foreach ($r in $roots) { $c = Join-Path $r $model; if (Test-Path $c) { $driverPath = $c; break } }
if (-not $driverPath) { "No model driver folder found." | Out-File $Log -Append; exit 0 }

"Using driver path: $driverPath" | Out-File $Log -Append
$infs = Get-ChildItem -Path $driverPath -Recurse -Filter *.inf -ErrorAction SilentlyContinue
foreach ($inf in $infs) {
    try {
        "Adding driver: $($inf.FullName)" | Out-File $Log -Append
        $out = pnputil /add-driver "$($inf.FullName)" /install
        ($out | Out-String) | Out-File $Log -Append
    } catch {
        "Failed: $($inf.FullName) - $($_.Exception.Message)" | Out-File $Log -Append
    }
}
"[$(Get-Date -Format s)] Driver install end" | Out-File $Log -Append
