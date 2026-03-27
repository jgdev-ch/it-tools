# Guest Access Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `tools/guest-audit/index.html` — a single-page tool that audits B2B guest accounts in the M365 tenant, showing risk signals, group memberships, and allowing disable/delete actions.

**Architecture:** Session consumer — no sign-in UI; inherits hub MSAL session from localStorage via `ITTools.auth.init()`, redirects to `../../` if no session found. All data fetched from Microsoft Graph. Group memberships fetched lazily per guest when the modal opens.

**Tech Stack:** Vanilla JS, shared/auth.js (ITTools.graph, ITTools.auth, ITTools.ui, ITTools.csv, ITTools.theme), shared/styles.css, shared/msal-browser.min.js, Microsoft Graph v1.0

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `tools/guest-audit/index.html` | Create | Entire tool: HTML structure, CSS, JS |
| `config.json` | Modify | Change guest-audit `status` from `"coming-soon"` to `"beta"`, add `"path": "tools/guest-audit/"` |

---

## Task 1: Scaffold — HTML shell, auth init, session consumer

**Files:**
- Create: `tools/guest-audit/index.html`

- [ ] **Step 1: Create the file with boilerplate, auth init, and redirect logic**

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Guest Access Audit — IT Tools</title>
<script src="../../shared/msal-browser.min.js"></script>
<link rel="stylesheet" href="../../shared/styles.css"/>
<style>
  .shell { max-width: 1060px; margin: 0 auto; padding: 1.75rem 1.25rem; }
  .page-header { margin-bottom: 1.5rem; }
  .page-header h1 { font-size: 22px; font-weight: 700; margin-bottom: 4px; }
  .page-header p  { font-size: 13px; color: var(--muted); }
</style>
</head>
<body>

<div id="topbar"></div>

<div id="appScreen" style="display:none">
  <div class="shell">
    <div class="page-header">
      <h1>Guest Access Audit</h1>
      <p>Identify stale B2B guest accounts — review last sign-in, group memberships, and license exposure.</p>
    </div>

    <div class="banner error" id="errBanner" style="display:none"></div>

    <div id="tableSection"></div>
  </div>
</div>

<script src="../../shared/auth.js"></script>
<script>
const TOOL_SCOPES = ["User.Read.All", "Directory.Read.All", "AuditLog.Read.All"];

async function init() {
  ITTools.theme.init();
  ITTools.ui.renderTopbar({ toolName: "Guest Access Audit", hubRelPath: "../../" });
  ITTools.ui.syncThemeIcon();

  let _sessionFound = false;
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: acct => {
      _sessionFound = true;
      document.getElementById("appScreen").style.display = "block";
      ITTools.ui.setUser(acct);
    },
    onSignOut: () => { window.location.href = "../../"; }
  });
  if (!_sessionFound) { window.location.href = "../../"; }
}

init();
</script>
</body>
</html>
```

- [ ] **Step 2: Open in browser (or preview), sign into hub first, then navigate to `tools/guest-audit/`**

Expected: topbar renders with "Guest Access Audit" title, no auth screen, no redirect loop.

- [ ] **Step 3: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat: scaffold guest-audit tool with session consumer auth"
```

---

## Task 2: Configure card and scan state

**Files:**
- Modify: `tools/guest-audit/index.html`

- [ ] **Step 1: Add CSS for controls and phase line (inside the `<style>` block)**

```css
  /* ── Controls ── */
  .controls-row { display:flex; flex-wrap:wrap; gap:12px; align-items:flex-end; }
  .controls-row .field { flex:1 1 180px; margin-bottom:0; }

  /* ── Cancel button ── */
  .btn-cancel {
    padding: 9px 20px; border-radius: var(--radius-sm);
    background: transparent; color: var(--red); border: 1.5px solid var(--red-border);
    font-size: 14px; font-weight: 600; cursor: pointer; font-family: inherit;
    transition: all .12s; display: none; align-items: center; gap: 6px;
  }
  .btn-cancel:hover { background: var(--red-light); }
  .btn-cancel.show  { display: inline-flex; }
```

- [ ] **Step 2: Add configure card HTML (replace the `<div id="tableSection"></div>` placeholder with this block above it)**

```html
    <!-- Configure -->
    <div class="card">
      <div class="card-title">Configure scan</div>
      <div class="controls-row">
        <div class="field">
          <label class="field-label">Stale threshold</label>
          <select id="staleSelect">
            <option value="30">30 days</option>
            <option value="60">60 days</option>
            <option value="90" selected>90 days</option>
            <option value="180">180 days</option>
            <option value="365">365 days</option>
          </select>
        </div>
        <div class="field">
          <label class="field-label">Department filter</label>
          <input type="text" id="deptFilter" placeholder="Leave blank for all"/>
        </div>
        <button class="btn btn-primary" id="scanBtn" onclick="startScan()">Run Scan</button>
        <button class="btn-cancel" id="cancelBtn" onclick="cancelScan()">✕ Cancel</button>
      </div>
      <div class="phase-line" id="phaseLine"><div class="spinner"></div><span id="phaseText"></span></div>
    </div>

    <!-- Stats (shown after scan) -->
    <div class="stats-row" id="statsRow" style="display:none"></div>
```

- [ ] **Step 3: Add scan state JS and setPhase/cancelScan (inside `<script>`, after `init()`)**

