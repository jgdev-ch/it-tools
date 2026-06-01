# Adobe License Monitor — Adobe Last Used Column Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Adobe Last Used" column to the member expansion table showing actual Adobe product activity per user, alongside a renamed "Entra Sign-In" column, so IT can distinguish active-in-M365-but-never-uses-Adobe users from genuinely active Adobe users.

**Architecture:** A new Azure Function `AdobeMembers` fetches per-user `lastAccessedDate` from UMAPI `/users?groupName=`, returning `[{ email, lastAccessedDate }]`. `AdobeProducts.js` is updated to also return the UMAPI `groupName` field so the front-end can pass the exact group name to `AdobeMembers`. The front-end loads Adobe data in parallel with Entra members on card expand and merges by UPN/email.

**Tech Stack:** Azure Functions v4 (Node.js), Adobe UMAPI v2, vanilla JS, GitHub Pages

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `adobe-func/src/functions/AdobeProducts.js` | Modify | Add `groupName` field to each product in response |
| `adobe-func/src/functions/AdobeMembers.js` | Create | New endpoint — fetch per-user `lastAccessedDate` for a UMAPI group |
| `tools/adobe-license-monitor/index.html` | Modify | Column rename, new column, data fetch, sort, render |

---

### Task 1: Add `groupName` to AdobeProducts response

**Files:**
- Modify: `adobe-func/src/functions/AdobeProducts.js:47-53`

The front-end needs the UMAPI `groupName` (e.g. `"Default Acrobat Pro DC profile"`) to pass as the `?groupName=` param to `AdobeMembers`. This is different from `productName` (`"Acrobat Pro DC"`). Currently the proxy returns `productName`, `quota`, `userCount` — add `groupName`.

- [ ] **Open `adobe-func/src/functions/AdobeProducts.js` and find the `.map()` at line 47**

Current code:
```js
const products = allGroups
    .filter(g => g.type === 'PRODUCT_PROFILE')
    .map(g => ({
        productName: g.productName,
        quota:       parseInt(g.licenseQuota, 10) || 0,
        userCount:   g.memberCount || 0,
    }));
```

- [ ] **Replace that `.map()` with:**

```js
const products = allGroups
    .filter(g => g.type === 'PRODUCT_PROFILE')
    .map(g => ({
        productName: g.productName,
        groupName:   g.groupName || null,
        quota:       parseInt(g.licenseQuota, 10) || 0,
        userCount:   g.memberCount || 0,
    }));
```

- [ ] **Commit**

```bash
cd /c/dev/projects/adobe-func
git add src/functions/AdobeProducts.js
git commit -m "adobe-products: include groupName in product profile response"
```

---

### Task 2: Create `AdobeMembers.js`

**Files:**
- Create: `adobe-func/src/functions/AdobeMembers.js`

New Azure Function that accepts `?groupName=` and returns `[{ email, lastAccessedDate }]` for every user in that UMAPI product profile group. Auth, UMAPI token fetch, and pagination follow the same pattern as `AdobeProducts.js`.

> **Field name note:** UMAPI returns `lastAccessedDate` per the spec. On first deploy, log the first user object to confirm the exact field name. If all values come back `null`, check whether the field is named `lastAccessed` instead and update accordingly.

- [ ] **Create `adobe-func/src/functions/AdobeMembers.js` with this content:**

