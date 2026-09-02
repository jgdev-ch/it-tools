# On-Call Rotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the On-Call Rotation hub tool (`tools/on-call/index.html`) with a live, admin-editable schedule backed by a new Azure Function App, replacing the team's shared `On Call Rotation.xlsx`.

**Architecture:** Two repos are touched. `it-tools` (this repo, `testing` branch) gets the new hub tool page, its seed data, a hub-card entry, and a new **deny-gate** mechanism (the inverse of the hub's existing allow-gates) so `SG-IT-Tools-GSD` members can't see the card. `adobe-func` (`C:\dev\projects\adobe-func`) gets two new HTTP functions, `OnCallGet`/`OnCallSave`, added to the existing Node-v4-programming-model Azure Functions project (same repo that already hosts `AdobeProducts.js`/`AdobeMembers.js`), reading/writing a JSON blob via the Function App's own managed identity — no SAS in client JS. The new Function App itself (`p-corp-fa-ittools-azuc-01`), its own dedicated Entra App Registration (EasyAuth needs one per Function App — mirrors the existing `7ad27c90-...` "IT Tools - Adobe License Monitor Function" registration), the `oncall-rotation` storage container, and the `SG-IT-Tools-OnCall-Admin` Entra group are **new infrastructure** — Tasks 1–9 (all code) can be built and locally verified without any of it existing yet; Tasks 10–11 provision and wire it up.

**Tech Stack:** Vanilla JS/HTML/CSS (hub tool, no build step, no framework — matches every other tool in `it-tools`). `@azure/functions` v4 programming model + `@azure/identity` + `@azure/storage-blob` (Function code, Node 22, Linux, Flex Consumption — matches `adobe-func`'s existing Adobe functions). Azure CLI for infra provisioning (confirmed working and authenticated this session).

---

### Task 1: Generate the seed data file from the source workbook

**Files:**
- Create (scratch, not committed): `C:\Users\JOSHUA~1\AppData\Local\Temp\claude\C--dev\767580f2-0a2b-489a-a6cd-a11d230ff1d9\scratchpad\generate-oncall-data.js`
- Create (committed): `tools/on-call/data.json`

The full 2024–2026 schedule is 161 rows across 3 sheets with two different date encodings (text dates in 2024/2026, Excel date serials in 2025) — generating this from the source `.xlsx` programmatically avoids any hand-transcription error versus typing 161 rows by hand.

- [ ] **Step 1: Write the generator script**

```javascript
// generate-oncall-data.js
const fs = require('fs');
const JSZip = require('C:/dev/projects/it-tools/tools/group-import/jszip.min.js');

const SRC = "C:/Users/JoshuaGarrett/OneDrive - CorroHealth/Documents/IT Tools Hub/On Call Rotation App/On Call Rotation.xlsx";
const excelEpoch = Date.UTC(1899, 11, 30);

function serialOrTextToIso(raw) {
  if (/^\d+$/.test(raw)) {
    const d = new Date(excelEpoch + parseInt(raw, 10) * 86400000);
    return d.toISOString().slice(0, 10);
  }
  // "Sunday, January 4, 2026" -> strip weekday prefix, then Date.parse
  const cleaned = raw.replace(/^[A-Za-z]+,\s*/, '');
  const d = new Date(cleaned + ' UTC');
  return d.toISOString().slice(0, 10);
}

async function readSheet(zip, relMap, sharedStrings, sheetName, workbookXml) {
  const sheetMatch = [...workbookXml.matchAll(/<sheet[^>]*name="([^"]*)"[^>]*r:id="([^"]*)"/g)]
    .find(m => m[1] === sheetName);
  const target = relMap[sheetMatch[2]];
  const xml = await zip.file('xl/' + target).async('string');
  const rows = [...xml.matchAll(/<row[^>]*r="(\d+)"[^>]*>([\s\S]*?)<\/row>/g)];
  return rows.map(row => {
    const cells = [...row[2].matchAll(/<c[^>]*r="([A-Z]+)\d+"(?:[^>]*t="([^"]*)")?[^>]*>(?:<v>([^<]*)<\/v>)?<\/c>/g)];
    const byCol = {};
    cells.forEach(c => {
      let val = c[3] || '';
      if (c[2] === 's' && val !== '') val = sharedStrings[parseInt(val, 10)] || '';
      byCol[c[1]] = val;
    });
    return byCol;
  }).filter(r => r.A); // drop fully-blank trailing rows
}

async function main() {
  const zip = await JSZip.loadAsync(fs.readFileSync(SRC));
  const workbookXml = await zip.file('xl/workbook.xml').async('string');
  const relsXml = await zip.file('xl/_rels/workbook.xml.rels').async('string');
  const relMap = {};
  [...relsXml.matchAll(/<Relationship[^>]*Id="([^"]*)"[^>]*Target="([^"]*)"/g)]
    .forEach(m => relMap[m[1]] = m[2]);
  const ssXml = await zip.file('xl/sharedStrings.xml').async('string');
  const sharedStrings = [...ssXml.matchAll(/<si>([\s\S]*?)<\/si>/g)].map(m =>
    [...m[1].matchAll(/<t[^>]*>([^<]*)<\/t>/g)].map(t => t[1]).join('')
  );

  const schedule = [];
  for (const sheetName of ['2024-Schedule', '2025-Schedule', '2026-Schedule']) {
    const rows = await readSheet(zip, relMap, sharedStrings, sheetName, workbookXml);
    rows.slice(1).forEach(r => { // slice(1) drops the header row
      if (!r.A || !r.B) return;
      schedule.push({
        startDate: serialOrTextToIso(r.A),
        tech: r.B,
        timeOff: r.C || '',
        notes: r.E || ''
      });
    });
  }

  const phoneRows = await readSheet(zip, relMap, sharedStrings, 'Phone Details', workbookXml);
  const people = {};
  let current = null;
  phoneRows.forEach(r => {
    if (r.A && !r.B) { current = r.A; people[current] = []; }
    else if (r.A && r.B && current) { people[current].push({ label: r.A, number: r.B }); }
  });

  const rotationNames = { Joshua: 'Joshua Garrett', Nick: 'Nick Zoshak', Joe: 'Joe Randazzo', Robert: 'Robert Tyson', Krista: 'Krista Guthrie' };
  const rotationTechs = Object.entries(rotationNames).map(([shortName, fullName]) => ({
    name: fullName, shortName, phones: people[fullName] || []
  }));
  const otherNames = ['Andy Singh', 'Justin Canales', 'Ian Sanchez'];
  const otherContacts = otherNames.map(name => ({ name, phones: people[name] || [] }));

  const out = { schedule, rotationTechs, otherContacts };
  fs.writeFileSync('C:/dev/projects/it-tools/tools/on-call/data.json', JSON.stringify(out, null, 2));
  console.log('schedule rows:', schedule.length);
  console.log('rotationTechs:', rotationTechs.map(t => t.name + ' (' + t.phones.length + ' numbers)'));
  console.log('otherContacts:', otherContacts.map(t => t.name + ' (' + t.phones.length + ' numbers)'));
  console.log('sample first/last schedule rows:', schedule[0], schedule[schedule.length - 1]);
}
main().catch(e => { console.error(e); process.exit(1); });
```

- [ ] **Step 2: Create the output directory and run it**

```bash
mkdir -p "C:/dev/projects/it-tools/tools/on-call"
/c/dev/tools/nodejs/node.exe "C:/Users/JOSHUA~1/AppData/Local/Temp/claude/C--dev/767580f2-0a2b-489a-a6cd-a11d230ff1d9/scratchpad/generate-oncall-data.js"
```

Expected output: `schedule rows: 147` (43 in 2024 + 52 in 2025 + 52 in 2026 — actual row ranges are one shorter per year than the loose "~53 rows/year" estimate made during brainstorming), `rotationTechs:` listing all 5 names each with >0 numbers (Nick shows `(1 numbers)`), `otherContacts:` listing all 3 names each with >0 numbers.

- [ ] **Step 3: Verify no David Wilhite leaked into the output**

```bash
grep -c "Wilhite" "C:/dev/projects/it-tools/tools/on-call/data.json"
```

Expected: `0` in the `rotationTechs`/`otherContacts` arrays — if this greps a hit, check it's only inside a `schedule[].tech` string value (his name is expected there historically), not a `rotationTechs`/`otherContacts` entry.

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/data.json
git commit -m "Add On-Call Rotation seed data generated from the source workbook"
```

---

### Task 2: Hub card + deny-gate mechanism — ✅ DONE (as-built, differs from original draft below)

**Files:**
- Modified: `config.json` (new `on-call` entry, `denyGate: "gsd"`)
- Modified: `index.html` (`cardHtml`, `runGateChecks`, new `applyDenyGates`)

**Reality check during execution:** the hub already had `buildLiveCard`/`buildComingSoonCard`/`buildLockedCard` helpers and an `isClickableStatus` gate — the original draft below invented a redundant `buildOpenCard`/`TOOL_ICONS` that don't exist in this codebase. Also, `gsd` was **already** a registered `GROUP_GATES` entry (used by `guest-audit`/`license-audit` for a different, in-tool purpose) — no new gate entry was needed, just a new consumer of the existing one. Built as:

- `config.json`: added the `on-call` tool entry with `"denyGate": "gsd"` and a real inline Lucide phone SVG icon (matching the existing icon convention — single-quoted attrs so it embeds safely inside a double-quoted `data-icon="..."` HTML attribute later).
- `cardHtml()`: inside the existing `isClickableStatus(tool.status) && tool.path` branch, if `tool.denyGate` is set, call the real `buildLiveCard(...)` and `.replace('<a class="tool-card"', ...)` to inject `data-deny`/`data-accent`/`data-icon`/`data-name` attributes onto the resulting anchor — no new card-building function.
- `runGateChecks()`: added `await applyDenyGates(token)` at the end.
- New `applyDenyGates(token)`: for every `[data-deny]` element, resolve the referenced `GROUP_GATES` entry and call the *existing* `checkMembership(token, gate.id)` helper (same one the allow-gates already use); on a match, swap the card's `outerHTML` for a small inline restricted-card snippet reusing only pre-existing classes (`.tool-card.no-hover`, `.tool-icon-sq`, `.tool-name`, `.tool-desc`) — **no new CSS was needed**, so the `.tool-card-denied` style from the original draft below was dropped entirely.
- Verified via Playwright against a local static server: confirmed the card renders with the correct `data-deny="gsd"`/name/href/icon, then mocked `checkMembership` to return true for the `gsd` id and confirmed `applyDenyGates` correctly swapped the card to `.tool-card.no-hover` with "Restricted for your access group" text.

Committed as `0971660`.

<details>
<summary>Original draft (superseded by the above — kept only for history)</summary>

The hub's existing gates are all **allow-gates**: a card starts locked, and unlocks only for members of a specific group. On-Call needs the opposite — visible by default, hidden specifically for `SG-IT-Tools-GSD` members.

Original plan assumed a `TOOL_ICONS` lookup table and a from-scratch `buildOpenCard`/`.tool-card-denied` CSS class, neither of which turned out to exist or be necessary — see the as-built summary above for what was actually done instead.

</details>

---

### Task 3: Tool skeleton, sign-in, and data loading

**Files:**
- Create: `tools/on-call/index.html`

- [ ] **Step 1: Write the skeleton**

Base this on `tools/exchange-audit/index.html`'s head/topbar/sign-in boilerplate (loads `shared/auth.js` + `shared/styles.css`, calls `ITTools.ui.renderTopbar` + `theme.init`, same pattern already proven this session to require **no MSAL** just for page chrome, but On-Call's spec requires sign-in to view — so unlike Exchange Audit, wrap the content in the standard hub sign-in gate used by `tools/user-creation/index.html` — `authScreen`/`appScreen` divs, `doSignIn()`).

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>On-Call Rotation: IT Tools Hub</title>
<link rel="stylesheet" href="../../shared/styles.css">
<style>
  .hero { background: var(--accent-cyan-light, var(--blue-light)); border: 1px solid var(--border); border-radius: 12px; padding: 20px; margin-bottom: 20px; }
  .hero-label { font-size: 11px; font-weight: 700; color: var(--muted); text-transform: uppercase; letter-spacing: .06em; }
  .hero-name { font-size: 24px; font-weight: 700; margin: 4px 0 10px; }
  .hero-phones { display: flex; gap: 16px; flex-wrap: wrap; }
  .hero-phone { font-size: 13px; color: var(--text); }
  .hero-phone .lbl { color: var(--muted); margin-right: 6px; }
  .year-tabs { display: flex; gap: 8px; margin-bottom: 12px; }
  .year-tab { padding: 6px 14px; border-radius: 8px; border: 1px solid var(--border); background: var(--surface); cursor: pointer; font-size: 13px; }
  .year-tab.active { background: var(--blue); color: #fff; border-color: var(--blue); }
  .contact-cards { display: flex; gap: 12px; flex-wrap: wrap; margin-top: 20px; }
  .contact-card { border: 1px solid var(--border); border-radius: 10px; padding: 12px 14px; min-width: 200px; background: var(--surface); }
  .contact-card h4 { margin: 0 0 6px; font-size: 14px; }
  .contact-card .phone-row { font-size: 12px; color: var(--muted); }
  .other-contacts-label { font-size: 11px; font-weight: 700; color: var(--muted); text-transform: uppercase; letter-spacing: .06em; margin: 20px 0 8px; }
</style>
</head>
<body>
<div id="topbar"></div>

<div id="authScreen" class="auth-screen">
  <div class="auth-card">
    <h1>On-Call Rotation</h1>
    <p>Sign in with your M365 account to view the on-call schedule.</p>
    <button class="btn-ms" onclick="doSignIn()">Sign in with Microsoft</button>
    <div class="auth-error" id="authErr"></div>
  </div>
</div>

<div id="appScreen" style="display:none">
  <div class="app-body">
    <main class="main-content" style="max-width:900px;margin:0 auto;padding:24px">
      <div id="deniedScreen" style="display:none">
        <h2>Access Restricted</h2>
        <p>This tool isn't available for your access group.</p>
      </div>
      <div id="toolContent" style="display:none">
        <h1>On-Call Rotation</h1>
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
      </div>
    </main>
  </div>
</div>

<script src="../../shared/auth.js"></script>
<script>
const TOOL_SCOPES = ["User.Read"];
const GSD_GROUP_ID = "3e1a4757-8189-4908-a611-b6029399e69e";
const ONCALL_ADMIN_GROUP = "SG-IT-Tools-OnCall-Admin";

const st = { data: null, year: "2026", isAdmin: false, isDenied: false };

async function doSignIn() {
  try {
    await ITTools.auth.signIn(TOOL_SCOPES);
    await afterSignIn();
  } catch (e) {
    document.getElementById("authErr").textContent = "Sign-in failed: " + e.message;
  }
}

async function afterSignIn() {
  document.getElementById("authScreen").style.display = "none";
  document.getElementById("appScreen").style.display = "block";

  const token = await ITTools.auth.getToken();
  const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
    method: "POST",
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: JSON.stringify({ ids: [GSD_GROUP_ID] }),
  });
  const denied = res.ok && (await res.json()).value.includes(GSD_GROUP_ID);
  if (denied) {
    document.getElementById("deniedScreen").style.display = "block";
    return;
  }
  document.getElementById("toolContent").style.display = "block";

  await checkOnCallAdminAccess();
  await loadData();
}

async function checkOnCallAdminAccess() {
  try {
    const enc = encodeURIComponent(`displayName eq '${ONCALL_ADMIN_GROUP}'`);
    const res = await ITTools.graph.get(`https://graph.microsoft.com/v1.0/groups?$filter=${enc}&$select=id`);
    const groups = res.value || [];
    if (!groups.length) { st.isAdmin = false; return; }
    const groupId = groups[0].id;
    const memberships = await ITTools.graph.getAll(`https://graph.microsoft.com/v1.0/me/transitiveMemberOf?$select=id`);
    st.isAdmin = memberships.some(m => m.id === groupId);
  } catch (_) {
    st.isAdmin = false; // fail secure
  }
}

