# Exchange Audit Tool — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a hub tool that surfaces all Exchange mailboxes ranked by Recoverable Items quota usage, with per-user drill-in showing the same diagnostic data as Mailbox Cleanup Phase 2, fed by a weekly Azure Automation runbook that writes JSON to Azure Blob Storage.

**Architecture:** Azure Automation runbook (`Invoke-ExchangeAudit.ps1`) runs weekly via managed identity, performs a two-pass Exchange scan, and writes `exchange-audit.json` to Azure Blob Storage. The static hub page fetches that blob on load and renders the data client-side — no Graph API calls, no backend. Local file fallback (file picker) enables development without Azure.

**Tech Stack:** Vanilla JS, HTML/CSS using existing `shared/styles.css` CSS custom properties, PowerShell 7 + ExchangeOnlineManagement v3.9+ + Az.Storage for the runbook.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `tools/exchange-audit/index.html` | Create | Full self-contained hub tool page |
| `tools/exchange-audit/Invoke-ExchangeAudit.ps1` | Create | Azure Automation runbook |
| `tools/exchange-audit/sample-data.json` | Create | Realistic mock JSON for local dev/testing |
| `config.json` | Modify | Add exchange-audit entry |

---

### Task 1: config.json entry + HTML skeleton + sample data

**Files:**
- Modify: `config.json`
- Create: `tools/exchange-audit/index.html`
- Create: `tools/exchange-audit/sample-data.json`

- [ ] **Step 1: Add exchange-audit entry to config.json**

Open `config.json`. Add this entry to the `"tools"` array (after the last entry, before the closing `]`):

```json
,
{
  "id": "exchange-audit",
  "name": "Exchange Audit",
  "description": "Weekly snapshot of all Exchange mailboxes ranked by Recoverable Items quota usage. Drill into any user for SIR status, hold details, and folder breakdown.",
  "icon": "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='#1a56db' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect width='20' height='16' x='2' y='4' rx='2'/><path d='m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7'/></svg>",
  "status": "beta",
  "path": "tools/exchange-audit/",
  "accent": "#1a56db",
  "iconBg": "#e8f0fe",
  "category": "reporting-audit",
  "reportingOnly": true
}
```

- [ ] **Step 2: Create sample-data.json**

Create `tools/exchange-audit/sample-data.json`:

```json
{
  "lastScan": "2026-05-26T02:14:37Z",
  "runDurationSeconds": 203,
  "totalMailboxes": 412,
  "mailboxes": [
    {
      "upn": "hrconnect@corrohealth.com",
      "displayName": "HR Connect",
      "recoverableUsedBytes": 128586891264,
      "recoverableQuotaBytes": 107374182400,
      "recoverablePct": 120,
      "status": "critical",
      "sirEnabled": false,
      "elcProcessingDisabled": false,
      "retentionHoldEnabled": false,
      "litigationHold": false,
      "delayHoldApplied": false,
      "inPlaceHoldsCount": 0,
      "hasDetailStats": true,
      "folders": {
        "discoveryHoldsBytes": 128449339392,
        "discoveryHoldsItems": 55712,
        "purgesBytes": 0,
        "purgesItems": 0,
        "versionsBytes": 19456,
        "substrateHoldsBytes": 19456
      }
    },
    {
      "upn": "divyalakshmi.palanivel@corrohealth.com",
      "displayName": "Divyalakshmi Palanivel",
      "recoverableUsedBytes": 89370009600,
      "recoverableQuotaBytes": 107374182400,
      "recoverablePct": 83,
      "status": "warning",
      "sirEnabled": true,
      "elcProcessingDisabled": false,
      "retentionHoldEnabled": false,
      "litigationHold": false,
      "delayHoldApplied": false,
      "inPlaceHoldsCount": 1,
      "hasDetailStats": true,
      "folders": {
        "discoveryHoldsBytes": 85899345920,
        "discoveryHoldsItems": 402000,
        "purgesBytes": 2147483648,
        "purgesItems": 1200,
        "versionsBytes": 0,
        "substrateHoldsBytes": 1048576
      }
    },
    {
      "upn": "blocked.elc@corrohealth.com",
      "displayName": "Blocked ELC User",
      "recoverableUsedBytes": 96636764160,
      "recoverableQuotaBytes": 107374182400,
      "recoverablePct": 90,
      "status": "critical",
      "sirEnabled": true,
      "elcProcessingDisabled": true,
      "retentionHoldEnabled": false,
      "litigationHold": false,
      "delayHoldApplied": false,
      "inPlaceHoldsCount": 0,
      "hasDetailStats": true,
      "folders": {
        "discoveryHoldsBytes": 96636764160,
        "discoveryHoldsItems": 800000,
        "purgesBytes": 0,
        "purgesItems": 0,
        "versionsBytes": 0,
        "substrateHoldsBytes": 0
      }
    },
    {
      "upn": "john.smith@corrohealth.com",
      "displayName": "John Smith",
      "recoverableUsedBytes": 21474836480,
      "recoverableQuotaBytes": 107374182400,
      "recoverablePct": 20,
      "status": "ok",
      "sirEnabled": true,
      "elcProcessingDisabled": false,
      "retentionHoldEnabled": false,
      "litigationHold": false,
      "delayHoldApplied": false,
      "inPlaceHoldsCount": 0,
      "hasDetailStats": false
    }
  ]
}
```

- [ ] **Step 3: Create tools/exchange-audit/index.html skeleton**

