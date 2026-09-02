# On-Call Rotation — Design Spec
**Date:** 2026-09-02
**Status:** Approved

## Overview

Replaces the team's shared `On Call Rotation.xlsx` with a hub page showing the weekly IT on-call schedule and tech contact details, with live in-hub editing for admins. Supersedes the original 2026-06-02 two-phase brainstorm (static-JSON-export-then-live-save) — Azure permission checks done during this brainstorm confirmed the live-save backend is buildable now with existing rights, so this ships as one build instead of two.

**Why:** The spreadsheet is inconvenient to share and update, and gives no visibility to anyone who isn't specifically handed the file. The hub gives every relevant admin a live view, and a smaller admin group a clean edit path with no more emailing an updated `.xlsx` around.

## Access

- **View:** any signed-in tenant user, **except** members of `SG-IT-Tools-GSD` (`3e1a4757-8189-4908-a611-b6029399e69e`) — the front-line service desk group, which doesn't need this data. This is a **deny-gate**, the inverse of every other hub gate today (`GROUP_GATES` in `index.html` / `shared/auth.js` are all allow-gates: locked by default, unlocked on match). The On-Call card gets no `reportingOnly`/`securityOnly`-style flag in `config.json` (same default-open pattern as User Creation/Group Admin), but a small GSD-specific check hides the card for members of that one group, and the tool page itself performs the same check on load in case someone navigates to the URL directly.
- **Save (edit the schedule):** requires membership in a new Entra group, `SG-IT-Tools-OnCall-Admin` (to be created — not yet provisioned). Gates both the lock/unlock edit UI in the tool and the `OnCallSave` backend function's write path.

## Data Model

Pulled from the live `On Call Rotation.xlsx` (2026-09-02) via the workbook's `2024-Schedule`/`2025-Schedule`/`2026-Schedule`/`Phone Details` sheets — not the stale 91-day-old placeholder data from the original brainstorm.

```json
{
  "schedule": [
    { "startDate": "2026-01-04", "tech": "Joshua", "timeOff": "", "notes": "" }
  ],
  "rotationTechs": [
    {
      "name": "Joshua Garrett",
      "shortName": "Joshua",
      "phones": [
        { "label": "8x8", "number": "484-380-9339" },
        { "label": "Work", "number": "223-271-6479" },
        { "label": "Personal", "number": "445-888-0009" },
        { "label": "Teams", "number": "417-719-1960" }
      ]
    }
  ],
  "otherContacts": [
    {
      "name": "Andy Singh",
      "phones": [
        { "label": "Personal", "number": "714-757-9224" },
        { "label": "Teams", "number": "417-719-1884" }
      ]
    }
  ]
}
```

- **`schedule`**: all 161 rows across 2024 (Jan 7 – Dec 29), 2025 (Jan 5 – Dec 28), and 2026 (Jan 4 – Dec 27), taken verbatim from the workbook. `startDate` normalized to ISO `YYYY-MM-DD` for every year (the 2025 sheet stores Excel date serials rather than text dates — converted, not re-typed by hand, to avoid transcription error). `timeOff`/`notes` are empty for all 161 rows in the source (confirmed — never used in 3 years of real operation) but the fields stay on every row since the fields may see real use once this is an app instead of a spreadsheet.
- **`rotationTechs`**: the 5 currently-active rotation members with contact cards — **Joshua Garrett, Nick Zoshak, Joe Randazzo, Robert Tyson, Krista Guthrie**. Phone label sets vary per person (e.g. Nick currently has only a Personal number on file; Joe and Robert use a combined `"Personal/Work"` label for one shared number) — preserved exactly as entered, not normalized into a fixed label set.
- **`otherContacts`**: **Andy Singh, Justin Canales, Ian Sanchez** — current employees who are not currently in the rotation cycle. Shown in a visually separate "Other Contacts" group so an admin can pull one into the rotation later without re-entering their numbers.
- **David Wilhite** is deliberately **not** in `rotationTechs` or `otherContacts` (no longer with the company) but his name stays as plain text in the historical `schedule` rows through his last on-call week (2026-04-26) — this is a historical record and isn't rewritten.
- The workbook's `On Call Phone Number` column (per-row) is dropped entirely — it was empty in every row of every year; the real phone lookup is always "find this week's `tech` in `rotationTechs`," not a stored per-row number.

