# Name Resolver — Design Spec
**Date:** 2026-03-29
**Tool path:** `tools/name-resolver/index.html`

---

## Overview

A read-only tenant lookup tool that accepts a file of user names (CSV, Excel, or pasted text), searches Microsoft Graph, and produces an email-only CSV ready to feed directly into the Group Import tool.

The tool bridges the gap between "a list of names from a ticket or HR export" and "a ready-to-go email list for group-import." It never writes to Graph — all operations are read-only.

**Graph permissions:** `User.Read.All`, `Directory.Read.All`
Both are already consented for group-import users — no new admin consent required.

---

## Input Formats

| Format | How |
|--------|-----|
| CSV (`.csv`) | Parsed natively in-browser |
| Excel (`.xlsx`) | Parsed via SheetJS (CDN) |
| Pasted text | Raw text area — one name per line; comma-split only applied when no newlines detected (inline lists) |

---

## Three-Step Wizard

Mirrors the group-import UX pattern for muscle memory / zero retraining cost.

### Step 1 — Upload & Map

- User drops a file or pastes text
- Tool auto-detects name columns by scoring headers against known patterns: `first`, `last`, `name`, `display`, `full`, `surname`, `given`
- Auto-detected best guess marked with `✦` (consistent with group-import)
- Supported column arrangements:
  - Full name in one column (`Display Name`, `Full Name`)
  - Separate first + last columns
  - Last + first (reversed order)
  - `"Last, First"` comma-reversed format
  - Last name only (surname-only columns)
- Names are deduplicated and normalised before lookup (whitespace trimmed, double spaces collapsed)
- Preview shows first 5 detected names before the user proceeds

### Step 2 — Resolve & Disambiguate

**Graph query per name:**
```
GET /users?$search="displayName:{name}"&$top=10&$select=displayName,mail,userPrincipalName,department,userType
ConsistencyLevel: eventual
```
Returns up to 10 candidates per name. `$select` limits payload to only the fields needed.

**Batching:** 5 concurrent requests to stay within Graph throttle limits.

**Result states:**

| State | Display | CSV output |
|-------|---------|------------|
| 1 match | ✓ green "Matched" | email address |
| 2+ matches | ⚠ amber "X matches" | blank until resolved |
| 0 matches | ✕ red "Not found" | blank |
| Skipped by user | — grey "Skipped" | blank |

**Disambiguation UI (inline expand — Option A):**
- Ambiguous row expands in-place below the matched row
- Each candidate shows: display name, email/UPN, department, account type (Member/Guest)
- User picks one via radio-style selection; row collapses and turns green
- "Skip" option available if no candidate is correct

**Progress:** Progress bar displays "X of Y resolved" during batch run. Re-run button available per row.

### Step 3 — Download

- Summary tally: X matched, Y disambiguated, Z not found / skipped
- **Download CSV** — email-only column; blank for not-found/skipped rows
- **Copy to clipboard** — same content, no file download required

---

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| Token refresh failure mid-resolve | Batch pauses; inline error with re-auth prompt; progress not lost |
| Graph 429 throttle | Auto-retry after `Retry-After` duration; progress bar shows countdown |
| SheetJS CDN failure | Excel input option hidden; CSV and paste still available |
| Empty / no detectable columns | Inline error explaining expected format; prompts retry |
| Special characters in names (O'Brien, accented) | Properly encoded in `$search` query |
| All candidates wrong / no good match | "Skip" on inline expand → blank email in output |

---

## Output CSV

Single column: `email`

- Matched users: their UPN / mail address
- Not found / skipped: blank value (row preserved so nothing is silently dropped)
- Group-import skips blank rows naturally; the file serves as a complete audit record for tickets

---

## File Structure

```
tools/
  name-resolver/
    index.html        ← entire tool (single file, no build step)
shared/
  auth.js             ← MSAL + ITTools.graph.* helpers (unchanged)
  styles.css          ← design tokens (unchanged)
  msal-browser.min.js ← MSAL lib (unchanged)
```

SheetJS loaded from CDN at runtime (not bundled). Falls back gracefully if unavailable.

---

## Permissions Note

The Entra app registration already has `User.Read.All` and `Directory.Read.All` consented (from group-import). No changes to the app registration are required. The tool requests these scopes at sign-in using the existing `ITTools.auth.init()` pattern.

---

## Out of Scope (v1)

- Writing to Graph (this tool is read-only)
- Bulk re-lookup / refresh all rows after initial resolve
- Exporting a full audit record with names + departments + statuses (email-only output is intentional)
- Offline / cached directory support
