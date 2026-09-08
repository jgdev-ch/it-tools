# Group Administration Script Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the generated Exchange PowerShell survive a mid-run re-authentication, stop
wasting the session's healthy window on a 1896-call dry run, and show the tech what it is doing.

**Architecture:** All changes are in `tools/group-import/exo-scripts.js`, a pure string builder
with no DOM/network/ITTools dependency. New shared PowerShell primitives are emitted by
`psPrologue` so every generated shape inherits them; the two generators
(`buildGroupMemberScript`, `buildMailboxPermissionScript`) then adopt a 5-phase structure where
phase 3 is a local membership diff and phase 4 is a chunked apply loop with retry, a circuit
breaker, and reconnect.

**Tech Stack:** ES5-flavoured JS in an IIFE, JS template literals emitting PowerShell 5.1/7
compatible script text, `ExchangeOnlineManagement` 3.9.0+, JSZip for bundling.

**Spec:** `docs/superpowers/specs/2026-09-08-group-admin-script-hardening-design.md`

---

## Read this before touching any template literal

From the header comment of `exo-scripts.js`. Violating these **silently corrupts** generated
scripts and `node --check` will not catch it:

- Never emit PowerShell `${var}` syntax. `${` interpolates in a JS template literal. Use `$var`
  and `$(...)` only.
- Write `\\` for every literal backslash. A lone `\` eats the next character.
- Never emit PowerShell backticks: no line continuations, no backtick-n. One line per cmdlet.
- Every injected value goes through `psStr()`.

## Two spec precisions this plan locks in

1. **Retry attempts.** Spec §4 says "up to 3 attempts with 2s / 6s / 15s backoff." Three
   attempts require only two sleeps. This plan implements **3 attempts with sleeps of 2s then
   6s**. The `15` is dropped.
2. **Per-member log lines stay.** Spec §4's console sample shows only chunk milestones, which
   could be misread as removing per-member output. The transcript is the audit record, so
   `ADDED:` / `FAILED:` / `SKIPPED:` lines per member **remain**. The ~3800 lines being removed
   are the *dry run's* duplicated `What if:` + `WOULD ADD:` pairs, not live-run records. Chunk
   milestone lines are additive.

## Verification model

This repo has **no JS or PowerShell test framework.** Do not invent one. Verification is:

- `node --check tools/group-import/exo-scripts.js` after every JS edit.
- **Render-and-parse sweep:** a throwaway node harness written to `$env:TEMP` (never committed)
  renders all 9 op x type combinations plus the AutoMapping-off grant variant, and each rendered
  `.ps1` is parsed with `pwsh` `[Parser]::ParseFile`. Any parse error fails the task.
- **Stub harness (Task 10):** replays the real 2026-09-08 incident against the generated script
  with `Add-DistributionGroupMember` stubbed, proving the breaker and reconnect work with no
  tenant.
- **Manual live matrix (Task 12):** Task 18 from the v2 plan. Never run. Not replaced by any of
  the above.

### The reusable render-and-parse harness

Write this once to `$env:TEMP` at the start of Task 1 and re-run it in every later task. It is
referenced throughout as **the sweep**.

```javascript
// %TEMP%\gi-sweep.js  — throwaway, never committed
const fs = require("fs");
const path = require("path");
const out = process.env.TEMP;

// exo-scripts.js is an IIFE that assigns to root.ExoScripts on globalThis. It has NO
// module.exports, so require() returns an empty object. Require it for the side effect
// and read the API off globalThis. Paths must be Windows-style: node on Windows
// resolves a leading-slash path like /c/dev/... to C:\c\dev\... and fails.
require("C:/dev/projects/it-tools/tools/group-import/exo-scripts.js");
const EXO = globalThis.ExoScripts;
if (!EXO || typeof EXO.buildContext !== "function") {
  throw new Error("ExoScripts did not attach to globalThis. Check the IIFE tail of exo-scripts.js.");
}

const shapes = [
  { typeId: "distribution-list",   typeLabel: "Distribution List",              op: "add" },
  { typeId: "distribution-list",   typeLabel: "Distribution List",              op: "remove" },
  { typeId: "distribution-list",   typeLabel: "Distribution List",              op: "export" },
  { typeId: "mail-security-group", typeLabel: "Mail-enabled Security Group",    op: "add" },
  { typeId: "mail-security-group", typeLabel: "Mail-enabled Security Group",    op: "remove" },
  { typeId: "mail-security-group", typeLabel: "Mail-enabled Security Group",    op: "export" },
  { typeId: "shared-mailbox",      typeLabel: "Shared Mailbox",                 op: "grant" },
  { typeId: "shared-mailbox",      typeLabel: "Shared Mailbox",                 op: "remove" },
  { typeId: "shared-mailbox",      typeLabel: "Shared Mailbox",                 op: "export" },
  { typeId: "shared-mailbox",      typeLabel: "Shared Mailbox",                 op: "grant",
    autoMapping: false, tag: "-nomap" },
];

// A 20-member set and an 1896-member set, so small-run and large-run shapes both render.
const small = Array.from({ length: 20 },   (_, i) => "user" + i + "@corrohealth.com");
const large = Array.from({ length: 1896 }, (_, i) => "bulk" + i + "@corrohealth.com");

let n = 0;
for (const s of shapes) {
  for (const [sizeName, ids] of [["small", small], ["large", large]]) {
    const ctx = EXO.buildContext({
      typeId: s.typeId, typeLabel: s.typeLabel, op: s.op,
      target: "zGlobalProviderAll@corrohealth.com", targetDisplay: "zGlobalProviderAll",
      identities: ids,
      perms: { full: true, sendAs: true, onBehalf: true },
      autoMapping: s.autoMapping !== false,
      tech: "harness",
    });
    const file = path.join(out, `gi-${s.typeId}-${s.op}${s.tag || ""}-${sizeName}.ps1`);
    fs.writeFileSync(file, EXO.buildScript(ctx));
    n++;
  }
}
console.log("rendered " + n + " scripts to " + out);
```

Run the sweep with:

```bash
/c/dev/tools/nodejs/node.exe "$TEMP/gi-sweep.js"
pwsh -NoProfile -Command "\$bad=0; Get-ChildItem \$env:TEMP\gi-*.ps1 | ForEach-Object { \$e=\$null; [System.Management.Automation.Language.Parser]::ParseFile(\$_.FullName,[ref]\$null,[ref]\$e) | Out-Null; if (\$e.Count) { \$bad++; Write-Host \$_.Name -Fore Red; \$e | Select-Object -First 3 | ForEach-Object { Write-Host ('   ' + \$_.Message) } } }; Write-Host ('files with parse errors: ' + \$bad)"
```

Expected in every task: `files with parse errors: 0`

**Pre-validated 2026-09-08 against unmodified `exo-scripts.js`:** the harness renders and the
baseline is clean, so the mechanism itself is known good before any change is made.

```
rendered 20 scripts to C:\Users\JOSHUA~1\AppData\Local\Temp
files scanned: 20
files with parse errors: 0
```

Run the `pwsh` parse step through the **PowerShell tool**, not Git Bash. Git Bash mangles the
escaped quoting and can also rewrite leading-slash arguments into Windows paths.

---

## File structure

Only one production file changes.

| File | Responsibility | Change |
|---|---|---|
| `tools/group-import/exo-scripts.js` | Generates the `.ps1` + `.bat` + `.zip` | Modified throughout |
| `changelog.json` | Hub Recent Updates feed | One entry added (Task 11) |
| `config.json` | Hub version string | Bumped (Task 11) |
| `%TEMP%\gi-sweep.js` | Render-and-parse harness | Created, never committed |
| `%TEMP%\gi-stub-*.ps1` | Incident replay harness | Created, never committed |

`exo-scripts.js` is ~630 lines and grows to roughly 950. That is within the file's existing
responsibility (it is the script generator) and splitting it would break the single-file
`<script src>` load the tool uses, so it stays one file.

---

## Task 1: Shared console and run-state primitives

Additive only. `Write-Head` and `Write-Item` stay in place so every existing call site keeps
working and the sweep stays green. They are removed in Task 9.

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`psPrologue`, ~line 108-155)

- [ ] **Step 1: Write the render-and-parse harness**

Save the `gi-sweep.js` content from "The reusable render-and-parse harness" above to
`$env:TEMP\gi-sweep.js`. Do not commit it.

- [ ] **Step 2: Run the sweep to capture a clean baseline**

```bash
/c/dev/tools/nodejs/node.exe "$TEMP/gi-sweep.js"
```

Expected: `rendered 20 scripts to C:\Users\...\Temp`

Then run the `pwsh` parse command from above.
Expected: `files with parse errors: 0`

If this baseline is not already 0, stop and fix that before making any change.

- [ ] **Step 3: Add the run-state block and primitives to `psPrologue`**

In `exo-scripts.js`, find this line inside the `psPrologue` return template:

```javascript
$ErrorActionPreference = "Continue"

