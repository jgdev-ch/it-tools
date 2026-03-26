# Hub index.html Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `index.html` to link `shared/styles.css` instead of duplicating design tokens, remove the hero section, and upgrade the UI with a slim title bar, 2-column card grid, corner ribbon status badges, and frosted "coming soon" overlays.

**Architecture:** Single-file HTML page — all changes are confined to `index.html`. The `<style>` block is slimmed to hub-only rules; all design tokens come from `shared/styles.css`. JS card-builder functions are updated in-place. No other files are touched.

**Tech Stack:** Vanilla HTML/CSS/JS, MSAL Browser v3, Microsoft Graph API

---

### Task 1: Replace inline CSS with shared/styles.css + hub-specific style block

**Files:**
- Modify: `index.html` (head section, lines 7–310)

- [ ] **Step 1: Replace the `<head>` block**

Replace everything from `<head>` through the closing `</style>` tag (lines 3–310) with:

```html
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>IT Tools — M365 Admin Hub</title>
<script src="https://cdn.jsdelivr.net/npm/@azure/msal-browser@3.28.1/lib/msal-browser.min.js"></script>
<link rel="stylesheet" href="shared/styles.css"/>
<style>
/* ── Hub topbar (unique: has sign-in btn + GitHub link) ── */
.hub-topbar {
  height: var(--topbar-h);
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  display: flex; align-items: center; justify-content: space-between;
  padding: 0 1.5rem;
  position: sticky; top: 0; z-index: 100;
}
.hub-brand { display: flex; align-items: center; gap: 10px; }
.hub-brand-icon {
  width: 30px; height: 30px; border-radius: 7px;
  background: var(--blue-light);
  display: flex; align-items: center; justify-content: center;
}
.hub-brand-name { font-size: 15px; font-weight: 700; letter-spacing: -.01em; }
.hub-brand-tag {
  font-size: 10px; font-weight: 500; color: var(--blue-mid);
  background: var(--blue-light); padding: 2px 8px; border-radius: 10px;
}
.hub-topbar-right { display: flex; align-items: center; gap: 8px; }

.btn-signin {
  display: flex; align-items: center; gap: 7px;
  padding: 5px 13px; border-radius: var(--radius-sm);
  border: 1px solid var(--border); background: transparent;
  font-size: 12px; font-weight: 600; color: var(--muted);
  cursor: pointer; font-family: inherit; transition: all .12s; white-space: nowrap;
}
.btn-signin:hover { background: var(--blue-light); color: var(--blue-dark); border-color: var(--blue); }
.btn-signin.loading { opacity: .55; pointer-events: none; }

.user-chip {
  display: none; align-items: center; gap: 7px;
  background: var(--surface3); border-radius: 20px;
  padding: 3px 10px 3px 4px; font-size: 12px; font-weight: 500;
}
.user-chip.show { display: flex; }
.user-avatar {
  width: 24px; height: 24px; border-radius: 50%;
  background: var(--amber-light); color: var(--amber);
  display: flex; align-items: center; justify-content: center;
  font-size: 10px; font-weight: 700;
}
.btn-signout {
  display: none; padding: 5px 11px; border-radius: var(--radius-sm);
  border: 1px solid var(--border); background: transparent;
  font-size: 12px; font-weight: 500; color: var(--muted);
  cursor: pointer; font-family: inherit; transition: all .12s;
}
.btn-signout.show { display: block; }
.btn-signout:hover { background: var(--red-light); color: var(--red); border-color: var(--red); }

/* ── Page shell ── */
.hub-shell { max-width: 860px; margin: 0 auto; padding: 1.5rem 1.25rem 4rem; }

/* ── Slim title bar ── */
.hub-title-bar {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 1.5rem;
}
.hub-title-bar h1 { font-size: 20px; font-weight: 700; letter-spacing: -.01em; }
.hub-count-pill {
  font-size: 12px; color: var(--muted);
  background: var(--surface3); border: 1px solid var(--border);
  border-radius: 20px; padding: 3px 12px;
}

/* ── Tools grid — 2 columns ── */
.tools-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 12px; margin-bottom: 2rem;
}
@media (max-width: 600px) { .tools-grid { grid-template-columns: 1fr; } }

/* ── Tool card ── */
.tool-card {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 12px; padding: 1.1rem;
  cursor: pointer; text-decoration: none; color: inherit;
  display: block; position: relative; overflow: hidden;
  transition: border-color .15s, box-shadow .15s, transform .1s;
}
.tool-card:hover { border-color: var(--border-mid); box-shadow: var(--shadow-md); transform: translateY(-1px); }
.tool-card.no-hover { cursor: default; }
.tool-card.no-hover:hover { transform: none; box-shadow: none; border-color: var(--border); }
.tool-card.locked { border-style: dashed; cursor: default; }
.tool-card.locked:hover { transform: none; box-shadow: none; border-color: var(--border); }

/* ── Corner ribbon ── */
.tool-ribbon {
  position: absolute; top: 0; right: 0;
  border-radius: 0 12px 0 6px;
  padding: 3px 9px; font-size: 9px; font-weight: 700;
  text-transform: uppercase; letter-spacing: .04em; white-space: nowrap;
}
.ribbon-live    { background: var(--green-light);  color: var(--green); }
.ribbon-beta    { background: var(--blue-light);   color: var(--blue-dark); }
.ribbon-soon    { background: var(--surface3);     color: var(--muted2); }
.ribbon-finance { background: var(--amber-light);  color: var(--amber); }
.ribbon-locked  { background: var(--surface3);     color: var(--muted2); }

/* ── Card body ── */
.tool-icon {
  width: 36px; height: 36px; border-radius: 9px;
  display: flex; align-items: center; justify-content: center; font-size: 18px;
  background: var(--icon-bg, var(--blue-light));
  margin-bottom: 10px;
}
.tool-name { font-size: 14px; font-weight: 700; margin-bottom: 4px; }
.tool-desc {
  font-size: 12px; color: var(--muted); line-height: 1.5;
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
}
.lock-hint {
  margin-top: 10px; padding-top: 10px;
  border-top: 1px solid var(--border);
  font-size: 11px; color: var(--muted2);
}

/* ── Coming-soon frosted overlay ── */
.tool-overlay {
  position: absolute; inset: 0; border-radius: 12px;
  background: rgba(248, 250, 252, 0.75);
  backdrop-filter: blur(2px);
  display: flex; align-items: center; justify-content: center;
  pointer-events: none;
}
[data-theme="dark"] .tool-overlay { background: rgba(26, 29, 39, 0.80); }
.tool-overlay-pill {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 20px; padding: 5px 14px;
  font-size: 11px; font-weight: 700; color: var(--muted);
  pointer-events: none;
}

/* ── Skeleton ── */
.skeleton-card {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 12px; height: 110px;
  animation: shimmer 1.5s infinite;
}
@keyframes shimmer { 0%, 100% { opacity: 1; } 50% { opacity: .5; } }

/* ── Section label ── */
.section-label {
  font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .07em;
  color: var(--muted2); margin-bottom: 1rem; padding-left: 2px;
}

/* ── Setup card ── */
.setup-card {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 1.25rem;
  font-size: 13px; line-height: 1.7; color: var(--muted);
}
.setup-card strong { color: var(--text); }
.setup-uri {
  font-family: 'Cascadia Code','Consolas',monospace; font-size: 12px;
  background: var(--surface2); border: 1px solid var(--border);
  border-radius: var(--radius-sm); padding: 8px 12px; color: var(--text);
  word-break: break-all; margin: .75rem 0;
}

/* ── Footer ── */
.hub-footer {
  border-top: 1px solid var(--border); padding: 1.5rem;
  display: flex; align-items: center; justify-content: space-between;
  max-width: 860px; margin: 0 auto;
  font-size: 12px; color: var(--muted2); flex-wrap: wrap; gap: 10px;
}
.footer-links { display: flex; gap: 16px; }
.footer-links a { color: var(--muted2); text-decoration: none; }
.footer-links a:hover { color: var(--blue-mid); }
</style>
</head>
```

