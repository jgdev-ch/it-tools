# Scripts & Downloads Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an auth-gated Scripts & Downloads section to the IT Tools Hub that renders a rich card row for each entry in `downloads.json`, letting techs download PowerShell scripts directly from the hub.

**Architecture:** `downloads.json` in the repo root drives the section — same pattern as `config.json` drives the tool grid. `loadDownloads()` is called from both sign-in paths; `hideDownloads()` from both sign-out paths. The `#downloadsSection` div is hidden by default and revealed only after a successful sign-in + fetch.

**Tech Stack:** Vanilla HTML/CSS/JS, no build step. Static JSON config. Raw GitHub URL downloads via temporary `<a download>` element.

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `scripts/.gitkeep` | Create | Establishes the `scripts/` directory in git |
| `downloads.json` | Create | Config driving the Downloads section |
| `index.html` | Modify | CSS block, `#downloadsSection` HTML, JS functions, auth wiring, version bump |

---

### Task 1: Create `scripts/` directory and `downloads.json`

**Files:**
- Create: `scripts/.gitkeep`
- Create: `downloads.json`

- [ ] **Step 1: Create the scripts directory placeholder**

```bash
# In the repo root
touch scripts/.gitkeep
```

(On Windows via bash: `echo "" > scripts/.gitkeep` or just create an empty file)

- [ ] **Step 2: Create `downloads.json`**

Create `downloads.json` in the repo root with this exact content:

```json
{
  "scripts": [
    {
      "id": "mailbox-cleanup",
      "name": "Mailbox Cleanup Script",
      "description": "Clear Recoverable Items for quota-blocked Exchange Online users under the 3-Year Retention Policy. Runs in ~6 minutes vs days with the legacy approach.",
      "version": "1.0",
      "type": "PowerShell",
      "accent": "#1d4ed8",
      "iconBg": "#1e2d5a",
      "roles": ["Exchange Admin", "Compliance Admin"],
      "requires": "ExchangeOnlineManagement v3.9+",
      "updated": "2026-05",
      "files": [
        { "label": "Download .ps1", "path": "tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1", "primary": true },
        { "label": "Launcher .bat", "path": "tools/mailbox-cleanup/Run-MailboxCleanup.bat" }
      ]
    }
  ]
}
```

- [ ] **Step 3: Verify the files exist**

```bash
ls scripts/.gitkeep downloads.json
```

Expected: both paths listed, no errors.

- [ ] **Step 4: Commit**

```bash
git add scripts/.gitkeep downloads.json
git commit -m "feat: add downloads.json and scripts/ directory for Downloads section"
```

---

### Task 2: Add Downloads CSS to `index.html`

**Files:**
- Modify: `index.html` — `<style>` block

The existing `<style>` block ends with the Footer section around line 270. Add the following CSS block immediately **before** the closing `</style>` tag.

- [ ] **Step 1: Locate the insertion point**

Find this line in `index.html`:
```css
.footer-links a:hover { color: var(--blue-mid); }
}
</style>
```

- [ ] **Step 2: Insert the Downloads CSS**

Replace that closing section with:

```css
.footer-links a:hover { color: var(--blue-mid); }
}

/* ── Downloads section ── */
.downloads-grid { display: flex; flex-direction: column; gap: 10px; }

.dl-row {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 0 10px 10px 0;
  display: flex; align-items: center; gap: 14px; padding: 14px 16px;
}
.dl-icon-badge {
  width: 36px; height: 36px; border-radius: 8px; flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
}
.dl-main  { flex: 1; min-width: 0; }
.dl-top   { display: flex; align-items: center; gap: 8px; margin-bottom: 3px; }
.dl-name  { font-size: 14px; font-weight: 700; color: var(--text); }
.dl-version { font-size: 10px; color: var(--muted2); }
.dl-desc  { font-size: 12px; color: var(--muted); line-height: 1.4; margin-bottom: 8px; }
.dl-meta  { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
.dl-type-pill {
  font-size: 10px; font-weight: 700; padding: 2px 7px; border-radius: 4px;
  background: var(--blue-light); color: var(--blue-dark);
  border: 1px solid var(--blue-border); white-space: nowrap;
}
.dl-role-pill {
  font-size: 10px; font-weight: 600; padding: 2px 7px; border-radius: 4px;
  background: var(--green-light); color: var(--green);
  border: 1px solid var(--green-border); white-space: nowrap;
}
.dl-requires { font-size: 10px; color: var(--muted2); font-style: italic; }
.dl-btns { display: flex; flex-direction: column; gap: 6px; align-items: flex-end; margin-left: 16px; flex-shrink: 0; }
.btn-dl-primary {
  display: flex; align-items: center; gap: 6px;
  padding: 7px 14px; border-radius: 7px; font-size: 12px; font-weight: 600;
  background: var(--blue); color: #fff; border: none; cursor: pointer; white-space: nowrap;
}
.btn-dl-primary:hover { opacity: .88; }
.btn-dl-ghost {
  display: flex; align-items: center; gap: 5px;
  padding: 4px 10px; border-radius: 7px; font-size: 11px; font-weight: 600;
  background: transparent; color: var(--blue-mid);
  border: 1px solid var(--blue-border); cursor: pointer; white-space: nowrap;
}
.btn-dl-ghost:hover { background: var(--blue-light); }
</style>
```

- [ ] **Step 3: Verify no CSS parse errors**

Open `index.html` in a browser and check DevTools console — no CSS errors expected.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add Downloads section CSS to hub"
```

---

### Task 3: Add `#downloadsSection` HTML to `index.html`

**Files:**
- Modify: `index.html` — HTML body, inside `.hub-shell`

The setup card is the last element inside `.hub-shell`. The closing `</div>` of `.hub-shell` is at line ~360. Insert `#downloadsSection` immediately before that closing tag.

- [ ] **Step 1: Locate the insertion point**

Find this block near line 355–360 in `index.html`:

```html
  <div class="setup-card" id="setupCard" hidden>
    <p>All tools share a single <strong>Entra ID app registration</strong>. Add the following redirect URI to your app under <em>Authentication → Single-page application</em>:</p>
    <div class="setup-uri" id="baseUri"></div>
    <p>Each tool will automatically use its own sub-path as the redirect URI. You only need one registration for the whole hub.</p>
  </div>
</div>
```

- [ ] **Step 2: Insert the downloads section HTML**

Replace the closing `</div>` of `.hub-shell` with:

```html
  <div class="setup-card" id="setupCard" hidden>
    <p>All tools share a single <strong>Entra ID app registration</strong>. Add the following redirect URI to your app under <em>Authentication → Single-page application</em>:</p>
    <div class="setup-uri" id="baseUri"></div>
    <p>Each tool will automatically use its own sub-path as the redirect URI. You only need one registration for the whole hub.</p>
  </div>

  <div id="downloadsSection" style="display:none;margin-top:1.5rem">
    <div class="section-label">Scripts &amp; Downloads</div>
    <div id="downloadsGrid" class="downloads-grid"></div>
  </div>
</div>
```

- [ ] **Step 3: Verify in browser**

Open `index.html`. The downloads section should be invisible (not signed in). Inspect the DOM — `#downloadsSection` should exist with `display:none`.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add #downloadsSection HTML structure to hub"
```

---

### Task 4: Add Downloads JS functions to `index.html`

**Files:**
- Modify: `index.html` — `<script>` block

Add the four functions (`downloadFile`, `buildDownloadRow`, `loadDownloads`, `hideDownloads`) and the `GITHUB_RAW` constant. Insert them immediately **before** the `// ── Setup toggle ──` comment (around line 798).

- [ ] **Step 1: Locate the insertion point**

Find this comment in the `<script>` block:

```javascript
// ── Setup toggle ──────────────────────────────────────────────────────────────
function toggleSetup() {
```

- [ ] **Step 2: Insert the Downloads JS block**

Insert the following immediately before that comment:

```javascript
// ── Downloads section ─────────────────────────────────────────────────────────
const GITHUB_RAW = "https://raw.githubusercontent.com/jgdev-ch/it-tools/main/";

const _DL_SCRIPT_ICON = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#93c5fd" stroke-width="2"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>`;
const _DL_BTN_ICON    = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>`;

function downloadFile(path) {
  const a = document.createElement("a");
  a.href     = GITHUB_RAW + path;
  a.download = path.split("/").pop();
  a.click();
}

function buildDownloadRow(script) {
  const rolePills = script.roles
    .map(r => `<span class="dl-role-pill">${r}</span>`)
    .join("");
  const requires = script.requires
    ? `<span class="dl-requires">· Requires ${script.requires}</span>`
    : "";
  const btns = script.files
    .map(f => {
      const cls = f.primary ? "btn-dl-primary" : "btn-dl-ghost";
      return `<button class="${cls}" onclick="downloadFile('${f.path}')">${_DL_BTN_ICON}${f.label}</button>`;
    })
    .join("");

  return `
    <div class="dl-row" style="border-left:3px solid ${script.accent}">
      <div class="dl-icon-badge" style="background:${script.iconBg}">${_DL_SCRIPT_ICON}</div>
      <div class="dl-main">
        <div class="dl-top">
          <span class="dl-name">${script.name}</span>
          <span class="dl-version">v${script.version}</span>
        </div>
        <div class="dl-desc">${script.description}</div>
        <div class="dl-meta">
          <span class="dl-type-pill">${script.type}</span>
          ${rolePills}
          ${requires}
        </div>
      </div>
      <div class="dl-btns">${btns}</div>
    </div>`;
}

async function loadDownloads() {
  try {
    const res  = await fetch("downloads.json?v=" + Date.now());
    const data = await res.json();
    document.getElementById("downloadsGrid").innerHTML = data.scripts.map(buildDownloadRow).join("");
    document.getElementById("downloadsSection").style.display = "";
  } catch(_) {}
}

function hideDownloads() {
  const section = document.getElementById("downloadsSection");
  if (!section) return;
  section.style.display = "none";
  document.getElementById("downloadsGrid").innerHTML = "";
}

```

- [ ] **Step 3: Verify functions are defined**

Open DevTools console in browser and type `typeof loadDownloads`. Expected: `"function"`.

- [ ] **Step 4: Smoke test `loadDownloads()` manually**

In DevTools console, run: `loadDownloads()`. Expected: the Downloads section appears with the Mailbox Cleanup card (accent bar, icon badge, description, both buttons). If the fetch fails because the file isn't on GitHub yet, the section will stay hidden — that's correct behavior.

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat: add loadDownloads, hideDownloads, downloadFile functions to hub"
```

---

### Task 5: Wire auth gating + bump version to v1.6.0

**Files:**
- Modify: `index.html` — `hubSignIn()`, `trySilentRestore()` `onSignIn` callback, `hubSignOut()` catch block, `onSignOut` callback, footer version string

There are **four** wiring points. Do them all in this task.

- [ ] **Step 1: Wire `loadDownloads()` into `hubSignIn()`**

Find this block (around line 633–637):

```javascript
    const acct  = await ITTools.auth.signIn();
    showSignedIn(acct);
    const token = await ITTools.auth.getToken();
    await runGateChecks(token);
  } catch(_) {
```

Change it to:

```javascript
    const acct  = await ITTools.auth.signIn();
    showSignedIn(acct);
    const token = await ITTools.auth.getToken();
    await runGateChecks(token);
    await loadDownloads();
  } catch(_) {
```

- [ ] **Step 2: Wire `loadDownloads()` into the `onSignIn` callback in `trySilentRestore()`**

Find this block (around line 670–677):

```javascript
    onSignIn: async acct => {
      sessionFound = true;
      showSignedIn(acct);
      try {
        const token = await ITTools.auth.getToken();
        await runGateChecks(token);
      } catch(_) {}
    },
```

Change it to:

```javascript
    onSignIn: async acct => {
      sessionFound = true;
      showSignedIn(acct);
      try {
        const token = await ITTools.auth.getToken();
        await runGateChecks(token);
        await loadDownloads();
      } catch(_) {}
    },
```

- [ ] **Step 3: Wire `hideDownloads()` into the `onSignOut` callback in `trySilentRestore()`**

Find this block (around line 678–681):

```javascript
    onSignOut: () => {
      clearAllGates();
      showSignedOut();
    }
```

Change it to:

```javascript
    onSignOut: () => {
      clearAllGates();
      showSignedOut();
      hideDownloads();
    }
```

- [ ] **Step 4: Wire `hideDownloads()` into the `hubSignOut()` catch block**

Find this block (around line 656–660):

```javascript
  } catch(_) {
    // signOut callback still fires; clear gates regardless
    clearAllGates();
    showSignedOut();
  }
