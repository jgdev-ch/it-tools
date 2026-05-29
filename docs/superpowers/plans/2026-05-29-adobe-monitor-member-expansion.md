# Adobe License Monitor — Member Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an expandable member table to each product card so technicians can see who is in each Adobe Entra group, identify disabled accounts, and remove members directly from the tool.

**Architecture:** All changes are in `tools/adobe-license-monitor/index.html`. New CSS rows in the product card use `grid-column: 1 / -1` to span all three columns. Member data loads on-demand on first expand and is cached per card in `_memberCache`. The remove flow uses `DELETE /groups/{id}/members/{userId}/$ref` and is gated behind `SG-IT-Tools-License-Modify`.

**Tech Stack:** Vanilla JS, Microsoft Graph API, existing `shared/auth.js` helpers (`ITTools.auth.getToken`, `ITTools.graph.friendlyError`, `ITTools.ui.withButtonSpinner`), CSS Grid.

**Spec:** `docs/superpowers/specs/2026-05-29-adobe-monitor-member-expansion-design.md`

---

## Task 1: Scope declaration + shell width + all new CSS

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

- [ ] **Step 1: Update TOOL_SCOPES**

Find this line (around line 206):
```js
const TOOL_SCOPES = ["User.Read", "GroupMember.Read.All"];
```
Replace with:
```js
const TOOL_SCOPES = [
  "User.Read",
  "User.Read.All",
  "AuditLog.Read.All",
  "GroupMember.Read.All",
  "GroupMember.ReadWrite.All",
];
```

- [ ] **Step 2: Widen the shell**

Find:
```css
  .shell { max-width: 860px; margin: 0 auto; padding: 1.75rem 1.25rem; }
```
Replace with:
```css
  .shell { max-width: 1200px; margin: 0 auto; padding: 1.75rem 1.25rem; }
```

- [ ] **Step 3: Add all new CSS to the `<style>` block, immediately before the closing `</style>` tag**

