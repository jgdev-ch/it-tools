# On-Call Rotation Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `tools/on-call/index.html`'s current flat-table UI with the calendar-strip design approved in `docs/superpowers/specs/2026-09-02-oncall-rotation-visual-redesign-design.md`: a restyled hero, a navigable month-grouped calendar strip with a click-to-edit detail panel, and a matched, color-coded contacts roster using the same panel pattern.

**Architecture:** Single-file rewrite of `tools/on-call/index.html` (this hub has no build step; every tool, including this one, is one self-contained HTML file per existing convention, and files in the 700-2200 line range are normal here, e.g. `tools/finance-dashboard/index.html` at 2234 lines). No changes to `data.json`'s shape, `shared/`, `config.json`, or either backend function. All new code is additive/replacing within this one file. Verification is manual + Playwright against a local static server, matching how the original 2026-09-02 on-call build was verified (this repo has no unit-test framework; it doesn't use one anywhere).

**Tech Stack:** Vanilla JS/HTML/CSS, no framework, no build step. Real inline Lucide SVGs (fetched from `lucide-static` and hand-copied, per the icon step below) instead of emoji/unicode, matching every other tool in the hub. No em dashes in any UI copy string.

---

### Task 1: Shared tokens: person-color map, Lucide icon constants, layout CSS reset

**Files:**
- Modify: `tools/on-call/index.html` (the `<style>` block, currently lines 10-30, and the top of the `<script>` block, currently lines 78-87)

This task lands the foundational pieces every later task depends on: the color each person is drawn with everywhere, the exact icon markup, and the base layout CSS. Nothing here is user-visible yet (old rendering functions still run), so this is deliberately a safe first commit.

- [ ] **Step 1: Replace the tool-specific `<style>` block**

Replace the current block (from `.main-content { max-width:900px; ... }` through `.other-contacts-label { ... }`, i.e. lines 15-29 of the current file) with:

```css
    .main-content { max-width:960px; margin:0 auto; padding:24px 24px 60px; }

    /* ── Hero ── */
    .hero { display:flex; align-items:center; gap:14px; border-radius:14px; padding:18px 20px; margin-bottom:20px;
            background:linear-gradient(135deg, var(--blue), color-mix(in srgb, var(--blue) 75%, #7b6bff)); color:#fff; }
    .hero-avatar { width:48px; height:48px; border-radius:50%; background:rgba(255,255,255,.22); display:flex; align-items:center;
                   justify-content:center; font-weight:700; font-size:17px; flex-shrink:0; }
    .hero-label { font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:.06em; opacity:.85; }
    .hero-name { font-size:22px; font-weight:700; margin:2px 0 8px; }
    .hero-phones { display:flex; gap:6px; flex-wrap:wrap; }
    .hero-chip { font-size:11px; background:rgba(255,255,255,.18); border-radius:20px; padding:3px 10px; }

    /* ── Calendar nav ── */
    .cal-navbar { display:flex; align-items:center; justify-content:space-between; gap:10px; margin-bottom:10px; }
    .year-seg { display:inline-flex; background:var(--surface-2, var(--surface)); border:1px solid var(--border); border-radius:8px; padding:2px; }
    .year-seg span { padding:5px 12px; border-radius:6px; font-size:12px; cursor:pointer; }
    .year-seg span.on { background:var(--blue); color:#fff; font-weight:700; }
    .cal-search { border:1px solid var(--border); border-radius:6px; padding:5px 10px; font-size:12px; background:var(--surface);
                  color:var(--text); width:150px; }
    .cal-nav-btns { display:flex; align-items:center; gap:6px; }
    .cal-nav-btns button { display:flex; align-items:center; gap:4px; background:var(--surface); border:1px solid var(--border);
                            border-radius:6px; padding:5px 10px; font-size:12px; cursor:pointer; color:var(--text); }
    .cal-nav-btns button.today-btn { background:var(--blue); color:#fff; border-color:var(--blue); font-weight:600; }

    /* ── Calendar strip ── */
    .month-row { display:flex; gap:6px; margin-bottom:4px; }
    .month-lbl { font-size:10px; font-weight:700; color:var(--muted); text-transform:uppercase; letter-spacing:.05em; }
    .week-strip { display:flex; gap:6px; margin-bottom:8px; }
    .week-tile { flex:1; border:1px solid var(--border); border-radius:10px; padding:10px 8px; text-align:center;
                 background:var(--surface); cursor:pointer; position:relative; transition:box-shadow .15s; }
    .week-tile:hover { box-shadow:0 2px 8px rgba(0,0,0,.08); }
    .week-tile.today { border-color:var(--blue); box-shadow:0 0 0 2px color-mix(in srgb, var(--blue) 25%, transparent); }
    .week-tile .tile-date { font-size:10px; color:var(--muted); }
    .week-tile .tile-dot { width:30px; height:30px; border-radius:50%; margin:6px auto 4px; display:flex; align-items:center;
                            justify-content:center; font-size:10px; font-weight:700; color:#fff; }
    .week-tile .tile-name { font-size:11px; font-weight:600; }
    .week-tile .ribbon { position:absolute; top:-8px; left:50%; transform:translateX(-50%); background:var(--blue); color:#fff;
                          font-size:9px; padding:2px 8px; border-radius:10px; font-weight:700; }
    .week-tile .tile-flags { position:absolute; top:5px; right:6px; display:flex; gap:3px; color:var(--muted); }
    .week-tile .tile-flags svg { display:block; }

    .overview-rail { display:flex; gap:2px; margin-bottom:20px; cursor:pointer; }
    .overview-rail .rail-seg { flex:1; height:6px; border-radius:2px; opacity:.35; }
    .overview-rail .rail-seg.in-view { opacity:1; }
    .overview-rail .rail-seg.now { outline:1px solid var(--blue); }

    /* ── Roster ── */
    .roster-section { margin-top:24px; }
    .roster-lbl { font-size:11px; font-weight:700; color:var(--muted); text-transform:uppercase; letter-spacing:.05em; margin:0 0 8px; }
    .roster-grid { display:grid; grid-template-columns:repeat(3, 1fr); gap:10px; margin-bottom:20px; }
    .roster-card { border:1px solid var(--border); border-radius:10px; padding:12px; background:var(--surface); cursor:pointer;
                   transition:box-shadow .15s; }
    .roster-card:hover { box-shadow:0 2px 8px rgba(0,0,0,.08); }
    .roster-card.dim { opacity:.6; }
    .roster-card-top { display:flex; align-items:center; gap:8px; margin-bottom:8px; }
    .roster-dot { width:32px; height:32px; border-radius:50%; display:flex; align-items:center; justify-content:center;
                  font-size:11px; font-weight:700; color:#fff; flex-shrink:0; }
    .roster-name { font-size:13px; font-weight:700; }
    .roster-role { font-size:10px; color:var(--muted); }
    .roster-chips { display:flex; gap:4px; flex-wrap:wrap; }
    .roster-chip { font-size:10px; background:var(--surface-2, rgba(0,0,0,.05)); color:var(--muted); padding:2px 8px; border-radius:9px; }
    .roster-chip.more { background:transparent; color:var(--blue); font-weight:700; padding:2px 2px; }
    .add-tile { border:1px dashed var(--border); border-radius:10px; display:flex; align-items:center; justify-content:center;
                gap:6px; color:var(--muted); font-size:12px; font-weight:600; cursor:pointer; min-height:70px; }
    .add-tile:hover { border-color:var(--blue); color:var(--blue); }

    /* ── Detail panel (shared: calendar week + roster contact) ── */
    #panelBackdrop { position:fixed; inset:0; background:rgba(0,0,0,0); pointer-events:none; transition:background .15s; z-index:40; }
    #panelBackdrop.open { background:rgba(0,0,0,.25); pointer-events:auto; }
    #detailPanel { position:fixed; top:0; right:0; bottom:0; width:340px; background:var(--surface); border-left:1px solid var(--border);
                   box-shadow:-8px 0 24px rgba(0,0,0,.12); transform:translateX(100%); transition:transform .2s; z-index:41;
                   padding:20px; overflow-y:auto; }
    #detailPanel.open { transform:translateX(0); }
    .panel-head { display:flex; align-items:center; gap:10px; margin-bottom:16px; }
    .panel-dot { width:34px; height:34px; border-radius:50%; display:flex; align-items:center; justify-content:center;
                 font-weight:700; font-size:12px; color:#fff; flex-shrink:0; }
    .panel-title { font-size:14px; font-weight:700; color:var(--text); }
    .panel-sub { font-size:11px; color:var(--muted); }
    .panel-badge { font-size:10px; background:#fef3c7; color:#92400e; padding:2px 9px; border-radius:10px; font-weight:700; margin-left:auto; }
    .panel-close { background:none; border:none; cursor:pointer; color:var(--muted); padding:4px; margin-left:4px; }
    .panel-row, .panel-field { margin-bottom:12px; }
    .panel-row label, .panel-field label { display:block; font-size:10px; text-transform:uppercase; color:var(--muted);
                                            letter-spacing:.05em; margin-bottom:4px; font-weight:700; }
    .panel-value { font-size:13px; color:var(--text); }
    .panel-input, .panel-select { width:100%; border:1px solid var(--border); border-radius:6px; padding:7px 9px; font-size:12px;
                                   background:var(--bg); color:var(--text); box-sizing:border-box; font-family:inherit; }
    .panel-toggle-row { display:flex; align-items:center; justify-content:space-between; font-size:12px; margin-bottom:12px; }
    .panel-toggle-row label { margin:0; text-transform:none; font-size:12px; font-weight:400; color:var(--text); }
    .phone-chip-row { font-size:12px; color:var(--text); margin-bottom:4px; }
    .phone-row { display:flex; gap:6px; margin-bottom:6px; align-items:center; }
    .phone-row .panel-input.phone-label { flex:0 0 90px; }
    .phone-row .panel-input.phone-num { flex:1; }
    .phone-rm { color:#c33; cursor:pointer; display:flex; }
    .add-phone-link { display:flex; align-items:center; gap:5px; font-size:11px; color:var(--blue); font-weight:600; cursor:pointer;
                       margin-bottom:14px; }
    .panel-btnrow { display:flex; gap:8px; margin-top:16px; }
    .panel-btnrow .btn { flex:1; }
```

- [ ] **Step 2: Add person-color, icon, and layout constants to the `<script>` block**

Insert immediately after the existing `const ONCALL_SAVE_URL = "";` line (currently line 85) and before `const st = { data: null, year: "2026", isAdmin: false };` (currently line 87):

```javascript
const PERSON_PALETTE      = ["#059669", "#1a56db", "#d97706", "#9333ea", "#dc2626", "#0891b2", "#db2777"];
const OTHER_CONTACT_COLOR = "#9ca3af";
const WEEKS_VISIBLE       = 5;

const ICON_CHEVRON_LEFT  = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>`;
const ICON_CHEVRON_RIGHT = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>`;
const ICON_SEARCH        = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/></svg>`;
const ICON_PLUS          = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>`;
const ICON_X             = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>`;
const ICON_FILE_TEXT     = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"/><path d="M14 2v5a1 1 0 0 0 1 1h5"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg>`;
const ICON_PALMTREE      = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13 8c0-2.76-2.46-5-5.5-5S2 5.24 2 8h2l1-1 1 1h4"/><path d="M13 7.14A5.82 5.82 0 0 1 16.5 6c3.04 0 5.5 2.24 5.5 5h-3l-1-1-1 1h-3"/><path d="M5.89 9.71c-2.15 2.15-2.3 5.47-.35 7.43l4.24-4.25.7-.7.71-.71 2.12-2.12c-1.95-1.96-5.27-1.8-7.42.35"/><path d="M11 15.5c.5 2.5-.17 4.5-1 6.5h4c2-5.5-.5-12-1-14"/></svg>`;

function initials(name) {
  return name.split(" ").map(p => p[0]).filter(Boolean).slice(0, 2).join("").toUpperCase();
}

function buildPersonColors(data) {
  const map = {};
  data.rotationTechs.forEach((t, i) => { map[t.shortName] = PERSON_PALETTE[i % PERSON_PALETTE.length]; });
  return map;
}

