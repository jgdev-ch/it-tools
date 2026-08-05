# Account Lockdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build "Account Lockdown," a new Security-category hub tool that lets a gated IT/Security tech search for or bulk-paste one or more compromised accounts, review them, type-to-confirm, then run a single Lockdown action (revoke sessions, reset password, reset MFA, block sign-in) against each — with per-account/per-action results, scoped retry on failure, and a CSV export of outcomes and temp passwords.

**Architecture:** Pure static HTML/CSS/JS, matching every other tool in this hub — no build step, no backend, no test framework. The tool is a single new file, `tools/security-lockdown/index.html`, following the existing 3-step-wizard skeleton (`gotoStep`/`markDone`/`.step-item`/`.section`, copied from `tools/user-creation/index.html`), the existing `ITTools.graph`/`ITTools.auth` wrappers from `shared/auth.js`, and the existing per-tool group-gate pattern (`checkFinanceAccess`-style, copied from `tools/finance-dashboard/index.html`). Three existing files get small, additive wiring changes: `config.json` (new tool entry), `index.html` (new accent color, new category, new gate), and `shared/auth.js` + `shared/styles.css` (new pill color).

**Tech Stack:** Static HTML/CSS/JS, Microsoft Graph v1.0 REST API via `fetch`, MSAL.js (already loaded hub-wide). Verification per task is a Node syntax-check of the tool's inline `<script>` block (`node -e "..."`, the existing convention in this repo) plus manual sign-in verification in a real browser; there is no unit test framework in this codebase. Pure logic (password generation, MFA method-type mapping, CSV row shaping) is written as standalone functions and verified with quick `node -e` assertions before being wired into the DOM, since that's the closest equivalent to TDD this codebase's tooling supports.

---

### Task 1: Create the Entra security group (manual, no code)

**Files:** none — this is an Entra admin center action, not a code change.

- [ ] **Step 1: Create the group**

In the Entra admin center (as discussed, Josh will do this): create a new Security group named `SG-IT-Tools-Security-Lockdown`. Add both IT/help-desk and Security/InfoSec team members who should have access.

- [ ] **Step 2: Record the group's Object ID**

Copy the group's Object ID (a GUID, e.g. `a1b2c3d4-5678-90ab-cdef-1234567890ab`) from the group's Overview page. This value is referenced as `REPLACE_WITH_SECURITY_GROUP_OBJECT_ID` in Tasks 3 and 4 below — replace every occurrence with the real GUID before those tasks are considered done. Do not proceed to Task 3 until this ID exists; the gate literally cannot function without it.

---

### Task 2: Add the shared "Security Access" pill color

**Files:**
- Modify: `shared/styles.css:261-266` (the `.account-pill--*` block)
- Modify: `index.html` (the hub's own duplicate `.account-pill--*` block, same content as `shared/styles.css:192-197`)
- Modify: `shared/auth.js:246-267` (`PILL_DEFS` — drives the pill shown on every *other* tool's topbar dropdown)

- [ ] **Step 1: Add the CSS class to `shared/styles.css`**

Find (`shared/styles.css:261-266`):
```css
.account-pill--green { background: rgba(4,120,87,.10);  border: 1px solid rgba(4,120,87,.22);  color: var(--green); }
.account-pill--amber { background: rgba(146,64,14,.10); border: 1px solid rgba(146,64,14,.22); color: var(--amber); }
.account-pill--blue  { background: rgba(26,86,219,.10); border: 1px solid rgba(26,86,219,.20); color: var(--blue);  }
[data-theme="dark"] .account-pill--green { background: rgba(52,199,111,.12); border-color: rgba(52,199,111,.25); }
[data-theme="dark"] .account-pill--amber { background: rgba(226,161,61,.12); border-color: rgba(226,161,61,.25);  }
[data-theme="dark"] .account-pill--blue  { background: rgba(76,141,255,.12); border-color: rgba(76,141,255,.25);  }
```

Replace with (adds a `--slate` variant using the same `#5b6472`-family tone as the new `--accent-slate` hub accent):
```css
.account-pill--green { background: rgba(4,120,87,.10);  border: 1px solid rgba(4,120,87,.22);  color: var(--green); }
.account-pill--amber { background: rgba(146,64,14,.10); border: 1px solid rgba(146,64,14,.22); color: var(--amber); }
.account-pill--blue  { background: rgba(26,86,219,.10); border: 1px solid rgba(26,86,219,.20); color: var(--blue);  }
.account-pill--slate { background: rgba(91,100,114,.12); border: 1px solid rgba(91,100,114,.28); color: #5b6472;  }
[data-theme="dark"] .account-pill--green { background: rgba(52,199,111,.12); border-color: rgba(52,199,111,.25); }
[data-theme="dark"] .account-pill--amber { background: rgba(226,161,61,.12); border-color: rgba(226,161,61,.25);  }
[data-theme="dark"] .account-pill--blue  { background: rgba(76,141,255,.12); border-color: rgba(76,141,255,.25);  }
[data-theme="dark"] .account-pill--slate { background: rgba(148,158,174,.16); border-color: rgba(148,158,174,.32); color: #b0b8c4; }
```

- [ ] **Step 2: Mirror the same change in `index.html`**

`index.html` has its own duplicate copy of this exact block (same selectors, same values) — find it and apply the identical edit from Step 1 to it.

- [ ] **Step 3: Add the `security` entry to `PILL_DEFS` in `shared/auth.js`**

Find (`shared/auth.js:262-266`):
```js
    "license-modify": {
      label: "License Admin",
      cls:   "account-pill--amber",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/></svg>`,
    },
  };
```

Replace with:
```js
    "license-modify": {
      label: "License Admin",
      cls:   "account-pill--amber",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/></svg>`,
    },
    "security": {
      label: "Security Access",
      cls:   "account-pill--slate",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`,
    },
  };
```

- [ ] **Step 4: Verify no syntax errors**

Run:
```bash
node -e "const fs=require('fs');new Function(fs.readFileSync('shared/auth.js','utf8'));console.log('OK')"
```
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add shared/styles.css shared/auth.js index.html
git commit -m "Add Security Access pill color (slate) alongside existing gate pills"
```

---

### Task 3: Wire the new gate, category, and accent color into the hub

