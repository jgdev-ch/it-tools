# Adobe License Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a new IT Tools tool that shows live Adobe seat utilization (purchased vs assigned) and Entra group member counts side-by-side for 3 Adobe products, with automatic drift detection.

**Architecture:** Single-file tool at `tools/adobe-license-monitor/index.html` following the exact same pattern as all other tools in this repo — shared MSAL auth via `shared/auth.js`, shared styles via `shared/styles.css`, no build system. On sign-in, `loadDashboard()` fetches an Adobe OAuth token (client credentials) and a Microsoft Graph token in parallel, then fires all 4 data calls in one `Promise.all`. Results are rendered as three horizontal stacked cards. A hub card entry is added to `config.json`.

**Tech Stack:** Vanilla JS, `shared/auth.js`, `shared/styles.css`, Adobe IMS OAuth2 (client credentials flow), Adobe User Management API v2, Microsoft Graph `/groups/$count`.

---

## File Map

| File | Change |
|---|---|
| `tools/adobe-license-monitor/index.html` | Create — complete tool (HTML + CSS + JS) |
| `config.json` | Modify — add Adobe License Monitor entry |

---

## Context for implementers

This repo has no build system. Files are plain HTML/CSS/JS served directly. All tools follow this pattern:

1. Load `../../shared/msal-browser.min.js` and `../../shared/styles.css` in `<head>`
2. Load `../../shared/auth.js` just before the closing `</body>`
3. Call `ITTools.theme.init()`, `ITTools.ui.renderTopbar(...)`, then `ITTools.auth.init(...)` inside an `init()` function wired to `DOMContentLoaded`
4. `ITTools.auth.init()` calls `onSignIn(account)` if a session exists (silent restore) or when the user signs in manually
5. `ITTools.ui.setUser(account)` shows the account avatar in the topbar
6. `ITTools.ui.clearUser()` hides it on sign-out

The shared CSS provides: `--blue`, `--blue-light`, `--blue-dark`, `--blue-border`, `--amber`, `--amber-light`, `--amber-border`, `--green`, `--green-light`, `--green-border`, `--red`, `--red-light`, `--surface`, `--surface2`, `--surface3`, `--border`, `--text`, `--muted`, `--muted2`, `var(--radius)`, `var(--shadow-md)`. Also provides `.btn-ms` (Microsoft sign-in button), `.banner.error`, `.banner.warn`, `.banner.info`, `.banner.success`.

The auth screen pattern (sign-in prompt shown when no session) uses `id="authScreen"` hidden by default. The app content uses `id="appScreen"` hidden by default. `onSignIn` hides `authScreen` and shows `appScreen`. `onSignOut` reverses this.

---

## Task 1: HTML shell, CSS, auth screen, and `init()`

**Files:**
- Create: `tools/adobe-license-monitor/index.html`

- [ ] **Step 1: Create the tool directory and file**

```bash
mkdir -p tools/adobe-license-monitor
```

- [ ] **Step 2: Write the complete HTML file**

