# Group Administration Tool — v1 (Graph-live) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the single-purpose "Group Import" tool into a card-launcher → per-type wizard that manages **add / remove / export** for **Entra security groups** and **Microsoft 365 groups**, all live in the browser via Microsoft Graph. (v2 adds the Exchange script-gen types — out of scope here.)

**Architecture:** One static `index.html` (hub pattern) refactored into three layers: a **launcher** (object-type card grid), a **wizard shell** (step nav for the selected type), and a small **operations layer** (Graph add/remove/export). A config-driven **object-type registry** describes each card and drives the wizard. v1 wires the two Graph cards live; the three Exchange cards render but are disabled ("v2").

**Tech Stack:** Static HTML/JS, MSAL (`shared/msal-browser.min.js`), shared helpers in `shared/auth.js` (`ITTools.auth`, `ITTools.graph` with `get/getAll/post/patch/del/friendlyError`, `ITTools.csv` with `parse/detectEmailColumn/download`, `ITTools.ui`, `ITTools.theme`), `shared/styles.css`. No build step; no JS test framework.

**Testing approach (codebase-adapted):** This repo has no JS test harness; hub tools are verified manually in-browser against a test group, dry-run before live. Each task below ends with a concrete manual verification (open the tool, do X, expect Y) and, for pure functions, a browser-console check. Use a disposable test security group and a 3-row CSV throughout.

**Branch/deploy:** Work on `testing` (auto-deploys to preview). Do not merge to `main` — promotion is Josh's explicit call.

---

## File Structure

- **Modify (major refactor):** `tools/group-import/index.html` — becomes launcher + wizard shell + Graph operations. Folder path kept for URL stability; only the display name rebrands.
- **Modify:** `config.json` — rebrand the `group-import` entry (name → "Group Administration", new description, permissions list). `id` and `path` unchanged.
- **No changes:** `shared/auth.js`, `shared/styles.css` (reused as-is).

Design note: to match the hub's one-file-per-tool convention, all JS stays inline in `index.html`, organized into clearly-commented sections (registry → launcher → router → wizard → operations → results). Reused functions from the current file (`loadFile`, `parseAndRender`, `getPrimed`, `renderRunStats`, `renderLog`, `filterRes`, `exportLog`) are preserved and re-homed under the operations/results sections.

---

## Task 1: Rebrand config.json entry

**Files:**
- Modify: `config.json:15-25` (the `group-import` object)

- [ ] **Step 1: Update the tool entry**

Replace the `group-import` object's `name`, `description`, and `permissions` (keep `id`, `icon`, `status`, `path`, `accent`, `category`):

```json
    {
      "id": "group-import",
      "name": "Group Administration",
      "description": "Add, remove, and export members across Entra security groups and Microsoft 365 groups from CSV, with dry-run preview and audit log. Distribution lists and shared mailboxes coming soon.",
      "icon": "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='#047857' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2'/><path d='M16 3.128a4 4 0 0 1 0 7.744'/><path d='M22 21v-2a4 4 0 0 0-3-3.87'/><circle cx='9' cy='7' r='4'/></svg>",
      "status": "live",
      "path": "tools/group-import/",
      "permissions": ["User.Read.All", "Group.ReadWrite.All", "GroupMember.ReadWrite.All", "Directory.Read.All"],
      "accent": "var(--accent-green)",
      "category": "daily-ops"
    },
```

- [ ] **Step 2: Verify JSON is valid**

Run: `/c/dev/tools/nodejs/node.exe -e "JSON.parse(require('fs').readFileSync('config.json','utf8')); console.log('config.json OK')"`
Expected: `config.json OK`

- [ ] **Step 3: Commit**

```bash
git add config.json
git commit -m "Group Admin: rebrand hub card to Group Administration"
```

---

## Task 2: Object-type registry

Introduces the config object that drives both the launcher cards and the wizard. This is the single source of truth for which types exist, their backend, and (v1) which are enabled.

**Files:**
- Modify: `tools/group-import/index.html` — add a `<script>` section `// ── Object-type registry ──` immediately after `const st = {...}` state (currently near `index.html:358`).

- [ ] **Step 1: Add the registry**

