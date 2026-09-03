# On-Call Rotation — Build Mode Design Spec
**Date:** 2026-09-03
**Status:** Approved

## Overview

Adds an in-app way for admins to generate future rotation cycles (new years), so the On-Call Rotation tool can fully retire `On Call Rotation.xlsx` as a reference/authoring source instead of just displaying a one-time export of it. Supersedes the "possible scope expansion" note from the 2026-09-02 visual redesign — Josh's director gave positive feedback on making this "the main on-call rotation app the team uses from here on out."

**Why:** Today's build (see `2026-09-02-oncall-rotation-design.md` and `2026-09-02-oncall-rotation-visual-redesign-design.md`) only supports editing rows that already exist. Extending into a new year (e.g. 2027) requires manually adding 52 rows one at a time with no assistance, which is worse than the spreadsheet it's replacing. This closes that gap while deliberately keeping the "no algorithmic rotation generation" constraint from the original spec: the app proposes a starting point based on the real historical pattern, but every proposed week stays fully editable before anything is saved — never a black-box generator.

## Access

No changes from the current model:
- **View:** any signed-in tenant user except `SG-IT-Tools-GSD` members (deny-gate, confirmed to stay indefinitely, not just during the beta period).
- **Edit/Build:** `SG-IT-Tools-OnCall-Admin` members only. Build Mode is gated exactly like today's existing edit mode — no new group, no new permission tier. Techs remain view-only; "build" refers to admins actively maintaining the schedule going forward, not a new tech-facing capability.

Existing contact-card editing (name, phones, In Rotation toggle) is untouched by this feature.

## Entry Point

- Year tabs (2024 / 2025 / 2026 today) become **dynamic**, derived from the distinct years present in `schedule`, instead of hardcoded — so a newly-committed year appears automatically.
- A **"Build [Year] Rotation"** button appears next to the tabs whenever the next sequential year (last existing year + 1) has no `schedule` rows, or has partial rows. The button targets that specific gap year — there's no generic "pick any year" flow, since cycles are always sequential.

## Setup

Clicking "Build [Year] Rotation" opens a setup bar:
- **Start date:** defaults to January 1 of the target year (not editable in v1 — full-year cycles only, see Out of Scope).
- **Length:** fixed at full year (52/53 weeks depending on the year's Sunday-start week count). No custom week-count option — admins can already trim/extend the result by editing individual proposed blocks after generation, so a shorter/partial build doesn't need its own setup path.
- **Continuing from:** read-only, computed field showing the last real assigned tech before the target year and who comes next in rotation order (e.g. "Continuing from Krista Guthrie → next: Joe Randazzo").

## Generation Logic

- Cycles through `rotationTechs` in array order, wrapping around, starting from the tech immediately after the last real `schedule` row's assigned tech (chronologically, regardless of year boundary).
- **Gap-fill only:** a proposed block is generated only for weeks in the target year that have no existing `schedule` row. Weeks that already have a row (e.g. an admin manually added a few 2027 rows before ever using Build Mode) are rendered in the ribbon for context/continuity but are **not** proposed blocks — not draggable, not part of the click-to-edit flow, left exactly as saved.
- The roster order used is whatever `rotationTechs` is at the moment "Build" is clicked. There is no mid-generation roster editing — if the order is wrong, the admin fixes the roster first (see Roster Reordering) and re-clicks Build, which discards any in-progress unsaved proposal and regenerates.
- No time-off or blackout awareness during generation — the generator never guesses at time off. Any adjustment for a known future absence is a manual edit on the affected proposed block (see Canvas Interactions).
- No conflict detection: by construction, exactly one tech is assigned per week and gap-fill never touches an existing row, so there's nothing meaningful to flag.

## Roster Reordering

- Rotation roster cards (the `rotationTechs` grid) gain a drag handle to reorder the underlying array. This order **is** the rotation sequence Build Mode cycles through — it's a prerequisite control for correct generation, not a standalone feature.
- Reordering saves immediately through the existing edit-mode save path, exactly like any other roster edit today (name/phone changes, In Rotation toggle) — it is not part of the Build Mode commit transaction.

## Build Canvas

Full-screen(within-page) canvas replacing the calendar strip while building, matching Glass Control Center tokens throughout (see `it-tools-design-system` memory for the token set):

- **Blocks:** 56px wide, showing the tech's initials and the week's start date on the face, colored with the same per-tech palette already used in the hero/calendar/roster (no new color mapping). Grouped by month with a small uppercase month label above each row, matching the existing calendar strip's grouping convention.
- **Drag-to-swap:** dragging one proposed block onto another swaps their assigned tech only (dates stay fixed to their position). A lifted block shows a small "swap with [date] →" label; the drop target gets a dashed outline. Only proposed blocks are draggable — pre-existing rows shown for gap-fill context are not.
- **Click-to-edit:** clicking a proposed block opens a small inline popover anchored to the block (not the existing full slide-over panel) with the same three fields as today's row editor: tech (dropdown), time off, notes. This is the only mechanism for setting time off/notes on a generated week.
- **Commit bar:** sticky bar at the bottom of the canvas showing a plain count ("52 weeks proposed"), with **Discard** (clears the unsaved proposal, no write) and **Commit [Year] Rotation** (writes all proposed weeks into `schedule` in one save, then the canvas closes and the normal calendar strip re-renders with the new year's tab now populated).

## Backend

No changes. Build Mode is entirely client-side authoring — it produces ordinary `schedule` rows in local state, and "Commit" calls the existing `OnCallSave` function exactly as today's row-by-row edits do. `OnCallGet`/`OnCallSave`'s contract, auth checks, and blob structure are unaffected.

## Out of Scope

- **Custom start date / partial-length builds.** v1 always proposes a full calendar year starting January 1. An admin who wants a shorter or offset range can generate the full year and then manually clear/adjust the blocks they don't want — no separate short-range setup flow.
- **Mid-generation roster edits.** Changing `rotationTechs` while a proposal is open isn't supported; fix the roster, then generate.
- **Time-off/blackout-aware generation.** The generator has no concept of known future absences; all such adjustments happen after generation via the click-to-edit popover.
- **Conflict detection.** Not meaningful given gap-fill-only generation (see Generation Logic).
- **Year-tab overflow/archive UI.** As the tool accumulates years (hypothetically 10-20+), the flat year-tab row will eventually need to collapse older years into a group or become scrollable. Not needed at today's scale (3 years) and not a data-volume problem (even 20 years of weekly rows is trivially small for the blob) — purely a future navigation concern. **Backlog note, not part of this build:** revisit once the tab row actually becomes unwieldy (roughly 8-10+ tabs), not preemptively.
