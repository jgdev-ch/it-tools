<#
          ################################
          ################################
          ################################
          ######  ################  ######
          ######  ################  ######
          ######  ################  ######
          ################################
          ################################
      ########################################
      ########################################
          ################################
          ################################
          ################################
              ##    ##        ##    ##
              ##    ##        ##    ##
#>

# Claw'd stays in his own comment block, kept apart from the help block below.
# Comment-based help has to begin with a help keyword, so folding the art into
# the help block, or butting the two blocks up against each other with no
# separation, silently kills Get-Help for this script. Verify with
# (Get-Help .\Enable-CoworkVirtualization.ps1).Synopsis before changing this.

<#
.SYNOPSIS
    Enables the Windows virtualization prerequisites that Claude Cowork needs.

.DESCRIPTION
    Cowork runs its sandboxed code-execution environment inside a lightweight
    VM built on the Windows Host Compute Service. Anthropic's deployment guide
    requires the "Virtual Machine Platform" optional feature, hardware
    virtualization enabled in firmware, and the HCS services (vmcompute, hns,
    vfpext) present on the machine.

    This script checks all of that, enables what it can, and tells the tech
    exactly what is left to do. It is safe to re-run.

    Phase 1  Check the host: elevation, Windows edition and build,
             architecture, physical vs virtual, Claude Desktop presence.
    Phase 2  Check hardware virtualization in firmware.
    Phase 3  Check and enable the Virtual Machine Platform feature.
    Phase 4  Check the hypervisor launch type in the boot configuration.
    Phase 5  Check the Host Compute Service services and drivers.
    Phase 6  Summarise and report whether a restart is required.

    A transcript of every run is written next to this script so the tech can
    copy it into the ticket and then delete the folder from the user's machine.

    Exit codes:
      0     Ready. Cowork should work on this machine.
      3010  Success, but a RESTART IS REQUIRED. This is the standard
            MSI/Intune "soft reboot" code, so Intune or an RMM can act on it
            if this is ever packaged for delivery.
      1     Not running as administrator.
      2     Enabling the Virtual Machine Platform feature failed.
      3     Host is not supported (Windows edition, architecture, or a guest
            VM without nested virtualization).
      4     Prerequisites are in place but the Host Compute Service services
            are missing and no restart is pending. Reinstall Claude Desktop.

.PARAMETER Unattended
    Skips the confirmation prompt before the boot configuration is changed.
    Intended for future Intune or RMM delivery. Leave it off for hands-on runs
    so the tech is always asked before the boot config is touched.

.NOTES
    Run elevated. Run-EnableCoworkVirtualization.bat self-elevates and calls
    this script for you.

    Deliberately targets Windows PowerShell 5.1, not PowerShell 7. The DISM
    cmdlets used in Phase 3 are 5.1-native; under 7 they run through the
    WinPSCompatSession shim, which is slower and has been flaky on the fleet.
    Do not "fix" the launcher to call pwsh.exe.
#>

[CmdletBinding()]
param(
    [switch]$Unattended
)

# --- Run state ----------------------------------------------------
$script:Phases        = 6
$script:RestartNeeded = $false
$script:Blockers      = 0
$script:Transcript    = ""

# --- Console helpers ----------------------------------------------
function Write-Step {
    param([int]$Step, [int]$Total, [string]$Message)
    Write-Host ""
    Write-Host ("  [" + $Step + "/" + $Total + "] " + $Message) -ForegroundColor Cyan
}

function Write-Detail {
    param([string]$Message, [string]$Color = "Gray")
    Write-Host ("      " + $Message) -ForegroundColor $Color
}

function Stop-Run {
    param([string]$Message = "", [string]$Color = "Yellow", [int]$Code = 0)
    if ($Message) { Write-Detail $Message $Color }
    if ($script:Transcript) { Write-Detail ("Transcript   : " + $script:Transcript) }
    Write-Host ""
    try { Stop-Transcript | Out-Null } catch { }
    exit $Code
}