```js
// ── Object-type registry ───────────────────────────────────────
// backend: "graph" (live) | "exchange" (v2 script-gen, disabled in v1)
// source:  "members" | "permissions"
const OBJECT_TYPES = [
  { id:"security-group", label:"Security Group", backend:"graph", source:"members",
    icon:"🛡️", tag:"Live · Graph", enabled:true,
    graphKind:"security", // used to filter lookup
    ops:["add","remove","export"] },
  { id:"m365-group", label:"Microsoft 365 Group", backend:"graph", source:"members",
    icon:"📦", tag:"Live · Graph", enabled:true,
    graphKind:"unified",
    ops:["add","remove","export"] },
  { id:"distribution-list", label:"Distribution List", backend:"exchange", source:"members",
    icon:"📧", tag:"Script · EXO", enabled:false, ops:["add","remove","export"] },
  { id:"mail-security-group", label:"Mail-enabled Security Group", backend:"exchange", source:"members",
    icon:"🔐", tag:"Script · EXO", enabled:false, ops:["add","remove","export"] },
  { id:"shared-mailbox", label:"Shared Mailbox", backend:"exchange", source:"permissions",
    icon:"📬", tag:"Script · EXO", enabled:false, ops:["grant","remove","export"] },
];
function getType(id){ return OBJECT_TYPES.find(t => t.id === id) || null; }
```

- [ ] **Step 2: Verify in browser console**

Open the tool (preview URL), open DevTools console, run:
`OBJECT_TYPES.filter(t=>t.enabled).map(t=>t.id)`
Expected: `["security-group", "m365-group"]`

- [ ] **Step 3: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin: add object-type registry"
```

---

## Task 3: Launcher view (card grid) + shell containers

Replaces the current single-purpose Step-1/2/3 markup with a launcher container and a (hidden) wizard container. The launcher renders cards from the registry, grouped by backend.

**Files:**
- Modify: `tools/group-import/index.html` — replace the `<main class="main-content">…</main>` contents (currently `index.html:121-277`) with the launcher + wizard-shell markup below. Also update the sidebar `How it works` copy and the auth-screen `<h1>`/`<p>` text (`index.html:79-80`) to "Group Administration".

- [ ] **Step 1: Replace `<main>` markup**

```html
<main class="main-content" style="max-width:900px">

  <!-- LAUNCHER -->
  <div id="launcher">
    <div class="section-hdr">
      <h2>Group Administration</h2>
      <p>Pick what you're working with. Security and Microsoft 365 groups run live here; the Exchange types generate a PowerShell script (coming soon).</p>
    </div>
    <div id="launcherLive"></div>
    <div id="launcherScript" style="margin-top:1.25rem"></div>
  </div>

  <!-- WIZARD (hidden until a card is chosen) -->
  <div id="wizard" style="display:none">
    <button class="btn btn-ghost" style="margin-bottom:1rem" onclick="backToLauncher()">← All object types</button>
    <div class="section-hdr">
      <h2 id="wizTitle">—</h2>
      <p id="wizSub"></p>
    </div>
    <div id="wizBody"></div>
  </div>

