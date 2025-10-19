## Build WinPE USB (AMD64)
copype amd64 D:\WinPE_amd64

Dism /Mount-Image /ImageFile:D:\WinPE_amd64\media\sources\boot.wim /Index:1 /MountDir:D:\WinPE_amd64\mount
Dism /Image:D:\WinPE_amd64\mount /Add-Package /PackagePath:"<ADK>\WinPE_OCs\WinPE-WMI.cab"
Dism /Image:D:\WinPE_amd64\mount /Add-Package /PackagePath:"<ADK>\WinPE_OCs\WinPE-Scripting.cab"
Dism /Image:D:\WinPE_amd64\mount /Add-Package /PackagePath:"<ADK>\WinPE_OCs\WinPE-PowerShell.cab"
Dism /Image:D:\WinPE_amd64\mount /Add-Driver /Driver:"E:\Tools\GOLD_Image\Drivers\Universal\BootCritical" /Recurse /ForceUnsigned

Dism /Unmount-Image /MountDir:D:\WinPE_amd64\mount /Commit
MakeWinPEMedia /UFD D:\WinPE_amd64 E:

Copy the entire Deploy/ folder to the USB root.
