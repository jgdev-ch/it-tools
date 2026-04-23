# Paste Scrubber — Design Spec
**Date:** 2026-04-23
**Tool:** Name Resolver (`tools/name-resolver/index.html`)
**Status:** Approved

## Problem

The paste tab's `handlePaste()` function only splits on newlines (or commas as a fallback). Real-world pastes from Outlook emails, Teams messages, and HR reports contain noise that breaks Graph lookups: numbered/bulleted list prefixes, `@mention` symbols, parenthetical context like `(IT)` or `[Contractor]`, honorific titles like `Dr.`, and names in Last, First format. All of this must be stripped and normalised before a name reaches the lookup engine.

## Design

### Behaviour

When the user pastes (or types) into the paste textarea:

1. A `scrubNames(lines)` function runs each non-empty line through a **named transform pipeline**.
2. Each transform returns the cleaned value and optionally a display tag if it changed anything.
3. The result is a list of `{ name, tags[] }` objects, deduplicated case-insensitively.
4. A **"Names detected" panel** renders below the textarea showing the cleaned names and any tags.
5. The existing **column mapper card is hidden** in paste mode — it is not needed since paste always produces a single synthetic `Name` column.
6. `_parsedRows` is populated from the cleaned names as before, so the rest of the resolve flow is unchanged.

### Transform Pipeline

Transforms run in order on each line. Each is a pure function: `(value: string) => { value: string, tag?: string }`.

| Order | Name | Strips | Tag shown |
|-------|------|--------|-----------|
| 1 | `stripListPrefix` | Leading `1.` `2.` `1)` `•` `*` `-` `–` `—` | none (silent) |
| 2 | `stripMentions` | Leading `@` | `@ stripped` |
| 3 | `stripTitles` | Leading `Dr.` `Mr.` `Ms.` `Mrs.` `Prof.` (case-insensitive) | `Dr. removed` (uses actual title) |
| 4 | `stripSuffixes` | `(...)` and `[...]` anywhere in the string | `(IT) removed` (uses actual text) |
| 5 | `flipLastFirst` | Line contains exactly one comma; both sides have ≥2 characters and ≥1 space-separated word; neither side looks like a suffix (`Jr`, `Sr`, `II`, `III`, `IV`) → swap to `"First Last"` | `Last, First → flipped` |
| 6 | `normalizeSpace` | Collapses multiple spaces, trims | none (silent) |

After all transforms, a final **dedup pass** removes case-insensitive duplicates silently.

Lines that are empty after transforms are discarded.

### "Names detected" Panel

Replaces the existing "Preview — first 5 names" section for paste mode. Renders below the textarea inside the source card.

**Header row:**
- Left: `✦ N names detected` (blue)
- Right: `N transformed` — count of names that had at least one tag (omitted if zero)

**Per-name row:**
- Blue dot + cleaned name
- Zero or more amber tags on the right (one per fired transform)
- No tag shown on clean names — visual noise only appears where it's informative

**Panel visibility:** Hidden when textarea is empty. Appears as soon as any name is detected.

### Column Mapper Card

Hidden (`display:none`) while paste mode is active. The synthetic `Name` column is implicit — no user decision is needed. The card re-shows if the user switches to File or Excel mode.

### Integration Points

- `handlePaste()` — replace direct `_parsedRows` assignment with `scrubNames()` call; render detected panel; skip `renderColumnMapper()`
- `setMode()` — hide/show column mapper card based on mode
- `clearInput()` — clear detected panel and hide it
- No changes to `buildNames()`, `s1Next()`, `startResolve()`, or anything downstream

## Out of Scope

- Tab-separated first/last columns in paste mode (can be added later as a `splitTabColumns` transform)
- Editable name correction in the detected panel
- Any changes to the File or Excel input modes
