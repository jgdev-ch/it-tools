# Archive Cleanup Mode + Navigation Overhaul — Design Spec

**Date:** 2026-06-30  
**Script:** `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`  
**Version target:** v2.0  

---

## Background

The mailbox cleanup script handles three scenarios today: full Recoverable Items cleanup ([C]), MFA re-trigger ([M]), and primary mailbox folder purge ([F]). A gap exists for In-Place Archive bloat — users (particularly F3 license holders with a 2 GB primary mailbox) can accumulate tens or hundreds of GB in their archive with no cleanup path in the script. Additionally, all current mode endings terminate the script or fall through to ticket export, forcing techs to relaunch from the batch file to perform additional work.

This spec covers two changes: adding [A] archive cleanup mode and redesigning post-action navigation to allow techs to loop back to the main menu.

---

## Change 1 — Phase 2 Status Display Redesign

### Current behavior
Phase 2 shows a single block of primary mailbox stats: Recoverable Items quota, SIR, RetentionHold, holds, folder breakdown, MFA history, Purview exception status.

### New behavior
Phase 2 splits into two clearly labeled sections.

**[Active Mailbox]** — identical to current output, no functional change.

**[In-Place Archive]** — new section appended after the active mailbox block:
- Total archive size and item count from `Get-MailboxStatistics -Identity $Mailbox -Archive`
- Top-level folder breakdown (folders > 0 items) from `Get-MailboxFolderStatistics -Identity $Mailbox -Archive`, sorted largest first, same color-scaling as the Recoverable Items folder breakdown (gray / yellow / orange / red scaled against archive total size)
- If no archive is provisioned: `No In-Place Archive provisioned.` (Gray)
- If archive exceeds 10 GB: advisory line in Yellow — `Archive is large — consider [A] Archive Cleanup from the main menu.`

**Archive threshold constant:** `$ARCHIVE_SIZE_ADVISORY_THRESHOLD = 10GB` — added to the constants block.

---

## Change 2 — [A] Archive Cleanup Mode

### Menu entry
```
  [A] Archive cleanup     — purge contents of an In-Place Archive folder
```
Added to the mode menu between [F] and [S].

### Mode state variable
`$archiveCleanupMode = $false` — added to the state block alongside `$folderCleanupMode`.

### Flow

**Step 1 — Hold check**  
Reuses `$mbx` data already fetched in Phase 2. No additional Exchange call needed.

- If `$mbx.LitigationHoldEnabled`: display the same hard red litigation hold banner as the primary path. Set `$archiveCleanupMode = $false`, `continue` back to mode loop. Do not proceed.
- If `$mbx.InPlaceHolds.Count -gt 0`: display a yellow warning banner before the folder picker:
  ```
  ================================================
   WARNING — Active Retention Holds Detected
   Items under active holds may be protected.
   Compliance search results may be partial.
   Confirm folder contents before proceeding.
  ================================================
  ```
  Tech can proceed — this is advisory, not a hard block.

**Step 2 — Warning banner**  
Identical PERMANENT DELETE banner as [F] mode. Requires Y to proceed; N returns to mode loop.

**Step 3 — Archive folder picker**  
- Fetch: `Get-MailboxFolderStatistics -Identity $Mailbox -Archive`
- Filter: exclude root, folders with 0 items, and folders smaller than `$PRIMARY_FOLDER_SIZE_THRESHOLD` (1 GB)
- Sort: largest first
- Display: same color-scaled numbered list as [F] mode, with archive total size header above
- [Q] at selection prompt returns to main menu (`$modeLoopActive = $true`, `continue`)

If no archive folders exceed 1 GB: `No archive folders exceed 1 GB. Nothing to target.` Return to mode loop.

**Step 4 — Confirmation**  
Same per-folder confirm prompt as [F]: `Proceed with HardDelete purge of all items in this folder? [Y/N]`

**Step 5 — Compliance search + HardDelete**  

Search name pattern: `ArchiveCleanup-<alias>-<foldersafename>-<timestamp>`

**Query strategy — folderid: is the only acceptable approach:**

`folderpath:` queries match same-named folders across BOTH the primary mailbox and the archive in a single compliance search. This means `folderpath:"Inbox"` would HardDelete items from the live primary Inbox alongside the archive Inbox. This is not an acceptable risk for [A] mode — the archive cleanup must exclusively touch archive folders, never the primary mailbox.

`folderid:` queries reference a single folder by its unique Exchange identifier. The archive Inbox and the primary Inbox have completely different FolderIds at the storage layer. A `folderid:` query targeting an archive folder is physically incapable of matching any primary mailbox folder, regardless of name.

