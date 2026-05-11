================================================================================
 MAILBOX CLEANUP TOOL — TECHNICAL REFERENCE
 Invoke-MailboxCleanup.ps1
================================================================================

PURPOSE
-------
Clears the Recoverable Items folder for Exchange Online users who are blocked
from sending and receiving mail because their quota is full. Targets users under
the "3 Year Email Retention Policy" whose DiscoveryHolds folder has accumulated
held items to the point of quota exhaustion.

Replaces a legacy script that used dangerous permanent mailbox-level changes
(RetainDeletedItemsFor 0, SingleItemRecoveryEnabled $False) and relied on
Start-ManagedFolderAssistant background crawls that took days. This script
completes a full cleanup in ~6 minutes with no permanent mailbox changes.


HOW TO RUN
----------
Double-click: Run-MailboxCleanup.bat
  - Prompts for the user's UPN (e.g. john.doe@corrohealth.com)
  - Launches the script in pwsh.exe automatically

Direct:
  pwsh.exe -File Invoke-MailboxCleanup.ps1 -Mailbox john.doe@corrohealth.com

The running account must have:
  - Exchange Administrator     (mailbox stats, quota inspection, delay hold clearing)
  - Compliance Administrator   (Purview policy management, compliance search + purge)

PowerShell requirement: PowerShell 7 (pwsh.exe)
  Install via: winget install Microsoft.PowerShell

The script self-installs ExchangeOnlineManagement v3.9.0+ if needed.


WHAT IT DOES — 6 PHASES
------------------------

Phase 1 — Connect Exchange Online
  Connects to Exchange Online via Connect-ExchangeOnline (MFA prompt).

Phase 2 — Mailbox Status Check
  Reads Recoverable Items quota, hold flags, and folder-level breakdown.
  Color-coded output: green (healthy), yellow (caution), red (at/near limit).
  Hard stops immediately if LitigationHoldEnabled is detected — purging a
  mailbox under litigation hold may violate legal preservation requirements.
  Operator reviews the status and confirms Y/N to proceed. Hitting N exits
  cleanly with no changes made — useful for documenting before-state in a ticket.

Phase 3 — Connect Security & Compliance
  Connects to IPPSSession (Purview/compliance center). Deferred until the
  operator has confirmed they want to proceed past the status check.

Phase 4 — Purview Policy Exclusion
  Adds the mailbox as an exception to the "3 Year Email Retention Policy" via
  Set-RetentionCompliancePolicy -AddExchangeLocationException. This lifts the
  compliance hold so the purge action can remove items.
  Progress bar waits 120 seconds for policy propagation before proceeding.
  Operator confirms again before the compliance search runs.

Phase 5 — Compliance Search + Purge
  Creates a compliance search scoped to the Recoverable Items folder
  (folderpath:"recoverable items"). Polls until complete, then displays item
  count and size. Operator confirms the final time before purge runs.
  Purge uses HardDelete — items are permanently removed and unrecoverable.

Phase 6 — Restore (always runs via finally block)
  Runs unconditionally — even on error or operator abort.
    - Shows before/after quota comparison
    - Removes the Purview policy exception (restores compliance coverage)
    - Clears DelayHoldApplied if present (covers primary Recoverable Items)
    - Clears DelayReleaseHoldApplied if present (covers Teams/cloud storage areas)
    - Triggers Start-ManagedFolderAssistant for immediate quota reclamation
    - Deletes the compliance search from the Purview portal
  Exchange reclaims the freed quota within ~1 hour after MFA runs.

Session Cleanup
  Disconnect-ExchangeOnline runs at the end regardless of outcome.

Ticket Export
  Optional — operator is prompted to export a TXT summary report saved to the
  Desktop. Contains pre-flight stats, folder breakdown, results, and all cleanup
  action statuses. Paste directly into the ticket.


SAFETY FEATURES
---------------
- try/catch/finally    Policy exception and compliance search are always cleaned
                       up, even if the script errors or the operator aborts.

- Litigation hold      Hard stop at Phase 2 — script exits without making any
  hard stop            changes if LitigationHoldEnabled is true.