**Files:**
- Modify: `index.html` (`GROUP_GATES` object, `SECTIONS` array, `:root` accent variables, `cardHtml()`, `renderAccountDropdown()`'s local `PILL_DEFS`)

- [ ] **Step 1: Add the new accent color**

Find the `:root` block containing the existing accent variables (includes `--accent-teal`, `--accent-rose`, `--accent-magenta`, `--accent-olive`):
```css
  --accent-teal:    #258990;
  --accent-rose:    #b34f70;
  --accent-magenta: #a25099;
  --accent-olive:   #80872d;
```
Replace with:
```css
  --accent-teal:    #258990;
  --accent-rose:    #b34f70;
  --accent-magenta: #a25099;
  --accent-olive:   #80872d;
  --accent-slate:   #5b6472;
```

- [ ] **Step 2: Add the `security` gate**

Find (`index.html:629-646`):
```js
const GROUP_GATES = {
  "finance": {
    id:       "ff9c3232-251f-4570-9564-340039d17aa9",
    localKey: "it-tools-finance-unlocked",
  },
  "reporting": {
    id:       "cea8f0fe-a3d5-4f8a-9f77-e9ce6fdf7b8d",
    localKey: "it-tools-reporting-unlocked",
  },
  "gsd": {
    id:       "3e1a4757-8189-4908-a611-b6029399e69e",
    localKey: "it-tools-gsd-unlocked",
  },
  "license-modify": {
    id:       "d98cbaa9-da66-4d1a-8a31-2442b7cc0ca8",
    localKey: "it-tools-license-modify-unlocked",
  },
};
```
Replace with (substitute the real GUID from Task 1 for `REPLACE_WITH_SECURITY_GROUP_OBJECT_ID`):
```js
const GROUP_GATES = {
  "finance": {
    id:       "ff9c3232-251f-4570-9564-340039d17aa9",
    localKey: "it-tools-finance-unlocked",
  },
  "reporting": {
    id:       "cea8f0fe-a3d5-4f8a-9f77-e9ce6fdf7b8d",
    localKey: "it-tools-reporting-unlocked",
  },
  "gsd": {
    id:       "3e1a4757-8189-4908-a611-b6029399e69e",
    localKey: "it-tools-gsd-unlocked",
  },
  "license-modify": {
    id:       "d98cbaa9-da66-4d1a-8a31-2442b7cc0ca8",
    localKey: "it-tools-license-modify-unlocked",
  },
  "security": {
    id:       "REPLACE_WITH_SECURITY_GROUP_OBJECT_ID",
    localKey: "it-tools-security-unlocked",
  },
};
```

- [ ] **Step 3: Add the `security` category**

Find (`index.html:949-952`):
```js
const SECTIONS = [
  { key: "daily-ops",       label: "Daily Operations" },
  { key: "reporting-audit", label: "Reporting & Audit" },
];
```
Replace with:
```js
const SECTIONS = [
  { key: "daily-ops",       label: "Daily Operations" },
  { key: "reporting-audit", label: "Reporting & Audit" },
  { key: "security",        label: "Security" },
];
```

- [ ] **Step 4: Add the `securityOnly` branch to `cardHtml()`**

Find (`index.html:960-979`):
```js
    function cardHtml(tool) {
      if (tool.financeOnly) {
        const meta = {
          path: tool.path, accent: tool.accent, icon: tool.icon,
          status: tool.status, name: tool.name, desc: tool.description,
        };
        if (!_gateCardMeta["finance"]) _gateCardMeta["finance"] = [];
        _gateCardMeta["finance"].push(meta);
        return buildLockedCard({ gateKey: "finance", ...meta });
      }

      if (tool.reportingOnly) {
        const meta = {
          path: tool.path, accent: tool.accent, icon: tool.icon,
          status: tool.status, name: tool.name, desc: tool.description,
        };
        if (!_gateCardMeta["reporting"]) _gateCardMeta["reporting"] = [];
        _gateCardMeta["reporting"].push(meta);
        return buildLockedCard({ gateKey: "reporting", ...meta });
      }
```
Replace with:
```js
    function cardHtml(tool) {
      if (tool.financeOnly) {
        const meta = {
          path: tool.path, accent: tool.accent, icon: tool.icon,
          status: tool.status, name: tool.name, desc: tool.description,
        };
        if (!_gateCardMeta["finance"]) _gateCardMeta["finance"] = [];
        _gateCardMeta["finance"].push(meta);
        return buildLockedCard({ gateKey: "finance", ...meta });
      }

      if (tool.reportingOnly) {
        const meta = {
          path: tool.path, accent: tool.accent, icon: tool.icon,
          status: tool.status, name: tool.name, desc: tool.description,
        };
        if (!_gateCardMeta["reporting"]) _gateCardMeta["reporting"] = [];
        _gateCardMeta["reporting"].push(meta);
        return buildLockedCard({ gateKey: "reporting", ...meta });
      }

      if (tool.securityOnly) {
        const meta = {
          path: tool.path, accent: tool.accent, icon: tool.icon,
          status: tool.status, name: tool.name, desc: tool.description,
        };
        if (!_gateCardMeta["security"]) _gateCardMeta["security"] = [];
        _gateCardMeta["security"].push(meta);
        return buildLockedCard({ gateKey: "security", ...meta });
      }
```

- [ ] **Step 5: Add the `security` pill to `renderAccountDropdown()`'s local `PILL_DEFS`**

`index.html`'s `renderAccountDropdown()` function (`index.html:817-839`) has its own local copy of `PILL_DEFS`, identical in shape to the one just edited in `shared/auth.js` in Task 2. Find the same `"license-modify": { ... }` entry inside this function and add the identical `"security": { ... }` entry immediately after it (same label, cls, and icon as Task 2 Step 3).

- [ ] **Step 6: Verify no syntax errors**

Run:
```bash
node -e "const fs=require('fs');const html=fs.readFileSync('index.html','utf8');const scripts=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);for(const s of scripts)new Function(s);console.log('OK')"
```
Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add index.html
git commit -m "Wire security gate, category, and accent color into the hub"
```

---

### Task 4: Add the `config.json` entry

**Files:**
- Modify: `config.json`

- [ ] **Step 1: Add the tool entry**

Find the closing of the `adobe-license-monitor` entry (`config.json:96-105`, the last entry in the `tools` array):
```json
    {
      "id": "adobe-license-monitor",
      "name": "Adobe License Monitor",
      "description": "Live Adobe seat utilization and Entra group sync status, showing purchased vs assigned seats across all Adobe products.",
      "icon": "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='#9a0000' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='m9 10 2 2 4-4'/><rect width='20' height='14' x='2' y='3' rx='2'/><path d='M12 17v4'/><path d='M8 21h8'/></svg>",
      "status": "live",
      "path": "tools/adobe-license-monitor/",
      "permissions": ["User.Read", "GroupMember.Read.All"],
      "accent": "var(--accent-red)",
      "category": "reporting-audit"
    }
  ]
}
```
Replace with:
```json
    {
      "id": "adobe-license-monitor",
      "name": "Adobe License Monitor",
      "description": "Live Adobe seat utilization and Entra group sync status, showing purchased vs assigned seats across all Adobe products.",
      "icon": "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='#9a0000' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='m9 10 2 2 4-4'/><rect width='20' height='14' x='2' y='3' rx='2'/><path d='M12 17v4'/><path d='M8 21h8'/></svg>",
      "status": "live",
      "path": "tools/adobe-license-monitor/",
      "permissions": ["User.Read", "GroupMember.Read.All"],
      "accent": "var(--accent-red)",
      "category": "reporting-audit"
    },
    {
      "id": "security-lockdown",
      "name": "Account Lockdown",
      "description": "Revoke sessions, reset password and MFA, and block sign-in for one or more compromised accounts during a security incident.",
      "icon": "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='#5b6472' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='3' y='11' width='18' height='11' rx='2' ry='2'/><path d='M7 11V7a5 5 0 0 1 10 0v4'/></svg>",
      "status": "beta",
      "path": "tools/security-lockdown/",
      "permissions": ["User.Read.All", "User.ReadWrite.All", "UserAuthenticationMethod.ReadWrite.All"],
      "accent": "var(--accent-slate)",
      "category": "security",
      "securityOnly": true
    }
  ]
}
```

- [ ] **Step 2: Verify valid JSON**

Run:
```bash
node -e "const c=JSON.parse(require('fs').readFileSync('config.json','utf8')); console.log(c.tools.find(t=>t.id==='security-lockdown'))"
```
Expected: prints the new tool object with no errors.

- [ ] **Step 3: Commit**

```bash
git add config.json
git commit -m "Add Account Lockdown tool entry to config.json"
```

---

### Task 5: Scaffold the tool page (auth, gate, empty wizard shell)

**Files:**
- Create: `tools/security-lockdown/index.html`

- [ ] **Step 1: Create the file with the full skeleton**

Write the following complete file. This gives every later task a stable set of marker comments (`<!-- TASKn: ... -->` / `/* TASKn: ... */`) to anchor their edits against, so line-number drift across tasks doesn't matter.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Account Lockdown: IT Tools</title>
<script src="../../shared/msal-browser.min.js"></script>
<link rel="stylesheet" href="../../shared/styles.css"/>
<style>
  /* TASK6: wizard chrome + step indicator CSS goes here */
  /* TASK7: step 1 (add accounts) CSS goes here */
  /* TASK9: step 2 (review & confirm) CSS goes here */
  /* TASK11: step 3 (results) CSS goes here */
</style>
</head>
<body>

<div id="topbar"></div>

<div id="authScreen" class="auth-screen">
  <div class="auth-card">
    <h1>Account Lockdown</h1>
    <p>Sign in with your Microsoft account to continue.</p>
    <button class="btn btn-primary" onclick="doSignIn()">Sign in with Microsoft</button>
    <div id="authErr" class="banner error" style="display:none"></div>
    <p style="font-size:12px;color:var(--muted);margin-top:12px">
      Requires <strong>User.Read.All</strong>, <strong>User.ReadWrite.All</strong>, and
      <strong>UserAuthenticationMethod.ReadWrite.All</strong>.
    </p>
  </div>
</div>

<div id="accessDeniedScreen" class="auth-screen" style="display:none">
  <div class="auth-card">
    <h2>Access Restricted</h2>
    <p>This tool is restricted to IT and Security team members with lockdown access. Contact your IT administrator to request access.</p>
    <a href="../../" class="btn btn-ghost" style="display:inline-flex">&larr; Back to hub</a>
  </div>
</div>

<div id="appScreen" style="display:none">
  <div class="shell">

    <!-- TASK6: wizard header + step indicator markup goes here -->

    <div class="section active" id="step1">
      <!-- TASK7/TASK8: search-and-add, paste/CSV add, and queue table go here -->
    </div>

    <div class="section" id="step2">
      <!-- TASK9: review list + type-to-confirm goes here -->
    </div>

    <div class="section" id="step3">
      <!-- TASK11/TASK12: results table + CSV export go here -->
    </div>

  </div>
</div>

<script src="../../shared/auth.js"></script>
<script>
const TOOL_SCOPES = ["User.Read.All", "User.ReadWrite.All", "UserAuthenticationMethod.ReadWrite.All"];
const SECURITY_GROUP_ID = "REPLACE_WITH_SECURITY_GROUP_OBJECT_ID";

const st = {
  queue:   [],   // { id, displayName, upn } — accounts pending lockdown
  results: [],   // { id, displayName, upn, actions: {...}, tempPassword } — after execution
};

async function checkSecurityAccess() {
  try {
    const token = await ITTools.auth.getToken();
    const res   = await fetch(
      "https://graph.microsoft.com/v1.0/me/checkMemberObjects",
      {
        method:  "POST",
        headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
        body:    JSON.stringify({ ids: [SECURITY_GROUP_ID] }),
      }
    );
    if (!res.ok) return false;
    const data = await res.json();
    return (data.value || []).includes(SECURITY_GROUP_ID);
  } catch(_) { return false; }
}

function gotoStep(n) {
  [1,2,3].forEach(i => {
    document.getElementById("step"+i).classList.toggle("active", i===n);
    const nav = document.getElementById("nav"+i);
    if (nav) nav.classList.toggle("active", i===n);
  });
}

function markDone(n, subtitle) {
  const nav = document.getElementById("nav"+n);
  if (!nav) return;
  nav.classList.remove("active");
  nav.classList.add("done");
  const sub = document.getElementById("sub"+n);
  if (subtitle && sub) sub.textContent = subtitle;
}

async function doSignIn() {
  try {
    const acct = await ITTools.auth.signIn();
    document.getElementById("authScreen").style.display = "none";
    ITTools.ui.setUser(acct);
    const ok = await checkSecurityAccess();
    if (!ok) { document.getElementById("accessDeniedScreen").style.display = "flex"; return; }
    document.getElementById("appScreen").style.display = "block";
  } catch(e) {
    const el = document.getElementById("authErr");
    el.textContent = e.message; el.style.display = "block";
  }
}

async function init() {
  ITTools.theme.init();
  ITTools.ui.renderTopbar({ toolName: "Account Lockdown", hubRelPath: "../../", status: "beta" });
  ITTools.ui.syncThemeIcon();

  let _sessionFound = false;
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: async acct => {
      _sessionFound = true;
      document.getElementById("authScreen").style.display = "none";
      ITTools.ui.setUser(acct);
      const ok = await checkSecurityAccess();
      if (!ok) { document.getElementById("accessDeniedScreen").style.display = "flex"; return; }
      document.getElementById("appScreen").style.display = "block";
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display = "none";
      document.getElementById("accessDeniedScreen").style.display = "none";
      document.getElementById("authScreen").style.display = "flex";
    },
  });
  if (!_sessionFound) {
    document.getElementById("authScreen").style.display = "flex";
  }
}

init();
</script>
</body>
</html>
```

