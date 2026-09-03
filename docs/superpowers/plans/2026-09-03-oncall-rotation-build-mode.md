# On-Call Rotation Build Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the "Build Mode" feature from `docs/superpowers/specs/2026-09-03-oncall-rotation-build-mode-design.md`: dynamic year tabs, an admin-only "Build [Year] Rotation" flow that proposes a full year of weekly assignments (continuing the real rotation order, gap-fill only), a drag-to-swap + click-to-edit canvas to adjust the proposal, and a commit step that writes it into the existing schedule/save path. Also adds drag-to-reorder on the rotation roster, since reorder defines the sequence Build Mode cycles through.

**Architecture:** Single-file addition to `tools/on-call/index.html` (this hub has no build step; every tool is one self-contained HTML file, and 700-2200 line files are normal here per the prior on-call redesign plan). No changes to `data.json`'s shape, `shared/`, `config.json`, or either backend function (`OnCallGet`/`OnCallSave`) — Build Mode is entirely client-side authoring that ends in the same `saveChanges()`/`OnCallSave` call every other edit already uses. Verification is manual + Playwright against a local static server, matching this tool's only prior plan (no unit-test framework exists anywhere in this repo).

**Tech Stack:** Vanilla JS/HTML/CSS, no framework, no build step. Native HTML5 Drag and Drop API for both roster reordering and build-canvas swapping (no library). Real inline Lucide SVGs for any new icon, matching every other tool in the hub. No em dashes in any UI copy string.

---

### Task 1: Roster drag-to-reorder + stable per-person color assignment

**Files:**
- Modify: `tools/on-call/index.html` (CSS block after line 91; `buildPersonColors` at lines 222-226; `rosterCardHtml` at lines 539-557)

