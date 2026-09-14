@echo off
REM ============================================================
REM Run-EnableCoworkVirtualization.bat
REM
REM Double-click launcher for Enable-CoworkVirtualization.ps1.
REM Self-elevates, runs the checks, and passes the script's exit
REM code back to whatever called it.
REM
REM Keep this file in the same folder as the .ps1.
REM
REM The banner is printed from the :run label rather than the top
REM of the file on purpose. This launcher re-runs itself elevated,
REM so anything echoed before the elevation check appears twice,
REM once in the window the tech double-clicked and again in the
REM elevated one.
REM
REM Calls powershell.exe (5.1) on purpose, not pwsh.exe. The DISM
REM cmdlets the script uses are 5.1-native. See the .NOTES block
REM in Enable-CoworkVirtualization.ps1 before changing this.
REM ============================================================

setlocal
set "SELF=%~f0"
set "PS1=%~dp0Enable-CoworkVirtualization.ps1"

REM Claw'd is #DA7757. cmd cannot type an ESC byte directly, and editors strip a
REM literal one silently, so capture it from prompt $E instead. Setting variables
REM echoes nothing, so this is safe above the elevation check. If the capture ever
REM fails, CLAWON and CLAWOFF stay empty and the art prints uncoloured rather than
REM spraying escape codes. The art lives in this .bat, which runs before the PS1
REM starts its transcript, so the escape bytes never reach the run log.
for /f %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
if defined ESC (set "CLAWON=%ESC%[38;2;218;119;87m") else (set "CLAWON=")
if defined ESC (set "CLAWOFF=%ESC%[0m") else (set "CLAWOFF=")

if not exist "%PS1%" goto :no_script

net session >nul 2>&1
if %errorlevel% equ 0 goto :run
if /i "%~1"=="elevated" goto :elevation_failed

echo.
echo  Administrator rights are required. Requesting elevation...
REM -Wait -PassThru so the elevated copy's exit code survives. Without it
REM this launcher always returned 0, including when nothing ran at all.
powershell.exe -NoProfile -Command "try { $p = Start-Process -FilePath $env:SELF -ArgumentList 'elevated' -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Host '  Elevation was cancelled or refused.' -ForegroundColor Yellow; exit 1 }"
exit /b %errorlevel%

:run
echo.%CLAWON%
echo                 ################################
echo                 ################################
echo                 ################################
echo                 ######  ################  ######
echo                 ######  ################  ######
echo                 ######  ################  ######
echo                 ################################
echo                 ################################
echo             ########################################
echo             ########################################
echo                 ################################
echo                 ################################
echo                 ################################
echo                     ##    ##        ##    ##
echo                     ##    ##        ##    ##
echo.%CLAWOFF%
echo ==========================================================
echo  Claude Cowork Virtualization Setup
echo  IT Tools Hub
echo ==========================================================
echo.
echo  Machine   : %COMPUTERNAME%
echo  Action    : Enable the virtualization prerequisites for Cowork
echo.
echo  This checks whether this machine can run Claude Cowork and
echo  enables the Virtual Machine Platform feature if it is off.
echo  You will be asked before anything in the boot configuration
echo  is changed. Most machines need one restart afterwards.
echo.
echo  A log of the run is saved in this folder. Copy it into the
echo  ticket, then delete this folder from the user's machine.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "PS_EXIT=%errorlevel%"

echo.
if "%PS_EXIT%"=="0"    goto :done_ready
if "%PS_EXIT%"=="3010" goto :done_restart
if "%PS_EXIT%"=="1"    goto :done_notadmin
if "%PS_EXIT%"=="2"    goto :done_feature
if "%PS_EXIT%"=="3"    goto :done_unsupported
if "%PS_EXIT%"=="4"    goto :done_services
goto :done_other

:done_ready
echo  DONE: This machine is ready for Cowork. No restart needed.
goto :finish

:done_restart
echo  DONE: RESTART REQUIRED before Cowork will work on this machine.
goto :finish

:done_notadmin
echo  FAILED: The script did not have administrator rights.
goto :finish

:done_feature
echo  FAILED: Could not enable the Virtual Machine Platform feature.
echo  Check Windows Update health on this machine, then re-run.
goto :finish

:done_unsupported
echo  FAILED: This machine cannot run Cowork as-is. See the log for
echo  which check failed (Windows edition, build, or firmware).
goto :finish

:done_services
echo  FAILED: Virtualization is set up, but Claude Desktop's
echo  components are missing. Reinstall Claude Desktop.
goto :finish

:done_other
echo  The script exited with code %PS_EXIT%. See the log in this folder.
goto :finish

:elevation_failed
echo.
echo  ERROR: Elevation was granted but administrator rights are still
echo  not present. Right-click this file and choose Run as administrator.
echo.
pause
exit /b 1

:no_script
echo.
echo  ERROR: Enable-CoworkVirtualization.ps1 was not found next to this file.
echo  Expected at: %PS1%
echo.
echo  Re-extract the whole zip and keep both files together.
echo.
pause
exit /b 1

:finish
echo.
pause
exit /b %PS_EXIT%
