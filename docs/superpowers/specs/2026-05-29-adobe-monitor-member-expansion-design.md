# Adobe License Monitor — Member Expansion Design Spec

**Date:** 2026-05-29
**Tool:** `tools/adobe-license-monitor/index.html`
**Status:** Approved, pending implementation plan

---

## Overview

Expand the Adobe License Monitor from a read-only utilization dashboard into an actionable group management tool. Technicians can expand each product card to see who is in the associated Entra security group, immediately identify disabled accounts wasting seats, and remove members directly — without needing access to the Adobe Admin Console or Entra portal.

---

## Goals

- Surface disabled accounts consuming Adobe licenses so techs can act immediately
- Enable Entra group removal from within the tool (auto-provisioning handles Adobe deprovisioning)
- Keep the workflow natural: one product card → expand → see members → clean up
- Maintain existing utilization and drift data unchanged

---

## Non-Goals

- No Adobe UMAPI write operations (Entra removal + auto-provisioning is sufficient)
- No bulk-remove / select-all (single-row removal only for this phase)
- No cross-product member comparison
- No export of the member list (can revisit later)

---

## Layout Changes

### Shell Width

Increase `max-width` from `860px` to `1200px`. The extra space accommodates the member table columns without crowding the three-panel product card above it.

### Product Card Structure

Each product card gains an **expand strip** — a full-width row appended below the existing three-panel layout (identity | utilization | entra). The strip is always visible and serves as the expand trigger.

```
┌─────────────────────────────────────────────────────────────────┐
│  Identity  │  Adobe Utilization  │  Entra Group Count           │
├─────────────────────────────────────────────────────────────────┤
│  ▾ View 550 group members    [3 disabled]          [chevron]   │  ← expand strip
├─────────────────────────────────────────────────────────────────┤
│  Member table (collapsible, smooth reveal)                      │
└─────────────────────────────────────────────────────────────────┘
```

**Expand strip states:**
- **Collapsed (default):** Neutral surface2 background, muted text, member count, red disabled badge if any disabled accounts exist
- **Expanded:** Blue-light background, blue-dark text, chevron rotated 180°

All three product cards are independently expandable — no accordion constraint.

---

## Data Loading

### Strategy: On-demand with in-memory cache

Member data fetches when a tech first expands a card. Once loaded, the data is cached in a per-card JS object for the lifetime of the page — collapse/re-expand is instant. Nothing prefetches on page load.

### Graph Calls (triggered on first expand)

**Call 1 — Group members:**
```
GET /groups/{groupId}/members
    ?$select=id,displayName,userPrincipalName,accountEnabled
    &$top=999
```
Follows `@odata.nextLink` if pagination is required (groups over 999 members).

**Call 2 — Sign-in activity (batched):**
```
GET /users
    ?$filter=id in ('{id1}','{id2}',...)
    &$select=id,signInActivity
```
Chunked into groups of 15 IDs per call (Graph `$filter` `in` operator limit). Calls fire in parallel. Results merged into the member list by `id`.

**Required scope:** `AuditLog.Read.All` — already requested in the tool's existing scope list.

### Loading State

While fetching, the expand strip shows a spinner and "Loading members…" text. The member section below renders a shimmer skeleton (3 placeholder rows) matching the table height.

---

## Member Table

### Columns

| Column | Width | Notes |
|--------|-------|-------|
| Member | 240px | Avatar circle (initials) + display name |
| UPN | 220px | Truncated with ellipsis |
| Account | 100px | Enabled / Disabled badge |
| Last Sign-In | 140px | Relative ("Today", "3 days ago", "142 days ago") or "Never" |
| Action | auto | Remove button or locked button |

### Sorting

- **Default:** Disabled accounts first, then alphabetical by display name within each group
- **Column sort:** All headers are clickable — chevron indicates active sort column and direction, matching the pattern in License Spend and Guest Audit
- Sort state is per-card and persists while the page is open

