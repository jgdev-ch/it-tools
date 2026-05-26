================================================================================
 MAILBOX CLEANUP TOOL — TECHNICAL REFERENCE
 Invoke-MailboxCleanup.ps1  v1.3
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
completes the interactive portion in minutes and handles the full cleanup
lifecycle across multiple runs.


HOW TO RUN
----------
Double-click: Run-MailboxCleanup.bat
  - Prompts for the user's UPN (e.g. john.doe@corrohealth.com)
  - Launches the script in pwsh.exe automatically

Direct:
  pwsh.exe -File Invoke-MailboxCleanup.ps1 -Mailbox john.doe@corrohealth.com

The running account must have:
  - Exchange Administrator     (mailbox stats, quota inspection, hold clearing)
  - Compliance Administrator   (Purview policy management, compliance search + purge)

PowerShell requirement: PowerShell 7 (pwsh.exe)
  Install via: winget install Microsoft.PowerShell

The script self-installs ExchangeOnlineManagement v3.9.0+ if needed.


WHAT IT DOES — 6 PHASES
------------------------

Phase 1 — Connect Exchange Online
  Connects to Exchange Online via Connect-ExchangeOnline (MFA prompt).

Phase 2 — Mailbox Status Check
  Reads Recoverable Items quota, hold flags, SIR state, RetentionHold state,
  and folder-level breakdown. Color-coded output: green (healthy), yellow
  (caution), red (at/near limit or error condition).

  Hard stops immediately if LitigationHoldEnabled is detected — purging a
  mailbox under litigation hold may violate legal preservation requirements.

  If SingleItemRecovery is already disabled (from a previous cleanup run),
  the script prompts to re-enable it before continuing.

  Mode selection — operator chooses how to proceed:
    [C] Full cleanup   — compliance search + purge + MFA (Phases 3-5 then 6)
    [M] MFA only       — clears delay holds and re-triggers MFA only;
                         use when a previous purge is still pending MFA
    [S] Status only    — exits cleanly, no changes made
    [Q] Quit

  On the full cleanup path, if DiscoveryHolds is large (>1 GB), the script
  offers to disable SingleItemRecovery temporarily so MFA can fully reclaim
  the space after purge. The script reminds you to re-enable it on the next run.

Phase 3 — Connect Security & Compliance
  Connects to IPPSSession (Purview/compliance center). Deferred until the
  operator has confirmed they want to run full cleanup.

Phase 4 — Purview Policy Exclusion
  Adds the mailbox as an exception to the "3 Year Email Retention Policy" via
  Set-RetentionCompliancePolicy -AddExchangeLocationException. This lifts the
  compliance hold so the purge action can remove items.
  Progress bar waits 120 seconds for policy propagation before proceeding.
  Operator confirms before the compliance search runs.

Phase 5 — Compliance Search + Purge
  Creates a compliance search scoped to the Recoverable Items folder
  (folderpath:"recoverable items"). Polls until complete, then displays item
  count and size. Operator confirms the final time before purge runs.
  Purge uses HardDelete — items are permanently removed and unrecoverable.

  If the search returns 0 items but Recoverable Items is still large, the
  script warns that items were likely already purged by a previous run but
  not yet reclaimed by Exchange — MFA (Phase 6) is the correct path.

Phase 6 — Verify and Restore (always runs via finally block)
  Runs unconditionally — even on error or operator abort.
    - Shows before/after quota comparison
    - Removes the Purview policy exception (restores compliance coverage)
    - Clears DelayHoldApplied if present (covers primary Recoverable Items)
    - Clears DelayReleaseHoldApplied if present (covers Teams/Skype areas)
    - Disables SingleItemRecovery if operator opted in (enables full MFA reclaim)
    - Triggers Start-ManagedFolderAssistant -FullCrawl -AggMailboxCleanup
    - Waits 90 seconds, then re-checks for async delay holds that Exchange
      may have applied after the policy exception was removed. If found,
      clears them and re-triggers MFA so it runs clean.
    - Deletes the compliance search from the Purview portal

  Exchange reclaims the freed quota after MFA runs. Wait time varies:
    SIR enabled     — typically within 1 hour
    SIR disabled, DiscoveryHolds <20 GB  — 2-4 hours
    SIR disabled, DiscoveryHolds 20-50 GB — 12-24 hours
    SIR disabled, DiscoveryHolds >50 GB   — 24-72 hours

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

- RetentionHold        Displayed with a warning and the clear command if
  warning              RetentionHoldEnabled is true. MFA will skip the mailbox
                       entirely while this flag is active — it must be cleared
                       before quota reclamation will work.

- Delay hold           Both DelayHoldApplied and DelayReleaseHoldApplied are
  auto-clear           checked and cleared automatically. Exchange re-applies
  (sync + async)       these any time a hold changes; without clearing them,
                       MFA will not reclaim quota for up to 30 days.
                       A second check runs 90 seconds after the first MFA
                       trigger to catch holds Exchange applies asynchronously
                       after the policy exception is removed.

- SIR handling         If SingleItemRecovery is already disabled (prior run),
                       the script prompts to re-enable it at the start. On
                       large DiscoveryHolds backlogs, it offers to disable SIR
                       so MFA can fully reclaim space — and reminds the operator
                       to re-enable it on the next run once quota recovers.