function Confirm-Continue {
    param([string]$Prompt)
    if ($Unattended) {
        # Read-Host would hang forever under Intune or an RMM, so record the
        # bypass in the transcript instead of silently skipping the question.
        Write-Detail "Running unattended. Proceeding without asking." Yellow
        return
    }
    Write-Host ""
    $response = Read-Host ("      " + $Prompt + " [Y/N]")
    Write-Host ""
    if ($response -notmatch "^[Yy]") { Stop-Run "Aborted. No changes were made." Yellow 0 }
    # PowerShell does not record the Read-Host prompt in the transcript, so
    # without this line the log shows a change being made with no evidence
    # anyone was asked for permission.
    Write-Detail "Confirmed." Green
}

# --- Transcript ---------------------------------------------------
# Everything the run produces stays in the folder this script was extracted
# to, so the tech can copy it off and delete the folder from the user's
# machine afterwards. Falls back to TEMP if that folder is not writable.
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$logName = "CoworkVirtualization-" + $stamp + ".log"
$logPath = Join-Path $PSScriptRoot $logName

try {
    Start-Transcript -Path $logPath -ErrorAction Stop | Out-Null
    $script:Transcript = $logPath
} catch {
    $logPath = Join-Path $env:TEMP $logName
    try {
        Start-Transcript -Path $logPath -ErrorAction Stop | Out-Null
        $script:Transcript = $logPath
        Write-Host ""
        Write-Host ("      NOTE: This folder is not writable. Logging to " + $logPath + " instead.") -ForegroundColor Yellow
    } catch {
        Write-Host ""
        Write-Host "      NOTE: Could not start a transcript. The run will continue unlogged." -ForegroundColor Yellow
    }
}

# --- Run details --------------------------------------------------
# The comment block at the top of this file never executes, so this is the
# only record of the run's provenance inside the transcript.
Write-Host ""
Write-Host "  Claude Cowork Virtualization Setup" -ForegroundColor Cyan

$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue

Write-Detail ("Machine      : " + $env:COMPUTERNAME)
Write-Detail ("Run by       : " + $env:USERNAME)
Write-Detail ("OS           : " + $(if ($os) { $os.Caption.Trim() } else { "unknown" }))
Write-Detail ("Build        : " + $(if ($os) { $os.BuildNumber } else { "unknown" }))
Write-Detail ("Architecture : " + $env:PROCESSOR_ARCHITECTURE)
Write-Detail ("Started      : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

# --- Phase 1: Check the host --------------------------------------
Write-Step 1 $script:Phases "Checking the host..."

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($currentIdentity)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Detail "ERROR: This script needs administrator rights to enable Windows features." Red
    Stop-Run "Right-click Run-EnableCoworkVirtualization.bat and choose Run as administrator." Yellow 1
}
Write-Detail "Running elevated." Green

# Windows edition. The fleet is Windows 11 Pro, where this is a non-event, but
# Cowork's sandbox needs the fuller Hyper-V/HCS stack that Home does not ship.
# Home can enable Virtual Machine Platform and still fail at runtime, so fail
# fast here rather than reporting a machine ready that never will be.
if ($os -and $os.Caption -match 'Home') {
    Write-Detail ("ERROR: " + $os.Caption.Trim() + " does not ship the Host Compute Service stack Cowork needs.") Red
    Stop-Run "Cowork needs Windows Pro, Enterprise, or Education. Rebuild or upgrade the edition." Yellow 3
}
if ($os) {
    Write-Detail ("Edition supported: " + $os.Caption.Trim()) Green
}

# Windows 10 22H2 (build 19045) is Anthropic's documented floor.
if ($os -and [int]$os.BuildNumber -lt 19045) {
    Write-Detail ("ERROR: Build " + $os.BuildNumber + " is below the Windows 10 22H2 floor (19045).") Red
    Stop-Run "Update Windows, then re-run this script." Yellow 3
}

