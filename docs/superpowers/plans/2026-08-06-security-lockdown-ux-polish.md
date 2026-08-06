# Account Lockdown UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Widen the Account Lockdown wizard to match the hub's shell width, fix the search-and-add flow so adding one result doesn't wipe the rest, cap the results list height, add icons to status badges, and add an overall progress bar during execution — per `docs/superpowers/specs/2026-08-06-security-lockdown-ux-polish-design.md`.

**Architecture:** Presentation and interaction changes to the existing single-file tool (`tools/security-lockdown/index.html`) only. No new files, no Graph call changes, no state-shape changes — the progress bar and badge icons read the same `st.results` data that already drives `renderResults()` and `renderSidebarProgress()`.

**Tech Stack:** Static HTML/CSS/JS, matching the rest of this codebase. Verification per task is a Node syntax-check of the inline `<script>` block; the DOM-driven behaviors (search list interaction, scroll cap, progress bar) are verified visually in the browser, folded into the already-open Task 15 checklist from the original build plan.

---

### Task 1: Widen the wizard shell

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Change the shell max-width**

Find:
```css
  .shell { max-width: 1000px; margin: 0 auto; padding: 24px 16px; }
```
Replace with:
```css
  .shell { max-width: 1300px; margin: 0 auto; padding: 24px 16px; }
```

This matches the hub's own `.hub-shell` max-width (`index.html`) exactly. `.wizard-layout`'s gap and `.lockdown-sidebar`'s width are unchanged — all the extra width goes to `.wizard-main`.

- [ ] **Step 2: Verify no syntax errors**

Run:
```bash
node -e "const fs=require('fs');const html=fs.readFileSync('tools/security-lockdown/index.html','utf8');const scripts=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);for(const s of scripts)new Function(s);console.log('OK')"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Widen Account Lockdown wizard shell to match hub width (1300px)"
```

---

### Task 2: Search-and-add UX fix

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Add CSS for the scrollable results box and Clear link**

Find:
```css
  .cand-row       { display: flex; align-items: center; gap: 10px; padding: 8px 10px; border: 1px solid var(--border); border-radius: 8px; margin-top: 6px; cursor: pointer; }
  .cand-row:hover { background: var(--surface2); }
  .cand-name      { font-size: 13px; font-weight: 600; }
  .cand-meta      { font-size: 11px; color: var(--muted); }
```
Replace with:
```css
  .cand-row       { display: flex; align-items: center; gap: 10px; padding: 8px 10px; border: 1px solid var(--border); border-radius: 8px; margin-top: 6px; cursor: pointer; }
  .cand-row:hover { background: var(--surface2); }
  .cand-name      { font-size: 13px; font-weight: 600; }
  .cand-meta      { font-size: 11px; color: var(--muted); }
  .search-results-clear { display: flex; justify-content: flex-end; margin-top: 8px; }
  .search-clear-btn     { color: var(--muted); cursor: pointer; background: none; border: none; font-size: 11px; font-weight: 600; padding: 0; }
  .search-clear-btn:hover { color: var(--blue); }
  .search-results-box   { max-height: 320px; overflow-y: auto; margin-top: 2px; }
```

`.search-results-box`'s `max-height: 320px` fits about 6 `.cand-row` rows (each ~52px including its own top margin) before scrolling — approximate by design, not meant to be pixel-exact.

- [ ] **Step 2: Wrap search results in the scrollable box with a Clear link, and stop clearing the input/list on add**

Find:
```js
    resultsEl.innerHTML = candidates.map(c => `
      <div class="cand-row" onclick='addCandidateFromJson(this)' data-account='${esc(JSON.stringify(c))}'>
        <div style="flex:1">
          <div class="cand-name">${esc(c.displayName)}</div>
          <div class="cand-meta">${esc(c.userPrincipalName)}${c.department ? " &middot; " + esc(c.department) : ""}</div>
        </div>
        <span style="font-size:11px;font-weight:600;color:var(--blue)">Add</span>
      </div>
    `).join("");
```
Replace with:
```js
    resultsEl.innerHTML = `
      <div class="search-results-clear"><button class="search-clear-btn" onclick="clearSearchResults()">Clear</button></div>
      <div class="search-results-box">
        ${candidates.map(c => `
          <div class="cand-row" onclick='addCandidateFromJson(this)' data-account='${esc(JSON.stringify(c))}'>
            <div style="flex:1">
              <div class="cand-name">${esc(c.displayName)}</div>
              <div class="cand-meta">${esc(c.userPrincipalName)}${c.department ? " &middot; " + esc(c.department) : ""}</div>
            </div>
            <span style="font-size:11px;font-weight:600;color:var(--blue)">Add</span>
          </div>
        `).join("")}
      </div>
    `;
```

