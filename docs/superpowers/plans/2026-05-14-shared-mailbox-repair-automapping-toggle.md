# Shared Mailbox Repair — AutoMapping Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Phase 3 action-selection wizard to `Invoke-RepairSharedMailboxes.ps1` so techs can repair (refresh pointer) or disable AutoMapping per mailbox in a single run.

**Architecture:** Single-file PowerShell script modification. The 4-phase flow shifts to 5 phases — the new Phase 3 wizard tags each automapped mailbox with `Repair`, `Disable`, or `Skip`. Phase 4 (permission operations) branches on that tag. Phase 5 (verify/summarise) reports all outcomes including the new `Disabled` state with conditional Next Steps guidance.

**Tech Stack:** PowerShell 5.1+, ExchangeOnlineManagement v3.9.0+

---

## File Map

| File | Change |
|------|--------|
| `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1` | All changes — single file |

---

### Task 1: Add `Action` field to mailbox objects, add `$toProcess` to state, bump phase count to 5

**Files:**
- Modify: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Add `$toProcess` to state declarations (lines 22–26)**

Replace:
```powershell
$allMailboxes    = @()
$toRefresh       = @()
$skipped         = @()
$results         = @()
$failureCount    = 0
```
With:
```powershell
$allMailboxes    = @()
$toRefresh       = @()
$skipped         = @()
$toProcess       = @()
$results         = @()
$failureCount    = 0
```

- [ ] **Step 2: Change Write-Step total from `/4` to `/5` (line 34)**

Replace:
```powershell
    Write-Host "`n[$Step/4] $Message" -ForegroundColor Cyan
```
With:
```powershell
    Write-Host "`n[$Step/5] $Message" -ForegroundColor Cyan
```

- [ ] **Step 3: Add `Action` field to mailbox PSCustomObject in scan loop (lines 81–86)**

Replace:
```powershell
        $allMailboxes += [PSCustomObject]@{
            Address     = $mbx.PrimarySmtpAddress
            DisplayName = $mbx.DisplayName
            AutoMapping = $autoMap
        }
```
With:
```powershell
        $allMailboxes += [PSCustomObject]@{
            Address     = $mbx.PrimarySmtpAddress
            DisplayName = $mbx.DisplayName
            AutoMapping = $autoMap
            Action      = if ($autoMap) { 'Repair' } else { 'Skip' }
        }
```

- [ ] **Step 4: Update Phase 2 summary line to reflect pre-wizard state (line 117)**

Replace:
```powershell
Write-Detail ("{0} mailbox(es) found — {1} will be refreshed" -f $allMailboxes.Count, $toRefresh.Count) White
```
With:
```powershell
Write-Detail ("{0} mailbox(es) found — {1} automapped, {2} already disabled" -f $allMailboxes.Count, $toRefresh.Count, $skipped.Count) White
```

- [ ] **Step 5: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: add Action field to mailbox objects and bump phase count to 5"
```

---

### Task 2: Remove old confirm prompt and insert Phase 3 Action Selection wizard

**Files:**
- Modify: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Remove old confirm prompt (lines 131–138)**

Delete these lines entirely:
```powershell
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

- [ ] **Step 2: Insert Phase 3 Action Selection wizard in place of the removed block**

Insert immediately after the `exit 0` on line 128 (the "all AutoMapping disabled" early-exit block):

```powershell
# --- Phase 3: Action Selection ---
Write-Step 3 "Action Selection"
Write-Host ""

$disableChoice = Read-Host "      Disable AutoMapping on any of these mailboxes? [Y/N]"
Write-Host ""

if ($disableChoice -match '^[Yy]') {
    $bulkChoice = Read-Host "      Apply to all [A] or one at a time [O]?"
    Write-Host ""

    if ($bulkChoice -match '^[Aa]') {
        foreach ($mbx in $allMailboxes | Where-Object { $_.Action -eq 'Repair' }) {
            $mbx.Action = 'Disable'
        }
    } else {
        $automapped = @($allMailboxes | Where-Object { $_.Action -eq 'Repair' })
        for ($i = 0; $i -lt $automapped.Count; $i++) {
            $mbx    = $automapped[$i]
            $prompt = "      [{0}/{1}] {2,-46} [R]epair / [D]isable / [S]kip" -f ($i + 1), $automapped.Count, $mbx.Address
            do {
                $choice = Read-Host $prompt
            } while ($choice -notmatch '^[RrDdSs]$')
            switch -Regex ($choice) {
                '^[Dd]$' { $mbx.Action = 'Disable' }
                '^[Ss]$' { $mbx.Action = 'Skip'    }
            }
        }
        Write-Host ""
    }
}