async function loadData() {
  const res = await fetch("data.json?v=" + Date.now());
  st.data = await res.json();
  renderAll();
}

function renderAll() {
  renderHero();
  renderYearTabs();
  renderScheduleTable();
  renderContacts();
}

window.addEventListener("DOMContentLoaded", () => {
  ITTools.ui.renderTopbar();
  ITTools.auth.init({ scopes: TOOL_SCOPES, onSignedIn: afterSignIn });
});
</script>
</body>
</html>
```

- [ ] **Step 2: Syntax-check the inline JS**

```bash
/c/dev/tools/nodejs/node.exe -e "
const fs = require('fs');
const html = fs.readFileSync('tools/on-call/index.html','utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
fs.writeFileSync('C:/Users/JOSHUA~1/AppData/Local/Temp/claude/C--dev/767580f2-0a2b-489a-a6cd-a11d230ff1d9/scratchpad/oncall_check.js', m[1]);
"
/c/dev/tools/nodejs/node.exe --check "C:/Users/JOSHUA~1/AppData/Local/Temp/claude/C--dev/767580f2-0a2b-489a-a6cd-a11d230ff1d9/scratchpad/oncall_check.js"
```

Expected: no output (clean parse). Note `renderHero`/`renderYearTabs`/`renderScheduleTable`/`renderContacts` are referenced but not yet defined — that's expected and fixed in Tasks 4–5; `node --check` only validates syntax, not references, so this passes even though those functions don't exist yet.

- [ ] **Step 3: Commit**

```bash
git add tools/on-call/index.html
git commit -m "Add On-Call Rotation tool skeleton with sign-in, GSD deny-check, and admin-access check"
```

---

### Task 4: Hero card and year tabs

**Files:**
- Modify: `tools/on-call/index.html` (add `renderHero`, `renderYearTabs`, `setYear`)

- [ ] **Step 1: Implement `renderHero`**

Add before the `renderAll` function:

```javascript
function findCurrentWeek(schedule) {
  const today = new Date();
  const todayUtc = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());
  let best = null;
  for (const row of schedule) {
    const rowUtc = Date.parse(row.startDate + "T00:00:00Z");
    if (rowUtc <= todayUtc && (!best || rowUtc > Date.parse(best.startDate + "T00:00:00Z"))) {
      best = row;
    }
  }
  return best;
}