- [ ] **Step 2: Verify no syntax errors**

Run:
```bash
node -e "const fs=require('fs');const html=fs.readFileSync('tools/security-lockdown/index.html','utf8');const scripts=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);for(const s of scripts)new Function(s);console.log('OK')"
```
Expected: `OK` (there are three `<script>` tags total — the MSAL and `shared/auth.js` `src` tags match too, but capture empty content, so `new Function("")` on them is a trivial no-op; only the final inline block has real content to check, and this command never calls the constructed functions, only builds them, so the unconditional `init();` at the bottom never executes here).

- [ ] **Step 3: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Scaffold Account Lockdown tool page: auth, gate, empty 3-step shell"
```

---

### Task 6: Build the dark-glass wizard header and step indicator

**Files:**
- Modify: `tools/security-lockdown/index.html` (the `/* TASK6 */` CSS marker and the header/step-indicator HTML marker)

- [ ] **Step 1: Add the header + step indicator CSS**

Find:
```css
  /* TASK6: wizard chrome + step indicator CSS goes here */
```
Replace with:
```css
  /* ── Restricted-access header: dark glass, same in light and dark theme ── */
  .lockdown-header {
    background:
      linear-gradient(160deg, rgba(255,255,255,.08), rgba(255,255,255,.02)),
      #1c1f26;
    border: 1px solid rgba(255,255,255,.14);
    border-radius: 22px;
    padding: 20px 24px;
    backdrop-filter: blur(16px) saturate(140%);
    box-shadow: 0 8px 24px rgba(0,0,0,.25);
    margin-bottom: 20px;
  }
  .lockdown-badge {
    display: flex; align-items: center; gap: 7px;
    font-size: 11px; font-weight: 700; letter-spacing: .5px;
    color: #c9cdd6; text-transform: uppercase;
  }
  .lockdown-badge svg { flex-shrink: 0; }
  .lockdown-title { margin-top: 8px; font-size: 18px; font-weight: 700; color: #fff; }
  .lockdown-steps { display: flex; gap: 8px; margin-top: 14px; font-size: 11px; }
  .lockdown-step {
    background: rgba(255,255,255,.14); color: #fff;
    padding: 6px 12px; border-radius: 20px; font-weight: 600; opacity: .4;
  }
  .lockdown-step.active { opacity: 1; }
  .lockdown-step.done   { opacity: .7; }
  .shell { max-width: 760px; margin: 0 auto; padding: 24px 16px; }
  .section { display: none; }
  .section.active { display: block; }
```

- [ ] **Step 2: Add the header + step indicator markup**

Find:
```html
    <!-- TASK6: wizard header + step indicator markup goes here -->
```
Replace with:
```html
    <div class="lockdown-header">
      <div class="lockdown-badge">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#e2a13d" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
        Restricted Access
      </div>
      <div class="lockdown-title">Account Lockdown</div>
      <div class="lockdown-steps">
        <div class="lockdown-step active" id="nav1">1&nbsp; Add Accounts</div>
        <div class="lockdown-step" id="nav2">2&nbsp; Review &amp; Confirm</div>
        <div class="lockdown-step" id="nav3">3&nbsp; Results</div>
      </div>
    </div>
```

- [ ] **Step 3: Verify no syntax errors**

Run the same Node check as Task 5 Step 2, pointed at `tools/security-lockdown/index.html`. Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add dark-glass wizard header and step indicator to Account Lockdown"
```

---

### Task 7: Step 1 — search-and-add

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Add Step 1 CSS**

Find:
```css
  /* TASK7: step 1 (add accounts) CSS goes here */
```
Replace with:
```css
  .add-methods    { display: flex; gap: 20px; margin-bottom: 16px; }
  .add-search     { flex: 1; }
  .cand-row       { display: flex; align-items: center; gap: 10px; padding: 8px 10px; border: 1px solid var(--border); border-radius: 8px; margin-top: 6px; cursor: pointer; }
  .cand-row:hover { background: var(--surface2); }
  .cand-name      { font-size: 13px; font-weight: 600; }
  .cand-meta      { font-size: 11px; color: var(--muted); }
  .queue-table    { width: 100%; border-collapse: collapse; margin-top: 16px; font-size: 13px; }
  .queue-table th, .queue-table td { padding: 8px 10px; text-align: left; border-bottom: 1px solid var(--border); }
  .queue-remove   { color: var(--red); cursor: pointer; background: none; border: none; font-size: 12px; font-weight: 600; }
```

- [ ] **Step 2: Add the search-and-add markup and queue table to Step 1**

Find:
```html
    <div class="section active" id="step1">
      <!-- TASK7/TASK8: search-and-add, paste/CSV add, and queue table go here -->
    </div>
```
Replace with:
```html
    <div class="section active" id="step1">
      <h2>Add Accounts</h2>
      <p class="subtitle">Search by name or UPN, or paste/upload a list below. Build the full list before continuing.</p>

      <div class="add-methods">
        <div class="add-search">
          <input type="text" id="searchInput" class="input" placeholder="Search by name or UPN&hellip;" onkeydown="if(event.key==='Enter')doSearch()">
          <button class="btn btn-secondary" onclick="doSearch()" style="margin-top:8px">Search</button>
          <div id="searchResults"></div>
        </div>
      </div>

      <div id="bulkAddSection">
        <!-- TASK8: paste/CSV bulk-add UI goes here -->
      </div>

      <table class="queue-table" id="queueTable" style="display:none">
        <thead><tr><th>Name</th><th>UPN</th><th></th></tr></thead>
        <tbody id="queueBody"></tbody>
      </table>
      <div id="queueEmpty" style="font-size:12px;color:var(--muted);margin-top:10px">No accounts added yet.</div>

      <button class="btn btn-primary" id="step1ContinueBtn" style="margin-top:20px" disabled onclick="goToStep2()">Continue &rarr;</button>
    </div>
```

- [ ] **Step 3: Add the search/lookup and queue-management JS**

Find (inside the main `<script>` block, right after the `st` object declaration):
```js
const st = {
  queue:   [],   // { id, displayName, upn } — accounts pending lockdown
  results: [],   // { id, displayName, upn, actions: {...}, tempPassword } — after execution
};
```
Replace with:
```js
const st = {
  queue:   [],   // { id, displayName, upn } — accounts pending lockdown
  results: [],   // { id, displayName, upn, actions: {...}, tempPassword } — after execution
};

function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, c => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
}

function addToQueue(account) {
  if (st.queue.some(a => a.id === account.id)) return;
  st.queue.push({ id: account.id, displayName: account.displayName, upn: account.userPrincipalName });
  renderQueue();
}

function removeFromQueue(id) {
  st.queue = st.queue.filter(a => a.id !== id);
  renderQueue();
}

function renderQueue() {
  const table = document.getElementById("queueTable");
  const body  = document.getElementById("queueBody");
  const empty = document.getElementById("queueEmpty");
  const cont  = document.getElementById("step1ContinueBtn");

  if (!st.queue.length) {
    table.style.display = "none";
    empty.style.display = "block";
    cont.disabled = true;
    return;
  }
  table.style.display = "table";
  empty.style.display = "none";
  cont.disabled = false;
  body.innerHTML = st.queue.map(a => `
    <tr>
      <td>${esc(a.displayName)}</td>
      <td>${esc(a.upn)}</td>
      <td><button class="queue-remove" onclick="removeFromQueue('${a.id}')">Remove</button></td>
    </tr>
  `).join("");
}

async function doSearch() {
  const name = document.getElementById("searchInput").value.trim();
  const resultsEl = document.getElementById("searchResults");
  if (!name) { resultsEl.innerHTML = ""; return; }
  resultsEl.innerHTML = `<p style="font-size:12px;color:var(--muted)">Searching&hellip;</p>`;

  try {
    const token = await ITTools.auth.getToken();
    const searchVal = '"displayName:' + name.replace(/"/g, '') + '" OR "userPrincipalName:' + name.replace(/"/g, '') + '"';
    const res = await fetch(
      "https://graph.microsoft.com/v1.0/users?$search=" + encodeURIComponent(searchVal) +
      "&$top=10&$select=id,displayName,userPrincipalName,department",
      { headers: { Authorization: "Bearer " + token, ConsistencyLevel: "eventual" } }
    );
    if (!res.ok) throw new Error("Search failed (" + res.status + ")");
    const data = await res.json();
    const candidates = data.value || [];

    if (!candidates.length) {
      resultsEl.innerHTML = `<p style="font-size:12px;color:var(--red)">No matches found.</p>`;
      return;
    }
    resultsEl.innerHTML = candidates.map(c => `
      <div class="cand-row" onclick='addCandidateFromJson(this)' data-account='${esc(JSON.stringify(c))}'>
        <div style="flex:1">
          <div class="cand-name">${esc(c.displayName)}</div>
          <div class="cand-meta">${esc(c.userPrincipalName)}${c.department ? " &middot; " + esc(c.department) : ""}</div>
        </div>
        <span style="font-size:11px;font-weight:600;color:var(--blue)">Add</span>
      </div>
    `).join("");
  } catch(e) {
    resultsEl.innerHTML = `<p style="font-size:12px;color:var(--red)">${esc(e.message)}</p>`;
  }
}

function addCandidateFromJson(el) {
  const account = JSON.parse(el.dataset.account);
  addToQueue(account);
  document.getElementById("searchInput").value = "";
  document.getElementById("searchResults").innerHTML = "";
}
```

**Note on the `$search` query:** unlike `tools/name-resolver/index.html` (which searches `displayName` only), this searches both `displayName` and `userPrincipalName` in one query so a tech can paste in an email-looking string or a real name and get a match either way — this is a deliberate difference from the Name Resolver precedent, not an oversight.

- [ ] **Step 4: Verify no syntax errors**

Run the same Node check as Task 5 Step 2. Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add search-and-add lookup and queue management to Account Lockdown Step 1"
```

---

### Task 8: Step 1 — paste/CSV bulk add

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Add the bulk-add markup**

Find:
```html
      <div id="bulkAddSection">
        <!-- TASK8: paste/CSV bulk-add UI goes here -->
      </div>
```
Replace with:
```html
      <div id="bulkAddSection">
        <p class="label" style="margin-top:16px">Or add multiple at once</p>
        <textarea id="bulkInput" class="input" rows="4" placeholder="Paste UPNs or emails, one per line&hellip;"></textarea>
        <div style="display:flex;gap:10px;margin-top:8px;align-items:center">
          <button class="btn btn-secondary" onclick="doBulkAdd()">Resolve &amp; Add</button>
          <span style="font-size:12px;color:var(--muted)">or</span>
          <input type="file" id="bulkFile" accept=".csv,.txt" onchange="handleBulkFile(event)" style="font-size:12px">
        </div>
        <div id="bulkAddStatus" style="font-size:12px;margin-top:8px"></div>
      </div>
```

- [ ] **Step 2: Add the bulk-resolve JS**

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
  document.getElementById("searchInput").value = "";
  document.getElementById("searchResults").innerHTML = "";
}

function handleBulkFile(e) {
  const file = e.target.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    document.getElementById("bulkInput").value = reader.result;
    doBulkAdd();
  };
  reader.readAsText(file);
}

async function doBulkAdd() {
  const raw = document.getElementById("bulkInput").value;
  const lines = raw.split(/[\r\n,]+/).map(s => s.trim()).filter(Boolean);
  const statusEl = document.getElementById("bulkAddStatus");
  if (!lines.length) return;

  statusEl.textContent = `Resolving ${lines.length} account(s)&hellip;`;
  let added = 0, notFound = [];

  for (const upn of lines) {
    try {
      const account = await ITTools.graph.get(
        `/users/${encodeURIComponent(upn)}?$select=id,displayName,userPrincipalName`
      );
      addToQueue(account);
      added++;
    } catch(_) {
      notFound.push(upn);
    }
  }

  statusEl.innerHTML = `Added ${added} of ${lines.length}.` +
    (notFound.length ? ` Not found: ${notFound.map(esc).join(", ")}` : "");
  document.getElementById("bulkInput").value = "";
}
```

- [ ] **Step 3: Verify no syntax errors**

Run the same Node check as Task 5 Step 2. Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add paste/CSV bulk-add to Account Lockdown Step 1"
```

---

### Task 9: Step 2 — review & type-to-confirm

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Add Step 2 CSS**

Find:
```css
  /* TASK9: step 2 (review & confirm) CSS goes here */
```
Replace with:
```css
  .review-table    { width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 13px; }
  .review-table th, .review-table td { padding: 8px 10px; text-align: left; border-bottom: 1px solid var(--border); }
  .confirm-input   { font-family: monospace; letter-spacing: 2px; text-transform: uppercase; }
  .confirm-warning { background: var(--red-light); border: 1px solid var(--red-border); border-radius: 10px; padding: 12px 14px; font-size: 13px; margin-bottom: 16px; }
```

- [ ] **Step 2: Add the review + confirm markup**

Find:
```html
    <div class="section" id="step2">
      <!-- TASK9: review list + type-to-confirm goes here -->
    </div>
```
Replace with:
```html
    <div class="section" id="step2">
      <h2>Review &amp; Confirm</h2>
      <div class="confirm-warning">
        This will revoke sessions, reset the password, reset MFA, and block sign-in for every account below. This cannot be undone from this tool.
      </div>
      <table class="review-table">
        <thead><tr><th>Name</th><th>UPN</th></tr></thead>
        <tbody id="reviewBody"></tbody>
      </table>
      <p class="label">Type <strong>LOCKDOWN</strong> to enable the button below</p>
      <input type="text" id="confirmInput" class="input confirm-input" placeholder="LOCKDOWN" oninput="checkConfirmText()">
      <div style="display:flex;gap:10px;margin-top:16px">
        <button class="btn btn-ghost" onclick="gotoStep(1)">&larr; Back</button>
        <button class="btn btn-danger" id="executeBtn" disabled onclick="executeLockdown()">Lock Down <span id="executeCount">0</span> Account(s)</button>
      </div>
    </div>
```

- [ ] **Step 3: Add the step-2 JS**

Find:
```js
function addCandidateFromJson(el) {
```
Insert immediately before it:
```js
function goToStep2() {
  if (!st.queue.length) return;
  document.getElementById("reviewBody").innerHTML = st.queue.map(a => `
    <tr><td>${esc(a.displayName)}</td><td>${esc(a.upn)}</td></tr>
  `).join("");
  document.getElementById("executeCount").textContent = st.queue.length;
  document.getElementById("confirmInput").value = "";
  document.getElementById("executeBtn").disabled = true;
  markDone(1, `${st.queue.length} account(s) added`);
  gotoStep(2);
}

function checkConfirmText() {
  const val = document.getElementById("confirmInput").value.trim();
  document.getElementById("executeBtn").disabled = (val !== "LOCKDOWN");
}

```

- [ ] **Step 4: Verify no syntax errors**

Run the same Node check as Task 5 Step 2. Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add Step 2 review table and LOCKDOWN type-to-confirm gate"
```

---

### Task 10: Password generator (pure function, verified standalone)

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Write the generator function**

Find:
```js
function esc(s) {
```
Insert immediately before it:
```js
// Avoids visually ambiguous characters (0/O, 1/l/I) since a tech may need to
// read this aloud over the phone when handing it back to the account owner.
function generateTempPassword() {
  const upper = "ABCDEFGHJKMNPQRSTUVWXYZ";
  const lower = "abcdefghjkmnpqrstuvwxyz";
  const digit = "23456789";
  const symbol = "!@#$%^&*-_=+";
  const all = upper + lower + digit + symbol;
  const pick = set => set[Math.floor(Math.random() * set.length)];

  let pw = [pick(upper), pick(lower), pick(digit), pick(symbol)];
  for (let i = pw.length; i < 16; i++) pw.push(pick(all));
  for (let i = pw.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pw[i], pw[j]] = [pw[j], pw[i]];
  }
  return pw.join("");
}

```

- [ ] **Step 2: Verify the generator meets complexity requirements**

Run:
```bash
node -e "
const fs = require('fs');
const html = fs.readFileSync('tools/security-lockdown/index.html', 'utf8');
// Strip the trailing init() call — it touches ITTools/document, which don't
// exist in Node. Every one of these standalone-logic checks needs this same
// strip since init() unconditionally runs at the bottom of the tool's script.
const script = html.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/)[1].replace(/init\(\);\s*\$/, '');
const fn = new Function(script + '; return generateTempPassword;')();
for (let i = 0; i < 50; i++) {
  const pw = fn();
  if (pw.length !== 16) throw new Error('wrong length: ' + pw);
  if (!/[A-Z]/.test(pw) || !/[a-z]/.test(pw) || !/[0-9]/.test(pw) || !/[!@#\$%\^&\*\-_=\+]/.test(pw)) {
    throw new Error('missing character class: ' + pw);
  }
  if (/[0O1lI]/.test(pw)) throw new Error('contains ambiguous character: ' + pw);
}
console.log('OK: 50 passwords generated, all 16 chars, all classes present, no ambiguous chars');
"
```
Expected: `OK: 50 passwords generated, all 16 chars, all classes present, no ambiguous chars`

- [ ] **Step 3: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add temp password generator for Account Lockdown"
```

---

### Task 11: The lockdown execution engine

**Files:**
- Modify: `tools/security-lockdown/index.html`

This is the core of the tool: given the confirmed queue, run the four actions per account, tracking per-account/per-action status.

- [ ] **Step 1: Add the MFA method-type mapping (pure data, verified standalone)**

Find:
```js
function generateTempPassword() {
```
Insert immediately before it:
```js
// Graph has no single "delete all MFA methods" call — each authentication
// method type has its own delete sub-path. passwordAuthenticationMethod is
// intentionally excluded: it can't be removed this way (it IS the password,
// handled separately by the resetPassword action) and isn't a second factor.
const MFA_METHOD_ENDPOINTS = {
  "#microsoft.graph.phoneAuthenticationMethod":                    "phoneMethods",
  "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod":   "microsoftAuthenticatorMethods",
  "#microsoft.graph.softwareOathAuthenticationMethod":             "softwareOathMethods",
  "#microsoft.graph.fido2AuthenticationMethod":                    "fido2Methods",
  "#microsoft.graph.emailAuthenticationMethod":                    "emailMethods",
  "#microsoft.graph.temporaryAccessPassAuthenticationMethod":      "temporaryAccessPassMethods",
  "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod":  "windowsHelloForBusinessMethods",
};

```

- [ ] **Step 2: Verify the mapping has no typos against a fixed expected set**

Run:
```bash
node -e "
const fs = require('fs');
const html = fs.readFileSync('tools/security-lockdown/index.html', 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/)[1].replace(/init\(\);\s*\$/, '');
const map = new Function(script + '; return MFA_METHOD_ENDPOINTS;')();
const expectedKeys = [
  '#microsoft.graph.phoneAuthenticationMethod',
  '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod',
  '#microsoft.graph.softwareOathAuthenticationMethod',
  '#microsoft.graph.fido2AuthenticationMethod',
  '#microsoft.graph.emailAuthenticationMethod',
  '#microsoft.graph.temporaryAccessPassAuthenticationMethod',
  '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod',
];
const actualKeys = Object.keys(map);
if (actualKeys.length !== expectedKeys.length) throw new Error('key count mismatch');
for (const k of expectedKeys) if (!(k in map)) throw new Error('missing key: ' + k);
console.log('OK: MFA_METHOD_ENDPOINTS has all 7 expected method types');
"
```
Expected: `OK: MFA_METHOD_ENDPOINTS has all 7 expected method types`

- [ ] **Step 3: Add the four per-account action functions and the orchestrator**

Find:
```js
function checkConfirmText() {
  const val = document.getElementById("confirmInput").value.trim();
  document.getElementById("executeBtn").disabled = (val !== "LOCKDOWN");
}

```
Insert immediately after it:
```js
async function actionRevokeSessions(accountId) {
  await ITTools.graph.post(`/users/${accountId}/revokeSignInSessions`, {});
}

async function actionResetPassword(accountId) {
  const password = generateTempPassword();
  await ITTools.graph.patch(`/users/${accountId}`, {
    passwordProfile: { password, forceChangePasswordNextSignIn: true },
  });
  return password;
}

async function actionResetMfa(accountId) {
  const methods = await ITTools.graph.get(`/users/${accountId}/authentication/methods`);
  const list = methods.value || [];
  let removed = 0, skipped = 0;
  for (const m of list) {
    const type = m["@odata.type"];
    if (type === "#microsoft.graph.passwordAuthenticationMethod") { continue; }
    const endpoint = MFA_METHOD_ENDPOINTS[type];
    if (!endpoint) { skipped++; continue; }
    await ITTools.graph.del(`/users/${accountId}/authentication/${endpoint}/${m.id}`);
    removed++;
  }
  return { removed, skipped };
}

async function actionBlockSignIn(accountId) {
  await ITTools.graph.patch(`/users/${accountId}`, { accountEnabled: false });
}

// One (account, action) pair. Called both during the initial run and by
// retry, so retry can target a single failed action without touching the
// others.
async function runAction(account, actionKey) {
  const row = st.results.find(r => r.id === account.id);
  row.actions[actionKey].status = "running";
  renderResults();
  try {
    if (actionKey === "revokeSessions") {
      await actionRevokeSessions(account.id);
    } else if (actionKey === "resetPassword") {
      row.tempPassword = await actionResetPassword(account.id);
    } else if (actionKey === "resetMfa") {
      await actionResetMfa(account.id);
    } else if (actionKey === "blockSignIn") {
      await actionBlockSignIn(account.id);
    }
    row.actions[actionKey].status = "success";
    row.actions[actionKey].error  = null;
  } catch(e) {
    row.actions[actionKey].status = "failed";
    row.actions[actionKey].error  = ITTools.graph.friendlyError(e);
  }
  renderResults();
}

const ACTION_ORDER = ["revokeSessions", "resetPassword", "resetMfa", "blockSignIn"];

async function executeLockdown() {
  document.getElementById("executeBtn").disabled = true;
  st.results = st.queue.map(a => ({
    id: a.id, displayName: a.displayName, upn: a.upn,
    tempPassword: null,
    actions: Object.fromEntries(ACTION_ORDER.map(k => [k, { status: "pending", error: null }])),
  }));
  markDone(2, `${st.queue.length} account(s) confirmed`);
  gotoStep(3);
  renderResults();

  for (const account of st.queue) {
    for (const actionKey of ACTION_ORDER) {
      await runAction(account, actionKey);
    }
  }
}

async function retryFailedActions(accountId) {
  const account = st.queue.find(a => a.id === accountId);
  const row     = st.results.find(r => r.id === accountId);
  const failed  = ACTION_ORDER.filter(k => row.actions[k].status === "failed");
  for (const actionKey of failed) {
    await runAction(account, actionKey);
  }
}

```

- [ ] **Step 4: Verify no syntax errors**

Run the same Node check as Task 5 Step 2. Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add Account Lockdown execution engine: revoke, reset password, reset MFA, block sign-in"
```

---

### Task 12: Step 3 — results table and retry UI

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Add Step 3 CSS**

Find:
```css
  /* TASK11: step 3 (results) CSS goes here */
```
Replace with:
```css
  .results-table   { width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 12px; }
  .results-table th, .results-table td { padding: 8px 8px; text-align: left; border-bottom: 1px solid var(--border); vertical-align: top; }
  .action-status          { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 10px; font-weight: 700; text-transform: uppercase; }
  .action-status--success { background: var(--green-light); color: var(--green); }
  .action-status--failed  { background: var(--red-light);   color: var(--red); }
  .action-status--pending, .action-status--running { background: var(--surface2); color: var(--muted); }
  .overall-badge          { font-size: 11px; font-weight: 700; padding: 3px 9px; border-radius: 12px; }
  .overall-badge--full    { background: var(--green-light); color: var(--green); }
  .overall-badge--partial { background: var(--amber-light); color: var(--amber); }
  .retry-btn { display: inline-flex; align-items: center; gap: 4px; background: none; border: none; color: var(--blue); font-size: 11px; font-weight: 600; cursor: pointer; padding: 0; }
```

- [ ] **Step 2: Add the results markup**

Find:
```html
    <div class="section" id="step3">
      <!-- TASK11/TASK12: results table + CSV export go here -->
    </div>
```
Replace with:
```html
    <div class="section" id="step3">
      <h2>Results</h2>
      <table class="results-table">
        <thead>
          <tr>
            <th>Name</th><th>UPN</th><th>Sessions</th><th>Password</th>
            <th>MFA</th><th>Sign-In</th><th>Overall</th><th></th>
          </tr>
        </thead>
        <tbody id="resultsBody"></tbody>
      </table>
      <button class="btn btn-secondary" id="csvExportBtn" disabled onclick="exportResultsCsv()">Download Results CSV</button>
    </div>
```

- [ ] **Step 3: Add the results-rendering JS**

Find:
```js
async function retryFailedActions(accountId) {
  const account = st.queue.find(a => a.id === accountId);
  const row     = st.results.find(r => r.id === accountId);
  const failed  = ACTION_ORDER.filter(k => row.actions[k].status === "failed");
  for (const actionKey of failed) {
    await runAction(account, actionKey);
  }
}

```
Insert immediately after it:
```js
function statusBadge(action) {
  return `<span class="action-status action-status--${action.status}">${action.status}</span>` +
    (action.error ? `<div style="font-size:10px;color:var(--red);margin-top:2px">${esc(action.error)}</div>` : "");
}

function renderResults() {
  const body = document.getElementById("resultsBody");
  body.innerHTML = st.results.map(row => {
    const allDone   = ACTION_ORDER.every(k => row.actions[k].status === "success" || row.actions[k].status === "failed");
    const anyFailed = ACTION_ORDER.some(k => row.actions[k].status === "failed");
    const overall   = !allDone ? "" :
      anyFailed
        ? `<span class="overall-badge overall-badge--partial">Partial &mdash; needs attention</span>`
        : `<span class="overall-badge overall-badge--full">Fully locked down</span>`;
    const retry = (allDone && anyFailed)
      ? `<button class="retry-btn" onclick="retryFailedActions('${row.id}')">&#8635; Retry failed actions</button>`
      : "";
    return `<tr>
      <td>${esc(row.displayName)}</td>
      <td>${esc(row.upn)}</td>
      <td>${statusBadge(row.actions.revokeSessions)}</td>
      <td>${statusBadge(row.actions.resetPassword)}</td>
      <td>${statusBadge(row.actions.resetMfa)}</td>
      <td>${statusBadge(row.actions.blockSignIn)}</td>
      <td>${overall}</td>
      <td>${retry}</td>
    </tr>`;
  }).join("");

  const allAccountsDone = st.results.length > 0 &&
    st.results.every(row => ACTION_ORDER.every(k => row.actions[k].status === "success" || row.actions[k].status === "failed"));
  document.getElementById("csvExportBtn").disabled = !allAccountsDone;
}