function Write-Head { param([string]$Message) Write-Host ""; Write-Host "  $Message" -ForegroundColor Cyan }
function Write-Item { param([string]$Message, [string]$Color = "Gray") Write-Host "    $Message" -ForegroundColor $Color }
```

Replace it with the following. Note `Write-Head` and `Write-Item` are retained verbatim.

```javascript
$ErrorActionPreference = "Continue"

# Progress bar placement. PowerShell 7 defaults to "Minimal", which pins the bar to the
# bottom of the console. "Classic" restores the 5.1 top block so the status line stays in
# one fixed place while the log scrolls underneath. $PSStyle does not exist on 5.1.
if ($null -ne $PSStyle) { try { $PSStyle.Progress.View = "Classic" } catch { } }

# --- Run state ----------------------------------------------------
$script:RunTotal      = 0
$script:RunCurrent    = 0
$script:RunOk         = 0
$script:RunFailed     = 0
$script:RunSkipped    = 0
$script:RunReconnects = 0
$script:RunStatus     = "Connected"
$script:RunActivity   = "Working"
$script:RunStart      = Get-Date
$script:ConnectedAt   = Get-Date
$script:LastDraw      = [datetime]::MinValue

# --- Tunables -----------------------------------------------------
$script:ChunkSize      = 150
$script:MaxAttempts    = 3
$script:Backoff        = @(2, 6)
$script:BreakerLimit   = 10
$script:MaxReconnects  = 3
$script:RefreshMinutes = 40
$script:DrawEveryMs    = 250

# --- Console helpers ----------------------------------------------
function Write-Head { param([string]$Message) Write-Host ""; Write-Host "  $Message" -ForegroundColor Cyan }
function Write-Item { param([string]$Message, [string]$Color = "Gray") Write-Host "    $Message" -ForegroundColor $Color }

function Write-Step {
    param([int]$Step, [int]$Total, [string]$Message)
    Write-Host ""
    Write-Host ("  [" + $Step + "/" + $Total + "] " + $Message) -ForegroundColor Cyan
}

function Write-Detail {
    param([string]$Message, [string]$Color = "Gray")
    Write-Host ("      " + $Message) -ForegroundColor $Color
}

function Stop-Run {
    param([string]$Message = "", [string]$Color = "Yellow", [int]$Code = 0)
    if ($Message) { Write-Detail $Message $Color }
    try { Write-Progress -Activity $script:RunActivity -Completed } catch { }
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
    exit $Code
}

function Confirm-Continue {
    param([string]$Prompt)
    Write-Host ""
    $response = Read-Host ("      " + $Prompt + " [Y/N]")
    Write-Host ""
    if ($response -notmatch "^[Yy]") { Stop-Run "Aborted. No changes were made." Yellow 0 }
}

function Confirm-Apply {
    param([int]$Count, [string]$What = "entries")
    Write-Host ""
    $answer = Read-Host ("      Type YES to apply these changes to " + $Count + " " + $What + " for real (anything else aborts)")
    if ($answer -ne "YES") { Stop-Run "Aborted. No changes were made." Yellow 0 }
}

function Update-Run {
    param([switch]$Force)
    $now = Get-Date
    if (-not $Force -and ($now - $script:LastDraw).TotalMilliseconds -lt $script:DrawEveryMs) { return }
    $script:LastDraw = $now

    $pct = 0
    if ($script:RunTotal -gt 0) {
        $pct = [int](($script:RunCurrent / $script:RunTotal) * 100)
        if ($pct -gt 100) { $pct = 100 }
    }
    $status = $script:RunStatus + "  |  " + $script:RunCurrent + "/" + $script:RunTotal + "  |  " + $script:RunOk + " ok, " + $script:RunFailed + " failed, " + $script:RunSkipped + " skipped"

    $left = -1
    if ($script:RunCurrent -gt 0 -and $script:RunTotal -gt 0) {
        $per  = ($now - $script:RunStart).TotalSeconds / $script:RunCurrent
        $left = [int]($per * ($script:RunTotal - $script:RunCurrent))
    }
    try {
        if ($left -ge 0) {
            Write-Progress -Activity $script:RunActivity -Status $status -PercentComplete $pct -SecondsRemaining $left
        } else {
            Write-Progress -Activity $script:RunActivity -Status $status -PercentComplete $pct
        }
    } catch { }
}
```

- [ ] **Step 4: Syntax check**

```bash
/c/dev/tools/nodejs/node.exe --check /c/dev/projects/it-tools/tools/group-import/exo-scripts.js
```

Expected: no output, exit 0.

- [ ] **Step 5: Run the sweep**

Expected: `rendered 20 scripts to ...` then `files with parse errors: 0`

- [ ] **Step 6: Confirm the new functions actually reached the output**

```bash
grep -c "function Update-Run\|function Write-Step\|function Stop-Run\|PSStyle.Progress.View" "$TEMP/gi-distribution-list-add-small.ps1"
```

Expected: `4`

- [ ] **Step 7: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: add console and run-state primitives to generated scripts"
```

---

## Task 2: Failure classification and retry helper

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`psPrologue`, after `Update-Run`)

- [ ] **Step 1: Append the classifier to the `psPrologue` template**

Add immediately after the `Update-Run` function inside the same template literal:

```javascript

# --- Failure classification ---------------------------------------
# "dead"      -> the EXO session is unusable; only a reconnect fixes it.
# "transient" -> Exchange told us to retry.
# "permanent" -> a data problem with this one entry. Never a session problem.
# "unknown"   -> unclassified. Treated as retryable AND counted toward the breaker,
#                because an unrecognised error is more likely session-related than benign.
$script:DeadSessionPatterns = @(
    "getresponseheader",
    "get-claimsfromexceptiondetails",
    "session has been closed",
    "connection to the remote server",
    "starting a command on the remote server",
    "the runspace state is not valid",
    "no longer available"
)
$script:TransientPatterns = @(
    "server side error",
    "please try again",
    "try again after some time",
    "operation could not be completed",
    "timed out",
    "timeout",
    "too many requests",
    "throttl",
    "temporarily unavailable",
    "service unavailable",
    "(429)",
    "(503)"
)
$script:PermanentPatterns = @(
    "couldn't be found",
    "could not be found",
    "wasn't found",
    "was not found",
    "is not a valid",
    "isn't a valid",
    "already a member",
    "is not a member",
    "isn't a member",
    "doesn't have a mailbox",
    "does not have a mailbox",
    "unlicensed",
    "invalid smtp address"
)

function Test-AnyPattern {
    param([string]$Text, [string[]]$Patterns)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $lower = $Text.ToLowerInvariant()
    foreach ($p in $Patterns) { if ($lower.Contains($p)) { return $true } }
    return $false
}

function Get-FailureClass {
    param([string]$Message)
    if (Test-AnyPattern -Text $Message -Patterns $script:DeadSessionPatterns) { return "dead" }
    if (Test-AnyPattern -Text $Message -Patterns $script:TransientPatterns)   { return "transient" }
    if (Test-AnyPattern -Text $Message -Patterns $script:PermanentPatterns)   { return "permanent" }
    return "unknown"
}

# Runs one scriptblock against one identity with retry. Returns a hashtable:
#   Ok (bool), Attempts (int), Message (string), Class (string)
function Invoke-WithRetry {
    param([scriptblock]$Action, [string]$Identity)
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            & $Action $Identity
            return @{ Ok = $true; Attempts = $attempt; Message = ""; Class = "ok" }
        } catch {
            $msg   = $_.Exception.Message
            $class = Get-FailureClass -Message $msg
            if ($class -eq "dead") {
                return @{ Ok = $false; Attempts = $attempt; Message = $msg; Class = $class }
            }
            $retryable = ($class -eq "transient" -or $class -eq "unknown")
            if ($retryable -and $attempt -lt $script:MaxAttempts) {
                Start-Sleep -Seconds $script:Backoff[$attempt - 1]
                continue
            }
            return @{ Ok = $false; Attempts = $attempt; Message = $msg; Class = $class }
        }
    }
}
```

