# Mailbox Health Audit Script — Design Spec

**Date:** 2026-06-02  
**Status:** Approved, ready for implementation planning

---

## Purpose

A proactive, read-only PowerShell diagnostic script that surfaces mailboxes trending toward the cleanup-needed state before they require remediation. Gives IT admins a tenant-wide health picture — flagging the configuration levers (ElcProcessingDisabled, legacy holds, SIR risk, size thresholds) that prevent Exchange from self-cleaning. Designed as a standalone companion to `Invoke-MailboxCleanup.ps1`.

---

## Problem Statement

Mailboxes hit the 100 GB Recoverable Items threshold because several Exchange configuration flags silently prevent automatic cleanup from running. The Managed Folder Assistant skips mailboxes with `ElcProcessingDisabled = $true`. Legacy in-place holds from on-prem migrations pin items in `/DiscoveryHolds` indefinitely. The compliance engine re-enables Single Item Recovery after cleanup runs, stalling MFA. Without a tenant-wide view of these flags, IT has no way to proactively identify at-risk mailboxes or correct upstream settings before they become tickets.

This script is the PowerShell-native equivalent of the Exchange Audit web tool (spec: `2026-05-22-exchange-audit-design.md`) — delivering the same diagnostic picture without requiring Azure infrastructure.

---

## Scope

- **In scope:** Tenant-wide read-only mailbox diagnostics, configurable size thresholds, standalone-callable check functions, individual user deep-dive, batch drill-downs, CSV + TXT export
- **Out of scope:** Any remediation or mailbox modification, compliance search operations, folder-level statistics (folder-level analysis belongs in `Invoke-MailboxCleanup.ps1`)
- **Future:** Output from this script feeds directly into the Exchange Audit web tool once Azure Blob Storage is provisioned

---

## Required Roles

The admin account used to run the script must have:
- **Exchange Administrator** — required for `Get-Mailbox`, `Get-MailboxStatistics`, `Get-MailboxFolderStatistics`

No compliance/Security & Compliance connection required — this script is Exchange Online only.

---

## Required PowerShell Modules

- `ExchangeOnlineManagement` v3.9.0 or later (same module as `Invoke-MailboxCleanup.ps1`)

---

## Script Location

```
C:\dev\projects\it-tools\tools\mailbox-health-audit\Invoke-MailboxHealthAudit.ps1
```

---

## Script Constants

```powershell
$SCRIPT_VERSION         = "1.0"
$DEFAULT_RI_THRESHOLD_GB  = 20    # Default Recoverable Items warning threshold (GB)
$DEFAULT_PRIMARY_THRESHOLD_GB = 80  # Default primary mailbox warning threshold (GB)
$RI_QUOTA_GB            = 100     # Standard Recoverable Items quota (GB)
```

---

## Parameters

```powershell
param(
    [string]$TenantDomain   # Optional — pre-fills the Connect-ExchangeOnline prompt
)
```

---

## Architecture

Single file, ~500–700 lines. Named check functions are defined at the top of the script and can be called independently by dot-sourcing the file. The main wizard body calls them in sequence. Helper functions (`Write-Step`, `Write-Detail`, `Format-Size`) are shared with the cleanup script pattern.

```
[Helper Functions]           — Write-Step, Write-Detail, Format-Size, Get-HoldType
[Check Functions]            — Get-ElcDisabledMailboxes, Get-LegacyHoldMailboxes,
                               Get-LitigationHoldMailboxes, Get-SIRRiskMailboxes,
                               Get-RecoverableItemsStats, Get-MailboxRiskScore
[Main Wizard Body]           — Phases 1–5, mode menu, export
```

### Standalone Usage (dot-source)

```powershell
. .\Invoke-MailboxHealthAudit.ps1   # Load functions without running wizard
Connect-ExchangeOnline
Get-ElcDisabledMailboxes            # Call any check function directly
```

---

## Phases

### Phase 1 — Connect to Exchange Online

- Auto-installs `ExchangeOnlineManagement` if missing (same pattern as cleanup script)
- Prompts for tenant domain if `$TenantDomain` not supplied
- Displays script version and purpose banner before connecting

### Phase 2 — Scan Configuration

Presents scan options before any data is pulled:

**Scan depth:**
```
[F] Fast scan   — mailbox properties only (ElcProcessingDisabled, holds, SIR, primary size)
                  No folder statistics. Runs in 1–3 minutes on most tenants.
[R] Full scan   — Fast scan + Recoverable Items folder size per mailbox
                  Requires Get-MailboxFolderStatistics on every mailbox.
                  ⚠ WARNING: May take 20–40 minutes on large tenants.
```

**Size thresholds (optional — press Enter to skip each):**
```
Primary mailbox threshold (GB) [default: 80]:
Recoverable Items threshold (GB) [default: 20]:
```

Setting a threshold filters results to mailboxes that meet or exceed it on either metric. Both thresholds can be set independently. Leaving both blank scans all mailboxes.

### Phase 3 — Scan Execution

- Calls `Get-Mailbox -ResultSize Unlimited` to pull all mailboxes
- Applies check functions against each mailbox
- Displays a live progress counter: `Scanning mailboxes... [142 / 1,847]`
- For Full scan, batches `Get-MailboxFolderStatistics` calls with progress
- Applies size threshold filters after collection
- Builds a `$flaggedMailboxes` array with risk scores for all subsequent phases

### Phase 4 — Overview Results

Displays a summary table of flagged mailboxes, sorted by risk score descending:

```
 ════════════════════════════════════════════════════════════
  MAILBOX HEALTH OVERVIEW — 2026-06-02
  Scanned: 1,847 mailboxes   Flagged: 38
 ════════════════════════════════════════════════════════════

  ElcProcessingDisabled     :  12 mailboxes
  Legacy holds (non-UniH)   :   8 mailboxes
  Litigation hold (no TTL)  :   5 mailboxes
  SIR + high RI risk        :  19 mailboxes
  Primary size ≥ 80 GB      :  11 mailboxes
  Recoverable Items ≥ 20 GB :  22 mailboxes  [Full scan only]

 ────────────────────────────────────────────────────────────
  # Risk  UPN                              Primary   Rec.Items
  1 ████  user@domain.com                  91.2 GB   78.4 GB
  2 ███   user2@domain.com                 84.0 GB   61.1 GB
  3 ██    user3@domain.com                 72.5 GB   34.2 GB
  ...
```

Risk bar colors: Red (score 3–4), Yellow (score 2), White (score 1), Gray (score 0 — included if size threshold matched).

### Phase 5 — Mode Menu + Export

```
 ────────────────────────────────────────────────────────────
  [U] Individual user deep-dive
  [B] Batch check across flagged set
  [X] Export results and exit
  [Q] Exit without export
```

---

## Check Functions

Each function includes a comment header explaining what it checks, why it causes mailbox accumulation, and what the recommended action is. All functions return a consistent object shape for composition into the overview table and CSV export.

### Return Object Shape

```powershell
[PSCustomObject]@{
    DisplayName             = $mbx.DisplayName
    UPN                     = $mbx.UserPrincipalName
    PrimarySize_GB          = [decimal]
    RecoverableItems_GB     = [decimal]   # $null if Fast scan
    ElcProcessingDisabled   = [bool]
    LitigationHold          = [bool]
    LitigationHoldDuration  = [string]    # "Unlimited" or duration string
    LegacyHoldCount         = [int]       # Count of non-UniH GUIDs in InPlaceHolds
    LegacyHoldGUIDs         = [string[]]
    SIREnabled              = [bool]
    RiskScore               = [int]       # 0–4
}
```

### `Get-ElcDisabledMailboxes`

Finds mailboxes where `ElcProcessingDisabled = $true`. When set, the Managed Folder Assistant completely skips the mailbox — retention policies never fire and Recoverable Items never gets processed. Commonly set during on-prem migrations and never cleared. Safe to bulk-clear with `Set-Mailbox -ElcProcessingDisabled $false` — no compliance review required.

```powershell
function Get-ElcDisabledMailboxes {
    param([object[]]$Mailboxes)
    $Mailboxes | Where-Object { $_.ElcProcessingDisabled -eq $true }
}
```

### `Get-LegacyHoldMailboxes`

