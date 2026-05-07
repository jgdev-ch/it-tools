# Network Speed Monitor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `tools/network-speed-monitor/` tool to the IT Tools Hub that lets IT staff search an Intune-enrolled device by name, view historical speed test results stored in a SharePoint list, trigger an on-demand Intune Remediation Script, and export a PDF report with charts for leadership.

**Architecture:** On-demand, investigation-driven — no fleet-wide collection. IT searches a device, the tool reads historical results from a SharePoint list via Graph API and renders them. The "Run Fresh Test" button calls the Intune beta Graph API to trigger a targeted Proactive Remediation on that device only; results appear in SharePoint after the device checks in (15–30 min). PDF is generated entirely in-browser via jsPDF.

**Tech Stack:** Plain HTML/CSS/JS (no build tooling), MSAL via `shared/msal-browser.min.js`, shared Graph helpers via `shared/auth.js`, jsPDF 2.5.1 via CDN, PowerShell for device-side remediation scripts.

---

## Pre-Flight: What the IT Admin Must Set Up First

Before the tool works, two one-time setup steps are required outside the codebase. Document these in a comment block at the top of `index.html`.

**Step A — SharePoint List:**
Create a list named `NetworkSpeedTests` on your IT Tools SharePoint site with these columns:
- `DeviceName` (Single line of text) — **index this column for query performance**
- `IntuneDeviceId` (Single line of text)
- `Timestamp` (Date and Time, ISO 8601)
- `DownloadMbps` (Number)
- `UploadMbps` (Number)
- `LatencyMs` (Number)
- `JitterMs` (Number)
- `ISP` (Single line of text)
- `ExternalIP` (Single line of text)

**Step B — Intune Proactive Remediation:**
Create a Proactive Remediation (Devices > Remediations) using the two scripts in `remediation/`. Note its Script ID (visible in Intune URL or via Graph API). Paste that ID into `SCRIPT_POLICY_ID` in `index.html`.

**Step C — Host Speedtest CLI:**
Download Speedtest CLI for Windows (`speedtest.exe`) from Ookla and host it at a URL accessible from enrolled devices (Azure Blob Storage, SharePoint document library, or internal file server). Paste that URL into `$SpeedtestUrl` in `remediation/remediate.ps1`.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `tools/network-speed-monitor/index.html` | Create | Full tool UI — auth, search, stats, chart, table, PDF export |
| `tools/network-speed-monitor/remediation/detect.ps1` | Create | Intune detection script — always exits 1 to force remediation |
| `tools/network-speed-monitor/remediation/remediate.ps1` | Create | Intune remediation script — downloads speedtest CLI, runs test, POSTs to SharePoint |
| `config.json` | Modify | Add tool card entry |

---

## Task 1: Scaffold Tool Shell + Auth

**Files:**
- Create: `tools/network-speed-monitor/index.html`

- [ ] **Step 1: Create directory and write the HTML scaffold**

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Network Speed Monitor — IT Tools</title>
<script src="../../shared/msal-browser.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
<link rel="stylesheet" href="../../shared/styles.css"/>
<style>
  .shell { max-width: 960px; margin: 0 auto; padding: 1.75rem 1.25rem; }
  .page-header { margin-bottom: 1.5rem; }
  .page-header h1 { font-size: 22px; font-weight: 700; margin-bottom: 4px; }
  .page-header p  { font-size: 13px; color: var(--muted); }
</style>
</head>
<body>

<div id="topbar"></div>

<div id="authScreen" class="auth-screen" style="display:none">
  <div class="auth-card">
    <div style="width:44px;height:44px;background:var(--blue-light);border-radius:11px;display:flex;align-items:center;justify-content:center;margin:0 auto 1.25rem">
      <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#1a56db" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
    </div>
    <h1>Network Speed Monitor</h1>
    <p>Sign in with your Microsoft 365 admin account to investigate device network speeds.</p>
    <button class="btn-ms" onclick="doSignIn(this)">
      <svg viewBox="0 0 21 21" width="17" height="17" fill="none">
        <rect x="1"  y="1"  width="9" height="9" fill="#f25022"/>
        <rect x="11" y="1"  width="9" height="9" fill="#7fba00"/>
        <rect x="1"  y="11" width="9" height="9" fill="#00a4ef"/>
        <rect x="11" y="11" width="9" height="9" fill="#ffb900"/>
      </svg>
      Sign in with Microsoft
    </button>
    <div class="auth-error" id="authErr"></div>
    <p class="auth-note">Requires <strong>DeviceManagementManagedDevices.Read.All</strong>, <strong>DeviceManagementConfiguration.ReadWrite.All</strong>, and <strong>Sites.ReadWrite.All</strong>.</p>
    <button class="redirect-toggle" onclick="toggleUri()">Show redirect URI for app registration</button>
    <div class="redirect-box" id="uriBox"></div>
  </div>
</div>

<div id="appScreen" style="display:none">
  <div class="shell">
    <div class="page-header">
      <h1>Network Speed Monitor</h1>
      <p>Search an Intune-enrolled device to view speed history and trigger a fresh test.</p>
    </div>
    <!-- content added in later tasks -->
  </div>
</div>

<script src="../../shared/auth.js"></script>
<script>
/*
 * SETUP REQUIRED — read before deploying:
 *
 * 1. SharePoint list: Create "NetworkSpeedTests" on your IT Tools SharePoint site.
 *    Columns: DeviceName (text, indexed), IntuneDeviceId (text), Timestamp (datetime),
 *    DownloadMbps (number), UploadMbps (number), LatencyMs (number), JitterMs (number),
 *    ISP (text), ExternalIP (text).
 *
 * 2. Intune Proactive Remediation: Deploy the scripts in remediation/ via Intune.
 *    Paste the Remediation Script ID below.
 *
 * 3. Host speedtest.exe at an internal URL and paste it into remediate.ps1.
 */

const TOOL_SCOPES = [
  "DeviceManagementManagedDevices.Read.All",
  "DeviceManagementConfiguration.ReadWrite.All",
  "Sites.ReadWrite.All",
];

const SP_HOSTNAME      = "corrohealth.sharepoint.com";
const SP_SITE_PATH     = "/sites/ITTools";
const SP_LIST_NAME     = "NetworkSpeedTests";
const SCRIPT_POLICY_ID = "REPLACE_WITH_INTUNE_REMEDIATION_SCRIPT_ID";

