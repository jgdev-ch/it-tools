# On-Call Rotation Layout 1a Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement layout 1a from `docs/superpowers/specs/2026-09-04-oncall-rotation-layout-1a-design.md`: replace the on-call tool's vertical stack (hero, 5-week strip, month pills, two 172px card grids) with a two-column page - a 376px left rail answering "who is on call now and what is their number", and a right column showing the whole year as a 12x5 board of 52 week cells. Everything fits one 1440x900 screen with no scrolling.

**Architecture:** Single-file rewrite of `tools/on-call/index.html` plus three additive tokens in `shared/styles.css`. This hub has no build step; every tool is one self-contained HTML file. No changes to `data.json`'s shape, `shared/auth.js`, `config.json`, or either backend function (`OnCallGet`/`OnCallSave`). Build Mode is carried forward unchanged and only has its visibility toggles repointed at new element IDs. Verification is manual + Playwright against a local static server, matching this tool's two prior plans - **this repo has no unit-test framework anywhere**, so there are no test files to write and steps verify observable browser behavior instead.

**Tech Stack:** Vanilla JS/HTML/CSS, no framework, no build step. Native HTML5 Drag and Drop for tech-strip reordering (handlers reused verbatim from the roster). Real inline Lucide SVGs only. No em dashes in any UI copy string. Every new CSS color must be a `var(--token)` - zero hardcoded colors, because the design brief was authored light-mode-only and the hub has a full dark theme.

**Sequencing:** Tasks 1-13 are built and committed locally with **no push**. Task 14 pushes the whole structural migration to `origin/testing` as one coherent unit. The layout is interdependent, so pushing mid-migration would leave preview visibly half-built. Polish after Task 14 follows the usual one-push-per-item rhythm.

**Local static server** (run from repo root, used by every verification step):

```bash
/c/dev/tools/nodejs/node.exe -e "require('http').createServer((q,s)=>{const p=decodeURI(q.url.split('?')[0]);const f='.'+(p==='/'?'/tools/on-call/index.html':p);require('fs').readFile(f,(e,d)=>{if(e){s.statusCode=404;s.end('not found')}else{s.end(d)}})}).listen(8850,()=>console.log('serving repo root on 8850'))"
```

Then open **`http://localhost:8850/tools/on-call/index.html`** with Playwright.

Two corrections to the command the two prior plans used, both found by hitting them during Task 2:

1. **The query string must be stripped.** `loadData()` cache-busts with `data.json?v=<timestamp>`, and the old one-liner passed that straight to `readFile`, which cannot open a path containing `?`. Worse, it returned the literal string `404` with HTTP **200**, so `res.json()` parsed it as the *number* 404 and the failure surfaced later as an unrelated `Cannot read properties of undefined (reading 'map')` inside `buildPersonColors`. This version returns a real 404 status so the next such failure is obvious.
2. **Load the tool at its real path, not `/`.** Serving it at `/` makes the page's relative `data.json` fetch resolve to `/data.json`, which does not exist.

**Port note:** 8790-8799 were all occupied by orphaned servers from prior sessions, hence 8850. If 8850 is taken too, any free port works; nothing depends on the number.

**Auth bypass** (same technique as both prior plans) via `browser_evaluate`:

```javascript
document.getElementById('authScreen').style.display='none';
document.getElementById('appScreen').style.display='block';
document.getElementById('toolContent').style.display='block';
document.body.style.opacity='1';
await loadData();
```

To exercise admin paths, additionally run `st.isAdmin = true; renderAll();` and for edit mode `toggleEditMode()`.

**Console baseline:** a single `404` for `/favicon.ico` is expected on this bare static server and is not a code fault. Wherever a task says "zero console errors", it means zero *other than* that. Treat anything else as a real failure.

**Screenshots:** call `browser_take_screenshot` with **no `filename`** so the image is returned inline and can actually be looked at. Passing a filename writes it to the Playwright server's own filesystem, which is not readable from here, so the screenshot cannot be reviewed and the "verify visually" steps become unverifiable claims.

**Theme switching** for the dark-mode checks in every task:

```javascript
document.documentElement.setAttribute('data-theme','dark');   // dark
document.documentElement.setAttribute('data-theme','light');  // light
```

---

### Task 1: Add the three theme tokens to the shared stylesheet

**Files:**
- Modify: `shared/styles.css` (`:root` block at lines 20-86; `[data-theme="dark"]` block at lines 91-134)

The design brief hardcodes `#4a4a52` secondary text and `rgba(255,255,255,.6/.7)` nested surfaces, and flags both as "used, not tokenized". They have no dark-mode equivalent, which is the single biggest risk in this redesign. Close the gap once, in the shared sheet, so every later task can use `var()` and the next tool that needs a nested glass surface gets it free.

- [ ] **Step 1: Add the light-mode values**

In `shared/styles.css`, insert immediately after the `--panel-fill:   rgba(255,255,255,.97);` line and its comment block (currently line 68), before the `/* Scrollbar thumb` comment:

```css
  /* Secondary body text - sits between --text and --muted. Used for supporting
     copy that should recede from a heading but stay clearly readable. */
  --text-secondary: #4a4a52;
  /* A surface raised ON TOP of a glass card (inset phone rows, segmented
     controls, avatar rings). Deliberately not --glass-fill: that is tuned for a
     card floating over the blurred page, and reads as flat when nested inside
     one. Deliberately not --panel-fill: that is near-opaque, for dropdowns. */
  --glass-raise:        rgba(255,255,255,.60);
  --glass-raise-border: rgba(255,255,255,.70);
```

- [ ] **Step 2: Add the dark-mode values**

Insert immediately after the `--panel-fill:   rgba(22,23,28,.96);` line (currently line 128), before `--scroll-thumb:`:

```css
  --text-secondary:     #c8cad2;
  --glass-raise:        rgba(255,255,255,.08);
  --glass-raise-border: rgba(255,255,255,.14);
```

The dark alphas are much lower than a naive inversion of `.60`/`.70` on purpose: over dark glass, a 60%-white fill blows out into an opaque light slab. `.08`/`.14` reads as "raised" while staying dark.

- [ ] **Step 3: Verify both themes resolve**

Start the static server, load `http://localhost:8850/tools/on-call/index.html`, and via `browser_evaluate`:

```javascript
const g = t => { document.documentElement.setAttribute('data-theme', t);
  const s = getComputedStyle(document.documentElement);
  return [t, s.getPropertyValue('--text-secondary').trim(),
             s.getPropertyValue('--glass-raise').trim(),
             s.getPropertyValue('--glass-raise-border').trim()]; };
JSON.stringify([g('light'), g('dark')]);
```

Expected: `[["light","#4a4a52","rgba(255,255,255,.60)","rgba(255,255,255,.70)"],["dark","#c8cad2","rgba(255,255,255,.08)","rgba(255,255,255,.14)"]]`

Also confirm no visual change to any existing tool: load `http://localhost:8850/index.html` (the hub) and confirm it renders as before. These tokens are additive; nothing existing references them yet.

- [ ] **Step 4: Commit**

```bash
git add shared/styles.css
git commit -m "Design system: add --text-secondary and --glass-raise tokens for nested glass surfaces"
```

---

### Task 2: Add the new derived helpers

**Files:**
- Modify: `tools/on-call/index.html` (insert after `weekRangeLabel` which ends at line 509)

Pure additions. Nothing is removed, so the page still renders the old layout and stays fully working after this task.

- [ ] **Step 1: Add the helper functions**

Insert after the closing brace of `weekRangeLabel` (currently line 509), before the `function tileHtml(row, todayStr) {` line:

```javascript
// ── Derived helpers (layout 1a) ─────────────────────────────
function sortedByDate(rows) {
  return rows.slice().sort((a, b) => (a.startDate < b.startDate ? -1 : 1));
}

function weekOrdinalInYear(startDate) {
  const weeks = sortedByDate(getYearWeeks(startDate.slice(0, 4)));
  return weeks.findIndex(w => w.startDate === startDate) + 1;
}

function unmatchedTechs(year) {
  const known = new Set(st.data.rotationTechs.map(t => t.shortName));
  const out = {};
  sortedByDate(getYearWeeks(year))
    .filter(r => !known.has(r.tech))
    .forEach(r => { (out[r.tech] = out[r.tech] || []).push(r.startDate); });
  return out;
}

function shortDate(startDate) {
  const d = new Date(startDate + "T00:00:00Z");
  return d.toLocaleDateString("en-US", { month: "short", timeZone: "UTC" }) + " " + d.getUTCDate();
}

function daysFromToday(startDate) {
  const now = new Date();
  const todayUtc = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  return Math.round((Date.parse(startDate + "T00:00:00Z") - todayUtc) / 86400000);
}

function nextWeekAfter(startDate) {
  const all = sortedByDate(st.data.schedule);
  const i = all.findIndex(w => w.startDate === startDate);
  return i !== -1 ? all[i + 1] || null : null;
}

function msToNextSunday() {
  const now = new Date();
  const next = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  next.setDate(next.getDate() + ((7 - next.getDay()) % 7 || 7));
  return next.getTime() - now.getTime();
}

function countdownLabel() {
  const totalHours = Math.floor(msToNextSunday() / 3600000);
  return Math.floor(totalHours / 24) + "d " + String(totalHours % 24).padStart(2, "0") + "h";
}

function coverageNote(phones) {
  if (!phones.length) return "No numbers on file.";
  const labels = phones.map(p => p.label.toLowerCase()).join(" ");
  const missing = ["8x8", "Teams"].filter(c => !labels.includes(c.toLowerCase()));
  const lead = phones.length === 1 ? "Only number on file." : "";
  const tail = missing.length ? "No " + missing.join(", no ") + " line." : "";
  return [lead, tail].filter(Boolean).join(" ");
}
```

`sortedByDate` exists because `getYearWeeks` filters without sorting and relies on `data.json` already being ordered. Every new component sorts defensively so a `commitBuild` append or a hand-edited blob cannot scramble the board.

- [ ] **Step 2: Add the new state field**

Replace (currently line 311):

```javascript
const st = { data: null, year: "2026", isAdmin: false, stripStart: 0, panel: null, draft: null, build: null };
```

with:

```javascript
const st = { data: null, year: "2026", isAdmin: false, stripStart: 0, panel: null, draft: null, build: null, highlightTech: null };
```

`stripStart` stays for now; it is removed in Task 3 once the strip itself is gone.

- [ ] **Step 3: Verify the helpers against real data**

Load the tool with the auth bypass, then via `browser_evaluate`:

```javascript
JSON.stringify({
  ordinal: weekOrdinalInYear('2026-08-30'),
  unmatched: unmatchedTechs('2026'),
  short: shortDate('2026-09-06'),
  next: nextWeekAfter('2026-08-30').tech,
  countdown: countdownLabel(),
  nickNote: coverageNote(st.data.rotationTechs.find(t => t.shortName === 'Nick').phones),
  joshNote: coverageNote(st.data.rotationTechs.find(t => t.shortName === 'Joshua').phones)
});
```

Expected:
- `ordinal` is `35`
- `unmatched` is `{"David":["2026-02-01","2026-03-15","2026-04-26"]}`
- `short` is `"Sep 6"`
- `next` is `"Joe"`
- `countdown` matches `/^\d+d \d\dh$/`
- `nickNote` is `"Only number on file. No 8x8, no Teams line."`
- `joshNote` is `""` (Joshua has 8x8, Work, Personal, and Teams, so nothing is missing)

Also confirm the page still renders the old layout unchanged and the console is clean.

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: add derived helpers for the layout 1a rail and year board"
```

---

### Task 3: Swap the page shell and strip out the dead layout

**Files:**
- Modify: `tools/on-call/index.html` (CSS lines 15-89 and 127-153; markup lines 210-246; icon consts 277-287; functions 394-414, 426-491, 493-560; call sites at 341, 372-378, 434-439, 635-638, 799, 807-816, 940-957, 959-965, 1081-1085, 1091-1094)

The single atomic task: the rail cannot exist while the hero does, and the board replaces the strip and month pills together. After this task the page loads with an empty two-column grid and a clean console. Tasks 4-11 fill it in.

- [ ] **Step 1: Replace the layout and component CSS**

Delete everything from `.main-content { max-width:1440px; ... }` (line 15) through `.edit-toggle-btn.active { ... }` (line 89) inclusive - that is the hero, calendar nav, admin toolbar, jump-to-person, calendar strip, month pills, and edit-toggle blocks. **Keep** the two lines above it (`#authScreen` and `body { opacity:0 }`).

Also delete the entire `/* ── Roster ── */` block, lines 127-153 inclusive (`.roster-section` through `.roster-card.drag-over`).

**Keep untouched:** the `/* ── Build Mode ── */` block (91-125) and the `/* ── Detail panel ── */` block (155-186).

In place of the deleted lines 15-89, insert:

```css
    .main-content { max-width:1440px; margin:0 auto; padding:20px 24px 24px; }
    .oc-layout { display:grid; grid-template-columns:376px 1fr; gap:16px; align-items:start; }
    .oc-rail { display:flex; flex-direction:column; gap:12px; }

    /* ── Rail cards (shared glass shell) ── */
    .oc-card { border-radius:16px; background:var(--glass-fill); border:1px solid var(--glass-border);
               backdrop-filter:blur(22px) saturate(180%); }
    #queueCard { padding:14px 16px 8px; }
    #attentionCard, #rosterNotesCard { padding:14px 16px; }
    .oc-card-lbl { display:flex; align-items:center; gap:5px; font-size:10px; font-weight:700;
                   text-transform:uppercase; letter-spacing:.12em; color:var(--muted); margin-bottom:6px; }

    /* ── On call now ── */
    .now-card { border-radius:16px; padding:18px; color:var(--text);
                background:color-mix(in srgb, var(--tech-color) 20%, var(--glass-fill));
                border:1px solid color-mix(in srgb, var(--tech-color) 28%, var(--glass-border));
                backdrop-filter:blur(22px) saturate(180%); }
    .now-eyebrow { display:flex; align-items:center; gap:5px; font-size:10px; font-weight:700;
                   text-transform:uppercase; letter-spacing:.12em;
                   color:color-mix(in srgb, var(--tech-color) 72%, var(--text)); }
    .now-id { display:flex; gap:14px; margin-top:12px; }
    .now-avatar { width:60px; height:60px; border-radius:50%; flex-shrink:0; display:flex; align-items:center;
                  justify-content:center; font-size:21px; font-weight:800; color:#fff;
                  border:2px solid var(--glass-raise-border); cursor:pointer; }
    .now-name { font-size:26px; font-weight:800; letter-spacing:-.02em; line-height:1.1; color:var(--text); }
    .now-sub { font-size:12px; color:var(--text-secondary); margin-top:3px; }
    .now-pips { display:flex; gap:4px; margin:16px 0 8px; }
    .now-pip { flex:1; height:7px; border-radius:4px;
               background:color-mix(in srgb, var(--tech-color) 22%, transparent); }
    .now-pip.done { background:var(--tech-color); }
    .now-pip.today { background:var(--tech-color); box-shadow:0 0 0 2px var(--glass-raise-border); }
    .now-handoff { display:flex; align-items:baseline; justify-content:space-between; gap:10px; }
    .now-handoff-txt { font-size:12px; color:var(--text-secondary); }
    .now-handoff-txt strong { font-weight:700; color:var(--text); }
    .now-countdown { font-size:22px; font-weight:800; letter-spacing:-.02em; white-space:nowrap;
                     color:color-mix(in srgb, var(--tech-color) 80%, var(--text)); }
    .now-divider { height:1px; background:var(--glass-raise-border); margin:14px 0 12px; }
    .now-phone { display:flex; align-items:center; justify-content:space-between; gap:10px;
                 background:var(--glass-raise); border-radius:10px; padding:9px 12px; margin-bottom:6px; }
    .now-phone:last-of-type { margin-bottom:0; }
    .now-phone-lbl { font-size:9px; font-weight:700; text-transform:uppercase; letter-spacing:.1em; color:var(--muted); }
    .now-phone-num { font-size:15px; font-weight:700; letter-spacing:-.01em; color:var(--text);
                     font-family:'Cascadia Code','Consolas',monospace; }
    .copy-btn { background:var(--surface); border:1px solid var(--border); border-radius:8px; padding:6px 11px;
                font-size:11px; font-weight:600; color:var(--blue); cursor:pointer; font-family:inherit; flex-shrink:0; }
    .now-note { font-size:10px; color:var(--muted); margin-top:8px; }

    /* ── Queue ── */
    .queue-row { display:flex; align-items:center; gap:10px; padding:9px 0; cursor:pointer;
                 border-bottom:1px solid var(--border); }
    .queue-row:last-child { border-bottom:none; }
    .queue-dot { width:8px; height:8px; border-radius:50%; flex-shrink:0; }
    .queue-name { flex:1; font-size:13px; font-weight:600; color:var(--text); }
    .queue-row.first .queue-name { font-weight:700; }
    .queue-date { font-size:11px; color:var(--muted); }
    .queue-next { font-size:10px; font-weight:700; background:var(--green-light); color:var(--green);
                  border-radius:20px; padding:2px 8px; }
    .queue-rel { font-size:10px; font-weight:600; color:var(--muted); min-width:44px; text-align:right; }

    /* ── Derived note lists (needs attention / roster notes) ── */
    .oc-note-item { display:flex; gap:9px; align-items:flex-start; font-size:11.5px; line-height:1.45;
                    color:var(--text-secondary); margin-bottom:8px; }
    .oc-note-item:last-child { margin-bottom:0; }
    .oc-note-item strong { color:var(--text); font-weight:700; }
    .oc-note-icon { flex-shrink:0; margin-top:1px; display:flex; }
    .oc-note-item.warn .oc-note-icon { color:var(--amber); }
    .oc-note-item.info .oc-note-icon { color:var(--muted2); }

    /* ── Right column toolbar ── */
    .oc-toolbar { display:flex; align-items:center; justify-content:space-between; gap:10px; margin-bottom:12px; }
    .oc-toolbar-left, .oc-toolbar-right { display:flex; align-items:center; gap:10px; }
    .oc-toolbar-right { gap:8px; }
    .year-seg { display:inline-flex; background:var(--glass-raise); border:1px solid var(--glass-raise-border);
                border-radius:10px; padding:3px; }
    .year-seg span { padding:6px 14px; border-radius:7px; font-size:12px; font-weight:600; color:var(--muted);
                     cursor:pointer; }
    .year-seg span.on { background:var(--blue); color:#fff; font-weight:700; }
    .oc-count { font-size:11px; color:var(--muted); }
    .oc-btn { display:flex; align-items:center; gap:6px; background:var(--surface); border:1px solid var(--border);
              border-radius:9px; padding:7px 12px; font-size:12px; font-weight:600; color:var(--text);
              cursor:pointer; font-family:inherit; }
    .oc-btn.active { background:var(--blue); border-color:var(--blue); color:#fff; }

    /* ── Find a person ── */
    .find-wrap { position:relative; }
    .find-panel { position:absolute; top:calc(100% + 6px); right:0; width:220px; max-height:260px; overflow-y:auto;
                  background:var(--panel-fill); border:1px solid var(--border); border-radius:10px;
                  box-shadow:var(--shadow-md); z-index:30; padding:4px; }
    .find-option { display:flex; align-items:center; gap:8px; padding:7px 8px; border-radius:7px; font-size:12px;
                   cursor:pointer; color:var(--text); }
    .find-option:hover { background:var(--surface2); }
    .find-option.on { background:var(--blue-light); color:var(--blue); font-weight:700; }
    .find-avatar { width:22px; height:22px; border-radius:50%; display:flex; align-items:center;
                   justify-content:center; font-size:9px; font-weight:700; color:#fff; flex-shrink:0; }

    /* ── Year board ── */
    .board-panel { border-radius:16px; padding:14px 16px; background:var(--glass-fill);
                   border:1px solid var(--glass-border); backdrop-filter:blur(22px) saturate(180%); }
    .board-grid { display:grid; grid-template-columns:34px repeat(5, 1fr); gap:5px; align-items:center; }
    .board-month { font-size:9px; font-weight:700; letter-spacing:.1em; color:var(--muted2); }
    .board-month.current { color:var(--text); }
    .wk { position:relative; height:38px; border-radius:8px; display:flex; align-items:center;
          justify-content:center; gap:5px; color:#fff; cursor:pointer;
          transition:transform .15s, box-shadow .15s, opacity .15s; }
    .wk:hover { transform:translateY(-1px); box-shadow:var(--shadow-sm); }
    .wk-day { font-size:10px; opacity:.75; }
    .wk-ini { font-size:11px; font-weight:800; }
    .wk.today { box-shadow:0 0 0 2px var(--text), 0 4px 12px rgba(0,0,0,.2); }
    .wk.next { box-shadow:0 0 0 1.5px color-mix(in srgb, var(--text) 35%, transparent); }
    .wk.unmatched { background:var(--surface2); border:1px dashed var(--muted2); color:var(--muted); }
    .wk.dim { opacity:.35; }
    .wk-now-tag { position:absolute; top:-9px; left:50%; transform:translateX(-50%); background:var(--text);
                  color:var(--bg); font-size:8px; font-weight:800; letter-spacing:.06em; padding:2px 7px;
                  border-radius:8px; pointer-events:none; }
    .wk-flags { position:absolute; top:2px; right:3px; display:flex; gap:2px; opacity:.8; }
    .wk-flags svg { display:block; width:10px; height:10px; }

    /* ── Per-tech summary strip ── */
    .tech-strip { display:grid; grid-template-columns:repeat(5, 1fr); gap:8px; margin-top:12px; }
    .tech-card { position:relative; border-radius:12px; padding:10px 12px; background:var(--glass-fill);
                 border:1px solid var(--glass-border); border-left:3px solid var(--tech-color);
                 backdrop-filter:blur(16px); cursor:pointer; transition:transform .15s, box-shadow .15s; }
    .tech-card:hover { transform:translateY(-1px); box-shadow:var(--shadow-sm); }
    .tech-card-name { font-size:12px; font-weight:700; color:var(--text); }
    .tech-card-meta { font-size:10.5px; color:var(--muted); margin-top:2px; }
    .tech-card-meta.warn { color:var(--amber); }
    .tech-grip { position:absolute; top:6px; right:6px; display:flex; cursor:grab; color:var(--muted); }
    .tech-card.dragging { opacity:.4; }
    .tech-card.drag-over { outline:2px dashed var(--blue); outline-offset:2px; }
    .tech-add { border-radius:12px; padding:10px 12px; border:1px dashed var(--border); display:flex;
                align-items:center; justify-content:center; gap:5px; font-size:11px; font-weight:600;
                color:var(--muted); cursor:pointer; }
    .tech-add:hover { border-color:var(--blue); color:var(--blue); }

    /* ── Also reachable ── */
    .also-bar { display:flex; align-items:center; gap:10px; flex-wrap:wrap; margin-top:10px; padding:9px 14px;
                border-radius:12px; background:var(--glass-fill); border:1px solid var(--glass-border); }
    .also-lbl { font-size:10px; font-weight:700; text-transform:uppercase; letter-spacing:.1em; color:var(--muted); }
    .also-chip { display:flex; align-items:center; gap:6px; font-size:11.5px; color:var(--text-secondary);
                 cursor:pointer; }
    .also-avatar { width:20px; height:20px; border-radius:50%; display:flex; align-items:center;
                   justify-content:center; font-size:8px; font-weight:800; color:#fff; flex-shrink:0; }
    .also-add { display:flex; align-items:center; gap:4px; font-size:11px; font-weight:600; color:var(--muted);
                border:1px dashed var(--border); border-radius:20px; padding:3px 10px; cursor:pointer; }
    .also-add:hover { border-color:var(--blue); color:var(--blue); }
```

- [ ] **Step 2: Replace the `#toolContent` markup**

Replace lines 210-246 (from `<div id="toolContent" style="display:none">` through its closing `</div>`) with:

```html
      <div id="toolContent" style="display:none">
        <div class="oc-layout">
          <aside class="oc-rail">
            <div class="now-card" id="nowCard"></div>
            <div class="oc-card" id="queueCard" style="display:none"></div>
            <div class="oc-card" id="attentionCard" style="display:none"></div>
            <div class="oc-card" id="rosterNotesCard" style="display:none"></div>
          </aside>

          <section class="oc-main">
            <div class="oc-toolbar">
              <div class="oc-toolbar-left">
                <div class="year-seg" id="yearSeg"></div>
                <span class="oc-count" id="ocCount"></span>
              </div>
              <div class="oc-toolbar-right">
                <div class="find-wrap" id="findWrap">
                  <button class="oc-btn" id="findBtn" onclick="toggleFindPanel()"></button>
                  <div class="find-panel" id="findPanel" style="display:none"></div>
                </div>
                <button class="oc-btn" id="editToggleBtn" style="display:none" onclick="toggleEditMode()" title="Edit Mode"></button>
                <button class="oc-btn" id="saveBtn" style="display:none" onclick="saveChanges()">Save</button>
                <div id="buildTriggerWrap"></div>
              </div>
            </div>

            <div class="board-panel" id="yearBoard"></div>
            <div id="buildSetupBar" class="build-setup-bar" style="display:none"></div>
            <div id="buildCanvasSection" style="display:none"></div>
            <div class="tech-strip" id="techStrip"></div>
            <div class="also-bar" id="alsoReachable"></div>
          </section>
        </div>
      </div>
```

The `yearSeg`, `editToggleBtn`, `saveBtn`, `buildTriggerWrap`, `buildSetupBar`, and `buildCanvasSection` IDs are deliberately preserved so `saveChanges`, `renderBuildTrigger`, and the Build Mode functions keep working with no edits.

- [ ] **Step 3: Delete the five now-unused icon constants**

Delete these lines (currently 277, 278, 285, 286, 287). Each is unused after this task: the chevrons were only on the deleted Prev/Next buttons, `ICON_USERS` only on the deleted roster headings, `ICON_SHIELD` only on the deleted admin-toolbar label, and `ICON_REFRESH_CW` only on the deleted "In Rotation" card tag.

```javascript
const ICON_CHEVRON_LEFT  = ...
const ICON_CHEVRON_RIGHT = ...
const ICON_USERS         = ...
const ICON_SHIELD        = ...
const ICON_REFRESH_CW    = ...
```

Also delete the now-unused `WEEKS_VISIBLE` constant (line 275) and remove `stripStart: 0, ` from the `st` initializer (line 311).

**Keep** `ICON_SEARCH` (currently unused, wired up in Task 11), `ICON_HEADSET`, `ICON_PLUS`, `ICON_X`, `ICON_FILE_TEXT`, `ICON_PALMTREE`, `ICON_PENCIL`, and `ICON_GRIP`.

- [ ] **Step 4: Delete the dead render functions**

Delete these function bodies entirely:
- `renderHero` (lines 394-414)
- `renderYearSeg` is **kept** - do not delete it
- `shiftStrip` (441-444), `jumpToWeek` (446-451), `goToday` (453-460)
- `renderPersonJumpPanel` (462-469), `togglePersonJump` (471-476), `jumpToPersonDate` (478-491)
- `monthLabelsHtml` (493-501)
- `tileHtml` (511-528), `renderCalendarStrip` (530-541)
- `renderMonthPills` (545-550), `jumpToMonth` (552-559)
- `rosterCardHtml` (895-914), `renderRoster` (916-925)

**Critical: keep `const MONTH_NAMES = [...]` (line 543).** It sits between `renderCalendarStrip` and `renderMonthPills` and is required by the year board in Task 8.

- [ ] **Step 5: Repoint every call site of the deleted functions**

Replace `renderAll` (lines 372-378):

```javascript
function renderAll() {
  renderNowCard();
  renderQueue();
  renderAttention();
  renderRosterNotes();
  renderYearSeg();
  renderToolbar();
  renderYearBoard();
  renderTechStrip();
  renderAlsoReachable();
  renderBuildTrigger();
}
```

Replace `setYear` (lines 434-439):

```javascript
function setYear(y) {
  st.year = y;
  renderYearSeg();
  renderToolbar();
  renderAttention();
  renderRosterNotes();
  renderYearBoard();
  renderTechStrip();
}
```

Replace `toggleEditMode` (lines 807-816):

```javascript
function toggleEditMode() {
  editMode = !editMode;
  if (!editMode && st.build) { st.build = null; setBuildViewVisibility(); }
  closePanel();
  renderToolbar();
  renderYearBoard();
  renderTechStrip();
  renderAlsoReachable();
  renderBuildTrigger();
}
```

The `editToggleBtn.classList.toggle` and `saveBtn.style.display` lines move into `renderToolbar` (Task 7), so they are deliberately gone from here.

In `setBuildViewVisibility` (lines 633-641), replace the four element lines:

```javascript
  document.getElementById("monthRow").style.display = inBuild ? "none" : "flex";
  document.getElementById("weekStrip").style.display = inBuild ? "none" : "flex";
  document.getElementById("monthPills").style.display = inBuild ? "none" : "flex";
  document.getElementById("rosterSection").style.display = inBuild ? "none" : "block";
```

with:

```javascript
  document.getElementById("yearBoard").style.display = inBuild ? "none" : "block";
  document.getElementById("techStrip").style.display = inBuild ? "none" : "grid";
  document.getElementById("alsoReachable").style.display = inBuild ? "none" : "flex";
```

In `commitBuild`, delete the `st.stripStart = 0;` line (currently 799).

In `rosterDrop`, replace the two render calls (lines 949-950):

```javascript
  renderRoster();
  renderCalendarStrip();
```

with:

```javascript
  renderTechStrip();
  renderYearBoard();
```

In `rosterDragEnd` (line 956), replace the selector:

```javascript
  document.querySelectorAll(".roster-card.drag-over").forEach(el => el.classList.remove("drag-over"));
```

with:

```javascript
  document.querySelectorAll(".tech-card.drag-over").forEach(el => el.classList.remove("drag-over"));
```

In `addContact` (line 963), replace `renderRoster();` with:

```javascript
  if (group === "rotation") renderTechStrip(); else renderAlsoReachable();
```

In `afterSignIn`, delete the admin-toolbar reveal (line 341) entirely - `renderToolbar` now owns admin visibility:

```javascript
  if (st.isAdmin) document.getElementById("adminToolbar").style.display = "flex";
```

In `init`, delete the four lines for removed elements (1081, 1082, 1085) and update the edit button (1084):

```javascript
  document.getElementById("navPrevBtn").innerHTML = ICON_CHEVRON_LEFT + " Prev";   // delete
  document.getElementById("navNextBtn").innerHTML = "Next " + ICON_CHEVRON_RIGHT;  // delete
  document.getElementById("adminToolbarLabel").innerHTML = `${ICON_SHIELD} Admin`; // delete
```

Replace line 1084 with:

```javascript
  document.getElementById("editToggleBtn").innerHTML = ICON_PENCIL + " Edit";
  document.getElementById("findBtn").innerHTML = ICON_SEARCH + " Find a person";
```

And replace the jump-panel click-outside listener (lines 1091-1094):

```javascript
  document.addEventListener("click", evt => {
    const panel = document.getElementById("findPanel");
    if (panel.style.display !== "none" && !evt.target.closest("#findWrap")) panel.style.display = "none";
  });
```

- [ ] **Step 6: Add temporary no-op stubs so the page loads**

`renderAll` now calls nine functions, seven of which do not exist yet. Insert these stubs immediately after `renderAll` so this task is independently verifiable. Each is replaced by its real implementation in Tasks 4-11.

```javascript
// Temporary stubs - replaced in Tasks 4-11.
function renderNowCard() {}
function renderQueue() {}
function renderAttention() {}
function renderRosterNotes() {}
function renderToolbar() {}
function renderYearBoard() {}
function renderTechStrip() {}
function renderAlsoReachable() {}
function toggleFindPanel() {}
```

- [ ] **Step 7: Verify the shell loads clean**

