# License Spend — Progressive Loading Design

**Date:** 2026-04-21
**Tool:** Finance Dashboard (`tools/finance-dashboard/index.html`)
**Status:** Approved — ready for implementation

---

## Problem

The License Spend dashboard currently blocks all rendering until the entire audit-log verification pass completes. This means users stare at a phase line spinner for 30–90 seconds before seeing anything, even though the majority of data (total spend, SKU breakdown, waste) is available within the first few seconds.

---

## Solution Overview

Split `loadDashboard()` into two rendering stages so the dashboard feels instant and communicates exactly what it is still computing.

- **Stage 1 — Initial render** fires immediately after step 3 (user processing), before any audit batches run. Shows all cards and charts with exact values where possible, and "Refining" badges on values that depend on audit verification.
- **Stage 2 — Fine-tune pass** runs the existing audit batch loop. Each batch updates KPI values in-place and ticks a progress bar. Tables show shimmer skeletons during this pass. When all batches complete, skeletons are replaced with real rows and badges are cleared.

No layout shift. The dashboard shape is fully established at Stage 1; Stage 2 only updates values within existing elements.

---

## Stage 1 — Initial Render

Triggered after step 3 (`processedUsers` is built, `skuStats` and `deptMap` computed).

### What renders

| Element | State | Reason |
|---|---|---|
| Hero spend card | Exact — no badge | Pure license-cost math, unaffected by audit logs |
| KPI: Active Seats | Value shown + `Refining ⟳` badge | Will increase as batches reclassify inactive → active |
| KPI: Inactive Cost | Value shown + `Refining ⟳` badge | Will decrease as batches reclassify users |
| KPI: Savings Found | Value shown + `Refining ⟳` badge | Derived from inactive cost + waste |
| SKU donut chart | Exact — no badge | Subscription-level data only |
| Utilization bar chart | Rendered — no badge | `inactiveCount` per SKU may shift slightly |
| Department chart | Rendered — no badge | Inactive spend per dept may shift slightly |
| Projection section | Rendered | Uses monthly/inactive cost, will update when Stage 2 completes |
| Inactive Holders table | Shimmer skeleton (5 rows) | Row list changes during verification |
| Active License Holders table | Shimmer skeleton (5 rows) | Row list changes during verification |
| Step tracker | `✓ Licenses → ✓ Users → ✓ Analysis → ⟳ Fine-tune` | Communicates current position in load sequence |
| Progress bar | Visible, 0% — "Fine-tune pass — verifying inactive users" | Signals active background work |

### Step tracker

A small horizontal stepper above the progress bar, always visible while loading:

```
✓ Licenses  ──  ✓ Users  ──  ✓ Analysis  ──  ⟳ Fine-tune
```

All steps use the existing `setPhase()` infrastructure; the stepper is a separate static element updated at key checkpoints.

---

## Stage 2 — Fine-Tune Pass (Audit Batch Loop)

The existing batch loop in step 3b runs unchanged in logic. After each batch of 20 users:

1. KPI values for "Inactive Cost", "Savings Found", and "Active Seats" are recalculated and updated in-place (no re-render of other elements).
2. Progress bar label updates: `Batch X of Y — cross-checking sign-in audit logs…`
3. Progress bar fill advances proportionally.
4. `Refining ⟳` badges remain on affected KPI cards throughout.

### Shimmer skeleton rows

Both `#inactiveTableWrap` and `#activeTableWrap` receive skeleton markup at Stage 1:

- 5 skeleton rows per table, matching the real table column structure
- Each cell contains a `<div class="skel">` placeholder with a shimmer animation
- Table header renders normally (columns are known) — only `<tbody>` is skeleton
- The `.skel` shimmer styles (`@keyframes shimmer`, background gradient, animation) must be added to `tools/finance-dashboard/index.html` local `<style>` block — they do not currently exist in `shared/styles.css`

---

## Stage 2 Completion

When the last batch finishes:

1. `renderAll()` fires as before — overwrites both table wrappers with real populated rows.
2. KPI "Refining ⟳" badges swap to `✓ Confirmed` (green) for 3 seconds, then fade out and are removed from the DOM.
3. Step tracker updates to `✓ Licenses → ✓ Users → ✓ Analysis → ✓ Fine-tune`.
4. Progress bar replaced by green completion banner: `✓ Audit scan complete — X users reclassified active. All figures confirmed.` (existing `errBanner` info style, dismisses after 6 seconds if no reclassifications, stays if reclassifications > 0).
5. Projection section re-renders with final inactive cost.

---

## New Functions

### `renderInitial(processedUsers, skuList, deptMap, days)`
Calls all existing render functions (`renderStats`, `renderDonut`, `renderUtilisation`, `renderDeptChart`, `renderProjections`) then:
- Adds `Refining` badges to KPI cards for inactive cost and savings
- Calls `renderTableSkeletons()` for both table wrappers
- Shows and initialises the step tracker and progress bar

### `renderTableSkeletons()`
Writes shimmer skeleton rows into `#inactiveTableWrap` and `#activeTableWrap`. Matches the fixed column widths of the real tables so no layout shift occurs when real rows replace them.

### `updateBatchProgress(batchNum, totalBatches, processedUsers, skuList)`
Called after each audit batch completes. Updates:
- Progress bar fill and label
- KPI values for Inactive Cost, Savings Found, Active Seats (in-place text update, no full re-render)

### `finaliseDashboard(reclaimedAudit)`
Called once all batches complete. Calls `renderAll()`, clears Refining badges → Confirmed → fade, updates step tracker, shows completion banner.

---

## Badge Specification

| State | Text | Style |
|---|---|---|
| Scanning | `⟳ Refining` | Blue-light background, blue text, spinner |
| Complete | `✓ Confirmed` | Green-light background, green text |
| Fade | Opacity 0 over 0.4s, then `remove()` | — |

---

## Constraints

- No layout shift: all card and table dimensions are established at Stage 1. Shimmer rows match real row height.
- No new dependencies: shimmer animation uses the existing `@keyframes shimmer` already in `shared/styles.css` (`.skel` class).
- Projection section re-renders at completion since it depends on final inactive cost — acceptable because it is below the fold.
- Charts are not re-rendered after Stage 2 to avoid flash. The shift in utilization/dept chart inactive values is small and acceptable.

---

## Deployment

Target branch: `testing` → validate on preview → merge to `main`.
Preview URL: jgdev-ch.github.io/it-tools-preview/
