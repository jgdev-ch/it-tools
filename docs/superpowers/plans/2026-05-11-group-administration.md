# Group Administration Tool — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 3-step Group Import wizard with a tabbed Group Administration tool that supports adding and removing Entra ID group members via bulk CSV/paste and live member browser.

**Architecture:** Single HTML file rewrite at `tools/group-import/index.html`. Auth, GSD gating, and shared module usage are preserved from the existing tool. CSS bug fix to `shared/styles.css` removes a transparent file input overlay that was breaking drag-and-drop. New layout uses a green/red pill toggle with two-column tab panels — no sidebar, no step navigation.

**Tech Stack:** Vanilla HTML/CSS/JS, MSAL Browser (popup flow), Microsoft Graph v1.0, `shared/auth.js` (`ITTools.auth`, `ITTools.graph`, `ITTools.ui`, `ITTools.csv`).

---

## File Map

| File | Change |
|------|--------|
| `shared/styles.css` | Fix `.file-drop input[type="file"]` — transparent overlay → `display:none` |
| `config.json` | Rename hub card, update description and permissions |
| `tools/group-import/index.html` | Full rewrite — replace 3-step wizard with tabbed layout |

---

### Task 1: CSS Bug Fix

**Files:**
- Modify: `shared/styles.css:464-466`

- [ ] **Step 1: Open `shared/styles.css` and locate lines 464–466**

Current code:
```css
.file-drop input[type="file"] {
  position: absolute; inset: 0; opacity: 0; cursor: pointer; width: 100%; height: 100%;
}
```

- [ ] **Step 2: Replace with `display:none`**

```css
.file-drop input[type="file"] {
  display: none;
}
```

The `<strong onclick="document.getElementById('fileIn').click()">browse</strong>` link already triggers the input explicitly — that path still works. Drag-and-drop events on the `.file-drop` div now receive events correctly instead of being intercepted by the overlay.

- [ ] **Step 3: Commit**

```bash
git add shared/styles.css
git commit -m "fix: remove transparent file input overlay from .file-drop"
```

---

### Task 2: Hub Card Rename

**Files:**
- Modify: `config.json:18-28`

- [ ] **Step 1: Locate the `group-import` entry in `config.json` (lines 18–28) and replace it**

```json
{
  "id": "group-import",
  "name": "Group Administration",
  "description": "Add and remove members from Entra ID security groups — bulk CSV/paste or live member browser with audit log.",
  "icon": "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='#047857' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2'/><path d='M16 3.128a4 4 0 0 1 0 7.744'/><path d='M22 21v-2a4 4 0 0 0-3-3.87'/><circle cx='9' cy='7' r='4'/></svg>",
  "status": "beta",
  "path": "tools/group-import/",
  "permissions": ["User.Read.All", "Group.ReadWrite.All", "GroupMember.ReadWrite.All", "Directory.Read.All"],
  "accent": "#047857",
  "iconBg": "#d1fae5",
  "category": "daily-ops"
}
```

Note: `status` changed from `"live"` to `"beta"` (Remove Members is new/untested). Permissions expanded to include `User.Read.All` and `Directory.Read.All` for user resolution.

- [ ] **Step 2: Commit**

```bash
git add config.json
git commit -m "feat: rename Group Import → Group Administration in hub card"
```

---

### Task 3: Page Scaffold — HTML, CSS, Auth Shell

**Files:**
- Modify: `tools/group-import/index.html` (full rewrite)

This task writes the complete new file structure: auth screen, app shell, CSS for the new layout. Tab panel JS logic is stubbed — stubs are filled in Tasks 4–8.

