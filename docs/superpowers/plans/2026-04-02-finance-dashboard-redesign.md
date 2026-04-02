# Finance Dashboard Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `tools/finance-dashboard/index.html` with the Dark Executive Terminal aesthetic — JetBrains Mono numbers, Syne page title, Open Sans UI chrome, colored KPI card accent lines, terminal-themed Chart.js colors, and a print/PDF export path via `@media print`.

**Architecture:** All changes are confined to `tools/finance-dashboard/index.html`. CSS goes in the existing `<style>` block. JS additions go in the existing `<script>` block. No changes to `shared/` files. The print layout is a hidden HTML section revealed only by `@media print`, triggered by a new Print button.

**Tech Stack:** Vanilla HTML/CSS/JS · Chart.js 4.4.0 (already loaded) · Google Fonts (JetBrains Mono + Syne, new) · Open Sans (already loaded via `shared/styles.css`)

---

## File Map

| File | Change type | What changes |
|------|-------------|-------------|
| `tools/finance-dashboard/index.html` | Modify | All changes — fonts, CSS, HTML, JS |

---

## Task 1: Load JetBrains Mono and Syne fonts

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `<head>` section (after the existing `<link rel="stylesheet" href="../../shared/styles.css"/>` line)

- [ ] **Step 1: Add font `<link>` tags**

Find the line:
```html
<link rel="stylesheet" href="../../shared/styles.css"/>
```

Add immediately after it:
```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Syne:wght@700;800&family=JetBrains+Mono:wght@400;600;700&display=swap" rel="stylesheet">
```

- [ ] **Step 2: Verify fonts load**

Open `tools/finance-dashboard/index.html` in a browser (via the preview URL). Open DevTools → Network tab → filter by "fonts". After signing in and loading the dashboard, confirm `JetBrains+Mono` and `Syne` appear as loaded resources.

- [ ] **Step 3: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat(finance-dashboard): load JetBrains Mono and Syne fonts"
```

---

## Task 2: Add Chart.js global font and color defaults

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `<script>` block, immediately after the `let _charts = {}; let _data = null;` lines (~line 363)

- [ ] **Step 1: Add Chart.defaults config**

Find:
```js
let _charts = {};
let _data   = null;  // processed dashboard data
```

Add immediately after:
```js
// ── Chart.js global defaults ───────────────────────────────────────────────────
Chart.defaults.font.family = "'Open Sans', 'Segoe UI', system-ui, sans-serif";
```

- [ ] **Step 2: Update the PALETTE constant to terminal accent colors**

Find:
```js
const PALETTE = [
  "#1a56db","#047857","#92400e","#5b21b6","#0e7490",
  "#991b1b","#065f46","#1e40af","#78350f","#4c1d95",
  "#0c4a6e","#7f1d1d","#064e3b","#1e3a5f","#451a03",
];
```

Replace with:
```js
// Terminal accent palette — matches KPI card accent colors
const PALETTE = [
  "#0e7490","#6366f1","#f59e0b","#10b981","#a78bfa",
  "#f43f5e","#06b6d4","#d97706","#059669","#818cf8",
  "#0891b2","#e11d48","#0284c7","#65a30d","#7c3aed",
];
```

- [ ] **Step 3: Update the `cd()` function to use CSS variable values**

Find:
```js
function cd() {
  const dark = document.documentElement.getAttribute("data-theme") === "dark";
  return {
    text:   dark ? "#94a3b8" : "#6b7280",
    grid:   dark ? "rgba(255,255,255,.06)" : "rgba(0,0,0,.06)",
    bg:     dark ? "#1a1d27" : "#ffffff",
    border: dark ? "#2d3148" : "#dde3ec",
  };
}
```

Replace with:
```js
function cd() {
  const dark = document.documentElement.getAttribute("data-theme") === "dark";
  return {
    text:   dark ? "#64748b" : "#94a3b8",
    grid:   dark ? "rgba(255,255,255,.05)" : "rgba(0,0,0,.05)",
    bg:     dark ? "#0c1020" : "#ffffff",
    border: dark ? "#1e2a3a" : "#e2e8f0",
    mono:   "'JetBrains Mono', 'Cascadia Code', monospace",
  };
}
```

- [ ] **Step 4: Verify no chart errors**

Load the dashboard in the browser and confirm all 4 charts render without console errors. The palette change won't be visible until Task 5.

- [ ] **Step 5: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat(finance-dashboard): set Chart.js global font and terminal palette"
```

---

## Task 3: KPI card CSS

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `<style>` block

The existing `.stat-card` / `.stats-row` CSS will be replaced with the new `.kpi-card` system. The existing classes are only used in the `sc()` helper (updated in Task 4), so replacing them here is safe.

- [ ] **Step 1: Replace the stats-row CSS block**

Find the existing stats-row styles. They look like:
```css
/* ── Scan summary row ── */
.scan-meta-row {
```
(the stats row styles are in `shared/styles.css`, not here — the local `<style>` block only has `.stat-value-md { font-size: 20px !important; }`)