- [ ] **Step 2: Open in browser and confirm page renders without errors**

Open `index.html` directly in a browser (or via a local file server). Confirm:
- No blank white page
- Background is light blue-grey (`#f0f4f9`)
- No JS console errors about missing styles

- [ ] **Step 3: Commit**

```bash
cd /c/dev/projects/it-tools
git add index.html
git commit -m "refactor: replace inline CSS with shared/styles.css link"
```

---

### Task 2: Replace hero section + legend with slim title bar

**Files:**
- Modify: `index.html` (body, lines 312–406)

- [ ] **Step 1: Replace the topbar class name and hero/legend HTML**

In the `<body>`, replace the entire block from `<div class="topbar">` through the end of the `<div class="tools-section">` opening content (before `<div class="tools-grid"`), keeping the topbar's inner content but switching to the new class names and removing the hero:

Replace the current topbar `<div class="topbar">` opening tag with:
```html
<div class="hub-topbar">
```

Replace `<div class="brand">` with `<div class="hub-brand">`.
Replace `<div class="brand-icon">` with `<div class="hub-brand-icon">`.
Replace `<span class="brand-name">IT Tools</span>` with `<span class="hub-brand-name">IT Tools</span>`.
Replace `<span class="brand-tag">M365 Admin Hub</span>` with `<span class="hub-brand-tag">M365 Admin Hub</span>`.
Replace `<div class="topbar-right">` with `<div class="hub-topbar-right">`.

