@echo off
set LOG=C:\PostOOBE\SetupComplete_Bootstrap.log
if not exist C:\PostOOBE md C:\PostOOBE
echo [%date% %time%] Bootstrap start > "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\SetupComplete.ps1" >> "%LOG%" 2>&1
echo [%date% %time%] Bootstrap end >> "%LOG%"
exit /b 0
