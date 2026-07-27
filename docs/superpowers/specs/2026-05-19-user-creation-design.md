# User Creation Tool — Design Spec
**Date:** 2026-05-19
**Status:** Approved · **Revised 2026-07-24** (Exchange-step automation added) · **Revised 2026-07-27** (Step 4 = explicit tech choice — see Revision History)

## Revision History

**2026-07-27 — Step 4 is an explicit choice, not a default-with-fallback.** Before the Exchange work runs, the tech chooses one of two co-equal paths: (A) let Azure automation complete the Exchange steps, or (B) download a ZIP and run it themselves. Automated is *recommended* when the *Distribution Groups* RBAC role is in place, but it is a deliberate selection the tech makes — not a silent default with a fallback. The two paths are otherwise unchanged; only their presentation in Step 4 is reframed.

**2026-07-24 — Exchange steps can now run via Azure automation.** When this spec was first written, no tenant-side Exchange automation existed, so delegating Exchange-only steps to a downloadable ZIP script was the only secure option. The Mailbox Cleanup project has since stood up an Azure Automation account with a managed identity that authenticates to Exchange Online unattended (`Connect-AzAccount -Identity` → token → `Connect-ExchangeOnline`). This revision adds an **automated Exchange-setup path** as the default, while **keeping the ZIP download as an always-available fallback**. Steps 1–3, the CSV standard, license/group logic, region handling, and in-browser password generation are unchanged. See the new sections: *Step 4 (revised)*, *Job Blob*, *Exchange Setup Runbook*, *Exchange RBAC*, *Completion Notification (Teams)*, and *Failure & Fallback Semantics*.

## Overview

A 4-step hub web tool that replaces the legacy `NewAccounts` PowerShell script. The hub handles everything reachable via Microsoft Graph (user creation, licensing, security groups). At completion, the tech **chooses how the Exchange-only steps** (distribution-group membership, archive enablement, retention policy, subcontractor attribute) **get done** — two co-equal paths, selected before the Exchange work runs:

- **Automated:** the hub enqueues a job to Azure storage; a scheduled runbook completes the Exchange steps once each mailbox provisions, then reports results to a Teams channel. The tech only downloads the credentials CSV. *Recommended when the Distribution Groups RBAC role is in place.*
- **Download ZIP:** the hub generates a pre-populated Exchange setup script + `.bat` launcher + credentials CSV, so the tech finishes the Exchange steps manually in their own EXO session — for when automation is unavailable, the RBAC grant hasn't landed, or the tech simply prefers to run it themselves.

This tool covers **account creation only**. Updating existing users, re-enabling disabled accounts, managing licenses on existing users, and MFA management are separate future tools.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│  Hub (browser — Microsoft Graph)            │
│  Step 1: Upload & validate CSV              │
│  Step 2: Review & edit (bulk + per-row)     │
│  Step 3: Create accounts (live progress)    │
│  Step 4: Automated setup  OR  Download ZIP  │
└──────────┬───────────────────────┬──────────┘
           │ ① write job blob        │ ② ZIP download (fallback)
           │   (scoped SAS)          │
           ▼                         ▼
┌────────────────────────┐   ┌─────────────────────────────────┐
│ Azure Storage          │   │ NewAccountsSetup-YYYY-MM-DD.zip │
│ user-creation-jobs/    │   │ ├── Exchange-Setup.ps1          │
│   pending/<jobid>.json │   │ ├── Run-Exchange-Setup.bat      │
└──────────┬─────────────┘   │ └── Credentials.csv             │
           │ polled ~15–30m  └──────────────┬──────────────────┘
           ▼                                │ tech extracts + runs bat
┌────────────────────────┐                 │
│ Runbook (scheduled)    │                 │
│ Invoke-UserCreation-   │                 │
│   ExchangeSetup.ps1    │                 │
│ - managed-identity EXO │                 │
│ - mailbox provisioned? │                 │
│   → run Exchange steps │                 │
│ - write result CSV     │                 │
│ - post Teams card      │                 │
└──────────┬─────────────┘                 │
           ▼                                ▼
