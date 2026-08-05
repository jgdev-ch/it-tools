# Mailbox Cleanup Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a safe, fast PowerShell script that clears the Recoverable Items folder for Exchange Online F3/Outlook Web users blocked by a full quota — replacing a slow, unsafe predecessor.

**Architecture:** Single PowerShell script (`Invoke-MailboxCleanup.ps1`). Opens Exchange Online + Security & Compliance sessions, snapshots the mailbox quota, validates the retention policy, then runs a `try/finally` block that: adds a Purview policy exception, creates and runs a targeted HardDelete compliance purge (minutes vs days), verifies the quota dropped, removes the policy exception, and deletes the search object — even on failure.

**Tech Stack:** PowerShell 5.1+, ExchangeOnlineManagement module (`Connect-ExchangeOnline`, `Connect-IPPSSession`, `Get-Mailbox`, `Get-MailboxFolderStatistics`, `Get-RetentionCompliancePolicy`, `Set-RetentionCompliancePolicy`, `New-ComplianceSearch`, `Start-ComplianceSearch`, `Get-ComplianceSearch`, `New-ComplianceSearchAction`, `Get-ComplianceSearchAction`, `Remove-ComplianceSearch`)

---

## File Structure

```
tools/
└── mailbox-cleanup/
    └── Invoke-MailboxCleanup.ps1    # Complete script — all logic in one file, no imports
```

One file, one responsibility. No config files, no additional modules beyond ExchangeOnlineManagement.

---

### Task 1: Scaffold — skeleton, constants, helpers

**Files:**
- Create: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p tools/mailbox-cleanup
```

- [ ] **Step 2: Create `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1` with this content**

```powershell
param(
    [Parameter(Mandatory, HelpMessage = "UPN of the affected user, e.g. john.doe@corrohealth.com")]
    [string]$Mailbox
)

# --- Module auto-install (runs silently on machines that already have it) ---
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Host "ExchangeOnlineManagement module not found. Installing..." -ForegroundColor Yellow
    Install-Module ExchangeOnlineManagement -Force -Scope CurrentUser
}
Import-Module ExchangeOnlineManagement

# --- Constants (update $RETENTION_POLICY_NAME if policy is renamed) ---
$RETENTION_POLICY_NAME    = "3 Year Retention Policy"
$PROPAGATION_WAIT_SECONDS = 120
$POLL_INTERVAL_SECONDS    = 30

# --- State (initialized before try block so finally can reference them) ---
$searchName = $null

# --- Helpers ---
function Write-Step {
    param([int]$Step, [string]$Message)
    Write-Host "`n[$Step/5] $Message" -ForegroundColor Cyan
}

function Write-Detail {
    param([string]$Message, [string]$Color = 'White')
    Write-Host "      $Message" -ForegroundColor $Color
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    return "{0:N0} KB" -f ($Bytes / 1KB)
}

function Get-RecoverableStats {
    param([string]$MailboxAddress)
    Get-MailboxFolderStatistics -Identity $MailboxAddress -FolderScope RecoverableItems |
        Where-Object { $_.FolderType -eq 'RecoverableItemsRoot' }
}

# --- Main ---
Write-Host "`nMailbox Cleanup" -ForegroundColor White
Write-Host "Target: $Mailbox`n" -ForegroundColor Gray
```

- [ ] **Step 3: Verify the file parses cleanly**

```powershell
powershell -NoProfile -Command "
    \$errors = \$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        'tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1', [ref]\$null, [ref]\$errors
    )
    if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_ -ForegroundColor Red } }
    else { Write-Host 'Parse OK' -ForegroundColor Green }
"
```

Expected: `Parse OK`

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: scaffold Invoke-MailboxCleanup.ps1 — constants, state, helpers"
```

---

### Task 2: Phase 1 — connections

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

- [ ] **Step 1: Append Phase 1 connection block at the end of the file (after the `Write-Host "Target..."` line)**