function renderHero() {
  const week = findCurrentWeek(st.data.schedule);
  const hero = document.getElementById("heroCard");
  if (!week) { hero.innerHTML = "<p>No current on-call week found.</p>"; return; }
  const tech = st.data.rotationTechs.find(t => t.shortName === week.tech);
  hero.innerHTML = `
    <div class="hero-label">On Call This Week</div>
    <div class="hero-name">${tech ? tech.name : week.tech}</div>
    <div class="hero-phones">
      ${(tech ? tech.phones : []).map(p => `<span class="hero-phone"><span class="lbl">${p.label}</span>${p.number}</span>`).join("")}
    </div>
  `;
}
```

- [ ] **Step 2: Implement `renderYearTabs`/`setYear`**

```javascript
function renderYearTabs() {
  const years = ["2024", "2025", "2026"];
  document.getElementById("yearTabs").innerHTML = years.map(y =>
    `<div class="year-tab${y === st.year ? " active" : ""}" onclick="setYear('${y}')">${y}</div>`
  ).join("");
}

function setYear(y) {
  st.year = y;
  renderYearTabs();
  renderScheduleTable();
}
```

- [ ] **Step 3: Manually verify with a local fixture**

Since real MSAL sign-in can't run headlessly, verify the pure date logic in Node directly:

```bash
/c/dev/tools/nodejs/node.exe -e "
const data = require('C:/dev/projects/it-tools/tools/on-call/data.json');
function findCurrentWeek(schedule, todayUtc) {
  let best = null;
  for (const row of schedule) {
    const rowUtc = Date.parse(row.startDate + 'T00:00:00Z');
    if (rowUtc <= todayUtc && (!best || rowUtc > Date.parse(best.startDate + 'T00:00:00Z'))) best = row;
  }
  return best;
}
const todayUtc = Date.parse('2026-09-02T00:00:00Z');
console.log(findCurrentWeek(data.schedule, todayUtc));
"
```

Expected: `{ startDate: '2026-08-30', tech: 'Nick', timeOff: '', notes: '' }` — the week containing 2026-09-02 (a Wednesday) is the Sunday-starting week of 2026-08-30.

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/index.html
git commit -m "Add hero card (current on-call week) and year tabs"
```