- [ ] **Step 2: Syntax check**

```bash
/c/dev/tools/nodejs/node.exe --check /c/dev/projects/it-tools/tools/group-import/exo-scripts.js
```

Expected: no output, exit 0.

- [ ] **Step 3: Run the sweep**

Expected: `files with parse errors: 0`

- [ ] **Step 4: Prove the classifier behaves, in pwsh, directly**

```bash
pwsh -NoProfile -Command ". \$env:TEMP\gi-distribution-list-add-small.ps1 -ErrorAction SilentlyContinue" 2>/dev/null || true
pwsh -NoProfile -Command "
\$src = Get-Content \$env:TEMP\gi-distribution-list-add-small.ps1 -Raw
\$block = [regex]::Match(\$src, '(?s)# --- Failure classification.*?^}', 'Multiline').Value
Invoke-Expression \$block
'dead      -> ' + (Get-FailureClass 'Method invocation failed because [System.Net.Http.HttpResponseMessage] does not contain a method named ''GetResponseHeader''.')
'transient -> ' + (Get-FailureClass 'A server side error has occurred because of which the operation could not be completed. Please try again after some time.')
'permanent -> ' + (Get-FailureClass \"Couldn't be found on 'contoso.onmicrosoft.com'\")
'unknown   -> ' + (Get-FailureClass 'Something nobody has ever seen before')
"
```

Expected exactly:

```
dead      -> dead
transient -> transient
permanent -> permanent
unknown   -> unknown
```

These are the two real messages from the 2026-09-08 transcript. If `dead` or `transient` come
back as anything else, the pattern lists are wrong and every later task is built on sand.

- [ ] **Step 5: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: classify generated-script failures and add a retry helper"
```

---

## Task 3: Phase count on the context

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`buildContext`, ~line 66-106)

- [ ] **Step 1: Add `phases` to the returned context**

In `buildContext`, find:

```javascript
      autoMapping: input.autoMapping !== false,
      tech: input.tech || "unknown",
```

Insert `phases` immediately above `autoMapping`:

```javascript
      // Export is read-only (connect, verify, export). Write ops add a compare
      // phase and an apply phase. Step numbering must never be hardcoded.
      phases: op === "export" ? 3 : 5,
      autoMapping: input.autoMapping !== false,
      tech: input.tech || "unknown",
```

- [ ] **Step 2: Syntax check and sweep**

```bash
/c/dev/tools/nodejs/node.exe --check /c/dev/projects/it-tools/tools/group-import/exo-scripts.js
/c/dev/tools/nodejs/node.exe "$TEMP/gi-sweep.js"
```

Expected: no output from `--check`; `rendered 20 scripts`.

- [ ] **Step 3: Assert the value directly**

```bash
/c/dev/tools/nodejs/node.exe -e '
require("C:/dev/projects/it-tools/tools/group-import/exo-scripts.js");
const EXO = globalThis.ExoScripts;
const mk = (op) => EXO.buildContext({ typeId:"distribution-list", typeLabel:"DL", op, target:"t@x.com", identities:["a@x.com"], tech:"h" }).phases;
console.log("add", mk("add"), "remove", mk("remove"), "export", mk("export"));
'
```

Expected: `add 5 remove 5 export 3`

- [ ] **Step 4: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: derive generated-script phase count from the operation"
```

---

## Task 4: Migrate connect, verify and epilogue to numbered phases

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`psConnect` ~line 158, `psEpilogue` ~line 190, both `verify` blocks at ~line 214 and ~line 320)

- [ ] **Step 1: Make `psConnect` take the context and emit phase 1**

Change the signature and body. Find `function psConnect() {` and replace the whole function
with:

```javascript
  /** ExchangeOnlineManagement install guard + Connect-ExchangeOnline. Phase 1. */
  function psConnect(ctx) {
    return `
# --- Phase 1: Connect to Exchange Online --------------------------
Write-Step 1 ${ctx.phases} "Connecting to Exchange Online..."

$minVersion = [Version]"3.9.0"
$installed  = Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $installed -or $installed.Version -lt $minVersion) {
    Write-Detail "ExchangeOnlineManagement 3.9.0 or newer not found. Installing for the current user..." Yellow
    try {
        Install-Module ExchangeOnlineManagement -MinimumVersion $minVersion -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
    } catch {
        Write-Detail ("ERROR: Could not install ExchangeOnlineManagement. " + $_.Exception.Message) Red
        Write-Detail "Install it manually, then re-run: Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force" Yellow
        Stop-Transcript | Out-Null
        exit 1
    }
}

try {
    Import-Module ExchangeOnlineManagement -MinimumVersion $minVersion -ErrorAction Stop
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    $script:ConnectedAt = Get-Date
    Write-Detail "Connected." Green
} catch {
    Write-Detail ("ERROR: Could not connect to Exchange Online. " + $_.Exception.Message) Red
    Stop-Transcript | Out-Null
    exit 1
}
`;
  }
```

Note `Stop-Run` is deliberately **not** used in the two failure paths here: it calls
`Disconnect-ExchangeOnline`, which is meaningless when the connect itself failed.

- [ ] **Step 2: Update both `psConnect()` call sites to pass `ctx`**

There are four calls, all of the form `psConnect()`. Change every one to `psConnect(ctx)`:

```bash
cd /c/dev/projects/it-tools/tools/group-import
grep -n "psConnect()" exo-scripts.js
```

Expected before the edit: 4 hits (two in `buildGroupMemberScript`, two in
`buildMailboxPermissionScript`).

```bash
sed -i 's/psConnect()/psConnect(ctx)/g' exo-scripts.js
grep -c "psConnect(ctx)" exo-scripts.js
```

Expected after: `4`

- [ ] **Step 3: Convert the group-member verify block to phase 2**

In `buildGroupMemberScript`, replace the `verify` template with:

```javascript
    const verify = `
# --- Phase 2: Verify the target -----------------------------------
Write-Step 2 ${ctx.phases} "Verifying the target in Exchange Online..."

# Re-verification after a reconnect uses this too, so it must be a function.
function Test-Target {
    $g = Get-DistributionGroup -Identity $Target -ErrorAction Stop
    return $g
}

try {
    $group = Test-Target
    Write-Detail ("Found: " + $group.DisplayName + " <" + $group.PrimarySmtpAddress + "> [" + $group.RecipientTypeDetails + "]") Green
} catch {
    Write-Detail ("ERROR: Could not find '$Target' in Exchange Online. " + $_.Exception.Message) Red
    Stop-Run "" Red 1
}
`;
```

- [ ] **Step 4: Convert the mailbox verify block to phase 2**

In `buildMailboxPermissionScript`, replace the `verify` template with:

```javascript
    const verify = `
# --- Phase 2: Verify the mailbox ----------------------------------
Write-Step 2 ${ctx.phases} "Verifying the mailbox in Exchange Online..."

function Test-Target {
    $m = Get-Mailbox -Identity $Mailbox -ErrorAction Stop
    return $m
}

try {
    $mbx = Test-Target
    Write-Detail ("Found: " + $mbx.DisplayName + " <" + $mbx.PrimarySmtpAddress + "> [" + $mbx.RecipientTypeDetails + "]") Green
    if ($mbx.RecipientTypeDetails -ne "SharedMailbox") {
        Write-Detail "WARNING: this is not a shared mailbox. Continue only if that is intentional." Yellow
    }
} catch {
    Write-Detail ("ERROR: Could not find mailbox '$Mailbox'. " + $_.Exception.Message) Red
    Stop-Run "" Red 1
}
`;
```

- [ ] **Step 5: Convert `psEpilogue` to the final phase**

Replace the whole `psEpilogue` function with:

```javascript
  /** Summary tail, disconnect, transcript stop. extraSummary is raw PowerShell lines. */
  function psEpilogue(ctx, extraSummary) {
    return `
# --- Phase ${ctx.phases}: Complete ---------------------------------
try { Write-Progress -Activity $script:RunActivity -Completed } catch { }
Write-Step ${ctx.phases} ${ctx.phases} "Complete"
${extraSummary || ""}Write-Detail ("Transcript : " + $transcript)
Write-Host ""

Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Stop-Transcript | Out-Null
`;
  }
```

- [ ] **Step 6: Update the four export-branch summary strings from `Write-Item` to `Write-Detail`**