- [ ] **Step 2: Remove hero section, replace tools-section with hub-shell + title bar**

Remove this entire block (lines 360–392):
```html
<!-- HERO -->
<div class="hero">
  ...entire hero div...
</div>

<!-- TOOLS -->
<div class="tools-section">
  <div class="section-label">Available tools</div>

  <div class="legend">
    <span class="legend-label">Status:</span>
    <span class="status-badge badge-live">Live</span>
    <span class="status-badge badge-beta">Beta</span>
    <span class="status-badge badge-in-development">In Development</span>
    <span class="status-badge badge-coming-soon">Coming Soon</span>
    <span class="status-badge badge-deprecated">Deprecated</span>
  </div>
```

Replace with:
```html
<div class="hub-shell">
  <div class="hub-title-bar">
    <h1>IT Tools Hub</h1>
    <span class="hub-count-pill" id="toolCountPill">Loading…</span>
  </div>
```

- [ ] **Step 3: Close `hub-shell` instead of `tools-section`**

Find the closing `</div>` that closes `<div class="tools-section">` (just before `<footer`) and confirm it now closes `<div class="hub-shell">`. No change needed to the tag itself — just verify the structure is:

```html
  </div>  <!-- closes hub-shell -->
</div>    <!-- NOT needed: tools-section is gone -->

<footer class="hub-footer">
```

Remove one extra `</div>` if present so the nesting is correct.

- [ ] **Step 4: Update skeleton cards count from 4 to 2**

In `<div class="tools-grid" id="toolsGrid">`, change from 4 skeleton cards to 2 (matching the 2-column grid):

```html
<div class="tools-grid" id="toolsGrid">
  <div class="skeleton-card"></div>
  <div class="skeleton-card"></div>
</div>
```

- [ ] **Step 5: Open in browser and verify**

Confirm:
- No hero section visible
- "IT Tools Hub" heading appears below topbar
- "Loading…" pill appears to the right of the heading
- 2 skeleton shimmer cards appear below

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "refactor: replace hero section with slim title bar"
```

---

### Task 3: Update card builders to use corner ribbon + new layout

**Files:**
- Modify: `index.html` (script section, `badgeHtml`, `buildLiveCard`, `buildLockedCard`, disabled card)

- [ ] **Step 1: ADD `ribbonHtml()` alongside `badgeHtml()` — do NOT remove `badgeHtml` yet**

The disabled-card template in `loadTools()` still calls `badgeHtml` and will be updated in Task 4. Removing `badgeHtml` before Task 4 is complete will cause a JS ReferenceError. Add `ribbonHtml` directly after the existing `badgeHtml` block:

```js
const RIBBON_LABELS = { "live":"Live", "beta":"Beta", "coming-soon":"Soon", "in-development":"Dev", "deprecated":"Depr." };
const RIBBON_CLASS  = { "live":"ribbon-live", "beta":"ribbon-beta", "coming-soon":"ribbon-soon", "in-development":"ribbon-soon", "deprecated":"ribbon-soon" };