Create `tools/exchange-audit/index.html` with the full page structure — no JS logic yet, just the HTML/CSS shell:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Exchange Audit — IT Tools</title>
<link rel="stylesheet" href="../../shared/styles.css"/>
<style>
  /* ── Layout ───────────────────────────────────────────────── */
  .audit-wrap     { padding: 1.25rem 1.5rem; max-width: 1400px; margin: 0 auto; }
  .audit-strip    { display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
                    margin-bottom: 1rem; padding: 10px 14px;
                    background: var(--surface); border: 1px solid var(--border);
                    border-radius: var(--radius); }
  .audit-layout   { display: grid; grid-template-columns: 60% 1fr; gap: 1rem;
                    height: calc(100vh - 200px); min-height: 500px; }
  .audit-table-wrap { overflow-y: auto; border: 1px solid var(--border);
                      border-radius: var(--radius); background: var(--surface); }
  .audit-panel    { border: 1px solid var(--border); border-radius: var(--radius);
                    background: var(--surface); overflow-y: auto; }

  /* ── Summary strip ───────────────────────────────────────── */
  .strip-scan     { font-size: 12px; color: var(--muted); margin-right: auto; }
  .strip-scan strong { color: var(--text); }
  .strip-scan.stale  { color: var(--amber); }
  .strip-scan.expired { color: var(--red); }
  .count-pill     { display: inline-flex; align-items: center; gap: 5px;
                    padding: 4px 10px; border-radius: 20px; font-size: 12px;
                    font-weight: 600; border: 1.5px solid; cursor: pointer;
                    transition: opacity .12s; white-space: nowrap; }
  .count-pill:hover { opacity: .75; }
  .pill-critical  { background: var(--red-light); color: var(--red); border-color: var(--red-border); }
  .pill-warning   { background: var(--amber-light); color: var(--amber); border-color: var(--amber-border); }
  .pill-total     { background: var(--surface2); color: var(--text); border-color: var(--border); cursor: default; }
  .strip-search   { padding: 5px 10px; border: 1px solid var(--border); border-radius: 6px;
                    background: var(--surface2); color: var(--text); font-size: 13px;
                    width: 200px; outline: none; }
  .strip-search:focus { border-color: var(--blue-mid); }
  .strip-select   { padding: 5px 8px; border: 1px solid var(--border); border-radius: 6px;
                    background: var(--surface2); color: var(--text); font-size: 12px;
                    cursor: pointer; outline: none; }

  /* ── Table ───────────────────────────────────────────────── */
  .audit-table    { width: 100%; border-collapse: collapse; font-size: 13px; }
  .audit-table th { position: sticky; top: 0; background: var(--surface2);
                    padding: 9px 14px; text-align: left; font-size: 11px;
                    font-weight: 700; text-transform: uppercase; letter-spacing: .05em;
                    color: var(--muted); border-bottom: 1px solid var(--border); }
  .audit-table td { padding: 9px 14px; border-bottom: 1px solid var(--border);
                    vertical-align: middle; }
  .audit-table tr:last-child td { border-bottom: none; }
  .audit-table tr.row-sel td    { background: var(--blue-light); }
  .audit-table tbody tr         { cursor: pointer; transition: background .1s; }
  .audit-table tbody tr:hover td { background: var(--surface2); }
  .audit-table tbody tr.row-sel:hover td { background: var(--blue-light); }
  .row-sel td:first-child { border-left: 3px solid var(--blue); padding-left: 11px; }

  .upn-cell       { line-height: 1.4; }
  .upn-name       { font-weight: 600; color: var(--text); }
  .upn-addr       { font-size: 11px; color: var(--muted); }

  .usage-bar-wrap { display: flex; align-items: center; gap: 8px; }
  .usage-bar      { flex: 1; height: 6px; border-radius: 3px; background: var(--surface3);
                    overflow: hidden; min-width: 60px; }
  .usage-fill     { height: 100%; border-radius: 3px; transition: width .2s; }
  .fill-green  { background: var(--green); }
  .fill-amber  { background: var(--amber); }
  .fill-red    { background: var(--red); }
  .usage-pct   { font-size: 12px; font-weight: 600; min-width: 36px; text-align: right; }
  .pct-green   { color: var(--green); }
  .pct-amber   { color: var(--amber); }
  .pct-red     { color: var(--red); }

  .status-badge   { display: inline-block; padding: 2px 7px; border-radius: 4px;
                    font-size: 10px; font-weight: 700; letter-spacing: .04em;
                    text-transform: uppercase; border: 1px solid; }
  .badge-critical { background: var(--red-light); color: var(--red); border-color: var(--red-border); }
  .badge-warning  { background: var(--amber-light); color: var(--amber); border-color: var(--amber-border); }

  /* ── Side panel ──────────────────────────────────────────── */
  .panel-empty    { display: flex; align-items: center; justify-content: center;
                    height: 100%; color: var(--muted); font-size: 13px; padding: 2rem;
                    text-align: center; }
  .panel-body     { padding: 1.25rem; }
  .panel-name     { font-size: 16px; font-weight: 700; color: var(--text);
                    margin-bottom: 2px; }
  .panel-upn      { font-size: 11px; color: var(--muted); margin-bottom: 1rem;
                    word-break: break-all; }
  .panel-bar-wrap { margin-bottom: 1rem; }
  .panel-bar      { height: 8px; border-radius: 4px; background: var(--surface3);
                    overflow: hidden; margin-top: 6px; }
  .panel-fill     { height: 100%; border-radius: 4px; }
  .panel-quota    { display: flex; justify-content: space-between; font-size: 12px;
                    color: var(--muted); margin-top: 4px; }

  .panel-section  { margin-top: 1rem; }
  .panel-sec-lbl  { font-size: 10px; font-weight: 700; text-transform: uppercase;
                    letter-spacing: .07em; color: var(--muted2); margin-bottom: 6px; }
  .panel-row      { display: flex; justify-content: space-between; align-items: center;
                    padding: 5px 0; border-bottom: 1px solid var(--border);
                    font-size: 13px; }
  .panel-row:last-child { border-bottom: none; }
  .panel-lbl      { color: var(--muted); font-size: 12px; }
  .panel-val      { font-weight: 600; }
  .val-green      { color: var(--green); }
  .val-amber      { color: var(--amber); }
  .val-red        { color: var(--red); }
  .panel-val-note { font-size: 11px; color: var(--muted); font-weight: 400;
                    display: block; margin-top: 2px; }

  .folder-row     { display: flex; justify-content: space-between; align-items: baseline;
                    padding: 4px 0; font-size: 12px; border-bottom: 1px solid var(--border); }
  .folder-row:last-child { border-bottom: none; }
  .folder-name    { color: var(--muted); font-family: 'Cascadia Code','Consolas',monospace;
                    font-size: 11px; }
  .folder-sz      { font-weight: 600; color: var(--text); }
  .folder-note    { font-size: 10px; color: var(--muted2); margin-left: 6px; }
  .no-detail-note { font-size: 12px; color: var(--muted); font-style: italic; padding: 6px 0; }

  .btn-copy-cmd   { margin-top: 1rem; width: 100%; padding: 8px 12px;
                    background: var(--blue-light); color: var(--blue-dark);
                    border: 1px solid var(--blue-border); border-radius: 6px;
                    font-size: 12px; font-weight: 600; cursor: pointer;
                    transition: background .12s; }
  .btn-copy-cmd:hover { background: var(--blue); color: #fff; }
  .btn-copy-cmd.copied { background: var(--green-light); color: var(--green);
                         border-color: var(--green-border); }

  /* ── States ──────────────────────────────────────────────── */
  .state-wrap     { display: flex; flex-direction: column; align-items: center;
                    justify-content: center; padding: 3rem; gap: 12px; color: var(--muted); }
  .state-wrap p   { font-size: 13px; text-align: center; max-width: 340px; line-height: 1.6; }
  .spinner        { width: 28px; height: 28px; border: 3px solid var(--border);
                    border-top-color: var(--blue); border-radius: 50%;
                    animation: spin .7s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .state-err      { color: var(--red); }

  .data-age-banner { padding: 8px 14px; border-radius: 6px; font-size: 12px;
                     margin-bottom: .75rem; display: none; }
  .age-stale      { background: var(--amber-light); color: var(--amber);
                    border: 1px solid var(--amber-border); }
  .age-expired    { background: var(--red-light); color: var(--red);
                    border: 1px solid var(--red-border); }

  .local-file-wrap { margin-top: 1rem; }
  .local-file-lbl  { font-size: 12px; color: var(--muted); margin-bottom: 6px; }
  .local-file-drop { border: 2px dashed var(--border); border-radius: 8px;
                     padding: 20px; text-align: center; cursor: pointer;
                     font-size: 13px; color: var(--muted);
                     transition: border-color .12s, background .12s; }
  .local-file-drop:hover { border-color: var(--blue-mid); background: var(--blue-light); }
  #localFileInput { display: none; }

  .empty-state    { padding: 2rem; text-align: center; color: var(--muted);
                    font-size: 13px; }
</style>
</head>
<body>

<div id="topbar">
  <div class="topbar-brand">
    <a href="../../" class="brand-hub-link">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
      <span class="brand-hub-text">IT Tools</span>
    </a>
    <span class="brand-separator">/</span>
    <span class="brand-tool">Exchange Audit</span>
    <span class="tool-beta-badge">Beta</span>
  </div>
</div>

<div class="audit-wrap">

  <!-- Data age banner (shown when JSON is stale) -->
  <div id="ageBanner" class="data-age-banner"></div>

  <!-- Summary strip -->
  <div class="audit-strip" id="auditStrip" style="display:none">
    <span class="strip-scan" id="scanMeta"></span>
    <span class="count-pill pill-total" id="pillTotal"></span>
    <span class="count-pill pill-critical" id="pillCritical" onclick="filterMode('critical')"></span>
    <span class="count-pill pill-warning"  id="pillWarning"  onclick="filterMode('warning')"></span>
    <input  type="text"   id="searchInput"  class="strip-search"  placeholder="Search name or UPN…" oninput="onSearch(this.value)">
    <select id="filterSel" class="strip-select" onchange="filterMode(this.value)">
      <option value="all">All mailboxes</option>
      <option value="critical">Critical only</option>
      <option value="warning">Warning +</option>
    </select>
    <select id="sortSel" class="strip-select" onchange="onSort(this.value)">
      <option value="pct-desc">Sort: Usage % ↓</option>
      <option value="pct-asc">Sort: Usage % ↑</option>
      <option value="name-asc">Sort: Name A–Z</option>
      <option value="gb-desc">Sort: GB ↓</option>
    </select>
  </div>

  <!-- Main layout: table + panel -->
  <div class="audit-layout" id="auditLayout" style="display:none">
    <div class="audit-table-wrap" id="tableWrap"></div>
    <div class="audit-panel"      id="sidePanel">
      <div class="panel-empty">Select a user to view details</div>
    </div>
  </div>

  <!-- Loading / error / local-file states -->
  <div id="stateArea"></div>

</div>

<script>
// ── Constants ──────────────────────────────────────────────────────────────
const AUDIT_BLOB_URL = ''; // TODO: set to Azure Blob URL when provisioned
const AGE_WARN_DAYS  = 8;
const AGE_ERR_DAYS   = 14;

// ── State ──────────────────────────────────────────────────────────────────
let auditData      = null;
let filteredList   = [];
let selectedUpn    = null;
let currentFilter  = 'all';
let currentSort    = 'pct-desc';
let searchQuery    = '';
</script>
</body>
</html>
```

- [ ] **Step 4: Verify page loads**

Open `tools/exchange-audit/index.html` in a browser (or via the dev server). Confirm:
- Topbar renders with "IT Tools / Exchange Audit" breadcrumb
- Page is blank (no data yet — expected)
- No console errors

- [ ] **Step 5: Commit**

```
git add tools/exchange-audit/index.html tools/exchange-audit/sample-data.json config.json
git commit -m "feat: exchange-audit scaffold — page skeleton, config entry, sample data"
```

---

### Task 2: Data layer — fetch, parse, age check, local file fallback

**Files:**
- Modify: `tools/exchange-audit/index.html` (add to `<script>` block)

- [ ] **Step 1: Add fetch + initialization logic**

Add the following to the `<script>` block in `index.html`, after the state variables:

```javascript
// ── Helpers ────────────────────────────────────────────────────────────────
function fmtBytes(bytes) {
  if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + ' GB';
  if (bytes >= 1048576)    return (bytes / 1048576).toFixed(1) + ' MB';
  return (bytes / 1024).toFixed(0) + ' KB';
}

function fmtCount(n) {
  return n >= 1000000 ? (n / 1000000).toFixed(1) + 'M' : n.toLocaleString();
}

function colorClass(pct) {
  return pct >= 90 ? 'red' : pct >= 70 ? 'amber' : 'green';
}

function dateDaysAgo(isoString) {
  return (Date.now() - new Date(isoString).getTime()) / 86400000;
}

// ── Loading / error states ─────────────────────────────────────────────────
function showLoading() {
  document.getElementById('stateArea').innerHTML = `
    <div class="state-wrap">
      <div class="spinner"></div>
      <p>Fetching audit data…</p>
    </div>`;
}

function showError(message, blobUrl) {
  document.getElementById('stateArea').innerHTML = `
    <div class="state-wrap">
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
      <p class="state-err">${message}</p>
      ${blobUrl ? `<p style="font-size:11px;font-family:monospace;word-break:break-all">${blobUrl}</p>` : ''}
      <div class="local-file-wrap">
        <p class="local-file-lbl">Load a local audit JSON file for testing:</p>
        <div class="local-file-drop" onclick="document.getElementById('localFileInput').click()">
          Click to browse or drop a JSON file here
        </div>
        <input type="file" id="localFileInput" accept=".json" onchange="loadLocalFile(this)">
      </div>
    </div>`;

  // Wire drag-and-drop on the drop zone
  const dropZone = document.querySelector('.local-file-drop');
  if (dropZone) {
    dropZone.addEventListener('dragover', e => { e.preventDefault(); dropZone.style.borderColor = 'var(--blue)'; });
    dropZone.addEventListener('dragleave', () => { dropZone.style.borderColor = ''; });
    dropZone.addEventListener('drop', e => {
      e.preventDefault();
      dropZone.style.borderColor = '';
      const file = e.dataTransfer.files[0];
      if (file) processLocalFile(file);
    });
  }
}

// ── Local file fallback ────────────────────────────────────────────────────
function loadLocalFile(input) {
  const file = input.files[0];
  if (file) processLocalFile(file);
}

async function processLocalFile(file) {
  try {
    const text = await Promise.race([
      file.text(),
      new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 10000))
    ]);
    const data = JSON.parse(text);
    onDataLoaded(data);
  } catch (e) {
    showError('Could not read or parse the JSON file: ' + e.message, null);
  }
}