```js
// ── State ─────────────────────────────────────────────────────────────────────
let allGuests  = [];
let sortCol    = "daysInactive";
let sortDir    = -1;
let _cancelled = false;

// ── Phase UI ──────────────────────────────────────────────────────────────────
function setPhase(msg) {
  const line   = document.getElementById("phaseLine");
  const btn    = document.getElementById("scanBtn");
  const cancel = document.getElementById("cancelBtn");
  if (msg) {
    line.classList.add("show");
    document.getElementById("phaseText").textContent = msg;
    btn.disabled    = true;
    btn.textContent = "Scanning…";
    cancel.classList.add("show");
  } else {
    line.classList.remove("show");
    btn.disabled    = false;
    btn.textContent = "Run Scan";
    cancel.classList.remove("show");
  }
}

function cancelScan() {
  _cancelled = true;
  setPhase(null);
  const b = document.getElementById("errBanner");
  b.textContent   = "⚠ Scan cancelled — partial results shown below.";
  b.className     = "banner warn";
  b.style.display = "block";
}

async function startScan() {
  document.getElementById("errBanner").style.display = "none";
  document.getElementById("statsRow").style.display  = "none";
  document.getElementById("tableSection").innerHTML  = "";
  allGuests  = [];
  _cancelled = false;
  setPhase("Fetching guest accounts…");
  try {
    await runScan();
  } catch(e) {
    const banner = document.getElementById("errBanner");
    if (e.message && e.message.includes("403")) {
      banner.textContent = "Permission denied — check Graph API consents in your Entra app registration (User.Read.All, Directory.Read.All, AuditLog.Read.All).";
    } else {
      banner.textContent = e.message || "An unexpected error occurred.";
    }
    banner.className     = "banner error";
    banner.style.display = "block";
    setPhase(null);
  }
}

async function runScan() {
  // Placeholder — implemented in Task 3
  setPhase(null);
}
```

- [ ] **Step 4: Verify in browser — "Run Scan" disables during scan and re-enables, Cancel appears, no JS errors**

- [ ] **Step 5: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat: add configure card and scan state to guest-audit"
```

---

## Task 3: Graph fetch with retry and pagination

**Files:**
- Modify: `tools/guest-audit/index.html`

- [ ] **Step 1: Add `graphWithRetry` and `countdownEta` helpers (add before `startScan`)**

```js
// ── Graph retry ────────────────────────────────────────────────────────────────
async function graphWithRetry(fn, maxRetries = 5) {
  let attempt = 0;
  while (true) {
    try { return await fn(); }
    catch(e) {
      attempt++;
      const isRateLimit = e.message && (
        e.message.includes("429") || e.message.includes("Rate limited") ||
        e.message.includes("Too Many Requests") || e.message.includes("503")
      );
      if (!isRateLimit || attempt > maxRetries) throw e;
      const waitSec = Math.min(60, Math.pow(2, attempt));
      setPhase(`Rate limited — retrying in ${waitSec}s…`);
      await countdownEta(waitSec);
    }
  }
}

async function countdownEta(seconds) {
  const line = document.getElementById("phaseText");
  for (let s = seconds; s > 0; s--) {
    if (line) line.textContent = `Rate limited — resuming in ${s}s…`;
    await new Promise(r => setTimeout(r, 1000));
  }
}
```

- [ ] **Step 2: Replace the `runScan` placeholder with the real fetch**

```js
async function runScan() {
  const threshold = parseInt(document.getElementById("staleSelect").value, 10);
  const dept      = document.getElementById("deptFilter").value.trim();

  // Build URL — filter server-side by userType eq 'Guest'
  let url = "https://graph.microsoft.com/v1.0/users"
    + "?$filter=userType eq 'Guest'"
    + "&$select=id,displayName,userPrincipalName,companyName,department,"
    + "accountEnabled,assignedLicenses,signInActivity,createdDateTime"
    + "&$top=999&$count=true";

  if (dept) {
    url = "https://graph.microsoft.com/v1.0/users"
      + `?$filter=userType eq 'Guest' and department eq '${dept.replace(/'/g, "''")}'`
      + "&$select=id,displayName,userPrincipalName,companyName,department,"
      + "accountEnabled,assignedLicenses,signInActivity,createdDateTime"
      + "&$top=999&$count=true";
  }

  let guests;
  try {
    guests = await graphWithRetry(() => ITTools.graph.getAll(url));
  } catch(fetchErr) {
    // Fallback: fetch without server-side filter, filter client-side
    setPhase("Fallback: fetching all users and filtering client-side…");
    const all = await graphWithRetry(() =>
      ITTools.graph.getAll(
        "https://graph.microsoft.com/v1.0/users"
        + "?$select=id,displayName,userPrincipalName,companyName,department,"
        + "accountEnabled,assignedLicenses,signInActivity,createdDateTime&$top=999"
      )
    );
    guests = all.filter(u => u.userType === "Guest");
    if (dept) guests = guests.filter(u => (u.department||"").toLowerCase().includes(dept.toLowerCase()));
  }

  if (!guests.length) {
    const b = document.getElementById("errBanner");
    b.textContent   = "No guest accounts found in your tenant.";
    b.className     = "banner info";
    b.style.display = "block";
    setPhase(null);
    return;
  }

  const now = Date.now();
  allGuests = guests.map(u => {
    const lastSignIn = u.signInActivity?.lastSignInDateTime || null;
    const created    = u.createdDateTime || null;
    let daysInactive = null;
    if (lastSignIn) {
      daysInactive = Math.floor((now - new Date(lastSignIn).getTime()) / 86400000);
    }
    const createdDaysAgo = created
      ? Math.floor((now - new Date(created).getTime()) / 86400000)
      : null;

    const isNever       = lastSignIn === null;
    const isStale       = daysInactive !== null && daysInactive > threshold;
    const isLicensed    = (u.assignedLicenses || []).length > 0;
    const isOldInvite   = isNever && createdDaysAgo !== null && createdDaysAgo > 365;

    return {
      id:            u.id,
      displayName:   u.displayName || "",
      upn:           u.userPrincipalName || "",
      companyName:   u.companyName || "",
      department:    u.department || "",
      accountEnabled: u.accountEnabled !== false,
      licenseCount:  (u.assignedLicenses || []).length,
      lastSignIn,
      daysInactive,
      created,
      createdDaysAgo,
      isNever,
      isStale,
      isLicensed,
      isOldInvite,
      threshold,
    };
  });

  renderStats(allGuests, threshold);
  renderTable(allGuests);
  setPhase(null);
}
```

- [ ] **Step 3: Add stub `renderStats` and `renderTable` functions (implement fully in Tasks 4 and 5)**

```js
function renderStats(guests, threshold) {
  // stub — implemented in Task 4
}