- [ ] **Step 1: Replace the entire contents of `tools/group-import/index.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Group Administration — IT Tools</title>
<script src="../../shared/msal-browser.min.js"></script>
<link rel="stylesheet" href="../../shared/styles.css"/>
<style>
  .ga-shell     { max-width:760px; margin:0 auto; padding:1.5rem; }

  /* ── Group picker ── */
  .picker-row   { display:flex; gap:8px; align-items:flex-end; }
  .picker-row .field { flex:1; }
  .group-confirmed { display:none; align-items:center; gap:10px; background:var(--green-light); border:1px solid var(--green-border); border-radius:6px; padding:10px 12px; margin-top:8px; }
  .group-confirmed-name { font-size:13px; font-weight:700; color:var(--green); flex:1; }
  .group-confirmed-id   { font-size:11px; color:var(--muted); font-family:'Cascadia Code','Consolas',monospace; }
  .group-confirmed-change { background:none; border:none; cursor:pointer; color:var(--muted2); font-size:12px; text-decoration:underline; }

  /* ── Mode pill toggle ── */
  .mode-pills   { display:flex; gap:4px; background:var(--surface2); border:1px solid var(--border); border-radius:20px; padding:3px; width:fit-content; }
  .mode-pill    { padding:6px 18px; border-radius:16px; font-size:12px; font-weight:700; cursor:pointer; transition:all .15s; color:var(--muted); user-select:none; }
  .mode-pill--add.active    { background:#16a34a; color:#fff; }
  .mode-pill--remove.active { background:#dc2626; color:#fff; }
  .mode-pill:not(.active):hover { background:var(--surface3); color:var(--text); }

  /* ── Tab card ── */
  .tab-card     { border:1px solid var(--border); border-radius:var(--radius); overflow:hidden; margin-top:8px; }
  .tab-panel    { display:none; padding:16px; }
  .tab-panel.active { display:block; }
  .tab-panel--add    { background:rgba(22,163,74,0.04); }
  .tab-panel--remove { background:rgba(220,38,38,0.03); }
  .tab-cols     { display:grid; grid-template-columns:1fr 1fr; gap:14px; }
  .tab-col-label { font-size:10px; font-weight:700; text-transform:uppercase; letter-spacing:.05em; color:var(--muted); margin-bottom:8px; }

  /* ── Drop zone ── */
  .tab-drop     { border:1.5px dashed var(--border); border-radius:8px; padding:16px; text-align:center; cursor:pointer; transition:border-color .15s,background .15s; min-height:76px; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:5px; }
  .tab-drop--green { border-color:var(--green-border); }
  .tab-drop--green:hover, .tab-drop--green.drag-over { border-color:var(--green); background:var(--green-light); }
  .tab-drop p   { font-size:12px; color:var(--muted); margin:0; }
  .tab-drop strong { color:#16a34a; cursor:pointer; }

  /* ── Resolution chips ── */
  .chip-row   { display:flex; flex-wrap:wrap; gap:5px; margin-top:8px; }
  .chip       { display:inline-flex; align-items:center; gap:4px; padding:2px 8px; border-radius:12px; font-size:11px; font-weight:600; }
  .chip--green { background:var(--green-light); color:var(--green); border:1px solid var(--green-border); }
  .chip--red   { background:var(--red-light);   color:var(--red);   border:1px solid var(--red-border); }
  .chip--amber { background:var(--amber-light); color:var(--amber); border:1px solid var(--amber-border); }
  .chip-dismiss { background:none; border:none; cursor:pointer; color:inherit; font-size:12px; padding:0; margin-left:2px; opacity:.7; }
  .chip-dismiss:hover { opacity:1; }

  /* ── User search results ── */
  .search-result-row { display:flex; align-items:center; gap:8px; padding:6px 8px; border-radius:6px; border:1px solid var(--border); background:var(--surface); margin-bottom:4px; }
  .user-avatar { width:26px; height:26px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:10px; font-weight:700; flex-shrink:0; }
  .user-avatar--add    { background:var(--green-light); color:var(--green); }
  .user-avatar--remove { background:var(--red-light);   color:#dc2626; }
  .user-info   { flex:1; min-width:0; }
  .user-name   { font-size:12px; font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .user-upn    { font-size:10px; color:var(--muted); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }

  /* ── Member list ── */
  .member-list { max-height:200px; overflow-y:auto; border:1px solid var(--border); border-radius:6px; }
  .member-row  { display:flex; align-items:center; gap:8px; padding:6px 10px; border-bottom:1px solid var(--border); font-size:12px; cursor:pointer; transition:background .1s; }
  .member-row:last-child { border-bottom:none; }
  .member-row.selected  { background:rgba(220,38,38,0.07); }
  .member-row input[type="checkbox"] { accent-color:#dc2626; flex-shrink:0; }
  .member-empty { padding:12px; text-align:center; font-size:12px; color:var(--muted); }

  /* ── Action row ── */
  .panel-action { display:flex; justify-content:flex-end; margin-top:12px; padding-top:10px; border-top:1px solid var(--border); }
  .btn-add-action    { background:#16a34a; color:#fff; border:none; padding:7px 18px; border-radius:7px; font-size:12px; font-weight:700; cursor:pointer; }
  .btn-add-action:disabled    { opacity:.45; cursor:default; }
  .btn-remove-action { background:#dc2626; color:#fff; border:none; padding:7px 18px; border-radius:7px; font-size:12px; font-weight:700; cursor:pointer; }
  .btn-remove-action:disabled { opacity:.45; cursor:default; }

  /* ── Log ── */
  .log-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:10px; }
  .log-title  { font-size:15px; font-weight:700; }

  /* ── GSD badge ── */
  .gsd-badge { display:inline-flex; align-items:center; gap:5px; background:var(--blue-light); border:1px solid var(--blue-border); color:var(--blue-dark); border-radius:20px; padding:3px 10px; font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:.04em; }

  @media (max-width:600px) { .tab-cols { grid-template-columns:1fr; } .picker-row { flex-direction:column; } }
</style>
</head>
<body>

<div id="topbar"></div>
<div id="gsdBadgeBar" style="display:none;padding:6px 1.25rem 0;align-items:center;gap:6px">
  <span class="gsd-badge" id="gsdIndicator">
    <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
    GSD Access
  </span>
</div>

<div id="authScreen" class="auth-screen" style="display:none">
  <div class="auth-card">
    <div style="width:44px;height:44px;background:var(--green-light);border-radius:11px;display:flex;align-items:center;justify-content:center;margin:0 auto 1.25rem">
      <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#047857" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><path d="M16 3.128a4 4 0 0 1 0 7.744"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><circle cx="9" cy="7" r="4"/></svg>
    </div>
    <h1>Group Administration</h1>
    <p>Sign in with your M365 admin account to add or remove members from Entra ID security groups.</p>
    <button class="btn-ms" onclick="doSignIn()">
      <svg viewBox="0 0 21 21" width="17" height="17" fill="none">
        <rect x="1"  y="1"  width="9" height="9" fill="#f25022"/>
        <rect x="11" y="1"  width="9" height="9" fill="#7fba00"/>
        <rect x="1"  y="11" width="9" height="9" fill="#00a4ef"/>
        <rect x="11" y="11" width="9" height="9" fill="#ffb900"/>
      </svg>
      Sign in with Microsoft
    </button>
    <div class="auth-error" id="authErr"></div>
    <p class="auth-note">Requires <strong>User.Read.All</strong>, <strong>Group.ReadWrite.All</strong>, <strong>GroupMember.ReadWrite.All</strong>, and <strong>Directory.Read.All</strong>.</p>
    <button class="redirect-toggle" onclick="toggleUri()">Show redirect URI for app registration</button>
    <div class="redirect-box" id="uriBox"></div>
  </div>
</div>

<div id="appScreen" style="display:none">
  <div class="ga-shell">

    <!-- Group picker -->
    <div class="card" style="margin-bottom:1rem">
      <div class="card-title">Target group</div>
      <div class="banner error" id="pickerErr" style="display:none"></div>
      <div class="picker-row">
        <div class="field">
          <label class="field-label">Group name or GUID</label>
          <input type="text" id="groupIn" placeholder="e.g. IT-Security-Team or 00000000-0000-…" onkeydown="if(event.key==='Enter')lookupGroup()"/>
        </div>
        <button class="btn btn-secondary" id="lookupBtn" onclick="lookupGroup()" style="white-space:nowrap;margin-bottom:0">Look up</button>
      </div>
      <div class="group-confirmed" id="groupConfirmed">
        <div style="flex:1">
          <div class="group-confirmed-name" id="groupConfirmedName"></div>
          <div class="group-confirmed-id"   id="groupConfirmedId"></div>
        </div>
        <button class="group-confirmed-change" onclick="changeGroup()">Change</button>
      </div>
      <div class="phase-line" id="lookupPhase"><span>Looking up…</span></div>
    </div>

    <!-- Main card -->
    <div id="mainCard" style="display:none">
      <div style="display:flex;align-items:center;gap:12px;margin-bottom:8px">
        <div class="mode-pills">
          <div class="mode-pill mode-pill--add active" id="pillAdd" onclick="setMode('add')">＋ Add Members</div>
          <div class="mode-pill mode-pill--remove" id="pillRemove" onclick="setMode('remove')">－ Remove Members</div>
        </div>
        <span id="groupNameBadge" style="font-size:12px;color:var(--muted)"></span>
      </div>

      <div class="tab-card">

        <!-- Add panel -->
        <div class="tab-panel tab-panel--add active" id="addPanel">
          <div class="tab-cols">
            <div>
              <div class="tab-col-label">Bulk — CSV or paste</div>
              <div class="tab-drop tab-drop--green" id="addDrop"
                   ondragover="addDragOver(event)" ondragleave="addDragLeave()" ondrop="addDropFile(event)">
                <div style="font-size:22px">📋</div>
                <p>Drag &amp; drop CSV or <strong onclick="document.getElementById('addFileIn').click()">browse</strong></p>
                <p style="font-size:11px">or paste below</p>
                <input type="file" id="addFileIn" accept=".csv" onchange="addHandleFile(event)"/>
              </div>
              <textarea id="addPasteIn" rows="3"
                placeholder="Or paste names / emails here…"
                oninput="addHandlePaste()"
                style="width:100%;margin-top:6px;font-size:12px;padding:7px 9px;border-radius:6px;border:1px solid var(--border);resize:vertical;background:var(--surface2)"></textarea>
              <div id="addChips" class="chip-row"></div>
            </div>
            <div>
              <div class="tab-col-label">Single user search</div>
              <input type="text" id="addSearch" placeholder="Type a name or email…" oninput="addSearchDebounced()" style="font-size:12px"/>
              <div id="addSearchResults" style="margin-top:6px"></div>
            </div>
          </div>
          <div class="panel-action">
            <button class="btn-add-action" id="addBtn" onclick="runAdd()" disabled>Add to Group →</button>
          </div>
        </div>

        <!-- Remove panel -->
        <div class="tab-panel tab-panel--remove" id="removePanel">
          <div class="tab-cols">
            <div>
              <div class="tab-col-label">Bulk remove — paste emails</div>
              <textarea id="removePasteIn" rows="4"
                placeholder="Paste emails or UPNs to remove…"
                oninput="removeHandlePaste()"
                style="width:100%;font-size:12px;padding:7px 9px;border-radius:6px;border:1px solid var(--border);resize:vertical;background:var(--surface2)"></textarea>
              <div id="removeChips" class="chip-row"></div>
            </div>
            <div>
              <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">
                <div class="tab-col-label" style="margin-bottom:0">Members <span id="memberCount"></span></div>
                <button onclick="loadMembers()" id="refreshBtn"
                  style="font-size:10px;background:none;border:1px solid var(--border);border-radius:5px;padding:2px 8px;cursor:pointer;color:var(--muted)">↻ Refresh</button>
              </div>
              <input type="text" id="memberSearch" placeholder="Search members…" oninput="filterMembers()" style="font-size:12px;margin-bottom:6px"/>
              <div class="member-list" id="memberList"><div class="member-empty">Select a group to load members.</div></div>
              <div id="memberLoadMore" style="display:none;margin-top:6px;text-align:center">
                <button onclick="loadMoreMembers()"
                  style="font-size:11px;background:none;border:1px solid var(--border);border-radius:5px;padding:4px 12px;cursor:pointer;color:var(--muted)">Load more…</button>
              </div>
            </div>
          </div>
          <div class="panel-action">
            <button class="btn-remove-action" id="removeBtn" onclick="runRemove()" disabled>Remove from Group →</button>
          </div>
        </div>

      </div>
    </div>

    <!-- Progress bar (shared by Add and Remove batch runs) -->
    <div id="progressCard" style="display:none;margin-top:1rem;padding:10px 14px;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius)">
      <div class="progress-wrap">
        <div class="progress-meta"><span id="progLabel">Processing…</span><span id="progPct">0%</span></div>
        <div class="progress-track"><div class="progress-fill" id="progFill"></div></div>
      </div>
    </div>

    <!-- Results log -->
    <div id="logSection" style="display:none;margin-top:1.5rem">
      <div class="log-header">
        <div class="log-title" id="logTitle"></div>
        <div style="display:flex;gap:8px">
          <input type="search" id="logSearch" placeholder="Filter…"
            style="width:160px;font-size:12px;padding:5px 9px" oninput="filterLog(this.value)"/>
          <button class="btn btn-ghost" style="padding:6px 12px;font-size:12px" onclick="exportLog()">Export CSV</button>
        </div>
      </div>
      <div class="stats-row" id="logStats" style="display:none"></div>
      <div class="tbl-wrap">
        <table>
          <thead><tr><th>Status</th><th>Identifier</th><th>Display Name</th><th>Message</th><th>Time</th></tr></thead>
          <tbody id="logBody"></tbody>
        </table>
      </div>
      <div class="empty-state" id="logEmpty" style="display:none">
        <div class="empty-icon">🔍</div><div class="empty-title">No matching results</div>
      </div>
    </div>

  </div>
</div>

<script src="../../shared/auth.js"></script>
<script>
const GSD_GROUP_ID = "3e1a4757-8189-4908-a611-b6029399e69e";
const TOOL_SCOPES  = ["User.Read.All","Group.ReadWrite.All","GroupMember.ReadWrite.All","Directory.Read.All"];
let _hasGsdAccess  = false;

// ── State ────────────────────────────────────────────────
const st = {
  groupId:  "", groupName: "", mode: "add",
  addResolved:       [],   // [{id, displayName, userPrincipalName, _input}]
  members:           [],   // [{id, displayName, userPrincipalName, mail}]
  membersNext:       null, // pagination nextLink
  _removeBulkResolved: [], // [{id, displayName, userPrincipalName}]
  lastLog:           [],
  lastLogType:       ""    // "add" | "remove"
};

// ── Auth ─────────────────────────────────────────────────
async function checkGsdAccess() {
  try {
    const token = await ITTools.auth.getToken();
    const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects",
      { method:"POST", headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},
        body:JSON.stringify({ids:[GSD_GROUP_ID]}) });
    if (!res.ok) { _hasGsdAccess=false; return; }
    const data = await res.json();
    _hasGsdAccess = (data.value||[]).includes(GSD_GROUP_ID);
  } catch(_) { _hasGsdAccess=false; }
}

async function init() {
  ITTools.theme.init();
  ITTools.ui.renderTopbar({ toolName:"Group Administration", status:"beta", hubRelPath:"../../" });
  ITTools.ui.syncThemeIcon();
  let _sessionFound = false;
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: async acct => {
      _sessionFound = true;
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
      await checkGsdAccess();
      if (_hasGsdAccess) document.getElementById("gsdBadgeBar").style.display = "flex";
    },
    onSignOut: () => {
      _hasGsdAccess = false;
      document.getElementById("gsdBadgeBar").style.display = "none";
      document.getElementById("appScreen").style.display   = "none";
      document.getElementById("authScreen").style.display  = "flex";
      ITTools.ui.clearUser();
    }
  });
  if (!_sessionFound) document.getElementById("authScreen").style.display = "flex";
}

async function doSignIn() {
  try {
    const acct = await ITTools.auth.signIn();
    document.getElementById("authScreen").style.display = "none";
    document.getElementById("appScreen").style.display  = "block";
    ITTools.ui.setUser(acct);
    await checkGsdAccess();
    if (_hasGsdAccess) document.getElementById("gsdBadgeBar").style.display = "flex";
  } catch(e) {
    const el = document.getElementById("authErr");
    el.textContent = ITTools.graph.friendlyError(e); el.style.display = "block";
  }
}

function toggleUri() {
  const b = document.getElementById("uriBox");
  b.textContent = ITTools.auth.redirectUri();
  b.style.display = b.style.display==="none" ? "block" : "none";
}

// ── Mode toggle ──────────────────────────────────────────
function setMode(mode) {
  st.mode = mode;
  document.getElementById("pillAdd").classList.toggle("active", mode==="add");
  document.getElementById("pillRemove").classList.toggle("active", mode==="remove");
  document.getElementById("addPanel").classList.toggle("active", mode==="add");
  document.getElementById("removePanel").classList.toggle("active", mode==="remove");
  if (mode==="remove" && st.groupId && st.members.length===0) loadMembers();
}

// ── Group picker ─────────────────────────────────────────
async function lookupGroup() {
  const input = document.getElementById("groupIn").value.trim();
  if (!input) { showPickerErr("Enter a group name or GUID."); return; }
  clearPickerErr();
  document.getElementById("groupConfirmed").style.display = "none";
  document.getElementById("mainCard").style.display = "none";
  document.getElementById("lookupPhase").classList.add("show");
  try {
    await ITTools.ui.withButtonSpinner(
      document.getElementById("lookupBtn"),
      async () => {
        let group;
        if (/^[0-9a-f-]{36}$/i.test(input)) {
          group = await ITTools.graph.get(`/groups/${input}`);
        } else {
          const escaped = input.replace(/'/g,"''");
          const res = await ITTools.graph.get(`/groups?$filter=displayName eq '${encodeURIComponent(escaped)}'&$count=true&$top=5`);
          if (!res.value?.length) throw new Error(`No group found named "${input}".`);
          group = res.value[0];
        }
        st.groupId = group.id; st.groupName = group.displayName;
        st.members = []; st.membersNext = null;
        document.getElementById("groupConfirmedName").textContent = group.displayName;
        document.getElementById("groupConfirmedId").textContent   = group.id;
        document.getElementById("groupConfirmed").style.display   = "flex";
        document.getElementById("groupNameBadge").textContent     = group.displayName;
        document.getElementById("mainCard").style.display         = "block";
        document.getElementById("memberList").innerHTML = '<div class="member-empty">Select a group to load members.</div>';
        document.getElementById("memberCount").textContent = "";
      },
      "Looking up…",
      [document.getElementById("groupIn")]
    );
  } catch(e) {
    showPickerErr(ITTools.graph.friendlyError(e)); st.groupId="";
  } finally {
    document.getElementById("lookupPhase").classList.remove("show");
  }
}

function changeGroup() {
  st.groupId=""; st.groupName="";
  document.getElementById("groupConfirmed").style.display = "none";
  document.getElementById("mainCard").style.display = "none";
  document.getElementById("groupIn").value = "";
  document.getElementById("groupIn").focus();
}

function showPickerErr(msg) { const el=document.getElementById("pickerErr"); el.textContent=msg; el.style.display="block"; }
function clearPickerErr()   { document.getElementById("pickerErr").style.display="none"; }

// ── Add tab — drag/drop wiring ───────────────────────────
function addDragOver(e)  { e.preventDefault(); document.getElementById("addDrop").classList.add("drag-over"); }
function addDragLeave()  { document.getElementById("addDrop").classList.remove("drag-over"); }
function addDropFile(e)  { e.preventDefault(); addDragLeave(); const f=e.dataTransfer.files[0]; if(f) addLoadFile(f); }
function addHandleFile(e){ addLoadFile(e.target.files[0]); }

function addLoadFile(file) {
  if (!file || !file.name.toLowerCase().endsWith(".csv")) return;
  const reader = new FileReader();
  reader.onload = ev => addResolveBulk(ev.target.result);
  reader.readAsText(file);
}

// ── Stubs (filled in Tasks 4–8) ──────────────────────────
function addHandlePaste()    { /* Task 4 */ }
function addResolveBulk(text){ /* Task 4 */ }
function addSearchDebounced(){ /* Task 5 */ }
function runAdd()            { /* Task 6 */ }
function loadMembers()       { /* Task 7 */ }
function loadMoreMembers()   { /* Task 7 */ }
function filterMembers()     { /* Task 7 */ }
function updateRemoveBtn()   { document.getElementById("removeBtn").disabled = true; /* Task 7 */ }
function removeHandlePaste() { /* Task 8 */ }
function runRemove()         { /* Task 8 */ }

// ── Helpers ──────────────────────────────────────────────
function initials(name) {
  if (!name) return "?";
  const p = name.trim().split(/\s+/);
  return (p[0][0]+(p[1]?p[1][0]:"")).toUpperCase();
}
function esc(s) { return (s||"").replace(/'/g,"\\'").replace(/"/g,"&quot;"); }
function logEntry(identifier, displayName, action, message) {
  return { timestamp:new Date().toISOString().slice(0,19).replace("T"," "), identifier, displayName, action, message };
}

function setProgress(curr, total, label) {
  const pct = total > 0 ? Math.round((curr/total)*100) : 0;
  document.getElementById("progressCard").style.display = "block";
  document.getElementById("progFill").style.width       = pct+"%";
  document.getElementById("progPct").textContent        = pct+"%";
  document.getElementById("progLabel").textContent      = label || `Processing ${curr} / ${total}`;
}
function hideProgress() {
  document.getElementById("progressCard").style.display = "none";
  document.getElementById("progFill").style.width = "0%";
}

// ── Results log ──────────────────────────────────────────
function renderLog(log, type) {
  st.lastLog=log; st.lastLogType=type;
  const pillMap = { Added:"pill-added", Removed:"pill-added", Skipped:"pill-skipped", NotMember:"pill-skipped", Error:"pill-error", NotFound:"pill-notfound" };
  document.getElementById("logTitle").textContent = type==="add" ? "Add results" : "Remove results";
  document.getElementById("logBody").innerHTML = log.map(r =>
    `<tr data-search="${(r.identifier+" "+r.displayName).toLowerCase()}">
      <td><span class="status-pill ${pillMap[r.action]||""}">${r.action}</span></td>
      <td class="mono text-xs">${r.identifier}</td>
      <td>${r.displayName||"—"}</td>
      <td class="muted text-xs">${r.message}</td>
      <td class="muted text-xs" style="white-space:nowrap">${r.timestamp}</td>
    </tr>`
  ).join("");
  const added   = log.filter(r=>r.action==="Added"||r.action==="Removed").length;
  const skipped = log.filter(r=>r.action==="Skipped"||r.action==="NotMember").length;
  const notFound= log.filter(r=>r.action==="NotFound").length;
  const errors  = log.filter(r=>r.action==="Error").length;
  const stats   = document.getElementById("logStats");
  stats.style.display = "flex";
  stats.innerHTML =
    sc("blue","Total",log.length) +
    sc("green", type==="add"?"Added":"Removed", added) +
    (skipped>0?sc("amber","Skipped",skipped):"") +
    (notFound>0?sc("red","Not Found",notFound):"") +
    (errors>0?sc("red","Errors",errors):"");
  document.getElementById("logSection").style.display = "block";
  document.getElementById("logEmpty").style.display   = "none";
}
function sc(c,l,v) { return `<div class="stat ${c}"><div class="stat-label">${l}</div><div class="stat-value">${v}</div></div>`; }

function filterLog(q) {
  q=q.toLowerCase(); let vis=0;
  document.querySelectorAll("#logBody tr").forEach(tr=>{
    const show=tr.dataset.search.includes(q); tr.style.display=show?"":"none"; if(show)vis++;
  });
  document.getElementById("logEmpty").style.display = vis===0?"block":"none";
}

function exportLog() {
  if (!st.lastLog.length) return;
  const prefix = st.lastLogType==="add" ? "GroupAdmin_Add" : "GroupAdmin_Remove";
  ITTools.csv.download(prefix+"_"+new Date().toISOString().slice(0,10)+".csv",
    st.lastLog.map(r=>({Status:r.action,Identifier:r.identifier,"Display Name":r.displayName,Message:r.message,Timestamp:r.timestamp}))
  );
}

init();
</script>
</body>
</html>
```

