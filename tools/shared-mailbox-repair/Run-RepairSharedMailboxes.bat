@echo off
echo.
echo  Shared Mailbox Repair Tool
echo  --------------------------
echo  Repairs disappearing shared mailboxes in Outlook by refreshing
echo  the AutoMapping pointer in Exchange Online.
echo.
echo  Requirements: Run as a Global Admin or Exchange Admin account.
echo.
set /p MAILBOX="  Enter affected user UPN (e.g. john.doe@corrohealth.com): "
echo.
if "%MAILBOX%"=="" (
    echo   ERROR: No UPN entered. Please re-run and provide a valid UPN.
    echo.
    pause
    exit /b 1
)
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-RepairSharedMailboxes.ps1" -Mailbox "%MAILBOX%"
echo.
pause