### Disabled Row Treatment

Rows where `accountEnabled === false`:
- Subtle red background tint (`rgba(138,36,36,.04)`)
- Red avatar background (`var(--red-light)`) with red initials
- `Disabled` badge (red pill)
- Last sign-in shown in red if > 30 days or "Never"

### Table Container

- `max-height: 360px` with `overflow-y: auto`
- Sticky column headers (`position: sticky; top: 0`)
- Consistent with MFA Status Report and Guest Audit table patterns

### Table Footer

Persistent strip below the table:
- Left: "N members · N disabled accounts shown first"
- Right: "License Admin" pill (shown if user has `SG-IT-Tools-License-Modify`) + "Remove enabled" label

---

## Remove Action

### Permission Gating

Gated behind `SG-IT-Tools-License-Modify` (same group used in License Audit).

- **Has permission:** Active red `Remove` button on every row
- **No permission:** Greyed-out button with lock icon, `title="Requires License Admin access"`, `cursor: not-allowed`

Permission check reuses the existing `checkMemberObjects` pattern from `shared/auth.js` — no new gate infrastructure needed.

### Removal Flow

1. Tech clicks `Remove` on a member row
2. Compact confirmation modal appears:
   - Member name + UPN
   - Group name being removed from
   - "Remove from group" confirm button (red) + Cancel
3. On confirm: `DELETE /groups/{groupId}/members/{userId}/$ref`
4. On success:
   - Row fades out and is removed from the DOM
   - Member count in expand strip decrements
   - Disabled count badge decrements if the removed user was disabled
   - Entra group count in the card header decrements
   - Drift calculation updates inline
5. On failure: Inline row-level error banner ("Could not remove — try again"), button re-enables

### Graph Call

```
DELETE https://graph.microsoft.com/v1.0/groups/{groupId}/members/{userId}/$ref
```

Required permission: `GroupMember.ReadWrite.All` — already in the tool's existing scope list.

---

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| Member load fails | Error banner inside table area with Retry button; expand strip shows error state |
| signInActivity call fails | Members still show, Last Sign-In column shows "—" with a warning tooltip |
| Remove fails (429, 5xx) | Inline row error, button re-enables, no row removed |
| Remove fails (403) | Inline error: "Permission denied — contact your IT administrator" |
| User has no group access | Card still shows utilization; expand strip shows "Members unavailable" |

---

## Updated Scope Declaration

Current `TOOL_SCOPES` in the tool: `["User.Read", "GroupMember.Read.All"]`

Three scopes must be added:

| Scope | Reason |
|-------|--------|
| `User.Read.All` | Read other users' `displayName`, `userPrincipalName`, `accountEnabled` |
| `AuditLog.Read.All` | Required for `signInActivity` on user objects |
| `GroupMember.ReadWrite.All` | Enables `DELETE /groups/{id}/members/{userId}/$ref` |

Updated declaration:
```js
const TOOL_SCOPES = [
  "User.Read",
  "User.Read.All",
  "AuditLog.Read.All",
  "GroupMember.Read.All",
  "GroupMember.ReadWrite.All",
];
```

The Entra app registration (`7ad27c90-0ddd-4a3f-8e74-1213de4130f8`) will need admin consent granted for `AuditLog.Read.All` and `GroupMember.ReadWrite.All` before the member table and remove action work in production.

---

## Files Changed

| File | Change |
|------|--------|
| `tools/adobe-license-monitor/index.html` | All changes — shell width, expand strip, member table, remove flow |

No changes to `shared/auth.js`, `shared/styles.css`, or `config.json`.

---

## Out of Scope for This Phase

- Bulk remove / select all
- Export member list to CSV
- Filter tabs (disabled / enabled) — sort-to-top handles this adequately
- Adobe UMAPI write operations
- Pagination controls (scroll is sufficient given group sizes)