function renderTable(guests) {
  // stub — implemented in Task 5
  document.getElementById("tableSection").innerHTML =
    `<div class="card"><p style="padding:1rem;color:var(--muted)">${guests.length} guests fetched — table coming soon.</p></div>`;
}
```

- [ ] **Step 4: Test: click "Run Scan" — should see phase message appear, data fetch from Graph, stub table card showing guest count**

- [ ] **Step 5: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat: add Graph fetch with retry and pagination to guest-audit"
```

---

## Task 4: Stats row

**Files:**
- Modify: `tools/guest-audit/index.html`

- [ ] **Step 1: Replace `renderStats` stub with the real implementation**

```js
function sc(color, label, value, sub) {
  return `<div class="stat ${color}"><div class="stat-label">${label}</div><div class="stat-value">${value}</div>${sub ? `<div class="stat-sub">${sub}</div>` : ""}</div>`;
}

function renderStats(guests, threshold) {
  const total    = guests.length;
  const never    = guests.filter(g => g.isNever).length;
  const stale    = guests.filter(g => g.isStale).length;
  const licensed = guests.filter(g => g.isLicensed).length;

  const row = document.getElementById("statsRow");
  row.innerHTML =
    sc("gray",  "Total Guests",    total,    null) +
    sc("red",   "Never Signed In", never,    never > 0 ? "null signInActivity" : "none found") +
    sc("amber", "Stale Accounts",  stale,    `inactive >${threshold}d`) +
    sc("blue",  "Licensed Guests", licensed, licensed > 0 ? "review exposure" : "no licenses");
  row.style.display = "flex";
}
```

- [ ] **Step 2: Verify stats row appears after scan with correct counts**

Expected: four stat cards in gray/red/amber/blue appear below the configure card.

- [ ] **Step 3: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat: add stats row to guest-audit"
```

---

## Task 5: Results table with sort and search

**Files:**
- Modify: `tools/guest-audit/index.html`

- [ ] **Step 1: Add table CSS (inside `<style>` block)**

```css
  /* ── Guest cell ── */
  .user-cell  { display:flex; align-items:center; gap:10px; }
  .avatar     { width:30px; height:30px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:11px; font-weight:700; flex-shrink:0; }
  .avatar.never { background:var(--red-light);   color:var(--red); }
  .avatar.stale { background:var(--amber-light); color:var(--amber); }
  .avatar.ok    { background:var(--blue-light);  color:var(--blue-dark); }
  .user-name { font-size:13px; font-weight:600; }
  .user-upn  { font-size:11px; color:var(--muted); }

  /* ── Age badge ── */
  .age-never    { background:var(--red-light);   color:var(--red);   border-radius:4px; padding:2px 8px; font-size:12px; font-weight:600; }
  .age-critical { background:var(--red-light);   color:var(--red);   border-radius:4px; padding:2px 8px; font-size:12px; font-weight:600; }
  .age-warning  { background:var(--amber-light); color:var(--amber); border-radius:4px; padding:2px 8px; font-size:12px; font-weight:600; }
  .age-ok       { background:var(--green-light); color:var(--green); border-radius:4px; padding:2px 8px; font-size:12px; font-weight:600; }

  /* ── Account status pills ── */
  .pill-active   { display:inline-block; background:var(--green-light); color:var(--green); border-radius:20px; padding:2px 10px; font-size:11px; font-weight:700; }
  .pill-disabled { display:inline-block; background:var(--red-light);   color:var(--red);   border-radius:20px; padding:2px 10px; font-size:11px; font-weight:700; }

  /* ── Risk badges ── */
  .risk-badge {
    display:inline-flex; align-items:center; gap:3px;
    padding:2px 7px; border-radius:20px; font-size:10px; font-weight:700;
    margin:1px; white-space:nowrap;
  }
  .risk-never    { background:var(--red-light);   color:var(--red); }
  .risk-stale    { background:var(--amber-light);  color:var(--amber); }
  .risk-licensed { background:var(--blue-light);   color:var(--blue-dark); }
  .risk-old-invite { background:var(--surface3);   color:var(--muted); border:1px solid var(--border); }

  /* ── Action buttons ── */
  .btn-action {
    padding: 4px 10px; border-radius: var(--radius-sm);
    background: transparent; font-size: 11px; font-weight: 600;
    cursor: pointer; font-family: inherit; transition: all .12s; white-space: nowrap;
  }
  .btn-disable {
    border: 1px solid var(--amber-border); color: var(--amber);
  }
  .btn-disable:hover { background: var(--amber-light); }
  .btn-disable:disabled { opacity: .4; cursor: not-allowed; }
  .btn-enable {
    border: 1px solid var(--green-border); color: var(--green);
  }
  .btn-enable:hover { background: var(--green-light); }
  .btn-enable:disabled { opacity: .4; cursor: not-allowed; }
  .btn-delete {
    border: 1px solid var(--red-border); color: var(--red);
  }
  .btn-delete:hover { background: var(--red-light); }
  .btn-delete:disabled { opacity: .4; cursor: not-allowed; }

  /* ── Groups button ── */
  .btn-groups {
    padding: 3px 10px; border-radius: var(--radius-sm);
    background: var(--surface2); border: 1px solid var(--border);
    font-size: 11px; font-weight: 600; cursor: pointer; font-family: inherit;
    transition: all .12s;
  }
  .btn-groups:hover { background: var(--surface3); }

  /* ── Inline row error ── */
  .row-error { font-size:11px; color:var(--red); margin-top:3px; }