- [ ] **Step 2: Verify the auth shell works**

Open `tools/group-import/index.html` in a browser. Confirm:
- Auth screen shows "Group Administration" title
- Sign in works — app screen appears with group picker
- Entering a valid group name and clicking "Look up" shows the green confirmed banner and reveals the tab card
- Green pill / red pill toggle switches the visible panel (green tint vs red tint)
- Clicking "Change" clears the group and hides the main card
- GSD badge bar shows for users with GSD Access

- [ ] **Step 3: Commit**

```bash
git add tools/group-import/index.html
git commit -m "feat: scaffold Group Administration layout — auth, picker, tab shell"
```

---

### Task 4: Add Tab — Bulk Resolution

**Files:**
- Modify: `tools/group-import/index.html` — replace `addHandlePaste` and `addResolveBulk` stubs

- [ ] **Step 1: Find this block in the script**

```javascript
function addHandlePaste()    { /* Task 4 */ }
function addResolveBulk(text){ /* Task 4 */ }
```

- [ ] **Step 2: Replace with**

```javascript
function addHandlePaste() {
  const text = document.getElementById("addPasteIn").value;
  if (!text.trim()) { document.getElementById("addChips").innerHTML=""; updateAddBtn(); return; }
  addResolveBulk(text);
}

async function addResolveBulk(text) {
  let lines;
  if (text.includes(",") && !text.includes("\n")) {
    try {
      const parsed = ITTools.csv.parse(text);
      const col = ITTools.csv.detectEmailColumn(parsed.headers, parsed.rows);
      lines = parsed.rows.map(r=>r[col]||"").filter(v=>v);
    } catch(_) {
      lines = text.split(/[\n,]+/).map(l=>l.trim()).filter(Boolean);
    }
  } else {
    lines = text.split(/\n/).map(l=>l.trim()).filter(Boolean);
  }
  lines = [...new Set(lines.map(l=>l.toLowerCase()))];
  if (!lines.length) { document.getElementById("addChips").innerHTML=""; updateAddBtn(); return; }

  st.addResolved = [];
  const chips = document.getElementById("addChips");
  chips.innerHTML = '<span style="font-size:11px;color:var(--muted)">Resolving…</span>';

  const results = [];
  for (const ident of lines) {
    let user = null;
    try {
      const r = await fetch(
        `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(ident)}?$select=id,displayName,userPrincipalName`,
        { headers:{ Authorization:"Bearer "+(await ITTools.auth.getToken()) } });
      if (r.ok) user = await r.json();
    } catch(_) {}
    if (!user) {
      try {
        const escaped = ident.replace(/'/g,"''");
        const r = await ITTools.graph.get(`/users?$filter=mail eq '${encodeURIComponent(escaped)}'&$select=id,displayName,userPrincipalName`);
        if (r.value?.length) user = r.value[0];
      } catch(_) {}
    }
    results.push({ ident, user });
    if (user) st.addResolved.push({...user, _input:ident});
  }

  chips.innerHTML = results.map(({ident, user}) => user
    ? `<span class="chip chip--green">✓ ${user.displayName}<button class="chip-dismiss" onclick="dismissAddChip('${user.id}')">✕</button></span>`
    : `<span class="chip chip--red">✗ ${ident}</span>`
  ).join("");
  updateAddBtn();
}

function dismissAddChip(userId) {
  st.addResolved = st.addResolved.filter(u=>u.id!==userId);
  document.querySelector(`.chip--green button[onclick="dismissAddChip('${userId}')"]`)?.closest(".chip")?.remove();
  updateAddBtn();
}

function updateAddBtn() {
  document.getElementById("addBtn").disabled = st.addResolved.length === 0;
}
```

