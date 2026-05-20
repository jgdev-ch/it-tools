# User Creation Tool — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 4-step hub web tool that creates M365 user accounts via Graph API and generates a ready-to-run ZIP (Exchange PS script + bat launcher + credentials CSV) for the Exchange-only steps that Graph can't reach.

**Architecture:** Single `tools/user-creation/index.html` following the hub's established sidebar-wizard pattern (auth screen → 4-step sidebar → main content). All Graph work runs in the browser; Exchange work is deferred to the generated PowerShell script. JSZip is vendored alongside the tool for client-side ZIP generation.

**Tech Stack:** JavaScript (ES2020 async/await), Microsoft Graph REST API via `ITTools.graph`, MSAL via `ITTools.auth`, `ITTools.csv.parse()` for CSV parsing, JSZip 3.10.1 for ZIP generation, `crypto.getRandomValues()` for password generation.

**Spec:** `docs/superpowers/specs/2026-05-19-user-creation-design.md`

---

### Task 1: Scaffold — directory, JSZip, config entry, HTML shell

**Files:**
- Create: `tools/user-creation/index.html`
- Create: `tools/user-creation/jszip.min.js`
- Modify: `config.json`

- [ ] **Step 1: Create directory and vendor JSZip**

```bash
mkdir tools/user-creation
curl -L "https://cdn.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js" -o tools/user-creation/jszip.min.js
```

Verify: `ls -lh tools/user-creation/jszip.min.js` — should show ~100 KB file.

- [ ] **Step 2: Add hub card to config.json**

Open `config.json`. In the `tools` array, add after the last entry:

```json
{
  "id": "user-creation",
  "name": "User Creation",
  "description": "Create new employee accounts from a CSV — assigns licenses, security groups, and generates a ready-to-run Exchange setup script.",
  "icon": "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='#7c3aed' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2'/><circle cx='9' cy='7' r='4'/><line x1='19' y1='8' x2='19' y2='14'/><line x1='22' y1='11' x2='16' y2='11'/></svg>",
  "status": "beta",
  "path": "tools/user-creation/",
  "permissions": ["User.ReadWrite.All", "Group.ReadWrite.All", "Directory.Read.All"],
  "accent": "#7c3aed",
  "iconBg": "#2e1065",
  "category": "daily-ops"
}
```

- [ ] **Step 3: Create index.html with auth screen, app shell, sidebar, and 4 empty step sections**

