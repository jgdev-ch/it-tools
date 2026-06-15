@echo off
echo.
echo  Mailbox Health Audit
echo  --------------------
echo  Scans all Exchange Online mailboxes and surfaces those at risk of
echo  hitting the Recoverable Items quota before they become tickets.
echo.
echo  Requirements: Run as an Exchange Administrator account.
echo.
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-MailboxHealthAudit.ps1"
echo.
pause