```css
  /* ── Expand strip ── */
  .expand-strip {
    grid-column: 1 / -1;
    border-top: 1px solid var(--border);
    display: flex; align-items: center; justify-content: space-between;
    padding: 8px 18px; background: var(--surface2);
    cursor: pointer; transition: background .15s; user-select: none;
  }
  .expand-strip:hover { background: var(--surface3); }
  .expand-strip.open  { background: var(--blue-light); border-top-color: var(--blue-border); }
  .expand-strip-left  { display: flex; align-items: center; gap: 8px; font-size: 12px; font-weight: 600; color: var(--muted); }
  .expand-strip.open .expand-strip-left { color: var(--blue-dark); }
  .expand-strip-right { display: flex; align-items: center; gap: 6px; font-size: 11px; color: var(--muted2); }
  .expand-chevron { font-size: 12px; color: var(--muted2); transition: transform .2s; display: inline-block; }
  .expand-chevron.open { transform: rotate(180deg); }

  /* Disabled count badge on strip */
  .dis-badge {
    display: none; align-items: center; gap: 4px;
    background: var(--red-light); color: var(--red); border: 1px solid var(--red-border);
    border-radius: 20px; padding: 2px 9px; font-size: 11px; font-weight: 700;
  }
  .dis-badge.show { display: inline-flex; }

  /* ── Member section ── */
  .member-section { grid-column: 1 / -1; border-top: 1px solid var(--border); }
  .member-tbl-wrap { max-height: 360px; overflow-y: auto; }

  /* Member table */
  .member-tbl { width: 100%; border-collapse: collapse; font-size: 12px; }
  .member-tbl thead th {
    position: sticky; top: 0; z-index: 2;
    padding: 9px 14px; text-align: left;
    font-size: 10px; font-weight: 700; text-transform: uppercase;
    letter-spacing: .07em; color: var(--muted);
    background: var(--surface2); border-bottom: 1px solid var(--border);
    white-space: nowrap; cursor: pointer; user-select: none;
  }
  .member-tbl thead th:hover { background: var(--surface3); }
  .member-tbl thead th .sort-icon { margin-left: 4px; opacity: .4; font-size: 10px; }
  .member-tbl thead th.sorted .sort-icon { opacity: 1; }
  .member-tbl tbody td {
    padding: 10px 14px; border-bottom: 1px solid var(--border); vertical-align: middle;
  }
  .member-tbl tbody tr:last-child td { border-bottom: none; }
  .member-tbl tbody tr:hover td { background: var(--surface2); }

  /* Disabled row */
  .member-tbl tbody tr.row-disabled td { background: rgba(138,36,36,.04); }
  .member-tbl tbody tr.row-disabled:hover td { background: rgba(138,36,36,.08); }

  /* User cell */
  .mem-user-cell { display: flex; align-items: center; gap: 10px; }
  .mem-avatar {
    width: 28px; height: 28px; border-radius: 50%; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center;
    font-size: 10px; font-weight: 700;
  }
  .mem-avatar.enabled  { background: var(--blue-light);  color: var(--blue-dark); }
  .mem-avatar.disabled { background: var(--red-light);   color: var(--red); }
  .mem-name { font-size: 12px; font-weight: 600; }

  /* Status badges */
  .mem-badge {
    display: inline-flex; align-items: center; gap: 3px;
    padding: 2px 8px; border-radius: 20px;
    font-size: 10px; font-weight: 700; white-space: nowrap;
  }
  .mem-badge.enabled  { background: var(--green-light); color: var(--green); border: 1px solid var(--green-border); }
  .mem-badge.disabled { background: var(--red-light);   color: var(--red);   border: 1px solid var(--red-border); }

  /* Last sign-in — red when > 30 days */
  .signin-stale { color: var(--red); font-weight: 600; }

  /* Remove button */
  .btn-mem-remove {
    padding: 4px 11px; border-radius: var(--radius-sm);
    background: transparent; border: 1px solid var(--red-border);
    color: var(--red); font-size: 11px; font-weight: 600;
    cursor: pointer; font-family: inherit; transition: all .15s; white-space: nowrap;
  }
  .btn-mem-remove:hover { background: var(--red-light); }
  .btn-mem-remove.gated {
    border-color: var(--border); color: var(--muted2);
    cursor: not-allowed; opacity: .5;
  }

  /* Table footer */
  .member-footer {
    display: flex; align-items: center; justify-content: space-between;
    padding: 9px 14px; background: var(--surface2);
    border-top: 1px solid var(--border);
    font-size: 11px; color: var(--muted2);
  }
  .license-admin-pill {
    display: inline-flex; align-items: center; gap: 4px;
    background: var(--blue-light); color: var(--blue-dark);
    border: 1px solid var(--blue-border); border-radius: 20px;
    padding: 2px 9px; font-size: 10px; font-weight: 700;
    margin-right: 5px;
  }

  /* Member shimmer skeleton */
  .member-skeleton { padding: 12px 14px; }
  .mem-skel-row { display: flex; align-items: center; gap: 12px; margin-bottom: 12px; }
  .mem-skel-avatar { width: 28px; height: 28px; border-radius: 50%; background: var(--surface3); flex-shrink: 0; animation: hub-shimmer 1.5s infinite; }
  .mem-skel-line { height: 12px; border-radius: 6px; background: var(--surface3); animation: hub-shimmer 1.5s infinite; }

  /* Member load error */
  .member-error {
    padding: 1rem 1.25rem; background: var(--red-light);
    border: 1px solid var(--red-border); color: var(--red);
    font-size: 13px; display: flex; align-items: center; gap: 10px;
  }
  .btn-mem-retry {
    padding: 4px 12px; border-radius: var(--radius-sm);
    background: transparent; border: 1px solid var(--red-border);
    color: var(--red); font-size: 11px; font-weight: 600;
    cursor: pointer; font-family: inherit; white-space: nowrap;
  }
  .btn-mem-retry:hover { background: rgba(138,36,36,.1); }

  /* ── Remove confirmation modal ── */
  .remove-modal-overlay {
    position: fixed; inset: 0; background: rgba(28,25,23,.6);
    display: flex; align-items: center; justify-content: center;
    z-index: 1000; padding: 1rem;
    opacity: 0; pointer-events: none; transition: opacity .15s;
  }
  .remove-modal-overlay.show { opacity: 1; pointer-events: all; }
  .remove-modal-card {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: var(--radius); padding: 2rem; max-width: 440px; width: 100%;
    box-shadow: 0 20px 60px rgba(80,60,40,.22);
    transform: translateY(10px); transition: transform .15s;
  }
  .remove-modal-overlay.show .remove-modal-card { transform: translateY(0); }
  .remove-modal-icon {
    width: 44px; height: 44px; border-radius: 11px;
    background: var(--red-light); display: flex; align-items: center;
    justify-content: center; margin-bottom: 1rem;
  }
  .remove-modal-title { font-size: 17px; font-weight: 700; margin-bottom: 6px; }
  .remove-modal-body  { font-size: 13px; color: var(--muted); line-height: 1.6; margin-bottom: 1.25rem; }
  .remove-modal-user  {
    background: var(--surface2); border: 1px solid var(--border);
    border-radius: var(--radius-sm); padding: 10px 14px; margin-bottom: 1.25rem;
  }
  .remove-modal-name  { font-size: 13px; font-weight: 700; margin-bottom: 2px; }
  .remove-modal-upn   { font-size: 11px; color: var(--muted); margin-bottom: 6px; }
  .remove-modal-group { font-size: 11px; font-weight: 600; color: var(--amber); }
  .remove-modal-actions { display: flex; gap: 10px; justify-content: flex-end; }
  .btn-modal-cancel {
    padding: 9px 20px; border-radius: var(--radius-sm);
    background: transparent; border: 1px solid var(--border);
    font-size: 14px; font-weight: 600; cursor: pointer;
    font-family: inherit; color: var(--muted); transition: all .12s;
  }
  .btn-modal-cancel:hover { background: var(--surface2); }
  .btn-modal-confirm {
    padding: 9px 20px; border-radius: var(--radius-sm);
    background: var(--red); border: none; color: #fff;
    font-size: 14px; font-weight: 600; cursor: pointer;
    font-family: inherit; transition: opacity .12s;
  }
  .btn-modal-confirm:hover    { opacity: .88; }
  .btn-modal-confirm:disabled { opacity: .5; cursor: not-allowed; }
```