- InPlaceHolds         Each hold GUID is listed in Phase 2 so the operator can
  enumeration          identify active policies before proceeding.

- ComplianceTagHold    Detected and displayed in the holds summary.
  detection

- Mode menu            [C/M/S/Q] — the operator chooses the appropriate action
                       based on where in the cleanup lifecycle the mailbox is.
                       Hitting [S] or [Q] exits cleanly with no changes.

- MFA wait estimate    Scaled by SIR state and DiscoveryHolds size — shown in
                       the done message and ticket report so the operator knows
                       how long to wait before closing the ticket.


TICKET WORKFLOW
---------------
The script is useful at every stage of a ticket without needing different tools:

  Run 1 (before):  Run → choose [S] Status only
                   Documents before-state quota and hold flags.

  Run 2 (cleanup): Run → choose [C] Full cleanup, confirm through gates
                   Performs cleanup, export TXT report, paste into ticket.
                   Note the MFA wait estimate from the done message.

  Wait for MFA to reclaim space (1 hour to 72 hours depending on backlog size).

  Run 3 (check):   If MFA stalls, run → choose [M] MFA only
                   Clears any late delay holds and re-triggers MFA.

  Run 4 (after):   Run → choose [S] Status only
                   Confirms quota has dropped. If SIR was disabled, script
                   prompts to re-enable it here.


MULTI-RUN LIFECYCLE
-------------------
Large DiscoveryHolds backlogs (>20 GB) often require more than one session:

  Session 1: Full cleanup — runs compliance search, purges items, triggers MFA.
             If SIR was disabled, the script reminds you to re-enable later.

  Wait: MFA runs in the background (hours to days for large backlogs).

  Session 2: Re-run → choose [S] to check quota OR [M] if MFA stalled.
             If quota has recovered and SIR is disabled, script prompts
             to re-enable SingleItemRecovery at the start of Phase 2.


ARCHITECTURE NOTES
------------------
The problem is ALWAYS DiscoveryHolds within the PRIMARY mailbox's Recoverable
Items folder. The 3-Year Retention Policy captures every deleted item and holds
it there. This is not the In-Place Archive (a completely separate mailbox object
with its own quota and folder structure — the script does not touch it).

Two cleanup paths exist depending on SIR state:
  Normal (SIR enabled)  — compliance search finds and purges items into /Purges;
                          MFA reclaims /Purges within ~1 hour.
  Backlog (SIR disabled) — compliance search may return 0 items; MFA must reach
                           into /DiscoveryHolds directly to reclaim space. This
                           takes 2-72 hours and requires SIR to be disabled.

The /Purges folder items shown in Phase 2 are already purged — they are queued
for MFA to reclaim, not items that still need to be deleted.

The async delay hold (DelayHoldApplied) is applied by Exchange ~30-90 seconds
after any hold change. Without the dual-check in Phase 6, MFA would run with
an active delay hold and fail to reclaim quota — triggering a wasted extra run.


VALIDATED RESULTS
-----------------
Date         User                    Before              After           Reduction
2026-05-07   priyanka.rengaraj       Over quota          30.4 GB/100GB   Cleared
2026-05-08   varunkumar.luthra       147.3 GB/100 GB     652.5 MB/100GB  99.6%
2026-05-11   varunkumar.luthra       [post-cleanup]      75.62 GB/100GB  User confirmed
             (screenshot confirmed)  user functional     (75.62%)        sending/receiving
2026-05-13   raviteja.kowtarapu      100.7 GB/100 GB     Pending MFA     2,713,009 items
                                     (101%)                              purged; SIR disabled
2026-05-21   divyalakshmi.palanivel  79.5 GB/100 GB      Pending MFA     Async delay hold
                                     (79%)                               found and cleared
                                                                         on session 2;
                                                                         MFA re-triggered

Note: Compliance-hold storage figures (238-338 GB) represent all versioned copies
under retention hold and are larger than the user-visible mailbox quota. The after
quota reflects what Exchange reports once MFA reclaims freed space.


KNOWN LIMITATIONS
-----------------
1. Single retention policy scope
   The script only removes the exception from the one named policy
   ($RETENTION_POLICY_NAME = "3 Year Email Retention Policy"). If a mailbox has
   additional holds (a second retention policy, eDiscovery holds), those still
   preserve items and the purge may be partial. The Phase 2 status check
   enumerates InPlaceHolds GUIDs — review these before proceeding if count > 1.

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
- Primary folder targeting: Compliance search purge scoped to specific primary
  mailbox folders (e.g. large third-party sync folders) for cases where the user
  cannot self-delete due to quota restrictions.
- Web app integration: Designed as the backend for a future IT Tools Hub web
  tool once Azure Automation or Azure Functions are provisioned.


FILES
-----
Invoke-MailboxCleanup.ps1   Main script
Run-MailboxCleanup.bat      Launcher (double-click to run, prompts for UPN)
Install-Prerequisites.ps1   Optional — pre-installs ExchangeOnlineManagement
Install-Prerequisites.bat   Launcher for Install-Prerequisites.ps1
README.txt                  This file

================================================================================
