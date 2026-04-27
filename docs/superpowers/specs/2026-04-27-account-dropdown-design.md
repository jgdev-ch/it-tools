# Account Dropdown — Design Spec

**Goal:** Replace the scattered topbar badges + sign-out button with a clean avatar-only chip that opens an account dropdown panel showing the user's full name, email, access pills, and sign-out. Cleans up the header and consolidates identity/access information into a single familiar UX pattern.

**Scope:** `index.html` (hub only). No changes to individual tool files.

**Tech Stack:** Vanilla JS, inline CSS, Lucide SVG icons (matching existing badge icons), no new dependencies.

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Header element | Avatar circle only (initials, e.g. "JG") | Name length varies globally — avatar avoids pushing icons left |
| Dropdown trigger | Click avatar → panel appears below-right | Standard UX muscle memory |
| Panel content | Avatar + full name + email, "Access" label, stacked pills, sign-out row | Option 1 from brainstorm |
| No-access state | Hide Access section entirely | Silence is clear; pills carry weight when shown |
| Sign out | Moves into dropdown panel | Removes separate button from header |
| Hub badges | Removed entirely | Replaced by dropdown |
| Close behavior | Click outside or press Escape | Standard dropdown dismiss |

---

## What's Removed

| Element | Location | Fate |
|---|---|---|
| `#hubBadges` div | `index.html` line 274 | Deleted |
| `#userChip` (chip with name) | `index.html` lines 277–280 | Replaced by `#accountBtn` avatar |
| `#userName` span | `index.html` line 279 | Deleted (name moves into dropdown) |
| `#signOutBtn` button | `index.html` line 283 | Deleted (sign-out moves into dropdown) |
| `.user-chip`, `.user-chip.show` | CSS line 58–63 | Deleted |
| `.user-avatar` | CSS line 64 | Deleted |
| `.btn-signout`, `.btn-signout.*` | CSS lines 70–77 | Deleted |
| `.hub-access-badge*` | CSS lines 34–43 | Deleted |
| `renderHubBadges()` | JS line 495 | Deleted — replaced by `renderAccountDropdown()` |

---

## What's Added

### HTML — hub topbar

Replace the removed elements with two new elements inside `.hub-topbar-right`:

```html
<!-- Avatar button — shown after sign-in -->
<button class="account-btn" id="accountBtn" onclick="toggleAccountDropdown()" style="display:none" aria-label="Account">
  <span id="accountInitials"></span>
</button>

<!-- Account dropdown panel — hidden until avatar clicked -->
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
    <!-- Lucide log-out SVG --> Sign out
  </button>
</div>
```

The `#accountDropdown` is positioned absolutely (relative to `.hub-topbar-right`) so it drops below the avatar and aligns to the right edge.

### CSS additions

```css
/* ── Account avatar button (topbar) ── */
.account-btn {
  width: 30px; height: 30px; border-radius: 50%;
  background: var(--accent); border: none;
  font-size: 11px; font-weight: 800; color: #fff;
  cursor: pointer; display: flex; align-items: center; justify-content: center;
  transition: opacity .15s;
  flex-shrink: 0;
}
.account-btn:hover { opacity: .85; }
.account-btn.open { box-shadow: 0 0 0 2px var(--accent); }

/* ── Dropdown panel ── */
.account-dropdown {
  position: absolute; right: 0; top: calc(100% + 8px);
  background: var(--card); border: 1px solid var(--border);
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
  background: var(--accent); flex-shrink: 0;
  font-size: 13px; font-weight: 800; color: #fff;
  display: flex; align-items: center; justify-content: center;
}
.account-panel-name  { font-size: 13px; font-weight: 700; color: var(--text); }
.account-panel-email { font-size: 11px; color: var(--muted2); margin-top: 1px; }

/* Access section */
.account-panel-access { padding: 10px 14px 6px; border-bottom: 1px solid var(--border); }
.account-panel-access-label {
  font-size: 10px; font-weight: 700; text-transform: uppercase;
  letter-spacing: .06em; color: var(--muted2); margin-bottom: 7px;
}
.account-panel-pills { display: flex; flex-direction: column; gap: 5px; }

/* Access pills (reuse existing badge token colors) */
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
  font-size: 12px; color: var(--muted2); cursor: pointer; text-align: left;
}
.account-panel-signout:hover { color: var(--red); background: var(--red-light); }
```

### JS additions and changes

#### `_accountData` module-level state

```js
let _accountData = null; // { initials, name, email }
```

Stores the signed-in user's display data so the dropdown can be rebuilt after gate checks complete.

#### `showSignedIn(account)` — updated

Current behavior: populates `#userInitials`, `#userName`, shows chip and sign-out button.

