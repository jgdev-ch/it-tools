# Archive Cleanup Mode + Navigation Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add [A] In-Place Archive folder cleanup mode to `Invoke-MailboxCleanup.ps1` and overhaul post-action navigation so techs can loop back to the main menu without restarting the script.

**Architecture:** All changes are to a single PowerShell script. [A] mode uses `folderid:` compliance search queries to exclusively target archive folders — never the primary mailbox. Navigation overhaul extracts ticket export into a function, wraps the mode loop in an outer `while ($continueScript)` loop, and adds a unified post-action menu between outer loop iterations. The inner mode loop structure is preserved intact.

**Tech Stack:** PowerShell 5.1+, ExchangeOnlineManagement v3.9.0+, Security & Compliance (IPPSSession / Connect-IPPSSession), Exchange Online REST API

---

## File Map

| File | Change |
|---|---|
| `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1` | All changes — single file |

---

### Task 1: Constants, state variables, version bump

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

- [ ] **Step 1: Bump version and add archive threshold constant**

In the constants block (lines 22–28), change `$SCRIPT_VERSION` and add one constant:

```powershell
$SCRIPT_VERSION                  = "2.0"
$RETENTION_POLICY_NAME           = "3 Year Email Retention Policy"
$PROPAGATION_WAIT_SECONDS        = 120
$POLL_INTERVAL_SECONDS           = 30
$DISCOVERY_HOLDS_SIR_THRESHOLD   = 1GB
$PRIMARY_FOLDER_SIZE_THRESHOLD   = 1GB
$ASYNC_HOLD_CHECK_WAIT           = 90
$ARCHIVE_SIZE_ADVISORY_THRESHOLD = 10GB
```

- [ ] **Step 2: Add archive state variables**

In the state block (lines 38–58), add after `$folderCleanupMode = $false` and `$folderCleanupResults = @()`:

```powershell
$archiveCleanupMode    = $false
$archiveCleanupResults = @()
$mfaWait               = ""
```

`$mfaWait` is initialized here so `Write-TicketReport` never receives a null value for modes ([S], [A], [F]) where Phase 6 doesn't execute and `Get-MfaWaitEstimate` never runs.

- [ ] **Step 3: Validate syntax**

```powershell
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1',
    [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red } } else { Write-Host 'No syntax errors.' -ForegroundColor Green }
```

Expected: `No syntax errors.`

- [ ] **Step 4: Commit**

```bash
cd /c/dev/projects/it-tools
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat(mailbox-cleanup): bump to v2.0, add archive constants and state vars"
```

---

### Task 2: Validate folderid: conversion — GATE TASK

**This task must pass before Task 6 implements the compliance search.** It validates that archive folder IDs from EXO v3 REST mode convert correctly for compliance search `folderid:` queries. If validation fails, the mode aborts safely — it does not fall back to `folderpath:`.

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

- [ ] **Step 1: Add ConvertTo-ComplianceFolderId helper**

Add this function to the helpers block after `Get-TrackingBlob` (after line 154, before `# --- Main ---`):

```powershell
function ConvertTo-ComplianceFolderId {
    param([string]$FolderId)
    if ([string]::IsNullOrWhiteSpace($FolderId)) { return $null }
    try {
        $bytes = [System.Convert]::FromBase64String($FolderId)
        return [System.Convert]::ToBase64String($bytes)
    } catch {
        return $null
    }
}
```

- [ ] **Step 2: Run manual validation — Connect and fetch archive folders**

Open PowerShell and run (use `prabhu.nithyanantharaj@corrohealth.com` — confirmed 97.9 GB archive):

```powershell
Connect-ExchangeOnline -ShowBanner:$false
$archiveFolders = Get-MailboxFolderStatistics -Identity 'prabhu.nithyanantharaj@corrohealth.com' -Archive
$archiveFolders | Where-Object { $_.ItemsInFolderAndSubfolders -gt 0 } |
    Select-Object Name, FolderPath, ItemsInFolderAndSubfolders, FolderAndSubfolderSize, FolderId |
    Format-Table -AutoSize
```

Note the FolderId format returned. It should look like a base64 string (e.g., `LgAAAABX...`).

- [ ] **Step 3: Test folderid: query in compliance search (read-only — no purge)**

```powershell
Connect-IPPSSession -EnableSearchOnlySession -WarningAction SilentlyContinue 6>$null

$testFolder  = $archiveFolders | Where-Object { $_.Name -eq 'Inbox' } | Select-Object -First 1
$rawId       = $testFolder.FolderId
$bytes       = [System.Convert]::FromBase64String($rawId)
$convertedId = [System.Convert]::ToBase64String($bytes)

$searchName = "ArchiveValidation-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-ComplianceSearch -Name $searchName `
    -ExchangeLocation 'prabhu.nithyanantharaj@corrohealth.com' `
    -ContentMatchQuery "folderid:$convertedId" | Out-Null
Start-ComplianceSearch -Identity $searchName
Start-Sleep -Seconds 45
$result = Get-ComplianceSearch -Identity $searchName
Write-Host "Status: $($result.Status)   Items: $($result.Items)   Size: $($result.Size)"
Remove-ComplianceSearch -Identity $searchName -Confirm:$false
```

