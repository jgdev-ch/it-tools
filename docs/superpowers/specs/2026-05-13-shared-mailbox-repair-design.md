# Shared Mailbox Repair Tool — Design Spec

**Date:** 2026-05-13
**Status:** Approved

---

## Problem

A small but recurring subset of users experience shared mailboxes disappearing from their Outlook profile. Root cause is a stale AutoMapping pointer in Exchange Online's Autodiscover layer — when Full Access permissions are granted, Exchange writes a hidden pointer into the user's Autodiscover response. OST cache drift, Exchange Online backend changes, or profile age can cause this pointer to go stale, silently dropping the shared mailbox from Outlook with no error shown to the user.

Fix: remove and re-grant Full Access for each affected shared mailbox, forcing Exchange to rewrite the Autodiscover pointer. No client-side intervention required in most cases.

---

## Scope

- Repairs stale AutoMapping pointers for a single affected user's UPN
- Refreshes only Full Access mailboxes where AutoMapping is **Enabled** — Disabled (manually-added) mailboxes are unaffected by AutoMapping staleness and are skipped
- Does not modify AutoMapping settings — refresh preserves existing AutoMapping=True state
- Does not manage Send As or Send on Behalf permissions (not related to mailbox visibility)
- AutoMapping toggle functionality is explicitly out of scope pending org-wide AutoMapping review

---

## File Structure

```
tools/shared-mailbox-repair/
├── Invoke-RepairSharedMailboxes.ps1   # main wizard
├── Run-RepairSharedMailboxes.bat       # double-click launcher
├── Install-Prerequisites.ps1          # EXO module check/install (same as mailbox-cleanup)
├── Install-Prerequisites.bat          # launcher for above
└── README.txt                         # tech reference guide
```

**Location:** `C:\dev\projects\it-tools\tools\shared-mailbox-repair\`

**Dependency:** `ExchangeOnlineManagement` v3.9.0+ (same module as mailbox-cleanup — no new prerequisites if already installed)

**Parameter:** `-Mailbox` (mandatory) — UPN of the affected user

---

## Phase Flow

### [1/4] Connect to Exchange Online
- Module version check (v3.9.0+ required)
- `Connect-ExchangeOnline -ShowBanner:$false`
- Confirm connected, exit with clear error if not

### [2/4] Shared Mailbox Status
- Enumerate by scanning SharedMailbox-type recipients: `Get-Mailbox -RecipientTypeDetails SharedMailbox` then `Get-EXOMailboxPermission` per mailbox filtered to the target user — scoped to shared mailboxes only to keep the scan fast
- For each result, capture: mailbox address, AutoMapping status (True/False), mailbox existence
- Orphaned detection: attempt `Get-Mailbox` on each permission's mailbox address — if it returns null, the mailbox was deleted but the permission record remains; label Orphaned and skip
- Display table: mailbox address + AutoMapping status + any flags (Disabled / Orphaned)
- Show count summary: total found, to be refreshed, skipped, orphaned
- **Exit paths from Phase 2:**
  - Zero mailboxes found → exit with message directing tech to verify Full Access grants
  - All mailboxes AutoMapping=Disabled → exit with message suggesting profile rebuild instead
- Confirm prompt: `Proceed with refresh? [Y/N]`

**Phase 2 display example:**
```
[2/4] Shared mailbox status: john.doe@corrohealth.com

      Mailbox                              AutoMapping
      finance@corrohealth.com              Enabled
      helpdesk@corrohealth.com             Enabled
      noreply@corrohealth.com              Disabled   (manually added, will be skipped)
      old-archive@corrohealth.com          Orphaned   (mailbox not found, will be skipped)

      4 mailboxes found — 2 will be refreshed

      Proceed with refresh? [Y/N]:
```

### [3/4] Permission Refresh
- Iterate AutoMapping=Enabled mailboxes only
- For each: `Remove-MailboxPermission` then `Add-MailboxPermission -AutoMapping $true`
- Show live per-mailbox progress with pass/fail indicator
- On failure: log error reason, continue to next mailbox

**Phase 3 display example:**
```
[3/4] Refreshing permissions...

      [1/2] finance@corrohealth.com        Done
      [2/2] helpdesk@corrohealth.com       Failed — insufficient permissions
```

### [4/4] Summary
- Re-query permissions to verify each refresh landed correctly
- Display result table: Refreshed / Skipped (AutoMapping disabled) / Orphaned / Failed
- If any failures: note manual remediation needed
- Two-step Outlook restart instruction:

```
      Next step:
        Step 1 — Ask john.doe to close and reopen Outlook.
                 Shared mailboxes should reappear within a few minutes.
        Step 2 — If still missing after restart, rebuild the local Outlook
                 profile via Control Panel > Mail > Show Profiles.
```

---

## Edge Cases

| Scenario | Behavior |
|---|---|
| Zero shared mailboxes found | Exit after Phase 2 — direct tech to verify Full Access grants, not an AutoMapping issue |
| All AutoMapping=Disabled | Exit after Phase 2 — AutoMapping not the cause, suggest profile rebuild |
| Orphaned permission (mailbox deleted) | Detected in Phase 2, labeled Orphaned, skipped in Phase 3, flagged in summary and report |
| Single mailbox refresh fails | Continue through remaining mailboxes, flag in Phase 4 summary with error reason |
| User UPN not found | Exit at Phase 2 with clear error |
| Tech lacks Exchange permissions | Error at Phase 1 or Phase 2 with actionable message |

---

## Ticket Report

Prompted at end of run. Saved as `.txt` to tech's Desktop.

```
============================================================
 SHARED MAILBOX REPAIR REPORT
============================================================
 Date   : 2026-05-13 09:15:00
 Target : john.doe@corrohealth.com

------------------------------------------------------------
 PRE-FLIGHT
------------------------------------------------------------
 Shared mailboxes found : 4
 To be refreshed        : 2 (AutoMapping enabled)
 Skipped                : 1 (AutoMapping disabled)
 Orphaned               : 1 (mailbox not found)

------------------------------------------------------------
 RESULTS
------------------------------------------------------------
 finance@corrohealth.com          Refreshed
 helpdesk@corrohealth.com         Refreshed
 noreply@corrohealth.com          Skipped (AutoMapping disabled)
 old-archive@corrohealth.com      Orphaned (mailbox not found — clean up permissions)

------------------------------------------------------------
 OUTCOME
------------------------------------------------------------
 Repair complete.
 Step 1: Ask user to close and reopen Outlook.
         Shared mailboxes should reappear within a few minutes.
 Step 2: If still missing after restart, rebuild the Outlook profile
         via Control Panel > Mail > Show Profiles.
============================================================
```

If failures occurred, Results shows `Failed — <reason>` and Outcome notes manual follow-up required.

---

## Constants

```powershell
$MIN_EXO_VERSION = [Version]"3.9.0"
```

No policy names or tenant-specific constants required — this script operates purely on mailbox permissions.

---

## State Tracked

| Variable | Purpose |
|---|---|
| `$allMailboxes` | Full list of shared mailboxes found with metadata |
| `$toRefresh` | Filtered list: AutoMapping=Enabled only |
| `$results` | Per-mailbox outcome: Refreshed / Skipped / Orphaned / Failed |
| `$failureCount` | Count of failed refreshes for summary and report |
| `$reportTime` / `$reportTimestamp` | Report file naming and header |

---

## Out of Scope

- AutoMapping toggle (enable/disable per mailbox) — deferred pending org-wide review
- Send As / Send on Behalf permission repair — different issue, different fix
- Scheduled/automated repair mode — tech-triggered only for now
- Client-side OST deletion or profile rebuild automation — out of PowerShell script scope