New behavior:
- Derive `initials` and `name` from account (same logic as today)
- Derive `email` from `account.username` (MSAL `username` field is the UPN/email)
- Store `_accountData = { initials, name, email }`
- Set `#accountInitials` text and `#accountPanelAvatar` text to `initials`
- Set `#accountPanelName` to `name`, `#accountPanelEmail` to `email`
- Show `#accountBtn` (set `display: flex`)
- Close any open dropdown

#### `showSignedOut()` — updated

- Clear and hide `#accountBtn`
- Hide and clear `#accountDropdown` (set `display:none`, clear `#accountPanelPills`, hide `#accountPanelAccess`)
- Clear `_accountData`
- Remove `.open` class from `#accountBtn`

#### `renderAccountDropdown(unlockedGates)` — new, replaces `renderHubBadges`

```js
function renderAccountDropdown(unlockedGates) {
  const PILL_DEFS = {
    finance:   { label: "Finance View",   cls: "account-pill--amber", icon: /* Lucide shield SVG */ },
    reporting: { label: "Reporting View", cls: "account-pill--blue",  icon: /* Lucide eye SVG */   },
    gsd:       { label: "GSD Access",     cls: "account-pill--blue",  icon: /* Lucide globe SVG */ },
  };
  const pills = unlockedGates.filter(k => PILL_DEFS[k]);
  const pillsEl = document.getElementById("accountPanelPills");
  const accessEl = document.getElementById("accountPanelAccess");
  if (!pills.length) {
    accessEl.style.display = "none";
    return;
  }
  pillsEl.innerHTML = pills
    .map(k => `<span class="account-pill ${PILL_DEFS[k].cls}">${PILL_DEFS[k].icon} ${PILL_DEFS[k].label}</span>`)
    .join("");
  accessEl.style.display = "block";
}
```

Called from `runGateChecks()` (replacing `renderHubBadges(unlocked)`), and also from the localStorage restore path at line 547.

#### `toggleAccountDropdown()` — new

```js
function toggleAccountDropdown() {
  const dropdown = document.getElementById("accountDropdown");
  const btn = document.getElementById("accountBtn");
  const isOpen = dropdown.style.display !== "none";
  dropdown.style.display = isOpen ? "none" : "block";
  btn.classList.toggle("open", !isOpen);
}
```

#### Click-outside + Escape close — new

Added once on `DOMContentLoaded` (or after sign-in):

```js
document.addEventListener("click", e => {
  const dropdown = document.getElementById("accountDropdown");
  const btn = document.getElementById("accountBtn");
  if (dropdown && dropdown.style.display !== "none" &&
      !dropdown.contains(e.target) && !btn.contains(e.target)) {
    dropdown.style.display = "none";
    btn.classList.remove("open");
  }
});
document.addEventListener("keydown", e => {
  if (e.key === "Escape") {
    const dropdown = document.getElementById("accountDropdown");
    const btn = document.getElementById("accountBtn");
    if (dropdown) { dropdown.style.display = "none"; }
    if (btn) { btn.classList.remove("open"); }
  }
});
```

#### `.hub-topbar-right` positioning

Add `position: relative` to `.hub-topbar-right` so the absolute-positioned dropdown anchors correctly.

---

## Lucide SVGs to use in pills (matching existing tool usage)

| Access | Icon name | Existing usage |
|---|---|---|
| Finance View | `shield` | Already in `renderHubBadges` |
| Reporting View | `eye` | Already in `renderHubBadges` |
| GSD Access | `globe` | Already in `renderHubBadges` |
| Sign out | `log-out` | New — standard logout icon |

Copy SVG strings from existing `renderHubBadges` BADGE_DEFS for finance/reporting/gsd. Use `width="12" height="12"` for pills. Use `width="13" height="13"` for sign-out row.

---

## Unchanged

- `.hub-topbar-right` layout (flex, gap, align) — only adds `position: relative`
- Theme toggle button and GitHub link — no changes
- Sign-in button behavior — no changes
- `runGateChecks()` logic — only the final call changes (`renderHubBadges` → `renderAccountDropdown`)
- `hubSignOut()` function itself — only the call site moves (from a button `onclick` to inside the dropdown panel)
- All individual tool files — no changes

---

## Edge Cases

| Case | Behavior |
|---|---|
| User has no special access | Access section hidden; panel shows identity + sign-out only |
| Dropdown open when sign-out clicked | `hubSignOut()` calls `showSignedOut()` which hides and resets dropdown |
| Page refresh with localStorage gate cache | `renderAccountDropdown` called from localStorage restore path at same callsite as today |
| Long name (e.g. "Bartholomew Kingsborough-Pierce") | Panel has `min-width: 220px`, name wraps naturally; avatar in header is always 30px |
| Long email address | Wraps within panel; max-width 320px caps extreme cases while still scaling up to that |
