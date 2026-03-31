# Guest Audit — CorroHealth Account Match & Email Tooltip

**Date:** 2026-03-31
**Tool:** `tools/guest-audit/index.html`
**Status:** Approved for implementation

---

## Overview

Two QoL improvements to the Guest Access Audit:

1. **CorroHealth Account Match column** — during the scan, check whether each invited guest has a corresponding internal CorroHealth member account (`firstname.lastname@corrohealth.com`), making it easy to identify redundant guest accounts.
2. **Email tooltip** — hover over any truncated UPN or Company name to see the full text in a clean CSS tooltip.

---

## Feature 1: CorroHealth Account Match

### UPN Parsing

Guest accounts in Entra follow the format:
```
firstname.lastname_externaldomain.com#EXT#@corrohealth.onmicrosoft.com
```

Extract the CorroHealth candidate UPN:
1. Check that the UPN contains `#EXT#` — if not, mark as not applicable (`corroMatch: { found: null }`).
2. Take the local part before `#EXT#`: `firstname.lastname_externaldomain.com`
3. Take everything before the first `_`: `firstname.lastname`
4. Construct: `firstname.lastname@corrohealth.com`

### Graph Batch Lookup

After the initial guest fetch completes, run a second scan phase:

- **Phase label:** `"Checking CorroHealth accounts… (X/Y)"`
- Split guests into batches of 20.
- POST each batch to `https://graph.microsoft.com/v1.0/$batch`.
- Each sub-request: `GET /users/{upn}?$select=id,displayName,userPrincipalName,accountEnabled`
- Parse responses:
  - HTTP 200 → match found; store `displayName` and `accountEnabled`
  - HTTP 404 → no match
  - Other errors → treat as no match, do not throw

### Guest Data Model Extension

Add to each guest object:
```js
corroMatch: {
  found: true | false | null,  // null = UPN couldn't be parsed (no #EXT#)
  displayName: string | null,
  accountEnabled: bool | null
}
```

### Risk Badge

If `corroMatch.found === true`, add a blue `Internal account exists` risk badge to the guest's cell in the Guest column. This is the primary signal that the guest account may be redundant.

No new badge for `found === false` — existing stale/never badges already surface those.

### Cancellation

Respect the existing `_cancelled` flag between batches — if the scan is cancelled mid-pass, stop processing remaining batches and return partial results.

---

## Feature 2: Table Column — "CorroHealth Acct"

### Position & Width

New column inserted between **Account** (col 8) and **Actions** (col 9), becoming col 9. Actions shifts to col 10.

Width: `~100px` — consistent with the Account column.

### Cell States

| State | Render |
|---|---|
| Match, account active | Green pill: `Matched` |
| Match, account disabled | Amber pill: `Disabled` |
| No match | Muted text: `None` |
| Not applicable (no `#EXT#`) | Muted dash: `—` |
| Scan in progress | Inline spinner |

### Sorting

Column is sortable via `setSortCol('corroMatch')`. Sort order: matched-active → matched-disabled → none → N/A.

### Column header CSS selector update

All `nth-child` column width rules shift by one for Actions (previously col 9, now col 10).

---

## Feature 3: Email & Company Tooltip

### CSS Rule

Add a shared `[data-tooltip]` tooltip rule to the page `<style>` block:

```css
[data-tooltip] { position: relative; cursor: default; }
[data-tooltip]::after {
  content: attr(data-tooltip);
  position: absolute; bottom: calc(100% + 6px); left: 50%;
  transform: translateX(-50%);
  background: #1e1e2e; color: #f0f0f0;
  font-size: 11px; padding: 4px 8px; border-radius: 5px;
  white-space: nowrap; pointer-events: none;
  opacity: 0; transition: opacity .12s;
  z-index: 50;
}
[data-tooltip]:hover::after { opacity: 1; }
```

### Applied To

- `.user-upn` element → `data-tooltip="${upn}"` (full UPN/email)
- Company `<td>` → `data-tooltip="${companyName}"` (only when `companyName` is non-empty)

---

## CSV Export Changes

Two new columns appended:

| Column | Values |
|---|---|
| `"CorroHealth Account"` | `Matched` / `None` / `—` |
| `"CorroHealth Account Status"` | `Active` / `Disabled` / `—` |

---

## Column Width Layout (updated)

```
col 1  — Guest          200px
col 2  — Company        110px
col 3  — Last Sign-In   108px
col 4  — Days Inactive  100px
col 5  — Created        108px
col 6  — Groups          68px
col 7  — Licenses        82px
col 8  — Account         90px
col 9  — CorroHealth    100px  ← new
col 10 — Actions        148px  ← shifted
```

---

## Out of Scope

- No UI to change the lookup domain (always `corrohealth.com`)
- No deep-linking to the matched internal account's profile
- No automatic remediation actions for matched guests