function ribbonHtml(status) {
  const cls   = RIBBON_CLASS[status]  || "ribbon-soon";
  const label = RIBBON_LABELS[status] || status;
  return `<div class="tool-ribbon ${cls}">${label}</div>`;
}
```

- [ ] **Step 2: Update `buildLiveCard()`**

Replace the `buildLiveCard` function body:

```js
function buildLiveCard({ path, accent, iconBg, icon, status, name, desc }) {
  return `<a class="tool-card" href="${path}" style="--icon-bg:${iconBg}">
    ${ribbonHtml(status)}
    <div class="tool-icon">${icon}</div>
    <div class="tool-name">${name}</div>
    <div class="tool-desc">${desc}</div>
  </a>`;
}
```

- [ ] **Step 3: Update `buildLockedCard()`**

Replace the `buildLockedCard` function body:

```js
function buildLockedCard({ gateKey, path, accent, iconBg, icon, status, name, desc, perms }) {
  const permsStr = (perms || []).join("|");
  return `<div class="tool-card locked" id="gate-${gateKey}"
      data-path="${path}" data-accent="${accent}" data-iconbg="${iconBg}"
      data-icon="${icon}" data-status="${status}"
      data-name="${name}" data-desc="${desc}" data-perms="${permsStr}"
      style="--icon-bg:${iconBg}">
    <div class="tool-ribbon ribbon-finance">Finance</div>
    <div class="tool-icon">${icon}</div>
    <div class="tool-name">${name}</div>
    <div class="tool-desc">${desc}</div>
    <div class="lock-hint">🔒 Sign in to unlock if you have access</div>
  </div>`;
}
```

- [ ] **Step 4: Update `unlockCard()` to use new `buildLiveCard` signature**

The current `unlockCard()` passes `perms` to `buildLiveCard` but the new signature drops `perms` from the card display. Verify `unlockCard()` still passes the required fields. Update it to match:

```js
function unlockCard(gateKey) {
  const locked = document.getElementById(`gate-${gateKey}`);
  if (!locked) return;

  locked.outerHTML = buildLiveCard({
    path:   locked.dataset.path,
    iconBg: locked.dataset.iconbg,
    icon:   locked.dataset.icon,
    status: locked.dataset.status,
    name:   locked.dataset.name,
    desc:   locked.dataset.desc,
  });
}
```

- [ ] **Step 5: Update `lockCard()` to use new `buildLockedCard` signature**

```js
function lockCard(gateKey) {
  const meta = _gateCardMeta[gateKey];
  if (!meta) return;
  const live = document.querySelector(`a.tool-card[href="${meta.path}"]`);
  if (!live) return;
  live.outerHTML = buildLockedCard({
    gateKey,
    path:   meta.path,
    accent: meta.accent,
    iconBg: meta.iconBg,
    icon:   meta.icon,
    status: meta.status,
    name:   meta.name,
    desc:   meta.desc,
    perms:  meta.perms,
  });
}
```

- [ ] **Step 6: Verify no remaining calls to `badgeHtml` in the builders you just updated**

The two builders (`buildLiveCard`, `buildLockedCard`) now use `ribbonHtml`. The disabled card in `loadTools()` still calls `badgeHtml` — that is expected and will be fixed in Task 4. Do not remove `badgeHtml` or `tagsHtml` yet.

- [ ] **Step 7: Open in browser, sign in, and verify cards render correctly**

Confirm:
- Live/beta cards show corner ribbon (green "Live", blue "Beta")
- Corner ribbon sits in the top-right corner of the card
- Card shows icon, name, description — no permission tags
- Finance Dashboard shows locked state with amber "Finance" ribbon after sign-in (if not in finance group)

- [ ] **Step 8: Commit**

```bash
git add index.html
git commit -m "refactor: update card builders to use corner ribbon layout"
```

---

### Task 4: Add frosted overlay for coming-soon cards

**Files:**
- Modify: `index.html` (script section, `loadTools()` disabled card template)

- [ ] **Step 1: Update the disabled/coming-soon card template inside `loadTools()`**

Find this block inside `loadTools()`:

```js
// Non-clickable (coming-soon, in-development, deprecated)
return `<div class="tool-card disabled" style="--card-accent:${tool.accent};--icon-bg:${tool.iconBg}">
  <div class="tool-card-header">
    <div class="tool-icon">${tool.icon}</div>
    ${badgeHtml(tool.status)}
  </div>
  <div class="tool-name">${tool.name}</div>
  <div class="tool-desc">${tool.description}</div>
  <div class="tool-tags">${tagsHtml(perms)}</div>
</div>`;
```

Replace with:

```js
// Non-clickable (coming-soon, in-development, deprecated)
return `<div class="tool-card no-hover" style="--icon-bg:${tool.iconBg}">
  ${ribbonHtml(tool.status)}
  <div class="tool-icon">${tool.icon}</div>
  <div class="tool-name">${tool.name}</div>
  <div class="tool-desc">${tool.description}</div>
  <div class="tool-overlay">
    <div class="tool-overlay-pill">Coming Soon</div>
  </div>
</div>`;
```

- [ ] **Step 2: Verify the coming-soon overlay in browser**

Open the hub. Guest Access Audit (status: `coming-soon`) should show:
- Card content visible underneath a frosted/semi-transparent overlay
- "Coming Soon" pill centered on the overlay
- Gray "Soon" ribbon in the top-right corner
- Card is not clickable (cursor: default, no hover lift)
- In dark mode: overlay should be dark-tinted (verify by toggling theme)

- [ ] **Step 2b: Remove `badgeHtml`, `STATUS_LABELS`, and `tagsHtml` — now safe to delete**

With the disabled card updated in Step 1, `badgeHtml` and `tagsHtml` are no longer called anywhere. Remove these now-dead functions:

```js
// DELETE these three blocks entirely:
const STATUS_LABELS = { ... };
function badgeHtml(status) { ... }
function tagsHtml(perms) { ... }
```

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat: add frosted overlay for coming-soon tool cards"
```

