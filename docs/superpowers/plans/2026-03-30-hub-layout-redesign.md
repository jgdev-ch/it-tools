# Hub Layout Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganise the IT Tools Hub home page into two labelled tool sections (Daily Operations / Reporting & Audit) and replace the always-visible Setup card with a collapsible pill toggle.

**Architecture:** Two targeted edits to existing files — `config.json` gains a `category` field per tool; `index.html` gets a grouped render loop replacing the flat `map()`, new CSS for the toggle, updated HTML for the setup section, and two new JS functions. No new files. No shared helper changes.

**Tech Stack:** Vanilla JS, existing CSS design tokens (`var(--surface)`, `var(--border)`, etc.), `localStorage` for toggle persistence.

---

## File Map

| Action | Path | What changes |
|--------|------|-------------|
| Modify | `config.json` | Add `"category"` field to every tool entry |
| Modify | `index.html` | Grouped render loop, setup toggle CSS/HTML/JS |

---

## Task 1: Add `category` field to `config.json`

**Files:**
- Modify: `config.json`

- [ ] **Step 1: Replace `config.json` with the categorised version**

Write the complete file — only change is adding `"category"` to each entry:

```json
{
  "tools": [
    {
      "id": "license-audit",
      "name": "M365 License Audit",
      "description": "Surface inactive license holders and recover unused seats before your next renewal.",
      "icon": "📊",
      "status": "beta",
      "path": "tools/license-audit/",
      "permissions": ["User.Read.All", "AuditLog.Read.All"],
      "accent": "#1a56db",
      "iconBg": "#e8f0fe",
      "category": "reporting-audit"
    },
    {
      "id": "group-import",
      "name": "Group Import",
      "description": "Bulk-add users to Entra ID security groups from CSV — with dry-run preview and audit log.",
      "icon": "👥",
      "status": "live",
      "path": "tools/group-import/",
      "permissions": ["Group.ReadWrite.All", "GroupMember.ReadWrite.All"],
      "accent": "#047857",
      "iconBg": "#d1fae5",
      "category": "daily-ops"
    },
    {
      "id": "name-resolver",
      "name": "Name Resolver",
      "description": "Resolve a name list (CSV, Excel, or paste) to emails via Graph lookup — produces a ready-to-go CSV for Group Import.",
      "icon": "🔍",
      "status": "beta",
      "path": "tools/name-resolver/",
      "permissions": ["User.Read.All", "Directory.Read.All"],
      "accent": "#1a56db",
      "iconBg": "#e8f0fe",
      "category": "daily-ops"
    },
    {
      "id": "mfa-status",
      "name": "MFA Status Report",
      "description": "Audit MFA coverage across your tenant and surface users with weak or missing auth methods.",
      "icon": "🔑",
      "status": "beta",
      "path": "tools/mfa-status/",
      "permissions": ["UserAuthMethod.Read.All"],
      "accent": "#92400e",
      "iconBg": "#fef3c7",
      "category": "reporting-audit"
    },
    {
      "id": "guest-audit",
      "name": "Guest Access Audit",
      "description": "Identify stale B2B guest accounts — review last sign-in, group memberships, and license exposure across your tenant.",
      "icon": "🛡️",
      "status": "beta",
      "path": "tools/guest-audit/",
      "permissions": ["User.Read.All", "User.ReadWrite.All", "Directory.Read.All", "AuditLog.Read.All"],
      "accent": "#5b21b6",
      "iconBg": "#ede9fe",
      "category": "reporting-audit"
    },
    {
      "id": "finance-dashboard",
      "name": "License Spend",
      "description": "Analyze M365 license costs by SKU and department, identify inactive seat waste, and model 12-month budget scenarios.",
      "icon": "💰",
      "status": "beta",
      "path": "tools/finance-dashboard/",
      "permissions": ["User.Read.All", "AuditLog.Read.All", "Directory.Read.All"],
      "accent": "#92400e",
      "iconBg": "#fef3c7",
      "financeOnly": true,
      "category": "reporting-audit"
    }
  ]
}
```

- [ ] **Step 2: Verify JSON is valid**

```bash
cd /c/dev/projects/it-tools
node -e "JSON.parse(require('fs').readFileSync('config.json','utf8')); console.log('OK')"
```

Expected output: `OK`

- [ ] **Step 3: Commit**

```bash
git add config.json
git commit -m "feat(hub): add category field to all tools in config"
```

---

## Task 2: Grouped section render in `index.html`

Replaces the flat `data.tools.map(...).join("")` with a loop that groups tools by their `category` field and renders a `section-label` + `tools-grid` per section. Also updates the skeleton placeholder HTML so it still renders correctly inside the now-bare `#toolsGrid` container.

