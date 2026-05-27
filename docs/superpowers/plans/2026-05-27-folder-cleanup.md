# Folder Cleanup [F] Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add [F] Folder cleanup mode to Invoke-MailboxCleanup.ps1 — lets techs permanently purge a primary mailbox folder via compliance search folderid: query, with a numbered folder list, warning gate, HardDelete purge, post-purge loop, and ticket report integration.

**Architecture:** [F] is a standalone execution path inside a new `while ($modeLoopActive)` loop that wraps the existing mode menu. The folder cleanup loop (select → purge → [A/M/Q]) runs independently of the Recoverable Items try/catch/finally block. [M] from the post-purge menu re-enters the outer mode loop so techs can chain folder cleanup into a full Recoverable Items cleanup. State is tracked in `$folderCleanupResults` for ticket report output.

**Tech Stack:** PowerShell 7, ExchangeOnlineManagement v3.9+, IPPSSession (Purview compliance search), Exchange Online `Get-MailboxFolderStatistics`, `Get-MailboxStatistics`

---

### Task 1: Add `ConvertTo-FolderQueryString` helper and new state variables

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

Exchange folder IDs are base64-encoded but compliance search requires hex-encoded `folderid:` queries. This helper converts between the two formats.

- [ ] **Step 1: Add state variables to the state block**

In `Invoke-MailboxCleanup.ps1`, find the `# --- State ---` block (lines 28-46). Add two new variables at the end of the block:

```powershell
$folderCleanupMode    = $false
$folderCleanupResults = @()
```

The full state block should now end:
```powershell
$mfaOnlyMode             = $false
$statusOnlyMode          = $false
$folderCleanupMode       = $false
$folderCleanupResults    = @()
$reportTime              = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportTimestamp         = Get-Date -Format 'yyyyMMdd-HHmmss'
```

- [ ] **Step 2: Add `ConvertTo-FolderQueryString` to the helpers section**

Find the `function Confirm-Continue` block (the last helper function, around line 94). Add the new helper immediately after it, before `# --- Main ---`:

```powershell
function ConvertTo-FolderQueryString {
    param([string]$FolderId)
    $encoding   = [System.Text.Encoding]::GetEncoding("us-ascii")
    $nibbler    = $encoding.GetBytes("0123456789ABCDEF")
    $idBytes    = [Convert]::FromBase64String($FolderId)
    $indexBytes = New-Object byte[] 48
    $indexBytes[0] = 1
    [System.Buffer]::BlockCopy($idBytes, 0, $indexBytes, 1, 24)
    $query = "folderid:"
    for ($i = 0; $i -lt 25; $i++) {
        $query += [char]$nibbler[$indexBytes[$i] -shr 4]
        $query += [char]$nibbler[$indexBytes[$i] -band 0x0F]
    }
    return $query
}
```

- [ ] **Step 3: Add version constant and display it in the header banner**

Add `$SCRIPT_VERSION = "1.4"` as the first constant in the `# --- Constants ---` block:

```powershell
# --- Constants ---
$SCRIPT_VERSION                = "1.4"
$RETENTION_POLICY_NAME         = "3 Year Email Retention Policy"
```

Update the header banner (around line 108) to show the version:

```powershell
Write-Host "  ================================================" -ForegroundColor DarkCyan
Write-Host "   Mailbox Cleanup Tool  v$SCRIPT_VERSION" -ForegroundColor White
Write-Host "  ================================================" -ForegroundColor DarkCyan
Write-Host "   Target: $Mailbox" -ForegroundColor Gray
```

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: add ConvertTo-FolderQueryString helper, folder cleanup state vars, v1.4 header"
```

---

### Task 2: Wrap mode selection in `while ($modeLoopActive)` and add [F] to menu

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

The mode loop allows [M] from the [F] post-purge menu to return to the mode selection without restarting the script. Phases 1 and 2 (connect + status) stay outside the loop — they run once. Everything from mode menu through done message runs inside the loop.

- [ ] **Step 1: Find the mode selection block and wrap it**

Find the comment `# --- Mode selection ---` (around line 238). Immediately before it, add the loop opener and reset block:

```powershell
# --- Mode loop — allows [F] post-purge [M] to return here ---
$modeLoopActive = $true
while ($modeLoopActive) {
    $modeLoopActive    = $false
    $mfaOnlyMode       = $false
    $statusOnlyMode    = $false
    $folderCleanupMode = $false
```