Finds mailboxes with non-`UniH` GUIDs in `InPlaceHolds`. `UniH` prefixed GUIDs are Unified Compliance Policy holds (expected — e.g., the 3-Year policy). Any other GUID format is a legacy Exchange in-place hold from an on-prem environment. These have no expiration, no owner visible in EAC or Purview, and silently pin all deleted items in `/DiscoveryHolds`. Removal requires compliance team review.

```powershell
function Get-LegacyHoldMailboxes {
    param([object[]]$Mailboxes)
    $Mailboxes | Where-Object {
        $_.InPlaceHolds | Where-Object { $_ -notmatch '^UniH' }
    }
}
```

### `Get-LitigationHoldMailboxes`

Finds mailboxes with `LitigationHoldEnabled = $true` and no hold duration set (`LitigationHoldDuration = "Unlimited"`). Litigation hold preserves all mailbox content indefinitely. With no TTL, items never age out, causing continuous Recoverable Items growth. Requires legal/compliance sign-off to modify.

```powershell
function Get-LitigationHoldMailboxes {
    param([object[]]$Mailboxes)
    $Mailboxes | Where-Object {
        $_.LitigationHoldEnabled -eq $true -and
        ($_.LitigationHoldDuration -eq 'Unlimited' -or $_.LitigationHoldDuration -eq $null)
    }
}
```

### `Get-SIRRiskMailboxes`

Finds mailboxes where `SingleItemRecoveryEnabled = $true` AND Recoverable Items size exceeds the configured threshold. SIR alone is expected — it's the combination with a large DiscoveryHolds backlog that signals a stalled cleanup. When SIR is on, MFA cannot reclaim `/DiscoveryHolds` directly. Available on Full scan only (requires Recoverable Items size data).

Note: unlike the other check functions which accept raw `$Mailboxes` objects from `Get-Mailbox`, this function takes the processed `$Results` array (already enriched with `RecoverableItems_GB` from `Get-RecoverableItemsStats`). The main wizard assembles the enriched result objects before calling this function.

```powershell
function Get-SIRRiskMailboxes {
    param([object[]]$Results, [decimal]$ThresholdGB)
    $Results | Where-Object {
        $_.SIREnabled -eq $true -and $_.RecoverableItems_GB -ge $ThresholdGB
    }
}
```

### `Get-RecoverableItemsStats`

Pulls `Get-MailboxFolderStatistics` for each mailbox and returns the size of the `Recoverable Items` root folder. Full scan path only. Called once during Phase 3 and stored in the results array — not re-called during drill-downs.

### `Get-MailboxRiskScore`

Combines all flags into a 0–4 risk score per mailbox:
- `+1` `ElcProcessingDisabled = $true`
- `+1` Legacy hold present (at least one non-`UniH` GUID)
- `+1` Litigation hold with no duration
- `+1` `SIREnabled = $true` AND `RecoverableItems_GB` ≥ threshold

---

## Mode Menu Detail

### [U] Individual User Deep-Dive

Prompts: `Enter UPN or result # :` — accepts either a number from the overview list or a typed UPN (including mailboxes not in the filtered results).

Displays a single-mailbox diagnostic panel:

```
 ════════════════════════════════════════════════════════════
  USER DIAGNOSTIC — user@domain.com
 ════════════════════════════════════════════════════════════
  Display Name          : First Last
  Primary Size          : 91.2 GB / 100 GB  (91%)
  Recoverable Items     : 78.4 GB / 100 GB  (78%)
  ElcProcessingDisabled : TRUE  ← MFA is skipped entirely for this mailbox
  SingleItemRecovery    : Enabled
  LitigationHold        : Disabled
  InPlaceHolds          :
    UniH7a3f...  ← 3 Year Email Retention Policy (expected)
    abc123...    ← LEGACY HOLD — review with compliance team
  RetentionHold         : False
  Risk Score            : 3 / 4  (HIGH)
 ════════════════════════════════════════════════════════════
```

After display, returns to the mode menu.

### [B] Batch Check — Sub-menu

```
  [E] ElcProcessingDisabled — list all affected mailboxes + bulk-fix guidance
  [H] Hold analysis         — hold type breakdown across all flagged mailboxes
  [S] SIR risk matrix       — SIR state + Recoverable Items size side by side
  [Q] Back to main menu
```