```bash
grep -n "psEpilogue(ctx, 'Write-Item" exo-scripts.js
```

Expected: 2 hits.

```bash
sed -i "s/psEpilogue(ctx, 'Write-Item (/psEpilogue(ctx, 'Write-Detail (/g" exo-scripts.js
grep -c "psEpilogue(ctx, 'Write-Detail (" exo-scripts.js
```

Expected: `2`

- [ ] **Step 7: Syntax check and sweep**

Expected: `--check` silent; `files with parse errors: 0`

- [ ] **Step 8: Eyeball one rendered script**

```bash
grep -n "Write-Step\|function Test-Target" "$TEMP/gi-distribution-list-add-small.ps1" | head
```

Expected: `Write-Step 1 5`, a `Test-Target` definition, `Write-Step 2 5`, and `Write-Step 5 5`.

```bash
grep -n "Write-Step" "$TEMP/gi-distribution-list-export-small.ps1"
```

Expected: `Write-Step 1 3`, `Write-Step 2 3`, `Write-Step 3 3` — never `/5`.

- [ ] **Step 9: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: number the generated-script phases and extract Test-Target"
```

---

## Task 5: Replace the group-member dry run with a membership diff

This is the single highest-value change in the plan. It removes 1896 `-WhatIf` API calls and
about 3800 lines of console noise.

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`buildGroupMemberScript`, the `body` template ~line 257-293)

- [ ] **Step 1: Replace the dry-run and confirm sections of `body`**

In `buildGroupMemberScript`, find the `const body = ` template and replace **only** the dry-run
and confirm portions (everything from `# --- Dry run` through the `exit 0` of the confirm gate)
with the phase 3 block below. Leave the live-run portion alone for now; Task 6 replaces it.

```javascript
    const desiredWord = isAdd ? "to add" : "to remove";
    const haveWord    = isAdd ? "already members" : "not members";

    const phase3 = `
# --- Phase 3: Compare against current membership ------------------
Write-Step 3 ${ctx.phases} "Comparing your list against current membership..."

# One read instead of one -WhatIf call per member. The old dry run issued an API
# call for every member before any real work started, consuming a large share of
# the session's usable window, and printed two lines per member.
$current = @()
try {
    $current = @(Get-DistributionGroupMember -Identity $Target -ResultSize Unlimited -ErrorAction Stop)
} catch {
    Write-Detail ("ERROR: Could not read current members. " + $_.Exception.Message) Red
    Stop-Run "" Red 1
}

# A CSV row may hold a primary SMTP address, an alias, a UPN or a secondary
# proxy address. Comparing on PrimarySmtpAddress alone would classify an existing
# member as "to add" whenever the CSV used any other form of their address, so
# every known address for every member goes into the lookup.
$have = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
foreach ($m in $current) {
    if ($m.PrimarySmtpAddress) { $null = $have.Add([string]$m.PrimarySmtpAddress) }
    if ($m.Alias)              { $null = $have.Add([string]$m.Alias) }
    if ($m.WindowsLiveID)      { $null = $have.Add([string]$m.WindowsLiveID) }
    foreach ($addr in @($m.EmailAddresses)) {
        $a = [string]$addr
        if ($a -like "smtp:*") { $a = $a.Substring(5) }
        if ($a) { $null = $have.Add($a) }
    }
}

$ToApply   = New-Object System.Collections.Generic.List[string]
$AlreadyOk = New-Object System.Collections.Generic.List[string]
foreach ($m in $Members) {
    $id = [string]$m
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $inGroup = $have.Contains($id.Trim())
    if (${isAdd ? "$inGroup" : "-not $inGroup"}) { $AlreadyOk.Add($id) } else { $ToApply.Add($id) }
}
$ToApply = @($ToApply)

$script:RunSkipped = $AlreadyOk.Count
Write-Detail ($Members.Count.ToString() + " in list  |  " + $current.Count + " currently in group  |  " + $ToApply.Count + " ${desiredWord}  |  " + $AlreadyOk.Count + " ${haveWord}")

function Show-Sample {
    param([string]$Label, $Items, [string]$Color = "Gray")
    if (@($Items).Count -eq 0) { return }
    $shown = @($Items) | Select-Object -First 10
    Write-Detail ($Label + ":") $Color
    foreach ($s in $shown) { Write-Detail ("  " + $s) $Color }
    if (@($Items).Count -gt 10) { Write-Detail ("  and " + (@($Items).Count - 10) + " more") $Color }
}

Show-Sample "${desiredWord.charAt(0).toUpperCase() + desiredWord.slice(1)}" $ToApply Yellow
Show-Sample "Skipping, ${haveWord}" $AlreadyOk Gray

if ($ToApply.Count -eq 0) {
    Write-Detail "Nothing to do. Every entry is already in the desired state." Green
    Stop-Run "" Gray 0
}

# The old -WhatIf loop proved, as a side effect, that this account could write to
# the target. A local diff cannot. One -WhatIf call against the first entry keeps
# that guarantee and fails early with actionable text instead of mid-run.
try {
    ${cmdlet} -Identity $Target -Member $ToApply[0] ${liveArgs} -WhatIf -ErrorAction Stop
    Write-Detail "Permission check passed." Green
} catch {
    Write-Detail ("ERROR: This account cannot modify '$Target'. " + $_.Exception.Message) Red
    Write-Detail "You need a role with write access to this group, for example Recipient Management." Yellow
    Stop-Run "" Red 1
}

Confirm-Apply $ToApply.Count "entries"
`;
```

- [ ] **Step 2: Wire `phase3` into the returned string**

At the bottom of `buildGroupMemberScript`, the return currently reads:

```javascript
    return psPrologue(ctx, ["#  Members     : " + ctx.identities.length]) +
           inputs + psConnect(ctx) + verify + body + psEpilogue(ctx, summary);
```

Change it to insert `phase3` between `verify` and `body`:

```javascript
    return psPrologue(ctx, ["#  Members     : " + ctx.identities.length]) +
           inputs + psConnect(ctx) + verify + phase3 + body + psEpilogue(ctx, summary);
```

- [ ] **Step 3: Syntax check and sweep**

Expected: `--check` silent; `files with parse errors: 0`

- [ ] **Step 4: Prove the dry run is gone and the diff is present**

```bash
grep -c "WhatIf" "$TEMP/gi-distribution-list-add-large.ps1"
```

Expected: `1` — exactly the capability probe, not 1896 loop calls.

```bash
grep -c "WOULD ADD" "$TEMP/gi-distribution-list-add-large.ps1"
```

Expected: `0`

```bash
grep -n "Get-DistributionGroupMember -Identity \$Target -ResultSize Unlimited" "$TEMP/gi-distribution-list-add-large.ps1" | wc -l
```

Expected: `1`

- [ ] **Step 5: Confirm the add/remove polarity is inverted correctly**

```bash
grep -n "if (\$inGroup)" "$TEMP/gi-distribution-list-add-small.ps1"
grep -n "if (-not \$inGroup)" "$TEMP/gi-distribution-list-remove-small.ps1"
```

Expected: one hit each. An add run skips people already in the group; a remove run skips people
who are not. Getting this backwards would make the tool a no-op, so verify both.

- [ ] **Step 6: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: replace the per-member dry run with one membership diff"
```

---

## Task 6: Chunked apply with retry, breaker and reconnect (group members)

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`buildGroupMemberScript`, the live-run portion of `body`)

- [ ] **Step 1: Add the shared `Reset-Session` function to `psPrologue`**

Append inside the `psPrologue` template, after `Invoke-WithRetry`:

```javascript