- [ ] **Step 4: Verify the page still loads and renders normally in the browser**

Open `tools/adobe-license-monitor/index.html` locally. Sign in. Three product cards should display exactly as before — no visual change yet, just wider shell.

- [ ] **Step 5: Commit**

```
git add tools/adobe-license-monitor/index.html
git commit -m "adobe-monitor: scope update, 1200px shell, member expansion CSS"
```

---

## Task 2: Card template — expand strip + member section + state globals

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

- [ ] **Step 1: Add state globals immediately before the `_getAdobeProducts` function**

Find `// ─── API ───` and insert above it:

```js
// ─── Member expansion state ───────────────────────────────────────────────────
const _memberCache   = {};    // { [idx]: { members: [], loaded: bool } }
const _sortState     = {};    // { [idx]: { col: string, dir: 1|-1 } }
let   _isLicenseAdmin = false;
let   _pendingRemove  = null; // { idx, userId, rowEl }

const LICENSE_MODIFY_GROUP = "d98cbaa9-da66-4d1a-8a31-2442b7cc0ca8";
```

- [ ] **Step 2: Update `renderCards` to append the expand strip and member section to each card**

Find the return template inside `renderCards`. It currently ends with:
```js
      </div>`;
  }).join("");
```

Replace the entire template string return with the version below. The only additions are the expand strip and member section divs — everything else inside the card is unchanged:

```js
    return `
      <div class="product-card" id="card-${r.groupId}">
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
          <div class="entra-big ${r.entra === null ? "na" : ""}" id="entra-big-${r.groupId}">${r.entra ?? "—"}</div>
          <div class="entra-sub">P-EID-SG-STD-SSO-Adobe_${r.name.replace(/ /g, "_")}</div>
          ${driftPill}
        </div>
        <div class="expand-strip" id="strip-${r.groupId}" onclick="toggleExpand('${r.groupId}', ${results.indexOf(r)})">
          <div class="expand-strip-left">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
            View <span id="mem-count-${r.groupId}">${r.entra ?? ""}</span> group members
            <span class="dis-badge" id="dis-${r.groupId}">
              <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
              <span id="dis-count-${r.groupId}">0</span> disabled
            </span>
          </div>
          <span class="expand-chevron" id="chev-${r.groupId}">▾</span>
        </div>
        <div class="member-section" id="ms-${r.groupId}" style="display:none"></div>
      </div>`;