- [ ] **Step 2: Add [F] to the mode menu display**

Replace the existing mode menu `Write-Host` lines with:

```powershell
    # --- Mode selection ---
    Write-Host ""
    Write-Host "      What would you like to do?" -ForegroundColor White
    Write-Host "        [C] Full cleanup   — compliance search, purge, and MFA" -ForegroundColor Gray
    Write-Host "        [M] MFA only       — re-check SIR, clear delay holds, and re-trigger MFA" -ForegroundColor Gray
    Write-Host "        [F] Folder cleanup — permanently purge contents of a primary mailbox folder" -ForegroundColor Gray
    Write-Host "        [S] Status only    — exit here, no changes made" -ForegroundColor Gray
    Write-Host "        [Q] Quit" -ForegroundColor Gray
    Write-Host ""
    $modeChoice = Read-Host "      Choice"
    Write-Host ""
```

- [ ] **Step 3: Add [F] to the switch statement**

Replace the existing switch block with:

```powershell
    switch -Regex ($modeChoice) {
        '^[Ss]' { $statusOnlyMode    = $true }
        '^[Mm]' { $mfaOnlyMode       = $true }
        '^[Cc]' { }
        '^[Ff]' { $folderCleanupMode = $true }
        default {
            $exitMsg = if ($sirRestored) { "SingleItemRecovery re-enabled. Exited." } else { "Exited. No changes were made." }
            Write-Host "  $exitMsg`n" -ForegroundColor Cyan
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            exit 0
        }
    }
```

- [ ] **Step 4: Close the mode loop after the done message / SIR banner**

Find the end of the SIR banner block (around line 563, the closing `}`  after the yellow ================================================ banner). Add the closing `}` for the while loop immediately after:

```powershell
    # (existing SIR banner block ends here)
    Write-Host "      ================================================`n" -ForegroundColor Yellow
    }

} # end mode loop
```

The ticket export and Disconnect-ExchangeOnline blocks stay outside the loop.

- [ ] **Step 5: Verify the script still runs for [C] and [M] modes**

Run the script and confirm [C], [M], and [S] still work as before — the mode loop should be transparent for those paths.

```powershell
pwsh.exe -File tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1 -Mailbox test@corrohealth.com
```

Choose [S] — should exit cleanly with "Status check complete."

- [ ] **Step 6: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "refactor: wrap mode selection in modeLoopActive loop, add [F] to menu and switch"
```

---

### Task 3: [F] warning banner and IPPSSession connection

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

The warning banner is a hard gate — no S&C connection is attempted until the tech explicitly confirms. N returns to the mode menu.

- [ ] **Step 1: Add the [F] mode block after the [S] status-only exit block**

Find the `# --- Status only: exit cleanly ---` block (around line 261). After its closing `}`, add:

```powershell
    # --- Folder cleanup mode ---
    if ($folderCleanupMode) {
        Write-Host ""
        Write-Host "      ================================================" -ForegroundColor Red
        Write-Host "       PERMANENT DELETE — Folder Cleanup" -ForegroundColor Red
        Write-Host "       This action will hard-delete ALL items in the" -ForegroundColor White
        Write-Host "       selected folder. They cannot be recovered." -ForegroundColor White
        Write-Host "" 
        Write-Host "       Confirm with the user that the folder contents" -ForegroundColor White
        Write-Host "       are safe to permanently delete before proceeding." -ForegroundColor White
        Write-Host "      ================================================" -ForegroundColor Red
        Write-Host ""
        $warnResponse = Read-Host "      Understood — proceed to folder selection? [Y/N]"
        Write-Host ""
        if ($warnResponse -notmatch '^[Yy]') {
            Write-Host "  Folder cleanup cancelled. No changes made.`n" -ForegroundColor Cyan
            continue
        }

        Write-Host ""
        Write-Detail "Connecting to Security & Compliance..." Cyan
        try {
            Connect-IPPSSession -EnableSearchOnlySession -ErrorAction Stop -WarningAction SilentlyContinue 6>$null
            Write-Detail "Security & Compliance: connected" Green
        } catch {
            Write-Detail "ERROR: Could not connect to Security & Compliance. $_" Red
            continue
        }

        # (folder loop added in Task 4-7)

    } # end folderCleanupMode