let _spSiteId = null;
let _spListId = null;
let _currentDevice = null;
let _testHistory   = [];
let _pendingTest   = false;

async function init() {
  ITTools.theme.init();
  ITTools.ui.renderTopbar({ toolName: "Network Speed Monitor", hubRelPath: "../../", status: "beta" });
  ITTools.ui.syncThemeIcon();

  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: acct => {
      document.getElementById("authScreen").style.display = "none";
      ITTools.ui.setUser(acct);
      document.getElementById("appScreen").style.display = "block";
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
      _currentDevice = null;
      _testHistory   = [];
    }
  });

  const accounts = ITTools.auth.isSignedIn();
  if (!accounts) document.getElementById("authScreen").style.display = "flex";
}

async function doSignIn(btn) {
  try {
    await ITTools.ui.withButtonSpinner(btn, async () => {
      await ITTools.auth.signIn();
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
    }, "Signing in…");
  } catch(e) {
    const el = document.getElementById("authErr");
    el.textContent = e.message; el.style.display = "block";
  }
}

function toggleUri() {
  const b = document.getElementById("uriBox");
  b.textContent   = ITTools.auth.redirectUri();
  b.style.display = b.style.display === "none" ? "block" : "none";
}

init();
</script>
</body>
</html>
```

- [ ] **Step 2: Verify auth works**

Open `tools/network-speed-monitor/index.html` via the hub or directly in browser (served from a local web server or the deployed environment — MSAL requires HTTPS or localhost). Confirm:
- Auth screen appears before sign-in
- Clicking "Sign in with Microsoft" opens MSAL popup
- After sign-in, topbar shows user name and app screen renders with the page header

- [ ] **Step 3: Commit**

```bash
git add tools/network-speed-monitor/index.html
git commit -m "feat(network-speed-monitor): scaffold tool shell with auth"
```

---

## Task 2: Device Search

**Files:**
- Modify: `tools/network-speed-monitor/index.html`

- [ ] **Step 1: Add search bar CSS and HTML inside `#appScreen .shell`**

Add this CSS inside `<style>`:
```css
  /* Search */
  .search-row { display:flex; gap:10px; margin-bottom:1.5rem; }
  .search-row input { flex:1; }

  /* Device header card */
  .device-card { display:none; }
  .device-card.show { display:block; }
  .device-meta { font-size:12px; color:var(--muted); margin-top:3px; }
  .device-actions { display:flex; gap:8px; align-items:center; }

  /* Prior tests badge */
  .prior-badge { font-size:11px; font-weight:600; padding:3px 10px; border-radius:9999px; }
  .prior-badge.has-tests  { background:var(--amber-light); color:var(--amber); }
  .prior-badge.none-tests { background:var(--surface2); color:var(--muted); }

  /* Banners */
  .pending-banner { display:none; }
  .pending-banner.show { display:block; }
```

Replace the `<!-- content added in later tasks -->` comment with:
```html
    <!-- Search -->
    <div class="search-row">
      <input type="text" id="deviceSearch" class="field-input" placeholder="Enter device name (e.g. DESKTOP-AB1234)…"
        onkeydown="if(event.key==='Enter') searchDevice()" style="font-size:14px"/>
      <button class="btn btn-primary" id="searchBtn" onclick="searchDevice()">Search</button>
    </div>

    <div class="banner error" id="searchErr" style="display:none"></div>

    <!-- Device header -->
    <div class="card device-card" id="deviceCard">
      <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px;flex-wrap:wrap">
        <div>
          <div style="font-weight:700;font-size:16px" id="deviceName">—</div>
          <div class="device-meta" id="deviceMeta">—</div>
        </div>
        <div class="device-actions">
          <span class="prior-badge" id="priorBadge">—</span>
          <button class="btn btn-primary" id="freshBtn" onclick="runFreshTest()" style="background:var(--green)">⚡ Run Fresh Test</button>
          <button class="btn btn-ghost" id="exportBtn" onclick="exportPdf()">↓ Export PDF</button>
        </div>
      </div>
      <div class="banner warn pending-banner" id="pendingBanner" style="margin-top:1rem">
        Test triggered — results will appear after the device checks in (typically 15–30 min). Refresh to check.
      </div>
    </div>

    <!-- Results injected here -->
    <div id="resultsSection"></div>
```

- [ ] **Step 2: Add `searchDevice()` and `getSpSiteId()` / `getSpListId()` stubs**

Add inside `<script>`, before `init()`:
```javascript
async function getSpSiteId() {
  if (_spSiteId) return _spSiteId;
  const data = await ITTools.graph.get(
    `https://graph.microsoft.com/v1.0/sites/${SP_HOSTNAME}:${SP_SITE_PATH}?$select=id`
  );
  _spSiteId = data.id;
  return _spSiteId;
}

async function getSpListId() {
  if (_spListId) return _spListId;
  const siteId = await getSpSiteId();
  const enc    = encodeURIComponent(`displayName eq '${SP_LIST_NAME}'`);
  const data   = await ITTools.graph.get(
    `https://graph.microsoft.com/v1.0/sites/${siteId}/lists?$filter=${enc}&$select=id`
  );
  if (!data.value?.length) throw new Error(`SharePoint list "${SP_LIST_NAME}" not found. Create it first — see setup instructions.`);
  _spListId = data.value[0].id;
  return _spListId;
}

async function searchDevice() {
  const query = document.getElementById("deviceSearch").value.trim();
  if (!query) return;

  const errEl  = document.getElementById("searchErr");
  const btn    = document.getElementById("searchBtn");
  errEl.style.display = "none";
  document.getElementById("deviceCard").classList.remove("show");
  document.getElementById("resultsSection").innerHTML = "";
  _currentDevice = null; _testHistory = []; _pendingTest = false;

  try {
    await ITTools.ui.withButtonSpinner(btn, async () => {
      // 1. Find device in Intune
      const enc = encodeURIComponent(`deviceName eq '${query}'`);
      const res = await ITTools.graph.get(
        `https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$filter=${enc}&$select=id,deviceName,userDisplayName,userId,lastSyncDateTime,operatingSystem`
      );

      if (!res.value?.length) {
        errEl.textContent   = `Device "${query}" not found in Intune — check the name and try again.`;
        errEl.style.display = "block";
        return;
      }

      const device = res.value[0];

      // 2. Get user's department
      let dept = "—";
      if (device.userId) {
        try {
          const user = await ITTools.graph.get(
            `https://graph.microsoft.com/v1.0/users/${device.userId}?$select=displayName,department,userPrincipalName`
          );
          dept = user.department || "—";
        } catch(_) { /* dept stays "—" */ }
      }

      _currentDevice = { ...device, department: dept };

      // 3. Load history (implemented in Task 3 — stubs empty array for now)
      _testHistory = await loadTestHistory(device.deviceName);

      // 4. Render
      renderDeviceCard();
      renderResults();
    }, "Searching…");
  } catch(e) {
    errEl.textContent   = ITTools.graph.friendlyError(e);
    errEl.style.display = "block";
  }
}