// ── Data age banner ────────────────────────────────────────────────────────
function checkDataAge(lastScan) {
  const days = dateDaysAgo(lastScan);
  const banner = document.getElementById('ageBanner');
  if (days > AGE_ERR_DAYS) {
    banner.className = 'data-age-banner age-expired';
    banner.textContent = `Audit data is ${Math.floor(days)} days old — runbook may not have run recently. Data may be unreliable.`;
    banner.style.display = 'block';
  } else if (days > AGE_WARN_DAYS) {
    banner.className = 'data-age-banner age-stale';
    banner.textContent = `Audit data is ${Math.floor(days)} days old — next runbook cycle should refresh this soon.`;
    banner.style.display = 'block';
  }
}

// ── Entry point ────────────────────────────────────────────────────────────
function onDataLoaded(data) {
  auditData = data;
  document.getElementById('stateArea').innerHTML = '';
  document.getElementById('auditStrip').style.display = '';
  document.getElementById('auditLayout').style.display = '';
  checkDataAge(data.lastScan);
  applyFilters();
}

// ── Init ───────────────────────────────────────────────────────────────────
async function init() {
  if (!AUDIT_BLOB_URL) {
    showError('Azure Blob URL is not configured. Load a local JSON file to test.', null);
    return;
  }
  showLoading();
  try {
    const res = await fetch(AUDIT_BLOB_URL, { cache: 'no-cache' });
    if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`);
    const data = await res.json();
    onDataLoaded(data);
  } catch (e) {
    showError(
      'Could not load audit data. Check that the Azure Blob URL is reachable and CORS is enabled on the storage account.',
      AUDIT_BLOB_URL
    );
  }
}

document.addEventListener('DOMContentLoaded', init);
```

- [ ] **Step 2: Test local file fallback**

1. Open `tools/exchange-audit/index.html` in a browser
2. The error state renders (AUDIT_BLOB_URL is empty)
3. Use the file picker to load `tools/exchange-audit/sample-data.json`
4. Confirm: no console errors, `onDataLoaded` fires, strip and layout divs become visible (empty — rendering not added yet)

- [ ] **Step 3: Commit**

```
git add tools/exchange-audit/index.html
git commit -m "feat: exchange-audit data layer — fetch, age check, local file fallback"
```

---

### Task 3: Summary strip rendering

**Files:**
- Modify: `tools/exchange-audit/index.html` (add to `<script>` block)

- [ ] **Step 1: Add renderStrip()**

Add after `onDataLoaded` in the script block:

```javascript
function renderStrip(data, filtered) {
  const total    = data.mailboxes.length;
  const critical = data.mailboxes.filter(m => m.status === 'critical').length;
  const warning  = data.mailboxes.filter(m => m.status === 'warning').length;

  const daysAgo = dateDaysAgo(data.lastScan);
  const scanDate = new Date(data.lastScan).toLocaleDateString('en-US', { weekday:'short', month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' });
  const meta = document.getElementById('scanMeta');
  meta.innerHTML = `<strong>${data.totalMailboxes.toLocaleString()}</strong> mailboxes &nbsp;·&nbsp; Last scan: <strong>${scanDate}</strong>`;
  meta.className = 'strip-scan' + (daysAgo > AGE_ERR_DAYS ? ' expired' : daysAgo > AGE_WARN_DAYS ? ' stale' : '');

  document.getElementById('pillTotal').textContent    = `${total.toLocaleString()} total`;
  document.getElementById('pillCritical').textContent = `${critical} critical`;
  document.getElementById('pillWarning').textContent  = `${warning} warning`;
}
```

- [ ] **Step 2: Call renderStrip from applyFilters (stub)**

Add a stub `applyFilters()` function that calls `renderStrip` so the strip renders when data loads. Full filter logic comes in Task 6 — this is just enough to wire the strip:

```javascript
function applyFilters() {
  if (!auditData) return;
  // Full filtering/sorting in Task 6 — stub renders everything for now
  filteredList = auditData.mailboxes.slice();
  renderStrip(auditData, filteredList);
  renderTable(filteredList);
}
```

Add a stub `renderTable` so applyFilters doesn't throw:

```javascript
function renderTable(list) {
  // Implemented in Task 4
  document.getElementById('tableWrap').innerHTML = `<p style="padding:1rem;color:var(--muted);font-size:13px">${list.length} mailboxes (table coming in Task 4)</p>`;
}
```

- [ ] **Step 3: Verify strip renders**

Load sample-data.json via the file picker. Confirm:
- Scan date and mailbox count appear in the strip
- Critical and warning pills show correct counts from the sample data (1 critical without elcBlocked, 1 warning — check counts against sample-data.json)
- Pills are clickable (no filter logic yet — that's Task 6)

- [ ] **Step 4: Commit**

```
git add tools/exchange-audit/index.html
git commit -m "feat: exchange-audit summary strip — scan meta, count pills, search/filter/sort controls"
```

---

### Task 4: Mailbox table

**Files:**
- Modify: `tools/exchange-audit/index.html` (replace `renderTable` stub)

- [ ] **Step 1: Replace renderTable stub with full implementation**

Replace the stub `renderTable` function with:

```javascript
function renderTable(list) {
  const wrap = document.getElementById('tableWrap');
  if (list.length === 0) {
    wrap.innerHTML = '<div class="empty-state">No mailboxes match your filter.</div>';
    return;
  }

  const rows = list.map(m => {
    const pct   = m.recoverablePct;
    const fill  = colorClass(pct);
    const gb    = (m.recoverableUsedBytes / 1073741824).toFixed(1);
    const sel   = m.upn === selectedUpn ? ' row-sel' : '';
    const badge = m.status === 'critical'
      ? `<span class="status-badge badge-critical">Critical</span>`
      : m.status === 'warning'
      ? `<span class="status-badge badge-warning">Warning</span>`
      : '';
    const barW  = Math.min(pct, 100);

    return `<tr class="${sel}" onclick="selectMailbox('${m.upn}')">
      <td class="upn-cell">
        <div class="upn-name">${m.displayName}</div>
        <div class="upn-addr">${m.upn}</div>
      </td>
      <td style="white-space:nowrap">${gb} GB</td>
      <td style="min-width:140px">
        <div class="usage-bar-wrap">
          <div class="usage-bar"><div class="usage-fill fill-${fill}" style="width:${barW}%"></div></div>
          <span class="usage-pct pct-${fill}">${pct}%</span>
        </div>
      </td>
      <td>${badge}</td>
    </tr>`;
  }).join('');

  wrap.innerHTML = `
    <table class="audit-table">
      <thead>
        <tr>
          <th>Name / UPN</th>
          <th>GB Used</th>
          <th>Usage</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>`;
}
```

- [ ] **Step 2: Add selectMailbox stub**

Add after `renderTable`:

```javascript
function selectMailbox(upn) {
  selectedUpn = upn;
  renderTable(filteredList);   // re-render to update row highlight
  renderPanel(auditData.mailboxes.find(m => m.upn === upn));
}
```

Add a stub `renderPanel` so selectMailbox doesn't throw:

```javascript
function renderPanel(mailbox) {
  // Implemented in Task 5
  document.getElementById('sidePanel').innerHTML =
    `<div class="panel-body"><div class="panel-name">${mailbox.displayName}</div><p style="font-size:12px;color:var(--muted)">${mailbox.upn}</p></div>`;
}
```

- [ ] **Step 3: Verify table renders**

Load sample-data.json. Confirm:
- All 4 sample mailboxes appear in the table
- Usage bars color correctly: green for John Smith (20%), amber for Divyalakshmi (83%), red for hrconnect (120%) and blocked.elc (90%)
- Critical/Warning badges appear on the right rows
- Clicking a row highlights it and shows the name/UPN stub panel

- [ ] **Step 4: Commit**

```
git add tools/exchange-audit/index.html
git commit -m "feat: exchange-audit mailbox table — usage bars, status badges, row selection"
```

---

### Task 5: Side panel

**Files:**
- Modify: `tools/exchange-audit/index.html` (replace `renderPanel` stub)

- [ ] **Step 1: Replace renderPanel stub with full implementation**

Replace the stub `renderPanel` function with:

```javascript
function renderPanel(mailbox) {
  const panel = document.getElementById('sidePanel');
  const pct   = mailbox.recoverablePct;
  const fill  = colorClass(pct);
  const usedGb  = (mailbox.recoverableUsedBytes  / 1073741824).toFixed(2);
  const quotaGb = (mailbox.recoverableQuotaBytes / 1073741824).toFixed(0);
  const barW    = Math.min(pct, 100);

  // SIR row
  const sirHtml = mailbox.sirEnabled
    ? `<span class="panel-val val-green">Enabled</span>`
    : `<span class="panel-val val-amber">DISABLED</span>`;

  // MFA Processing row (ElcProcessingDisabled)
  const mfaHtml = mailbox.elcProcessingDisabled
    ? `<span class="panel-val val-red">BLOCKED
         <span class="panel-val-note">ElcProcessingDisabled is set — MFA will not reclaim space on this mailbox.<br>
         Fix: Set-Mailbox '${mailbox.upn}' -ElcProcessingDisabled $false</span>
       </span>`
    : `<span class="panel-val val-green">Allowed</span>`;

  // RetentionHold row
  const retHtml = mailbox.retentionHoldEnabled
    ? `<span class="panel-val val-amber">ENABLED <span class="panel-val-note">MFA skips this mailbox while active</span></span>`
    : `<span class="panel-val val-green">False</span>`;

  // Holds row
  let holdsText = 'None';
  const holdParts = [];
  if (mailbox.litigationHold)               holdParts.push('Litigation Hold');
  if (mailbox.delayHoldApplied)             holdParts.push('Delay Hold');
  if (mailbox.inPlaceHoldsCount > 0)        holdParts.push(`${mailbox.inPlaceHoldsCount} policy/eDiscovery hold(s)`);
  if (holdParts.length) holdsText = holdParts.join(', ');
  const holdsColor = holdParts.length ? 'val-amber' : 'val-green';

  // Folder breakdown
  let folderHtml = '';
  if (mailbox.hasDetailStats && mailbox.folders) {
    const f = mailbox.folders;
    const dhGb = (f.discoveryHoldsBytes / 1073741824).toFixed(2);
    const puGb = (f.purgesBytes         / 1073741824).toFixed(2);
    const veGb = (f.versionsBytes       / 1073741824).toFixed(2);
    const suGb = (f.substrateHoldsBytes / 1073741824).toFixed(2);

    const purgesNote = f.purgesItems > 0 ? `<span class="folder-note">(${fmtCount(f.purgesItems)} items — pending MFA)</span>` : '';
    const subNote    = f.substrateHoldsBytes > 0 ? `<span class="folder-note">(Teams/Skype)</span>` : '';
    const dhNote     = f.discoveryHoldsItems > 0 ? ` · ${fmtCount(f.discoveryHoldsItems)} items` : '';

    folderHtml = `
      <div class="panel-section">
        <div class="panel-sec-lbl">Folder Breakdown</div>
        <div class="folder-row">
          <span class="folder-name">/DiscoveryHolds</span>
          <span class="folder-sz">${dhGb} GB<span style="font-weight:400;color:var(--muted);font-size:11px">${dhNote}</span></span>
        </div>
        ${f.purgesBytes > 0 ? `<div class="folder-row">
          <span class="folder-name">/Purges</span>
          <span class="folder-sz">${puGb} GB${purgesNote}</span>
        </div>` : ''}
        ${f.versionsBytes > 0 ? `<div class="folder-row">
          <span class="folder-name">/Versions</span>
          <span class="folder-sz">${veGb} GB</span>
        </div>` : ''}
        ${f.substrateHoldsBytes > 0 ? `<div class="folder-row">
          <span class="folder-name">/SubstrateHolds</span>
          <span class="folder-sz">${suGb} GB${subNote}</span>
        </div>` : ''}
      </div>`;
  } else if (!mailbox.hasDetailStats) {
    folderHtml = `
      <div class="panel-section">
        <div class="panel-sec-lbl">Folder Breakdown</div>
        <p class="no-detail-note">Not available — below 80 GB deep-scan threshold</p>
      </div>`;
  }

  // Copy cleanup command button (warning + critical only)
  const copyBtnHtml = (mailbox.status === 'critical' || mailbox.status === 'warning')
    ? `<button class="btn-copy-cmd" id="copyBtn" onclick="copyCleanupCmd('${mailbox.upn}')">
         ⎘ Copy cleanup command
       </button>`
    : '';

  panel.innerHTML = `
    <div class="panel-body">
      <div class="panel-name">${mailbox.displayName}</div>
      <div class="panel-upn">${mailbox.upn}</div>

      <div class="panel-bar-wrap">
        <div style="display:flex;justify-content:space-between;font-size:13px">
          <span style="color:var(--muted)">Recoverable Items</span>
          <span style="font-weight:700;color:var(--pct-${fill})">${pct}%</span>
        </div>
        <div class="panel-bar"><div class="panel-fill fill-${fill}" style="width:${barW}%"></div></div>
        <div class="panel-quota"><span>${usedGb} GB used</span><span>${quotaGb} GB quota</span></div>
      </div>

      <div class="panel-section">
        <div class="panel-sec-lbl">Mailbox State</div>
        <div class="panel-row"><span class="panel-lbl">SIR</span>${sirHtml}</div>
        <div class="panel-row"><span class="panel-lbl">MFA Processing</span>${mfaHtml}</div>
        <div class="panel-row"><span class="panel-lbl">Retention Hold</span>${retHtml}</div>
        <div class="panel-row"><span class="panel-lbl">Holds active</span><span class="panel-val ${holdsColor}">${holdsText}</span></div>
      </div>

      ${folderHtml}
      ${copyBtnHtml}
    </div>`;
}

function copyCleanupCmd(upn) {
  navigator.clipboard.writeText(`.\\Invoke-MailboxCleanup.ps1 -Mailbox ${upn}`).then(() => {
    const btn = document.getElementById('copyBtn');
    if (!btn) return;
    btn.textContent = '✓ Copied!';
    btn.classList.add('copied');
    setTimeout(() => {
      btn.textContent = '⎘ Copy cleanup command';
      btn.classList.remove('copied');
    }, 2000);
  });
}
```

- [ ] **Step 2: Verify side panel**

Load sample-data.json. Click each row and confirm:
- **hrconnect** — red bar at 120%, SIR=DISABLED (amber), MFA Processing=Allowed (green), folder breakdown shows DiscoveryHolds 119.8 GB, copy button present
- **blocked.elc** — red bar at 90%, MFA Processing=BLOCKED (red) with inline fix command shown, copy button present
- **Divyalakshmi** — amber bar at 83%, SIR=Enabled, MFA Allowed, Purges row visible with item count, 1 policy hold shown
- **John Smith** — green bar at 20%, "Not available — below 80 GB" note, no copy button

- [ ] **Step 3: Commit**

```
git add tools/exchange-audit/index.html
git commit -m "feat: exchange-audit side panel — diagnostic view, MFA Processing, folder breakdown, copy command"
```

---

### Task 6: Interactivity — search, filter, sort

**Files:**
- Modify: `tools/exchange-audit/index.html` (replace `applyFilters` stub, add handlers)

- [ ] **Step 1: Replace applyFilters stub and add event handlers**

Replace the stub `applyFilters` and add all interactivity handlers:

```javascript
function applyFilters() {
  if (!auditData) return;

  let list = auditData.mailboxes.slice();

  // Search
  if (searchQuery) {
    const q = searchQuery.toLowerCase();
    list = list.filter(m =>
      m.displayName.toLowerCase().includes(q) ||
      m.upn.toLowerCase().includes(q)
    );
  }

  // Filter mode
  if (currentFilter === 'critical') {
    list = list.filter(m => m.status === 'critical');
  } else if (currentFilter === 'warning') {
    list = list.filter(m => m.status === 'critical' || m.status === 'warning');
  }

  // Sort
  list.sort((a, b) => {
    switch (currentSort) {
      case 'pct-desc': return b.recoverablePct - a.recoverablePct;
      case 'pct-asc':  return a.recoverablePct - b.recoverablePct;
      case 'name-asc': return a.displayName.localeCompare(b.displayName);
      case 'gb-desc':  return b.recoverableUsedBytes - a.recoverableUsedBytes;
      default:         return b.recoverablePct - a.recoverablePct;
    }
  });

  filteredList = list;
  renderStrip(auditData, filteredList);
  renderTable(filteredList);

  // If selected user was filtered out, clear the panel
  if (selectedUpn && !filteredList.find(m => m.upn === selectedUpn)) {
    selectedUpn = null;
    document.getElementById('sidePanel').innerHTML =
      '<div class="panel-empty">Select a user to view details</div>';
  }
}

function onSearch(value) {
  searchQuery = value.trim();
  applyFilters();
}

function filterMode(mode) {
  currentFilter = mode;
  // Sync the dropdown
  const sel = document.getElementById('filterSel');
  if (sel) sel.value = mode === 'critical' || mode === 'warning' ? mode : 'all';
  applyFilters();
}

function onSort(value) {
  currentSort = value;
  applyFilters();
}
```

- [ ] **Step 2: Verify interactivity**

Load sample-data.json. Test:
- Search "hr" → only hrconnect row shows
- Search "divya" → only Divyalakshmi shows
- Clear search → all rows return
- Click Critical pill → only critical rows shown, dropdown syncs to "Critical only"
- Click Warning pill → critical + warning rows shown
- Sort by Name A–Z → John Smith first
- If selected user is filtered out, side panel returns to "Select a user" empty state

- [ ] **Step 3: Commit**

```
git add tools/exchange-audit/index.html
git commit -m "feat: exchange-audit interactivity — search, filter, sort wired up"
```

---

### Task 7: Azure Automation Runbook

**Files:**
- Create: `tools/exchange-audit/Invoke-ExchangeAudit.ps1`

- [ ] **Step 1: Create the runbook**

Create `tools/exchange-audit/Invoke-ExchangeAudit.ps1`:

```powershell
<#
.SYNOPSIS
    Exchange Online Recoverable Items audit runbook for IT Tools Hub.
    Runs weekly via Azure Automation managed identity.
    Outputs exchange-audit.json to Azure Blob Storage.

.NOTES
    Requires:
      - Managed identity with Exchange Administrator role
      - Az.Accounts and Az.Storage modules in the Automation account
      - ExchangeOnlineManagement module in the Automation account
    Constants below must be set before first run.
#>

# ── Constants — set before deploying ──────────────────────────────────────
$STORAGE_ACCOUNT         = 'your-storage-account-name'   # e.g. ittools01stor
$CONTAINER_NAME          = 'it-tools'
$BLOB_NAME               = 'exchange-audit.json'
$DEEP_SCAN_THRESHOLD_GB  = 80    # Run Pass 2 only on mailboxes >= this value
$STATUS_CRITICAL_PCT     = 90    # Recoverable Items % threshold for "critical"
$STATUS_WARNING_PCT      = 70    # Recoverable Items % threshold for "warning"

# ── Helper: parse Exchange Online size strings to bytes ───────────────────
function ConvertTo-Bytes {
    param($Value)
    if ($null -eq $Value) { return [long]0 }
    if ($Value.GetType().Name -eq 'ByteQuantifiedSize') { return $Value.ToBytes() }
    if ($Value -is [string] -and $Value -match '\((\d[\d,]*)\s+bytes?\)') {
        return [long]($Matches[1] -replace ',', '')
    }
    try { return [long]$Value } catch { return [long]0 }
}

# ── Connect ────────────────────────────────────────────────────────────────
Write-Output "Connecting to Exchange Online via managed identity..."
try {
    Connect-ExchangeOnline -ManagedIdentity -ShowBanner:$false -ErrorAction Stop
    Write-Output "Exchange Online: connected"
} catch {
    throw "Failed to connect to Exchange Online: $_"
}

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-Output "Azure: connected via managed identity"
} catch {
    throw "Failed to connect to Azure: $_"
}

$runStart = Get-Date

# ── Pass 1: All mailboxes ─────────────────────────────────────────────────
Write-Output "Pass 1: fetching all user mailboxes..."
$allMailboxes = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Select-Object UserPrincipalName, DisplayName,
                  RecoverableItemsQuota, RecoverableItemsSize,
                  SingleItemRecoveryEnabled, ElcProcessingDisabled,
                  RetentionHoldEnabled, LitigationHoldEnabled,
                  DelayHoldApplied, InPlaceHolds

Write-Output "Pass 1 complete — $($allMailboxes.Count) mailboxes retrieved"

$mailboxObjects = [System.Collections.Generic.List[hashtable]]::new()

foreach ($mbx in $allMailboxes) {
    $usedBytes  = ConvertTo-Bytes $mbx.RecoverableItemsSize
    $quotaBytes = ConvertTo-Bytes $mbx.RecoverableItemsQuota

    $pct = if ($quotaBytes -gt 0) { [int][Math]::Round(($usedBytes / $quotaBytes) * 100) } else { 0 }

    $status = if     ($pct -ge $STATUS_CRITICAL_PCT) { 'critical' }
              elseif ($pct -ge $STATUS_WARNING_PCT)  { 'warning'  }
              else                                    { 'ok'       }

    $obj = @{
        upn                  = $mbx.UserPrincipalName
        displayName          = $mbx.DisplayName
        recoverableUsedBytes = $usedBytes
        recoverableQuotaBytes= $quotaBytes
        recoverablePct       = $pct
        status               = $status
        sirEnabled           = [bool]$mbx.SingleItemRecoveryEnabled
        elcProcessingDisabled= [bool]$mbx.ElcProcessingDisabled
        retentionHoldEnabled = [bool]$mbx.RetentionHoldEnabled
        litigationHold       = [bool]$mbx.LitigationHoldEnabled
        delayHoldApplied     = [bool]$mbx.DelayHoldApplied
        inPlaceHoldsCount    = if ($mbx.InPlaceHolds) { $mbx.InPlaceHolds.Count } else { 0 }
        hasDetailStats       = $false
    }

    $mailboxObjects.Add($obj)
}

# ── Pass 2: Deep scan for flagged mailboxes ────────────────────────────────
$flagged = $mailboxObjects | Where-Object { $_.recoverableUsedBytes -ge ($DEEP_SCAN_THRESHOLD_GB * 1GB) }
Write-Output "Pass 2: deep scan on $($flagged.Count) mailboxes >= ${DEEP_SCAN_THRESHOLD_GB} GB..."

foreach ($obj in $flagged) {
    try {
        $folders = Get-MailboxFolderStatistics -Identity $obj.upn -FolderScope RecoverableItems |
            Where-Object { $_.FolderPath -in @('/DiscoveryHolds', '/Purges', '/Versions', '/SubstrateHolds') }

        $dh = $folders | Where-Object { $_.FolderPath -eq '/DiscoveryHolds' }
        $pu = $folders | Where-Object { $_.FolderPath -eq '/Purges' }
        $ve = $folders | Where-Object { $_.FolderPath -eq '/Versions' }
        $su = $folders | Where-Object { $_.FolderPath -eq '/SubstrateHolds' }

        $obj.hasDetailStats = $true
        $obj.folders = @{
            discoveryHoldsBytes = if ($dh) { ConvertTo-Bytes $dh.FolderAndSubfolderSize } else { [long]0 }
            discoveryHoldsItems = if ($dh) { [int]$dh.ItemsInFolder } else { 0 }
            purgesBytes         = if ($pu) { ConvertTo-Bytes $pu.FolderAndSubfolderSize } else { [long]0 }
            purgesItems         = if ($pu) { [int]$pu.ItemsInFolder } else { 0 }
            versionsBytes       = if ($ve) { ConvertTo-Bytes $ve.FolderAndSubfolderSize } else { [long]0 }
            substrateHoldsBytes = if ($su) { ConvertTo-Bytes $su.FolderAndSubfolderSize } else { [long]0 }
        }
    } catch {
        Write-Warning "Pass 2 failed for $($obj.upn): $_"
    }
}

Write-Output "Pass 2 complete"

# ── Build output JSON ──────────────────────────────────────────────────────
$runDuration = [int]((Get-Date) - $runStart).TotalSeconds

$output = @{
    lastScan           = (Get-Date).ToUniversalTime().ToString('o')
    runDurationSeconds = $runDuration
    totalMailboxes     = $mailboxObjects.Count
    mailboxes          = @($mailboxObjects)
} | ConvertTo-Json -Depth 5 -Compress

Write-Output "JSON built — $($output.Length) bytes, $($mailboxObjects.Count) mailboxes"

# ── Upload to Azure Blob Storage ───────────────────────────────────────────
Write-Output "Uploading to Blob Storage: $STORAGE_ACCOUNT/$CONTAINER_NAME/$BLOB_NAME..."

try {
    $storageCtx = New-AzStorageContext -StorageAccountName $STORAGE_ACCOUNT -UseConnectedAccount

    $tempFile = [System.IO.Path]::GetTempFileName() + '.json'
    $output | Out-File $tempFile -Encoding UTF8 -NoNewline

    Set-AzStorageBlobContent -Container $CONTAINER_NAME `
        -Blob $BLOB_NAME `
        -File $tempFile `
        -Context $storageCtx `
        -Properties @{ ContentType = 'application/json' } `
        -Force | Out-Null

    Remove-Item $tempFile -Force
    Write-Output "Upload complete — exchange-audit.json updated in $CONTAINER_NAME"
} catch {
    throw "Blob upload failed: $_"
} finally {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Output "Exchange Audit runbook complete. Duration: ${runDuration}s"
```

- [ ] **Step 2: Verify runbook structure**

Review the script manually (can't run without Azure infra). Check:
- `$STORAGE_ACCOUNT` placeholder is clearly labelled with a comment
- Pass 1 captures all 9 fields including `elcProcessingDisabled`
- Pass 2 only runs on mailboxes ≥ 80 GB
- `folders` hashtable matches the JSON data model in the spec exactly (`discoveryHoldsBytes`, `discoveryHoldsItems`, `purgesBytes`, `purgesItems`, `versionsBytes`, `substrateHoldsBytes`)
- `ConvertTo-Bytes` handles both RPS `ByteQuantifiedSize` and REST string format
- `finally` block disconnects Exchange even if blob upload fails

- [ ] **Step 3: Commit**

```
git add tools/exchange-audit/Invoke-ExchangeAudit.ps1
git commit -m "feat: exchange-audit runbook — two-pass Exchange scan, blob upload, elcProcessingDisabled included"
```

---

### Task 8: Final wiring + deploy

**Files:**
- Modify: `tools/exchange-audit/index.html` (add responsive behaviour, final polish)
- Modify: `config.json` (verify entry is correct)

- [ ] **Step 1: End-to-end test with sample data**

Load `sample-data.json` via the file picker. Run through the full checklist:

- [ ] Summary strip shows correct total (4), critical (2), warning (1) counts
- [ ] Table rows sorted by usage % descending by default (hrconnect 120% first)
- [ ] hrconnect row: red bar, CRITICAL badge, click → side panel shows DISABLED SIR, Allowed MFA, DiscoveryHolds 119.8 GB, copy button
- [ ] blocked.elc row: red bar, CRITICAL badge, click → side panel shows **BLOCKED** MFA Processing in red with fix command
- [ ] Divyalakshmi row: amber bar, WARNING badge, 1 policy hold shown, Purges row visible
- [ ] John Smith row: green bar, no badge, side panel shows "below 80 GB" folder note, no copy button
- [ ] Search "blocked" → only blocked.elc row, clear → all rows back
- [ ] Click Critical pill → only 2 critical rows; click Warning pill → 3 rows; click total or select All → all 4
- [ ] Sort by Name A–Z → Blocked ELC User first
- [ ] Copy button on hrconnect copies `.\Invoke-MailboxCleanup.ps1 -Mailbox hrconnect@corrohealth.com` — verify in clipboard, button flashes green

- [ ] **Step 2: Push testing branch and verify on preview**

```
git push
```

Navigate to the preview hub URL, sign in, and confirm the Exchange Audit card appears in the hub (reportingOnly gate will show it locked to non-IT users).

- [ ] **Step 3: Merge to main (live)**

Only when preview confirms the card renders correctly and the tool loads cleanly:

```
git checkout main
git merge testing
git push
git checkout testing
```

- [ ] **Step 4: Update downloads.json version / Obsidian note if applicable**

Exchange Audit is a hub tool (not a downloads script), so no `downloads.json` change needed. Update `C:\dev\notes\Projects\IT Tools Hub\Tools\Exchange Audit.md` status line from "design phase" to "built — pending Azure infra for live data."

---

## Self-Review Against Spec

| Spec requirement | Covered in |
|-----------------|-----------|
| Azure Automation runbook, weekly Monday 02:00 | Task 7 (script created; schedule set in Azure portal, not in code) |
| Pass 1: all mailboxes with all 9 fields incl. `ElcProcessingDisabled` | Task 7 |
| Pass 2: ≥80 GB only, folder breakdown | Task 7 |
| Status thresholds baked server-side (critical/warning/ok) | Task 7 |
| JSON blob output, `lastScan`, `runDurationSeconds`, `totalMailboxes` | Task 7 |
| Hub page fetches blob, BLOB_URL constant | Task 2 |
| Data age warning >8 days, error banner >14 days | Task 2 |
| Local file fallback (file picker) | Task 2 |
| Summary strip: total, critical pill, warning pill, search, filter, sort | Task 3 + Task 6 |
| Table: name/UPN, GB, usage bar, status badge, click to select | Task 4 |
| Side panel: quota, SIR, MFA Processing (ElcProcessingDisabled), RetentionHold, holds, folder breakdown | Task 5 |
| Copy cleanup command (warning + critical only) | Task 5 |
| `hasDetailStats: false` shows "below 80 GB threshold" note | Task 5 |
| `reportingOnly: true` config gate | Task 1 |
| Fetch failure: error state with blob URL shown | Task 2 |
| Uses existing `shared/styles.css` CSS vars | Task 1 |

No gaps found.