Create `tools/user-creation/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>User Creation — IT Tools Hub</title>
  <script src="../../shared/msal-browser.min.js"></script>
  <script src="../../shared/auth.js"></script>
  <script src="jszip.min.js"></script>
  <link rel="stylesheet" href="../../shared/styles.css"/>
  <style>
    /* ── Mode toggle ── */
    .mode-toggle { display:flex; background:var(--surface); border:1px solid var(--border); border-radius:8px; overflow:hidden; }
    .mode-btn    { padding:6px 16px; font-size:12px; font-weight:600; cursor:pointer; color:var(--muted); border:none; background:transparent; }
    .mode-btn.active { background:var(--blue); color:#fff; }

    /* ── Validation summary bar ── */
    .val-bar  { display:flex; gap:10px; align-items:center; margin-bottom:12px; }
    .val-pill { display:flex; align-items:center; gap:5px; font-size:12px; padding:4px 10px; border-radius:20px; font-weight:600; }
    .val-pill .dot { width:6px; height:6px; border-radius:50%; background:currentColor; }
    .val-pill.ok   { background:var(--green-light); color:var(--green); }
    .val-pill.warn { background:#451a03; color:#fbbf24; }
    .val-pill.err  { background:#450a0a; color:#fca5a5; }

    /* ── Bulk settings bar ── */
    .bulk-bar           { border:1px solid var(--border); border-radius:10px; margin-bottom:14px; overflow:hidden; }
    .bulk-header        { display:flex; align-items:center; gap:10px; padding:10px 14px; background:var(--surface); cursor:pointer; user-select:none; }
    .bulk-header:hover  { filter:brightness(1.1); }
    .bulk-title         { font-size:12px; font-weight:700; color:var(--text); }
    .bulk-subtitle      { font-size:11px; color:var(--muted); margin-left:auto; }
    .bulk-body          { padding:16px; border-top:1px solid var(--border); display:flex; align-items:flex-end; gap:24px; flex-wrap:wrap; }
    .bulk-field         { display:flex; flex-direction:column; gap:6px; }
    .bulk-field label   { font-size:11px; font-weight:700; color:var(--muted); text-transform:uppercase; letter-spacing:.06em; }
    .bulk-select        { background:var(--surface); border:1px solid var(--border); color:var(--text); font-size:13px; padding:7px 10px; border-radius:7px; cursor:pointer; min-width:170px; }
    .bulk-toggle-row    { display:flex; align-items:center; gap:8px; font-size:13px; color:var(--text-sub); padding:4px 0; }
    .bulk-note          { font-size:11px; color:var(--muted); margin-top:4px; width:100%; }

    /* ── Toggle switch ── */
    .tog           { display:inline-flex; align-items:center; cursor:pointer; }
    .tog input     { display:none; }
    .tog .track    { width:32px; height:18px; background:var(--border); border-radius:9px; position:relative; transition:background .15s; }
    .tog input:checked + .track { background:var(--blue); }
    .tog .track::after { content:''; position:absolute; left:3px; top:3px; width:12px; height:12px; background:#fff; border-radius:50%; transition:left .15s; }
    .tog input:checked + .track::after { left:17px; }

    /* ── Review table ── */
    .review-tbl th { font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:.06em; color:var(--muted); padding:9px 12px; white-space:nowrap; }
    .review-tbl td { padding:8px 12px; vertical-align:middle; }
    .review-tbl tr.row-warn { background:#451a0311; }
    .review-tbl tr.row-err  { background:#450a0a22; }
    .inline-sel  { background:var(--surface); border:1px solid var(--border); color:var(--text); font-size:12px; padding:3px 6px; border-radius:5px; cursor:pointer; }
    .upn-cell    { font-family:monospace; font-size:11px; color:var(--blue-text); }

    /* ── Status pills ── */
    .spill        { display:inline-flex; align-items:center; gap:4px; font-size:11px; padding:3px 8px; border-radius:12px; font-weight:600; white-space:nowrap; }
    .spill.ok     { background:var(--green-light); color:var(--green); }
    .spill.warn   { background:#451a03; color:#fcd34d; }
    .spill.err    { background:#450a0a; color:#fca5a5; }

    /* ── Modal ── */
    .modal-overlay { position:fixed; inset:0; background:#00000099; display:flex; align-items:center; justify-content:center; z-index:200; }
    .modal         { background:var(--surface); border:1px solid var(--border); border-radius:12px; padding:24px; max-width:420px; width:90%; }
    .modal h3      { font-size:16px; font-weight:700; color:var(--text); margin-bottom:8px; }
    .modal p       { font-size:13px; color:var(--text-sub); line-height:1.6; margin-bottom:6px; }
    .change-list   { background:var(--bg); border:1px solid var(--border); border-radius:8px; padding:10px 14px; margin:12px 0; font-size:12px; display:flex; flex-direction:column; gap:6px; }
    .change-row    { display:flex; gap:8px; }
    .change-row .lbl { color:var(--muted); min-width:130px; }
    .modal-actions { display:flex; gap:10px; margin-top:16px; }
    .btn-confirm   { flex:1; padding:9px; background:var(--blue); color:#fff; border:none; border-radius:8px; font-size:13px; font-weight:700; cursor:pointer; }
    .btn-cancel    { flex:1; padding:9px; background:transparent; color:var(--text-sub); border:1px solid var(--border); border-radius:8px; font-size:13px; cursor:pointer; }
    .modal-note    { font-size:11px; color:var(--muted); margin-top:10px; text-align:center; }

    /* ── Progress rows (Step 3) ── */
    .prog-row      { display:flex; align-items:center; gap:12px; padding:8px 0; border-bottom:1px solid var(--border); font-size:13px; }
    .prog-row:last-child { border-bottom:none; }
    .prog-upn      { font-family:monospace; font-size:12px; color:var(--text-sub); flex:1; }
    .prog-status   { font-size:12px; white-space:nowrap; }

    /* ── Download step ── */
    .dl-card       { display:flex; flex-direction:column; align-items:center; gap:12px; padding:32px; background:var(--surface); border:1px solid var(--border); border-radius:12px; text-align:center; }
    .dl-icon       { font-size:48px; }
    .dl-filename   { font-family:monospace; font-size:13px; color:var(--blue-text); }
    .dl-contents   { font-size:12px; color:var(--muted); line-height:1.8; }
  </style>
</head>
<body>
<div id="topbar"></div>

<!-- ── Auth screen ── -->
<div id="authScreen" class="auth-screen">
  <div class="auth-card">
    <div style="width:44px;height:44px;background:var(--blue-light);border-radius:11px;display:flex;align-items:center;justify-content:center;margin:0 auto 1.25rem">
      <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#7c3aed" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><line x1="19" y1="8" x2="19" y2="14"/><line x1="22" y1="11" x2="16" y2="11"/></svg>
    </div>
    <h1>User Creation</h1>
    <p>Sign in with your M365 admin account to create new employee accounts from a CSV.</p>
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
    <p class="auth-note">Requires <strong>User.ReadWrite.All</strong>, <strong>Group.ReadWrite.All</strong>, and <strong>Directory.Read.All</strong>.</p>
  </div>
</div>

<!-- ── App screen ── -->
<div id="appScreen" style="display:none">
  <div class="app-body">

    <nav class="sidebar">
      <div class="sidebar-lbl">Steps</div>
      <div class="step-item active" id="nav1">
        <div class="step-bullet" id="bul1">1</div>
        <div><div class="step-title">Upload CSV</div><div class="step-sub" id="sub1">Choose file</div></div>
      </div>
      <div class="step-item" id="nav2">
        <div class="step-bullet" id="bul2">2</div>
        <div><div class="step-title">Review &amp; Edit</div><div class="step-sub" id="sub2">Verify users</div></div>
      </div>
      <div class="step-item" id="nav3">
        <div class="step-bullet" id="bul3">3</div>
        <div><div class="step-title">Create Accounts</div><div class="step-sub" id="sub3">Pending</div></div>
      </div>
      <div class="step-item" id="nav4">
        <div class="step-bullet" id="bul4">4</div>
        <div><div class="step-title">Download Scripts</div><div class="step-sub" id="sub4">Pending</div></div>
      </div>
      <div class="sidebar-divider"></div>
      <div class="sidebar-tip">
        <strong>How it works</strong>
        Upload the standard NewAccounts CSV. Review and adjust per user. The hub creates accounts via Microsoft Graph, then generates an Exchange setup script for the remaining mailbox steps.
      </div>
    </nav>

    <main class="main-content">

      <!-- ── Step 1: Upload ── -->
      <div class="section active" id="step1">
        <div class="section-hdr">
          <h2>Upload CSV</h2>
          <p>Use the standard NewAccounts template. The hub validates all columns and checks for existing UPNs before you proceed.</p>
        </div>
        <div class="banner error" id="s1Err" style="display:none"></div>
        <div class="card">
          <div class="card-title">Source file</div>
          <div class="file-drop" id="fileDrop" ondragover="dragOver(event)" ondragleave="dragLeave(event)" ondrop="dropFile(event)">
            <div class="file-drop-idle">
              <div style="font-size:28px;margin-bottom:8px">📄</div>
              <p>Drag &amp; drop your CSV, or <strong style="cursor:pointer" onclick="document.getElementById('fileIn').click()">browse</strong></p>
              <p style="font-size:11px;color:var(--muted2);margin-top:4px">.csv files only</p>
            </div>
            <div class="file-drop-busy"><span class="spinner" style="width:14px;height:14px;border-width:2px"></span> Reading file…</div>
            <input type="file" id="fileIn" accept=".csv" onchange="handleFileInput(event)"/>
          </div>
          <div class="file-loaded" id="fileLoaded" style="display:none">
            <span style="font-size:16px">✅</span>
            <span class="file-loaded-name" id="fileName"></span>
            <span class="file-loaded-count" id="fileCount"></span>
            <button class="file-loaded-clear" onclick="clearFile()">✕</button>
          </div>
        </div>
        <div class="btn-row">
          <button class="btn btn-primary" id="s1Btn" onclick="goToStep2()" disabled>Continue →</button>
          <span id="s1Msg" style="font-size:12px;color:var(--muted)"></span>
        </div>
      </div>

      <!-- ── Step 2: Review & Edit ── -->
      <div class="section" id="step2">
        <div class="section-hdr">
          <h2>Review &amp; Edit</h2>
          <p>Adjust license, apps, or flags before creation. Use bulk settings for uniform batches, then override per row as needed.</p>
        </div>
        <div class="banner error" id="s2Err" style="display:none"></div>

        <!-- Region toggle -->
        <div style="display:flex;align-items:center;gap:12px;margin:16px 0 12px">
          <span style="font-size:11px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.06em">Region</span>
          <div class="mode-toggle">
            <button class="mode-btn active" id="modeIndia" onclick="setRegion('India')">🇮🇳 India</button>
            <button class="mode-btn"        id="modeUS"    onclick="setRegion('US')">🇺🇸 US</button>
          </div>
          <span style="font-size:11px;color:var(--muted)">Affects group assignments &amp; Exchange setup script</span>
        </div>

        <!-- Validation summary -->
        <div class="val-bar" id="valBar"></div>

        <!-- Bulk settings -->
        <div class="bulk-bar" id="bulkBar">
          <div class="bulk-header" onclick="toggleBulk()">
            <span id="bulkChevron" style="color:var(--muted);font-size:10px">▶</span>
            <span class="bulk-title">Bulk Settings</span>
            <span class="bulk-subtitle" id="bulkSubtitle">Apply the same license &amp; flags to all users at once</span>
          </div>
          <div class="bulk-body" id="bulkBody" style="display:none">
            <div class="bulk-field">
              <label>License for all</label>
              <select class="bulk-select" id="bulkLicense">
                <option value="">— keep per-row values —</option>
                <option value="2GB">F3 (2 GB mailbox)</option>
                <option value="50GB">F3+ (50 GB + Archive)</option>
                <option value="E3">E3 (full suite)</option>
              </select>
            </div>
            <div class="bulk-field">
              <label>Apps for all</label>
              <div class="bulk-toggle-row">
                <label class="tog"><input type="checkbox" id="bulkApps"/><div class="track"></div></label>
                <span>Microsoft 365 desktop apps</span>
              </div>
            </div>
            <div class="bulk-field">
              <label>Subcontractor for all</label>
              <div class="bulk-toggle-row">
                <label class="tog"><input type="checkbox" id="bulkSub"/><div class="track"></div></label>
                <span>Tag as subcontractor</span>
              </div>
            </div>
            <button class="btn btn-primary" onclick="showBulkModal()">Apply to All →</button>
            <div class="bulk-note">⚠ Overwrites per-row values. Individual rows can still be adjusted after applying.</div>
          </div>
        </div>

        <!-- Review table -->
        <div class="tbl-wrap" id="reviewWrap">
          <table class="review-tbl" style="width:100%;border-collapse:collapse">
            <thead>
              <tr>
                <th>#</th><th>Display Name</th><th>UPN</th><th>EID</th>
                <th>License</th><th>Apps</th><th>Subcontractor</th><th>Status</th>
              </tr>
            </thead>
            <tbody id="reviewBody"></tbody>
          </table>
        </div>

        <div class="btn-row" style="margin-top:16px">
          <button class="btn btn-primary" id="s2Btn" onclick="goToStep3()" disabled>Continue to Create Accounts →</button>
          <button class="btn btn-ghost"   onclick="gotoStep(1)">← Back</button>
          <span id="s2Msg" style="font-size:12px;color:var(--muted);margin-left:8px"></span>
        </div>
      </div>

      <!-- ── Step 3: Create Accounts ── -->
      <div class="section" id="step3">
        <div class="section-hdr">
          <h2>Create Accounts</h2>
          <p>Creating accounts via Microsoft Graph. Do not close this tab until complete.</p>
        </div>
        <div class="banner error" id="s3Err" style="display:none"></div>
        <div class="card">
          <div class="card-title">Progress</div>
          <div id="progRows"></div>
        </div>
        <div class="btn-row" id="s3BtnRow" style="display:none">
          <button class="btn btn-primary" onclick="gotoStep(4)">Continue to Download →</button>
        </div>
      </div>

      <!-- ── Step 4: Download ── -->
      <div class="section" id="step4">
        <div class="section-hdr">
          <h2>Download Scripts</h2>
          <p>All accounts created. Download the ZIP to complete mailbox configuration via Exchange Online.</p>
        </div>
        <div class="banner error" id="s4Err" style="display:none"></div>
        <div class="card">
          <div class="dl-card">
            <div class="dl-icon">📦</div>
            <div id="dlFilename" class="dl-filename"></div>
            <div class="dl-contents">
              Exchange-Setup.ps1 — pre-populated Exchange script<br/>
              Run-Exchange-Setup.bat — double-click launcher<br/>
              Credentials.csv — per-user temp passwords
            </div>
            <button class="btn btn-primary" id="dlBtn" onclick="downloadZip()">Download ZIP</button>
          </div>
        </div>
        <div style="margin-top:16px;padding:12px 14px;background:var(--surface);border:1px solid var(--border);border-radius:8px;font-size:12px;color:var(--muted)">
          🔑 <strong style="color:var(--text)">Credentials CSV is inside the ZIP.</strong> Extract to Desktop, double-click the .bat to run Exchange setup. Store credentials securely before distributing to new hires.
        </div>
      </div>

    </main>
  </div>
</div>

<!-- ── Bulk confirm modal ── -->
<div class="modal-overlay" id="bulkModal" style="display:none" onclick="if(event.target===this)this.style.display='none'">
  <div class="modal">
    <h3>⚠️ Apply bulk settings?</h3>
    <p>This will overwrite current per-row values with:</p>
    <div class="change-list" id="bulkChangeList"></div>
    <p>Individual rows can still be adjusted after applying.</p>
    <div class="modal-actions">
      <button class="btn-confirm" onclick="applyBulk()">Yes, apply to all</button>
      <button class="btn-cancel"  onclick="document.getElementById('bulkModal').style.display='none'">Cancel</button>
    </div>
    <div class="modal-note" id="bulkModalNote"></div>
  </div>
</div>

<script>
const TOOL_SCOPES = [
  "User.ReadWrite.All",
  "Group.ReadWrite.All",
  "Directory.Read.All"
];

const REQUIRED_COLS = [
  "EID","Firstname","Lastname","UserPrincipalName",
  "RequiredMailboxSize","InternalEmailOnly","EntApps",
  "Designation","City","Province","Country","Office","SubContractor"
];

const VALID_SIZES = ["2 GB","2GB","50 GB","50GB","E3","e3"];

const INDIA_GROUPS = {
  subContractor: "P-SG-InTune-Global-SubContractor-User-Group",
  teamMember:    "P-SG-InTune-Global-Team_Member-User-Group",
  o365Login:     "India O365 Login Access",
  internalEmail: "internal email only",
  disableOutlook:"Disable Outlook Access"
};

const US_GROUPS = {
  subContractor: "TBD_US_SUBCONTRACTOR_GROUP",
  teamMember:    "TBD_US_TEAM_MEMBER_GROUP"
};

const st = {
  rows:    [],     // enriched row objects (see parseAndRender)
  region:  "India",
  skus:    {},     // { f3, f3archive, e3, appsEnt } — SkuId GUIDs
  groups:  {},     // { subContractor, teamMember, o365Login, internalEmail, disableOutlook } — Group IDs
  created: []      // rows that succeeded creation (with .password)
};

function showErr(id, msg) {
  const el = document.getElementById(id);
  el.textContent = msg;
  el.className = "banner error";
  el.style.display = msg ? "block" : "none";
}

async function doSignIn() {
  try {
    const acct = await ITTools.auth.signIn();
    document.getElementById("authScreen").style.display = "none";
    document.getElementById("appScreen").style.display  = "block";
    ITTools.ui.setUser(acct);
  } catch(e) {
    const el = document.getElementById("authErr");
    el.textContent = e.message; el.style.display = "block";
  }
}

function gotoStep(n) {
  [1,2,3,4].forEach(i => {
    document.getElementById("step"+i).classList.toggle("active", i===n);
    document.getElementById("nav"+i).classList.toggle("active",  i===n);
  });
}

function markDone(n, subtitle) {
  const nav = document.getElementById("nav"+n);
  nav.classList.remove("active");
  nav.classList.add("done");
  if (subtitle) document.getElementById("sub"+n).textContent = subtitle;
}

async function init() {
  ITTools.theme.init();
  ITTools.ui.renderTopbar({ toolName: "User Creation", hubRelPath: "../../", status: "beta" });
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: async acct => {
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
    }
  });
}

window.addEventListener("load", init);
</script>
</body>
</html>
```

