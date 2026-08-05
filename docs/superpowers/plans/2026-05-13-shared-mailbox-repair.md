# Shared Mailbox Repair Tool — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a PowerShell wizard that repairs disappearing shared mailboxes in Outlook by refreshing stale AutoMapping pointers in Exchange Online for a target user's Full Access permissions.

**Architecture:** Single-file wizard (`Invoke-RepairSharedMailboxes.ps1`) with four numbered phases matching the existing mailbox-cleanup tool's UX pattern. Phase 2 enumerates shared mailboxes by scanning SharedMailbox recipients and checking permissions, displays a status table, then Phase 3 removes and re-grants Full Access for AutoMapping-enabled mailboxes only. Phase 4 verifies the refresh landed and outputs a two-step Outlook recovery instruction.

**Tech Stack:** PowerShell 7+, ExchangeOnlineManagement v3.9.0+ (`Get-EXOMailbox`, `Get-EXOMailboxPermission`, `Remove-MailboxPermission`, `Add-MailboxPermission`)

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1` | Create | Main wizard script |
| `tools/shared-mailbox-repair/Run-RepairSharedMailboxes.bat` | Create | Double-click launcher for techs |
| `tools/shared-mailbox-repair/Install-Prerequisites.ps1` | Create | EXO module install (mirrors mailbox-cleanup) |
| `tools/shared-mailbox-repair/Install-Prerequisites.bat` | Create | Launcher for prerequisites script |
| `tools/shared-mailbox-repair/README.txt` | Create | Tech reference guide |

---

### Task 1: Support files — bat launchers and prerequisites

**Files:**
- Create: `tools/shared-mailbox-repair/Install-Prerequisites.ps1`
- Create: `tools/shared-mailbox-repair/Install-Prerequisites.bat`
- Create: `tools/shared-mailbox-repair/Run-RepairSharedMailboxes.bat`

- [ ] **Step 1: Create the directory and Install-Prerequisites.ps1**

```powershell
#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  ERR $msg" -ForegroundColor Red }

Write-Host ""

Write-Step "Trusting PSGallery..."
try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Write-OK "PSGallery trusted"
} catch {
    Write-Fail "Could not trust PSGallery: $_"
    exit 1
}

