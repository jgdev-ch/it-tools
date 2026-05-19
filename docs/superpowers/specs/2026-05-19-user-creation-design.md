# User Creation Tool — Design Spec
**Date:** 2026-05-19
**Status:** Approved

## Overview

A 4-step hub web tool that replaces the legacy `NewAccounts` PowerShell script. The hub handles everything reachable via Microsoft Graph (user creation, licensing, security groups). At completion it generates a single ZIP download containing a pre-populated Exchange setup script, a `.bat` launcher, and a credentials CSV — so the tech runs one file to finish the Exchange-only steps.

This tool covers **account creation only**. Updating existing users, re-enabling disabled accounts, managing licenses on existing users, and MFA management are separate future tools.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│  Hub (browser — Microsoft Graph)            │
│  Step 1: Upload & validate CSV              │
│  Step 2: Review & edit (bulk + per-row)     │
│  Step 3: Create accounts (live progress)    │
│  Step 4: Generate & download ZIP            │
└────────────────────┬────────────────────────┘
                     │ ZIP download
                     ▼
┌─────────────────────────────────────────────┐
│  NewAccountsSetup-YYYY-MM-DD.zip            │
│  ├── Exchange-Setup.ps1  (pre-populated)    │
│  ├── Run-Exchange-Setup.bat  (launcher)     │
│  └── Credentials.csv  (per-user passwords) │
└─────────────────────────────────────────────┘
                     │ tech extracts + runs bat
                     ▼
┌─────────────────────────────────────────────┐
│  Exchange Online (PowerShell)               │
│  - Distribution group membership           │
│  - Enable-Mailbox archive (50 GB users)     │
│  - Set retention policy (50 GB users)       │
│  - Set-Mailbox CustomAttribute4             │
│    (subcontractors)                         │
└─────────────────────────────────────────────┘
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

## Step 4 — Download Scripts

Single **Download ZIP** button. ZIP generated client-side via JSZip. Button label: `Download NewAccountsSetup-YYYY-MM-DD.zip`.

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
- Credentials CSV is inside the ZIP — single controlled download, not a separate loose file
- Exchange script contains no credentials — it prompts for MFA via `Connect-ExchangeOnline` at runtime
- Graph token acquired via MSAL popup — standard hub auth pattern, no special handling needed

---

## File Location

```
tools/user-creation/
├── index.html           ← hub tool
└── jszip.min.js         ← client-side ZIP library (vendored)
```

JSZip vendored alongside the tool (same approach as `msal-browser.min.js` in shared/) to avoid CDN dependency.

---

## config.json Entry

```json
{
  "id": "user-creation",
  "name": "User Creation",
  "description": "Create new employee accounts from a CSV — assigns licenses, security groups, and generates a ready-to-run Exchange setup script.",
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