```

- [ ] **Step 2: Add sort helper and table toolbar/search to the JS**

```js
function sortGuests(guests) {
  return [...guests].sort((a, b) => {
    if (sortCol === "daysInactive") {
      const av = a.isNever ? Infinity : (a.daysInactive ?? -1);
      const bv = b.isNever ? Infinity : (b.daysInactive ?? -1);
      return sortDir * (bv - av);
    }
    if (sortCol === "licenseCount") return sortDir * (b.licenseCount - a.licenseCount);
    if (sortCol === "accountEnabled") return sortDir * ((a.accountEnabled ? 1 : 0) - (b.accountEnabled ? 1 : 0));
    const av = a[sortCol] || "", bv = b[sortCol] || "";
    return sortDir * av.toString().toLowerCase().localeCompare(bv.toString().toLowerCase());
  });
}

function thSortIcon(col) {
  if (col !== sortCol) return "";
  return sortDir === 1 ? " ▲" : " ▼";
}

function filterGuestTbl(q) {
  q = q.toLowerCase();
  document.querySelectorAll("#guestBody tr").forEach(tr => {
    tr.style.display = tr.dataset.search.includes(q) ? "" : "none";
  });
}
```

- [ ] **Step 3: Replace `renderTable` stub with the full implementation**

```js
function ageBadge(g) {
  if (g.isNever) return `<span class="age-never">Never</span>`;
  const d = g.daysInactive;
  if (d > g.threshold) return `<span class="age-critical">${d}d</span>`;
  if (d > 30)          return `<span class="age-warning">${d}d</span>`;
  return `<span class="age-ok">${d}d</span>`;
}

function riskBadges(g) {
  let html = "";
  if (g.isNever)     html += `<span class="risk-badge risk-never">Never signed in</span>`;
  if (g.isStale)     html += `<span class="risk-badge risk-stale">Stale</span>`;
  if (g.isLicensed)  html += `<span class="risk-badge risk-licensed">Licensed</span>`;
  if (g.isOldInvite) html += `<span class="risk-badge risk-old-invite">Old invite</span>`;
  return html;
}

function avatarClass(g) {
  if (g.isNever) return "never";
  if (g.isStale) return "stale";
  return "ok";
}

function initials(name) {
  return name.split(" ").filter(Boolean).slice(0, 2).map(w => w[0]).join("").toUpperCase() || "?";
}

function fmtDate(iso) {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric" });
}