```

- [ ] **Step 4: Verify no syntax errors**

Run the same Node check as Task 5 Step 2. Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add Account Lockdown Step 3 results table with scoped retry"
```

---

### Task 13: CSV export of results

**Files:**
- Modify: `tools/security-lockdown/index.html`

- [ ] **Step 1: Add the export function**

Find:
```js
function statusBadge(action) {
```
Insert immediately before it:
```js
function exportResultsCsv() {
  if (!st.results.length) return;
  const today = new Date().toISOString().slice(0, 10);
  ITTools.csv.download(`AccountLockdown_Results_${today}.csv`, st.results.map(row => ({
    "Display Name":     row.displayName,
    "UPN":               row.upn,
    "Sessions Revoked":  row.actions.revokeSessions.status,
    "Password Reset":    row.actions.resetPassword.status,
    "MFA Reset":         row.actions.resetMfa.status,
    "Sign-In Blocked":   row.actions.blockSignIn.status,
    "Temp Password":     row.actions.resetPassword.status === "success" ? row.tempPassword : "",
    "Timestamp":         new Date().toISOString(),
  })));
}

```

- [ ] **Step 2: Verify no syntax errors**

Run the same Node check as Task 5 Step 2. Expected: `OK`.

- [ ] **Step 3: Verify the CSV row shape with a fixture**