# Re-establishes a dead session. Depends on Test-Target, which each generator
# defines for its own object type. Returns $true if the session is usable again.
function Reset-Session {
    if ($script:RunReconnects -ge $script:MaxReconnects) {
        Write-Detail ("Reconnect limit of " + $script:MaxReconnects + " reached. Stopping.") Red
        return $false
    }
    $script:RunStatus = "Reconnecting..."
    Update-Run -Force
    Write-Detail "Re-establishing the Exchange Online session..." Yellow
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try {
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        $null = Test-Target
        $script:RunReconnects++
        $script:ConnectedAt = Get-Date
        $script:RunStatus   = "Connected"
        Update-Run -Force
        Write-Detail ("Reconnected. Reconnect " + $script:RunReconnects + " of " + $script:MaxReconnects + ".") Green
        return $true
    } catch {
        Write-Detail ("Reconnect failed. " + $_.Exception.Message) Red
        $script:RunStatus = "Disconnected"
        Update-Run -Force
        return $false
    }
}
```

- [ ] **Step 2: Replace the live-run portion of `body` with the chunked loop**

In `buildGroupMemberScript`, `const body` should now contain **only** the live run. Replace it
entirely with:

```javascript
    const body = `
# --- Phase 4: Apply changes ---------------------------------------
Write-Step 4 ${ctx.phases} "Applying changes..."

$script:RunTotal    = $ToApply.Count
$script:RunActivity = "${isAdd ? "Adding members to" : "Removing members from"} " + $Target
$script:RunStart    = Get-Date
$script:RunCurrent  = 0
Update-Run -Force

$failRows    = New-Object System.Collections.Generic.List[object]
$consecutive = 0
$aborted     = $false
$chunkCount  = [Math]::Ceiling($script:RunTotal / $script:ChunkSize)
$i           = 0

$applyOne = { param($Identity) ${cmdlet} -Identity $Target -Member $Identity ${liveArgs} -ErrorAction Stop }

for ($c = 1; $c -le $chunkCount; $c++) {
    if ($aborted) { break }

    # Proactive refresh. The 2026-09-08 run died at 62 minutes because the access
    # token needed renewing and the module's own claims handler crashed. Refreshing
    # before the token ages out means that path is never reached.
    if (((Get-Date) - $script:ConnectedAt).TotalMinutes -ge $script:RefreshMinutes) {
        Write-Detail ("Session has been open " + $script:RefreshMinutes + "+ minutes. Refreshing before the next chunk.") Yellow
        if (-not (Reset-Session)) { $aborted = $true; break }
    }

    $end = [Math]::Min($i + $script:ChunkSize, $script:RunTotal)
    while ($i -lt $end) {
        $identity = $ToApply[$i]
        $res      = Invoke-WithRetry -Action $applyOne -Identity $identity
        $i++
        $script:RunCurrent = $i

        if ($res.Ok) {
            Write-Detail ("${didWord}: " + $identity) Green
            $script:RunOk++
            $consecutive = 0
        } else {
            $suffix = ""
            if ($res.Attempts -gt 1) { $suffix = " (after " + $res.Attempts + " attempts)" }
            Write-Detail ("FAILED: " + $identity + " - " + $res.Message + $suffix) Red
            $script:RunFailed++
            $failRows.Add([pscustomobject]@{
                Identity = $identity
                Reason   = $res.Message
                Class    = $res.Class
                Attempts = $res.Attempts
            })

            # A permanent failure is a data problem with this one entry and must not
            # count toward the session breaker. Without this, a list with ten bad
            # addresses in a row would declare a healthy session dead.
            if ($res.Class -ne "permanent") { $consecutive++ } else { $consecutive = 0 }

            if ($res.Class -eq "dead" -or $consecutive -ge $script:BreakerLimit) {
                if ($res.Class -eq "dead") {
                    Write-Detail "The Exchange session is no longer usable." Yellow
                } else {
                    Write-Detail ($consecutive.ToString() + " consecutive failures. Treating the session as dead.") Yellow
                }
                if (Reset-Session) {
                    $consecutive = 0
                    # Retry the entry that tripped the breaker, so nothing is skipped.
                    $i--
                    $script:RunCurrent = $i
                    $failRows.RemoveAt($failRows.Count - 1)
                    $script:RunFailed--
                } else {
                    $aborted = $true
                    break
                }
            }
        }
        Update-Run
    }

    if (-not $aborted) {
        Write-Detail ($script:RunCurrent.ToString() + "/" + $script:RunTotal + "   " + $script:RunOk + " ok, " + $script:RunFailed + " failed        (chunk " + $c + " of " + $chunkCount + " done, session ok)") Cyan
    }
}
Update-Run -Force

if ($aborted) {
    Write-Detail "" Yellow
    Write-Detail ("STOPPED EARLY at entry " + $script:RunCurrent + " of " + $script:RunTotal + ".") Yellow
    Write-Detail "Re-run this script to finish. It will skip everything already applied." Yellow
}

# --- Failures CSV -------------------------------------------------
$failFile = ""
if ($failRows.Count -gt 0) {
    $failFile = Join-Path $PSScriptRoot (${psStr(ctx.logBase)} + "-" + $stamp + "-failures.csv")
    $failRows | Export-Csv -Path $failFile -NoTypeInformation -Encoding UTF8
}
`;
```

- [ ] **Step 3: Replace the summary string**

Still in `buildGroupMemberScript`, replace:

```javascript
    const summary = 'Write-Item ("Succeeded : " + $ok)\nWrite-Item ("Failed    : " + $failed)\n';
```

with:

```javascript
    const summary =
      'Write-Detail ("' + didWord.padEnd(10) + ' : " + $script:RunOk)\n' +
      'Write-Detail ("Skipped    : " + $script:RunSkipped + "   (' + haveWord + ')")\n' +
      'Write-Detail ("Failed     : " + $script:RunFailed)\n' +
      'Write-Detail ("Reconnects : " + $script:RunReconnects)\n' +
      'if ($failFile) { Write-Detail ("Failures   : " + $failFile) Yellow }\n';
```

- [ ] **Step 4: Syntax check and sweep**

Expected: `--check` silent; `files with parse errors: 0`

- [ ] **Step 5: Confirm the loop shape reached the output**

```bash
grep -c "Reset-Session\|Invoke-WithRetry\|BreakerLimit\|RefreshMinutes\|failures.csv" "$TEMP/gi-distribution-list-add-large.ps1"
```

Expected: at least `5`.

```bash
grep -n "if (\$res.Class -ne \"permanent\")" "$TEMP/gi-distribution-list-add-large.ps1"
```

Expected: one hit. This is the false-trip guard; if it is missing, the breaker is wrong.

- [ ] **Step 6: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: chunk the member apply loop with retry, a breaker and reconnect"
```

---

## Task 7: Same treatment for the shared-mailbox generator

The mailbox generator applies up to three permissions per trustee, so its unit of work is a
trustee rather than a single cmdlet call. `Invoke-AccessChange` becomes the retried action.

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`buildMailboxPermissionScript`, ~line 303-550)

- [ ] **Step 1: Strip `$Preview` from the three permission blocks**

The `-WhatIf` half of each block is dead once phase 3 exists. For `fullBlock`, `sendAsBlock` and
`onBehalfBlock`, remove the `if ($Preview) { ... } else {` wrapper and keep only the live call.
`fullBlock` for the grant case becomes:

```javascript
    const fullBlock = isGrant
      ? `    if ($DoFullAccess) {
        Add-MailboxPermission -Identity $Mailbox -User $Trustee -AccessRights FullAccess -AutoMapping $AutoMapping -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Detail ("GRANTED FullAccess (AutoMapping " + $AutoMapping + "): " + $Trustee) Green
    }`
      : `    if ($DoFullAccess) {
        Remove-MailboxPermission -Identity $Mailbox -User $Trustee -AccessRights FullAccess -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Detail ("REMOVED FullAccess: " + $Trustee) Green
    }`;
```

`sendAsBlock`:

```javascript
    const sendAsBlock = isGrant
      ? `    if ($DoSendAs) {
        Add-RecipientPermission -Identity $Mailbox -Trustee $Trustee -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Detail ("GRANTED SendAs: " + $Trustee) Green
    }`
      : `    if ($DoSendAs) {
        Remove-RecipientPermission -Identity $Mailbox -Trustee $Trustee -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Detail ("REMOVED SendAs: " + $Trustee) Green
    }`;
```

`onBehalfBlock`:

```javascript
    const onBehalfBlock = isGrant
      ? `    if ($DoSendOnBehalf) {
        Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Add=$Trustee} -ErrorAction Stop
        Write-Detail ("GRANTED SendOnBehalf: " + $Trustee) Green
    }`
      : `    if ($DoSendOnBehalf) {
        Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Remove=$Trustee} -ErrorAction Stop
        Write-Detail ("REMOVED SendOnBehalf: " + $Trustee) Green
    }`;
```

The per-block `try/catch` and `$script:ok++` bookkeeping are gone: `Invoke-WithRetry` now owns
error handling, and a throw from any block fails the whole trustee, which is correct. A trustee
who got FullAccess but failed SendAs is reported as failed and appears in the failures CSV.

- [ ] **Step 2: Replace the `body` template**

