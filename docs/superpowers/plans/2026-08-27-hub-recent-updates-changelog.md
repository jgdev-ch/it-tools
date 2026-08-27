# Hub Recent Updates Changelog + Glass Scrollbars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Recent Updates" changelog dropdown to the IT Tools hub header, and give every scrollbar in the hub (and every tool page, via `shared/styles.css`) a glass-styled treatment consistent with the rest of the design system.

**Architecture:** A new `changelog.json` at the repo root (same convention as `config.json`/`downloads.json`) holds hand-written version-bump entries. `index.html` gets a topbar icon button that opens a fixed-size (380×420px) floating panel — reusing the exact `.downloads-panel` absolute-positioning pattern already in the file — so opening it, scrolling inside it, or expanding a month bucket can never shift the tool grid. Entries newer than 30 days render flat; older entries group into collapsible month buckets using the hub's existing `.tool-section`/`.section-label`/`.section-chevron`/`.section-collapse` classes (same mechanism as the "Daily Operations"/"Reporting & Audit" category collapsibles). `shared/styles.css` gets two new theme-aware tokens (`--scroll-thumb`/`--scroll-thumb-hover`) and global `::-webkit-scrollbar`/`scrollbar-color` rules.

**Tech Stack:** Vanilla HTML/CSS/JS, no build step, no frameworks — matches the existing `it-tools` hub. Verification follows this repo's established convention for this stack: `node --check` to syntax-validate the inline `<script>` block, plus manual browser verification (there is no test framework or build step in this repo).

---

## Task 1: `changelog.json` seed data

**Files:**
- Create: `changelog.json` (repo root)

- [ ] **Step 1: Create the file**

```json
{
  "entries": [
    {
      "version": "2.3.3",
      "date": "2026-08-27",
      "notes": [
        "User Creation: numeric UPN support, chevron/theme-color polish",
        "Account Lockdown: wizard width, search-and-add fix, status badge icons, progress bar",
        "Hub: Recent Updates panel and glass-styled scrollbars"
      ]
    },
    {
      "version": "2.3.2",
      "date": "2026-08-05",
      "notes": ["Account Lockdown: initial ship and visual polish"]
    }
  ]
}
```

- [ ] **Step 2: Validate it parses**

Run:
```bash
node -e "JSON.parse(require('fs').readFileSync('changelog.json','utf8')); console.log('JSON OK')"
```
Expected: `JSON OK`

- [ ] **Step 3: Commit**

```bash
git add changelog.json
git commit -m "Add changelog.json seed data for the Recent Updates panel"
```

---

## Task 2: Glass-styled scrollbars in `shared/styles.css`

**Files:**
- Modify: `shared/styles.css:68` (end of `:root` token block)
- Modify: `shared/styles.css:122` (end of `[data-theme="dark"]` token block)
- Modify: `shared/styles.css` (append new section at end of file, after line 581)

- [ ] **Step 1: Add the light-theme token**

In `shared/styles.css`, find this block (around line 63-68):

```css
  /* Glass */
  --glass-fill:   rgba(255,255,255,.55);
  --glass-border: rgba(255,255,255,.65);
  /* Near-opaque fill for floating panels (dropdowns) so page content behind
     them doesn't bleed through — glass-fill is too transparent over content. */
  --panel-fill:   rgba(255,255,255,.97);
```

Add directly after the `--panel-fill` line, still inside the same `:root { }` block:

```css
  /* Scrollbar thumb — deliberately not --glass-fill/--glass-border: those are
     tuned for translucent surfaces over a blurred backdrop, and a white-tinted
     thumb over a flat white panel is invisible. Dark tint here, light tint in
     dark theme below. */
  --scroll-thumb:       rgba(0,0,0,.16);
  --scroll-thumb-hover: rgba(0,0,0,.30);
```

- [ ] **Step 2: Add the dark-theme token**

Find this block (around line 120-122):

```css
  --glass-fill:   rgba(255,255,255,.055);
  --glass-border: rgba(255,255,255,.10);
  --panel-fill:   rgba(22,23,28,.96);
```

Add directly after the `--panel-fill` line, still inside the same `[data-theme="dark"] { }` block:

```css
  --scroll-thumb:       rgba(255,255,255,.18);
  --scroll-thumb-hover: rgba(255,255,255,.32);
```

- [ ] **Step 3: Add the global scrollbar rules**

Append at the very end of `shared/styles.css` (after the closing `}` of the `@media (max-width: 640px)` block, currently the last line of the file):

```css

/* ─────────────────────────────────────────────────────────────
   SCROLLBARS — glass-styled, hub-wide
───────────────────────────────────────────────────────────── */
::-webkit-scrollbar       { width: 10px; height: 10px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb {
  background: var(--scroll-thumb);
  border: 2px solid transparent;
  background-clip: padding-box;
  border-radius: 20px;
}
::-webkit-scrollbar-thumb:hover { background: var(--scroll-thumb-hover); }
* { scrollbar-width: thin; scrollbar-color: var(--scroll-thumb) transparent; }
```