</main>
```

- [ ] **Step 2: Add launcher render + card CSS**

Add to the `<style>` block:

```css
.type-grid  { display:flex; flex-wrap:wrap; gap:14px; margin-top:10px; }
.type-card  { width:200px; padding:18px 16px; border:1px solid var(--glass-border); border-radius:12px; background:var(--glass-fill); cursor:pointer; transition:transform .12s, box-shadow .12s; }
.type-card:hover { transform:translateY(-2px); box-shadow:0 6px 20px rgba(0,0,0,.08); }
.type-card.disabled { opacity:.55; cursor:not-allowed; }
.type-card.disabled:hover { transform:none; box-shadow:none; }
.type-icon  { font-size:26px; }
.type-name  { font-size:15px; font-weight:700; margin-top:8px; }
.type-tag   { display:inline-block; margin-top:8px; font-size:10px; font-weight:700; text-transform:uppercase; letter-spacing:.05em; padding:2px 8px; border-radius:20px; }
.type-tag.live   { background:var(--green-light); color:var(--green); }
.type-tag.script { background:var(--surface3); color:var(--muted); }
```

Add to the `<script>` section:

```js
// ── Launcher ────────────────────────────────────────────────────
function renderLauncher() {
  const card = t => `
    <div class="type-card${t.enabled?"":" disabled"}" ${t.enabled?`onclick="openWizard('${t.id}')"`:""}>
      <div class="type-icon">${t.icon}</div>
      <div class="type-name">${t.label}</div>
      <span class="type-tag ${t.backend==="graph"?"live":"script"}">${t.enabled?t.tag:"v2 — coming soon"}</span>
    </div>`;
  const live   = OBJECT_TYPES.filter(t => t.backend==="graph");
  const script = OBJECT_TYPES.filter(t => t.backend==="exchange");
  document.getElementById("launcherLive").innerHTML =
    `<div class="sidebar-lbl">Live in browser · Microsoft Graph</div><div class="type-grid">${live.map(card).join("")}</div>`;
  document.getElementById("launcherScript").innerHTML =
    `<div class="sidebar-lbl">Generates a PowerShell script · Exchange Online</div><div class="type-grid">${script.map(card).join("")}</div>`;
}
function backToLauncher() {
  document.getElementById("wizard").style.display   = "none";
  document.getElementById("launcher").style.display = "block";
}
```

- [ ] **Step 3: Call `renderLauncher()` on sign-in**

In `init()`'s `onSignIn` and in `doSignIn()`, after `ITTools.ui.setUser(acct)`, add: `renderLauncher();`

- [ ] **Step 4: Manual verification**

Deploy to preview (`git push`), sign in. Expected: launcher shows two enabled cards (Security Group, M365 Group) under "Live in browser", and three disabled cards under "Generates a PowerShell script". Disabled cards don't respond to clicks.

- [ ] **Step 5: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin: launcher card grid + wizard shell"
```

---

## Task 4: Wizard shell + router

`openWizard(typeId)` swaps launcher → wizard and renders the step scaffold for that type. v1 only handles `source:"members"` graph types; the shell is built so v2 can add a `permissions` renderer.

**Files:**
- Modify: `tools/group-import/index.html` — add a `// ── Wizard router ──` section.

- [ ] **Step 1: Add wizard state + router**

```js
// ── Wizard ──────────────────────────────────────────────────────
const wiz = { typeId:"", op:"", groupId:"", groupName:"", identifiers:[], csvName:"", dryDone:false, lastLog:[] };

function openWizard(typeId) {
  const t = getType(typeId);
  if (!t || !t.enabled) return;
  Object.assign(wiz, { typeId, op:"", groupId:"", groupName:"", identifiers:[], csvName:"", dryDone:false, lastLog:[] });
  document.getElementById("launcher").style.display = "none";
  document.getElementById("wizard").style.display   = "block";
  document.getElementById("wizTitle").textContent = t.label;
  document.getElementById("wizSub").textContent   = "Add, remove, or export members — live via Microsoft Graph.";
  renderActionStep();
}
```

- [ ] **Step 2: Manual verification**

Deploy, sign in, click **Security Group**. Expected: launcher hides, wizard shows titled "Security Group" with a "← All object types" button that returns to the launcher.

- [ ] **Step 3: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin: wizard router + open/close"
```

---

## Task 5: Action step (Add / Remove / Export)

**Files:**
- Modify: `tools/group-import/index.html` — add `renderActionStep()`.

- [ ] **Step 1: Implement**

```js
function renderActionStep() {
  wiz.op = "";
  document.getElementById("wizBody").innerHTML = `
    <div class="card">
      <div class="card-title">What do you want to do?</div>
      <div class="type-grid">
        <div class="type-card" onclick="chooseOp('add')"><div class="type-name">Add members</div><p class="step-sub">Import a CSV into this group</p></div>
        <div class="type-card" onclick="chooseOp('remove')"><div class="type-name">Remove members</div><p class="step-sub">Remove a CSV of users from this group</p></div>
        <div class="type-card" onclick="chooseOp('export')"><div class="type-name">Export members</div><p class="step-sub">Download current membership as CSV</p></div>
      </div>
    </div>`;
}
function chooseOp(op) {
  wiz.op = op;
  renderTargetStep();
}
```

- [ ] **Step 2: Manual verification**

In the wizard, expect three action cards. Clicking one advances to the Target step (built next; until then it errors — acceptable mid-build).

- [ ] **Step 3: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin: wizard action step"
```

---

## Task 6: Target lookup step (Graph, kind-filtered)

