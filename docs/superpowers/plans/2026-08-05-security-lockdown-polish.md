# Account Lockdown Visual Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent right-hand info sidebar to the Account Lockdown wizard and extend its dark-glass header with an amber "signal" accent, per `docs/superpowers/specs/2026-08-05-security-lockdown-polish-design.md`.

**Architecture:** Pure presentation change to the existing single-file tool (`tools/security-lockdown/index.html`) — no new files, no build step, no changes to Graph calls or state shape. The wizard shell goes from one centered column to a two-column flex layout (main column + sticky sidebar); the sidebar reads the same `st.results` array that already drives the Step-3 results table, via one new render function.

**Tech Stack:** Static HTML/CSS/JS, matching the rest of this codebase. Verification per task is a Node syntax-check of the inline `<script>` block (the existing convention in this repo), since the DOM-manipulating function this plan adds (`renderSidebarProgress`) can't be unit-tested standalone without a DOM — it's verified visually in the browser instead, folded into the project's already-pending live verification pass.

---

### Task 1: Two-column shell restructure

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Widen the shell and add the two-column layout CSS**

Find:
```css
  .shell { max-width: 760px; margin: 0 auto; padding: 24px 16px; }
```
Replace with:
```css
  .shell { max-width: 1000px; margin: 0 auto; padding: 24px 16px; }
  .wizard-layout { display: flex; gap: 24px; align-items: flex-start; }
  .wizard-main   { flex: 1; min-width: 0; }
```

- [ ] **Step 2: Open the two-column wrapper before Step 1's section**

Find:
```html
    <div class="section active" id="step1">
```
Replace with:
```html
    <div class="wizard-layout">
      <div class="wizard-main">

    <div class="section active" id="step1">
```

- [ ] **Step 3: Close the wrapper and add the (empty) sidebar shell after Step 3's section**

Find:
```html
      <button class="btn btn-secondary" id="csvExportBtn" disabled onclick="exportResultsCsv()">Download Results CSV</button>
    </div>

  </div>
</div>
```
Replace with:
```html
      <button class="btn btn-secondary" id="csvExportBtn" disabled onclick="exportResultsCsv()">Download Results CSV</button>
    </div>

      </div>

      <aside class="lockdown-sidebar">
        <!-- TASK2: sidebar content goes here -->
      </aside>
    </div>

  </div>
</div>
```

- [ ] **Step 4: Verify no syntax errors**

Run:
```bash
node -e "const fs=require('fs');const html=fs.readFileSync('tools/security-lockdown/index.html','utf8');const scripts=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);for(const s of scripts)new Function(s);console.log('OK')"
```
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Restructure Account Lockdown wizard shell into two columns"
```

---

### Task 2: Sidebar CSS and static content

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Add the sidebar CSS**

Find:
```css
  .wizard-layout { display: flex; gap: 24px; align-items: flex-start; }
  .wizard-main   { flex: 1; min-width: 0; }