# Cowork ships x64. ARM64 support is not confirmed, so warn rather than block.
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
    Write-Detail "WARNING: This is an ARM64 machine. Cowork on ARM64 is not confirmed supported." Yellow
    Write-Detail "Continuing, but if Cowork still fails after a restart, that is the likely reason." Yellow
}

# Nested virtualization is required inside a guest, and Anthropic does not
# support VDI or VMs without it. Model strings are the cheapest reliable tell.
$isGuest = $false
if ($cs) {
    $hw = ($cs.Manufacturer + " " + $cs.Model)
    if ($hw -match 'VMware|VirtualBox|Virtual Machine|KVM|QEMU|Xen|Hyper-V') { $isGuest = $true }
}
if ($isGuest) {
    Write-Detail ("WARNING: This looks like a virtual machine (" + $cs.Model.Trim() + ").") Yellow
    Write-Detail "Cowork is not supported on VMs or VDI without nested virtualization enabled by the host." Yellow
} else {
    Write-Detail "Physical machine." Green
}

# Informational only. Cowork's own service appears after Claude Desktop runs.
#
# This has to measure the END USER's profile, not the caller's. Under a tech run
# the script is elevated as an admin account, so $env:LOCALAPPDATA resolves to
# the tech's own profile and Claude Desktop looks absent on every invocation.
# Win32_ComputerSystem.UserName gives the interactively signed-in user instead,
# which is the person we actually care about. Verified against an AzureAD\ account,
# whose SID translates correctly through NTAccount.
$claudeRoot = $null
$targetUser = if ($cs) { $cs.UserName } else { $null }

if ($targetUser) {
    try {
        $targetSid  = (New-Object System.Security.Principal.NTAccount($targetUser)).Translate(
                          [System.Security.Principal.SecurityIdentifier]).Value
        $targetHome = (Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
                          Where-Object { $_.SID -eq $targetSid }).LocalPath
        if ($targetHome) {
            $claudeRoot = Join-Path $targetHome 'AppData\Local\AnthropicClaude'
        } else {
            Write-Detail ("NOTE: No local profile found for " + $targetUser + ", so the Claude Desktop check was skipped.") Yellow
        }
    } catch {
        Write-Detail ("NOTE: Could not resolve the profile for " + $targetUser + ", so the Claude Desktop check was skipped.") Yellow
    }
} else {
    Write-Detail "NOTE: Nobody is signed in interactively, so the Claude Desktop check was skipped." Yellow
}

if ($claudeRoot) {
    if (Test-Path $claudeRoot) {
        # Reports the Squirrel folder version. The machine may also carry an MSIX
        # package on an unrelated version scheme, so this one is treated as
        # authoritative rather than compared against it.
        $appDir = Get-ChildItem -Path $claudeRoot -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($appDir) {
            Write-Detail ("Claude Desktop installed for " + $targetUser + ": " + $appDir.Name.Replace('app-', 'v')) Green
        } else {
            Write-Detail ("Claude Desktop installed for " + $targetUser + ".") Green
        }
    } else {
        Write-Detail ("NOTE: Claude Desktop is not installed for " + $targetUser + " yet. Install it after the restart.") Yellow
    }
}

# --- Phase 2: Hardware virtualization -----------------------------
Write-Step 2 $script:Phases "Checking hardware virtualization in firmware..."