async function loadTestHistory(deviceName) {
  // Stub — implemented in Task 3
  return [];
}

function renderDeviceCard() {
  if (!_currentDevice) return;
  const d = _currentDevice;

  const lastSeen = d.lastSyncDateTime
    ? new Date(d.lastSyncDateTime).toLocaleDateString("en-US", { month:"short", day:"numeric", year:"numeric", hour:"2-digit", minute:"2-digit" })
    : "Unknown";

  document.getElementById("deviceName").textContent = d.deviceName;
  document.getElementById("deviceMeta").textContent =
    `${d.userDisplayName || "—"} · ${d.department} · Last seen: ${lastSeen}`;

  const badge = document.getElementById("priorBadge");
  if (_testHistory.length > 0) {
    badge.textContent = `${_testHistory.length} prior test${_testHistory.length !== 1 ? "s" : ""}`;
    badge.className   = "prior-badge has-tests";
  } else {
    badge.textContent = "No prior tests";
    badge.className   = "prior-badge none-tests";
  }

  document.getElementById("pendingBanner").classList.toggle("show", _pendingTest);
  document.getElementById("deviceCard").classList.add("show");
}

function renderResults() {
  const sec = document.getElementById("resultsSection");
  if (!_testHistory.length) {
    sec.innerHTML = `<div class="card"><div class="empty-state">
      <div class="empty-icon">📡</div>
      <div class="empty-title">No speed tests on record</div>
      <p class="empty-sub">Click "⚡ Run Fresh Test" to trigger a test on this device. Results appear after it checks in with Intune (15–30 min).</p>
    </div></div>`;
    return;
  }
  // Populated in Tasks 4 & 5
}
```

- [ ] **Step 3: Verify search works**

Search for a real device name from your Intune tenant. Confirm:
- "Not found" error appears for a bogus name like `FAKE-DEVICE-999`
- A real device name shows the device card with name, user, department, last seen
- Browser DevTools Network tab shows a successful `managedDevices?$filter=...` call

- [ ] **Step 4: Commit**

```bash
git add tools/network-speed-monitor/index.html
git commit -m "feat(network-speed-monitor): add device search via Intune Graph API"
```

---

## Task 3: SharePoint History Reader

**Files:**
- Modify: `tools/network-speed-monitor/index.html`

- [ ] **Step 1: Implement `loadTestHistory()`**

Replace the stub `loadTestHistory` function with:
```javascript
async function loadTestHistory(deviceName) {
  try {
    const siteId = await getSpSiteId();
    const listId = await getSpListId();

    // Fetch all items — filter client-side (DeviceName column must be indexed
    // in SharePoint for this to perform well at scale; fine for < 1000 total rows)
    const items = await ITTools.graph.getAll(
      `https://graph.microsoft.com/v1.0/sites/${siteId}/lists/${listId}/items?$expand=fields&$top=999`
    );

    return items
      .filter(item => (item.fields?.DeviceName || "").toLowerCase() === deviceName.toLowerCase())
      .map(item => ({
        id:           item.id,
        timestamp:    item.fields.Timestamp,
        downloadMbps: parseFloat(item.fields.DownloadMbps) || 0,
        uploadMbps:   parseFloat(item.fields.UploadMbps)   || 0,
        latencyMs:    parseInt(item.fields.LatencyMs)       || 0,
        jitterMs:     parseFloat(item.fields.JitterMs)      || 0,
        isp:          item.fields.ISP          || "—",
        externalIp:   item.fields.ExternalIP   || "—",
        deviceName:   item.fields.DeviceName,
        intuneId:     item.fields.IntuneDeviceId || "",
      }))
      .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
  } catch(e) {
    // If the list doesn't exist yet, return empty rather than crashing
    if (e.message?.includes("not found")) throw e;
    console.warn("[loadTestHistory]", e);
    return [];
  }
}
```

- [ ] **Step 2: Verify with browser console**

After signing in and searching a real device, open DevTools Console and run:
```javascript
loadTestHistory("DESKTOP-RX9421").then(r => console.log("History rows:", r.length, r));
```
Expected: logs `History rows: 0 []` for a new device (no records yet) without throwing an error. If it throws "not found", the SharePoint list doesn't exist yet — follow the setup steps.

- [ ] **Step 3: Commit**

```bash
git add tools/network-speed-monitor/index.html
git commit -m "feat(network-speed-monitor): load test history from SharePoint list"
```

---

## Task 4: Stat Pills + Test Log Table

**Files:**
- Modify: `tools/network-speed-monitor/index.html`

- [ ] **Step 1: Add CSS for stat pills, ISP pill, and table**

Add inside `<style>`:
```css
  /* Stats row */
  .speed-stats { display:flex; gap:10px; flex-wrap:wrap; margin-bottom:1.25rem; }
  .speed-stat  { background:var(--surface2); border-radius:var(--radius); padding:10px 16px; min-width:110px; text-align:center; flex:1; }
  .speed-stat-label { font-size:11px; color:var(--muted); text-transform:uppercase; letter-spacing:.05em; margin-bottom:4px; }
  .speed-stat-value { font-size:22px; font-weight:700; line-height:1; }
  .speed-stat-unit  { font-size:12px; font-weight:400; color:var(--muted); }

  /* ISP row */
  .isp-row { display:flex; gap:8px; margin-bottom:1.25rem; flex-wrap:wrap; }
  .isp-pill { background:var(--surface2); border-radius:var(--radius); padding:8px 14px; font-size:12px; }
  .isp-pill strong { font-size:13px; color:var(--fg); }
  .isp-ip { color:var(--muted2); font-size:11px; margin-top:2px; }

  /* Test log table */
  .tbl-section { overflow-x:auto; }
  .tbl-section table { width:100%; border-collapse:collapse; font-size:12px; }
  .tbl-section thead th { padding:9px 12px; text-align:left; color:var(--muted); font-weight:600;
    font-size:11px; text-transform:uppercase; letter-spacing:.04em; border-bottom:1px solid var(--border);
    background:var(--surface2); }
  .tbl-section tbody td { padding:9px 12px; border-bottom:1px solid var(--border); }
  .tbl-section tbody tr:last-child td { border-bottom:none; }
  .tbl-section tbody tr.latest { background:var(--blue-light); }
  .tbl-down { color:var(--blue-dark); font-weight:600; }
  .tbl-up   { color:var(--green);     font-weight:600; }