function renderTable(guests) {
  const sec = document.getElementById("tableSection");

  if (!guests.length) {
    sec.innerHTML = `<div class="card"><div class="empty-state">
      <div class="empty-icon">👥</div>
      <div class="empty-title">No guest accounts found</div>
      <div class="empty-sub">No guest accounts found in your tenant.</div>
    </div></div>`;
    return;
  }

  const sorted = sortGuests(guests);

  function thBtn(col, label) {
    return `<th class="sortable${col === sortCol ? " sorted" : ""}" onclick="setSortCol('${col}')">${label}${thSortIcon(col)}</th>`;
  }

  const rows = sorted.map(g => {
    const search = [g.displayName, g.upn, g.companyName, g.department].join(" ").toLowerCase();
    const disabledBtns = g.accountEnabled
      ? `<button class="btn-action btn-disable" id="dis-${g.id}" onclick="promptDisable('${g.id}')">Disable</button>`
      : `<button class="btn-action btn-enable"  id="ena-${g.id}" onclick="promptEnable('${g.id}')">Enable</button>`;
    return `
    <tr data-id="${g.id}" data-search="${search}">
      <td>
        <div class="user-cell">
          <div class="avatar ${avatarClass(g)}">${initials(g.displayName)}</div>
          <div>
            <div class="user-name">${g.displayName || "(no name)"}</div>
            <div class="user-upn">${g.upn}</div>
            ${riskBadges(g)}
          </div>
        </div>
      </td>
      <td>${g.companyName ? g.companyName : `<span style="color:var(--muted2)">—</span>`}</td>
      <td>${g.isNever ? `<span style="color:var(--muted2)">Never</span>` : fmtDate(g.lastSignIn)}</td>
      <td>${ageBadge(g)}</td>
      <td>${fmtDate(g.created)}</td>
      <td><button class="btn-groups" onclick="openGroupModal('${g.id}','${g.displayName.replace(/'/g,"\\'")}')">View</button></td>
      <td>${g.licenseCount > 0 ? `<span class="pill-active" style="background:var(--blue-light);color:var(--blue-dark)">${g.licenseCount}</span>` : `<span style="color:var(--muted2)">None</span>`}</td>
      <td id="acct-${g.id}">${g.accountEnabled ? `<span class="pill-active">Active</span>` : `<span class="pill-disabled">Disabled</span>`}</td>
      <td>
        <div style="display:flex;gap:6px;flex-wrap:wrap">
          ${disabledBtns}
          <button class="btn-action btn-delete" id="del-${g.id}" onclick="promptDelete('${g.id}')">Delete</button>
        </div>
        <div class="row-error" id="err-${g.id}"></div>
      </td>
    </tr>`;
  }).join("");

  sec.innerHTML = `
  <div class="card" style="padding:0;overflow:hidden">
    <div style="display:flex;align-items:center;justify-content:space-between;padding:1rem 1.25rem;border-bottom:1px solid var(--border);flex-wrap:wrap;gap:10px">
      <div class="card-title" style="margin-bottom:0">
        ${guests.length} guest account${guests.length !== 1 ? "s" : ""}
      </div>
      <div style="display:flex;gap:8px;align-items:center">
        <input type="search" placeholder="Filter by name, email, company…" style="padding:6px 10px;border-radius:var(--radius-sm);border:1px solid var(--border);background:var(--surface2);color:inherit;font-size:13px;width:220px" oninput="filterGuestTbl(this.value)"/>
        <button class="btn btn-ghost" style="padding:7px 14px;font-size:12px" onclick="exportCsv()">Export CSV</button>
      </div>
    </div>
    <div style="overflow-x:auto">
      <table>
        <thead>
          <tr>
            ${thBtn("displayName","Guest")}
            ${thBtn("companyName","Company")}
            ${thBtn("lastSignIn","Last Sign-In")}
            ${thBtn("daysInactive","Days Inactive")}
            ${thBtn("created","Created")}
            <th>Groups</th>
            ${thBtn("licenseCount","Licenses")}
            ${thBtn("accountEnabled","Account")}
            <th>Actions</th>
          </tr>
        </thead>
        <tbody id="guestBody">${rows}</tbody>
      </table>
    </div>
  </div>`;
}

function setSortCol(col) {
  if (sortCol === col) sortDir *= -1;
  else { sortCol = col; sortDir = -1; }
  renderTable(allGuests);
  filterGuestTbl(document.querySelector('input[type="search"]')?.value || "");
}
```

- [ ] **Step 4: Add `exportCsv` stub (full impl in Task 8)**

```js
function exportCsv() {
  // stub — implemented in Task 8
}
```

- [ ] **Step 5: Test: run scan, verify table renders with all columns, sort headers work (click to sort asc/desc), search filters rows**

- [ ] **Step 6: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat: add sortable results table to guest-audit"
```

---

## Task 6: Group membership modal

**Files:**
- Modify: `tools/guest-audit/index.html`

- [ ] **Step 1: Add modal CSS (inside `<style>` block)**

```css
  /* ── Group modal ── */
  .modal-overlay {
    position: fixed; inset: 0; background: rgba(0,0,0,.55);
    display: flex; align-items: center; justify-content: center;
    z-index: 1000; padding: 1rem;
    opacity: 0; pointer-events: none; transition: opacity .15s;
  }
  .modal-overlay.show { opacity: 1; pointer-events: all; }
  .modal-card {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 14px; padding: 2rem; max-width: 480px; width: 100%;
    box-shadow: 0 20px 60px rgba(0,0,0,.25);
    transform: translateY(10px); transition: transform .15s;
    max-height: 80vh; display: flex; flex-direction: column;
  }
  .modal-overlay.show .modal-card { transform: translateY(0); }
  .modal-title { font-size: 17px; font-weight: 700; margin-bottom: 4px; }
  .modal-sub   { font-size: 12px; color: var(--muted); margin-bottom: 1rem; }
  .modal-body  { flex: 1; overflow-y: auto; }
  .modal-actions { display:flex; justify-content:flex-end; margin-top:1.25rem; }
  .btn-modal-cancel {
    padding: 9px 20px; border-radius: var(--radius-sm);
    background: transparent; border: 1px solid var(--border);
    font-size: 14px; font-weight: 600; cursor: pointer;
    font-family: inherit; color: var(--muted); transition: all .12s;
  }
  .btn-modal-cancel:hover { background: var(--surface2); }
  .group-list { list-style: none; padding: 0; margin: 0; }
  .group-item {
    padding: 8px 10px; border-radius: var(--radius-sm);
    font-size: 13px; border-bottom: 1px solid var(--border);
  }
  .group-item:last-child { border-bottom: none; }
```

- [ ] **Step 2: Add modal HTML (inside `#appScreen`, before `</div>` closing the shell — after tableSection)**

```html
<!-- Group modal -->
<div class="modal-overlay" id="groupModal">
  <div class="modal-card">
    <div class="modal-title" id="groupModalTitle"></div>
    <div class="modal-sub">Group memberships</div>
    <div class="modal-body" id="groupModalBody"></div>
    <div class="modal-actions">
      <button class="btn-modal-cancel" onclick="closeGroupModal()">Close</button>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Add modal JS**

```js
function closeGroupModal() {
  document.getElementById("groupModal").classList.remove("show");
}