- [ ] **Step 4: Verify scaffold in browser**

Open `http://localhost` (or the testing branch preview URL). Navigate to the User Creation tool. Verify:
- Hub card appears in daily-ops section with purple accent
- Clicking card opens the tool
- Auth screen shows with purple icon and correct permission note
- Sign in works — app screen appears with 4-step sidebar

- [ ] **Step 5: Commit**

```bash
git add tools/user-creation/ config.json
git commit -m "feat: scaffold user creation tool — auth shell, 4-step sidebar, JSZip"
```

---

### Task 2: Step 1 — CSV file drop, parse, and validate

**Files:**
- Modify: `tools/user-creation/index.html` — add `dragOver`, `dragLeave`, `dropFile`, `handleFileInput`, `loadFile`, `clearFile`, `parseAndRender` functions

- [ ] **Step 1: Add file drop handlers and loadFile with AV timeout**

Inside the `<script>` block, add after `markDone()`:

```javascript
// ── Step 1: File upload ──────────────────────────────────

function dragOver(e)  { e.preventDefault(); document.getElementById("fileDrop").classList.add("drag-over"); }
function dragLeave()  { document.getElementById("fileDrop").classList.remove("drag-over"); }
function dropFile(e)  { e.preventDefault(); dragLeave(); loadFile(e.dataTransfer.files[0]); }
function handleFileInput(e) { loadFile(e.target.files[0]); }

function clearFile() {
  st.rows = [];
  document.getElementById("fileLoaded").style.display = "none";
  document.getElementById("fileDrop").style.display   = "block";
  document.getElementById("fileDrop").classList.remove("file-reading");
  document.getElementById("fileIn").value = "";
  document.getElementById("s1Btn").disabled = true;
  document.getElementById("s1Msg").textContent = "";
  showErr("s1Err", "");
}

async function loadFile(file) {
  if (!file) return;
  if (!file.name.toLowerCase().endsWith(".csv")) {
    showErr("s1Err", "Please upload a .csv file.");
    return;
  }
  const drop = document.getElementById("fileDrop");
  drop.classList.add("file-reading");
  showErr("s1Err", "");
  try {
    const text = await Promise.race([
      file.text(),
      new Promise((_, reject) => setTimeout(() => reject(new Error("AV_TIMEOUT")), 10000))
    ]);
    parseAndRender(file.name, text);
  } catch(e) {
    drop.classList.remove("file-reading");
    document.getElementById("fileIn").value = "";
    if (e.message === "AV_TIMEOUT") {
      showErr("s1Err", "File took too long to read — Windows Defender may be scanning it. Wait a moment and try again.");
    } else {
      showErr("s1Err", "Could not read file. (" + e.message + ")");
    }
  }
}
```