Reuses the current lookup logic (`index.html:480-520`), parameterized by the type's `graphKind` so Security-Group lookups exclude Unified groups and vice-versa. Uses `ITTools.graph.get`.

**Files:**
- Modify: `tools/group-import/index.html` — add `renderTargetStep()` + `wizLookup()`.

- [ ] **Step 1: Implement**

```js
function renderTargetStep() {
  document.getElementById("wizBody").innerHTML = `
    <div class="banner error" id="wErr" style="display:none"></div>
    <div class="card">
      <div class="card-title">Target group</div>
      <div class="field"><label class="field-label">Group name or GUID</label>
        <div class="input-row">
          <input type="text" id="wGroupIn" placeholder="e.g. IT-Security-Team or 00000000-…" onkeydown="if(event.key==='Enter')wizLookup()"/>
          <button class="btn btn-secondary" id="wLookupBtn" onclick="wizLookup()" style="white-space:nowrap">Look up</button>
        </div>
      </div>
      <div class="group-ok" id="wGroupOk"><div class="group-ok-name" id="wGroupOkName"></div><div class="group-ok-id" id="wGroupOkId"></div></div>
    </div>
    <div class="btn-row">
      <button class="btn btn-ghost" onclick="renderActionStep()">← Back</button>
      <button class="btn btn-primary" id="wTargetNext" onclick="afterTarget()" disabled>Continue →</button>
    </div>`;
}

async function wizLookup() {
  const input = document.getElementById("wGroupIn").value.trim();
  const err = document.getElementById("wErr");
  if (!input) { err.textContent = "Enter a group name or GUID."; err.style.display="block"; return; }
  err.style.display = "none";
  const t = getType(wiz.typeId);
  try {
    await ITTools.ui.withButtonSpinner(document.getElementById("wLookupBtn"), async () => {
      let group;
      if (/^[0-9a-f-]{36}$/i.test(input)) {
        group = await ITTools.graph.get(`/groups/${input}`);
      } else {
        const esc = input.replace(/'/g, "''");
        const kindFilter = t.graphKind === "unified"
          ? " and groupTypes/any(c:c eq 'Unified')"
          : " and not(groupTypes/any(c:c eq 'Unified'))";
        const res = await ITTools.graph.get(`/groups?$filter=displayName eq '${encodeURIComponent(esc)}'${encodeURIComponent(kindFilter)}&$count=true&$top=5`);
        if (!res.value?.length) throw new Error(`No ${t.label} found named "${input}".`);
        group = res.value[0];
      }
      wiz.groupId = group.id; wiz.groupName = group.displayName;
      document.getElementById("wGroupOkName").textContent = group.displayName;
      document.getElementById("wGroupOkId").textContent   = group.id;
      document.getElementById("wGroupOk").style.display    = "block";
      document.getElementById("wTargetNext").disabled      = false;
    }, "Looking up…", [document.getElementById("wGroupIn")]);
  } catch(e) {
    err.textContent = ITTools.graph.friendlyError(e); err.style.display = "block"; wiz.groupId = "";
  }
}

function afterTarget() {
  if (!wiz.groupId) return;
  if (wiz.op === "export") { renderRunStep(); } else { renderSourceStep(); }
}
```

Note: `$filter` with `$count=true` requires the `ConsistencyLevel: eventual` header for the `groupTypes` clause. `ITTools.graph.get` must send it — verify in Step 2; if the count/filter errors, fall back to client-side kind filtering (fetch `displayName eq` only, then check `group.groupTypes`).

- [ ] **Step 2: Manual verification**

Security Group → Add → look up your test group by name. Expected: green confirmation with name + GUID, Continue enabled. Look up a known M365 group under the Security Group card → expect "No Security Group found" (kind filter working). If the lookup throws a Graph filter error, apply the client-side fallback noted above and re-verify.