- [ ] **Step 3: Verify**

Pick a group, switch to Add tab. Paste a valid UPN or email — a green chip appears with a ✕. Paste an invalid string — a red chip appears. Click ✕ on a green chip — it disappears. Drop a CSV that has an email column — it resolves the rows automatically. The "Add to Group →" button enables only when at least one green chip is present.

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/index.html
git commit -m "feat: add bulk paste/CSV resolution with chips to Add Members tab"
```

---

### Task 5: Add Tab — Single User Search

**Files:**
- Modify: `tools/group-import/index.html` — replace `addSearchDebounced` stub

- [ ] **Step 1: Find this line in the script**

```javascript
function addSearchDebounced(){ /* Task 5 */ }
```

- [ ] **Step 2: Replace with**

```javascript
let _addSearchTimer = null;
function addSearchDebounced() {
  clearTimeout(_addSearchTimer);
  _addSearchTimer = setTimeout(addSearchUsers, 300);
}

async function addSearchUsers() {
  const q = document.getElementById("addSearch").value.trim();
  const container = document.getElementById("addSearchResults");
  if (q.length < 2) { container.innerHTML=""; return; }
  container.innerHTML = '<span style="font-size:11px;color:var(--muted)">Searching…</span>';
  try {
    const token = await ITTools.auth.getToken();
    const res = await fetch(
      `https://graph.microsoft.com/v1.0/users?$search="displayName:${encodeURIComponent(q)}"&$select=id,displayName,userPrincipalName,mail&$top=8`,
      { headers:{ Authorization:"Bearer "+token, ConsistencyLevel:"eventual" } }
    );
    if (!res.ok) throw new Error(res.status);
    const data = await res.json();
    const users = data.value||[];
    if (!users.length) { container.innerHTML='<span style="font-size:11px;color:var(--muted)">No results.</span>'; return; }
    container.innerHTML = users.map(u =>
      `<div class="search-result-row" id="sr-${u.id}">
        <div class="user-avatar user-avatar--add">${initials(u.displayName)}</div>
        <div class="user-info">
          <div class="user-name">${u.displayName}</div>
          <div class="user-upn">${u.userPrincipalName||u.mail||""}</div>
        </div>
        <button onclick="addSingleUser('${u.id}','${esc(u.displayName)}','${esc(u.userPrincipalName||u.mail||"")}',this)"
          style="font-size:11px;padding:4px 10px;border-radius:5px;background:#16a34a;color:#fff;border:none;cursor:pointer;font-weight:600;white-space:nowrap">
          Add
        </button>
      </div>`
    ).join("");
  } catch(e) {
    container.innerHTML = `<span style="font-size:11px;color:var(--red)">${ITTools.graph.friendlyError(e)}</span>`;
  }
}