- [ ] **Step 2: Add parseAndRender — validate columns and rows**

```javascript
function normaliseSize(raw) {
  const s = (raw || "").trim().toUpperCase().replace(/\s+/g, "");
  if (s === "2GB")  return "2GB";
  if (s === "50GB") return "50GB";
  if (s === "E3")   return "E3";
  return null;
}

function parseAndRender(filename, text) {
  const drop = document.getElementById("fileDrop");
  let parsed;
  try {
    parsed = ITTools.csv.parse(text);
  } catch(e) {
    drop.classList.remove("file-reading");
    document.getElementById("fileIn").value = "";
    showErr("s1Err", "Could not parse CSV: " + e.message);
    return;
  }

  // Validate required columns (case-insensitive)
  const headerMap = {};
  parsed.headers.forEach(h => { headerMap[h.trim().toLowerCase()] = h.trim(); });
  const missing = REQUIRED_COLS.filter(c => !headerMap[c.toLowerCase()]);
  if (missing.length) {
    drop.classList.remove("file-reading");
    document.getElementById("fileIn").value = "";
    showErr("s1Err", "Missing required columns: " + missing.join(", "));
    return;
  }

  // Build enriched rows
  const upnRe = /^[a-zA-Z]+\.[a-zA-Z]+@corrohealth\.com$/i;
  st.rows = parsed.rows.map((r, i) => {
    const fn  = (r.Firstname  || "").trim();
    const ln  = (r.Lastname   || "").trim();
    const upn = (r.UserPrincipalName || "").trim();
    const sz  = normaliseSize(r.RequiredMailboxSize);
    let   err = "", warn = "";

    if (!fn || !ln)      err  = "Missing first or last name";
    else if (!upnRe.test(upn)) err = "UPN format invalid";
    else if (!sz)        err  = "RequiredMailboxSize must be 2 GB, 50 GB, or E3";

    return {
      num:             i + 1,
      fn, ln,
      upn,
      eid:             (r.EID || "").trim(),
      size:            sz || r.RequiredMailboxSize,
      internalEmail:   (r.InternalEmailOnly || "").toUpperCase() === "Y",
      entApps:         (r.EntApps      || "").toUpperCase() === "Y",
      subContractor:   (r.SubContractor || "").toUpperCase() === "Y",
      designation:     (r.Designation  || "").trim(),
      city:            (r.City     || "").trim(),
      province:        (r.Province || "").trim(),
      country:         (r.Country  || "").trim(),
      office:          (r.Office   || "").trim(),
      status:          err ? "error" : "checking",
      err, warn,
      password:        ""
    };
  });

  const hardErrors = st.rows.filter(r => r.err).length;

  drop.classList.remove("file-reading");
  drop.style.display = "none";
  document.getElementById("fileLoaded").style.display = "flex";
  document.getElementById("fileName").textContent  = filename;
  document.getElementById("fileCount").textContent = st.rows.length + " rows";

  if (hardErrors) {
    showErr("s1Err", hardErrors + " row(s) have errors — fix the CSV and re-upload.");
  } else {
    document.getElementById("s1Btn").disabled = false;
    document.getElementById("s1Msg").textContent = st.rows.length + " rows ready — checking UPNs…";
    checkUpns();
  }
}
```

- [ ] **Step 3: Verify parse in browser**

Upload the `NewAccountsTemplate.csv`. Verify:
- Spinner shows briefly while reading
- File-loaded bar appears with filename and row count
- Continue button enables (no hard errors in the sample)
- Try uploading a CSV with a missing column (e.g. delete `EID` header) — verify error banner appears

- [ ] **Step 4: Commit**

```bash
git add tools/user-creation/index.html
git commit -m "feat: user-creation step 1 — CSV file drop, parse, column validation"
```

---

### Task 3: Step 1 — UPN existence check via Graph

**Files:**
- Modify: `tools/user-creation/index.html` — add `checkUpns()` and `goToStep2()` functions

- [ ] **Step 1: Add checkUpns() — batch UPN existence check**

Add after `parseAndRender()`:

```javascript
async function checkUpns() {
  const toCheck = st.rows.filter(r => r.status === "checking");
  let checked = 0;
  for (const row of toCheck) {
    try {
      const res = await ITTools.graph.get(
        `/users?$filter=userPrincipalName eq '${encodeURIComponent(row.upn)}'&$select=id&$count=true`
      );
      const exists = res && res.value && res.value.length > 0;
      row.status = exists ? "warn" : "ok";
      row.warn   = exists ? "UPN already exists in Entra — will be skipped" : "";
    } catch(e) {
      row.status = "ok";  // fail open — don't block on Graph errors
    }
    checked++;
    document.getElementById("s1Msg").textContent =
      `Checking UPNs… ${checked}/${toCheck.length}`;
  }

  const errors   = st.rows.filter(r => r.status === "error").length;
  const warnings = st.rows.filter(r => r.status === "warn").length;
  const ready    = st.rows.filter(r => r.status === "ok").length;

  if (errors > 0) {
    document.getElementById("s1Btn").disabled = true;
    document.getElementById("s1Msg").textContent = "";
    showErr("s1Err", errors + " row(s) have errors — fix the CSV and re-upload.");
  } else {
    document.getElementById("s1Btn").disabled = false;
    document.getElementById("s1Msg").textContent =
      `${ready} ready${warnings ? " · " + warnings + " warning(s)" : ""}`;
  }
}
```

