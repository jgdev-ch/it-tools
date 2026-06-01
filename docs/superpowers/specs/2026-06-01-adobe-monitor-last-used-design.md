# Adobe License Monitor — Adobe Last Used Column

**Date:** 2026-06-01  
**Status:** Approved  
**Scope:** `adobe-func` + `tools/adobe-license-monitor/index.html`

## Summary

Two related changes that ship together:

1. **Column rename** — "Last Sign-In" in the member table becomes "Entra Sign-In". Removes the ⓘ tooltip icon; the label is now self-explanatory.
2. **New "Adobe Last Used" column** — shows actual Adobe product activity per user via UMAPI `lastAccessedDate`, loaded from a new Azure Function endpoint `AdobeMembers`.

Together these give a complete picture: Entra Sign-In shows company-wide M365 activity; Adobe Last Used shows whether the user actually touches the Adobe product they're licensed for.

## Why Both Columns Matter

A user can be active in M365 every day (recent Entra Sign-In) but have never opened Acrobat. With only one date column that distinction is invisible. With both columns, IT can immediately identify:

- **Disabled + no Adobe usage** → safe to remove (termed user holding a seat)
- **Enabled + active in M365 + no/stale Adobe usage** → candidate for a reach-out or reclaim
- **Enabled + recent Adobe usage** → keep

## Stale Thresholds (Red)

| Column | Threshold | Rationale |
|--------|-----------|-----------|
| Entra Sign-In | 30 days | M365 auth happens constantly for active employees |
| Adobe Last Used | 90 days | Adobe usage is naturally less frequent; 30 days would flag legitimate occasional users |

## Architecture

### New Azure Function: `AdobeMembers`

**File:** `adobe-func/src/functions/AdobeMembers.js`  
**Endpoint:** `GET /api/AdobeMembers?groupName={productProfileGroupName}`  
**Auth:** EasyAuth v2 on the existing Function App — identical to `AdobeProducts`.

**Flow:**
1. Read `ADOBE_ORG_ID`, `ADOBE_CLIENT_ID`, `ADOBE_CLIENT_SECRET` from env (same app settings)
2. Fetch UMAPI token via `client_credentials` (same as `AdobeProducts.js`)
3. Paginate `GET /v2/usermanagement/users/{orgId}/{page}?groupName={encodedGroupName}` until `lastPage: true`
4. For each user return `{ email, lastAccessedDate }` — `lastAccessedDate` is null if not present
5. Return `200` with JSON array; `502` with message on UMAPI error

**No new Azure resources required** — deploys to the same Function App (`p-corp-fa-adobelicmon-azuc-01`).

### `AdobeProducts.js` — Minor Update

Add `groupName` to each product object in the response. This is the UMAPI `groupName` field (e.g., `"Default Acrobat Pro DC profile"`) — distinct from `productName` (`"Acrobat Pro DC"`). The front-end needs the exact UMAPI group name to pass to `AdobeMembers` as the `groupName` query param.

**Response shape change (additive):**
```json
{
  "productName": "Acrobat Pro DC",
  "groupName": "Default Acrobat Pro DC profile",
  "quota": 500,
  "userCount": 550
}
```

### Front-end: `tools/adobe-license-monitor/index.html`

**New constant:**
```js
const ADOBE_MEMBERS_URL = "https://p-corp-fa-adobelicmon-azuc-01.azurewebsites.net/api/AdobeMembers";
```

**`PRODUCTS` config** — `groupName` is written back onto each `PRODUCTS[i]` entry during `loadDashboard()` once the AdobeProducts proxy responds. Not hardcoded — stays in sync with UMAPI automatically.

```js
// in loadDashboard(), after proxy responds:
PRODUCTS.forEach((p, i) => {
  const ap = adobeProducts.find(x => x.productName.toLowerCase().includes(p.adobeMatch.toLowerCase()));
  if (ap?.groupName) p.adobeGroupName = ap.groupName;
});
```

`toggleExpand(groupId, idx)` then reads `PRODUCTS[idx].adobeGroupName` — no signature change needed on the inline onclick, no risk of special characters in HTML attributes.

**New function `_fetchAdobeLastUsed(adobeGroupName)`:**
- GET `{ADOBE_MEMBERS_URL}?groupName={encodeURIComponent(adobeGroupName)}`
- Uses the Adobe Function scope token (`ADOBE_FUNC_SCOPE`) — not a Graph token
- Returns `Map<string, string|null>` keyed by email (lowercased) → `lastAccessedDate`
- On any error: returns empty `Map` — degrades gracefully, column shows "—" rather than breaking

**`_loadMembers(groupId, adobeGroupName, idx)` — signature update:**
- Add `adobeGroupName` parameter
- Fire `_fetchMembers` + `_enrichSignIn` (Entra) AND `_fetchAdobeLastUsed(adobeGroupName)` in `Promise.all`
- After both resolve, merge: `m.adobeLastUsed = adobeMap.get(m.userPrincipalName.toLowerCase()) ?? null`

**New function `_adobeRelativeTime(dateStr)`:**
- Same shape as `_relativeTime` but stale threshold is 90 days (not 30)
- Returns `{ text, stale }` — `stale: true` renders red in the Adobe column

**`_sortMembers` — add `adobeLastUsed` case:**
```js
if (col === "adobeLastUsed") {
  const ta = a.adobeLastUsed ? new Date(a.adobeLastUsed).getTime() : 0;
  const tb = b.adobeLastUsed ? new Date(b.adobeLastUsed).getTime() : 0;
  return dir * (ta - tb);
}
```

**`renderMemberTable` — column changes:**
- Rename `lastSignIn` column header: "Last Sign-In" → "Entra Sign-In" (remove ⓘ icon entirely)
- Add "Adobe Last Used" `<th>` after Entra Sign-In, same sortable pattern
- Rename sort key `lastSignIn` → `entraSignIn` in `onclick` and `_sortMembers`
- Render Adobe cell: `_adobeRelativeTime(m.adobeLastUsed)` with `.signin-stale` class when stale

**`toggleExpand` — pass `adobeGroupName`:**
- Read `PRODUCTS[idx].adobeGroupName` (written during `loadDashboard`)
- Pass to `_loadMembers(groupId, PRODUCTS[idx].adobeGroupName, idx)`
- If `adobeGroupName` is undefined (proxy failed), pass `null` — `_fetchAdobeLastUsed(null)` returns empty Map immediately

## CSS

One new style rule for the Adobe stale color — reuses the existing `.signin-stale` class (same red color, same visual weight). No new CSS needed.

## Loading Behavior

Adobe Last Used data loads in parallel with the Entra member fetch when a card is expanded. The shimmer skeleton covers both columns during load. If `_fetchAdobeLastUsed` fails silently, the Adobe column shows "—" for all rows — the table still renders, Entra data still shows, and the user loses nothing critical.

## Deployment

1. Deploy updated `adobe-func` to Azure (`func azure functionapp publish p-corp-fa-adobelicmon-azuc-01`)
2. No new app settings, no CORS changes, no Entra app changes required
3. Front-end changes deploy via normal `testing` → `main` GitHub Pages pipeline

## Files Changed

| File | Change |
|------|--------|
| `adobe-func/src/functions/AdobeProducts.js` | Add `groupName` to response shape |
| `adobe-func/src/functions/AdobeMembers.js` | New file — UMAPI per-user last-used endpoint |
| `tools/adobe-license-monitor/index.html` | Column rename, new column, `_fetchAdobeLastUsed`, `_adobeRelativeTime`, sort update |