Find in the `<style>` block:
```css
  /* ── Inline stat number sizing ── */
  .stat-value-md { font-size: 20px !important; }
```

Replace with:
```css
  /* ── KPI cards (terminal style) ── */
  .kpi-row {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 10px;
    margin-bottom: 1.25rem;
  }
  @media (max-width: 800px) { .kpi-row { grid-template-columns: repeat(2, 1fr); } }
  @media (max-width: 480px) { .kpi-row { grid-template-columns: 1fr; } }

  .kpi-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 0.875rem 1rem;
    position: relative;
    overflow: hidden;
  }
  /* Colored top accent line */
  .kpi-card::before {
    content: '';
    position: absolute;
    top: 0; left: 10%; right: 10%;
    height: 1px;
  }
  .kpi-card.kpi-cyan::before   { background: linear-gradient(90deg, transparent, var(--teal), transparent); }
  .kpi-card.kpi-amber::before  { background: linear-gradient(90deg, transparent, var(--amber), transparent); }
  .kpi-card.kpi-green::before  { background: linear-gradient(90deg, transparent, var(--green), transparent); }
  .kpi-card.kpi-rose::before   { background: linear-gradient(90deg, transparent, var(--red), transparent); }

  .kpi-label {
    font-size: 9px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--muted2);
    margin-bottom: 7px;
  }
  .kpi-value {
    font-family: 'JetBrains Mono', 'Cascadia Code', monospace;
    font-size: 21px;
    font-weight: 700;
    line-height: 1;
    margin-bottom: 4px;
  }
  .kpi-card.kpi-cyan  .kpi-value { color: var(--teal); }
  .kpi-card.kpi-amber .kpi-value { color: var(--amber); }
  .kpi-card.kpi-green .kpi-value { color: var(--green); }
  .kpi-card.kpi-rose  .kpi-value { color: var(--red); }

  /* Glow — dark mode only */
  [data-theme="dark"] .kpi-card.kpi-cyan  .kpi-value { text-shadow: 0 0 18px rgba(14,116,144,0.5); }
  [data-theme="dark"] .kpi-card.kpi-amber .kpi-value { text-shadow: 0 0 18px rgba(245,158,11,0.45); }
  [data-theme="dark"] .kpi-card.kpi-green .kpi-value { text-shadow: 0 0 18px rgba(16,185,129,0.45); }
  [data-theme="dark"] .kpi-card.kpi-rose  .kpi-value { text-shadow: 0 0 18px rgba(239,68,68,0.4); }

  .kpi-sub {
    font-family: 'JetBrains Mono', 'Cascadia Code', monospace;
    font-size: 10px;
    color: var(--muted2);
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .kpi-trend {
    font-size: 9px;
    font-weight: 700;
  }
  .kpi-trend.up   { color: var(--red); }
  .kpi-trend.down { color: var(--green); }

  /* Legacy stat-value-md kept for safety */
  .stat-value-md { font-size: 20px !important; }
```

- [ ] **Step 2: Verify CSS parses without errors**

Open DevTools → Console. There should be no CSS parse errors after saving.

- [ ] **Step 3: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat(finance-dashboard): add KPI card terminal CSS"
```

---

## Task 4: Rewrite renderStats() to emit KPI cards

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `renderStats()` and `sc()` functions and the `renderAll()` call to `renderStats()`

The spec calls for 4 KPI cards: Monthly Spend · Active Seats · Savings Found · Inactive Cost. The current implementation has 5 stats and uses `.stat` classes. This task replaces them.

- [ ] **Step 1: Update the HTML container for the stats row**

Find in the HTML body:
```html
  <!-- Overview stats -->
  <div class="stats-row" id="statsRow" style="display:none"></div>
```

Replace with:
```html
  <!-- KPI cards -->
  <div class="kpi-row" id="statsRow" style="display:none"></div>