- [ ] **Step 2: Add goToStep2() — advance and render review table**

```javascript
function goToStep2() {
  markDone(1, st.rows.length + " rows loaded");
  gotoStep(2);
  renderReviewTable();
  updateValBar();
  updateS2Btn();
  const date = new Date().toLocaleDateString("en-US",{month:"short",day:"numeric",year:"numeric"});
  document.getElementById("dlFilename").textContent =
    "NewAccountsSetup-" + new Date().toISOString().slice(0,10) + ".zip";
}
```

- [ ] **Step 3: Verify UPN check in browser**

Sign in, upload the template. After parse, the "Checking UPNs…" message should count up. Once done, rows for existing UPNs should be marked. Continue button should enable when checking is done and there are zero hard errors.

- [ ] **Step 4: Commit**

```bash
git add tools/user-creation/index.html
git commit -m "feat: user-creation step 1 — UPN existence check via Graph"
```

---

### Task 4: Step 2 — Review table rendering with per-row controls

**Files:**
- Modify: `tools/user-creation/index.html` — add `renderReviewTable()`, `updateValBar()`, `updateS2Btn()`, `rowChanged()`, `setRegion()`

- [ ] **Step 1: Add renderReviewTable()**

```javascript
// ── Step 2: Review table ──────────────────────────────────

function licenseLabel(size) {
  if (size === "2GB")  return "F3 (2 GB)";
  if (size === "50GB") return "F3+ (50 GB)";
  if (size === "E3")   return "E3";
  return size;
}

function renderReviewTable() {
  const tbody = document.getElementById("reviewBody");
  tbody.innerHTML = "";
  st.rows.forEach((row, idx) => {
    const tr = document.createElement("tr");
    tr.className = row.status === "warn" ? "row-warn" : row.status === "error" ? "row-err" : "";
    tr.innerHTML = `
      <td style="color:var(--muted);font-size:12px">${row.num}</td>
      <td>${row.fn} ${row.ln}</td>
      <td class="upn-cell" style="${row.status==="warn"?"color:#fca5a5":""}">${row.upn}</td>
      <td style="color:var(--muted);font-size:12px">${row.eid}</td>
      <td>
        <select class="inline-sel" onchange="rowChanged(${idx},'size',this.value)">
          <option value="2GB"  ${row.size==="2GB" ?"selected":""}>F3 (2 GB)</option>
          <option value="50GB" ${row.size==="50GB"?"selected":""}>F3+ (50 GB)</option>
          <option value="E3"   ${row.size==="E3"  ?"selected":""}>E3</option>
        </select>
      </td>
      <td>
        <label class="tog" title="Adds Microsoft 365 desktop apps (Word, Excel, PowerPoint). Does not include Outlook desktop — E3 required for that.">
          <input type="checkbox" ${row.entApps?"checked":""} onchange="rowChanged(${idx},'entApps',this.checked)"/>
          <div class="track"></div>
        </label>
      </td>
      <td>
        <label class="tog">
          <input type="checkbox" ${row.subContractor?"checked":""} onchange="rowChanged(${idx},'subContractor',this.checked)"/>
          <div class="track"></div>
        </label>
      </td>
      <td>${pillHtml(row)}</td>
    `;
    tbody.appendChild(tr);
  });
}

function pillHtml(row) {
  if (row.status === "ok")    return '<span class="spill ok">✓ Ready</span>';
  if (row.status === "warn")  return `<span class="spill warn">⚠ ${row.warn || "Warning"}</span>`;
  if (row.status === "error") return `<span class="spill err">✗ ${row.err  || "Error"}</span>`;
  return '<span class="spill warn">⏳ Checking…</span>';
}

function rowChanged(idx, field, value) {
  st.rows[idx][field] = value;
  // Re-render just the status pill for this row
  const rows = document.getElementById("reviewBody").querySelectorAll("tr");
  if (rows[idx]) {
    rows[idx].querySelector("td:last-child").innerHTML = pillHtml(st.rows[idx]);
  }
  updateValBar();
  updateS2Btn();
}
```

- [ ] **Step 2: Add updateValBar(), updateS2Btn(), setRegion()**

```javascript
function updateValBar() {
  const ok   = st.rows.filter(r => r.status === "ok").length;
  const warn = st.rows.filter(r => r.status === "warn").length;
  const err  = st.rows.filter(r => r.status === "error").length;
  document.getElementById("valBar").innerHTML = `
    <div class="val-pill ok"><div class="dot"></div> ${ok} ready</div>
    <div class="val-pill warn" ${warn===0?"style='opacity:.35'":""}><div class="dot"></div> ${warn} warning${warn!==1?"s":""}</div>
    <div class="val-pill err"  ${err ===0?"style='opacity:.35'":""}><div class="dot"></div> ${err} error${err!==1?"s":""}</div>
    ${err>0?"<span style='margin-left:auto;font-size:12px;color:var(--muted)'>Errors must be resolved before you can proceed</span>":""}
  `;
}

function updateS2Btn() {
  const ready    = st.rows.filter(r => r.status === "ok").length;
  const warnings = st.rows.filter(r => r.status === "warn").length;
  const errors   = st.rows.filter(r => r.status === "error").length;
  const btn = document.getElementById("s2Btn");
  btn.disabled = errors > 0 || ready === 0;
  document.getElementById("s2Msg").textContent =
    errors > 0
      ? `${errors} error(s) must be fixed`
      : `${ready} account${ready!==1?"s":""} will be created${warnings ? " · " + warnings + " skipped (UPN exists)" : ""}`;
}

function setRegion(r) {
  st.region = r;
  document.getElementById("modeIndia").classList.toggle("active", r === "India");
  document.getElementById("modeUS").classList.toggle("active",    r === "US");
}
```

- [ ] **Step 3: Verify review table in browser**

Upload the template and advance to Step 2. Verify:
- Table renders with all 13 rows from the sample CSV
- License dropdowns reflect values from CSV (row 2 should show F3+)
- Apps toggle checked for row 2 (EntApps=Y)
- Validation summary bar shows correct counts
- Continue button is enabled for the clean sample

- [ ] **Step 4: Commit**

```bash
git add tools/user-creation/index.html
git commit -m "feat: user-creation step 2 — review table with per-row license/apps/subcontractor controls"
```

---

### Task 5: Step 2 — Bulk settings bar and confirmation modal

**Files:**
- Modify: `tools/user-creation/index.html` — add `toggleBulk()`, `showBulkModal()`, `applyBulk()`

- [ ] **Step 1: Add bulk bar toggle and modal functions**

