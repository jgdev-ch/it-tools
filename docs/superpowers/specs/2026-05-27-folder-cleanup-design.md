# Folder Cleanup Feature — Design Spec
**Date:** 2026-05-27
**Script:** `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`
**Feature:** [F] Folder cleanup mode — primary mailbox folder targeting via compliance search

---

## Overview

Adds a new `[F]` mode to the Mailbox Cleanup Tool that allows techs to permanently purge the contents of a specific primary mailbox folder. Targets the **primary mailbox quota** (the visible 99 GB bucket users see in Outlook storage), completely separate from the Recoverable Items quota the existing `[C]` and `[M]` modes address.

Primary use cases:
- Third-party sync folders bloated by archiving tools (e.g. MimeCast, 60+ GB)
- Deleted Items (recycle bin) accumulation visible in primary quota
- User-created folders that have grown excessively large
- Any primary folder the user cannot self-delete due to quota restrictions

---

## Prerequisites

Same as existing script:
- **Exchange Administrator** — mailbox stats, folder statistics
- **Compliance Administrator** — IPPSSession, compliance search + purge

No new role requirements. Outlook does not need to be closed — purge operates entirely server-side through the compliance center.

---

## Mode Menu Change

Add `[F]` as a peer option alongside `[C]` and `[M]`:

```
What would you like to do?
  [C] Full cleanup   — compliance search, purge, and MFA
  [M] MFA only       — re-check SIR, clear delay holds, and re-trigger MFA
  [F] Folder cleanup — permanently purge contents of a primary mailbox folder
  [S] Status only    — exit here, no changes made
  [Q] Quit
```

---

## Flow

### 1. Warning Banner (hard gate)

Before any connection to Security & Compliance, display a prominent banner and require Y to proceed:

```
================================================
 PERMANENT DELETE — Folder Cleanup
 This action will hard-delete ALL items in the
 selected folder. They cannot be recovered.

 Confirm with the user that the folder contents
 are safe to permanently delete before proceeding.
================================================
```

- Y → continue
- N → exit cleanly, no changes made, no S&C connection attempted

### 2. Connect Security & Compliance

Connect via `Connect-IPPSSession -EnableSearchOnlySession` (same as [C] path). If connection fails, exit with error — no folder list is shown.

### 3. Primary Quota Display

Fetch primary mailbox size via `Get-MailboxStatistics` and display above the folder list so the tech knows what quota they are working against:

```
Primary Mailbox    : 83.1 GB / 99.0 GB (83% full)
```

Primary quota limit sourced from `$mbx.ProhibitSendReceiveQuota` (already fetched in Phase 2).

### 4. Folder List

Fetch all primary mailbox folders via `Get-MailboxFolderStatistics -Identity $Mailbox` (no `-FolderScope` — returns primary mailbox only, not Recoverable Items).

Filter to folders where size > 1 GB. Display as a numbered list with color scaling applied against the **primary mailbox quota**:

| Threshold (% of primary quota) | Color |
|---|---|
| ≥ 60% | Red |
| ≥ 20% | DarkYellow (orange) |
| ≥ 5% | Yellow |
| < 5% | Gray (excluded by 1 GB filter in practice) |

Annotation: `/Deletions`-equivalent soft-delete folders annotated as `← large soft-delete backlog` when ≥ 20%.

Example output:
```
Select a folder to purge:

  [1]  Deleted Items          572 items    88.8 MB
  [2]  MimeCast            1000000 items    62.8 GB   ← red
  [3]  Inbox                 4821 items     3.2 GB    ← yellow
```

If no folders exceed 1 GB, display a message and return to the main menu.

### 5. Folder Selection

Tech enters a number. Script validates input — if invalid, re-prompts. On valid selection, echo back the chosen folder with size and item count:

```
Selected: MimeCast  (1,000,000 items / 62.8 GB)
Proceed with HardDelete purge of all items in this folder? [Y/N]:
```

Y proceeds to purge. N returns to the folder list.

### 6. Folder ID Encoding

Exchange folder IDs (base64) must be hex-encoded for `folderid:` compliance search queries. A new helper function `ConvertTo-FolderQueryString` handles this conversion:

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

### 7. Compliance Search + Purge

Same pattern as [C] Phase 5. Search name includes the sanitised folder name for traceability in the Purview portal:

```
FolderCleanup-<alias>-<foldername>-<timestamp>
```

- `New-ComplianceSearch` with `folderid:` query scoped to selected folder
- `Start-ComplianceSearch` + poll loop (30s intervals)
- Display item count and size on completion
- `New-ComplianceSearchAction -Purge -PurgeType HardDelete`
- Poll purge action until Completed or Failed
- `Remove-ComplianceSearch` always runs (finally block) regardless of outcome

Results display:
```
================================================
 Results
  Folder : MimeCast
  Purged : 1,000,000 items  (62.8 GB)
================================================
```

### 8. Post-Purge Loop

After each purge (or on failure), prompt:

```
What would you like to do next?
  [A] Target another folder
  [M] Back to main menu
  [Q] Quit
```

- `[A]` — re-fetches `Get-MailboxFolderStatistics` (fresh sizes post-purge) and returns to folder list
- `[M]` — returns to `[C/M/F/S/Q]` mode menu; tech can chain a folder cleanup into a full Recoverable Items cleanup in one session
- `[Q]` — exits cleanly, disconnects Exchange Online session

---

## State Tracking

New state for [F] mode:

```powershell
$folderCleanupMode    = $false
$folderCleanupResults = @()   # array of [PSCustomObject] per purge run
```

Each completed purge appends:
```powershell
[PSCustomObject]@{
    FolderName = $selectedFolder.Name
    Items      = $search.Items
    SizeBytes  = $search.Size
    Status     = 'Purged'   # or 'Failed' / 'Aborted'
}
```

---

## Ticket Report

[F] actions append a dedicated section to the existing ticket export:

```
------------------------------------------------------------
 FOLDER CLEANUP
------------------------------------------------------------
 MimeCast      : 1,000,000 items purged  (62.8 GB) — HardDelete
 Deleted Items :       572 items purged  (88.8 MB) — HardDelete
```

If no folder cleanups were run in the session, this section is omitted from the report.

---

## Error Handling

- IPPSSession connection failure → error message, return to main menu
- No folders exceed 1 GB → "No primary folders exceed 1 GB. Nothing to target." → return to main menu
- Invalid folder selection → re-prompt
- Compliance search failure → log error, cleanup search, offer loop menu
- Purge action failure → log error, cleanup search, offer loop menu
- All cleanup (Remove-ComplianceSearch) runs in finally block regardless of outcome

---

## Helper Function Placement

`ConvertTo-FolderQueryString` added to the helpers section alongside existing helpers (`Write-Step`, `Write-Detail`, `Format-Size`, `ConvertTo-Bytes`, `Get-RecoverableStats`, `Get-MfaWaitEstimate`, `Confirm-Continue`).

---

## Out of Scope

- Multi-folder selection in a single pass (can loop via [A] instead)
- Subfolder targeting — `folderid:` queries target the selected folder only, not subfolders. For flat folders (MimeCast, Deleted Items) this is sufficient. Recursive subfolder purge deferred to a future pass if needed.
- Recoverable Items subfolder targeting via [F] (those are handled by [C] and [M])
- SoftDelete purge type
- Scheduled / automated folder cleanup (deferred to Azure Automation runbook phase)