```js
const { app } = require('@azure/functions');

app.http('AdobeMembers', {
    methods: ['GET'],
    authLevel: 'anonymous', // auth handled by EasyAuth (Entra Bearer token required)
    handler: async (request, context) => {
        const groupName    = request.query.get('groupName');
        const orgId        = process.env.ADOBE_ORG_ID;
        const clientId     = process.env.ADOBE_CLIENT_ID;
        const clientSecret = process.env.ADOBE_CLIENT_SECRET;

        if (!groupName) {
            return { status: 400, body: 'Missing required query param: groupName' };
        }

        try {
            const tokenRes = await fetch('https://ims-na1.adobelogin.com/ims/token/v3', {
                method:  'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({
                    grant_type:    'client_credentials',
                    client_id:     clientId,
                    client_secret: clientSecret,
                    scope:         'openid,AdobeID,user_management_sdk',
                }),
            });
            if (!tokenRes.ok) {
                const err = await tokenRes.text();
                return { status: 502, body: `Adobe token failed: ${tokenRes.status} — ${err}` };
            }
            const { access_token } = await tokenRes.json();
            const headers = { Authorization: 'Bearer ' + access_token, 'x-api-key': clientId };

            const allUsers = [];
            let page = 0;
            while (true) {
                const url = `https://usermanagement.adobe.io/v2/usermanagement/users/${encodeURIComponent(orgId)}/${page}?groupName=${encodeURIComponent(groupName)}`;
                const res = await fetch(url, { headers });
                if (!res.ok) {
                    const err = await res.text();
                    return { status: 502, body: `UMAPI users failed: ${res.status} — ${err}` };
                }
                const data = await res.json();
                allUsers.push(...(data.users || []));
                if (data.lastPage) break;
                page++;
            }

            const members = allUsers.map(u => ({
                email:           (u.email || '').toLowerCase(),
                lastAccessedDate: u.lastAccessedDate ?? null,
            }));

            return {
                status:  200,
                headers: { 'Content-Type': 'application/json' },
                body:    JSON.stringify(members),
            };
        } catch (err) {
            return { status: 500, body: 'Internal error: ' + err.message };
        }
    },
});
```

- [ ] **Commit**

```bash
git add src/functions/AdobeMembers.js
git commit -m "adobe-members: new endpoint — UMAPI per-user lastAccessedDate by group"
```

---

### Task 3: Deploy `adobe-func` to Azure and verify

**Files:** none (deploy step)

Both function changes need to be live before front-end work begins so they can be tested end-to-end.

- [ ] **Deploy from the adobe-func directory**

```bash
cd /c/dev/projects/adobe-func
func azure functionapp publish p-corp-fa-adobelicmon-azuc-01
```

Expected output ends with: `Deployment successful.`

- [ ] **Verify `AdobeProducts` still returns `groupName`**

Open in browser (you'll need an Entra Bearer token — easiest to test via the live tool's console):
```
https://p-corp-fa-adobelicmon-azuc-01.azurewebsites.net/api/AdobeProducts
```
Expected response shape (one item shown):
```json
[
  {
    "productName": "Acrobat Pro DC",
    "groupName": "Default Acrobat Pro DC profile",
    "quota": 500,
    "userCount": 550
  }
]
```
Note the exact `groupName` value for each product — you will need it in the next verification step.

- [ ] **Verify `AdobeMembers` returns user data**

Use the `groupName` value from the step above:
```
https://p-corp-fa-adobelicmon-azuc-01.azurewebsites.net/api/AdobeMembers?groupName=Default%20Acrobat%20Pro%20DC%20profile
```
Expected: JSON array of `{ email, lastAccessedDate }` objects.

> **If `lastAccessedDate` is `null` for all users:** log one full user object from `allUsers` in `AdobeMembers.js` (`context.log(allUsers[0])`) to find the actual field name. Common alternative is `lastAccessed`. Update the `.map()` in `AdobeMembers.js` accordingly, redeploy, and re-verify.

---

### Task 4: Front-end — add `ADOBE_MEMBERS_URL`, `_adobeRelativeTime`, `_fetchAdobeLastUsed`

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

Three new additions to the JS section. No existing code changes yet — purely additive. After this task the front-end is not visually changed.

- [ ] **Add `ADOBE_MEMBERS_URL` constant after the existing `ADOBE_PROXY_URL` constant (line 408)**

Find:
```js
const ADOBE_PROXY_URL = "https://p-corp-fa-adobelicmon-azuc-01.azurewebsites.net/api/AdobeProducts";
```

Replace with:
```js
const ADOBE_PROXY_URL    = "https://p-corp-fa-adobelicmon-azuc-01.azurewebsites.net/api/AdobeProducts";
const ADOBE_MEMBERS_URL  = "https://p-corp-fa-adobelicmon-azuc-01.azurewebsites.net/api/AdobeMembers";
```

- [ ] **Add `_adobeRelativeTime` immediately after the existing `_relativeTime` function (after line 814)**

Find:
```js
function _relativeTime(dateStr) {
  if (!dateStr) return { text: "Never", stale: true };
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (days === 0) return { text: "Today",       stale: false };
  if (days === 1) return { text: "Yesterday",   stale: false };
  if (days < 30)  return { text: `${days} days ago`,                       stale: false };
  if (days < 365) return { text: `${Math.floor(days / 30)} months ago`,    stale: true  };
  return               { text: `${Math.floor(days / 365)} year${Math.floor(days / 365) > 1 ? "s" : ""} ago`, stale: true };
}
```

Replace with:
```js
function _relativeTime(dateStr) {
  if (!dateStr) return { text: "Never", stale: true };
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (days === 0) return { text: "Today",       stale: false };
  if (days === 1) return { text: "Yesterday",   stale: false };
  if (days < 30)  return { text: `${days} days ago`,                       stale: false };
  if (days < 365) return { text: `${Math.floor(days / 30)} months ago`,    stale: true  };
  return               { text: `${Math.floor(days / 365)} year${Math.floor(days / 365) > 1 ? "s" : ""} ago`, stale: true };
}