async function openGroupModal(userId, displayName) {
  const modal = document.getElementById("groupModal");
  const title = document.getElementById("groupModalTitle");
  const body  = document.getElementById("groupModalBody");

  title.textContent = displayName;
  body.innerHTML    = `<div style="display:flex;align-items:center;gap:8px;padding:1rem 0"><div class="spinner"></div><span style="font-size:13px;color:var(--muted)">Loading groups…</span></div>`;
  modal.classList.add("show");

  try {
    const data = await graphWithRetry(() =>
      ITTools.graph.getAll(
        `https://graph.microsoft.com/v1.0/users/${userId}/memberOf?$select=id,displayName`
      )
    );
    if (!data.length) {
      body.innerHTML = `<p style="font-size:13px;color:var(--muted);padding:0.5rem 0">Not a member of any groups.</p>`;
      return;
    }
    body.innerHTML = `<ul class="group-list">${data.map(g =>
      `<li class="group-item">${g.displayName || g.id}</li>`
    ).join("")}</ul>`;
  } catch(e) {
    body.innerHTML = `<p style="font-size:13px;color:var(--red);padding:0.5rem 0">Could not load groups — ${e.message}</p>`;
  }
}

// Close modal on overlay click
document.getElementById("groupModal")?.addEventListener("click", e => {
  if (e.target === document.getElementById("groupModal")) closeGroupModal();
});
```

- [ ] **Step 4: Test: click "View" on any guest row — modal opens with loading state, then shows group list (or "not a member" message)**

- [ ] **Step 5: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat: add group membership modal to guest-audit"
```

---

## Task 7: Disable / Delete actions with confirmation modals

**Files:**
- Modify: `tools/guest-audit/index.html`

- [ ] **Step 1: Add confirmation modal CSS (add to `<style>`)**

```css
  /* ── Confirm modal ── */
  .confirm-modal-overlay {
    position: fixed; inset: 0; background: rgba(0,0,0,.55);
    display: flex; align-items: center; justify-content: center;
    z-index: 1100; padding: 1rem;
    opacity: 0; pointer-events: none; transition: opacity .15s;
  }
  .confirm-modal-overlay.show { opacity: 1; pointer-events: all; }
  .confirm-modal-card {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 14px; padding: 2rem; max-width: 440px; width: 100%;
    box-shadow: 0 20px 60px rgba(0,0,0,.25);
    transform: translateY(10px); transition: transform .15s;
  }
  .confirm-modal-overlay.show .confirm-modal-card { transform: translateY(0); }
  .confirm-modal-icon {
    width: 44px; height: 44px; border-radius: 11px;
    display: flex; align-items: center; justify-content: center; font-size: 20px;
    margin-bottom: 1rem;
  }
  .confirm-modal-icon.warn   { background: var(--amber-light); }
  .confirm-modal-icon.danger { background: var(--red-light); }
  .confirm-modal-title { font-size: 17px; font-weight: 700; margin-bottom: 6px; }
  .confirm-modal-body  { font-size: 13px; color: var(--muted); line-height: 1.6; margin-bottom: 1.25rem; }
  .confirm-modal-actions { display: flex; gap: 10px; justify-content: flex-end; }
  .btn-confirm-cancel {
    padding: 9px 20px; border-radius: var(--radius-sm);
    background: transparent; border: 1px solid var(--border);
    font-size: 14px; font-weight: 600; cursor: pointer;
    font-family: inherit; color: var(--muted); transition: all .12s;
  }
  .btn-confirm-cancel:hover { background: var(--surface2); }
  .btn-confirm-ok {
    padding: 9px 20px; border-radius: var(--radius-sm);
    border: none; color: #fff; font-size: 14px; font-weight: 600;
    cursor: pointer; font-family: inherit; transition: background .12s;
  }
  .btn-confirm-ok:hover    { opacity: .88; }
  .btn-confirm-ok:disabled { opacity: .5; cursor: not-allowed; }
  .btn-confirm-ok.warn   { background: var(--amber); }
  .btn-confirm-ok.danger { background: var(--red); }
```

- [ ] **Step 2: Add confirmation modal HTML (inside `#appScreen`, after the group modal)**

```html
<!-- Confirmation modal -->
<div class="confirm-modal-overlay" id="confirmModal">
  <div class="confirm-modal-card">
    <div class="confirm-modal-icon" id="confirmIcon"></div>
    <div class="confirm-modal-title" id="confirmTitle"></div>
    <div class="confirm-modal-body"  id="confirmBody"></div>
    <div class="confirm-modal-actions">
      <button class="btn-confirm-cancel" onclick="closeConfirmModal()">Cancel</button>
      <button class="btn-confirm-ok"     id="confirmOkBtn" onclick="executeConfirm()"></button>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Add action JS**

```js
let _pendingAction = null; // { type: 'disable'|'enable'|'delete', userId, displayName }

function closeConfirmModal() {
  document.getElementById("confirmModal").classList.remove("show");
  _pendingAction = null;
}

function promptDisable(userId) {
  const guest = allGuests.find(g => g.id === userId);
  if (!guest) return;
  _pendingAction = { type: "disable", userId, displayName: guest.displayName };
  document.getElementById("confirmIcon").className  = "confirm-modal-icon warn";
  document.getElementById("confirmIcon").textContent = "⚠️";
  document.getElementById("confirmTitle").textContent = `Disable ${guest.displayName}?`;
  document.getElementById("confirmBody").textContent  =
    "This will block their sign-in. The account will remain in the tenant and can be re-enabled later.";
  const btn = document.getElementById("confirmOkBtn");
  btn.textContent  = "Disable account";
  btn.className    = "btn-confirm-ok warn";
  btn.disabled     = false;
  document.getElementById("confirmModal").classList.add("show");
}

