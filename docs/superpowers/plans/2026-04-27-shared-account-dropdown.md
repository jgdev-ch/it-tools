# Shared Tool Header — Account Dropdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the old `user-chip` + Sign Out button in every tool's topbar with the same avatar-only circle → account dropdown from the hub, showing the user's full name, email, all 4 access pills (checked centrally via Graph), and sign-out.

**Architecture:** All changes live in `shared/auth.js` and `shared/styles.css` — no individual tool files are touched. `renderTopbar()` injects the new dropdown HTML and wires event listeners. `setUser()` populates identity fields and fires `_loadGatePills()` async, which POSTs all 4 group IDs to `checkMemberObjects` and calls `_renderPills()`. `clearUser()` and `signOut()` reset the dropdown state.

**Tech Stack:** Vanilla JS, CSS custom properties (shared design tokens), Lucide SVGs (inline, same strings as hub).

---

## File Map

| File | Change |
|---|---|
| `shared/styles.css` | Add `button { font-family: inherit; }` to reset; remove `.user-chip`, `.user-avatar`, mobile rule; add `--blue-border` token; add account dropdown CSS |
| `shared/auth.js` | Add `GROUP_GATE_IDS`, `PILL_DEFS`, `_toggleAccountDropdown`, `_loadGatePills`, `_renderPills`; update `renderTopbar()`, `setUser()`, `clearUser()`, `signOut()` |

**Note:** `.btn-sm-ghost` in `shared/styles.css` must NOT be removed — `finance-dashboard` uses it for pagination buttons.

---

## Task 1: Update `shared/styles.css`

**Files:**
- Modify: `shared/styles.css`

- [ ] **Step 1: Add `button { font-family: inherit; }` to the CSS reset**

Browsers don't inherit `font-family` from `body` on `<button>` elements by default — they use the system font. This one-line fix ensures Open Sans is used on all buttons (avatar circle, dropdown sign-out, pagination, etc.) globally without patching each class individually.

Find the reset block at the top of `shared/styles.css`:

```css
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
```

Add the following line immediately after it:

```css
button, input, select, textarea { font-family: inherit; }
```

- [ ] **Step 2: Add `--blue-border` token to `:root`**

In `shared/styles.css`, find the `--blue-mid` line inside `:root` and add the token on the next line:

```css
  --blue-mid:    #4285f4;
  --blue-border: #93c5fd;
```

- [ ] **Step 3: Add `--blue-border` token to `[data-theme="dark"]`**

Find `--blue-mid` inside `[data-theme="dark"]` and add:

```css
  --blue-mid:    #5a9fd4;
  --blue-border: #2d4a7a;
```

- [ ] **Step 4: Remove `.user-chip` and `.user-avatar` blocks**

Find and delete this entire block (lines ~159–169):

```css
.user-chip {
  display: flex; align-items: center; gap: 7px;
  background: var(--surface3); border-radius: 20px;
  padding: 3px 12px 3px 4px; font-size: 13px; font-weight: 500;
}
.user-avatar {
  width: 24px; height: 24px; border-radius: 50%;
  background: var(--blue-light); color: var(--blue-dark);
  display: flex; align-items: center; justify-content: center;
  font-size: 10px; font-weight: 700;
}
```

- [ ] **Step 5: Remove the mobile `.user-chip` rule**

Find and delete this line inside the `@media (max-width: 640px)` block (line ~420):

```css
  .user-chip span:not(.user-avatar) { display: none; }
```

- [ ] **Step 6: Add account dropdown CSS after the `.btn-icon` block**

Find the end of the `.btn-icon:hover` rule:

```css
.btn-icon:hover { background: var(--surface3); color: var(--text); }
```

Insert the following block immediately after it:

```css
/* ── Account avatar button (topbar) ── */
.account-btn {
  width: 30px; height: 30px; border-radius: 50%;
  background: var(--blue); border: none;
  font-size: 11px; font-weight: 800; color: #fff;
  cursor: pointer; display: flex; align-items: center; justify-content: center;
  transition: opacity .15s; flex-shrink: 0;
}
.account-btn:hover { opacity: .85; }
.account-btn.open { box-shadow: 0 0 0 2px var(--surface2), 0 0 0 4px var(--blue); }

/* ── Dropdown panel ── */
.account-dropdown {
  position: absolute; right: 0; top: calc(100% + 8px);
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 10px; box-shadow: 0 8px 28px rgba(0,0,0,.35);
  min-width: 220px; max-width: 320px; z-index: 200; overflow: hidden;
}

/* Panel head — avatar + name + email */
.account-panel-head {
  display: flex; align-items: center; gap: 10px;
  padding: 13px 14px 12px; border-bottom: 1px solid var(--border);
}
.account-panel-avatar {
  width: 36px; height: 36px; border-radius: 50%;
  background: var(--blue); flex-shrink: 0;
  font-size: 13px; font-weight: 800; color: #fff;
  display: flex; align-items: center; justify-content: center;
}
.account-panel-name  { font-size: 13px; font-weight: 700; color: var(--text); }
.account-panel-email { font-size: 11px; color: var(--muted2); margin-top: 1px; }

/* Access section */
.account-panel-access { padding: 10px 14px 8px; }
.account-panel-access-label {
  font-size: 10px; font-weight: 700; text-transform: uppercase;
  letter-spacing: .06em; color: var(--muted2); margin-bottom: 7px;
}
.account-panel-pills { display: flex; flex-direction: column; gap: 5px; }

/* Access pills */
.account-pill {
  display: inline-flex; align-items: center; gap: 5px;
  padding: 4px 10px; border-radius: 20px;
  font-size: 11px; font-weight: 700; letter-spacing: .04em; text-transform: uppercase;
  width: fit-content;
}
.account-pill--amber {
  background: var(--amber-light); border: 1px solid var(--amber-border); color: var(--amber);
}
.account-pill--blue {
  background: var(--blue-light); border: 1px solid var(--blue-border); color: var(--blue-dark);
}

/* Divider */
.account-panel-divider { height: 1px; background: var(--border); }

/* Sign out row */
.account-panel-signout {
  display: flex; align-items: center; gap: 8px;
  width: 100%; padding: 10px 14px;
  background: transparent; border: none;
  font-size: 12px; color: var(--muted2); cursor: pointer; text-align: left; font-family: inherit;
}
.account-panel-signout:hover { color: var(--red); background: var(--red-light); }
```

- [ ] **Step 7: Verify CSS parses cleanly**

Open any tool in a browser (e.g. `tools/license-audit/index.html` via the preview URL). Open DevTools → Console. Confirm no CSS parse errors. The topbar still renders (auth button visible, theme toggle works). No visual regressions on non-auth elements.

- [ ] **Step 8: Commit**

```bash
git add shared/styles.css
git commit -m "style: add font-family reset, replace user-chip CSS with account dropdown styles"
```

---

## Task 2: Add constants and private functions to `ITTools.ui`

**Files:**
- Modify: `shared/auth.js`

- [ ] **Step 1: Add `GROUP_GATE_IDS` and `PILL_DEFS` constants at the top of `ITTools.ui`**

Find this line in `shared/auth.js`:

```js
ITTools.ui = (() => {
```

Insert the following constants immediately after the opening line (before `renderTopbar`):

