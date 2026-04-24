# Reporting Gate & GSD Access Control — Design Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `SG-IT-Tools-Reporting-View` gate on the 3 ungated reporting/audit tools, wire `SG-IT-Tools-GSD` into the gate system for future use, add gold lock styling for reporting-gated cards, and add Reporting View + GSD Access badges across the hub and tools.

**Architecture:** Follows the existing `financeOnly` / `GROUP_GATES` pattern — new flags in config.json, new entries in `GROUP_GATES`, locked cards unlock on group membership confirmed via Graph. Defense-in-depth: hub locks cards, tools enforce access on their own sign-in flow.

**Tech Stack:** Vanilla JS, Microsoft Graph (`/me/checkMemberObjects`), localStorage gate caching, Lucide SVG icons inline.

---

## Groups

| Group name | Purpose | New? |
|---|---|---|
| `SG-IT-Tools-Finance-View` | Gates License Spend (existing, unchanged) | No |
| `SG-IT-Tools-License-Modify` | Gates license management actions (existing, unchanged) | No |
| `SG-IT-Tools-Reporting-View` | Gates M365 License Audit, MFA Status Report, Guest Access Audit | Yes |
| `SG-IT-Tools-GSD` | Identifies global service desk members; no tools gated yet | Yes |

The admin creates both new groups in Entra. Object IDs are substituted into the code once created.

---

## Tool Gating Matrix

| Tool | Category | Gate |
|---|---|---|
| Group Import | daily-ops | None — open to all signed-in users |
| Name Resolver | daily-ops | None — open to all signed-in users |
| M365 License Audit | reporting-audit | `SG-IT-Tools-Reporting-View` |
| MFA Status Report | reporting-audit | `SG-IT-Tools-Reporting-View` |
| Guest Access Audit | reporting-audit | `SG-IT-Tools-Reporting-View` |
| License Spend | reporting-audit | `SG-IT-Tools-Finance-View` (existing, unchanged) |

---

## config.json Changes

Add `reportingOnly: true` to the three newly gated tools:

```json
{ "id": "license-audit", ..., "reportingOnly": true }
{ "id": "mfa-status",    ..., "reportingOnly": true }
{ "id": "guest-audit",   ..., "reportingOnly": true }
```

`finance-dashboard` keeps `financeOnly: true` only — no change.

---

## Hub (index.html) Changes

### GROUP_GATES addition

```js
const GROUP_GATES = {
  "finance": {
    id:       "ff9c3232-251f-4570-9564-340039d17aa9",
    localKey: "it-tools-finance-unlocked",
  },
  "reporting": {
    id:       "<SG-IT-Tools-Reporting-View Object ID>",
    localKey: "it-tools-reporting-unlocked",
  },
  "gsd": {
    id:       "<SG-IT-Tools-GSD Object ID>",
    localKey: "it-tools-gsd-unlocked",
  },
};
```

### Card rendering

`buildLockedCard()` is called when `tool.financeOnly || tool.reportingOnly`. The gate key passed to the card is:
- `"finance"` for `financeOnly` tools
- `"reporting"` for `reportingOnly` tools

### Gold lock styling for reporting-gated cards

Reporting-gated locked cards get a modifier class `locked--reporting`. The lock icon renders in `var(--amber)` (gold/amber on theme) instead of the default muted color.

```css
.tool-card.locked--reporting .lock-hint {
  color: var(--amber);
}
```

Hover tooltip on the lock element:
```
"Requires reporting access — contact your IT administrator"
```

Finance-gated cards keep their existing lock styling unchanged.

### Hub badges

After `runGateChecks()` resolves, render access badges in the hub's user/topbar area for each gate the signed-in user holds:

| Gate unlocked | Badge label | Lucide icon |
|---|---|---|
| `finance` | Finance View | `shield` |
| `reporting` | Reporting View | `eye` |
| `gsd` | GSD Access | `globe` |

Badges render as small amber/blue pills consistent with the existing topbar badge style. No badge shown if user doesn't hold the access.

---

## Tool-Level Enforcement

Each of the 3 newly gated tools (License Audit, MFA Status Report, Guest Access Audit) checks `SG-IT-Tools-Reporting-View` membership on sign-in using the existing `checkMemberObjects` pattern:

```js
const REPORTING_GROUP_ID = "<SG-IT-Tools-Reporting-View Object ID>";

async function checkReportingAccess() {
  const token = await ITTools.auth.getToken();
  const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
    method: "POST",
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: JSON.stringify({ ids: [REPORTING_GROUP_ID] }),
  });
  if (!res.ok) return false;
  const data = await res.json();
  return (data.value || []).includes(REPORTING_GROUP_ID);
}
```

If check returns `false` → show access-denied full-page screen with link back to hub (same pattern as Finance Dashboard). If `true` → proceed with normal tool initialization.

---

## Badges in Tools

### Reporting View badge

Shown in each of the 3 reporting tools when the user passes the access check. Renders in the topbar next to the tool name — consistent with the Finance View and License Admin badge pattern in License Audit.

```html
<span id="reportingViewIndicator" class="badge badge--blue" style="display:none">
  <!-- Lucide eye SVG -->
  Reporting View
</span>
```

Set to visible after `checkReportingAccess()` returns `true`.

### Existing badges in License Audit

License Audit already shows Finance View and License Admin badges. Reporting View badge is added as a third indicator — shown when user also holds `SG-IT-Tools-Reporting-View`.

### GSD Access badge — shown in every tool

The GSD Access badge renders in the topbar of **every tool** when the signed-in user is a GSD member. This is their designation indicator regardless of which tool they're using.

Implementation: each tool batches the GSD group ID into its existing `checkMemberObjects` call. Tools that currently make no group check (Group Import, Name Resolver) get a lightweight GSD-only `checkMemberObjects` call on sign-in. If the response includes the GSD group ID, the badge renders.

```js
const GSD_GROUP_ID = "<SG-IT-Tools-GSD Object ID>";

// In tools with an existing group check — add GSD_GROUP_ID to the ids array:
body: JSON.stringify({ ids: [REPORTING_GROUP_ID, GSD_GROUP_ID] })

// In tools with no existing group check (Group Import, Name Resolver):
async function checkGsdAccess() {
  const token = await ITTools.auth.getToken();
  const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
    method: "POST",
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: JSON.stringify({ ids: [GSD_GROUP_ID] }),
  });
  if (!res.ok) return false;
  const data = await res.json();
  return (data.value || []).includes(GSD_GROUP_ID);
}
```

```html
<span id="gsdIndicator" class="badge badge--blue" style="display:none">
  <!-- Lucide globe SVG -->
  GSD Access
</span>
```

---

## What GSD Does Now vs. Later

**Now:** `SG-IT-Tools-GSD` is added to `GROUP_GATES` on the hub and checked in every tool on sign-in. The GSD Access badge renders in the hub topbar and in every individual tool topbar for GSD members. No tools are gated behind this group yet.

**Later:** Any new tool built for the GSD team gets a `gsdOnly: true` flag in config.json and the existing unlock flow handles it automatically — no further hub plumbing needed.

---

## Unchanged

- Finance Dashboard gate, access-denied screen, and Finance View badge behavior — no changes
- License Modify gating and License Admin badge in License Audit — no changes
- Group Import and Name Resolver — remain ungated, open to all signed-in users
- Shared auth.js — no changes required