```javascript
// ── Step 2: Bulk settings ──────────────────────────────────

function toggleBulk() {
  const body    = document.getElementById("bulkBody");
  const chevron = document.getElementById("bulkChevron");
  const open    = body.style.display !== "none";
  body.style.display    = open ? "none" : "flex";
  chevron.textContent   = open ? "▶" : "▼";
}

function showBulkModal() {
  const lic  = document.getElementById("bulkLicense").value;
  const apps = document.getElementById("bulkApps").checked;
  const sub  = document.getElementById("bulkSub").checked;
  const warn = st.rows.filter(r => r.status === "warn").length;
  const total= st.rows.length;

  const licLabel = lic === "2GB" ? "F3 (2 GB mailbox)"
                 : lic === "50GB" ? "F3+ (50 GB + Archive)"
                 : lic === "E3"   ? "E3 (full suite)"
                 : "— no change —";

  document.getElementById("bulkChangeList").innerHTML = `
    <div class="change-row"><span class="lbl">License:</span><strong>${licLabel}</strong></div>
    <div class="change-row"><span class="lbl">Apps:</span><strong>${apps ? "On — desktop apps" : "Off — web apps only"}</strong></div>
    <div class="change-row"><span class="lbl">Subcontractor:</span><strong>${sub ? "On — subcontractor group" : "Off — team member group"}</strong></div>
  `;
  document.getElementById("bulkModalNote").textContent =
    warn > 0 ? `${warn} row(s) with UPN warnings will be skipped regardless.` : "";
  document.getElementById("bulkModal").style.display = "flex";
}

function applyBulk() {
  const lic  = document.getElementById("bulkLicense").value;
  const apps = document.getElementById("bulkApps").checked;
  const sub  = document.getElementById("bulkSub").checked;

  st.rows.forEach(row => {
    if (row.status === "warn" || row.status === "error") return;  // skip warnings/errors
    if (lic)  row.size         = lic;
    row.entApps      = apps;
    row.subContractor= sub;
  });

  document.getElementById("bulkModal").style.display = "none";
  renderReviewTable();
  updateValBar();
  updateS2Btn();
}
```

- [ ] **Step 2: Verify bulk settings in browser**

On Step 2, expand the Bulk Settings bar. Set License to E3. Click Apply to All. Verify:
- Modal appears listing "E3 (full suite)" as the change
- On confirm, all ready rows update their license dropdown to E3
- Warning rows are unchanged

- [ ] **Step 3: Commit**

```bash
git add tools/user-creation/index.html
git commit -m "feat: user-creation step 2 — bulk settings bar with confirmation modal"
```

---

### Task 6: Step 3 — Account creation with live progress

**Files:**
- Modify: `tools/user-creation/index.html` — add `goToStep3()`, `generatePassword()`, `fetchSkus()`, `resolveGroups()`, `createAccounts()`, `createUser()`

- [ ] **Step 1: Add password generator**

```javascript
// ── Step 3: Create accounts ──────────────────────────────────

function generatePassword() {
  const upper   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const lower   = "abcdefghijklmnopqrstuvwxyz";
  const digits  = "0123456789";
  const symbols = "!@#$%^&*";
  const all     = upper + lower + digits + symbols;
  const bytes   = new Uint8Array(20);
  crypto.getRandomValues(bytes);
  let pwd = "";
  pwd += upper  [bytes[0]  % upper.length];
  pwd += lower  [bytes[1]  % lower.length];
  pwd += digits [bytes[2]  % digits.length];
  pwd += symbols[bytes[3]  % symbols.length];
  for (let i = 4; i < 16; i++) pwd += all[bytes[i] % all.length];
  // Fisher-Yates shuffle
  const chars = pwd.split("");
  for (let i = chars.length - 1; i > 0; i--) {
    const j = bytes[i % bytes.length] % (i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}
```

- [ ] **Step 2: Add SKU fetch and group ID resolution**

```javascript
async function fetchSkus() {
  const res  = await ITTools.graph.get("/subscribedSkus");
  const skus = (res && res.value) ? res.value : [];
  const find = (part) => {
    const s = skus.find(x => x.skuPartNumber === part);
    return s ? s.skuId : null;
  };
  st.skus = {
    f3:       find("SPE_F1"),
    f3archive:find("EXCHANGEARCHIVE_ADDON"),
    e3:       find("SPE_E3"),
    appsEnt:  find("OFFICESUBSCRIPTION")
  };
  const missing = Object.entries(st.skus).filter(([,v]) => !v).map(([k]) => k);
  if (missing.length) {
    throw new Error("Could not find SKUs: " + missing.join(", ") + ". Check tenant license inventory.");
  }
}

async function resolveGroups() {
  const groupNames = st.region === "India" ? INDIA_GROUPS : US_GROUPS;
  for (const [key, name] of Object.entries(groupNames)) {
    if (name.startsWith("TBD_")) { st.groups[key] = null; continue; }
    const res = await ITTools.graph.get(
      `/groups?$filter=displayName eq '${encodeURIComponent(name)}'&$select=id,displayName&$top=1`
    );
    const grp = res && res.value && res.value[0];
    if (!grp) throw new Error(`Group not found: "${name}"`);
    st.groups[key] = grp.id;
  }
}
```

- [ ] **Step 3: Add goToStep3() and createAccounts() loop**

```javascript
async function goToStep3() {
  markDone(2, st.rows.filter(r=>r.status==="ok").length + " ready");
  gotoStep(3);
  await createAccounts();
}

async function createAccounts() {
  showErr("s3Err", "");
  document.getElementById("s3BtnRow").style.display = "none";

  // Pre-flight: fetch SKUs and resolve group IDs
  const progRows = document.getElementById("progRows");
  progRows.innerHTML = '<div class="prog-row"><span class="prog-upn">Fetching licenses and groups…</span></div>';

  try {
    await fetchSkus();
    await resolveGroups();
  } catch(e) {
    showErr("s3Err", "Setup failed: " + ITTools.graph.friendlyError(e));
    return;
  }

  const toCreate = st.rows.filter(r => r.status === "ok");
  progRows.innerHTML = "";
  st.created = [];

  for (const row of toCreate) {
    // Add progress row
    const div = document.createElement("div");
    div.className = "prog-row";
    div.id = "prog-" + row.num;
    div.innerHTML = `
      <span class="prog-upn">${row.upn}</span>
      <span class="prog-status" style="color:var(--muted)">
        <span class="spinner" style="width:10px;height:10px;border-width:2px"></span> Creating…
      </span>
    `;
    progRows.appendChild(div);

    try {
      const password = generatePassword();
      await createUser(row, password);
      row.password = password;
      st.created.push(row);
      setProgStatus(row.num, "✓ Done", "var(--green)");
    } catch(e) {
      setProgStatus(row.num, "✗ " + ITTools.graph.friendlyError(e), "#fca5a5");
    }
  }

  // Summary
  const failed = toCreate.length - st.created.length;
  const warned = st.rows.filter(r => r.status === "warn").length;
  document.getElementById("sub3").textContent =
    `${st.created.length} created${failed ? " · " + failed + " failed" : ""}${warned ? " · " + warned + " skipped" : ""}`;
  document.getElementById("s3BtnRow").style.display = st.created.length > 0 ? "flex" : "none";
  if (st.created.length === 0) {
    showErr("s3Err", "No accounts were created. Check errors above.");
  }
}

function setProgStatus(num, msg, color) {
  const el = document.getElementById("prog-" + num);
  if (el) el.querySelector(".prog-status").innerHTML =
    `<span style="color:${color}">${msg}</span>`;
}
```