- [ ] **Step 3: Replace the whole-list clear on add with removing just that row, and add `clearSearchResults()`**

Find:
```js
function addCandidateFromJson(el) {
  const account = JSON.parse(el.dataset.account);
  addToQueue(account);
  document.getElementById("searchInput").value = "";
  document.getElementById("searchResults").innerHTML = "";
}
```
Replace with:
```js
function addCandidateFromJson(el) {
  const account = JSON.parse(el.dataset.account);
  addToQueue(account);
  const box = el.parentElement;
  el.remove();
  // If that was the last remaining match, collapse back to the pre-search
  // state (no empty box, no dangling Clear link) instead of leaving an
  // empty scrollable box behind.
  if (box && box.classList.contains("search-results-box") && !box.children.length) {
    document.getElementById("searchResults").innerHTML = "";
  }
}

function clearSearchResults() {
  document.getElementById("searchResults").innerHTML = "";
  document.getElementById("searchInput").value = "";
}
```

Note: the search input's value is deliberately left alone by `addCandidateFromJson` now — only `clearSearchResults()` (the explicit Clear link) touches it. Multiple candidates from one search can now be added one at a time without retyping, and the remaining matches don't move around when one is added since the removed row simply disappears rather than the whole list re-rendering.

- [ ] **Step 4: Verify no syntax errors**

Run the same Node check as Task 1 Step 2. Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Fix search-and-add: keep remaining results visible, cap list height, add Clear link"
```

---

### Task 3: Status badges get success/failed icons

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Make the badge a flex row so an icon can sit before the text**

Find:
```css
  .action-status          { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 10px; font-weight: 700; text-transform: uppercase; }
```
Replace with:
```css
  .action-status          { display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px; border-radius: 10px; font-size: 10px; font-weight: 700; text-transform: uppercase; }
```

- [ ] **Step 2: Add the icon to `statusBadge()`, reusing the existing `SIDEBAR_ICONS`**

Find:
```js
function statusBadge(action) {
  return `<span class="action-status action-status--${action.status}">${action.status}</span>` +
    (action.error ? `<div style="font-size:10px;color:var(--red);margin-top:2px">${esc(action.error)}</div>` : "");
}
```
Replace with:
```js
function statusBadge(action) {
  // Only terminal states (success/failed) get an icon — pending/running
  // stay text-only since there's nothing confirmed yet to put a check or
  // x next to.
  const icon = action.status === "success" ? SIDEBAR_ICONS.success
             : action.status === "failed"  ? SIDEBAR_ICONS.failed
             : "";
  return `<span class="action-status action-status--${action.status}">${icon}${action.status}</span>` +
    (action.error ? `<div style="font-size:10px;color:var(--red);margin-top:2px">${esc(action.error)}</div>` : "");
}
```

`SIDEBAR_ICONS` is already defined earlier in this file (added in the previous polish pass for the sidebar's own success/failed badges) — this reuses it rather than redefining the same two SVGs a second time.

- [ ] **Step 3: Verify no syntax errors**

Run the same Node check as Task 1 Step 2. Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add check/x icons to Account Lockdown status badges on terminal states"
```

---

### Task 4: Overall progress bar during execution

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Add the progress bar CSS**

Find:
```css
  .retry-btn { display: inline-flex; align-items: center; gap: 4px; background: none; border: none; color: var(--blue); font-size: 11px; font-weight: 600; cursor: pointer; padding: 0; }
```
Replace with:
```css
  .retry-btn { display: inline-flex; align-items: center; gap: 4px; background: none; border: none; color: var(--blue); font-size: 11px; font-weight: 600; cursor: pointer; padding: 0; }
  .progress-bar-wrap  { margin: 12px 0 16px; }
  .progress-bar-label { font-size: 12px; color: var(--muted); margin-bottom: 6px; }
  .progress-bar-track { height: 6px; background: var(--surface2); border-radius: 4px; overflow: hidden; }
  .progress-bar-fill  { height: 100%; width: 0%; background: #e2a13d; border-radius: 4px; transition: width .3s; }
```