**Files:**
- Modify: `index.html`

- [ ] **Step 1: Update the `#toolsGrid` skeleton HTML (lines 251–254)**

Old:
```html
  <div class="tools-grid" id="toolsGrid">
    <div class="skeleton-card"></div>
    <div class="skeleton-card"></div>
  </div>
```

New — wrap skeletons in an inner `.tools-grid` so they stay in a 2-column layout while loading:
```html
  <div id="toolsGrid">
    <div class="tools-grid">
      <div class="skeleton-card"></div>
      <div class="skeleton-card"></div>
    </div>
  </div>
```

- [ ] **Step 2: Replace the `loadTools()` function (lines 503–569)**

Replace the entire function with this version, which adds the `SECTIONS` constant and the grouped render:

```js
// ── Render tools from config ──────────────────────────────────────────────────
const SECTIONS = [
  { key: "daily-ops",       label: "Daily Operations" },
  { key: "reporting-audit", label: "Reporting & Audit" },
];

async function loadTools() {
  const grid = document.getElementById("toolsGrid");
  try {
    const res  = await fetch("config.json?v=" + Date.now());
    const data = await res.json();
    const clickable = ["live", "beta"];

    // Build card HTML for one tool (same logic as before, extracted to inner fn)
    function cardHtml(tool) {
      const perms = tool.permissions || [];

      if (tool.financeOnly) {
        const meta = {
          path: tool.path, iconBg: tool.iconBg, icon: tool.icon,
          status: tool.status, name: tool.name, desc: tool.description, perms,
        };
        _gateCardMeta["finance"] = meta;
        return buildLockedCard({ gateKey: "finance", ...meta });
      }

      if (clickable.includes(tool.status) && tool.path) {
        return buildLiveCard({
          path: tool.path, accent: tool.accent, iconBg: tool.iconBg,
          icon: tool.icon, status: tool.status, name: tool.name,
          desc: tool.description,
        });
      }

      const overlayLabel = tool.status === "deprecated" ? "Deprecated"
        : tool.status === "in-development" ? "In Development"
        : "Coming Soon";
      return `<div class="tool-card no-hover" style="--icon-bg:${tool.iconBg}">
        ${ribbonHtml(tool.status)}
        <div class="tool-icon">${tool.icon}</div>
        <div class="tool-name">${tool.name}</div>
        <div class="tool-desc">${tool.description}</div>
        <div class="tool-overlay">
          <div class="tool-overlay-pill">${overlayLabel}</div>
        </div>
      </div>`;
    }

    // Group tools by category; tools with no category go to "other"
    const grouped = {};
    for (const tool of data.tools) {
      const key = tool.category || "other";
      if (!grouped[key]) grouped[key] = [];
      grouped[key].push(tool);
    }

    // Render defined sections first, then any uncategorised tools at the end
    const allSections = [...SECTIONS];
    if (grouped["other"]) allSections.push({ key: "other", label: "Other" });

    grid.innerHTML = allSections
      .filter(s => grouped[s.key]?.length)
      .map(s => `
        <div class="section-label">${s.label}</div>
        <div class="tools-grid">
          ${grouped[s.key].map(cardHtml).join("")}
        </div>
      `).join("");

    // 1 — Instant unlock from localStorage (no network)
    restoreFromLocalStorage();

    // 2 — Silent MSAL restore in background
    //     Updates topbar user chip and re-validates all gates
    trySilentRestore();

    // Update title bar count pill
    const total  = data.tools.length;
    const active = data.tools.filter(t => t.status === "live" || t.status === "beta").length;
    const pill   = document.getElementById("toolCountPill");
    if (pill) pill.textContent = `${total} tools · ${active} active`;

  } catch(e) {
    grid.innerHTML = `<div style="padding:2rem;text-align:center;color:var(--muted);font-size:13px">
      Could not load tools config. Make sure config.json is in the repo root.
    </div>`;
    const pill = document.getElementById("toolCountPill");
    if (pill) pill.textContent = "";
  }
}
```

- [ ] **Step 3: Verify visually**