```

- [ ] **Step 2: Replace renderStats() and the sc() helper**

Find:
```js
function renderStats(monthly, waste, inactive, skuCount, inactiveCount, days) {
  const annual   = monthly * 12;
  const saveable = waste + inactive;
  document.getElementById("statsRow").innerHTML =
    sc("amber",  "Monthly Spend",        fmt(monthly,  true), `across ${skuCount} paid SKUs`) +
    sc("blue",   "Annual Projection",    fmt(annual,   true), "at current spend rate") +
    sc("red",    "Unassigned Seat Waste",fmt(waste,    true) + "/mo", "seats paid for, not assigned") +
    sc("amber",  `Inactive Cost (>${days}d)`, fmt(inactive, true) + "/mo", `${inactiveCount} users`) +
    sc("green",  "Total Recoverable",    fmt(saveable, true) + "/mo", fmt(saveable * 12, true) + "/yr potential");
}
function sc(c,l,v,s) {
  return `<div class="stat ${c}"><div class="stat-label">${l}</div><div class="stat-value stat-value-md">${v}</div>${s?`<div class="stat-sub">${s}</div>`:""}</div>`;
}
```

Replace with:
```js
function renderStats(monthly, waste, inactive, skuCount, inactiveCount, days, assignedSeats, totalSeats) {
  const saveable   = waste + inactive;
  const utilPct    = totalSeats > 0 ? Math.round(assignedSeats / totalSeats * 100) : 0;

  document.getElementById("statsRow").innerHTML =
    kpiCard("kpi-cyan",  "Monthly Spend",  fmt(monthly, true),
      `${skuCount} paid SKUs`, `▲ ${fmt(monthly * 12, true)}/yr`) +
    kpiCard("kpi-amber", "Active Seats",   assignedSeats.toLocaleString(),
      `of ${totalSeats.toLocaleString()} total`, `${utilPct}% utilization`) +
    kpiCard("kpi-green", "Savings Found",  fmt(saveable, true) + "/mo",
      `${inactiveCount} inactive users`, `▼ ${fmt(saveable * 12, true)}/yr`) +
    kpiCard("kpi-rose",  `Inactive Cost`,  fmt(inactive, true) + "/mo",
      `>${days}-day threshold`, `▲ REVIEW`);
}

function kpiCard(accent, label, value, sub, trend) {
  const trendCls = trend.startsWith("▲") ? "up" : "down";
  return `<div class="kpi-card ${accent}">
    <div class="kpi-label">${label}</div>
    <div class="kpi-value">${value}</div>
    <div class="kpi-sub">
      <span>${sub}</span>
      <span class="kpi-trend ${trendCls}">${trend}</span>
    </div>
  </div>`;
}
```

- [ ] **Step 3: Pass assignedSeats and totalSeats from renderAll()**

Find in `renderAll()`:
```js
  const monthly     = skuList.reduce((s, k) => s + k.assignedCost,  0);
  const waste       = skuList.reduce((s, k) => s + k.wasteCost,     0);
  const inactiveCost= inactiveU.reduce((s, u) => s + u.totalCost,    0);
  const saveable    = waste + inactiveCost;

  renderStats(monthly, waste, inactiveCost, skuList.length, inactiveU.length, days);
```

Replace with:
```js
  const monthly      = skuList.reduce((s, k) => s + k.assignedCost,  0);
  const waste        = skuList.reduce((s, k) => s + k.wasteCost,     0);
  const inactiveCost = inactiveU.reduce((s, u) => s + u.totalCost,    0);
  const saveable     = waste + inactiveCost;
  const assignedSeats = skuList.reduce((s, k) => s + k.assigned,     0);
  const totalSeats    = skuList.reduce((s, k) => s + k.total,        0);

  renderStats(monthly, waste, inactiveCost, skuList.length, inactiveU.length, days, assignedSeats, totalSeats);
```

- [ ] **Step 4: Load dashboard and verify KPI cards render**

Sign in and click Load Dashboard. Confirm:
- 4 KPI cards appear in a row
- Each has a colored top accent line (may be faint — check in dark mode for glow)
- Values use JetBrains Mono font (verify in DevTools → Computed → font-family)
- Trend badges appear bottom-right of each card

- [ ] **Step 5: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat(finance-dashboard): replace stats row with terminal KPI cards"
```

---

## Task 5: Update chart colors to terminal palette

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `renderUtilisation()`, `renderDeptChart()`, `updateProjections()` functions

- [ ] **Step 1: Update utilisation chart colors**

Find in `renderUtilisation()`:
```js
        { label: "Active",     data: top.map(s => Math.max(0, s.assigned - s.inactiveCount)), backgroundColor: "#047857bb", stack: "s" },
        { label: "Inactive",   data: top.map(s => s.inactiveCount),                           backgroundColor: "#92400ebb", stack: "s" },
        { label: "Unassigned", data: top.map(s => s.unassigned),                               backgroundColor: "#991b1bbb", stack: "s" },
```

Replace with:
```js
        { label: "Active",     data: top.map(s => Math.max(0, s.assigned - s.inactiveCount)), backgroundColor: "#10b981bb", stack: "s" },
        { label: "Inactive",   data: top.map(s => s.inactiveCount),                           backgroundColor: "#f59e0bbb", stack: "s" },
        { label: "Unassigned", data: top.map(s => s.unassigned),                               backgroundColor: "#f43f5ebb", stack: "s" },
```

Also update the tick font to use monospace for the axis values. Find in `renderUtilisation()` options:
```js
        x: { stacked: true, grid: { color: grid }, ticks: { color: text, font: { size: 10 } } },
        y: { stacked: true, grid: { color: grid }, ticks: { color: text, font: { size: 10 }, maxRotation: 0 } }
```

