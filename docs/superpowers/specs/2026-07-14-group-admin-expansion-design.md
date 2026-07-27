# Group Administration Tool — Expansion Design

**Date:** 2026-07-14
**Status:** Design approved (brainstorm) — pending spec review → implementation plan
**Supersedes scope of:** the current single-purpose "Group Import" tool (`tools/group-import/index.html`)

## Purpose

Expand the current tool — which only **adds** members to a single **Entra security group** from a CSV — into a one-stop membership & permission management tool spanning five Microsoft 365 object types, each supporting **add / remove / export**, presented as a card launcher that drops into a per-type wizard.

## Scope

### Object types (5)

| # | Object type | Backend | Operations run |
|---|-------------|---------|----------------|
| 1 | Entra ID security group | Microsoft Graph | Live in browser |
| 2 | Microsoft 365 group | Microsoft Graph | Live in browser |
| 3 | Distribution list | Exchange Online | Generated PowerShell script |
| 4 | Mail-enabled security group | Exchange Online | Generated PowerShell script |
| 5 | Shared mailbox (access permissions) | Exchange Online | Generated PowerShell script |

### Operations (3)

- **Add** (grant, for shared mailbox)
- **Remove**
- **Export** (current membership / access list to CSV)

## Key architectural decision — the backend split

This is a static, browser-based tool authenticating via MSAL and calling Microsoft Graph. That split is hard and non-negotiable:

- **Graph-native (security groups, M365 groups):** every operation runs **live in the browser** — resolve identities, dry-run preview, live add/remove, in-browser result log + CSV export. Extends the current tool's behavior.
- **Exchange-only (distribution lists, mail-enabled security groups, shared mailboxes):** Graph has **no write path**. Every operation **generates a ready-to-run PowerShell `.ps1`** that the tech executes in their **own authenticated Exchange Online session**.

**Why script generation, not a live Exchange backend:** A browser-triggered Azure Function/Automation endpoint that could edit DLs and grant mailbox access tenant-wide is a serious new security surface (caller authorization, a managed identity with broad EXO write roles, CORS, hardening). Script generation adds **zero new attack surface**, ships without new infra, runs each privileged action in the tech's own context, and matches the existing mailbox-cleanup workflow techs already know. A live Exchange backend (Azure Function/Automation, app-only EXO) is a **documented future upgrade**, not v1.

**Consistency rule:** backend is chosen **per object type**, uniformly across all its operations. Graph types are live for add/remove/export; Exchange types generate a script for add/remove/export (including export). This keeps the card's Live/Script tag honest and the mental model clean. (Possible future optimization: live Graph reads for Exchange-type *exports*, since Graph can read DL and mail-enabled SG members — deferred for uniformity.)

## UX / Navigation

### Landing — card launcher

- A grid of object-type cards, styled as slightly smaller versions of the IT Tools Hub landing cards so the UI flow carries through.
- Grouped by backend, with a functional tag on each card:
  - **Live · Graph:** Security Group, Microsoft 365 Group
  - **Script · Exchange:** Distribution List, Mail-enabled Security Group, Shared Mailbox
- The Live/Script tag is functional (tells the tech whether they get a live run or a downloadable script), not decorative.
- Clicking a card enters that type's wizard. A "← All object types" control returns to the launcher.

### Per-type wizard — group-like types (security group, M365 group, distribution list, mail-enabled security group)

1. **Action** — Add members / Remove members / Export members
2. **Target** — look up the group/list by name or GUID
3. **Source CSV** — drop a CSV of members (Add/Remove only; skipped for Export)
4. **Run / Generate:**
   - Graph types → **Dry Run → Live Run**, in-browser result log + CSV export (current pattern)
   - Exchange types → **Generate PowerShell (.ps1)**

### Per-type wizard — shared mailbox

Swaps "members" for **access permissions**:

1. **Action** — Grant access / Remove access / Export access list
2. **Target** — look up the shared mailbox
3. **Permission type** — Full Access / Send As / Send on Behalf (all three supported, selectable). **AutoMapping** toggle (Full Access only), **default ON** (the majority of bulk adds want it; outliers with AutoMapping issues are the minority).
4. **Users CSV** — the trustees to grant/remove (Grant/Remove only)
5. **Generate PowerShell (.ps1)**

## Components

Reuse existing shared modules: `ITTools.auth` (MSAL), `ITTools.graph`, `ITTools.csv`, `ITTools.ui`, `shared/styles.css`.

New/changed:

- **Launcher view** — the object-type card grid.
- **Object-type registry** — a config object, one entry per type: `label`, `icon`, `backend` (`graph` | `exchange`), supported operations, target lookup method, source model (`members` | `permissions`), and (for Exchange types) the script template + cmdlet mapping.
- **Wizard controller** — renders the tailored steps for the selected type from its registry entry.
- **Graph operations module** — resolve / add / remove / export for group types (reuses and extends the current add logic; adds remove + export).
- **PowerShell script generator** — builds the `.ps1` for Exchange types from the resolved inputs.

