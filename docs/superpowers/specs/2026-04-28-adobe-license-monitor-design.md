# Adobe License Monitor — Design Spec

**Goal:** A new IT Tools tool that pulls live seat counts from the Adobe Admin Console API and cross-references them against Entra security group membership counts — giving the IT team a single view of purchased seats, Adobe-assigned seats, and Entra group size per product, with automatic drift detection.

**Scope:** `tools/adobe-license-monitor/index.html` (new tool), `index.html` (new hub card). No changes to shared modules.

**Tech Stack:** Vanilla JS, shared `auth.js` / `styles.css`, Adobe IMS OAuth2 (client credentials), Adobe User Management API (UMAPI), Microsoft Graph (`/groups/$count`).

**First third-party API integration** in the IT Tools hub — Adobe is separate from Microsoft Graph and requires its own token obtained via client credentials flow.

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Adobe credentials storage | Hardcoded constants in tool file | Same pattern as Entra group Object IDs across all tools. Private repo = same security posture. No config UI for techs. |
| Adobe auth method | Client credentials (OAuth2) | Service-to-service — no user login required for Adobe side. One token per page load. |
| Adobe API | User Management API v2 (UMAPI) | Purpose-built for license/product management. Returns `quota` (purchased) and `userCount` (assigned) per product. |
| Entra group counts | `GET /groups/{id}/members/$count` | Single call per group, returns integer. Requires `ConsistencyLevel: eventual` header. |
| Data fetch | Both APIs in parallel on sign-in | Minimises time-to-data. Each can fail independently without blocking the other. |
| Access gate | None — open to all authenticated IT Tools users | Read-only utilisation data, no cost figures. Visible to all IT staff. |
| Layout | Horizontal stacked cards (one per product) | Three-column layout per card: identity / utilisation bar / Entra count. Approved in visual mockup v3. |
| Drift definition | Entra count ≠ Adobe assigned count | Both over and under flagged as amber. Over = unprovisioned (group member not yet in Adobe). Under = orphaned Adobe seat. |

---

## What's Removed

Nothing. This is a net-new tool.

---

## What's Added

### `tools/adobe-license-monitor/index.html`

New single-file tool. Loads `../../shared/auth.js` and `../../shared/styles.css`.

#### Hardcoded constants (admin sets once)

```js
const ADOBE_ORG_ID        = "";   // e.g. "ABCD1234@AdobeOrg"
const ADOBE_CLIENT_ID     = "";   // from Adobe Developer Console project
const ADOBE_CLIENT_SECRET = "";   // from Adobe Developer Console project

const PRODUCTS = [
  {
    name:       "Acrobat DC Pro",          // display name shown in UI
    adobeMatch: "Acrobat Pro DC",          // substring matched against UMAPI productName
    groupId:    "422c070e-b330-4df5-ac34-70b91d9ed0bc",
  },
  {
    name:       "Creative Cloud All Apps",
    adobeMatch: "All Apps",               // matches "All Apps - Edition 4"
    groupId:    "06d901c3-e604-4991-aec6-b044c51de773",
  },
  {
    name:       "Captivate",
    adobeMatch: "Captivate",             // matches "Adobe Captivate"
    groupId:    "1f5c83ec-22d0-4dce-b811-284cdbaf3c64",
  },
];
```

Adobe products are matched to `PRODUCTS` entries using `adobeMatch` — a case-insensitive substring matched against the UMAPI `productName`. Display names shown in the UI (`name`) intentionally differ from Adobe's naming (e.g. "All Apps - Edition 4" in Adobe vs "Creative Cloud All Apps" in the UI).

#### Adobe authentication — `_getAdobeToken()`

```js
async function _getAdobeToken() {
  const res = await fetch("https://ims-na1.adobelogin.com/ims/token/v3", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type:    "client_credentials",
      client_id:     ADOBE_CLIENT_ID,
      client_secret: ADOBE_CLIENT_SECRET,
      scope:         "openid,AdobeID,user_management_sdk",
    }),
  });
  if (!res.ok) throw new Error("Adobe token fetch failed: " + res.status);
  return (await res.json()).access_token;
}
```

#### Adobe product fetch — `_getAdobeProducts(token)`