```javascript
    const permLabel = isGrant ? "Granting access on " : "Removing access on ";
    const didWord   = isGrant ? "GRANTED" : "REMOVED";

    const body = `
# --- Access change worker -----------------------------------------
function Invoke-AccessChange {
    param([string]$Trustee)

${fullBlock}

${sendAsBlock}

${onBehalfBlock}
}

# --- Phase 3: Compare against current access ----------------------
Write-Step 3 ${ctx.phases} "Comparing your list against current access..."

if (-not ($DoFullAccess -or $DoSendAs -or $DoSendOnBehalf)) {
    Write-Detail "No permission types were selected. Nothing to do." Yellow
    Stop-Run "" Yellow 0
}

$ToApply = @()
foreach ($t in $Trustees) {
    $id = [string]$t
    if (-not [string]::IsNullOrWhiteSpace($id)) { $ToApply += $id.Trim() }
}
$ToApply = @($ToApply)

Write-Detail ($Trustees.Count.ToString() + " in list  |  " + $ToApply.Count + " to process")
$permList = @()
if ($DoFullAccess)   { $permList += "Full Access" }
if ($DoSendAs)       { $permList += "Send As" }
if ($DoSendOnBehalf) { $permList += "Send on Behalf" }
Write-Detail ("Permissions: " + ($permList -join ", "))

if ($ToApply.Count -eq 0) { Stop-Run "Nothing to do." Green 0 }

# Capability probe. Confirms this account can change permissions on this mailbox
# before any real change, and fails with actionable text if not.
try {
    Get-MailboxPermission -Identity $Mailbox -ErrorAction Stop | Out-Null
    Write-Detail "Permission check passed." Green
} catch {
    Write-Detail ("ERROR: This account cannot read or change permissions on '$Mailbox'. " + $_.Exception.Message) Red
    Write-Detail "You need a role with mailbox permission rights, for example Recipient Management." Yellow
    Stop-Run "" Red 1
}

Confirm-Apply $ToApply.Count "users"

# --- Phase 4: Apply changes ---------------------------------------
Write-Step 4 ${ctx.phases} "Applying changes..."

$script:RunTotal    = $ToApply.Count
$script:RunActivity = "${permLabel}" + $Mailbox
$script:RunStart    = Get-Date
$script:RunCurrent  = 0
Update-Run -Force

$failRows    = New-Object System.Collections.Generic.List[object]
$consecutive = 0
$aborted     = $false
$chunkCount  = [Math]::Ceiling($script:RunTotal / $script:ChunkSize)
$i           = 0

$applyOne = { param($Identity) Invoke-AccessChange -Trustee $Identity }

for ($c = 1; $c -le $chunkCount; $c++) {
    if ($aborted) { break }

    if (((Get-Date) - $script:ConnectedAt).TotalMinutes -ge $script:RefreshMinutes) {
        Write-Detail ("Session has been open " + $script:RefreshMinutes + "+ minutes. Refreshing before the next chunk.") Yellow
        if (-not (Reset-Session)) { $aborted = $true; break }
    }

    $end = [Math]::Min($i + $script:ChunkSize, $script:RunTotal)
    while ($i -lt $end) {
        $identity = $ToApply[$i]
        $res      = Invoke-WithRetry -Action $applyOne -Identity $identity
        $i++
        $script:RunCurrent = $i

        if ($res.Ok) {
            $script:RunOk++
            $consecutive = 0
        } else {
            $suffix = ""
            if ($res.Attempts -gt 1) { $suffix = " (after " + $res.Attempts + " attempts)" }
            Write-Detail ("FAILED: " + $identity + " - " + $res.Message + $suffix) Red
            $script:RunFailed++
            $failRows.Add([pscustomobject]@{
                Identity = $identity
                Reason   = $res.Message
                Class    = $res.Class
                Attempts = $res.Attempts
            })

            if ($res.Class -ne "permanent") { $consecutive++ } else { $consecutive = 0 }

            if ($res.Class -eq "dead" -or $consecutive -ge $script:BreakerLimit) {
                if ($res.Class -eq "dead") {
                    Write-Detail "The Exchange session is no longer usable." Yellow
                } else {
                    Write-Detail ($consecutive.ToString() + " consecutive failures. Treating the session as dead.") Yellow
                }
                if (Reset-Session) {
                    $consecutive = 0
                    $i--
                    $script:RunCurrent = $i
                    $failRows.RemoveAt($failRows.Count - 1)
                    $script:RunFailed--
                } else {
                    $aborted = $true
                    break
                }
            }
        }
        Update-Run
    }

    if (-not $aborted) {
        Write-Detail ($script:RunCurrent.ToString() + "/" + $script:RunTotal + "   " + $script:RunOk + " ok, " + $script:RunFailed + " failed        (chunk " + $c + " of " + $chunkCount + " done, session ok)") Cyan
    }
}
Update-Run -Force

if ($aborted) {
    Write-Detail "" Yellow
    Write-Detail ("STOPPED EARLY at user " + $script:RunCurrent + " of " + $script:RunTotal + ".") Yellow
    Write-Detail "Re-run this script to finish. Re-applying an existing permission is harmless." Yellow
}

$failFile = ""
if ($failRows.Count -gt 0) {
    $failFile = Join-Path $PSScriptRoot (${psStr(ctx.logBase)} + "-" + $stamp + "-failures.csv")
    $failRows | Export-Csv -Path $failFile -NoTypeInformation -Encoding UTF8
}
`;
```

Note the mailbox path deliberately does **not** diff current permissions into a skip list.
`Get-MailboxPermission` plus `Get-RecipientPermission` plus `GrantSendOnBehalfTo` is three reads
producing three different shapes, and re-applying an existing permission is harmless and fast.
The read is used purely as a capability probe. This is a deviation from spec §3's table, taken
because the group-member case is the one with 1896 entries; a shared mailbox has a handful.

- [ ] **Step 3: Replace the mailbox summary string**

```javascript
    const summary =
      'Write-Detail ("' + didWord.padEnd(10) + ' : " + $script:RunOk)\n' +
      'Write-Detail ("Failed     : " + $script:RunFailed)\n' +
      'Write-Detail ("Reconnects : " + $script:RunReconnects)\n' +
      'if ($failFile) { Write-Detail ("Failures   : " + $failFile) Yellow }\n';
```

- [ ] **Step 4: Syntax check and sweep**

Expected: `--check` silent; `files with parse errors: 0`

- [ ] **Step 5: Confirm `$Preview` is fully gone and AutoMapping survived**

```bash
grep -c "Preview" "$TEMP/gi-shared-mailbox-grant-small.ps1"
```

Expected: `0`

```bash
grep -n "AutoMapping \$AutoMapping" "$TEMP/gi-shared-mailbox-grant-small.ps1"
grep -n "AutoMapping    = \$False" "$TEMP/gi-shared-mailbox-grant-nomap-small.ps1"
```

Expected: one hit each. The AutoMapping-off variant must still render with `$False`.

- [ ] **Step 6: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: apply chunking, retry and reconnect to the mailbox permission script"
```

---

## Task 8: Update the prologue's "what this does" header text

The header still promises a `-WhatIf` dry run, which no longer happens.

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`psPrologue`, the `steps` array ~line 121-134)

- [ ] **Step 1: Replace the write-op `steps` array**

Find:

```javascript
      : [
          "#    1. Connects to Exchange Online in your own admin context.",
          "#    2. Starts a transcript next to this script for audit.",
          "#    3. Runs every change with -WhatIf first, so nothing changes yet.",
          "#    4. Waits for you to type YES, then applies the changes for real.",
        ];
```

Replace with:

```javascript
      : [
          "#    1. Connects to Exchange Online in your own admin context.",
          "#    2. Starts a transcript next to this script for audit.",
          "#    3. Reads the current state and shows you exactly what will change.",
          "#    4. Waits for you to type YES, then applies the changes for real.",
          "#    5. Retries transient errors, and reconnects by itself if the",
          "#       Exchange session drops part-way through a long run.",
          "#    6. Writes a failures CSV next to this script if anything fails,",
          "#       so you can finish the job by re-uploading just those entries.",
        ];
```

- [ ] **Step 2: Syntax check, sweep, and read the header**

```bash
/c/dev/tools/nodejs/node.exe --check /c/dev/projects/it-tools/tools/group-import/exo-scripts.js
/c/dev/tools/nodejs/node.exe "$TEMP/gi-sweep.js"
head -25 "$TEMP/gi-distribution-list-add-small.ps1"
```

Expected: no `-WhatIf` promise in the header; the six new lines present.

- [ ] **Step 3: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: correct the generated-script header now the dry run is a diff"
```