---

### Task 5: Schedule table and contacts

**Files:**
- Modify: `tools/on-call/index.html` (add `renderScheduleTable`, `renderContacts`)

- [ ] **Step 1: Implement `renderScheduleTable`**

```javascript
function renderScheduleTable() {
  const rows = st.data.schedule.filter(r => r.startDate.startsWith(st.year));
  document.getElementById("scheduleBody").innerHTML = rows.map(r => `
    <tr>
      <td>${r.startDate}</td>
      <td>${r.tech}</td>
      <td>${r.timeOff || "—"}</td>
      <td>${r.notes || "—"}</td>
    </tr>
  `).join("");
}
```

- [ ] **Step 2: Implement `renderContacts`**

```javascript
function contactCardHtml(person) {
  return `
    <div class="contact-card">
      <h4>${person.name}</h4>
      ${person.phones.map(p => `<div class="phone-row"><strong>${p.label}:</strong> ${p.number}</div>`).join("")}
    </div>
  `;
}

function renderContacts() {
  document.getElementById("rotationCards").innerHTML = st.data.rotationTechs.map(contactCardHtml).join("");
  document.getElementById("otherCards").innerHTML = st.data.otherContacts.map(contactCardHtml).join("");
}
```

- [ ] **Step 3: Syntax-check and verify row counts with a local fixture**

