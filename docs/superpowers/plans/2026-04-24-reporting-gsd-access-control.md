# Reporting Gate & GSD Access Control — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `SG-IT-Tools-Reporting-View` gate on the 3 ungated reporting/audit tools, wire `SG-IT-Tools-GSD` into the hub gate system for future use, apply gold lock styling to reporting-gated hub cards, and add Reporting View + GSD Access badges across all tools.

**Architecture:** Follows the existing `financeOnly` / `GROUP_GATES` pattern throughout. New `reportingOnly` flag in config.json, new entries in hub `GROUP_GATES`, locked cards unlock on confirmed group membership. Tool-level enforcement uses a single `checkMemberObjects` POST batching both new group IDs. Badges are static HTML elements shown/hidden via JS after group checks resolve.

**Tech Stack:** Vanilla JS, Microsoft Graph `/me/checkMemberObjects`, localStorage gate caching, Lucide SVG icons inline, CSS custom properties (`var(--amber)`, `var(--blue-light)`, etc.).

**Two placeholder Object IDs used throughout — replace before testing:**
- `REPORTING_GROUP_ID` = `"<SG-IT-Tools-Reporting-View Object ID>"`
- `GSD_GROUP_ID` = `"<SG-IT-Tools-GSD Object ID>"`

---

## File Map

| File | Changes |
|---|---|
| `config.json` | Add `reportingOnly: true` to 3 tools |
| `index.html` (hub) | GROUP_GATES, cardHtml(), buildLockedCard(), gold lock CSS, hub badges HTML+CSS+JS |
| `tools/license-audit/index.html` | Reporting gate enforcement, Reporting View + GSD badges |
| `tools/mfa-status/index.html` | Reporting gate enforcement, Reporting View + GSD badges |
| `tools/guest-audit/index.html` | Reporting gate enforcement, Reporting View + GSD badges |
| `tools/group-import/index.html` | GSD badge only |
| `tools/name-resolver/index.html` | GSD badge only |

---

## Task 1: config.json — reportingOnly flag

**Files:**
- Modify: `config.json`

- [ ] **Step 1: Add `reportingOnly: true` to the three tools**

In `config.json`, add `"reportingOnly": true` to the objects for `license-audit`, `mfa-status`, and `guest-audit`. `finance-dashboard` keeps `"financeOnly": true` only — do not touch it.

After editing, the license-audit entry looks like:
```json
{
  "id": "license-audit",
  "name": "M365 License Audit",
  "description": "Surface inactive license holders and recover unused seats before your next renewal.",
  "betaNote": "Multi-license mode is new — behavior with group-inherited licenses at scale is still being validated.",
  "icon": "<svg .../>",
  "status": "beta",
  "path": "tools/license-audit/",
  "permissions": ["User.Read.All", "AuditLog.Read.All"],
  "accent": "#1a56db",
  "iconBg": "#e8f0fe",
  "category": "reporting-audit",
  "reportingOnly": true
}
```

Apply the same `"reportingOnly": true` line to `mfa-status` and `guest-audit` in the same way.

- [ ] **Step 2: Verify JSON is valid**

```bash
node -e "JSON.parse(require('fs').readFileSync('config.json','utf8')); console.log('OK')"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add config.json
git commit -m "feat: mark reporting-audit tools as reportingOnly in config"
```

---

## Task 2: Hub — GROUP_GATES, card rendering, gold lock styling

**Files:**
- Modify: `index.html` (hub)

The hub currently gates only `financeOnly` tools via a single `GROUP_GATES` entry. This task adds `reporting` and `gsd` gates and updates card rendering to handle `reportingOnly`.

- [ ] **Step 1: Add reporting and GSD entries to GROUP_GATES**

Find the existing `GROUP_GATES` object at line ~324:
```js
const GROUP_GATES = {
  "finance": {
    id:       "ff9c3232-251f-4570-9564-340039d17aa9",
    localKey: "it-tools-finance-unlocked",
  }
};
```

Replace it with:
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

- [ ] **Step 2: Update `buildLockedCard()` to use `data-gate` and support gold lock**

The current function uses `id="gate-${gateKey}"` for selection. With 3 reporting cards this creates 3 duplicate IDs — only the first would unlock. Fix: switch to a `data-gate` attribute for selection so `querySelectorAll` can find all cards for a given gate.

Find `buildLockedCard()` at line ~379. Replace the entire function:

```js
function buildLockedCard({ gateKey, path, iconBg, icon, status, name, desc, perms, betaNote }) {
  const permsStr  = (perms || []).join("|");
  const lockClass = gateKey === "reporting" ? " locked--reporting" : "";
  const lockTitle = gateKey === "reporting"
    ? "Requires reporting access — contact your IT administrator"
    : "Permissions required — sign in with an authorized account to unlock this tool.";
  return `<div class="tool-card locked${lockClass}" data-gate="${gateKey}"
      data-path="${path}" data-iconbg="${iconBg}"
      data-icon="${icon}" data-status="${status}"
      data-name="${name}" data-desc="${desc}" data-perms="${permsStr}"
      data-betanote="${betaNote || ""}"
      style="--icon-bg:${iconBg}">
    ${ribbonHtml(status)}
    <div class="tool-icon">${icon}</div>
    <div class="tool-name-row">
      <div class="tool-name">${name}</div>
      <div class="lock-hint" title="${lockTitle}"><svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg></div>
    </div>
    <div class="tool-desc">${lockTitle}</div>
  </div>`;
}
```

- [ ] **Step 2b: Update `unlockCard()` to use `querySelectorAll` on `data-gate`**

Find `unlockCard()` at line ~411:
```js
function unlockCard(gateKey) {
  const locked = document.getElementById(`gate-${gateKey}`);
  if (!locked) return;
  locked.outerHTML = buildLiveCard({ ... });
}
```

Replace with:
```js
function unlockCard(gateKey) {
  document.querySelectorAll(`[data-gate="${gateKey}"]`).forEach(locked => {
    locked.outerHTML = buildLiveCard({
      path:     locked.dataset.path,
      iconBg:   locked.dataset.iconbg,
      icon:     locked.dataset.icon,
      status:   locked.dataset.status,
      name:     locked.dataset.name,
      desc:     locked.dataset.desc,
      betaNote: locked.dataset.betanote || "",
    });
  });
}
```

- [ ] **Step 2c: Update `lockCard()` and `_gateCardMeta` to handle multiple cards per gate**

`_gateCardMeta` currently stores one object per gate key. Change it to store arrays so multiple cards can be re-locked. Find `lockCard()` at line ~426 and the `_gateCardMeta` declaration at line ~445.

Replace `lockCard()`:
```js
function lockCard(gateKey) {
  const metas = _gateCardMeta[gateKey];
  if (!metas) return;
  for (const meta of metas) {
    const live = document.querySelector(`a.tool-card[href="${meta.path}"]`);
    if (!live) continue;
    live.outerHTML = buildLockedCard({
      gateKey,
      path:     meta.path,
      iconBg:   meta.iconBg,
      icon:     meta.icon,
      status:   meta.status,
      name:     meta.name,
      desc:     meta.desc,
      perms:    meta.perms,
      betaNote: meta.betaNote || "",
    });
  }
}
```

The `_gateCardMeta` declaration stays the same (`const _gateCardMeta = {};`) — arrays are pushed into it per gate key in Step 4 below.

- [ ] **Step 3: Add gold lock CSS for reporting-gated cards**

Find the `.lock-hint` CSS rule at line ~152:
```css
.lock-hint {
  font-size: 11px; color: var(--muted2);
  display: flex; align-items: center; gap: 4px;
  white-space: nowrap; flex-shrink: 0;
}
```

Add the modifier rule immediately after it:
```css
.tool-card.locked--reporting .lock-hint {
  color: var(--amber);
}
```

- [ ] **Step 4: Update `cardHtml()` to handle `reportingOnly` tools**

Find `cardHtml(tool)` inside `loadTools()` at line ~565. The current function handles `financeOnly` then falls through to live/coming-soon. Add a `reportingOnly` branch immediately after the `financeOnly` block:

```js
function cardHtml(tool) {
  const perms = tool.permissions || [];

  if (tool.financeOnly) {
    const meta = {
      path: tool.path, iconBg: tool.iconBg, icon: tool.icon,
      status: tool.status, name: tool.name, desc: tool.description,
      perms, betaNote: tool.betaNote || "",
    };
    if (!_gateCardMeta["finance"]) _gateCardMeta["finance"] = [];
    _gateCardMeta["finance"].push(meta);
    return buildLockedCard({ gateKey: "finance", ...meta });
  }

  if (tool.reportingOnly) {
    const meta = {
      path: tool.path, iconBg: tool.iconBg, icon: tool.icon,
      status: tool.status, name: tool.name, desc: tool.description,
      perms, betaNote: tool.betaNote || "",
    };
    if (!_gateCardMeta["reporting"]) _gateCardMeta["reporting"] = [];
    _gateCardMeta["reporting"].push(meta);
    return buildLockedCard({ gateKey: "reporting", ...meta });
  }

  if (clickable.includes(tool.status) && tool.path) {
    return buildLiveCard({
      path: tool.path, accent: tool.accent, iconBg: tool.iconBg,
      icon: tool.icon, status: tool.status, name: tool.name,
      desc: tool.description, betaNote: tool.betaNote || "",
    });
  }

  const overlayLabel = tool.status === "deprecated" ? "Deprecated"
    : tool.status === "in-development" ? "In Development"
    : "Coming Soon";
  return `<div class="tool-card no-hover" style="--icon-bg:${tool.iconBg}">
    ${ribbonHtml(tool.status)}
    <div class="tool-icon">${tool.icon}</div>
    <div class="tool-name">${tool.name}</div>
    <div class="tool-desc">${tool.description}</div>
    <div class="tool-overlay">
      <div class="tool-overlay-pill">${overlayLabel}</div>
    </div>
  </div>`;
}
```