async function addSingleUser(userId, displayName, upn, btn) {
  if (!st.groupId) return;
  btn.disabled=true; btn.textContent="…";
  const entry = logEntry(upn||displayName, displayName, "", "");
  try {
    await ITTools.graph.post(`/groups/${st.groupId}/members/$ref`,
      {"@odata.id":`https://graph.microsoft.com/v1.0/directoryObjects/${userId}`});
    entry.action="Added"; entry.message="Success";
    btn.textContent="✓"; btn.style.background="var(--green)";
  } catch(e) {
    entry.action="Error"; entry.message=ITTools.graph.friendlyError(e);
    btn.textContent="✗"; btn.style.background="var(--red)"; btn.disabled=false;
  }
  st.lastLog=[...st.lastLog, entry]; st.lastLogType="add";
  renderLog(st.lastLog, "add");
}
```

- [ ] **Step 3: Verify**

Pick a group, stay on Add tab. Type 2+ characters in the search field — matching users appear within ~300 ms. Click "Add" next to a user — button shows "…" then "✓", the results log appears at the bottom with an "Added" entry. Subsequent inline adds append rows to the existing log. Typing a non-existent name returns "No results."

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/index.html
git commit -m "feat: add single-user search with inline add to Add Members tab"
```

---

### Task 6: Add Tab — "Add to Group" Batch Action