┌─────────────────────────────────────────────┐
│  Exchange Online (PowerShell)               │
│  - Distribution group membership           │
│  - Enable-Mailbox archive (50 GB users)     │
│  - Set retention policy (50 GB users)       │
│  - Set-Mailbox CustomAttribute4             │
│    (subcontractors)                         │
└─────────────────────────────────────────────┘

Both paths converge on the same Exchange operations. Credentials.csv
(browser-generated passwords) is ALWAYS downloaded locally in both paths —
passwords are never written to the job blob or transmitted to any server.
```

### Graph scopes required
- `User.ReadWrite.All` — create users, check for existing UPNs
- `Group.ReadWrite.All` — add users to security groups
- `Directory.Read.All` — read subscribed SKUs for license assignment

---

## CSV Standard

Fixed 13-column format. The hub enforces this schema — no column mapping step.

| Column | Required | Notes |
|--------|----------|-------|
| `EID` | Yes | Employee ID — used as `EmployeeId` and `PreferredDataLocation` |
| `Firstname` | Yes | `GivenName` |
| `Lastname` | Yes | `Surname` |
| `UserPrincipalName` | Yes | Pre-computed `Firstname.Lastname@corrohealth.com` — validated on parse |
| `RequiredMailboxSize` | Yes | `2 GB`, `50 GB`, or `E3` |
| `InternalEmailOnly` | Yes | `Y`/`N` — controls distribution group assignment |
| `EntApps` | Yes | `Y`/`N` — adds `OFFICESUBSCRIPTION` SKU |
| `Designation` | Yes | Job title |
| `City` | Yes | |
| `Province` | Yes | State/province |
| `Country` | Yes | Drives `UsageLocation` (IN/US) |
| `Office` | Yes | Office location code |
| `SubContractor` | Yes | `Y`/`N` — group assignment + Exchange CustomAttribute4 |

**Dropped from legacy script:** `S.No` (ignored if present), `CONTACT NO` (removed — add back if needed in a future iteration).

### UPN validation rules
- Must match pattern `[A-Za-z]+\.[A-Za-z]+@corrohealth.com`
- Must not already exist in Entra ID (checked via Graph on upload)
- Rows with existing UPNs shown as warnings and excluded from creation

---

## Step 1 — Upload CSV

- Standard file drop zone (`file-drop-idle` / `file-drop-busy` / `file.text()` pattern)
- On parse: validate all 13 required columns are present — hard error if missing
- Per-row validation: UPN format, required fields not blank, `RequiredMailboxSize` is a known value
- UPN existence check against Graph — marks rows as warnings, does not block upload
- Advances to Step 2 once parse completes with zero hard errors

---

## Step 2 — Review & Edit

### Region toggle
`🇮🇳 India` / `🇺🇸 US` — defaults to India. Controls:
- `UsageLocation` field on the created user (IN vs US)
- Group set in the Exchange script
- Retention policy in the Exchange script

US mode stubs are scaffolded in the Exchange script template; group names and policy names populated from a config object in the tool JS. **US group names and retention policy TBD — to be confirmed with the team before US mode is activated. US mode UI is present but the Exchange script output for US will be a clearly labelled placeholder until confirmed.**

### Validation summary bar
Three pills — `N ready` / `N warning` / `N errors`. Errors must reach 0 before Continue is enabled. Warnings (UPN exists) are shown but skipped at creation time.

### Bulk Settings bar
Collapsed by default. Expands to show:
- **License for all** — dropdown: `— keep per-row —` / `F3 (2 GB)` / `F3+ (50 GB + Archive)` / `E3`
- **Apps for all** — toggle: Microsoft 365 desktop apps
- **Subcontractor for all** — toggle

**Apply to All** button triggers a confirmation modal listing exactly what will change and how many users are affected. Rows with warnings (UPN exists) are explicitly noted as skipped in the modal. After applying, per-row controls still reflect the bulk values and remain individually editable.

### Per-row table
Columns: `#` · `Display Name` · `UPN` · `EID` · `License` (dropdown) · `Apps` (toggle) · `Subcontractor` (toggle) · `Status` (pill)

Status pills:
- `✓ Ready` — green
- `⚠ UPN exists` — amber — row excluded from creation
- `✗ [error]` — red — must be resolved before continuing