function personColorFor(shortName) {
  return st.personColors[shortName] || OTHER_CONTACT_COLOR;
}
```

Icon SVGs above were fetched verbatim from `lucide-static` (`chevron-left`, `chevron-right`, `search`, `plus`, `x`, `file-text`, `palmtree`) with only the `width`/`height` attributes reduced from the library default of 24 to fit these compact UI elements, and the `class="lucide lucide-*"` attribute dropped (unused, matches how `config.json`'s existing tool icons already strip it).

- [ ] **Step 3: Verify the page still loads with no console errors**

Open `tools/on-call/index.html` via a local static server (e.g. `/c/dev/tools/nodejs/node.exe -e "require('http').createServer((q,s)=>require('fs').readFile('.'+decodeURI(q.url==='/'?'/tools/on-call/index.html':q.url),(e,d)=>{s.end(e?'404':d)})).listen(8790)"` run from the repo root) and load `http://localhost:8790/`. The page should render exactly as before (old table/cards) since no rendering function has changed yet, just added constants and CSS. Confirm via browser devtools console: no errors, and `typeof buildPersonColors === "function"` evaluates `true`.

- [ ] **Step 4: Commit**

```bash
cd /c/dev/projects/it-tools
git add tools/on-call/index.html
git commit -m "On-Call Rotation redesign: add person-color map, Lucide icon constants, new layout CSS"
```

---

### Task 2: Hero card restyle

**Files:**
- Modify: `tools/on-call/index.html` (`renderHero()`, currently lines 168-180; the `init()`/`afterSignIn()` flow needs `st.personColors` populated before first render)

- [ ] **Step 1: Populate `st.personColors` once data loads**

In `loadData()` (currently lines 135-145), add the color-map build immediately after `st.data` is assigned in both branches. Replace the whole function body with:

```javascript
async function loadData() {
  if (ONCALL_GET_URL) {
    const token = await ITTools.auth.getToken();
    const res = await fetch(ONCALL_GET_URL, { headers: { Authorization: "Bearer " + token } });
    st.data = await res.json();
  } else {
    const res = await fetch("data.json?v=" + Date.now());
    st.data = await res.json();
  }
  st.personColors = buildPersonColors(st.data);
  renderAll();
}
```

- [ ] **Step 2: Rewrite `renderHero()`**

Replace the current function (lines 168-180) with:

```javascript
function renderHero() {
  const week = findCurrentWeek(st.data.schedule);
  const hero = document.getElementById("heroCard");
  if (!week) { hero.innerHTML = "<p>No current on-call week found.</p>"; return; }
  const tech = st.data.rotationTechs.find(t => t.shortName === week.tech);
  const name = tech ? tech.name : week.tech;
  const color = personColorFor(week.tech);
  hero.innerHTML = `
    <div class="hero-avatar" style="background:${color}">${initials(name)}</div>
    <div>
      <div class="hero-label">On Call This Week</div>
      <div class="hero-name">${name}</div>
      <div class="hero-phones">
        ${(tech ? tech.phones : []).map(p => `<span class="hero-chip">${p.label} ${p.number}</span>`).join("")}
      </div>
    </div>
  `;
}
```