**Files:**
- Modify: `tools/group-import/index.html` — replace `runAdd` stub

- [ ] **Step 1: Find this line in the script**

```javascript
function runAdd()            { /* Task 6 */ }
```

- [ ] **Step 2: Replace with**

```javascript
async function runAdd() {
  if (!st.groupId || !st.addResolved.length) return;
  const btn = document.getElementById("addBtn");
  btn.disabled=true; btn.textContent="Adding…";
  const total = st.addResolved.length;

  setProgress(0, total, "Checking membership…");
  const existing = {};
  try {
    let next = `/groups/${st.groupId}/members?$select=id&$top=999`;
    while (next) {
      const page = await ITTools.graph.get(next.startsWith("http") ? next : "https://graph.microsoft.com/v1.0"+next);
      (page.value||[]).forEach(m=>existing[m.id]=true);
      next = page["@odata.nextLink"]||null;
    }
  } catch(_) {}

  const log = [];
  for (let i=0; i<total; i++) {
    const user = st.addResolved[i];
    setProgress(i+1, total, `(${i+1}/${total}) ${user.displayName||user._input}`);
    const entry = logEntry(user._input||user.userPrincipalName, user.displayName, "", "");
    if (existing[user.id]) {
      entry.action="Skipped"; entry.message="Already a member";
    } else {
      try {
        await ITTools.graph.post(`/groups/${st.groupId}/members/$ref`,
          {"@odata.id":`https://graph.microsoft.com/v1.0/directoryObjects/${user.id}`});
        existing[user.id]=true; entry.action="Added"; entry.message="Success";
      } catch(e) { entry.action="Error"; entry.message=ITTools.graph.friendlyError(e); }
      await new Promise(r=>setTimeout(r,150));
    }
    log.push(entry);
  }

  hideProgress();
  btn.textContent="Add to Group →";
  btn.disabled = st.addResolved.length === 0;
  renderLog(log, "add");
}
```

- [ ] **Step 3: Verify**

Pick a group, paste 2–3 valid emails. Wait for green chips. Click "Add to Group →". Button shows "Adding…", then the results table appears with Added/Skipped statuses. Re-run with the same users — all show "Skipped — Already a member". Export CSV produces `GroupAdmin_Add_YYYY-MM-DD.csv`.

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/index.html
git commit -m "feat: implement Add to Group batch action with membership pre-check"
```

