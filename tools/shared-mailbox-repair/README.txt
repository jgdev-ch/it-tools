============================================================
 SHARED MAILBOX REPAIR TOOL — TECH REFERENCE
============================================================

PURPOSE
-------
Repairs disappearing shared mailboxes in Outlook for a single
affected user. Root cause is a stale AutoMapping pointer in
Exchange Online's Autodiscover layer.

Only repairs mailboxes where AutoMapping is Enabled (the
default). Manually-added shared mailboxes (AutoMapping=Disabled)
are displayed but not touched.

WHEN TO USE
-----------
- User reports one or more shared mailboxes missing from Outlook
- Mailboxes reappear after profile rebuild but disappear again
- Issue recurs for the same user

WHEN NOT TO USE
---------------
- Mailbox never appeared (may be a permissions issue — verify
  Full Access grant in Exchange admin)
- All shared mailboxes show AutoMapping=Disabled (manually added
  — rebuild the Outlook profile instead)

PREREQUISITES
-------------
Run Install-Prerequisites.bat once before first use.
Requires ExchangeOnlineManagement v3.9.0+.

USAGE
-----
Double-click Run-RepairSharedMailboxes.bat
Enter the affected user's UPN when prompted.

Must be run as a Global Admin or Exchange Admin account.

WHAT THE SCRIPT DOES
--------------------
Phase 1 — Connects to Exchange Online (interactive MFA)
Phase 2 — Lists all shared mailboxes the user has Full Access to,
           shows AutoMapping status for each
Phase 3 — Removes and re-grants Full Access on AutoMapping-enabled
           mailboxes, forcing Exchange to rewrite the Autodiscover
           pointer
Phase 4 — Verifies each refresh landed, displays result table,
           outputs Outlook restart instructions for the user

AFTER THE SCRIPT
----------------
Step 1: Ask the user to close and reopen Outlook.
        Shared mailboxes should reappear within a few minutes.
Step 2: If still missing, rebuild the local Outlook profile:
        Control Panel > Mail > Show Profiles > Add

TICKET EXPORT
-------------
At the end of each run you are prompted to save a .txt report
to your Desktop for pasting into the helpdesk ticket.

============================================================