# --- Action plan table ---
Write-Host ""
Write-Detail ("{0,-50} {1}" -f 'Mailbox', 'Action') Gray
Write-Detail ("{0,-50} {1}" -f '-------', '------') Gray
foreach ($mbx in $allMailboxes) {
    $actionLabel = switch ($mbx.Action) {
        'Repair'  { 'Repair'                              }
        'Disable' { 'Disable AutoMapping'                  }
        'Skip'    { 'Skip  (already disabled / orphaned)'  }
    }
    $actionColor = switch ($mbx.Action) {
        'Repair'  { 'Green'  }
        'Disable' { 'Yellow' }
        'Skip'    { 'Gray'   }
    }
    Write-Detail ("{0,-50} {1}" -f $mbx.Address, $actionLabel) $actionColor
}
Write-Host ""

$toProcess = @($allMailboxes | Where-Object { $_.Action -in 'Repair', 'Disable' })

if ($toProcess.Count -eq 0) {
    Write-Detail "No changes selected — all mailboxes skipped." Yellow
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
    exit 0
}

$go = Read-Host "      Proceed? [Y/N]"
Write-Host ""
if ($go -notmatch '^[Yy]') {
    Write-Host "  No changes made.`n" -ForegroundColor Cyan
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 0
}
```

- [ ] **Step 3: Verify Phase 3 displays correctly (manual spot check)**

Run: `pwsh -File tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1 -Mailbox <test-upn>`

Verify:
- After Phase 2 table, `[3/5] Action Selection` header appears
- Answer **N** → action plan table shows all automapped as `Repair` (green) → `Proceed? [Y/N]` prompt
- Answer **Y → A** → action plan table shows all automapped as `Disable AutoMapping` (yellow)
- Answer **Y → O** → loops through each mailbox one at a time; invalid input (e.g. `X`) re-prompts the same line

- [ ] **Step 4: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: insert Phase 3 action selection wizard"
```

---

### Task 3: Update Phase 4 — Permission Operations

**Files:**
- Modify: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Update Write-Step call from 3 to 4 and rename header**

Replace:
```powershell
Write-Step 3 "Refreshing permissions..."
```
With:
```powershell
Write-Step 4 "Permission Operations..."
```

- [ ] **Step 2: Replace the permission loop and skipped-results block**

Replace from `$results = @()` through the end of the `foreach ($mbx in $skipped)` block (lines ~144–183) with:

```powershell
$results = @()
$i = 0
foreach ($mbx in $toProcess) {
    $label = "[{0}/{1}] {2}" -f ($i + 1), $toProcess.Count, $mbx.Address
    Write-Host ("      {0,-68}" -f $label) -NoNewline

    try {
        Remove-MailboxPermission -Identity $mbx.Address -User $Mailbox `
            -AccessRights FullAccess -Confirm:$false -ErrorAction Stop
        Add-MailboxPermission -Identity $mbx.Address -User $Mailbox `
            -AccessRights FullAccess -AutoMapping ($mbx.Action -eq 'Repair') -ErrorAction Stop | Out-Null

        $outcome      = if ($mbx.Action -eq 'Repair') { 'Refreshed' } else { 'Disabled' }
        $outcomeColor = if ($mbx.Action -eq 'Repair') { 'Green' }     else { 'Yellow' }
        Write-Host $outcome -ForegroundColor $outcomeColor
        $results += [PSCustomObject]@{
            Address = $mbx.Address
            Action  = $mbx.Action
            Outcome = $outcome
            Reason  = ''
        }
    } catch {
        $errMsg = $_.Exception.Message
        Write-Host "Failed" -ForegroundColor Red
        Write-Detail "    $errMsg" Red
        $results += [PSCustomObject]@{
            Address = $mbx.Address
            Action  = $mbx.Action
            Outcome = 'Failed'
            Reason  = $errMsg
        }
        $failureCount++
    }
    $i++
}

# Add skipped mailboxes to results
foreach ($mbx in $allMailboxes | Where-Object { $_.Action -eq 'Skip' }) {
    $skipReason = if (-not $mbx.AutoMapping) { 'AutoMapping already disabled' } else { 'Skipped by tech' }
    $results += [PSCustomObject]@{
        Address = $mbx.Address
        Action  = 'Skip'
        Outcome = 'Skipped'
        Reason  = $skipReason
    }
}
```

- [ ] **Step 3: Verify Phase 4 output**