```

The `continue` statement re-evaluates the `while ($modeLoopActive)` condition. Since `$modeLoopActive` is `$false` (reset at top of loop), it exits — unless [M] was chosen in the post-purge menu, which sets it back to `$true`.

- [ ] **Step 2: Verify warning gate works**

Run the script, choose [F], then answer N. Should print "Folder cleanup cancelled. No changes made." and exit cleanly.

- [ ] **Step 3: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: add [F] mode warning banner and IPPSSession connection gate"
```

---

### Task 4: Primary quota display and folder list

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

The folder list shows primary mailbox folders over 1 GB, sorted largest first, with the same color scaling used in the Recoverable Items breakdown. Recoverable Items folders and the root folder are excluded.

- [ ] **Step 1: Add a constant for the primary folder size threshold**

In the `# --- Constants ---` block, add after `$DISCOVERY_HOLDS_SIR_THRESHOLD`:

```powershell
$PRIMARY_FOLDER_SIZE_THRESHOLD = 1GB
```

- [ ] **Step 2: Add the folder loop opener and primary quota display inside the [F] block**

Replace the `# (folder loop added in Task 4-7)` placeholder with:

```powershell
        $folderLoopActive = $true
        while ($folderLoopActive) {
            $folderLoopActive = $false

            # Primary mailbox quota display
            $primaryStats      = $null
            $primaryUsedBytes  = [long]0
            $primaryLimitBytes = ConvertTo-Bytes $mbx.ProhibitSendReceiveQuota
            try {
                $primaryStats     = Get-MailboxStatistics -Identity $Mailbox -ErrorAction Stop
                $primaryUsedBytes = ConvertTo-Bytes $primaryStats.TotalItemSize
            } catch {
                Write-Detail "WARNING: Could not fetch primary mailbox size. $_" Yellow
            }
            $primaryPct = if ($primaryLimitBytes -gt 0) { [int](($primaryUsedBytes / $primaryLimitBytes) * 100) } else { 0 }

            Write-Host ""
            Write-Detail ("Primary Mailbox    : {0} / {1} ({2}% full)" -f `
                (Format-Size $primaryUsedBytes), (Format-Size $primaryLimitBytes), $primaryPct) `
                $(if ($primaryPct -ge 90) { 'Red' } elseif ($primaryPct -ge 70) { 'Yellow' } else { 'Green' })
            Write-Host ""

            # Primary folder list — exclude Recoverable Items and root; filter > 1 GB; sort largest first
            $primaryFolders = Get-MailboxFolderStatistics -Identity $Mailbox |
                Where-Object {
                    $_.FolderType -notlike 'RecoverableItems*' -and
                    $_.FolderType -ne 'Root' -and
                    (ConvertTo-Bytes $_.FolderAndSubfolderSize) -gt $PRIMARY_FOLDER_SIZE_THRESHOLD
                } |
                Sort-Object { ConvertTo-Bytes $_.FolderAndSubfolderSize } -Descending

            if (-not $primaryFolders -or $primaryFolders.Count -eq 0) {
                Write-Detail "No primary folders exceed 1 GB. Nothing to target." Yellow
                Write-Host ""
                continue
            }

            Write-Detail "Select a folder to purge:" White
            Write-Host ""
            $nameColWidth = [Math]::Max(($primaryFolders | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum + 2, 20)
            $idx = 1
            foreach ($f in $primaryFolders) {
                $fBytes = ConvertTo-Bytes $f.FolderAndSubfolderSize
                $fPct   = if ($primaryLimitBytes -gt 0) { ($fBytes / $primaryLimitBytes) * 100 } else { 0 }
                $fColor = if     ($fPct -ge 60) { 'Red' }
                          elseif ($fPct -ge 20) { 'DarkYellow' }
                          elseif ($fPct -ge 5)  { 'Yellow' }
                          else                   { 'Gray' }
                Write-Host ("      [{0}]  {1} {2,8} items   {3}" -f $idx, $f.Name.PadRight($nameColWidth), $f.ItemsInFolder, (Format-Size $fBytes)) -ForegroundColor $fColor
                $idx++
            }
            Write-Host ""

            # (folder selection added in Task 5)

        } # end folder loop
```

- [ ] **Step 3: Verify folder list renders**

Run with a real mailbox, choose [F], answer Y. Should show primary quota line followed by numbered color-coded folder list.

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: add primary quota display and color-scaled folder list for [F] mode"
```

---

### Task 5: Folder selection with validation

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

Tech enters a number; script validates range and re-prompts on invalid input. Echoes the selection back with size and item count before the final confirm.

- [ ] **Step 1: Add folder selection after the folder list display**

Replace the `# (folder selection added in Task 5)` placeholder with:

```powershell
            # Folder selection with validation
            $selectedFolder = $null
            while ($null -eq $selectedFolder) {
                $folderChoice = Read-Host "      Enter folder number"
                $folderIndex  = 0
                if ([int]::TryParse($folderChoice, [ref]$folderIndex) -and
                    $folderIndex -ge 1 -and $folderIndex -le $primaryFolders.Count) {
                    $selectedFolder = $primaryFolders[$folderIndex - 1]
                } else {
                    Write-Detail "Invalid selection. Enter a number between 1 and $($primaryFolders.Count)." Yellow
                }
            }

            $selBytes = ConvertTo-Bytes $selectedFolder.FolderAndSubfolderSize
            Write-Host ""
            Write-Detail ("Selected: {0}  ({1:N0} items / {2})" -f `
                $selectedFolder.Name, $selectedFolder.ItemsInFolder, (Format-Size $selBytes)) White
            $purgeConfirm = Read-Host "      Proceed with HardDelete purge of all items in this folder? [Y/N]"
            Write-Host ""
            if ($purgeConfirm -notmatch '^[Yy]') {
                Write-Detail "Purge cancelled. Returning to folder list." Yellow
                $folderLoopActive = $true
                continue
            }

            # (compliance search + purge added in Task 6)
```

- [ ] **Step 2: Verify selection and re-prompt**

Run with a real mailbox, choose [F], answer Y to warning, enter an invalid number (e.g. 99). Should re-prompt. Enter a valid number — should echo back the folder name, size, and item count, then show [Y/N]. Answer N — should return to the folder list.

- [ ] **Step 3: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: add folder selection validation and pre-purge confirmation for [F] mode"
```

---

### Task 6: Compliance search and HardDelete purge

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

Same poll loop pattern as [C] Phase 5. Uses a separate `$folderSearchName` variable so it doesn't interfere with the Recoverable Items `$searchName`. `Remove-ComplianceSearch` always runs in the finally block.

- [ ] **Step 1: Add the compliance search + purge block**

Replace `# (compliance search + purge added in Task 6)` with:

```powershell
            # Compliance search + HardDelete purge
            $folderSearchName = $null
            $folderSearch     = $null
            $folderPurgeError = $false
            try {
                $folderAlias      = ($Mailbox -split '@')[0]
                $folderSafeName   = $selectedFolder.Name -replace '[^A-Za-z0-9]', ''
                $folderTimestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
                $folderSearchName = "FolderCleanup-$folderAlias-$folderSafeName-$folderTimestamp"
                $folderQuery      = ConvertTo-FolderQueryString -FolderId $selectedFolder.FolderId

                Write-Detail "Compliance search: $folderSearchName" Gray

                New-ComplianceSearch -Name $folderSearchName `
                    -ExchangeLocation $Mailbox `
                    -ContentMatchQuery $folderQuery `
                    -ErrorAction Stop | Out-Null

                Start-ComplianceSearch -Identity $folderSearchName -ErrorAction Stop

                $elapsed = 0
                do {
                    Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
                    $elapsed += $POLL_INTERVAL_SECONDS
                    $folderSearch = Get-ComplianceSearch -Identity $folderSearchName
                    Write-Detail "Searching... (${elapsed}s) - $($folderSearch.Status)"
                } while ($folderSearch.Status -notin @('Completed', 'Failed'))

                if ($folderSearch.Status -eq 'Failed') {
                    throw "Compliance search '$folderSearchName' failed. Check the Security & Compliance portal."
                }

                Write-Detail ("Search complete — {0:N0} items found ({1})" -f `
                    $folderSearch.Items, (Format-Size $folderSearch.Size)) Green

                Write-Detail "Running purge (HardDelete)..." Yellow

                New-ComplianceSearchAction -SearchName $folderSearchName `
                    -Purge -PurgeType HardDelete -Confirm:$false -ErrorAction Stop | Out-Null

                $folderActionName = "$folderSearchName`_Purge"
                $elapsed = 0
                do {
                    Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
                    $elapsed += $POLL_INTERVAL_SECONDS
                    $folderAction = Get-ComplianceSearchAction -Identity $folderActionName
                    Write-Detail "Purging... (${elapsed}s) - $($folderAction.Status)"
                } while ($folderAction.Status -notin @('Completed', 'Failed'))

                if ($folderAction.Status -eq 'Failed') {
                    throw "Compliance purge '$folderActionName' failed. Check the Security & Compliance portal."
                }

                Write-Detail "Purge complete." Green

                Write-Host ""
                Write-Host "      ================================================" -ForegroundColor DarkCyan
                Write-Host "       Results" -ForegroundColor White
                Write-Detail ("  Folder : {0}" -f $selectedFolder.Name) White
                Write-Detail ("  Purged : {0:N0} items  ({1})" -f $folderSearch.Items, (Format-Size $folderSearch.Size)) Green
                Write-Host "      ================================================" -ForegroundColor DarkCyan
                Write-Host ""

                $folderCleanupResults += [PSCustomObject]@{
                    FolderName = $selectedFolder.Name
                    Items      = $folderSearch.Items
                    SizeBytes  = $folderSearch.Size
                    Status     = 'Purged'
                }

            } catch {
                Write-Host "`n      ERROR: $_" -ForegroundColor Red
                $folderPurgeError = $true
                $folderCleanupResults += [PSCustomObject]@{
                    FolderName = if ($selectedFolder) { $selectedFolder.Name } else { 'Unknown' }
                    Items      = 0
                    SizeBytes  = 0
                    Status     = 'Failed'
                }
            } finally {
                if ($folderSearchName) {
                    try {
                        Remove-ComplianceSearch -Identity $folderSearchName -Confirm:$false -ErrorAction Stop
                        Write-Detail "Compliance search deleted." Green
                    } catch {
                        Write-Detail "WARNING: Could not delete compliance search '$folderSearchName'. Delete it from the Security & Compliance portal." Yellow
                    }
                }
            }

            # (post-purge loop menu added in Task 7)