function _adobeRelativeTime(dateStr) {
  if (!dateStr) return { text: "Never", stale: true };
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (days === 0) return { text: "Today",       stale: false };
  if (days === 1) return { text: "Yesterday",   stale: false };
  if (days < 30)  return { text: `${days} days ago`,                       stale: false };
  if (days < 365) return { text: `${Math.floor(days / 30)} months ago`,    stale: days >= 90 };
  return               { text: `${Math.floor(days / 365)} year${Math.floor(days / 365) > 1 ? "s" : ""} ago`, stale: true };
}
```

- [ ] **Add `_fetchAdobeLastUsed` immediately after `_loadMembers` (after line 511)**

Find:
```js
async function _loadMembers(groupId, idx) {
  // keyed by PRODUCTS index (idx), not groupId — cache is invalidated on page reload
  if (_memberCache[idx]?.loaded) return _memberCache[idx].members;
  const token   = await ITTools.auth.getToken();
  const raw     = await _fetchMembers(token, groupId);
  const members = await _enrichSignIn(token, raw);
  _memberCache[idx] = { loaded: true, members };
  return members;
}
```

Replace with:
```js
async function _loadMembers(groupId, idx) {
  // keyed by PRODUCTS index (idx), not groupId — cache is invalidated on page reload
  if (_memberCache[idx]?.loaded) return _memberCache[idx].members;
  const token   = await ITTools.auth.getToken();
  const raw     = await _fetchMembers(token, groupId);
  const members = await _enrichSignIn(token, raw);
  _memberCache[idx] = { loaded: true, members };
  return members;
}

async function _fetchAdobeLastUsed(adobeGroupName) {
  if (!adobeGroupName) return new Map();
  try {
    const token = await ITTools.auth.getToken([ADOBE_FUNC_SCOPE]);
    const res   = await fetch(
      `${ADOBE_MEMBERS_URL}?groupName=${encodeURIComponent(adobeGroupName)}`,
      { headers: { Authorization: "Bearer " + token } }
    );
    if (!res.ok) return new Map();
    const data = await res.json();
    return new Map(data.map(u => [u.email.toLowerCase(), u.lastAccessedDate ?? null]));
  } catch (_) {
    return new Map();
  }
}
```

- [ ] **Commit**

```bash
cd /c/dev/projects/it-tools
git add tools/adobe-license-monitor/index.html
git commit -m "adobe-monitor: add ADOBE_MEMBERS_URL, _adobeRelativeTime, _fetchAdobeLastUsed"
```

---

### Task 5: Front-end — wire up data layer

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

Three wiring changes: `_loadMembers` gets the parallel Adobe fetch and merge; `loadDashboard` writes `adobeGroupName` back onto `PRODUCTS`; `toggleExpand` passes it through.

- [ ] **Update `_loadMembers` to fetch Adobe data in parallel (replace the function added in Task 4)**

Find the `_loadMembers` function (the original, not `_fetchAdobeLastUsed`):
```js
async function _loadMembers(groupId, idx) {
  // keyed by PRODUCTS index (idx), not groupId — cache is invalidated on page reload
  if (_memberCache[idx]?.loaded) return _memberCache[idx].members;
  const token   = await ITTools.auth.getToken();
  const raw     = await _fetchMembers(token, groupId);
  const members = await _enrichSignIn(token, raw);
  _memberCache[idx] = { loaded: true, members };
  return members;
}
```

Replace with:
```js
async function _loadMembers(groupId, adobeGroupName, idx) {
  // keyed by PRODUCTS index (idx), not groupId — cache is invalidated on page reload
  if (_memberCache[idx]?.loaded) return _memberCache[idx].members;
  const token = await ITTools.auth.getToken();
  const [enriched, adobeMap] = await Promise.all([
    _fetchMembers(token, groupId).then(raw => _enrichSignIn(token, raw)),
    _fetchAdobeLastUsed(adobeGroupName),
  ]);
  const members = enriched.map(m => ({
    ...m,
    adobeLastUsed: adobeMap.get((m.userPrincipalName || "").toLowerCase()) ?? null,
  }));
  _memberCache[idx] = { loaded: true, members };
  return members;
}
```

- [ ] **Update `loadDashboard` to write `adobeGroupName` onto each PRODUCTS entry**

Find (inside `loadDashboard`, after the proxy result is parsed):
```js
    const adobeProducts = adobeResult || [];
    const adobeFailed   = adobeResult === null;
