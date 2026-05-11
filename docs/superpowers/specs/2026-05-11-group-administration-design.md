# Group Administration Tool — Design Spec

**Date:** 2026-05-11
**Replaces:** Group Import (`tools/group-import/index.html`)
**Status:** Approved

---

## Overview

Expand the existing Group Import wizard into a full Group Administration tool. Techs can add members (CSV/paste bulk or single-user search) and remove members (bulk paste or interactive member list) from the same tool. Also fixes a drag-and-drop bug present in the current tool.

The tool lives at the same path (`tools/group-import/index.html`) and hub card. Only the name, description, and UI change.

---

## Bug Fix: CSV Drag-and-Drop

**File:** `shared/styles.css`, lines 464–466

**Problem:** `.file-drop input[type="file"]` is styled with `position:absolute; inset:0; opacity:0` — a transparent full-zone overlay that intercepts all pointer events. This makes drag events unreliable cross-browser (the overlay catches `dragover`/`drop` before the handler on the parent div) and makes the "browse" click path inconsistent.

**Fix:**
```css
/* Before */
.file-drop input[type="file"] {
  position: absolute; inset: 0; opacity: 0; cursor: pointer; width: 100%; height: 100%;
}

/* After */
.file-drop input[type="file"] {
  display: none;
}
```

The `<strong onclick="document.getElementById('fileIn').click()">browse</strong>` link in the HTML already triggers the input explicitly — this path continues to work. Drag-and-drop uses the `ondrop` handler on the `.file-drop` div, which now receives events correctly.

---

## Layout

The 3-step sidebar wizard is replaced with a single-card layout:

```
┌─────────────────────────────────────────────────────────┐
│  [Group picker input]          [Look up button]         │
│  ✓ IT Support Team  (group confirmed banner)            │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────────────────┐  ┌────────────────────┐   │
│  │ + Add Members  (green)   │  │ − Remove Members   │   │  ← pill toggle
│  └──────────────────────────┘  └────────────────────┘   │
├─────────────────────────────────────────────────────────┤
│  [Tab panel — green or red tint depending on mode]      │
│                                                         │
│  Add tab:    [CSV / paste zone]  |  [User search]       │
│  Remove tab: [Bulk paste zone]   |  [Live member list]  │
│                                                         │
│                          [Action button (Add/Remove)]   │
├─────────────────────────────────────────────────────────┤
│  [Results / audit log table — shown after each run]     │
└─────────────────────────────────────────────────────────┘
```

---

## Group Picker

Reuses the existing lookup logic from Step 2 of the current tool:

- Text input: "Group name or GUID"
- "Look up" button calls `GET /groups/{id}` (GUID path) or `GET /groups?$filter=displayName eq '{name}'`
- On success: green confirmed banner shows display name + object ID
- Group must be confirmed before Add or Remove actions are enabled
- Group can be changed at any time (clears member list cache, re-enables picker)

---

## Tab Toggle

Pill row below the group picker. Same pattern as License Spend and Name Resolver mode toggles.

- **Green pill** — "＋ Add Members" (active state: green background, white text; panel background: `rgba(22,163,74,0.04)`)
- **Red pill** — "− Remove Members" (active state: red background, white text; panel background: `rgba(220,38,38,0.03)`)
- Inactive pill: muted text, no background
- Switching tabs does not reset the group picker or clear the results log

---

## Add Members Tab

Two-column layout inside the green-tinted panel.

### Left — Bulk CSV / Paste

- Drag-and-drop zone (reuses `.file-drop` pattern with the bug fix applied)
- CSV files: parsed with `ITTools.csv.parse()`, column auto-detected via `ITTools.csv.detectEmailColumn()`
- Paste: `<textarea>` accepting raw name/email list, parsed line-by-line (strips blank lines, trims whitespace)
- Resolution chips shown after parsing: green chip = Graph-resolved user, red chip = unresolved identifier
- Chips are dismissible (remove unresolved entries before proceeding)

### Right — Single User Search

- Text input with debounced (300 ms) Graph search:
  `GET /users?$search="displayName:{q}"&$select=id,displayName,userPrincipalName,mail&$top=8`
  Requires `ConsistencyLevel: eventual` header.
- Each result row: avatar circle (initials), display name, UPN, inline "Add" button
- "Add" button calls `POST /groups/{groupId}/members/$ref` immediately for that one user, shows inline success/error state on the row, and appends an entry to the results log below

### Add to Group Button

- Enabled when at least one resolved user is staged in the bulk area
- Calls `POST /groups/{groupId}/members/$ref` for each resolved user
- Same progress + results log as current tool (Added / Skipped-already-member / Error)
- Existing membership pre-check: `GET /groups/{id}/members?$select=id&$top=999` (paginated) run before batch, same as current tool

---

## Remove Members Tab

Two-column layout inside the red-tinted panel.

### Left — Bulk Paste

- `<textarea>` for pasting a list of emails/UPNs to remove
- Same resolution logic as Add bulk flow (Graph lookup per identifier)
- Resolution chips shown: green = resolved + is a member, amber = resolved but not a member, red = unresolved
- "Remove" applies to green chips only

### Right — Live Member List

- Loaded when a group is confirmed: `GET /groups/{groupId}/members?$select=id,displayName,userPrincipalName,mail&$top=100`
- Paginated — "Load more" if `@odata.nextLink` present
- Search filter input above list (client-side filter on loaded members by displayName/UPN)
- Each row: checkbox, avatar initials, display name, UPN
- Checked rows highlight with red background tint (`rgba(220,38,38,0.08)`)
- Member count shown in column header: "Members (24)"

### Remove from Group Button

- Enabled when at least one checkbox is checked (live list) or at least one green chip exists (bulk paste)
- Calls `DELETE /groups/{groupId}/members/{userId}/$ref` for each selected user
- Results log entries: Removed / NotMember / Error

---

## Results / Audit Log

Shown below the tab panel after any Add or Remove operation completes. Same format as current tool:

| Column | Notes |
|--------|-------|
| Status | Added / Removed / Skipped / NotFound / Error — color-coded pills |
| Identifier | Email or UPN from input |
| Display Name | Resolved from Graph |
| Message | Human-readable outcome |
| Timestamp | ISO timestamp of operation |

- Filter input (client-side)
- "Export CSV" button — filename: `GroupAdmin_Add_YYYY-MM-DD.csv` or `GroupAdmin_Remove_YYYY-MM-DD.csv`
- Log is replaced (not appended) on each new operation run

---

## Hub Card

`config.json` update:

```json
{
  "name": "Group Administration",
  "description": "Add and remove members from Entra ID security groups. Supports bulk CSV/paste and live member browser.",
  "path": "tools/group-import/",
  "section": "Daily Operations",
  "status": "beta"
}
```

Auth screen title and description updated to match new tool name.

---

## Auth / Permissions

No changes to app registration. All required scopes already declared:

- `User.Read.All` — user resolution
- `Group.ReadWrite.All` — group lookup
- `GroupMember.ReadWrite.All` — add and remove members
- `Directory.Read.All` — group search

Access gate: GSD Access (`SG-IT-Tools-GSD`, `3e1a4757-8189-4908-a611-b6029399e69e`) — unchanged.

---

## What Is Not Changing

- File path (`tools/group-import/index.html`) — no redirect needed
- Shared modules (`shared/auth.js`, `shared/styles.css`) — only the one `.file-drop` rule changes
- Graph permissions / MSAL scopes
- GSD access gate
- Export CSV format
- Dark mode (inherits from shared CSS variables)