```

- [ ] **Step 2: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: add compliance search and HardDelete purge flow for [F] mode"
```

---

### Task 7: Post-purge loop menu [A/M/Q]

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

[A] re-fetches folder statistics (fresh sizes) and loops back. [M] sets `$modeLoopActive = $true` so the outer while re-runs the mode menu. [Q] (or any other key) exits — falls through to ticket export and disconnect.

- [ ] **Step 1: Add the post-purge loop menu**

Replace `# (post-purge loop menu added in Task 7)` with:

```powershell
            Write-Host ""
            Write-Host "      What would you like to do next?" -ForegroundColor White
            Write-Host "        [A] Target another folder" -ForegroundColor Gray
            Write-Host "        [M] Back to main menu" -ForegroundColor Gray
            Write-Host "        [Q] Quit" -ForegroundColor Gray
            Write-Host ""
            $loopChoice = Read-Host "      Choice"
            Write-Host ""

            switch -Regex ($loopChoice) {
                '^[Aa]' { $folderLoopActive = $true }
                '^[Mm]' { $modeLoopActive   = $true }
                default { }
            }
```

- [ ] **Step 2: Verify the full [F] loop**

Run the script, choose [F], answer Y to warning, select a folder, answer Y to purge confirm. After purge completes:
- Choose [A] — should re-fetch folder list and show updated sizes
- Choose [M] — should return to the [C/M/F/S/Q] menu
- Choose [Q] — should fall through to ticket export prompt then disconnect

- [ ] **Step 3: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: add post-purge loop menu [A/M/Q] for [F] mode"
```

---

### Task 8: Ticket report — Mode label and Folder Cleanup section

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

Update the Mode line in the ticket report to show 'Folder Cleanup' for [F] runs. Append a FOLDER CLEANUP section if any folder purges ran in the session.

- [ ] **Step 1: Update the Mode line in the ticket report**

Find the Mode line in the report builder (around line 582):

```powershell
        " Mode   : $(if ($mfaOnlyMode) { 'MFA Only' } else { 'Full Cleanup' })"
```

Replace with:

```powershell
        " Mode   : $(if ($mfaOnlyMode) { 'MFA Only' } elseif ($folderCleanupMode) { 'Folder Cleanup' } else { 'Full Cleanup' })"
