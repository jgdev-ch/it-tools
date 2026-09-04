# On-Call Rotation: Roster Delete and Per-Person Lock Design Spec

**Status:** approved 2026-09-04. Follows the layout 1a work in
`2026-09-04-oncall-rotation-layout-1a-design.md`.

## Overview

Roster entries currently cannot be deleted. There is no `removeContact` anywhere and the
contact panel offers only Cancel and Save, so an accidental "Add tech" creates a permanent
"New Person" that can only be cleared by hand-editing the data. This adds an admin delete,
plus a per-person lock that blocks deletion of permanent staff, plus the color-stability fix
that makes deletion safe in the first place.

Applies to both `rotationTechs` and `otherContacts`, which already share one panel.

## Why pinned colors come first

Deleting a tech today recolors the survivors. `buildPersonColors` assigns palette slots by
sorted `shortName` position, so removing a name shifts everyone after it. Verified 2026-09-04
by deleting Krista: Nick went `#9333ea` purple to `#d97706` orange, and Robert inherited
Nick's purple. That breaks the color-equals-identity rule deliberately carried across the
hero card, the year board, and the tech strip.

Shipping delete without this would scramble the board on every departure, so pinned colors
are a prerequisite, not a nice-to-have.

## 1. Pinned colors

Add an optional `color` field to each entry in `rotationTechs`:

```json
{ "name": "Nick Zoshak", "shortName": "Nick", "color": "#9333ea", "phones": [ ... ] }
```

`buildPersonColors` becomes read-then-backfill:

1. Any tech with a non-empty `color` keeps it verbatim.
2. Techs without one are assigned in **sorted `shortName` order**, taking the first
   `PERSON_PALETTE` entry not already claimed, and the chosen value is **written back onto
   the tech object** so it persists on the next save. "Already claimed" means held by any
   entry in `rotationTechs`, counting both pre-existing `color` values and ones assigned
   earlier in the same backfill pass.
3. Blank `shortName` entries continue to be skipped entirely (see the layout 1a spec).

**The write-back in step 2 is load-bearing, not an optimization.** It is what makes deletion
safe before the first save has ever happened: because every tech holds a concrete `color` in
memory immediately after load, a post-delete rebuild takes the step-1 path for every survivor
and cannot reshuffle them. If the backfill computed colors without mutating `st.data`, a
delete on a freshly loaded page would recompute from sorted order minus the removed name and
shift everyone, which is the exact bug this section exists to prevent.

Step 2's ordering matters: with no pre-existing colors, sorted-order-plus-first-unused
reproduces today's assignment exactly, so **nothing changes visually on the day this ships**.
Once a tech has a color, later roster changes cannot move it.

A newly added tech gets the first palette entry no current tech holds, so it does not collide
with a colleague.

`otherContacts` get no `color` field. They are uniformly `OTHER_CONTACT_COLOR` grey.

`personColorFor(shortName)` is unchanged: map lookup with the grey fallback.

**Known limitation:** `PERSON_PALETTE` has 7 entries. An eighth simultaneous rotation tech
reuses a color. Acceptable at a team size of 5, and no worse than today's behavior.

**Persistence timing:** the backfill mutates `st.data` in memory and is written whenever
`saveChanges` next runs. Until then each load recomputes the same deterministic values, so
there is no visible difference either way.

## 2. Lock

A `locked: true` flag on any rotation tech or other contact. It blocks **deletion only**.
Renaming, phone edits, drag-to-reorder, board drag-to-swap, and the In Rotation toggle all
remain available on a locked person.

- **Panel control:** a "Protected" toggle row styled exactly like the existing "In Rotation"
  row, admin + edit mode only. The visible label is "Protected"; the underlying field stays
  `locked`. Do not rename the field to match the label.

  **Prerequisite discovered 2026-09-04:** that "In Rotation" row is currently **broken**.
  `.tog` and `.track` have no CSS anywhere in the repo, so the row renders as a raw native OS
  checkbox beside a 13x0px invisible div, verified in the browser. It was almost certainly
  orphaned when the Edit Mode checkbox+track switch was replaced by a pencil button on
  2026-09-03. Since this spec says to copy that row's styling, the switch CSS has to be
  restored first, or the new toggle inherits the same broken rendering. It is also the only
  unstyled control left in the tool, and a raw checkbox is exactly what was removed from the
  toolbar. Restoring it is the first implementation task.
- **At-a-glance state:** a genuine inline Lucide `lock` icon on the tech card and on the
  also-reachable chip, rendered in **both view and edit mode**, so "this person is permanent"
  is legible without opening the panel.
- **Enforcement:** when the person is locked, the Remove button renders **disabled** with the
  hint "Unlock to remove." It is not hidden, because a hidden button reads as a missing
  feature rather than a deliberate guard.