- [ ] **Step 3: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin: wizard target lookup (kind-filtered)"
```

---

## Task 7: Source CSV step (Add / Remove)

Reuses the current CSV upload, column-pick, and normalization logic verbatim (`loadFile`/`parseAndRender`/`renderColPills`/`selectCol`/`getPrimed` at `index.html:397-469`) — keep those functions; this step renders their markup inside `wizBody` and stores the result in `wiz.identifiers`.

**Files:**
- Modify: `tools/group-import/index.html` — add `renderSourceStep()` + `sourceNext()`; keep the existing file/column functions.

- [ ] **Step 1: Implement the source step**

```js
function renderSourceStep() {
  document.getElementById("wizBody").innerHTML = `
    <div class="banner error" id="s1Err" style="display:none"></div>
    <div class="card">
      <div class="card-title">${wiz.op === "add" ? "Members to add" : "Members to remove"} (CSV)</div>
      <div class="file-drop" id="fileDrop" ondragover="dragOver(event)" ondragleave="dragLeave(event)" ondrop="dropFile(event)">
        <div class="file-drop-idle"><div style="font-size:28px;margin-bottom:8px">📄</div>
          <p>Drag &amp; drop your CSV, or <strong onclick="document.getElementById('fileIn').click()">browse</strong></p></div>
        <div class="file-drop-busy"><span class="spinner" style="width:14px;height:14px;border-width:2px"></span> Reading file…</div>
        <input type="file" id="fileIn" accept=".csv" onchange="handleFile(event)"/>
      </div>
      <div class="file-loaded" id="fileLoaded" style="display:none"><span style="font-size:16px">✅</span>
        <span class="file-loaded-name" id="fileName"></span><span class="file-loaded-count" id="fileCount"></span>
        <button class="file-loaded-clear" onclick="clearFile()">✕</button></div>
    </div>
    <div class="card" id="colCard" style="display:none">
      <div class="card-title">Identifier column</div>
      <div class="col-pills" id="colPills"></div>
      <div id="previewWrap" style="display:none;margin-top:12px"><div class="preview-list" id="previewList"></div></div>
    </div>
    <div class="btn-row">
      <button class="btn btn-ghost" onclick="renderTargetStep()">← Back</button>
      <button class="btn btn-primary" id="s1Btn" onclick="sourceNext()" disabled>Continue to Run →</button>
    </div>`;
}
function sourceNext() {
  wiz.identifiers = getPrimed();
  if (!wiz.identifiers.length) { showErr("s1Err","No identifiers found."); return; }
  renderRunStep();
}
```

- [ ] **Step 2: Point `updateS1()` at the wizard button**

The reused `updateS1()` enables `#s1Btn`; confirm it still targets `#s1Btn` (it does). The normalization checkboxes were removed from markup for brevity — update `getPrimed()` to default trim+lowercase+dedup ON when the checkboxes are absent:

```js
function getPrimed() {
  if (!_parsed || !_selCol) return [];
  let vals = _parsed.rows.map(r => r[_selCol]||"").filter(v=>v);
  const on = id => { const el = document.getElementById(id); return el ? el.checked : true; };
  if (on("chkTrim"))  vals = vals.map(v=>v.trim());
  if (on("chkLower")) vals = vals.map(v=>v.toLowerCase());
  if (on("chkDedup")) vals = [...new Set(vals)];
  return vals.filter(v=>v);
}
```

- [ ] **Step 3: Manual verification**

