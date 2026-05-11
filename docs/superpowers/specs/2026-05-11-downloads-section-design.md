# Scripts & Downloads Section — Design Spec

**Date:** 2026-05-11
**Status:** Approved
**Version target:** v1.6.0

---

## Overview

Add a **Scripts & Downloads** section to the IT Tools Hub main page. The section renders below the existing tool sections (Daily Operations, Reporting & Audit) and is only visible after sign-in. Techs can browse and download curated PowerShell scripts directly from the hub without needing repo access.

Adding a new script requires one entry in `downloads.json` and dropping the file in the appropriate folder — no HTML changes needed.

---

## File Structure

```
it-tools/
├── scripts/                        ← new — home for pure download scripts
│   └── (future scripts with no web tool destination go here)
├── downloads.json                  ← new — drives the Downloads section
├── config.json                     ← unchanged
├── index.html                      ← updated: loadDownloads(), card CSS, section div
└── tools/
    └── mailbox-cleanup/            ← unchanged — stays for future Azure wiring
        ├── Invoke-MailboxCleanup.ps1
        ├── Run-MailboxCleanup.bat
        └── README.txt
```

`scripts/` is the canonical home for scripts with no planned web tool equivalent. Scripts that live in `tools/` (e.g. mailbox-cleanup, destined for future Azure wiring) are referenced from their existing location via raw GitHub URL — no duplication.

---

## `downloads.json` Schema

```json
{
  "scripts": [
    {
      "id": "mailbox-cleanup",
      "name": "Mailbox Cleanup Script",
      "description": "Clear Recoverable Items for quota-blocked Exchange Online users under the 3-Year Retention Policy. Runs in ~6 minutes vs days with the legacy approach.",
      "version": "1.0",
      "type": "PowerShell",
      "accent": "#1d4ed8",
      "iconBg": "#1e2d5a",
      "roles": ["Exchange Admin", "Compliance Admin"],
      "requires": "ExchangeOnlineManagement v3.9+",
      "updated": "2026-05",
      "files": [
        { "label": "Download .ps1", "path": "tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1", "primary": true },
        { "label": "Launcher .bat", "path": "tools/mailbox-cleanup/Run-MailboxCleanup.bat" }
      ]
    }
  ]
}
```

### Field reference

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique identifier |
| `name` | Yes | Display name on card |
| `description` | Yes | Full description shown on card |
| `version` | Yes | Shown next to name (e.g. "v1.0") |
| `type` | Yes | Language/type badge — "PowerShell", "Batch", etc. |
| `accent` | Yes | Left border color (hex) |
| `iconBg` | Yes | Icon badge background (hex) |
| `roles` | Yes | Array of required role strings — rendered as green pills |
| `requires` | No | Dependency note shown in italic (e.g. module version) |
| `updated` | Yes | Last updated string (e.g. "2026-05") |
| `files` | Yes | Array of downloadable files — see below |

### `files` array

| Field | Required | Description |
|-------|----------|-------------|
| `label` | Yes | Button label (e.g. "Download .ps1") |
| `path` | Yes | Repo-relative path — resolved to raw GitHub URL at render time |
| `primary` | No | `true` = solid blue button; omit or `false` = ghost secondary button |

Raw GitHub URL base: `https://raw.githubusercontent.com/jgdev-ch/it-tools/main/`

---

## Hub Rendering

### New elements in `index.html`

1. **`#downloadsSection` div** — sits below `#toolsGrid`, hidden by default (`display:none`).
2. **`loadDownloads()` async function** — fetches `downloads.json`, renders the section HTML, shows `#downloadsSection`.
3. **CSS** — download row styles (accent bar, PS badge, pills, primary/ghost buttons) added to the existing `<style>` block following the established naming conventions.

### Auth gating

`loadDownloads()` is called inside the existing `onSignIn` callback, immediately after `loadTools()` and the gate checks. On sign-out, `#downloadsSection` is hidden and its content cleared. This matches the pattern used for the tool gate unlock/lock cycle.

```
onSignIn:
  → setUser(acct)
  → restoreFromLocalStorage()    ← existing
  → loadTools()                  ← existing
  → checkGates()                 ← existing
  → loadDownloads()              ← new

onSignOut:
  → clearUser()
  → clearAllGates()              ← existing
  → hideDownloads()              ← new
```

### Section placement

Rendered below all tool sections, above the footer. Uses the same `.section-label` / section pattern as Daily Operations and Reporting & Audit.

### Card design (Option C — Rich Row)

Each script renders as a full-width row with:

- **Left accent bar** — 3px solid, color from `accent` field, `border-radius: 0 10px 10px 0`
- **Icon badge** — 36×36px rounded square, `iconBg` background, terminal/script SVG icon
- **Header row** — name (bold, 14px) + version (muted, 10px)
- **Description** — 12px muted, 2 lines typical
- **Metadata row** — type pill (blue), role pills (green), requires note (italic muted)
- **Button column** — primary file = solid blue button; additional files = ghost buttons stacked below

### Download mechanism

Each button triggers a direct browser download via a temporary `<a download>` element pointing to the raw GitHub URL. No backend, no redirect — file downloads from the repo directly.

```javascript
function downloadFile(path) {
  const a = document.createElement("a");
  a.href = `https://raw.githubusercontent.com/jgdev-ch/it-tools/main/${path}`;
  a.download = path.split("/").pop();
  a.click();
}
```

---

## Error Handling

- If `downloads.json` fails to fetch — section stays hidden, silent failure (no broken UI).
- If a file download fails — browser handles the error natively (404 page or network error). No special handling needed since files are static assets in a public repo.

---

## Future Extensibility

- **New script** — add one entry to `downloads.json` + drop file in `scripts/` (or `tools/` if web-destined). Zero HTML changes.
- **Script categories** — `downloads.json` can grow a `category` field and the renderer can group rows under sub-labels, same pattern as `config.json`.
- **README/docs link** — a future `docs` field on each entry could add a third ghost button linking to the script's README or Obsidian note.
- **Version history** — a `changelog` array could power a future expand/collapse version history row.