---

## Task 9: Remove the `Write-Head` / `Write-Item` shims

**Files:**
- Modify: `tools/group-import/exo-scripts.js`

- [ ] **Step 1: Find every remaining call site**

```bash
cd /c/dev/projects/it-tools/tools/group-import
grep -n "Write-Head\|Write-Item" exo-scripts.js
```

Expected: the two `function` definitions in `psPrologue`, plus remaining calls in the two
**export** branches (which Tasks 5-7 did not touch).

- [ ] **Step 2: Convert the export branches**

In `buildGroupMemberScript`'s export branch, change `Write-Head "Reading current members..."` to
`Write-Step 3 ${ctx.phases} "Reading current members..."` and every `Write-Item` to
`Write-Detail`.

In `buildMailboxPermissionScript`'s export branch, change
`Write-Head "Reading access permissions..."` to
`Write-Step 3 ${ctx.phases} "Reading access permissions..."` and every `Write-Item` to
`Write-Detail`.

- [ ] **Step 3: Delete the two shim definitions**

Remove these two lines from the `psPrologue` template:

```
function Write-Head { param([string]$Message) Write-Host ""; Write-Host "  $Message" -ForegroundColor Cyan }
function Write-Item { param([string]$Message, [string]$Color = "Gray") Write-Host "    $Message" -ForegroundColor $Color }
```

- [ ] **Step 4: Prove nothing references them**

```bash
grep -c "Write-Head\|Write-Item" exo-scripts.js
```

Expected: `0`

- [ ] **Step 5: Syntax check and sweep**

Expected: `--check` silent; `files with parse errors: 0`

- [ ] **Step 6: Prove no rendered script calls an undefined function**

```bash
pwsh -NoProfile -Command "
Get-ChildItem \$env:TEMP\gi-*.ps1 | ForEach-Object {
  \$t=[System.Management.Automation.Language.Parser]::ParseFile(\$_.FullName,[ref]\$null,[ref]\$null)
  \$defined = \$t.FindAll({param(\$n) \$n -is [System.Management.Automation.Language.FunctionDefinitionAst]},\$true) | ForEach-Object { \$_.Name }
  \$called  = \$t.FindAll({param(\$n) \$n -is [System.Management.Automation.Language.CommandAst]},\$true) | ForEach-Object { \$_.GetCommandName() } | Where-Object { \$_ -like 'Write-*' -or \$_ -like '*-Run' -or \$_ -like 'Confirm-*' -or \$_ -like 'Test-*' -or \$_ -like 'Show-*' -or \$_ -like 'Invoke-With*' -or \$_ -like 'Reset-*' -or \$_ -like 'Get-FailureClass' }
  \$missing = \$called | Sort-Object -Unique | Where-Object { \$_ -notin \$defined -and \$_ -notin @('Write-Host','Write-Progress','Write-Output','Write-Error','Write-Warning','Test-Path','Invoke-WithRetry') }
  if (\$missing) { Write-Host (\$_.Name + ' -> ' + (\$missing -join ', ')) -Fore Red }
}
Write-Host 'undefined-helper scan done'
"
```

Expected: only `undefined-helper scan done`, with no red lines. `Invoke-WithRetry` is whitelisted
because it is defined in `psPrologue` and this crude matcher can miss it.

- [ ] **Step 7: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: retire Write-Head and Write-Item from generated scripts"
```

---

## Task 10: Replay the 2026-09-08 incident against the stub harness

This is the task that proves the fix. It needs no Exchange tenant.

**Files:**
- Create: `%TEMP%\gi-stub-incident.ps1` (never committed)

- [ ] **Step 1: Render a large add script to work from**

```bash
/c/dev/tools/nodejs/node.exe "$TEMP/gi-sweep.js"
ls -la "$TEMP/gi-distribution-list-add-large.ps1"
```

Expected: the file exists and is non-empty.

- [ ] **Step 2: Build the stub harness**

Write this to `$env:TEMP\gi-stub-incident.ps1`. It loads the generated script's phase-4 logic
with every Exchange cmdlet stubbed, reproducing the exact incident: a transient error at entry
374, then the `GetResponseHeader` failure from entry 614 until a reconnect happens.

```powershell
# %TEMP%\gi-stub-incident.ps1  — throwaway, never committed
$ErrorActionPreference = "Continue"

$script:calls        = 0
$script:sessionDead  = $true   # dead from entry 614 until Connect-ExchangeOnline runs
$script:reconnects   = 0
$script:deadFrom     = 614

function Connect-ExchangeOnline    { param([switch]$ShowBanner) $script:sessionDead = $false; $script:reconnects++ }
function Disconnect-ExchangeOnline { param([switch]$Confirm) }
function Get-DistributionGroup     { param($Identity) [pscustomobject]@{ DisplayName="zGlobalProviderAll"; PrimarySmtpAddress="z@x.com"; RecipientTypeDetails="MailUniversalDistributionGroup" } }
function Stop-Transcript           { }
function Start-Transcript           { param($Path) }

function Add-DistributionGroupMember {
    param($Identity, $Member, [switch]$BypassSecurityGroupManagerCheck, [switch]$WhatIf)
    if ($WhatIf) { return }
    $script:calls++
    if ($script:calls -eq 374) {
        throw "A server side error has occurred because of which the operation could not be completed. Please try again after some time."
    }
    if ($script:calls -ge $script:deadFrom -and $script:sessionDead) {
        throw "Method invocation failed because [System.Net.Http.HttpResponseMessage] does not contain a method named 'GetResponseHeader'."
    }
}

# Pull the generated helpers and the phase-4 loop out of the real script.
$gen = Get-Content "$env:TEMP\gi-distribution-list-add-large.ps1" -Raw

# Helpers: everything from the run-state block to the end of Reset-Session.
$helpers = [regex]::Match($gen, '(?s)# --- Run state.*?\n}\r?\n(?=\r?\n# --- Phase 1)').Value
Invoke-Expression $helpers

function Test-Target { Get-DistributionGroup -Identity "z@x.com" }

$Target  = "zGlobalProviderAll@corrohealth.com"
$stamp   = "stub"
$PSScriptRoot = $env:TEMP
$ToApply = @(1..1896 | ForEach-Object { "bulk$_@corrohealth.com" })

# Make the stub run fast: no real backoff sleeps.
$script:Backoff = @(0, 0)

$phase4 = [regex]::Match($gen, '(?s)# --- Phase 4: Apply changes.*?(?=\r?\n# --- Phase 5)').Value
Invoke-Expression $phase4