```

- [ ] **Step 2: Implement `renderResults()` with stats and table**

Replace the existing `renderResults()` function with:
```javascript
function renderResults() {
  const sec = document.getElementById("resultsSection");
  if (!_testHistory.length) {
    sec.innerHTML = `<div class="card"><div class="empty-state">
      <div class="empty-icon">📡</div>
      <div class="empty-title">No speed tests on record</div>
      <p class="empty-sub">Click "⚡ Run Fresh Test" to trigger a test on this device. Results appear after it checks in with Intune (15–30 min).</p>
    </div></div>`;
    return;
  }

  const latest = _testHistory[0];

  // Mask external IP: show first octet only, rest as xxx
  function maskIp(ip) {
    if (!ip || ip === "—") return "—";
    const parts = ip.split(".");
    if (parts.length !== 4) return ip;
    return `${parts[0]}.xxx.xxx.xxx`;
  }

  function fmtDate(iso) {
    return new Date(iso).toLocaleString("en-US", {
      month:"short", day:"numeric", year:"numeric",
      hour:"2-digit", minute:"2-digit"
    });
  }

  sec.innerHTML = `
    <!-- Stat pills -->
    <div class="speed-stats">
      <div class="speed-stat">
        <div class="speed-stat-label">Latest Download</div>
        <div class="speed-stat-value" style="color:var(--blue-dark)">${latest.downloadMbps.toFixed(1)}<span class="speed-stat-unit"> Mbps</span></div>
      </div>
      <div class="speed-stat">
        <div class="speed-stat-label">Latest Upload</div>
        <div class="speed-stat-value" style="color:var(--green)">${latest.uploadMbps.toFixed(1)}<span class="speed-stat-unit"> Mbps</span></div>
      </div>
      <div class="speed-stat">
        <div class="speed-stat-label">Latency</div>
        <div class="speed-stat-value" style="color:var(--amber)">${latest.latencyMs}<span class="speed-stat-unit"> ms</span></div>
      </div>
      <div class="speed-stat">
        <div class="speed-stat-label">Jitter</div>
        <div class="speed-stat-value">${latest.jitterMs.toFixed(1)}<span class="speed-stat-unit"> ms</span></div>
      </div>
      <div class="speed-stat" style="text-align:left;flex:2;min-width:180px">
        <div class="speed-stat-label">ISP / External IP</div>
        <div style="font-size:14px;font-weight:600;margin-top:4px">${latest.isp}</div>
        <div class="isp-ip">${maskIp(latest.externalIp)}</div>
      </div>
    </div>

    <!-- Chart inserted here in Task 5 -->
    <div id="chartSection"></div>

    <!-- Test log table -->
    <div class="card" style="padding:0;overflow:hidden">
      <div class="tbl-toolbar" style="padding:14px 16px">
        <span class="tbl-title">Speed History</span>
      </div>
      <div class="tbl-section">
        <table>
          <thead>
            <tr>
              <th>Date & Time</th>
              <th>Download</th>
              <th>Upload</th>
              <th>Latency</th>
              <th>Jitter</th>
              <th>ISP</th>
            </tr>
          </thead>
          <tbody>
            ${_testHistory.map((r, i) => `
              <tr class="${i === 0 ? "latest" : ""}">
                <td>${fmtDate(r.timestamp)}${i === 0 ? " ★" : ""}</td>
                <td class="tbl-down">${r.downloadMbps.toFixed(1)} Mbps</td>
                <td class="tbl-up">${r.uploadMbps.toFixed(1)} Mbps</td>
                <td>${r.latencyMs} ms</td>
                <td>${r.jitterMs.toFixed(1)} ms</td>
                <td>${r.isp}</td>
              </tr>`).join("")}
          </tbody>
        </table>
      </div>
    </div>`;
}
```

- [ ] **Step 3: Verify with injected test data**

In DevTools Console, inject mock data and re-render to confirm layout:
```javascript
_testHistory = [
  { timestamp:"2026-05-06T14:14:00Z", downloadMbps:87.4, uploadMbps:42.1, latencyMs:24, jitterMs:3.2, isp:"Comcast Business", externalIp:"72.100.200.5", deviceName:"TEST" },
  { timestamp:"2026-04-28T09:42:00Z", downloadMbps:71.2, uploadMbps:39.0, latencyMs:31, jitterMs:5.1, isp:"Comcast Business", externalIp:"72.100.200.5", deviceName:"TEST" }
];
renderResults();
```
Expected: stat pills show 87.4 Mbps / 42.1 Mbps / 24 ms / 3.2 ms, ISP shows "Comcast Business", table shows 2 rows with the first highlighted in blue.

- [ ] **Step 4: Commit**

```bash
git add tools/network-speed-monitor/index.html
git commit -m "feat(network-speed-monitor): add stat pills and test log table"
```

---

## Task 5: Speed History Chart

**Files:**
- Modify: `tools/network-speed-monitor/index.html`

- [ ] **Step 1: Add chart CSS**

Add inside `<style>`:
```css
  /* Bar chart */
  .chart-card { margin-bottom:1.25rem; }
  .chart-title { font-size:12px; font-weight:600; text-transform:uppercase;
    letter-spacing:.05em; color:var(--muted); margin-bottom:12px; }
  .chart-row   { display:flex; align-items:center; gap:8px; margin-bottom:8px; }
  .chart-label { width:50px; font-size:11px; color:var(--muted); text-align:right;
    white-space:nowrap; flex-shrink:0; }
  .chart-label.latest { color:var(--fg); font-weight:700; }
  .chart-bars  { flex:1; display:flex; flex-direction:column; gap:4px; }
  .chart-bar-row { display:flex; align-items:center; gap:6px; }
  .chart-val   { width:32px; font-size:10px; font-weight:700; text-align:right; flex-shrink:0; }
  .chart-val.down { color:var(--blue-dark); }
  .chart-val.up   { color:var(--green); }
  .chart-track { flex:1; height:13px; border-radius:3px; overflow:hidden; }
  .chart-track.down { background:var(--blue-light); }
  .chart-track.up   { background:var(--green-light); }
  .chart-fill  { height:100%; border-radius:3px; }
  .chart-fill.down { background:var(--blue-dark); }
  .chart-fill.up   { background:var(--green); }
  .chart-unit  { width:30px; font-size:10px; color:var(--muted); flex-shrink:0; }
  .chart-row.latest-row { background:var(--blue-light); border-radius:var(--radius-sm);
    padding:5px 4px; border-left:3px solid var(--blue-dark); }
  .chart-legend { display:flex; gap:14px; margin-top:8px; }
  .chart-legend-item { display:flex; align-items:center; gap:5px; font-size:11px; color:var(--muted); }
  .chart-legend-dot  { width:10px; height:10px; border-radius:2px; }
