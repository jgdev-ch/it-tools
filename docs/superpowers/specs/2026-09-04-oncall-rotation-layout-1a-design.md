# On-Call Rotation: Layout 1a Design Spec

**Status:** approved 2026-09-04. Supersedes the page layout established by
`2026-09-02-oncall-rotation-visual-redesign-design.md`. Build Mode
(`2026-09-03-oncall-rotation-build-mode-design.md`) is carried forward unchanged.

## Overview

A whole-page rearrangement of `tools/on-call/index.html` into a two-column layout: a
376px left rail answering "who is on call right now and what is their number", and a right
column showing the entire year as a 12x5 board of 52 week cells. Everything fits one
1440x900 screen with no scrolling.

The data model, auth, gating, and backend contract are unchanged. This is a presentation
and information-hierarchy change only.

**Pixel-level authority:** `docs/superpowers/assets/2026-09-04-oncall-rotation-design-mockup/README.md`
plus `screenshots/1a-now-panel-year-board.png` (the approved layout). That bundle is a
design reference authored in standalone HTML; its inline styles are NOT carried across.
This spec records structure, behavior, and the decisions that deviate from it.

**Verified against live data 2026-09-04:** every figure in the mockup is real. Phone counts
(Joshua 4, Nick 1, Joe 2, Robert 2, Krista 3), 2026 week counts (10/10/10/10/9), the
4-week queue, and zero `timeOff`/`notes` across all 147 rows.

## Page Structure

`main.main-content` becomes `display: grid; grid-template-columns: 376px 1fr; gap: 16px`,
padding `20px 24px 24px`, max-width 1440px.

The `<h1>On-Call Rotation</h1>` and the `.admin-toolbar` strip are both deleted. The topbar
already names the tool and admin controls move into the right column toolbar. This is
where the reclaimed vertical space comes from.

```
main-content
├─ aside.oc-rail
│   ├─ #nowCard           (tech-tinted, replaces .hero)
│   ├─ #queueCard         (next 4 weeks)
│   ├─ #attentionCard     (derived, actionable; hidden when empty)
│   └─ #rosterNotesCard   (derived, neutral; hidden when empty)
└─ section.oc-main
    ├─ .oc-toolbar
    ├─ #yearBoard
    ├─ #buildSetupBar         (unchanged, relocated)
    ├─ #buildCanvasSection    (unchanged, relocated)
    ├─ #techStrip
    └─ #alsoReachable
```

`#detailPanel`, `#panelBackdrop`, `#authScreen`, and `#deniedScreen` are untouched.

## Left Rail

**Now card.** Tinted `color-mix(in srgb, var(--tech-color) 20%, var(--glass-fill))`, so it
recolors every Sunday and adapts to both themes without an override. This is the same
formula already blessed on the hero. `--tech-color` is not a global token: it is set as an
inline custom property on the card element from `personColorFor(week.tech)`, the same way
avatar colors are already applied. Contents: 60px avatar, name at 26/800, sub-line of
`weekRangeLabel(startDate)` plus `week N`, seven day-pips, a handoff line with a live
countdown at 22/800, one row per phone with a Copy button, and a coverage note rendered
only when a channel is actually missing.

`week N` is the row's **ordinal position within the selected year's sorted schedule rows**
(index + 1), not an ISO week number. For 2026-08-30 both happen to be 35; ordinal position
is the intended meaning and needs no new date helper.

The countdown recomputes to the next Sunday 00:00 local on a 60s interval, showing
`Nd HHh` with no seconds. The interval handle is module-level and `renderNowCard` must
`clearInterval` any existing handle before starting a new one, so repeated renders (year
switches, saves, panel closes) cannot stack duplicate timers.

**Queue card.** The next four weeks in date order: color dot, name, date. Row one gets a
green "next up" pill; rows two through four get relative labels (`in 10d`). Rows open the
existing week panel.

**Needs attention.** Derived from data, never authored. Actionable items only. Hidden
entirely when nothing is detected rather than showing an empty state. Today it holds one
item: no `timeOff` recorded anywhere in the selected year.

**Roster notes.** New card, same glass treatment, quieter styling, no warning icon. Holds
derived facts that are true but deliberately not actionable. Today it holds the unmatched
tech case:

> 3 weeks in 2026 are assigned to David, who has left the rotation. Kept as historical
> record.