- [ ] **Step 4: Add createUser() — Graph user creation, license, groups**

```javascript
async function createUser(row, password) {
  const sizeKey = row.size === "2GB" ? "f3" : row.size === "50GB" ? "f3" : "e3";

  // 1. Create user
  setProgStatus(row.num, "⏳ Creating user…", "var(--muted)");
  const created = await ITTools.graph.post("/users", {
    accountEnabled:       true,
    displayName:          row.fn + " " + row.ln,
    givenName:            row.fn,
    surname:              row.ln,
    userPrincipalName:    row.upn,
    mailNickname:         row.upn.split("@")[0],
    employeeId:           row.eid,
    preferredDataLocation:row.eid,
    jobTitle:             row.designation,
    city:                 row.city,
    state:                row.province,
    country:              row.country,
    officeLocation:       row.office,
    usageLocation:        row.country.toUpperCase() === "INDIA" || st.region === "India" ? "IN" : "US",
    passwordProfile: {
      forceChangePasswordNextSignIn: true,
      password
    }
  });
  const userId = created.id;

  // 2. Assign license(s)
  setProgStatus(row.num, "⏳ Assigning license…", "var(--muted)");
  const skusToAdd = [{ skuId: sizeKey === "f3" ? st.skus.f3 : st.skus.e3 }];
  if (row.size === "50GB") skusToAdd.push({ skuId: st.skus.f3archive });
  if (row.entApps)         skusToAdd.push({ skuId: st.skus.appsEnt  });
  await ITTools.graph.post(`/users/${userId}/assignLicense`, {
    addLicenses: skusToAdd,
    removeLicenses: []
  });

  // 3. Add to security groups
  setProgStatus(row.num, "⏳ Adding to groups…", "var(--muted)");
  const groupsToAdd = [];
  groupsToAdd.push(row.subContractor ? st.groups.subContractor : st.groups.teamMember);
  if (st.region === "India") {
    if (row.size === "E3" && st.groups.o365Login)      groupsToAdd.push(st.groups.o365Login);
    if (row.size !== "E3"  && st.groups.internalEmail)  groupsToAdd.push(st.groups.internalEmail);
    if (row.size !== "E3"  && st.groups.disableOutlook) groupsToAdd.push(st.groups.disableOutlook);
  }
  for (const gid of groupsToAdd.filter(Boolean)) {
    await ITTools.graph.post(`/groups/${gid}/members/$ref`, {
      "@odata.id": `https://graph.microsoft.com/v1.0/directoryObjects/${userId}`
    });
  }
}
```

- [ ] **Step 5: Verify creation flow in browser**

Using a test/sandbox tenant: upload a single-row CSV, advance to Step 3, verify:
- "Fetching licenses and groups…" appears briefly
- Progress row shows UPN with spinner
- Status updates through Creating → Assigning license → Adding to groups → ✓ Done
- Continue button appears after completion
- Created user appears in Entra admin portal

- [ ] **Step 6: Commit**

```bash
git add tools/user-creation/index.html
git commit -m "feat: user-creation step 3 — account creation via Graph with live progress"
```

---

### Task 7: Step 4 — ZIP generation and download

**Files:**
- Modify: `tools/user-creation/index.html` — add `buildExchangeScript()`, `buildBatFile()`, `buildCredentialsCsv()`, `downloadZip()`

- [ ] **Step 1: Add Exchange script builder**

```javascript
// ── Step 4: ZIP generation ──────────────────────────────────

function buildExchangeScript() {
  const date      = new Date().toISOString().slice(0, 10);
  const region    = st.region;
  const count     = st.created.length;
  const retPolicy = region === "India" ? "India F3 Users" : "TBD_US_RETENTION_POLICY";

  const indiaE3Block = region === "India" ? `
    if ($u.Size -eq "E3") {
        try {
            Add-DistributionGroupMember -Identity "India O365 Login Access" -Member $u.UPN \`
                -BypassSecurityGroupManagerCheck -ErrorAction Stop
            Write-Detail "Added to: India O365 Login Access" Green
        } catch { Write-Detail "  India O365 Login Access: \$(\$_.Exception.Message)" Yellow }
    }` : `
    # US E3 group: TBD — confirm group name with team before activating`;

  const userEntries = st.created.map(r =>
    `    @{ UPN="${r.upn}"; Size="${r.size}"; SubContractor=\$${r.subContractor}; InternalEmailOnly=\$${r.internalEmail} }`
  ).join(",\r\n");

  return `# Generated by IT Tools Hub
# Date   : ${date}
# Region : ${region}
# Users  : ${count}
# Run AFTER verifying accounts appear in Entra ID (allow 2-5 minutes)

$ErrorActionPreference = "Continue"

function Write-Step   { param([int]$n,[string]$msg) Write-Host "\`n[$n/3] $msg" -ForegroundColor Cyan }
function Write-Detail { param([string]$msg,[string]$color="White") Write-Host "      $msg" -ForegroundColor $color }

Write-Host ""
Write-Host "  ================================================" -ForegroundColor DarkCyan
Write-Host "   Exchange Setup - Generated by IT Tools Hub"      -ForegroundColor White
Write-Host "  ================================================" -ForegroundColor DarkCyan
Write-Host "   Date   : ${date}"   -ForegroundColor Gray
Write-Host "   Region : ${region}" -ForegroundColor Gray
Write-Host "   Users  : ${count}"  -ForegroundColor Gray
Write-Host ""

$users = @(
${userEntries}
)

# --- Phase 1: Connect ---
Write-Step 1 "Connecting to Exchange Online..."
try {
    Connect-ExchangeOnline -ShowBanner:\$false -ErrorAction Stop
    Write-Detail "Exchange Online: connected" Green
} catch {
    Write-Host "ERROR: Could not connect. \$_" -ForegroundColor Red
    exit 1
}

# --- Phase 2: Per-user operations ---
Write-Step 2 "Configuring mailboxes..."
Write-Host ""

$i = 0
foreach (\$u in \$users) {
    \$i++
    Write-Host ("  [{0}/{1}] {2}" -f \$i, \$users.Count, \$u.UPN) -ForegroundColor White

    if (\$u.InternalEmailOnly) {
        try {
            Add-DistributionGroupMember -Identity "internal email only" -Member \$u.UPN \`
                -BypassSecurityGroupManagerCheck -ErrorAction Stop
            Write-Detail "Added to: internal email only" Green
        } catch { Write-Detail "  internal email only: \$(\$_.Exception.Message)" Yellow }

        try {
            Add-DistributionGroupMember -Identity "Disable Outlook Access" -Member \$u.UPN \`
                -BypassSecurityGroupManagerCheck -ErrorAction Stop
            Write-Detail "Added to: Disable Outlook Access" Green
        } catch { Write-Detail "  Disable Outlook Access: \$(\$_.Exception.Message)" Yellow }
    }
${indiaE3Block}

    if (\$u.SubContractor) {
        try {
            Set-Mailbox \$u.UPN -CustomAttribute4 "SubContractor" -ErrorAction Stop
            Write-Detail "CustomAttribute4 = SubContractor" Green
        } catch { Write-Detail "  CustomAttribute4: \$(\$_.Exception.Message)" Yellow }
    }

    if (\$u.Size -eq "50GB") {
        try {
            Enable-Mailbox -Identity \$u.UPN -Archive -ErrorAction Stop
            Write-Detail "Archive: enabled" Green
        } catch { Write-Detail "  Archive: \$(\$_.Exception.Message)" Yellow }

        try {
            Set-Mailbox -Identity \$u.UPN -RetentionPolicy "${retPolicy}" -ErrorAction Stop
            Write-Detail "Retention policy: ${retPolicy}" Green
        } catch { Write-Detail "  Retention policy: \$(\$_.Exception.Message)" Yellow }
    }

    Write-Host ""
}

# --- Phase 3: Complete ---
Write-Step 3 "Complete"
Write-Host ""
Write-Host "  \$(\$users.Count) users processed." -ForegroundColor White
Write-Host "  Next: Ask each user to sign in at portal.office.com to verify access." -ForegroundColor Gray
Write-Host ""

Disconnect-ExchangeOnline -Confirm:\$false -ErrorAction SilentlyContinue
Write-Host "  Exchange Online session disconnected.\`n" -ForegroundColor DarkGray
`;
}
```

- [ ] **Step 2: Add bat file and credentials CSV builders**

```javascript
function buildBatFile() {
  const date   = new Date().toISOString().slice(0, 10);
  const region = st.region;
  const count  = st.created.length;
  return `@echo off
echo ================================================
echo  Exchange Setup - Generated by IT Tools Hub
echo ================================================
echo.
echo  Date   : ${date}
echo  Region : ${region}
echo  Users  : ${count}
echo.
echo  This will connect to Exchange Online and complete
echo  mailbox configuration for newly created accounts.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Exchange-Setup.ps1"
pause
`;
}