```

- [ ] **Step 2: Add `renderChart()` and call it from `renderResults()`**

Add this function:
```javascript
function renderChart() {
  const sec = document.getElementById("chartSection");
  if (!sec || _testHistory.length < 1) return;

  // Show oldest→newest (chart reads left to right chronologically)
  const rows = [..._testHistory].reverse();
  const maxVal = Math.max(
    100,
    ...rows.map(r => Math.max(r.downloadMbps, r.uploadMbps))
  );

  function fmtChartDate(iso) {
    return new Date(iso).toLocaleDateString("en-US", { month:"short", day:"numeric" });
  }

  const rowsHtml = rows.map((r, i) => {
    const isLatest    = i === rows.length - 1;
    const downPct     = Math.max(2, (r.downloadMbps / maxVal) * 100).toFixed(1);
    const upPct       = Math.max(2, (r.uploadMbps   / maxVal) * 100).toFixed(1);
    const labelCls    = isLatest ? "chart-label latest" : "chart-label";
    const rowCls      = isLatest ? "chart-row latest-row" : "chart-row";
    const dateLbl     = fmtChartDate(r.timestamp) + (isLatest ? " ★" : "");

    return `<div class="${rowCls}">
      <div class="${labelCls}">${dateLbl}</div>
      <div class="chart-bars">
        <div class="chart-bar-row">
          <div class="chart-val down">${r.downloadMbps.toFixed(1)}</div>
          <div class="chart-track down"><div class="chart-fill down" style="width:${downPct}%"></div></div>
          <div class="chart-unit">Mbps</div>
        </div>
        <div class="chart-bar-row">
          <div class="chart-val up">${r.uploadMbps.toFixed(1)}</div>
          <div class="chart-track up"><div class="chart-fill up" style="width:${upPct}%"></div></div>
          <div class="chart-unit">Mbps</div>
        </div>
      </div>
    </div>`;
  }).join("");

  sec.innerHTML = `
    <div class="card chart-card">
      <div class="chart-title">Speed History</div>
      ${rowsHtml}
      <div class="chart-legend">
        <div class="chart-legend-item"><div class="chart-legend-dot" style="background:var(--blue-dark)"></div>Download</div>
        <div class="chart-legend-item"><div class="chart-legend-dot" style="background:var(--green)"></div>Upload</div>
      </div>
    </div>`;
}
```

At the end of `renderResults()`, just before the closing brace (after `sec.innerHTML = ...`), call `renderChart()`:
```javascript
  // call after setting innerHTML so #chartSection exists
  renderChart();
```

Wait — `renderChart()` reads `#chartSection` which is inside `sec.innerHTML`. Call it on the next line after setting `sec.innerHTML`:

In `renderResults()`, add this immediately after the `sec.innerHTML = \`...\`` assignment:
```javascript
  renderChart();
```

- [ ] **Step 3: Verify chart renders correctly**

Re-run the console injection from Task 4 Step 3 and call `renderResults()`. Confirm:
- Chart shows one group per test date, oldest left → newest right
- Each group has blue download bar and green upload bar
- Mbps values appear to the left of each bar, "Mbps" label to the right
- Most recent test row has blue left border and light blue background
- Bars scale correctly — a 50 Mbps bar should be roughly half the width of a 100 Mbps bar

- [ ] **Step 4: Commit**

```bash
git add tools/network-speed-monitor/index.html
git commit -m "feat(network-speed-monitor): add horizontal bar chart with labeled Mbps values"
```

---

## Task 6: Run Fresh Test Button

**Files:**
- Modify: `tools/network-speed-monitor/index.html`

- [ ] **Step 1: Implement `runFreshTest()`**