- [ ] **Step 5: Verify in browser**

Open `index.html` in a browser (serve from repo root — e.g. `npx serve .` then open `http://localhost:3000`).

Expected before sign-in:
- M365 License Audit, MFA Status Report, Guest Access Audit cards show as locked with **gold** lock icon in the name row
- License Spend card shows locked with the default muted lock (unchanged)
- Group Import and Name Resolver cards are live (clickable)

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat: add reporting+GSD gates to hub, gold lock styling for reporting cards"
```

---

## Task 3: Hub — access badges in topbar

**Files:**
- Modify: `index.html` (hub)

After sign-in, users who hold Finance View, Reporting View, or GSD Access see corresponding badge pills in the hub topbar.

- [ ] **Step 1: Add badge HTML to hub topbar**

Find the `hub-topbar-right` div at line ~247. Add badge HTML between the GitHub link and the user-chip:

```html
    <!-- Access badges — shown after gate checks -->
    <div id="hubBadges" style="display:none;align-items:center;gap:6px"></div>
```

Full updated `hub-topbar-right`:
```html
  <div class="hub-topbar-right">
    <button class="btn-icon" onclick="toggleTheme()" title="Toggle theme">
      <svg id="themeIcon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="15" height="15"></svg>
    </button>
    <a href="https://github.com/jgdev-ch/it-tools" target="_blank" class="btn-icon" title="GitHub repository">
      <svg viewBox="0 0 24 24" fill="currentColor" width="15" height="15">
        <path d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"/>
      </svg>
    </a>

    <!-- Access badges — shown after gate checks -->
    <div id="hubBadges" style="display:none;align-items:center;gap:6px"></div>

    <!-- User chip — visible after sign-in -->
    <div class="user-chip" id="userChip">
      <div class="user-avatar" id="userInitials"></div>
      <span id="userName"></span>
    </div>

    <!-- Sign out — visible after sign-in -->
    <button class="btn-signout" id="signOutBtn" onclick="hubSignOut()">Sign out</button>

    <!-- Sign in — visible when signed out -->
    <button class="btn-signin" id="signInBtn" onclick="hubSignIn()">
      <svg viewBox="0 0 21 21" width="13" height="13" fill="none">
        <rect x="1"  y="1"  width="9" height="9" fill="#f25022"/>
        <rect x="11" y="1"  width="9" height="9" fill="#7fba00"/>
        <rect x="1"  y="11" width="9" height="9" fill="#00a4ef"/>
        <rect x="11" y="11" width="9" height="9" fill="#ffb900"/>
      </svg>
      Sign in
    </button>
  </div>