```powershell
# --- Phase 1: Connect ---
Write-Step 1 "Connecting to Exchange Online and Security & Compliance..."
try {
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Detail "Exchange Online: connected" Green
} catch {
    Write-Host "ERROR: Could not connect to Exchange Online. $_" -ForegroundColor Red
    exit 1
}
try {
    Connect-IPPSSession -ErrorAction Stop
    Write-Detail "Security & Compliance: connected" Green
} catch {
    Write-Host "ERROR: Could not connect to Security & Compliance (IPPSSession). $_" -ForegroundColor Red
    exit 1
}
```

- [ ] **Step 2: Verify parse**

```powershell
powershell -NoProfile -Command "
    \$errors = \$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        'tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1', [ref]\$null, [ref]\$errors
    )
    if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_ -ForegroundColor Red } }
    else { Write-Host 'Parse OK' -ForegroundColor Green }
"
```

Expected: `Parse OK`

- [ ] **Step 3: Manual smoke test — run and confirm both sessions open**

```powershell
.\tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1 -Mailbox yourtest@corrohealth.com
```

Two browser auth windows will open (one for Exchange, one for Security & Compliance). Expected output:

```
Mailbox Cleanup
Target: yourtest@corrohealth.com

[1/5] Connecting to Exchange Online and Security & Compliance...
      Exchange Online: connected
      Security & Compliance: connected
```

Script will then exit (Phase 2 not yet implemented — that's expected).

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: Phase 1 — Connect-ExchangeOnline and Connect-IPPSSession"
```

---

### Task 3: Phase 2 — pre-flight mailbox snapshot

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

- [ ] **Step 1: Append Phase 2 block at the end of the file (after Phase 1)**

```powershell
# --- Phase 2: Pre-flight ---
Write-Step 2 "Pre-flight: $Mailbox"
$mbx = $null
try {
    $mbx = Get-Mailbox -Identity $Mailbox -ErrorAction Stop
} catch {
    Write-Host "ERROR: Mailbox '$Mailbox' not found. Check the UPN and try again." -ForegroundColor Red
    exit 1
}

$statsBefore = Get-RecoverableStats -MailboxAddress $Mailbox
$usedBytes   = $statsBefore.FolderAndSubfolderSize.ToBytes()
$limitBytes  = $mbx.RecoverableItemsQuota.ToBytes()
$pct         = if ($limitBytes -gt 0) { [int](($usedBytes / $limitBytes) * 100) } else { 0 }

Write-Detail ("Recoverable Items: {0} / {1} ({2}% full)" -f `
    (Format-Size $usedBytes), (Format-Size $limitBytes), $pct) `
    $(if ($pct -ge 90) { 'Red' } elseif ($pct -ge 70) { 'Yellow' } else { 'Green' })
```

- [ ] **Step 2: Verify parse**

```powershell
powershell -NoProfile -Command "
    \$errors = \$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        'tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1', [ref]\$null, [ref]\$errors
    )
    if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_ -ForegroundColor Red } }
    else { Write-Host 'Parse OK' -ForegroundColor Green }
"
```

Expected: `Parse OK`

- [ ] **Step 3: Manual smoke test**

Run the script against a known mailbox. Expected Phase 2 output:

```
[2/5] Pre-flight: john.doe@corrohealth.com
      Recoverable Items: 28.4 GB / 30 GB (94% full)
```

Cross-check the reported size against Exchange Admin Center > Mailbox > Mailbox usage for that user. Numbers should match within a few MB (stats can lag slightly).

If you test with a mailbox that has no Recoverable Items, you'll see `0.0 GB / 30 GB (0% full)` — that's correct.

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: Phase 2 — pre-flight Recoverable Items snapshot"
```

---

### Task 4: Phase 3 — Purview policy exclusion inside try/finally

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

This task introduces the `try/finally` wrapper. The finally block starts minimal (just removes the exception); it gets expanded in Task 7.

- [ ] **Step 1: Append Phase 3 block at the end of the file (after Phase 2)**