```

Replace with:
```js
    const adobeProducts = adobeResult || [];
    const adobeFailed   = adobeResult === null;

    // Write UMAPI groupName back onto PRODUCTS config so toggleExpand can pass it to AdobeMembers
    PRODUCTS.forEach(p => {
      const ap = adobeProducts.find(x => x.productName.toLowerCase().includes(p.adobeMatch.toLowerCase()));
      if (ap?.groupName) p.adobeGroupName = ap.groupName;
    });
```

- [ ] **Update `toggleExpand` to pass `adobeGroupName` to `_loadMembers`**

Find (inside `toggleExpand`):
```js
    const members = await _loadMembers(groupId, idx);
```

Replace with:
```js
    const members = await _loadMembers(groupId, PRODUCTS[idx].adobeGroupName ?? null, idx);
```

- [ ] **Commit**

```bash
git add tools/adobe-license-monitor/index.html
git commit -m "adobe-monitor: wire Adobe Last Used data fetch into _loadMembers and toggleExpand"
```

---

### Task 6: Front-end — update sort and render

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

Rename sort key `lastSignIn` → `entraSignIn` throughout, add `adobeLastUsed` sort case, update column headers, add Adobe cell rendering.

- [ ] **Update `_sortMembers` — rename lastSignIn case and add adobeLastUsed case**

Find:
```js
    if (col === "lastSignIn") {
      const ta = a.lastSignIn ? new Date(a.lastSignIn).getTime() : 0;
      const tb = b.lastSignIn ? new Date(b.lastSignIn).getTime() : 0;
      return dir * (ta - tb);
    }
    return 0;
```

Replace with:
```js
    if (col === "entraSignIn") {
      const ta = a.lastSignIn ? new Date(a.lastSignIn).getTime() : 0;
      const tb = b.lastSignIn ? new Date(b.lastSignIn).getTime() : 0;
      return dir * (ta - tb);
    }
    if (col === "adobeLastUsed") {
      const ta = a.adobeLastUsed ? new Date(a.adobeLastUsed).getTime() : 0;
      const tb = b.adobeLastUsed ? new Date(b.adobeLastUsed).getTime() : 0;
      return dir * (ta - tb);
    }
    return 0;
```

- [ ] **Update `sortBy` — rename lastSignIn default-dir check and add adobeLastUsed**

Find:
```js
  const dir = (current.col === col) ? current.dir * -1 : (col === "lastSignIn" ? 1 : -1);
```

Replace with:
```js
  const dir = (current.col === col) ? current.dir * -1 : (col === "entraSignIn" || col === "adobeLastUsed" ? 1 : -1);
```

- [ ] **Update `renderMemberTable` — column headers, Entra cell, and new Adobe cell**

Find the rows mapping and table HTML (inside `renderMemberTable`):
```js
  const rows = sorted.map(m => {
    const initials  = (m.displayName || "?").split(" ").map(n => n[0]).join("").slice(0, 2).toUpperCase() || "?";
    const statusCls = m.accountEnabled ? "enabled" : "disabled";
    const si        = _relativeTime(m.lastSignIn);
    const siHtml    = `<span${si.stale ? ' class="signin-stale"' : ""}>${si.text}</span>`;
    const removeBtn = _isLicenseAdmin
      ? `<button class="btn-mem-remove" onclick="showRemoveModal('${groupId}',${idx},'${m.id}')">Remove</button>`
      : `<button class="btn-mem-remove gated" title="Requires License Admin access" disabled>Remove</button>`;

    return `
      <tr class="${m.accountEnabled ? "" : "row-disabled"}" id="mrow-${m.id}">
        <td>
          <div class="mem-user-cell">
            <div class="mem-avatar ${statusCls}">${initials}</div>
            <div class="mem-name">${m.displayName}</div>
          </div>
        </td>
        <td style="font-size:11px;color:var(--muted)">${m.userPrincipalName}</td>
        <td><span class="mem-badge ${statusCls}">${m.accountEnabled ? "Enabled" : "Disabled"}</span></td>
        <td>${siHtml}</td>
        <td>${removeBtn}</td>
      </tr>`;
  }).join("");