```

- [ ] **Step 2: Add hub badge CSS**

Add the following CSS near the other topbar styles (around line ~30, before or after `.hub-brand`):

```css
/* ── Hub access badges ── */
.hub-access-badge {
  display: inline-flex; align-items: center; gap: 4px;
  padding: 2px 8px; border-radius: 20px;
  font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em;
}
.hub-access-badge--amber {
  background: var(--amber-light); border: 1px solid var(--amber-border); color: var(--amber);
}
.hub-access-badge--blue {
  background: var(--blue-light); border: 1px solid var(--blue-border); color: var(--blue-dark);
}
```

- [ ] **Step 3: Add `renderHubBadges()` function**

Add this function near `runGateChecks()` (around line ~461):

```js
function renderHubBadges(unlockedGates) {
  const BADGE_DEFS = {
    finance: {
      label: "Finance View",
      cls:   "hub-access-badge--amber",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>`,
    },
    reporting: {
      label: "Reporting View",
      cls:   "hub-access-badge--blue",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>`,
    },
    gsd: {
      label: "GSD Access",
      cls:   "hub-access-badge--blue",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>`,
    },
  };
  const container = document.getElementById("hubBadges");
  const html = unlockedGates
    .filter(k => BADGE_DEFS[k])
    .map(k => `<span class="hub-access-badge ${BADGE_DEFS[k].cls}">${BADGE_DEFS[k].icon} ${BADGE_DEFS[k].label}</span>`)
    .join("");
  if (!html) { container.style.display = "none"; return; }
  container.innerHTML = html;
  container.style.display = "flex";
}
```

- [ ] **Step 4: Update `runGateChecks()` to call `renderHubBadges()`**

Find `runGateChecks()` at line ~461:
```js
async function runGateChecks(token) {
  for (const [gateKey, gate] of Object.entries(GROUP_GATES)) {
    const isMember = await checkMembership(token, gate.id);
    if (isMember) {
      localStorage.setItem(gate.localKey, "true");
      unlockCard(gateKey);
    }
  }
}
```

Replace with:
```js
async function runGateChecks(token) {
  const unlocked = [];
  for (const [gateKey, gate] of Object.entries(GROUP_GATES)) {
    const isMember = await checkMembership(token, gate.id);
    if (isMember) {
      localStorage.setItem(gate.localKey, "true");
      unlockCard(gateKey);
      unlocked.push(gateKey);
    }
  }
  renderHubBadges(unlocked);
}
```

- [ ] **Step 5: Clear badges on sign-out**

Find `showSignedOut()` (the function that hides the user chip after sign-out). Add badge clearing to it:

```js
document.getElementById("hubBadges").style.display = "none";
document.getElementById("hubBadges").innerHTML = "";
```

Search for `showSignedOut` to find the exact function. Add both lines inside it.

- [ ] **Step 6: Verify in browser**

Sign in as a user in `SG-IT-Tools-Finance-View`. After sign-in, the hub topbar should show a **Finance View** amber badge. Sign out — badge disappears. A user in no groups should see no badges.

Note: Reporting View and GSD badges won't show until real Object IDs are substituted.

- [ ] **Step 7: Commit**

```bash
git add index.html
git commit -m "feat: add access badges to hub topbar after gate checks"
```

---

## Task 4: License Audit — reporting gate enforcement + badges

**Files:**
- Modify: `tools/license-audit/index.html`

License Audit already has Finance View and License Admin checks. This task adds Reporting View enforcement (full access denial if not a member), a Reporting View badge, and a GSD badge.

- [ ] **Step 1: Add group ID constants and state flags**

Find the existing group constants near line ~500:
```js
const FINANCE_GROUP = "SG-IT-Tools-Finance-View";
let _hasFinanceAccess = false;

const LICENSE_MODIFY_GROUP = "SG-IT-Tools-License-Modify";
let _hasLicenseModifyAccess = false;
```

Add immediately after:
```js
const REPORTING_GROUP_ID = "<SG-IT-Tools-Reporting-View Object ID>";
const GSD_GROUP_ID       = "<SG-IT-Tools-GSD Object ID>";
let _hasReportingAccess  = false;
let _hasGsdAccess        = false;
```

- [ ] **Step 2: Add `checkReportingAndGsdAccess()` function**

Add this function immediately after the existing `checkLicenseModifyAccess()` function:

```js
async function checkReportingAndGsdAccess() {
  try {
    const token = await ITTools.auth.getToken();
    const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ ids: [REPORTING_GROUP_ID, GSD_GROUP_ID] }),
    });
    if (!res.ok) { _hasReportingAccess = false; _hasGsdAccess = false; return; }
    const data = await res.json();
    const members = data.value || [];
    _hasReportingAccess = members.includes(REPORTING_GROUP_ID);
    _hasGsdAccess       = members.includes(GSD_GROUP_ID);
  } catch (_) {
    _hasReportingAccess = false;
    _hasGsdAccess       = false;
  }
}
```

- [ ] **Step 3: Add access-denied screen HTML**

Find `<div id="authScreen"` in the file. Add the reporting-denied screen immediately after the closing `</div>` of `#authScreen`:

```html
<div id="reportingDeniedScreen" class="auth-screen" style="display:none">
  <div class="auth-card">
    <div style="width:44px;height:44px;background:var(--amber-light);border-radius:11px;display:flex;align-items:center;justify-content:center;margin:0 auto 1.25rem"><svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--amber)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg></div>
    <h1>M365 License Audit</h1>
    <p>Reporting View access is required to use this tool. Contact your IT administrator to request access.</p>
    <a href="../../" class="btn-ms" style="display:inline-flex;align-items:center;gap:8px;text-decoration:none">Back to IT Tools Hub</a>
  </div>
</div>
```

- [ ] **Step 4: Add Reporting View and GSD badge HTML**

Find the existing badge spans at line ~263:
```html
        <span class="finance-badge" id="financeIndicator">...</span>
        <span class="license-admin-badge" id="licenseAdminIndicator">...</span>
```

Add two more spans immediately after `licenseAdminIndicator`:
```html
        <span class="reporting-badge" id="reportingViewIndicator"><svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg> Reporting View</span>
        <span class="gsd-badge" id="gsdIndicator"><svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg> GSD Access</span>
```

- [ ] **Step 5: Add CSS for the two new badges**

Find the `.license-admin-badge` CSS block at line ~31. Add immediately after it:

```css
  /* ── Reporting View badge ── */
  .reporting-badge {
    display: none; align-items: center; gap: 5px;
    background: var(--blue-light); border: 1px solid var(--blue-border);
    color: var(--blue-dark); border-radius: 20px;
    padding: 3px 10px; font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .04em;
  }

  /* ── GSD Access badge ── */
  .gsd-badge {
    display: none; align-items: center; gap: 5px;
    background: var(--blue-light); border: 1px solid var(--blue-border);
    color: var(--blue-dark); border-radius: 20px;
    padding: 3px 10px; font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .04em;
  }
```

- [ ] **Step 6: Update `onSignIn` to enforce reporting gate and show badges**

Find the `onSignIn` callback in the `ITTools.auth.init()` call. It currently looks like:
```js
onSignIn: async acct => {
  _sessionFound = true;
  document.getElementById("authScreen").style.display = "none";
  document.getElementById("appScreen").style.display  = "block";
  ITTools.ui.setUser(acct);
  await Promise.all([checkFinanceAccess(), checkLicenseModifyAccess(), loadSkus(), loadCosts()]);
  if (_hasFinanceAccess) {
    document.getElementById("financeIndicator").style.display = "inline-flex";
    rebuildDropdown();
  }
  if (_hasLicenseModifyAccess) {
    document.getElementById("licenseAdminIndicator").style.display = "inline-flex";
  }
},
```

Replace with:
```js
onSignIn: async acct => {
  _sessionFound = true;
  document.getElementById("authScreen").style.display = "none";
  ITTools.ui.setUser(acct);
  await Promise.all([checkFinanceAccess(), checkLicenseModifyAccess(), checkReportingAndGsdAccess(), loadSkus(), loadCosts()]);
  if (!_hasReportingAccess) {
    document.getElementById("reportingDeniedScreen").style.display = "flex";
    return;
  }
  document.getElementById("appScreen").style.display = "block";
  document.getElementById("reportingViewIndicator").style.display = "inline-flex";
  if (_hasFinanceAccess) {
    document.getElementById("financeIndicator").style.display = "inline-flex";
    rebuildDropdown();
  }
  if (_hasLicenseModifyAccess) {
    document.getElementById("licenseAdminIndicator").style.display = "inline-flex";
  }
  if (_hasGsdAccess) {
    document.getElementById("gsdIndicator").style.display = "inline-flex";
  }
},
```

- [ ] **Step 7: Verify in browser**

Open `tools/license-audit/index.html`. Sign in as a user **without** `SG-IT-Tools-Reporting-View` — should see the access-denied screen with "Back to IT Tools Hub" link. Sign in as a user **with** the group — should reach the audit UI with the Reporting View blue badge visible in the page header.

Note: placeholder Object IDs mean the check always returns `false` until real IDs are substituted.

- [ ] **Step 8: Commit**

```bash
git add tools/license-audit/index.html
git commit -m "feat: reporting gate enforcement and badges in license-audit"
```

---

## Task 5: MFA Status Report — reporting gate enforcement + badges

**Files:**
- Modify: `tools/mfa-status/index.html`

MFA Status currently has no group checks. This task adds reporting gate enforcement and Reporting View + GSD badges using the same pattern as Task 4.

- [ ] **Step 1: Add group ID constants**

Find the `<script>` block near the bottom of the file (before `ITTools.auth.init()`). Add at the top of the script block:

```js
const REPORTING_GROUP_ID = "<SG-IT-Tools-Reporting-View Object ID>";
const GSD_GROUP_ID       = "<SG-IT-Tools-GSD Object ID>";
let _hasReportingAccess  = false;
let _hasGsdAccess        = false;
```

- [ ] **Step 2: Add `checkReportingAndGsdAccess()` function**

Add immediately after the constants:

```js
async function checkReportingAndGsdAccess() {
  try {
    const token = await ITTools.auth.getToken();
    const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ ids: [REPORTING_GROUP_ID, GSD_GROUP_ID] }),
    });
    if (!res.ok) { _hasReportingAccess = false; _hasGsdAccess = false; return; }
    const data = await res.json();
    const members = data.value || [];
    _hasReportingAccess = members.includes(REPORTING_GROUP_ID);
    _hasGsdAccess       = members.includes(GSD_GROUP_ID);
  } catch (_) {
    _hasReportingAccess = false;
    _hasGsdAccess       = false;
  }
}
```

- [ ] **Step 3: Add access-denied screen HTML**

Find `<div id="authScreen"` in the file. Add the reporting-denied screen immediately after the closing `</div>` of `#authScreen`:

```html
<div id="reportingDeniedScreen" class="auth-screen" style="display:none">
  <div class="auth-card">
    <div style="width:44px;height:44px;background:var(--amber-light);border-radius:11px;display:flex;align-items:center;justify-content:center;margin:0 auto 1.25rem"><svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--amber)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg></div>
    <h1>MFA Status Report</h1>
    <p>Reporting View access is required to use this tool. Contact your IT administrator to request access.</p>
    <a href="../../" class="btn-ms" style="display:inline-flex;align-items:center;gap:8px;text-decoration:none">Back to IT Tools Hub</a>
  </div>
</div>
```

- [ ] **Step 4: Add badge HTML inside the app screen page header**

Find the app screen page header at line ~140:
```html
    <div class="page-header">
      <h1>MFA Status Report</h1>
      <p>Audit MFA registration across your tenant...</p>
    </div>
```

Replace with:
```html
    <div class="page-header">
      <div style="display:flex;align-items:center;gap:10px;margin-bottom:4px">
        <h1 style="margin-bottom:0">MFA Status Report</h1>
        <span class="reporting-badge" id="reportingViewIndicator"><svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg> Reporting View</span>
        <span class="gsd-badge" id="gsdIndicator"><svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg> GSD Access</span>
      </div>
      <p>Audit MFA registration across your tenant. Flag users with weak or missing authentication methods.</p>
    </div>
```

- [ ] **Step 5: Add badge CSS**

Find the `<style>` block at the top of the file (around line ~10). Add before the closing `</style>`:

```css
  .reporting-badge {
    display: none; align-items: center; gap: 5px;
    background: var(--blue-light); border: 1px solid var(--blue-border);
    color: var(--blue-dark); border-radius: 20px;
    padding: 3px 10px; font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .04em;
  }
  .gsd-badge {
    display: none; align-items: center; gap: 5px;
    background: var(--blue-light); border: 1px solid var(--blue-border);
    color: var(--blue-dark); border-radius: 20px;
    padding: 3px 10px; font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .04em;
  }
```

- [ ] **Step 6: Update `onSignIn` to enforce reporting gate and show badges**

Find the `onSignIn` callback. It currently looks like:
```js
onSignIn: acct => {
  _sessionFound = true;
  document.getElementById("authScreen").style.display = "none";
  document.getElementById("appScreen").style.display  = "block";
  ITTools.ui.setUser(acct);
},
```

Replace with:
```js
onSignIn: async acct => {
  _sessionFound = true;
  document.getElementById("authScreen").style.display = "none";
  ITTools.ui.setUser(acct);
  await checkReportingAndGsdAccess();
  if (!_hasReportingAccess) {
    document.getElementById("reportingDeniedScreen").style.display = "flex";
    return;
  }
  document.getElementById("appScreen").style.display = "block";
  document.getElementById("reportingViewIndicator").style.display = "inline-flex";
  if (_hasGsdAccess) {
    document.getElementById("gsdIndicator").style.display = "inline-flex";
  }
},
```

- [ ] **Step 7: Verify in browser**

Open `tools/mfa-status/index.html`. Sign in — with placeholder IDs the gate blocks access showing denied screen. Temporarily hardcode `_hasReportingAccess = true` after `await checkReportingAndGsdAccess()` to verify the badge layout renders correctly in the page header. Remove the hardcode before committing.

- [ ] **Step 8: Commit**

```bash
git add tools/mfa-status/index.html
git commit -m "feat: reporting gate enforcement and badges in mfa-status"
```

---

## Task 6: Guest Audit — reporting gate enforcement + badges

**Files:**
- Modify: `tools/guest-audit/index.html`

Identical pattern to Task 5. Guest Audit's `onSignIn` and page header structure are the same as MFA Status Report.

- [ ] **Step 1: Add group ID constants**

Find the `<script>` block. Add at the top:

```js
const REPORTING_GROUP_ID = "<SG-IT-Tools-Reporting-View Object ID>";
const GSD_GROUP_ID       = "<SG-IT-Tools-GSD Object ID>";
let _hasReportingAccess  = false;
let _hasGsdAccess        = false;
```

- [ ] **Step 2: Add `checkReportingAndGsdAccess()` function**

Add immediately after the constants (identical to Task 5 Step 2):

```js
async function checkReportingAndGsdAccess() {
  try {
    const token = await ITTools.auth.getToken();
    const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ ids: [REPORTING_GROUP_ID, GSD_GROUP_ID] }),
    });
    if (!res.ok) { _hasReportingAccess = false; _hasGsdAccess = false; return; }
    const data = await res.json();
    const members = data.value || [];
    _hasReportingAccess = members.includes(REPORTING_GROUP_ID);
    _hasGsdAccess       = members.includes(GSD_GROUP_ID);
  } catch (_) {
    _hasReportingAccess = false;
    _hasGsdAccess       = false;
  }
}
```

- [ ] **Step 3: Add access-denied screen HTML**

Find `<div id="authScreen"`. Add immediately after the closing `</div>` of `#authScreen`:

```html
<div id="reportingDeniedScreen" class="auth-screen" style="display:none">
  <div class="auth-card">
    <div style="width:44px;height:44px;background:var(--amber-light);border-radius:11px;display:flex;align-items:center;justify-content:center;margin:0 auto 1.25rem"><svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--amber)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg></div>
    <h1>Guest Access Audit</h1>
    <p>Reporting View access is required to use this tool. Contact your IT administrator to request access.</p>
    <a href="../../" class="btn-ms" style="display:inline-flex;align-items:center;gap:8px;text-decoration:none">Back to IT Tools Hub</a>
  </div>
</div>
```

- [ ] **Step 4: Add badge HTML inside the app screen page header**

Find the app screen page header at line ~232:
```html
    <div class="page-header">
      <h1>Guest Access Audit</h1>
```

Replace with:
```html
    <div class="page-header">
      <div style="display:flex;align-items:center;gap:10px;margin-bottom:4px">
        <h1 style="margin-bottom:0">Guest Access Audit</h1>
        <span class="reporting-badge" id="reportingViewIndicator"><svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg> Reporting View</span>
        <span class="gsd-badge" id="gsdIndicator"><svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg> GSD Access</span>
      </div>
```

Also find and keep the existing `<p>` description line from the page header, placing it after the new `</div>`.

- [ ] **Step 5: Add badge CSS**

Find the `<style>` block. Add before `</style>`:

```css
  .reporting-badge {
    display: none; align-items: center; gap: 5px;
    background: var(--blue-light); border: 1px solid var(--blue-border);
    color: var(--blue-dark); border-radius: 20px;
    padding: 3px 10px; font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .04em;
  }
  .gsd-badge {
    display: none; align-items: center; gap: 5px;
    background: var(--blue-light); border: 1px solid var(--blue-border);
    color: var(--blue-dark); border-radius: 20px;
    padding: 3px 10px; font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .04em;
  }
```

- [ ] **Step 6: Update `onSignIn`**

Find the `onSignIn` callback. Replace:
```js
onSignIn: acct => {
  _sessionFound = true;
  document.getElementById("authScreen").style.display = "none";
  document.getElementById("appScreen").style.display  = "block";
  ITTools.ui.setUser(acct);
},
```

With:
```js
onSignIn: async acct => {
  _sessionFound = true;
  document.getElementById("authScreen").style.display = "none";
  ITTools.ui.setUser(acct);
  await checkReportingAndGsdAccess();
  if (!_hasReportingAccess) {
    document.getElementById("reportingDeniedScreen").style.display = "flex";
    return;
  }
  document.getElementById("appScreen").style.display = "block";
  document.getElementById("reportingViewIndicator").style.display = "inline-flex";
  if (_hasGsdAccess) {
    document.getElementById("gsdIndicator").style.display = "inline-flex";
  }
},
```

- [ ] **Step 7: Verify in browser**

Open `tools/guest-audit/index.html`. Same verification as Task 5 Step 7 — temporarily force `_hasReportingAccess = true` to check badge layout, then remove.

- [ ] **Step 8: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat: reporting gate enforcement and badges in guest-audit"
```

---

## Task 7: Group Import — GSD badge only

**Files:**
- Modify: `tools/group-import/index.html`

Group Import is ungated — open to all signed-in users. This task adds a GSD Access badge that appears for GSD members.

- [ ] **Step 1: Add GSD group ID constant**

Find the `<script>` block. Add at the top:

```js
const GSD_GROUP_ID = "<SG-IT-Tools-GSD Object ID>";
let _hasGsdAccess  = false;
```

- [ ] **Step 2: Add `checkGsdAccess()` function**

Add immediately after the constant:

```js
async function checkGsdAccess() {
  try {
    const token = await ITTools.auth.getToken();
    const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ ids: [GSD_GROUP_ID] }),
    });
    if (!res.ok) { _hasGsdAccess = false; return; }
    const data = await res.json();
    _hasGsdAccess = (data.value || []).includes(GSD_GROUP_ID);
  } catch (_) {
    _hasGsdAccess = false;
  }
}
```

- [ ] **Step 3: Add GSD badge HTML**

Group Import uses a sidebar layout — there is no `page-header` div with an h1. Instead, add the badge in the topbar area. Find `<div id="topbar"></div>` and add a badge container immediately after it:

```html
<div id="topbar"></div>
<div id="gsdBadgeBar" style="display:none;padding:6px 1.25rem 0;align-items:center;gap:6px">
  <span class="gsd-badge" id="gsdIndicator"><svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg> GSD Access</span>