```js
ITTools.ui = (() => {

  const GROUP_GATE_IDS = {
    finance:           "ff9c3232-251f-4570-9564-340039d17aa9",
    reporting:         "cea8f0fe-a3d5-4f8a-9f77-e9ce6fdf7b8d",
    gsd:               "3e1a4757-8189-4908-a611-b6029399e69e",
    "license-modify":  "d98cbaa9-da66-4d1a-8a31-2442b7cc0ca8",
  };

  const PILL_DEFS = {
    finance: {
      label: "Finance View",
      cls:   "account-pill--amber",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8"/><path d="M12 18V6"/></svg>`,
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
    "license-modify": {
      label: "License Admin",
      cls:   "account-pill--amber",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/></svg>`,
    },
  };
```

- [ ] **Step 2: Add `_toggleAccountDropdown`, `_loadGatePills`, `_renderPills` private functions**

Find this line inside `ITTools.ui`:

```js
  function renderTopbar({ toolName, hubRelPath = "../../", status = "", scopes = [], onReady } = {}) {
```

Insert the three private functions immediately before it:

```js
  function _toggleAccountDropdown() {
    const dropdown = document.getElementById("accountDropdown");
    const btn      = document.getElementById("accountBtn");
    const isOpen   = dropdown.style.display !== "none";
    dropdown.style.display = isOpen ? "none" : "block";
    btn.classList.toggle("open", !isOpen);
    btn.setAttribute("aria-expanded", String(!isOpen));
  }

  async function _loadGatePills() {
    try {
      const token = await ITTools.auth.getToken();
      const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
        method:  "POST",
        headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
        body:    JSON.stringify({ ids: Object.values(GROUP_GATE_IDS) }),
      });
      if (!res.ok) return;
      const data        = await res.json();
      const unlockedIds = new Set(data.value || []);
      const unlockedKeys = Object.entries(GROUP_GATE_IDS)
        .filter(([, id]) => unlockedIds.has(id))
        .map(([key]) => key);
      _renderPills(unlockedKeys);
    } catch (_) {}
  }

  function _renderPills(keys) {
    const pillsEl  = document.getElementById("accountPanelPills");
    const accessEl = document.getElementById("accountPanelAccess");
    if (!pillsEl || !accessEl) return;
    const pills = keys.filter(k => PILL_DEFS[k])
                      .sort((a, b) => PILL_DEFS[a].cls.localeCompare(PILL_DEFS[b].cls));
    if (!pills.length) { accessEl.style.display = "none"; return; }
    pillsEl.innerHTML = pills
      .map(k => `<span class="account-pill ${PILL_DEFS[k].cls}">${PILL_DEFS[k].icon} ${PILL_DEFS[k].label}</span>`)
      .join("");
    accessEl.style.display = "block";
  }

  function renderTopbar({ toolName, hubRelPath = "../../", status = "", scopes = [], onReady } = {}) {
```

- [ ] **Step 3: Verify the file has no syntax errors**

Open browser DevTools console on any tool page. Run:

```js
typeof ITTools.ui.renderTopbar
```

Expected: `"function"` — the module still loads.

- [ ] **Step 4: Commit**

```bash
git add shared/auth.js
git commit -m "feat: add GROUP_GATE_IDS, PILL_DEFS, and private dropdown helpers to ITTools.ui"
```

---

## Task 3: Update `renderTopbar()` HTML and wire event listeners

**Files:**
- Modify: `shared/auth.js`

- [ ] **Step 1: Replace the `user-chip` and `signOutBtn` HTML in `renderTopbar()`**

Find this exact block inside the `el.innerHTML` template string in `renderTopbar()`:

```js
        <div class="user-chip" id="userChip" style="display:none">
          <div class="user-avatar" id="userInitials"></div>
          <span id="userName"></span>
        </div>
        <button class="btn-sm-ghost" id="signOutBtn" onclick="ITTools.auth.signOut()" style="display:none">Sign out</button>
      </div>
    `;
```

Replace it with:

```js
        <div style="position:relative" id="accountWrap">
          <button type="button" class="account-btn" id="accountBtn"
            style="display:none" aria-label="Account menu"
            aria-expanded="false" aria-controls="accountDropdown">
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
            <button type="button" class="account-panel-signout" id="accountSignOutBtn">
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
              Sign out
            </button>
          </div>
        </div>
      </div>
    `;
```

- [ ] **Step 2: Wire event listeners after `syncThemeIcon()` call in `renderTopbar()`**

Find this line at the end of `renderTopbar()`:

```js
    syncThemeIcon();
  }
```

Replace it with:

```js
    syncThemeIcon();

    document.getElementById("accountBtn").addEventListener("click", _toggleAccountDropdown);
    document.getElementById("accountSignOutBtn").addEventListener("click", () => ITTools.auth.signOut());
    document.addEventListener("click", e => {
      const dropdown = document.getElementById("accountDropdown");
      const btn      = document.getElementById("accountBtn");
      if (!dropdown || dropdown.style.display === "none") return;
      if (!dropdown.contains(e.target) && !btn.contains(e.target)) {
        dropdown.style.display = "none";
        btn.classList.remove("open");
        btn.setAttribute("aria-expanded", "false");
      }
    });
    document.addEventListener("keydown", e => {
      if (e.key !== "Escape") return;
      const dropdown = document.getElementById("accountDropdown");
      if (!dropdown || dropdown.style.display === "none") return;
      const btn = document.getElementById("accountBtn");
      dropdown.style.display = "none";
      if (btn) { btn.classList.remove("open"); btn.setAttribute("aria-expanded", "false"); }
    });
  }
```

- [ ] **Step 3: Verify topbar renders correctly before sign-in**

Open a tool (e.g. `tools/name-resolver/index.html` on the preview URL). Before signing in:
- Topbar is visible with the IT Tools brand and tool name ✓
- Theme toggle button is present and functional ✓
- No avatar button visible (hidden until signed in) ✓
- No console errors ✓

- [ ] **Step 4: Commit**

```bash
git add shared/auth.js
git commit -m "feat: update renderTopbar() with account dropdown HTML and event listeners"
```

---

## Task 4: Update `setUser()`, `clearUser()`, and `signOut()`

**Files:**
- Modify: `shared/auth.js`

- [ ] **Step 1: Replace `setUser()` body**

Find and replace the entire `setUser` function:

```js
  function setUser(account) {
    if (!account) return;
    const name = account.name || account.username || "User";
    const initials = name.split(" ").map(n => n[0]).join("").slice(0, 2).toUpperCase();
    const chip = document.getElementById("userChip");
    const btn  = document.getElementById("signOutBtn");
    if (chip) { document.getElementById("userInitials").textContent = initials; document.getElementById("userName").textContent = name; chip.style.display = "flex"; }
    if (btn)  btn.style.display = "block";
  }
```

Replace with:

```js
  function setUser(account) {
    if (!account) return;
    const name     = account.name || account.username || "User";
    const email    = account.username || "";
    const initials = name.split(" ").map(n => n[0]).join("").slice(0, 2).toUpperCase();
    document.getElementById("accountInitials").textContent    = initials;
    document.getElementById("accountPanelAvatar").textContent = initials;
    document.getElementById("accountPanelName").textContent   = name;
    document.getElementById("accountPanelEmail").textContent  = email;
    document.getElementById("accountBtn").style.display       = "flex";
    _loadGatePills();
  }
```

- [ ] **Step 2: Replace `clearUser()` body**

Find and replace the entire `clearUser` function:

```js
  function clearUser() {
    const chip = document.getElementById("userChip");
    const btn  = document.getElementById("signOutBtn");
    if (chip) chip.style.display = "none";
    if (btn)  btn.style.display  = "none";
  }
```

Replace with:

```js
  function clearUser() {
    const btn      = document.getElementById("accountBtn");
    const dropdown = document.getElementById("accountDropdown");
    if (!btn) return;
    btn.style.display = "none";
    btn.classList.remove("open");
    btn.setAttribute("aria-expanded", "false");
    if (dropdown) dropdown.style.display = "none";
    const pillsEl  = document.getElementById("accountPanelPills");
    const accessEl = document.getElementById("accountPanelAccess");
    if (pillsEl)  pillsEl.innerHTML      = "";
    if (accessEl) accessEl.style.display = "none";
  }
```

- [ ] **Step 3: Update `signOut()` in `ITTools.auth` to call `clearUser` first**

Find the `signOut` function in the `ITTools.auth` IIFE (near line 95):

```js
  async function signOut() {
    await _msal.logoutPopup({ account: _account });
    _account = null;
    ITTools.auth._onSignOut?.();
  }
```

Replace with:

```js
  async function signOut() {
    ITTools.ui.clearUser?.();
    await _msal.logoutPopup({ account: _account });
    _account = null;
    ITTools.auth._onSignOut?.();
  }
```

- [ ] **Step 4: Verify full sign-in flow in browser**

Open a tool (e.g. `tools/license-audit/index.html` on the preview URL) and sign in with your Microsoft account:

- After sign-in: avatar circle appears in topbar with correct initials ✓
- Click avatar: dropdown opens showing full name and email ✓
- A beat after open: access pills appear (amber Finance View / License Admin first, blue Reporting View / GSD Access second) — only shows pills for groups the signed-in account is actually in ✓
- Click avatar again: dropdown closes ✓
- Click outside dropdown: dropdown closes ✓
- Press Escape while dropdown open: dropdown closes ✓
- `.open` ring appears on avatar while dropdown is open ✓
- Click Sign out in dropdown: MSAL logout popup opens, after logout avatar disappears ✓

- [ ] **Step 5: Verify hub is unaffected**

Navigate to the hub (`index.html`). The hub has its own standalone implementation — confirm:
- Hub topbar still shows the hub's avatar button (not the shared one) ✓
- Hub account dropdown still works ✓
- Hub gate cards still unlock ✓

- [ ] **Step 6: Verify finance-dashboard pagination is unaffected**

Open `tools/finance-dashboard/index.html` and run a report. Confirm the Prev/Next pagination buttons (which use `.btn-sm-ghost`) still render and function correctly — the CSS class was not removed.

- [ ] **Step 7: Commit**

```bash
git add shared/auth.js
git commit -m "feat: update setUser/clearUser/signOut for account dropdown in shared tools"
```

---

## Task 5: Push to preview and smoke-test remaining tools

**Files:** None

- [ ] **Step 1: Push to preview**

```bash
git push origin testing
```

- [ ] **Step 2: Smoke-test each tool**

Open each tool on the preview URL and sign in. Confirm the account dropdown appears and shows the correct identity + pills for each:

| Tool | URL path | Expected pills (for your account) |
|---|---|---|
| License Audit | `tools/license-audit/` | Finance View, License Admin, Reporting View, GSD Access |
| License Spend | `tools/finance-dashboard/` | Finance View, License Admin, Reporting View, GSD Access |
| Guest Access Audit | `tools/guest-audit/` | Reporting View, GSD Access |
| MFA Status Report | `tools/mfa-status/` | Reporting View, GSD Access |
| Name Resolver | `tools/name-resolver/` | GSD Access |
| Group Import | `tools/group-import/` | GSD Access |

- [ ] **Step 3: Confirm theme toggle still works across light/dark in each tool**

Toggle dark ↔ light in at least two tools. Confirm avatar and dropdown render correctly in both themes.