Apps toggle tooltip: *"Adds Microsoft 365 desktop apps (Word, Excel, PowerPoint). Does not include Outlook desktop — E3 license required for that."*

---

## Step 3 — Create Accounts

Per-user live progress. Each row shows the UPN and a status that updates in real time:

1. `Creating user…` → `New-MgUser` (Graph)
2. `Assigning license…` → `Set-MgUserLicense`
3. `Adding to groups…` → `New-MgGroupMember` (security groups only)
4. `✓ Done` or `✗ Failed — [reason]`

SKUs fetched once before the loop (`Get-MgSubscribedSku`) and cached for the session.

### License → SKU mapping
| RequiredMailboxSize | SKUs assigned |
|---|---|
| `2 GB` | `SPE_F1` (F3) |
| `50 GB` | `SPE_F1` + `EXCHANGEARCHIVE_ADDON` |
| `E3` | `SPE_E3` |
| + EntApps = Y | + `OFFICESUBSCRIPTION` (any tier) |

### Group assignment logic
| Condition | Security group |
|---|---|
| SubContractor = Y | `P-SG-InTune-Global-SubContractor-User-Group` |
| SubContractor = N | `P-SG-InTune-Global-Team_Member-User-Group` |
| RequiredMailboxSize = E3 | + `India O365 Login Access` (India mode) |
| RequiredMailboxSize = 2 GB or 50 GB | + `internal email only` + `Disable Outlook Access` |

### Failure handling
- A failure on one user does not stop the loop
- Failed users are excluded from the Exchange script and credentials CSV
- Summary on completion: `X created · X skipped (UPN exists) · X failed`

---

## Step 4 — Complete Exchange Setup (revised 2026-07-24, reframed 2026-07-27)

Step 4 presents the tech with an **explicit choice** between two co-equal paths, made before any Exchange work runs. The UI shows both options side by side with a short description of each; **Automated** carries a *Recommended* tag when the *Distribution Groups* RBAC role is available, but neither is preselected — the tech deliberately picks one.

In both paths, `Credentials.csv` is generated in-browser and **downloaded locally** — passwords never leave the browser (see *Password generation*).

### Path ① — Automated Exchange setup

Button: **Queue Exchange Setup**.

On click, the hub:
1. Generates the browser-side passwords and prompts a local download of `Credentials.csv` (same file as the ZIP path).
2. Writes a **job blob** to `user-creation-jobs/pending/<jobid>.json` in the audit storage account, using a scoped, write-limited SAS token vendored into the tool (same mechanism the Mailbox Cleanup script uses for its tracking blob).
3. Shows a confirmation: *"Exchange setup queued for N users. Results will post to the [IT Automation] Teams channel when mailboxes finish provisioning (usually within a few hours)."*

The tech is then done — no script to run. A scheduled runbook takes it from here (see *Exchange Setup Runbook*).

### Path ② — Download ZIP

Button: **Download ZIP**. Identical to the original design — chosen when automation is unavailable, the *Distribution Groups* RBAC role has not yet been granted, or a tech prefers to run it manually. Generates `NewAccountsSetup-YYYY-MM-DD.zip` client-side via JSZip.

### Job Blob

Written to `user-creation-jobs/pending/<jobid>.json`. Contains only UPNs and Exchange config flags — **never passwords**.

```json
{
  "jobId": "2026-07-24-01",
  "createdBy": "tech.upn@corrohealth.com",
  "createdAt": "2026-07-24T14:03:00Z",
  "region": "India",
  "users": [
    { "upn": "reddy.teja@corrohealth.com", "size": "50GB",
      "subContractor": false, "internalEmailOnly": true,
      "status": "pending" }
  ]
}
```

Per-user `status` is updated by the runbook (`pending` → `done` / `failed`). When all users are resolved, the blob moves `pending/` → `completed/`.

### Exchange Setup Runbook

**`Invoke-UserCreationExchangeSetup.ps1`** — new runbook in the existing Automation account, scheduled every ~15–30 minutes. Reuses the SIR-watchdog connection pattern exactly: `Connect-AzAccount -Identity` → `Get-AzAccessToken -ResourceUrl "https://outlook.office365.com"` → `Connect-ExchangeOnline -AccessToken -Organization trusthcs0.onmicrosoft.com`.