```

Note: the `results.indexOf(r)` call works because `results` is in scope inside `renderCards`. The `idx` parameter passed to `toggleExpand` is the product's position in the `PRODUCTS` array (0, 1, or 2).

- [ ] **Step 3: Add `checkLicenseAdmin` call at the end of `loadDashboard`, after `render(results)`**

Find:
```js
    render(results);
    document.getElementById("statusText").textContent =
```

Insert between those two lines:
```js
    render(results);
    _checkLicenseAdmin();
    document.getElementById("statusText").textContent =
```

- [ ] **Step 4: Add the `_checkLicenseAdmin` function above `// ─── Auth ───`**

```js
async function _checkLicenseAdmin() {
  try {
    const token = await ITTools.auth.getToken();
    const res   = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
      method:  "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body:    JSON.stringify({ ids: [LICENSE_MODIFY_GROUP] }),
    });
    if (!res.ok) return;
    _isLicenseAdmin = (await res.json()).value?.includes(LICENSE_MODIFY_GROUP) ?? false;
  } catch (_) { _isLicenseAdmin = false; }
}
```

- [ ] **Step 5: Add the remove modal HTML inside `<div id="appScreen" ...>` immediately before `<div class="shell">`**

Find:
```html
<div id="appScreen" style="display:none">
  <div class="shell">
```

Insert between those two lines:
```html
<div id="appScreen" style="display:none">

<!-- Remove confirmation modal -->
<div class="remove-modal-overlay" id="removeModal" onclick="if(event.target===this)closeRemoveModal()">
  <div class="remove-modal-card">
    <div class="remove-modal-icon">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><line x1="18" y1="8" x2="23" y2="13"/><line x1="23" y1="8" x2="18" y2="13"/></svg>
    </div>
    <div class="remove-modal-title">Remove from group?</div>
    <div class="remove-modal-body">This will remove the member from the Entra security group. Adobe access will be revoked automatically via SSO provisioning.</div>
    <div class="remove-modal-user">
      <div class="remove-modal-name" id="modalName"></div>
      <div class="remove-modal-upn"  id="modalUpn"></div>
      <div class="remove-modal-group" id="modalGroup"></div>
    </div>
    <div class="remove-modal-actions">
      <button class="btn-modal-cancel" onclick="closeRemoveModal()">Cancel</button>
      <button class="btn-modal-confirm" id="modalConfirmBtn" onclick="executeRemove()">Remove from group</button>
    </div>
  </div>
</div>

  <div class="shell">
```

- [ ] **Step 6: Verify in browser — cards render with the expand strip visible at the bottom of each card, chevron on the right. Clicking the strip does nothing yet (toggleExpand not defined). No console errors.**

- [ ] **Step 7: Commit**

```
git add tools/adobe-license-monitor/index.html
git commit -m "adobe-monitor: expand strip in card template, state globals, license admin check, remove modal"
```

---

## Task 3: Graph functions — member fetch + sign-in enrichment

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

Add all three functions below into the `// ─── API ───` section, after `_getGroupCount`.

- [ ] **Step 1: Add `_fetchMembers` — paginates through group members**

