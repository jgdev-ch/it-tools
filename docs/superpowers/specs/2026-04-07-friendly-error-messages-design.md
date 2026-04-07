# Friendly Error Messages — Design Spec

**Date:** 2026-04-07
**Status:** Approved

## Goal

Replace raw JavaScript/Graph error strings shown in tool banners with consistent, human-readable messages that tell users what went wrong and what to do about it. Error detection only — no timeout progress notifications.

## Problem

When a Graph API call fails today, tools display `e.message` directly in `#errBanner`. Depending on the failure type, users see strings like:

- `"Failed to fetch"` — network dropout mid-scan
- `"NetworkError when attempting to fetch resource"` — Firefox variant of the above
- `"Graph error 503"` — Microsoft service outage
- `"Rate limited by Microsoft Graph. Try again in a moment."` — already reasonable (from `_checkResponse`)
- `"Permission denied — ..."` — already reasonable (from `_checkResponse`)

The first two are unactionable to a non-technical user. The 503 case gives no guidance. The goal is to catch these at a single shared classification point and replace them with friendly, actionable text.

## Approach

Add `ITTools.graph.friendlyError(err)` to the existing `ITTools.graph` IIFE in `shared/auth.js`. Each tool's error catch block calls this function instead of using `e.message` directly. No new UI patterns, no new files — the existing `#errBanner` elements and `showErr()` helpers in each tool are unchanged.

## New API — `ITTools.graph.friendlyError`

```js
ITTools.graph.friendlyError(err)
```

**Parameter:** `err` — any thrown value (Error object, string, or unknown)

**Returns:** A user-friendly string describing the error and what to do.

**Classification logic (checked in order):**

| Priority | Detection | Message returned |
|----------|-----------|-----------------|
| 1 | `err instanceof TypeError` OR message contains `"Failed to fetch"`, `"NetworkError"`, or `"Load failed"` | `"Unable to reach Microsoft Graph — check your internet connection and try again."` |
| 2 | Message contains `"503"`, `"502"`, or `"Service Unavailable"` | `"Microsoft Graph is temporarily unavailable. Try again in a few minutes."` |
| 3 | Message contains `"429"`, `"Rate limited"`, or `"Too Many Requests"` | `"Microsoft Graph is rate limiting requests. Wait a moment and try again."` |
| 4 | Message contains `"401"` or `"Not signed in"` | `"Your session has expired. Please sign out and sign in again."` |
| 5 | Everything else (403, other Graph errors, unknown) | Pass through original `err.message` — `_checkResponse` already formats permission errors well |

The function never throws. If `err` is not an Error object (e.g. a raw string), it falls through to the passthrough case.

## Per-Tool Wiring

Each tool's main catch block(s) that currently set `#errBanner` or call `showErr()` on Graph failures replace `e.message` with `ITTools.graph.friendlyError(e)`.

| Tool | Change |
|------|--------|
| `tools/license-audit/index.html` | Main scan catch (sets `#errBanner`) |
| `tools/finance-dashboard/index.html` | Main scan catch (sets `#errBanner`) |
| `tools/mfa-status/index.html` | Main scan catch (sets `#errBanner`) |
| `tools/guest-audit/index.html` | Main scan catch (sets `#errBanner`) |
| `tools/group-import/index.html` | Graph call catch blocks (call `showErr()`) |
| `tools/name-resolver/index.html` | Top-level batch error display |

**What is not changing:**
- The `#errBanner` elements themselves — no HTML changes
- The `showErr()` helper in Group Import — unchanged
- `graphWithRetry` / `gwr` retry logic — rate-limit retry behaviour is untouched
- `_checkResponse` in `shared/auth.js` — permission and rate-limit messages from there are already good and pass through unchanged (priority 5)
- Name Resolver's per-row `retryRow()` not-found fallback — individual row failures are not surfaced as banners; that behaviour is unchanged

## Files Changed

| File | Change |
|------|--------|
| `shared/auth.js` | Add `friendlyError` to `ITTools.graph` IIFE; add to return object |
| `tools/license-audit/index.html` | 1 catch block |
| `tools/finance-dashboard/index.html` | 1 catch block |
| `tools/mfa-status/index.html` | 1 catch block |
| `tools/guest-audit/index.html` | 1 catch block |
| `tools/group-import/index.html` | `lookupGroup()` catch + `runImport()` catch |
| `tools/name-resolver/index.html` | 1 catch block |

**Total:** 1 new shared method + ~8 small call-site edits across 6 tool files.
