# Account Dropdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hub's scattered topbar badges + user chip + sign-out button with an avatar-only button that opens a dropdown panel showing the user's name, email, access pills, and sign-out.

**Architecture:** Single-file change to `index.html`. Remove `#hubBadges`, `#userChip`, `#signOutBtn` and their CSS/JS. Add `#accountBtn` (avatar circle) + `#accountDropdown` (panel). Rewrite `showSignedIn`, `showSignedOut`, replace `renderHubBadges` with `renderAccountDropdown`. Add `toggleAccountDropdown` and click-outside/Escape dismiss handlers.

**Tech Stack:** Vanilla JS, inline CSS, Lucide SVG icons, no new dependencies. No test framework — verification is manual browser testing after each task.

---

## File Map

| File | Changes |
|---|---|
| `index.html` | All changes — HTML (topbar), CSS (remove old, add new), JS (state, functions, event listeners) |

---

## Task 1: HTML — swap old topbar elements for account button + dropdown shell

**Files:**
- Modify: `index.html` lines 273–283

- [ ] **Step 1: Replace the three old elements with the account button + dropdown**

Find this exact block (lines 273–283):
```html
    <!-- Access badges — shown after gate checks -->
    <div id="hubBadges" style="display:none;align-items:center;gap:6px"></div>

    <!-- User chip — visible after sign-in -->
    <div class="user-chip" id="userChip">
      <div class="user-avatar" id="userInitials"></div>
      <span id="userName"></span>
    </div>

    <!-- Sign out — visible after sign-in -->
    <button class="btn-signout" id="signOutBtn" onclick="hubSignOut()">Sign out</button>
```

Replace it with:
```html
    <!-- Account button + dropdown — visible after sign-in -->
    <div style="position:relative">
      <button class="account-btn" id="accountBtn" onclick="toggleAccountDropdown()" style="display:none" aria-label="Account menu">
        <span id="accountInitials"></span>
      </button>
      <div class="account-dropdown" id="accountDropdown" style="display:none">
        <div class="account-panel-head">
          <div class="account-panel-avatar" id="accountPanelAvatar"></div>
          <div>
            <div class="account-panel-name" id="accountPanelName"></div>
            <div class="account-panel-email" id="accountPanelEmail"></div>
          </div>
        </div>
        <div class="account-panel-access" id="accountPanelAccess" style="display:none">
          <div class="account-panel-access-label">Access</div>
          <div class="account-panel-pills" id="accountPanelPills"></div>
        </div>
        <div class="account-panel-divider"></div>
        <button class="account-panel-signout" onclick="hubSignOut()">
          <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
          Sign out
        </button>
      </div>
    </div>
```

- [ ] **Step 2: Verify HTML structure in browser**

Open `index.html` via a local server (`npx serve .` then `http://localhost:3000`). Before signing in:
- The topbar shows only the theme toggle, GitHub icon, and Sign in button — no avatar, no badges, no sign-out button.

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat: account dropdown HTML shell — replace hubBadges/userChip/signOutBtn"
```

---

## Task 2: CSS — remove old styles, add account dropdown styles

**Files:**
- Modify: `index.html` CSS block (lines 33–77)

- [ ] **Step 1: Remove the three obsolete CSS blocks**

Find and delete this entire block (lines 33–44):
```css
/* ── Hub access badges ── */
.hub-access-badge {
  display: inline-flex; align-items: center; gap: 4px;
  padding: 2px 8px; border-radius: 20px;
  font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em;
}
.hub-access-badge--amber {
  background: var(--amber-light); border: 1px solid var(--amber-border); color: var(--amber);
}
.hub-access-badge--blue {
  background: var(--blue-light); border: 1px solid var(--blue-border); color: var(--blue-dark);
}
```

Find and delete this entire block (lines 56–77):
```css
/* Overrides shared/styles.css .user-chip (which defaults to display:flex) —
   hub uses display:none + .show toggle for sign-in state management */
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
.btn-signout:hover { background: var(--red-light); color: var(--red); border-color: var(--red-border); }
```

- [ ] **Step 2: Add new account dropdown CSS**

Find this line (now approximately line 31 after the deletions):
```css
.hub-topbar-right { display: flex; align-items: center; gap: 8px; }
```

Add the following block immediately after it:
```css
/* ── Account avatar button (topbar) ── */
.account-btn {
  width: 30px; height: 30px; border-radius: 50%;
  background: var(--accent); border: none;
  font-size: 11px; font-weight: 800; color: #fff;
  cursor: pointer; display: flex; align-items: center; justify-content: center;
  transition: opacity .15s; flex-shrink: 0;
}
.account-btn:hover { opacity: .85; }
.account-btn.open { box-shadow: 0 0 0 2px var(--accent); }

