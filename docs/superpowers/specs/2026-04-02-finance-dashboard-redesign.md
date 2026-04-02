# Finance Dashboard Redesign — Design Spec
Date: 2026-04-02

## Goal

Redesign `tools/finance-dashboard/index.html` with the **Dark Executive Terminal** aesthetic — visually striking, data-forward, and equally usable by a power analyst and an executive scanning headline numbers. Supports both light and dark mode via CSS variables, and adds a print/PDF export path alongside the existing CSV exports.

No changes to `shared/styles.css`, `shared/auth.js`, `shared/msal-browser.min.js`, or any other tool pages.

---

## Design Direction

**Dark Executive Terminal.** Deep navy base, colored accent lines on KPI cards, JetBrains Mono for all numeric values, Syne for the page title, Open Sans for all UI chrome and body text. Numbers are the hero — every dollar value, seat count, and percentage reads immediately at a glance.

This aesthetic is consistent with the existing hub palette (the hub already uses CSS variables for cyan, amber, emerald, and rose accent colors) and works in both dark and light mode without introducing new design tokens beyond what is already in `shared/styles.css`.

---

## Typography

| Role | Font | Usage |
|------|------|-------|
| UI chrome | Open Sans (from `shared/styles.css`) | Topbar, labels, buttons, descriptions, table text — inherited from shared |
| Numeric values | JetBrains Mono | All dollar amounts, seat counts, percentages, dates in the data layer |
| Page title | Syne 700 | "License Spend" heading only — loaded locally in `finance-dashboard/index.html` |

`shared/styles.css` already imports Open Sans and sets it as `body { font-family }`. JetBrains Mono and Syne are loaded via a `<link>` in `finance-dashboard/index.html` only — no impact on other tools.

---

## Color Tokens

All colors reference existing CSS variables from `shared/styles.css`. Two local additions are already in the file (`--teal`, `--teal-light`, `--teal-border`) and are retained.

### KPI card accent colors (top border line per card)

| KPI | Dark mode accent | Light mode accent | Meaning |
|-----|-----------------|-------------------|---------|
| Monthly Spend | `--blue` / cyan | `--teal` | Neutral spend metric |
| Active Seats | `--amber` | `--amber` | Utilization signal |
| Savings Found | `--green` | `--green` | Positive / recoverable |
| Inactive Cost / Projection | `--red` / rose | `--red` | Risk / alert |

These reuse existing variables — no new tokens required.

---

## Layout & Components

### 1. Page Header

Replace the current plain `<div class="page-header">` with a terminal-styled section label row:

- Left: "License Spend" in Syne 700, ~22px, tight letter-spacing
- Right: Finance badge + "April 2026" context chip (month/year computed from current date at render time)
- Below heading: a single muted descriptor line (existing `<p>` text, Open Sans 13px)

### 2. Action Row (new)

A slim row directly below the page header, above the Configure card:

- **🖨 Print / PDF** button — calls `window.print()`; triggers `@media print` stylesheet
- **Export CSV ↓** dropdown or split button — keeps existing inactive + projections CSV exports, surfaced more visibly
- Sits flush left, uses existing `.btn` and `.btn-ghost` classes

### 3. KPI Stats Row

Transform the existing `.stats-row` into 4 terminal-style cards using existing `.stat-card` or a new `.kpi-card` class:

Each card:
- White (light) / `#0c1020` (dark) background
- 1px border using `var(--border)`
- **Colored top accent line**: 1px, gradient from transparent → accent color → transparent, spanning 80% of card width
- **Label**: Open Sans 9px, uppercase, letter-spacing 0.1em, `var(--muted2)` color
- **Value**: JetBrains Mono 22px bold — color matches accent (cyan/amber/green/rose per card)
- **Glow**: `text-shadow` with matching accent color at low opacity — dark mode only (suppressed in light mode and print)
- **Sub-line**: JetBrains Mono 10px, `var(--muted2)` — secondary context (e.g. "of 921 total", "74 inactive seats")
- **Trend badge**: absolute top-right, 9px, colored up/down arrow + percentage

Cards (all post-load, hidden until `loadDashboard()` completes): Monthly Spend · Active Seats · Savings Found · **Inactive Cost** (rose/red accent — the most actionable risk signal on-screen). The print view swaps the 4th card to **12-mo Projection** since that's more useful for executive reporting context.

### 4. Configure Card

Unchanged functionally and visually. The `.card-title` "Configure" label inherits Open Sans from `shared/styles.css` — no change needed. Dropdowns and buttons already use `font-family: inherit`.

### 5. Callout Banners

Existing `.callout.savings` and `.callout.warning` retained with no font changes — both title and body stay Open Sans (consistent with shared styles). Only the page heading uses Syne.

### 6. Chart Cards — Aesthetic Updates

Chart.js charts are already present. Updates are CSS + Chart.js config only — no logic changes:

**Spend by SKU (donut)**
- Chart colors updated to match KPI accent palette: `var(--blue)`, `var(--blue-mid)`, `var(--amber)`, `var(--green)`, `var(--muted2)`
- Center label (existing plugin or overlay): JetBrains Mono for the dollar total
- SKU list rows: name in Open Sans, cost in JetBrains Mono amber

**Seat Utilisation (stacked bar)**
- Bar colors: active → `var(--green)`, inactive → `var(--amber)`, unassigned → `var(--muted2)`
- Axis tick labels: Open Sans 10px