# Win32_Processor.VirtualizationFirmwareEnabled reports false once a hypervisor
# is already running, because Windows masks the firmware properties from the
# now-virtualized host OS. Checking HypervisorPresent first avoids telling the
# tech to go reboot into the BIOS on a machine that is already working.
if ($cs -and $cs.HypervisorPresent) {
    Write-Detail "A hypervisor is already running, so firmware virtualization is on." Green
} else {
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $fwOn = $cpu | Where-Object { $_.VirtualizationFirmwareEnabled -eq $true }
        if ($fwOn) {
            Write-Detail "Hardware virtualization (VT-x / AMD-V) is enabled in firmware." Green
        } else {
            Write-Detail "ERROR: Hardware virtualization is disabled in firmware." Red
            Write-Detail "Reboot into BIOS/UEFI and enable Intel VT-x or AMD SVM Mode. This script cannot do that." Yellow
            $script:Blockers++
        }
    } catch {
        Write-Detail ("WARNING: Could not read the firmware virtualization state. " + $_.Exception.Message) Yellow
    }
}

# --- Phase 3: Virtual Machine Platform ----------------------------
Write-Step 3 $script:Phases "Checking the Virtual Machine Platform feature..."

try {
    $vmp = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop
    if ($vmp.State -eq "Enabled") {
        Write-Detail "Virtual Machine Platform is already enabled." Green
    } else {
        Write-Detail "Virtual Machine Platform is disabled. Enabling it now..." Yellow
        $result = Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart -ErrorAction Stop
        Write-Detail "Virtual Machine Platform enabled." Green
        if ($result.RestartNeeded) { Write-Detail "Windows reports a restart is needed." Yellow }
        $script:RestartNeeded = $true
    }
} catch {
    Write-Detail ("ERROR: Could not check or enable the Virtual Machine Platform feature. " + $_.Exception.Message) Red
    Stop-Run "Nothing was changed. Check Windows Update health, then re-run this script." Yellow 2
}

# --- Phase 4: Hypervisor launch type ------------------------------
Write-Step 4 $script:Phases "Checking the hypervisor launch type..."

# Checked on every machine, not just ones running VMware or VirtualBox. A
# machine with hypervisorlaunchtype set to off has Virtual Machine Platform
# enabled and still cannot start the Cowork VM, and that setting is a common
# leftover from gaming and anti-cheat troubleshooting. The identifier itself
# is not localized, so matching on it is safe on any Windows language.
$launchType = $null
try {
    # No {current} identifier on purpose. bcdedit rejects that argument when it
    # is passed from PowerShell regardless of how the braces are quoted, and
    # bare braces parse as a script block. Omitting it enumerates the active
    # boot loader entry, which is the same thing and needs no escaping.
    $bcdOut = & bcdedit.exe /enum 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("bcdedit exited with code " + $LASTEXITCODE) }
    $match = ($bcdOut -join "`n") | Select-String -Pattern 'hypervisorlaunchtype\s+(\S+)'
    if ($match) { $launchType = $match.Matches[0].Groups[1].Value }
} catch {
    Write-Detail ("WARNING: Could not read the boot configuration. " + $_.Exception.Message) Yellow
}

if ($null -eq $launchType) {
    # Absent means the setting has never been overridden, and the default is
    # Auto. Do not "fix" this, or every clean machine takes a needless restart.
    Write-Detail "Hypervisor launch type is at its default (Auto)." Green
} elseif ($launchType -match '^Auto$') {
    Write-Detail "Hypervisor launch type is set to Auto." Green
} else {
    Write-Detail ("Hypervisor launch type is set to '" + $launchType + "'. The Cowork VM cannot start like this.") Yellow
    Write-Detail "This needs to be set back to Auto, which changes the boot configuration and needs a restart." Yellow
    Confirm-Continue "Set hypervisorlaunchtype back to Auto?"

    # Same reason as the /enum above: no identifier, so bcdedit applies this to
    # the current boot entry, which is what we want.
    & bcdedit.exe /set hypervisorlaunchtype auto | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Detail "Hypervisor launch type set to Auto." Green
        $script:RestartNeeded = $true
    } else {
        Write-Detail ("ERROR: bcdedit could not change the setting (exit code " + $LASTEXITCODE + ").") Red
        Write-Detail "Set it by hand in an admin prompt: bcdedit /set hypervisorlaunchtype auto" Yellow
        $script:Blockers++
    }
}

