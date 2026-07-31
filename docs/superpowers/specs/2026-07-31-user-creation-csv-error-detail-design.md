# User Creation — CSV Error Detail — Design Spec
**Date:** 2026-07-31
**Tool path:** `tools/user-creation/index.html`

---

## Problem

When CSV validation in Step 1 finds bad rows (missing name, invalid UPN format, bad `RequiredMailboxSize`, EID too long), the tool only shows a count: *"N row(s) have errors — fix the CSV and re-upload."* The "Continue" button stays disabled, so the user can never reach Step 2's review table, where the specific per-row reason is normally rendered. They have no way to know which rows are bad or why without guessing, opening dev tools, or re-uploading repeatedly.

## Fix

Add a small errors-only table under the existing red banner in Step 1, listing every row that failed validation with enough detail to jump straight to it in the source spreadsheet and fix it.

### Row numbering

`row.num` changes from `i + 1` (data-row count, ignoring header) to `i + 2` (matches the literal row number in Excel/Sheets, where row 1 is the header). This is a single change at the point `st.rows` is built from `parsed.rows.map(...)`, so the new numbering is consistent everywhere `row.num` is already displayed (Step 2 review table included) — not just the new error table.

### Errors table

- Rendered directly below the `#s1Err` banner, only when hard errors exist.
- Columns: **Row** (the renumbered value above), **Name** (`fn ln`, or blank if both missing), **EID**, **Error** (`row.err` text, already produced by existing validation).
- Hidden entirely (no empty table) when there are zero hard errors.

### Shared render path

Both existing call sites that currently just set the count message:
- `parseAndRender()` (initial column/field validation)
- `checkUpns()` (final gate, after the UPN-exists check pass)

will call one new function, e.g. `renderCsvErrorTable(rows)`, so the table is always built from the same data as the banner count and never goes stale between the two passes.

### Out of scope

- No change to the block-until-fixed gating behavior — hard errors still prevent proceeding to Step 2.
- No change to warning handling (UPN-already-exists) — that stays as today, surfaced only in the Step 2 review table.
