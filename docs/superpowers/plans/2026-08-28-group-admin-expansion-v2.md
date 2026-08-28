# Group Administration Tool — v2 (Exchange script generation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the Group Administration tool by wiring the three Exchange Online object types (Distribution List, Mail-enabled Security Group, Shared Mailbox) so each supports add/remove/export and produces a downloadable `.zip` containing a ready-to-run PowerShell script plus a self-running `.bat` launcher.

**Architecture:** v1 already shipped the launcher + wizard shell + `OBJECT_TYPES` registry in `tools/group-import/index.html`, with the three Exchange cards rendered as disabled "v2, coming soon" placeholders. v2 flips those three to `enabled:true`, adds two new wizard steps (an Exchange target step that Graph-*reads* for verification, and a shared-mailbox permission-type step), and routes the Exchange "Generate" path to a **new sibling module** `tools/group-import/exo-scripts.js` that builds the `.ps1` / `.bat` text and bundles them with JSZip. All Graph-live behavior from v1 is untouched. No new Graph scopes: `Group.ReadWrite.All` + `Directory.Read.All` already cover the read-only lookups, and every Exchange write happens inside the tech's own PowerShell session.

**Tech Stack:** Static HTML/JS, no build step. MSAL via `shared/msal-browser.min.js`; shared helpers `ITTools.auth` (`getToken`, `getAccount`), `ITTools.graph` (`get`, `getAll`, `friendlyError` — always sends `ConsistencyLevel: eventual`), `ITTools.csv` (`parse`, `detectEmailColumn`, `download`), `ITTools.ui` (`withButtonSpinner`, `renderTopbar`, `setUser`), `shared/styles.css`. JSZip 3.10.1 vendored (copied from `tools/user-creation/jszip.min.js`). Generated scripts target PowerShell 7 (`pwsh`) with a Windows PowerShell 5.1 fallback and `ExchangeOnlineManagement` 3.9.0+.

**Testing approach (codebase-adapted):** This repo has **no JS test framework and no build step**. The established verification convention is:
1. `node --check` on standalone JS files, and the extract-then-check one-liner for inline `<script>` blocks (used by `docs/superpowers/plans/2026-07-29-exchange-audit-redesign-phase-a.md` and `2026-08-27-hub-recent-updates-changelog.md`).
2. `[System.Management.Automation.Language.Parser]::ParseFile(...)` via `pwsh` for every generated PowerShell script (used by the mailbox-cleanup, archive-cleanup, user-creation and exchange-audit plans).
3. **Real functional testing is manual, in-browser, against a disposable test DL and a disposable test shared mailbox** — generate the zip, run the `.bat`, review the `-WhatIf` dry run, confirm, verify the transcript. Task 18 is that manual matrix; do not invent automated tests that this codebase cannot run.

Every task that touches generated PowerShell renders it to `$TEMP` with a small node harness (written to `$TEMP`, never committed) and parses it with `pwsh`. That is real verification, not a stand-in.

**Escaping rules (read before writing any template literal in `exo-scripts.js`) — these cause silent corruption if ignored:**
- `${` inside a JS template literal interpolates. **Never** use PowerShell's `${var}` syntax in generated code. `$var` and `$(...)` subexpressions are safe.
- A backslash in a template literal eats the next character (`"NT AUTHORITY\SELF"` becomes `NT AUTHORITY SELF`... actually `NT AUTHORITYSELF`). **Always write `\\` for a literal backslash.**
- Backticks must be escaped as `` \` ``. **Avoid PowerShell backticks entirely** — no line continuations, no `` `n ``. Use `Write-Host ""` for blank lines and keep cmdlet calls on one line.
- All injected values go through `psStr()` (single-quoted PowerShell literal with `''` doubling). Never interpolate a raw user string into generated code.

**Branch/deploy:** Work on `testing` (already the current branch; auto-deploys to the preview site). Commit after every task. **Do not merge to `main`** — promotion is Josh's explicit call and is out of scope for this plan.

---

## File Structure

- **Create:** `tools/group-import/exo-scripts.js` — the PowerShell/batch/zip generator. Pure string building plus one JSZip call; **zero DOM access**. Exposes a single global `ExoScripts` with `buildContext`, `buildScript`, `buildBat`, `buildZip` (plus `_` prefixed internals used only by verification). Lives in its own file rather than inline because (a) it is ~350 lines of template text that would push `index.html` past 1,000 lines, (b) a standalone file is directly `node --check`-able and directly loadable in a node harness for parser verification, and (c) the tool folder already has the precedent of sibling JS files (`jszip.min.js` in `tools/user-creation/`).
- **Create:** `tools/group-import/jszip.min.js` — byte copy of `tools/user-creation/jszip.min.js` (JSZip 3.10.1). Copied, not re-downloaded and not referenced across folders, so the tool folder stays self-contained and deployable on its own (same convention as user-creation).
- **Modify:** `tools/group-import/index.html` — enable the three Exchange types, make the action step registry-driven, add the Exchange target step, the shared-mailbox permission step, CSV validation, and the Generate step. All wizard UI stays inline here (hub one-file-per-tool convention); only the generator moves out.
- **Modify:** `config.json` — update the `group-import` entry's `description` (drop "coming soon", state the Graph-live vs script split). `id`, `path`, `status`, `permissions`, `accent`, `category` unchanged.
- **Modify:** `changelog.json` — new `2.4.0` entry.
- **Modify:** `index.html` (repo root) — hub footer version `v2.3.4` → `v2.4.0`.
- **No changes:** `shared/auth.js`, `shared/styles.css` (reused as-is; `.card`, `.card-title`, `.field`, `.field-label`, `.input-row`, `.checkbox-label`, `.checkbox-group`, `.banner.error`, `.banner.warn`, `.btn-row`, `.mono`, `.text-xs`, `.muted` all already exist).