---

### Task 7: Remove Tab — Live Member List

**Files:**
- Modify: `tools/group-import/index.html` — replace `loadMembers`, `loadMoreMembers`, `filterMembers`, `updateRemoveBtn` stubs

- [ ] **Step 1: Find this block in the script**

```javascript
function loadMembers()       { /* Task 7 */ }
function loadMoreMembers()   { /* Task 7 */ }
function filterMembers()     { /* Task 7 */ }
function updateRemoveBtn()   { document.getElementById("removeBtn").disabled = true; /* Task 7 */ }
```

- [ ] **Step 2: Replace with**

```javascript
async function loadMembers() {
  if (!st.groupId) return;
  st.members=[]; st.membersNext=null;
  document.getElementById("memberList").innerHTML = '<div class="member-empty">Loading…</div>';
  document.getElementById("memberCount").textContent = "";
  document.getElementById("memberLoadMore").style.display = "none";
  await fetchMemberPage(`/groups/${st.groupId}/members?$select=id,displayName,userPrincipalName,mail&$top=100`);
}

async function loadMoreMembers() {
  if (!st.membersNext) return;
  await fetchMemberPage(st.membersNext);
}

async function fetchMemberPage(url) {
  try {
    const full = url.startsWith("http") ? url : "https://graph.microsoft.com/v1.0"+url;
    const page = await ITTools.graph.get(full);
    st.members = [...st.members, ...(page.value||[])];
    st.membersNext = page["@odata.nextLink"]||null;
    renderMemberList(st.members);
    document.getElementById("memberLoadMore").style.display = st.membersNext ? "block" : "none";
  } catch(e) {
    document.getElementById("memberList").innerHTML =
      `<div class="member-empty" style="color:var(--red)">${ITTools.graph.friendlyError(e)}</div>`;
  }
}

function renderMemberList(members) {
  const q = document.getElementById("memberSearch").value.toLowerCase();
  const filtered = q
    ? members.filter(m=>(m.displayName||"").toLowerCase().includes(q)||(m.userPrincipalName||"").toLowerCase().includes(q))
    : members;
  document.getElementById("memberCount").textContent = "("+members.length+(st.membersNext?"+":"")+")";
  if (!filtered.length) {
    document.getElementById("memberList").innerHTML = '<div class="member-empty">No members match.</div>';
    updateRemoveBtn(); return;
  }
  document.getElementById("memberList").innerHTML = filtered.map(m =>
    `<div class="member-row" id="mrow-${m.id}" onclick="toggleMemberCheck('${m.id}')">
      <input type="checkbox" id="mchk-${m.id}" onclick="event.stopPropagation();toggleMemberCheck('${m.id}')">
      <div class="user-avatar user-avatar--remove">${initials(m.displayName)}</div>
      <div class="user-info">
        <div class="user-name">${m.displayName||"—"}</div>
        <div class="user-upn">${m.userPrincipalName||m.mail||""}</div>
      </div>
    </div>`
  ).join("");
  updateRemoveBtn();
}

function toggleMemberCheck(id) {
  const chk=document.getElementById("mchk-"+id);
  const row=document.getElementById("mrow-"+id);
  if (!chk||!row) return;
  chk.checked=!chk.checked;
  row.classList.toggle("selected", chk.checked);
  updateRemoveBtn();
}

function filterMembers() { renderMemberList(st.members); }

function getCheckedMemberIds() {
  return st.members.filter(m=>document.getElementById("mchk-"+m.id)?.checked);
}

function updateRemoveBtn() {
  const fromList = getCheckedMemberIds().length;
  const fromBulk = (st._removeBulkResolved||[]).length;
  document.getElementById("removeBtn").disabled = (fromList+fromBulk) === 0;
}
```

- [ ] **Step 3: Verify**