```js
async function _fetchMembers(token, groupId) {
  const members = [];
  let url = `https://graph.microsoft.com/v1.0/groups/${groupId}/members` +
            `?$select=id,displayName,userPrincipalName,accountEnabled&$top=999`;
  while (url) {
    const res = await fetch(url, { headers: { Authorization: "Bearer " + token } });
    if (!res.ok) throw new Error(`Member fetch failed: ${res.status}`);
    const data = await res.json();
    members.push(...(data.value || []));
    url = data["@odata.nextLink"] ?? null;
  }
  return members;
}
```

- [ ] **Step 2: Add `_enrichSignIn` — fetches signInActivity in batches of 15**

```js
async function _enrichSignIn(token, members) {
  const CHUNK = 15;
  const chunks = [];
  for (let i = 0; i < members.length; i += CHUNK) chunks.push(members.slice(i, i + CHUNK));

  const results = await Promise.allSettled(chunks.map(async chunk => {
    const ids = chunk.map(m => `'${m.id}'`).join(",");
    const res = await fetch(
      `https://graph.microsoft.com/v1.0/users?$filter=id in (${ids})&$select=id,signInActivity`,
      { headers: { Authorization: "Bearer " + token } }
    );
    if (!res.ok) return [];
    return (await res.json()).value || [];
  }));

  const signInMap = {};
  results.forEach(r => {
    if (r.status === "fulfilled") r.value.forEach(u => {
      signInMap[u.id] = u.signInActivity?.lastSignInDateTime ?? null;
    });
  });

  return members.map(m => ({ ...m, lastSignIn: signInMap[m.id] ?? null }));
}
```

- [ ] **Step 3: Add `_loadMembers` — orchestrates fetch + enrich, stores in cache**

```js
async function _loadMembers(groupId, idx) {
  if (_memberCache[idx]?.loaded) return _memberCache[idx].members;
  const token   = await ITTools.auth.getToken();
  const raw     = await _fetchMembers(token, groupId);
  const members = await _enrichSignIn(token, raw);
  _memberCache[idx] = { loaded: true, members };
  return members;
}
```

- [ ] **Step 4: Verify no syntax errors — open browser console, sign in, confirm no errors on load**

- [ ] **Step 5: Commit**

```
git add tools/adobe-license-monitor/index.html
git commit -m "adobe-monitor: _fetchMembers, _enrichSignIn, _loadMembers graph functions"
```

---

## Task 4: toggleExpand — expand/collapse + loading shimmer

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

Add these functions above `// ─── Auth ───`.

- [ ] **Step 1: Add `_shimmerHtml` helper**

```js
function _shimmerHtml() {
  const row = `
    <div class="mem-skel-row">
      <div class="mem-skel-avatar"></div>
      <div style="flex:1;display:flex;flex-direction:column;gap:6px">
        <div class="mem-skel-line" style="width:45%"></div>
        <div class="mem-skel-line" style="width:65%"></div>
      </div>
    </div>`;
  return `<div class="member-skeleton">${row}${row}${row}</div>`;
}
```

- [ ] **Step 2: Add `toggleExpand`**

```js
async function toggleExpand(groupId, idx) {
  const section = document.getElementById(`ms-${groupId}`);
  const strip   = document.getElementById(`strip-${groupId}`);
  const chev    = document.getElementById(`chev-${groupId}`);
  const isOpen  = section.style.display !== "none";

  if (isOpen) {
    section.style.display = "none";
    strip.classList.remove("open");
    chev.classList.remove("open");
    return;
  }

  // Open
  strip.classList.add("open");
  chev.classList.add("open");
  section.style.display = "";
  section.innerHTML = _shimmerHtml();

  try {
    const members = await _loadMembers(groupId, idx);
    _sortState[idx] = _sortState[idx] || { col: "status", dir: -1 };
    renderMemberTable(groupId, idx, members);
    _updateStripCounts(groupId, idx, members);
  } catch (err) {
    section.innerHTML = `
      <div class="member-error">
        <span>${ITTools.graph.friendlyError(err)}</span>
        <button class="btn-mem-retry" onclick="retryExpand('${groupId}',${idx})">Retry</button>
      </div>`;
  }
}

async function retryExpand(groupId, idx) {
  delete _memberCache[idx];
  await toggleExpand(groupId, idx);
}
```