Add this function:
```javascript
async function runFreshTest() {
  if (!_currentDevice) return;
  const btn = document.getElementById("freshBtn");

  try {
    await ITTools.ui.withButtonSpinner(btn, async () => {
      const token = await ITTools.auth.getToken();
      const res   = await fetch(
        `https://graph.microsoft.com/beta/deviceManagement/managedDevices/${_currentDevice.id}/initiateOnDemandProactiveRemediation`,
        {
          method:  "POST",
          headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
          body:    JSON.stringify({ scriptPolicyId: SCRIPT_POLICY_ID }),
        }
      );

      if (!res.ok && res.status !== 204) {
        const body = await res.json().catch(() => ({}));
        const msg  = body?.error?.message || `Graph error ${res.status}`;
        if (res.status === 403) throw new Error("Permission denied — ensure DeviceManagementConfiguration.ReadWrite.All is consented.");
        if (res.status === 404) throw new Error("Remediation script not found — verify SCRIPT_POLICY_ID is set correctly.");
        throw new Error(msg);
      }

      _pendingTest = true;
      document.getElementById("pendingBanner").classList.add("show");
    }, "Triggering…");
  } catch(e) {
    document.getElementById("searchErr").textContent   = ITTools.graph.friendlyError(e);
    document.getElementById("searchErr").style.display = "block";
  }
}
```

- [ ] **Step 2: Verify in DevTools**

Search for a real device, click "⚡ Run Fresh Test". Check:
- Button shows "Triggering…" spinner while the call is in flight
- DevTools Network tab shows a `POST` to `graph.microsoft.com/beta/deviceManagement/managedDevices/{id}/initiateOnDemandProactiveRemediation` returning 204
- Pending banner appears: "Test triggered — results will appear after the device checks in…"
- If `SCRIPT_POLICY_ID` is still the placeholder, a 404 error message should appear — that is the expected failure mode before the Intune setup is complete

- [ ] **Step 3: Commit**

```bash
git add tools/network-speed-monitor/index.html
git commit -m "feat(network-speed-monitor): trigger on-demand Intune remediation per device"
```

---

## Task 7: PDF Export

**Files:**
- Modify: `tools/network-speed-monitor/index.html`

- [ ] **Step 1: Implement `exportPdf()`**

Add this function (uses jsPDF loaded from CDN in the `<head>`):
```javascript
function exportPdf() {
  if (!_currentDevice || !_testHistory.length) {
    document.getElementById("searchErr").textContent   = "No data to export — run a test first.";
    document.getElementById("searchErr").style.display = "block";
    return;
  }

  const { jsPDF } = window.jspdf;
  const doc = new jsPDF({ unit: "pt", format: "letter" });
  const PW = 612, M = 40;
  let y = M;

  // ── Helpers ──────────────────────────────────────────────────
  function hline(yPos, color = [229, 231, 235]) {
    doc.setDrawColor(...color);
    doc.line(M, yPos, PW - M, yPos);
  }
  function label(text, xPos, yPos, color = [107, 114, 128]) {
    doc.setFont("helvetica", "normal").setFontSize(8).setTextColor(...color);
    doc.text(text.toUpperCase(), xPos, yPos);
  }
  function val(text, xPos, yPos, color = [17, 24, 39], size = 12, style = "normal") {
    doc.setFont("helvetica", style).setFontSize(size).setTextColor(...color);
    doc.text(String(text), xPos, yPos);
  }

  const latest = _testHistory[0];
  const d      = _currentDevice;

  function fmtDate(iso) {
    return new Date(iso).toLocaleString("en-US", {
      month:"short", day:"numeric", year:"numeric", hour:"2-digit", minute:"2-digit"
    });
  }

  const adminUpn = ITTools.auth.getAccount()?.username || "—";

  // ── Header bar ───────────────────────────────────────────────
  doc.setFillColor(26, 86, 219);
  doc.rect(M, y, PW - M * 2, 2, "F");
  y += 16;

  val("Network Speed Report", M, y, [17, 24, 39], 18, "bold");
  val("Corro Health IT  ·  Confidential", PW - M, y, [156, 163, 175], 9, "normal");
  doc.setTextAlignment?.("right"); // graceful no-op in older jsPDF
  y += 5;
  val(`Generated: ${fmtDate(new Date().toISOString())}`, M, y, [107, 114, 128], 9);
  val(`Prepared by: ${adminUpn}`, M, y + 11, [107, 114, 128], 9);
  y += 28;
  hline(y); y += 14;

  // ── Device info row ──────────────────────────────────────────
  const cols = [
    ["Device",  d.deviceName],
    ["User",    d.userDisplayName || "—"],
    ["Dept",    d.department],
    ["Tests",   String(_testHistory.length)],
    ["ISP",     latest.isp],
  ];
  const colW = (PW - M * 2) / cols.length;
  cols.forEach(([lbl, v], i) => {
    const x = M + i * colW;
    label(lbl, x, y);
    val(v, x, y + 14, [17, 24, 39], 11, "bold");
  });
  y += 36;
  hline(y); y += 16;

  // ── Most recent test tiles ───────────────────────────────────
  label("Most Recent Test  ·  " + fmtDate(latest.timestamp), M, y);
  y += 12;

  const tiles = [
    { label: "Download", value: latest.downloadMbps.toFixed(1), unit: "Mbps", rgb: [26, 86, 219],  bgRgb: [239, 246, 255] },
    { label: "Upload",   value: latest.uploadMbps.toFixed(1),   unit: "Mbps", rgb: [4, 120, 87],   bgRgb: [240, 253, 244] },
    { label: "Latency",  value: String(latest.latencyMs),        unit: "ms",   rgb: [146, 64, 14],  bgRgb: [255, 251, 235] },
    { label: "Jitter",   value: latest.jitterMs.toFixed(1),      unit: "ms",   rgb: [55, 65, 81],   bgRgb: [249, 250, 251] },
  ];
  const tileW = (PW - M * 2 - 9 * 3) / 4;
  tiles.forEach(({ label: lbl, value, unit, rgb, bgRgb }, i) => {
    const tx = M + i * (tileW + 9);
    doc.setFillColor(...bgRgb);
    doc.roundedRect(tx, y, tileW, 52, 4, 4, "F");
    label(lbl, tx + 8, y + 14);
    val(value, tx + 8, y + 34, rgb, 22, "bold");
    val(unit,  tx + 8, y + 46, rgb, 9);
  });
  y += 66;

  // ── Bar chart ────────────────────────────────────────────────
  label("Speed Trend — All Tests", M, y);
  y += 14;

  const chartRows = [..._testHistory].reverse();
  const maxVal    = Math.max(100, ...chartRows.map(r => Math.max(r.downloadMbps, r.uploadMbps)));
  const barAreaW  = PW - M * 2 - 80; // 80pt reserved for date label + val label
  const dateColW  = 52;
  const valColW   = 26;
  const barW      = barAreaW - dateColW - valColW;

  chartRows.forEach((r, i) => {
    const isLatest = i === chartRows.length - 1;
    const rowH     = 28;

    if (isLatest) {
      doc.setFillColor(239, 246, 255);
      doc.rect(M, y - 4, PW - M * 2, rowH + 2, "F");
      doc.setFillColor(26, 86, 219);
      doc.rect(M, y - 4, 3, rowH + 2, "F");
    }

    const dateStr = new Date(r.timestamp).toLocaleDateString("en-US", { month:"short", day:"numeric" })
      + (isLatest ? " ★" : "");
    const lbl = isLatest ? [17, 24, 39] : [107, 114, 128];
    val(dateStr, M + 2, y + 7, lbl, 8, isLatest ? "bold" : "normal");

    // Download bar
    const downW = Math.max(2, (r.downloadMbps / maxVal) * barW);
    val(r.downloadMbps.toFixed(1), M + dateColW, y + 7, [26, 86, 219], 8, "bold");
    doc.setFillColor(219, 234, 254);
    doc.rect(M + dateColW + valColW, y, barW, 6, "F");
    doc.setFillColor(26, 86, 219);
    doc.rect(M + dateColW + valColW, y, downW, 6, "F");

    // Upload bar
    const upW = Math.max(2, (r.uploadMbps / maxVal) * barW);
    val(r.uploadMbps.toFixed(1), M + dateColW, y + 17, [4, 120, 87], 8, "bold");
    doc.setFillColor(209, 250, 229);
    doc.rect(M + dateColW + valColW, y + 10, barW, 6, "F");
    doc.setFillColor(4, 120, 87);
    doc.rect(M + dateColW + valColW, y + 10, upW, 6, "F");

    y += rowH;
  });

  // Legend
  doc.setFillColor(26, 86, 219);
  doc.rect(M, y + 4, 8, 8, "F");
  val("Download (Mbps)", M + 12, y + 11, [107, 114, 128], 8);
  doc.setFillColor(4, 120, 87);
  doc.rect(M + 100, y + 4, 8, 8, "F");
  val("Upload (Mbps)", M + 114, y + 11, [107, 114, 128], 8);
  y += 22;
  hline(y); y += 14;

  // ── Full test log table ───────────────────────────────────────
  label("Full Test Log", M, y); y += 12;

  const tblCols = ["Date & Time", "Down (Mbps)", "Up (Mbps)", "Latency (ms)", "Jitter (ms)"];
  const tblW    = [160, 75, 75, 85, 75];
  let   tx      = M;

  // Header row
  doc.setFillColor(243, 244, 246);
  doc.rect(M, y, PW - M * 2, 18, "F");
  tblCols.forEach((col, i) => {
    label(col, tx + 4, y + 12);
    tx += tblW[i];
  });
  y += 18;

  // Data rows
  _testHistory.forEach((r, i) => {
    if (i === 0) { doc.setFillColor(239, 246, 255); doc.rect(M, y, PW - M * 2, 18, "F"); }
    tx = M;
    const rowData = [
      fmtDate(r.timestamp) + (i === 0 ? " ★" : ""),
      r.downloadMbps.toFixed(1),
      r.uploadMbps.toFixed(1),
      String(r.latencyMs),
      r.jitterMs.toFixed(1),
    ];
    rowData.forEach((cell, j) => {
      const color = j === 1 ? [26, 86, 219] : j === 2 ? [4, 120, 87] : [17, 24, 39];
      const style = i === 0 ? "bold" : "normal";
      val(cell, tx + 4, y + 12, color, 9, style);
      tx += tblW[j];
    });
    doc.setDrawColor(229, 231, 235);
    doc.line(M, y + 18, PW - M, y + 18);
    y += 18;
  });
  y += 12;

  // ── Footer ───────────────────────────────────────────────────
  hline(y); y += 10;
  const footerText = "Tests triggered on-demand via Intune Remediation Script. Results measured using Speedtest CLI on the device and stored in SharePoint. This report reflects all available test results for this device.";
  const lines = doc.splitTextToSize(footerText, PW - M * 2);
  doc.setFont("helvetica", "normal").setFontSize(8).setTextColor(156, 163, 175);
  doc.text(lines, M, y);

  // ── Save ─────────────────────────────────────────────────────
  const filename = `SpeedReport_${d.deviceName}_${new Date().toISOString().slice(0, 10)}.pdf`;
  doc.save(filename);
}
```

- [ ] **Step 2: Verify PDF exports correctly**

With mock test data injected (from Task 4 Step 3), click "↓ Export PDF". Confirm:
- File downloads as `SpeedReport_TEST_2026-05-07.pdf`
- PDF contains: header with blue bar, device info row, four stat tiles, bar chart with labeled Mbps values, test log table, footer note
- Most recent test is highlighted in the chart and table
- Download bars are blue, upload bars are green
- Mbps values appear to the left of each bar

- [ ] **Step 3: Commit**

```bash
git add tools/network-speed-monitor/index.html
git commit -m "feat(network-speed-monitor): add in-browser PDF export via jsPDF"
```

---

## Task 8: Wire Up Config.json and Hub

**Files:**
- Modify: `config.json`

- [ ] **Step 1: Add tool entry to config.json**

Open `config.json`. After the last tool object and before the closing `]`, add a comma and then:
```json
    {
      "id": "network-speed-monitor",
      "name": "Network Speed Monitor",
      "description": "Investigate upload/download speeds on a specific Intune-enrolled device and export a trend report for leadership.",
      "betaNote": "Requires Intune Proactive Remediation setup and a SharePoint results list — see setup instructions in tools/network-speed-monitor/index.html.",
      "icon": "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='#1a56db' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M22 12h-4l-3 9L9 3l-3 9H2'/></svg>",
      "status": "beta",
      "path": "tools/network-speed-monitor/",
      "permissions": [
        "DeviceManagementManagedDevices.Read.All",
        "DeviceManagementConfiguration.ReadWrite.All",
        "Sites.ReadWrite.All"
      ],
      "accent": "#1a56db",
      "iconBg": "#e8f0fe",
      "category": "reporting-audit",
      "reportingOnly": true
    }