```powershell
# --- Phase 3: Purview policy exclusion ---
Write-Step 3 "Adding Purview policy exclusion..."
$policy = $null
try {
    $policy = Get-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME -ErrorAction Stop
} catch {
    Write-Host "ERROR: Retention policy '$RETENTION_POLICY_NAME' not found. Update `$RETENTION_POLICY_NAME in the script constants." -ForegroundColor Red
    exit 1
}

try {
    Set-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME `
        -AddExchangeLocationException $Mailbox -ErrorAction Stop
    Write-Detail "Policy exception added for $Mailbox" Green

    $elapsed = 0
    while ($elapsed -lt $PROPAGATION_WAIT_SECONDS) {
        $remaining = $PROPAGATION_WAIT_SECONDS - $elapsed
        Write-Host "`r      Waiting for propagation: ${remaining}s..." -NoNewline -ForegroundColor Yellow
        $sleep = [Math]::Min($POLL_INTERVAL_SECONDS, $remaining)
        Start-Sleep -Seconds $sleep
        $elapsed += $sleep
    }
    Write-Host "`r      Propagation wait complete.                    " -ForegroundColor Green

} finally {
    # Minimal finally — exception removal only. Expanded in Task 7.
    if ($policy) {
        try {
            Set-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME `
                -RemoveExchangeLocationException $Mailbox -ErrorAction Stop
            Write-Detail "Purview policy exception removed." Green
        } catch {
            Write-Detail "WARNING: Could not remove Purview exception. Remove '$Mailbox' from '$RETENTION_POLICY_NAME' exceptions in Purview manually." Yellow
        }
    }
}
```

- [ ] **Step 2: Verify parse**

```powershell
powershell -NoProfile -Command "
    \$errors = \$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        'tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1', [ref]\$null, [ref]\$errors
    )
    if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_ -ForegroundColor Red } }
    else { Write-Host 'Parse OK' -ForegroundColor Green }
"
```

Expected: `Parse OK`

- [ ] **Step 3: Manual smoke test**

Run the script. Expected Phase 3 output (propagation countdown ticks every 30s):

```
[3/5] Adding Purview policy exclusion...
      Policy exception added for john.doe@corrohealth.com
      Waiting for propagation: 120s...
      Waiting for propagation: 90s...
      Waiting for propagation: 60s...
      Waiting for propagation: 30s...
      Propagation wait complete.
      Purview policy exception removed.
```

During the countdown, open Microsoft Purview > Data lifecycle management > Retention policies > [your policy] > Excluded. Verify the mailbox appears as an exception. After the script completes, verify it's been removed from Excluded.

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: Phase 3 — Purview policy exclusion with try/finally and propagation countdown"
```

---

### Task 5: Phase 4a — compliance search (inside try block)

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

The compliance search code goes inside the `try` block — between the propagation countdown and the `} finally {` line.

- [ ] **Step 1: Locate the `} finally {` line in Phase 3 and insert the search block immediately before it**

Find this exact line in the file:

```powershell
} finally {
    # Minimal finally — exception removal only. Expanded in Task 7.
```

Insert the following block ABOVE that line (inside the try block, after the propagation countdown):

```powershell
    # --- Phase 4: Compliance search ---
    $alias      = ($Mailbox -split '@')[0]
    $timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $searchName = "RecovItems-$alias-$timestamp"

    Write-Step 4 "Compliance search: $searchName"

    New-ComplianceSearch -Name $searchName `
        -ExchangeLocation $Mailbox `
        -ContentMatchQuery 'folderpath:"recoverable items"' `
        -ErrorAction Stop | Out-Null

    Start-ComplianceSearch -Identity $searchName -ErrorAction Stop

    $elapsed = 0
    do {
        Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
        $elapsed += $POLL_INTERVAL_SECONDS
        $search = Get-ComplianceSearch -Identity $searchName
        Write-Detail "Searching... (${elapsed}s) — $($search.Status)"
    } while ($search.Status -notin @('Completed', 'Failed'))

    if ($search.Status -eq 'Failed') {
        throw "Compliance search '$searchName' failed. Check the Security & Compliance portal for details."
    }

    Write-Detail ("Search complete — {0:N0} items found ({1})" -f `
        $search.Items, (Format-Size ($search.Size))) Green

```

- [ ] **Step 2: Verify parse**

```powershell
powershell -NoProfile -Command "
    \$errors = \$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        'tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1', [ref]\$null, [ref]\$errors
    )
    if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_ -ForegroundColor Red } }
    else { Write-Host 'Parse OK' -ForegroundColor Green }