Start the server, load the tool with the auth bypass, and confirm:
- **Zero console errors.** This is the whole point of the task; a missing element or function shows up here.
- A two-column grid exists. Via `browser_evaluate`: `getComputedStyle(document.querySelector('.oc-layout')).gridTemplateColumns` returns two values, the first `376px`.
- The rail's three lower cards are hidden (`display:none`) and `#nowCard` is present but empty.
- The toolbar row renders with an empty year segment, a "Find a person" button, and no Edit/Save (not admin yet).
- Screenshot in both light and dark. Expect a mostly empty page - correct at this stage.
- `st.stripStart` is `undefined` and `typeof WEEKS_VISIBLE` is `"undefined"`.
- `typeof MONTH_NAMES` is `"object"` (it must have survived).

- [ ] **Step 8: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: replace page shell with the layout 1a two-column grid, remove the strip and roster grids"
```

---

### Task 4: On call now card

**Files:**
- Modify: `tools/on-call/index.html` (replace the `renderNowCard` stub from Task 3)

- [ ] **Step 1: Add the countdown timer handle**

Insert immediately before the `function renderAll() {` line:

```javascript
let countdownTimer = null;
```

- [ ] **Step 2: Implement `renderNowCard`**

Replace the `function renderNowCard() {}` stub with:

```javascript
function renderNowCard() {
  const el = document.getElementById("nowCard");
  if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }

  const week = findCurrentWeek(st.data.schedule);
  if (!week) {
    el.style.removeProperty("--tech-color");
    el.innerHTML = `<div class="now-eyebrow">${ICON_HEADSET} On call now</div>
      <div class="now-sub" style="margin-top:10px">No current on-call week found.</div>`;
    return;
  }

  const techIdx = st.data.rotationTechs.findIndex(t => t.shortName === week.tech);
  const tech = techIdx !== -1 ? st.data.rotationTechs[techIdx] : null;
  const name = tech ? tech.name : week.tech;
  el.style.setProperty("--tech-color", personColorFor(week.tech));

  const elapsed = daysFromToday(week.startDate) * -1;
  const pips = Array.from({ length: 7 }, (_, i) =>
    `<span class="now-pip${i < elapsed ? " done" : i === elapsed ? " today" : ""}"></span>`).join("");

  const nextRow = nextWeekAfter(week.startDate);
  let handoff = "";
  if (nextRow) {
    const nextTech = st.data.rotationTechs.find(t => t.shortName === nextRow.tech);
    const nextName = nextTech ? nextTech.name : nextRow.tech;
    const d = new Date(nextRow.startDate + "T00:00:00Z");
    const dayName = d.toLocaleDateString("en-US", { weekday: "long", timeZone: "UTC" });
    const monthName = d.toLocaleDateString("en-US", { month: "short", timeZone: "UTC" });
    handoff = `<div class="now-handoff">
        <span class="now-handoff-txt">Hands off to <strong>${nextName}</strong>, ${dayName} ${monthName} ${ordinal(d.getUTCDate())}</span>
        <span class="now-countdown" id="nowCountdown">${countdownLabel()}</span>
      </div>`;
  }

  const phones = tech ? tech.phones : [];
  const phoneRows = phones.map(p => `
    <div class="now-phone">
      <div>
        <div class="now-phone-lbl">${p.label}</div>
        <div class="now-phone-num">${p.number}</div>
      </div>
      <button class="copy-btn" onclick="copyNumber(event, '${p.number}')">Copy</button>
    </div>`).join("");

  const note = coverageNote(phones);
  const avatarClick = tech ? `onclick="openContactPanel('rotation', ${techIdx})"` : "";

  el.innerHTML = `
    <div class="now-eyebrow">${ICON_HEADSET} On call now</div>
    <div class="now-id">
      <div class="now-avatar" ${avatarClick} style="background:${personColorFor(week.tech)}"
           title="${tech ? "View " + name + "'s contact info" : ""}">${initials(name)}</div>
      <div>
        <div class="now-name">${name}</div>
        <div class="now-sub">${weekRangeLabel(week.startDate)} &middot; week ${weekOrdinalInYear(week.startDate)}</div>
      </div>
    </div>
    <div class="now-pips">${pips}</div>
    ${handoff}
    ${phoneRows ? `<div class="now-divider"></div>${phoneRows}` : ""}
    ${note ? `<div class="now-note">${note}</div>` : ""}`;

  if (nextRow) {
    countdownTimer = setInterval(() => {
      const c = document.getElementById("nowCountdown");
      if (!c) { clearInterval(countdownTimer); countdownTimer = null; return; }
      c.textContent = countdownLabel();
    }, 60000);
  }
}
```

- [ ] **Step 3: Implement the Copy button**

Insert immediately after `renderNowCard`:

```javascript
function copyNumber(evt, number) {
  evt.stopPropagation();
  const btn = evt.currentTarget;
  navigator.clipboard.writeText(number).then(() => {
    btn.textContent = "Copied";
    setTimeout(() => { btn.textContent = "Copy"; }, 1500);
  });
}
```

`stopPropagation` matters because the button sits inside the card; without it a future card-level click handler would also fire.

- [ ] **Step 4: Verify**

Load with the auth bypass. Confirm:
- The card is purple-tinted (Nick Zoshak is on call the week of 2026-08-30, color `#9333ea`).
- Name reads "Nick Zoshak", sub-line reads "August 30th to September 5th &middot; week 35".
- Seven pips render; the elapsed ones and today are solid purple, the rest faint.
- Handoff reads "Hands off to Joe Randazzo, Sunday Sep 6th" with a countdown matching `/^\d+d \d\dh$/`.
- One phone row labelled PERSONAL with a monospace number and a Copy button.
- Coverage note reads "Only number on file. No 8x8, no Teams line."
- Clicking the avatar opens the contact panel for Nick.
- Clicking Copy flips the label to "Copied" then back after ~1.5s. (If the headless context denies clipboard access, confirm no console error is thrown and note it - the permission prompt is environmental, not a code fault.)
- `renderNowCard(); renderNowCard();` twice in a row leaves exactly one interval: check via `countdownTimer` being a single handle and no duplicate tick.
- Screenshot in both light and dark. In dark the card should read as a subtly purple-tinted dark glass panel, not a light slab.

- [ ] **Step 5: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: add the on-call-now rail card with day pips, handoff countdown, and copyable numbers"
```

---

### Task 5: Queue card

**Files:**
- Modify: `tools/on-call/index.html` (replace the `renderQueue` stub)

- [ ] **Step 1: Implement `renderQueue`**

Replace `function renderQueue() {}` with:

```javascript
function renderQueue() {
  const el = document.getElementById("queueCard");
  const week = findCurrentWeek(st.data.schedule);
  const all = sortedByDate(st.data.schedule);
  const startIdx = week ? all.findIndex(w => w.startDate === week.startDate) + 1 : 0;
  const upcoming = all.slice(startIdx, startIdx + 4);
  if (!upcoming.length) { el.style.display = "none"; return; }
  el.style.display = "block";

  const rows = upcoming.map((row, i) => {
    const tech = st.data.rotationTechs.find(t => t.shortName === row.tech);
    const name = tech ? tech.name : row.tech;
    const right = i === 0
      ? `<span class="queue-next">next up</span>`
      : `<span class="queue-rel">in ${daysFromToday(row.startDate)}d</span>`;
    return `<div class="queue-row${i === 0 ? " first" : ""}" onclick="openWeekPanel('${row.startDate}')">
        <span class="queue-dot" style="background:${personColorFor(row.tech)}"></span>
        <span class="queue-name">${name}</span>
        <span class="queue-date">${shortDate(row.startDate)}</span>
        ${right}
      </div>`;
  }).join("");

  el.innerHTML = `<div class="oc-card-lbl">Queue</div>${rows}`;
}
```

- [ ] **Step 2: Verify**

Load with the auth bypass. Confirm:
- Four rows in date order: Joe Randazzo / Sep 6, Joshua Garrett / Sep 13, Krista Guthrie / Sep 20, Robert Tyson / Sep 27.
- Row one carries a green "next up" pill; rows two through four carry `in Nd` labels that agree with today's real date.
- Each dot matches that person's colour from the now card and board.
- Clicking a row opens the week detail panel for that `startDate`.
- Screenshot both themes; confirm the hairline row dividers are visible in dark (they use `var(--border)`).

- [ ] **Step 3: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: add the upcoming-weeks queue card to the rail"
```

---

### Task 6: Needs attention and Roster notes cards