### Generated script shape (Exchange types)

Each generated `.ps1`:
- Header comment: what it does, target, operation, generated timestamp, generating tech.
- `Connect-ExchangeOnline` (tech's own context).
- `Start-Transcript` for audit.
- A **`-WhatIf` dry-run block first**, then the live commands, per resolved item, with per-item try/catch.
- Cmdlet mapping:
  - Distribution list / mail-enabled security group: `Add-DistributionGroupMember` / `Remove-DistributionGroupMember`; export via `Get-DistributionGroupMember`.
  - Shared mailbox Full Access: `Add-MailboxPermission -AccessRights FullAccess -AutoMapping $true|$false` / `Remove-MailboxPermission`.
  - Shared mailbox Send As: `Add-RecipientPermission -AccessRights SendAs` / `Remove-RecipientPermission`.
  - Shared mailbox Send on Behalf: `Set-Mailbox -GrantSendOnBehalfTo @{Add=…}` / `@{Remove=…}`.
  - Shared mailbox export: `Get-MailboxPermission` + `Get-RecipientPermission`.

### Delivery — script + self-running launcher

Every Exchange-type "Generate" produces **both** the `.ps1` **and** a self-running `Run-<operation>.bat` launcher (same pattern as `Run-MailboxCleanup.bat`), so the tech can double-click to execute immediately after building it in the wizard — no manual PowerShell invocation. The batch runs the co-located script, e.g. `pwsh -ExecutionPolicy Bypass -File "%~dp0<script>.ps1"`.

Delivery mechanism (to finalize in the plan): a **single downloadable `.zip` bundling the `.ps1` + `.bat`** is preferred so the two stay co-located and the batch's `%~dp0` reference resolves; fall back to paired downloads with fixed filenames if in-browser zipping is undesirable.

## Data flow

- **Graph (live):** CSV → resolve identities via Graph (UPN/mail) → pre-check existing membership → dry-run preview → live add/remove via Graph `$ref` endpoints → in-browser result log → CSV export.
- **Exchange (script):** CSV → normalize/validate identities in-browser → generate `.ps1` embedding the resolved list + cmdlets + `-WhatIf` block + transcript → tech downloads and runs → reviews transcript output.

## Error handling

- **Graph live:** per-identity `NotFound`, already-member skip, guest handling, Graph errors surfaced per-row (existing result-log pattern). Dry run required before live.
- **Script generation:** validate CSV/identities in-browser before generating; the script itself carries the `-WhatIf` dry run, per-item error handling, and transcript.
- **File upload:** keep the `file.text()` + visible-error-banner pattern (resilience against AV interference — prior HitmanPro learnings). Never fail silently.

## Reuse of the existing tool

The current `tools/group-import/index.html` becomes the Security Group / M365 Group **live path**, refactored into the new launcher + wizard shell. The existing Graph add logic is reused; **remove** and **export** operations are added.

## Open implementation decisions (for the planning phase)

- **Folder / identity:** keep the `group-import` path (URL stability) vs. rename to `group-admin` and rebrand the hub card ("Group Administration"). Requires updating the hub tool config either way if renamed.
- **Graph scopes:** current scopes (`User.Read.All`, `Group.ReadWrite.All`, `GroupMember.ReadWrite.All`, `Directory.Read.All`) cover security + M365 group add/remove/export. No new scopes needed if Exchange operations are script-only.

## Non-goals / deferred

- Live Azure Exchange backend (Option C).
- Visual polish pass — after the functional build.
- Live Graph reads for Exchange-type exports.
- Batch operations spanning multiple object types in a single run.

## Testing

- Manual matrix: each object type × each operation.
  - Graph types: dry-run then live against a test group.
  - Exchange types: generate script, run `-WhatIf` then live against a test DL / shared mailbox, verify transcript.
- CSV parsing edge cases (existing `ITTools.csv` helper).
- Auth scopes and sign-in flow.

## Decision log (brainstorm 2026-07-14)

1. All five object types in scope.
2. Backend = **per-run PowerShell script generation** for Exchange types (security over a live backend); Graph types stay live in-browser. Live Exchange backend deferred.
3. Navigation = **card launcher → per-type wizard** hybrid (cards echo the Hub landing).
4. Cards carry a functional **Live/Script** tag.
5. Shared mailbox: **all three permission types** supported; **AutoMapping default ON**.
6. Exchange "Generate" ships a **self-running `.bat` launcher** alongside the `.ps1` (double-click to run), preferably bundled in a single `.zip`.