Per cycle:
1. List blobs under `user-creation-jobs/pending/`.
2. For each user with `status = pending`, check the mailbox has provisioned (`Get-Mailbox -Identity <upn>` succeeds).
   - **Ready** → run the same Exchange operations as the ZIP script (`Add-DistributionGroupMember`, `Enable-Mailbox -Archive` for 50 GB, `Set-Mailbox -RetentionPolicy` for 50 GB India, `Set-Mailbox -CustomAttribute4` for subcontractors), each guarded by an idempotency check; set `status = done`.
   - **Not ready** → leave `pending`; retry next cycle.
   - **Not ready past cutoff** (job age > ~6h) → set `status = failed`, reason `mailbox not provisioned`.
3. When every user in a job is resolved, write `result-<jobid>.csv` to the audit container, move the job blob to `completed/`, and post the Teams card (see *Completion Notification*).

**Idempotency:** every operation checks current state first (e.g., skip `Add-DistributionGroupMember` if already a member, skip `Enable-Mailbox -Archive` if archive already present), so re-running a cycle never double-applies.

### Exchange RBAC (prerequisite for Path ①)

The managed identity `p-corp-aa-mailboxcleanup-azuc-01` currently holds **Mail Recipients**, **Mailbox Import Export**, and **Mailbox Search**.

| Exchange step | Role required | Status |
|---|---|---|
| `Enable-Mailbox -Archive` | Mail Recipients | ✅ held |
| `Set-Mailbox` (retention / CustomAttribute4) | Mail Recipients | ✅ held |
| `Add-DistributionGroupMember` | **Distribution Groups** | ❌ **must be granted** |

**One new role — *Distribution Groups*** — must be assigned to the managed identity's service principal via `New-ManagementRoleAssignment` (requires an Exchange admin, same class of grant as the Search And Purge role). Path ① does not fully work until this lands; **Path ② (ZIP) requires none of it**, so the tool is usable from day one via the fallback while the grant is in flight.

*Infra naming note:* the Automation account and storage are branded `mailboxcleanup`. Reusing them is fine and in-scope. A future rename to a neutral `p-corp-aa-ittools-*` would be cleaner but is explicitly out of scope — not worth re-plumbing working infrastructure.

### Completion Notification (Teams)

The runbook posts an **Adaptive Card** to a new dedicated **[IT Automation] Teams channel** via an **incoming webhook** (URL stored as an Automation account variable — not in the hub, not in the repo).

Card contents:
- Header: `Exchange setup complete — N users · <region>`
- Per-user rows: ✓/✗ with what was applied (or the failure reason)
- A **Download results** button linking to `result-<jobid>.csv` in the audit container via a short-lived scoped SAS URL

(Incoming webhooks cannot attach binary files, so the result CSV lives in blob storage and is surfaced as a download link.)

### Failure & Fallback Semantics

- **Per-user isolation** — one user's failure never blocks the rest of the job; it is marked ✗ with a reason in the card and result CSV.
- **Provisioning cutoff** — a mailbox not ready ~6h after job creation is marked failed. The tech re-runs only those stragglers via the ZIP fallback.
- **Automation unavailable** — the ZIP path is always offered, so a broken or paused runbook never blocks onboarding.
- **Idempotent retries** — safe to re-run; state is checked before every operation.

## Step 4 — ZIP Contents (Path ② detail)

Generated client-side via JSZip. Button label: `Download NewAccountsSetup-YYYY-MM-DD.zip`.

### ZIP contents

**`Exchange-Setup.ps1`**
Pre-populated with all successfully created users. Handles Exchange-only operations the hub cannot reach via Graph.

Operations per user:
- `Add-DistributionGroupMember` for distribution groups (InternalEmailOnly / India groups)
- `Set-Mailbox -CustomAttribute4 "SubContractor"` (SubContractor = Y)
- `Enable-Mailbox -Archive` (50 GB users)
- `Set-Mailbox -RetentionPolicy "India F3 Users"` (50 GB India users)