function promptEnable(userId) {
  const guest = allGuests.find(g => g.id === userId);
  if (!guest) return;
  _pendingAction = { type: "enable", userId, displayName: guest.displayName };
  document.getElementById("confirmIcon").className  = "confirm-modal-icon";
  document.getElementById("confirmIcon").style.background = "var(--green-light)";
  document.getElementById("confirmIcon").textContent = "✅";
  document.getElementById("confirmTitle").textContent = `Enable ${guest.displayName}?`;
  document.getElementById("confirmBody").textContent  =
    "This will restore their sign-in access. The account will become active again.";
  const btn = document.getElementById("confirmOkBtn");
  btn.textContent  = "Enable account";
  btn.className    = "btn-confirm-ok";
  btn.style.background = "var(--green)";
  btn.disabled     = false;
  document.getElementById("confirmModal").classList.add("show");
}

function promptDelete(userId) {
  const guest = allGuests.find(g => g.id === userId);
  if (!guest) return;
  _pendingAction = { type: "delete", userId, displayName: guest.displayName };
  document.getElementById("confirmIcon").className  = "confirm-modal-icon danger";
  document.getElementById("confirmIcon").textContent = "🗑️";
  document.getElementById("confirmTitle").textContent = `Permanently delete ${guest.displayName}?`;
  document.getElementById("confirmBody").textContent  =
    "This cannot be undone. The account will be permanently removed from the tenant.";
  const btn = document.getElementById("confirmOkBtn");
  btn.textContent  = "Delete account";
  btn.className    = "btn-confirm-ok danger";
  btn.disabled     = false;
  document.getElementById("confirmModal").classList.add("show");
}

async function executeConfirm() {
  if (!_pendingAction) return;
  const { type, userId, displayName } = _pendingAction;
  const okBtn = document.getElementById("confirmOkBtn");
  okBtn.disabled = true;
  closeConfirmModal();

  const errEl = document.getElementById(`err-${userId}`);
  if (errEl) errEl.textContent = "";

  try {
    const token = await ITTools.auth.getToken();
    if (type === "disable" || type === "enable") {
      const enabled = type === "enable";
      await ITTools.graph.patch(`https://graph.microsoft.com/v1.0/users/${userId}`,
        { accountEnabled: enabled }, token);
      // Update local state
      const g = allGuests.find(g => g.id === userId);
      if (g) g.accountEnabled = enabled;
      // Update Account pill in row
      const acctEl = document.getElementById(`acct-${userId}`);
      if (acctEl) acctEl.innerHTML = enabled
        ? `<span class="pill-active">Active</span>`
        : `<span class="pill-disabled">Disabled</span>`;
      // Swap disable/enable button
      const disBtn = document.getElementById(`dis-${userId}`);
      const enaBtn = document.getElementById(`ena-${userId}`);
      if (enabled) {
        if (disBtn) { disBtn.style.display = ""; }
        if (enaBtn) { enaBtn.style.display = "none"; }
      } else {
        if (disBtn) { disBtn.style.display = "none"; disBtn.id = `dis-${userId}-hidden`; }
        // Insert enable button
        const actionsCell = document.querySelector(`tr[data-id="${userId}"] td:last-child div`);
        if (actionsCell && !document.getElementById(`ena-${userId}`)) {
          const enaNew = document.createElement("button");
          enaNew.id        = `ena-${userId}`;
          enaNew.className = "btn-action btn-enable";
          enaNew.textContent = "Enable";
          enaNew.onclick   = () => promptEnable(userId);
          actionsCell.insertBefore(enaNew, actionsCell.firstChild);
        }
      }
    } else if (type === "delete") {
      await ITTools.graph.delete(`https://graph.microsoft.com/v1.0/users/${userId}`, token);
      // Remove from local state and DOM
      allGuests = allGuests.filter(g => g.id !== userId);
      const row = document.querySelector(`tr[data-id="${userId}"]`);
      if (row) row.remove();
      // Update stats
      const threshold = parseInt(document.getElementById("staleSelect").value, 10);
      renderStats(allGuests, threshold);
    }
  } catch(e) {
    if (errEl) errEl.textContent = e.message || "Action failed";
    okBtn.disabled = false;
  }
}

document.getElementById("confirmModal")?.addEventListener("click", e => {
  if (e.target === document.getElementById("confirmModal")) closeConfirmModal();
});
```

- [ ] **Step 4: Check that `ITTools.graph` exposes `patch` and `delete` methods**

Run in browser console after auth: `Object.keys(ITTools.graph)` — if `patch` or `delete` are missing, use `ITTools.graph.fetch` with method override instead:

```js
// Fallback if ITTools.graph.patch doesn't exist:
await ITTools.graph.fetch(
  `https://graph.microsoft.com/v1.0/users/${userId}`,
  { method: "PATCH", body: JSON.stringify({ accountEnabled: false }) }
);
```

Check `shared/auth.js` for the actual API and adjust the calls to match what's available.

- [ ] **Step 5: Test disable flow: run scan → click Disable on a guest → confirm → Account pill changes to "Disabled", Disable button replaced by Enable**

- [ ] **Step 6: Test delete flow (use a test/sandbox guest only): run scan → click Delete → confirm → row removed, stats updated**

- [ ] **Step 7: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat: add disable/delete actions with confirmation modals to guest-audit"
```

---

## Task 8: CSV export

**Files:**
- Modify: `tools/guest-audit/index.html`

- [ ] **Step 1: Replace the `exportCsv` stub with the real implementation**