```bash
/c/dev/tools/nodejs/node.exe -e "
const fs = require('fs');
const html = fs.readFileSync('tools/on-call/index.html','utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
fs.writeFileSync('C:/Users/JOSHUA~1/AppData/Local/Temp/claude/C--dev/767580f2-0a2b-489a-a6cd-a11d230ff1d9/scratchpad/oncall_check2.js', m[1]);
"
/c/dev/tools/nodejs/node.exe --check "C:/Users/JOSHUA~1/AppData/Local/Temp/claude/C--dev/767580f2-0a2b-489a-a6cd-a11d230ff1d9/scratchpad/oncall_check2.js"
/c/dev/tools/nodejs/node.exe -e "
const data = require('C:/dev/projects/it-tools/tools/on-call/data.json');
console.log('2026 rows:', data.schedule.filter(r => r.startDate.startsWith('2026')).length);
console.log('rotation cards:', data.rotationTechs.length, 'other cards:', data.otherContacts.length);
"
```

Expected: clean syntax check, `2026 rows: 53`, `rotation cards: 5 other cards: 3`.

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/index.html
git commit -m "Add schedule table and contact cards (rotation + other contacts)"
```

---

### Task 6: Admin lock/unlock edit UI

**Files:**
- Modify: `tools/on-call/index.html`

Editing is scoped to what the spec actually asked for: adding/editing schedule rows and phone numbers, gated to `st.isAdmin`. Kept intentionally simple — a single "Edit Mode" toggle that makes the table and contact cards editable in place, and a Save button that calls `OnCallSave` (wired in Task 7).

- [ ] **Step 1: Add the toggle and editable-state rendering**

Find the `<h1>On-Call Rotation</h1>` line inside `#toolContent` and change to:

```html
        <div style="display:flex;align-items:center;justify-content:space-between">
          <h1>On-Call Rotation</h1>
          <div id="adminControls" style="display:none">
            <label class="tog"><input type="checkbox" id="editToggle" onchange="toggleEditMode()"/><div class="track"></div></label>
            <span>Edit Mode</span>
            <button class="btn btn-primary" id="saveBtn" style="display:none" onclick="saveChanges()">Save</button>
          </div>
        </div>
```

- [ ] **Step 2: Show admin controls and implement the toggle**

Find `await checkOnCallAdminAccess();` in `afterSignIn()` and change the surrounding block to also reveal the controls:

```javascript
  await checkOnCallAdminAccess();
  if (st.isAdmin) document.getElementById("adminControls").style.display = "flex";
  await loadData();
```

Add near `renderContacts`:

```javascript
let editMode = false;

function toggleEditMode() {
  editMode = document.getElementById("editToggle").checked;
  document.getElementById("saveBtn").style.display = editMode ? "inline-block" : "none";
  renderScheduleTable();
  renderContacts();
}
```

- [ ] **Step 3: Make the table editable when `editMode` is on**

Find (the version from Task 5, Step 1):

```javascript
function renderScheduleTable() {
  const rows = st.data.schedule.filter(r => r.startDate.startsWith(st.year));
  document.getElementById("scheduleBody").innerHTML = rows.map(r => `
    <tr>
      <td>${r.startDate}</td>
      <td>${r.tech}</td>
      <td>${r.timeOff || "—"}</td>
      <td>${r.notes || "—"}</td>
    </tr>
  `).join("");
}
```

Change to:

```javascript
function renderScheduleTable() {
  const rows = st.data.schedule.filter(r => r.startDate.startsWith(st.year));
  document.getElementById("scheduleBody").innerHTML = rows.map((r, i) => editMode ? `
    <tr>
      <td><input value="${r.startDate}" onchange="updateScheduleField('${st.year}', ${i}, 'startDate', this.value)"/></td>
      <td><input value="${r.tech}" onchange="updateScheduleField('${st.year}', ${i}, 'tech', this.value)"/></td>
      <td><input value="${r.timeOff}" onchange="updateScheduleField('${st.year}', ${i}, 'timeOff', this.value)"/></td>
      <td><input value="${r.notes}" onchange="updateScheduleField('${st.year}', ${i}, 'notes', this.value)"/></td>
    </tr>
  ` : `
    <tr>
      <td>${r.startDate}</td>
      <td>${r.tech}</td>
      <td>${r.timeOff || "—"}</td>
      <td>${r.notes || "—"}</td>
    </tr>
  `).join("");
}

function updateScheduleField(year, indexInYear, field, value) {
  const yearRows = st.data.schedule.filter(r => r.startDate.startsWith(year));
  const target = yearRows[indexInYear];
  target[field] = value;
}
```

- [ ] **Step 4: Syntax-check**

```bash
/c/dev/tools/nodejs/node.exe -e "
const fs = require('fs');
const html = fs.readFileSync('tools/on-call/index.html','utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
fs.writeFileSync('C:/Users/JOSHUA~1/AppData/Local/Temp/claude/C--dev/767580f2-0a2b-489a-a6cd-a11d230ff1d9/scratchpad/oncall_check3.js', m[1]);
"
/c/dev/tools/nodejs/node.exe --check "C:/Users/JOSHUA~1/AppData/Local/Temp/claude/C--dev/767580f2-0a2b-489a-a6cd-a11d230ff1d9/scratchpad/oncall_check3.js"
```

Expected: clean parse.