**Files:**
- Modify: `tools/on-call/index.html` (replace the `renderAttention` and `renderRosterNotes` stubs)

Two derived lists sharing one visual pattern. "Needs attention" is amber and actionable; "Roster notes" is grey and informational. The split exists because David's three 2026 rows are a deliberate historical-record keep, so filing them as a warning would create a nag that can only be cleared by reversing that decision.

- [ ] **Step 1: Implement `renderAttention`**

Replace `function renderAttention() {}` with:

```javascript
function renderAttention() {
  const el = document.getElementById("attentionCard");
  const items = [];

  const yearRows = getYearWeeks(st.year);
  if (yearRows.length && !yearRows.some(r => r.timeOff)) {
    items.push({ icon: ICON_PALMTREE,
      text: `No time off recorded anywhere in ${st.year}. Worth a pass before the holidays.` });
  }

  if (!items.length) { el.style.display = "none"; return; }
  el.style.display = "block";
  el.innerHTML = `<div class="oc-card-lbl">Needs attention</div>` + items.map(i =>
    `<div class="oc-note-item warn"><span class="oc-note-icon">${i.icon}</span><span>${i.text}</span></div>`
  ).join("");
}
```

- [ ] **Step 2: Implement `renderRosterNotes`**

Replace `function renderRosterNotes() {}` with:

```javascript
function renderRosterNotes() {
  const el = document.getElementById("rosterNotesCard");
  const byTech = unmatchedTechs(st.year);
  const names = Object.keys(byTech);
  if (!names.length) { el.style.display = "none"; return; }
  el.style.display = "block";

  const items = names.map(t => {
    const dates = byTech[t].map(shortDate).join(", ");
    const n = byTech[t].length;
    return `<div class="oc-note-item info">
        <span class="oc-note-icon">${ICON_FILE_TEXT}</span>
        <span>${n} week${n === 1 ? "" : "s"} in ${st.year} ${n === 1 ? "is" : "are"} assigned to
        <strong>${t}</strong>, who has left the rotation. Kept as historical record. ${dates}.</span>
      </div>`;
  }).join("");

  el.innerHTML = `<div class="oc-card-lbl">Roster notes</div>${items}`;
}
```

- [ ] **Step 3: Verify**

Load with the auth bypass on year 2026. Confirm:
- "Needs attention" shows exactly one item, with an amber palm-tree icon, reading "No time off recorded anywhere in 2026. Worth a pass before the holidays."
- "Roster notes" shows exactly one item, with a grey file-text icon, reading "3 weeks in 2026 are assigned to **David**, who has left the rotation. Kept as historical record. Feb 1, Mar 15, Apr 26."
- No em dashes appear in either string.
- Switch to 2024 via `setYear('2024')`: roster notes should now list 10 David weeks and still read grammatically ("10 weeks in 2024 are assigned to...").
- Force both cards empty and confirm they hide rather than showing an empty shell:

```javascript
st.data.schedule.find(r => r.startDate === '2026-01-04').timeOff = 'x';
st.data.rotationTechs.push({ name: 'David W', shortName: 'David', phones: [] });
renderAttention(); renderRosterNotes();
```

Both cards should be `display:none`. Reload afterwards to discard those mutations - **do not save**.
- Screenshot both themes.

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: add derived needs-attention and roster-notes rail cards"
```

---

### Task 7: Toolbar state

**Files:**
- Modify: `tools/on-call/index.html` (replace the `renderToolbar` stub)

`renderYearSeg` is kept as-is for the year pills. `renderToolbar` owns the count text and the admin button visibility that used to live in `toggleEditMode` and `afterSignIn`.

- [ ] **Step 1: Implement `renderToolbar`**

Replace `function renderToolbar() {}` with:

```javascript
function renderToolbar() {
  document.getElementById("ocCount").textContent =
    `${getYearWeeks(st.year).length} weeks · ${st.data.rotationTechs.length} techs`;

  const editBtn = document.getElementById("editToggleBtn");
  editBtn.style.display = st.isAdmin ? "flex" : "none";
  editBtn.classList.toggle("active", editMode);
  document.getElementById("saveBtn").style.display = (st.isAdmin && editMode) ? "flex" : "none";
}
```

`·` is a middle dot, matching the mockup's `&middot;`. It is not an em dash.

- [ ] **Step 2: Verify**

Load with the auth bypass. Confirm:
- Year pills read 2024 / 2025 / 2026 with 2026 selected and blue.
- Count text reads "52 weeks &middot; 5 techs". Switch to 2024 and it reads "43 weeks &middot; 5 techs".
- With `st.isAdmin = false`, neither Edit nor Save is visible.
- After `st.isAdmin = true; renderAll();`, Edit appears with a pencil icon; Save stays hidden.
- After `toggleEditMode()`, Edit turns blue/active and Save appears. Toggling again reverses both.
- Screenshot both themes; confirm the year segment's `--glass-raise` background reads as a raised control in dark rather than a white slab.

- [ ] **Step 3: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: add toolbar count and admin button state"
```

---

### Task 8: Year board

**Files:**
- Modify: `tools/on-call/index.html` (replace the `renderYearBoard` stub; add `weekCellHtml`)

- [ ] **Step 1: Implement `weekCellHtml`**

Insert immediately before the `renderYearBoard` stub:

```javascript
function weekCellHtml(row, todayStr, nextStr) {
  const known = st.data.rotationTechs.find(t => t.shortName === row.tech);
  const name = known ? known.name : row.tech;
  const d = new Date(row.startDate + "T00:00:00Z");
  const cls = ["wk"];
  if (!known) cls.push("unmatched");
  if (row.startDate === todayStr) cls.push("today");
  else if (row.startDate === nextStr) cls.push("next");
  if (st.highlightTech && row.tech !== st.highlightTech) cls.push("dim");
  const flags = (row.notes ? ICON_FILE_TEXT : "") + (row.timeOff ? ICON_PALMTREE : "");
  return `<div class="${cls.join(" ")}" ${known ? `style="background:${personColorFor(row.tech)}"` : ""}
       title="${name}" onclick="openWeekPanel('${row.startDate}')">
      ${row.startDate === todayStr ? `<span class="wk-now-tag">NOW</span>` : ""}
      <span class="wk-day">${d.getUTCDate()}</span>
      <span class="wk-ini">${initials(name)}</span>
      ${flags ? `<span class="wk-flags">${flags}</span>` : ""}
    </div>`;
}
```

- [ ] **Step 2: Implement `renderYearBoard`**

Replace `function renderYearBoard() {}` with:

```javascript
function renderYearBoard() {
  const el = document.getElementById("yearBoard");
  const weeks = sortedByDate(getYearWeeks(st.year));
  const cur = findCurrentWeek(st.data.schedule);
  const todayStr = cur ? cur.startDate : null;
  const nextRow = cur ? nextWeekAfter(cur.startDate) : null;
  const nextStr = nextRow ? nextRow.startDate : null;
  const todayMonth = todayStr && todayStr.slice(0, 4) === st.year
    ? new Date(todayStr + "T00:00:00Z").getUTCMonth() : -1;

  let html = "";
  for (let m = 0; m < 12; m++) {
    const inMonth = weeks.filter(w => new Date(w.startDate + "T00:00:00Z").getUTCMonth() === m);
    html += `<div class="board-month${m === todayMonth ? " current" : ""}">${MONTH_NAMES[m].toUpperCase()}</div>`;
    html += inMonth.map(w => weekCellHtml(w, todayStr, nextStr)).join("");
    for (let i = inMonth.length; i < 5; i++) html += `<div></div>`;
  }
  el.innerHTML = `<div class="board-grid">${html}</div>`;
}
```

The spacer `<div></div>` loop is what keeps columns aligned in months with only four Sundays. Never let the grid reflow to fit.

- [ ] **Step 3: Verify**