/* ── Account dropdown panel ── */
.account-dropdown {
  position: absolute; right: 0; top: calc(100% + 8px);
  background: var(--card); border: 1px solid var(--border);
  border-radius: 10px; box-shadow: 0 8px 28px rgba(0,0,0,.35);
  min-width: 220px; max-width: 320px; z-index: 200; overflow: hidden;
}
.account-panel-head {
  display: flex; align-items: center; gap: 10px;
  padding: 13px 14px 12px; border-bottom: 1px solid var(--border);
}
.account-panel-avatar {
  width: 36px; height: 36px; border-radius: 50%;
  background: var(--accent); flex-shrink: 0;
  font-size: 13px; font-weight: 800; color: #fff;
  display: flex; align-items: center; justify-content: center;
}
.account-panel-name  { font-size: 13px; font-weight: 700; color: var(--text); }
.account-panel-email { font-size: 11px; color: var(--muted2); margin-top: 1px; }
.account-panel-access { padding: 10px 14px 8px; border-bottom: 1px solid var(--border); }
.account-panel-access-label {
  font-size: 10px; font-weight: 700; text-transform: uppercase;
  letter-spacing: .06em; color: var(--muted2); margin-bottom: 7px;
}
.account-panel-pills { display: flex; flex-direction: column; gap: 5px; }
.account-pill {
  display: inline-flex; align-items: center; gap: 5px;
  padding: 4px 10px; border-radius: 20px;
  font-size: 11px; font-weight: 700; letter-spacing: .04em; text-transform: uppercase;
  width: fit-content;
}
.account-pill--amber { background: var(--amber-light); border: 1px solid var(--amber-border); color: var(--amber); }
.account-pill--blue  { background: var(--blue-light);  border: 1px solid var(--blue-border);  color: var(--blue-dark); }
.account-panel-divider { height: 1px; background: var(--border); }
.account-panel-signout {
  display: flex; align-items: center; gap: 8px;
  width: 100%; padding: 10px 14px;
  background: transparent; border: none;
  font-size: 12px; color: var(--muted2); cursor: pointer;
  text-align: left; font-family: inherit;
}
.account-panel-signout:hover { color: var(--red); background: var(--red-light); }
```

- [ ] **Step 3: Verify no console errors**

Reload `http://localhost:3000`. No JS errors should appear in the browser console related to missing CSS classes.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: account dropdown CSS — remove badge/chip styles, add panel styles"
```

---

## Task 3: JS — update showSignedIn, showSignedOut, replace renderHubBadges

**Files:**
- Modify: `index.html` JS block — functions at lines ~380, ~389, ~495, ~535, ~547

- [ ] **Step 1: Add `_accountData` state variable**

Find this comment (line ~379):
```js
// ── Topbar state ──────────────────────────────────────────────────────────────
function showSignedIn(account) {
```

Add the state variable on the line before the comment:
```js
let _accountData = null; // { initials, name, email } — set on sign-in, cleared on sign-out

// ── Topbar state ──────────────────────────────────────────────────────────────
function showSignedIn(account) {
```

- [ ] **Step 2: Replace `showSignedIn()`**

Find and replace the entire `showSignedIn` function:
```js
function showSignedIn(account) {
  const name     = account?.name || account?.username || "";
  const initials = name.split(" ").map(n => n[0]).join("").slice(0, 2).toUpperCase() || "ME";
  document.getElementById("userInitials").textContent = initials;
  document.getElementById("userName").textContent     = name;
  document.getElementById("userChip").classList.add("show");
  document.getElementById("signOutBtn").classList.add("show");
  document.getElementById("signInBtn").style.display  = "none";
}
```

Replace with:
```js
function showSignedIn(account) {
  const name     = account?.name || account?.username || "";
  const email    = account?.username || "";
  const initials = name.split(" ").map(n => n[0]).join("").slice(0, 2).toUpperCase() || "ME";
  _accountData   = { initials, name, email };
  document.getElementById("accountInitials").textContent    = initials;
  document.getElementById("accountPanelAvatar").textContent = initials;
  document.getElementById("accountPanelName").textContent   = name;
  document.getElementById("accountPanelEmail").textContent  = email;
  document.getElementById("accountBtn").style.display       = "flex";
  document.getElementById("signInBtn").style.display        = "none";
}
```

- [ ] **Step 3: Replace `showSignedOut()`**

Find and replace the entire `showSignedOut` function:
```js
function showSignedOut() {
  document.getElementById("userChip").classList.remove("show");
  document.getElementById("signOutBtn").classList.remove("show");
  document.getElementById("signInBtn").style.display  = "";
  document.getElementById("hubBadges").style.display = "none";
  document.getElementById("hubBadges").innerHTML = "";
}
```

Replace with:
```js
function showSignedOut() {
  _accountData = null;
  const btn      = document.getElementById("accountBtn");
  const dropdown = document.getElementById("accountDropdown");
  btn.style.display        = "none";
  btn.classList.remove("open");
  dropdown.style.display   = "none";
  document.getElementById("accountPanelPills").innerHTML       = "";
  document.getElementById("accountPanelAccess").style.display  = "none";
  document.getElementById("signInBtn").style.display           = "";
}
```

- [ ] **Step 4: Replace `renderHubBadges()` with `renderAccountDropdown()`**

Find and replace the entire `renderHubBadges` function (lines ~494–522):
```js
// ── Render hub access badge pills ────────────────────────────────────────────
function renderHubBadges(unlockedGates) {
  const BADGE_DEFS = {
    finance: {
      label: "Finance View",
      cls:   "hub-access-badge--amber",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>`,
    },
    reporting: {
      label: "Reporting View",
      cls:   "hub-access-badge--blue",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>`,
    },
    gsd: {
      label: "GSD Access",
      cls:   "hub-access-badge--blue",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>`,
    },
  };
  const container = document.getElementById("hubBadges");
  if (!container) return;
  const html = unlockedGates
    .filter(k => BADGE_DEFS[k])
    .map(k => `<span class="hub-access-badge ${BADGE_DEFS[k].cls}">${BADGE_DEFS[k].icon} ${BADGE_DEFS[k].label}</span>`)
    .join("");
  if (!html) { container.style.display = "none"; return; }
  container.innerHTML = html;
  container.style.display = "flex";
}
```

Replace with:
```js
// ── Render account dropdown access pills ──────────────────────────────────────
function renderAccountDropdown(unlockedGates) {
  const PILL_DEFS = {
    finance: {
      label: "Finance View",
      cls:   "account-pill--amber",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>`,
    },
    reporting: {
      label: "Reporting View",
      cls:   "account-pill--blue",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>`,
    },
    gsd: {
      label: "GSD Access",
      cls:   "account-pill--blue",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>`,
    },
  };
  const pills    = unlockedGates.filter(k => PILL_DEFS[k]);
  const pillsEl  = document.getElementById("accountPanelPills");
  const accessEl = document.getElementById("accountPanelAccess");
  if (!pillsEl || !accessEl) return;
  if (!pills.length) { accessEl.style.display = "none"; return; }
  pillsEl.innerHTML = pills
    .map(k => `<span class="account-pill ${PILL_DEFS[k].cls}">${PILL_DEFS[k].icon} ${PILL_DEFS[k].label}</span>`)
    .join("");
  accessEl.style.display = "block";
}
```

- [ ] **Step 5: Update the two `renderHubBadges` call sites**

In `runGateChecks()`, find:
```js
  renderHubBadges(unlocked);
```
Replace with:
```js
  renderAccountDropdown(unlocked);
```

In `restoreFromLocalStorage()`, find:
```js
  if (unlocked.length) renderHubBadges(unlocked);
```
Replace with:
```js
  renderAccountDropdown(unlocked);
```
(The `if (unlocked.length)` guard is no longer needed — `renderAccountDropdown` handles the empty case itself.)

- [ ] **Step 6: Verify in browser**

Sign in at `http://localhost:3000`. Expected:
- Avatar circle with your initials appears in the topbar (no name, no sign-out button, no floating badges)
- Clicking the avatar opens the panel with your full name, email, and any access pills you hold
- Users in no special groups see no Access section — just name, email, and sign out

- [ ] **Step 7: Commit**

```bash
git add index.html
git commit -m "feat: account dropdown JS — showSignedIn/Out rewrite, renderAccountDropdown"
```

---

## Task 4: JS — toggleAccountDropdown, click-outside, Escape dismiss

**Files:**
- Modify: `index.html` JS block — add functions before `loadTools()` call (line ~751)

- [ ] **Step 1: Add `toggleAccountDropdown()` and dismiss event listeners**

Find the final line of the script (line ~751):
```js
loadTools();
```

Add these functions immediately before it:
```js
// ── Account dropdown toggle and dismiss ───────────────────────────────────────
function toggleAccountDropdown() {
  const dropdown = document.getElementById("accountDropdown");
  const btn      = document.getElementById("accountBtn");
  const isOpen   = dropdown.style.display !== "none";
  dropdown.style.display = isOpen ? "none" : "block";
  btn.classList.toggle("open", !isOpen);
}

document.addEventListener("click", e => {
  const dropdown = document.getElementById("accountDropdown");
  const btn      = document.getElementById("accountBtn");
  if (!dropdown || dropdown.style.display === "none") return;
  if (!dropdown.contains(e.target) && !btn.contains(e.target)) {
    dropdown.style.display = "none";
    btn.classList.remove("open");
  }
});

document.addEventListener("keydown", e => {
  if (e.key !== "Escape") return;
  const dropdown = document.getElementById("accountDropdown");
  const btn      = document.getElementById("accountBtn");
  if (dropdown) dropdown.style.display = "none";
  if (btn)      btn.classList.remove("open");
});
```

- [ ] **Step 2: Verify toggle behavior**

At `http://localhost:3000`, sign in and confirm:
- Clicking the avatar opens the panel; avatar gets a ring (`box-shadow`)
- Clicking the avatar again closes the panel
- Clicking anywhere outside the panel closes it
- Pressing Escape closes it

- [ ] **Step 3: Verify sign-out from dropdown**

Click the avatar to open the panel, then click "Sign out":
- Panel closes
- Avatar disappears
- Sign in button reappears
- Tool cards re-lock (Finance/Reporting cards lock back up)

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: account dropdown toggle, click-outside, Escape dismiss"
```

---

## Final verification checklist

Before pushing to `testing`:

- [ ] Topbar before sign-in: theme toggle + GitHub icon + Sign in button only — no avatar, no badges, no sign-out
- [ ] Topbar after sign-in: theme toggle + GitHub icon + avatar circle (initials) only
- [ ] Clicking avatar opens panel: larger avatar + full name + email in head
- [ ] Finance View member: Finance View amber pill visible in Access section
- [ ] Reporting View member: Reporting View blue pill visible
- [ ] GSD member: GSD Access blue pill visible
- [ ] No special access: Access section hidden entirely — panel shows identity + sign out only
- [ ] Click outside panel: closes and removes avatar ring
- [ ] Escape key: closes panel
- [ ] Sign out button in panel: calls `hubSignOut()`, avatar disappears, sign-in button returns, cards re-lock
- [ ] Light mode + dark mode: panel uses CSS custom properties and looks correct in both themes

- [ ] **Push to preview**

```bash
git push
```

Expected: GitHub Actions deploys to `jgdev-ch.github.io/it-tools-preview/` within ~60 seconds.
