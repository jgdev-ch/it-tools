# Mailbox Cleanup Script — Design Spec

**Date:** 2026-05-07  
**Status:** Approved, ready for implementation planning

---

## Purpose

Replace an unsafe, slow PowerShell script used to clear the Recoverable Items folder for users on Outlook Web / F3 licenses who have hit their quota and are blocked from sending and receiving mail.

The new script automates every manual step, uses a faster cleanup method, and is safe to run without side-effects beyond the targeted cleanup.

---

## Problem Statement

F3/Outlook Web users have small mailbox quotas. When a user is under a compliance hold (3-year retention policy) and deletes items, those items accumulate in the Recoverable Items folder rather than being permanently removed. Once Recoverable Items hits its limit, the user can no longer delete items or send/receive mail.

The old script used `Start-ManagedFolderAssistant` — a background crawling process that takes days and required manually excluding the user from the retention policy in Purview beforehand. It also contained dangerous operations (`Set-Mailbox -RetainDeletedItemsFor 0` and `-SingleItemRecoveryEnabled $False`) that could permanently disable recovery capabilities — these are removed entirely from the new design.

---

## Scope

- **In scope:** Single-mailbox on-demand cleanup via PowerShell
- **Out of scope:** Multi-user batch processing (deferred to web app phase), scheduling, reporting dashboards
- **Future:** This script is designed to be the backend of a future web-based hub tool once Azure Automation or Azure Functions are provisioned

---

## Required Roles

The admin account used to run the script must have:
- **Exchange Administrator** (for `Get-MailboxFolderStatistics`, quota inspection)
- **Compliance Administrator** (for `Connect-IPPSSession`, retention policy management, `New-ComplianceSearch`, `New-ComplianceSearchAction`)

---

## Required PowerShell Modules

- `ExchangeOnlineManagement` (provides `Connect-ExchangeOnline`, `Connect-IPPSSession`)

---

## Script Constants

Defined at the top of the script — the only values that require manual configuration:

```powershell
$RETENTION_POLICY_NAME = "3 Year Retention Policy"   # Update if policy name changes
$PROPAGATION_WAIT_SECONDS = 120                        # Time to wait after policy exclusion before searching
$POLL_INTERVAL_SECONDS = 30                            # Polling interval for search/purge status
```

---

## Parameters

```powershell
param(
    [Parameter(Mandatory)]
    [string]$Mailbox    # UPN of the affected user, e.g. john.doe@corrohealth.com
)
```

---

## Execution Flow

### Phase 1 — Connect
Open both PowerShell sessions with the admin's credentials:
- `Connect-ExchangeOnline` — interactive MFA login
- `Connect-IPPSSession` — Security & Compliance (Purview)

Both connections use the same admin account. The tech authenticates once via browser.

### Phase 2 — Pre-flight snapshot
- Verify the mailbox exists; exit with a clear error if not found
- Retrieve current Recoverable Items folder size using `Get-MailboxFolderStatistics -FolderScope RecoverableItems`
- Display current usage and quota so the tech has a before-state on record

### Phase 3 — Purview policy exclusion
- Verify `$RETENTION_POLICY_NAME` exists via `Get-RetentionCompliancePolicy`; exit with a clear error if not found
- Add the mailbox as an exception: `Set-RetentionCompliancePolicy -AddExchangeLocationException $Mailbox`
- Wait `$PROPAGATION_WAIT_SECONDS` with a visible countdown before proceeding — the compliance search must not run until the exclusion has propagated

### Phase 4 — Compliance search and purge
- Create a new compliance search with a unique name: `RecovItems-<alias>-<yyyyMMdd-HHmmss>`
  - Scoped to the target mailbox only
  - Targets the Recoverable Items folder: `folderpath:"recoverable items"`
- Start the search: `Start-ComplianceSearch`
- Poll `Get-ComplianceSearch` every `$POLL_INTERVAL_SECONDS` until `Status -eq "Completed"`
- Display items found and estimated size
- Run `New-ComplianceSearchAction -SearchName <name> -Purge -PurgeType HardDelete -Confirm:$false`
- **PurgeType rationale:** Items in Recoverable Items are already user-deleted; they are only retained due to the compliance hold. With the hold temporarily lifted, `HardDelete` is the correct action — it actually frees the quota. `SoftDelete` would only move items between Recoverable Items sub-folders without freeing space.
- Poll `Get-ComplianceSearchAction` until `Status -eq "Completed"`

### Phase 5 — Verification and restore (always runs via `finally`)
- Re-check Recoverable Items folder size and display after-state
- Remove the Purview policy exception: `Set-RetentionCompliancePolicy -RemoveExchangeLocationException $Mailbox`
- Delete the compliance search object: `Remove-ComplianceSearch -Identity <name> -Confirm:$false`
- Print final summary: mailbox, before/after quota, items purged, outcome

---

## Safety Guarantees

The entire cleanup (Phases 4–6) is wrapped in `try/finally`:

```
try {
    Phase 3 — add exclusion
    Phase 4 — search and purge
} finally {
    Phase 5 — always remove exclusion and delete search
}
```

If the script errors at any point after Phase 3, the `finally` block restores the policy exception and removes any partial compliance search objects before exiting. The admin is never left with a user permanently excluded from the retention policy due to a script crash.

---

## Output Format

```
[1/5] Connecting to Exchange Online and Security & Compliance...
[2/5] Pre-flight: john.doe@corrohealth.com
      Recoverable Items: 28.4 GB / 30 GB (94% full)
[3/5] Adding Purview policy exclusion...
      Waiting for propagation: 120s... 90s... 60s... 30s... done.
[4/5] Compliance search: RecovItems-john.doe-20260507-143022
      Searching... (30s)
      Searching... (60s)
      Search complete — 14,832 items found (26.1 GB)
      Running purge (HardDelete)...
      Purging... (30s)
      Purge complete.
[5/5] Verifying and restoring...
      Recoverable Items: 0.2 GB / 30 GB (1% full)
      Purview policy exception removed.
      Compliance search deleted.

Done. john.doe@corrohealth.com is clear to send and receive.
```

Errors are caught and printed as plain-language messages. Raw PowerShell exception dumps are suppressed.

---

## What Was Removed from the Old Script

| Old operation | Reason removed |
|---|---|
| `Set-Mailbox -RetainDeletedItemsFor 0.00:00:00` | Sets deleted item retention to zero — permanently disables recoverable deleted items for the mailbox |
| `Set-Mailbox -SingleItemRecoveryEnabled $False` | Disables single-item recovery — items deleted by any method become permanently unrecoverable |
| Manual Purview exclusion step | Automated via `Set-RetentionCompliancePolicy` |
| `Start-ManagedFolderAssistant` loop | Replaced by Compliance Search Purge — minutes/hours instead of days |

---

## File Location

`tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`