```js
async function _getAdobeProducts(token) {
  const res = await fetch(
    `https://usermanagement.adobe.io/v2/usermanagement/organizations/${ADOBE_ORG_ID}/products`,
    { headers: { Authorization: "Bearer " + token, "x-api-key": ADOBE_CLIENT_ID } }
  );
  if (!res.ok) throw new Error("UMAPI products fetch failed: " + res.status);
  const data = await res.json();
  // Returns array of { id, productName, quota, userCount }
  return data.products || [];
}
```

#### Entra group count fetch — `_getGroupCount(graphToken, groupId)`

```js
async function _getGroupCount(graphToken, groupId) {
  const res = await fetch(
    `https://graph.microsoft.com/v1.0/groups/${groupId}/members/$count`,
    { headers: { Authorization: "Bearer " + graphToken, ConsistencyLevel: "eventual" } }
  );
  if (!res.ok) throw new Error("Group count fetch failed for " + groupId);
  return parseInt(await res.text(), 10);
}
```

#### Dashboard load — `loadDashboard()`

```js
async function loadDashboard() {
  setLoading(true);
  try {
    const [adobeToken, graphToken] = await Promise.all([
      _getAdobeToken(),
      ITTools.auth.getToken(),
    ]);
    const [adobeProducts, ...groupCounts] = await Promise.all([
      _getAdobeProducts(adobeToken),
      ...PRODUCTS.map(p => _getGroupCount(graphToken, p.groupId)),
    ]);
    const results = PRODUCTS.map((p, i) => {
      const ap = adobeProducts.find(x =>
        x.productName.toLowerCase().includes(p.adobeMatch.toLowerCase())
      );
      return {
        name:      p.name,
        groupId:   p.groupId,
        purchased: ap?.quota     ?? null,
        assigned:  ap?.userCount ?? null,
        entra:     groupCounts[i],
      };
    });
    render(results);
  } catch (err) {
    showError(err);
  } finally {
    setLoading(false);
  }
}
```

#### Drift logic

A product has drift when `assigned !== entra` (and both values are non-null).

- `entra > assigned` → amber "X unprovisioned" — group members not yet in Adobe
- `entra < assigned` → amber "X orphaned" — Adobe seats with no matching group member

#### Summary strip

Three stat boxes above the cards:
- **Total purchased seats** — sum of `purchased` across all products
- **Assigned in Adobe** — sum of `assigned`
- **Products with drift** — count of products where drift detected

#### Drift banner

Shown above cards when any product has drift. Lists each affected product by name with the specific mismatch. Hidden when all products are in sync.

#### Per-product card (horizontal layout)

Three-column grid per card:
- **Left (200px):** Product name + group name tag
- **Middle (flex):** "Adobe seat utilization" label, gradient progress bar (green ≤ 90%, amber > 90%, red = 100%), big assigned/total numbers, seats-available line
- **Right (220px):** Blue Entra panel — big member count, group name, sync status pill

Bar colour thresholds:
- < 90% used → green
- 90–99% used → amber (approaching capacity)
- 100% used → red (no seats available)

Note: drift (Entra ≠ Adobe) and bar colour are independent signals.

#### Error states

| Failure | Behaviour |
|---|---|
| Adobe token fails | Cards show amber "Adobe data unavailable" in middle column; Entra counts still render |
| Graph count fails for one group | That card's Entra panel shows "—" with amber indicator |
| Both fail | Full-page error banner; Refresh button remains active |
| Partial Adobe product match | Card shows "—" for purchased/assigned; Entra count still renders |

#### Loading state

Skeleton shimmer on all three card columns while data loads. Matches the shimmer pattern used in License Spend.

---

### `index.html` — new hub card

Add a new card to the hub in the Reporting & Audit section:

```html
<div class="tool-card" onclick="location.href='tools/adobe-license-monitor/'">
  <!-- Adobe product icon (red square "Ai" badge) -->
  <h3>Adobe License Monitor</h3>
  <p>Live seat utilization and Entra group sync across Acrobat DC Pro, Creative Cloud All Apps, and Captivate.</p>
  <!-- No gate ribbon — visible to all authenticated users -->
</div>
```

---

## Adobe Developer Console Setup (one-time, admin only)

1. Go to [Adobe Developer Console](https://developer.adobe.com/console)
2. Create a new project → Add API → User Management API
3. Choose **OAuth Server-to-Server** credential type
4. Copy **Organization ID**, **Client ID**, **Client Secret**
5. Paste into the three constants at the top of `tools/adobe-license-monitor/index.html`

The `scope` required is `openid,AdobeID,user_management_sdk`.

---

## Edge Cases

| Case | Behaviour |
|---|---|
| Adobe product name doesn't match | Card shows `—` for Adobe columns; Entra still renders. `adobeMatch` is a case-insensitive substring checked against the UMAPI `productName` field. |
| Purchased seats = 0 | Bar renders empty (0%), no divide-by-zero crash |
| Entra group returns 0 members | Shows 0, marked as in sync if Adobe assigned is also 0 |
| Token expires mid-session | Refresh button re-fetches both tokens |
| Adobe adds a 4th product | Only the 3 configured products are shown; extra Adobe products ignored |

---

## What's Unchanged

- All 6 existing tools — no changes
- `shared/auth.js`, `shared/styles.css` — no changes
- Hub gate logic — Adobe Monitor card is ungated