- [ ] **Step 5: Commit**

```bash
git add tools/on-call/index.html
git commit -m "Add admin-gated edit mode for the schedule table"
```

---

### Task 7: Wire fetch/save against the (not-yet-deployed) Function endpoints

**Files:**
- Modify: `tools/on-call/index.html`

Follows the same "constant left blank until infra exists, falls back to a local file" pattern already used by `AUDIT_BLOB_URL` (Exchange Audit) and `JOBS_CONTAINER_URL` (User Creation).

- [ ] **Step 1: Add the endpoint constants and update `loadData`**

Find near the top of the `<script>` block:

```javascript
const TOOL_SCOPES = ["User.Read"];
```

Change to:

```javascript
const TOOL_SCOPES = ["User.Read"];
// Left blank until the Function App (Task 10) is provisioned and deployed (Task 11).
// While blank, the tool reads/writes the local data.json file instead of the live blob.
const ONCALL_GET_URL  = "";
const ONCALL_SAVE_URL = "";
```

Find (the version from Task 3, Step 1):

```javascript
async function loadData() {
  const res = await fetch("data.json?v=" + Date.now());
  st.data = await res.json();
  renderAll();
}
```

Change to:

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
  renderAll();
}
```

- [ ] **Step 2: Implement `saveChanges`**

```javascript
async function saveChanges() {
  const btn = document.getElementById("saveBtn");
  btn.disabled = true;
  btn.textContent = "Saving…";
  try {
    if (ONCALL_SAVE_URL) {
      const token = await ITTools.auth.getToken();
      const res = await fetch(ONCALL_SAVE_URL, {
        method: "POST",
        headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
        body: JSON.stringify(st.data),
      });
      if (!res.ok) throw new Error("Save failed: " + res.status);
    } else {
      console.warn("ONCALL_SAVE_URL not configured yet — changes are local-only until Task 10/11 land.");
    }
    btn.textContent = "Saved";
    setTimeout(() => { btn.textContent = "Save"; btn.disabled = false; }, 1500);
  } catch (e) {
    alert("Save failed: " + e.message);
    btn.textContent = "Save";
    btn.disabled = false;
  }
}
```

- [ ] **Step 3: Syntax-check and commit**

```bash
/c/dev/tools/nodejs/node.exe -e "
const fs = require('fs');
const html = fs.readFileSync('tools/on-call/index.html','utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
fs.writeFileSync('C:/Users/JOSHUA~1/AppData/Local/Temp/claude/C--dev/767580f2-0a2b-489a-a6cd-a11d230ff1d9/scratchpad/oncall_check4.js', m[1]);
"
/c/dev/tools/nodejs/node.exe --check "C:/Users/JOSHUA~1/AppData/Local/Temp/claude/C--dev/767580f2-0a2b-489a-a6cd-a11d230ff1d9/scratchpad/oncall_check4.js"
git add tools/on-call/index.html
git commit -m "Wire fetch/save against Function endpoints with local-file fallback"
```

---

### Task 8: `OnCallGet` function

**Files (in `C:\dev\projects\adobe-func`, separate repo):**
- Create: `src/functions/OnCallGet.js`
- Modify: `package.json` (add `@azure/identity`, `@azure/storage-blob`)

- [ ] **Step 1: Add the new dependencies**

```bash
cd /c/dev/projects/adobe-func
/c/dev/tools/nodejs/npm install @azure/identity @azure/storage-blob
```

- [ ] **Step 2: Write `OnCallGet.js`**

```javascript
const { app } = require('@azure/functions');
const { DefaultAzureCredential } = require('@azure/identity');
const { BlobServiceClient } = require('@azure/storage-blob');

const STORAGE_ACCOUNT = 'pcorpsambcleanupazuc01';
const CONTAINER       = 'oncall-rotation';
const BLOB_NAME       = 'data.json';

app.http('OnCallGet', {
    methods: ['GET'],
    authLevel: 'anonymous', // auth handled by EasyAuth (Entra Bearer token required)
    handler: async (request, context) => {
        try {
            const credential = new DefaultAzureCredential();
            const blobService = new BlobServiceClient(`https://${STORAGE_ACCOUNT}.blob.core.windows.net`, credential);
            const container = blobService.getContainerClient(CONTAINER);
            const blob = container.getBlockBlobClient(BLOB_NAME);

            const exists = await blob.exists();
            if (!exists) {
                return { status: 404, body: 'oncall-rotation/data.json not found — has it been seeded yet?' };
            }
            const downloaded = await blob.downloadToBuffer();
            return {
                status: 200,
                headers: { 'Content-Type': 'application/json' },
                body: downloaded.toString('utf-8'),
            };
        } catch (err) {
            return { status: 500, body: 'Internal error: ' + err.message };
        }
    },
});
```

- [ ] **Step 3: Verify it parses**

```bash
/c/dev/tools/nodejs/node.exe --check src/functions/OnCallGet.js
```

Expected: no output. (Cannot run it end-to-end yet — `DefaultAzureCredential` needs either a real managed identity, which only exists once deployed to Azure in Task 11, or local `az login` credentials, and the target container doesn't exist until Task 10.)

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json src/functions/OnCallGet.js
git commit -m "Add OnCallGet function (reads oncall-rotation/data.json via managed identity)"
```

---

### Task 9: `OnCallSave` function (with server-side admin check)

**Files (in `C:\dev\projects\adobe-func`):**
- Create: `src/functions/OnCallSave.js`

The tool's own client-side `checkOnCallAdminAccess()` (Task 6) only controls whether the UI *shows* edit controls — it doesn't stop someone from calling the save endpoint directly with a valid-but-non-admin token. `OnCallSave` re-checks membership server-side using the Function's own managed identity against Microsoft Graph (an **application permission**, not the caller's delegated token — avoids an on-behalf-of flow entirely). This requires a Graph application permission grant, added to the "Not Yet Provisioned" list in Task 10.

