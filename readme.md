# Windows 11 Provisioning SOP (Dell | Hyper‑V → DISM → WinPE USB)

Turnkey SOP and scripts to build and deploy a Dell‑optimized Windows 11 image:
- Golden image in Hyper‑V
- DISM capture → split WIM (SWM) for USB
- WinPE USB one‑touch apply (PowerShell)
- Pre‑login drivers/BIOS/DCU/PPKG
- Recovery partition + WinRE
- Post‑deploy validation artifacts

## Contents
- GoldenImage/: Commands for capture/validation
- WinPE/: Steps to build WinPE USB
- Deploy/: All runtime payloads and scripts
  - Images/: Win11Gold*.swm go here (not included)
  - Drivers/: Model folders (must match Win32_ComputerSystem.Model)
  - BIOS/: Model BIOS payloads with BIOS_version.txt
  - PostOOBE/: DCU, PPKG, Apps
  - Unattend/: Optional Unattend.xml
  - Scripts/: WinPE + in‑OS scripts

## Quick Start
1) Build Golden VM in Hyper‑V and Sysprep.
2) Capture with DISM and split to SWM (see GoldenImage/Capture-Commands.txt).
3) Build WinPE USB and copy Deploy/ to USB root (see WinPE/Build-WinPE-USB.md).
4) Boot device, script auto‑runs, and completes pre‑login tasks.

## Logs on deployed device
- C:\PostOOBE\Apply-Win11.log
- C:\PostOOBE\SetupComplete_Bootstrap.log
- C:\PostOOBE\SetupComplete.ps1.log
- C:\PostOOBE\DriverInstall.log
- C:\PostOOBE\PostDeploy_Validation_*.json / *.txt