```

Change it to:

```javascript
  } catch(_) {
    // signOut callback still fires; clear gates regardless
    clearAllGates();
    showSignedOut();
    hideDownloads();
  }
```

- [ ] **Step 5: Bump version to v1.6.0 in the footer**

Find this line in the footer (around line 363):

```html
  <span>Built by Josh Garrett · <a href="https://github.com/jgdev-ch/it-tools" style="color:var(--muted2)">github.com/jgdev-ch/it-tools</a> · <span style="color:var(--muted2)">v1.5.0</span></span>
```

Change `v1.5.0` to `v1.6.0`:

```html
  <span>Built by Josh Garrett · <a href="https://github.com/jgdev-ch/it-tools" style="color:var(--muted2)">github.com/jgdev-ch/it-tools</a> · <span style="color:var(--muted2)">v1.6.0</span></span>
```

- [ ] **Step 6: End-to-end verification**

1. Open `index.html` in a browser (via the GitHub Pages preview URL, not `file://`, so MSAL works)
2. Before sign-in: confirm `#downloadsSection` is hidden
3. Sign in with a valid account
4. Confirm the Scripts & Downloads section appears below the tool sections
5. Confirm the Mailbox Cleanup card shows: left blue accent bar, terminal icon badge, name + version, full description, PowerShell pill, two role pills, requires note, primary Download .ps1 button, ghost Launcher .bat button
6. Click "Download .ps1" — browser should download `Invoke-MailboxCleanup.ps1` from raw.githubusercontent.com
7. Click "Launcher .bat" — browser should download `Run-MailboxCleanup.bat`
8. Sign out — confirm the Downloads section is hidden and grid is cleared
9. Sign in again — confirm the section reappears (tests the clear + re-render cycle)

- [ ] **Step 7: Commit**

```bash
git add index.html
git commit -m "feat: wire Downloads section auth gating and bump hub to v1.6.0"
```

---

### Task 6: Push to testing and confirm on preview site

**Files:** None — git operations only.

- [ ] **Step 1: Push testing branch**

```bash
git push origin testing
```

- [ ] **Step 2: Confirm GitHub Actions deployment**

Check the Actions tab on the repo. The `testing` branch deploy should complete within ~30 seconds.

- [ ] **Step 3: Verify on preview URL**

Open the preview site URL. Repeat the end-to-end verification from Task 5 Step 6 using the live preview environment (real MSAL flow, real GitHub raw downloads).

- [ ] **Step 4: Confirm download filenames**

When the browser downloads `Invoke-MailboxCleanup.ps1`, the saved filename should be `Invoke-MailboxCleanup.ps1` (not a hashed name or `download`). Same for `Run-MailboxCleanup.bat`. This validates that `a.download = path.split("/").pop()` is working correctly.