function buildCredentialsCsv() {
  const lines = ["DisplayName,UPN,TempPassword"];
  st.created.forEach(r => {
    const display = `${r.fn} ${r.ln}`.replace(/,/g, "");
    lines.push(`${display},${r.upn},${r.password}`);
  });
  return lines.join("\r\n");
}
```

- [ ] **Step 3: Add downloadZip()**

```javascript
async function downloadZip() {
  const btn = document.getElementById("dlBtn");
  btn.disabled = true;
  btn.textContent = "Generating…";
  try {
    const zip = new JSZip();
    zip.file("Exchange-Setup.ps1", buildExchangeScript());
    zip.file("Run-Exchange-Setup.bat", buildBatFile());
    zip.file("Credentials.csv", buildCredentialsCsv());

    const blob = await zip.generateAsync({ type: "blob", compression: "DEFLATE" });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement("a");
    a.href     = url;
    a.download = "NewAccountsSetup-" + new Date().toISOString().slice(0, 10) + ".zip";
    a.click();
    URL.revokeObjectURL(url);

    markDone(4, st.created.length + " accounts ready");
    btn.textContent = "Downloaded ✓";
  } catch(e) {
    showErr("s4Err", "ZIP generation failed: " + e.message);
    btn.disabled = false;
    btn.textContent = "Download ZIP";
  }
}
```

- [ ] **Step 4: Wire up goToStep4() from Step 3 Continue button**

In the Step 3 Continue button (already in the HTML as `onclick="gotoStep(4)"`), add a markDone call. Replace the inline onclick with a proper function. Find the Step 3 Continue button in the HTML and change `onclick="gotoStep(4)"` to `onclick="goToStep4()"`, then add:

```javascript
function goToStep4() {
  markDone(3, st.created.length + " created");
  gotoStep(4);
}
```

- [ ] **Step 5: Verify ZIP download in browser**

After completing a test creation run, advance to Step 4. Click Download ZIP. Verify:
- ZIP downloads with correct filename (`NewAccountsSetup-YYYY-MM-DD.zip`)
- Extract and inspect contents:
  - `Exchange-Setup.ps1` — opens in editor, shows correct user array, correct region, correct operations
  - `Run-Exchange-Setup.bat` — opens in editor, shows correct user count and date
  - `Credentials.csv` — opens in Excel/Notepad, shows DisplayName, UPN, TempPassword for each created user
- Passwords in credentials CSV are 16 chars with mixed character types

- [ ] **Step 6: Commit**

```bash
git add tools/user-creation/index.html
git commit -m "feat: user-creation step 4 — ZIP generation with Exchange script, bat launcher, credentials CSV"
```

---

### Task 8: Navigation polish, sidebar done states, push to testing and main

**Files:**
- Modify: `tools/user-creation/index.html` — wire sidebar click guards, final sidebar subtitle updates
- Modify: `config.json` — already done in Task 1

- [ ] **Step 1: Add click guards to sidebar navigation**

Replace the empty `gotoStep()` function with a guarded version:

```javascript
function gotoStep(n) {
  // Guard: can't jump ahead past completed steps
  if (n >= 2 && st.rows.length === 0)   return;
  if (n >= 3 && st.created.length === 0 && n > 3) return;
  [1,2,3,4].forEach(i => {
    document.getElementById("step"+i).classList.toggle("active", i===n);
    document.getElementById("nav"+i).classList.toggle("active",  i===n);
  });
}
```

- [ ] **Step 2: Final end-to-end walkthrough**

Complete a full run using the NewAccountsTemplate.csv against a sandbox tenant:
1. Upload CSV → verify 13 rows, UPN checks run
2. Review table → apply bulk F3 license → verify all rows update
3. Create accounts → verify progress rows complete for all ready rows
4. Download ZIP → extract and inspect all 3 files

- [ ] **Step 3: Push testing branch, then merge to main**

```bash
git push origin testing
git checkout main
git merge testing --no-edit
git push origin main
git checkout testing
```

- [ ] **Step 4: Commit memory and Obsidian note placeholder**

Update memory with status. Create Obsidian stub at `C:\dev\notes\Projects\IT Tools Hub\Tools\User Creation.md` with the spec summary and plan path for team review reference.

---

## Self-Review Against Spec

| Spec requirement | Task |
|---|---|
| 4-step wizard with sidebar | Task 1 |
| CSV file drop zone with AV timeout | Task 2 |
| Validate 13 required columns | Task 2 |
| UPN format validation | Task 2 |
| UPN existence check via Graph | Task 3 |
| Region toggle (India/US) | Task 4 |
| Validation summary bar | Task 4 |
| Per-row license/apps/subcontractor | Task 4 |
| Bulk settings bar with confirmation modal | Task 5 |
| Continue button gated on zero errors | Task 4 |
| SKU fetch once before loop | Task 6 |
| New-MgUser via Graph POST /users | Task 6 |
| assignLicense via Graph POST /users/{id}/assignLicense | Task 6 |
| Security group membership via Graph | Task 6 |
| Per-user live progress rows | Task 6 |
| Failure isolation (one failure doesn't stop loop) | Task 6 |
| Per-user crypto password generation | Task 6 |
| Exchange-Setup.ps1 with user array | Task 7 |
| Run-Exchange-Setup.bat with %~dp0 | Task 7 |
| Credentials.csv with per-user passwords | Task 7 |
| JSZip client-side ZIP generation | Task 7 |
| Single ZIP download button | Task 7 |
| config.json entry | Task 1 |
| JSZip vendored | Task 1 |
| Passwords via crypto.getRandomValues() | Task 6 |
| Strict creation only (no updates) | Throughout — no update path exists |
