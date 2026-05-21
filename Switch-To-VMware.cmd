@echo off
set "SCRIPT=%~dp0WSL2-VMware-Switch.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode VMware
pause