**Implementation requirement:**
- Retrieve archive folder ID: `Get-MailboxFolderStatistics -Identity $Mailbox -Archive` → `.FolderId` property
- Convert to compliance search format (Base64 re-encoding — exact conversion to be validated in implementation, as EXO v3 REST mode returns FolderIds in a different byte format than legacy RPS mode)
- Use `ContentMatchQuery = "folderid:<converted-id>"`

**If folderid: conversion cannot be made to work in REST mode:** [A] mode aborts with a clear error message explaining that safe archive-only targeting is unavailable in the current module version. The tech is directed to raise it as a known limitation. `folderpath:` is NOT used as a fallback — cross-contamination of an active mailbox is worse than the feature not working.

Mechanics (same as [F] mode once folderid: is resolved):
- `New-ComplianceSearch` with `ExchangeLocation = $Mailbox`, `ContentMatchQuery = "folderid:<id>"`
- `Start-ComplianceSearch`, poll until Completed/Failed
- `New-ComplianceSearchAction -Purge -PurgeType HardDelete`
- Poll until Completed/Failed
- `Remove-ComplianceSearch` in finally block

**No additional Exchange operations:** No SIR management, no Purview exception, no delay hold clearing, no MFA trigger. Archive folders contain regular email items — compliance search HardDelete is the complete cleanup path.

**Step 6 — Post-folder loop**  
```
  [A] Target another archive folder
  [M] Back to main menu
  [Q] Continue to post-action menu
```

### Results tracking
`$archiveCleanupResults = @()` — parallel to `$folderCleanupResults`. Each entry:
```powershell
[PSCustomObject]@{
    FolderName = $selectedFolder.Name
    Items      = $folderSearch.Items
    SizeBytes  = $folderSearch.Size
    Status     = 'Purged'  # or 'Failed'
}
```

---

## Change 3 — Post-Action Navigation Overhaul

### Problem
All current non-error endings either exit the script or fall through to the inline ticket export prompt, requiring a full relaunch for additional work.

### New post-action menu
Every non-error path end lands at a unified post-action menu:

```
  What would you like to do next?
    [R] Export report and quit
    [M] Back to main menu
    [Q] Quit without exporting
```

**[R]** — runs the existing ticket export logic (currently inline at end of script), then disconnects and exits.  
**[M]** — sets `$modeLoopActive = $true`, `continue`. Returns to mode selection. Does NOT disconnect Exchange — session stays open.  
**[Q]** — skips export, disconnects, exits.

### Paths affected

| Current behavior | New behavior |
|---|---|
| [S] status-only → `exit 0` | [S] → post-action menu |
| [C]/[M] runs → inline export prompt → exit | [C]/[M] → post-action menu |
| [F] post-folder: [A]/[M]/[Q] → inline export → exit | [F] post-folder: [A]/[M]/[Q=post-action menu] |
| [A] post-folder: [A]/[M]/[Q] → post-action menu | (new, consistent with above) |

### Paths that still exit hard (unchanged)
- EXO connection failure → `exit 1`
- Mailbox not found → `exit 1`
- Litigation hold detected → mode blocked, returns to mode loop (not a hard exit — tech can still use other modes or export)
- Module install failure → `exit 1`

### Session lifecycle
`Disconnect-ExchangeOnline` moves from its current inline position to the [R] and [Q] exit paths only. The [M] path keeps the session alive for the next mode run.

---

## Ticket Report Updates

### Mode label
Report header `Mode:` field gains two new values: `Archive Cleanup` and `Status Only`.

### New ARCHIVE CLEANUP section
Appended after FOLDER CLEANUP section if `$archiveCleanupResults.Count -gt 0`:

```
------------------------------------------------------------
 ARCHIVE CLEANUP
------------------------------------------------------------
 Inbox                          : 12,847 items purged  (15.2 GB) — HardDelete
 Deleted Items                  :  3,201 items purged   (4.1 GB) — HardDelete
```

Failed folders: `{FolderName,-30} : Failed — check console output`

---

## Constants Added

```powershell
$ARCHIVE_SIZE_ADVISORY_THRESHOLD = 10GB   # triggers advisory in Phase 2 archive section
```

`$PRIMARY_FOLDER_SIZE_THRESHOLD` (existing, 1 GB) is reused as the archive folder filter threshold in [A] mode — no new constant needed. If the name feels misleading after this change, it can be renamed to `$FOLDER_SIZE_THRESHOLD` during implementation.

---

## State Variables Added

```powershell
$archiveCleanupMode    = $false
$archiveCleanupResults = @()
```

---

## Version Bump

`$SCRIPT_VERSION = "2.0"` — navigation overhaul + [A] mode is a substantial enough change to warrant a major version bump.

---

## Out of Scope

- Archive deprovisioning (`Disable-Mailbox -Archive`) — policy review pending
- Unindexed item handling in archive (same limitation as primary [F] mode — MimeCast sync content is opaque to compliance search)
- Multiple retention policy exception management