Replace with:
```js
        x: { stacked: true, grid: { color: grid }, ticks: { color: text, font: { size: 10, family: cd().mono } } },
        y: { stacked: true, grid: { color: grid }, ticks: { color: text, font: { size: 10 }, maxRotation: 0 } }
```

- [ ] **Step 2: Update department chart colors**

Find in `renderDeptChart()`:
```js
        { label: "Active spend",   data: sorted.map(([,v]) => +v.active.toFixed(2)),   backgroundColor: "#1a56dbbb", stack: "s" },
        { label: "Inactive spend", data: sorted.map(([,v]) => +v.inactive.toFixed(2)), backgroundColor: "#92400ebb", stack: "s" },
```

Replace with:
```js
        { label: "Active spend",   data: sorted.map(([,v]) => +v.active.toFixed(2)),   backgroundColor: "#6366f1bb", stack: "s" },
        { label: "Inactive spend", data: sorted.map(([,v]) => +v.inactive.toFixed(2)), backgroundColor: "#f59e0bbb", stack: "s" },
```

Also update the y-axis tick font. Find in `renderDeptChart()` options:
```js
        y: { stacked: true, grid: { color: grid }, ticks: { color: text, font: { size: 10 }, callback: v => "$" + Math.round(v).toLocaleString() } }
```

Replace with:
```js
        y: { stacked: true, grid: { color: grid }, ticks: { color: text, font: { size: 10, family: cd().mono }, callback: v => "$" + Math.round(v).toLocaleString() } }
```

- [ ] **Step 3: Update projection chart colors and add y-axis mono font**

Find in `updateProjections()` the datasets array:
```js
        { label: "Flat",              data: flat,      borderColor: "#1a56db", backgroundColor: "transparent", borderWidth: 2.5, tension: .2, pointRadius: 3 },
        { label: "Savings",           data: savings,   borderColor: "#047857", backgroundColor: "transparent", borderWidth: 2.5, borderDash: [6,3], tension: .2, pointRadius: 3 },
        { label: "Growth",            data: growth,    borderColor: "#92400e", backgroundColor: "transparent", borderWidth: 2.5, tension: .2, pointRadius: 3 },
        { label: "Optimised Growth",  data: optGrowth, borderColor: "#0e7490", backgroundColor: "transparent", borderWidth: 2.5, borderDash: [6,3], tension: .2, pointRadius: 3 },
```

Replace with:
```js
        { label: "Flat",             data: flat,      borderColor: "#6366f1", backgroundColor: "rgba(99,102,241,0.06)", fill: true, borderWidth: 2, tension: .3, pointRadius: 2 },
        { label: "Savings",          data: savings,   borderColor: "#10b981", backgroundColor: "transparent", borderWidth: 2, borderDash: [6,3], tension: .3, pointRadius: 2 },
        { label: "Growth",           data: growth,    borderColor: "#f59e0b", backgroundColor: "transparent", borderWidth: 2, tension: .3, pointRadius: 2 },
        { label: "Optimised Growth", data: optGrowth, borderColor: "#06b6d4", backgroundColor: "transparent", borderWidth: 2, borderDash: [6,3], tension: .3, pointRadius: 2 },
```

Also update the legend colors in `updateProjections()`. Find:
```js
    { label: "Flat (status quo)",                    color: "#1a56db", dash: false },
    { label: "Savings (waste + inactive removed)",   color: "#047857", dash: true  },
    { label: `Growth (${(growthR*100).toFixed(1)}%/mo)`, color: "#92400e", dash: false },
    { label: "Optimised growth",                     color: "#0e7490", dash: true  },
```

Replace with:
```js
    { label: "Flat (status quo)",                    color: "#6366f1", dash: false },
    { label: "Savings (waste + inactive removed)",   color: "#10b981", dash: true  },
    { label: `Growth (${(growthR*100).toFixed(1)}%/mo)`, color: "#f59e0b", dash: false },
    { label: "Optimised growth",                     color: "#06b6d4", dash: true  },
```

Also update the y-axis tick font. Find in `updateProjections()` scales:
```js
          ticks: { color: text, font: { size: 11 }, callback: v => "$" + Math.round(v).toLocaleString() }
```

Replace with:
```js
          ticks: { color: text, font: { size: 11, family: cd().mono }, callback: v => "$" + Math.round(v).toLocaleString() }
```

- [ ] **Step 4: Update donut chart border color to use card background**

Find in `renderDonut()`:
```js
        borderColor: cd().bg,
```

This is already correct — it uses `cd().bg` which now returns the terminal card color. No change needed.

- [ ] **Step 5: Update the SKU list cost cells to JetBrains Mono**

Find in `renderDonut()` the `skuList` innerHTML map — the line that builds each `.sku-row`:
```js
        <span class="sku-cost">${fmt(s.assignedCost)}</span>
        <span class="sku-seats">${(s.assigned||0).toLocaleString()} seats</span>
```

In the `<style>` block, find:
```css
  .sku-cost { font-weight: 700; color: var(--amber); white-space: nowrap; }
  .sku-seats { font-size: 10px; color: var(--muted2); white-space: nowrap; }
```

