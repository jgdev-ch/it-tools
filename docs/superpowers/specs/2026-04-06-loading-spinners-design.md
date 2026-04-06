# Loading Spinners — Universal Visual Feedback Design

**Date:** 2026-04-06
**Status:** Approved

## Goal

Add consistent loading/spinner feedback to every async operation across all 6 IT Tools — covering action buttons, sign-in init, and secondary lookups. The existing phase-line spinners during main scan operations are already in place and are not changed.

## Approach

Add a single new method, `ITTools.ui.withButtonSpinner()`, to the existing `ITTools.ui` module in `shared/auth.js`. No new files. Each tool's `index.html` gets small targeted call-site edits to wire in the helper.

## New API — `ITTools.ui.withButtonSpinner`

```js
await ITTools.ui.withButtonSpinner(btn, asyncFn, loadingText?, disableEls?)
```

**Parameters:**
- `btn` — the button element to show the spinner on
- `asyncFn` — async function to await; its result is returned
- `loadingText` — optional label shown during load (e.g. `"Removing…"`); defaults to `"Loading…"`
- `disableEls` — optional array of additional elements to disable during the call (e.g. a paired Cancel button or input field)

**Behaviour:**
1. Saves `btn.innerHTML` and `btn.disabled`
2. Sets `btn.disabled = true`, replaces label with spinner SVG + `loadingText`
3. Disables any extra `disableEls`
4. `await asyncFn()`
5. In `finally`: restores original label, re-enables `btn` and `disableEls`
6. Errors propagate normally — the call site handles them as before

The spinner SVG matches the existing `.spinner` animation already defined in `shared/styles.css` (14×14, `border-top-color: var(--blue)`), rendered inline so no extra CSS is needed.

## Per-Tool Wiring

### License Audit (`tools/license-audit/index.html`)
- `confirmRemoval()` — wrap the Graph `assignLicense` fetch; disable the Remove button + Cancel button during call
- `confirmManageRemoval()` — same pattern for the manage modal's confirm button
- `doSignIn()` — wrap the post-popup `Promise.all([checkFinanceAccess, checkLicenseModifyAccess, loadSkus, loadCosts])` using the sign-in button as the anchor; loading text: `"Loading your account…"`

### Finance Dashboard (`tools/finance-dashboard/index.html`)
- `doSignIn()` — wrap the post-popup `checkFinanceAccess()` + init sequence; loading text: `"Loading your account…"`

### MFA Status Report (`tools/mfa-status/index.html`)
- `doSignIn()` — wrap the post-popup init; loading text: `"Loading your account…"`

### Guest Audit (`tools/guest-audit/index.html`)
- `doSignIn()` — wrap the post-popup init; loading text: `"Loading your account…"`

### Group Import (`tools/group-import/index.html`)
- `lookupGroup()` — wrap the Graph group lookup; disable the Find button + the group name/ID input field during call; loading text: `"Finding…"`

### Name Resolver (`tools/name-resolver/index.html`)
- `doSignIn()` — wrap the post-popup init; loading text: `"Loading your account…"`
- Per-row retry button (`retryRow()`) — wrap with loading text `"Retrying…"`

## What Is Not Changing

- Phase-line spinners during main scan/run operations — already in place, untouched
- Manage Licenses modal body spinner — already injected inline via `body.innerHTML`, works well as-is
- Guest Audit CorroHealth inline cell spinners — already in place

## Files Changed

| File | Change |
|------|--------|
| `shared/auth.js` | Add `withButtonSpinner` to `ITTools.ui` module |
| `tools/license-audit/index.html` | Wire 3 call sites |
| `tools/finance-dashboard/index.html` | Wire 1 call site |
| `tools/mfa-status/index.html` | Wire 1 call site |
| `tools/guest-audit/index.html` | Wire 1 call site |
| `tools/group-import/index.html` | Wire 1 call site |
| `tools/name-resolver/index.html` | Wire 2 call sites |

**Total:** 1 new shared method + 10 small call-site edits across 6 tool files.