- [ ] **Step 3: Add `_updateStripCounts` — updates member count, disabled badge, and Entra big number**

```js
function _updateStripCounts(groupId, idx, members) {
  const disCount = members.filter(m => !m.accountEnabled).length;

  // Member count span inside the strip
  const memCountEl = document.getElementById(`mem-count-${groupId}`);
  if (memCountEl) memCountEl.textContent = members.length;

  // Disabled badge
  const disBadgeEl  = document.getElementById(`dis-${groupId}`);
  const disCountEl  = document.getElementById(`dis-count-${groupId}`);
  if (disBadgeEl && disCountEl) {
    disCountEl.textContent = disCount;
    disBadgeEl.classList.toggle("show", disCount > 0);
  }

  // Entra big count on the card header
  const entraBigEl = document.getElementById(`entra-big-${groupId}`);
  if (entraBigEl) entraBigEl.textContent = members.length;
}
```

- [ ] **Step 4: Test in browser — sign in, click an expand strip. Shimmer should appear for ~1-2 seconds then be replaced. Open browser network tab to confirm Graph calls fire. Check that collapse on second click works.**

- [ ] **Step 5: Commit**

```
git add tools/adobe-license-monitor/index.html
git commit -m "adobe-monitor: toggleExpand with shimmer loading and retryExpand"
```

---

## Task 5: renderMemberTable + column sort

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

Add these functions above `// ─── Auth ───`.

- [ ] **Step 1: Add `_relativeTime` — converts ISO date to human-readable string**

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

- [ ] **Step 2: Add `_sortMembers` — applies current sort state to member array**

```js
function _sortMembers(members, col, dir) {
  return [...members].sort((a, b) => {
    // Disabled always floats to top when sorting by status or using default
    if (col === "status") {
      if (a.accountEnabled !== b.accountEnabled)
        return a.accountEnabled ? 1 : -1; // disabled first (dir ignored for tiebreak)
      return a.displayName.localeCompare(b.displayName);
    }
    if (col === "name") {
      return dir * a.displayName.localeCompare(b.displayName);
    }
    if (col === "upn") {
      return dir * (a.userPrincipalName || "").localeCompare(b.userPrincipalName || "");
    }
    if (col === "lastSignIn") {
      const ta = a.lastSignIn ? new Date(a.lastSignIn).getTime() : 0;
      const tb = b.lastSignIn ? new Date(b.lastSignIn).getTime() : 0;
      return dir * (ta - tb);
    }
    return 0;
  });
}
```

- [ ] **Step 3: Add `sortBy` — click handler for column headers**

```js
function sortBy(groupId, idx, col) {
  const current = _sortState[idx] || { col: "status", dir: -1 };
  const dir = (current.col === col) ? current.dir * -1 : (col === "lastSignIn" ? 1 : -1);
  _sortState[idx] = { col, dir };
  const members = _memberCache[idx]?.members || [];
  renderMemberTable(groupId, idx, members);
}
```

- [ ] **Step 4: Add `renderMemberTable` — builds and injects the full table**