```

- [ ] **Step 2: Add FOLDER CLEANUP section to the report**

Find `$report += $sep` near the bottom of the report builder (the closing line before `$report | Out-File`). Insert the folder cleanup section before it:

```powershell
    if ($folderCleanupResults.Count -gt 0) {
        $report += @(
            ""
            $dash
            " FOLDER CLEANUP"
            $dash
        )
        foreach ($r in $folderCleanupResults) {
            if ($r.Status -eq 'Purged') {
                $report += (" {0,-30} : {1:N0} items purged  ({2}) — HardDelete" -f `
                    $r.FolderName, $r.Items, (Format-Size $r.SizeBytes))
            } else {
                $report += (" {0,-30} : Failed — check console output" -f $r.FolderName)
            }
        }
    }
    $report += $sep
```

- [ ] **Step 3: Verify ticket report includes [F] section**

Run the script, do a [F] folder purge, answer Y to ticket export. Open the report file on the Desktop — should show Mode: Folder Cleanup and a FOLDER CLEANUP section with the folder name, item count, and size.

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat: add Folder Cleanup section and mode label to ticket report"
```

---

### Task 9: README update, version bump in downloads.json, re-zip, and push

**Files:**
- Modify: `tools/mailbox-cleanup/README.txt`
- Modify: `downloads.json`
- Modify: `tools/mailbox-cleanup.zip` (re-zip)

- [ ] **Step 1: Update README.txt — add [F] to the WHAT IT DOES section**

In the `WHAT IT DOES — 6 PHASES` section of `tools/mailbox-cleanup/README.txt`, add after the Phase 2 description:

```
Folder Cleanup Mode [F]
  Independent of the 6-phase Recoverable Items cleanup. After the Phase 2
  status display, choosing [F] enters a standalone folder cleanup wizard:
    - Warning banner: hard gate requiring tech to confirm user sign-off
    - Primary quota display (separate from Recoverable Items quota)
    - Numbered list of primary mailbox folders over 1 GB, color-scaled
      by severity (gray/yellow/orange/red against primary quota)
    - Compliance search scoped to the selected folder via folderid: query
    - HardDelete purge — permanently removes items, bypasses Recoverable Items
    - Post-purge loop: [A] target another folder, [M] back to main menu, [Q] quit
  Use for: third-party sync folders (MimeCast etc.), Deleted Items bloat,
  user-created folders the user cannot self-delete due to quota restrictions.
```

Also update the version line at the top of README.txt from `v1.3` to `v1.4`.

- [ ] **Step 2: Update downloads.json version**

In `downloads.json`, change:
```json
"version": "1.3",
```
to:
```json
"version": "1.4",
```

- [ ] **Step 3: Re-zip**

```powershell
Remove-Item tools\mailbox-cleanup.zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path tools\mailbox-cleanup\* -DestinationPath tools\mailbox-cleanup.zip
```

- [ ] **Step 4: Commit and push to both sites**

```bash
git add tools/mailbox-cleanup/README.txt downloads.json tools/mailbox-cleanup.zip
git commit -m "feat: mailbox cleanup v1.4 — folder cleanup [F] mode

Adds [F] mode for primary mailbox folder targeting via compliance search
folderid: query. Warning gate, color-scaled folder list, HardDelete purge,
post-purge loop [A/M/Q], ticket report FOLDER CLEANUP section.
Mode loop allows chaining [F] → [C] in one session.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"

git push origin testing
git checkout main && git merge testing && git push origin main && git checkout testing
```

---

## Self-Review Notes

- **Spec coverage:** All 8 spec sections covered — menu, warning gate, IPPSSession, primary quota display, folder list (color-scaled, 1 GB filter, Recoverable Items excluded), folder selection + validation, compliance search + purge (finally cleanup), post-purge loop [A/M/Q], ticket report FOLDER CLEANUP section.
- **State vars:** `$folderCleanupMode` reset at top of mode loop each iteration — correct. `$folderCleanupResults` persists across loop iterations (intentional — ticket report needs all runs).
- **Type consistency:** `ConvertTo-FolderQueryString` defined in Task 1, called in Task 6 — matches. `$folderSearch.Size` used in Task 6 and Task 8 — same property name throughout. `$PRIMARY_FOLDER_SIZE_THRESHOLD` defined in Task 4 constants, used in Task 4 filter — matches.
- **Error paths:** IPPSSession failure → `continue` (back to mode menu). No folders over 1 GB → message + `continue`. Invalid selection → re-prompt loop. Search/purge failure → caught, logged, appended to results as 'Failed', falls to post-purge menu. `Remove-ComplianceSearch` always runs in finally.
- **Mode loop close brace:** Task 2 adds `} # end mode loop` — ensure this closes the while, not an inner block. The ticket export and Disconnect-ExchangeOnline must be outside this brace.