---

### Task 5: Wire up dynamic tool count in title bar

**Files:**
- Modify: `index.html` (script section, `loadTools()`)

- [ ] **Step 1: Add count computation to `loadTools()` after rendering cards**

Inside `loadTools()`, after `grid.innerHTML = data.tools.map(...).join("")`, add:

```js
// Update title bar count pill
const total  = data.tools.length;
const active = data.tools.filter(t => t.status === "live" || t.status === "beta").length;
const pill   = document.getElementById("toolCountPill");
if (pill) pill.textContent = `${total} tools · ${active} active`;
```

- [ ] **Step 2: Handle count pill in the error case**

Inside the `catch(e)` block in `loadTools()`, after setting the error message, add:

```js
const pill = document.getElementById("toolCountPill");
if (pill) pill.textContent = "";
```

- [ ] **Step 3: Verify count in browser**

With 5 tools in config.json (1 live, 3 beta, 1 coming-soon), the pill should read:
**`5 tools · 4 active`**

Confirm it appears to the right of "IT Tools Hub" in the title bar.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add dynamic tool count to hub title bar"
```

---

### Task 6: Final verification pass

- [ ] **Step 1: Full light mode check**

Open `index.html` in browser (light mode). Verify:
- [ ] Topbar: MS logo, "IT Tools", "M365 Admin Hub" tag, theme button, sign-in button visible
- [ ] Title bar: "IT Tools Hub" left, "5 tools · 4 active" pill right
- [ ] Grid: 2 columns, all 5 tools rendered
- [ ] License Audit: blue "Beta" ribbon, no tags
- [ ] Group Import: green "Live" ribbon
- [ ] MFA Status: blue "Beta" ribbon
- [ ] Finance Dashboard: amber "Finance" ribbon (locked), or live if signed in with finance access
- [ ] Guest Audit: gray "Soon" ribbon, frosted overlay with "Coming Soon" pill

- [ ] **Step 2: Dark mode check**

Toggle to dark mode. Verify:
- [ ] Background goes dark (`#0f1117`)
- [ ] Cards, topbar, title bar all use dark tokens correctly (no hardcoded light colors)
- [ ] Frosted overlay on Guest Audit is dark-tinted (not white)

- [ ] **Step 3: Sign-in check**

Click Sign in and authenticate. Verify:
- [ ] User chip appears in topbar with correct initials
- [ ] Sign in button hides, Sign out button appears
- [ ] Finance Dashboard unlocks to a live card if user is in the finance group (amber ribbon disappears, card becomes clickable)
- [ ] Signing out re-locks the Finance Dashboard

- [ ] **Step 4: Mobile check (narrow browser window)**

Resize browser to < 600px. Verify:
- [ ] Grid collapses to 1 column

- [ ] **Step 5: Final commit**

```bash
git add index.html
git commit -m "feat: hub index.html redesign — slim title bar, 2-col grid, ribbon badges, coming-soon overlay"
```