```js
function renderMemberTable(groupId, idx, members) {
  const section = document.getElementById(`ms-${groupId}`);
  const { col, dir } = _sortState[idx] || { col: "status", dir: -1 };
  const sorted  = _sortMembers(members, col, dir);

  function thIcon(c) {
    if (col !== c) return `<span class="sort-icon">↕</span>`;
    return `<span class="sort-icon">${dir === 1 ? "↑" : "↓"}</span>`;
  }
  function thCls(c) { return col === c ? "sorted" : ""; }

  const rows = sorted.map(m => {
    const initials  = m.displayName.split(" ").map(n => n[0]).join("").slice(0, 2).toUpperCase();
    const statusCls = m.accountEnabled ? "enabled" : "disabled";
    const si        = _relativeTime(m.lastSignIn);
    const siHtml    = `<span${si.stale ? ' class="signin-stale"' : ""}>${si.text}</span>`;
    const removeBtn = _isLicenseAdmin
      ? `<button class="btn-mem-remove" onclick="showRemoveModal('${groupId}',${idx},'${m.id}',${JSON.stringify(m.displayName)},${JSON.stringify(m.userPrincipalName)})">Remove</button>`
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

  const adminPill = _isLicenseAdmin
    ? `<span class="license-admin-pill">License Admin</span> Remove enabled`
    : "Read-only — License Admin required to remove";

  section.innerHTML = `
    <div class="member-tbl-wrap">
      <table class="member-tbl">
        <thead>
          <tr>
            <th class="${thCls("name")}"    style="width:240px" onclick="sortBy('${groupId}',${idx},'name')">Member ${thIcon("name")}</th>
            <th class="${thCls("upn")}"     style="width:220px" onclick="sortBy('${groupId}',${idx},'upn')">UPN ${thIcon("upn")}</th>
            <th class="${thCls("status")}"  style="width:105px" onclick="sortBy('${groupId}',${idx},'status')">Account ${thIcon("status")}</th>
            <th class="${thCls("lastSignIn")}" style="width:145px" onclick="sortBy('${groupId}',${idx},'lastSignIn')">Last Sign-In ${thIcon("lastSignIn")}</th>
            <th>Action</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    </div>
    <div class="member-footer">
      <span id="footer-count-${groupId}">${members.length} members · ${members.filter(m => !m.accountEnabled).length} disabled</span>
      <span>${adminPill}</span>
    </div>`;
}
```

- [ ] **Step 5: Test in browser — expand a product card. Member table should appear with all columns populated. Click column headers to verify sort works. Disabled accounts should be at the top by default. Last sign-in should show relative dates.**

- [ ] **Step 6: Commit**

```
git add tools/adobe-license-monitor/index.html
git commit -m "adobe-monitor: renderMemberTable, sortBy, _relativeTime, _sortMembers"
```

---

## Task 6: Remove action — modal + Graph DELETE + counter update

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

Add these functions above `// ─── Auth ───`.

- [ ] **Step 1: Add `showRemoveModal` and `closeRemoveModal`**

```js
function showRemoveModal(groupId, idx, userId, displayName, upn) {
  _pendingRemove = { groupId, idx, userId };
  document.getElementById("modalName").textContent  = displayName;
  document.getElementById("modalUpn").textContent   = upn;
  document.getElementById("modalGroup").textContent = `Removing from: P-EID-SG-STD-SSO-Adobe_${PRODUCTS[idx].name.replace(/ /g, "_")}`;
  document.getElementById("modalConfirmBtn").disabled = false;
  document.getElementById("modalConfirmBtn").textContent = "Remove from group";
  document.getElementById("removeModal").classList.add("show");
}

function closeRemoveModal() {
  document.getElementById("removeModal").classList.remove("show");
  _pendingRemove = null;
}
```

- [ ] **Step 2: Add `executeRemove` — fires DELETE, updates DOM on success**

```js
async function executeRemove() {
  if (!_pendingRemove) return;
  const { groupId, idx, userId } = _pendingRemove;
  const confirmBtn = document.getElementById("modalConfirmBtn");
  confirmBtn.disabled = true;
  confirmBtn.textContent = "Removing…";

  try {
    const token = await ITTools.auth.getToken();
    const res   = await fetch(
      `https://graph.microsoft.com/v1.0/groups/${groupId}/members/${userId}/$ref`,
      { method: "DELETE", headers: { Authorization: "Bearer " + token } }
    );
    if (!res.ok && res.status !== 204) throw new Error(`Remove failed: ${res.status}`);

    closeRemoveModal();
    _removeRowFromTable(groupId, idx, userId);
  } catch (err) {
    confirmBtn.disabled = false;
    confirmBtn.textContent = "Remove from group";
    // Show inline error below the modal user card
    let errEl = document.getElementById("modalErr");
    if (!errEl) {
      errEl = document.createElement("div");
      errEl.id = "modalErr";
      errEl.style.cssText = "font-size:12px;color:var(--red);margin-bottom:1rem;";
      document.querySelector(".remove-modal-user").after(errEl);
    }
    errEl.textContent = ITTools.graph.friendlyError(err);
  }
}
```

- [ ] **Step 3: Add `_removeRowFromTable` — removes row from cache + DOM, updates counters**

```js
function _removeRowFromTable(groupId, idx, userId) {
  // Remove from cache
  if (_memberCache[idx]?.members) {
    _memberCache[idx].members = _memberCache[idx].members.filter(m => m.id !== userId);
  }
  const members = _memberCache[idx]?.members || [];

  // Fade out and remove the DOM row
  const row = document.getElementById(`mrow-${userId}`);
  if (row) {
    row.style.transition = "opacity .3s";
    row.style.opacity = "0";
    setTimeout(() => row.remove(), 310);
  }

  // Update table footer count
  const footerEl = document.getElementById(`footer-count-${groupId}`);
  if (footerEl) {
    const disCount = members.filter(m => !m.accountEnabled).length;
    footerEl.textContent = `${members.length} members · ${disCount} disabled`;
  }

  // Update strip counts + disabled badge + Entra big number (all in one call)
  _updateStripCounts(groupId, idx, members);
}
```

- [ ] **Step 4: Add `Escape` key to close modal — add inside the existing `// ─── Auth ───` section or at the bottom of the script block, before `window.addEventListener("DOMContentLoaded", init)`**