Replace with:
```css
  .sku-cost { font-family: 'JetBrains Mono', monospace; font-weight: 700; color: var(--amber); white-space: nowrap; }
  .sku-seats { font-family: 'JetBrains Mono', monospace; font-size: 10px; color: var(--muted2); white-space: nowrap; }
```

- [ ] **Step 6: Load dashboard and verify all 4 charts render with new colors**

Confirm in browser:
- Utilisation chart: green/amber/rose bars
- Department chart: indigo/amber stacked bars
- Projection chart: 4 colored lines with updated legend chips
- Donut chart: new PALETTE colors (blues, teals, ambers)
- SKU cost list: JetBrains Mono amber font

- [ ] **Step 7: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat(finance-dashboard): update chart colors and apply JetBrains Mono to data cells"
```

---

## Task 6: Apply JetBrains Mono to table number cells

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `<style>` block (cost/number cell classes) and `renderInactiveTable()` / projection table rendering

- [ ] **Step 1: Add mono class to cost-cell and number cells in CSS**

Find in the `<style>` block:
```css
  /* ── Inactive cost cell ── */
  .cost-cell { font-size: 12px; font-weight: 700; color: var(--amber); white-space: nowrap; }
```

Replace with:
```css
  /* ── Data cells — monospace for all numbers ── */
  .cost-cell  { font-family: 'JetBrains Mono', monospace; font-size: 12px; font-weight: 700; color: var(--amber); white-space: nowrap; }
  .num-cell   { font-family: 'JetBrains Mono', monospace; font-size: 12px; color: var(--muted); white-space: nowrap; }
  .date-cell  { font-family: 'JetBrains Mono', monospace; font-size: 11px; color: var(--muted2); white-space: nowrap; }
```

- [ ] **Step 2: Find renderInactiveTable() and add num-cell / date-cell classes**

Search for `renderInactiveTable` in the `<script>` block. Locate where it builds `<td>` cells. Find the cells that render `daysSince`, `lastSignIn`, and seat counts — they will look something like:

```js
<td>${u.daysSince !== null ? u.daysSince + "d" : "Never"}</td>
<td class="cost-cell">${fmt(u.totalCost)}/mo</td>
```

Update each numeric/date `<td>` to use the new classes:
- `daysSince` cell → add `class="num-cell"`
- `lastSignIn` formatted date cell → add `class="date-cell"`
- The cost cell already uses `cost-cell` ✓

The exact markup depends on the current table structure. Read `renderInactiveTable()` in full, then apply `num-cell` to any `<td>` containing a pure number/count/date that doesn't already have `cost-cell`.

- [ ] **Step 3: Apply mono to projection table number cells**

The projection table is built in `updateProjections()`. Find where it builds the `<td>` cells for the dollar values in `projTable`. Each dollar cell should use `class="cost-cell"`. Find the table row builder (it will be inside the `proj-table-wrap`) and add `class="cost-cell"` to any `<td>` that contains a `fmt()` call.

- [ ] **Step 4: Verify table rendering**

Load the dashboard, scroll to Inactive License Holders. Confirm:
- All cost values are in JetBrains Mono amber
- Date/days columns use JetBrains Mono muted styling

- [ ] **Step 5: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat(finance-dashboard): apply JetBrains Mono to table number cells"
```

---

## Task 7: Add page header with Syne title and action row

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `<style>` block + HTML body (page header + action row)

- [ ] **Step 1: Add page header and action row CSS**

Find in the `<style>` block:
```css
  /* ── Page header ── */
  .page-header { margin-bottom: 1.5rem; }
  .page-header h1 { font-size: 22px; font-weight: 700; margin-bottom: 4px; }
  .page-header p  { font-size: 13px; color: var(--muted); }
```

Replace with:
```css
  /* ── Page header ── */
  .page-header { margin-bottom: 1rem; }
  .page-header h1 {
    font-family: 'Syne', 'Open Sans', sans-serif;
    font-size: 22px; font-weight: 800; margin-bottom: 4px; letter-spacing: -0.02em;
  }
  .page-header p { font-size: 13px; color: var(--muted); }

  /* ── Action row ── */
  .action-row {
    display: flex; align-items: center; gap: 8px;
    margin-bottom: 1.25rem; flex-wrap: wrap;
  }
  .action-row .btn-print {
    display: flex; align-items: center; gap: 6px;
    padding: 6px 14px; border-radius: var(--radius-sm);
    background: var(--surface); border: 1px solid var(--border);
    font-size: 12px; font-weight: 600; color: var(--muted);
    cursor: pointer; font-family: inherit; transition: all .12s;
  }
  .action-row .btn-print:hover { border-color: var(--teal); color: var(--teal); background: var(--teal-light); }
```

- [ ] **Step 2: Update the page header HTML**

