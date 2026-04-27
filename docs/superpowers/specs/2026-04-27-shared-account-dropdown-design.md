# Shared Tool Header — Account Dropdown Design Spec

**Goal:** Replace the `user-chip` + separate Sign Out button in every tool's topbar with the same avatar-only circle → dropdown panel from the hub. The dropdown shows the signed-in user's name, email, their complete access pills (all 4 gates checked centrally, not just those relevant to the current tool), and sign-out. The entire change lives in `shared/auth.js` and `shared/styles.css` — zero per-tool file changes.

**Scope:** `shared/auth.js`, `shared/styles.css` only.

**Tech Stack:** Vanilla JS, CSS custom properties (shared design tokens), Lucide SVG icons (same strings as hub).

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Gate check location | Centralized in shared module, triggered by `setUser()` | All tools always show the complete access picture regardless of which tool-level gate checks they run |
| Gate check method | `checkMemberObjects` POST (all 4 IDs in one call) | Same pattern as hub — single round-trip, works regardless of total group count |
| Pills on sign-out | Cleared immediately | `clearUser()` resets dropdown; no stale access shown |
| Individual tool files | No changes | `renderTopbar()` and `setUser()` already provide the integration surface |
| `onclick` attributes | Replaced with `addEventListener` | Private IIFE functions can't be referenced by inline `onclick` strings |

---

## What's Removed

### From `shared/styles.css`

| Block | Lines (approx) | Fate |
|---|---|---|
| `.user-chip` | ~159–163 | Deleted — replaced by `.account-btn` |
| `.user-avatar` | ~164–169 | Deleted — replaced by `.account-panel-avatar` |
| `.btn-sm-ghost` | ~179–185 | Deleted — was used only as the sign-out button; verify no other usages before removing |
| `.user-chip span:not(.user-avatar)` mobile rule | ~420 | Deleted |

### From `shared/auth.js` — `ITTools.ui`

| Element | Fate |
|---|---|
| `#userChip` div in `renderTopbar()` HTML | Deleted |
| `#userInitials` div | Deleted |
| `#userName` span | Deleted |
| `#signOutBtn` button | Deleted |
| `setUser()` body (chip + btn logic) | Replaced |
| `clearUser()` body (chip + btn logic) | Replaced |

---

## What's Added

### `shared/styles.css` — new token

Add `--blue-border` to both `:root` and `[data-theme="dark"]` (absent from shared styles today, required by `.account-pill--blue`):

```css
/* in :root */
--blue-border: #93c5fd;

/* in [data-theme="dark"] */
--blue-border: #2d4a7a;
```

### `shared/styles.css` — new component CSS

Add after the `.btn-icon` block:

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

---

### `shared/auth.js` — new constants inside `ITTools.ui` IIFE

```js
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

---

### `shared/auth.js` — `renderTopbar()` — updated HTML injection

Replace the `user-chip` + `signOutBtn` HTML with:

```html
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
```

After setting `el.innerHTML`, wire up all event listeners via JS (private IIFE functions cannot be referenced by `onclick` attributes):

```js
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
```

---

### `shared/auth.js` — `_toggleAccountDropdown()` (private)

```js
function _toggleAccountDropdown() {
  const dropdown = document.getElementById("accountDropdown");
  const btn      = document.getElementById("accountBtn");
  const isOpen   = dropdown.style.display !== "none";
  dropdown.style.display = isOpen ? "none" : "block";
  btn.classList.toggle("open", !isOpen);
  btn.setAttribute("aria-expanded", String(!isOpen));
}
```

---

### `shared/auth.js` — `setUser(account)` — updated

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

---

### `shared/auth.js` — `clearUser()` — updated

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

---

### `shared/auth.js` — `_loadGatePills()` (private async)

```js
async function _loadGatePills() {
  try {
    const token = await ITTools.auth.getToken();
    const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
      method:  "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body:    JSON.stringify({ ids: Object.values(GROUP_GATE_IDS) }),
    });
    if (!res.ok) return;
    const data = await res.json();
    const unlockedIds  = new Set(data.value || []);
    const unlockedKeys = Object.entries(GROUP_GATE_IDS)
      .filter(([, id]) => unlockedIds.has(id))
      .map(([key]) => key);
    _renderPills(unlockedKeys);
  } catch (_) {}
}
```

---

### `shared/auth.js` — `_renderPills(keys)` (private)

```js
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
```

---

### `shared/auth.js` — `ITTools.auth.signOut()` — updated

Add `ITTools.ui.clearUser?.()` before the logout popup so the UI resets immediately, even if the tool has no `onSignOut` handler:

```js
async function signOut() {
  ITTools.ui.clearUser?.();
  await _msal.logoutPopup({ account: _account });
  _account = null;
  ITTools.auth._onSignOut?.();
}
```

(`ITTools.ui` is defined later in the file but will be populated by call time.)

---

## What's Unchanged

- `renderTopbar()` function signature — no tool call sites change
- `setUser()` call sites in tool files — no changes
- Tool-level gate check functions — still run for their own access-control logic (showing/hiding gated content); the shared gate check is additive for the dropdown only
- Theme button in topbar — no changes
- Hub `index.html` — no changes (has its own standalone implementation)
- All other `ITTools.ui` methods — no changes

---

## Edge Cases

| Case | Behavior |
|---|---|
| User has no special access | Access section hidden; panel shows identity + sign-out only |
| Gate check fails (network error) | Silently swallowed — pills section stays hidden, tool still functions |
| `setUser()` called before DOM ready | Guarded — `getElementById` returns null, no crash |
| Sign-out before pills load | `clearUser()` hides dropdown; if `_loadGatePills()` completes after, `_renderPills()` updates hidden elements — no visual glitch |
| `.btn-sm-ghost` used elsewhere | Grep all tool files for `.btn-sm-ghost` before deleting from CSS; if found, keep the class or migrate those usages |