Run:
```bash
node -e "
const fs = require('fs');
const html = fs.readFileSync('tools/security-lockdown/index.html', 'utf8');
// Strip the trailing init() call (see Task 10 Step 2 for why). The script
// declares its own top-level 'const st', so it can't also be a function
// parameter — instead, have the constructed function return both st and
// exportResultsCsv, so the test can overwrite st.results before calling it.
const script = html.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/)[1].replace(/init\(\);\s*\$/, '');
let captured = null;
const ITTools = { csv: { download: (filename, rows) => { captured = { filename, rows }; } } };
const { st, exportResultsCsv } = new Function('ITTools', script + '; return { st, exportResultsCsv };')(ITTools);
st.results = [{
  displayName: 'Jane Doe', upn: 'jane.doe@corrohealth.com', tempPassword: 'Ab3!Fake-Pass9\$Zk',
  actions: {
    revokeSessions: { status: 'success' }, resetPassword: { status: 'success' },
    resetMfa: { status: 'failed' }, blockSignIn: { status: 'success' },
  },
}];
exportResultsCsv();
if (!captured) throw new Error('download was not called');
if (captured.rows[0]['Temp Password'] !== 'Ab3!Fake-Pass9\$Zk') throw new Error('temp password missing on success row');
console.log('OK:', JSON.stringify(captured.rows[0]));
"
```
Expected: prints `OK:` followed by the row JSON, with `"Temp Password":"Ab3!Fake-Pass9$Zk"` present since `resetPassword` succeeded.