Security Group → Add → target → drop a 3-row CSV. Expect: file-loaded chip, auto-selected identifier column with preview, Continue enables. Export path skips this step (verified in Task 10).

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin: wizard CSV source step"
```

---

## Task 8: Run step scaffold + Add operation

Renders the run summary + Dry Run/Live buttons, and implements **add**. The add loop is the current `runImport` logic (`index.html:544-622`) re-homed to read from `wiz` and dispatch by `wiz.op`.

**Files:**
- Modify: `tools/group-import/index.html` — add `renderRunStep()`, `runOp(isDry)`, and `opAdd(...)`.

- [ ] **Step 1: Run step markup**

```js
function renderRunStep() {
  const isExport = wiz.op === "export";
  document.getElementById("wizBody").innerHTML = `
    <div class="stats-row" id="runStats" style="display:none"></div>
    <div class="card"><div class="card-title">Summary</div>
      <div class="run-summary">
        <div class="run-summary-item"><span>Action</span><span>${wiz.op}</span></div>
        <div class="run-summary-item"><span>Group</span><span style="color:var(--blue-dark)">${wiz.groupName}</span></div>
        ${isExport ? "" : `<div class="run-summary-item"><span>Identifiers</span><span>${wiz.identifiers.length}</span></div>`}
      </div>
    </div>
    <div class="banner error" id="s3Err" style="display:none"></div>
    <div class="card" id="progCard" style="display:none"><div class="progress-wrap">
      <div class="progress-meta"><span id="progLabel">Processing…</span><span id="progPct">0%</span></div>
      <div class="progress-track"><div class="progress-fill" id="progFill"></div></div></div></div>
    <div class="btn-row">
      <button class="btn btn-ghost" onclick="${isExport?"renderTargetStep()":"renderSourceStep()"}">← Back</button>
      ${isExport
        ? `<button class="btn btn-success" onclick="runExport()">⭳ Export members</button>`
        : `<button class="btn btn-secondary" id="btnDry" onclick="runOp(true)">▷ Dry Run</button>
           <button class="btn btn-success" id="btnLive" onclick="runOp(false)" disabled>▶ Live Run</button>`}
    </div>
    <div id="resultsWrap" style="display:none;margin-top:1.5rem">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px">
        <div style="font-size:15px;font-weight:700" id="resTitle"></div>
        <button class="btn btn-ghost" style="padding:6px 12px;font-size:12px" onclick="exportLog()">Export log CSV</button>
      </div>
      <div class="tbl-wrap"><table><thead><tr><th>Status</th><th>Identifier</th><th>Display Name</th><th>Message</th></tr></thead><tbody id="resBody"></tbody></table></div>
    </div>`;
}
```

- [ ] **Step 2: Resolve helper + add operation**

```js
async function resolveUser(ident) {
  try {
    const r = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(ident)}?$select=id,displayName,userPrincipalName,userType`,
      { headers: { Authorization: "Bearer " + (await ITTools.auth.getToken()) } });
    if (r.ok) return await r.json();
    const esc = ident.replace(/'/g,"''");
    const res = await ITTools.graph.get(`/users?$filter=mail eq '${encodeURIComponent(esc)}'&$select=id,displayName,userPrincipalName,userType`);
    return res.value?.length ? res.value[0] : null;
  } catch(_) { return null; }
}

async function loadExistingMembers() {
  const set = {};
  const page = await ITTools.graph.getAll(`/groups/${wiz.groupId}/members?$select=id&$top=999`);
  (page || []).forEach(m => set[m.id] = true);
  return set;
}

async function opAdd(existing, user, isDry, entry) {
  if (existing[user.id]) { entry.action="Skipped"; entry.message="Already a member"; return; }
  if (isDry) { entry.action="WouldAdd"; entry.message="Dry run — no change"; return; }
  try {
    await ITTools.graph.post(`/groups/${wiz.groupId}/members/$ref`, { "@odata.id":`https://graph.microsoft.com/v1.0/directoryObjects/${user.id}` });
    existing[user.id]=true; entry.action="Added"; entry.message="Success";
  } catch(e) { entry.action="Error"; entry.message=ITTools.graph.friendlyError(e); }
}
```

- [ ] **Step 3: Shared run loop (dispatches by op)**

```js
async function runOp(isDry) {
  document.getElementById("s3Err").style.display = "none";
  const btnDry=document.getElementById("btnDry"), btnLive=document.getElementById("btnLive");
  if (btnDry) btnDry.disabled = true; if (btnLive) btnLive.disabled = true;
  document.getElementById("progCard").style.display = "block";
  setProgress(0, wiz.identifiers.length, "Loading existing members…");
  let existing = {};
  try { existing = await loadExistingMembers(); }
  catch(e){ showErr("s3Err","Could not load members: "+ITTools.graph.friendlyError(e)); }
  const log = [];
  for (let i=0;i<wiz.identifiers.length;i++){
    const ident = wiz.identifiers[i];
    setProgress(i+1, wiz.identifiers.length, `(${i+1}/${wiz.identifiers.length}) ${ident}`);
    const entry = { identifier:ident, displayName:"", action:"", message:"" };
    const user = await resolveUser(ident);
    if (!user) { entry.action="NotFound"; entry.message="Could not resolve via UPN or email"; log.push(entry); continue; }
    entry.displayName = user.displayName||"";
    if (wiz.op==="add")    await opAdd(existing, user, isDry, entry);
    if (wiz.op==="remove") await opRemove(existing, user, isDry, entry);
    if (!isDry) await new Promise(r=>setTimeout(r,150));
    log.push(entry);
  }
  wiz.lastLog = log;
  if (isDry && btnLive) { wiz.dryDone=true; btnLive.disabled=false; }
  if (btnDry) btnDry.disabled=false;
  setProgress(wiz.identifiers.length, wiz.identifiers.length, "Complete");
  renderRunStats(log, isDry); renderLog(log, isDry);
}
```

Keep the existing `setProgress`, `renderRunStats`, `sc`, `renderLog`, `filterRes`, `exportLog` functions; update `exportLog` to read `wiz.lastLog` instead of `st.lastLog`.

- [ ] **Step 4: Manual verification (Add)**

Security Group → Add → target test group → 3-row CSV → **Dry Run**. Expect stats showing "Would Add" counts, no membership change (confirm in Entra). Then **Live Run** → members added, re-run dry shows "Already a member". Verify in the Entra portal.

- [ ] **Step 5: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin: run step + Add operation (dry-run + live)"
```