```js
document.addEventListener("keydown", e => {
  if (e.key === "Escape") closeRemoveModal();
});
```

- [ ] **Step 5: Test the full flow in browser**

1. Expand a product card
2. Click Remove on any row (must be signed in as License Admin, otherwise button is greyed)
3. Confirm modal appears with correct name, UPN, and group name
4. Click "Remove from group" — row should fade out, member count decrements, disabled badge updates
5. Press Escape — modal closes without removing
6. Test with a non-License-Admin account — Remove buttons should be greyed out

- [ ] **Step 6: Commit**

```
git add tools/adobe-license-monitor/index.html
git commit -m "adobe-monitor: remove modal, executeRemove, _removeRowFromTable, Escape to close"
```

---

## Task 7: Error handling + push to preview

**Files:**
- Modify: `tools/adobe-license-monitor/index.html`

The error states for member load failure and signInActivity degradation are already partially handled in Tasks 3 and 4. This task verifies them and adds the row-level remove error.

- [ ] **Step 1: Verify member load error path**

In browser DevTools, temporarily add `throw new Error("test")` at the top of `_fetchMembers`. Expand a card — you should see the red error banner with a Retry button inside the card. Remove the throw.

- [ ] **Step 2: Verify signInActivity graceful degradation**

In `_enrichSignIn`, note that each chunk uses `Promise.allSettled` — if a chunk fails the members still render, just with `lastSignIn: null`. Confirm `_relativeTime(null)` returns `{ text: "Never", stale: true }` (it does — check Task 5 Step 1 code).

- [ ] **Step 3: Add row-level remove error display**

The `executeRemove` function already shows an error below the modal user card. Verify this works by temporarily making the DELETE call fail. The confirm button should re-enable and show the error message inline in the modal — the modal should NOT close.

- [ ] **Step 4: Final visual check**

Open `tools/adobe-license-monitor/index.html` and verify:
- [ ] Shell is noticeably wider than before
- [ ] All three product cards have an expand strip with chevron
- [ ] Expanding a card shows shimmer then member table
- [ ] Disabled accounts appear at top with red row tint and Disabled badge
- [ ] Last sign-in column shows relative dates, stale dates in red
- [ ] Column headers are clickable and sort works with chevron indicator
- [ ] Disabled count badge appears on strip after load if any disabled users exist
- [ ] Strip turns blue when open, reverts when closed
- [ ] Second expand of same card is instant (cached)
- [ ] Multiple cards can be open simultaneously
- [ ] Remove button is active for License Admins, greyed for others
- [ ] Confirmation modal shows correct data, fires DELETE on confirm, fades row on success
- [ ] Escape and clicking outside modal closes it

- [ ] **Step 5: Push to preview**

```
git push origin testing
```

Preview site: https://jgdev-ch.github.io/it-tools-preview/tools/adobe-license-monitor/