Find in the HTML body (inside `<div id="appScreen">`):
```html
  <!-- Page header -->
  <div class="page-header">
    <div style="display:flex;align-items:center;gap:10px;margin-bottom:4px;flex-wrap:wrap">
      <h1 style="margin-bottom:0">License Spend</h1>
      <span class="finance-badge">💰 Finance View</span>
    </div>
    <p>Full M365 license spend analysis, seat utilisation, department breakdown, and 12-month cost projections.</p>
  </div>
```

Replace with:
```html
  <!-- Page header -->
  <div class="page-header">
    <div style="display:flex;align-items:center;gap:10px;margin-bottom:4px;flex-wrap:wrap">
      <h1 style="margin-bottom:0">License Spend</h1>
      <span class="finance-badge">💰 Finance View</span>
    </div>
    <p>Full M365 license spend analysis, seat utilisation, department breakdown, and 12-month cost projections.</p>
  </div>

  <!-- Action row -->
  <div class="action-row">
    <button class="btn-print" id="printBtn">
      <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 6 2 18 2 18 9"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/></svg>
      Print / PDF
    </button>
    <button class="btn btn-ghost" id="exportInactiveBtn" onclick="exportInactive()" style="display:none;font-size:12px;padding:6px 14px">
      Export Inactive CSV ↓
    </button>
    <button class="btn btn-ghost" id="exportProjBtn" onclick="exportProjections()" style="display:none;font-size:12px;padding:6px 14px">
      Export Projections CSV ↓
    </button>
  </div>
```

Note: The `exportInactiveBtn` and `exportProjBtn` buttons mirror the existing export buttons inside the card sections. They will be shown once data loads (see Task 8 for the JS wiring).

- [ ] **Step 3: Verify header renders correctly**

Reload the page. Confirm:
- "License Spend" heading uses Syne font (verify in DevTools Computed panel)
- Print / PDF button appears below the header
- The existing Export CSV buttons inside the cards are still present and functional

- [ ] **Step 4: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat(finance-dashboard): add Syne page title and action row with print button"
```

---

## Task 8: Wire print button and show action row export buttons on load

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `<script>` block

- [ ] **Step 1: Add print button click handler**

Find at the bottom of the `<script>` block (near the `ITTools.auth.init` call or at the very end). Add:

```js
// ── Print / PDF ───────────────────────────────────────────────────────────────
document.getElementById("printBtn").addEventListener("click", () => {
  // Stamp timestamp into the print report header just before the dialog opens
  const ts = new Date().toLocaleString("en-US", { dateStyle: "medium", timeStyle: "short" });
  const el = document.getElementById("printTimestamp");
  if (el) el.textContent = ts;
  window.print();
});
```

- [ ] **Step 2: Show action row export buttons when data loads**

Find in `renderAll()`, after the lines that show the card sections:
```js
  document.getElementById("inactiveCard").style.display= "block";
```

Add immediately after:
```js
  // Surface export buttons in the action row once data is available
  document.getElementById("exportInactiveBtn").style.display = "";
  document.getElementById("exportProjBtn").style.display     = "";
```

- [ ] **Step 3: Verify print button works (no print layout yet)**

Click Print / PDF. The browser print dialog should open. The output will look broken at this stage (no print styles yet) — that's expected. Confirm the dialog opens without JS errors.

- [ ] **Step 4: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat(finance-dashboard): wire print button and action row export buttons"
```

---

## Task 9: Build the print/PDF layout

**Files:**
- Modify: `tools/finance-dashboard/index.html` — HTML body (print header + print KPI row) and `<style>` block (`@media print`)

- [ ] **Step 1: Add the hidden print report header HTML**

Find in the HTML body, immediately before `<div id="topbar"></div>`:

```html
<div id="topbar"></div>
```

Add immediately before it:
```html
<!-- ── Print report header — hidden on screen, shown in @media print ── -->
<div id="printHeader" class="print-only">
  <div class="print-report-header">
    <div class="print-report-left">
      <div class="print-report-title">License Spend Report</div>
      <div class="print-report-meta">CorroHealth · IT Tools M365 Admin Hub · <span id="printThresholdLabel">90</span>-day inactivity threshold · All departments</div>
    </div>
    <div class="print-report-right">
      <div class="print-report-gen-label">Generated</div>
      <div class="print-report-gen-date" id="printTimestamp"></div>
    </div>
  </div>
  <!-- KPI row for print — populated by renderStats() -->
  <div class="print-kpi-row" id="printKpiRow"></div>
</div>
```

- [ ] **Step 2: Update renderStats() to also populate the print KPI row**

Find in `renderStats()` (from Task 4). After the line:
```js
  document.getElementById("statsRow").innerHTML =
    kpiCard("kpi-cyan",  "Monthly Spend", ...) + ...;
```

Add immediately after the `document.getElementById("statsRow").innerHTML = ...` block:

```js
  // Also populate the print KPI strip
  const printRow = document.getElementById("printKpiRow");
  if (printRow) {
    const projAnnual = monthly * 12;
    const projLabel  = projAnnual >= 1000000
      ? "$" + (projAnnual / 1000000).toFixed(2) + "M"
      : fmt(projAnnual, true);
    printRow.innerHTML =
      printKpiCard("print-cyan",  "Monthly Spend",  fmt(monthly, true),    `${skuCount} paid SKUs`,              `▲ ${projLabel}/yr`) +
      printKpiCard("print-amber", "Active Seats",   assignedSeats.toLocaleString(), `of ${totalSeats.toLocaleString()} · ${utilPct}%`, `↓ ${inactiveCount} idle`) +
      printKpiCard("print-green", "Savings Found",  fmt(saveable, true) + "/mo", `${inactiveCount} inactive users`,  `▼ ${fmt(saveable * 12, true)}/yr`) +
      printKpiCard("print-rose",  "12-mo Projection", projLabel,            `+2% growth rate`,                    `▲ review`);
  }
  // Stamp the threshold label
  const tLabel = document.getElementById("printThresholdLabel");
  if (tLabel) tLabel.textContent = days;
```

Add the `printKpiCard()` helper immediately after `kpiCard()`:

```js
function printKpiCard(accent, label, value, sub, trend) {
  const trendCls = trend.startsWith("▲") ? "up" : "down";
  return `<div class="print-kpi ${accent}">
    <div class="print-kpi-label">${label}</div>
    <div class="print-kpi-value">${value}</div>
    <div class="print-kpi-sub">
      <span>${sub}</span>
      <span class="print-kpi-trend ${trendCls}">${trend}</span>
    </div>
  </div>`;
}
```

- [ ] **Step 3: Add @media print CSS and print-only element styles**

At the very end of the `<style>` block, add:

```css
  /* ══════════════════════════════════════════════════════
     PRINT / PDF
  ══════════════════════════════════════════════════════ */

  /* Hidden on screen, shown in print */
  .print-only { display: none; }

  @media print {
    @page { size: A4 landscape; margin: 1.2cm 1.5cm; }

    /* ── Show / hide ── */
    .print-only        { display: block !important; }
    #topbar            { display: none !important; }
    .action-row        { display: none !important; }
    .card:has(#loadBtn){ display: none !important; }  /* Configure card */
    .page-header       { display: none !important; }
    .hub-footer        { display: none !important; }

    /* ── Page base ── */
    body, html { background: #fff !important; color: #0f172a !important; }
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;

    /* ── Remove glow effects ── */
    .kpi-value { text-shadow: none !important; }

    /* ── Print report header ── */
    .print-report-header {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      padding-bottom: 0.6rem;
      margin-bottom: 0.75rem;
      border-bottom: 2px solid #0f172a;
    }
    .print-report-title {
      font-family: 'Syne', 'Open Sans', sans-serif;
      font-size: 18px; font-weight: 800; color: #0f172a; letter-spacing: -0.02em;
      margin-bottom: 2px;
    }
    .print-report-meta { font-size: 8px; color: #94a3b8; }
    .print-report-gen-label { font-size: 7px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.1em; color: #94a3b8; text-align: right; }
    .print-report-gen-date  { font-family: 'JetBrains Mono', monospace; font-size: 9px; color: #475569; text-align: right; }

    /* ── Print KPI row ── */
    .print-kpi-row {
      display: grid !important;
      grid-template-columns: repeat(4, 1fr);
      gap: 8px;
      margin-bottom: 0.75rem;
    }
    .print-kpi {
      background: #fff;
      border: 1px solid #e2e8f0;
      border-radius: 6px;
      padding: 0.5rem 0.75rem;
      position: relative;
      overflow: hidden;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }
    .print-kpi::before {
      content: '';
      position: absolute;
      top: 0; left: 8%; right: 8%; height: 2px;
    }
    .print-cyan::before  { background: linear-gradient(90deg, transparent, #0e7490, transparent); }
    .print-amber::before { background: linear-gradient(90deg, transparent, #d97706, transparent); }
    .print-green::before { background: linear-gradient(90deg, transparent, #059669, transparent); }
    .print-rose::before  { background: linear-gradient(90deg, transparent, #dc2626, transparent); }

    .print-kpi-label {
      font-size: 7px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.09em;
      color: #94a3b8; margin-bottom: 4px;
    }
    .print-kpi-value {
      font-family: 'JetBrains Mono', monospace;
      font-size: 15px; font-weight: 700; line-height: 1; margin-bottom: 3px;
    }
    .print-cyan  .print-kpi-value { color: #0e7490; }
    .print-amber .print-kpi-value { color: #d97706; }
    .print-green .print-kpi-value { color: #059669; }
    .print-rose  .print-kpi-value { color: #dc2626; }

    .print-kpi-sub {
      font-size: 7px; color: #94a3b8;
      display: flex; align-items: center; justify-content: space-between;
    }
    .print-kpi-trend { font-size: 7px; font-weight: 700; }
    .print-kpi-trend.up   { color: #dc2626; }
    .print-kpi-trend.down { color: #059669; }

    /* ── Hide on-screen KPI row and callout (replaced by print versions) ── */
    #statsRow    { display: none !important; }

    /* ── Print callout (savings banner) ── */
    .callout {
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
      page-break-inside: avoid;
      margin-bottom: 0.6rem !important;
      padding: 6px 10px !important;
      font-size: 11px !important;
    }

    /* ── Charts ── */
    .dash-grid-2 { gap: 0.5rem !important; margin-bottom: 0.5rem !important; }
    .card { box-shadow: none !important; border: 1px solid #e2e8f0 !important; page-break-inside: avoid; }
    canvas { max-height: 220px !important; }

    /* ── Hide projection controls, projection table, inactive table ── */
    #projCard .proj-controls { display: none !important; }
    #projCard .proj-table-wrap { display: none !important; }
    #projCard #projLegend { display: none !important; }
    #inactiveCard { display: none !important; }

    /* ── Print footer ── */
    body::after {
      content: 'Generated by IT Tools · M365 Admin Hub  ·  Confidential · Finance use only';
      display: block;
      position: fixed;
      bottom: 0.6cm; left: 1.5cm; right: 1.5cm;
      font-size: 7px;
      color: #94a3b8;
      border-top: 1px solid #e2e8f0;
      padding-top: 4px;
      display: flex;
      justify-content: space-between;
    }
  }
```