```
Replace with:
```css
  .wizard-layout { display: flex; gap: 24px; align-items: flex-start; }
  .wizard-main   { flex: 1; min-width: 0; }
  .lockdown-sidebar {
    width: 220px; flex-shrink: 0; position: sticky; top: 24px;
    background: #1c1f26; border: 1px solid rgba(226,161,61,.35); border-left: 3px solid #e2a13d;
    border-radius: 14px; padding: 16px; font-size: 12px;
  }
  .sidebar-heading { font-size: 11px; font-weight: 700; letter-spacing: .4px; text-transform: uppercase; color: #f0c47a; margin-bottom: 12px; }
  .sidebar-step  { display: flex; gap: 8px; align-items: flex-start; margin-bottom: 10px; }
  .sidebar-num   {
    width: 18px; height: 18px; border-radius: 50%; flex-shrink: 0;
    background: rgba(226,161,61,.25); color: #f0c47a;
    font-size: 10px; font-weight: 700; display: flex; align-items: center; justify-content: center;
  }
  .sidebar-num.success { background: rgba(52,199,111,.22); }
  .sidebar-num.failed  { background: rgba(234,106,96,.25); }
  .sidebar-label { color: #c9cdd6; font-size: 12px; font-weight: 600; }
  .sidebar-desc  { display: block; color: #8b909c; font-size: 10px; font-weight: 400; margin-top: 1px; }
  .sidebar-warning {
    display: flex; gap: 7px; align-items: flex-start; margin-top: 14px;
    background: rgba(234,106,96,.12); border: 1px solid rgba(234,106,96,.3);
    border-radius: 8px; padding: 9px 10px; font-size: 11px; color: #ea6a60;
  }
  .sidebar-warning svg { flex-shrink: 0; margin-top: 1px; }
  .sidebar-tally { margin-top: 12px; padding-top: 10px; border-top: 1px solid rgba(255,255,255,.08); font-size: 11px; font-weight: 600; color: #c9cdd6; }
```

Note: all sidebar colors are hardcoded hex/rgba, not `var(--red-light)`-style theme tokens — this matches how `.lockdown-header` and `.lockdown-badge` already work. The sidebar is theme-independent (same dark-glass fill in light or dark hub theme), so it can't use the CSS custom properties that flip between light/dark theme values, or it would look washed out in light mode.

- [ ] **Step 2: Add the static sidebar markup**

Find:
```html
      <aside class="lockdown-sidebar">
        <!-- TASK2: sidebar content goes here -->
      </aside>
```
Replace with:
```html
      <aside class="lockdown-sidebar">
        <div class="sidebar-heading">What Happens</div>
        <div class="sidebar-step">
          <span class="sidebar-num" id="sidebarNum-revokeSessions">1</span>
          <span class="sidebar-label">Revoke sessions<span class="sidebar-desc">Kills active tokens immediately</span></span>
        </div>
        <div class="sidebar-step">
          <span class="sidebar-num" id="sidebarNum-resetPassword">2</span>
          <span class="sidebar-label">Reset password<span class="sidebar-desc">Random temp password, forced change</span></span>
        </div>
        <div class="sidebar-step">
          <span class="sidebar-num" id="sidebarNum-resetMfa">3</span>
          <span class="sidebar-label">Reset MFA<span class="sidebar-desc">Removes all registered auth methods</span></span>
        </div>
        <div class="sidebar-step">
          <span class="sidebar-num" id="sidebarNum-blockSignIn">4</span>
          <span class="sidebar-label">Block sign-in<span class="sidebar-desc">Disables the account entirely</span></span>
        </div>
        <div class="sidebar-warning">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#ea6a60" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>
          <span>Cannot be undone from this tool. Every action is logged to Entra's audit trail. Confirm this is approved before continuing.</span>
        </div>
        <div class="sidebar-tally" id="sidebarTally" style="display:none"></div>
      </aside>
```

The warning icon is Lucide's `triangle-alert` icon (real SVG path from lucide.dev), not a unicode ⚠ character — per the spec's icon-consistency requirement.

- [ ] **Step 3: Verify no syntax errors**

Run the same Node check as Task 1 Step 4. Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add Account Lockdown sidebar: static step breakdown and irreversibility warning"
```

---

### Task 3: Amber header badge

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Change the badge text color to amber**

Find:
```css
  .lockdown-badge {
    display: flex; align-items: center; gap: 7px;
    font-size: 11px; font-weight: 700; letter-spacing: .5px;
    color: #c9cdd6; text-transform: uppercase;
  }
```
Replace with:
```css
  .lockdown-badge {
    display: flex; align-items: center; gap: 7px;
    font-size: 11px; font-weight: 700; letter-spacing: .5px;
    color: #e2a13d; text-transform: uppercase;
  }
```

This now matches the badge's lock icon, which was already stroked in the same amber (`#e2a13d`) from the original build.

- [ ] **Step 2: Verify no syntax errors**

Run the same Node check as Task 1 Step 4. Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Recolor Account Lockdown header badge text to amber, matching its icon"
```

---

### Task 4: Dynamic sidebar progress on Results

**Files:**
- Modify: `tools/security-lockdown/index.html`

This makes the sidebar's four numbered badges reflect live outcomes once `executeLockdown()` starts running, by reading the same `st.results[].actions` state that already drives the Step-3 results table — no new state is introduced.

- [ ] **Step 1: Add the icon constants and the render function**

Find:
```js
function statusBadge(action) {
```
Insert immediately before it:
```js
const SIDEBAR_ICONS = {
  success: `<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#34c76f" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>`,
  failed:  `<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#ea6a60" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>`,
};

// A sidebar action badge only leaves "pending" once every account in the
// queue has reached a terminal state (success/failed) for that specific
// action. Accounts are locked down one at a time, in full, before the next
// account starts (see executeLockdown's nested loop), so an aggregate
// "any account still mid-run" badge would otherwise flicker per account
// instead of reflecting the whole queue.
function renderSidebarProgress() {
  ACTION_ORDER.forEach((key, idx) => {
    const num = document.getElementById("sidebarNum-" + key);
    if (!num) return;
    num.classList.remove("success", "failed");
    const allTerminal = st.results.length > 0 &&
      st.results.every(r => r.actions[key].status === "success" || r.actions[key].status === "failed");
    if (!allTerminal) {
      num.textContent = idx + 1;
      return;
    }
    const anyFailed = st.results.some(r => r.actions[key].status === "failed");
    num.classList.add(anyFailed ? "failed" : "success");
    num.innerHTML = anyFailed ? SIDEBAR_ICONS.failed : SIDEBAR_ICONS.success;
  });

  const tally = document.getElementById("sidebarTally");
  if (!st.results.length) { tally.style.display = "none"; return; }
  const fullyDone = st.results.filter(r => ACTION_ORDER.every(k => r.actions[k].status === "success")).length;
  tally.style.display = "block";
  tally.textContent = `${fullyDone} of ${st.results.length} account(s) fully locked down`;
}

function statusBadge(action) {
```

Both icons are Lucide's `check` and `x` icons (real SVG paths from lucide.dev), not unicode ✓/✗ characters.

- [ ] **Step 2: Call it from the existing results renderer**

Find:
```js
  const allAccountsDone = st.results.length > 0 &&
    st.results.every(row => ACTION_ORDER.every(k => row.actions[k].status === "success" || row.actions[k].status === "failed"));
  document.getElementById("csvExportBtn").disabled = !allAccountsDone;
}
```
Replace with:
```js
  const allAccountsDone = st.results.length > 0 &&
    st.results.every(row => ACTION_ORDER.every(k => row.actions[k].status === "success" || row.actions[k].status === "failed"));
  document.getElementById("csvExportBtn").disabled = !allAccountsDone;
  renderSidebarProgress();
}
```

`renderResults()` is already called from every point in the code that changes `st.results` (`executeLockdown`, and both status transitions inside `runAction`), so this single call site keeps the sidebar in sync everywhere without touching those call sites.

- [ ] **Step 3: Verify no syntax errors**

Run the same Node check as Task 1 Step 4. Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Make Account Lockdown sidebar badges reflect live lockdown progress"
```

---

### Task 5: Push to preview and fold into pending visual verification

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

- [ ] **Step 3: Fold this pass into the existing pending E2E verification**

The original implementation plan's Task 15 (end-to-end verification against test accounts) is still open and requires Josh's live browser session regardless of this polish pass. Add these checks to that same pass rather than scheduling a separate one:
- Sidebar renders at 220px on the right, sticky while scrolling, on all three wizard steps.
- Header badge text and icon are both the same amber (`#e2a13d`).
- Sidebar's four badges start as plain amber numbers on Steps 1–2.
- After running a lockdown, each sidebar badge turns to a green check or red x once every account has reached a terminal state for that specific action, and the tally line under them reads correctly (e.g. "2 of 2 account(s) fully locked down").
- The "cannot be undone" callout renders with the triangle-alert icon (not a broken image or missing glyph) and reads clearly against the dark sidebar.
- No layout breakage at a normal desktop window width (this pass is desktop-only by design, matching the rest of the hub).
