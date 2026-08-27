# Hub Recent Updates — Changelog Panel + Glass Scrollbars

**Date:** 2026-08-27
**Status:** Approved

## Problem

The hub's only version tracking today is a single semver string hardcoded in `index.html`'s footer (`v2.3.2`), bumped ad hoc whenever Josh judges a change notable enough. That bump is invisible to anyone else using the hub, and there's no record anywhere of *what* changed at each version — just git history, which isn't something a non-technical hub user would ever dig through. Two real fixes shipped today (User Creation's numeric-UPN validation + chevron/theme-color polish, and the Account Lockdown UX polish pass already on preview) prompted the ask: when someone asks "did you fix the thing I mentioned," there should be a visible place to check, without turning it into a process that has to be maintained separately from the existing version-bump habit.

Separately, once a dropdown panel with a scrollable list entered the picture, the hub's total lack of custom scrollbar styling (page-level and inside any panel) stood out as visually inconsistent with the rest of the Glass Control Center design language.

## Decision

### 1. `changelog.json` — new data file, same convention as `config.json`/`downloads.json`

A flat array of version-bump entries at the repo root:

```json
{
  "entries": [
    {
      "version": "2.3.3",
      "date": "2026-08-27",
      "notes": [
        "User Creation: numeric UPN support, chevron/theme-color polish",
        "Account Lockdown: wizard width, search fix, progress bar"
      ]
    },
    {
      "version": "2.3.2",
      "date": "2026-08-07",
      "notes": ["Account Lockdown: UX polish pass"]
    }
  ]
}
```

Entries are hand-written, one per version bump — same judgment call Josh already makes about whether a change is "worth" bumping the footer version, just with one more file touched in the same commit. No auto-generation from commit messages: commit history is noisy (internal refactors, typo fixes, doc commits) and not written for a non-technical reader. `index.html` fetches this file client-side exactly like `config.json` and `downloads.json` already are.

### 2. Trigger: a header icon button, not an inline page section

Originally scoped as a collapsible section inline in the page flow (below the title bar, above the tool grid). Revised after seeing it live: an inline section — even collapsed — still occupies permanent space and needs its own visual weight next to the "Daily Operations" / "Reporting & Audit" category headers. Moved instead to a **topbar icon button** that opens a floating panel, reusing the exact pattern already established by the Scripts & Downloads button (`#downloadsBtn` / `.downloads-panel` in `index.html`):

- Button sits in `.hub-topbar-right`, between the theme toggle and the Downloads button.
- Icon: Lucide **`megaphone`** (chosen after comparing `history`, `clock`, `sparkles`, `bell`, `scroll-text`, `rss`, `refresh-cw`, and `calendar-clock` side by side).
- `title`/`aria-label`: "Recent Updates".

### 3. Panel: fixed size, internally scrollable, never touches the card grid

New `.changelog-panel` — same `position: absolute; right: 0; top: calc(100% + 8px)` floating pattern as `.downloads-panel`, but with an explicit fixed footprint rather than `.downloads-panel`'s max-height-only sizing:

- `width: 380px; height: 420px; max-width: calc(100vw - 32px)`
- `display: flex; flex-direction: column` — header stays pinned, list area is the only part that scrolls (`flex: 1; overflow-y: auto`)
- Because it's `position: absolute` and floats over the page, opening/closing it or scrolling inside it **cannot** shift, resize, or reflow the tool grid or anything else on the page — confirmed visually in the mockup by forcing extra entries and watching the grid underneath stay static.

Panel header: `RECENT UPDATES` label (left) + `Last updated <date>` (right), where the date is always the `date` field of `changelog.json`'s first (most recent) entry — no separate "last updated" value to maintain.

### 4. Panel content: recent entries flat, older entries grouped by month

- Entries from the **last 30 days** render in full: version, date, and the bulleted notes for that bump.
- Entries **older than 30 days** collapse into per-month buckets (e.g. `▸ July 2026 (2 updates)`), using the hub's existing collapsible chevron pattern (`m6 9 6 6 6-6` Lucide chevron, CSS `transform: rotate(-90deg)` when collapsed) — the same mechanism as the tool-category sections on the hub landing page. Expanding a month bucket reveals the individual dated entries inside it, styled identically to the flat recent entries. This is two levels deep (recent list → month bucket → entries within), not a full year/month/day tree — not worth the extra UI for how infrequently the version actually bumps.
- Grouping is computed client-side at render time from the flat `changelog.json` array (bucket by calendar month for anything past the 30-day cutoff); the JSON file itself stays a simple flat list.

### 5. Hub-wide glass-styled scrollbars

Applies to **every** scrollable area across the hub and all tools (not just the changelog panel), added once in `shared/styles.css` so it's automatically inherited everywhere:

```css
:root            { --scroll-thumb: rgba(0,0,0,.16);   --scroll-thumb-hover: rgba(0,0,0,.30); }
[data-theme="dark"] { --scroll-thumb: rgba(255,255,255,.18); --scroll-thumb-hover: rgba(255,255,255,.32); }

::-webkit-scrollbar       { width: 10px; height: 10px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb {
  background: var(--scroll-thumb);
  border: 2px solid transparent;
  background-clip: padding-box;
  border-radius: 20px;
}
::-webkit-scrollbar-thumb:hover { background: var(--scroll-thumb-hover); }
* { scrollbar-width: thin; scrollbar-color: var(--scroll-thumb) transparent; }
```

**`--scroll-thumb`/`--scroll-thumb-hover` are new tokens, not a reuse of `--glass-fill`/`--glass-border`.** Tried reusing the existing glass tokens first — visually confirmed in a light-theme mockup that a white-tinted thumb over a near-white panel (`--panel-fill`) is essentially invisible. The existing glass tokens are tuned for translucent surfaces layered over a blurred, varied backdrop (topbar over a gradient, panels over blurred page content); a scrollbar thumb needs to stay legible over *any* background, flat or not. New tokens use a dark tint in light theme and a light tint in dark theme instead, same inversion logic the hub already applies to other theme-swapped tokens.

Also worth noting for anyone extending this later: no browser supports `backdrop-filter` on scrollbar pseudo-elements, so this is a translucent-rounded-thumb look, not literal frosted-blur glass. That's the ceiling of what's achievable here, not an oversight.

## Implementation Notes

- New file: `changelog.json` (repo root), fetched by `index.html`.
- `index.html` changes: topbar button + `.changelog-panel` markup/CSS/JS (fetch + render + 30-day/month bucketing + toggle), following the `downloadsBtn`/`downloadsPanel`/`toggleDownloadsDropdown()` pattern already in the file.
- `shared/styles.css` changes: the two new scrollbar tokens + the global `::-webkit-scrollbar*`/`scrollbar-color` rules. This automatically styles scrollbars in every tool page too, since they all link `shared/styles.css`.
- Version-bump workflow gets one added step: whenever the footer version bumps, prepend a matching entry to `changelog.json` in the same commit. No new tooling, no CI step — same manual discipline as today's version bump, just one more file.

## Testing

Visual verification in both themes, following the same mockup-and-screenshot approach used to validate this design: panel open/closed doesn't move the tool grid, internal scroll works once content overflows the fixed 420px height, month-bucket expand/collapse works, and the scrollbar thumb is legible in both light and dark themes (specifically re-tested after the light-theme contrast issue found during design).

## Out of Scope

- Per-tool version badges/history (only the hub-wide version + changelog, not a per-tool changelog).
- Auto-generating changelog entries from git commit messages.
- Year-level grouping or deeper than a two-level (recent → month) drill-down.
- Any build/CI automation for the version bump or changelog entry — stays a manual step.