</div>
```

- [ ] **Step 4: Add GSD badge CSS**

Find the `<style>` block. Add before `</style>`:

```css
  .gsd-badge {
    display: inline-flex; align-items: center; gap: 5px;
    background: var(--blue-light); border: 1px solid var(--blue-border);
    color: var(--blue-dark); border-radius: 20px;
    padding: 3px 10px; font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .04em;
  }
```

Note: `.gsd-badge` uses `display: inline-flex` here (not `none`) because visibility is controlled by the parent `#gsdBadgeBar` container.

- [ ] **Step 5: Update `onSignIn` to call `checkGsdAccess()` and show badge**

Find `onSignIn` callback:
```js
onSignIn: acct => {
  _sessionFound = true;
  document.getElementById("authScreen").style.display = "none";
  document.getElementById("appScreen").style.display  = "block";
  ITTools.ui.setUser(acct);
},
```

Replace with:
```js
onSignIn: async acct => {
  _sessionFound = true;
  document.getElementById("authScreen").style.display = "none";
  document.getElementById("appScreen").style.display  = "block";
  ITTools.ui.setUser(acct);
  await checkGsdAccess();
  if (_hasGsdAccess) {
    document.getElementById("gsdBadgeBar").style.display = "flex";
  }
},
```

- [ ] **Step 6: Verify in browser**

