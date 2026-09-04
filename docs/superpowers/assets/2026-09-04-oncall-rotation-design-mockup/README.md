# Handoff: On-Call Rotation, layout 1a ("Now panel + full-year board")

## Overview

A whole-page rearrangement of the existing `tools/on-call/index.html` tool in the IT Tools
hub. The data model, auth/gating, and backend contract are unchanged. This is a
presentation and information-hierarchy change only.

The current tool stacks a hero, a 5-week horizontal strip, a month-pill row, and two 5-up
grids of contact cards, which runs past one screen and answers "who is on call in
November?" only by paging. Layout 1a replaces that with a two-column page:

- **Left rail (376px):** who is on call now, when they hand off, their phone number, the
  queue of the next four techs, and a "needs attention" panel for data problems.
- **Right column:** the entire year as a 12-row x 5-column board (52 week cells, all
  visible at once), a per-tech summary strip, and a single-line "also reachable" bar for
  non-rotation contacts.

Everything fits one 1440x900 screen with no scrolling.

## About the Design Files

The files in this bundle are **design references created in HTML**. They are prototypes
showing intended look and layout, not production code to copy directly.

The target codebase (`jgdev-ch/it-tools-preview`) is vanilla HTML/CSS/JS with no build
step, no framework, no node_modules. Tools are single `tools/<name>/index.html` files that
link `../../shared/styles.css` and `../../shared/auth.js`. **Implement this design in that
existing environment**: keep the `st` state object, the `render*()` function pattern, the
`ITTools.*` helpers, and the CSS-class-per-component style already used in
`tools/on-call/index.html`.

The prototype files here use inline styles and hardcoded token values because they must
render standalone outside the repo. **Do not carry the inline styles across.** In the real
tool, write CSS classes in the page's `<style>` block and reference the `var(--token)`
names from `shared/styles.css`. Every literal hex in this README is followed by the token
it stands for.

## Fidelity

**High fidelity.** Colors, typography, spacing, and radii are final and are taken from
`shared/styles.css` and the existing on-call tool. Recreate pixel-perfectly. Copy is final
as written.

## Screens / Views

### Screen: On-Call Rotation (signed in, admin, view mode)

**Purpose:** answer "who is on call right now and what is their number" in about two
seconds, and "who is on call in any week of any year" without navigating.

**Page shell (unchanged from today):**

- `#topbar`, 58px (`--topbar-h`), rendered by
  `ITTools.ui.renderTopbar({ toolName: "On-Call Rotation", hubRelPath: "../../", status: "beta" })`.
- One addition to the topbar right side for admins: an "On-Call Admin" pill, reusing the
  existing `.account-pill.account-pill--purple` styling and the phone icon already defined
  for the `oncall-admin` gate in `shared/auth.js`. Background `#ede9fe`
  (`--purple-light`), text `#5b21b6` (`--purple`), 1px border `rgba(91,33,182,.22)`,
  radius 20px, padding 3px 10px, 10px/700 uppercase, letter-spacing .05em, 11px icon.
- Page background and `body::before` mesh unchanged.

**Main layout:**