- [ ] **Step 4: Verify print layout**

Click Print / PDF. In the browser print preview confirm:
- Report header appears with "License Spend Report" title and timestamp
- 4 print KPI cards with colored accent lines
- Savings callout banner visible
- Spend by SKU + Department charts visible
- Projection chart visible (controls and table hidden)
- Inactive users table hidden
- Configure card hidden
- Topbar hidden
- Layout fits A4 landscape without horizontal overflow

- [ ] **Step 5: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat(finance-dashboard): add print/PDF layout with terminal KPI cards and report header"
```

---

## Task 10: Light mode verification and push to preview

**Files:**
- No code changes — verification and deploy only

- [ ] **Step 1: Test dark mode end-to-end**

1. Set theme to dark mode via the theme toggle
2. Click Load Dashboard — sign in if required
3. Confirm:
   - KPI cards: colored accent lines visible, glow on values, JetBrains Mono numbers
   - Charts: new terminal palette colors
   - SKU cost list: JetBrains Mono amber
   - Inactive table: JetBrains Mono on cost/number columns
   - Action row: Print + Export CSV buttons visible

- [ ] **Step 2: Test light mode end-to-end**

1. Toggle to light mode
2. Reload dashboard (or re-run Load Dashboard)
3. Confirm:
   - KPI cards: accent lines visible, no glow, accents use deepened light-mode colors
   - Charts re-render correctly (colors are theme-independent hex values — should look identical)
   - All text remains legible

- [ ] **Step 3: Test print from both modes**

1. From dark mode, click Print / PDF → confirm print preview renders white background with print KPI cards
2. From light mode, click Print / PDF → same result
3. Both should produce identical print output regardless of current theme

- [ ] **Step 4: Push to preview**

```bash
git push
```

Wait ~60 seconds for GitHub Actions to deploy, then visit the preview URL and repeat steps 1-3 with real M365 data.

- [ ] **Step 5: Final commit if any tweaks made during preview testing**

```bash
git add tools/finance-dashboard/index.html
git commit -m "fix(finance-dashboard): preview testing adjustments"
git push
```

---

## Self-Review Notes

**Spec coverage check:**
- ✓ Syne page title (Task 7)
- ✓ JetBrains Mono for all numbers (Tasks 3, 4, 5, 6)
- ✓ Open Sans inherited from shared (no change needed — already the body font)
- ✓ KPI cards with colored accent lines + glow (Tasks 3, 4)
- ✓ 4 cards: Monthly Spend / Active Seats / Savings Found / Inactive Cost (Task 4)
- ✓ Chart.js palette updated (Task 5)
- ✓ Chart.js global font config (Task 2)
- ✓ Section labels — `.section-title` uses `var(--muted2)` and uppercase already; no explicit task needed as it already matches
- ✓ Inactive table JetBrains Mono (Task 6)
- ✓ Projection table JetBrains Mono (Task 6)
- ✓ Print / PDF button (Task 7, 8)
- ✓ Print KPI cards with colored accent lines (Task 9)
- ✓ Print: report header + timestamp (Task 9)
- ✓ Print: A4 landscape (Task 9)
- ✓ Print: footer watermark (Task 9)
- ✓ Print: topbar/configure/controls hidden (Task 9)
- ✓ Print: shortened "12-mo Projection" label / `$X.XXM` format (Task 9)
- ✓ No changes to shared/ files (confirmed — no task touches shared/)
