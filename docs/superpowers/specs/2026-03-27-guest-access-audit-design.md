# Guest Access Audit — Design Spec
Date: 2026-03-27

## Goal

Build `tools/guest-audit/index.html` — a tool for auditing B2B guest accounts in the M365 tenant. IT staff can view guest health at a glance, identify stale or risky accounts, inspect group memberships, and take direct action (disable or delete) without leaving the hub.

---

## Architecture

- **Single file:** `tools/guest-audit/index.html` — no new shared files
- **Auth:** Session consumer only — inherits hub MSAL session via localStorage. No sign-in UI on the tool page. If no session found on load, redirect to `../../` (hub)
- **Graph scopes:** `User.Read.All`, `Directory.Read.All`, `AuditLog.Read.All`
- **Access:** Open to all signed-in IT staff — no security group gate
- **Patterns:** Follows License Audit and MFA Status Report conventions exactly (HTML structure, JS patterns, retry logic, table rendering, CSV export)

---

## Data Flow

1. Page loads → `ITTools.auth.init()` → if no session, redirect to hub
2. User configures scan (stale threshold, optional department filter)
3. Click "Run Scan" → fetch all guests from Graph
4. Client-side: compute risk signals per guest, render stats row and table
5. User can sort/filter table, expand group modal, export CSV, disable or delete accounts

### Graph Calls

```
GET /users?$filter=userType eq 'Guest'
    &$select=id,displayName,userPrincipalName,companyName,department,
             accountEnabled,assignedLicenses,signInActivity,createdDateTime
    &$top=999
    &$count=true
```

Group memberships fetched per guest on modal open (lazy per-guest, not bulk):
```
GET /users/{id}/memberOf?$select=id,displayName
```

---

## Layout

```
┌─────────────────────────────────────────────────────┐
│ TOPBAR  [🔲]  IT Tools / Guest Access Audit  [☀️] [User] [Sign Out] │
├─────────────────────────────────────────────────────┤
│  Guest Access Audit                                  │
│  Identify stale B2B guest accounts...               │
├─────────────────────────────────────────────────────┤
│  CONFIGURE CARD                                     │
│  [Stale threshold ▾]  [Dept filter]  [Run Scan]    │
├─────────────────────────────────────────────────────┤
│  STATS ROW (shown after scan)                       │
│  [Total Guests]  [Never Signed In]  [Stale]  [Licensed] │
├─────────────────────────────────────────────────────┤
│  TABLE (sortable, filterable)                       │
│  Guest | Company | Last Sign-In | Days | Created |  │
│  Groups | Licenses | Account | Actions              │
└─────────────────────────────────────────────────────┘
```

---

## Components

### Stats Row
Four stat cards shown after scan completes:
- **Total Guests** — count of all guest accounts (gray)
- **Never Signed In** — guests with null `signInActivity` (red)
- **Stale Accounts** — guests inactive beyond threshold (amber)
- **Licensed Guests** — guests with ≥1 license assignment (blue)

### Configure Card
- **Stale threshold** — select: 30 / 60 / 90 (default) / 180 / 365 days
- **Department filter** — text input, optional, filters on `department` field
- **Run Scan** button → triggers data fetch and render
- **Cancel** button — appears during scan, sets cancellation flag

### Results Table
All columns sortable (click header toggles asc/desc). Columns:

| Column | Source | Notes |
|--------|--------|-------|
| Guest | `displayName` + `userPrincipalName` | Avatar initials + name + email |
| Company | `companyName` | Muted if empty |
| Last Sign-In | `signInActivity.lastSignInDateTime` | "Never" if null |
| Days Inactive | Computed from last sign-in | Age badge: red >threshold, amber >30d, green otherwise |
| Created | `createdDateTime` | Formatted date |
| Groups | Fetched on modal open | "View" button → group modal (no pre-fetch during scan) |
| Licenses | `assignedLicenses.length` | Badge count or "None" |
| Account | `accountEnabled` | `pill-active` / `pill-disabled` status pill |
| Actions | — | Disable button + Delete button |

### Group Modal
- Triggered by clicking the Groups pill on any row
- Shows guest display name as modal title
- Fetches `GET /users/{id}/memberOf` on open (with loading state)
- Lists group display names in a scrollable list
- Close button dismisses

### Risk Signals (per row)
Each guest row gets inline risk badges where applicable:
- 🔴 **Never signed in** — `signInActivity` is null
- 🟠 **Stale** — last sign-in older than threshold
- 🟡 **Licensed** — has license assignments
- 🔵 **Old invite** — `signInActivity` is null AND `createdDateTime` is >365 days ago (invited but never signed in)

### Actions
Both actions require confirmation modal before executing:

**Disable:**
- Modal: "Disable [Name]? This will block their sign-in. The account will remain in the tenant."
- API: `PATCH /users/{id}` → `{ accountEnabled: false }`
- On success: row Account pill updates to Disabled, Disable button hides, Enable button appears

**Delete:**
- Modal: "Permanently delete [Name]? This cannot be undone."
- API: `DELETE /users/{id}`
- On success: row removed from table, stats updated

### CSV Export
Filename: `Guest_Access_Audit_YYYY-MM-DD.csv`
Columns: Display Name, UPN, Company, Department, Last Sign-In, Days Inactive, Created, Licenses (count), Account Status, Risk Signals

---

## Error Handling

- **No session on load** → redirect to `../../`
- **403** → banner: "Permission denied — check Graph API consents in your Entra app registration"
- **429** → exponential backoff retry (max 5 attempts), phase label shows countdown
- **No guests found** → empty state: "No guest accounts found in your tenant"
- **Group fetch fails** → modal shows "Could not load groups" inline error, does not crash table
- **Action fails** → inline error on the row, does not affect other rows

---

## Out of Scope

- Bulk disable/delete (single account actions only for v1)
- Re-enable a previously disabled guest (can be added later)
- Showing guest's external organisation/domain details beyond `companyName`
- Guest invite history or resending invitations
- Security group gating (open access for now, can add later)