Naming contract used by every task below (defined once in Task 2's `buildContext`, consumed everywhere after):

| Field | Meaning | Example |
|---|---|---|
| `ctx.typeId` | registry id | `"distribution-list"` |
| `ctx.op` | `add` \| `remove` \| `export` \| `grant` | `"add"` |
| `ctx.model` | `"members"` \| `"permissions"` | `"members"` |
| `ctx.opLabel` | human label | `"Add members"` |
| `ctx.title` | header title | `"Distribution List: add members"` |
| `ctx.target` | identity passed to `-Identity` | `"it-all@corrohealth.com"` |
| `ctx.targetDisplay` | display name for copy | `"IT All"` |
| `ctx.identities` | validated member/trustee list | `["a@x.com"]` |
| `ctx.perms` | `{full, sendAs, onBehalf}` (shared mailbox) | `{full:true,...}` |
| `ctx.autoMapping` | boolean, Full Access only | `true` |
| `ctx.scriptName` / `ctx.batName` / `ctx.zipName` | output filenames | `Add-DistributionListMembers.ps1` |

---

## Task 1: Vendor JSZip into the tool folder

**Files:**
- Create: `tools/group-import/jszip.min.js`
- Modify: `tools/group-import/index.html:7-8` (script tags in `<head>`)

- [ ] **Step 1: Copy the vendored library**

```bash
cp tools/user-creation/jszip.min.js tools/group-import/jszip.min.js
```

- [ ] **Step 2: Verify the copy is intact**

```bash
node --check tools/group-import/jszip.min.js && echo "JSZip OK"
```
Expected: `JSZip OK`

- [ ] **Step 3: Add the script tag**

In `tools/group-import/index.html`, replace:

```html
<script src="../../shared/msal-browser.min.js"></script>
<link rel="stylesheet" href="../../shared/styles.css"/>
```

with:

```html
<script src="../../shared/msal-browser.min.js"></script>
<script src="jszip.min.js"></script>
<link rel="stylesheet" href="../../shared/styles.css"/>
```

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/jszip.min.js tools/group-import/index.html
git commit -m "Group Admin v2: vendor JSZip into the tool folder"
```

---

## Task 2: Create `exo-scripts.js` with helpers and `buildContext`

The context builder is the single source of truth for operation labels and output filenames. Everything downstream reads from it.

**Files:**
- Create: `tools/group-import/exo-scripts.js`

- [ ] **Step 1: Write the module skeleton**

```js
/*
 * exo-scripts.js — Exchange Online script generator for the Group Administration tool.
 *
 * Pure string building: no DOM, no network, no ITTools dependency. Loadable in node
 * for verification (see docs/superpowers/plans/2026-08-28-group-admin-expansion-v2.md).
 *
 * TEMPLATE ESCAPING RULES (violating these silently corrupts generated scripts):
 *   - Never emit PowerShell ${var} syntax — "${" interpolates in JS template literals.
 *   - Write "\\" for every literal backslash (a lone "\" eats the next character).
 *   - Never emit PowerShell backticks: no line continuations, no `n. One line per cmdlet.
 *   - Every injected value goes through psStr().
 */
(function (root) {
  "use strict";

  // ── Low-level helpers ─────────────────────────────────────────
  /** Single-quoted PowerShell string literal, with '' doubling. */
  function psStr(value) {
    return "'" + String(value == null ? "" : value).replace(/'/g, "''") + "'";
  }

  /** Filename-safe slug for output names. */
  function slug(value) {
    const s = String(value == null ? "" : value)
      .replace(/[^A-Za-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 40);
    return s || "target";
  }

  /** Normalise to CRLF so the .ps1 and .bat behave on Windows. */
  function crlf(text) {
    return String(text).replace(/\r?\n/g, "\r\n");
  }

  // ── Operation labels + output filenames ───────────────────────
  const OP_LABELS = {
    members:     { add: "Add members", remove: "Remove members", export: "Export members" },
    permissions: { grant: "Grant access", remove: "Remove access", export: "Export access list" },
  };

  const SCRIPT_BASE = {
    "distribution-list": {
      add:    "Add-DistributionListMembers",
      remove: "Remove-DistributionListMembers",
      export: "Export-DistributionListMembers",
    },
    "mail-security-group": {
      add:    "Add-MailSecurityGroupMembers",
      remove: "Remove-MailSecurityGroupMembers",
      export: "Export-MailSecurityGroupMembers",
    },
    "shared-mailbox": {
      grant:  "Grant-SharedMailboxAccess",
      remove: "Remove-SharedMailboxAccess",
      export: "Export-SharedMailboxAccess",
    },
  };

  function isMailbox(typeId) { return typeId === "shared-mailbox"; }

  /**
   * buildContext({ typeId, typeLabel, op, target, targetDisplay, identities,
   *                perms:{full,sendAs,onBehalf}, autoMapping, tech }) -> ctx
   */
  function buildContext(input) {
    const typeId = input.typeId;
    const op     = input.op;
    const model  = isMailbox(typeId) ? "permissions" : "members";
    const base   = (SCRIPT_BASE[typeId] || {})[op];
    if (!base) throw new Error("Unsupported object type / operation: " + typeId + " / " + op);

    const now     = new Date();
    const target  = String(input.target || "").trim();
    const display = input.targetDisplay || target;
    const label   = input.typeLabel || typeId;
    const opLabel = OP_LABELS[model][op];

    return {
      typeId: typeId,
      op: op,
      model: model,
      opLabel: opLabel,
      typeLabel: label,
      title: label + ": " + opLabel.toLowerCase(),
      target: target,
      targetDisplay: display,
      targetSlug: slug(display),
      identities: (input.identities || []).slice(),
      perms: {
        full:     !!(input.perms && input.perms.full),
        sendAs:   !!(input.perms && input.perms.sendAs),
        onBehalf: !!(input.perms && input.perms.onBehalf),
      },
      autoMapping: input.autoMapping !== false,
      tech: input.tech || "unknown",
      timestamp: now.toISOString().replace("T", " ").slice(0, 19) + " UTC",
      dateOnly: now.toISOString().slice(0, 10),
      scriptName: base + ".ps1",
      batName: "Run-" + base + ".bat",
      zipName: base + "-" + slug(display) + "-" + now.toISOString().slice(0, 10) + ".zip",
      logBase: base,
    };
  }

  root.ExoScripts = {
    buildContext: buildContext,
    _psStr: psStr,
    _slug: slug,
    _crlf: crlf,
  };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 2: Syntax check**

```bash
node --check tools/group-import/exo-scripts.js && echo "JS OK"
```
Expected: `JS OK`

- [ ] **Step 3: Verify `buildContext` output in node**

```bash
node -e "
globalThis.window = globalThis;
require('./tools/group-import/exo-scripts.js');
const a = ExoScripts.buildContext({ typeId:'distribution-list', typeLabel:'Distribution List', op:'add', target:'it-all@corrohealth.com', targetDisplay:'IT All', identities:['x@y.com'], tech:'josh@corrohealth.com' });
console.log(a.title, '|', a.scriptName, '|', a.batName, '|', a.zipName);
const b = ExoScripts.buildContext({ typeId:'shared-mailbox', typeLabel:'Shared Mailbox', op:'export', target:'helpdesk@corrohealth.com' });
console.log(b.model, '|', b.opLabel, '|', b.scriptName, '|', b.autoMapping);
console.log(ExoScripts._psStr(\"O'Brien\"));
"
```
Expected (date will be today's):
```
Distribution List: add members | Add-DistributionListMembers.ps1 | Run-Add-DistributionListMembers.bat | Add-DistributionListMembers-IT-All-2026-08-28.zip
permissions | Export access list | Export-SharedMailboxAccess.ps1 | true
'O''Brien'
```

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin v2: exo-scripts module skeleton + buildContext"
```

---

## Task 3: Shared PowerShell prologue / connect / epilogue blocks

Three reusable blocks every generated script uses. The module-install guard and connect pattern match `tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1` and the user-creation generator (floor `3.9.0`, `Scope CurrentUser`).

**Files:**
- Modify: `tools/group-import/exo-scripts.js` — insert the three functions immediately after `buildContext`, and extend the exported object.

- [ ] **Step 1: Add the prologue builder**

Insert after the closing brace of `buildContext`:

```js
  // ── Shared script blocks ──────────────────────────────────────
  /** Header comment + error preference + logging helpers + transcript start. */
  function psPrologue(ctx, extraHeaderLines) {
    const header = [
      "#  Object type : " + ctx.typeLabel,
      "#  Target      : " + ctx.targetDisplay + " <" + ctx.target + ">",
      "#  Operation   : " + ctx.opLabel,
    ]
      .concat(extraHeaderLines || [])
      .concat([
        "#  Generated   : " + ctx.timestamp,
        "#  Generated by: " + ctx.tech,
      ])
      .join("\n");

    const readOnly = ctx.op === "export";
    const steps = readOnly
      ? [
          "#    1. Connects to Exchange Online in your own admin context.",
          "#    2. Starts a transcript next to this script for audit.",
          "#    3. Reads the current state and writes a CSV next to this script.",
          "#    Nothing is changed. This script only reads.",
        ]
      : [
          "#    1. Connects to Exchange Online in your own admin context.",
          "#    2. Starts a transcript next to this script for audit.",
          "#    3. Runs every change with -WhatIf first, so nothing changes yet.",
          "#    4. Waits for you to type YES, then applies the changes for real.",
        ];

    return `# =====================================================================
#  ${ctx.title}
#  Generated by IT Tools Hub, Group Administration
# ---------------------------------------------------------------------
${header}
# ---------------------------------------------------------------------
#  What this does:
${steps.join("\n")}
# =====================================================================

$ErrorActionPreference = "Continue"

function Write-Head { param([string]$Message) Write-Host ""; Write-Host "  $Message" -ForegroundColor Cyan }
function Write-Item { param([string]$Message, [string]$Color = "Gray") Write-Host "    $Message" -ForegroundColor $Color }

$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $PSScriptRoot (${psStr(ctx.logBase)} + "-" + $stamp + ".log")
Start-Transcript -Path $transcript | Out-Null
`;
  }
```

- [ ] **Step 2: Add the connect block**

```js
  /** ExchangeOnlineManagement install guard + Connect-ExchangeOnline. */
  function psConnect() {
    return `
# --- Connect to Exchange Online ------------------------------------
Write-Head "Connecting to Exchange Online..."

$minVersion = [Version]"3.9.0"
$installed  = Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $installed -or $installed.Version -lt $minVersion) {
    Write-Item "ExchangeOnlineManagement 3.9.0 or newer not found. Installing for the current user..." Yellow
    try {
        Install-Module ExchangeOnlineManagement -MinimumVersion $minVersion -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
    } catch {
        Write-Item ("ERROR: Could not install ExchangeOnlineManagement. " + $_.Exception.Message) Red
        Write-Item "Install it manually, then re-run: Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force" Yellow
        Stop-Transcript | Out-Null
        exit 1
    }
}

try {
    Import-Module ExchangeOnlineManagement -MinimumVersion $minVersion -ErrorAction Stop
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Item "Connected." Green
} catch {
    Write-Item ("ERROR: Could not connect to Exchange Online. " + $_.Exception.Message) Red
    Stop-Transcript | Out-Null
    exit 1
}
`;
  }
```

- [ ] **Step 3: Add the epilogue builder**

```js
  /** Summary tail, disconnect, transcript stop. extraSummary is raw PowerShell lines. */
  function psEpilogue(ctx, extraSummary) {
    return `
# --- Finish --------------------------------------------------------
Write-Head "Complete"
${extraSummary || ""}Write-Item ("Transcript: " + $transcript)
Write-Host ""

Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Stop-Transcript | Out-Null
`;
  }
```

- [ ] **Step 4: Export the new internals**

Replace the export block at the bottom of the file:

```js
  root.ExoScripts = {
    buildContext: buildContext,
    _psStr: psStr,
    _slug: slug,
    _crlf: crlf,
    _psPrologue: psPrologue,
    _psConnect: psConnect,
    _psEpilogue: psEpilogue,
  };
```

- [ ] **Step 5: Verify the blocks parse as PowerShell**

```bash
node --check tools/group-import/exo-scripts.js && node -e "
globalThis.window = globalThis;
require('./tools/group-import/exo-scripts.js');
const fs = require('fs');
const ctx = ExoScripts.buildContext({ typeId:'distribution-list', typeLabel:'Distribution List', op:'add', target:\"it-all@corrohealth.com\", targetDisplay:'IT All', identities:['a@b.com'], tech:'josh@corrohealth.com' });
const ps = ExoScripts._crlf(ExoScripts._psPrologue(ctx, ['#  Members     : 1']) + ExoScripts._psConnect() + ExoScripts._psEpilogue(ctx, 'Write-Item \"Succeeded : 1\"\n'));
fs.writeFileSync(process.env.TEMP + '/exo-blocks.ps1', ps);
console.log('wrote', process.env.TEMP + '/exo-blocks.ps1');
"
pwsh -NoProfile -Command "\$errs=\$null; \$null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path \$env:TEMP 'exo-blocks.ps1'), [ref]\$null, [ref]\$errs); if (\$errs) { \$errs; exit 1 } else { 'parse OK' }"
```
Expected: `wrote …/exo-blocks.ps1` then `parse OK`

- [ ] **Step 6: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin v2: shared PowerShell prologue, connect guard, epilogue"
```

---

## Task 4: Group-member script builder (add / remove) + dispatcher

Covers Distribution List **and** Mail-enabled Security Group — both are distribution groups in Exchange Online, so the cmdlets are identical.

**Files:**
- Modify: `tools/group-import/exo-scripts.js` — add `buildGroupMemberScript`, `buildScript`, extend exports.

- [ ] **Step 1: Add the builder**

Insert after `psEpilogue`:

```js
  // ── Distribution list / mail-enabled security group ───────────
  function buildGroupMemberScript(ctx) {
    const memberBlock = ctx.identities.length
      ? "$Members = @(\n" + ctx.identities.map(v => "    " + psStr(v)).join(",\n") + "\n)"
      : "$Members = @()";

    const inputs = `
# --- Inputs -------------------------------------------------------
$Target = ${psStr(ctx.target)}
${memberBlock}
`;

    const verify = `
# --- Verify the target --------------------------------------------
Write-Head "Verifying the target in Exchange Online..."
try {
    $group = Get-DistributionGroup -Identity $Target -ErrorAction Stop
    Write-Item ("Found: " + $group.DisplayName + " <" + $group.PrimarySmtpAddress + "> [" + $group.RecipientTypeDetails + "]") Green
} catch {
    Write-Item ("ERROR: Could not find '$Target' in Exchange Online. " + $_.Exception.Message) Red
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
    exit 1
}
`;

    const isAdd     = ctx.op === "add";
    const cmdlet    = isAdd ? "Add-DistributionGroupMember" : "Remove-DistributionGroupMember";
    const liveArgs  = isAdd ? "-BypassSecurityGroupManagerCheck" : "-BypassSecurityGroupManagerCheck -Confirm:$false";
    const wouldWord = isAdd ? "WOULD ADD" : "WOULD REMOVE";
    const didWord   = isAdd ? "ADDED" : "REMOVED";

    const body = `
# --- Dry run (-WhatIf, nothing changes) ---------------------------
Write-Head "Dry run. Showing what would change. No changes are made yet."
foreach ($m in $Members) {
    try {
        ${cmdlet} -Identity $Target -Member $m ${liveArgs} -WhatIf -ErrorAction Stop
        Write-Item ("${wouldWord}: " + $m) Yellow
    } catch {
        Write-Item ("WOULD FAIL: " + $m + " - " + $_.Exception.Message) Red
    }
}

# --- Confirm ------------------------------------------------------
Write-Host ""
$answer = Read-Host "  Type YES to apply these changes for real (anything else aborts)"
if ($answer -ne "YES") {
    Write-Item "Aborted. No changes were made." Yellow
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
    exit 0
}

# --- Live run -----------------------------------------------------
Write-Head "Applying changes..."
$ok = 0
$failed = 0
foreach ($m in $Members) {
    try {
        ${cmdlet} -Identity $Target -Member $m ${liveArgs} -ErrorAction Stop
        Write-Item ("${didWord}: " + $m) Green
        $ok++
    } catch {
        Write-Item ("FAILED: " + $m + " - " + $_.Exception.Message) Red
        $failed++
    }
}
`;

    const summary = 'Write-Item ("Succeeded : " + $ok)\nWrite-Item ("Failed    : " + $failed)\n';

    return psPrologue(ctx, ["#  Members     : " + ctx.identities.length]) +
           inputs + psConnect() + verify + body + psEpilogue(ctx, summary);
  }

  /** Dispatch on object type. */
  function buildScript(ctx) {
    if (ctx.typeId === "distribution-list" || ctx.typeId === "mail-security-group") {
      return crlf(buildGroupMemberScript(ctx));
    }
    throw new Error("Script generation is not implemented for object type: " + ctx.typeId);
  }
```

Note: the `shared-mailbox` branch is added to `buildScript` in Task 6. Until then only the two group types generate.

- [ ] **Step 2: Export `buildScript`**

Replace the export block:

```js
  root.ExoScripts = {
    buildContext: buildContext,
    buildScript: buildScript,
    _psStr: psStr,
    _slug: slug,
    _crlf: crlf,
    _psPrologue: psPrologue,
    _psConnect: psConnect,
    _psEpilogue: psEpilogue,
  };
```

- [ ] **Step 3: Write the reusable generation harness to `$TEMP`**

```bash
cat > "$TEMP/gen-exo.js" <<'EOF'
globalThis.window = globalThis;
require("C:/dev/projects/it-tools/tools/group-import/exo-scripts.js");
const fs = require("fs");
const which = process.argv[2];
const base = {
  typeId: "distribution-list", typeLabel: "Distribution List", op: "add",
  target: "it-all@corrohealth.com", targetDisplay: "IT All",
  identities: ["a.one@corrohealth.com", "b.two@corrohealth.com"],
  perms: { full: true, sendAs: true, onBehalf: true },
  autoMapping: true, tech: "joshua.garrett@corrohealth.com",
};
const mbx = Object.assign({}, base, {
  typeId: "shared-mailbox", typeLabel: "Shared Mailbox",
  target: "helpdesk@corrohealth.com", targetDisplay: "Help Desk",
});
const cases = {
  "dl-add":     Object.assign({}, base),
  "dl-remove":  Object.assign({}, base, { op: "remove" }),
  "dl-export":  Object.assign({}, base, { op: "export", identities: [] }),
  "msg-add":    Object.assign({}, base, { typeId: "mail-security-group", typeLabel: "Mail-enabled Security Group" }),
  "msg-export": Object.assign({}, base, { typeId: "mail-security-group", typeLabel: "Mail-enabled Security Group", op: "export", identities: [] }),
  "smb-grant":  Object.assign({}, mbx, { op: "grant" }),
  "smb-grant-full-only": Object.assign({}, mbx, { op: "grant", perms: { full: true, sendAs: false, onBehalf: false }, autoMapping: false }),
  "smb-remove": Object.assign({}, mbx, { op: "remove" }),
  "smb-export": Object.assign({}, mbx, { op: "export", identities: [] }),
};
if (!cases[which]) { console.error("unknown case: " + which); process.exit(1); }
const ctx = ExoScripts.buildContext(cases[which]);
fs.writeFileSync(process.env.TEMP + "/" + which + ".ps1", ExoScripts.buildScript(ctx));
console.log(which, "->", ctx.scriptName, "|", ctx.zipName);
EOF
echo "harness written"
```

- [ ] **Step 4: Generate and parse-check add + remove for both group types**

```bash
node "$TEMP/gen-exo.js" dl-add && node "$TEMP/gen-exo.js" dl-remove && node "$TEMP/gen-exo.js" msg-add
pwsh -NoProfile -Command "foreach (\$f in 'dl-add','dl-remove','msg-add') { \$errs=\$null; \$null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path \$env:TEMP (\$f + '.ps1')), [ref]\$null, [ref]\$errs); if (\$errs) { \"FAIL \$f\"; \$errs; exit 1 } else { \"parse OK \$f\" } }"
```
Expected: three `parse OK …` lines.

- [ ] **Step 5: Eyeball the generated add script for escaping damage**

```bash
grep -n 'Add-DistributionGroupMember\|Read-Host\|Start-Transcript\|\$Members' "$TEMP/dl-add.ps1" | head -20
```
Expected: the cmdlet appears twice (once with `-WhatIf`, once without), `$Members = @(` lists both quoted addresses, `Read-Host` gate present, no stray `${` and no missing `$` sigils.

- [ ] **Step 6: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin v2: DL and mail-enabled SG add/remove script builder"
```

---

## Task 5: Group-member export branch

Export is read-only: no dry run, no confirmation gate, writes a CSV next to the script.

**Files:**
- Modify: `tools/group-import/exo-scripts.js` — add an early export branch inside `buildGroupMemberScript`.

- [ ] **Step 1: Add the export branch**

In `buildGroupMemberScript`, immediately after the `const verify = \`…\`;` block and **before** `const isAdd = ctx.op === "add";`, insert:

```js
    if (ctx.op === "export") {
      const exportBody = `
# --- Export members -----------------------------------------------
Write-Head "Reading current members..."
$outFile = Join-Path $PSScriptRoot (${psStr(ctx.logBase + "-" + ctx.targetSlug)} + "-" + $stamp + ".csv")
$count = 0
try {
    $members = Get-DistributionGroupMember -Identity $Target -ResultSize Unlimited -ErrorAction Stop
    $count = @($members).Count
    if ($count -eq 0) {
        Write-Item "This group has no members. No CSV was written." Yellow
    } else {
        $members | Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails, Alias | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
        Write-Item ("Exported " + $count + " members to:") Green
        Write-Item $outFile
    }
} catch {
    Write-Item ("ERROR: Could not read members. " + $_.Exception.Message) Red
}
`;
      return psPrologue(ctx, []) + inputs + psConnect() + verify + exportBody +
             psEpilogue(ctx, 'Write-Item ("Members read: " + $count)\n');
    }
```

- [ ] **Step 2: Generate and parse-check the export scripts**

```bash
node --check tools/group-import/exo-scripts.js && node "$TEMP/gen-exo.js" dl-export && node "$TEMP/gen-exo.js" msg-export
pwsh -NoProfile -Command "foreach (\$f in 'dl-export','msg-export') { \$errs=\$null; \$null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path \$env:TEMP (\$f + '.ps1')), [ref]\$null, [ref]\$errs); if (\$errs) { \"FAIL \$f\"; \$errs; exit 1 } else { \"parse OK \$f\" } }"
```
Expected: `parse OK dl-export` and `parse OK msg-export`

- [ ] **Step 3: Confirm the export script has no write path**

```bash
grep -c 'Read-Host\|Add-DistributionGroupMember\|Remove-DistributionGroupMember' "$TEMP/dl-export.ps1"
```
Expected: `0`

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin v2: DL and mail-enabled SG member export script"
```

---

## Task 6: Shared-mailbox permission script (grant / remove)

All three permission types, driven by flags embedded in the script so the tech can see exactly what was selected. AutoMapping applies to Full Access only.

**Files:**
- Modify: `tools/group-import/exo-scripts.js` — add `buildMailboxPermissionScript`, wire it into `buildScript`.

- [ ] **Step 1: Add the builder**

Insert after `buildGroupMemberScript`:

```js
  // ── Shared mailbox access permissions ─────────────────────────
  function buildMailboxPermissionScript(ctx) {
    const isGrant = ctx.op === "grant";

    const trusteeBlock = ctx.identities.length
      ? "$Trustees = @(\n" + ctx.identities.map(v => "    " + psStr(v)).join(",\n") + "\n)"
      : "$Trustees = @()";

    const inputs = `
# --- Inputs -------------------------------------------------------
$Mailbox = ${psStr(ctx.target)}
${trusteeBlock}
$DoFullAccess   = $${ctx.perms.full}
$DoSendAs       = $${ctx.perms.sendAs}
$DoSendOnBehalf = $${ctx.perms.onBehalf}
$AutoMapping    = $${ctx.autoMapping}
`;

    const verify = `
# --- Verify the mailbox -------------------------------------------
Write-Head "Verifying the mailbox in Exchange Online..."
try {
    $mbx = Get-Mailbox -Identity $Mailbox -ErrorAction Stop
    Write-Item ("Found: " + $mbx.DisplayName + " <" + $mbx.PrimarySmtpAddress + "> [" + $mbx.RecipientTypeDetails + "]") Green
    if ($mbx.RecipientTypeDetails -ne "SharedMailbox") {
        Write-Item "WARNING: this is not a shared mailbox. Continue only if that is intentional." Yellow
    }
} catch {
    Write-Item ("ERROR: Could not find mailbox '$Mailbox'. " + $_.Exception.Message) Red
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
    exit 1
}
`;

    // Per-permission blocks. -WhatIf preview and live call are emitted side by side
    // so the dry run exercises exactly the cmdlet the live run will use.
    const fullBlock = isGrant
      ? `    if ($DoFullAccess) {
        try {
            if ($Preview) {
                Add-MailboxPermission -Identity $Mailbox -User $Trustee -AccessRights FullAccess -AutoMapping $AutoMapping -Confirm:$false -WhatIf -ErrorAction Stop | Out-Null
                Write-Item ("WOULD GRANT FullAccess (AutoMapping " + $AutoMapping + "): " + $Trustee) Yellow
            } else {
                Add-MailboxPermission -Identity $Mailbox -User $Trustee -AccessRights FullAccess -AutoMapping $AutoMapping -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Item ("GRANTED FullAccess (AutoMapping " + $AutoMapping + "): " + $Trustee) Green
                $script:ok++
            }
        } catch {
            Write-Item ("FullAccess FAILED for " + $Trustee + " - " + $_.Exception.Message) Red
            if (-not $Preview) { $script:failed++ }
        }
    }`
      : `    if ($DoFullAccess) {
        try {
            if ($Preview) {
                Remove-MailboxPermission -Identity $Mailbox -User $Trustee -AccessRights FullAccess -Confirm:$false -WhatIf -ErrorAction Stop | Out-Null
                Write-Item ("WOULD REMOVE FullAccess: " + $Trustee) Yellow
            } else {
                Remove-MailboxPermission -Identity $Mailbox -User $Trustee -AccessRights FullAccess -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Item ("REMOVED FullAccess: " + $Trustee) Green
                $script:ok++
            }
        } catch {
            Write-Item ("FullAccess FAILED for " + $Trustee + " - " + $_.Exception.Message) Red
            if (-not $Preview) { $script:failed++ }
        }
    }`;

    const sendAsBlock = isGrant
      ? `    if ($DoSendAs) {
        try {
            if ($Preview) {
                Add-RecipientPermission -Identity $Mailbox -Trustee $Trustee -AccessRights SendAs -Confirm:$false -WhatIf -ErrorAction Stop | Out-Null
                Write-Item ("WOULD GRANT SendAs: " + $Trustee) Yellow
            } else {
                Add-RecipientPermission -Identity $Mailbox -Trustee $Trustee -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Item ("GRANTED SendAs: " + $Trustee) Green
                $script:ok++
            }
        } catch {
            Write-Item ("SendAs FAILED for " + $Trustee + " - " + $_.Exception.Message) Red
            if (-not $Preview) { $script:failed++ }
        }
    }`
      : `    if ($DoSendAs) {
        try {
            if ($Preview) {
                Remove-RecipientPermission -Identity $Mailbox -Trustee $Trustee -AccessRights SendAs -Confirm:$false -WhatIf -ErrorAction Stop | Out-Null
                Write-Item ("WOULD REMOVE SendAs: " + $Trustee) Yellow
            } else {
                Remove-RecipientPermission -Identity $Mailbox -Trustee $Trustee -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Item ("REMOVED SendAs: " + $Trustee) Green
                $script:ok++
            }
        } catch {
            Write-Item ("SendAs FAILED for " + $Trustee + " - " + $_.Exception.Message) Red
            if (-not $Preview) { $script:failed++ }
        }
    }`;

    const onBehalfBlock = isGrant
      ? `    if ($DoSendOnBehalf) {
        try {
            if ($Preview) {
                Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Add=$Trustee} -WhatIf -ErrorAction Stop
                Write-Item ("WOULD GRANT SendOnBehalf: " + $Trustee) Yellow
            } else {
                Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Add=$Trustee} -ErrorAction Stop
                Write-Item ("GRANTED SendOnBehalf: " + $Trustee) Green
                $script:ok++
            }
        } catch {
            Write-Item ("SendOnBehalf FAILED for " + $Trustee + " - " + $_.Exception.Message) Red
            if (-not $Preview) { $script:failed++ }
        }
    }`
      : `    if ($DoSendOnBehalf) {
        try {
            if ($Preview) {
                Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Remove=$Trustee} -WhatIf -ErrorAction Stop
                Write-Item ("WOULD REMOVE SendOnBehalf: " + $Trustee) Yellow
            } else {
                Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Remove=$Trustee} -ErrorAction Stop
                Write-Item ("REMOVED SendOnBehalf: " + $Trustee) Green
                $script:ok++
            }
        } catch {
            Write-Item ("SendOnBehalf FAILED for " + $Trustee + " - " + $_.Exception.Message) Red
            if (-not $Preview) { $script:failed++ }
        }
    }`;

    const body = `
# --- Access change worker -----------------------------------------
$script:ok = 0
$script:failed = 0

function Invoke-AccessChange {
    param([string]$Trustee, [bool]$Preview)

${fullBlock}

${sendAsBlock}

${onBehalfBlock}
}

# --- Dry run (-WhatIf, nothing changes) ---------------------------
Write-Head "Dry run. Showing what would change. No changes are made yet."
foreach ($t in $Trustees) { Invoke-AccessChange -Trustee $t -Preview $true }

# --- Confirm ------------------------------------------------------
Write-Host ""
$answer = Read-Host "  Type YES to apply these changes for real (anything else aborts)"
if ($answer -ne "YES") {
    Write-Item "Aborted. No changes were made." Yellow
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
    exit 0
}

# --- Live run -----------------------------------------------------
Write-Head "Applying changes..."
foreach ($t in $Trustees) { Invoke-AccessChange -Trustee $t -Preview $false }
`;

    const permNames = [];
    if (ctx.perms.full)     permNames.push("Full Access" + (ctx.autoMapping ? " (AutoMapping on)" : " (AutoMapping off)"));
    if (ctx.perms.sendAs)   permNames.push("Send As");
    if (ctx.perms.onBehalf) permNames.push("Send on Behalf");

    const extraHeader = [
      "#  Permissions : " + (permNames.length ? permNames.join(", ") : "none selected"),
      "#  Users       : " + ctx.identities.length,
    ];

    const summary = 'Write-Item ("Succeeded : " + $script:ok)\nWrite-Item ("Failed    : " + $script:failed)\n';

    return psPrologue(ctx, extraHeader) + inputs + psConnect() + verify + body + psEpilogue(ctx, summary);
  }
```

- [ ] **Step 2: Route shared mailbox through the dispatcher**

In `buildScript`, replace:

```js
    throw new Error("Script generation is not implemented for object type: " + ctx.typeId);
```

with:

```js
    if (ctx.typeId === "shared-mailbox") {
      return crlf(buildMailboxPermissionScript(ctx));
    }
    throw new Error("Script generation is not implemented for object type: " + ctx.typeId);
```

- [ ] **Step 3: Generate and parse-check grant + remove**

```bash
node --check tools/group-import/exo-scripts.js && node "$TEMP/gen-exo.js" smb-grant && node "$TEMP/gen-exo.js" smb-grant-full-only && node "$TEMP/gen-exo.js" smb-remove
pwsh -NoProfile -Command "foreach (\$f in 'smb-grant','smb-grant-full-only','smb-remove') { \$errs=\$null; \$null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path \$env:TEMP (\$f + '.ps1')), [ref]\$null, [ref]\$errs); if (\$errs) { \"FAIL \$f\"; \$errs; exit 1 } else { \"parse OK \$f\" } }"
```
Expected: three `parse OK …` lines.

- [ ] **Step 4: Verify the flags and AutoMapping default rendered correctly**

```bash
grep -n '^\$Do\|^\$AutoMapping\|Permissions :' "$TEMP/smb-grant.ps1"
grep -n '^\$Do\|^\$AutoMapping\|Permissions :' "$TEMP/smb-grant-full-only.ps1"
```
Expected: `smb-grant.ps1` shows `$DoFullAccess = $true`, `$DoSendAs = $true`, `$DoSendOnBehalf = $true`, `$AutoMapping = $true`, and a header line listing all three permissions. `smb-grant-full-only.ps1` shows `$DoSendAs = $false`, `$DoSendOnBehalf = $false`, `$AutoMapping = $false`, header `Full Access (AutoMapping off)`.

- [ ] **Step 5: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin v2: shared mailbox grant/remove access script builder"
```

---

## Task 7: Shared-mailbox access export

Combines `Get-MailboxPermission`, `Get-RecipientPermission`, and `GrantSendOnBehalfTo` into one CSV.

**Files:**
- Modify: `tools/group-import/exo-scripts.js` — add an early export branch inside `buildMailboxPermissionScript`.

- [ ] **Step 1: Add the export branch**

In `buildMailboxPermissionScript`, immediately after the `const verify = \`…\`;` block and **before** `const fullBlock = isGrant`, insert:

```js
    if (ctx.op === "export") {
      const exportBody = `
# --- Export access list -------------------------------------------
Write-Head "Reading access permissions..."
$outFile = Join-Path $PSScriptRoot (${psStr(ctx.logBase + "-" + ctx.targetSlug)} + "-" + $stamp + ".csv")
$rows = New-Object System.Collections.Generic.List[object]

try {
    Get-MailboxPermission -Identity $Mailbox -ErrorAction Stop |
        Where-Object { $_.User -notlike "NT AUTHORITY\\*" -and -not $_.IsInherited -and $_.User -ne $Mailbox } |
        ForEach-Object {
            $rows.Add([pscustomobject]@{
                Mailbox    = $Mailbox
                Trustee    = [string]$_.User
                Permission = (@($_.AccessRights) -join ";")
                Deny       = [bool]$_.Deny
            })
        }
    Write-Item "Mailbox permissions read." Green
} catch {
    Write-Item ("Could not read mailbox permissions. " + $_.Exception.Message) Red
}

try {
    Get-RecipientPermission -Identity $Mailbox -ErrorAction Stop |
        Where-Object { $_.Trustee -ne "NT AUTHORITY\\SELF" } |
        ForEach-Object {
            $rows.Add([pscustomobject]@{
                Mailbox    = $Mailbox
                Trustee    = [string]$_.Trustee
                Permission = (@($_.AccessRights) -join ";")
                Deny       = ($_.AccessControlType -eq "Deny")
            })
        }
    Write-Item "Send As permissions read." Green
} catch {
    Write-Item ("Could not read Send As permissions. " + $_.Exception.Message) Red
}

try {
    foreach ($sob in $mbx.GrantSendOnBehalfTo) {
        $rows.Add([pscustomobject]@{
            Mailbox    = $Mailbox
            Trustee    = [string]$sob
            Permission = "SendOnBehalf"
            Deny       = $false
        })
    }
    Write-Item "Send on Behalf permissions read." Green
} catch {
    Write-Item ("Could not read Send on Behalf permissions. " + $_.Exception.Message) Red
}

if ($rows.Count -eq 0) {
    Write-Item "No explicit access entries found. No CSV was written." Yellow
} else {
    $rows | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
    Write-Item ("Exported " + $rows.Count + " access entries to:") Green
    Write-Item $outFile
}
`;
      return psPrologue(ctx, []) + inputs + psConnect() + verify + exportBody +
             psEpilogue(ctx, 'Write-Item ("Access entries: " + $rows.Count)\n');
    }
```

- [ ] **Step 2: Generate and parse-check**

```bash
node --check tools/group-import/exo-scripts.js && node "$TEMP/gen-exo.js" smb-export
pwsh -NoProfile -Command "\$errs=\$null; \$null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path \$env:TEMP 'smb-export.ps1'), [ref]\$null, [ref]\$errs); if (\$errs) { \$errs; exit 1 } else { 'parse OK' }"
```
Expected: `parse OK`

- [ ] **Step 3: Verify the backslash escaping survived**

```bash
grep -n 'NT AUTHORITY' "$TEMP/smb-export.ps1"
```
Expected exactly two lines, containing `NT AUTHORITY\*` and `NT AUTHORITY\SELF` **with the backslash present**. If the backslash is missing, the JS used `\` instead of `\\` — fix and re-run.

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin v2: shared mailbox access export script"
```

---

## Task 8: Batch launcher + zip bundling

**Files:**
- Modify: `tools/group-import/exo-scripts.js` — add `buildBat` and `buildZip`, extend exports.

- [ ] **Step 1: Add `buildBat`**

Insert after `buildScript`:

```js
  // ── Self-running batch launcher ───────────────────────────────
  function buildBat(ctx) {
    const readOnly = ctx.op === "export";
    const blurb = readOnly
      ? [
          "echo  This connects to Exchange Online and writes a CSV",
          "echo  next to this file. It does not change anything.",
        ]
      : [
          "echo  This connects to Exchange Online, shows a dry run first,",
          "echo  then asks you to type YES before changing anything.",
        ];
    const countLine = readOnly ? "" : "echo  Users     : " + ctx.identities.length + "\n";

    return crlf(`@echo off
echo ==========================================================
echo  ${ctx.title}
echo  Generated by IT Tools Hub
echo ==========================================================
echo.
echo  Target    : ${ctx.target}
echo  Action    : ${ctx.opLabel}
${countLine}echo  Generated : ${ctx.dateOnly}
echo.
${blurb.join("\n")}
echo.
pause
where pwsh.exe >nul 2>nul
if %ERRORLEVEL%==0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0${ctx.scriptName}"
) else (
    echo.
    echo  WARNING: PowerShell 7 not found ^(pwsh.exe^). Falling back to
    echo  Windows PowerShell 5.1. Install PowerShell 7 for best results:
    echo  https://aka.ms/powershell-release?tag=stable
    echo.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0${ctx.scriptName}"
)
pause
`);
  }

  /** Bundle the .ps1 + .bat into one zip Blob. Requires the JSZip global. */
  async function buildZip(ctx) {
    if (typeof JSZip === "undefined") throw new Error("JSZip did not load. Refresh the page and try again.");
    const zip = new JSZip();
    zip.file(ctx.scriptName, buildScript(ctx));
    zip.file(ctx.batName, buildBat(ctx));
    return zip.generateAsync({ type: "blob", compression: "DEFLATE" });
  }
```

- [ ] **Step 2: Export the new functions**

Replace the export block:

```js
  root.ExoScripts = {
    buildContext: buildContext,
    buildScript: buildScript,
    buildBat: buildBat,
    buildZip: buildZip,
    _psStr: psStr,
    _slug: slug,
    _crlf: crlf,
    _psPrologue: psPrologue,
    _psConnect: psConnect,
    _psEpilogue: psEpilogue,
  };
```

- [ ] **Step 3: Verify the bat and the zip in node**

```bash
node --check tools/group-import/exo-scripts.js && node -e "
globalThis.window = globalThis;
globalThis.JSZip = require('./tools/group-import/jszip.min.js');
require('./tools/group-import/exo-scripts.js');
const fs = require('fs');
const ctx = ExoScripts.buildContext({ typeId:'shared-mailbox', typeLabel:'Shared Mailbox', op:'grant', target:'helpdesk@corrohealth.com', targetDisplay:'Help Desk', identities:['a.one@corrohealth.com'], perms:{full:true,sendAs:false,onBehalf:false}, autoMapping:true, tech:'josh@corrohealth.com' });
fs.writeFileSync(process.env.TEMP + '/' + ctx.batName, ExoScripts.buildBat(ctx));
const zip = new JSZip();
zip.file(ctx.scriptName, ExoScripts.buildScript(ctx));
zip.file(ctx.batName, ExoScripts.buildBat(ctx));
zip.generateAsync({ type:'nodebuffer', compression:'DEFLATE' }).then(buf => {
  fs.writeFileSync(process.env.TEMP + '/' + ctx.zipName, buf);
  console.log('zip bytes', buf.length, '->', ctx.zipName);
});
"
```
Expected: a `zip bytes <n> -> Grant-SharedMailboxAccess-Help-Desk-<date>.zip` line with `n` in the low thousands.

- [ ] **Step 4: Confirm the zip contains both files with the right names**

```bash
pwsh -NoProfile -Command "\$z = Get-ChildItem (Join-Path \$env:TEMP 'Grant-SharedMailboxAccess-Help-Desk-*.zip') | Sort-Object LastWriteTime -Descending | Select-Object -First 1; Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::OpenRead(\$z.FullName).Entries | ForEach-Object { \$_.FullName }"
```
Expected:
```
Grant-SharedMailboxAccess.ps1
Run-Grant-SharedMailboxAccess.bat
```

- [ ] **Step 5: Confirm the batch references the exact script filename**

```bash
grep -n 'pwsh.exe\|powershell.exe' "$TEMP/Run-Grant-SharedMailboxAccess.bat"
```
Expected: both lines end with `-File "%~dp0Grant-SharedMailboxAccess.ps1"` (matching `ctx.scriptName` so `%~dp0` resolves inside the extracted folder).

- [ ] **Step 6: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin v2: batch launcher and zip bundling"
```

---

## Task 9: Enable the three Exchange types and fix the Graph kind filter

v1's lookup only distinguished Unified vs non-Unified, so a distribution list would satisfy a "Security Group" lookup. v2 needs four distinct kinds, so replace `isUnified` with a real classifier.

**Files:**
- Modify: `tools/group-import/index.html` — `<head>` script tag, `OBJECT_TYPES`, `isUnified` → `graphKindOf`, `wizLookup` filter, `wizSub` copy.

- [ ] **Step 1: Load the generator module**

In `tools/group-import/index.html`, replace:

```html
<script src="../../shared/auth.js"></script>
<script>
```

with:

```html
<script src="../../shared/auth.js"></script>
<script src="exo-scripts.js"></script>
<script>
```

- [ ] **Step 2: Enable the Exchange types in the registry**

Replace the three Exchange entries in `OBJECT_TYPES`:

```js
  { id:"distribution-list", label:"Distribution List", backend:"exchange", source:"members",
    icon:ICONS.mail, tag:"Script · EXO", enabled:true, graphKind:"distribution",
    ops:["add","remove","export"] },
  { id:"mail-security-group", label:"Mail-enabled Security Group", backend:"exchange", source:"members",
    icon:ICONS.shieldCheck, tag:"Script · EXO", enabled:true, graphKind:"mailSecurity",
    ops:["add","remove","export"] },
  { id:"shared-mailbox", label:"Shared Mailbox", backend:"exchange", source:"permissions",
    icon:ICONS.inbox, tag:"Script · EXO", enabled:true, graphKind:"mailbox",
    ops:["grant","remove","export"] },
```

Also update the comment two lines above the array:

```js
// ── Object-type registry ───────────────────────────────────────
// backend: "graph" (live in browser) | "exchange" (generates a PowerShell script)
// source:  "members" | "permissions"
// graphKind: "security" | "unified" | "distribution" | "mailSecurity" | "mailbox"
```

- [ ] **Step 3: Replace `isUnified` with a four-way classifier**

Replace:

```js
function isUnified(group){ return (group.groupTypes || []).includes("Unified"); }
```

with:

```js
// Graph can READ all four group kinds; only the Graph-native two can be written here.
function graphKindOf(group) {
  if ((group.groupTypes || []).includes("Unified")) return "unified";
  if (group.mailEnabled && group.securityEnabled)   return "mailSecurity";
  if (group.mailEnabled && !group.securityEnabled)  return "distribution";
  return "security";
}
const KIND_LABELS = {
  unified:      "Microsoft 365 group",
  security:     "Entra security group",
  distribution: "distribution list",
  mailSecurity: "mail-enabled security group",
};
```

- [ ] **Step 4: Update `wizLookup` to use the classifier**

Replace the whole body of `wizLookup` (currently the `async function wizLookup() { … }` block) with:

```js
async function wizLookup() {
  const input = document.getElementById("wGroupIn").value.trim();
  const err = document.getElementById("wErr");
  if (!input) { err.textContent = "Enter a name, email address, or GUID."; err.style.display="block"; return; }
  err.style.display = "none";
  const t = getType(wiz.typeId);
  const wantKind = t.graphKind;
  const select = "id,displayName,mail,groupTypes,mailEnabled,securityEnabled";
  try {
    await ITTools.ui.withButtonSpinner(document.getElementById("wLookupBtn"), async () => {
      let group;
      if (/^[0-9a-f-]{36}$/i.test(input)) {
        group = await ITTools.graph.get(`/groups/${input}?$select=${select}`);
        const got = graphKindOf(group);
        if (got !== wantKind)
          throw new Error(`That group is a ${KIND_LABELS[got]}, not a ${t.label.toLowerCase()}.`);
      } else {
        const esc = input.replace(/'/g, "''");
        const byEmail = input.includes("@");
        const field = byEmail ? "mail" : "displayName";
        const res = await ITTools.graph.get(`/groups?$filter=${field} eq '${encodeURIComponent(esc)}'&$select=${select}&$count=true&$top=20`);
        const matches = (res.value || []).filter(g => graphKindOf(g) === wantKind);
        if (!matches.length) throw new Error(`No ${t.label.toLowerCase()} found ${byEmail ? `with email "${input}"` : `named "${input}"`}.`);
        group = matches[0];
      }
      wiz.groupId        = group.id;
      wiz.groupName      = group.displayName;
      wiz.targetIdentity = group.mail || group.displayName;
      wiz.targetVerified = true;
      document.getElementById("wGroupOkName").textContent = group.displayName;
      document.getElementById("wGroupOkId").textContent   = wiz.targetIdentity + "  ·  " + group.id;
      document.getElementById("wGroupOk").style.display   = "block";
      document.getElementById("wTargetNext").disabled     = false;
    }, "Looking up…", [document.getElementById("wGroupIn")]);
  } catch(e) {
    err.textContent = ITTools.graph.friendlyError(e); err.style.display = "block";
    wiz.groupId = ""; wiz.targetIdentity = ""; wiz.targetVerified = false;
    const manual = document.getElementById("wManualWrap");
    if (manual) manual.style.display = "block";
  }
}
```

- [ ] **Step 5: Extend the wizard state**

Replace the `const wiz = {…}` declaration:

```js
const wiz = { typeId:"", op:"", groupId:"", groupName:"", targetIdentity:"", targetVerified:false,
              identifiers:[], validIdentifiers:[], perms:{ full:true, sendAs:false, onBehalf:false },
              autoMapping:true, csvName:"", dryDone:false, lastLog:[] };
```

And in `openWizard`, replace the `Object.assign(wiz, {…})` line:

```js
  Object.assign(wiz, { typeId, op:"", groupId:"", groupName:"", targetIdentity:"", targetVerified:false,
                       identifiers:[], validIdentifiers:[], perms:{ full:true, sendAs:false, onBehalf:false },
                       autoMapping:true, csvName:"", dryDone:false, lastLog:[] });
```

- [ ] **Step 6: Backend-aware subtitle**

In `openWizard`, replace:

```js
  document.getElementById("wizSub").textContent   = "Add, remove, or export members (live via Microsoft Graph).";
```

with:

```js
  document.getElementById("wizSub").textContent = t.backend === "graph"
    ? "Add, remove, or export members, live via Microsoft Graph."
    : (t.source === "permissions"
        ? "Build a PowerShell script that grants, removes, or exports shared mailbox access in Exchange Online."
        : "Build a PowerShell script that adds, removes, or exports members in Exchange Online.");
```

- [ ] **Step 7: Drop the "coming soon" copy**

Replace the launcher header paragraph (`tools/group-import/index.html`, inside `#launcher`):

```html
          <p>Pick what you're working with. Security and Microsoft 365 groups run live here; the Exchange types generate a PowerShell script you download and run yourself.</p>
```

Replace the first sidebar tip body:

```html
        Add, remove, or export members of Entra security groups and Microsoft 365 groups live via Microsoft Graph. Distribution lists, mail-enabled security groups, and shared mailbox access download as a ready-to-run PowerShell script.
```

Replace the auth-screen paragraph:

```html
    <p>Sign in with your M365 admin account to manage group members and shared mailbox access.</p>
```

- [ ] **Step 8: Syntax check the inline script**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('tools/group-import/index.html','utf8');const m=h.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/);fs.writeFileSync(process.env.TEMP+'/ga_v2.js',m[1]);" && node --check "$TEMP/ga_v2.js" && echo "JS OK"
```
Expected: `JS OK`

- [ ] **Step 9: Confirm `isUnified` is fully gone**

```bash
grep -n 'isUnified' tools/group-import/index.html
```
Expected: no output (exit code 1). If any line prints, replace that call with `graphKindOf(...)` and re-run Step 8.

- [ ] **Step 10: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin v2: enable Exchange types, four-way Graph kind filter"
```

---

## Task 10: Registry-driven action step

The action step currently hardcodes three "members" cards. Drive it from `t.ops` + `t.source` so the shared mailbox gets access wording.

**Files:**
- Modify: `tools/group-import/index.html` — replace `renderActionStep`.

- [ ] **Step 1: Replace `renderActionStep`**

Replace the existing `function renderActionStep() { … }` with:

```js
const OP_META = {
  members: {
    add:    { label:"Add members",    hint:"Import a CSV of members into this group",  icon:"userPlus"  },
    remove: { label:"Remove members", hint:"Remove a CSV of members from this group",  icon:"userMinus" },
    export: { label:"Export members", hint:"Download the current membership as CSV",   icon:"download"  },
  },
  permissions: {
    grant:  { label:"Grant access",       hint:"Give users access to this mailbox",     icon:"userPlus"  },
    remove: { label:"Remove access",      hint:"Take access away from users",           icon:"userMinus" },
    export: { label:"Export access list", hint:"List who has access to this mailbox",   icon:"download"  },
  },
};

function renderActionStep() {
  wiz.op = "";
  const t = getType(wiz.typeId);
  const meta = OP_META[t.source];
  document.getElementById("wizBody").innerHTML = `
    <div class="card">
      <div class="card-title">What do you want to do?</div>
      <div class="type-grid">
        ${t.ops.map(op => `
        <div class="type-card" onclick="chooseOp('${op}')">
          <div class="type-icon">${ICONS[meta[op].icon]}</div>
          <div class="type-name">${meta[op].label}</div>
          <p class="step-sub">${meta[op].hint}</p>
        </div>`).join("")}
      </div>
    </div>`;
}
```

- [ ] **Step 2: Syntax check**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('tools/group-import/index.html','utf8');const m=h.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/);fs.writeFileSync(process.env.TEMP+'/ga_v2.js',m[1]);" && node --check "$TEMP/ga_v2.js" && echo "JS OK"
```
Expected: `JS OK`

- [ ] **Step 3: Manual verification**

Push to preview (`git push origin testing`), sign in, and check: **Security Group** still shows Add members / Remove members / Export members (unchanged from v1); **Shared Mailbox** shows Grant access / Remove access / Export access list. Icons are Lucide SVGs, not emoji.

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin v2: registry-driven action step"
```

---

## Task 11: Exchange target step with Graph verification and manual fallback

Graph can *read* DLs, mail-enabled security groups, and the user objects behind shared mailboxes, so the lookup is reused for verification. It can never write them, so the generated script re-verifies with `Get-DistributionGroup` / `Get-Mailbox` at run time and a manual-entry fallback is always offered.

**Files:**
- Modify: `tools/group-import/index.html` — replace `renderTargetStep`, add `mailboxLookup`, `useTargetAsTyped`, replace `afterTarget`.

- [ ] **Step 1: Replace `renderTargetStep`**

```js
function renderTargetStep() {
  const t = getType(wiz.typeId);
  const isMailbox = t.graphKind === "mailbox";
  const lbl = isMailbox ? "Mailbox email address" : "Name, email address, or GUID";
  const ph  = isMailbox
    ? "e.g. helpdesk@corrohealth.com"
    : (t.graphKind === "security" ? "e.g. IT-Security-Team or a GUID" : "e.g. IT All, it-all@corrohealth.com, or a GUID");
  const lookupFn = isMailbox ? "mailboxLookup()" : "wizLookup()";
  const manualBlock = t.backend === "exchange" ? `
      <div id="wManualWrap" style="display:none;margin-top:10px">
        <div class="banner warn" style="display:block">Not found in Entra ID. You can still continue with the identity exactly as typed. The generated script verifies it in Exchange Online before it changes anything.</div>
        <button class="btn btn-secondary" style="margin-top:8px" onclick="useTargetAsTyped()">Use the identity as typed</button>
      </div>` : "";
  document.getElementById("wizBody").innerHTML = `
    <div class="banner error" id="wErr" style="display:none"></div>
    <div class="card">
      <div class="card-title">Target ${t.label.toLowerCase()}</div>
      <div class="field"><label class="field-label">${lbl}</label>
        <div class="input-row">
          <input type="text" id="wGroupIn" placeholder="${ph}" onkeydown="if(event.key==='Enter')${lookupFn}"/>
          <button class="btn btn-secondary" id="wLookupBtn" onclick="${lookupFn}" style="white-space:nowrap">Look up</button>
        </div>
      </div>
      <div class="group-ok" id="wGroupOk"><div class="group-ok-name" id="wGroupOkName"></div><div class="group-ok-id" id="wGroupOkId"></div></div>${manualBlock}
    </div>
    <div class="btn-row">
      <button class="btn btn-ghost" onclick="renderActionStep()">← Back</button>
      <button class="btn btn-primary" id="wTargetNext" onclick="afterTarget()" disabled>Continue →</button>
    </div>`;
}
```

- [ ] **Step 2: Add the mailbox lookup**

Insert directly after `wizLookup`:

```js
// Shared mailboxes exist in Entra as (disabled) user objects, so Graph can read them.
// Graph exposes no mailbox-type field, so "is it really shared" is checked by the
// generated script via Get-Mailbox -RecipientTypeDetails.
async function mailboxLookup() {
  const input = document.getElementById("wGroupIn").value.trim();
  const err = document.getElementById("wErr");
  if (!input) { err.textContent = "Enter the mailbox email address."; err.style.display="block"; return; }
  err.style.display = "none";
  try {
    await ITTools.ui.withButtonSpinner(document.getElementById("wLookupBtn"), async () => {
      let user = null;
      const r = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(input)}?$select=id,displayName,mail,userPrincipalName`,
        { headers: { Authorization: "Bearer " + (await ITTools.auth.getToken()) } });
      if (r.ok) {
        user = await r.json();
      } else {
        const esc = input.replace(/'/g, "''");
        const res = await ITTools.graph.get(`/users?$filter=mail eq '${encodeURIComponent(esc)}'&$select=id,displayName,mail,userPrincipalName`);
        user = (res.value || [])[0] || null;
      }
      if (!user) throw new Error(`No mailbox found for "${input}".`);
      wiz.groupId        = user.id;
      wiz.groupName      = user.displayName || input;
      wiz.targetIdentity = user.mail || user.userPrincipalName || input;
      wiz.targetVerified = true;
      document.getElementById("wGroupOkName").textContent = wiz.groupName;
      document.getElementById("wGroupOkId").textContent   = wiz.targetIdentity;
      document.getElementById("wGroupOk").style.display   = "block";
      document.getElementById("wManualWrap").style.display = "none";
      document.getElementById("wTargetNext").disabled     = false;
    }, "Looking up…", [document.getElementById("wGroupIn")]);
  } catch(e) {
    err.textContent = ITTools.graph.friendlyError(e); err.style.display = "block";
    wiz.groupId = ""; wiz.targetIdentity = ""; wiz.targetVerified = false;
    document.getElementById("wManualWrap").style.display = "block";
  }
}

const TARGET_RE = /^[A-Za-z0-9][A-Za-z0-9 ._'()-]{1,63}(@[^\s@]+\.[A-Za-z]{2,})?$/;

function useTargetAsTyped() {
  const input = document.getElementById("wGroupIn").value.trim();
  const err = document.getElementById("wErr");
  if (!TARGET_RE.test(input)) {
    err.textContent = "That does not look like a valid name or email address. Fix it before continuing.";
    err.style.display = "block";
    return;
  }
  err.style.display = "none";
  wiz.groupId        = "";
  wiz.groupName      = input;
  wiz.targetIdentity = input;
  wiz.targetVerified = false;
  document.getElementById("wGroupOkName").textContent = input;
  document.getElementById("wGroupOkId").textContent   = "Not verified in Entra ID. The script verifies it in Exchange Online.";
  document.getElementById("wGroupOk").style.display   = "block";
  document.getElementById("wTargetNext").disabled     = false;
}
```

- [ ] **Step 3: Replace `afterTarget` with the full router**

```js
function afterTarget() {
  const t = getType(wiz.typeId);
  if (!wiz.targetIdentity) return;
  if (wiz.op === "export") {
    if (t.backend === "exchange") renderGenerateStep(); else renderRunStep();
    return;
  }
  if (t.source === "permissions") { renderPermStep(); return; }
  renderSourceStep();
}
```

`renderPermStep` arrives in Task 12 and `renderGenerateStep` in Task 14; the Graph paths keep working throughout.

- [ ] **Step 4: Syntax check**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('tools/group-import/index.html','utf8');const m=h.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/);fs.writeFileSync(process.env.TEMP+'/ga_v2.js',m[1]);" && node --check "$TEMP/ga_v2.js" && echo "JS OK"
```
Expected: `JS OK`

- [ ] **Step 5: Manual verification**

Push to preview. Check:
- **Distribution List → Add members** → look up a real DL by name and by its SMTP address. Expect the green confirmation showing display name plus the SMTP address used as the script identity.
- Look up a known **security** group under Distribution List. Expect "That group is a … , not a distribution list." or "No distribution list found named …".
- Type a nonsense name and look it up. Expect the amber banner and the "Use the identity as typed" button, which enables Continue with the "Not verified in Entra ID" note.
- **Security Group → Add members** still resolves exactly as it did in v1.

- [ ] **Step 6: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin v2: Exchange target step with Graph verify and manual fallback"
```

---

## Task 12: Shared-mailbox permission step

**Files:**
- Modify: `tools/group-import/index.html` — add `renderPermStep`, `permChanged`, `permNext`.

- [ ] **Step 1: Add the step**

Insert immediately after `useTargetAsTyped`:

```js
// ── Permission type step (shared mailbox only) ──────────────────
function renderPermStep() {
  const isGrant = wiz.op === "grant";
  const verb = isGrant ? "grant" : "remove";
  document.getElementById("wizBody").innerHTML = `
    <div class="banner error" id="pErr" style="display:none"></div>
    <div class="card">
      <div class="card-title">Permission type</div>
      <p style="font-size:13px;color:var(--muted);margin-bottom:10px">Pick every permission to ${verb}. You can select more than one.</p>
      <div class="checkbox-group">
        <label class="checkbox-label"><input type="checkbox" id="permFull" ${wiz.perms.full?"checked":""} onchange="permChanged()"/> Full Access <span class="muted text-xs">&nbsp;open the mailbox and read its mail</span></label>
        <label class="checkbox-label"><input type="checkbox" id="permSendAs" ${wiz.perms.sendAs?"checked":""} onchange="permChanged()"/> Send As <span class="muted text-xs">&nbsp;send mail as the mailbox itself</span></label>
        <label class="checkbox-label"><input type="checkbox" id="permOnBehalf" ${wiz.perms.onBehalf?"checked":""} onchange="permChanged()"/> Send on Behalf <span class="muted text-xs">&nbsp;recipients see it was sent on behalf of the mailbox</span></label>
      </div>
    </div>
    <div class="card" id="autoCard" style="display:none">
      <div class="card-title">AutoMapping</div>
      <p style="font-size:13px;color:var(--muted);margin-bottom:10px">Full Access only. When this is on, the mailbox appears in Outlook automatically for each user. Leave it on unless this mailbox is known to cause Outlook mapping problems.</p>
      <label class="checkbox-label"><input type="checkbox" id="permAuto" ${wiz.autoMapping?"checked":""} onchange="permChanged()"/> Add the mailbox to Outlook automatically</label>
    </div>
    <div class="btn-row">
      <button class="btn btn-ghost" onclick="renderTargetStep()">← Back</button>
      <button class="btn btn-primary" id="permNextBtn" onclick="permNext()">Continue →</button>
    </div>`;
  permChanged();
}

function permChanged() {
  wiz.perms.full     = document.getElementById("permFull").checked;
  wiz.perms.sendAs   = document.getElementById("permSendAs").checked;
  wiz.perms.onBehalf = document.getElementById("permOnBehalf").checked;
  const autoEl = document.getElementById("permAuto");
  if (autoEl) wiz.autoMapping = autoEl.checked;
  document.getElementById("autoCard").style.display = wiz.perms.full ? "block" : "none";
  const any = wiz.perms.full || wiz.perms.sendAs || wiz.perms.onBehalf;
  document.getElementById("permNextBtn").disabled = !any;
}

function permNext() {
  if (!(wiz.perms.full || wiz.perms.sendAs || wiz.perms.onBehalf)) {
    showErr("pErr", "Pick at least one permission type.");
    return;
  }
  renderSourceStep();
}
```

Note: the target step's Back button returns to `renderTargetStep` and the wizard's own "← All object types" resets state, so no extra teardown is needed.

- [ ] **Step 2: Syntax check**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('tools/group-import/index.html','utf8');const m=h.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/);fs.writeFileSync(process.env.TEMP+'/ga_v2.js',m[1]);" && node --check "$TEMP/ga_v2.js" && echo "JS OK"
```
Expected: `JS OK`

- [ ] **Step 3: Manual verification**

Push to preview. **Shared Mailbox → Grant access → target a test mailbox → Continue.** Expect: Full Access pre-checked, the AutoMapping card visible with its box checked (default ON per the spec). Untick Full Access: the AutoMapping card hides. Untick all three: Continue disables. Re-tick Send As only: Continue enables, AutoMapping card stays hidden.

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin v2: shared mailbox permission type step with AutoMapping"
```

---

## Task 13: CSV source step routing and identity validation

**Files:**
- Modify: `tools/group-import/index.html` — replace `renderSourceStep` and `sourceNext`, add `validateIdentities`.

- [ ] **Step 1: Replace `renderSourceStep`**

```js
// ── Source CSV step (add / remove / grant) ──────────────────────
function sourceTitle() {
  const t = getType(wiz.typeId);
  if (t.source === "permissions") return wiz.op === "grant" ? "Users to grant access (CSV)" : "Users to remove access (CSV)";
  return wiz.op === "add" ? "Members to add (CSV)" : "Members to remove (CSV)";
}

function renderSourceStep() {
  const t = getType(wiz.typeId);
  const backFn   = t.source === "permissions" ? "renderPermStep()" : "renderTargetStep()";
  const nextText = t.backend === "exchange" ? "Continue to Generate →" : "Continue to Run →";
  document.getElementById("wizBody").innerHTML = `
    <div class="banner error" id="s1Err" style="display:none"></div>
    <div class="card">
      <div class="card-title">${sourceTitle()}</div>
      <div class="file-drop" id="fileDrop" ondragover="dragOver(event)" ondragleave="dragLeave(event)" ondrop="dropFile(event)">
        <div class="file-drop-idle"><div style="margin-bottom:8px;color:var(--muted2);display:flex;justify-content:center"><svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg></div>
          <p>Drag &amp; drop your CSV, or <strong onclick="document.getElementById('fileIn').click()">browse</strong></p></div>
        <div class="file-drop-busy"><span class="spinner" style="width:14px;height:14px;border-width:2px"></span> Reading file…</div>
        <input type="file" id="fileIn" accept=".csv" onchange="handleFile(event)"/>
      </div>
      <div class="file-loaded" id="fileLoaded" style="display:none"><span style="font-size:16px">✅</span>
        <span class="file-loaded-name" id="fileName"></span><span class="file-loaded-count" id="fileCount"></span>
        <button class="file-loaded-clear" onclick="clearFile()">✕</button></div>
    </div>
    <div class="card" id="colCard" style="display:none">
      <div class="card-title">Identifier column</div>
      <p style="font-size:13px;color:var(--muted);margin-bottom:10px">Select the column with email addresses or UPNs. Auto-detected columns are marked ✦.</p>
      <div class="col-pills" id="colPills"></div>
      <div id="previewWrap" style="display:none;margin-top:12px"><div class="preview-list" id="previewList"></div></div>
    </div>
    <div class="btn-row">
      <button class="btn btn-ghost" onclick="${backFn}">← Back</button>
      <button class="btn btn-primary" id="s1Btn" onclick="sourceNext()" disabled>${nextText}</button>
    </div>`;
}
```

- [ ] **Step 2: Add validation and replace `sourceNext`**

```js
// Exchange scripts cannot resolve a typo the way the live Graph path can, so
// identities are format-validated in the browser before a script is generated.
const IDENTITY_RE = /^[^\s@,;]+@[^\s@,;]+\.[A-Za-z]{2,}$/;

function validateIdentities(list) {
  const valid = [], invalid = [];
  (list || []).forEach(v => (IDENTITY_RE.test(v) ? valid : invalid).push(v));
  return { valid, invalid };
}

function sourceNext() {
  wiz.identifiers = getPrimed();
  if (!wiz.identifiers.length) { showErr("s1Err","No identifiers found."); return; }
  const t = getType(wiz.typeId);
  if (t.backend === "exchange") renderGenerateStep(); else renderRunStep();
}
```

- [ ] **Step 3: Syntax check plus a validation spot-check**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('tools/group-import/index.html','utf8');const m=h.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/);fs.writeFileSync(process.env.TEMP+'/ga_v2.js',m[1]);" && node --check "$TEMP/ga_v2.js" && echo "JS OK"
node -e "
const RE = /^[^\s@,;]+@[^\s@,;]+\.[A-Za-z]{2,}$/;
const cases = ['a.one@corrohealth.com','bad-no-at','two@@x.com','has space@x.com','ok@sub.corrohealth.co.uk'];
cases.forEach(c => console.log(RE.test(c), c));
"
```
Expected: `JS OK`, then `true / false / false / false / true` in that order.

- [ ] **Step 4: Manual verification**

Push to preview. **Distribution List → Add members → target → CSV step.** Expect the file drop, auto-detected identifier column, preview, and a Continue button reading "Continue to Generate →". For **Security Group → Add members** the button still reads "Continue to Run →". For **Shared Mailbox → Grant access** the card title reads "Users to grant access (CSV)" and Back returns to the permission step.

- [ ] **Step 5: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin v2: CSV step routing, wording, and identity validation"
```

---

## Task 14: Generate step with script preview and zip download

**Files:**
- Modify: `tools/group-import/index.html` — add the small-icon set, the `.script-pre` style, `exoContext`, `renderGenerateStep`, `downloadScriptBundle`.

- [ ] **Step 1: Add the preview style**

Add to the `<style>` block, after the `.type-tag.script` rule:

```css
  /* ── Generated script preview ── */
  .script-pre  { max-height:320px; overflow:auto; background:var(--surface3); border:1px solid var(--border); border-radius:8px; padding:12px; font-family:'Cascadia Code','Consolas',monospace; font-size:11px; line-height:1.5; white-space:pre; margin:0; }
  .gen-files   { display:flex; flex-direction:column; gap:6px; font-size:12px; color:var(--muted); margin-top:10px; }
```

- [ ] **Step 2: Add a small-size Lucide icon set**

Insert directly after the existing `const ICONS = { … };` block:

```js
const _svgSm = p => `<svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-2px;margin-right:6px">${p}</svg>`;
const ICONS_SM = {
  download: _svgSm(`<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/>`),
  fileText: _svgSm(`<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M16 13H8"/><path d="M16 17H8"/><path d="M10 9H8"/>`),
  terminal: _svgSm(`<polyline points="4 17 10 11 4 5"/><line x1="12" x2="20" y1="19" y2="19"/>`),
};
```

- [ ] **Step 3: Add the Generate step**

Insert after `runExport()`:

```js
// ── Generate step (Exchange types) ──────────────────────────────
function exoContext() {
  const t = getType(wiz.typeId);
  const acct = ITTools.auth.getAccount();
  return ExoScripts.buildContext({
    typeId:        wiz.typeId,
    typeLabel:     t.label,
    op:            wiz.op,
    target:        wiz.targetIdentity,
    targetDisplay: wiz.groupName || wiz.targetIdentity,
    identities:    wiz.validIdentifiers,
    perms:         { full: wiz.perms.full, sendAs: wiz.perms.sendAs, onBehalf: wiz.perms.onBehalf },
    autoMapping:   wiz.autoMapping,
    tech:          (acct && acct.username) || "unknown",
  });
}

function renderGenerateStep() {
  const t = getType(wiz.typeId);
  const isExport = wiz.op === "export";
  const checked  = isExport ? { valid: [], invalid: [] } : validateIdentities(wiz.identifiers);
  wiz.validIdentifiers = checked.valid;

  const permNames = [];
  if (wiz.perms.full)     permNames.push("Full Access" + (wiz.autoMapping ? " (AutoMapping on)" : " (AutoMapping off)"));
  if (wiz.perms.sendAs)   permNames.push("Send As");
  if (wiz.perms.onBehalf) permNames.push("Send on Behalf");

  const backFn = isExport
    ? "renderTargetStep()"
    : "renderSourceStep()";

  const invalidBlock = checked.invalid.length ? `
    <div class="banner warn" style="display:block">
      ${checked.invalid.length} row(s) are not valid email addresses and are left out of the script:
      <span class="mono text-xs">${checked.invalid.slice(0, 10).join(", ")}${checked.invalid.length > 10 ? ", …" : ""}</span>
    </div>` : "";

  const unverifiedBlock = wiz.targetVerified ? "" : `
    <div class="banner warn" style="display:block">The target was not verified in Entra ID. The script verifies it in Exchange Online with a lookup before it changes anything.</div>`;

  document.getElementById("wizBody").innerHTML = `
    ${unverifiedBlock}${invalidBlock}
    <div class="banner error" id="genErr" style="display:none"></div>
    <div class="card"><div class="card-title">Summary</div>
      <div class="run-summary">
        <div class="run-summary-item"><span>Object type</span><span>${t.label}</span></div>
        <div class="run-summary-item"><span>Action</span><span>${OP_META[t.source][wiz.op].label}</span></div>
        <div class="run-summary-item"><span>Target</span><span style="color:var(--blue-dark)">${wiz.groupName}</span></div>
        <div class="run-summary-item"><span>Identity used</span><span class="mono text-xs">${wiz.targetIdentity}</span></div>
        ${isExport ? "" : `<div class="run-summary-item"><span>${t.source === "permissions" ? "Users" : "Members"}</span><span>${checked.valid.length}</span></div>`}
        ${t.source === "permissions" && !isExport ? `<div class="run-summary-item"><span>Permissions</span><span>${permNames.join(", ")}</span></div>` : ""}
      </div>
      <div class="gen-files">
        <div>${ICONS_SM.fileText}<span class="mono text-xs">${"" /* filled in below */}</span></div>
      </div>
    </div>
    <div class="card">
      <div class="card-title">${ICONS_SM.terminal}Generated script</div>
      <pre class="script-pre" id="scriptPreview"></pre>
    </div>
    <div class="btn-row">
      <button class="btn btn-ghost" onclick="${backFn}">← Back</button>
      <button class="btn btn-success" id="genBtn" onclick="downloadScriptBundle()">${ICONS_SM.download}Download script bundle (.zip)</button>
    </div>`;

  if (!isExport && !checked.valid.length) {
    showErr("genErr", "None of the CSV rows are valid email addresses. Fix the CSV and upload it again.");
    document.getElementById("genBtn").disabled = true;
    document.getElementById("scriptPreview").textContent = "";
    return;
  }

  let ctx;
  try {
    ctx = exoContext();
    document.getElementById("scriptPreview").textContent = ExoScripts.buildScript(ctx);
    document.querySelector(".gen-files").innerHTML =
      `<div>${ICONS_SM.fileText}<span class="mono text-xs">${ctx.scriptName}</span></div>` +
      `<div>${ICONS_SM.terminal}<span class="mono text-xs">${ctx.batName}</span></div>` +
      `<div>${ICONS_SM.download}<span class="mono text-xs">${ctx.zipName}</span></div>`;
  } catch(e) {
    showErr("genErr", "Could not build the script: " + e.message);
    document.getElementById("genBtn").disabled = true;
  }
}

async function downloadScriptBundle() {
  const btn = document.getElementById("genBtn");
  const label = btn.innerHTML;
  btn.disabled = true;
  btn.textContent = "Building…";
  try {
    const ctx  = exoContext();
    const blob = await ExoScripts.buildZip(ctx);
    const url  = URL.createObjectURL(blob);
    const a    = Object.assign(document.createElement("a"), { href: url, download: ctx.zipName });
    a.click();
    URL.revokeObjectURL(url);
    btn.innerHTML = label;
    btn.disabled = false;
  } catch(e) {
    showErr("genErr", "Could not build the script bundle: " + e.message);
    btn.innerHTML = label;
    btn.disabled = false;
  }
}
```

- [ ] **Step 4: Syntax check**

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('tools/group-import/index.html','utf8');const m=h.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/);fs.writeFileSync(process.env.TEMP+'/ga_v2.js',m[1]);" && node --check "$TEMP/ga_v2.js" && echo "JS OK"
```
Expected: `JS OK`

- [ ] **Step 5: Manual verification (in-browser generation)**

Push to preview. For each of the six write paths (DL add/remove, mail-SG add/remove, Shared Mailbox grant/remove) and the three exports, reach the Generate step and confirm:
- The summary shows the right object type, action, target, identity, count, and (shared mailbox) the permission list including the AutoMapping state.
- The script preview is readable PowerShell with the header comment naming the target, operation, timestamp, and your own UPN.
- The three filenames listed match the pattern in the preview header.
- Clicking **Download script bundle (.zip)** downloads a zip containing exactly the `.ps1` and the `Run-*.bat`, and the button returns to its normal label so it can be clicked again.
- Feed a CSV with one bad row (e.g. `not-an-email`). Expect the amber "not valid email addresses" banner and a member count one lower than the CSV row count.

- [ ] **Step 6: Commit**

```bash
git add tools/group-import/index.html
git commit -m "Group Admin v2: generate step with script preview and zip download"
```

---

## Task 15: Update the hub card description

**Files:**
- Modify: `config.json` (the `group-import` object, currently `config.json:16-25`)

- [ ] **Step 1: Replace the description**

Change only the `description` value of the `group-import` entry to:

```json
      "description": "Add, remove, and export members across Entra security groups, Microsoft 365 groups, distribution lists, and mail-enabled security groups, plus shared mailbox access. Graph types run live in the browser; Exchange types download a ready-to-run PowerShell script.",
```

Leave `id`, `name`, `icon`, `status`, `path`, `permissions`, `accent`, and `category` exactly as they are. No new Graph scopes are needed: `Group.ReadWrite.All` and `Directory.Read.All` already grant the read-only lookups this feature uses, and every Exchange write happens in the tech's own PowerShell session.

- [ ] **Step 2: Verify the JSON still parses**

```bash
node -e "JSON.parse(require('fs').readFileSync('config.json','utf8')); console.log('config.json OK')"
```
Expected: `config.json OK`

- [ ] **Step 3: Confirm no em dashes crept in**

```bash
grep -n '—' config.json
```
Expected: no output (exit code 1).

- [ ] **Step 4: Commit**

```bash
git add config.json
git commit -m "Group Admin v2: update hub card description"
```

---

## Task 16: Changelog entry and hub version bump

Standing repo rule: the changelog entry and version bump ship in the same push as the code.

**Files:**
- Modify: `changelog.json:2-10` (prepend a new entry)
- Modify: `index.html:625` (hub footer)

- [ ] **Step 1: Prepend the changelog entry**

In `changelog.json`, insert a new object as the first element of `entries`, directly after `"entries": [`:

```json
    {
      "version": "2.4.0",
      "date": "2026-08-28",
      "notes": [
        "Group Administration: distribution lists and mail-enabled security groups can now add, remove, and export members",
        "Group Administration: shared mailbox access for Full Access, Send As, and Send on Behalf, with an AutoMapping toggle",
        "Group Administration: Exchange actions download a PowerShell script plus a double-click launcher in one zip, with a dry run before any change"
      ]
    },
```

- [ ] **Step 2: Bump the hub footer version**

In the repo-root `index.html`, replace:

```html
  <span>Built by Josh Garrett &middot; v2.3.4</span>
```

with:

```html
  <span>Built by Josh Garrett &middot; v2.4.0</span>
```

- [ ] **Step 3: Verify**

```bash
node -e "const c=JSON.parse(require('fs').readFileSync('changelog.json','utf8')); console.log(c.entries[0].version, c.entries[0].notes.length);"
grep -n 'v2.4.0' index.html
```
Expected: `2.4.0 3`, and one matching footer line in `index.html`.

- [ ] **Step 4: Commit**

```bash
git add changelog.json index.html
git commit -m "Group Admin v2: changelog 2.4.0 and hub version bump"
```

---

## Task 17: Full-file verification sweep

One consolidated check before the manual matrix, so a syntax or naming slip cannot reach the functional test.

**Files:**
- No changes; verification only.

- [ ] **Step 1: Check every JS file**

```bash
node --check tools/group-import/exo-scripts.js && node --check tools/group-import/jszip.min.js && \
node -e "const fs=require('fs');const h=fs.readFileSync('tools/group-import/index.html','utf8');const m=h.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/);fs.writeFileSync(process.env.TEMP+'/ga_v2.js',m[1]);" && node --check "$TEMP/ga_v2.js" && echo "ALL JS OK"
```
Expected: `ALL JS OK`

- [ ] **Step 2: Parse-check all nine generated script shapes**

```bash
for c in dl-add dl-remove dl-export msg-add msg-export smb-grant smb-grant-full-only smb-remove smb-export; do node "$TEMP/gen-exo.js" "$c" || exit 1; done
pwsh -NoProfile -Command "foreach (\$f in 'dl-add','dl-remove','dl-export','msg-add','msg-export','smb-grant','smb-grant-full-only','smb-remove','smb-export') { \$errs=\$null; \$null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path \$env:TEMP (\$f + '.ps1')), [ref]\$null, [ref]\$errs); if (\$errs) { \"FAIL \$f\"; \$errs; exit 1 } else { \"parse OK \$f\" } }"
```
Expected: nine `parse OK …` lines. (If `$TEMP/gen-exo.js` is missing because this task runs in a fresh shell, re-create it with the heredoc from Task 4 Step 3.)

- [ ] **Step 3: Check for banned characters in UI-facing copy**

```bash
grep -n '—' tools/group-import/index.html tools/group-import/exo-scripts.js config.json changelog.json
```
Expected: no output. Em dashes are banned in hub-facing copy.

- [ ] **Step 4: Confirm no emoji or unicode glyphs were added as icons**

```bash
grep -n 'type-icon\|ICONS_SM\.' tools/group-import/index.html | head -20
```
Expected: every `type-icon` div and every small-icon usage renders an `ICONS.*` / `ICONS_SM.*` Lucide SVG. The three pre-existing v1 glyphs in the CSV card (`✅`, `✕`, `✦`) are untouched legacy and out of scope here.

- [ ] **Step 5: Confirm no new Graph scopes**

```bash
grep -n 'TOOL_SCOPES' tools/group-import/index.html
```
Expected: exactly the v1 list `["User.Read.All","Group.ReadWrite.All","GroupMember.ReadWrite.All","Directory.Read.All"]`. If a new scope was added, remove it: the Exchange paths must never need one.

- [ ] **Step 6: Push to preview**

```bash
git push origin testing
```

---

## Task 18: Manual functional matrix (the real test)

This is the actual functional verification for this feature. There is no automated substitute in this codebase: the cmdlets only run inside a real Exchange Online session.

**Prerequisites:** a disposable test distribution list, a disposable test mail-enabled security group, a disposable test shared mailbox, two test user accounts, and a 3-row CSV of their addresses (with one deliberately bad row for the validation check).

**Files:**
- No changes; testing only.

- [ ] **Step 1: Distribution List matrix**

| Operation | Steps | Expected |
|---|---|---|
| Add members | Generate zip, extract, double-click the `.bat` | Dry run lists `WOULD ADD` per member, no change in EXO yet; typing `YES` adds them; `ADDED` per member; transcript `.log` written beside the script |
| Add members (abort) | Re-run, type anything except `YES` | "Aborted. No changes were made." and no change in EXO |
| Remove members | Generate, run, confirm | `WOULD REMOVE` then `REMOVED`; members gone from the DL in the EXO admin center |
| Export members | Generate, run | CSV written beside the script with DisplayName / PrimarySmtpAddress / RecipientTypeDetails / Alias; no `Read-Host` prompt |

- [ ] **Step 2: Mail-enabled Security Group matrix**

Repeat all four rows from Step 1 against the test mail-enabled security group. Also confirm the target step rejects the DL when looked up under this card (kind filter) and vice versa.

- [ ] **Step 3: Shared Mailbox matrix**

| Operation | Steps | Expected |
|---|---|---|
| Grant, Full Access, AutoMapping on | Generate, run, confirm | `WOULD GRANT FullAccess (AutoMapping True)` then `GRANTED`; `Get-MailboxPermission` shows FullAccess; the mailbox auto-appears in the test user's Outlook after propagation |
| Grant, Full Access, AutoMapping off | Untick AutoMapping, generate, run | Script shows `$AutoMapping = $false`; permission granted without automapping |
| Grant, all three permissions | Tick all three, generate, run | FullAccess, SendAs, and SendOnBehalf all applied; verify with `Get-MailboxPermission`, `Get-RecipientPermission`, and `(Get-Mailbox …).GrantSendOnBehalfTo` |
| Remove, all three | Generate, run, confirm | All three removed; the three cmdlets above show the trustee gone |
| Export access list | Generate, run | CSV with Mailbox / Trustee / Permission / Deny rows, no `NT AUTHORITY\SELF` noise, SendOnBehalf rows present |

- [ ] **Step 4: Cross-cutting checks**

- Bad CSV row is excluded and reported in the amber banner; the member count in the generated script matches the valid count.
- "Use the identity as typed" path: type a real DL address without looking it up, continue, generate, run. The script's own `Get-DistributionGroup` verification succeeds.
- Same path with a deliberately wrong address: the script exits 1 with "Could not find …" and still writes a transcript.
- "← All object types" then entering a different type does not carry over stale identifiers, permissions, or target (start Shared Mailbox → Grant with all three permissions ticked, go back, enter Distribution List → Add: no permission step, no leftover CSV).
- Security Group and M365 Group live paths (add, remove, export) still behave exactly as they did in v1.
- The `.bat` works on a machine without PowerShell 7 (fallback warning shown, `powershell.exe` used).

- [ ] **Step 5: Stop. Promotion to `main` is Josh's call**

Report the matrix results and the transcript locations. **Do not merge `testing` into `main`.**

---

## Self-Review

**1. Spec coverage** (`docs/superpowers/specs/2026-07-14-group-admin-expansion-design.md`):

| Spec requirement | Task |
|---|---|
| Distribution list add/remove/export via generated script | 4, 5, 9, 11, 13, 14 |
| Mail-enabled security group add/remove/export via generated script | 4, 5, 9, 11, 13, 14 |
| Shared mailbox grant/remove/export access | 6, 7, 12, 14 |
| Group-like wizard shape (Action → Target → Source CSV → Generate) | 10, 11, 13, 14 |
| Shared-mailbox wizard shape (Action → Target → Permission type → Users CSV → Generate) | 10, 11, 12, 13, 14 |
| All three permission types selectable | 6, 12 |
| AutoMapping toggle, Full Access only, default ON | 6 (`autoMapping: input.autoMapping !== false`), 12 (`wiz.autoMapping:true` default, card hidden unless Full Access) |
| Cmdlet mapping exactly as specified | 4 (`Add`/`Remove-DistributionGroupMember`), 5 (`Get-DistributionGroupMember`), 6 (`Add`/`Remove-MailboxPermission` + `-AutoMapping`, `Add`/`Remove-RecipientPermission`, `Set-Mailbox -GrantSendOnBehalfTo`), 7 (`Get-MailboxPermission` + `Get-RecipientPermission`) |
| Script header comment: what / target / operation / timestamp / generating tech | 3 (`psPrologue`) |
| `Connect-ExchangeOnline` with module install guard | 3 (`psConnect`) |
| `Start-Transcript` | 3 (`psPrologue`), stopped in `psEpilogue` |
| `-WhatIf` dry run first, then live, per-item try/catch | 4, 6 |
| Self-running `Run-<operation>.bat` bundled with the `.ps1` in one `.zip` | 8 |
| In-browser CSV/identity validation before generating | 13, 14 |
| Live/Script card tags stay honest | 9 (tags unchanged, all cards enabled) |
| Reuse `ITTools.auth` / `graph` / `csv` / `ui` / `styles.css` | 9, 11, 13, 14 (no shared-module edits anywhere) |
| No new Graph scopes | 15, 17 Step 5 |
| Non-goals excluded (live EXO backend, cross-type batch, polish pass) | no task exists for any of them |

**Deliberate spec deviation, flagged:** the spec's "consistency rule" says Exchange-type *exports* also generate a script, and this plan honors that (`Get-DistributionGroupMember` / `Get-MailboxPermission` run inside the generated script, not via live Graph reads). The spec's deferred "live Graph reads for Exchange-type exports" optimization is intentionally **not** implemented. Graph reads *are* used for target verification only, which the spec explicitly allows ("Graph has no write path") and which Task 11 pairs with a script-side re-verification.

**2. Placeholder scan:** every code step contains complete, runnable content. The one `{ /* filled in below */ }` marker in Task 14 Step 3 is inside a string that is unconditionally overwritten three lines later by the `.gen-files` innerHTML assignment, and the overwrite code is shown in full. Task 4 Step 1 deliberately throws for `shared-mailbox` and Task 6 Step 2 shows the exact line to replace, so no task leaves a stub behind. No "TBD", no "add error handling", no "similar to Task N".

**3. Type and signature consistency:**
- `ExoScripts.buildContext(input)` → `ctx` field names (`typeId`, `op`, `model`, `opLabel`, `title`, `target`, `targetDisplay`, `targetSlug`, `identities`, `perms.{full,sendAs,onBehalf}`, `autoMapping`, `tech`, `timestamp`, `dateOnly`, `scriptName`, `batName`, `zipName`, `logBase`) are defined in Task 2 and used with identical spelling in Tasks 3, 4, 5, 6, 7, 8, and 14.
- `psPrologue(ctx, extraHeaderLines)`, `psConnect()`, `psEpilogue(ctx, extraSummary)` — signatures defined in Task 3, called with matching arity in Tasks 4, 5, 6, 7.
- `buildScript(ctx)` / `buildBat(ctx)` / `buildZip(ctx)` — defined in Tasks 4 and 8, called from Task 14's `renderGenerateStep` and `downloadScriptBundle`.
- Op strings are consistent: `add` / `remove` / `export` for group-like types and `grant` / `remove` / `export` for the shared mailbox, in `OBJECT_TYPES.ops` (Task 9), `OP_META` (Task 10), `OP_LABELS` and `SCRIPT_BASE` (Task 2), and every builder branch.
- `graphKind` values `security` / `unified` / `distribution` / `mailSecurity` / `mailbox` are set in Task 9's registry and consumed by `graphKindOf` + `KIND_LABELS` (Task 9) and `renderTargetStep` (Task 11).
- Wizard state field names (`targetIdentity`, `targetVerified`, `validIdentifiers`, `perms`, `autoMapping`) are added to both the declaration and the `openWizard` reset in Task 9 Step 5, then read in Tasks 11, 12, 13, 14.
- Render function names (`renderActionStep`, `renderTargetStep`, `renderPermStep`, `renderSourceStep`, `renderRunStep`, `renderGenerateStep`) and helpers (`validateIdentities`, `exoContext`, `downloadScriptBundle`, `permChanged`, `permNext`, `useTargetAsTyped`, `mailboxLookup`) are each defined once and referenced with the same name everywhere, including inside `onclick` strings.
- DOM ids introduced (`wManualWrap`, `pErr`, `permFull`, `permSendAs`, `permOnBehalf`, `permAuto`, `autoCard`, `permNextBtn`, `genErr`, `genBtn`, `scriptPreview`) do not collide with any v1 id in `tools/group-import/index.html`.
