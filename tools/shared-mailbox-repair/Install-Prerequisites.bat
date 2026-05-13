@echo off
echo.
echo  Shared Mailbox Repair Tool — Prerequisites
echo  -------------------------------------------
echo  Installs the ExchangeOnlineManagement PowerShell module.
echo  Run this once before using the repair tool.
echo.
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Prerequisites.ps1"
echo.
pause