Load with the auth bypass on 2026. Confirm:
- Twelve rows, each led by a 3-letter month label. SEP is the only label in `--text` (today is in September); the rest are `--muted2`.
- 52 cells total for 2026: 49 coloured plus 3 dashed grey. Check via `document.querySelectorAll('#yearBoard .wk').length` returning `52`, and `document.querySelectorAll('#yearBoard .wk.unmatched').length` returning `3`. (The three David rows are part of the 52, not extra: 10+10+10+10+9 known plus 3 unmatched.)
- The three dashed cells fall on Feb 1, Mar 15, and Apr 26 and show initials "D".
- The 2026-08-30 cell carries a 2px ring and a floating "NOW" tag; the 2026-09-06 cell carries a lighter ring and no tag.
- Column alignment holds: `getComputedStyle(document.querySelector('.board-grid')).gridTemplateColumns` starts with `34px` followed by five equal widths.
- Hovering a cell lifts it 1px.
- Clicking a cell opens that week's detail panel.
- Switch to 2024 (43 rows, partial year starting Jan 7) and confirm the grid still aligns and JAN shows four cells with a leading spacer pattern consistent with the real dates.
- Screenshot both themes. In dark, confirm the NOW tag is a light chip with dark text (it uses `var(--text)` on `var(--bg)`) and the today ring is visible.

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: add the full-year 12x5 week board with today, next, and unmatched-tech states"
```

---

### Task 9: Per-tech summary strip, with reorder and add-tech carried over

**Files:**
- Modify: `tools/on-call/index.html` (replace the `renderTechStrip` stub)

This task restores the two admin capabilities the design brief omitted: drag-to-reorder (which defines the rotation order Build Mode cycles through) and add-to-rotation. The drag handlers themselves are reused verbatim; only their host element changes.

- [ ] **Step 1: Implement `renderTechStrip`**

Replace `function renderTechStrip() {}` with:

```javascript
function renderTechStrip() {
  const el = document.getElementById("techStrip");
  const cur = findCurrentWeek(st.data.schedule);
  const canEdit = st.isAdmin && editMode;
  const yearRows = getYearWeeks(st.year);

  const cards = st.data.rotationTechs.map((t, i) => {
    const count = yearRows.filter(r => r.tech === t.shortName).length;
    const isNow = cur && cur.tech === t.shortName;
    const upcoming = sortedByDate(st.data.schedule)
      .find(r => r.tech === t.shortName && daysFromToday(r.startDate) > 0);
    let when = "no upcoming week";
    if (isNow) when = "on call now";
    else if (upcoming) when = "next " + shortDate(upcoming.startDate);

    const n = t.phones.length;
    const dragAttrs = canEdit
      ? `draggable="true" ondragstart="rosterDragStart(event, ${i})" ondragover="rosterDragOver(event)" ondrop="rosterDrop(event, ${i})" ondragend="rosterDragEnd(event)"`
      : "";

    return `<div class="tech-card" ${dragAttrs} style="--tech-color:${personColorFor(t.shortName)}"
         onclick="openContactPanel('rotation', ${i})">
        ${canEdit ? `<span class="tech-grip">${ICON_GRIP}</span>` : ""}
        <div class="tech-card-name">${t.name}</div>
        <div class="tech-card-meta">${count} week${count === 1 ? "" : "s"} · ${when}</div>
        <div class="tech-card-meta${n === 1 ? " warn" : ""}">${n} number${n === 1 ? "" : "s"} on file</div>
      </div>`;
  }).join("");

  const addCard = canEdit
    ? `<div class="tech-add" onclick="addContact('rotation')">${ICON_PLUS} Add tech</div>` : "";

  el.innerHTML = cards + addCard;
}
```

- [ ] **Step 2: Verify the view-mode strip**

Load with the auth bypass on 2026. Confirm five cards in `rotationTechs` order, each with a coloured left border matching that person elsewhere, and:
- Joshua Garrett - "10 weeks &middot; next Sep 13" - "4 numbers on file"
- Nick Zoshak - "10 weeks &middot; on call now" - "1 number on file" **in amber**
- Joe Randazzo - "10 weeks &middot; next Sep 6" - "2 numbers on file"
- Robert Tyson - "10 weeks &middot; next Sep 27" - "2 numbers on file"
- Krista Guthrie - "9 weeks &middot; next Sep 20" - "3 numbers on file"

Clicking a card opens that person's contact panel. No grip handles and no add tile are visible.

- [ ] **Step 3: Verify the edit-mode strip and reorder**

Run `st.isAdmin = true; renderAll(); toggleEditMode();`. Confirm:
- Each card gains a grip icon top-right, and a dashed "Add tech" tile appears after the fifth card (wrapping to a second row - expected).
- Drag the first card onto the third position. Confirm the cards reorder, `st.data.rotationTechs` order changes to match, and **the colours do not shuffle** (colours are keyed to sorted `shortName`, not array position, since the Build Mode work).
- Confirm the year board re-renders and its cell colours are unchanged by the reorder.
- Confirm `saveChanges()` fires - with `ONCALL_SAVE_URL` blank it will fall through its no-backend path; verify no console error.
- Click "Add tech": a new "New Person" entry appends and the contact panel opens for it. Reload to discard - **do not save**.

- [ ] **Step 4: Verify dark mode and commit**

Screenshot both themes; confirm the amber "1 number on file" is legible in dark and the left border colour reads clearly against dark glass.

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: add the per-tech summary strip, carrying over drag-to-reorder and add-to-rotation"
```

---

### Task 10: Also reachable bar

**Files:**
- Modify: `tools/on-call/index.html` (replace the `renderAlsoReachable` stub)

- [ ] **Step 1: Implement `renderAlsoReachable`**

Replace `function renderAlsoReachable() {}` with:

```javascript
function renderAlsoReachable() {
  const el = document.getElementById("alsoReachable");
  const canEdit = st.isAdmin && editMode;
  const chips = st.data.otherContacts.map((c, i) => `
    <span class="also-chip" onclick="openContactPanel('other', ${i})">
      <span class="also-avatar" style="background:${OTHER_CONTACT_COLOR}">${initials(c.name)}</span>${c.name}
    </span>`).join("");
  const addChip = canEdit
    ? `<span class="also-add" onclick="addContact('other')">${ICON_PLUS} Add</span>` : "";

  if (!chips && !addChip) { el.style.display = "none"; return; }
  el.style.display = "flex";
  el.innerHTML = `<span class="also-lbl">Also reachable</span>${chips}${addChip}`;
}
```

- [ ] **Step 2: Verify**

Load with the auth bypass. Confirm:
- One line reading "ALSO REACHABLE" followed by three grey-avatar chips: Andy Singh, Justin Canales, Ian Sanchez.
- Total height is one row, materially shorter than the 172px card grid it replaces.
- Clicking a chip opens that contact's panel.
- In edit mode a dashed "+ Add" chip appears; clicking it appends a contact and opens the panel. Reload to discard.
- Screenshot both themes.

- [ ] **Step 3: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: replace the other-contacts grid with a single also-reachable bar"
```

---

### Task 11: Find a person

**Files:**
- Modify: `tools/on-call/index.html` (replace the `toggleFindPanel` stub)

The brief specs pure highlight. This adds the year-switch fallback so the jump-to-next-upcoming behaviour added on 2026-09-03 is not silently lost.

- [ ] **Step 1: Implement the find panel and highlight**

Replace `function toggleFindPanel() {}` with:

```javascript
function renderFindPanel() {
  document.getElementById("findPanel").innerHTML = st.data.rotationTechs.map(t => `
    <div class="find-option${st.highlightTech === t.shortName ? " on" : ""}" onclick="highlightPerson('${t.shortName}')">
      <span class="find-avatar" style="background:${personColorFor(t.shortName)}">${initials(t.name)}</span>
      ${t.name}
    </div>`).join("");
}

function toggleFindPanel() {
  const panel = document.getElementById("findPanel");
  const opening = panel.style.display === "none";
  if (opening) renderFindPanel();
  panel.style.display = opening ? "block" : "none";
}

function highlightPerson(shortName) {
  document.getElementById("findPanel").style.display = "none";

  if (st.highlightTech === shortName) { clearHighlight(); return; }
  st.highlightTech = shortName;

  // If this tech has no weeks in the year on screen, jump to the year holding
  // their next upcoming shift, falling back to their most recent past one.
  if (!getYearWeeks(st.year).some(r => r.tech === shortName)) {
    const rows = sortedByDate(st.data.schedule.filter(r => r.tech === shortName));
    const target = rows.find(r => daysFromToday(r.startDate) >= 0) || rows[rows.length - 1];
    if (target) {
      st.year = target.startDate.slice(0, 4);
      renderYearSeg();
      renderToolbar();
      renderAttention();
      renderRosterNotes();
      renderTechStrip();
    }
  }

  const tech = st.data.rotationTechs.find(t => t.shortName === shortName);
  document.getElementById("findBtn").innerHTML = ICON_SEARCH + " " + (tech ? tech.name : shortName);
  renderYearBoard();
}