Write-Host ""
Write-Host "=== STUB RESULTS ==="
Write-Host ("cmdlet calls   : " + $script:calls)
Write-Host ("ok             : " + $script:RunOk)
Write-Host ("failed         : " + $script:RunFailed)
Write-Host ("reconnects     : " + $script:RunReconnects)
Write-Host ("stub reconnects: " + $script:reconnects)
Write-Host ("failure rows   : " + $failRows.Count)
```

- [ ] **Step 3: Run it**

```bash
pwsh -NoProfile -File "$TEMP/gi-stub-incident.ps1" 2>&1 | tail -30
```

- [ ] **Step 4: Assert the results**

Expected, and each of these is a distinct claim about the fix:

| Line | Expected | Proves |
|---|---|---|
| `ok` | `1896` | Every member eventually succeeded. The old script managed 612. |
| `failed` | `0` | The transient error at 374 was retried, not lost. Compare: it silently dropped one member on 2026-09-08. |
| `reconnects` | `1` | The breaker fired once and recovery worked. |
| `failure rows` | `0` | No spurious rows in the failures CSV. |

**Critical:** `failed` must **not** be anywhere near `1284`. If it is, the breaker never fired
and the cascade is still present.

- [ ] **Step 5: Prove the breaker fires promptly, not after 1283 attempts**

Change `$script:deadFrom = 614` to a permanent dead session by removing the reconnect recovery:
edit the stub so `Connect-ExchangeOnline` does **not** clear `$script:sessionDead`:

```powershell
function Connect-ExchangeOnline { param([switch]$ShowBanner) $script:reconnects++ }
```

Re-run.

Expected: `ok` is `613`, `failed` is between `10` and `40`, and `reconnects` is `3` — the run
aborts after the reconnect cap instead of grinding through the remaining 1283. The old script's
number here was 1284.

Restore the working `Connect-ExchangeOnline` stub afterwards.

- [ ] **Step 6: Prove a bad list does not trip the breaker**

Add a second stub scenario: make entries 1-10 all throw a permanent error.

```powershell
function Add-DistributionGroupMember {
    param($Identity, $Member, [switch]$BypassSecurityGroupManagerCheck, [switch]$WhatIf)
    if ($WhatIf) { return }
    $script:calls++
    if ($script:calls -le 10) { throw "Couldn't be found on 'corrohealth.onmicrosoft.com'." }
}
```

Set `$ToApply` to 20 entries and re-run.

Expected: `ok` is `10`, `failed` is `10`, **`reconnects` is `0`**, and the run completes without
aborting. Ten consecutive permanent failures must not be mistaken for a dead session. If
`reconnects` is not 0, the `$res.Class -ne "permanent"` guard is broken.

- [ ] **Step 7: Commit**

Nothing to commit — the harness lives in `$TEMP` by design. Record the results in the task
checkbox and move on.

---

## Task 11: Small-run sanity, changelog and version

**Files:**
- Modify: `changelog.json`
- Modify: `config.json`

- [ ] **Step 1: Confirm a 20-member run stays quiet**

```bash
wc -l "$TEMP/gi-distribution-list-add-small.ps1" "$TEMP/gi-distribution-list-add-large.ps1"
grep -c "ChunkSize\|RefreshMinutes" "$TEMP/gi-distribution-list-add-small.ps1"
```

Expected: the small and large scripts differ **only** in the `$Members` array length. All the
resilience machinery is present but inert. Per spec, none of it should be perceptible on a small
run: 20 members is one chunk, the 40-minute refresh never fires, and the breaker cannot fire on
bad data.

- [ ] **Step 2: Read the current hub version**

```bash
cd /c/dev/projects/it-tools
grep -n '"version"' config.json | head -3
head -12 changelog.json
```

- [ ] **Step 3: Add the changelog entry**

Insert a new entry at the **top** of the entries array in `changelog.json`, with the version
bumped one patch above the current hub version and today's date. Tech-facing wording, no em
dashes:

```json
{
  "version": "<current + 0.0.1>",
  "date": "2026-09-08",
  "notes": [
    "Group Administration: Exchange scripts now check current membership first, so anyone already in the group is skipped instead of being re-attempted, and the preview is a short summary instead of thousands of lines",
    "Group Administration: Exchange scripts now show a progress bar with a running count, time remaining, and the current connection status",
    "Group Administration: Exchange scripts now retry temporary Exchange errors and reconnect by themselves if the session drops during a long run",
    "Group Administration: if anything fails, a failures CSV is saved next to the log so you can finish the job by re-uploading just those entries"
  ]
}
```

- [ ] **Step 4: Bump the hub version in `config.json`**

Set `version` to the same value used in the changelog entry.

- [ ] **Step 5: Verify both files are valid JSON**

```bash
/c/dev/tools/nodejs/node.exe -e 'require("./changelog.json"); require("./config.json"); console.log("both parse")'
```

Expected: `both parse`

- [ ] **Step 6: Commit**

```bash
git add changelog.json config.json
git commit -m "Group Admin: changelog and version bump for the script hardening"
```

---

## Task 12: Manual live matrix (Josh and Krista)

Not automatable. This is Task 18 from the v2 plan, still never run, and the stub harness does
**not** replace it. The stub proves the resilience logic; only a real tenant proves the cmdlets.

**Files:**
- No changes; testing only.

**Prerequisites:** a disposable test distribution list, a disposable test mail-enabled security
group, a disposable test shared mailbox, two test user accounts, and a small CSV with one
deliberately bad row.

- [ ] **Step 1: Push to `testing` and confirm the preview deploy**

Per the two-hop preview deploy: confirm both the `it-tools` "Deploy to Preview" run and the
`it-tools-preview` Pages build report `success` with matching `head_sha`, then `curl` the served
page to confirm the new `exo-scripts.js` is live. Do not match on newest-run; match on
`head_sha`.

- [ ] **Step 2: Small DL matrix on the test list**

| Operation | Expected |
|---|---|
| Add 2 users + 1 bad row | 2 added, 1 failed as permanent, breaker never fires, failures CSV holds exactly the bad row |
| Add the same 2 users again | 2 skipped, 0 added, script exits at phase 3 with "Nothing to do" |
| Remove 1 user | 1 removed, 1 skipped |
| Export | CSV written, 3 phases only, never `/5` |

- [ ] **Step 3: Shared mailbox matrix**

Grant Full Access + Send As to 1 test user with AutoMapping on, confirm both applied; repeat with
AutoMapping off; remove; export.

- [ ] **Step 4: The real run**

Krista re-runs the full `zGlobalProviderAll` list of 1896. Expected:

- Phase 3 reports roughly 612 already members and roughly 1284 to add.
- The run crosses 40 minutes and the **proactive refresh fires at least once**, visible as
  "Session has been open 40+ minutes" in the transcript and `Reconnects : 1` or more in the
  summary.
- Final `Failed` is in single digits, not four.
- `sangeeta.vedpal@corrohealth.com` is added this time. That member was silently lost to the
  un-retried transient error on 2026-09-08.

- [ ] **Step 5: Promote to `main` only after step 4 passes**

Josh's explicit call. Do not merge on the strength of the stub harness alone.

---

## Self-review

**Spec coverage.**

| Spec section | Task |
|---|---|
| §1 primitives, `Write-Step` / `Write-Detail` / `Confirm-Continue` / `Confirm-Apply` | 1, 9 |
| §1 progress bar, `Classic`, throttle, connection status | 1 |
| §2 phase structure, per-shape totals | 3, 4 |
| §3 membership diff, buckets, sampled output | 5 |
| §3 capability probe | 5 (groups), 7 (mailbox) |
| §4 chunking, retry, backoff, transient vs permanent | 2, 6, 7 |
| §5 breaker, signature match, reconnect, 40-min refresh, cap of 3 | 2, 6, 7 |
| §5 small-run behaviour table | 11 |
| §6 summary buckets and failures CSV | 6, 7 |
| §7 `node --check`, render-and-parse, stub harness, manual matrix | every task, 10, 12 |
| §9 changelog | 11 |

**Two deliberate deviations from the spec, both recorded inline where they occur:**

1. **Retry delays** are 2s then 6s over 3 attempts, not 2/6/15. Three attempts allow only two
   sleeps. (Top of this plan.)
2. **The shared-mailbox path does not build a skip list**, only a capability probe. Diffing three
   different permission shapes is disproportionate when a shared mailbox has a handful of
   trustees, and re-applying an existing permission is harmless. (Task 7, Step 2.)

**Placeholder scan.** No `TBD`, no "add error handling", no "similar to Task N". Every code step
carries complete code. Task 11's version number is intentionally computed from the current
`config.json` at execution time rather than guessed here.

**Type and name consistency.** Checked across tasks: `$script:RunOk` (not `$ok`), `$script:RunTotal`,
`$script:RunCurrent`, `$script:RunFailed`, `$script:RunSkipped`, `$script:RunReconnects`,
`$script:RunStatus`, `$script:RunActivity`, `$script:ConnectedAt`, `$script:LastDraw`;
`$script:ChunkSize`, `$script:MaxAttempts`, `$script:Backoff`, `$script:BreakerLimit`,
`$script:MaxReconnects`, `$script:RefreshMinutes`, `$script:DrawEveryMs`. Functions:
`Write-Step`, `Write-Detail`, `Stop-Run`, `Confirm-Continue`, `Confirm-Apply`, `Update-Run`,
`Test-AnyPattern`, `Get-FailureClass`, `Invoke-WithRetry`, `Reset-Session`, `Test-Target`,
`Show-Sample`, `Invoke-AccessChange`. `Invoke-WithRetry` returns `Ok` / `Attempts` / `Message` /
`Class` and every consumer reads exactly those four keys. `ctx.phases` is defined in Task 3 and
consumed in Tasks 4, 5, 7 and 9.

**One risk worth stating.** Tasks 5, 6 and 7 embed multi-line PowerShell inside JS template
literals, which is where the escaping rules bite. `node --check` will not catch a `${`
interpolation accident or a swallowed backslash; only the `pwsh` parse sweep will, and even that
can miss a semantically-wrong-but-parseable result. Run the sweep after **every** step that edits
a template, not just at the end of a task.