Open `tools/group-import/index.html`. Sign in — tool loads normally. Temporarily force `_hasGsdAccess = true` after `await checkGsdAccess()` to verify the GSD badge bar renders. Remove the hardcode before committing.

- [ ] **Step 7: Commit**

```bash
git add tools/group-import/index.html
git commit -m "feat: GSD Access badge in group-import"
```

---

## Task 8: Name Resolver — GSD badge only

**Files:**
- Modify: `tools/name-resolver/index.html`

Identical pattern to Task 7.

- [ ] **Step 1: Add GSD group ID constant**

Find the `<script>` block. Add at the top:

```js
const GSD_GROUP_ID = "<SG-IT-Tools-GSD Object ID>";
let _hasGsdAccess  = false;
```

- [ ] **Step 2: Add `checkGsdAccess()` function**

Add immediately after the constant (identical to Task 7 Step 2):

```js
async function checkGsdAccess() {
  try {
    const token = await ITTools.auth.getToken();
    const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ ids: [GSD_GROUP_ID] }),
    });
    if (!res.ok) { _hasGsdAccess = false; return; }
    const data = await res.json();
    _hasGsdAccess = (data.value || []).includes(GSD_GROUP_ID);
  } catch (_) {
    _hasGsdAccess = false;
  }
}
```