Rotation order (the `rotationTechs` array order) becomes editable in this task, and it also happens to be the input `buildPersonColors` uses today to assign colors positionally. Left alone, reordering would silently recolor every person hub-wide (hero/calendar/roster) every time someone drags a card, since color = "index in this task order" today. Fix that first, then add the reorder UI. This is a one-time visible recolor for the 5 current techs (alphabetical instead of today's positional order) — acceptable now since the tool is still admin-only preview, not something a live audience has memorized yet.

- [ ] **Step 1: Make `buildPersonColors` order-independent**

Replace (currently lines 222-226):

```javascript
function buildPersonColors(data) {
  const map = {};
  data.rotationTechs.forEach((t, i) => { map[t.shortName] = PERSON_PALETTE[i % PERSON_PALETTE.length]; });
  return map;
}
```

with:

```javascript
function buildPersonColors(data) {
  const map = {};
  const sortedNames = data.rotationTechs.map(t => t.shortName).slice().sort();
  sortedNames.forEach((shortName, i) => { map[shortName] = PERSON_PALETTE[i % PERSON_PALETTE.length]; });
  return map;
}
```

- [ ] **Step 2: Add the drag-handle icon constant**

Insert after `const ICON_PENCIL = ...` (currently line 216):

```javascript
const ICON_GRIP = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="12" r="1"/><circle cx="9" cy="5" r="1"/><circle cx="9" cy="19" r="1"/><circle cx="15" cy="12" r="1"/><circle cx="15" cy="5" r="1"/><circle cx="15" cy="19" r="1"/></svg>`;
```

(Fetched verbatim from `lucide-static`'s `grip-vertical`, sized down from 24 to 14 like every other inline icon in this file.)

- [ ] **Step 3: Add roster drag-to-reorder CSS**

Insert after `.add-tile:hover { border-color:var(--blue); color:var(--blue); }` (currently line 91), before the `/* ── Detail panel (shared: calendar week + roster contact) ── */` comment:

```css
    .roster-drag-handle { display:flex; align-items:center; cursor:grab; color:var(--muted); margin-right:2px; }
    .roster-card.dragging { opacity:.4; }
    .roster-card.drag-over { outline:2px dashed var(--blue); outline-offset:2px; }
```

- [ ] **Step 4: Wire the drag handle into `rosterCardHtml`**

Replace (currently lines 539-557):

```javascript
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
```

with:

```javascript
function rosterCardHtml(person, group, idx) {
  const color = group === "rotation" ? personColorFor(person.shortName) : OTHER_CONTACT_COLOR;
  const visiblePhones = person.phones.slice(0, 2);
  const extra = person.phones.length - visiblePhones.length;
  const canReorder = group === "rotation" && st.isAdmin && editMode;
  const dragAttrs = canReorder
    ? `draggable="true" ondragstart="rosterDragStart(event, ${idx})" ondragover="rosterDragOver(event)" ondrop="rosterDrop(event, ${idx})" ondragend="rosterDragEnd(event)"`
    : "";
  return `
    <div class="roster-card${group === "other" ? " dim" : ""}" ${dragAttrs} onclick="openContactPanel('${group}', ${idx})">
      <div class="roster-card-top">
        ${canReorder ? `<span class="roster-drag-handle">${ICON_GRIP}</span>` : ""}
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
```

- [ ] **Step 5: Add the drag handler functions**

Insert immediately after `renderRoster()` (currently ends at line 567, right before `function addContact(group) {`):

```javascript
let rosterDragSrcIdx = null;

function rosterDragStart(evt, idx) {
  rosterDragSrcIdx = idx;
  evt.currentTarget.classList.add("dragging");
  evt.dataTransfer.effectAllowed = "move";
}

function rosterDragOver(evt) {
  evt.preventDefault();
  evt.currentTarget.classList.add("drag-over");
}

function rosterDrop(evt, idx) {
  evt.preventDefault();
  evt.currentTarget.classList.remove("drag-over");
  if (rosterDragSrcIdx === null || rosterDragSrcIdx === idx) return;
  const arr = st.data.rotationTechs;
  const [moved] = arr.splice(rosterDragSrcIdx, 1);
  arr.splice(idx, 0, moved);
  st.personColors = buildPersonColors(st.data);
  rosterDragSrcIdx = null;
  renderRoster();
  renderCalendarStrip();
  saveChanges();
}

function rosterDragEnd(evt) {
  evt.currentTarget.classList.remove("dragging");
  document.querySelectorAll(".roster-card.drag-over").forEach(el => el.classList.remove("drag-over"));
}
```

(Reordering saves immediately through the existing `saveChanges()` path, same as any other roster edit — it is not part of Build Mode's own commit transaction, per the spec.)

- [ ] **Step 6: Verify via Playwright against the local static server**

```bash
cd /c/dev/projects/it-tools
/c/dev/tools/nodejs/node.exe -e "require('http').createServer((q,s)=>require('fs').readFile('.'+decodeURI(q.url==='/'?'/tools/on-call/index.html':q.url),(e,d)=>{s.end(e?'404':d)})).listen(8790)"
```

Open `http://localhost:8790/` with Playwright, and in the console/`browser_evaluate` set `st.isAdmin = true` then call `toggleEditMode()` (matches the bypass technique used throughout the prior on-call plan). Confirm:
- Every rotation roster card now shows a grip-dot handle to the left of the avatar; Other Contacts cards do not.
- Colors are still unique per rotation person and match between hero/calendar/roster (now alphabetical-by-shortName order instead of original array order — expected, one-time change).
- Dragging a rotation card to a new position reorders `st.data.rotationTechs` (verify via `console.log(st.data.rotationTechs.map(t=>t.shortName))`), the roster re-renders in the new order, and colors stay the same for each person (proves Step 1's fix works — colors don't shuffle just because order changed).
- With Edit Mode off, no drag handles appear and cards are not draggable.

- [ ] **Step 7: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Build Mode: add roster drag-to-reorder and make person colors order-independent"
```

---

### Task 2: Dynamic year tabs, Build entry point, setup bar, and proposal generation (read-only canvas)

**Files:**
- Modify: `tools/on-call/index.html` (CSS after line 71; markup at lines 158-177; `st` object at line 232; `renderYearSeg`/`renderAll`/`toggleEditMode`)

This task lands the whole generation pipeline and a read-only view of its result. Dragging and click-to-edit come in Tasks 3-4; committing comes in Task 5 (the Commit button in this task's canvas markup calls `commitBuild()`, which doesn't exist until Task 5 — a forward reference, harmless since this task's own verification never clicks Commit, matching how the prior on-call plan forward-referenced `renderRoster()` before it existed).

- [ ] **Step 1: Add Build Mode CSS**

Insert after `.edit-toggle-btn.active { background:var(--blue); border-color:var(--blue); color:#fff; }` (currently line 71), before `/* ── Roster ── */`:

```css
    /* ── Build Mode ── */
    .build-trigger-btn { display:flex; align-items:center; gap:6px; background:var(--green); color:#fff; border:none;
                          border-radius:10px; padding:8px 14px; font-size:12px; font-weight:700; cursor:pointer; }
    .build-setup-bar { display:flex; align-items:center; gap:14px; padding:14px 18px; margin-bottom:16px; border-radius:14px;
                        background:var(--glass-fill); border:1px solid var(--glass-border); backdrop-filter:blur(16px); }
    .setup-field { display:flex; flex-direction:column; gap:3px; font-size:12px; }
    .setup-field .tag { font-size:10px; text-transform:uppercase; letter-spacing:.05em; color:var(--muted); font-weight:700; }
    .setup-field .val { font-weight:600; color:var(--text); }
    .setup-go-btn { margin-left:auto; background:var(--green); color:#fff; border:none; border-radius:10px; padding:8px 16px;
                    font-weight:700; font-size:12px; cursor:pointer; }
    .setup-cancel-btn { background:none; border:1px solid var(--border); border-radius:10px; padding:8px 14px; font-weight:600;
                        font-size:12px; cursor:pointer; color:var(--muted); }
    .build-canvas-panel { padding:14px 16px; border-radius:14px; background:var(--glass-fill);
                           border:1px solid var(--glass-border); backdrop-filter:blur(16px); margin-bottom:14px; }
    .build-month-group { margin-bottom:12px; }
    .build-month-lbl { font-size:10px; font-weight:700; color:var(--muted); text-transform:uppercase; letter-spacing:.05em; margin:0 0 4px 2px; }
    .build-ribbon { display:flex; gap:5px; flex-wrap:wrap; }
    .build-block { width:56px; height:52px; border-radius:9px; display:flex; flex-direction:column; align-items:center;
                   justify-content:center; gap:2px; color:#fff; cursor:grab; box-shadow:0 1px 2px rgba(0,0,0,.1); }
    .build-block.existing { opacity:.55; cursor:default; }
    .build-block.dragging { transform:translateY(-8px) rotate(-3deg) scale(1.06); box-shadow:0 10px 20px rgba(0,0,0,.22); z-index:3; }
    .build-block.drag-over { outline:2px dashed rgba(0,0,0,.35); outline-offset:2px; }
    .build-block .build-block-initials { font-size:13px; font-weight:800; letter-spacing:.02em; }
    .build-block .build-block-date { font-size:9px; font-weight:600; opacity:.85; }
    .build-commit-bar { display:flex; align-items:center; justify-content:space-between; padding:12px 16px; border-radius:14px;
                        background:var(--glass-fill); border:1px solid var(--glass-border); backdrop-filter:blur(16px); font-size:12px; }
    .build-commit-bar > div { display:flex; gap:8px; }
    .ghost-btn { background:none; border:1px solid var(--border); border-radius:10px; padding:8px 16px; font-weight:600;
                 font-size:12px; cursor:pointer; color:var(--muted); }
    .build-popover { position:absolute; width:200px; padding:12px; z-index:50; border-radius:12px;
                      background:var(--glass-fill); border:1px solid var(--glass-border);
                      backdrop-filter:blur(16px); box-shadow:0 14px 28px rgba(0,0,0,.16); }
    .build-popover .pop-field { margin-bottom:8px; }
    .build-popover .pop-field label { display:block; font-size:10px; color:var(--muted); font-weight:700; margin-bottom:3px;
                                       text-transform:uppercase; }
```

- [ ] **Step 2: Add the new markup**

Replace (currently lines 158-171):

```html
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
        <div class="month-pills" id="monthPills"></div>

        <div class="roster-section">
```

with:

```html
        <div class="cal-navbar">
          <div class="year-seg" id="yearSeg"></div>
          <div id="buildTriggerWrap"></div>
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
        <div class="month-pills" id="monthPills"></div>
        <div id="buildSetupBar" class="build-setup-bar" style="display:none"></div>
        <div id="buildCanvasSection" style="display:none"></div>

        <div class="roster-section" id="rosterSection">
```

- [ ] **Step 3: Add `build: null` to state**

Replace (currently line 232):

```javascript
const st = { data: null, year: "2026", isAdmin: false, stripStart: 0, panel: null, draft: null };
```

with:

```javascript
const st = { data: null, year: "2026", isAdmin: false, stripStart: 0, panel: null, draft: null, build: null };
```

- [ ] **Step 4: Make year tabs dynamic**

Replace (currently lines 338-343):

```javascript
function renderYearSeg() {
  const years = ["2024", "2025", "2026"];
  document.getElementById("yearSeg").innerHTML = years.map(y =>
    `<span class="${y === st.year ? "on" : ""}" onclick="setYear('${y}')">${y}</span>`
  ).join("");
}
```

with:

```javascript
function getScheduleYears() {
  const years = new Set(st.data.schedule.map(r => r.startDate.slice(0, 4)));
  return Array.from(years).sort();
}

function renderYearSeg() {
  const years = getScheduleYears();
  if (!years.includes(st.year)) st.year = years[years.length - 1] || st.year;
  document.getElementById("yearSeg").innerHTML = years.map(y =>
    `<span class="${y === st.year ? "on" : ""}" onclick="setYear('${y}')">${y}</span>`
  ).join("");
}
```

- [ ] **Step 5: Call `renderBuildTrigger()` from `renderAll()` and `toggleEditMode()`**

Replace (currently lines 293-298):

```javascript
function renderAll() {
  renderHero();
  renderYearSeg();
  renderCalendarStrip();
  renderRoster();
}
```

with:

```javascript
function renderAll() {
  renderHero();
  renderYearSeg();
  renderCalendarStrip();
  renderRoster();
  renderBuildTrigger();
}
```

Replace (currently lines 453-460):

```javascript
function toggleEditMode() {
  editMode = !editMode;
  document.getElementById("editToggleBtn").classList.toggle("active", editMode);
  document.getElementById("saveBtn").style.display = editMode ? "inline-block" : "none";
  closePanel();
  renderCalendarStrip();
  renderRoster();
}
```

with:

```javascript
function toggleEditMode() {
  editMode = !editMode;
  document.getElementById("editToggleBtn").classList.toggle("active", editMode);
  document.getElementById("saveBtn").style.display = editMode ? "inline-block" : "none";
  if (!editMode && st.build) { st.build = null; setBuildViewVisibility(); }
  closePanel();
  renderCalendarStrip();
  renderRoster();
  renderBuildTrigger();
}
```

- [ ] **Step 6: Add the Build Mode functions**

Insert this whole new section right after `renderMonthPills`/`jumpToMonth` (currently ending at line 448), before the `// ── Edit mode toggle ── ` comment:

```javascript
// ── Build Mode ──────────────────────────────────────────────
function computeYearSundays(year) {
  const y = Number(year);
  let d = new Date(Date.UTC(y, 0, 1));
  while (d.getUTCDay() !== 0) d.setUTCDate(d.getUTCDate() + 1);
  const sundays = [];
  while (d.getUTCFullYear() === y) {
    sundays.push(d.toISOString().slice(0, 10));
    d.setUTCDate(d.getUTCDate() + 7);
  }
  return sundays;
}

function getNextGapYear() {
  const years = getScheduleYears();
  const lastYear = years.length ? Number(years[years.length - 1]) : new Date().getUTCFullYear();
  const candidate = String(lastYear + 1);
  const sundays = computeYearSundays(candidate);
  const existing = new Set(st.data.schedule.map(r => r.startDate));
  const hasGap = sundays.some(d => !existing.has(d));
  return hasGap ? candidate : null;
}

function renderBuildTrigger() {
  const wrap = document.getElementById("buildTriggerWrap");
  const gapYear = (st.isAdmin && editMode) ? getNextGapYear() : null;
  wrap.innerHTML = gapYear
    ? `<button class="build-trigger-btn" onclick="openBuildSetup('${gapYear}')">${ICON_PENCIL} Build ${gapYear} Rotation</button>`
    : "";
}

function describeContinuation(year) {
  const sundays = computeYearSundays(year);
  const before = st.data.schedule
    .filter(r => r.startDate < sundays[0])
    .sort((a, b) => (a.startDate < b.startDate ? 1 : -1))[0];
  if (!before) return { fromLabel: "No prior rotation history", nextLabel: "", nextIdx: 0 };
  const fromIdx = st.data.rotationTechs.findIndex(t => t.shortName === before.tech);
  const fromTech = st.data.rotationTechs.find(t => t.shortName === before.tech);
  const nextIdx = fromIdx === -1 ? 0 : (fromIdx + 1) % st.data.rotationTechs.length;
  const nextTech = st.data.rotationTechs[nextIdx];
  return {
    fromLabel: (fromTech ? fromTech.name : before.tech) + " (" + before.startDate + ")",
    nextLabel: nextTech ? nextTech.name : "",
    nextIdx
  };
}

function openBuildSetup(year) {
  st.build = { phase: "setup", year, weeks: [] };
  setBuildViewVisibility();
  renderBuildSetupBar();
}

function renderBuildSetupBar() {
  const info = describeContinuation(st.build.year);
  document.getElementById("buildSetupBar").innerHTML = `
    <div class="setup-field"><span class="tag">Start date</span><span class="val">January 1, ${st.build.year}</span></div>
    <div class="setup-field"><span class="tag">Length</span><span class="val">Full year</span></div>
    <div class="setup-field"><span class="tag">Continuing from</span><span class="val">${info.fromLabel} &rarr; next: ${info.nextLabel}</span></div>
    <button class="setup-go-btn" onclick="generateProposal()">Generate Proposal</button>
    <button class="setup-cancel-btn" onclick="cancelBuild()">Cancel</button>
  `;
}

function cancelBuild() {
  st.build = null;
  setBuildViewVisibility();
  renderBuildTrigger();
}

function setBuildViewVisibility() {
  const inBuild = !!st.build;
  document.getElementById("monthRow").style.display = inBuild ? "none" : "flex";
  document.getElementById("weekStrip").style.display = inBuild ? "none" : "flex";
  document.getElementById("monthPills").style.display = inBuild ? "none" : "flex";
  document.getElementById("rosterSection").style.display = inBuild ? "none" : "block";
  document.getElementById("buildSetupBar").style.display = (inBuild && st.build.phase === "setup") ? "flex" : "none";
  document.getElementById("buildCanvasSection").style.display = (inBuild && st.build.phase === "canvas") ? "block" : "none";
}

function generateProposal() {
  const year = st.build.year;
  const sundays = computeYearSundays(year);
  const existingByDate = {};
  st.data.schedule.forEach(r => { existingByDate[r.startDate] = r; });
  const info = describeContinuation(year);
  let position = info.nextIdx;
  const weeks = sundays.map(startDate => {
    const existingRow = existingByDate[startDate];
    if (existingRow) {
      const idx = st.data.rotationTechs.findIndex(t => t.shortName === existingRow.tech);
      if (idx !== -1) position = (idx + 1) % st.data.rotationTechs.length;
      return { startDate, tech: existingRow.tech, timeOff: existingRow.timeOff, notes: existingRow.notes, existing: true };
    }
    const tech = st.data.rotationTechs[position];
    position = (position + 1) % st.data.rotationTechs.length;
    return { startDate, tech: tech ? tech.shortName : "", timeOff: "", notes: "", existing: false };
  });
  st.build.phase = "canvas";
  st.build.weeks = weeks;
  setBuildViewVisibility();
  renderBuildCanvas();
}

function buildBlockHtml(week) {
  const tech = st.data.rotationTechs.find(t => t.shortName === week.tech);
  const name = tech ? tech.name : week.tech;
  const color = personColorFor(week.tech);
  const dateLabel = new Date(week.startDate + "T00:00:00Z").toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
  return `
    <div class="build-block${week.existing ? " existing" : ""}" style="background:${color}" title="${name}${week.existing ? " (already saved)" : ""}">
      <span class="build-block-initials">${initials(name)}</span>
      <span class="build-block-date">${dateLabel}</span>
    </div>`;
}

function renderBuildCanvas() {
  const groups = [];
  st.build.weeks.forEach((w, idx) => {
    const d = new Date(w.startDate + "T00:00:00Z");
    const label = d.toLocaleDateString("en-US", { month: "long", timeZone: "UTC" }).toUpperCase() + " " + d.getUTCFullYear();
    if (!groups.length || groups[groups.length - 1].label !== label) groups.push({ label, items: [] });
    groups[groups.length - 1].items.push({ week: w, idx });
  });
  const proposedCount = st.build.weeks.filter(w => !w.existing).length;
  document.getElementById("buildCanvasSection").innerHTML = `
    <div class="build-canvas-panel">
      ${groups.map(g => `
        <div class="build-month-group">
          <div class="build-month-lbl">${g.label}</div>
          <div class="build-ribbon">${g.items.map(it => buildBlockHtml(it.week, it.idx)).join("")}</div>
        </div>`).join("")}
    </div>
    <div class="build-commit-bar">
      <span>${proposedCount} week${proposedCount === 1 ? "" : "s"} proposed</span>
      <div>
        <button class="ghost-btn" onclick="cancelBuild()">Discard</button>
        <button class="setup-go-btn" onclick="commitBuild()">Commit ${st.build.year} Rotation</button>
      </div>
    </div>
  `;
}
```

Note `buildBlockHtml(it.week, it.idx)` already passes `idx` even though the Task 2 version of `buildBlockHtml` ignores a second argument — this is deliberate so Task 3 only needs to change the function signature/body, not this call site.

- [ ] **Step 7: Verify via Playwright**

Reload against the local static server, `st.isAdmin = true`, `toggleEditMode()`. Confirm:
- Year segmented control now reads directly from `data.json`'s years (still 2024/2025/2026 today) instead of a hardcoded list.
- A green "Build 2027 Rotation" button appears next to the year tabs (2026 is fully populated, 2027 has zero rows).
- Clicking it hides the calendar strip and roster, and shows a setup bar reading "Continuing from Krista Guthrie (2026-12-27) → next: Joshua Garrett" (or whoever the real last 2026 row and array order resolve to).
- Clicking "Generate Proposal" shows a canvas of blocks grouped by month (JANUARY 2027, FEBRUARY 2027, ...), each showing initials + date, colored per the same palette as the calendar/roster, cycling through the 5 rotation techs in order starting from the "next" tech shown in setup.
- The bottom bar reads "52 weeks proposed" (or 53, whichever `computeYearSundays("2027")` produces).
- Clicking "Discard" (the `cancelBuild()`-bound button, currently just labeled Discard in the commit bar) returns to the normal calendar/roster view and the Build button reappears.
- Clicking "Commit" does nothing usable yet (undefined function) — expected, Task 5 implements it; do not treat this as a failure.
- Turning Edit Mode off while build is open (re-toggle) closes Build Mode and returns to the normal view.

- [ ] **Step 8: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Build Mode: dynamic year tabs, setup bar, and gap-fill proposal generation"
```

---

### Task 3: Drag-to-swap between proposed blocks

**Files:**
- Modify: `tools/on-call/index.html` (`buildBlockHtml`/`renderBuildCanvas` from Task 2)

- [ ] **Step 1: Add drag attributes and a stable `data-idx` to proposed blocks**

Replace (added in Task 2):

```javascript
function buildBlockHtml(week) {
  const tech = st.data.rotationTechs.find(t => t.shortName === week.tech);
  const name = tech ? tech.name : week.tech;
  const color = personColorFor(week.tech);
  const dateLabel = new Date(week.startDate + "T00:00:00Z").toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
  return `
    <div class="build-block${week.existing ? " existing" : ""}" style="background:${color}" title="${name}${week.existing ? " (already saved)" : ""}">
      <span class="build-block-initials">${initials(name)}</span>
      <span class="build-block-date">${dateLabel}</span>
    </div>`;
}
```

with:

```javascript
function buildBlockHtml(week, idx) {
  const tech = st.data.rotationTechs.find(t => t.shortName === week.tech);
  const name = tech ? tech.name : week.tech;
  const color = personColorFor(week.tech);
  const dateLabel = new Date(week.startDate + "T00:00:00Z").toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
  const dragAttrs = week.existing ? "" :
    `draggable="true" ondragstart="buildDragStart(event, ${idx})" ondragover="buildDragOver(event)" ondrop="buildDrop(event, ${idx})" ondragend="buildDragEnd(event)"`;
  return `
    <div class="build-block${week.existing ? " existing" : ""}" data-idx="${idx}" style="background:${color}"
         title="${name}${week.existing ? " (already saved)" : ""}" ${dragAttrs}>
      <span class="build-block-initials">${initials(name)}</span>
      <span class="build-block-date">${dateLabel}</span>
    </div>`;
}
```

- [ ] **Step 2: Add the drag handler functions**

Insert immediately after `renderBuildCanvas()` (from Task 2):

```javascript
let buildDragSrcIdx = null;

function buildDragStart(evt, idx) {
  buildDragSrcIdx = idx;
  evt.currentTarget.classList.add("dragging");
  evt.dataTransfer.effectAllowed = "move";
}

function buildDragOver(evt) {
  evt.preventDefault();
  evt.currentTarget.classList.add("drag-over");
}

function buildDrop(evt, idx) {
  evt.preventDefault();
  evt.currentTarget.classList.remove("drag-over");
  if (buildDragSrcIdx === null || buildDragSrcIdx === idx) return;
  const weeks = st.build.weeks;
  const techA = weeks[buildDragSrcIdx].tech;
  weeks[buildDragSrcIdx].tech = weeks[idx].tech;
  weeks[idx].tech = techA;
  buildDragSrcIdx = null;
  renderBuildCanvas();
}

function buildDragEnd(evt) {
  evt.currentTarget.classList.remove("dragging");
  document.querySelectorAll(".build-block.drag-over").forEach(el => el.classList.remove("drag-over"));
}
```

Existing (already-saved) blocks never get `dragAttrs`, so they're never draggable and never receive a drop — no extra guard needed for them.

- [ ] **Step 3: Verify via Playwright**

With a generated 2027 proposal open (repeat Task 2's setup): drag one proposed block onto another proposed block. Confirm their `tech`/initials/color swap immediately on the canvas, and the block being dragged shows the lift/rotate styling mid-drag. Confirm dragging a proposed block onto a 2027 row that already existed before Build Mode ran (if you first manually add one row to `data.json`'s 2027 range to test this — or skip if 2027 is fully empty in current data, in which case just confirm all blocks are draggable) does nothing, since existing blocks have no drop handler. Confirm the commit bar's proposed-week count is unchanged after any swap (swaps never add/remove weeks, only reassign techs).

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Build Mode: drag-to-swap between proposed rotation blocks"
```

---

### Task 4: Click-to-edit popover (tech / time off / notes)

**Files:**
- Modify: `tools/on-call/index.html` (`buildBlockHtml` from Task 3; `cancelBuild` from Task 2; `init()`)

- [ ] **Step 1: Add `onclick` to proposed blocks**

Replace the `dragAttrs` line inside `buildBlockHtml` (from Task 3):

```javascript
  const dragAttrs = week.existing ? "" :
    `draggable="true" ondragstart="buildDragStart(event, ${idx})" ondragover="buildDragOver(event)" ondrop="buildDrop(event, ${idx})" ondragend="buildDragEnd(event)"`;
```

with:

```javascript
  const dragAttrs = week.existing ? "" :
    `draggable="true" ondragstart="buildDragStart(event, ${idx})" ondragover="buildDragOver(event)" ondrop="buildDrop(event, ${idx})" ondragend="buildDragEnd(event)" onclick="openBuildPopover(${idx})"`;
```

- [ ] **Step 2: Add the popover functions**

Insert immediately after `buildDragEnd()` (from Task 3):

```javascript
let buildPopoverIdx = null;

function openBuildPopover(idx) {
  buildPopoverIdx = idx;
  renderBuildPopover();
}

function closeBuildPopover() {
  buildPopoverIdx = null;
  const el = document.getElementById("buildPopover");
  if (el) el.remove();
}

function renderBuildPopover() {
  const existingEl = document.getElementById("buildPopover");
  if (existingEl) existingEl.remove();
  const week = st.build.weeks[buildPopoverIdx];
  const blockEl = document.querySelector(`.build-block[data-idx="${buildPopoverIdx}"]`);
  if (!blockEl) return;
  const rect = blockEl.getBoundingClientRect();
  const options = st.data.rotationTechs.map(t =>
    `<option value="${t.shortName}"${t.shortName === week.tech ? " selected" : ""}>${t.name}</option>`
  ).join("");
  const pop = document.createElement("div");
  pop.id = "buildPopover";
  pop.className = "build-popover";
  pop.style.top = (rect.bottom + window.scrollY + 6) + "px";
  pop.style.left = (rect.left + window.scrollX) + "px";
  pop.innerHTML = `
    <div class="pop-field"><label>Week of ${week.startDate}</label></div>
    <div class="pop-field"><label>Tech</label>
      <select class="panel-select" onchange="st.build.weeks[${buildPopoverIdx}].tech=this.value">${options}</select>
    </div>
    <div class="pop-field"><label>Time off</label>
      <input class="panel-input" value="${week.timeOff || ""}" onchange="st.build.weeks[${buildPopoverIdx}].timeOff=this.value"/>
    </div>
    <div class="pop-field"><label>Notes</label>
      <input class="panel-input" value="${week.notes || ""}" onchange="st.build.weeks[${buildPopoverIdx}].notes=this.value"/>
    </div>
    <button class="setup-go-btn" style="width:100%" onclick="applyBuildPopover()">Apply</button>
  `;
  document.body.appendChild(pop);
}

function applyBuildPopover() {
  closeBuildPopover();
  renderBuildCanvas();
}
```

- [ ] **Step 3: Close the popover when discarding a build**

Replace (currently, from Task 2):

```javascript
function cancelBuild() {
  st.build = null;
  setBuildViewVisibility();
  renderBuildTrigger();
}
```

with:

```javascript
function cancelBuild() {
  closeBuildPopover();
  st.build = null;
  setBuildViewVisibility();
  renderBuildTrigger();
}
```

- [ ] **Step 4: Close the popover on outside click**

Add this line inside `init()` (currently the function starting at line 687), anywhere after the other `document.getElementById(...).innerHTML = ICON_...` icon-wiring lines:

```javascript
  document.addEventListener("click", evt => {
    if (buildPopoverIdx === null) return;
    const pop = document.getElementById("buildPopover");
    if (pop && !pop.contains(evt.target) && !evt.target.closest(".build-block")) closeBuildPopover();
  });
```

- [ ] **Step 5: Verify via Playwright**

With a generated 2027 proposal open: click a proposed block. Confirm a small popover appears anchored just below it, showing "Week of 2027-XX-XX", a tech dropdown pre-selected to that block's current tech, and Time off/Notes inputs. Change the dropdown to a different tech and click Apply: confirm the block's initials/color update immediately and the popover closes. Click a different block, then click empty space elsewhere on the page: confirm the popover closes without applying uncommitted dropdown/input changes beyond what was already live-bound via `onchange` (matches the existing week-panel's own behavior, where `onchange` writes straight to the draft as you type, and Apply is just a close-and-refresh). Confirm clicking an "already saved" block (if any exist in the test data) does nothing, since it never got `onclick`.

- [ ] **Step 6: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Build Mode: click-to-edit popover for tech/time off/notes on proposed blocks"
```

---

### Task 5: Commit / Discard, writing the proposal into the real schedule

**Files:**
- Modify: `tools/on-call/index.html` (add `commitBuild()`, already referenced by Task 2's commit-bar markup)

- [ ] **Step 1: Add `commitBuild()`**

Insert immediately after `applyBuildPopover()` (from Task 4):

```javascript
function commitBuild() {
  const proposed = st.build.weeks.filter(w => !w.existing).map(w => ({
    startDate: w.startDate, tech: w.tech, timeOff: w.timeOff || "", notes: w.notes || ""
  }));
  st.data.schedule.push(...proposed);
  st.data.schedule.sort((a, b) => (a.startDate < b.startDate ? -1 : 1));
  const builtYear = st.build.year;
  st.build = null;
  setBuildViewVisibility();
  st.year = builtYear;
  st.stripStart = 0;
  renderAll();
  saveChanges();
}
```

- [ ] **Step 2: Verify via Playwright**

Repeat the setup → generate flow for 2027. Optionally drag-swap and/or edit a block or two first (to prove edits survive commit). Click "Commit 2027 Rotation". Confirm:
- The view returns to the normal calendar strip, now on the 2027 tab, showing the first week of January with the tech from your (possibly edited) proposal.
- The year segmented control now includes "2027".
- `st.data.schedule.length` grew by exactly the proposed-week count from the commit bar (52 or 53, matching Task 2's step 7 count).
- `st.data.schedule` is still date-sorted (spot-check a few consecutive rows).
- The "Build [Year] Rotation" button, re-checked by toggling Edit Mode off and back on, now offers "Build 2028 Rotation" instead of 2027 (since 2027 has no more gaps).
- Repeat the whole flow once more but click "Discard" instead of Commit: confirm `st.data.schedule` is completely unchanged (same length as before generating), the view returns to the calendar/roster, and the Build button still offers 2027.

- [ ] **Step 3: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Build Mode: commit proposed weeks into the schedule via the existing save path"
```

---

### Task 6: Full walkthrough and cleanup

**Files:**
- Modify: `tools/on-call/index.html` (only if the grep in Step 1 finds something)

- [ ] **Step 1: Grep for stray debug output**

```bash
cd /c/dev/projects/it-tools
grep -n "console.log\|TODO\|FIXME" tools/on-call/index.html
```

Expected: no matches introduced by Tasks 1-5 (the file may already contain the pre-existing `console.warn("ONCALL_SAVE_URL not configured yet...")` from before this plan — that's fine, leave it). Remove anything new found.

- [ ] **Step 2: Full walkthrough via Playwright, non-admin**

Fresh load, no `st.isAdmin` bypass. Confirm:
- No "Build" button ever appears, no drag handles on roster cards, everything else (hero, calendar strip, roster, panels) works exactly as before this plan.
- No console errors at any point.

- [ ] **Step 3: Full walkthrough via Playwright, admin with Edit Mode on**

With `st.isAdmin = true` and Edit Mode toggled on, exercise every feature from this plan once in a single continuous session (not in isolation, to catch cross-feature interference the per-task verifications might have missed):
1. Drag-reorder two rotation roster cards.
2. Click "Build [next gap year] Rotation", review the setup bar's continuation text.
3. Generate the proposal.
4. Drag-swap two proposed blocks.
5. Click-to-edit a third block's tech via the popover, and set a Time Off value on a fourth.
6. Commit.
7. Confirm the new year's data reflects steps 4-5 correctly (the swapped pair, the edited tech, the time-off note).
8. Verify the existing week/contact edit panels (from before this plan) still work unchanged: edit a week's tech via its slide-over panel, edit a contact's phone numbers.

- [ ] **Step 4: Commit (only if Step 1 found and fixed anything)**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Build Mode: remove stray debug output"
```

---

## Out of Scope

- **No changelog.json entry.** Per established convention (`feedback_changelog_in_parallel`), changelog entries describe changes to something already live for real users. On-Call Rotation is still gated to `coming-soon`/admin-preview and has never shipped — this plan doesn't change that. Add an entry only when the tool actually goes live.
- **No backend changes.** `OnCallGet`/`OnCallSave`, EasyAuth, and the blob structure are untouched — confirmed unaffected by every task above.
- **No custom start date, partial-length builds, time-off-aware generation, or conflict detection** — all explicitly out of scope per the design spec.
- **No year-tab overflow/archive UI** — backlog item per the spec, not part of this build.
- **No mobile/responsive layout** — desktop-only is the standing hub-wide decision (`project_hub_no_mobile_scope`).