Note this drops the gradient background color set inline via `background:${color}` on the avatar circle specifically (not the whole hero card, which keeps its fixed blue gradient from Task 1's CSS) so the avatar always shows that person's own color even though the card itself stays on-brand blue.

- [ ] **Step 3: Verify via Playwright against the local static server**

Using the same local server from Task 1 Step 3 (or restart it), use the Playwright MCP tools to navigate to the tool, then in the page evaluate a bypass of the MSAL wall the same way the original 2026-09-02 build's plan did: reveal `#appScreen`/`#toolContent` directly and call `loadData()` from the console (or via `browser_evaluate`). Confirm:
- The hero shows a colored circular avatar with initials (e.g. "NZ" for whoever `findCurrentWeek` resolves to for the current date)
- Phone chips render as small pills, not the old inline label/value text

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation redesign: restyle hero card with colored avatar and phone chips"
```

---

### Task 3: Calendar strip markup, rendering, and navigation

**Files:**
- Modify: `tools/on-call/index.html` (replace the year-tabs + table markup, currently lines 63-69, and replace `renderAll()`/`renderYearTabs()`/`setYear()`/`renderScheduleTable()`/`updateScheduleField()`, currently lines 147-229)

This task lands the full calendar strip as **read-only** (no click-to-edit panel yet, that's Task 4). Clicking a tile does nothing until Task 4.

- [ ] **Step 1: Replace the year-tabs + table HTML**

Replace the current block:
```html
        <div class="hero" id="heroCard"></div>
        <div class="year-tabs" id="yearTabs"></div>
        <div class="tbl-wrap">
          <table class="review-tbl" style="width:100%;border-collapse:collapse">
            <thead><tr><th>Start Date</th><th>Tech</th><th>Time Off</th><th>Notes</th></tr></thead>
            <tbody id="scheduleBody"></tbody>
          </table>
        </div>
        <div class="contact-cards" id="rotationCards"></div>
        <div class="other-contacts-label">Other Contacts</div>
        <div class="contact-cards" id="otherCards"></div>
```

with:
```html
        <div class="hero" id="heroCard"></div>

        <div class="cal-navbar">
          <div class="year-seg" id="yearSeg"></div>
          <input class="cal-search" id="searchInput" placeholder="Jump to person"
                 onkeydown="if(event.key==='Enter') searchPerson(this.value)"/>
          <div class="cal-nav-btns">
            <button onclick="shiftStrip(-1)" id="navPrevBtn"></button>
            <button class="today-btn" onclick="goToday()">Today</button>
            <button onclick="shiftStrip(1)" id="navNextBtn"></button>
          </div>
        </div>
        <div class="month-row" id="monthRow"></div>
        <div class="week-strip" id="weekStrip"></div>
        <div class="overview-rail" id="overviewRail"></div>

        <div class="roster-section">
          <div class="roster-lbl" id="rotationLbl"></div>
          <div class="roster-grid" id="rotationGrid"></div>
          <div class="roster-lbl">Other Contacts</div>
          <div class="roster-grid" id="otherGrid"></div>
        </div>
```

(`rotationGrid`/`otherGrid`/`rotationLbl` are wired up in Task 6; leave them rendering empty for now, that's expected and not a bug in this task.)

- [ ] **Step 2: Add nav button icons on init**

In `init()` (currently the function starting at line 273), add these two lines right after `ITTools.ui.syncThemeIcon();`:

```javascript
  document.getElementById("navPrevBtn").innerHTML = ICON_CHEVRON_LEFT + " Prev";
  document.getElementById("navNextBtn").innerHTML = "Next " + ICON_CHEVRON_RIGHT;
```

- [ ] **Step 3: Replace `renderAll()`, `renderYearTabs()`, `setYear()`, `renderScheduleTable()`, and `updateScheduleField()`**

Replace the whole block from `function renderAll() {` through the end of `updateScheduleField()` (currently lines 147-229, i.e. everything between the `findCurrentWeek`/`renderHero` section and the `// ── Contacts ──` comment) with:

```javascript
function renderAll() {
  renderHero();
  renderYearSeg();
  renderCalendarStrip();
  renderRoster();
}

// ── Calendar strip ──────────────────────────────────────────
function getYearWeeks(year) {
  return st.data.schedule.filter(r => r.startDate.startsWith(year));
}

function renderYearSeg() {
  const years = ["2024", "2025", "2026"];
  document.getElementById("yearSeg").innerHTML = years.map(y =>
    `<span class="${y === st.year ? "on" : ""}" onclick="setYear('${y}')">${y}</span>`
  ).join("");
}

function setYear(y) {
  st.year = y;
  st.stripStart = 0;
  renderYearSeg();
  renderCalendarStrip();
}

function shiftStrip(direction) {
  st.stripStart += direction * WEEKS_VISIBLE;
  renderCalendarStrip();
}

function jumpToWeek(indexInYear) {
  const weeks = getYearWeeks(st.year);
  const maxStart = Math.max(0, weeks.length - WEEKS_VISIBLE);
  st.stripStart = Math.min(Math.max(0, indexInYear - Math.floor(WEEKS_VISIBLE / 2)), maxStart);
  renderCalendarStrip();
}

function goToday() {
  const week = findCurrentWeek(st.data.schedule);
  if (!week) return;
  st.year = week.startDate.slice(0, 4);
  renderYearSeg();
  const weeks = getYearWeeks(st.year);
  jumpToWeek(weeks.findIndex(w => w.startDate === week.startDate));
}

function searchPerson(query) {
  const q = query.trim().toLowerCase();
  if (!q) return;
  const weeks = getYearWeeks(st.year);
  if (!weeks.length) return;
  for (let step = 1; step <= weeks.length; step++) {
    const idx = (st.stripStart + step) % weeks.length;
    const tech = st.data.rotationTechs.find(t => t.shortName === weeks[idx].tech);
    const name = (tech ? tech.name : weeks[idx].tech).toLowerCase();
    if (name.includes(q)) { jumpToWeek(idx); return; }
  }
}

function monthLabelsHtml(weeks) {
  const groups = [];
  weeks.forEach(w => {
    const label = new Date(w.startDate + "T00:00:00Z").toLocaleDateString("en-US", { month: "short", timeZone: "UTC" }).toUpperCase();
    if (groups.length && groups[groups.length - 1].label === label) groups[groups.length - 1].count++;
    else groups.push({ label, count: 1 });
  });
  return groups.map(g => `<div class="month-lbl" style="flex:${g.count}">${g.label}</div>`).join("");
}

function tileHtml(row, todayStr) {
  const tech = st.data.rotationTechs.find(t => t.shortName === row.tech);
  const name = tech ? tech.name : row.tech;
  const color = personColorFor(row.tech);
  const dayNum = new Date(row.startDate + "T00:00:00Z").getUTCDate();
  const flags = (row.notes ? ICON_FILE_TEXT : "") + (row.timeOff ? ICON_PALMTREE : "");
  const isToday = row.startDate === todayStr;
  return `
    <div class="week-tile${isToday ? " today" : ""}" onclick="openWeekPanel('${row.startDate}')">
      ${isToday ? `<div class="ribbon">Today</div>` : ""}
      ${flags ? `<div class="tile-flags">${flags}</div>` : ""}
      <div class="tile-date">${dayNum}</div>
      <div class="tile-dot" style="background:${color}">${initials(name)}</div>
      <div class="tile-name">${row.tech}</div>
    </div>`;
}

function renderCalendarStrip() {
  const weeks = getYearWeeks(st.year);
  const todayWeek = findCurrentWeek(st.data.schedule);
  const todayStr = todayWeek ? todayWeek.startDate : null;
  const maxStart = Math.max(0, weeks.length - WEEKS_VISIBLE);
  st.stripStart = Math.min(Math.max(0, st.stripStart), maxStart);
  const visible = weeks.slice(st.stripStart, st.stripStart + WEEKS_VISIBLE);

  document.getElementById("monthRow").innerHTML = monthLabelsHtml(visible);
  document.getElementById("weekStrip").innerHTML = visible.map(w => tileHtml(w, todayStr)).join("");
  document.getElementById("overviewRail").innerHTML = weeks.map((w, i) => `
    <div class="rail-seg${w.startDate === todayStr ? " now" : ""}${i >= st.stripStart && i < st.stripStart + WEEKS_VISIBLE ? " in-view" : ""}"
         style="background:${personColorFor(w.tech)}" title="${w.startDate}: ${w.tech}" onclick="jumpToWeek(${i})"></div>
  `).join("");
}
```

Note `updateScheduleField` is intentionally not carried forward. It only existed to support the old naked-`<input>`-per-cell editing; Task 5's panel-based save replaces it entirely with a lookup-by-`startDate` mutation.

- [ ] **Step 4: Add `stripStart` to initial state**

Update the `st` object declaration (currently line 87) to:

```javascript
const st = { data: null, year: "2026", isAdmin: false, stripStart: 0, panel: null, draft: null };
```

(`panel`/`draft` are unused until Task 4/5 but declaring them now keeps the state shape stable across tasks.)

- [ ] **Step 5: Verify via Playwright**

Reload the tool against the local static server (same bypass approach as Task 2). Confirm:
- Year segmented control shows 2024/2025/2026, clicking each re-renders the strip for that year starting from `stripStart = 0`
- The strip shows 5 tiles with month labels grouped correctly above them (e.g. two tiles under "AUG", three under "SEP" if the visible window spans a month boundary)
- Whichever tile contains the real current date has the "Today" ribbon and highlighted border
- Prev/Next buttons page the strip by 5 weeks, clamped at both ends (clicking Prev repeatedly does not go negative, clicking Next repeatedly does not run past the last week)
- The Today button jumps to the correct year and centers the strip on today's tile
- Typing a rotation tech's name (e.g. "Krista") into the search box and pressing Enter jumps the strip to their next occurrence
- Clicking a segment in the full-year overview rail jumps the main strip there
- Clicking any tile does nothing yet (expected, Task 4 wires it up)

- [ ] **Step 6: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation redesign: replace flat table with navigable calendar strip"
```

---

### Task 4: Detail panel shell + read-only week view

**Files:**
- Modify: `tools/on-call/index.html` (add panel markup after `toolContent`'s closing structure, currently around line 73; add panel JS functions)

- [ ] **Step 1: Add the panel markup**

Insert immediately before the closing `</div>` of `#appScreen` (currently line 76, right after the `</main>` close), i.e. as a sibling of `<main class="main-content">`:

```html
      <div id="panelBackdrop" onclick="closePanel()"></div>
      <div id="detailPanel">
        <div class="panel-head">
          <div class="panel-dot" id="panelDot"></div>
          <div>
            <div class="panel-title" id="panelTitle"></div>
            <div class="panel-sub" id="panelSub"></div>
          </div>
          <span class="panel-badge" id="panelBadge" style="display:none">Edit Mode</span>
          <button class="panel-close" id="panelCloseBtn" onclick="closePanel()"></button>
        </div>
        <div id="panelBody"></div>
      </div>
```

- [ ] **Step 2: Set the close-button icon on init**

Add this line in `init()`, alongside the nav-icon lines added in Task 3 Step 2:

```javascript
  document.getElementById("panelCloseBtn").innerHTML = ICON_X;
```

- [ ] **Step 3: Add the panel shell and week-panel functions**

Add this new section right after the `renderCalendarStrip()` function from Task 3:

```javascript
// ── Detail panel (shared shell) ─────────────────────────────
function openPanelShell(color, ini, title, sub) {
  document.getElementById("panelDot").style.background = color;
  document.getElementById("panelDot").textContent = ini;
  document.getElementById("panelTitle").textContent = title;
  document.getElementById("panelSub").textContent = sub;
  document.getElementById("panelBadge").style.display = st.draft ? "inline-block" : "none";
  document.getElementById("detailPanel").classList.add("open");
  document.getElementById("panelBackdrop").classList.add("open");
}

function closePanel() {
  st.panel = null;
  st.draft = null;
  document.getElementById("detailPanel").classList.remove("open");
  document.getElementById("panelBackdrop").classList.remove("open");
}

function renderPanel() {
  if (!st.panel) return;
  if (st.panel.kind === "week") renderWeekPanelBody();
  else renderContactPanelBody();
}

// ── Week panel ───────────────────────────────────────────────
function openWeekPanel(startDate) {
  const row = st.data.schedule.find(r => r.startDate === startDate);
  const tech = st.data.rotationTechs.find(t => t.shortName === row.tech);
  const name = tech ? tech.name : row.tech;
  st.panel = { kind: "week", startDate };
  st.draft = null;
  openPanelShell(personColorFor(row.tech), initials(name), "Week of " + row.startDate, name);
  renderWeekPanelBody();
}

function renderWeekPanelBody() {
  const row = st.data.schedule.find(r => r.startDate === st.panel.startDate);
  const tech = st.data.rotationTechs.find(t => t.shortName === row.tech);
  const phones = tech ? tech.phones : [];
  document.getElementById("panelBody").innerHTML = `
    <div class="panel-row"><label>On-Call Tech</label><div class="panel-value">${tech ? tech.name : row.tech}</div></div>
    <div class="panel-row"><label>Phone Numbers</label>
      ${phones.length ? phones.map(p => `<div class="phone-chip-row"><strong>${p.label}:</strong> ${p.number}</div>`).join("")
                       : `<div class="phone-chip-row">No numbers on file</div>`}
    </div>
    ${row.timeOff ? `<div class="panel-row"><label>Time Off</label><div class="panel-value">${row.timeOff}</div></div>` : ""}
    ${row.notes ? `<div class="panel-row"><label>Notes</label><div class="panel-value">${row.notes}</div></div>` : ""}
  `;
}
```

- [ ] **Step 4: Verify via Playwright**

Reload the tool. Confirm:
- Clicking any week-tile slides the panel in from the right with a backdrop dimming the rest of the page
- The panel header shows the correct colored avatar, initials, week label, and person name (matching that tile)
- The body shows the phone list (or "No numbers on file" for a historical tech no longer in `rotationTechs`, e.g. an old David Wilhite row if one is visible)
- A week with `notes`/`timeOff` set (if any exist in `data.json`; if none do, temporarily edit a row's `notes` field in the loaded `st.data` via the console to test, without saving it back) shows those rows
- Clicking the backdrop or the close (X) button closes the panel
- The `Edit Mode` badge never appears (expected, `st.draft` is always `null` in this task)

- [ ] **Step 5: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation redesign: add slide-over detail panel with read-only week view"
```

---

### Task 5: Week panel edit mode + save

**Files:**
- Modify: `tools/on-call/index.html` (`openWeekPanel`/`renderWeekPanelBody`, `toggleEditMode`, add `saveWeekPanel`)

- [ ] **Step 1: Make `openWeekPanel` draft-aware**

Replace `openWeekPanel` (added in Task 4) with:

```javascript
function openWeekPanel(startDate) {
  const row = st.data.schedule.find(r => r.startDate === startDate);
  const tech = st.data.rotationTechs.find(t => t.shortName === row.tech);
  const name = tech ? tech.name : row.tech;
  st.panel = { kind: "week", startDate };
  st.draft = (st.isAdmin && editMode) ? JSON.parse(JSON.stringify(row)) : null;
  openPanelShell(personColorFor(row.tech), initials(name), "Week of " + row.startDate, st.draft ? "Editing this week's assignment" : name);
  renderWeekPanelBody();
}
```

- [ ] **Step 2: Make `renderWeekPanelBody` branch on `st.draft`**

Replace `renderWeekPanelBody` with:

```javascript
function renderWeekPanelBody() {
  const row = st.data.schedule.find(r => r.startDate === st.panel.startDate);
  if (!st.draft) {
    const tech = st.data.rotationTechs.find(t => t.shortName === row.tech);
    const phones = tech ? tech.phones : [];
    document.getElementById("panelBody").innerHTML = `
      <div class="panel-row"><label>On-Call Tech</label><div class="panel-value">${tech ? tech.name : row.tech}</div></div>
      <div class="panel-row"><label>Phone Numbers</label>
        ${phones.length ? phones.map(p => `<div class="phone-chip-row"><strong>${p.label}:</strong> ${p.number}</div>`).join("")
                         : `<div class="phone-chip-row">No numbers on file</div>`}
      </div>
      ${row.timeOff ? `<div class="panel-row"><label>Time Off</label><div class="panel-value">${row.timeOff}</div></div>` : ""}
      ${row.notes ? `<div class="panel-row"><label>Notes</label><div class="panel-value">${row.notes}</div></div>` : ""}
    `;
    return;
  }
  const options = st.data.rotationTechs.map(t =>
    `<option value="${t.shortName}"${t.shortName === st.draft.tech ? " selected" : ""}>${t.name}</option>`
  ).join("");
  document.getElementById("panelBody").innerHTML = `
    <div class="panel-field">
      <label>On-Call Tech</label>
      <select class="panel-select" onchange="st.draft.tech=this.value">${options}</select>
    </div>
    <div class="panel-field">
      <label>Time Off</label>
      <input class="panel-input" value="${st.draft.timeOff || ""}" onchange="st.draft.timeOff=this.value"/>
    </div>
    <div class="panel-field">
      <label>Notes</label>
      <textarea class="panel-input" rows="3" onchange="st.draft.notes=this.value">${st.draft.notes || ""}</textarea>
    </div>
    <div class="panel-btnrow">
      <button class="btn btn-secondary" onclick="closePanel()">Cancel</button>
      <button class="btn btn-primary" onclick="saveWeekPanel()">Save</button>
    </div>
  `;
}

function saveWeekPanel() {
  const row = st.data.schedule.find(r => r.startDate === st.panel.startDate);
  Object.assign(row, st.draft);
  closePanel();
  renderAll();
  saveChanges();
}
```

- [ ] **Step 3: Re-render the strip and panel when Edit Mode toggles**

Replace `toggleEditMode()` (currently lines 199-204) with:

```javascript
function toggleEditMode() {
  editMode = document.getElementById("editToggle").checked;
  document.getElementById("saveBtn").style.display = editMode ? "inline-block" : "none";
  closePanel();
  renderCalendarStrip();
  renderRoster();
}
```

(Closing any open panel when the toggle flips avoids a stale read-only panel staying open while `editMode` changes underneath it; `renderRoster()` is a forward reference to Task 6, harmless since Task 6 lands before this is exercised end-to-end in Task 8's final pass, and it already exists as a no-op-safe call target once Task 6 is committed. If running Task 5's verification before Task 6 is committed, temporarily comment out the `renderRoster()` line, verify, then restore it, since `renderRoster` doesn't exist yet at that point.)

- [ ] **Step 4: Verify via Playwright**

With the local static server, simulate an admin session (set `st.isAdmin = true` via console after load, matching the same bypass technique used for the original build's Task 2/3-7 verification) and toggle Edit Mode on:
- Click a week-tile: panel opens with the "Edit Mode" badge, a tech dropdown pre-selected to that week's current assignment, a Time Off input, and a Notes textarea
- Change the dropdown to a different tech, click Save: panel closes, that tile's avatar/initials/color update immediately to the new tech, and the console shows the `ONCALL_SAVE_URL not configured yet` warning (expected, matches current no-op-until-Task-11 behavior) rather than throwing
- Reopen the same tile: the new assignment persists in `st.data` (confirms the `Object.assign` write landed)
- Click Cancel instead of Save on a different tile: no change persists
- With Edit Mode off, clicking a tile shows the read-only view again (no dropdown/inputs)

- [ ] **Step 5: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation redesign: wire week panel edit mode with tech/time-off/notes form"
```

---

### Task 6: Roster grid (read-only)

**Files:**
- Modify: `tools/on-call/index.html` (replace `contactCardHtml`/`renderContacts`, currently lines 232-244, with the new grid; wire the panel's contact-read path)

- [ ] **Step 1: Replace `contactCardHtml` and `renderContacts`**

Replace the block from `// ── Contacts ──` through the end of `renderContacts()` (currently lines 231-244) with:

```javascript
// ── Roster ──────────────────────────────────────────────────
function rosterCardHtml(person, group, idx) {
  const color = group === "rotation" ? personColorFor(person.shortName) : OTHER_CONTACT_COLOR;
  const visiblePhones = person.phones.slice(0, 2);
  const extra = person.phones.length - visiblePhones.length;
  return `
    <div class="roster-card${group === "other" ? " dim" : ""}" onclick="openContactPanel('${group}', ${idx})">
      <div class="roster-card-top">
        <div class="roster-dot" style="background:${color}">${initials(person.name)}</div>
        <div>
          <div class="roster-name">${person.name}</div>
          <div class="roster-role">${group === "rotation" ? "Rotation" : "Other"}</div>
        </div>
      </div>
      <div class="roster-chips">
        ${visiblePhones.map(p => `<span class="roster-chip">${p.label}</span>`).join("")}
        ${extra > 0 ? `<span class="roster-chip more">+${extra}</span>` : ""}
      </div>
    </div>`;
}

function renderRoster() {
  document.getElementById("rotationLbl").textContent = `Rotation: ${st.data.rotationTechs.length} techs`;
  document.getElementById("rotationGrid").innerHTML =
    st.data.rotationTechs.map((t, i) => rosterCardHtml(t, "rotation", i)).join("");
  document.getElementById("otherGrid").innerHTML =
    st.data.otherContacts.map((t, i) => rosterCardHtml(t, "other", i)).join("");
}
```

- [ ] **Step 2: Add the contact read-only panel functions**

Add this section after `saveWeekPanel()` (from Task 5):

```javascript
// ── Contact panel ────────────────────────────────────────────
function openContactPanel(group, idx) {
  const person = st.data[group === "rotation" ? "rotationTechs" : "otherContacts"][idx];
  st.panel = { kind: "contact", group, idx };
  st.draft = null;
  const color = group === "rotation" ? personColorFor(person.shortName) : OTHER_CONTACT_COLOR;
  openPanelShell(color, initials(person.name), person.name, group === "rotation" ? "Rotation member" : "Other contact");
  renderContactPanelBody();
}

function renderContactPanelBody() {
  const person = st.data[st.panel.group === "rotation" ? "rotationTechs" : "otherContacts"][st.panel.idx];
  document.getElementById("panelBody").innerHTML = `
    <div class="panel-row"><label>Name</label><div class="panel-value">${person.name}</div></div>
    <div class="panel-row"><label>Phone Numbers</label>
      ${person.phones.length ? person.phones.map(p => `<div class="phone-chip-row"><strong>${p.label}:</strong> ${p.number}</div>`).join("")
                              : `<div class="phone-chip-row">No numbers on file</div>`}
    </div>
  `;
}
```

- [ ] **Step 3: Verify via Playwright**

Reload the tool. Confirm:
- Below the calendar strip, a "Rotation: 5 techs" section shows one card per `rotationTechs` entry, each avatar colored to match that same person's calendar tile color
- An "Other Contacts" section below it shows `otherContacts` entries, visually dimmed
- Any contact with more than 2 phone numbers shows a "+N" chip instead of listing every number
- Clicking any roster card opens the same slide-over panel as calendar tiles, read-only, showing the full phone list
- No "+ Add" tiles yet (expected, that's Task 7)

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation redesign: replace plain contact cards with color-coded roster grid"
```

---

### Task 7: Contact panel edit mode + add-tiles

**Files:**
- Modify: `tools/on-call/index.html` (`openContactPanel`/`renderContactPanelBody`, `rosterCardHtml`'s caller `renderRoster`, add save/add functions)

- [ ] **Step 1: Make `openContactPanel` draft-aware**

Replace `openContactPanel` with:

```javascript
function openContactPanel(group, idx) {
  const person = st.data[group === "rotation" ? "rotationTechs" : "otherContacts"][idx];
  st.panel = { kind: "contact", group, idx };
  st.draft = (st.isAdmin && editMode) ? JSON.parse(JSON.stringify(person)) : null;
  if (st.draft && st.draft.shortName === undefined) st.draft.shortName = "";
  const color = group === "rotation" ? personColorFor(person.shortName) : OTHER_CONTACT_COLOR;
  openPanelShell(color, initials(person.name), person.name, group === "rotation" ? "Rotation member" : "Other contact");
  renderContactPanelBody();
}
```

(`otherContacts` entries have no `shortName` field in the data model; defaulting it to `""` on the draft avoids `undefined` leaking into an input's value and gives a starting point if this contact gets moved into rotation.)

- [ ] **Step 2: Make `renderContactPanelBody` branch on `st.draft`, with phone row editing**

Replace `renderContactPanelBody` with:

```javascript
function renderContactPanelBody() {
  const person = st.data[st.panel.group === "rotation" ? "rotationTechs" : "otherContacts"][st.panel.idx];
  if (!st.draft) {
    document.getElementById("panelBody").innerHTML = `
      <div class="panel-row"><label>Name</label><div class="panel-value">${person.name}</div></div>
      <div class="panel-row"><label>Phone Numbers</label>
        ${person.phones.length ? person.phones.map(p => `<div class="phone-chip-row"><strong>${p.label}:</strong> ${p.number}</div>`).join("")
                                : `<div class="phone-chip-row">No numbers on file</div>`}
      </div>
    `;
    return;
  }
  document.getElementById("panelBody").innerHTML = `
    <div class="panel-field"><label>Full Name</label>
      <input class="panel-input" value="${st.draft.name}" onchange="st.draft.name=this.value"/>
    </div>
    <div class="panel-field"><label>Short Name</label>
      <input class="panel-input" value="${st.draft.shortName}" onchange="st.draft.shortName=this.value"/>
    </div>
    <div class="panel-toggle-row">
      <label>In Rotation</label>
      <label class="tog"><input type="checkbox" id="draftInRotation" ${st.panel.group === "rotation" ? "checked" : ""}/><div class="track"></div></label>
    </div>
    <div id="draftPhones"></div>
    <div class="add-phone-link" onclick="addDraftPhone()">${ICON_PLUS} Add phone number</div>
    <div class="panel-btnrow">
      <button class="btn btn-secondary" onclick="closePanel()">Cancel</button>
      <button class="btn btn-primary" onclick="saveContactPanel()">Save</button>
    </div>
  `;
  renderDraftPhones();
}

function renderDraftPhones() {
  document.getElementById("draftPhones").innerHTML = st.draft.phones.map((p, i) => `
    <div class="phone-row">
      <input class="panel-input phone-label" value="${p.label}" onchange="st.draft.phones[${i}].label=this.value"/>
      <input class="panel-input phone-num" value="${p.number}" onchange="st.draft.phones[${i}].number=this.value"/>
      <span class="phone-rm" onclick="removeDraftPhone(${i})">${ICON_X}</span>
    </div>`).join("");
}

function removeDraftPhone(i) {
  st.draft.phones.splice(i, 1);
  renderDraftPhones();
}

function addDraftPhone() {
  st.draft.phones.push({ label: "", number: "" });
  renderDraftPhones();
}

function saveContactPanel() {
  const wantsRotation = document.getElementById("draftInRotation").checked;
  if (wantsRotation && !st.draft.shortName.trim()) {
    alert("Short Name is required for rotation members (used to match them on the calendar).");
    return;
  }
  const currentlyRotation = st.panel.group === "rotation";
  const sourceArr = st.data[currentlyRotation ? "rotationTechs" : "otherContacts"];
  if (wantsRotation === currentlyRotation) {
    sourceArr[st.panel.idx] = st.draft;
  } else {
    sourceArr.splice(st.panel.idx, 1);
    st.data[wantsRotation ? "rotationTechs" : "otherContacts"].push(st.draft);
    st.personColors = buildPersonColors(st.data);
  }
  closePanel();
  renderAll();
  saveChanges();
}
```

- [ ] **Step 3: Add "+ Add" tiles and their handlers**

Update `renderRoster()` (from Task 6) to append an add-tile after each grid:

```javascript
function renderRoster() {
  document.getElementById("rotationLbl").textContent = `Rotation: ${st.data.rotationTechs.length} techs`;
  const rotationHtml = st.data.rotationTechs.map((t, i) => rosterCardHtml(t, "rotation", i)).join("");
  const otherHtml = st.data.otherContacts.map((t, i) => rosterCardHtml(t, "other", i)).join("");
  const addRotationTile = (st.isAdmin && editMode) ? `<div class="add-tile" onclick="addContact('rotation')">${ICON_PLUS} Add to Rotation</div>` : "";
  const addOtherTile = (st.isAdmin && editMode) ? `<div class="add-tile" onclick="addContact('other')">${ICON_PLUS} Add Contact</div>` : "";
  document.getElementById("rotationGrid").innerHTML = rotationHtml + addRotationTile;
  document.getElementById("otherGrid").innerHTML = otherHtml + addOtherTile;
}

function addContact(group) {
  const arr = st.data[group === "rotation" ? "rotationTechs" : "otherContacts"];
  const blank = group === "rotation" ? { name: "New Person", shortName: "", phones: [] } : { name: "New Person", phones: [] };
  arr.push(blank);
  renderRoster();
  openContactPanel(group, arr.length - 1);
}
```

- [ ] **Step 4: Verify via Playwright**

With `st.isAdmin = true` and Edit Mode on:
- Clicking a rotation contact's card opens the panel with Full Name, Short Name, an "In Rotation" toggle (checked), and editable phone rows with a working remove (✕) button and "+ Add phone number" link
- Turning "In Rotation" off and clicking Save moves that person's card into the Other Contacts section and it disappears from the calendar's color legend going forward (their old schedule rows fall back to the gray "no color match" rendering, same as a departed tech like David Wilhite)
- Turning "In Rotation" on for an Other Contact without filling Short Name and clicking Save shows the alert and does not save
- Filling Short Name and saving moves them into Rotation with their own new color
- "+ Add to Rotation" and "+ Add Contact" tiles appear only in Edit Mode, and clicking one adds a blank card and immediately opens its edit panel
- With Edit Mode off, no add-tiles appear and cards open read-only

- [ ] **Step 5: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation redesign: add contact edit mode, phone row management, and add-contact tiles"
```

---

### Task 8: Cleanup, full walkthrough, changelog

**Files:**
- Modify: `tools/on-call/index.html` (remove now-dead CSS/markup left over from the old table/card design, if any survived)
- Modify: `changelog.json`
- Modify: `index.html` (hub footer version string, only if this ships as a version bump per existing convention)

- [ ] **Step 1: Grep for dead references**

```bash
cd /c/dev/projects/it-tools
grep -n "review-tbl\|tbl-wrap\|contact-cards\|other-contacts-label\|year-tab\b" tools/on-call/index.html
```

Expected: no matches (Task 3 already replaced every markup block that used these classes). If anything matches, remove it, it's leftover from the pre-redesign version.

- [ ] **Step 2: Full walkthrough via Playwright, non-admin**

Fresh load, no admin bypass:
- Hero, calendar strip, and roster all render correctly on first load
- Every interactive element (year segment, prev/today/next, search, tile click, roster card click, panel close) works
- No console errors at any point in the walkthrough

- [ ] **Step 3: Full walkthrough via Playwright, admin with Edit Mode on**

Repeat the walkthrough with `st.isAdmin = true` and Edit Mode toggled on, touching every edit path once each (edit a week's tech/time-off/notes, edit a contact's name/phones, move someone in and out of rotation, add a new rotation member, add a new other contact) to catch any interaction between features that the per-task verifications, done in isolation, might have missed.

- [ ] **Step 4: Update the hub changelog**

Following the established convention (changelog entry ships in the same push as the feature), add an entry to `changelog.json`. Check the existing file's structure first:

```bash
grep -n "\"version\"" changelog.json | tail -5
```

Add a new entry at the top of the array matching the existing schema (version bump from whatever the previous On-Call entry used, or the hub's current version if On-Call had no prior changelog entry, plus a short description: "On-Call Rotation: redesigned with a navigable calendar strip and color-coded contacts roster, replacing the flat table view.").

- [ ] **Step 5: Commit**

```bash
git add tools/on-call/index.html changelog.json
git commit -m "On-Call Rotation redesign: cleanup dead CSS, changelog entry"
```

---

## Out of Scope

- No mobile/responsive layout (see `hub-no-mobile-scope` memory; desktop-only is the standing hub-wide decision).
- No change to `data.json`'s shape, the GSD deny-gate, MSAL auth flow, or either Azure Function (`OnCallGet`/`OnCallSave`).
- No resolution of the "should Other Contacts be more de-emphasized than just dimming" open question from the spec. Josh will judge that once he can click through the live preview, per his own stated plan.
- No further icon additions beyond the seven Lucide icons listed in Task 1 (chevron-left, chevron-right, search, plus, x, file-text, palmtree). If a future tweak needs another icon, fetch it the same way (`curl -sL https://unpkg.com/lucide-static@latest/icons/<name>.svg`) rather than guessing at path data.
