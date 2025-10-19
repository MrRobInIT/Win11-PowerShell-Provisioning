wpeinit
@echo off
title Hudson Windows 11 Auto-Deploy
for %%i in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if exist "%%i:\Deploy\Scripts\Apply-Win11.ps1" set USBDRV=%%i:
)
if "%USBDRV%"=="" (
  echo ERROR: Could not locate Deploy Scripts. Press any key for CMD...
  pause >nul
  cmd /k
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%USBDRV%\Deploy\Scripts\Apply-Win11.ps1"