---

## Task 9: Remove operation

Adds `opRemove` using `ITTools.graph.del` against `/groups/{id}/members/{userId}/$ref`.

**Files:**
- Modify: `tools/group-import/index.html` — add `opRemove(...)`.

- [ ] **Step 1: Implement**

```js
async function opRemove(existing, user, isDry, entry) {
  if (!existing[user.id]) { entry.action="Skipped"; entry.message="Not a member"; return; }
  if (isDry) { entry.action="WouldRemove"; entry.message="Dry run — no change"; return; }
  try {
    await ITTools.graph.del(`/groups/${wiz.groupId}/members/${user.id}/$ref`);
    delete existing[user.id]; entry.action="Removed"; entry.message="Success";
  } catch(e) { entry.action="Error"; entry.message=ITTools.graph.friendlyError(e); }
}
```

- [ ] **Step 2: Add the removal pills to `renderRunStats`**

Extend `renderRunStats` counts to include removals:

```js
const added    = log.filter(r=>["Added","WouldAdd"].includes(r.action)).length;
const removed  = log.filter(r=>["Removed","WouldRemove"].includes(r.action)).length;
const skipped  = log.filter(r=>r.action==="Skipped").length;
const notFound = log.filter(r=>r.action==="NotFound").length;
const errors   = log.filter(r=>r.action==="Error").length;
// row.innerHTML: show whichever of added/removed is > 0
```

And add pill classes `pill-removed`/`pill-wouldremove` to the `pillMap` in `renderLog` (reuse existing pill styling; map both to the existing skipped/added colors if no dedicated class exists).

- [ ] **Step 3: Manual verification (Remove)**

Security Group → Remove → target test group → CSV of the 3 users just added → Dry Run (expect "Would Remove"), then Live (expect "Removed"; confirm in Entra). Re-run dry → "Not a member".

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin: Remove operation (dry-run + live)"
```

---

## Task 10: Export operation

Reads full membership via `ITTools.graph.getAll` and downloads a CSV via `ITTools.csv.download`. No dry-run (read-only).

**Files:**
- Modify: `tools/group-import/index.html` — add `runExport()`.

- [ ] **Step 1: Implement**

```js
async function runExport() {
  document.getElementById("s3Err").style.display = "none";
  document.getElementById("progCard").style.display = "block";
  setProgress(0, 1, "Loading members…");
  try {
    const members = await ITTools.graph.getAll(
      `/groups/${wiz.groupId}/members?$select=id,displayName,userPrincipalName,mail,userType&$top=999`);
    setProgress(1, 1, "Complete");
    if (!members.length) { showErr("s3Err","This group has no members."); return; }
    ITTools.csv.download(
      `GroupExport_${wiz.groupName.replace(/[^A-Za-z0-9]/g,"")}_${new Date().toISOString().slice(0,10)}.csv`,
      members.map(m => ({
        DisplayName:m.displayName||"", UserPrincipalName:m.userPrincipalName||"",
        Mail:m.mail||"", UserType:m.userType||"", Id:m.id
      })));
  } catch(e) { showErr("s3Err","Export failed: "+ITTools.graph.friendlyError(e)); }
}
```

- [ ] **Step 2: Manual verification (Export)**

Security Group → Export → target test group → **Export members**. Expect a CSV download with DisplayName/UPN/Mail/UserType/Id rows matching the group's members. Try an M365 Group too.

- [ ] **Step 3: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin: Export members to CSV"
```