- [ ] **Step 4: Commit**

```bash
git add tools/security-lockdown/index.html
git commit -m "Add CSV export of Account Lockdown results"
```

---

### Task 14: Style pass — buttons, inputs, and existing hub CSS classes

**Files:**
- Modify: `tools/security-lockdown/index.html`

The tool references several classes (`.btn`, `.btn-primary`, `.btn-secondary`, `.btn-ghost`, `.btn-danger`, `.input`, `.label`, `.subtitle`, `.banner`, `.auth-screen`, `.auth-card`) that should already exist in `shared/styles.css` since every other tool uses them.

- [ ] **Step 1: Confirm the classes exist and note any gaps**

Run:
```bash
grep -oE '\.btn-danger|\.btn-ghost|\.btn-secondary|\.btn-primary\b|^\.btn\b|\.input\b|\.label\b|\.subtitle\b|\.banner\b|\.auth-screen\b|\.auth-card\b' shared/styles.css | sort -u
```
Expected: all of `.btn`, `.btn-primary`, `.btn-secondary`, `.btn-ghost`, `.input`, `.label`, `.subtitle`, `.banner`, `.auth-screen`, `.auth-card` are present. If `.btn-danger` is **not** in the output, add it — it's used for the "Lock Down N Account(s)" button and doesn't exist elsewhere in the hub yet (every other destructive action in this hub, e.g. guest-audit's delete, styles its button inline via `.btn-confirm-ok.danger` inside a modal, not as a standalone button class).

- [ ] **Step 2: Add `.btn-danger` to `shared/styles.css` if missing**

If Step 1 showed `.btn-danger` is missing, find the `.btn-ghost` rule in `shared/styles.css` and add immediately after it:
```css
.btn-danger { background: var(--red); color: #fff; border: none; }
.btn-danger:hover { opacity: .88; }
.btn-danger:disabled { opacity: .5; cursor: not-allowed; }
```

- [ ] **Step 3: Verify no syntax errors**

Run the same Node check as Task 5 Step 2 for both `tools/security-lockdown/index.html` and `shared/styles.css` doesn't need a JS check (it's CSS) — just confirm the dev server or a browser renders the page without console errors in Task 15.