```

Replace with:
```js
  const rows = sorted.map(m => {
    const initials    = (m.displayName || "?").split(" ").map(n => n[0]).join("").slice(0, 2).toUpperCase() || "?";
    const statusCls   = m.accountEnabled ? "enabled" : "disabled";
    const si          = _relativeTime(m.lastSignIn);
    const siHtml      = `<span${si.stale ? ' class="signin-stale"' : ""}>${si.text}</span>`;
    const adobe       = _adobeRelativeTime(m.adobeLastUsed);
    const adobeHtml   = `<span${adobe.stale ? ' class="signin-stale"' : ""}>${adobe.text}</span>`;
    const removeBtn   = _isLicenseAdmin
      ? `<button class="btn-mem-remove" onclick="showRemoveModal('${groupId}',${idx},'${m.id}')">Remove</button>`
      : `<button class="btn-mem-remove gated" title="Requires License Admin access" disabled>Remove</button>`;

    return `
      <tr class="${m.accountEnabled ? "" : "row-disabled"}" id="mrow-${m.id}">
        <td>
          <div class="mem-user-cell">
            <div class="mem-avatar ${statusCls}">${initials}</div>
            <div class="mem-name">${m.displayName}</div>
          </div>
        </td>
        <td style="font-size:11px;color:var(--muted)">${m.userPrincipalName}</td>
        <td><span class="mem-badge ${statusCls}">${m.accountEnabled ? "Enabled" : "Disabled"}</span></td>
        <td>${siHtml}</td>
        <td>${adobeHtml}</td>
        <td>${removeBtn}</td>
      </tr>`;
  }).join("");
```

- [ ] **Update the table `<thead>` inside `renderMemberTable`**

Find:
```js
            <th class="${thCls("lastSignIn")}" style="width:145px" onclick="sortBy('${groupId}',${idx},'lastSignIn')">Last Sign-In <span class="col-info" title="Entra ID sign-in date — last M365 activity (Windows login, Teams, Outlook, etc.), not Adobe product usage">ⓘ</span> ${thIcon("lastSignIn")}</th>
            <th>Action</th>
```

Replace with:
```js
            <th class="${thCls("entraSignIn")}"  style="width:130px" onclick="sortBy('${groupId}',${idx},'entraSignIn')">Entra Sign-In ${thIcon("entraSignIn")}</th>
            <th class="${thCls("adobeLastUsed")}" style="width:130px" onclick="sortBy('${groupId}',${idx},'adobeLastUsed')">Adobe Last Used ${thIcon("adobeLastUsed")}</th>
            <th>Action</th>
```

- [ ] **Commit**

```bash
git add tools/adobe-license-monitor/index.html
git commit -m "adobe-monitor: Entra Sign-In + Adobe Last Used columns, sort, render"
```

---

### Task 7: Push to testing and verify end-to-end

**Files:** none (deploy + verification)

- [ ] **Push to testing branch**

```bash
git checkout testing
git merge main
git push origin testing
```

Wait ~60 seconds for GitHub Pages to deploy, then open the preview URL:
`https://jgdev-ch.github.io/it-tools-preview/tools/adobe-license-monitor/`

- [ ] **Verify AdobeProducts response includes groupName**

Open browser DevTools → Network tab. Sign in and let the dashboard load. Find the request to `AdobeProducts`. Confirm response includes `groupName` on each product object.

- [ ] **Expand a product card and verify both columns**

Click the "View X group members" expand strip. Confirm:
- Table shows **Entra Sign-In** and **Adobe Last Used** column headers (no ⓘ icon anywhere)
- Entra Sign-In shows relative dates from the existing sign-in data
- Adobe Last Used shows relative dates (or "Never" for users who have never accessed Adobe)
- Stale Adobe dates (≥90 days or "Never") are red; recent ones are grey

- [ ] **Verify sort works on both new columns**

Click "Entra Sign-In" header — rows sort by Entra date ascending/descending. Click "Adobe Last Used" header — rows sort by Adobe date ascending/descending.

- [ ] **Verify graceful degradation**

If you want to test the error path: temporarily change `ADOBE_MEMBERS_URL` to a bad URL, expand a card — Adobe column should show "Never" for all rows while Entra data loads normally. Revert the URL change afterward.

- [ ] **Promote to main when verified**

```bash
git checkout main
git merge testing
git push origin main
```

Version bump optional — this is an additive feature on top of v2.0.0. If bumping: update the version comment in the HTML `<head>`.
