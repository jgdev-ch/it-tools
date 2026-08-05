# Auth Screen Consistency Fix

**Date:** 2026-03-30
**Scope:** Visual/functional fix across 4 tool pages

---

## Problem

Four tools show a broken unauthenticated state when opened directly (i.e. without first signing in at the hub):

| Tool | Symptom |
|------|---------|
| Group Import | Topbar renders; body is blank dark page |
| License Audit | Topbar renders; body is blank dark page |
| MFA Status Report | Topbar renders; body is blank dark page |
| Name Resolver | Entire page invisible (body opacity stays 0) |

**Root cause — JS (all 4 tools):** `ITTools.auth.init()` is async and only fires `onSignIn` if a cached session exists. When no session is found, neither `onSignIn` nor `onSignOut` fires, so `#authScreen` stays `display:none` and the page shows nothing useful.

**Root cause — CSS (Name Resolver only):** The page has `body { opacity: 0; }` as a flash-of-content guard. The `onSignIn` and `onSignOut` callbacks both set `opacity: 1`, but neither fires when there is no session, so the page remains invisible.

**Reference implementation:** `tools/guest-audit/index.html` already handles this correctly with a `_sessionFound` flag checked after `await ITTools.auth.init(...)`. All fixes replicate that pattern.

---

## What Changes

### JS fix — Group Import, License Audit, MFA Status, Name Resolver

In each tool's `init()` function, add the `_sessionFound` guard pattern:

```js
// Before await ITTools.auth.init(...)
let _sessionFound = false;

// First line of onSignIn callback
_sessionFound = true;

// After await ITTools.auth.init(...) resolves
if (!_sessionFound) {
  document.getElementById("authScreen").style.display = "flex";
}
```

Name Resolver additionally sets opacity in the fallback:

```js
if (!_sessionFound) {
  document.getElementById("authScreen").style.display = "flex";
  document.body.style.opacity = "1";
}
```

### Color fix — Group Import, MFA Status

Standardize auth card icon backgrounds to `var(--blue-light)` to match all other tools:

| Tool | Current | New |
|------|---------|-----|
| Group Import | `var(--green-light)` | `var(--blue-light)` |
| MFA Status | `var(--red-light)` | `var(--blue-light)` |

---

## What Does NOT Change

- `shared/auth.js` — untouched
- `index.html` (hub page) — untouched
- `tools/guest-audit/index.html` — already correct, untouched
- All tool functionality, layouts, app-screen CSS
- Each tool's icon/emoji identity (only the background color behind it changes)

---

## Files Modified

1. `tools/group-import/index.html` — JS fix + icon bg color
2. `tools/license-audit/index.html` — JS fix only
3. `tools/mfa-status/index.html` — JS fix + icon bg color
4. `tools/name-resolver/index.html` — JS fix + opacity fallback

---

## Success Criteria

- Opening any tool directly without a cached session shows the centered auth card
- Signing in from the tool's own auth card works and transitions to the app screen
- Signing out from any tool returns to the auth card
- Name Resolver page is visible immediately (no invisible flash)
- All 5 auth card icon backgrounds are `var(--blue-light)`
- No regressions when opening tools after signing in at the hub