# Informational. Detected by installed service, not by running process, so it
# is still found when the product is installed but not currently open.
$thirdParty = @()
foreach ($name in @('VMAuthdService', 'VMwareHostd', 'vmware-usbarbitrator64', 'VBoxSup', 'VBoxDrv', 'VBoxNetLwf')) {
    if (Get-Service -Name $name -ErrorAction SilentlyContinue) { $thirdParty += $name }
}
if ($thirdParty.Count -gt 0) {
    Write-Detail ("NOTE: A third-party hypervisor is installed (" + ($thirdParty -join ", ") + ").") Yellow
    Write-Detail "Cowork needs the Windows hypervisor running, which can slow down or break older VMware and VirtualBox VMs." Yellow
}

# --- Phase 5: Host Compute Service --------------------------------
Write-Step 5 $script:Phases "Checking the Host Compute Service services..."

# Anthropic's deploy guide names HNS, vmcompute, and vfpext. vfpext is a
# kernel driver rather than a Win32 service, so Get-Service will not see it.
$missing = @()

foreach ($svcName in @('vmcompute', 'hns')) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Detail ("Service '" + $svcName + "' found. Start type " + $svc.StartType + ", status " + $svc.Status + ".") Green
    } else {
        Write-Detail ("Service '" + $svcName + "' not found.") Yellow
        $missing += $svcName
    }
}

$vfp = Get-CimInstance -ClassName Win32_SystemDriver -Filter "Name='vfpext'" -ErrorAction SilentlyContinue
if ($vfp) {
    Write-Detail ("Driver 'vfpext' found. State " + $vfp.State + ".") Green
} else {
    Write-Detail "Driver 'vfpext' not found." Yellow
    $missing += 'vfpext'
}

# Installed by Claude Desktop itself, so its absence is not this script's
# problem to solve and must never gate the result.
if (Get-Service -Name 'CoworkVMService' -ErrorAction SilentlyContinue) {
    Write-Detail "Cowork's own service (CoworkVMService) is registered." Green
} else {
    Write-Detail "NOTE: CoworkVMService is not registered yet. Claude Desktop adds it on first run." Yellow
}

if ($missing.Count -gt 0 -and -not $script:RestartNeeded) {
    # Nothing was changed this run, so a restart will not conjure these up.
    # The old version returned "restart required" here, which sent techs
    # round a reboot loop that could never resolve.
    Write-Detail ("ERROR: Missing and no restart is pending: " + ($missing -join ", ") + ".") Red
    Stop-Run "Virtualization is set up correctly, so reinstall Claude Desktop to restore these components." Yellow 4
}

if ($missing.Count -gt 0) {
    Write-Detail "These appear after the restart below. That is expected on a first run." Yellow
}

# --- Phase 6: Complete --------------------------------------------
Write-Step 6 $script:Phases "Complete"

if ($script:Blockers -gt 0) {
    Write-Detail "RESULT: Something still needs a human. Read the red lines above." Red
    Write-Detail "The most common cause is hardware virtualization being switched off in the BIOS/UEFI." Yellow
    if ($script:RestartNeeded) {
        # Report this too, or the work already done gets lost behind the blocker
        # and the tech reboots later without knowing it was already pending.
        Write-Detail "This run did change settings, so restart the machine as well once that is sorted." Yellow
    }
    Stop-Run "" Yellow 3
}

if ($script:RestartNeeded) {
    Write-Detail "RESULT: Restart this machine, then Cowork will be ready to use." Yellow
    Write-Detail "Cowork will keep reporting that virtualization is unavailable until the restart happens." Yellow
    Stop-Run "" Yellow 3010
}

Write-Detail "RESULT: This machine is ready for Cowork. No restart needed." Green
Write-Detail "If Cowork still reports virtualization is unavailable, restart Claude Desktop first." Gray
Stop-Run "" Green 0