"
```

Expected: `Parse OK`

- [ ] **Step 3: Manual smoke test**

Run the script against a test mailbox. Expected Phase 4 search output:

```
[4/5] Compliance search: RecovItems-john.doe-20260507-143022
      Searching... (30s) — InProgress
      Searching... (60s) — InProgress
      Search complete — 14,832 items found (26.1 GB)
      Purview policy exception removed.
```

In the Security & Compliance portal (Purview > Content Search), verify a search named `RecovItems-<alias>-<timestamp>` appears and shows Completed status. Item count should match the output.

The search object is NOT deleted yet (that's in Task 7). Delete it manually after the test:

```powershell
Connect-IPPSSession
Remove-ComplianceSearch -Identity "RecovItems-<alias>-<timestamp>" -Confirm:$false
```

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: Phase 4a — compliance search with status polling"
```

---

### Task 6: Phase 4b — HardDelete purge (inside try block)

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

The purge block goes immediately after the search polling block, still inside the `try`.

- [ ] **Step 1: Find the `Write-Detail "Search complete..."` line and insert the purge block immediately after it**

Find this exact block (the last lines of the search section):

```powershell
    Write-Detail ("Search complete — {0:N0} items found ({1})" -f `
        $search.Items, (Format-Size ($search.Size))) Green

```

Insert the following immediately after:

```powershell
    # --- Phase 4b: Purge ---
    Write-Detail "Running purge (HardDelete)..." Yellow

    New-ComplianceSearchAction -SearchName $searchName `
        -Purge -PurgeType HardDelete -Confirm:$false -ErrorAction Stop | Out-Null

    $actionName = "$searchName`_Purge"
    $elapsed    = 0
    do {
        Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
        $elapsed += $POLL_INTERVAL_SECONDS
        $action = Get-ComplianceSearchAction -Identity $actionName
        Write-Detail "Purging... (${elapsed}s) — $($action.Status)"
    } while ($action.Status -notin @('Completed', 'Failed'))

    if ($action.Status -eq 'Failed') {
        throw "Compliance purge action '$actionName' failed. Check the Security & Compliance portal for details."
    }

    Write-Detail "Purge complete." Green

```

- [ ] **Step 2: Verify parse**

```powershell
powershell -NoProfile -Command "
    \$errors = \$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        'tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1', [ref]\$null, [ref]\$errors
    )
    if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_ -ForegroundColor Red } }
    else { Write-Host 'Parse OK' -ForegroundColor Green }
"
```

Expected: `Parse OK`

- [ ] **Step 3: Manual smoke test**

Run the script against a test mailbox with Recoverable Items. Expected Phase 4b output:

```
      Running purge (HardDelete)...
      Purging... (30s) — InProgress
      Purge complete.
      Purview policy exception removed.
```

In Purview > Content Search > select the search > Actions tab: verify a completed Purge action appears showing items purged.

The search object is still not auto-deleted (Task 7). Delete manually after the test:

```powershell
Remove-ComplianceSearch -Identity "RecovItems-<alias>-<timestamp>" -Confirm:$false
```

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: Phase 4b — HardDelete purge with status polling"
```

---

### Task 7: Phase 5 — verification, search cleanup, final summary

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

This task expands the `finally` block (currently only removes the Purview exception) to add the post-cleanup quota check and search object deletion, and adds the "Done." summary after the try/finally.

- [ ] **Step 1: Replace the entire `finally` block with the expanded version**

Find and replace this existing finally block:

```powershell
} finally {
    # Minimal finally — exception removal only. Expanded in Task 7.
    if ($policy) {
        try {
            Set-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME `
                -RemoveExchangeLocationException $Mailbox -ErrorAction Stop
            Write-Detail "Purview policy exception removed." Green
        } catch {
            Write-Detail "WARNING: Could not remove Purview exception. Remove '$Mailbox' from '$RETENTION_POLICY_NAME' exceptions in Purview manually." Yellow
        }
    }
}
```

Replace with:

```powershell
} finally {
    # --- Phase 5: Verify and restore (always runs) ---
    Write-Step 5 "Verifying and restoring..."

    if ($mbx) {
        $statsAfter = Get-RecoverableStats -MailboxAddress $Mailbox
        $afterBytes = $statsAfter.FolderAndSubfolderSize.ToBytes()
        $afterPct   = if ($limitBytes -gt 0) { [int](($afterBytes / $limitBytes) * 100) } else { 0 }
        Write-Detail ("Recoverable Items: {0} / {1} ({2}% full)" -f `
            (Format-Size $afterBytes), (Format-Size $limitBytes), $afterPct) `
            $(if ($afterPct -ge 70) { 'Yellow' } else { 'Green' })
    }

    if ($policy) {
        try {
            Set-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME `
                -RemoveExchangeLocationException $Mailbox -ErrorAction Stop
            Write-Detail "Purview policy exception removed." Green
        } catch {
            Write-Detail "WARNING: Could not remove Purview exception. Remove '$Mailbox' from '$RETENTION_POLICY_NAME' exceptions in Purview manually." Yellow
        }
    }

    if ($searchName) {
        try {
            Remove-ComplianceSearch -Identity $searchName -Confirm:$false -ErrorAction Stop
            Write-Detail "Compliance search deleted." Green
        } catch {
            Write-Detail "WARNING: Could not delete compliance search '$searchName'. Delete it manually from the Security & Compliance portal." Yellow
        }
    }
}

Write-Host "`nDone. $Mailbox is clear to send and receive.`n" -ForegroundColor Green
```

- [ ] **Step 2: Verify parse**

```powershell
powershell -NoProfile -Command "
    \$errors = \$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        'tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1', [ref]\$null, [ref]\$errors
    )
    if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Host \$_ -ForegroundColor Red } }
    else { Write-Host 'Parse OK' -ForegroundColor Green }
"
```

Expected: `Parse OK`

- [ ] **Step 3: End-to-end test — full run on a test mailbox**

```powershell
.\tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1 -Mailbox yourtest@corrohealth.com
```

Expected full output:

```
Mailbox Cleanup
Target: yourtest@corrohealth.com

[1/5] Connecting to Exchange Online and Security & Compliance...
      Exchange Online: connected
      Security & Compliance: connected

[2/5] Pre-flight: yourtest@corrohealth.com
      Recoverable Items: 28.4 GB / 30 GB (94% full)

[3/5] Adding Purview policy exclusion...
      Policy exception added for yourtest@corrohealth.com
      Waiting for propagation: 120s...
      Waiting for propagation: 90s...
      Waiting for propagation: 60s...
      Waiting for propagation: 30s...
      Propagation wait complete.

[4/5] Compliance search: RecovItems-yourtest-20260507-143022
      Searching... (30s) — InProgress
      Searching... (60s) — InProgress
      Search complete — 14,832 items found (26.1 GB)
      Running purge (HardDelete)...
      Purging... (30s) — InProgress
      Purge complete.

[5/5] Verifying and restoring...
      Recoverable Items: 0.2 GB / 30 GB (1% full)
      Purview policy exception removed.
      Compliance search deleted.

Done. yourtest@corrohealth.com is clear to send and receive.
```

Verify in Purview that the mailbox no longer appears in the retention policy exceptions. Verify in Content Search that the search object is gone.

- [ ] **Step 4: Test error recovery — verify finally always runs**

Add a temporary `throw "test"` line anywhere inside the `try` block after `Set-RetentionCompliancePolicy -AddExchangeLocationException` (so the exception HAS been added). Run the script. Confirm:
- Phase 5 `[5/5] Verifying and restoring...` prints
- "Purview policy exception removed." prints
- The mailbox does NOT remain in the policy exceptions in Purview

Remove the `throw "test"` line after confirming.

- [ ] **Step 5: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: Phase 5 — verification, search cleanup, try/finally complete"
```

---

### Task 8: Batch file launcher — tech-friendly distribution package

**Files:**
- Create: `tools/mailbox-cleanup/Run-MailboxCleanup.bat`

- [ ] **Step 1: Create `tools/mailbox-cleanup/Run-MailboxCleanup.bat`**

```batch
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-MailboxCleanup.ps1" -Mailbox "%MAILBOX%"
echo.
pause
```

`%~dp0` resolves to the directory of the batch file itself — the two files can be dropped anywhere together and it works without any path changes.

- [ ] **Step 2: Verify the batch file launches the script correctly**

From a terminal in `tools/mailbox-cleanup/`:

```cmd
Run-MailboxCleanup.bat
```

Expected: header block prints, UPN prompt appears, entering a UPN launches `Invoke-MailboxCleanup.ps1` with that value. Confirm PowerShell auth windows open as normal.

- [ ] **Step 3: Test from a different directory to confirm path-independence**

Copy `Run-MailboxCleanup.bat` and `Invoke-MailboxCleanup.ps1` to a temp folder (e.g. `C:\Temp\MailboxCleanup\`). Double-click the batch file. Confirm it launches correctly without any path errors.

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Run-MailboxCleanup.bat
git commit -m "feat: add Run-MailboxCleanup.bat launcher for tech distribution"
```

---

## Self-Review

**Spec coverage:**
- ✅ Module auto-install (replaces `#Requires`) — Task 1
- ✅ `[Parameter(Mandatory, HelpMessage)]` — Task 1
- ✅ `$RETENTION_POLICY_NAME`, `$PROPAGATION_WAIT_SECONDS`, `$POLL_INTERVAL_SECONDS` constants — Task 1
- ✅ `Connect-ExchangeOnline` + `Connect-IPPSSession` — Task 2
- ✅ Mailbox validation + `Get-MailboxFolderStatistics` quota snapshot — Task 3
- ✅ `Get-RetentionCompliancePolicy` validation with clear error — Task 4
- ✅ `Set-RetentionCompliancePolicy -AddExchangeLocationException` + countdown — Task 4
- ✅ `New-ComplianceSearch` scoped to mailbox + `folderpath:"recoverable items"` — Task 5
- ✅ `Start-ComplianceSearch` + polling until Completed/Failed — Task 5
- ✅ Items found + size displayed — Task 5
- ✅ `New-ComplianceSearchAction -Purge -PurgeType HardDelete` — Task 6
- ✅ Purge action polling until Completed/Failed — Task 6
- ✅ Post-cleanup quota re-check — Task 7
- ✅ `Set-RetentionCompliancePolicy -RemoveExchangeLocationException` — Task 7
- ✅ `Remove-ComplianceSearch` — Task 7
- ✅ `try/finally` wrapping phases 3b–4 — Tasks 4–7
- ✅ `$searchName = $null` initialized before try so finally can reference it — Task 1
- ✅ Batch launcher with `%~dp0` path-independence — Task 8
- ✅ Plain-language errors (not raw PS exception dumps) — Tasks 2, 3, 4
- ✅ Output format matches spec — all tasks
- ✅ "Done." summary — Task 7

**Placeholder scan:** None found.

**Type consistency:**
- `Get-RecoverableStats` defined Task 1, called Tasks 3 and 7 ✅
- `Format-Size` defined Task 1, called Tasks 3, 5, 7 ✅
- `Write-Step` / `Write-Detail` defined Task 1, used throughout ✅
- `$searchName` initialized Task 1, assigned Task 5, checked Task 7 ✅
- `$mbx` set Task 3, checked Task 7 (`if ($mbx)`) ✅
- `$policy` set Task 4, checked Task 7 (`if ($policy)`) ✅
- `$limitBytes` set Task 3, used Task 7 (only accessed inside `if ($mbx)` guard which guarantees Phase 2 succeeded) ✅
- `$actionName` built as `"$searchName\`_Purge"` Task 6, used in same block ✅
