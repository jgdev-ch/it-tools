# Hub Layout Redesign — Design Spec
**Date:** 2026-03-30
**Files touched:** `index.html`, `config.json`

---

## Overview

Two focused improvements to the IT Tools Hub home page as the tool count grows beyond 6:

1. **Tool categorization** — group cards into labelled sections instead of a flat grid
2. **Collapsible Setup** — collapse the always-visible setup card into a pill toggle

Both changes are purely cosmetic and structural. No auth logic, no Graph calls, no shared helper changes.

---

## 1. Tool Categorization

### Sections

| Section label | Tools |
|---|---|
| Daily Operations | Group Import, Name Resolver |
| Reporting & Audit | License Audit, MFA Status Report, Guest Access Audit, License Spend |

"License Spend" remains gated (locked card) for non-finance users within its section — gating behaviour is unchanged.

### Data model change — `config.json`

Each tool entry gains a `category` field:

```json
{ "id": "group-import", "category": "daily-ops", ... }
{ "id": "name-resolver", "category": "daily-ops", ... }
{ "id": "license-audit", "category": "reporting-audit", ... }
{ "id": "mfa-status",    "category": "reporting-audit", ... }
{ "id": "guest-audit",   "category": "reporting-audit", ... }
{ "id": "finance-dashboard", "category": "reporting-audit", ... }
```

Valid category values: `"daily-ops"`, `"reporting-audit"`. Future tools are categorized by adding this field — no JS changes required.

### Render logic change — `index.html`

The existing flat `data.tools.map(...)` render is replaced with a grouped render:

```
SECTIONS = [
  { key: "daily-ops",       label: "Daily Operations" },
  { key: "reporting-audit", label: "Reporting & Audit" }
]

for each section:
  render <div class="section-label">{label}</div>
  render <div class="tools-grid"> … tools in this section … </div>
```

Tools without a `category` field (future-proofing) fall through to an "Other" section appended at the end — no tool is ever silently dropped.

The existing `.section-label` and `.tools-grid` CSS classes are reused unchanged. No new CSS needed for the grid itself.

---

## 2. Collapsible Setup

### Behaviour

- Rendered below the last tool section
- **Default state:** collapsed — displays as a compact pill: `⚙️  Setup  ▾`
- **Expanded state:** pill becomes a full-width toggle button (`⚙️  Setup  ▴`) with the setup card revealed immediately below it
- **Toggle:** clicking the pill/button flips state
- **Persistence:** `localStorage` key `ittools_setup_open` stores `"true"` or `"false"`; if key is absent (first visit), defaults to collapsed

### HTML structure

```html
<!-- Toggle trigger (replaces current .section-label + .setup-card) -->
<button class="setup-toggle" id="setupToggle" onclick="toggleSetup()">
  <span>⚙️</span>
  <span>Setup</span>
  <span class="setup-chevron" id="setupChevron">▾</span>
</button>
<div class="setup-card" id="setupCard" hidden>
  <!-- existing content unchanged -->
</div>
```

### New CSS (added to `index.html` `<style>` block)

```css
.setup-toggle {
  display: inline-flex; align-items: center; gap: 6px;
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 20px; padding: 5px 14px 5px 10px;
  font-size: 12px; font-weight: 600; color: var(--muted);
  cursor: pointer; transition: border-color .15s, color .15s;
  margin-bottom: 0;
}
.setup-toggle:hover { border-color: var(--border-mid); color: var(--text); }
.setup-toggle.open {
  border-radius: 8px 8px 0 0; border-bottom-color: var(--surface3);
  width: 100%; justify-content: flex-start;
}
.setup-toggle.open + .setup-card { border-radius: 0 0 8px 8px; border-top: none; }
.setup-chevron { font-size: 10px; color: var(--muted2); margin-left: auto; }
```

### JS (added to `index.html` `<script>` block)

```js
function toggleSetup() {
  const open = localStorage.getItem('ittools_setup_open') === 'true';
  const next = !open;
  localStorage.setItem('ittools_setup_open', next);
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

// Called once after auth / page load:
applySetupState(localStorage.getItem('ittools_setup_open') === 'true');
```

---

## Out of Scope

- Reordering tools within a section (order follows `config.json` as today)
- Adding a search or filter bar to the hub
- Any changes to individual tool pages
- Changing the gating logic for finance-only tools