Each sub-mode prints a one-paragraph explanation of the flag before displaying results — what it means, why it causes accumulation, and what action is needed (and whether compliance sign-off is required).

**[E] ElcProcessingDisabled batch:**
Lists all `ElcProcessingDisabled = $true` mailboxes. Ends with the bulk-fix command the tech can run independently:
```powershell
# To clear — run for each mailbox after verifying no active migration:
Set-Mailbox -Identity "UPN" -ElcProcessingDisabled $false
```

**[H] Hold analysis batch:**
Groups hold GUIDs across all flagged mailboxes. Classifies each as:
- `UniH` — Compliance policy hold (expected, no action)
- Other GUID — Legacy in-place hold (flag for compliance review)
- `LitigationHoldEnabled` — Litigation hold (flag for legal review)

**[S] SIR risk matrix:**
Side-by-side table: `UPN | SIR State | Recoverable Items GB | Risk Score` — sorted by Recoverable Items size descending.

---

## Export

Prompted after any mode menu session or when `[X]` is selected.

### CSV — `MailboxHealthAudit-{yyyyMMdd-HHmmss}.csv`

One row per scanned mailbox (all mailboxes, not just flagged). Columns:

```
DisplayName, UPN, PrimarySize_GB, RecoverableItems_GB, ElcProcessingDisabled,
LitigationHold, LitigationHoldDuration, LegacyHoldCount, LegacyHoldGUIDs,
SIREnabled, RiskScore
```

`RecoverableItems_GB` is empty for Fast scan runs.

### TXT Summary — `MailboxHealthAudit-{yyyyMMdd-HHmmss}.txt`

```
════════════════════════════════════════════════════════════
 MAILBOX HEALTH AUDIT SUMMARY
════════════════════════════════════════════════════════════
 Date        : 2026-06-02 09:14:22
 Scan Type   : Fast | Full
 Thresholds  : Primary ≥ 80 GB | Recoverable Items ≥ 20 GB
 Scanned     : 1,847 mailboxes
 Flagged     : 38 mailboxes

────────────────────────────────────────────────────────────
 FLAG BREAKDOWN
────────────────────────────────────────────────────────────
 ElcProcessingDisabled     : 12   Safe to clear — no compliance review needed
 Legacy holds (non-UniH)   :  8   Requires compliance team review before removal
 Litigation hold (no TTL)  :  5   Requires legal sign-off
 SIR + high RI risk        : 19   Candidates for Invoke-MailboxCleanup.ps1

────────────────────────────────────────────────────────────
 RISK TIER BREAKDOWN
────────────────────────────────────────────────────────────
 HIGH   (score 3–4) : 7 mailboxes
 MEDIUM (score 2)   : 14 mailboxes
 LOW    (score 1)   : 17 mailboxes

────────────────────────────────────────────────────────────
 RECOMMENDED ACTIONS
────────────────────────────────────────────────────────────
 1. ElcProcessingDisabled = True
    Run: Set-Mailbox -Identity <UPN> -ElcProcessingDisabled $false
    Effect: MFA resumes processing — mailbox rejoins normal retention cycle.
    Approval: None required.

 2. Legacy in-place holds (non-UniH GUIDs)
    Review each GUID with the compliance team to confirm the hold is still needed.
    If stale: Remove-MailboxSearch or close the eDiscovery case that created it.
    Approval: Compliance team sign-off required.

 3. Litigation hold with no duration
    Confirm with legal whether an expiry date can be set.
    If no longer needed: Set-Mailbox -LitigationHoldEnabled $false
    Approval: Legal sign-off required.

 4. SIR + high Recoverable Items
    These mailboxes are candidates for Invoke-MailboxCleanup.ps1 [C] mode.
    See: tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1

════════════════════════════════════════════════════════════
```

Both files saved to the Desktop. UTF-8 encoding.

---

## Out of Scope

- Any `Set-Mailbox` or other write operations (read-only diagnostic only)
- Compliance search or purge operations (belongs in `Invoke-MailboxCleanup.ps1`)
- Folder-level size breakdown (belongs in `Invoke-MailboxCleanup.ps1 [F]` mode)
- Scheduling or automated cadence (future — Azure Automation runbook)
- Archive mailbox statistics
