# Shared Mailbox Repair — AutoMapping Toggle Feature Design

**Date:** 2026-05-14
**Status:** Approved
**Extends:** `2026-05-13-shared-mailbox-repair-design.md`

---

## Problem

The existing repair script refreshes stale AutoMapping pointers by removing and re-granting Full Access with `AutoMapping $true`. For some users, the pointer keeps going stale — repeated repairs don't hold. In these cases, disabling AutoMapping entirely and having the user manually map the mailbox in Outlook is the more stable fix. Techs currently have no in-script way to do this; it requires manual PowerShell outside the tool.

---

## Scope

- Add a per-mailbox action selection wizard (Phase 3) between the scan and the permission operations
- Support two actions per mailbox: **Repair** (re-grant with AutoMapping=$true, existing behaviour) and **Disable** (re-grant with AutoMapping=$false, new)
- Bulk-disable shortcut: apply Disable to all automapped mailboxes in one prompt
- Already-disabled and orphaned mailboxes remain skipped — no change
- Phase count increases from 4 to 5; existing repair-only fast path is fully preserved
- README to be updated after field testing

---

## Phase Structure

```
[1/5] Connect to Exchange Online        — unchanged
[2/5] Shared Mailbox Status             — unchanged (scan + display table)
[3/5] Action Selection                  — NEW
[4/5] Permission Operations             — was Phase 3; now handles Repair + Disable
[5/5] Verify and Summarise              — was Phase 4; updated for expanded outcomes
```

---

## Data Model

The mailbox object gains an `Action` field:

| Field       | Type   | Values                          |
|-------------|--------|---------------------------------|
| Address     | string | PrimarySmtpAddress              |
| DisplayName | string | mailbox display name            |
| AutoMapping | bool   | current state from EXO          |
| Action      | string | `Repair` / `Disable` / `Skip`   |

On entry to Phase 3, automapped mailboxes default to `Action = Repair`. Already-disabled and orphaned mailboxes are pre-set to `Action = Skip` and do not enter the wizard.

---

## Phase 3 — Action Selection

Entry condition: `$toRefresh.Count -gt 0` (same as existing confirm prompt).

```
[3/5] Action Selection

      Disable AutoMapping on any of these mailboxes? [Y/N]:
```

**If N:** all automapped mailboxes keep `Action = Repair`. Skip to action plan display and confirm.

**If Y:**
```
      Apply to all [A] or one at a time [O]?:
```

- **All:** set `Action = Disable` on every automapped mailbox.
- **One at a time:** iterate each automapped mailbox in order:
  ```
        [1/3] finance@corrohealth.com        [R]epair / [D]isable / [S]kip:
        [2/3] helpdesk@corrohealth.com       [R]epair / [D]isable / [S]kip:
        [3/3] noreply-alerts@corrohealth.com [R]epair / [D]isable / [S]kip:
  ```
  Invalid input re-prompts the same mailbox.

After selection (any path), show the action plan table and final confirm:

```
      Action plan:
      finance@corrohealth.com              Disable AutoMapping
      helpdesk@corrohealth.com             Repair
      noreply-alerts@corrohealth.com       Repair
      old-archive@corrohealth.com          Skip  (already disabled / orphaned)

      Proceed? [Y/N]:
```

---

## Phase 4 — Permission Operations

Single loop over all mailboxes with `Action = Repair` or `Action = Disable`:

- **Repair:** `Remove-MailboxPermission` → `Add-MailboxPermission -AutoMapping $true`
- **Disable:** `Remove-MailboxPermission` → `Add-MailboxPermission -AutoMapping $false`

Live progress output:
```
[4/5] Permission Operations...

      [1/3] finance@corrohealth.com        Disabled
      [2/3] helpdesk@corrohealth.com       Refreshed
      [3/3] noreply-alerts@corrohealth.com Refreshed
```

Failures log the error reason and continue to the next mailbox.

---

## Phase 5 — Verify and Summarise

Re-queries `Get-EXOMailboxPermission` for every Repair and Disable outcome to confirm the permission landed. If not found after the operation, outcome flips to `Failed`.

Result table outcomes: `Refreshed / Disabled / Skipped / Failed`

### Next Steps block

Shown conditionally based on what actually ran:

- If any `Refreshed`: Step 1 — ask user to restart Outlook; repaired mailboxes should reappear.
- If any `Disabled`: Step 2 — manually add the mailbox in Outlook:
  - **Classic Outlook:** File → Account Settings → Change → More Settings → Advanced → Add shared mailbox address under "Open these additional mailboxes"
  - **New Outlook / OWA:** Right-click Folders → Add shared folder → enter mailbox address
- Always: if repaired mailboxes still missing after restart → rebuild Outlook profile via Control Panel → Mail → Show Profiles.

---

## Ticket Report Updates

**PRE-FLIGHT section** gains a "To be disabled" count:
```
 Shared mailboxes found : 4
 To be repaired         : 2 (AutoMapping pointer refresh)
 To be disabled         : 1 (AutoMapping will be set to disabled)
 Skipped                : 1 (AutoMapping already disabled)
```

**RESULTS section** shows `Disabled` alongside existing outcomes.

**OUTCOME section** notes if any mailboxes were disabled and require manual mapping.

---

## Edge Cases

| Scenario | Behaviour |
|---|---|
| Tech answers N to disable prompt | All automapped mailboxes repair as before — identical to current behaviour |
| Tech skips all mailboxes in one-at-a-time | `$toProcess.Count = 0`; exit with "No changes made" |
| All mailboxes set to Disable | No Refreshed entries; Next Steps shows only the manual-add instructions |
| Disable operation fails on one mailbox | Logged as Failed, continues; failure noted in summary and report |
| Already-disabled mailboxes | Remain Skip throughout; not surfaced in wizard |

---

## State Variables Added

| Variable     | Purpose                                              |
|--------------|------------------------------------------------------|
| `$toDisable` | Filtered list: mailboxes with Action = Disable       |
| `$toProcess` | Combined list: Repair + Disable (drives Phase 4 loop)|

---

## Out of Scope

- Azure / web interface integration — future consideration once field-tested
- Enabling AutoMapping on a currently-disabled mailbox — not a current use case
- Send As / Send on Behalf permission management
- Scheduled or automated repair mode