**Cost by Department (horizontal bar)**
- Gradient fill per bar: accent color → `var(--blue-light)` (dark mode) or solid accent (light mode)
- Bar value labels: JetBrains Mono 10px

**12-Month Projection (line)**
- Growth scenario line: `var(--blue)` with gradient fill below
- Flat/reduction scenario: `var(--muted2)` dashed
- Axis values: JetBrains Mono 10px

Chart.js global config set once at top of script:
```js
Chart.defaults.font.family = "'Open Sans', 'Segoe UI', system-ui, sans-serif";
Chart.defaults.color = getComputedStyle(document.documentElement).getPropertyValue('--muted').trim();
```

### 7. Section Labels

Existing `.section-title` updated to match terminal style:
- 10px, uppercase, letter-spacing 0.1em, `var(--muted2)`
- Followed by a 1px `var(--border)` rule (CSS `::after` or `<hr>`)

### 8. Inactive License Holders Table

No structural changes. Style updates:
- Cost column values: JetBrains Mono, `var(--amber)` color
- Seat count cells: JetBrains Mono
- All other text: Open Sans (inherited)

### 9. Projection Table

No structural changes. Style updates:
- All dollar/number cells: JetBrains Mono
- Header row: Open Sans uppercase, letter-spacing

---

## Print / PDF View

Triggered by `window.print()` via the **🖨 Print / PDF** action button. An `@media print` block in `<style>` overrides the dashboard layout.

### What the print view shows

```
┌────────────────────────────────────────────────────────┐
│  License Spend Report          Generated: 2026-04-02   │
│  CorroHealth · M365 Admin Hub · 90-day threshold       │
├────────────────────────────────────────────────────────┤
│  [Spend] [Active Seats] [Savings Found] [12-mo Proj.]  │  ← terminal KPI cards, colored accent lines
├────────────────────────────────────────────────────────┤
│  💡 $170,640 annual savings identified. 74 inactive…   │  ← callout (green left border)
├────────────────────────────────────────────────────────┤
│  Spend by SKU            │  Cost by Department         │
│  [bar chart]             │  [bar chart]                │
├────────────────────────────────────────────────────────┤
│  Generated by IT Tools · M365 Admin Hub   Confidential │  ← footer
└────────────────────────────────────────────────────────┘
```

### Print-specific rules

- **Topbar**: `display: none`
- **Configure card**: `display: none`
- **Action row**: `display: none`
- **Background colors**: forced via `-webkit-print-color-adjust: exact; print-color-adjust: exact` so accent lines and bar fills render in PDF
- **Glow effects**: suppressed (`text-shadow: none`)
- **Body background**: white (`#ffffff`)
- **KPI card background**: white, 1px `#e2e8f0` border
- **KPI accent lines**: retained — same colored gradient top border as screen, using deepened light-mode accent values for print legibility
- **KPI labels**: shortened to avoid truncation:
  - "Monthly Spend" → "Monthly Spend" (fits)
  - "Active Seats" → "Active Seats" (fits)
  - "Savings Found" → "Savings Found" (fits)
  - "Annual Projection" → "12-mo Projection" (prevents truncation)
- **KPI values**: JetBrains Mono retained; `$1,011,840` displayed as `$1.01M` for the projection card to prevent overflow
- **KPI sub-line**: Open Sans 7px, single line — e.g. `of 921 · 91.9%` / `▲ 2.6% MoM`
- **Report header**: Syne 800 title + right-aligned generated timestamp (stamped via the Print button click handler immediately before `window.print()` is called)
- **Footer**: IT Tools branding watermark left, "Confidential · Finance use only · Page 1 of 1" right
- **Page size**: A4 landscape via `@page { size: A4 landscape; margin: 1.5cm; }`

### Print button behavior

```js
document.getElementById('printBtn').addEventListener('click', () => {
  // Stamp the current date/time into the report header before print dialog opens
  document.getElementById('printTimestamp').textContent =
    new Date().toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
  window.print();
});
```

---

## CSS Architecture

A single `<style>` block in `finance-dashboard/index.html` contains all redesign styles. Structure:

```
/* ── Font imports (Syne + JetBrains Mono) ── */
/* ── Local token additions (already present: --teal variants) ── */
/* ── KPI card ── */
/* ── Action row ── */
/* ── Chart cards ── */
/* ── Section labels ── */
/* ── Table overrides (JetBrains Mono on data cells) ── */
/* ── @media print ── */
```

No design tokens are duplicated from `shared/styles.css`. All colors, spacing, shadows, and base typography reference CSS variables.

---

## Data Flow

Unchanged. No modifications to fetch logic, Graph API calls, cost calculations, or auth flow.

The only JS additions:
1. `Chart.defaults` config (2 lines at script top)
2. Print button click handler (timestamp injection + `window.print()`)
3. Trend computation for KPI sub-lines (derive from existing computed values already present in `loadDashboard()`)

---

## Error Handling

Unchanged from current implementation.

---

## Out of Scope

- Changes to `shared/styles.css`, `shared/auth.js`, or any other tool pages
- New Graph API data sources or new cost calculations
- New chart types (can be added in a future pass)
- Scheduled/automated PDF delivery
- Changes to `config.json` or `costs.json`