After a test run through the wizard:
- Repair mailboxes → `Refreshed` in green
- Disable mailboxes → `Disabled` in yellow
- A failure → `Failed` in red with error message on next line

- [ ] **Step 4: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: update Phase 4 to handle Repair and Disable actions"
```

---

### Task 4: Update Phase 5 — Verify and Summarise

**Files:**
- Modify: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Update Write-Step call from 4 to 5**

Replace:
```powershell
Write-Step 4 "Verifying and summarising..."
```
With:
```powershell
Write-Step 5 "Verifying and summarising..."
```

- [ ] **Step 2: Expand verify loop to cover Refreshed and Disabled outcomes**

Replace:
```powershell
foreach ($r in $results | Where-Object { $_.Outcome -eq 'Refreshed' }) {
```
With:
```powershell
foreach ($r in $results | Where-Object { $_.Outcome -in 'Refreshed', 'Disabled' }) {
```

Also update the failure reason string inside that block:
```powershell
        $r.Reason  = 'Permission not found after operation — verify manually in Exchange admin'
```

- [ ] **Step 3: Add Disabled to result table color and suffix logic**

Replace the `$color` switch and `$suffix` expression in the result table `foreach` loop:
```powershell
    $color = switch ($r.Outcome) {
        'Refreshed' { 'Green'  }
        'Disabled'  { 'Yellow' }
        'Skipped'   { 'Gray'   }
        'Failed'    { 'Red'    }
        default     { 'White'  }
    }
    $suffix = if ($r.Outcome -eq 'Skipped') { "  ($($r.Reason))" } `
              elseif ($r.Outcome -eq 'Failed') { "  — $($r.Reason)" } `
              else { '' }
```

- [ ] **Step 4: Replace counts and Next Steps block**

Replace from `$refreshedCount = ...` through the closing `================================================` and blank line (lines ~218–238) with:

```powershell
$refreshedCount = ($results | Where-Object { $_.Outcome -eq 'Refreshed' }).Count
$disabledCount  = ($results | Where-Object { $_.Outcome -eq 'Disabled'  }).Count
$skippedCount   = ($results | Where-Object { $_.Outcome -eq 'Skipped'   }).Count
$failedCount    = ($results | Where-Object { $_.Outcome -eq 'Failed'    }).Count

# Failure callout
if ($failedCount -gt 0) {
    Write-Detail "$failedCount mailbox(es) failed — manual remediation required." Red
    Write-Detail "Check Exchange admin permissions and re-run, or grant Full Access manually." Gray
    Write-Host ""
}

# Conditional Next Steps
$alias = ($Mailbox -split '@')[0]
$step  = 1
Write-Host "      ================================================" -ForegroundColor DarkCyan
Write-Host "       Next Steps" -ForegroundColor White
if ($refreshedCount -gt 0) {
    Write-Detail "  Step $step — Ask $alias to close and reopen Outlook." White
    Write-Detail "           Repaired mailboxes should reappear within a few minutes." Gray
    $step++
}
if ($disabledCount -gt 0) {
    Write-Detail "  Step $step — Manually add disabled mailboxes in Outlook:" White
    Write-Detail "           Classic: File > Account Settings > Change > More Settings" Gray
    Write-Detail "                    > Advanced > add shared mailbox address" Gray
    Write-Detail "           New Outlook: Right-click Folders > Add shared folder" Gray
    $step++
}
if ($refreshedCount -gt 0) {
    Write-Detail "  Step $step — If repaired mailboxes still missing after restart," White
    Write-Detail "           rebuild the Outlook profile: Control Panel > Mail > Show Profiles." Gray
}
Write-Host "      ================================================" -ForegroundColor DarkCyan
Write-Host ""
```

- [ ] **Step 5: Verify Phase 5 output**

- Pure repair run: Next Steps shows restart step + rebuild-if-missing step only
- Pure disable run: Next Steps shows manual-add step only
- Mixed run: restart step, manual-add step, rebuild-if-missing step all appear
- Result table: Refreshed (green), Disabled (yellow), Skipped (gray), Failed (red)

- [ ] **Step 6: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: update Phase 5 with Disabled outcome and conditional Next Steps"
```

---

### Task 5: Update ticket report for Disable counts and outcomes

**Files:**
- Modify: `tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1`

- [ ] **Step 1: Update PRE-FLIGHT counts in report array**

Replace these three lines in the `$report = @(...)` initialization:
```powershell
        (" Shared mailboxes found : {0}" -f $allMailboxes.Count)
        (" To be refreshed        : {0} (AutoMapping enabled)"  -f $toRefresh.Count)
        (" Skipped                : {0} (AutoMapping disabled)" -f $skipped.Count)
```
With:
```powershell
        (" Shared mailboxes found : {0}" -f $allMailboxes.Count)
        (" To be repaired         : {0} (AutoMapping pointer refresh)"        -f (($toProcess | Where-Object { $_.Action -eq 'Repair'  }).Count))
        (" To be disabled         : {0} (AutoMapping will be set to disabled)" -f (($toProcess | Where-Object { $_.Action -eq 'Disable' }).Count))
        (" Skipped                : {0} (AutoMapping already disabled)"        -f ($allMailboxes | Where-Object { $_.Action -eq 'Skip' }).Count)
```

- [ ] **Step 2: Update RESULTS suffix switch to handle Disabled**

Replace the `$suffix` switch inside the report `foreach ($r in $results)` loop:
```powershell
        $suffix = switch ($r.Outcome) {
            'Skipped'  { " ($($r.Reason))" }
            'Disabled' { ' (AutoMapping disabled — manually add in Outlook)' }
            'Failed'   { " — $($r.Reason)" }
            default    { '' }
        }
```

- [ ] **Step 3: Update OUTCOME section with conditional steps**

Replace from `if ($failedCount -eq 0)` through the closing `$sep` line in the report:
```powershell
    if ($failedCount -eq 0) {
        $report += " Operation complete."
    } else {
        $report += " Operation complete with $failedCount failure(s) — manual follow-up required."
    }

    $rStep = 1
    if ($refreshedCount -gt 0) {
        $report += " Step ${rStep}: Ask user to close and reopen Outlook."
        $report += "         Repaired mailboxes should reappear within a few minutes."
        $rStep++
    }
    if ($disabledCount -gt 0) {
        $report += " Step ${rStep}: Manually add disabled mailboxes in Outlook:"
        $report += "         Classic: File > Account Settings > Change > More Settings > Advanced"
        $report += "         New Outlook: Right-click Folders > Add shared folder"
        $rStep++
    }
    if ($refreshedCount -gt 0) {
        $report += " Step ${rStep}: If repaired mailboxes still missing after restart, rebuild"
        $report += "         the Outlook profile via Control Panel > Mail > Show Profiles."
    }
    $report += $sep
```

- [ ] **Step 4: Verify ticket report contents**

Export a report after a mixed Repair/Disable run. Open the `.txt` from the Desktop and verify:
- PRE-FLIGHT shows "To be repaired", "To be disabled", and "Skipped" with correct counts
- RESULTS shows `Disabled (AutoMapping disabled — manually add in Outlook)` for disabled entries
- OUTCOME section steps match what ran (no repair steps on a pure-disable run)

- [ ] **Step 5: Commit**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "feat: update ticket report for Disable counts and outcomes"
```

---

### Task 6: Full manual test pass

No code changes — validation only. Run through each scenario end-to-end against a real or sandbox Exchange tenant.

- [ ] **Scenario 1 — Pure repair fast path (existing behaviour unchanged)**

  Answer N to "Disable AutoMapping?" → action plan shows all Repair (green) → confirm Y → Phase 4 shows Refreshed → Phase 5 Next Steps shows restart + rebuild-if-missing steps only.

- [ ] **Scenario 2 — Disable all**

  Answer Y → A → action plan shows all "Disable AutoMapping" (yellow) → Phase 4 shows Disabled → Phase 5 Next Steps shows manual-add step only.

- [ ] **Scenario 3 — One at a time, mixed choices**

  Answer Y → O → choose D on first mailbox, R on second, S on third → action plan shows correct mix → Phase 4 processes D and R only, skips S → Phase 5 shows restart step + manual-add step + rebuild-if-missing step.

- [ ] **Scenario 4 — Tech skips all in one-at-a-time**

  Answer Y → O → answer S for every mailbox → `toProcess.Count = 0` → script exits with "No changes selected — all mailboxes skipped."

- [ ] **Scenario 5 — All mailboxes already AutoMapping disabled (early exit)**

  Phase 2 exits with "All shared mailboxes use manual mapping" message — Phase 3 wizard never reached. Existing behaviour unchanged.

- [ ] **Scenario 6 — Invalid input in one-at-a-time loop**

  Enter `X` at an R/D/S prompt → same mailbox prompt repeats without advancing.

- [ ] **Commit any fixes found during testing**

```bash
git add tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
git commit -m "fix: address issues found during manual test pass"
```
