# Account Lockdown — Visual Polish Pass (Sidebar + Amber Signal)

**Date:** 2026-08-05
**Status:** Approved

## Problem

The initial build (shipped to preview 2026-08-05, see `2026-08-04-security-lockdown-design.md`) is functionally complete but visually reads as a plain form. Josh reviewed it on the preview deploy and wants it to feel more robust and security-centric, plus wants an informational panel explaining what the tool actually does and why, since a tech opening this for the first time has no in-tool context beyond the wizard fields themselves.

## Decision

Add a persistent right-hand info sidebar to the wizard, and extend the existing dark-glass header treatment with an amber "signal" accent — deliberately reconsidering (not reversing outright) the original spec's "no warning color" call. The tone stays calm and non-alarming (per the original spec's explicit rejection of a red/full-alert scheme), but amber is now used consistently to say "this matters," with red held in reserve for the one fact that's genuinely irreversible.

Three color/layout directions were mocked up (deepened neutral slate, amber signal throughout, red-only-at-the-edge); Josh picked the amber-signal direction because it "attracts the eye but doesn't make it appear that the actions are not reversible."

### Layout

The wizard shell changes from a single centered column (`.shell`, max-width 760px) to a two-column layout inside a wider shell (max-width ~1000px):
- **Left column:** existing wizard content (Steps 1–3), unchanged in structure.
- **Right column (~220px):** new persistent info sidebar, `position: sticky` at the top so it stays visible as the main column scrolls.
- The dark-glass header stays full-width above both columns, unchanged in structure.
- **Desktop-only, no responsive breakpoint** — consistent with the rest of the hub, which makes the same assumption. Not revisiting this for any tool right now; noted as a possible future pass across the whole hub, not scoped here.

### Sidebar content

**Static, shown on Steps 1 and 2 (Add Accounts, Review & Confirm):**

```
WHAT HAPPENS
① Revoke sessions      — kills active tokens immediately
② Reset password       — random temp password, forced change
③ Reset MFA            — removes all registered auth methods
④ Block sign-in        — disables the account entirely

⚠ Cannot be undone from this tool. Every action
   is logged to Entra's audit trail. Confirm this
   is approved before continuing.
```

**Dynamic, shown on Step 3 (Results):** the same four numbered rows, but each row's number badge switches from amber "pending" to green-check or red-x as that specific action completes across the whole queue (i.e., it reflects aggregate progress across all accounts, not a single account). A one-line live tally appears below the list, e.g. "6 of 8 accounts fully locked down." This reuses the existing `st.results[].actions` state that already drives the main results table — no new state is introduced, just a second read/render of the same data from a new `renderSidebarProgress()` function, called at the same points `renderResults()` already is.

"Fully locked down" for the tally means every one of the four actions succeeded for that account (mirrors the existing `overall-badge--full` logic in `renderResults()`).

### Visual language

Extends the existing `#1c1f26` dark-glass header (`.lockdown-header`) rather than replacing it — same blur/radius/shadow recipe, plus:
- Header badge text (`.lockdown-badge`) changes from neutral gray (`#c9cdd6`) to amber (`#e2a13d`) — now matches the lock icon stroke color, which was already amber.
- Sidebar panel (`.lockdown-sidebar`, new): `#1c1f26` fill matching the header, `3px` solid amber (`#e2a13d`) left border, amber-tinted (`rgba(226,161,61,.25)`) number badges, amber heading text.
- The single red element in the whole tool remains the "cannot be undone" callout at the bottom of the sidebar — same red tokens already used by `.confirm-warning` in Step 2 (`var(--red-light)` / `var(--red-border)`). Red is not used anywhere else in the sidebar or header.
- Everything outside the header/sidebar (search box, queue table, buttons, results table) is unchanged — still normal hub glass, preserving the original spec's intent that the tool still feels part of the hub rather than a bolted-on separate app.

## Implementation Notes

- New CSS: `.lockdown-sidebar`, `.sidebar-step`, `.sidebar-step .num` (three visual states: pending/success/failed), `.sidebar-warning`, `.sidebar-tally`. Shell/header CSS (`.shell`, `.lockdown-header`, `.lockdown-badge`) gets adjusted, not replaced.
- New JS: `renderSidebarProgress()` — reads `st.results`, updates the four badge states + tally text. No new state object; purely a render function over existing data.
- No changes to any Graph call, action logic, retry logic, or CSV export — this pass is presentation-only.

## Testing

No new unit-testable logic (no pure functions, no new data shaping) — this is markup/CSS restructuring plus one render function reading existing state. Verified the same way as the rest of this codebase: a Node syntax-check of the tool's inline `<script>` block. Full visual verification happens as part of the already-pending Task 15 (end-to-end browser check on the preview deploy), not as a separate testing pass.

## Out of Scope

- Responsive/stacked layout for narrow viewports (explicitly deferred — desktop-only, matches the rest of the hub).
- Any change to the Lockdown execution engine, retry logic, or CSV export.
- Any change to the hub landing-page card (still the plain tinted-glass square from the original spec — this pass only touches the tool's own page).