**Success:** `Status: Completed   Items: <non-zero>` — base64 round-trip works. Proceed to Task 3.

**Failure (Items: 0 but Inbox clearly has items):** Try hex encoding instead:

```powershell
$hexId      = [System.BitConverter]::ToString($bytes).Replace('-', '').ToLower()
$searchName2 = "ArchiveValidation2-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-ComplianceSearch -Name $searchName2 `
    -ExchangeLocation 'prabhu.nithyanantharaj@corrohealth.com' `
    -ContentMatchQuery "folderid:$hexId" | Out-Null
Start-ComplianceSearch -Identity $searchName2
Start-Sleep -Seconds 45
$result2 = Get-ComplianceSearch -Identity $searchName2
Write-Host "Status: $($result2.Status)   Items: $($result2.Items)"
Remove-ComplianceSearch -Identity $searchName2 -Confirm:$false
```

If hex succeeds, update `ConvertTo-ComplianceFolderId` to return hex:

```powershell
function ConvertTo-ComplianceFolderId {
    param([string]$FolderId)
    if ([string]::IsNullOrWhiteSpace($FolderId)) { return $null }
    try {
        $bytes = [System.Convert]::FromBase64String($FolderId)
        return [System.BitConverter]::ToString($bytes).Replace('-', '').ToLower()
    } catch {
        return $null
    }
}
```

**If both fail:** Stop. Document the FolderId format observed. Do not ship [A] mode until a working conversion is confirmed. `folderpath:` is not an acceptable fallback.

- [ ] **Step 4: Validate syntax**

```powershell
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1',
    [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red } } else { Write-Host 'No syntax errors.' -ForegroundColor Green }
```

- [ ] **Step 5: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat(mailbox-cleanup): add ConvertTo-ComplianceFolderId helper — validated against archive"
```

---

### Task 3: Phase 2 — split into Active Mailbox / In-Place Archive sections

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

- [ ] **Step 1: Add [Active Mailbox] header**

Find line 175:
```powershell
Write-Step 2 "Mailbox status: $Mailbox"
```

Replace with:
```powershell
Write-Step 2 "Mailbox status: $Mailbox"
Write-Host ""
Write-Host "  --- [Active Mailbox] ---" -ForegroundColor DarkCyan
```

- [ ] **Step 2: Add [In-Place Archive] section**

After the Purview exception block (after the `if ($blobData -and $blobData.purviewExceptionActive)` block, around line 308), add:

```powershell
# --- In-Place Archive status ---
Write-Host ""
Write-Host "  --- [In-Place Archive] ---" -ForegroundColor DarkCyan
$archiveStats       = $null
$archiveFolderStats = $null
try {
    $archiveStats = Get-MailboxStatistics -Identity $Mailbox -Archive -ErrorAction Stop
} catch { }