- [ ] **Step 4: Verify visually**

Serve the repo root locally:
```bash
node -e "const h=require('http'),fs=require('fs'),path=require('path');h.createServer((req,res)=>{let p=path.join('.',decodeURIComponent(req.url.split('?')[0]));if(p.endsWith(path.sep))p+='index.html';fs.readFile(p,(e,d)=>{if(e){res.writeHead(404);res.end('not found');return;}res.writeHead(200);res.end(d);});}).listen(8791,()=>console.log('serving on 8791'));"
```
Open `http://localhost:8791/index.html` in a browser. Resize the window short enough that the tool grid overflows vertically, or open the Scripts & Downloads panel (if signed in) and shrink it so its list overflows. Confirm:
- The page scrollbar and the downloads-panel-list scrollbar both show a thin, rounded, translucent thumb (not the browser's default gray bar).
- Toggle the theme switch (moon/sun icon) — the thumb should stay legible in both light and dark theme, not disappear.

Stop the server (`Ctrl+C` or kill the background process) once confirmed.

- [ ] **Step 5: Commit**

```bash
git add shared/styles.css
git commit -m "Add theme-aware glass-styled scrollbars hub-wide"
```

---

## Task 3: Changelog panel — HTML markup + CSS in `index.html`

**Files:**
- Modify: `index.html:250` (CSS, after `.downloads-panel-list`)
- Modify: `index.html:508` (HTML, topbar button, before the Downloads button)
- Modify: `index.html:573` (footer version string)

- [ ] **Step 1: Add the panel CSS**

In `index.html`, find this block (around line 247-250):

```css
.downloads-panel-list {
  padding: 10px; display: flex; flex-direction: column; gap: 8px;
  max-height: 70vh; overflow-y: auto;
}
```

Add directly after it:

```css

/* ── Recent Updates dropdown panel ── */
.changelog-panel {
  position: absolute; right: 0; top: calc(100% + 8px);
  background: var(--panel-fill);
  backdrop-filter: blur(28px) saturate(200%);
  -webkit-backdrop-filter: blur(28px) saturate(200%);
  border: 1px solid var(--border);
  border-radius: 14px; box-shadow: var(--shadow-md);
  width: 380px; height: 420px; max-width: calc(100vw - 32px);
  z-index: 200; overflow: hidden;
  display: flex; flex-direction: column;
}
.changelog-panel-head {
  padding: 12px 14px 10px; border-bottom: 1px solid var(--border);
  display: flex; align-items: baseline; justify-content: space-between; gap: 10px;
  font-size: 11px; font-weight: 700; text-transform: uppercase;
  letter-spacing: .08em; color: var(--ink-dim); flex-shrink: 0;
}
.changelog-panel-date { font-size: 10px; font-weight: 600; text-transform: none; letter-spacing: 0; }
.changelog-panel-list {
  padding: 12px 14px; display: flex; flex-direction: column; gap: 14px;
  overflow-y: auto; flex: 1;
}
.changelog-entry { padding-bottom: 12px; border-bottom: 1px solid var(--border); }
/* :last-of-type = "last div among all siblings" — when there are no month
   buckets after it, this removes the trailing border; when there are, it
   correctly leaves a divider before the grouped-months section. */
.changelog-entry:last-of-type { border-bottom: none; padding-bottom: 0; }
.changelog-entry-hdr { display: flex; align-items: baseline; gap: 8px; font-size: 13px; color: var(--ink); margin-bottom: 4px; }
.changelog-date { font-size: 11px; color: var(--ink-dim); }
.changelog-entry ul { margin: 0; padding-left: 18px; font-size: 12px; color: var(--ink-dim); line-height: 1.6; }
```

- [ ] **Step 2: Add the topbar button + panel markup**

Find this block (around line 508-511):

```html
    <div style="position:relative">
      <button type="button" class="btn-icon" id="downloadsBtn" onclick="toggleDownloadsDropdown()" title="Scripts &amp; Downloads" aria-label="Scripts and Downloads" aria-expanded="false" style="display:none">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="15" height="15"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
      </button>
```

Insert this immediately **before** that block (still inside `.hub-topbar-right`, before the Downloads button's own `<div style="position:relative">`):

```html
    <div style="position:relative">
      <button type="button" class="btn-icon" id="changelogBtn" onclick="toggleChangelogPanel()" title="Recent Updates" aria-label="Recent Updates" aria-expanded="false" style="display:none">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="15" height="15"><path d="M11 6a13 13 0 0 0 8.4-2.8A1 1 0 0 1 21 4v12a1 1 0 0 1-1.6.8A13 13 0 0 0 11 14H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z"/><path d="M6 14a12 12 0 0 0 2.4 7.2 2 2 0 0 0 3.2-2.4A8 8 0 0 1 10 14"/><path d="M8 6v8"/></svg>
      </button>
      <div class="changelog-panel" id="changelogPanel" style="display:none">
        <div class="changelog-panel-head">
          <span>Recent Updates</span>
          <span class="changelog-panel-date" id="changelogPanelDate"></span>
        </div>
        <div class="changelog-panel-list" id="changelogPanelList"></div>
      </div>
    </div>

```

- [ ] **Step 3: Bump the footer version**

Find (around line 573):

```html
  <span>Built by Josh Garrett &middot; v2.3.2</span>
```

Change to:

```html
  <span>Built by Josh Garrett &middot; v2.3.3</span>
```

- [ ] **Step 4: Syntax-check the file still loads**

Run:
```bash
node -e "require('fs').readFileSync('index.html','utf8'); console.log('read OK')"
```
Expected: `read OK` (this task only touches HTML/CSS — the real JS syntax check happens in Task 4 once the functions these markup IDs depend on exist).

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "Add Recent Updates panel markup/CSS, bump hub version to v2.3.3"
```

---

## Task 4: Changelog panel — JS behavior in `index.html`

**Files:**
- Modify: `index.html:1104` (new functions, after `toggleDownloadsDropdown()`)
- Modify: `index.html:1128-1146` (click-outside listener)
- Modify: `index.html:1148-1162` (Escape-key listener)
- Modify: `index.html:1164` (boot sequence)

- [ ] **Step 1: Add the changelog functions**

Find this block (around line 1098-1104):

```js
function toggleDownloadsDropdown() {
  const panel = document.getElementById("downloadsPanel");
  const btn   = document.getElementById("downloadsBtn");
  const isOpen = panel.style.display !== "none";
  panel.style.display = isOpen ? "none" : "block";
  btn.setAttribute("aria-expanded", String(!isOpen));
}
```

Add directly after it:

```js

// ── Recent Updates changelog panel ────────────────────────────────────────────
let _changelogEntries = [];

async function loadChangelog() {
  try {
    const res  = await fetch("changelog.json?v=" + Date.now());
    if (!res.ok) throw new Error(res.status);
    const data = await res.json();
    _changelogEntries = data.entries || [];
    if (!_changelogEntries.length) return;
    document.getElementById("changelogPanelDate").textContent =
      "Last updated " + formatChangelogDate(_changelogEntries[0].date);
    renderChangelog();
    document.getElementById("changelogBtn").style.display = "flex";
  } catch(_) {}
}

function formatChangelogDate(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function changelogEntryHtml(entry) {
  return `
    <div class="changelog-entry">
      <div class="changelog-entry-hdr"><strong>v${entry.version}</strong><span class="changelog-date">${formatChangelogDate(entry.date)}</span></div>
      <ul>${entry.notes.map(n => `<li>${n}</li>`).join("")}</ul>
    </div>`;
}

function renderChangelog() {
  const cutoffMs = Date.now() - 30 * 24 * 60 * 60 * 1000;
  const recent = [];
  const monthGroups = new Map(); // "2026-07" -> entries[]

  for (const entry of _changelogEntries) {
    const entryMs = new Date(entry.date + "T00:00:00").getTime();
    if (entryMs >= cutoffMs) {
      recent.push(entry);
    } else {
      const key = entry.date.slice(0, 7);
      if (!monthGroups.has(key)) monthGroups.set(key, []);
      monthGroups.get(key).push(entry);
    }
  }

  const monthHtml = [...monthGroups.entries()].map(([key, entries]) => {
    const [y, m] = key.split("-").map(Number);
    const label = new Date(y, m - 1, 1).toLocaleDateString("en-US", { month: "long", year: "numeric" });
    return `
    <div class="tool-section collapsed changelog-month" data-month="${key}">
      <button class="section-label" onclick="toggleChangelogMonth('${key}')" aria-expanded="false">
        <span>${label} (${entries.length} update${entries.length !== 1 ? "s" : ""})</span>
        <svg class="section-chevron" xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>
      </button>
      <div class="section-collapse">
        <div class="section-collapse-inner">
          ${entries.map(changelogEntryHtml).join("")}
        </div>
      </div>
    </div>`;
  }).join("");

  document.getElementById("changelogPanelList").innerHTML =
    recent.map(changelogEntryHtml).join("") + monthHtml;
}

function toggleChangelogMonth(key) {
  const el = document.querySelector(`.changelog-month[data-month="${key}"]`);
  if (!el) return;
  const collapsed = el.classList.toggle("collapsed");
  el.querySelector(".section-label").setAttribute("aria-expanded", String(!collapsed));
}

function toggleChangelogPanel() {
  const panel = document.getElementById("changelogPanel");
  const btn   = document.getElementById("changelogBtn");
  const isOpen = panel.style.display !== "none";
  panel.style.display = isOpen ? "none" : "flex";
  btn.setAttribute("aria-expanded", String(!isOpen));
}
```

- [ ] **Step 2: Close the panel on outside click**

Find this block (around line 1138-1145):

```js
  const dlPanel = document.getElementById("downloadsPanel");
  const dlBtn   = document.getElementById("downloadsBtn");
  if (dlPanel && dlPanel.style.display !== "none") {
    if (!dlPanel.contains(e.target) && !dlBtn.contains(e.target)) {
      dlPanel.style.display = "none";
      dlBtn.setAttribute("aria-expanded", "false");
    }
  }
});
```

Insert this before the closing `});` of that same `document.addEventListener("click", ...)` handler:

```js
  const clPanel = document.getElementById("changelogPanel");
  const clBtn   = document.getElementById("changelogBtn");
  if (clPanel && clPanel.style.display !== "none") {
    if (!clPanel.contains(e.target) && !clBtn.contains(e.target)) {
      clPanel.style.display = "none";
      clBtn.setAttribute("aria-expanded", "false");
    }
  }