- [ ] **Step 4: Commit (only if Step 2 made a change)**

```bash
git add shared/styles.css
git commit -m "Add .btn-danger button style for Account Lockdown's execute action"
```

---

### Task 15: End-to-end verification against test accounts

**Files:** none — this is a verification pass, not a code change.

**Why this task exists:** per the design spec's Testing section, this tool's blast radius means it must be validated against real (test) accounts before any real incident use — this is not optional polish.

- [ ] **Step 1: Push to `testing` and confirm the preview deploy**

```bash
git push
gh api repos/jgdev-ch/it-tools-preview/actions/runs --jq '.workflow_runs[0].status, .workflow_runs[0].conclusion'
```
Expected: `completed` then `success` (poll every ~15s if still `in_progress`).

- [ ] **Step 2: Sign in and confirm the security gate**

Navigate to `https://jgdev-ch.github.io/it-tools-preview/tools/security-lockdown/` while signed in as an account that is **not** yet in `SG-IT-Tools-Security-Lockdown`. Confirm the "Access Restricted" screen appears. Add your account to the group, sign out and back in, confirm the wizard now appears.

- [ ] **Step 3: Full flow against 1-2 designated test/dummy accounts**

Using accounts explicitly set aside for this test (never a real employee account):
1. Search-and-add one test account; separately, paste the UPN of a second test account into the bulk-add box and confirm both resolve into the queue.
2. Continue to Step 2, confirm the review table lists both accounts, confirm the execute button stays disabled until `LOCKDOWN` is typed exactly.
3. Execute, and in Entra confirm for each test account: sign-in is blocked (`accountEnabled: false`), the password was reset (attempt a sign-in with the old password and confirm it fails), and registered MFA methods were removed (check the account's Authentication methods blade).
4. Confirm the Results table shows all four actions as `success` for both accounts, and download the CSV — confirm it contains both temp passwords.

- [ ] **Step 4: Verify retry behavior**

Temporarily revoke the signed-in tech's own `UserAuthenticationMethod.ReadWrite.All` consent (or test against an account where MFA reset is expected to fail some other way) to produce at least one `failed` action, and confirm: the Results table shows `Partial — needs attention`, the "Retry failed actions" control appears, and clicking it re-runs only the failed action (confirm via Entra's audit log that the already-succeeded actions were not called again during the retry).

- [ ] **Step 5: Visual check, light and dark mode**

Screenshot the wizard header in both themes (`document.documentElement.setAttribute('data-theme', 'dark')` to toggle). Confirm the dark-glass header renders identically regardless of the page's light/dark setting (it's intentionally theme-independent), and that it doesn't look broken/washed out in either mode.

- [ ] **Step 6: Report back to Josh**

Summarize what was verified and link the preview URL before deciding whether to promote `testing` → `main`.