```

- [ ] **Step 2: Verify hub card appears**

Open the IT Tools Hub (`index.html`). Confirm:
- "Network Speed Monitor" card appears in the grid with the correct icon and blue accent
- "Beta" ribbon shows on the card
- Clicking the card navigates to `tools/network-speed-monitor/`

- [ ] **Step 3: Commit**

```bash
git add config.json
git commit -m "feat(network-speed-monitor): add tool card to hub config"
```

---

## Task 9: PowerShell Remediation Scripts

**Files:**
- Create: `tools/network-speed-monitor/remediation/detect.ps1`
- Create: `tools/network-speed-monitor/remediation/remediate.ps1`

- [ ] **Step 1: Write detect.ps1**

```powershell
# detect.ps1 — Intune Proactive Remediation detection script
# Always exits 1 (not healthy) so the remediation script always runs when triggered.
# Intune on-demand trigger (initiateOnDemandProactiveRemediation) only runs the
# remediation script when detection exits 1 — this ensures the test actually fires.
exit 1
```

- [ ] **Step 2: Write remediate.ps1**

```powershell
# remediate.ps1 — Intune Proactive Remediation script
# Downloads Speedtest CLI, runs a speed test, and POSTs results to a SharePoint list.
#
# SETUP: Replace all REPLACE_WITH_* placeholders before deploying to Intune.
#
# Required: An Azure AD App Registration with:
#   - Sites.ReadWrite.All (Application permission, admin-consented)
#   - Client secret generated and stored below
#
# Do NOT store credentials in plain text in production — use Intune's script
# parameter store or Azure Key Vault if your security policy requires it.