---

## Task 11: Scope guard + polish pass

**Files:**
- Modify: `tools/group-import/index.html`

- [ ] **Step 1: Update auth-screen + scopes copy**

Set the auth-screen `<h1>` to "Group Administration" and `<p>` to "Sign in with your M365 admin account to add, remove, or export group members." Confirm `TOOL_SCOPES` still = `["User.Read.All","Group.ReadWrite.All","GroupMember.ReadWrite.All","Directory.Read.All"]` (unchanged; already covers all three ops).

- [ ] **Step 2: Confirm live-run confirm gate on Remove**

In `runOp`, before a non-dry Remove run, require the dry run first (mirror the Add guard): if `!isDry && !wiz.dryDone` show a `confirm()` prompt. (Add already gated via disabled Live button; keep that pattern.)

- [ ] **Step 3: Replace emoji icons with Lucide SVGs** *(added 2026-07-15)*

The launcher cards and action step currently use emoji (🛡️📦📧🔐📬) placeholders. Swap them for inline Lucide SVGs matching the hub's visual design (stroke-based, `viewBox="0 0 24 24"`, `stroke-width="2"`, accent stroke color) — same style as the `config.json` tool icons. Update the `icon` field in `OBJECT_TYPES` and the action-step markup. Proposed mapping:

| Element | Emoji | Lucide |
|---|---|---|
| Security Group | 🛡️ | `shield` |
| Microsoft 365 Group | 📦 | `package` |
| Distribution List | 📧 | `mail` |
| Mail-enabled Security Group | 🔐 | `shield-check` |
| Shared Mailbox | 📬 | `inbox` |
| Add members | — | `user-plus` |
| Remove members | — | `user-minus` |
| Export members | — | `download` |

Part of the hub-wide Lucide adoption already tracked in the design system; keep sizing/stroke consistent with the hub landing cards.

- [ ] **Step 4: Full manual matrix**

| Type | Add | Remove | Export |
|------|-----|--------|--------|
| Security Group | dry→live, verify Entra | dry→live, verify Entra | CSV matches |
| M365 Group | dry→live, verify Entra | dry→live, verify Entra | CSV matches |

Also verify: disabled Exchange cards inert; "← All object types" resets wizard state (start Add, go back, start Export — no stale identifiers).

- [ ] **Step 5: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin: scope guard, remove confirm gate, copy polish"
```

---

## Task 12: Deploy to preview & hand off

- [ ] **Step 1: Push testing → preview**

```bash
git push origin testing
```

- [ ] **Step 2: Verify on preview**

Open `https://jgdev-ch.github.io/it-tools-preview/`, sign in, run the full matrix from Task 11 Step 3 against a disposable test group. Confirm dry-run-before-live on Add and Remove, and that Export produces a correct CSV.

- [ ] **Step 3: Stop — promotion to main is Josh's call**

Do not merge to `main`. Report results and let Josh decide when to promote.

---

## v1 Self-review checklist (done during authoring)

- **Spec coverage:** launcher (Task 3), per-type wizard (Task 4), Security + M365 groups (registry Task 2, kind filter Task 6), add/remove/export (Tasks 8/9/10), Live/Script tags + disabled Exchange cards (Task 3), reuse of current tool (Tasks 6-8), no new scopes (Tasks 1/11). Exchange script-gen + shared mailbox = v2, intentionally excluded.
- **Types consistent:** `wiz` state, `OBJECT_TYPES`/`getType`, op strings (`add`/`remove`/`export`), and function names (`renderActionStep`/`renderTargetStep`/`renderSourceStep`/`renderRunStep`, `opAdd`/`opRemove`/`runExport`) are used consistently across tasks.
- **Known risk flagged inline:** Graph `$filter` + `groupTypes` + `$count` needs `ConsistencyLevel: eventual`; Task 6 carries a client-side fallback if `ITTools.graph.get` doesn't send it.

## Deferred to v2 (separate plan)

Distribution List, Mail-enabled Security Group, and Shared Mailbox wizards; the PowerShell script + self-running `.bat` generator (bundled `.zip`); shared-mailbox permission types (Full Access/Send As/Send on Behalf) with AutoMapping default ON.