if ($null -eq $archiveStats) {
    Write-Detail "No In-Place Archive provisioned." Gray
} else {
    $archiveTotalBytes = ConvertTo-Bytes $archiveStats.TotalItemSize
    $archiveItemCount  = $archiveStats.ItemCount
    Write-Detail ("Total size         : {0}  ({1:N0} items)" -f (Format-Size $archiveTotalBytes), $archiveItemCount) `
        $(if ($archiveTotalBytes -ge 50GB) { 'Red' } elseif ($archiveTotalBytes -ge 10GB) { 'Yellow' } else { 'Green' })

    try {
        $archiveFolderStats = Get-MailboxFolderStatistics -Identity $Mailbox -Archive -ErrorAction Stop |
            Where-Object { $_.FolderType -ne 'Root' -and $_.ItemsInFolderAndSubfolders -gt 0 } |
            Sort-Object { ConvertTo-Bytes $_.FolderAndSubfolderSize } -Descending

        if ($archiveFolderStats) {
            Write-Detail "Folder breakdown   :" Gray
            $archColWidth = [Math]::Max(($archiveFolderStats | ForEach-Object { $_.FolderPath.Length } | Measure-Object -Maximum).Maximum + 2, 30)
            $archiveFolderStats | ForEach-Object {
                $aBytes = ConvertTo-Bytes $_.FolderAndSubfolderSize
                $aPct   = if ($archiveTotalBytes -gt 0) { ($aBytes / $archiveTotalBytes) * 100 } else { 0 }
                $aColor = if     ($aPct -ge 60) { 'Red' }
                           elseif ($aPct -ge 20) { 'DarkYellow' }
                           elseif ($aPct -ge 5)  { 'Yellow' }
                           else                   { 'Gray' }
                Write-Detail ("    {0} {1,8} items   {2}" -f $_.FolderPath.PadRight($archColWidth), $_.ItemsInFolderAndSubfolders, (Format-Size $aBytes)) $aColor
            }
        }
    } catch { }

    if ($archiveTotalBytes -ge $ARCHIVE_SIZE_ADVISORY_THRESHOLD) {
        Write-Host ""
        Write-Detail "Archive is large — consider [A] Archive Cleanup from the main menu." Yellow
    }
}
```

- [ ] **Step 3: Validate syntax**

```powershell
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1',
    [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red } } else { Write-Host 'No syntax errors.' -ForegroundColor Green }
```

- [ ] **Step 4: Manual smoke test**

Run the script against `prabhu.nithyanantharaj@corrohealth.com`. Select `[S]` at the mode menu. Verify:
- `--- [Active Mailbox] ---` section shows Recoverable Items, SIR, holds
- `--- [In-Place Archive] ---` section shows ~97.9 GB total, folder breakdown sorted by size, and the yellow advisory line

- [ ] **Step 5: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat(mailbox-cleanup): split Phase 2 into Active Mailbox / In-Place Archive sections"
```

---

### Task 4: Add [A] to mode menu and mode loop

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

- [ ] **Step 1: Update mode menu display**

Find (around line 379):
```powershell
Write-Host "        [F] Folder cleanup — permanently purge contents of a primary mailbox folder" -ForegroundColor Gray
Write-Host "        [S] Status only    — exit here, no changes made" -ForegroundColor Gray
```

Replace with:
```powershell
Write-Host "        [F] Folder cleanup   — permanently purge contents of a primary mailbox folder" -ForegroundColor Gray
Write-Host "        [A] Archive cleanup  — permanently purge contents of an In-Place Archive folder" -ForegroundColor Gray
Write-Host "        [S] Status only      — view status, no changes" -ForegroundColor Gray
```

- [ ] **Step 2: Add [A] to the switch-Regex block**

Find (around line 387):
```powershell
    switch -Regex ($modeChoice) {
        '^[Ss]' { $statusOnlyMode    = $true }
        '^[Mm]' { $mfaOnlyMode       = $true }
        '^[Cc]' { }
        '^[Ff]' { $folderCleanupMode = $true }
        default {
```

Replace with:
```powershell
    switch -Regex ($modeChoice) {
        '^[Ss]' { $statusOnlyMode     = $true }
        '^[Mm]' { $mfaOnlyMode        = $true }
        '^[Cc]' { }
        '^[Ff]' { $folderCleanupMode  = $true }
        '^[Aa]' { $archiveCleanupMode = $true }
        default {
```

- [ ] **Step 3: Add $archiveCleanupMode to mode loop state reset**

Find the state resets at the top of the while loop body (around line 368):
```powershell
    $modeLoopActive    = $false
    $mfaOnlyMode       = $false
    $statusOnlyMode    = $false
    $folderCleanupMode = $false
    $quitRequested     = $false
```

Replace with:
```powershell
    $modeLoopActive     = $false
    $mfaOnlyMode        = $false
    $statusOnlyMode     = $false
    $folderCleanupMode  = $false
    $archiveCleanupMode = $false
    $quitRequested      = $false
```

- [ ] **Step 4: Validate syntax**

```powershell
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1',
    [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red } } else { Write-Host 'No syntax errors.' -ForegroundColor Green }
```

- [ ] **Step 5: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat(mailbox-cleanup): add [A] archive mode to menu and mode loop switch"
```

---

### Task 5: [A] mode — hold checks, warning banners, and archive folder picker

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

Insert the entire [A] mode handler block immediately after the `continue` / `} # end folderCleanupMode` closing line (around line 626), before the `# --- MFA only` comment.

- [ ] **Step 1: Add [A] mode handler — hold checks, banners, and S&C connect**

```powershell
# --- Archive cleanup mode ---
if ($archiveCleanupMode) {

    # Hard block: litigation hold covers entire mailbox including archive
    if ($mbx.LitigationHoldEnabled) {
        Write-Host ""
        Write-Host "      ================================================" -ForegroundColor Red
        Write-Host "       BLOCKED — Litigation Hold Detected" -ForegroundColor Red
        Write-Host "       This mailbox is under an active litigation hold." -ForegroundColor White
        Write-Host "       Purging archive items may violate legal" -ForegroundColor White
        Write-Host "       preservation requirements." -ForegroundColor White
        Write-Host "       Contact your compliance team before proceeding." -ForegroundColor White
        Write-Host "      ================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Archive cleanup blocked. Returning to main menu.`n" -ForegroundColor Yellow
        $modeLoopActive = $true
        continue
    }

    # Advisory: active holds may protect some items — not a hard block
    if ($mbx.InPlaceHolds -and $mbx.InPlaceHolds.Count -gt 0) {
        Write-Host ""
        Write-Host "      ================================================" -ForegroundColor Yellow
        Write-Host "       WARNING — Active Retention Holds Detected" -ForegroundColor Yellow
        Write-Host "       Items under active holds may be protected." -ForegroundColor White
        Write-Host "       Compliance search results may be partial." -ForegroundColor White
        Write-Host "       Confirm folder contents before proceeding." -ForegroundColor White
        Write-Host "      ================================================" -ForegroundColor Yellow
        Write-Host ""
    }

    # Verify archive exists (fetched in Phase 2)
    if ($null -eq $archiveStats) {
        Write-Host ""
        Write-Detail "No In-Place Archive provisioned for $Mailbox. Nothing to clean." Yellow
        $modeLoopActive = $true
        continue
    }

    # PERMANENT DELETE warning gate — identical to [F] mode
    Write-Host ""
    Write-Host "      ================================================" -ForegroundColor Red
    Write-Host "       PERMANENT DELETE — Archive Folder Cleanup" -ForegroundColor Red
    Write-Host "       This action will hard-delete ALL items in the" -ForegroundColor White
    Write-Host "       selected archive folder. They cannot be recovered." -ForegroundColor White
    Write-Host ""
    Write-Host "       Only the selected archive folder is targeted." -ForegroundColor White
    Write-Host "       Primary mailbox folders are never touched." -ForegroundColor White
    Write-Host "      ================================================" -ForegroundColor Red
    Write-Host ""
    $archWarnResponse = Read-Host "      Understood — proceed to archive folder selection? [Y/N]"
    Write-Host ""
    if ($archWarnResponse -notmatch '^[Yy]') {
        Write-Host "  Archive cleanup cancelled. No changes made.`n" -ForegroundColor Cyan
        $modeLoopActive = $true
        continue
    }

    Write-Detail "Connecting to Security & Compliance..." Cyan
    try {
        Connect-IPPSSession -EnableSearchOnlySession -ErrorAction Stop -WarningAction SilentlyContinue 6>$null
        Write-Detail "Security & Compliance: connected" Green
    } catch {
        Write-Detail "ERROR: Could not connect to Security & Compliance. $_" Red
        $modeLoopActive = $true
        continue
    }
```

- [ ] **Step 2: Add archive folder picker loop**

Continuing directly inside `if ($archiveCleanupMode)`:

```powershell
    $archiveLoopActive = $true
    while ($archiveLoopActive) {
        $archiveLoopActive = $false

        # Refresh archive folder stats each loop so sizes reflect previous purge
        $allArchiveFolders = Get-MailboxFolderStatistics -Identity $Mailbox -Archive
        $archiveTotalBytes = ConvertTo-Bytes $archiveStats.TotalItemSize

        Write-Host ""
        Write-Detail ("In-Place Archive   : {0}  ({1:N0} items)" -f (Format-Size $archiveTotalBytes), $archiveStats.ItemCount) `
            $(if ($archiveTotalBytes -ge 50GB) { 'Red' } elseif ($archiveTotalBytes -ge 10GB) { 'Yellow' } else { 'Green' })
        Write-Host ""

        # Archive folder list — exclude root and RecoverableItems; filter > 1 GB; sort largest first
        $archiveFolders = $allArchiveFolders |
            Where-Object {
                $_.FolderType -ne 'Root' -and
                $_.FolderType -notlike 'RecoverableItems*' -and
                (ConvertTo-Bytes $_.FolderAndSubfolderSize) -gt $PRIMARY_FOLDER_SIZE_THRESHOLD
            } |
            Sort-Object { ConvertTo-Bytes $_.FolderAndSubfolderSize } -Descending

        if (-not $archiveFolders -or $archiveFolders.Count -eq 0) {
            Write-Detail "No archive folders exceed 1 GB. Nothing to target." Yellow
            Write-Host ""
            $modeLoopActive = $true
            continue
        }

        Write-Detail "Select an archive folder to purge (or [Q] to return to main menu):" White
        Write-Host ""
        $archNameColWidth = [Math]::Max(($archiveFolders | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum + 2, 20)
        $idx = 1
        foreach ($f in $archiveFolders) {
            $fBytes = ConvertTo-Bytes $f.FolderAndSubfolderSize
            $fPct   = if ($archiveTotalBytes -gt 0) { ($fBytes / $archiveTotalBytes) * 100 } else { 0 }
            $fColor = if     ($fPct -ge 60) { 'Red' }
                      elseif ($fPct -ge 20) { 'DarkYellow' }
                      elseif ($fPct -ge 5)  { 'Yellow' }
                      else                   { 'Gray' }
            Write-Host ("      [{0}]  {1} {2,8} items   {3}" -f $idx, $f.Name.PadRight($archNameColWidth), $f.ItemsInFolderAndSubfolders, (Format-Size $fBytes)) -ForegroundColor $fColor
            $idx++
        }
        Write-Host ""

        $selectedArchiveFolder = $null
        while ($null -eq $selectedArchiveFolder) {
            $archiveChoice = Read-Host "      Choice"
            if ($archiveChoice -match '^[Qq]') {
                Write-Host ""
                $modeLoopActive = $true
                break
            }
            $archiveIndex = 0
            if ([int]::TryParse($archiveChoice, [ref]$archiveIndex) -and
                $archiveIndex -ge 1 -and $archiveIndex -le $archiveFolders.Count) {
                $selectedArchiveFolder = $archiveFolders[$archiveIndex - 1]
            } else {
                Write-Detail "Invalid selection. Enter a number between 1 and $($archiveFolders.Count), or Q to return." Yellow
            }
        }
        if ($null -eq $selectedArchiveFolder) { continue }

        $selArchiveBytes = ConvertTo-Bytes $selectedArchiveFolder.FolderAndSubfolderSize
        Write-Host ""
        Write-Detail ("Selected: {0}  ({1:N0} items / {2})" -f `
            $selectedArchiveFolder.Name, $selectedArchiveFolder.ItemsInFolderAndSubfolders, (Format-Size $selArchiveBytes)) White
        $archivePurgeConfirm = Read-Host "      Proceed with HardDelete purge of all items in this archive folder? [Y/N]"
        Write-Host ""
        if ($archivePurgeConfirm -notmatch '^[Yy]') {
            Write-Detail "Purge cancelled. Returning to archive folder list." Yellow
            $archiveLoopActive = $true
            continue
        }
```

- [ ] **Step 3: Validate syntax**

```powershell
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1',
    [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red } } else { Write-Host 'No syntax errors.' -ForegroundColor Green }
```

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat(mailbox-cleanup): implement [A] mode hold checks, banners, and archive folder picker"
```

---

### Task 6: [A] mode — compliance search, HardDelete, and post-folder loop

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

This continues inside the `while ($archiveLoopActive)` block from Task 5, after the purge confirmation prompt.

- [ ] **Step 1: Add compliance search + HardDelete block**

```powershell
        # folderid: compliance search — archive-only, never touches primary mailbox
        $archiveSearchName = $null
        $archiveSearch     = $null
        try {
            $archiveAlias      = ($Mailbox -split '@')[0]
            $archiveSafeName   = $selectedArchiveFolder.Name -replace '[^A-Za-z0-9]', ''
            $archiveTimestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
            $archiveSearchName = "ArchiveCleanup-$archiveAlias-$archiveSafeName-$archiveTimestamp"

            $convertedFolderId = ConvertTo-ComplianceFolderId -FolderId $selectedArchiveFolder.FolderId
            if ($null -eq $convertedFolderId) {
                throw "Could not convert archive folder ID for '$($selectedArchiveFolder.Name)' to compliance search format. Archive cleanup aborted — primary mailbox is unaffected."
            }

            Write-Detail "Archive folder ID  : verified — targeting archive folder exclusively" Green
            Write-Detail "Compliance search  : $archiveSearchName" Gray

            New-ComplianceSearch -Name $archiveSearchName `
                -ExchangeLocation $Mailbox `
                -ContentMatchQuery "folderid:$convertedFolderId" `
                -ErrorAction Stop | Out-Null

            Start-ComplianceSearch -Identity $archiveSearchName -ErrorAction Stop

            $elapsed = 0
            do {
                Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
                $elapsed += $POLL_INTERVAL_SECONDS
                $archiveSearch = Get-ComplianceSearch -Identity $archiveSearchName
                Write-Detail "Searching... (${elapsed}s) - $($archiveSearch.Status)"
            } while ($archiveSearch.Status -notin @('Completed', 'Failed'))

            if ($archiveSearch.Status -eq 'Failed') {
                throw "Compliance search '$archiveSearchName' failed. Check the Security & Compliance portal."
            }

            Write-Detail ("Search complete — {0:N0} items found ({1})" -f `
                $archiveSearch.Items, (Format-Size $archiveSearch.Size)) Green

            if ($archiveSearch.Items -eq 0) {
                Write-Host ""
                Write-Detail "0 items found. The folder may be protected by an active hold," Yellow
                Write-Detail "or the folderid conversion may not match this module version." Yellow
                Write-Detail "No purge action will run — primary mailbox is unaffected." Gray
                $archiveCleanupResults += [PSCustomObject]@{
                    FolderName = $selectedArchiveFolder.Name
                    Items      = 0
                    SizeBytes  = 0
                    Status     = 'NoItems'
                }
            } else {
                Write-Detail "Running purge (HardDelete)..." Yellow

                New-ComplianceSearchAction -SearchName $archiveSearchName `
                    -Purge -PurgeType HardDelete -Confirm:$false -ErrorAction Stop | Out-Null

                $archiveActionName = "$archiveSearchName`_Purge"
                $elapsed = 0
                do {
                    Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
                    $elapsed += $POLL_INTERVAL_SECONDS
                    $archiveAction = Get-ComplianceSearchAction -Identity $archiveActionName
                    Write-Detail "Purging... (${elapsed}s) - $($archiveAction.Status)"
                } while ($archiveAction.Status -notin @('Completed', 'Failed'))

                if ($archiveAction.Status -eq 'Failed') {
                    throw "Compliance purge '$archiveActionName' failed. Check the Security & Compliance portal."
                }

                Write-Detail "Purge complete." Green

                Write-Host ""
                Write-Host "      ================================================" -ForegroundColor DarkCyan
                Write-Host "       Results" -ForegroundColor White
                Write-Detail ("  Folder : {0} (Archive)" -f $selectedArchiveFolder.Name) White
                Write-Detail ("  Purged : {0:N0} items  ({1})" -f $archiveSearch.Items, (Format-Size $archiveSearch.Size)) Green
                Write-Host "      ================================================" -ForegroundColor DarkCyan
                Write-Host ""

                $archiveCleanupResults += [PSCustomObject]@{
                    FolderName = $selectedArchiveFolder.Name
                    Items      = $archiveSearch.Items
                    SizeBytes  = $archiveSearch.Size
                    Status     = 'Purged'
                }
            }

        } catch {
            Write-Host "`n      ERROR: $_" -ForegroundColor Red
            $archiveCleanupResults += [PSCustomObject]@{
                FolderName = if ($selectedArchiveFolder) { $selectedArchiveFolder.Name } else { 'Unknown' }
                Items      = 0
                SizeBytes  = 0
                Status     = 'Failed'
            }
        } finally {
            if ($archiveSearchName) {
                try {
                    Remove-ComplianceSearch -Identity $archiveSearchName -Confirm:$false -ErrorAction Stop
                    Write-Detail "Compliance search deleted." Green
                } catch {
                    Write-Detail "WARNING: Could not delete compliance search '$archiveSearchName'. Delete it from the Security & Compliance portal." Yellow
                }
            }
        }
```

- [ ] **Step 2: Add post-folder loop menu and close all open blocks**

```powershell
        Write-Host ""
        Write-Host "      What would you like to do next?" -ForegroundColor White
        Write-Host "        [A] Target another archive folder" -ForegroundColor Gray
        Write-Host "        [M] Back to main menu" -ForegroundColor Gray
        Write-Host "        [Q] Quit" -ForegroundColor Gray
        Write-Host ""
        $archiveLoopChoice = Read-Host "      Choice"
        Write-Host ""

        switch -Regex ($archiveLoopChoice) {
            '^[Aa]' { $archiveLoopActive = $true }
            '^[Mm]' { $modeLoopActive    = $true }
            default { }
        }

    } # end archive loop

    continue
} # end archiveCleanupMode
```

- [ ] **Step 3: Validate syntax**

```powershell
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1',
    [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red } } else { Write-Host 'No syntax errors.' -ForegroundColor Green }