param(
  [string]$ClientId      = "REPLACE_WITH_APP_REGISTRATION_CLIENT_ID",
  [string]$ClientSecret  = "REPLACE_WITH_APP_REGISTRATION_CLIENT_SECRET",
  [string]$TenantId      = "REPLACE_WITH_TENANT_ID",
  [string]$SpSiteId      = "REPLACE_WITH_SHAREPOINT_SITE_ID",
  [string]$SpListId      = "REPLACE_WITH_SHAREPOINT_LIST_ID",
  [string]$SpeedtestUrl  = "REPLACE_WITH_INTERNAL_SPEEDTEST_EXE_URL"
)

$ErrorActionPreference = "Stop"
$tempExe = Join-Path $env:TEMP "speedtest_run.exe"

try {
  # 1. Download Speedtest CLI from internal hosting
  Invoke-WebRequest -Uri $SpeedtestUrl -OutFile $tempExe -UseBasicParsing

  # 2. Run speed test and capture JSON output
  $raw    = & $tempExe --format=json --accept-license --accept-gdpr 2>$null
  $result = $raw | ConvertFrom-Json

  # Speedtest CLI returns bandwidth in bytes/sec — convert to Mbps
  $downloadMbps = [math]::Round($result.download.bandwidth / 125000, 1)
  $uploadMbps   = [math]::Round($result.upload.bandwidth   / 125000, 1)
  $latencyMs    = [math]::Round($result.ping.latency, 0)
  $jitterMs     = [math]::Round($result.ping.jitter,  1)
  $isp          = $result.isp
  $externalIp   = $result.interface.externalIp
  $timestamp    = (Get-Date).ToUniversalTime().ToString("o")
  $deviceName   = $env:COMPUTERNAME

  # 3. Get Graph API token (client credentials flow)
  $tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = "https://graph.microsoft.com/.default"
  }
  $tokenRes    = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                   -Method POST -Body $tokenBody
  $accessToken = $tokenRes.access_token

  # 4. POST result to SharePoint list
  $headers = @{
    Authorization  = "Bearer $accessToken"
    "Content-Type" = "application/json"
  }
  $listItemBody = @{
    fields = @{
      DeviceName    = $deviceName
      IntuneDeviceId = ""          # device cannot self-report its Intune ID reliably
      Timestamp     = $timestamp
      DownloadMbps  = $downloadMbps
      UploadMbps    = $uploadMbps
      LatencyMs     = $latencyMs
      JitterMs      = $jitterMs
      ISP           = $isp
      ExternalIP    = $externalIp
    }
  } | ConvertTo-Json -Depth 3

  Invoke-RestMethod `
    -Uri     "https://graph.microsoft.com/v1.0/sites/$SpSiteId/lists/$SpListId/items" `
    -Method  POST `
    -Headers $headers `
    -Body    $listItemBody

  Write-Output "Speed test complete: Down=${downloadMbps} Mbps, Up=${uploadMbps} Mbps, Latency=${latencyMs}ms"
  exit 0

} catch {
  Write-Error "Speed test remediation failed: $_"
  exit 1

} finally {
  # Always clean up the temp binary
  if (Test-Path $tempExe) { Remove-Item $tempExe -Force -ErrorAction SilentlyContinue }
}
```

- [ ] **Step 3: Verify scripts are syntactically valid**

Run in a local PowerShell session (not on a device — just to check syntax):
```powershell
# Check detect.ps1 parses without error
$null = [System.Management.Automation.Language.Parser]::ParseFile(
  "C:\dev\projects\it-tools\tools\network-speed-monitor\remediation\detect.ps1", [ref]$null, [ref]$null)
Write-Host "detect.ps1: OK"

# Check remediate.ps1 parses without error
$null = [System.Management.Automation.Language.Parser]::ParseFile(
  "C:\dev\projects\it-tools\tools\network-speed-monitor\remediation\remediate.ps1", [ref]$null, [ref]$null)
Write-Host "remediate.ps1: OK"
```
Expected output: both lines print `OK` with no red errors.

- [ ] **Step 4: Commit**

```bash
git add tools/network-speed-monitor/remediation/detect.ps1
git add tools/network-speed-monitor/remediation/remediate.ps1
git commit -m "feat(network-speed-monitor): add Intune Proactive Remediation PowerShell scripts"
```

---

## Self-Review Checklist

Spec section → task coverage:

| Spec Requirement | Task |
|-----------------|------|
| Device search via Intune managedDevices | Task 2 |
| Historical results from SharePoint list | Task 3 |
| Stat pills (down, upload, latency, jitter, ISP) | Task 4 |
| Full test log table, reverse-chrono, latest highlighted | Task 4 |
| Horizontal bar chart, Mbps values labeled, latest highlighted | Task 5 |
| Run Fresh Test → `initiateOnDemandProactiveRemediation` | Task 6 |
| Pending state banner after trigger | Task 6 |
| PDF export with header, device info, tiles, chart, table, footer | Task 7 |
| Config.json entry + hub card | Task 8 |
| PowerShell detection + remediation scripts | Task 9 |
| Device not found error | Task 2 (`renderDeviceCard` + error banner) |
| No prior tests empty state | Task 4 |
| Test pending state | Task 6 |
| Speedtest CLI download at runtime | Task 9 (`remediate.ps1`) |
| Chart scale dynamic (max of dataset, min 100) | Task 5 |
| PDF chart bars labeled with Mbps values | Task 7 |
