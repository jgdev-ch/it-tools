# Hub index.html Redesign — Design Spec
Date: 2026-03-26

## Goal
Refactor `index.html` (the IT Tools Hub home page) to:
1. Eliminate duplicated inline CSS by linking to `shared/styles.css`
2. Refresh the UI with a cleaner, more scalable card layout

No changes to `shared/styles.css`, `shared/auth.js`, `config.json`, or any tool pages.

---

## Layout Structure

```
┌─────────────────────────────────────────────────────┐
│ TOPBAR  [🔲 MS logo]  IT Tools Hub  [☀️] [User] [Sign Out] │  ← unchanged
├─────────────────────────────────────────────────────┤
│  IT Tools Hub                    5 tools · 3 active │  ← slim title bar (new)
├─────────────────────────────────────────────────────┤
│  [📊 License Audit]  [👥 Group Import]              │
│  [🔑 MFA Status]     [🛡️ Guest Audit]              │  ← 2-col card grid
│  [💰 Finance Dash]                                  │
└─────────────────────────────────────────────────────┘
```

---

## Components

### 1. Topbar
Unchanged. Retains:
- Microsoft logo icon (links back to hub — no-op on hub page itself)
- "IT Tools Hub" brand name
- Theme toggle button (light/dark)
- User chip (initials + name, shown after sign-in)
- Sign out button (shown after sign-in)

Uses `ITTools.ui.renderTopbar()` from `shared/auth.js` with `toolName: "IT Tools Hub"` and `hubRelPath: "./"`.

### 2. Slim Title Bar
A single row below the topbar, inside the page shell:
- Left: page title "IT Tools Hub" (h1, ~20px, bold)
- Right: dynamic tool count pill — e.g. `5 tools · 3 active` (counts tools where status is `live` or `beta`)
- Count is computed from `config.json` at runtime — no hardcoding

### 3. Tool Card Grid
- 2-column CSS grid (`grid-template-columns: repeat(2, 1fr)`)
- Collapses to 1 column on mobile (`max-width: 600px`)
- Cards are loaded dynamically from `config.json` (existing behavior preserved)

### 4. Tool Card
Each card contains:
- **Icon background**: colored square (uses `iconBg` from config), 32×32px, rounded
- **Emoji icon**: from config `icon` field
- **Tool name**: bold, 14px
- **Description**: muted, 12px, 2-line clamp
- **Corner ribbon badge**: top-right, colored by status:
  - `live` → green background, "Live"
  - `beta` → blue background, "Beta"
  - `coming-soon` → gray background, "Soon"
  - `financeOnly: true` → amber "Finance" badge replaces status badge
- Cards with `path` set are clickable links; `coming-soon` cards are not clickable

### 5. Coming Soon Overlay
Cards where `status === "coming-soon"`:
- Frosted semi-transparent overlay (`rgba` + slight blur) covers the entire card
- Centered "Coming Soon" pill label on the overlay
- Card content visible underneath but not interactive
- `cursor: default`, no hover effect

### 6. Auth Screen
Unchanged. Shown before sign-in. Existing sign-in card with Microsoft button is preserved.

---

## CSS Strategy (Option 1)

`index.html` links to `shared/styles.css` for all design tokens and shared components:
```html
<link rel="stylesheet" href="shared/styles.css"/>
```

A small `<style>` block in `index.html` contains only hub-specific styles:
- `.hub-shell` — page max-width and padding
- `.hub-title-bar` — slim title row layout
- `.tools-grid` — 2-column grid
- `.tool-card` — card layout, hover state, cursor
- `.tool-card-ribbon` — corner badge positioning and color variants
- `.tool-card-overlay` — frosted coming-soon overlay

No design tokens are duplicated. All colors, spacing, shadows, and typography reference CSS variables from `shared/styles.css`.

---

## Data Flow

1. Page loads → `ITTools.theme.init()` applies saved theme
2. `ITTools.ui.renderTopbar()` renders the topbar
3. `fetch("config.json")` loads tool definitions
4. Title bar tool count is computed from loaded config
5. Cards are rendered into the grid from config data
6. `ITTools.auth.init()` checks for cached session → shows auth screen or tool grid

---

## Error Handling

- If `config.json` fails to load: show an inline error banner in the grid area
- If MSAL init throws (popup callback edge case): silently catch and stop render (existing behavior)
- `coming-soon` tools with no `path` are rendered but not linked — no 404 risk

---

## Out of Scope

- Changes to any tool pages (`tools/*/index.html`)
- Changes to `shared/styles.css` or `shared/auth.js`
- Search or filter functionality (can be added later without layout changes)
- New tools (Guest Access Audit build is a separate task)