```js
function exportCsv() {
  if (!allGuests.length) return;
  const today = new Date().toISOString().slice(0, 10);
  ITTools.csv.download(
    `Guest_Access_Audit_${today}.csv`,
    allGuests.map(g => ({
      "Display Name":     g.displayName,
      "UPN":              g.upn,
      "Company":          g.companyName,
      "Department":       g.department,
      "Last Sign-In":     g.isNever ? "Never" : (g.lastSignIn || ""),
      "Days Inactive":    g.isNever ? "Never" : (g.daysInactive ?? ""),
      "Created":          g.created ? fmtDate(g.created) : "",
      "Licenses":         g.licenseCount,
      "Account Status":   g.accountEnabled ? "Active" : "Disabled",
      "Risk Signals":     [
        g.isNever     ? "Never signed in" : "",
        g.isStale     ? "Stale"           : "",
        g.isLicensed  ? "Licensed"        : "",
        g.isOldInvite ? "Old invite"      : "",
      ].filter(Boolean).join("; "),
    }))
  );
}
```

- [ ] **Step 2: Test: run scan → click Export CSV → file downloads as `Guest_Access_Audit_YYYY-MM-DD.csv` with correct columns**

Open CSV in Excel/text editor — verify columns match spec: Display Name, UPN, Company, Department, Last Sign-In, Days Inactive, Created, Licenses, Account Status, Risk Signals.

- [ ] **Step 3: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat: add CSV export to guest-audit"
```

---

## Task 9: Wire up config.json

**Files:**
- Modify: `config.json`

- [ ] **Step 1: Read config.json to find the guest-audit entry**

```bash
grep -n "guest-audit" config.json
```

- [ ] **Step 2: Update guest-audit entry — change status to `"beta"` and add path**

Change:
```json
{ "id": "guest-audit", "name": "Guest Access Audit", "description": "...", "status": "coming-soon" }
```

To:
```json
{ "id": "guest-audit", "name": "Guest Access Audit", "description": "Identify stale B2B guest accounts — review last sign-in, group memberships, and license exposure across your tenant.", "status": "beta", "path": "tools/guest-audit/" }
```

- [ ] **Step 3: Verify hub card links to the tool correctly**

Open hub, sign in — Guest Access Audit card should show "Beta" ribbon and link to `tools/guest-audit/`.

- [ ] **Step 4: Commit**

```bash
git add config.json
git commit -m "feat: enable guest-audit card in hub config as beta"
```

---

## Task 10: Final polish and error handling

**Files:**
- Modify: `tools/guest-audit/index.html`

- [ ] **Step 1: Fix the duplicate title in the `<title>` tag (license-audit has "M365 M365" typo — avoid repeating)**

Verify: `<title>Guest Access Audit — IT Tools</title>` — should already be correct from Task 1.

- [ ] **Step 2: Add `ConsistencyLevel: eventual` header support for `$count` queries**

The `$count=true` parameter on the guest filter URL requires the `ConsistencyLevel: eventual` header. Check if `ITTools.graph.getAll` adds this automatically. If it doesn't, the filter will fall through to the client-side fallback added in Task 3 — confirm this fallback works correctly in testing.

To verify: open browser DevTools network tab, run scan, look at the `/users?$filter=userType eq 'Guest'` request headers. If `ConsistencyLevel` is missing and the request returns 400, the fallback path kicks in. Confirm the fallback path completes correctly.

- [ ] **Step 3: Test the 403 banner path**

Temporarily use a test account without `User.Read.All` consent, run scan — should see the permission denied banner (not a JS error or blank page).

- [ ] **Step 4: Test no-session redirect**

Open `tools/guest-audit/index.html` directly without signing into hub — should redirect to `../../` (hub root).

- [ ] **Step 5: Test empty tenant**

If you have a dev tenant with no guests: run scan → should see "No guest accounts found in your tenant." banner, not a crash.

- [ ] **Step 6: Test group modal error path**

Open group modal for any guest, then open browser DevTools, override the `/memberOf` fetch to return 403 — modal should show "Could not load groups" inline error, not crash.

- [ ] **Step 7: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "fix: guest-audit polish, error handling verification, title fix"
```

---

## Spec Coverage Check

| Spec Requirement | Task |
|-----------------|------|
| Single file tools/guest-audit/index.html | Task 1 |
| Session consumer — redirect to hub if no session | Task 1 |
| Graph scopes User.Read.All, Directory.Read.All, AuditLog.Read.All | Task 3 |
| Stale threshold select (30/60/90/180/365) | Task 2 |
| Department filter | Task 2, 3 |
| Run Scan button + Cancel button | Task 2 |
| 429 exponential backoff retry (max 5) | Task 3 |
| Stats row: Total Guests, Never Signed In, Stale, Licensed | Task 4 |
| Table: all 9 columns | Task 5 |
| Table: all columns sortable | Task 5 |
| Table: search/filter | Task 5 |
| Risk badges: Never / Stale / Licensed / Old invite | Task 5 |
| Groups column: View button → modal | Task 6 |
| Group modal: lazy fetch, loading state, error state | Task 6 |
| Disable action + confirmation modal | Task 7 |
| Delete action + confirmation modal | Task 7 |
| On disable: Account pill updates, Disable→Enable | Task 7 |
| On delete: row removed, stats updated | Task 7 |
| CSV export with correct filename and columns | Task 8 |
| config.json: status beta + path | Task 9 |
| 403 banner | Task 3, 10 |
| Empty state banner | Task 3 |
| Group fetch fail: inline error, no crash | Task 6, 10 |
| Action fail: inline row error | Task 7 |