Pick a group, switch to Remove tab. The member list loads automatically (triggered by `setMode` calling `loadMembers` on first switch). Members appear as rows with checkboxes and initials avatars. Click a row — it highlights red and the "Remove from Group →" button enables. Click again — deselects. Type in the search field — rows filter. If the group has >100 members, "Load more…" appears.

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/index.html
git commit -m "feat: implement live member list with checkboxes on Remove Members tab"
```

---

### Task 8: Remove Tab — Bulk Paste + Remove Action

**Files:**
- Modify: `tools/group-import/index.html` — replace `removeHandlePaste` and `runRemove` stubs

- [ ] **Step 1: Find this block in the script**

```javascript
function removeHandlePaste() { /* Task 8 */ }
function runRemove()         { /* Task 8 */ }
```

- [ ] **Step 2: Replace with**

```javascript
async function removeHandlePaste() {
  const text = document.getElementById("removePasteIn").value;
  if (!text.trim()) {
    document.getElementById("removeChips").innerHTML="";
    st._removeBulkResolved=[];
    updateRemoveBtn(); return;
  }
  const lines = [...new Set(text.split(/\n/).map(l=>l.trim()).filter(Boolean).map(l=>l.toLowerCase()))];
  const chips = document.getElementById("removeChips");
  chips.innerHTML = '<span style="font-size:11px;color:var(--muted)">Resolving…</span>';

  const results = [];
  for (const ident of lines) {
    let user = null;
    try {
      const r = await fetch(
        `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(ident)}?$select=id,displayName,userPrincipalName`,
        { headers:{ Authorization:"Bearer "+(await ITTools.auth.getToken()) } });
      if (r.ok) user = await r.json();
    } catch(_) {}
    if (!user) {
      try {
        const escaped = ident.replace(/'/g,"''");
        const r = await ITTools.graph.get(`/users?$filter=mail eq '${encodeURIComponent(escaped)}'&$select=id,displayName,userPrincipalName`);
        if (r.value?.length) user = r.value[0];
      } catch(_) {}
    }
    const isMember = user && st.members.some(m=>m.id===user.id);
    results.push({ ident, user, isMember });
  }

  chips.innerHTML = results.map(({ident, user, isMember}) => {
    if (!user)     return `<span class="chip chip--red">✗ ${ident}</span>`;
    if (!isMember) return `<span class="chip chip--amber">~ ${user.displayName} (not a member)</span>`;
    return `<span class="chip chip--green">✓ ${user.displayName}</span>`;
  }).join("");

  st._removeBulkResolved = results.filter(r=>r.user&&r.isMember).map(r=>r.user);
  updateRemoveBtn();
}

async function runRemove() {
  if (!st.groupId) return;
  const fromList = getCheckedMemberIds();
  const fromBulk = st._removeBulkResolved||[];
  const seen = new Set();
  const targets = [...fromList, ...fromBulk].filter(u=>{ if(seen.has(u.id))return false; seen.add(u.id); return true; });
  if (!targets.length) return;

  const btn = document.getElementById("removeBtn");
  btn.disabled=true; btn.textContent="Removing…";
  const total = targets.length;

  const log = [];
  for (let i=0; i<total; i++) {
    const user = targets[i];
    setProgress(i+1, total, `(${i+1}/${total}) ${user.displayName||user.userPrincipalName}`);
    const entry = logEntry(user.userPrincipalName||user.mail||user.id, user.displayName, "", "");
    try {
      const token = await ITTools.auth.getToken();
      const res = await fetch(
        `https://graph.microsoft.com/v1.0/groups/${st.groupId}/members/${user.id}/$ref`,
        { method:"DELETE", headers:{ Authorization:"Bearer "+token } });
      if (res.ok||res.status===204) {
        entry.action="Removed"; entry.message="Success";
        st.members = st.members.filter(m=>m.id!==user.id);
      } else {
        const body = await res.json().catch(()=>({}));
        entry.action="Error"; entry.message=body?.error?.message||"HTTP "+res.status;
      }
    } catch(e) { entry.action="Error"; entry.message=ITTools.graph.friendlyError(e); }
    await new Promise(r=>setTimeout(r,150));
    log.push(entry);
  }

  hideProgress();
  renderMemberList(st.members);
  st._removeBulkResolved=[];
  document.getElementById("removePasteIn").value="";
  document.getElementById("removeChips").innerHTML="";
  btn.textContent="Remove from Group →";
  updateRemoveBtn();
  renderLog(log, "remove");
}
```

- [ ] **Step 3: Verify**

Switch to Remove tab with a group selected. Paste a valid email that's a group member — green chip. Paste a valid email that's NOT a member — amber chip. Paste an unresolvable string — red chip. Click "Remove from Group →" — button shows "Removing…", results log shows Removed status, user disappears from the member list.

Also verify the live list path: check a member from the list, click "Remove from Group →" — that member disappears from the list and the log shows Removed.

Export CSV produces `GroupAdmin_Remove_YYYY-MM-DD.csv`.

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/index.html
git commit -m "feat: implement Remove Members bulk paste and Remove from Group action"
```

---

### Task 9: Smoke Test and Cleanup

**Files:**
- Modify: `tools/group-import/index.html` — confirm no stubs remain

- [ ] **Step 1: Search for leftover stubs**

Open `tools/group-import/index.html` and search for `/* Task`. All stubs should be replaced. If any remain, they indicate a missed implementation step — do not proceed until resolved.

- [ ] **Step 2: Full end-to-end smoke test on preview site**

Deploy `testing` branch to the preview site, then run through:

1. Hub shows "Group Administration" card in Daily Operations with Beta ribbon
2. Open tool → "Group Administration" auth screen and description
3. Sign in → group picker loads
4. Look up a group by name → green confirmed banner, main card appears
5. **Add tab** — paste 2 emails → green chips appear → "Add to Group →" → Added/Skipped log
6. **Add tab** — type name in search → results list → click Add → log entry appended
7. **Remove tab** — switch pill → member list loads → check 1 member → "Remove from Group →" → Removed in log, member gone from list
8. **Remove tab** — paste an email → green chip → "Remove from Group →" → Removed in log
9. Export CSV from Add results → `GroupAdmin_Add_YYYY-MM-DD.csv`
10. Export CSV from Remove results → `GroupAdmin_Remove_YYYY-MM-DD.csv`
11. Click "Change" group → picker resets, main card hides
12. Sign out → auth screen shown

- [ ] **Step 3: Commit**

```bash
git add tools/group-import/index.html
git commit -m "chore: smoke test and stub cleanup for Group Administration tool"
```