Open `index.html` in a browser (file:// or local server). Expected:
- Two section labels visible: "Daily Operations" above 2 cards (Group Import, Name Resolver), "Reporting & Audit" above 4 cards
- Skeleton shimmer still shows on initial load before tools render
- Existing "Setup" section still visible below (unchanged for now — Task 3 handles it)

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat(hub): group tool cards into Daily Operations and Reporting & Audit sections"
```

---

## Task 3: Collapsible setup toggle

Replaces the static `section-label` + `setup-card` HTML with a pill button that expands/collapses the card. State persists in `localStorage`. Collapsed by default.

**Files:**
- Modify: `index.html`

- [ ] **Step 1: Add setup toggle CSS to the `<style>` block**

Add the following CSS after the `.setup-card strong { color: var(--text); }` rule (after line 177):

```css
/* ── Setup toggle (collapsible pill) ── */
.setup-toggle {
  display: inline-flex; align-items: center; gap: 6px;
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 20px; padding: 5px 14px 5px 10px;
  font-size: 12px; font-weight: 600; color: var(--muted);
  cursor: pointer; font-family: inherit;
  transition: border-color .15s, color .15s;
}
.setup-toggle:hover { border-color: var(--border-mid); color: var(--text); }
.setup-toggle.open {
  border-radius: 8px 8px 0 0; width: 100%;
  justify-content: flex-start; border-bottom-color: transparent;
}
.setup-toggle.open + .setup-card { border-radius: 0 0 var(--radius) var(--radius); border-top: none; }
.setup-chevron { font-size: 10px; color: var(--muted2); margin-left: auto; }
```

- [ ] **Step 2: Replace the static setup section HTML (lines 256–261)**

Old:
```html
  <div class="section-label">Setup</div>
  <div class="setup-card">
    <p>All tools share a single <strong>Entra ID app registration</strong>. Add the following redirect URI to your app under <em>Authentication → Single-page application</em>:</p>
    <div class="setup-uri" id="baseUri"></div>
    <p>Each tool will automatically use its own sub-path as the redirect URI. You only need one registration for the whole hub.</p>
  </div>
```

New:
```html
  <button class="setup-toggle" id="setupToggle" onclick="toggleSetup()">
    <span>⚙️</span>
    <span>Setup</span>
    <span class="setup-chevron" id="setupChevron">▾</span>
  </button>
  <div class="setup-card" id="setupCard" hidden>
    <p>All tools share a single <strong>Entra ID app registration</strong>. Add the following redirect URI to your app under <em>Authentication → Single-page application</em>:</p>
    <div class="setup-uri" id="baseUri"></div>
    <p>Each tool will automatically use its own sub-path as the redirect URI. You only need one registration for the whole hub.</p>
  </div>
```

- [ ] **Step 3: Add `toggleSetup` and `applySetupState` to the `<script>` block**

Add the following just before the `// ── Boot ──` comment (before line 572):

```js
// ── Setup toggle ──────────────────────────────────────────────────────────────
function toggleSetup() {
  const open = localStorage.getItem('ittools_setup_open') === 'true';
  const next = !open;
  localStorage.setItem('ittools_setup_open', String(next));
  applySetupState(next);
}

function applySetupState(open) {
  const btn  = document.getElementById('setupToggle');
  const card = document.getElementById('setupCard');
  const chev = document.getElementById('setupChevron');
  btn.classList.toggle('open', open);
  card.hidden = !open;
  chev.textContent = open ? '▴' : '▾';
}
```

- [ ] **Step 4: Call `applySetupState` in the boot section**

Old boot block (lines 572–574):
```js
document.getElementById("baseUri").textContent = ITTools.auth.redirectUri();
initTheme();
loadTools();
```

New:
```js
document.getElementById("baseUri").textContent = ITTools.auth.redirectUri();
initTheme();
applySetupState(localStorage.getItem('ittools_setup_open') === 'true');
loadTools();
```

- [ ] **Step 5: Verify visually**

Open `index.html` in a browser. Expected:
- Setup pill visible at the bottom: `⚙️ Setup ▾` — compact, inline
- Clicking it expands into a full-width toggle button with the setup card below it, chevron flips to `▴`
- Clicking again collapses back to the pill, chevron returns to `▾`
- Refresh the page — state is preserved (if collapsed it stays collapsed, if expanded it stays expanded)
- Clear `localStorage` key `ittools_setup_open` via DevTools → refresh → pill is collapsed (default)
- `baseUri` inside the setup card shows the correct redirect URI when expanded

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat(hub): collapsible setup pill — collapsed by default, state persisted in localStorage"
```

---

## Task 4: Push to preview

- [ ] **Step 1: Push to `testing` branch**

```bash
cd /c/dev/projects/it-tools
git push
```

Expected: GitHub Actions deploys to `https://jgdev-ch.github.io/it-tools-preview/` within ~60 seconds.

- [ ] **Step 2: Smoke check on preview URL**

Open `https://jgdev-ch.github.io/it-tools-preview/`. Confirm:
- "Daily Operations" section shows Group Import + Name Resolver
- "Reporting & Audit" section shows License Audit, MFA Status, Guest Access Audit, License Spend (locked)
- Setup pill at the bottom, collapsed by default
- Expand/collapse Setup works and persists across page reloads