- Delay hold           Both DelayHoldApplied and DelayReleaseHoldApplied are
  auto-clear           checked and cleared automatically. Exchange re-applies
                       these any time a hold changes; without clearing them,
                       MFA will not reclaim quota for up to 30 days.

- MFA auto-trigger     Start-ManagedFolderAssistant is called automatically
                       after purge to accelerate quota reclamation.

- 3 confirmation       Operator confirms at: (1) status check, (2) post-
  gates                propagation, (3) pre-purge. Each gate shows relevant
                       data so the operator can make an informed call.

- Status-check mode    Hitting N at Phase 2 exits cleanly — no connections to
                       Compliance are made, no policy is touched.


TICKET WORKFLOW
---------------
The script is useful at every stage of a ticket without needing different tools:

  Run 1 (before):  Run → answer N at Phase 2
                   Documents before-state quota and hold flags.

  Run 2 (cleanup): Run → answer Y through all gates
                   Performs cleanup, export TXT report, paste into ticket.

  Wait 30–60 min for Exchange to reclaim space after MFA runs.

  Run 3 (after):   Run → answer N at Phase 2
                   Confirms quota has dropped, documents after-state.


ARCHITECTURE NOTES
------------------
The problem is ALWAYS DiscoveryHolds within the PRIMARY mailbox's Recoverable
Items folder. The 3-Year Retention Policy captures every deleted item and holds
it there. This is not the In-Place Archive (a completely separate mailbox object
with its own quota and folder structure — the script does not touch it).

The old script fought the symptom by disabling mailbox recovery settings. This
script addresses the root cause: uses the compliance layer to remove what the
retention policy is holding, then restores the policy immediately.


VALIDATED RESULTS
-----------------
Date         User                    Before              After          Reduction
2026-05-07   priyanka.rengaraj       Over quota          30.4 GB/100GB  Cleared
2026-05-08   varunkumar.luthra       147.3 GB/100 GB     652.5 MB/100GB  99.6%
2026-05-11   varunkumar.luthra       [post-cleanup]      75.62 GB/100GB  User confirmed
             (screenshot confirmed)  user functional     (75.62%)        sending/receiving

Note: "Before" compliance-hold storage figures (238–338 GB) represent all
versioned copies under retention hold — larger than user-visible mailbox quota.
The after quota reflects what Exchange reports once MFA reclaims freed space.


KNOWN LIMITATIONS
-----------------
1. Single retention policy scope
   The script only removes the exception from the one named policy
   ($RETENTION_POLICY_NAME = "3 Year Email Retention Policy"). If a mailbox has
   additional holds (a second retention policy, eDiscovery holds), those still
   preserve items and the purge may be partial. The Phase 2 status check
   displays InPlaceHolds count — review this before proceeding if count > 1.

2. Unindexed items
   The compliance search keyword query (folderpath:"recoverable items") only
   reaches indexed items. The MFA trigger + delay hold clearing combo handles
   unindexed items in practice (confirmed by Varun's 99.6% reduction). A second
   compliance search pass with no keyword filter is planned as a V2 improvement
   for any edge cases where MFA does not fully clear them.

3. SCC REST migration banner
   Connect-IPPSSession emits a deprecation banner about the REST migration.
   Suppressed via -WarningAction SilentlyContinue 6>$null — verify on future
   module updates if the banner reappears.


FUTURE / PLANNED IMPROVEMENTS
------------------------------
- V2: Second compliance search pass (no keyword filter) to sweep unindexed items
  as a belt-and-suspenders measure if MFA does not handle edge cases.
- Multi-hold wizard: Enumerate InPlaceHolds and offer per-hold exception options
  for mailboxes with multiple active holds.
- Web app integration: Designed as the backend for a future IT Tools Hub web
  tool once Azure Automation or Azure Functions are provisioned. The 6 phases
  map cleanly to API endpoints. Multi-user batch mode deferred to that phase.


FILES
-----
Invoke-MailboxCleanup.ps1   Main script
Run-MailboxCleanup.bat      Launcher (double-click to run, prompts for UPN)
README.txt                  This file

================================================================================
