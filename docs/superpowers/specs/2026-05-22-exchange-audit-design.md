# Exchange Audit Tool — Design Spec

**Date:** 2026-05-22  
**Status:** Approved for implementation  
**Tool path:** `tools/exchange-audit/index.html`  
**Config ID:** `exchange-audit`

---

## Problem

IT has no proactive visibility into Exchange Online Recoverable Items quota. Users only surface when they are already blocked — unable to delete items or receive calendar invites. The Mailbox Cleanup script resolves the acute case, but without a broad audit view there is no way to catch users trending toward the limit before they ticket.

---

## Goal

A hub tool that surfaces all Exchange mailboxes ranked by Recoverable Items quota usage, with per-user drill-in showing the same diagnostic data the Mailbox Cleanup script displays in Phase 2. Enables IT to work the list proactively rather than reactively.

---

## Architecture

```
Azure Automation Runbook (weekly, Monday 02:00)
  → Pass 1: Get-Mailbox (all mailboxes) — quick stats
  → Pass 2: Get-MailboxFolderStatistics (mailboxes ≥ 80 GB only) — folder detail
  → Outputs exchange-audit.json → Azure Blob Storage (public read, CORS enabled)

Hub tool on load
  → fetch(BLOB_URL) → parse JSON → render table + side panel
```

No backend required. The hub page is a static HTML file that fetches the pre-built JSON blob. The Blob URL is hardcoded in the tool page (same pattern as the Adobe License Monitor). The runbook runs under a managed identity with Exchange Administrator delegated scope.

---

## Runbook Design (`Invoke-ExchangeAudit.ps1`)

### Pass 1 — All mailboxes

Single batched call: `Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox`

Fields captured per mailbox:
- `UserPrincipalName`, `DisplayName`
- `RecoverableItemsSize`, `RecoverableItemsQuota` (converted to bytes)
- `SingleItemRecoveryEnabled`
- `ElcProcessingDisabled` — if `$true`, MFA will never process this mailbox regardless of other settings
- `RetentionHoldEnabled`
- `LitigationHoldEnabled`
- `DelayHoldApplied`
- `InPlaceHolds` (count only)

Status assigned server-side (not client-side):
- `critical` — Recoverable Items ≥ 90% of quota
- `warning` — ≥ 70% and < 90%
- `ok` — below 70%

### Pass 2 — Flagged mailboxes only

Runs `Get-MailboxFolderStatistics -FolderScope RecoverableItems` only on mailboxes where Recoverable Items ≥ 80 GB. Sets `hasDetailStats: true` for these users.

Folder fields captured:
- `/DiscoveryHolds` — size in bytes, item count
- `/Purges` — size in bytes, item count
- `/Versions` — size in bytes
- `/SubstrateHolds` — size in bytes (Teams/Skype hold area)

### Output

JSON written to Azure Blob Storage as `exchange-audit.json`, overwriting the previous file. No versioning — latest snapshot only.

### Schedule

Weekly, Monday at 02:00. Can be upgraded to twice-weekly (Mon + Thu) by adding a second schedule trigger with no other changes.

---

## JSON Data Model

```json
{
  "lastScan": "2026-05-22T02:14:37Z",
  "runDurationSeconds": 183,
  "totalMailboxes": 847,
  "mailboxes": [
    {
      "upn": "sanjaykumar.natarajan@corrohealth.com",
      "displayName": "Sanjaykumar Natarajan",
      "recoverableUsedBytes": 107534893056,
      "recoverableQuotaBytes": 107374182400,
      "recoverablePct": 100,
      "status": "critical",
      "sirEnabled": false,
      "elcProcessingDisabled": false,
      "retentionHoldEnabled": false,
      "litigationHold": false,
      "delayHoldApplied": false,
      "inPlaceHoldsCount": 0,
      "hasDetailStats": true,
      "folders": {
        "discoveryHoldsBytes": 102950993920,
        "discoveryHoldsItems": 1536236,
        "purgesBytes": 4509715456,
        "purgesItems": 66686,
        "versionsBytes": 0,
        "substrateHoldsBytes": 49152
      }
    }
  ]
}
```

Healthy mailboxes (status `ok`) are included with `hasDetailStats: false` and no `folders` object so the broad view is complete and filterable.

---

## Hub Page Structure

### Layout: Compact Strip + Side Panel (Layout B)

```
┌─────────────────────────────────────────────────────────────┐
│  Exchange Audit                    Last scan: Mon 02:00     │
├─────────────────────────────────────────────────────────────┤
│  847 mailboxes  [12 critical]  [31 warning]  [Search...]    │
│  Show: All ▾   Sort: Usage ▾                                │
├──────────────────────────────────┬──────────────────────────┤
│  TABLE (60%)                     │  SIDE PANEL (40%)        │
│  Name          GB      Usage     │  Sanjaykumar Natarajan   │
│  ─────────     ─────   ───────   │  sanjay...@corrohealth   │
│  ► Sanjay N.   100.1   ████ 100% │                          │
│    Divya P.     83.2   ███▌  83% │  Used   100.1 GB         │
│    Raviteja K.  81.4   ███▌  81% │  Quota  100.0 GB         │
│    Priyanka R.  30.4   █▌    30% │  SIR    DISABLED         │
│    ...                           │  Ret.   False            │
│                                  │  Holds  None             │
│                                  │                          │
│                                  │  DiscoveryHolds  95.9 GB │
│                                  │  Purges           4.2 GB │
│                                  │  Versions         1.4 GB │
│                                  │                          │
│                                  │  [⎘ Copy cleanup cmd]   │
└──────────────────────────────────┴──────────────────────────┘
```