- Container padding `20px 24px 24px` (replaces today's `32px 40px 60px`).
- `display: grid; grid-template-columns: 376px 1fr; gap: 16px`.
- **The `<h1>On-Call Rotation</h1>` and the separate `.admin-toolbar` strip are both
  removed.** The topbar already names the tool, and the admin controls move into the right
  column's toolbar row (see below). This is where most of the reclaimed vertical space
  comes from.

---

#### Left rail

Three stacked cards, `display: flex; flex-direction: column; gap: 12px`.

**1. "On call now" card**

- Radius 16px, padding 18px.
- Background `color-mix(in srgb, var(--tech-color) 20%, var(--glass-fill))`.
- Border 1px `color-mix(in srgb, var(--tech-color) 28%, var(--glass-border))`.
- `backdrop-filter: blur(22px) saturate(180%)`.
- This is the existing `.hero` treatment, except tinted with **the on-call tech's own
  color** rather than a fixed green. Nick Zoshak is `#9333ea`, so the whole card is
  purple-tinted. It changes color every Sunday, which is the point.
- **Eyebrow:** existing headset Lucide icon (12px) + "On call now". 10px/700 uppercase,
  letter-spacing .12em, color `color-mix(in srgb, var(--tech-color) 72%, #1c1c1e)`.
- **Identity row:** `flex, gap 14px, margin-top 12px`.
  - Avatar 60x60, radius 50%, background = tech color, 2px border
    `rgba(255,255,255,.7)`, initials 21px/800 white.
  - Name 26px/800, letter-spacing -.02em, line-height 1.1, color `#1c1c1e` (`--text`).
  - Sub-line 12px, color `#4a4a52`: "August 30th to September 5th &middot; week 35".
    Use the existing `weekRangeLabel(startDate)` output verbatim, then the ISO week number.
- **Week progress:** 7 pips, `flex; gap 4px; margin 16px 0 8px`. Each `flex: 1; height:
  7px; border-radius: 4px`. Days already elapsed and today: solid tech color. Today's pip
  additionally gets `box-shadow: 0 0 0 2px rgba(255,255,255,.85)`. Remaining days:
  tech color at 22% alpha. Computed client-side from today's date, same as
  `findCurrentWeek`. Nothing stored server-side.
- **Handoff line:** `flex; align-items: baseline; justify-content: space-between`.
  - Left, 12px, color `#4a4a52`: "Hands off to **Joe Randazzo**, Sunday Sep 6th" (name in
    700, `#1c1c1e`).
  - Right, 22px/800, letter-spacing -.02em, color
    `color-mix(in srgb, var(--tech-color) 80%, #1c1c1e)`: "3d 07h".
  - The countdown is the largest number on the page after the tech's name. Ticks live;
    recompute on a 60s interval, no seconds shown.
- Divider: 1px `rgba(255,255,255,.6)`, margin `14px 0 12px`.
- **Phone block:** one row per number on file. Background `rgba(255,255,255,.6)`, radius
  10px, padding 9px 12px, `flex; justify-content: space-between; align-items: center`.
  - Label 9px/700 uppercase, letter-spacing .1em, `#6e6e73` (`--muted`).
  - Number 15px/700 in `'Cascadia Code', Consolas, monospace` (the existing `.mono`
    stack), letter-spacing -.01em.
  - "Copy" button: 1px `#dde1e8` (`--border`), background `#fff` (`--surface`), radius 8px,
    padding 6px 11px, 11px/600, color `#1a56db` (`--blue`). Writes the number to the
    clipboard.
  - Multiple numbers stack with 6px gap.
- **Coverage note:** 10px, `#6e6e73`, margin-top 8px. Text is derived, not authored:
  when a tech has exactly one number, "Only number on file. No 8x8, no Teams line."
  When they have several, list what is missing or omit the line entirely.

**2. "Queue" card**

- Radius 16px, `--glass-fill` / `--glass-border`, `blur(22px) saturate(180%)`,
  padding `14px 16px 8px`.
- Section label 10px/700 uppercase, letter-spacing .12em, `#6e6e73`, margin-bottom 4px.
- Four rows, one per upcoming week, in date order. Each row: `flex; gap 10px; padding
  9px 0`, 1px bottom border `rgba(0,0,0,.06)` except the last.
  - 8x8 dot, radius 50%, background = that tech's color.
  - Name, `flex: 1`. First row 13px/700; the rest 13px/600.
  - Date 11px `#6e6e73` ("Sep 6").
  - First row gets a "next up" pill: 10px/700, background `#d1fae5` (`--green-light`),
    color `#047857` (`--green`), radius 20px, padding 2px 8px.
  - Rows 2-4 get a relative-time label instead: 10px/600 `#6e6e73`, `min-width: 44px`,
    right-aligned, "in 10d" / "in 17d" / "in 24d".
- Clicking a row opens that week in the existing detail panel.

**3. "Needs attention" card**

- Same glass treatment, padding `14px 16px`.
- Label "Needs attention", same 10px/700 uppercase style, margin-bottom 9px.
- Each item: `flex; gap 9px; align-items: flex-start`, 11.5px/1.45 text `#4a4a52`,
  13px Lucide icon in `#92400e` (`--amber`), `margin-top: 1px`.
- Items are **derived from the data, never authored**. The two shown are the two that
  `data.json` actually produces today:
  - `file-text` icon: "3 weeks in 2026 are still assigned to **David**, who is not in the
    roster. Feb 1, Mar 15, Apr 26." Detection: any `schedule[].tech` with no matching
    `rotationTechs[].shortName`. This is a real bug in the live data that the current UI
    hides by falling back to gray.
  - `palm-tree` icon: "No time off recorded anywhere in 2026. Worth a pass before the
    holidays." Detection: no row in the selected year has a non-empty `timeOff`.
- If nothing is detected, hide the card entirely rather than showing an empty state.

---

#### Right column

**Toolbar row:** `flex; justify-content: space-between; align-items: center;
margin-bottom: 12px`.

- Left group, `flex; gap 10px`:
  - Year segmented control. Wrapper: background `rgba(255,255,255,.6)`, 1px border
    `rgba(255,255,255,.7)`, radius 10px, padding 3px. Each year: padding 6px 14px, radius
    7px, 12px/600, `#6e6e73`. Selected: background `#1a56db` (`--blue`), white, 700.
    Years stay dynamic, derived from distinct years in `schedule`, per the build-mode spec.
  - Count text 11px `#6e6e73`: "52 weeks &middot; 5 techs".
- Right group, `flex; gap 8px`. All three buttons: background `#fff`, 1px `#dde1e8`,
  radius 9px, padding 7px 12px, 12px/600, 13-14px Lucide icon, 6px gap.
  - "Find a person" (`search` icon) replaces today's "Jump to person" dropdown.
  - "Edit" (`pencil` icon) replaces the whole `.admin-toolbar` strip. Admin-only.
    Active state: background `#1a56db`, white.
  - "Build 2027" (`plus` icon): background `#047857` (`--green`), white, no border,
    padding 7px 13px, 12px/700. Admin-only, and only when the next sequential year has a
    gap, exactly as `getNextGapYear()` already decides.
  - **Prev / Today / Next are gone.** With the full year on screen there is nothing to
    page through.

**Year board**

- Card: `--glass-fill` / `--glass-border`, `blur(22px) saturate(180%)`, radius 16px,
  padding `14px 16px`.
- Grid: `display: grid; grid-template-columns: 34px repeat(5, 1fr); gap: 5px;
  align-items: center`.
- 12 rows, one per month. First cell of each row is the month label: 9px/700, letter
  spacing .1em, `#9a9a9f` (`--muted2`). The month containing today is `#1c1c1e` instead.
- Then up to 5 week cells in date order. Months with only 4 Sundays get one empty `<div>`
  so columns stay aligned. Never reflow the grid to fit.
- **Week cell:** `height: 38px; border-radius: 8px; background: <tech color>; color: #fff;
  flex; align-items: center; justify-content: center; gap: 5px; cursor: pointer`.
  - Day number 10px, `opacity: .75`.
  - Initials 11px/800.
  - Click opens the existing week detail panel. Hover: lift 1px + `--shadow-sm`.
- **Today's cell:** `box-shadow: 0 0 0 2px #1c1c1e, 0 4px 12px rgba(0,0,0,.2)`, plus a
  "NOW" tag absolutely positioned at `top: -9px; left: 50%; translateX(-50%)`, background
  `#1c1c1e`, white, 8px/800, letter-spacing .06em, padding 2px 7px, radius 8px.
- **Next week's cell:** `box-shadow: 0 0 0 1.5px rgba(28,28,30,.35)`, no tag.
- **Unmatched tech cell** (the David case): background `#f0f2f5` (`--surface2`), 1px
  **dashed** `#9a9a9f`, text `#6e6e73`, initials from whatever string is in `tech`. This
  makes the data problem visible in place, and pairs with the "needs attention" item.
- Cells with `timeOff` or `notes` get the existing `palm-tree` / `file-text` badge at
  10px, white at 80% opacity, in the cell's top-right corner.

**Per-tech summary strip**

- `display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px; margin-top: 12px`.
  One card per rotation tech, in `rotationTechs` order.
- Card: `--glass-fill` / `--glass-border`, `blur(16px)`, radius 12px, padding `10px 12px`,
  and `border-left: 3px solid <tech color>` as the only color carrier.
- Line 1: name, 12px/700.
- Line 2: 10.5px `#6e6e73`, "10 weeks &middot; next Sep 13", or "10 weeks &middot; on call
  now" for the current tech. Week count is that tech's row count in the selected year.
- Line 3: 10.5px, "4 numbers on file". When the count is 1, color it `#92400e`
  (`--amber`) as a soft warning.
- Clicking a card opens that person in the existing contact panel.
- **This replaces the 5-up 172px-tall contact card grid.** Same information, roughly a
  fifth of the height, and it now carries the two facts a planner actually wants (how many
  weeks, when next).

**"Also reachable" bar**

- One line. `flex; gap 10px; align-items: center; margin-top: 10px; padding: 9px 14px`,
  background `rgba(255,255,255,.4)`, 1px `rgba(255,255,255,.6)`, radius 12px.
- Label 10px/700 uppercase, letter-spacing .1em, `#6e6e73`: "Also reachable".
- One chip per `otherContacts` entry: 20px gray avatar (`#9ca3af`, 8px/800 initials) +
  name at 11.5px `#4a4a52`. Click opens the contact panel.
- **This replaces the second 172px card grid.** Non-rotation contacts never appear on the
  calendar, so they get one line, not a whole section. It also resolves the open question
  from the visual-redesign spec about how far to de-emphasize Other Contacts: the answer
  is a different component, not a dimmed copy of the same one.
- In edit mode, append a dashed `+` chip for adding a contact.

## Interactions & Behavior

Unchanged from the current tool unless noted.

- **Week cell click** -> existing `openWeekPanel(startDate)` slide-over. Read-only, or the
  edit form when admin + edit mode.
- **Queue row / summary card / "also reachable" chip click** -> existing
  `openContactPanel(group, idx)`.
- **Copy button** -> `navigator.clipboard.writeText(number)`; swap the label to "Copied"
  for 1.5s, then back.
- **Year tab click** -> `setYear(y)`. The board re-renders in place. No strip offset state
  is needed any more, so `st.stripStart`, `shiftStrip()`, `jumpToWeek()`, `goToday()`,
  `jumpToMonth()`, and `renderMonthPills()` can all be deleted.
- **"Find a person"** -> opens the existing person list as a popover; picking a person
  highlights that tech's cells across the whole board (others drop to `opacity: .35`) and
  scrolls nothing, since the year is already visible. Picking again, or Escape, clears it.
- **Edit toggle** -> same `editMode` flag and same panel-based editing. Board cells become
  draggable to swap assignments, matching the build-canvas drag-to-swap behavior that
  already exists.
- **Build [Year]** -> unchanged flow: setup bar, then the build canvas replaces the board.
- **Countdown** -> `setInterval` at 60s, recomputing "Nd HHh" to the next Sunday 00:00
  local. Clear it on unmount.
- **Hover** on week cells and cards: `transform: translateY(-1px)` and `--shadow-sm`,
  `transition: transform .15s, box-shadow .15s`.
- **Card entrance:** none. The current `cardIn` stagger belongs to the hub's tile grid,
  not here; 52 staggered cells would read as noise.
- **Responsive:** none. The hub is desktop-only by standing decision.

## State Management

No new state beyond what the tool already has.

- `st.data` — the `{ schedule, rotationTechs, otherContacts }` blob from `OnCallGet`.
- `st.year` — selected year string. Now the only navigation state.
- `st.isAdmin`, `editMode`, `st.panel`, `st.draft`, `st.build` — unchanged.
- `st.personColors` — unchanged, built by `buildPersonColors()`.
- `st.highlightTech` — **new**, nullable `shortName` set by "Find a person".
- Countdown interval handle — new, module-level.
- **Removed:** `st.stripStart`.

Derived per render, never stored: current week (`findCurrentWeek`), the next four weeks,
days/hours to handoff, per-tech week counts and next-shift dates for the selected year,
unmatched-tech list, and the time-off-missing check.

Data fetching unchanged: `OnCallGet` on load, `OnCallSave` on every mutation.

## Design Tokens

All from `shared/styles.css` unless marked. Use the `var()` names, not the literals.

**Surfaces:** `--bg` #eef0f4 &middot; `--page-2` #dde1e8 &middot; `--surface` #ffffff
&middot; `--surface2` #f0f2f5 &middot; `--surface3` #e5e8ed
**Glass:** `--glass-fill` rgba(255,255,255,.55) &middot; `--glass-border`
rgba(255,255,255,.65). Also used, not tokenized: rgba(255,255,255,.6) and .4 fills,
rgba(255,255,255,.7) and .6 borders.
**Borders:** `--border` #dde1e8 &middot; `--border-mid` #c4c9d4 &middot; hairline
rgba(0,0,0,.06)
**Text:** `--text` #1c1c1e &middot; `--muted` #6e6e73 &middot; `--muted2` #9a9a9f &middot;
secondary body #4a4a52 (not tokenized; between `--text` and `--muted`)
**Accents:** `--blue` #1a56db &middot; `--blue-light` #e8f0fe &middot; `--blue-border`
#93b4f5 &middot; `--green` #047857 &middot; `--green-light` #d1fae5 &middot; `--amber`
#92400e &middot; `--amber-light` #fef3c7 &middot; `--purple` #5b21b6 &middot;
`--purple-light` #ede9fe
**Per-tech palette** (`PERSON_PALETTE`, assigned by sorted `shortName`, unchanged):
Joe #059669 &middot; Joshua #1a56db &middot; Krista #d97706 &middot; Nick #9333ea &middot;
Robert #dc2626. Overflow: #0891b2, #db2777. `OTHER_CONTACT_COLOR` #9ca3af, also the
fallback for an unmatched tech.
**Radii:** `--radius` 14px &middot; `--radius-sm` 9px &middot; `--radius-xs` 5px. Plus
16px cards, 12px sub-cards, 8px week cells, 20px pills.
**Shadows:** `--shadow-sm` and `--shadow-md`. Plus today's cell
`0 0 0 2px #1c1c1e, 0 4px 12px rgba(0,0,0,.2)`.
**Type:** `'Plus Jakarta Sans', system-ui, sans-serif`. Mono:
`'Cascadia Code', 'Consolas', monospace`.
Scale used here: 26/800 name, 22/800 countdown, 15/700 mono phone, 13/700 and 12/700 card
titles, 12 and 11.5 body, 11/800 cell initials, 10.5 and 10 meta, 10/700 uppercase section
labels (letter-spacing .12em), 9/700 micro labels (letter-spacing .1em).
**Spacing:** 4, 5, 6, 8, 9, 10, 12, 14, 16, 18, 20, 24.
**Backdrop:** `blur(22px) saturate(180%)` on primary glass, `blur(16px)` on secondary.

## Assets

No new assets. Every icon is an inline Lucide `<svg>` already present in the repo:
`headset`, `phone` (from the `oncall-admin` pill in `shared/auth.js`), `search`, `pencil`,
`plus`, `file-text`, `palm-tree`, `x`, `chevron-left`, `chevron-right`, `grip`, `users`,
`shield`, `refresh-cw`. No icon font, no CDN, no emoji. If a new icon is needed, copy the
Lucide path inline in the same style.

The Microsoft four-square logo in the topbar is unchanged and comes from
`ITTools.ui.renderTopbar`.

Every name, phone number, and week assignment in the prototypes is real data read from
`tools/on-call/data.json`, including the "David" rows and the empty `timeOff`/`notes`
fields. Nothing was invented.

## Files

In this bundle:

- `screenshots/1a-now-panel-year-board.png` — **the approved layout**, 1440x819 at 2x.
- `screenshots/1b-quarter-calendar.png` — reference only.
- `screenshots/1c-handoff-conveyor.png` — reference only.
- `screenshots/00-current-tool-today.png` — the tool as it ships today, for before/after.
  Captured at the preview's full width, so the page's `max-width: 1440px` content column
  sits centered with empty margins either side.
- `support.js` — runtime needed to open the two `.dc.html` files locally. Keep it beside
  them.
- `On-Call Rotation Mockups.dc.html` — the three explored layouts. **Layout 1a is the
  approved one**; open the file and jump to the `#1a` anchor. 1b (quarter calendar) and 1c
  (handoff conveyor) are kept for reference only.
- `On-Call Rotation (current).dc.html` — a faithful recreation of the tool as it ships
  today, for before/after comparison.
- `data.json` — the schedule/roster data the prototypes were built from, copied from
  `tools/on-call/data.json`.
- `styles.css` — the shared token sheet, copied from `shared/styles.css`, so the token
  names in this README resolve without the repo open.

In the target repo, the work lands in:

- `tools/on-call/index.html` — the page `<style>` block and the `render*()` functions.
- No changes needed to `shared/styles.css`, `shared/auth.js`, `config.json`, or the
  Function App.