- [ ] **Step 2: Add the progress bar markup between the Results heading and the table**

Find:
```html
    <div class="section" id="step3">
      <h2>Results</h2>
      <table class="results-table">
```
Replace with:
```html
    <div class="section" id="step3">
      <h2>Results</h2>
      <div class="progress-bar-wrap" id="progressBarWrap" style="display:none">
        <div class="progress-bar-label" id="progressBarLabel"></div>
        <div class="progress-bar-track"><div class="progress-bar-fill" id="progressBarFill"></div></div>
      </div>
      <table class="results-table">
```

- [ ] **Step 3: Add `renderProgressBar()` and call it from `renderResults()`**

Find:
```js
function statusBadge(action) {
```
Insert immediately before it:
```js
// Counts accounts that have reached a terminal state (success OR failed)
// for every one of the four actions — i.e. "done being processed", not
// "fully succeeded". This is deliberately different from
// renderSidebarProgress()'s fullyDone (which requires all-success, for its
// "N fully locked down" wording) — the progress bar tracks queue-wide
// completion, not queue-wide success.
function renderProgressBar() {
  const wrap  = document.getElementById("progressBarWrap");
  const label = document.getElementById("progressBarLabel");
  const fill  = document.getElementById("progressBarFill");
  if (!st.results.length) { wrap.style.display = "none"; return; }

  const processedCount = st.results.filter(row =>
    ACTION_ORDER.every(k => row.actions[k].status === "success" || row.actions[k].status === "failed")
  ).length;
  if (processedCount === st.results.length) { wrap.style.display = "none"; return; }

  wrap.style.display = "block";
  label.textContent = `Locking down ${processedCount} of ${st.results.length} account(s)…`;
  fill.style.width = `${Math.round((processedCount / st.results.length) * 100)}%`;
}

function statusBadge(action) {
```

Find:
```js
  const allAccountsDone = st.results.length > 0 &&
    st.results.every(row => ACTION_ORDER.every(k => row.actions[k].status === "success" || row.actions[k].status === "failed"));
  document.getElementById("csvExportBtn").disabled = !allAccountsDone;
  renderSidebarProgress();
}
```
Replace with:
```js
  const allAccountsDone = st.results.length > 0 &&
    st.results.every(row => ACTION_ORDER.every(k => row.actions[k].status === "success" || row.actions[k].status === "failed"));
  document.getElementById("csvExportBtn").disabled = !allAccountsDone;
  renderSidebarProgress();
  renderProgressBar();
}
```

The bar reuses the same `st.results` data `renderResults()` and `renderSidebarProgress()` already read — no new state, and it disappears in the same render pass that enables the CSV button, so the two stay in sync.

- [ ] **Step 4: Verify no syntax errors**

Run the same Node check as Task 1 Step 2. Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add overall progress bar to Account Lockdown Results step during execution"
```

---

### Task 5: Push to preview and fold into pending E2E checklist

**Files:** none — deployment + checklist update only.

- [ ] **Step 1: Push to `testing`**

```bash
git push
```

- [ ] **Step 2: Confirm the preview deploy succeeded**

```bash
curl -s "https://api.github.com/repos/jgdev-ch/it-tools-preview/actions/runs?per_page=1" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const j=JSON.parse(d);const r=j.workflow_runs[0];console.log(r.status, r.conclusion)})"
```
Expected: eventually `completed success` (poll every ~15s while `in_progress`).

- [ ] **Step 3: Fold these checks into the still-open E2E verification**

Add to the same outstanding checklist from the original build plan (already partially completed — core Graph actions confirmed live on 2026-08-06):
- Wizard reads noticeably less cramped at the wider 1300px shell; sidebar still sticks and stays 220px.
- Searching a common name with multiple matches, adding one leaves the rest visible and adds them without re-searching; a 7th+ match scrolls inside the results box instead of pushing the queue table down.
- The Clear link empties the results list and the search box.
- Success/failed badges show a small check/x icon; pending/running stay text-only.
- During execution, the amber progress bar tracks "Locking down X of Y accounts…" and disappears once every account (success or failed) is done, at the same moment the CSV button enables.
