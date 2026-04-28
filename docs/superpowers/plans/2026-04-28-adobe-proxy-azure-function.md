# Adobe Proxy — Azure Function Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Adobe CORS error in the Adobe License Monitor tool by routing Adobe API calls through an Azure Function that holds the credentials server-side.

**Architecture:** A new Azure Function App (Node.js 20, consumption plan) exposes a single HTTP-triggered endpoint `AdobeProducts` that fetches an Adobe IMS token and UMAPI product list server-side, then returns the products array as JSON. The IT Tools browser page calls this proxy instead of Adobe directly — Adobe credentials move out of the HTML into Azure app settings. A function-level API key protects the endpoint; the key is stored as a constant in the tool HTML (acceptable — it only grants access to read seat counts).

**Tech Stack:** Azure Functions v2 runtime, Node.js 20 LTS, native `fetch` (no packages needed), Azure Portal in-browser editor.

---

## File Map

| File | Change |
|---|---|
| Azure Function `AdobeProducts/index.js` | Create — proxy handler (edited in Azure Portal) |
| Azure Function `AdobeProducts/function.json` | Create — binding config (edited in Azure Portal) |
| `tools/adobe-license-monitor/index.html` | Modify — remove Adobe constants + `_getAdobeToken()`, replace `_getAdobeProducts()`, simplify `loadDashboard()` |

---

## Context for implementers

The IT Tools hub lives at `C:\dev\projects\it-tools` on the `testing` branch. It is a static GitHub Pages site — no backend, no build step. The Adobe License Monitor tool at `tools/adobe-license-monitor/index.html` currently fails because it tries to call Adobe IMS directly from the browser, which Adobe's CORS policy blocks.

The fix is two-part:
1. An Azure Function (set up manually in the Azure Portal — Tasks 1–4) acts as the proxy
2. The IT Tools HTML is updated to call the proxy instead of Adobe (Task 5)

Tasks 1–4 are portal setup steps that must be completed by a human with Azure access before Task 5 can be done.

---

## Task 1: Create the Azure Function App in the Azure Portal

**Files:** None — Azure Portal UI steps only.

- [ ] **Step 1: Open the Azure Portal and start Function App creation**

Navigate to `https://portal.azure.com`. In the search bar at the top, type **Function App** and select it. Click **+ Create**.

- [ ] **Step 2: Fill in the Basics tab**

| Field | Value |
|---|---|
| Subscription | Your active subscription |
| Resource group | Create new: `rg-it-tools-adobe-proxy` (or add to an existing RG) |
| Function App name | `it-tools-adobe-proxy` (must be globally unique — append initials if taken) |
| Runtime stack | **Node.js** |
| Version | **20 LTS** |
| Region | East US (or whichever region your other Azure resources use) |
| Operating System | **Linux** |
| Hosting plan | **Consumption (Serverless)** |

Click **Next: Storage**.

- [ ] **Step 3: Storage tab**

Accept the default (a new storage account will be created). Click **Next: Networking**, then **Next: Monitoring**.

- [ ] **Step 4: Monitoring tab**

Set **Enable Application Insights** to **No** (not needed for this simple proxy). Click **Review + create**, then **Create**.

- [ ] **Step 5: Wait for deployment**

Deployment takes 1–2 minutes. When "Your deployment is complete" appears, click **Go to resource**.

---

## Task 2: Create the AdobeProducts HTTP trigger function

**Files:** `AdobeProducts/function.json`, `AdobeProducts/index.js` — created in the Azure Portal editor.

- [ ] **Step 1: Open the Functions blade**

In your Function App, click **Functions** in the left sidebar, then click **+ Create**.

- [ ] **Step 2: Select template**

In the "Select a template" panel:
- Choose **HTTP trigger**
- Set **New Function** name to: `AdobeProducts`
- Set **Authorization level** to: `Function`

Click **Create**.

- [ ] **Step 3: Open the code editor**

After the function is created, click **AdobeProducts** in the functions list. Click **Code + Test** in the left sidebar.

- [ ] **Step 4: Replace `index.js` with the proxy code**

The editor shows `index.js` by default. Select all and replace with:

```js
module.exports = async function (context, req) {
  const orgId       = process.env.ADOBE_ORG_ID;
  const clientId    = process.env.ADOBE_CLIENT_ID;
  const clientSecret = process.env.ADOBE_CLIENT_SECRET;

  try {
    const tokenRes = await fetch("https://ims-na1.adobelogin.com/ims/token/v3", {
      method:  "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body:    new URLSearchParams({
        grant_type:    "client_credentials",
        client_id:     clientId,
        client_secret: clientSecret,
        scope:         "openid,AdobeID,user_management_sdk",
      }),
    });

    if (!tokenRes.ok) {
      context.res = { status: 502, body: "Adobe token fetch failed: " + tokenRes.status };
      return;
    }

    const { access_token } = await tokenRes.json();

    const productsRes = await fetch(
      `https://usermanagement.adobe.io/v2/usermanagement/organizations/${orgId}/products`,
      { headers: { Authorization: "Bearer " + access_token, "x-api-key": clientId } }
    );

    if (!productsRes.ok) {
      context.res = { status: 502, body: "UMAPI fetch failed: " + productsRes.status };
      return;
    }

    const data = await productsRes.json();

    context.res = {
      status: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data.products || []),
    };
  } catch (err) {
    context.res = { status: 500, body: "Internal error: " + err.message };
  }
};
```

Click **Save**.

- [ ] **Step 5: Verify `function.json`**

In the dropdown at the top of the editor (currently showing `index.js`), switch to **function.json**. It should contain:

```json
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
```

If `authLevel` is not `"function"` or `methods` includes extra verbs, edit it to match the above exactly. Click **Save**.

---

## Task 3: Configure app settings and CORS

**Files:** None — Azure Portal settings UI.

- [ ] **Step 1: Add Adobe credentials as app settings**

In the Function App (go up one level from the function), click **Configuration** in the left sidebar under Settings. Click **+ New application setting** three times, adding:

| Name | Value |
|---|---|
| `ADOBE_ORG_ID` | `8032749550D882010A490D45@AdobeOrg` |
| `ADOBE_CLIENT_ID` | `c5406ca9553040aaa969ecc3fc31a39d` |
| `ADOBE_CLIENT_SECRET` | `p8e-1PcvrCo_NpyjYlwSBFC9f7003Lufl1W6` |

Click **Save** at the top, then **Continue** to confirm the restart.

- [ ] **Step 2: Configure CORS**

In the Function App left sidebar, click **CORS** (under API). Delete any existing wildcard `*` entry if present. Add:

```
https://jgdev-ch.github.io
```

Click **Save**.

This single origin covers both the preview site (`/it-tools-preview/`) and the production site (`/it-tools/`) since they share the same origin.

---

## Task 4: Get the function URL and key, test the endpoint

**Files:** None — portal test.

- [ ] **Step 1: Get the function URL**

Navigate back to the `AdobeProducts` function → **Code + Test**. Click **Get function URL** (button near the top right). Select **default (function key)** from the dropdown. Copy the full URL — it looks like:

```
https://it-tools-adobe-proxy.azurewebsites.net/api/AdobeProducts?code=XXXXXXXXXXXXXXXX==
```

Save this URL — you'll need both parts in Task 5:
- **Base URL:** `https://it-tools-adobe-proxy.azurewebsites.net/api/AdobeProducts`
- **Key:** everything after `?code=`

- [ ] **Step 2: Test via the portal Test/Run pane**

Still in Code + Test, click **Test/Run** on the right panel. Set HTTP method to **GET**, leave the body empty, click **Run**.

Expected response body:
```json
[
  { "id": "...", "productName": "Acrobat Pro DC", "quota": 25, "userCount": 18 },
  ...
]
```

If you see a 502 error, check:
- App settings were saved correctly (Task 3 Step 1)
- The function restarted after saving settings (it does automatically)
- The Adobe credentials are correct

If the array is empty (`[]`), the credentials are working but Adobe returned no products — re-check the Org ID.

---

## Task 5: Update the IT Tools HTML to call the proxy

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

- [ ] **Step 1: Replace the config block**

Find and replace the three Adobe constants and `_getAdobeToken` and `_getAdobeProducts` functions. The current block (lines ~184–233) looks like:

```js
const ADOBE_ORG_ID        = "8032749550D882010A490D45@AdobeOrg";
const ADOBE_CLIENT_ID     = "c5406ca9553040aaa969ecc3fc31a39d";
const ADOBE_CLIENT_SECRET = "p8e-1PcvrCo_NpyjYlwSBFC9f7003Lufl1W6";

const PRODUCTS = [ ... ];   // keep this unchanged

const TOOL_SCOPES = ["User.Read", "GroupMember.Read.All"];   // keep this unchanged

async function _getAdobeToken() { ... }    // DELETE this entire function

async function _getAdobeProducts(token) { ... }   // REPLACE this function
```

Replace with:

```js
const ADOBE_PROXY_URL = "https://it-tools-adobe-proxy.azurewebsites.net/api/AdobeProducts";
const ADOBE_PROXY_KEY = "PASTE_FUNCTION_KEY_HERE";

const PRODUCTS = [
  {
    name:       "Acrobat DC Pro",
    adobeMatch: "Acrobat Pro DC",
    groupId:    "422c070e-b330-4df5-ac34-70b91d9ed0bc",
  },
  {
    name:       "Creative Cloud All Apps",
    adobeMatch: "All Apps",
    groupId:    "06d901c3-e604-4991-aec6-b044c51de773",
  },
  {
    name:       "Captivate",
    adobeMatch: "Captivate",
    groupId:    "1f5c83ec-22d0-4dce-b811-284cdbaf3c64",
  },
];

const TOOL_SCOPES = ["User.Read", "GroupMember.Read.All"];

async function _getAdobeProducts() {
  const res = await fetch(ADOBE_PROXY_URL + "?code=" + ADOBE_PROXY_KEY);
  if (!res.ok) throw new Error("Adobe proxy fetch failed: " + res.status);
  return await res.json();
}
```

- [ ] **Step 2: Simplify `loadDashboard()`**

Find the current `loadDashboard()` opening (lines ~244–262):

```js
async function loadDashboard() {
  setLoading(true);
  document.getElementById("pageErr").style.display = "none";
  try {
    const [adobeTokenResult, graphToken] = await Promise.all([
      _getAdobeToken().catch(() => null),
      ITTools.auth.getToken(),
    ]);

    let adobeProducts = [];
    let adobeFailed   = adobeTokenResult === null;
    if (!adobeFailed) {
      try {
        adobeProducts = await _getAdobeProducts(adobeTokenResult);
      } catch (_) {
        adobeFailed = true;
      }
    }
```

Replace with:

```js
async function loadDashboard() {
  setLoading(true);
  document.getElementById("pageErr").style.display = "none";
  try {
    const [adobeResult, graphToken] = await Promise.all([
      _getAdobeProducts().catch(() => null),
      ITTools.auth.getToken(),
    ]);

    let adobeProducts = adobeResult || [];
    let adobeFailed   = adobeResult === null;
```

Everything after this point in `loadDashboard()` stays unchanged — `groupCounts`, `results`, `render()`, etc.

- [ ] **Step 3: Verify `_getGroupCount` is untouched**

Confirm the `_getGroupCount(graphToken, groupId)` function is still present and unchanged — it still takes a `graphToken` parameter and calls Microsoft Graph directly (no changes needed there).

- [ ] **Step 4: Commit**

```bash
git add tools/adobe-license-monitor/index.html
git commit -m "fix: route Adobe API calls through Azure Function proxy to resolve CORS"
git push origin testing
```

- [ ] **Step 5: Smoke test on preview**

Open `https://jgdev-ch.github.io/it-tools-preview/tools/adobe-license-monitor/`. Sign in. Confirm:
- All 3 product cards show real utilization bars (not "Adobe data unavailable")
- Summary strip shows real purchased and assigned totals
- Drift banner shows or hides correctly
- Entra counts still display correctly

---

## Self-Review

**Spec coverage:**
- ✅ Azure credentials out of browser HTML → app settings in Task 3
- ✅ CORS fixed → Azure CORS config in Task 3 + proxy returns JSON
- ✅ Graceful degradation preserved → `_getAdobeProducts().catch(() => null)` in loadDashboard
- ✅ Parallelism preserved → proxy call and Graph token fetch still happen in `Promise.all`
- ✅ `_getGroupCount` unchanged → Entra side unaffected
- ✅ Function key in HTML → acceptable per design (read-only seat count data)

**Placeholder scan:** None found. All code blocks are complete.

**Type consistency:** `_getAdobeProducts()` now takes no arguments (token handled server-side). `loadDashboard()` uses `adobeResult` (the products array or null) consistently throughout the replacement block.