- [ ] **Step 3: Add GSD badge HTML**

Name Resolver also uses a sidebar layout. Find `<div id="topbar"></div>` at line 147. Add a badge container immediately after it:

```html
<div id="topbar"></div>
<div id="gsdBadgeBar" style="display:none;padding:6px 1.25rem 0;align-items:center;gap:6px">
  <span class="gsd-badge" id="gsdIndicator"><svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg> GSD Access</span>
</div>
```

- [ ] **Step 4: Add GSD badge CSS**

Find the `<style>` block. Add before `</style>`:

```css
  .gsd-badge {
    display: inline-flex; align-items: center; gap: 5px;
    background: var(--blue-light); border: 1px solid var(--blue-border);
    color: var(--blue-dark); border-radius: 20px;
    padding: 3px 10px; font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .04em;
  }
```

- [ ] **Step 5: Update `onSignIn`**

Find the `onSignIn` callback:
```js
onSignIn: acct => {
  _sessionFound = true;
  document.getElementById("authScreen").style.display = "none";
  document.getElementById("appScreen").style.display  = "block";
  ITTools.ui.setUser(acct);
  document.body.style.opacity = "1";
},
```

Replace with:
```js
onSignIn: async acct => {
  _sessionFound = true;
  document.getElementById("authScreen").style.display = "none";
  document.getElementById("appScreen").style.display  = "block";
  ITTools.ui.setUser(acct);
  document.body.style.opacity = "1";
  await checkGsdAccess();
  if (_hasGsdAccess) {
    document.getElementById("gsdBadgeBar").style.display = "flex";
  }
},
```

- [ ] **Step 6: Verify in browser**

Open `tools/name-resolver/index.html`. Sign in — tool loads normally. Temporarily force `_hasGsdAccess = true` after `await checkGsdAccess()` to verify the GSD badge bar renders. Remove before committing.

- [ ] **Step 7: Commit**

```bash
git add tools/name-resolver/index.html
git commit -m "feat: GSD Access badge in name-resolver"
```

---

## Final verification checklist

Before pushing to testing:

- [ ] Hub: 3 reporting-audit cards (License Audit, MFA Status, Guest Audit) show locked with **gold** lock icon
- [ ] Hub: License Spend card shows locked with default muted lock (unchanged)
- [ ] Hub: Group Import and Name Resolver are live/clickable
- [ ] Hub: Finance View badge appears after sign-in for Finance group members
- [ ] License Audit: users without reporting access see access-denied screen; users with access see Reporting View badge in page header
- [ ] MFA Status + Guest Audit: same access-denied / badge behavior
- [ ] Group Import + Name Resolver: GSD badge bar visible for GSD members; non-GSD users see no badge
- [ ] Sign-out clears all hub badges and re-locks reporting cards
