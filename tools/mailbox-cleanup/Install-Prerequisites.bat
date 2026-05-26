@echo off
echo.
echo  Mailbox Cleanup Tool - Prerequisite Installer
echo  -----------------------------------------------
echo  Installs PowerShellGet and ExchangeOnlineManagement
echo  required to run the Mailbox Cleanup Tool.
echo.
echo  Note: You do not need to update PackageManagement.
echo.
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Prerequisites.ps1"
echo.
pause
