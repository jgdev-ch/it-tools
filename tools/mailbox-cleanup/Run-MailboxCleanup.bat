@echo off
echo.
echo  Mailbox Cleanup Tool
echo  --------------------
echo  Clears the Recoverable Items folder for a user blocked from
echo  sending and receiving mail due to a full mailbox quota.
echo.
echo  Requirements: Run as a Global Admin or Compliance Admin account.
echo.
set /p MAILBOX="  Enter mailbox UPN (e.g. john.doe@corrohealth.com): "
echo.
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-MailboxCleanup.ps1" -Mailbox "%MAILBOX%"
echo.
pause