## Page Layout ("Spotlight + Table")

Chosen over two alternatives (split dashboard; compact table-only) via the visual brainstorm companion — picked for making "who's on call right now" unmissable on load.

1. **Hero card** — "On Call This Week": resolves today's date to its containing Sunday-start week, looks up that week's `schedule` entry, and shows the assigned tech's name plus every phone number from their `rotationTechs` entry inline.
2. **Year tabs** — 2024 / 2025 / 2026, switching which `schedule` rows the table below renders. (No 2027 data yet — an admin adds it via the edit flow once finalized, same as any other row.)
3. **Schedule table** — columns: Start Date · Tech · Time Off · Notes.
4. **Contacts section** (below the table) — one card per `rotationTechs` entry, then a visually distinct "Other Contacts" row for `otherContacts`.
5. **Edit mode** — a lock/unlock toggle, visible only to `SG-IT-Tools-OnCall-Admin` members, switches the schedule table and contact cards into an editable state (add/edit rows, add/remove phone numbers). "Save" calls the backend directly — no export/import step.

## Backend

Reuses existing Azure rights confirmed live during this brainstorm (`az role assignment list`), rather than requesting new infra the way Exchange Audit Phase B did (still blocked on `Microsoft.Web/Sites/write` in the Mailbox Cleanup resource group).

| Piece | Value |
|---|---|
| Function App (new) | `p-corp-fa-ittools-azuc-01`, created in the existing `P-RG-CORP-EUS-AdobeLicenseMonitor-AZUC-01` resource group (confirmed: current user has `Website Contributor` + `Web Plan Contributor` there today) |
| Storage container (new) | `oncall-rotation`, created inside the existing `pcorpsambcleanupazuc01` storage account (confirmed: current user has `Storage Blob Data Contributor` there; a brand-new storage *account* is not possible — no account-creation rights exist in either candidate resource group, only container-level data-plane rights) |
| Blob | `oncall-rotation/data.json` — the JSON structure above |
| Function: `OnCallGet` | EasyAuth: any signed-in tenant user (Entra bearer token) except `SG-IT-Tools-GSD` members (see Access). Reads the blob via the Function App's own system-assigned managed identity — no SAS in client JS. |
| Function: `OnCallSave` | EasyAuth: signed-in user, additionally checks caller's membership in `SG-IT-Tools-OnCall-Admin` before writing. Writes the blob via the same managed identity. |

This Function App is intentionally generic (not Adobe-branded) — it's the first tenant of what can become a shared backend for future tools needing authenticated server-side logic, without requiring a new infra request each time.

## Not Yet Provisioned (blockers before build)

- `SG-IT-Tools-OnCall-Admin` Entra group — needs creation and initial membership decided.
- `p-corp-fa-ittools-azuc-01` Function App — needs creation (rights confirmed, not yet actually created).
- `oncall-rotation` container in `pcorpsambcleanupazuc01` — needs creation.
- Managed identity role grant: the new Function App's system-assigned identity needs `Storage Blob Data Contributor` (or Reader/Contributor split between `OnCallGet`/`OnCallSave`) scoped to the `oncall-rotation` container.
- EasyAuth configuration on the new Function App (audience/scope, matching the pattern already live on `p-corp-fa-adobelicmon-azuc-01`).

## Out of Scope

- No algorithmic rotation generation — the schedule has real manual deviations from a strict 6-person cycle (confirmed in the source data), so all data is literal committed/stored rows, never computed.
- No changes to the historical 2024/2025/2026 schedule data beyond format normalization (date parsing) — who was assigned which week is not being corrected or re-litigated as part of this build.
- No re-inclusion of David Wilhite in any contact list.
