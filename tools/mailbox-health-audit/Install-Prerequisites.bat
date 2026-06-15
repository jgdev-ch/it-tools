@echo off
echo.
echo  Mailbox Health Audit - Prerequisite Installer
echo  -----------------------------------------------
echo  Installs PowerShellGet and ExchangeOnlineManagement
echo  required to run the Mailbox Health Audit.
echo.
echo  Note: You do not need to update PackageManagement.
echo.
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Prerequisites.ps1"
echo.
pause