```

- [ ] **Step 3: Close the panel on Escape**

Find this block (around line 1156-1161):

```js
  const dlPanel = document.getElementById("downloadsPanel");
  const dlBtn   = document.getElementById("downloadsBtn");
  if (dlPanel && dlPanel.style.display !== "none") {
    dlPanel.style.display = "none";
    if (dlBtn) dlBtn.setAttribute("aria-expanded", "false");
  }
});
```

Insert this before the closing `});` of that same `document.addEventListener("keydown", ...)` handler:

```js
  const clPanel = document.getElementById("changelogPanel");
  const clBtn   = document.getElementById("changelogBtn");
  if (clPanel && clPanel.style.display !== "none") {
    clPanel.style.display = "none";
    if (clBtn) clBtn.setAttribute("aria-expanded", "false");
  }
```

- [ ] **Step 4: Load the changelog at boot**

Find (around line 1164):

```js
loadTools();
```

Change to:

```js
loadTools();
loadChangelog();
```

- [ ] **Step 5: Syntax-check the inline script**

Run:
```bash
node -e "const fs=require('fs');const h=fs.readFileSync('index.html','utf8');const m=h.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/);fs.writeFileSync(process.env.TEMP+'/it_hub.js',m[1]);" && node --check "$TEMP/it_hub.js" && echo "JS OK"
```
Expected: `JS OK`

- [ ] **Step 6: Verify in the browser**

Serve the repo root (same command as Task 2, Step 4) and open `http://localhost:8791/index.html`. Confirm:
- A megaphone icon button appears in the topbar, between the theme toggle and the Downloads button (Downloads itself may stay hidden — it only shows once signed in — but the changelog button should show unconditionally, since `loadChangelog()` runs unconditionally at boot).
- Clicking it opens the panel showing "v2.3.3" and "v2.3.2" entries (both are within 30 days of a real clock, so no month buckets will appear yet — that's expected with only two seed entries).
- The panel header shows "Last updated Aug 27, 2026".
- Clicking outside the panel, or pressing Escape, closes it.
- Opening/closing the panel does not shift or resize the tool grid underneath it.
- The panel's own scrollbar (if you temporarily add enough entries to `changelog.json` to force overflow — optional, revert after) shows the same glass-styled thumb as Task 2.

Stop the server once confirmed.

- [ ] **Step 7: Commit**

```bash
git add index.html
git commit -m "Wire up Recent Updates panel: fetch, render, month grouping, dismiss"
```

---

## Task 5: Push to preview

**Files:** none (deploy step only)

- [ ] **Step 1: Push `testing`**

```bash
git push origin testing
```

- [ ] **Step 2: Confirm the preview deploy succeeded**

```bash
curl -s "https://api.github.com/repos/jgdev-ch/it-tools/actions/runs?branch=testing&per_page=3" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));for(const r of d.workflow_runs.slice(0,3))console.log(r.head_sha.slice(0,7),r.name,r.status,r.conclusion);"
```
Confirm the row for the commit just pushed (match `head_sha` to `git log -1 --format=%h`) shows `completed success`.

- [ ] **Step 3: Manual check on the live preview URL**

Open `https://jgdev-ch.github.io/it-tools-preview/` and repeat the checks from Task 4, Step 6 against the real deployed site (this also exercises the real MSAL redirect URI, unlike the local server).

Do **not** merge to `main` as part of this plan — per this repo's standing rule, promotion to `main` is Josh's call, done explicitly, not automatically after a testing push.