- [ ] **Step 1: Write `OnCallSave.js`**

```javascript
const { app } = require('@azure/functions');
const { DefaultAzureCredential } = require('@azure/identity');
const { BlobServiceClient } = require('@azure/storage-blob');

const STORAGE_ACCOUNT     = 'pcorpsambcleanupazuc01';
const CONTAINER           = 'oncall-rotation';
const BLOB_NAME           = 'data.json';
const ADMIN_GROUP_NAME    = 'SG-IT-Tools-OnCall-Admin';

async function getGraphAppToken(credential) {
    const token = await credential.getToken('https://graph.microsoft.com/.default');
    return token.token;
}

async function isCallerAdmin(request, credential) {
    const callerId = request.headers.get('x-ms-client-principal-id');
    if (!callerId) return false;

    const graphToken = await getGraphAppToken(credential);
    const groupRes = await fetch(
        `https://graph.microsoft.com/v1.0/groups?$filter=${encodeURIComponent(`displayName eq '${ADMIN_GROUP_NAME}'`)}&$select=id`,
        { headers: { Authorization: 'Bearer ' + graphToken } }
    );
    if (!groupRes.ok) return false;
    const groups = (await groupRes.json()).value || [];
    if (!groups.length) return false;
    const groupId = groups[0].id;

    const memberRes = await fetch(
        `https://graph.microsoft.com/v1.0/users/${callerId}/checkMemberGroups`,
        {
            method: 'POST',
            headers: { Authorization: 'Bearer ' + graphToken, 'Content-Type': 'application/json' },
            body: JSON.stringify({ groupIds: [groupId] }),
        }
    );
    if (!memberRes.ok) return false;
    const memberOf = (await memberRes.json()).value || [];
    return memberOf.includes(groupId);
}

app.http('OnCallSave', {
    methods: ['POST'],
    authLevel: 'anonymous', // auth handled by EasyAuth (Entra Bearer token required)
    handler: async (request, context) => {
        try {
            const credential = new DefaultAzureCredential();

            const admin = await isCallerAdmin(request, credential);
            if (!admin) {
                return { status: 403, body: 'Not a member of ' + ADMIN_GROUP_NAME };
            }

            const body = await request.json();
            if (!body || !Array.isArray(body.schedule) || !Array.isArray(body.rotationTechs) || !Array.isArray(body.otherContacts)) {
                return { status: 400, body: 'Malformed payload — expected { schedule, rotationTechs, otherContacts }' };
            }

            const blobService = new BlobServiceClient(`https://${STORAGE_ACCOUNT}.blob.core.windows.net`, credential);
            const container = blobService.getContainerClient(CONTAINER);
            const blob = container.getBlockBlobClient(BLOB_NAME);
            const content = JSON.stringify(body, null, 2);
            await blob.upload(content, Buffer.byteLength(content), { overwrite: true });

            return { status: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ saved: true }) };
        } catch (err) {
            return { status: 500, body: 'Internal error: ' + err.message };
        }
    },
});
```

- [ ] **Step 2: Verify it parses**

```bash
/c/dev/tools/nodejs/node.exe --check src/functions/OnCallSave.js
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add src/functions/OnCallSave.js
git commit -m "Add OnCallSave function with server-side admin-group check via managed identity"
```

---

### Task 10: Provision Azure/Entra infrastructure

**No files — Azure CLI / Entra portal actions.** Each of these creates or modifies real, shared infrastructure. Confirm with Josh before running any command in this task — do not run them unattended.

- [ ] **Step 1: Create the Entra security group**

```bash
az ad group create --display-name "SG-IT-Tools-OnCall-Admin" --mail-nickname "SG-IT-Tools-OnCall-Admin" --description "Members can edit the On-Call Rotation schedule in IT Tools Hub"
```

If this hits the same Graph Continuous Access Evaluation challenge seen earlier this session (`InteractionRequired`/`LocationConditionEvaluationSatisfied`), it needs to be done via the Entra admin portal instead (Groups → New group) — note the resulting Object ID either way, since `OnCallSave.js` looks the group up by **display name**, not ID, so no code change is needed once it exists, but Josh should add the initial admin members at creation time.

- [ ] **Step 2: Create the dedicated App Registration for EasyAuth**

Mirrors the existing "IT Tools - Adobe License Monitor Function" registration (client ID `7ad27c90-0ddd-4a3f-8e74-1213de4130f8`) — one app registration per Function App.

```bash
az ad app create --display-name "IT Tools - On-Call Function" --sign-in-audience AzureADMyOrg
```

Note the returned `appId` — needed for Steps 3–4. Expose a custom scope (via the Entra portal: App registration → Expose an API → Add a scope) named `OnCall.ReadWrite`, then grant it to the hub's own MSAL app (client ID `6d881af5-d626-4df6-8969-69f1f0292772`) as an admin-consented OAuth2 permission grant — same process already done for `AdobeData.Read`.

- [ ] **Step 3: Create the Function App**

Matches the existing Adobe Function App's exact configuration (Linux, Flex Consumption FC1, Node 22) confirmed via `az functionapp show`/`az resource show` earlier this session:

```bash
az functionapp create \
  --name p-corp-fa-ittools-azuc-01 \
  --resource-group P-RG-CORP-EUS-AdobeLicenseMonitor-AZUC-01 \
  --storage-account <a storage account for Functions' own runtime state — do not reuse pcorpsambcleanupazuc01 or pcorpsaadobelicazuc01, which are app-data accounts, not Functions runtime accounts> \
  --flexconsumption-location "Central US" \
  --runtime node \
  --runtime-version 22 \
  --functions-version 4