Create `tools/adobe-license-monitor/index.html` with this complete content:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Adobe License Monitor — IT Tools</title>
<script src="../../shared/msal-browser.min.js"></script>
<link rel="stylesheet" href="../../shared/styles.css"/>
<style>
  .shell { max-width: 860px; margin: 0 auto; padding: 1.75rem 1.25rem; }

  /* ── Page header ── */
  .page-header { display: flex; align-items: flex-start; justify-content: space-between; margin-bottom: 1.5rem; gap: 12px; }
  .page-header-left h1 { font-size: 22px; font-weight: 800; display: flex; align-items: center; gap: 10px; margin-bottom: 4px; }
  .page-header-left p  { font-size: 13px; color: var(--muted); }
  .adobe-badge { width: 26px; height: 26px; background: #fa0f00; border-radius: 6px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 900; color: #fff; flex-shrink: 0; }

  /* ── Summary bar ── */
  .summary-bar { display: grid; grid-template-columns: repeat(3,1fr); gap: 12px; margin-bottom: 1.25rem; }
  .summary-stat { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 14px 16px; display: flex; align-items: center; gap: 12px; }
  .summary-icon { width: 36px; height: 36px; border-radius: 9px; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .summary-icon.blue  { background: var(--blue-light);  color: var(--blue); }
  .summary-icon.green { background: var(--green-light); color: var(--green); }
  .summary-icon.amber { background: var(--amber-light); color: var(--amber); }
  .summary-num   { font-size: 24px; font-weight: 800; line-height: 1; }
  .summary-label { font-size: 11px; color: var(--muted2); margin-top: 2px; }

  /* ── Status bar ── */
  .status-bar { display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; font-size: 12px; color: var(--muted2); }
  .status-live { display: flex; align-items: center; gap: 7px; }
  .status-dot  { width: 7px; height: 7px; border-radius: 50%; background: var(--green); }

  /* ── Drift banner ── */
  .drift-banner { background: var(--amber-light); border: 1px solid var(--amber-border); border-radius: 10px; padding: 11px 16px; margin-bottom: 1.25rem; display: flex; align-items: flex-start; gap: 10px; font-size: 12px; color: var(--amber); font-weight: 600; }
  .drift-banner svg { flex-shrink: 0; margin-top: 1px; }

  /* ── Product cards ── */
  .product-stack { display: flex; flex-direction: column; gap: 14px; }
  .product-card  {
    background: var(--surface); border: 1px solid var(--border); border-radius: 12px;
    display: grid; grid-template-columns: 200px 1fr 220px; overflow: hidden;
  }

  /* Left: identity */
  .card-identity { padding: 22px 20px; border-right: 1px solid var(--border); display: flex; flex-direction: column; justify-content: center; gap: 6px; }
  .card-identity-top { display: flex; align-items: center; gap: 8px; }
  .adobe-dot  { width: 10px; height: 10px; border-radius: 50%; background: #fa0f00; flex-shrink: 0; }
  .product-name  { font-size: 14px; font-weight: 700; line-height: 1.2; }
  .product-group { font-size: 10px; color: var(--muted2); background: var(--surface2); border: 1px solid var(--border); border-radius: 5px; padding: 3px 7px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; width: fit-content; max-width: 160px; }

  /* Middle: utilization */
  .card-util { padding: 22px 28px; border-right: 1px solid var(--border); display: flex; flex-direction: column; justify-content: center; }
  .util-section-label { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em; color: var(--muted2); margin-bottom: 10px; display: flex; align-items: center; gap: 5px; }
  .util-bar-wrap { background: var(--surface3); border-radius: 8px; height: 12px; overflow: hidden; margin-bottom: 10px; }
  .util-bar { height: 100%; border-radius: 8px; }
  .util-bar.ok   { background: linear-gradient(90deg, #16a34a, #22c55e); }
  .util-bar.warn { background: linear-gradient(90deg, #d97706, #f59e0b); }
  .util-bar.full { background: linear-gradient(90deg, #dc2626, #ef4444); }
  .util-bar.na   { background: var(--surface3); }
  .util-numbers { display: flex; align-items: baseline; gap: 6px; margin-bottom: 6px; }
  .util-big  { font-size: 32px; font-weight: 800; line-height: 1; }
  .util-big.ok   { color: var(--green); }
  .util-big.warn { color: var(--amber); }
  .util-big.full { color: var(--red); }
  .util-big.na   { color: var(--muted2); }
  .util-sep   { font-size: 14px; color: var(--muted2); }
  .util-total { font-size: 22px; font-weight: 700; color: var(--text); }
  .util-pct   { font-size: 12px; color: var(--muted2); margin-left: 2px; }
  .util-free-row { font-size: 12px; font-weight: 600; }
  .util-free-row.ok   { color: var(--green); }
  .util-free-row.warn { color: var(--amber); }
  .util-free-row.full { color: var(--red); }
  .util-unavail { font-size: 12px; color: var(--muted2); font-style: italic; }

  /* Right: Entra */
  .card-entra { padding: 22px 20px; background: var(--blue-light); display: flex; flex-direction: column; justify-content: center; gap: 4px; }
  .entra-heading { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em; color: var(--blue-dark); opacity: .7; margin-bottom: 6px; display: flex; align-items: center; gap: 5px; }
  .entra-big { font-size: 42px; font-weight: 800; color: var(--blue); line-height: 1; }
  .entra-big.na { color: var(--muted2); font-size: 28px; }
  .entra-sub  { font-size: 10px; color: var(--blue-dark); opacity: .65; margin-bottom: 8px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .entra-sync { display: inline-flex; align-items: center; gap: 5px; font-size: 11px; font-weight: 700; padding: 4px 10px; border-radius: 20px; width: fit-content; }
  .entra-sync.ok    { background: var(--green-light); color: var(--green);  border: 1px solid var(--green-border); }
  .entra-sync.drift { background: var(--amber-light); color: var(--amber);  border: 1px solid var(--amber-border); }
  .entra-sync.na    { background: var(--surface2);    color: var(--muted2); border: 1px solid var(--border); }

  /* ── Shimmer skeletons ── */
  @keyframes shimmer { 0%{background-position:-200% 0} 100%{background-position:200% 0} }
  .skeleton { background: linear-gradient(90deg, var(--surface3) 25%, var(--surface2) 50%, var(--surface3) 75%); background-size: 200% 100%; animation: shimmer 1.5s infinite; border-radius: 6px; }

  /* ── Auth screen ── */
  .auth-screen { min-height: 60vh; display: flex; align-items: center; justify-content: center; }
  .auth-card { background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 2rem 2.25rem; max-width: 400px; width: 100%; text-align: center; }
  .auth-card .adobe-badge { margin: 0 auto 1rem; width: 40px; height: 40px; font-size: 15px; }
  .auth-card h2 { font-size: 18px; font-weight: 700; margin-bottom: 8px; }
  .auth-card p  { font-size: 13px; color: var(--muted); margin-bottom: 1.5rem; line-height: 1.5; }
</style>
</head>
<body>

<!-- Auth screen — shown when no session -->
<div id="authScreen" class="auth-screen" style="display:none">
  <div class="auth-card">
    <div class="adobe-badge">Ai</div>
    <h2>Adobe License Monitor</h2>
    <p>Sign in with your Microsoft account to view live Adobe seat utilization and Entra group sync status.</p>
    <button class="btn-ms" onclick="doSignIn(this)">
      <svg viewBox="0 0 21 21" width="13" height="13" fill="none">
        <rect x="1"  y="1"  width="9" height="9" fill="#f25022"/>
        <rect x="11" y="1"  width="9" height="9" fill="#7fba00"/>
        <rect x="1"  y="11" width="9" height="9" fill="#00a4ef"/>
        <rect x="11" y="11" width="9" height="9" fill="#ffb900"/>
      </svg>
      Sign in with Microsoft
    </button>
    <div class="banner error" id="authErr" style="display:none"></div>
  </div>
</div>

<!-- App screen — shown after sign-in -->
<div id="appScreen" style="display:none">
  <div class="shell">
    <div class="page-header">
      <div class="page-header-left">
        <h1>
          <div class="adobe-badge">Ai</div>
          Adobe License Monitor
        </h1>
        <p>Live seat utilization and Entra group sync status across all Adobe products</p>
      </div>
      <button class="btn" id="refreshBtn" onclick="loadDashboard()" style="display:flex;align-items:center;gap:6px;padding:7px 14px;border-radius:8px;font-size:12px;font-weight:600;cursor:pointer;border:1px solid var(--blue);background:var(--blue);color:#fff">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
        Refresh
      </button>
    </div>

    <!-- Summary strip -->
    <div class="summary-bar" id="summaryBar">
      <div class="summary-stat">
        <div class="summary-icon blue">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
        </div>
        <div><div class="summary-num" id="sumPurchased">—</div><div class="summary-label">Total purchased seats</div></div>
      </div>
      <div class="summary-stat">
        <div class="summary-icon green">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
        </div>
        <div><div class="summary-num" id="sumAssigned">—</div><div class="summary-label">Assigned in Adobe</div></div>
      </div>
      <div class="summary-stat">
        <div class="summary-icon amber">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/></svg>
        </div>
        <div><div class="summary-num" id="sumDrift">—</div><div class="summary-label">Products with drift</div></div>
      </div>
    </div>

    <!-- Status bar -->
    <div class="status-bar">
      <div class="status-live">
        <div class="status-dot"></div>
        <span id="statusText">Loading...</span>
      </div>
      <span>Adobe UMAPI + Microsoft Graph</span>
    </div>

    <!-- Drift banner -->
    <div class="drift-banner" id="driftBanner" style="display:none">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
      <div id="driftBannerText"></div>
    </div>

    <!-- Page-level error banner -->
    <div class="banner error" id="pageErr" style="display:none"></div>

    <!-- Product cards -->
    <div class="product-stack" id="productStack"></div>
  </div>
</div>

<script src="../../shared/auth.js"></script>
<script>
// ─── Config ──────────────────────────────────────────────────────────────────
const ADOBE_ORG_ID        = "";   // e.g. "ABCD1234@AdobeOrg"
const ADOBE_CLIENT_ID     = "";   // from Adobe Developer Console
const ADOBE_CLIENT_SECRET = "";   // from Adobe Developer Console

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

// ─── API ─────────────────────────────────────────────────────────────────────
async function _getAdobeToken() {
  const res = await fetch("https://ims-na1.adobelogin.com/ims/token/v3", {
    method:  "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:    new URLSearchParams({
      grant_type:    "client_credentials",
      client_id:     ADOBE_CLIENT_ID,
      client_secret: ADOBE_CLIENT_SECRET,
      scope:         "openid,AdobeID,user_management_sdk",
    }),
  });
  if (!res.ok) throw new Error("Adobe token fetch failed: " + res.status);
  return (await res.json()).access_token;
}

async function _getAdobeProducts(token) {
  const res = await fetch(
    `https://usermanagement.adobe.io/v2/usermanagement/organizations/${ADOBE_ORG_ID}/products`,
    { headers: { Authorization: "Bearer " + token, "x-api-key": ADOBE_CLIENT_ID } }
  );
  if (!res.ok) throw new Error("UMAPI products fetch failed: " + res.status);
  const data = await res.json();
  return data.products || [];
}

async function _getGroupCount(graphToken, groupId) {
  const res = await fetch(
    `https://graph.microsoft.com/v1.0/groups/${groupId}/members/$count`,
    { headers: { Authorization: "Bearer " + graphToken, ConsistencyLevel: "eventual" } }
  );
  if (!res.ok) throw new Error("Group count fetch failed for " + groupId);
  return parseInt(await res.text(), 10);
}

// ─── Dashboard ───────────────────────────────────────────────────────────────
async function loadDashboard() {
  setLoading(true);
  document.getElementById("pageErr").style.display = "none";
  try {
    const [adobeToken, graphToken] = await Promise.all([
      _getAdobeToken(),
      ITTools.auth.getToken(),
    ]);

    let adobeProducts = [];
    let adobeFailed   = false;
    try {
      adobeProducts = await _getAdobeProducts(adobeToken);
    } catch (_) {
      adobeFailed = true;
    }

    const groupCounts = await Promise.all(
      PRODUCTS.map(async p => {
        try { return await _getGroupCount(graphToken, p.groupId); }
        catch (_) { return null; }
      })
    );

    const results = PRODUCTS.map((p, i) => {
      const ap = adobeProducts.find(x =>
        x.productName.toLowerCase().includes(p.adobeMatch.toLowerCase())
      );
      return {
        name:        p.name,
        groupId:     p.groupId,
        purchased:   adobeFailed ? null : (ap?.quota     ?? null),
        assigned:    adobeFailed ? null : (ap?.userCount ?? null),
        entra:       groupCounts[i],
        adobeFailed,
      };
    });

    render(results);
    document.getElementById("statusText").textContent =
      "Last refreshed " + new Date().toLocaleTimeString();
  } catch (err) {
    ITTools.ui.banner("pageErr", ITTools.graph.friendlyError(err), "error");
    setLoading(false);
  }
}

// ─── Render ──────────────────────────────────────────────────────────────────
function barClass(pct) {
  if (pct === null) return "na";
  if (pct >= 100)   return "full";
  if (pct >= 90)    return "warn";
  return "ok";
}

function driftStatus(assigned, entra) {
  if (assigned === null || entra === null) return null;
  if (entra > assigned)  return { type: "drift", label: (entra - assigned) + " unprovisioned" };
  if (entra < assigned)  return { type: "drift", label: (assigned - entra) + " orphaned seats" };
  return { type: "ok", label: "In sync" };
}

function renderSummary(results) {
  const validPurchased = results.filter(r => r.purchased !== null);
  const validAssigned  = results.filter(r => r.assigned  !== null);
  const driftCount     = results.filter(r => {
    const d = driftStatus(r.assigned, r.entra);
    return d && d.type === "drift";
  }).length;

  document.getElementById("sumPurchased").textContent =
    validPurchased.length ? validPurchased.reduce((s, r) => s + r.purchased, 0) : "—";
  document.getElementById("sumAssigned").textContent =
    validAssigned.length  ? validAssigned.reduce((s, r)  => s + r.assigned,  0) : "—";
  document.getElementById("sumDrift").textContent = driftCount;
  document.getElementById("sumDrift").style.color =
    driftCount > 0 ? "var(--amber)" : "var(--green)";
}

function renderDriftBanner(results) {
  const driftEl   = document.getElementById("driftBanner");
  const driftText = document.getElementById("driftBannerText");
  const driftItems = results
    .map(r => ({ name: r.name, drift: driftStatus(r.assigned, r.entra) }))
    .filter(x => x.drift && x.drift.type === "drift");

  if (!driftItems.length) { driftEl.style.display = "none"; return; }
  driftText.textContent = driftItems
    .map(x => x.name + " — " + x.drift.label)
    .join(" · ");
  driftEl.style.display = "flex";
}

function renderCards(results) {
  const stack = document.getElementById("productStack");
  stack.innerHTML = results.map(r => {
    const pct    = (r.purchased && r.assigned !== null) ? Math.round(r.assigned / r.purchased * 100) : null;
    const bc     = barClass(pct);
    const drift  = driftStatus(r.assigned, r.entra);
    const free   = (r.purchased !== null && r.assigned !== null) ? r.purchased - r.assigned : null;
    const shortGroup = r.groupId ? "..." + r.groupId.slice(-8) : "";

    const utilMiddle = r.adobeFailed
      ? `<div class="util-unavail">Adobe data unavailable — API error</div>`
      : `
        <div class="util-bar-wrap"><div class="util-bar ${bc}" style="width:${pct ?? 0}%"></div></div>
        <div class="util-numbers">
          <span class="util-big ${bc}">${r.assigned ?? "—"}</span>
          <span class="util-sep">of</span>
          <span class="util-total">${r.purchased ?? "—"}</span>
          <span class="util-pct">${pct !== null ? "assigned · " + pct + "%" : ""}</span>
        </div>
        <div class="util-free-row ${bc}">${free !== null ? free + " seat" + (free !== 1 ? "s" : "") + " available" : ""}</div>`;

    const driftPill = drift
      ? `<div class="entra-sync ${drift.type}">${drift.type === "ok" ? "✓" : "⚠"} ${drift.label}</div>`
      : `<div class="entra-sync na">—</div>`;

    return `
      <div class="product-card">
        <div class="card-identity">
          <div class="card-identity-top">
            <div class="adobe-dot"></div>
            <div class="product-name">${r.name}</div>
          </div>
          <div class="product-group">${shortGroup}</div>
        </div>
        <div class="card-util">
          <div class="util-section-label">
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
            Adobe seat utilization
          </div>
          ${utilMiddle}
        </div>
        <div class="card-entra">
          <div class="entra-heading">
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/></svg>
            Entra group members
          </div>
          <div class="entra-big ${r.entra === null ? "na" : ""}">${r.entra ?? "—"}</div>
          <div class="entra-sub">P-EID-SG-STD-SSO-Adobe_${r.name.replace(/ /g, "_")}</div>
          ${driftPill}
        </div>
      </div>`;
  }).join("");
}

function setLoading(loading) {
  const stack = document.getElementById("productStack");
  if (!loading) return;
  stack.innerHTML = PRODUCTS.map(() => `
    <div class="product-card">
      <div class="card-identity" style="gap:10px">
        <div class="skeleton" style="height:14px;width:80%"></div>
        <div class="skeleton" style="height:10px;width:60%"></div>
      </div>
      <div class="card-util" style="gap:10px">
        <div class="skeleton" style="height:10px;width:40%"></div>
        <div class="skeleton" style="height:12px;width:100%"></div>
        <div class="skeleton" style="height:32px;width:50%"></div>
      </div>
      <div class="card-entra" style="gap:10px">
        <div class="skeleton" style="height:10px;width:60%"></div>
        <div class="skeleton" style="height:42px;width:40%"></div>
      </div>
    </div>`).join("");
  document.getElementById("sumPurchased").textContent = "—";
  document.getElementById("sumAssigned").textContent  = "—";
  document.getElementById("sumDrift").textContent     = "—";
  document.getElementById("driftBanner").style.display = "none";
}

function render(results) {
  renderSummary(results);
  renderDriftBanner(results);
  renderCards(results);
}

// ─── Auth ─────────────────────────────────────────────────────────────────────
async function doSignIn(btn) {
  const errEl = document.getElementById("authErr");
  errEl.style.display = "none";
  try {
    await ITTools.ui.withButtonSpinner(btn, async () => {
      const acct = await ITTools.auth.signIn();
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
      await loadDashboard();
    });
  } catch (err) {
    ITTools.ui.banner("authErr", ITTools.graph.friendlyError(err), "error");
  }
}

async function init() {
  ITTools.theme.init();
  ITTools.ui.renderTopbar({ toolName: "Adobe License Monitor", hubRelPath: "../../" });

  let sessionFound = false;
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: async acct => {
      sessionFound = true;
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
      await loadDashboard();
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
    },
  });
  if (!sessionFound) {
    document.getElementById("authScreen").style.display = "flex";
  }
}

window.addEventListener("DOMContentLoaded", init);
</script>
</body>
</html>
```

- [ ] **Step 3: Verify the page loads without errors (before filling in credentials)**

Open `tools/adobe-license-monitor/index.html` directly in a browser (or via the preview URL if deployed). You should see:
- The IT Tools topbar with "Adobe License Monitor" as the tool name
- The sign-in screen with the Microsoft sign-in button
- No console errors

The page should NOT crash just because credentials are empty — it only fetches when the user signs in.

- [ ] **Step 4: Commit**

```bash
git add tools/adobe-license-monitor/index.html
git commit -m "feat: add Adobe License Monitor tool — shell, CSS, auth, API, and render"
```

---

## Task 2: Fill in Adobe credentials and verify live data

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

- [ ] **Step 1: Drop in the three Adobe constants**

Open `tools/adobe-license-monitor/index.html`. Find these three lines near the top of the `<script>` block:

```js
const ADOBE_ORG_ID        = "";
const ADOBE_CLIENT_ID     = "";
const ADOBE_CLIENT_SECRET = "";
```

Fill them in with the values from the Adobe Developer Console:

```js
const ADOBE_ORG_ID        = "YOUR_ORG_ID@AdobeOrg";
const ADOBE_CLIENT_ID     = "YOUR_CLIENT_ID";
const ADOBE_CLIENT_SECRET = "YOUR_CLIENT_SECRET";
```

Do not commit these values to git — this step is local verification only. The file with real credentials must not be committed.

- [ ] **Step 2: Open the tool in a browser and sign in**

Navigate to the tool on the preview URL or open `index.html` directly. Sign in with your Microsoft account. You should see:
- Shimmer skeletons appear briefly in all three cards
- Cards populate with real data: three products, utilization bars, Entra member counts
- Summary strip shows total purchased seats, total assigned, and drift count
- Drift banner visible if any Entra count differs from Adobe assigned count
- Status bar shows "Last refreshed [time]"

- [ ] **Step 3: Verify each card's Adobe data**

In the browser, open DevTools → Console and run:
```js
_getAdobeToken().then(t => _getAdobeProducts(t)).then(p => console.table(p.map(x => ({ productName: x.productName, quota: x.quota, userCount: x.userCount }))))
```

Confirm the three products appear in the table with non-zero `quota` values. If a product shows `null` for purchased/assigned, the `adobeMatch` substring didn't match — compare `productName` in the table against the `adobeMatch` values in `PRODUCTS` and adjust.

- [ ] **Step 4: Verify Entra group counts**

In DevTools console run:
```js
ITTools.auth.getToken().then(t => Promise.all([
  fetch("https://graph.microsoft.com/v1.0/groups/422c070e-b330-4df5-ac34-70b91d9ed0bc/members/$count", { headers: { Authorization: "Bearer " + t, ConsistencyLevel: "eventual" } }).then(r => r.text()),
  fetch("https://graph.microsoft.com/v1.0/groups/06d901c3-e604-4991-aec6-b044c51de773/members/$count", { headers: { Authorization: "Bearer " + t, ConsistencyLevel: "eventual" } }).then(r => r.text()),
  fetch("https://graph.microsoft.com/v1.0/groups/1f5c83ec-22d0-4dce-b811-284cdbaf3c64/members/$count", { headers: { Authorization: "Bearer " + t, ConsistencyLevel: "eventual" } }).then(r => r.text()),
])).then(counts => console.log("Acrobat:", counts[0], "CC:", counts[1], "Captivate:", counts[2]))
```

Confirm three integer values are returned. Cross-check against the member counts in the Entra admin portal for those groups.

- [ ] **Step 5: Remove credentials before committing**

Reset the three constants back to empty strings:

```js
const ADOBE_ORG_ID        = "";
const ADOBE_CLIENT_ID     = "";
const ADOBE_CLIENT_SECRET = "";
```

- [ ] **Step 6: Commit the verified-but-empty file**

```bash
git add tools/adobe-license-monitor/index.html
git commit -m "feat: verify Adobe License Monitor data flow — credentials confirmed working, constants left empty for security"
```

---

## Task 3: Add tool to `config.json` and hub card

**Files:**
- Modify: `config.json`

- [ ] **Step 1: Add the Adobe License Monitor entry to `config.json`**

Open `config.json`. The file contains a `"tools"` array. Add this entry at the end of the array (before the closing `]`):

```json
,
{
  "id": "adobe-license-monitor",
  "name": "Adobe License Monitor",
  "description": "Live seat utilization and Entra group sync across Acrobat DC Pro, Creative Cloud All Apps, and Captivate.",
  "icon": "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='#9a0000' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='2' y='3' width='20' height='14' rx='2'/><line x1='8' y1='21' x2='16' y2='21'/><line x1='12' y1='17' x2='12' y2='21'/><path d='M9 8l2 2 4-4'/></svg>",
  "status": "live",
  "path": "tools/adobe-license-monitor/",
  "permissions": ["User.Read", "GroupMember.Read.All"],
  "accent": "#9a0000",
  "iconBg": "#fee2e2",
  "category": "reporting-audit"
}
```

- [ ] **Step 2: Verify the hub card appears**

Open `index.html` (the hub) in a browser and sign in. Navigate to the Reporting & Audit section. Confirm:
- "Adobe License Monitor" card is visible
- Card description matches
- Clicking the card navigates to `tools/adobe-license-monitor/`
- No gate ribbon (ungated — visible to all authenticated users)

- [ ] **Step 3: Commit**

```bash
git add config.json
git commit -m "feat: add Adobe License Monitor hub card to config.json"
```

---

## Task 4: Push to preview and smoke-test

**Files:** None

- [ ] **Step 1: Push to preview**

```bash
git push origin testing
```

- [ ] **Step 2: Add real credentials on the preview branch locally for testing**

The credentials are never committed. For live testing, temporarily edit the file locally on your machine with the real values. Reload the preview URL and verify the full flow.

- [ ] **Step 3: Full smoke test checklist**

Open the tool on the preview URL (`https://jgdev-ch.github.io/it-tools-preview/tools/adobe-license-monitor/`):

- Sign in → shimmer appears → cards render with real data ✓
- All 3 product cards visible: Acrobat DC Pro, Creative Cloud All Apps, Captivate ✓
- Each card: utilization bar colour matches utilization level (green/amber/red) ✓
- Each card: Entra member count matches what you see in Entra admin portal ✓
- Summary strip: purchased total = sum of all 3 quota values ✓
- Drift banner: visible if any Entra ≠ Adobe assigned count, hidden if all in sync ✓
- Refresh button re-fetches all data ✓
- Sign out → auth screen reappears, account dropdown hides ✓
- Hub card links correctly to the tool ✓
- Theme toggle (light/dark) works correctly ✓
