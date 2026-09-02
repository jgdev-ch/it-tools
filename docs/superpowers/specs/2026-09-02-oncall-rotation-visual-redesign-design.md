# On-Call Rotation: Visual Redesign Design Spec
**Date:** 2026-09-02
**Status:** Approved

## Overview

Replaces the current On-Call Rotation UI (`tools/on-call/index.html`, built earlier the same day per `2026-09-02-oncall-rotation-design.md`) with a fully restyled front end. The data model, auth/gating, and backend contract (`ONCALL_GET_URL`/`ONCALL_SAVE_URL`, the `schedule`/`rotationTechs`/`otherContacts` JSON shape) are **unchanged**; this spec covers presentation and interaction only.

**Why:** The as-built tool worked but read as a spreadsheet dumped into a web page: a plain hero box, a raw `<table>` with naked `<input>` cells in edit mode, and unstyled bordered-box contact cards, none of it using the hub's shared glass `.card` treatment. Explored via the visual-companion brainstorming flow (six mockup rounds: three initial layout directions, three bolder style directions, an expanded calendar with navigation, and the matched contacts roster) before converging on a calendar-strip direction.

## Scope

**In scope:** hero card restyle, schedule presentation (calendar strip replacing the flat table), the click-to-edit interaction pattern (replacing inline `<input>`-per-cell editing), contacts roster restyle, consistent per-person color-coding across both, Lucide icons, copy conventions.

**Out of scope:** any change to `data.json`'s shape, the backend functions, auth/gating logic, or the GSD deny-gate. **No mobile/responsive design work.** The hub is desktop-only by deliberate standing decision (see `hub-no-mobile-scope` memory), so no fallback layout is being designed for narrow viewports.

## Hero Card

Keeps the concept from the original build (auto-resolves the current week via `findCurrentWeek`, unchanged) but restyled: a colored circular avatar (initials, using that person's assigned color, see Color Coding below) instead of plain text, name as the primary heading, phone numbers as small pill chips instead of inline label/value pairs.

## Color Coding (carried across every component)

Each rotation tech is assigned one fixed accent color, used everywhere they appear: their avatar/dot in the hero, their week-tiles on the calendar strip, their contact card in the roster, and the full-year overview rail. This is the thread that ties every restyled piece together into one visual system rather than independently-styled sections. Colors are assigned once (e.g. in a `PERSON_COLORS` map keyed by `shortName`) and reused, not recomputed per component. `otherContacts` (not in rotation) get a single shared neutral gray rather than their own color, since they never appear on the calendar.

## Schedule: Calendar Strip (replaces the flat table)

- **Week-tiles**, not day-tiles: each tile represents one Sunday-start rotation week (matches the data model; this is a calendar-styled presentation of weekly data, not a literal day-by-day calendar).
- **Month-grouped labels** above the strip (e.g. "SEPTEMBER") spanning the tiles that fall in that month, so the strip reads like a calendar even though rotation is weekly.
- **"Today" indicator**: computed client-side on every load exactly like the existing `findCurrentWeek` logic. The tile containing today's date gets a ribbon/highlight. This is presentation only; nothing is stored server-side about "today," so it moves automatically every Sunday and is correct independently for every viewer regardless of when they open the tool. If today falls in a week with no schedule row yet (e.g. next year not seeded), no tile is highlighted, same fallback behavior as the current hero.
- **Notes/time-off indicators**: a small icon badge on any tile with a non-empty `notes` or `timeOff` value, so admins can spot them without opening every tile.
- **Navigation**: year segmented control (2024/2025/2026, replacing the current year-tab row 1:1), Prev/Today/Next buttons, a "jump to person" search box, and a compressed full-year overview rail beneath the strip (one thin colored segment per week, click to jump the main strip to that point). This set exists specifically to make 52+ weeks/year navigable without endless manual scrolling.

## Click-to-Edit Panel (replaces inline `<input>`-per-cell editing)

Clicking any week-tile opens a detail panel:
- **Everyone** (no edit rights, or Edit Mode off): read-only panel showing the assigned tech's name, full phone list, and any notes/time-off value.
- **Admins with Edit Mode on**: the same panel becomes a form: a dropdown to reassign the tech (populated from `rotationTechs`, not free text, so a mistyped name can't silently break the hero/color-coding lookup), a time-off toggle, a notes textarea, and Save/Cancel buttons. Save calls the same `updateScheduleField`-style local mutation as today, then the existing `saveChanges()` flow.

This replaces the current behavior where toggling Edit Mode turns every visible table row into four naked `<input>` elements simultaneously. Instead, only one week is ever being edited at a time, in a focused panel.

## Contacts Roster (replaces the plain bordered contact-card row)

- **Grouped the same way the calendar groups by month**: a "Rotation" section, then an "Other Contacts" section, each with the same small uppercase section-label style used for the calendar's month labels.
- **Cards** reuse the calendar's exact tokens (border color, radius, type scale) so the two sections of the page read as one system, not two different components glued together. Each card shows the person's colored avatar/initials, name, and phone chips (numbers beyond the first couple collapse behind a "+N" indicator rather than listing every number on the collapsed card).
- **Other Contacts cards render visually de-emphasized** (dimmed) relative to Rotation cards. This is an open question going into implementation (flagged during brainstorming, not yet fully resolved): whether dimming alone is enough distinction, or whether it needs to go further (smaller cards, collapsed-by-default). Default to dimming only for v1; Josh will judge this once he can click through the live preview.
- **Same click-to-edit panel pattern** as the calendar: clicking a card opens the read-only or (Edit Mode) editable panel, with name, an "in rotation" toggle (moves the person between the two sections), and phone rows with add/remove controls, matching the calendar panel's Save/Cancel affordance.
- A dashed "+ Add" tile at the end of each group's grid for adding a new rotation member or other contact.

## Icons and Copy

- **No em dashes anywhere in the tool's UI copy** (same standing hub-wide rule as everywhere else in it-tools).
- **Every icon is a real inline Lucide SVG**, matching the rest of the hub's convention (icons are hand-copied inline `<svg>` markup, no Lucide script/CDN dependency), never emoji or unicode glyphs. Concretely: `chevron-left`/`chevron-right` for Prev/Next, `search` for the jump-to-person box, `plus` for add-tiles, `x` for phone-row removal, `file-text` (or similar) for the notes indicator, `palm-tree` for the time-off indicator.

## Not Yet Resolved (defer to live preview)

Per Josh's own plan: once this is wired up and deployed to preview, he'll click through it as a real user would and flag anything that still needs adjustment (e.g. the Other-Contacts de-emphasis question above) rather than resolving every open visual question speculatively now.