Write-Step "Installing PowerShellGet..."
try {
    Install-Module PowerShellGet -Scope CurrentUser -Force -AllowClobber
    $v = (Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-OK "PowerShellGet v$v"
} catch {
    Write-Fail "PowerShellGet failed: $_"
    exit 1
}

Write-Step "Installing ExchangeOnlineManagement..."
try {
    Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
    $v = (Get-Module ExchangeOnlineManagement -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-OK "ExchangeOnlineManagement v$v"
} catch {
    Write-Fail "ExchangeOnlineManagement failed: $_"
    exit 1
}

Write-Host ""
Write-Host "  All prerequisites installed. You are ready to run the Shared Mailbox Repair Tool." -ForegroundColor Green
Write-Host ""
```

- [ ] **Step 2: Create Install-Prerequisites.bat**

```bat
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
```

- [ ] **Step 3: Create Run-RepairSharedMailboxes.bat**

```bat
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
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-RepairSharedMailboxes.ps1" -Mailbox "%MAILBOX%"
echo.
pause
```

- [ ] **Step 4: Verify files exist**

Open `C:\dev\projects\it-tools\tools\shared-mailbox-repair\` in Explorer. Confirm three files are present: `Install-Prerequisites.ps1`, `Install-Prerequisites.bat`, `Run-RepairSharedMailboxes.bat`.

- [ ] **Step 5: Commit**

```bash
git add tools/shared-mailbox-repair/Install-Prerequisites.ps1
git add tools/shared-mailbox-repair/Install-Prerequisites.bat
git add tools/shared-mailbox-repair/Run-RepairSharedMailboxes.bat
git commit -m "feat: add shared-mailbox-repair support files and launchers"
```

---

### Task 2: Script skeleton — params, module check, constants, state, helpers, banner

**Files:**
- Create: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Create the script with skeleton content**

```powershell
param(
    [Parameter(Mandatory, HelpMessage = "UPN of the affected user, e.g. john.doe@corrohealth.com")]
    [string]$Mailbox
)

# --- Module install/update (requires v3.9.0+ for Get-EXOMailboxPermission) ---
$minVersion = [Version]"3.9.0"
$installed = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
    Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $installed -or $installed.Version -lt $minVersion) {
    Write-Host "Installing/updating ExchangeOnlineManagement to v3.9.0+..." -ForegroundColor Yellow
    Install-Module ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser
}
try {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
} catch {
    Write-Host "ERROR: Failed to load ExchangeOnlineManagement module. $_" -ForegroundColor Red
    exit 1
}

# --- State ---
$allMailboxes    = @()
$toRefresh       = @()
$results         = @()
$failureCount    = 0
$reportTime      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- Helpers ---
function Write-Step {
    param([int]$Step, [string]$Message)
    Write-Host "`n[$Step/4] $Message" -ForegroundColor Cyan
}

function Write-Detail {
    param([string]$Message, [string]$Color = 'White')
    Write-Host "      $Message" -ForegroundColor $Color
}

# --- Banner ---
Write-Host ""
Write-Host "  ================================================" -ForegroundColor DarkCyan
Write-Host "   Shared Mailbox Repair Tool" -ForegroundColor White
Write-Host "  ================================================" -ForegroundColor DarkCyan
Write-Host "   Target: $Mailbox" -ForegroundColor Gray
Write-Host ""
```

- [ ] **Step 2: Verify the file parses without errors**

Run: `pwsh.exe -NoProfile -Command "& { . 'C:\dev\projects\it-tools\tools\shared-mailbox-repair\Invoke-RepairSharedMailboxes.ps1' -Mailbox 'test@test.com' }" 2>&1 | Select-Object -First 5`

Expected: Banner output printed, then a missing-phase error or clean stop — no parse errors.

- [ ] **Step 3: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: add shared-mailbox-repair script skeleton"
```

---

### Task 3: Phase 1 — EXO connection

**Files:**
- Modify: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Add Phase 1 block after the banner**

Append to the script after the banner `Write-Host` lines:

```powershell
# --- Phase 1: Connect to Exchange Online ---
Write-Step 1 "Connecting to Exchange Online..."
try {
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Detail "Exchange Online: connected" Green
} catch {
    Write-Host "ERROR: Could not connect to Exchange Online. $_" -ForegroundColor Red
    exit 1
}
```

- [ ] **Step 2: Verify Phase 1 is the last block in the file**

Read `Invoke-RepairSharedMailboxes.ps1` and confirm Phase 1 block is at the bottom, helpers and banner are above it.

- [ ] **Step 3: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: shared-mailbox-repair phase 1 - EXO connection"
```

---

### Task 4: Phase 2 — Enumerate shared mailboxes, display table, exit paths, confirm

**Files:**
- Modify: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Add Phase 2 block after Phase 1**

Append after the Phase 1 block:

```powershell
# --- Phase 2: Shared mailbox status ---
Write-Step 2 "Shared mailbox status: $Mailbox"

# Verify target user exists
try {
    $null = Get-EXOMailbox -Identity $Mailbox -ErrorAction Stop
} catch {
    Write-Host "ERROR: Mailbox '$Mailbox' not found. Check the UPN and try again." -ForegroundColor Red
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 1
}

Write-Detail "Scanning shared mailboxes for $Mailbox ..." Gray

$sharedMailboxes = Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -ErrorAction Stop

$allMailboxes = @()
foreach ($mbx in $sharedMailboxes) {
    $perm = Get-EXOMailboxPermission -Identity $mbx.Identity -User $Mailbox -ErrorAction SilentlyContinue |
        Where-Object { $_.AccessRights -contains 'FullAccess' -and -not $_.Deny }
    if ($perm) {
        $autoMap = if ($null -ne $perm.AutoMapping) { [bool]$perm.AutoMapping } else { $true }
        $allMailboxes += [PSCustomObject]@{
            Address     = $mbx.PrimarySmtpAddress
            DisplayName = $mbx.DisplayName
            AutoMapping = $autoMap
        }
    }
}

# --- Exit: no shared mailboxes found ---
if ($allMailboxes.Count -eq 0) {
    Write-Host ""
    Write-Detail "No shared mailbox access found for $Mailbox." Yellow
    Write-Detail "If mailboxes should be present, verify Full Access grants in Exchange admin." Gray
    Write-Detail "This is a permissions issue, not an AutoMapping issue." Gray
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
    exit 0
}

$toRefresh = $allMailboxes | Where-Object { $_.AutoMapping -eq $true }
$skipped   = $allMailboxes | Where-Object { $_.AutoMapping -eq $false }

# --- Display table ---
Write-Host ""
Write-Detail ("{0,-50} {1}" -f 'Mailbox', 'AutoMapping') Gray
Write-Detail ("{0,-50} {1}" -f '-------', '-----------') Gray

foreach ($mbx in $allMailboxes) {
    if ($mbx.AutoMapping) {
        Write-Detail ("{0,-50} {1}" -f $mbx.Address, 'Enabled') Green
    } else {
        Write-Detail ("{0,-50} {1,-10}  (manually added, will be skipped)" -f $mbx.Address, 'Disabled') Gray
    }
}

Write-Host ""
Write-Detail ("{0} mailbox(es) found — {1} will be refreshed" -f $allMailboxes.Count, $toRefresh.Count) White

# --- Exit: all mailboxes have AutoMapping disabled ---
if ($toRefresh.Count -eq 0) {
    Write-Host ""
    Write-Detail "All shared mailboxes use manual mapping — AutoMapping is not the likely cause." Yellow
    Write-Detail "Consider rebuilding the Outlook profile:" Gray
    Write-Detail "  Control Panel > Mail > Show Profiles > Add (create new profile)" Gray
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
    exit 0
}

# --- Confirm ---
Write-Host ""
$go = Read-Host "      Proceed with refresh? [Y/N]"
Write-Host ""
if ($go -notmatch '^[Yy]') {
    Write-Host "  No changes made.`n" -ForegroundColor Cyan
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 0
}
```

- [ ] **Step 2: Verify Phase 2 structure by reading the file**

Open `Invoke-RepairSharedMailboxes.ps1` and confirm:
- Phase 2 exits cleanly when zero mailboxes found (with EXO disconnect)
- Phase 2 exits cleanly when all are AutoMapping=Disabled
- `$toRefresh` and `$skipped` are populated from `$allMailboxes`
- Confirm prompt is the last line of Phase 2

- [ ] **Step 3: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: shared-mailbox-repair phase 2 - enumerate and display shared mailbox status"
```

---

### Task 5: Phase 3 — Permission refresh loop

**Files:**
- Modify: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Add Phase 3 block after Phase 2**

Append after the Phase 2 confirm block:

```powershell
# --- Phase 3: Permission refresh ---
Write-Step 3 "Refreshing permissions..."
Write-Host ""

$results = @()
$i = 0
foreach ($mbx in $toRefresh) {
    $label = "[{0}/{1}] {2}" -f ($i + 1), $toRefresh.Count, $mbx.Address
    Write-Host ("      {0,-68}" -f $label) -NoNewline

    try {
        Remove-MailboxPermission -Identity $mbx.Address -User $Mailbox `
            -AccessRights FullAccess -Confirm:$false -ErrorAction Stop
        Add-MailboxPermission -Identity $mbx.Address -User $Mailbox `
            -AccessRights FullAccess -AutoMapping $true -ErrorAction Stop | Out-Null

        Write-Host "Done" -ForegroundColor Green
        $results += [PSCustomObject]@{
            Address = $mbx.Address
            Outcome = 'Refreshed'
            Reason  = ''
        }
    } catch {
        $errMsg = $_.Exception.Message
        Write-Host "Failed" -ForegroundColor Red
        Write-Detail "    $errMsg" Red
        $results += [PSCustomObject]@{
            Address = $mbx.Address
            Outcome = 'Failed'
            Reason  = $errMsg
        }
        $failureCount++
    }
    $i++
}

# Add skipped mailboxes to results for reporting
foreach ($mbx in $skipped) {
    $results += [PSCustomObject]@{
        Address = $mbx.Address
        Outcome = 'Skipped'
        Reason  = 'AutoMapping disabled'
    }
}
```

- [ ] **Step 2: Verify Phase 3 structure**

Read `Invoke-RepairSharedMailboxes.ps1` and confirm:
- Loop iterates `$toRefresh` only (not `$skipped`)
- Each iteration removes then re-adds the permission with `AutoMapping $true`
- Failures increment `$failureCount` and continue (no `break`)
- `$skipped` mailboxes are appended to `$results` after the loop with Outcome = 'Skipped'

- [ ] **Step 3: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: shared-mailbox-repair phase 3 - permission refresh loop"
```

---

### Task 6: Phase 4 — Verify refreshes, result table, Outlook instructions

**Files:**
- Modify: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Add Phase 4 block after Phase 3**

Append after the Phase 3 block:

```powershell
# --- Phase 4: Verify and summarise ---
Write-Step 4 "Verifying and summarising..."
Write-Host ""

# Re-query to confirm each refresh landed
foreach ($r in $results | Where-Object { $_.Outcome -eq 'Refreshed' }) {
    $verify = Get-EXOMailboxPermission -Identity $r.Address -User $Mailbox -ErrorAction SilentlyContinue |
        Where-Object { $_.AccessRights -contains 'FullAccess' -and -not $_.Deny }
    if (-not $verify) {
        $r.Outcome = 'Failed'
        $r.Reason  = 'Permission not found after refresh — verify manually in Exchange admin'
        $failureCount++
    }
}

# Result table
Write-Host "      ================================================" -ForegroundColor DarkCyan
Write-Host "       Results" -ForegroundColor White
foreach ($r in $results) {
    $color = switch ($r.Outcome) {
        'Refreshed' { 'Green'  }
        'Skipped'   { 'Gray'   }
        'Failed'    { 'Red'    }
        default     { 'White'  }
    }
    $suffix = if ($r.Outcome -eq 'Skipped') { '  (AutoMapping disabled)' } `
              elseif ($r.Outcome -eq 'Failed') { "  — $($r.Reason)" } `
              else { '' }
    Write-Detail ("  {0,-50} {1}{2}" -f $r.Address, $r.Outcome, $suffix) $color
}
Write-Host "      ================================================" -ForegroundColor DarkCyan
Write-Host ""

# Failure callout
if ($failureCount -gt 0) {
    Write-Detail "$failureCount mailbox(es) failed to refresh — manual remediation required." Red
    Write-Detail "Check Exchange admin permissions and re-run, or grant Full Access manually." Gray
    Write-Host ""
}

# Outlook restart instructions
$alias = ($Mailbox -split '@')[0]
Write-Host "      ================================================" -ForegroundColor DarkCyan
Write-Host "       Next Steps" -ForegroundColor White
Write-Detail "  Step 1 — Ask $alias to close and reopen Outlook." White
Write-Detail "           Shared mailboxes should reappear within a few minutes." Gray
Write-Detail "  Step 2 — If still missing after restart, rebuild the local" White
Write-Detail "           Outlook profile: Control Panel > Mail > Show Profiles." Gray
Write-Host "      ================================================" -ForegroundColor DarkCyan
Write-Host ""
```

- [ ] **Step 2: Verify Phase 4 structure**

Read the file and confirm:
- Verify loop only checks results with `Outcome = 'Refreshed'` — does not re-check Skipped/Failed
- Result table iterates all `$results` (Refreshed + Skipped + Failed)
- Color coding: Green=Refreshed, Gray=Skipped, Red=Failed
- Failure callout only appears when `$failureCount -gt 0`
- Two-step Outlook instruction block always appears

- [ ] **Step 3: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: shared-mailbox-repair phase 4 - verify, summary, outlook instructions"
```

---

### Task 7: Ticket export and session cleanup

**Files:**
- Modify: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Add ticket export block after Phase 4**

Append after the Phase 4 block:

```powershell
# --- Ticket export ---
Write-Host ""
$export = Read-Host "      Export summary report for ticket? [Y/N]"
if ($export -match '^[Yy]') {
    $reportAlias = ($Mailbox -split '@')[0]
    $reportFile  = "$([System.Environment]::GetFolderPath('Desktop'))\SharedMailboxRepair-$reportAlias-$reportTimestamp.txt"

    $refreshedCount = ($results | Where-Object { $_.Outcome -eq 'Refreshed' }).Count
    $skippedCount   = ($results | Where-Object { $_.Outcome -eq 'Skipped'   }).Count
    $orphanedCount  = ($results | Where-Object { $_.Outcome -eq 'Orphaned'  }).Count
    $failedCount    = ($results | Where-Object { $_.Outcome -eq 'Failed'    }).Count

    $sep  = "=" * 60
    $dash = "-" * 60

    $report = @(
        $sep
        " SHARED MAILBOX REPAIR REPORT"
        $sep
        " Date   : $reportTime"
        " Target : $Mailbox"
        ""
        $dash
        " PRE-FLIGHT"
        $dash
        (" Shared mailboxes found : {0}" -f $allMailboxes.Count)
        (" To be refreshed        : {0} (AutoMapping enabled)"  -f $toRefresh.Count)
        (" Skipped                : {0} (AutoMapping disabled)" -f $skipped.Count)
        ""
        $dash
        " RESULTS"
        $dash
    )

    foreach ($r in $results) {
        $suffix = switch ($r.Outcome) {
            'Skipped'  { ' (AutoMapping disabled)' }
            'Failed'   { " — $($r.Reason)" }
            default    { '' }
        }
        $report += (" {0,-50} {1}{2}" -f $r.Address, $r.Outcome, $suffix)
    }

    $report += @(
        ""
        $dash
        " OUTCOME"
        $dash
    )

    if ($failureCount -eq 0) {
        $report += " Repair complete."
    } else {
        $report += " Repair complete with $failureCount failure(s) — manual follow-up required."
    }

    $report += @(
        " Step 1: Ask user to close and reopen Outlook."
        "         Shared mailboxes should reappear within a few minutes."
        " Step 2: If still missing after restart, rebuild the Outlook profile"
        "         via Control Panel > Mail > Show Profiles."
        $sep
    )

    $report | Out-File -FilePath $reportFile -Encoding UTF8
    Write-Host ""
    Write-Host "      Report saved to: $reportFile" -ForegroundColor Green
    Write-Host ""
}

# --- Session cleanup ---
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
```

- [ ] **Step 2: Verify report structure**

Read the file and confirm:
- `$refreshedCount`, `$skippedCount`, `$failedCount` are computed from `$results` (not hardcoded)
- Report file name uses `$reportAlias` and `$reportTimestamp`
- `Disconnect-ExchangeOnline` is the last line of the script
- Outcome section shows failure count when `$failureCount -gt 0`

- [ ] **Step 3: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: shared-mailbox-repair ticket export and session cleanup"
```

---

### Task 8: README.txt and final commit

**Files:**
- Create: `tools/shared-mailbox-repair/README.txt`

- [ ] **Step 1: Create README.txt**

```
============================================================
 SHARED MAILBOX REPAIR TOOL — TECH REFERENCE
============================================================

PURPOSE
-------
Repairs disappearing shared mailboxes in Outlook for a single
affected user. Root cause is a stale AutoMapping pointer in
Exchange Online's Autodiscover layer.

Only repairs mailboxes where AutoMapping is Enabled (the
default). Manually-added shared mailboxes (AutoMapping=Disabled)
are displayed but not touched.

WHEN TO USE
-----------
- User reports one or more shared mailboxes missing from Outlook
- Mailboxes reappear after profile rebuild but disappear again
- Issue recurs for the same user

WHEN NOT TO USE
---------------
- Mailbox never appeared (may be a permissions issue — verify
  Full Access grant in Exchange admin)
- All shared mailboxes show AutoMapping=Disabled (manually added
  — rebuild the Outlook profile instead)

PREREQUISITES
-------------
Run Install-Prerequisites.bat once before first use.
Requires ExchangeOnlineManagement v3.9.0+.

USAGE
-----
Double-click Run-RepairSharedMailboxes.bat
Enter the affected user's UPN when prompted.

Must be run as a Global Admin or Exchange Admin account.

WHAT THE SCRIPT DOES
--------------------
Phase 1 — Connects to Exchange Online (interactive MFA)
Phase 2 — Lists all shared mailboxes the user has Full Access to,
           shows AutoMapping status for each
Phase 3 — Removes and re-grants Full Access on AutoMapping-enabled
           mailboxes, forcing Exchange to rewrite the Autodiscover
           pointer
Phase 4 — Verifies each refresh landed, displays result table,
           outputs Outlook restart instructions for the user

AFTER THE SCRIPT
----------------
Step 1: Ask the user to close and reopen Outlook.
        Shared mailboxes should reappear within a few minutes.
Step 2: If still missing, rebuild the local Outlook profile:
        Control Panel > Mail > Show Profiles > Add

TICKET EXPORT
-------------
At the end of each run you are prompted to save a .txt report
to your Desktop for pasting into the helpdesk ticket.

============================================================
```

- [ ] **Step 2: Verify all five files are present**

Run:
```bash
ls /c/dev/projects/it-tools/tools/shared-mailbox-repair/
```

Expected output contains:
```
Install-Prerequisites.bat
Install-Prerequisites.ps1
Invoke-RepairSharedMailboxes.ps1
README.txt
Run-RepairSharedMailboxes.bat
```

- [ ] **Step 3: Final commit**

```bash
git add tools/shared-mailbox-repair/README.txt
git commit -m "feat: shared-mailbox-repair README and tool complete"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Covered by |
|---|---|
| Scan SharedMailbox recipients, get EXO permissions | Task 4 Phase 2 |
| Display mailbox + AutoMapping status | Task 4 Phase 2 display table |
| Exit: zero mailboxes found | Task 4 Phase 2 exit path |
| Exit: all AutoMapping=Disabled | Task 4 Phase 2 exit path |
| Refresh AutoMapping=Enabled only | Task 5 Phase 3 loop on `$toRefresh` |
| Continue on failure, flag in summary | Task 5 Phase 3 catch block + Task 6 result table |
| Verify refresh landed | Task 6 Phase 4 re-query |
| Two-step Outlook restart instruction | Task 6 Phase 4 Next Steps block |
| Ticket report matching spec format | Task 7 export |
| Session disconnect | Task 7 final line |
| README.txt | Task 8 |
| Orphaned detection | Phase 2 scans active mailboxes only — deleted mailboxes don't appear in `Get-EXOMailbox`, so they are naturally excluded. If `Get-EXOMailboxPermission` returns a result but `Remove-MailboxPermission` fails in Phase 3, it surfaces as a Failed result with the error reason. |

**Placeholder scan:** No TBD, TODO, or "similar to above" patterns. All code blocks are complete.

**Type consistency:** `$results` is `[PSCustomObject]@{ Address; Outcome; Reason }` throughout Tasks 5, 6, and 7. `$toRefresh` and `$skipped` are both arrays of `[PSCustomObject]@{ Address; DisplayName; AutoMapping }` from Task 4, consumed in Tasks 5 and 7. No mismatches.
