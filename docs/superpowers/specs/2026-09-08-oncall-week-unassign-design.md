# On-Call Rotation: Unassigned Weeks Design Spec

**Status:** approved 2026-09-08. Follows the roster delete and lock work in
`2026-09-04-oncall-roster-delete-lock-design.md`.

## Overview

There is currently no way to clear a week's assignment. `openWeekPanel`'s tech `<select>` is
populated only from `rotationTechs`, so every week in `schedule` always names somebody. When a
tech cannot take their week and nobody has picked it up yet, the tool has no way to say so.

This adds an **unassigned** state for a schedule week, surfaced as a coverage gap.

## What this is not

This started as "add a way to delete a schedule week." That framing was rejected during the
brainstorm. Josh: *"I don't want to get rid of a week or space of time where someone isn't
assigned but merely keep it highlighted that another tech needs to take that week's time."*

A week is a period of time. Time does not stop existing because nobody signed up for it, and
the 12x5 board is built on the assumption that a year's weeks are structurally complete. So
**no schedule row is ever removed.** There is no hard delete in this spec, and the following
are deliberately out of scope:

- Removing a row from `schedule` for any reason.
- Undo or restore for a week. It is not needed: the row keeps its `startDate`, `timeOff` and
  `notes`, so reassigning someone *is* the undo. Nothing is lost to restore.
- Any `formerMembers` or archived-person concept (see "David's weeks" below).
- Sub-week or day-level coverage. That is the next brainstorm, tracked separately.

## 1. Data model

No schema change. Unassigning sets `tech` to the empty string on the existing row:

```json
{ "startDate": "2026-09-06", "tech": "", "timeOff": "", "notes": "" }
```

Because the row survives:

- Year tabs cannot disappear. `getScheduleYears()` derives tabs from row dates.
- `computeYearSundays` / `getNextGapYear` gap detection is unaffected. The date is still present.
- The board never re-packs. Sparse-year left-packing, which Josh confirmed he wants to keep
  ("that history is good reference"), stays exactly as it is.

Add one predicate so the concept has a single definition rather than six inline checks:

```js
function isUnassigned(row) { return !row.tech || !row.tech.trim(); }
```

Every site below tests `isUnassigned(row)`, never `row.tech === ""` directly.

## 2. The control

The week panel's existing `On-Call Tech` select gains a first option with `value=""` and the
label `Unassigned`. That is the entire mechanism. `saveWeekPanel` already does
`Object.assign(row, st.draft)` and needs no change.

**No confirm dialog.** It is one click to reverse and destroys nothing. This is deliberately
unlike roster delete, which needed a `confirm()` because it removes a person from the roster.

## 3. Render surfaces

Six sites read `row.tech`. All six need an explicit unassigned branch. None of them crash
today (`initials("")` returns `""` and `personColorFor("")` already falls back to
`OTHER_CONTACT_COLOR`), which is precisely the problem: an unassigned week degrades into a
*blank person* rather than a visible gap.

### 3.1 Board cell (`weekCellHtml`)

Reuses the existing `.wk.unmatched` treatment: `--surface2` fill, dashed `--muted2` border,
`--muted` text. Josh confirmed sharing the visual with departed-tech cells is fine.

- Keeps its real date, since the row still has one.
- In place of initials, a genuine Lucide **`user-x`** inline SVG. Not a unicode dash: a glyph
  standing in for a state is an icon, and hub icons are always real Lucide SVGs.
- `title="Unassigned"`.
- **Excluded from drag as both source and target.** `canSwap` already requires a matched tech,
  so this falls out of the existing rule with no new condition. Rationale: a swap onto an
  unassigned cell does not fill the gap, it moves the gap onto a week that was covered. One
  consistent rule for every dashed cell, and no stray drag can uncover a covered week.
  Assignment happens through the panel.

### 3.2 Now card (`renderNowCard`)

A new branch when `isUnassigned(week)`, distinct from the existing `if (!week)` early return.
Those two states say different things and both stay:

| Condition | Meaning | Card |
|---|---|---|
| `!week` | No row exists for today at all | Existing "No current on-call week found." |
| `isUnassigned(week)` | A row exists, nobody is on it | New amber card below |

The amber card:

- `--tech-color` set to `var(--amber)`. `.now-card` already derives its background and border
  from `color-mix` against that variable, so this recolors the whole card with no new CSS.
- Eyebrow reads `No coverage` with a Lucide `triangle-alert`, replacing the `headset` icon.
- Avatar circle is amber, holding a `triangle-alert` rather than initials.
- Name line reads `Unassigned`; the week range and week ordinal subtitle are unchanged.
- All seven day pips render hollow (transparent, dashed amber border). No day is covered.
- Handoff line reframed to `Coverage resumes with <strong>NAME</strong>, DAY MON ORDINAL`.
  The countdown value and its 60s interval are unchanged.
- No phone rows and **no `coverageNote`** call. "No numbers on file." implies a person exists
  who cannot be reached, which is the wrong message.
- **No fallback-number or "call the wider team" line.** The tool is internal to the team, and
  leads and managers already know the escalation path.
- Admin **and** Edit Mode only: an `Assign this week` button that opens the existing week
  panel for that `startDate`. Non-admins see the card without it.

### 3.3 Handoff line, when the *next* week is unassigned

Independent of 3.2 and easy to miss: `renderNowCard` builds the handoff from `nextWeekAfter`,
so an unassigned next week currently renders `Hands off to <strong></strong>, Sunday Sep 13th`.
It becomes `No one assigned for DAY MON ORDINAL`, with the countdown retained.