The lock is a guard against accident, not a permission boundary. Any admin who can delete can
also unlock, which is the intent.

## 3. Delete

A red **Remove** button in the panel's existing `.panel-btnrow`, to the left of Cancel and
Save, rendered only for admins in Edit Mode.

Confirmation is a native `confirm()`, matching the `alert()` already used for Short Name
validation, and it names the person and their week count:

> Remove Krista Guthrie from the roster?
>
> Her 9 scheduled weeks in 2026 are kept as historical record.

**No cascade.** Schedule rows are never touched. Verified 2026-09-04: deleting Krista left all
147 rows intact, her 9 week cells became dashed grey unmatched cells, and the Roster notes
card picked her up automatically without any new code. Delete falls straight into the
historical-record pattern already built for David.

On confirm: splice the entry from its array, rebuild the color map (survivors keep their
pinned colors), close the panel, `renderAll()`, `saveChanges()`.

## 4. Split unmatched weeks by whether they still matter

Adding delete exposes a gap in the existing detection. `unmatchedTechs` currently lumps every
unmatched week in a year into "Roster notes" as history. That is right for David, whose weeks
are all in the past. But deleting someone with **upcoming** weeks leaves real uncovered
coverage, and the hero card would show a grey departed name with no phone number.

Route the same detection by date:

| Unmatched weeks for a person | Card | Copy |
|---|---|---|
| All in the past | Roster notes (grey, `--muted2` icon) | "N weeks in YYYY are assigned to X, who has left the rotation. Kept as historical record. <dates>." |
| One or more upcoming | **Needs attention** (amber icon) | "N upcoming week(s) are assigned to X, who is no longer in the roster. Reassign them. <dates>." |

A person with both past and upcoming unmatched weeks appears in **both** cards, each listing
only its own dates. "Upcoming" means `daysFromToday(startDate) > 0`, consistent with the queue
and the board's next-week ring.

Without this, deleting an active tech silently leaves unassigned weeks with no prompt.

## 5. Code changes

| Modified | New |
|---|---|
| CSS: restore `.tog` / `.track` (prerequisite above) | `removeContact()` — reads `st.panel`, takes no args |
| `buildPersonColors` (read-then-backfill) | `ICON_LOCK` constant (the same Lucide `lock` path the hub already uses for its locked-tile badge) |
| `renderContactPanelBody` (Protected toggle + Remove button) | CSS: `.tech-lock`, `.also-lock`, `.tech-card.has-grip`, `.btn-remove` |
| `renderTechStrip` (lock icon + `has-grip`) | |
| `renderAlsoReachable` (lock icon) | |
| `unmatchedTechs` (return `{ past, upcoming }`) | |
| `renderAttention` / `renderRosterNotes` (consume the split) | |

Two simplifications against an earlier draft of this table:

- **No `toggleDraftLock()` function.** The Protected checkbox sets `st.draft.locked` inline and
  re-renders the panel body, matching how the existing tech and phone inputs already work. The
  re-render is deliberate: it refreshes the Remove button's disabled state the instant the
  toggle flips.
- **`.btn-remove`, not `.btn-danger`.** It mirrors `.btn-secondary`'s transparent-with-colored-border
  shape using `--red` / `--red-border`, and reuses the existing `:disabled` convention from
  `.btn-primary:disabled`. No new `.btn[disabled]` rule is needed.
- **`saveContactPanel` needs no edit.** It already assigns the whole `st.draft` object into the
  array, so `locked` persists for free.

Unchanged: the backend, `shared/`, `config.json`, `data.json`'s existing shape (`color` and
`locked` are additive and optional), Build Mode, and the week panel.

## 6. Verification

No test framework exists in this repo, so verification is Playwright plus light and dark
screenshots, per the layout 1a spec. Specifically:

- Colors are byte-identical to today's on first load, before any save.
- Deleting a tech leaves every survivor's color unchanged.
- Deleting a tech preserves all 147 schedule rows and produces dashed cells.
- A locked person's Remove button is disabled; unlocking enables it.
- Lock icons appear in view mode as well as edit mode, in both themes.
- Deleting a tech with upcoming weeks produces an amber Needs attention item; David continues
  to produce only a grey Roster notes item.
- A new tech gets a palette color no current tech holds.
- Remove is absent entirely for non-admins and outside Edit Mode.

## 7. Out of scope

- Bulk delete, undo, or restore of a removed person.
- Any archive or "past members" UI.
- Reassigning the departed person's upcoming weeks automatically. The Needs attention item
  prompts it; the admin does it via the week panel or a board swap.
- Locking individual schedule weeks. The lock is per person only.
- Changing `PERSON_PALETTE` or adding an eighth color.