```

The `--storage-account` needs its own dedicated account for Functions' internal runtime state (matching `pcorpsaadobelicfaazuc01`'s role for the Adobe app) — check with Josh whether to create a new small storage account for this (needs Storage Account Contributor, which — per this session's RBAC check — Josh does **not** currently have in either candidate resource group) or reuse an existing Functions-runtime-purpose account if one is available. This may itself need an infra request; don't assume it's unblocked just because the Function App creation rights are confirmed.

- [ ] **Step 4: Enable EasyAuth on the new Function App**

```bash
az webapp auth update \
  --name p-corp-fa-ittools-azuc-01 \
  --resource-group P-RG-CORP-EUS-AdobeLicenseMonitor-AZUC-01 \
  --enabled true \
  --action LoginWithAzureActiveDirectory \
  --aad-client-id <appId from Step 2> \
  --aad-token-issuer-url "https://sts.windows.net/683d57e7-70bf-4bc4-b88d-bd8905a0c39a/v2.0" \
  --aad-allowed-token-audiences "api://<appId from Step 2>"
```

- [ ] **Step 5: Create the storage container and seed it**

```bash
az storage container create --account-name pcorpsambcleanupazuc01 --name oncall-rotation --auth-mode login
az storage blob upload --account-name pcorpsambcleanupazuc01 --container-name oncall-rotation --name data.json --file tools/on-call/data.json --auth-mode login
```

- [ ] **Step 6: Grant the Function App's managed identity access**

```bash
FUNC_PRINCIPAL_ID=$(az functionapp identity show --name p-corp-fa-ittools-azuc-01 --resource-group P-RG-CORP-EUS-AdobeLicenseMonitor-AZUC-01 --query principalId -o tsv)

az role assignment create \
  --assignee "$FUNC_PRINCIPAL_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/3f473b6a-f66b-4932-9a35-d784c3f1231d/resourceGroups/P-RG-CORP-EUS-MailboxCleanup-AZUC-01/providers/Microsoft.Storage/storageAccounts/pcorpsambcleanupazuc01/blobServices/default/containers/oncall-rotation"
```

Then grant the Graph **application permission** `GroupMember.Read.All` (needed by `OnCallSave.js`'s `checkMemberGroups` call) to the managed identity — this needs a Graph admin consent, done via the Entra portal (Enterprise Applications → find the Function App's service principal → API permissions) or:

```bash
az ad app permission add --id <Function App's managed identity's associated app object, if it has one> --api 00000003-0000-0000-c000-000000000000 --api-permissions <GroupMember.Read.All permission id>=Role
```

This step is likely to need the Entra portal rather than CLI — managed identity service principals don't always support `az ad app permission` the same way app registrations do; confirm the exact mechanism when executing this step rather than assuming the command above works as-is.

---

### Task 11: Deploy function code, wire URLs, end-to-end verification

**Files:**
- Modify: `tools/on-call/index.html` (fill in `ONCALL_GET_URL`/`ONCALL_SAVE_URL`)

- [ ] **Step 1: Deploy the function code**

```bash
cd /c/dev/projects/adobe-func
func azure functionapp publish p-corp-fa-ittools-azuc-01
```

(Requires the Azure Functions Core Tools CLI — confirm it's installed; if not, this is a one-time `npm install -g azure-functions-core-tools@4` first.)

- [ ] **Step 2: Fill in the URL constants**

```javascript
const ONCALL_GET_URL  = "https://p-corp-fa-ittools-azuc-01.azurewebsites.net/api/OnCallGet";
const ONCALL_SAVE_URL = "https://p-corp-fa-ittools-azuc-01.azurewebsites.net/api/OnCallSave";
```

- [ ] **Step 3: Push to testing and verify on preview**

```bash
git add tools/on-call/index.html
git commit -m "Wire On-Call Rotation to the live Function endpoints"
git push origin testing
```

On the deployed preview URL: sign in, confirm the hero card/table/contacts render from the live blob (not the local `data.json` fallback), toggle Edit Mode as an `SG-IT-Tools-OnCall-Admin` member, change a field, Save, then reload the page and confirm the change persisted. Separately, sign in as a non-admin account and confirm Edit Mode never appears; sign in as an `SG-IT-Tools-GSD` member and confirm the hub card shows as restricted and the tool page shows the denied screen if reached directly.

- [ ] **Step 4: Update the hub changelog**

Follow the established convention (changelog entry ships in the same push as the feature, not deferred) — add a new version entry to `changelog.json` and bump the footer version string in `index.html`, same as done for the User Creation India-groups feature earlier this session.

---

## Out of Scope

- No year-2027 schedule — added later by an admin through the edit UI once finalized, not part of this build.
- No per-row validation beyond what's already in the browser (e.g. no server-side check that `tech` is a real rotation name) — this mirrors the spreadsheet's own lack of validation and isn't a regression.
- No notification/Teams-post on save — schedule changes are silent, matching the spec (which didn't ask for one).
- No retry/offline queue if `OnCallSave` fails — a failed save just shows an alert; the admin retries manually.