Detection is fully general: any `schedule[].tech` with no matching
`rotationTechs[].shortName`. It lands in notes rather than in Needs attention because
David's 22 rows (2024-01-21 through 2026-04-26, three of them in 2026) are a deliberate
keep per the original spec's historical-record reasoning. Filing it as a warning would
create a permanent nag that can only be cleared by reversing that decision. A future
departure surfaces here automatically.

## Right Column

**Toolbar.** Year segment (dynamic, from `getScheduleYears()`), a `52 weeks · 5 techs`
count, then Find a person, Edit (admin only, replaces the whole `.admin-toolbar`), and
Build [Year] (admin only, gated by the existing `getNextGapYear()`). Prev / Today / Next
are deleted: with the full year visible there is nothing to page through.

**Year board.** `grid-template-columns: 34px repeat(5, 1fr)`, twelve rows, 38px cells. The
first cell of each row is the month label; the month containing today renders in `--text`
instead of `--muted2`. Months with only four Sundays get one empty spacer div so columns
never reflow.

- Week cell: tech color background, day number at 10px/.75 opacity, initials at 11/800.
  Click opens the existing week panel. Hover lifts 1px.
- Today: 2px `var(--text)` ring plus a floating NOW tag.
- Next week: a lighter 1.5px ring, no tag.
- Unmatched tech: `--surface2` background with a **dashed** border, which pairs visually
  with the roster-notes entry.
- `timeOff` / `notes` keep the existing palm-tree / file-text badges.

**Tech strip.** Five cards, one per rotation tech in `rotationTechs` order, with
`border-left: 3px solid <tech color>` as the only color carrier. Three lines: name;
`10 weeks · next Sep 13` (or `on call now`); `4 numbers on file`, colored `--amber` when
the count is 1. Clicking opens the existing contact panel.

Phone-type chips are deliberately not repeated here. The count is enough because the
detail panel carries the numbers and the now card already shows full numbers for whoever
is currently on call. This density is what buys the whole year on one screen.

**Also reachable.** One line: label plus an avatar+name chip per `otherContacts` entry,
and a dashed `+` chip in edit mode bound to `addContact('other')`. This replaces the second
172px card grid and resolves the visual-redesign spec's open question about de-emphasizing
Other Contacts. The answer is a different component, not a dimmed copy of the same one.

### Capabilities carried over from the roster grid

The design brief omits two admin affordances that exist today on `.roster-card` and would
otherwise be silently lost when the tech strip replaces it. Both are additions to the
brief, not deviations from it.

- **Add to rotation.** `renderRoster` currently renders two add-tiles in edit mode:
  `addContact('rotation')` and `addContact('other')`. The brief only provides the `+` chip
  for other contacts. The tech strip therefore gains a dashed `+` card, appended in edit
  mode only, bound to `addContact('rotation')`, so onboarding a new tech stays possible.
  It wraps to a second grid row, which is acceptable because it appears only in edit mode.
- **Drag-to-reorder.** `rosterDragStart` / `rosterDragOver` / `rosterDrop` /
  `rosterDragEnd` define the `rotationTechs` order that Build Mode cycles through. They are
  transplanted onto the tech strip cards unchanged, with the `ICON_GRIP` handle shown in
  edit mode only. Losing this would make rotation order uneditable and break the premise of
  Build Mode's generation logic.

## Find a Person

Selecting a tech highlights their cells across the board and drops all others to
`opacity: .35`. Selecting again, or Escape, clears it. State is a new nullable
`st.highlightTech`.

**Deviation from the design brief:** the brief specs pure highlight with no navigation.
That would silently drop the jump-to-next-upcoming behavior added 2026-09-03. So if the
selected tech has no cells in the currently viewed year, also switch to the year holding
their next upcoming shift (falling back to their most recent past shift). This preserves
the earlier intent inside the new model.

## Dark Mode

Designed deliberately and verified, not inferred. The design brief was authored in light
mode only and hardcodes values with no dark equivalent. Two tokens are added to
`shared/styles.css` in both `:root` and `[data-theme="dark"]` (additive only, so no
existing tool changes behavior):

| Token | Light | Dark |
|---|---|---|
| `--text-secondary` | `#4a4a52` | `#c8cad2` |
| `--glass-raise` | `rgba(255,255,255,.60)` | `rgba(255,255,255,.08)` |
| `--glass-raise-border` | `rgba(255,255,255,.70)` | `rgba(255,255,255,.14)` |

The new CSS contains **zero hardcoded colors**. Mapping of the brief's literals:

- Nested surfaces (phone block, year segment wrapper, avatar ring) use `--glass-raise`,
  tuned in dark to read as raised above dark glass rather than washing out the way a .6
  white would.