function clearHighlight() {
  if (!st.highlightTech) return;
  st.highlightTech = null;
  document.getElementById("findBtn").innerHTML = ICON_SEARCH + " Find a person";
  renderYearBoard();
}
```

- [ ] **Step 2: Wire Escape to clear the highlight**

In `init`, insert after the find-panel click-outside listener added in Task 3:

```javascript
  document.addEventListener("keydown", evt => {
    if (evt.key !== "Escape") return;
    document.getElementById("findPanel").style.display = "none";
    clearHighlight();
  });
```

- [ ] **Step 3: Verify**

Load with the auth bypass. Confirm:
- Clicking "Find a person" opens a dropdown of all five techs, each with their real avatar colour.
- Picking Krista Guthrie dims every non-Krista cell to 35% opacity, leaves her 9 cells at full colour, and relabels the button "Find a person" -> "Krista Guthrie". Verify via `document.querySelectorAll('#yearBoard .wk.dim').length` equalling `52 - 9` = `43`.
- Picking Krista again clears the highlight and restores the button label.
- Pressing Escape clears an active highlight.
- Clicking outside the open dropdown closes it without selecting.
- The dropdown is opaque, not see-through (it uses `--panel-fill`).
- **Year-switch fallback:** run `setYear('2024'); highlightPerson('Krista');`. Krista has no 2024 rows, so the board should switch to the year holding her next upcoming shift (2026) and highlight there. Confirm the year segment updates to match.
- Screenshot both themes with a highlight active.

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: add find-a-person board highlighting with an upcoming-year fallback"
```

---

### Task 12: Build Mode regression pass

**Files:**
- Verify only: `tools/on-call/index.html` (no edits expected; `setBuildViewVisibility` was already repointed in Task 3)

Build Mode shipped on 2026-09-03 and must survive the relayout untouched. This task is verification, plus fixes only if something is found.

- [ ] **Step 1: Verify the build trigger and setup bar**

Run `st.isAdmin = true; renderAll(); toggleEditMode();`. Confirm:
- A green "Build 2027 Rotation" button appears in the toolbar's right group, inside `#buildTriggerWrap`.
- Clicking it hides `#yearBoard`, `#techStrip`, and `#alsoReachable`, and shows the setup bar.
- **The left rail stays visible**, mirroring how the hero stayed visible before this redesign.
- The setup bar still reads its continuation point correctly from the last 2026 row.

- [ ] **Step 2: Verify the canvas, drag-swap, popover, and discard**

- "Generate Proposal" shows the month-grouped canvas of 56px blocks with ordinal dates.
- Drag one proposed block onto another: the two techs swap.
- Click a proposed block: the inline popover opens with tech / time off / notes, and applying a change updates the block.
- Existing/gap-filled weeks render dimmed and are not draggable.
- "Discard" returns to the normal view with the board, strip, and also-reachable bar all restored, and the Build button reappears.

- [ ] **Step 3: Verify commit and edit-mode exit**

- "Commit" writes the proposed rows into `st.data.schedule`, returns to the normal view, and the year segment now offers 2027 with a full board.
- Reload (discarding), then re-enter build and toggle Edit Mode off mid-build: build should close and the normal view return.
- Screenshot the canvas in both themes.

- [ ] **Step 4: Commit (only if Step 1-3 found and fixed something)**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: fix Build Mode integration with the layout 1a shell"
```

---

### Task 13: Dark mode audit

**Files:**
- Modify: `tools/on-call/index.html` (page `<style>` block, only if the audit finds a problem)

Every earlier task screenshotted both themes, so this is a focused sweep for anything that slipped through, plus the two treatments flagged during design as needing a judgement call once rendered.

- [ ] **Step 1: Prove there are no hardcoded colours in the new CSS**

From the repo root:

```bash
sed -n '/oc-layout/,/Build Mode/p' tools/on-call/index.html | grep -nE '#[0-9a-fA-F]{3,6}|rgba?\('
```

Expected: only `color:#fff` on `.wk`, `.now-avatar`, `.find-avatar`, `.also-avatar`, and `.year-seg span.on`, plus the `rgba(0,0,0,.2)` in `.wk.today`'s drop shadow. Every one of those is intentional - white on a saturated tech colour is correct in both themes, and a black drop shadow is correct in both. **Any other literal is a bug**; replace it with the matching token.

- [ ] **Step 2: Review the two flagged treatments in dark mode**

Load the tool in dark mode with a full render and look specifically at:
- **`.now-pip.today`'s ring.** It uses `var(--glass-raise-border)`, which is `rgba(255,255,255,.14)` in dark and may read too faint to mark today. If it does, add a page-scoped override rather than changing the shared token:

```css
    [data-theme="dark"] .now-pip.today { box-shadow:0 0 0 2px rgba(255,255,255,.45); }
```

- **The now card's tint strength.** It is `color-mix(in srgb, var(--tech-color) 20%, var(--glass-fill))`, and dark's `--glass-fill` has very low alpha, so per the 2026-09-03 hero precedent it should look materially similar. If the tech colour does not read at all, bump the dark percentage page-scoped:

```css
    [data-theme="dark"] .now-card { background:color-mix(in srgb, var(--tech-color) 28%, var(--glass-fill)); }
```

- [ ] **Step 3: Full both-theme sweep**

In each of light and dark, screenshot and confirm legibility of: the now card and all its inner rows, queue rows and their dividers, both note cards' icons and text, the year segment, all three board cell states (normal / today+NOW / unmatched dashed), a highlight-dimmed board, all five tech cards including the amber warning, the also-reachable bar, the find dropdown open, and the build canvas. Confirm zero console errors in both.

- [ ] **Step 4: Commit (only if Steps 1-3 changed anything)**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: dark-mode corrections for the layout 1a components"
```

---

### Task 14: Push the structural migration to preview

**Files:**
- None modified. This task pushes Tasks 1-13.

- [ ] **Step 1: Final pre-push review**

```bash
git status
git log --oneline origin/testing..HEAD
git diff origin/testing..HEAD --stat
```

Expected: a clean tree, ~11-13 commits, and only `shared/styles.css` and `tools/on-call/index.html` changed. **If any other file appears, stop and investigate** - especially anything containing real contact data, per the known public-Pages exposure.

- [ ] **Step 2: Confirm no real data is being added**

```bash
git diff origin/testing..HEAD | grep -cE '[0-9]{3}-[0-9]{3}-[0-9]{4}'
```

Expected: `0`. This redesign must not introduce any new copy of real phone numbers.

- [ ] **Step 3: Push**

```bash
git push origin testing
```

- [ ] **Step 4: Confirm both deploy hops**

The preview deploy is two hops and both must be polled - matching by `head_sha`, never by "newest run":

1. `it-tools` -> workflow "Deploy to Preview" for the pushed SHA must report `success`.
2. `jgdev-ch/it-tools-preview` -> its own Pages build must then report `success`.

Then confirm the served HTML actually contains the new code:

```bash
curl -s "https://jgdev-ch.github.io/it-tools-preview/tools/on-call/" | grep -c "oc-layout"
```

Expected: at least `1`. If it returns `0`, the Pages cache has not rolled over yet (GitHub Pages sets `max-age=600`); re-check response headers (`Last-Modified` / `Age` / `X-Cache`) before assuming a deploy failure.

- [ ] **Step 5: Hand off for review**

Report to Josh that 1a is live on `https://jgdev-ch.github.io/it-tools-preview/tools/on-call/` and ready for a click-through punch list. Remind him that each tool subpage caches independently, so a hard refresh on the hub tab does not refresh an already-open tool tab.

**Deliberately not done in this plan** (all per the spec's Out of Scope): no changelog entry, no `ONCALL_GET_URL`/`ONCALL_SAVE_URL` wiring, no page-level lock, no responsive work, and no promotion to `main`.