Script structure:
```powershell
# Generated by IT Tools Hub — <date>
# <N> users — <region> mode
# Run AFTER verifying accounts appear in Entra ID

$region = "India"  # or "US"

$users = @(
  @{ UPN="..."; Size="2GB"; SubContractor=$false; InternalEmailOnly=$true },
  ...
)

# Phase 1: Connect
# Phase 2: Per-user Exchange operations
# Phase 3: Summary + disconnect
```

Uses the same 5-phase wizard shell and formatting conventions as Mailbox Cleanup and Shared Mailbox Repair scripts (consistent tech experience).

**`Run-Exchange-Setup.bat`**
```batch
@echo off
echo ================================================
echo  Exchange Setup — Generated by IT Tools Hub
echo ================================================
echo.
echo Target: <N> users — <region> mode
echo Date generated: <YYYY-MM-DD>
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Exchange-Setup.ps1"
pause
```

`%~dp0` ensures the `.bat` finds the `.ps1` in the same folder regardless of where it is extracted.

**`Credentials.csv`**
```
DisplayName,UPN,TempPassword
Reddy Teja,Reddy.teja@corrohealth.com,xK9#mP2qR8...
```

### Password generation
- Generated in-browser via `crypto.getRandomValues()`
- 16 characters: uppercase + lowercase + digits + symbols
- Never transmitted to any server
- The credentials CSV is the sole record — tech is responsible for secure handoff to new hires

---

## Security Considerations

- No passwords stored in hub session, localStorage, or any server
- Credentials CSV is downloaded locally in both paths (inside the ZIP for Path ②, direct download for Path ①) — a single controlled download, never a separate loose server-side file
- **Job blob carries no secrets** — only UPNs and Exchange config flags; passwords are never written to storage or transmitted
- **Scoped SAS token** — the SAS vendored into the hub is write-limited to the `user-creation-jobs` container (create/write, no read/list/delete), object-scoped and time-bounded, matching the least-privilege approach used for the Mailbox Cleanup tracking blob. Reissue on the same cadence.
- **No inbound web endpoint** — the hub never triggers Exchange writes directly; it only drops a job blob that a scheduled runbook polls. This preserves the security posture set in the Group Administration design (no web-exposed tenant-write endpoint).
- **Runbook auth** — managed identity only; no stored credentials. Exchange RBAC is least-privilege (Mail Recipients + Distribution Groups).
- **Teams webhook URL** stored as an Automation account variable — not in the hub, not in the repo
- Exchange script (Path ②) contains no credentials — it prompts for MFA via `Connect-ExchangeOnline` at runtime
- Graph token acquired via MSAL popup — standard hub auth pattern, no special handling needed

---

## File Location

```
tools/user-creation/
├── index.html           ← hub tool
└── jszip.min.js         ← client-side ZIP library (vendored)

runbook/                  ← Azure Automation (deployed separately, tracked in repo)
└── Invoke-UserCreationExchangeSetup.ps1
```

JSZip vendored alongside the tool (same approach as `msal-browser.min.js` in shared/) to avoid CDN dependency. The runbook is tracked in the repo alongside the tool (mirroring `tools/mailbox-cleanup/runbook/`) but deployed to the Automation account out of band.

---

## config.json Entry

```json
{
  "id": "user-creation",
  "name": "User Creation",
  "description": "Create new employee accounts from a CSV — assigns licenses and security groups, then finishes Exchange setup your way: automatically via Azure or a downloadable script you run yourself.",
  "status": "beta",
  "path": "tools/user-creation/",
  "permissions": ["User.ReadWrite.All", "Group.ReadWrite.All"],
  "accent": "#7c3aed",
  "iconBg": "#2e1065",
  "category": "daily-ops"
}
```

---

## Out of Scope (future tools)

| Function | Notes |
|---|---|
| Re-enable disabled accounts | Separate PS wizard — `Update-MgUser -AccountEnabled` |
| Update existing user properties | Separate hub tool — name, title, location changes |
| License management on existing users | Separate hub tool |
| MFA management | Separate PS wizard — `Remove-MgUserAuthenticationPhoneMethod` |