### Components

**Header bar**
- Tool title + "Exchange Audit" category badge
- `Last scan: Mon 2026-05-22 02:00` with data age warning if > 8 days old (amber)

**Summary strip**
- Total mailboxes count
- Critical pill (red, clickable — filters table to critical only)
- Warning pill (amber, clickable — filters to warning+)
- Search box (filters by display name or UPN, client-side)
- Show dropdown: All / Critical only / Warning+ / Custom (GB threshold input)
- Sort dropdown: Usage % (default) / Name / GB used

**Table (left panel)**
- Columns: Display name + truncated UPN, GB used, usage bar + %, status badge
- Selected row highlighted with left blue border
- Status badges: red `CRITICAL`, amber `WARNING`, no badge for `ok`
- Default sort: usage % descending
- Clicking any row loads that user into the side panel

**Side panel (right panel)**
- Defaults to empty state: "Select a user to view details"
- On row click, populates with:
  - Display name + full UPN
  - Quota stats (used GB, quota GB, %)
  - Usage bar (color-coded)
  - SIR status (green `Enabled` / amber `DISABLED`)
  - MFA Processing (green `Allowed` / red `BLOCKED` — surfaces `ElcProcessingDisabled = $true`; when blocked, inline note reads "MFA will not reclaim space on this mailbox")
  - RetentionHold (green `False` / amber `ENABLED` with note)
  - Holds active (LitigationHold, DelayHold, InPlaceHolds count)
  - Folder breakdown section (only if `hasDetailStats: true`):
    - DiscoveryHolds — GB + item count
    - Purges — GB + item count + "(pending MFA)" note
    - Versions — GB
    - SubstrateHolds — GB + "(Teams/Skype)" note (if present)
  - If `hasDetailStats: false`: note reading "Folder breakdown not available — below 80 GB deep-scan threshold"
  - **Copy cleanup command** button — copies `.\Invoke-MailboxCleanup.ps1 -Mailbox <UPN>` to clipboard. Only shown for `warning` and `critical` users.

**Error / loading states**
- Loading: spinner with "Fetching audit data..."
- Fetch failure: "Could not load audit data. Check that the Azure Blob URL is reachable." with the URL shown for diagnostics
- JSON older than 14 days: banner warning "Audit data is X days old — runbook may not have run"

---

## Access Gating

`reportingOnly: true` in `config.json` — same gate as License Audit and Finance Dashboard. Requires membership in the IT Reporting Entra group. The tool card shows as locked on the hub for users outside that group.

---

## config.json Entry

```json
{
  "id": "exchange-audit",
  "name": "Exchange Audit",
  "description": "Weekly snapshot of all Exchange mailboxes ranked by Recoverable Items quota usage. Drill into any user for SIR status, hold details, and folder breakdown.",
  "icon": "<svg><!-- mailbox/envelope icon --></svg>",
  "status": "beta",
  "path": "tools/exchange-audit/",
  "accent": "#1a56db",
  "iconBg": "#e8f0fe",
  "category": "reporting-audit",
  "reportingOnly": true
}
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `tools/exchange-audit/index.html` | Hub tool page — full self-contained HTML/CSS/JS |
| `tools/exchange-audit/Invoke-ExchangeAudit.ps1` | Azure Automation runbook |
| `config.json` | Add exchange-audit entry (modify existing) |

No new shared files required — tool uses existing `shared/auth.js` and `shared/styles.css`.

---

## Implementation Notes

- The runbook does not use MSAL — it authenticates via managed identity (`Connect-ExchangeOnline -ManagedIdentity`). No interactive auth.
- The hub page does not use Graph API for this tool. It only fetches the static blob JSON. No MSAL sign-in is required to view the audit data (access is controlled by the hub's group gate, not per-request auth).
- The blob URL should be defined as a constant at the top of the tool's JS: `const AUDIT_BLOB_URL = "https://<storage>.blob.core.windows.net/it-tools/exchange-audit.json"`.
- For local development/testing, the tool should fall back gracefully when the blob is unreachable — provide a "Load local file" button that accepts a JSON file dropped from a local audit run.
- Format-Size logic mirrors `Invoke-MailboxCleanup.ps1` for visual consistency.
- Usage bar color thresholds: green < 70%, amber 70–89%, red ≥ 90%.

---

## Out of Scope (v1)

- On-demand runbook trigger from the hub page (requires Logic App or Function endpoint — deferred)
- Multi-tenant support
- Historical trend data (would require blob versioning or a database)
- Email alerting when mailboxes cross thresholds
- Batch "launch cleanup" for multiple users simultaneously
