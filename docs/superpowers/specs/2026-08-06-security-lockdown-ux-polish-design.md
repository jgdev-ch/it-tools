# Account Lockdown — Layout Width, Search UX Fix, Status Badges, Progress Bar

**Date:** 2026-08-06
**Status:** Approved

## Problem

After the first live end-to-end test passed (all four Graph actions confirmed working against a real test account — see `2026-08-05-security-lockdown-polish-design.md` and its follow-up commits), Josh reviewed the tool again and found it functionally solid but visually cramped, plus two real UX quirks in the search-and-add flow:

1. The wizard's tables (queue, review, results) feel tight — a name like "Josh Test Account" wraps to two lines while there's unused whitespace elsewhere on the page.
2. Clicking "Add" on a search result clears the entire results list, forcing a re-search to add a second match from the same query.
3. A large result set has no height cap, so it grows the page and pushes the queue table / Continue button down unpredictably.
4. Status badges (success/failed/pending) are text-only — no icon to reinforce state at a glance.
5. While a lockdown is executing, there's no queue-wide progress signal — only per-row static "running" pills that look identical to "pending."

## Decision

### 1. Layout width

`.shell` max-width changes from `1000px` to `1300px`, matching the hub's own landing-page shell (`.hub-shell`) exactly — this also means the tool's outer edges align with the hub when navigating back and forth. `.wizard-layout`'s gap (24px) and `.lockdown-sidebar`'s width (220px) are unchanged; all the extra width goes to `.wizard-main`, where the queue/review/results tables live.

### 2. Search-and-add fix

Three behavior changes to `doSearch()` / `addCandidateFromJson()` in `tools/security-lockdown/index.html`:

- **Adding a candidate removes only that row** from the results list, instead of clearing the whole list. The remaining matches stay visible so multiple people from one search can be added without re-searching.
- **The search input is left untouched on add** (not cleared) — since the list is still showing results for that exact text, clearing the input while the list is still open would be inconsistent.
- **A "Clear" text link** appears above the results list (styled like the existing `.queue-remove` text-button pattern — text-only, no icon, matching that established row-action style) that empties the results list and the search input in one click, letting a tech start a fresh search without waiting for one to auto-replace it.
- **If the list becomes empty** (every match added, or a new search returns nothing), the results container collapses to nothing — visually identical to the pre-search state, not an empty box with a border.

### 3. Fixed-height scrolling results list

The results container (`#searchResults`) gets a `max-height` capped at 6 visible rows with `overflow-y: auto`, plus a border/background so the scroll boundary reads clearly. A 7th+ match scrolls inside that box instead of growing the page and pushing the queue table / Continue button down.

### 4. Status badges — icon + text

Extends the existing `.action-status` pill (unchanged size/shape) by adding a small Lucide icon before the text, **only for terminal states**:
- `success`: Lucide `check` icon (reusing the same icon already added for the sidebar in the previous polish pass — see `SIDEBAR_ICONS.success`).
- `failed`: Lucide `x` icon (same source as `SIDEBAR_ICONS.failed`).
- `pending` and `running` stay **text-only, no icon** — deliberately, since there's nothing to confirm yet in those states. Only confirmed outcomes get an icon; this keeps the icon meaningful rather than decorative on every state.

### 5. Overall progress bar (replaces per-row spinner idea — not building both)

A single progress bar + label appears between the "Results" `<h2>` and the results table, visible only while the lockdown is actively running:

```
Locking down 3 of 5 accounts…
[███████████████░░░░░░░░░]
```

- Tracks **accounts fully completed** (all four actions reached a terminal state for that account) out of the total queue length — same "fully done" calculation already used by `renderSidebarProgress()`'s tally and `renderResults()`'s `allAccountsDone` check, just surfaced as a fraction instead of only gating the CSV button.
- Fill color is the same amber (`#e2a13d`) used everywhere else in this tool's signal language.
- **Disappears once every account reaches a terminal state** — there's no reason to keep a "3 of 5" bar on screen once the table below it already shows the final outcome for all 5. This reuses the same `allAccountsDone` boolean that already disables/enables the CSV export button, so the bar and the button appear/disappear in sync.
- A per-row spinner (the alternative discussed and not chosen) is explicitly out of scope for this pass — the overall bar is the only progress signal being added.

## Implementation Notes

- All new/changed logic lives in `tools/security-lockdown/index.html` — no other files touched.
- The search-and-add changes only affect `doSearch()`'s rendered markup and `addCandidateFromJson()` — `addToQueue()`/`removeFromQueue()`/`renderQueue()` are unaffected.
- The progress bar reads `st.results`, exactly like `renderSidebarProgress()` and `renderResults()` already do — no new state object, one more render function (`renderProgressBar()` or folded into an existing render call) driven by the same data.
- Icons reused from the existing `SIDEBAR_ICONS` constant (added in the previous polish pass) rather than redefining the same check/x SVGs a second time — `SIDEBAR_ICONS.success` / `SIDEBAR_ICONS.failed` get referenced directly from `statusBadge()`.

## Testing

Same convention as every prior task in this codebase: Node syntax-check of the inline `<script>` block. The search-and-add list behavior, scroll cap, and progress bar are all DOM-driven and get verified visually in the browser (folded into the still-open items from the original Task 15 checklist — CSV/retry/gate/visual-check — rather than a separate pass).

## Out of Scope

- Per-row spinners during execution (discussed, explicitly not chosen — the overall bar is the only progress signal).
- Any change to the four Graph actions themselves, retry logic, or CSV export — this pass is layout/UX/visual only.
- Any change to the Review & Confirm step's table or the sidebar beyond what's already shipped.