```

- [ ] **Step 4: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat(mailbox-cleanup): implement [A] compliance search, HardDelete, and post-folder loop"
```

---

### Task 7: Navigation overhaul — Write-TicketReport function + post-action menu

This task restructures the script's exit flow. Current: all paths either call `exit` or fall through to an inline ticket export. New: all non-error paths land at a unified post-action menu. Key change: the mode loop and post-action menu are wrapped in an outer `while ($continueScript)` loop so `[M]` can re-enter the mode selection without restarting the script.

**Files:**
- Modify: `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`

- [ ] **Step 1: Add Write-TicketReport function to helpers block**

Add after `ConvertTo-ComplianceFolderId`, before `# --- Main ---`. This function reads script-scope variables directly — no parameters needed since PowerShell functions share the enclosing script scope.

```powershell
function Write-TicketReport {
    $reportAlias = ($Mailbox -split '@')[0]
    $reportFile  = "$([System.Environment]::GetFolderPath('Desktop'))\MailboxCleanup-$reportAlias-$reportTimestamp.txt"

    $modeLabel = if     ($mfaOnlyMode)       { 'MFA Only' }
                 elseif ($folderCleanupMode)  { 'Folder Cleanup' }
                 elseif ($archiveCleanupMode) { 'Archive Cleanup' }
                 elseif ($statusOnlyMode)     { 'Status Only' }
                 else                          { 'Full Cleanup' }

    $sep  = "=" * 60
    $dash = "-" * 60
    $report = @(
        $sep
        " MAILBOX CLEANUP REPORT"
        $sep
        " Date   : $reportTime"
        " Target : $Mailbox"
        " Mode   : $modeLabel"
        ""
        $dash
        " PRE-FLIGHT"
        $dash
        (" Recoverable Items  : {0} / {1} ({2}% full)" -f (Format-Size $usedBytes), (Format-Size $limitBytes), $pct)
        (" SingleItemRecovery : {0}" -f $(if ($sirEnabledOriginal) { 'Enabled' } else { 'DISABLED' }))
        (" RetentionHold      : {0}" -f $(if ($retentionHoldEnabled) { 'ENABLED (MFA will not reclaim space while active)' } else { 'False' }))
        (" Holds active       : {0}" -f $holdDisplay)
    )
    if ($mbx.InPlaceHolds -and $mbx.InPlaceHolds.Count -gt 0) {
        $mbx.InPlaceHolds | ForEach-Object { $report += "     - $_" }
    }
    $report += " Folder breakdown   :"
    if ($folderBreakdown) {
        $rptColWidth = [Math]::Max(($folderBreakdown | ForEach-Object { $_.FolderPath.Length } | Measure-Object -Maximum).Maximum + 2, 30)
        $folderBreakdown | ForEach-Object {
            $report += ("   {0} {1,8} items   {2}" -f $_.FolderPath.PadRight($rptColWidth), $_.ItemsInFolder, $_.FolderAndSubfolderSize)
        }
    }
    $report += @(
        ""
        $dash
        " RESULTS"
        $dash
        (" Before : {0} / {1} ({2}% full)" -f (Format-Size $usedBytes), (Format-Size $limitBytes), $pct)
    )
    if ($search -and $search.Items -gt 0) {
        $report += (" Purged : {0:N0} items  ({1} compliance-hold storage freed)" -f $search.Items, (Format-Size $search.Size))
    }
    if ($null -ne $afterBytes) {
        $report += (" After  : {0} / {1} ({2}%)*" -f (Format-Size $afterBytes), (Format-Size $limitBytes), $afterPct)
        $report += " * Exchange reclaims space within ~1h after MFA runs"
    }
    $report += @(
        ""
        $dash
        " CLEANUP ACTIONS"
        $dash
        (" Purview exception left in place  : {0}" -f $(if ($purviewExceptionActive)   { 'Yes — remove when cleanup confirmed' } else { 'No / N-A' }))
        (" Purview exception removed        : {0}" -f $(if ($policyRestored)           { 'Yes' } else { 'No' }))
        (" Delay hold cleared               : {0}" -f $(if ($delayHoldCleared)         { 'Yes' } else { 'No (not present)' }))
        (" Delay release hold cleared       : {0}" -f $(if ($delayReleaseHoldCleared)  { 'Yes' } else { 'No (not present)' }))
        (" Late delay hold cleared          : {0}" -f $(if ($lateDelayHoldCleared)     { 'Yes — Exchange applied async after policy exception removed' } else { 'No' }))
        (" SIR disabled this run            : {0}" -f $(if ($sirWasDisabledByScript)   { 'Yes — re-enable after quota recovers' } else { 'No' }))
        (" SIR re-enabled this run          : {0}" -f $(if ($sirRestored)              { 'Yes' } else { 'No' }))
        (" Managed Folder Assistant triggered: {0}" -f $(if ($mfaTriggered)            { 'Yes' } else { 'No' }))
        (" MFA re-triggered (late hold)     : {0}" -f $(if ($mfaRetriggered)           { 'Yes' } else { 'No' }))
        ""
        $dash
        " OUTCOME"
        $dash
    )
    if (-not $aborted -and -not $errorOccurred) {
        if ($statusOnlyMode) {
            $report += " Status check complete. No changes made."
        } elseif ($folderCleanupMode -or $archiveCleanupMode) {
            $report += " Cleanup complete. See folder/archive sections above for details."
        } else {
            $actionLabel = if ($mfaOnlyMode) { "MFA re-triggered." } else { "Purge complete. MFA triggered." }
            $waitStr     = if ($mfaWait)     { " Space reclaims within $mfaWait." } else { "" }
            $report += " $actionLabel$waitStr"
            if ($sirWasDisabledByScript) {
                $report += " Re-run script on $Mailbox to re-enable SingleItemRecovery once quota recovers."
            }
        }
    } elseif ($aborted) {
        $report += " Aborted by operator. No items were purged."
    } else {
        $report += " Completed with errors. Review console output for details."
    }
    if ($folderCleanupResults.Count -gt 0) {
        $report += @("", $dash, " FOLDER CLEANUP", $dash)
        foreach ($r in $folderCleanupResults) {
            if ($r.Status -eq 'Purged') {
                $report += (" {0,-30} : {1:N0} items purged  ({2}) — HardDelete" -f `
                    $r.FolderName, $r.Items, (Format-Size $r.SizeBytes))
            } else {
                $report += (" {0,-30} : Failed — check console output" -f $r.FolderName)
            }
        }
    }
    if ($archiveCleanupResults.Count -gt 0) {
        $report += @("", $dash, " ARCHIVE CLEANUP", $dash)
        foreach ($r in $archiveCleanupResults) {
            if ($r.Status -eq 'Purged') {
                $report += (" {0,-30} : {1:N0} items purged  ({2}) — HardDelete" -f `
                    $r.FolderName, $r.Items, (Format-Size $r.SizeBytes))
            } elseif ($r.Status -eq 'NoItems') {
                $report += (" {0,-30} : 0 items found — folder may be hold-protected or folderid conversion failed" -f $r.FolderName)
            } else {
                $report += (" {0,-30} : Failed — check console output" -f $r.FolderName)
            }
        }
    }
    $report += $sep

    $report | Out-File -FilePath $reportFile -Encoding UTF8
    Write-Host ""
    Write-Host "      Report saved to: $reportFile" -ForegroundColor Green
    Write-Host ""
}
```

- [ ] **Step 2: Fix [S] status-only mode — remove exit 0**

Find the [S] status-only handler (around line 402):
```powershell
if ($statusOnlyMode) {
    $exitMsg = if ($sirRestored) { "SingleItemRecovery re-enabled. Status check complete." } else { "Status check complete. No changes were made." }
    Write-Host "  $exitMsg`n" -ForegroundColor Cyan
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 0
}
```

Replace with (no disconnect, no exit — falls through to post-action menu):
```powershell
if ($statusOnlyMode) {
    $exitMsg = if ($sirRestored) { "SingleItemRecovery re-enabled. Status check complete." } else { "Status check complete. No changes were made." }
    Write-Host "  $exitMsg`n" -ForegroundColor Cyan
}
```

- [ ] **Step 3: Wrap mode loop in outer continueScript loop**

Find the mode loop declaration (around line 366):
```powershell
# --- Mode loop — allows [F] post-purge [M] to return here ---
$modeLoopActive = $true
while ($modeLoopActive) {
```

Replace with:
```powershell
# --- Outer loop — allows post-action [M] to return to mode selection ---
$continueScript = $true
while ($continueScript) {
    $continueScript = $false

# --- Mode loop — allows [F]/[A] post-purge [M] to return here ---
$modeLoopActive = $true
while ($modeLoopActive) {
```

- [ ] **Step 4: Add post-action menu and close outer loop — replace inline ticket export**

Find the closing `} # end mode loop` line (around line 960) through the end of the session cleanup block (around line 1067). Replace everything from `} # end mode loop` onward (but before the `# --- Future enhancement notes ---` comment) with:

```powershell
} # end mode loop

# --- Post-action menu ---
Write-Host ""
Write-Host "      What would you like to do next?" -ForegroundColor White
Write-Host "        [R] Export report and quit" -ForegroundColor Gray
Write-Host "        [M] Back to main menu" -ForegroundColor Gray
Write-Host "        [Q] Quit without exporting" -ForegroundColor Gray
Write-Host ""
$postChoice = Read-Host "      Choice"
Write-Host ""

switch -Regex ($postChoice) {
    '^[Rr]' {
        Write-TicketReport
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
    }
    '^[Mm]' {
        $continueScript = $true
    }
    default {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
    }
}

} # end outer continueScript loop
```

- [ ] **Step 5: Validate syntax**

```powershell
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1',
    [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red } } else { Write-Host 'No syntax errors.' -ForegroundColor Green }
```

- [ ] **Step 6: Manual end-to-end navigation test**

Run the script against any mailbox. Verify each path:

1. **[S] → post-action menu:** Select [S], confirm "Status check complete" message, then post-action menu appears. [M] returns to mode selection. [Q] disconnects and exits.
2. **[C] or [M] run → post-action menu:** Run a mode, confirm it completes, post-action menu appears. [R] exports report to Desktop and disconnects. [M] returns to mode selection without disconnecting. [Q] disconnects without exporting.
3. **[F] then [Q] → post-action menu:** Run folder cleanup, at post-folder [Q], confirm post-action menu appears (not immediate exit).
4. **[M] back to menu keeps session alive:** After [M] in post-action, mode menu appears, select [S], confirm no reconnect message (session was already open).

- [ ] **Step 7: Commit**

```bash
git add tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1
git commit -m "feat(mailbox-cleanup): navigation overhaul — Write-TicketReport function, unified post-action menu, outer continueScript loop"
```

---

### Task 8: Push to testing branch and update hub downloads.json

**Files:**
- Modify: `downloads.json`

- [ ] **Step 1: Bump version in downloads.json**

Find the mailbox-cleanup entry in `downloads.json` and update version to `2.0` and date to `2026-06`:

```json
{
  "id": "mailbox-cleanup",
  "version": "2.0",
  "releaseDate": "2026-06",
  ...
}
```

- [ ] **Step 2: Validate syntax**

```powershell
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1',
    [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red } } else { Write-Host 'No syntax errors.' -ForegroundColor Green }
```

- [ ] **Step 3: Full end-to-end smoke test against prabhu**

Run the script against `prabhu.nithyanantharaj@corrohealth.com`:
1. Phase 2 shows `[Active Mailbox]` and `[In-Place Archive]` sections with the 97.9 GB advisory
2. Select `[A]` — PERMANENT DELETE banner appears with "Only the selected archive folder is targeted"
3. Archive folder picker shows color-scaled list (Inbox at top, ~79 GB red)
4. Select Inbox → confirm → compliance search runs with `folderid:` query
5. Results banner shows items purged
6. Post-folder menu: select `[M]` → mode menu reappears (session still live)
7. Select `[S]` → status check → post-action menu → `[R]` → report on Desktop → disconnect

- [ ] **Step 4: Commit and push to testing**

```bash
git add downloads.json
git commit -m "feat(mailbox-cleanup): v2.0 — archive cleanup mode, navigation overhaul"
git push origin testing
```