### 3.4 Queue (`renderQueue`)

Grey `OTHER_CONTACT_COLOR` dot, and the name renders `Unassigned` in `--muted`. The `next up`
badge and the `in Nd` relative labels are unchanged. The row stays clickable, since clicking
it to assign someone is the natural action.

### 3.5 Split `unmatchedTechs`, then the two derived cards

`unmatchedTechs(year)` currently buckets by `r.tech`, so unassigned rows would group under an
empty-string key and render `3 weeks assigned to <strong></strong>`. Its return value gains a
separate channel:

```js
{ past: {...}, upcoming: {...}, unassignedPast: [...], unassignedUpcoming: [...] }
```

`past` and `upcoming` keep their existing shape (keyed by name) and now exclude unassigned
rows. The two new keys are flat arrays of `startDate`. The past/upcoming split uses the
existing `daysFromToday(r.startDate) > 0` test, unchanged, so it matches the queue and the
board's next-week ring.

**Needs attention** (`renderAttention`), amber, from `unassignedUpcoming`:

> `N upcoming week(s) is/are unassigned. Assign it/them. Sep 6, Sep 13.`

Appended as its own item after the existing departed-tech items, not merged with them.

**Roster notes** (`renderRosterNotes`), grey, from `unassignedPast`:

> `N week(s) in YEAR was/were never assigned. Sep 6, Sep 13.`

Both use the existing `.oc-note-item warn` / `.oc-note-item info` styling and `ICON_FILE_TEXT`.
Singular and plural wording follows the pattern already in both functions.

## 4. Two pre-existing hazards this makes reachable

`addContact('rotation')` creates `{ name: "New Person", shortName: "", phones: [] }`. Abandon
that mid-edit and `rotationTechs` holds a tech with a blank `shortName`. Today nothing produces
`tech: ""`, so neither hazard below can fire. This feature is what arms them, so both are
in scope here.

1. **`unmatchedTechs` builds `known` from every `shortName`, blanks included.** With a blank in
   the set, `known.has("")` is true, so every unassigned week is treated as *matched* and
   **silently disappears from Needs attention.** A real coverage gap would stop being reported.
2. **`weekCellHtml` does `rotationTechs.find(t => t.shortName === row.tech)`.** That matches the
   same blank tech, so an unassigned week would render as a **fully colored cell labelled
   "New Person"**, indistinguishable from real coverage.

Both are fixed the same way: the tech lookup and the `known` set must ignore entries whose
`shortName` is missing or whitespace. `buildPersonColors` already does exactly this and
documents why, so this matches existing precedent in the file.

## 5. Build Mode

`generateProposal` keys `existingByDate` off every row in `schedule` and marks matches
`existing: true`, which renders them dimmed and non-interactive in the Build Canvas. An
unassigned row would therefore be inherited as a permanent hole in a newly generated year,
un-fixable from the canvas.

Unassigned rows must count as **fillable**: `generateProposal` treats a date whose existing row
`isUnassigned` as if no row were present, so the proposal assigns the next tech in sequence and
the block stays draggable and editable. `commitBuild` already writes proposed rows into
`schedule`; it must overwrite the existing unassigned row for that date rather than appending a
duplicate row with the same `startDate`.

No other part of Build Mode changes. `getNextGapYear` is untouched: an unassigned row's date is
still present, so it is correctly not counted as a gap.

## 6. Verification

No test framework exists in this repo, so each task is verified with Playwright against real
data: DOM and state assertions, light **and** dark screenshots, and real click-throughs, with
zero console errors.

Specific checks beyond the per-task ones:

- **Nothing is ever removed.** `st.data.schedule.length` is 147 before and after unassigning,
  and the target row still holds its `startDate`, `timeOff` and `notes`.
- **The amber now card**, by unassigning the live current week (`2026-09-06`), screenshotted in
  both themes. Then reassign and confirm the card returns to the tech-tinted version.
- **The `!week` state still differs from the unassigned state**, since both are empty-ish and
  regressing one into the other would be easy.
- **Card routing by date**: unassign one upcoming and one past week in 2026 and confirm they
  land in Needs attention and Roster notes respectively, with correct singular/plural copy and
  no empty `<strong></strong>`.
- **Blank-shortName hazard**: add a tech, leave `shortName` empty, then confirm an unassigned
  week still renders dashed and still appears in Needs attention.
- **Board drag**: an unassigned cell has no `draggable` attribute, and dropping a tech onto one
  is a no-op.
- **Build Mode**: unassign a week in a year, generate the next year, and confirm the proposal is
  complete with no inherited holes and no duplicate `startDate` rows after commit.

The 52-week NOW-tag collision sweep does **not** need re-running: this changes no type size and
no row gap.

## 7. Out of scope, confirmed

- **David's weeks stay exactly as they are.** His 22 rows (2024-01-21 to 2026-04-26) name a
  person who exists nowhere in `rotationTechs` or `otherContacts`, so there is no profile to
  annotate. Josh's call: *"come next year he'll be gone from the 52 week display so it's a
  non-issue."* His three 2026 rows are already past weeks and already sit quietly in grey
  Roster notes. No `formerMembers` array, no departure note, no per-row annotation.
- Deleting a schedule row.
- Day-level or partial-week coverage.
- Any backend change. `ONCALL_GET_URL` / `ONCALL_SAVE_URL` remain blank pending the storage
  RBAC grant, and this feature works identically in local `data.json` fallback mode.
- No `changelog.json` entry. Per convention, entries describe changes to something already
  live, and On-Call has not shipped to real users yet.