- The "also reachable" bar uses the existing `--glass-fill` / `--glass-border`.
- Hairline row dividers use the existing `--border`.
- Today's ring and the NOW tag use `var(--text)`, which correctly inverts to a light
  marker on dark.
- Week-cell text stays `#fff` in both themes: cells are saturated tech colors in both, so
  white is correct regardless.
- The tinted now card and colored cells carry their own color and need no override.

## Build Mode

Carried forward unchanged. No edits to `generateProposal`, `buildBlockHtml`, drag-to-swap,
the inline popover, or `commitBuild`. The roster drag-to-reorder handlers are also
unmodified, but are re-bound to the tech strip cards since `.roster-card` no longer exists
(see "Capabilities carried over from the roster grid").

`setBuildViewVisibility` is repointed at the new IDs: entering build hides `#yearBoard`,
`#techStrip`, and `#alsoReachable`, and shows the setup bar or canvas by phase. **The left
rail stays visible during build**, mirroring how the hero stays visible today.

## Code Changes

| Deleted | Rewritten | New |
|---|---|---|
| `st.stripStart`, `WEEKS_VISIBLE` | `renderHero` to `renderNowCard` | `renderQueue`, `renderAttention`, `renderRosterNotes`, `renderToolbar` |
| `shiftStrip`, `goToday`, `jumpToWeek` | `renderCalendarStrip` to `renderYearBoard` | `renderFindPanel`, `highlightPerson`, `clearHighlight`, `copyNumber` |
| `renderMonthPills`, `jumpToMonth` | `tileHtml` to `weekCellHtml` | `st.highlightTech`, `countdownTimer` handle |
| `monthLabelsHtml` | `renderRoster` splits into `renderTechStrip` + `renderAlsoReachable` | Helpers: `sortedByDate`, `weekOrdinalInYear`, `unmatchedTechs`, `shortDate`, `daysFromToday`, `nextWeekAfter`, `msToNextSunday`, `countdownLabel`, `coverageNote` |
| `renderPersonJumpPanel`, `togglePersonJump`, `jumpToPersonDate` (replaced by the find-panel trio) | | |
| Icon consts `ICON_CHEVRON_LEFT`, `ICON_CHEVRON_RIGHT`, `ICON_USERS`, `ICON_SHIELD`, `ICON_REFRESH_CW` (each unused once their only host element is deleted) | | |

`renderAll()` becomes: `renderNowCard`, `renderQueue`, `renderAttention`,
`renderRosterNotes`, `renderYearSeg`, `renderToolbar`, `renderYearBoard`,
`renderTechStrip`, `renderAlsoReachable`, `renderBuildTrigger`.

`renderYearSeg` is preserved as-is for the year pills; `renderToolbar` separately owns the
week/tech count and the admin button visibility that previously lived in `toggleEditMode`
and `afterSignIn`. `MONTH_NAMES` must survive the deletion of the calendar-strip block that
currently surrounds it, since the year board depends on it.

Preserved as-is: `findCurrentWeek`, `weekRangeLabel`, `ordinal`, `initials`,
`buildPersonColors`, `personColorFor`, `getYearWeeks`, `getScheduleYears`, `setYear`,
`computeYearSundays`, `getNextGapYear`, `openWeekPanel`, `openContactPanel`, all panel
rendering, `saveChanges`, and the whole auth and gating path.

## Sequencing

Structural tasks are built and verified locally, then pushed to `origin/testing` as one
coherent unit. The layout is interdependent (the rail cannot exist while the hero does,
and the board replaces the strip and month pills together), so per-task pushes would leave
preview visibly half-migrated. Polish after that first push follows the usual rhythm: one
push per item, deploy-confirmed individually.

## Verification

Per task: Playwright load, zero console errors, and a screenshot in **both** light and
dark. Interactive pieces get a real click-through: week cell to panel, queue row to panel,
Copy to clipboard, Find a person highlight and year switch, Edit toggle state, and Build
Mode still reaching its canvas.

## Out of Scope

- Responsive or mobile work. The hub is desktop-only by standing decision.
- A page-level lock. The coming-soon gate still only hides the hub card.
- A changelog entry. Nothing user-facing has shipped yet.
- Wiring `ONCALL_GET_URL` / `ONCALL_SAVE_URL`. Still blocked on the storage RBAC grant.
- Backend, `shared/auth.js`, `config.json`, and Function App changes.
- Layouts 1b (quarter calendar) and 1c (handoff conveyor). Reference only.
