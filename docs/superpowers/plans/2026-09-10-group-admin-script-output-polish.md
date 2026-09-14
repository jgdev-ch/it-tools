# Group Administration Generated-Script Output Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tighten the console formatting of the generated Exchange scripts and stop the progress
bar flickering, without touching any run logic.

**Architecture:** All changes are in `tools/group-import/exo-scripts.js`, a pure string builder
with no DOM, network or ITTools dependency. Shared PowerShell primitives live in `psPrologue` and
are inherited by every generated shape; the two generators (`buildGroupMemberScript`,
`buildMailboxPermissionScript`) each carry one copy of the chunk milestone line.

**Tech Stack:** ES5-flavoured JS in an IIFE, JS template literals emitting PowerShell 5.1/7
compatible script text, `ExchangeOnlineManagement` 3.9.0+, JSZip for bundling.

**Spec:** `docs/superpowers/specs/2026-09-10-group-admin-script-output-polish-design.md`

---

## Read this before touching any template literal

From the header comment of `exo-scripts.js`. Violating these **silently corrupts** generated
scripts and `node --check` will not catch it:

- Never emit PowerShell `${var}` syntax. `${` interpolates in a JS template literal. Use `$var`
  and `$(...)` only.
- Write `\\` for every literal backslash. A lone `\` eats the next character.
- Never emit PowerShell backticks: no line continuations, no backtick-n. One line per cmdlet.
- Every injected value goes through `psStr()`.

**Specific to this plan:** Task 4 introduces PowerShell format strings containing `{0,$w}` width
specifiers. These are safe (`$` is followed by `w`, not `{`) but must be checked by eye. If you
ever write `${w}` the generated script silently loses the width.

## Verification model

This repo has **no JS or PowerShell test framework.** Do not invent one. There is no `npm test`.
Verification is four existing gates plus three new harnesses, all of which run with no Exchange
tenant.

**Existing gates**, referenced throughout as *the four gates*:

```bash
# 1. JS syntax
/c/dev/tools/nodejs/node.exe --check /c/dev/projects/it-tools/tools/group-import/exo-scripts.js

# 2. Render 20 shapes, 3. parse each with the PowerShell parser
/c/dev/tools/nodejs/node.exe "$TEMP/gi-sweep.js"
pwsh -NoProfile -File "$TEMP/gi-parse.ps1"

# 4. Undefined-helper scan
pwsh -NoProfile -File "$TEMP/gi-helpers.ps1"
```

Expected: `--check` silent and exit 0, `rendered 20 scripts`, `files with parse errors: 0`,
`undefined-helper scan done` with no red lines.

**Stub harness**, referenced as *the stub*, must stay green and unchanged by this work:

```bash
pwsh -NoProfile -File "$TEMP/gi-stub-incident.ps1" -Scenario recover
pwsh -NoProfile -File "$TEMP/gi-stub-incident.ps1" -Scenario permadead
pwsh -NoProfile -File "$TEMP/gi-stub-incident.ps1" -Scenario badlist
```

Expected, unchanged from 2026-09-09: `recover` 1896 ok / 0 failed / 1 reconnect / 0 rows;
`permadead` 612 ok / 3 reconnects / aborted True; `badlist` 10 ok / 10 failed / **0 reconnects** /
aborted False.

**These harness files already exist in `$env:TEMP` from the 2026-09-09 session.** If they are gone
(the directory is cleaned periodically), recreate them from
`docs/superpowers/plans/2026-09-08-group-admin-script-hardening.md`, and note two corrections
recorded in `project_group_admin_status`: the helper-extraction regex must anchor on the `$stamp`
line, and `$PSScriptRoot` must be string-replaced in the extracted text rather than assigned.

Run the four gates after **every** step that edits a template literal, not just at the end of a
task.

## What no automated gate can check

**The progress bar colour.** Progress output cannot be captured from a piped session. Task 2 is
verified by reading the emitted code, and then by eye on the first real run. This is called out in
the spec and is expected.

---

## File structure

| File | Responsibility | Change |
|---|---|---|
| `tools/group-import/exo-scripts.js` | Generates the `.ps1` + `.bat` + `.zip` | Modified in 6 places |
| `changelog.json` | Hub Recent Updates feed | One note appended to the existing 2.4.3 entry |
| `%TEMP%\gi-redraw.ps1` | Redraw-count harness | Created, never committed |
| `%TEMP%\gi-whatif.ps1` | WhatIf suppression harness | Created, never committed |
| `%TEMP%\gi-align.ps1` | Column alignment harness | Created, never committed |

`exo-scripts.js` is ~975 lines and grows to roughly 1030. It stays one file: the tool loads it
with a single `<script src>` and has no build step, so splitting it would break the load.

---

## Task 1: Progress bar redraws become content-driven

The highest-value change. Harness first, so the ~1284 baseline is measured on unmodified code
before anything is edited.

**Files:**
- Create: `%TEMP%\gi-redraw.ps1`
- Modify: `tools/group-import/exo-scripts.js` (`psPrologue` run-state block and `Update-Run`)

- [ ] **Step 1: Confirm the four gates are green before starting**

Run the four gates. If the baseline is not already clean, stop and fix that first. You cannot
attribute a later failure if you did not start from green.

- [ ] **Step 2: Write the redraw-count harness**

Write to `$env:TEMP\gi-redraw.ps1`. It shadows `Write-Progress` with a counter and `Get-Date` with
a fake clock, so a 1284-entry run at the observed 1.68 s cadence is simulated instantly.

```powershell
# %TEMP%\gi-redraw.ps1  - throwaway, never committed
# Counts real Write-Progress calls over a simulated 1284-entry run.
$ErrorActionPreference = "Stop"

$script:draws = 0
function Write-Progress {
    param($Activity, $Status, $PercentComplete, $SecondsRemaining, [switch]$Completed)
    $script:draws++
}

# Fake clock. Update-Run calls Get-Date with no arguments; shadowing it lets the
# simulation advance time without sleeping. Nothing else in the helper block needs
# a real timestamp.
$script:fakeNow = [datetime]"2026-09-09T16:52:53"
function Get-Date { param([string]$Format) return $script:fakeNow }

# Pull the helper block (run state, tunables, console helpers, classifier,
# Invoke-WithRetry, Reset-Session) out of a rendered script. Anchor on the $stamp
# line: the block ends immediately before it.
$gen = Get-Content "$env:TEMP\gi-distribution-list-add-large.ps1" -Raw
$helpers = [regex]::Match($gen, '(?s)# --- Run state.*?(?=\r?\n\$stamp\s+= Get-Date)').Value
if (-not $helpers) { throw "helper block not found" }
if ($helpers -notmatch 'function Update-Run') { throw "helper block is truncated: Update-Run missing" }
Invoke-Expression $helpers

$total   = 1284
$perItem = 1.68

$script:RunTotal    = $total
$script:RunActivity = "Adding members to zExampleGroupAll@corrohealth.com"
$script:RunStatus   = "Connected"
$script:RunSkipped  = 612
$script:RunStart    = $script:fakeNow
$script:RunCurrent  = 0
$script:RunOk       = 0
$script:RunFailed   = 0

for ($i = 1; $i -le $total; $i++) {
    $script:fakeNow    = $script:fakeNow.AddSeconds($perItem)
    $script:RunCurrent = $i
    $script:RunOk      = $i
    Update-Run
}

Write-Host ""
Write-Host "=== REDRAW COUNT ==="
Write-Host ("entries        : " + $total)
Write-Host ("Write-Progress : " + $script:draws)
Write-Host ("draws / entry  : " + [math]::Round($script:draws / $total, 3))
```

- [ ] **Step 3: Run the harness against unmodified code to establish the baseline**

```bash
pwsh -NoProfile -File "$TEMP/gi-redraw.ps1"
```

Expected: `Write-Progress : 1284` and `draws / entry : 1`. One redraw per member, which is the
defect. If this reports a number well below 1284, the harness is not exercising the real
`Update-Run` and must be fixed before continuing.

- [ ] **Step 4: Add the new run-state fields**

In `exo-scripts.js`, find this line in the `psPrologue` run-state block:

```javascript
$script:LastDraw      = [datetime]::MinValue
```

Replace it with:

```javascript
$script:LastDraw      = [datetime]::MinValue
$script:LastPct       = -1
$script:LastLeft      = -1
$script:LastState     = ""
```

- [ ] **Step 5: Add the ETA bucket tunable and raise the draw floor**

Find:

```javascript
$script:RefreshMinutes = 30
$script:DrawEveryMs    = 250
```

Replace with:

```javascript
$script:RefreshMinutes = 30
$script:EtaBucket      = 30
$script:DrawEveryMs    = 500
```

- [ ] **Step 6: Replace `Update-Run`**

Replace the whole `Update-Run` function in the `psPrologue` template with:

```javascript
function Update-Run {
    param([switch]$Force)
    $now = Get-Date

    $pct = 0
    if ($script:RunTotal -gt 0) {
        $pct = [int](($script:RunCurrent / $script:RunTotal) * 100)
        if ($pct -gt 100) { $pct = 100 }
    }

    # ETA, quantised into buckets so it stops changing on every single entry.
    $left = -1
    if ($script:RunCurrent -gt 0 -and $script:RunTotal -gt 0) {
        $per  = ($now - $script:RunStart).TotalSeconds / $script:RunCurrent
        $raw  = $per * ($script:RunTotal - $script:RunCurrent)
        $left = [int]([Math]::Round($raw / $script:EtaBucket) * $script:EtaBucket)
    }

    # Redraw only when something a viewer can actually see has changed. This is
    # deliberately NOT a comparison of the composed status string: that string
    # carries $script:RunCurrent, which increments on every entry, so comparing it
    # would never match and the redraw rate would be unchanged. Percent, the ETA
    # bucket and the connection state all change slowly. The visible cost is that
    # the counter advances in steps of roughly 13 rather than 1.
    if (-not $Force -and
        $pct  -eq $script:LastPct  -and
        $left -eq $script:LastLeft -and
        $script:RunStatus -eq $script:LastState) { return }

    # Time floor, measured from the last real draw rather than the last call.
    if (-not $Force -and ($now - $script:LastDraw).TotalMilliseconds -lt $script:DrawEveryMs) { return }

    $script:LastDraw  = $now
    $script:LastPct   = $pct
    $script:LastLeft  = $left
    $script:LastState = $script:RunStatus

    $status = $script:RunStatus + "  |  " + $script:RunCurrent + "/" + $script:RunTotal + "  |  " + $script:RunOk + " ok, " + $script:RunFailed + " failed, " + $script:RunSkipped + " skipped"
    try {
        if ($left -ge 0) {
            Write-Progress -Activity $script:RunActivity -Status $status -PercentComplete $pct -SecondsRemaining $left
        } else {
            Write-Progress -Activity $script:RunActivity -Status $status -PercentComplete $pct
        }
    } catch { }
}
```

- [ ] **Step 7: Run the four gates**

Expected: `--check` silent, `rendered 20 scripts`, `files with parse errors: 0`,
`undefined-helper scan done` clean.

- [ ] **Step 8: Re-run the redraw harness and confirm the reduction**

```bash
/c/dev/tools/nodejs/node.exe "$TEMP/gi-sweep.js"
pwsh -NoProfile -File "$TEMP/gi-redraw.ps1"
```

Expected: `Write-Progress` **under 200**, versus 1284 at Step 3. Roughly 160 is the predicted
value: percent ticks ~100 times and the 30-second ETA bucket changes ~72 times over the run.

If it is still near 1284, the content gate is not firing. The most likely cause is comparing the
composed `$status` string somewhere instead of `$pct` / `$left` / `$script:RunStatus`.

- [ ] **Step 9: Confirm the forced draws still work**

```bash
grep -c "Update-Run -Force" "$TEMP/gi-distribution-list-add-large.ps1"
```

Expected: `5`, verified against the rendered output on 2026-09-10. Three are in `Reset-Session`
(entering `Reconnecting...`, reconnect success, reconnect failure) and two are in the apply body
(phase 4 start, and after the chunk loop finishes). All five must draw regardless of the content
gate, because each marks a state change a viewer needs to see immediately. If this is lower, a
`-Force` call was lost; if the count differs between shapes, one generator was missed:

```bash
grep -c "Update-Run -Force" "$TEMP/gi-shared-mailbox-grant-small.ps1"
```

Expected: `5` here too.

- [ ] **Step 10: Run the stub, all three scenarios**

Expected: unchanged from 2026-09-09. `Update-Run` is called from the apply loop, so a mistake here
could silently change control flow.

- [ ] **Step 11: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: redraw the progress bar on content change, not on a timer"
```

---

## Task 2: Progress bar colour becomes teal

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`psPrologue`, the progress placement guard)

- [ ] **Step 1: Replace the progress placement guard**

Find:

```javascript
# Progress bar placement. PowerShell 7 defaults to "Minimal", which pins the bar to the
# bottom of the console. "Classic" restores the 5.1 top block so the status line stays in
# one fixed place while the log scrolls underneath. $PSStyle does not exist on 5.1.
if ($null -ne $PSStyle) { try { $PSStyle.Progress.View = "Classic" } catch { } }
```

Replace with:

```javascript
# Progress bar placement. PowerShell 7 defaults to "Minimal", which pins the bar to the
# bottom of the console. "Classic" restores the 5.1 top block so the status line stays in
# one fixed place while the log scrolls underneath. $PSStyle does not exist on 5.1.
if ($null -ne $PSStyle) { try { $PSStyle.Progress.View = "Classic" } catch { } }

# Progress bar colour. Classic view reads its colours from $Host.PrivateData on both
# 5.1 and 7, not from $PSStyle.Progress.Style, which applies only to Minimal view.
# One code path therefore covers both hosts, and the named console colour resolves
# through the terminal's own palette so the result is identical on each. The default
# is yellow, which is already this script's warning colour for refresh, reconnect and
# abort messages, so the always-on bar was competing with real warnings.
# PrivateData is absent or differently shaped on non-console hosts, hence the guard.
try {
    $Host.PrivateData.ProgressBackgroundColor = "Cyan"
    $Host.PrivateData.ProgressForegroundColor = "Black"
} catch { }
```

- [ ] **Step 2: Run the four gates**

Expected: all clean.

- [ ] **Step 3: Confirm the emitted code and that no dead `$PSStyle.Progress.Style` crept in**

```bash
grep -n "ProgressBackgroundColor\|ProgressForegroundColor\|Progress.View\|Progress.Style" "$TEMP/gi-distribution-list-add-small.ps1"
```

Expected exactly three hits: the `Progress.View` line, `ProgressBackgroundColor = "Cyan"`, and
`ProgressForegroundColor = "Black"`. There must be **no** `Progress.Style` hit; that property only
affects Minimal view and would be dead code.

- [ ] **Step 4: Confirm the guard survived**

```bash
grep -c "try {" "$TEMP/gi-shared-mailbox-export-small.ps1"
```

Expected: at least `1`. The point of this check is that the colour block is inside a `try/catch`,
because `$Host.PrivateData` throws on hosts that do not implement it. Read the surrounding lines
to confirm visually.

- [ ] **Step 5: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: colour the generated-script progress bar teal instead of warning yellow"
```

---

## Task 3: Label the `-WhatIf` leak

> **Revised 2026-09-10 during execution.** Steps 1 and 2 ran as written and the harness
> **disproved the planned fix**: `*> $null` does not suppress the line. `ShouldProcess` writes to
> the host past all six streams. `-InformationAction Ignore` also has no effect, and muting
> `[Console]::Out` suppresses it but permanently silences the host for the rest of the run. Josh
> chose to label the line instead of removing the probe. Step 3 below is the revised fix; steps 1
> and 2 are unchanged and are what found this. Expected output for step 2 is corrected to reflect
> reality.

Harness first. The trap here is fixing the visible half (text suppressed) while breaking the
invisible half (the error must still reach `catch`).

**Files:**
- Create: `%TEMP%\gi-whatif.ps1`
- Modify: `tools/group-import/exo-scripts.js` (`buildGroupMemberScript`, the phase 3 capability probe)

- [ ] **Step 1: Write the WhatIf harness**

Write to `$env:TEMP\gi-whatif.ps1`. Each case runs in a child `pwsh` so output is captured from
outside, which is the only reliable way to observe host chatter.

```powershell
# %TEMP%\gi-whatif.ps1  - throwaway, never committed
# Proves "*> $null" hides the What if: text AND still lets -ErrorAction Stop throw.
$stub = @'
function Test-Probe {
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$Boom)
    if ($Boom) { throw "This account cannot modify the group." }
    $null = $PSCmdlet.ShouldProcess("zGlobalProviderAll", "Add member")
}
'@

function Invoke-Case {
    param([string]$Name, [string]$Body)
    $out = pwsh -NoProfile -Command ($stub + "`n" + $Body) 2>&1 | Out-String
    return [pscustomobject]@{ Name = $Name; Output = $out.Trim() }
}

$a = Invoke-Case "unsuppressed"    'Test-Probe -WhatIf'
$b = Invoke-Case "suppressed"      'Test-Probe -WhatIf *> $null'
$c = Invoke-Case "still throws"    'try { Test-Probe -Boom -WhatIf -ErrorAction Stop *> $null } catch { "CAUGHT: " + $_.Exception.Message }'

Write-Host ""
Write-Host "=== WHATIF SUPPRESSION ==="
Write-Host ("1. unsuppressed prints What if:  " + $(if ($a.Output -match 'What if:')    { "YES  (expected YES)" } else { "no   <-- FAIL, stub is wrong" }))
Write-Host ("2. suppressed prints nothing  :  " + $(if ($b.Output -eq '')               { "YES  (expected YES)" } else { "no   <-- FAIL: [" + $b.Output + "]" }))
Write-Host ("3. error still reaches catch  :  " + $(if ($c.Output -match '^CAUGHT: ')   { "YES  (expected YES)" } else { "no   <-- FAIL: [" + $c.Output + "]" }))
```

- [ ] **Step 2: Run it**

```bash
pwsh -NoProfile -File "$TEMP/gi-whatif.ps1"
```

**Actual result on pwsh 7.6.5, 2026-09-10:**

```
1. unsuppressed prints What if:  YES  (expected YES)
2. suppressed prints nothing  :  no   <-- FAIL: [What if: Performing the operation ...]
3. error still reaches catch  :  YES  (expected YES)
```

Line 1 proves the stub reproduces the real behaviour. Line 3 proves a redirect does not swallow
the failure the probe exists to catch. **Line 2 is the finding:** the announcement is not on any
stream, so it cannot be redirected. This is expected output for this harness now, not a
regression. Do not try to make line 2 say `YES`.

- [ ] **Step 3: Label the probe instead of suppressing it**

In `buildGroupMemberScript`, inside the `phase3` template, find the three comment lines above the
probe's `try {` and add a labelling line plus a record of what was tested. The probe call itself
does **not** change:

```javascript
# The old -WhatIf loop proved, as a side effect, that this account could write to
# the target. A local diff cannot. One -WhatIf call against the first entry keeps
# that guarantee and fails early with actionable text instead of mid-run.
#
# PowerShell writes its own "What if:" announcement directly to the host, past all
# six streams, so it cannot be redirected or suppressed. Tested 2026-09-10:
# "*> \$null" has no effect; -InformationAction Ignore has no effect; muting
# [Console]::Out does suppress it but permanently silences the host for the rest of
# the run, even after the writer is restored. The line is therefore labelled rather
# than hidden. Do not spend time trying to suppress it again.
Write-Detail 'Checking write permission. The "What if" line below is expected.'
try {
    ${cmdlet} -Identity $Target -Member $ToApply[0] ${liveArgs} -WhatIf -ErrorAction Stop
    Write-Detail "Permission check passed." Green
```

Note `"*> \$null"` inside the comment: the backslash is required so the JS template literal emits
a literal `$null` rather than interpolating. Verify after rendering.

This fixes the line reading as a failure. It does **not** fix the column-zero indentation, which
is not controllable. That limit is accepted; see the spec.

Leave the mailbox generator alone. Its probe is a `Get-MailboxPermission` read piped to
`Out-Null` and never had this problem.

- [ ] **Step 4: Run the four gates**

Expected: all clean.

- [ ] **Step 5: Confirm the label rendered and the escaping held**

```bash
grep -n "Checking write permission" -A 3 "$TEMP/gi-distribution-list-add-large.ps1"
```

Expected: the `Write-Detail` label, then `try {`, then the unchanged probe call, then
`Write-Detail "Permission check passed." Green`.

```bash
grep -c '\\\$null' "$TEMP/gi-distribution-list-add-large.ps1"
```

Expected: `0`. A stray backslash here means the escaping in the comment leaked into the output.

```bash
grep -c 'Checking write permission' "$TEMP/gi-shared-mailbox-grant-small.ps1"
```

Expected: `0`. The mailbox path must not have gained a label it does not need.

- [ ] **Step 6: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: stop the capability probe leaking raw WhatIf text to the console"
```

---

## Task 4: Chunk milestone columns align at any magnitude

**Files:**
- Create: `%TEMP%\gi-align.ps1`
- Modify: `tools/group-import/exo-scripts.js` (both generators, the chunk milestone line)

- [ ] **Step 1: Write the alignment harness**

Write to `$env:TEMP\gi-align.ps1`. The property under test is that **within a single run** every
chunk line puts `(chunk` at the same column. Across runs of different sizes the column legitimately
differs, because the field width derives from that run's total; you never see two runs interleaved.

```powershell
# %TEMP%\gi-align.ps1  - throwaway, never committed
# Reproduces the 2026-09-09 defect: chunk milestone columns drifting once a
# counter gains a digit. Asserts every line in one run agrees on the column.
$total      = 1284
$chunkSize  = 150
$chunkCount = [Math]::Ceiling($total / $chunkSize)

$w   = $total.ToString().Length
$cw  = $chunkCount.ToString().Length
$fmt = "{0,$w}/{1}   {2,$w} ok, {3,$w} failed   (chunk {4,$cw} of {5} done, session ok)"

$cols = @()
Write-Host ""
Write-Host "=== CHUNK LINE ALIGNMENT ==="
for ($c = 1; $c -le $chunkCount; $c++) {
    $current = [Math]::Min($c * $chunkSize, $total)
    $line = $fmt -f $current, $total, $current, 0, $c, $chunkCount
    $cols += $line.IndexOf("(chunk")
    Write-Host ("      " + $line)
}

$unique = $cols | Sort-Object -Unique
Write-Host ""
Write-Host ("distinct (chunk columns : " + $unique.Count + "   [" + ($unique -join ", ") + "]")
Write-Host ("aligned                 : " + $(if ($unique.Count -eq 1) { "YES" } else { "NO  <-- FAIL" }))
```

- [ ] **Step 2: Run it**

```bash
pwsh -NoProfile -File "$TEMP/gi-align.ps1"
```

Expected: `distinct (chunk columns : 1` and `aligned : YES`. This validates the format string
before it is pasted into the generator. If it fails here, fix the format string here, not in
`exo-scripts.js`.

- [ ] **Step 3: Replace the chunk milestone line in the group-member generator**

In `buildGroupMemberScript`, in the `body` template, find:

```javascript
    if (-not $aborted) {
        Write-Detail ($script:RunCurrent.ToString() + "/" + $script:RunTotal + "   " + $script:RunOk + " ok, " + $script:RunFailed + " failed        (chunk " + $c + " of " + $chunkCount + " done, session ok)") Cyan
    }
```

Replace with:

```javascript
    if (-not $aborted) {
        # Field widths come from the run's own totals, so the columns hold whether
        # this is 20 entries or 20,000. The previous version separated fields with a
        # fixed run of spaces, which drifted the moment a counter gained a digit.
        $w   = $script:RunTotal.ToString().Length
        $cw  = $chunkCount.ToString().Length
        $fmt = "{0,$w}/{1}   {2,$w} ok, {3,$w} failed   (chunk {4,$cw} of {5} done, session ok)"
        Write-Detail ($fmt -f $script:RunCurrent, $script:RunTotal, $script:RunOk, $script:RunFailed, $c, $chunkCount) Cyan
    }
```

**Check by eye that you wrote `{0,$w}` and not `${w}`.** The latter would be interpolated by the
JS template literal and silently destroy the format string.

- [ ] **Step 4: Replace the identical line in the mailbox generator**

In `buildMailboxPermissionScript`, in the `body` template, find the same
`if (-not $aborted) { Write-Detail (...) Cyan }` block and apply the **same** replacement, comment
included. There are two copies of this line in the file, one per generator; both must change.

- [ ] **Step 5: Run the four gates**

Expected: all clean.

- [ ] **Step 6: Prove both copies changed and no magic spacing survives**

```bash
grep -c 'fmt -f \$script:RunCurrent' /c/dev/projects/it-tools/tools/group-import/exo-scripts.js
```

Expected: `2`, one per generator.

```bash
grep -c 'failed        (chunk' /c/dev/projects/it-tools/tools/group-import/exo-scripts.js
```

Expected: `0`. The eight-space run is gone.

```bash
grep -n '{0,\$w}' "$TEMP/gi-distribution-list-add-large.ps1" "$TEMP/gi-shared-mailbox-grant-small.ps1"
```

Expected: one hit in each file, with `$w` intact. If you see `{0,}` the interpolation accident
happened.

- [ ] **Step 7: Run the stub and read the real chunk lines**

```bash
pwsh -NoProfile -File "$TEMP/gi-stub-incident.ps1" -Scenario recover 2>&1 | grep "chunk"
```

Expected: 13 chunk lines (1896 entries / 150), every `(chunk` at the same column, and the counts
right-aligned. This is the end-to-end proof, since the stub executes the generated line rather
than a copy of it.

- [ ] **Step 8: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: compute chunk milestone column widths from the run totals"
```

---

## Task 5: The confirm gate records its own approval

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`psPrologue`, `Confirm-Apply`)

- [ ] **Step 1: Replace `Confirm-Apply`**

Find:

```javascript
function Confirm-Apply {
    param([int]$Count, [string]$What = "entries")
    Write-Host ""
    $answer = Read-Host ("      Type YES to apply these changes to " + $Count + " " + $What + " for real (anything else aborts)")
    if ($answer -ne "YES") { Stop-Run "Aborted. No changes were made." Yellow 0 }
}
```

Replace with:

```javascript
function Confirm-Apply {
    param([int]$Count, [string]$What = "entries")
    Write-Host ""
    $answer = Read-Host ("      Type YES to apply these changes to " + $Count + " " + $What + " for real (anything else aborts)")
    if ($answer -ne "YES") { Stop-Run "Aborted. No changes were made." Yellow 0 }
    # PowerShell does not record the Read-Host prompt in the transcript, so without
    # this line the log shows changes being applied with no evidence anyone was asked,
    # and the reader sees a doubled blank line where the prompt should have been.
    Write-Detail ("Confirmed. Applying to " + $Count + " " + $What + " now.") Green
}
```

- [ ] **Step 2: Run the four gates**

Expected: all clean.

- [ ] **Step 3: Confirm the line reached both generators' output**

```bash
grep -c "Confirmed. Applying to" "$TEMP/gi-distribution-list-add-small.ps1" "$TEMP/gi-shared-mailbox-grant-small.ps1"
```

Expected: `1` in each. `Confirm-Apply` lives in the shared prologue, so both inherit it.

- [ ] **Step 4: Confirm export scripts do not gain a confirm gate**

```bash
grep -c "Confirm-Apply \$ToApply" "$TEMP/gi-distribution-list-export-small.ps1"
```

Expected: `0`. Export is read-only and must never prompt.

- [ ] **Step 5: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: record the apply-gate approval in the transcript"
```

---

## Task 6: Run provenance reaches the transcript

The only structural refactor in this plan. The header becomes label/value pairs rendered twice, so
the comment banner and the logged copy cannot drift.

**Files:**
- Modify: `tools/group-import/exo-scripts.js` (`psPrologue` signature and body, and all four call sites)

- [ ] **Step 1: Replace the header construction in `psPrologue`**

Find:

```javascript
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
```

Replace with:

```javascript
  /**
   * extraFields is an array of [label, value] pairs, not pre-formatted comment
   * lines. One list of fields is rendered twice: as the comment banner at the top
   * of the file, and as Write-Detail lines after Start-Transcript. Comments never
   * execute, so before this the transcript recorded no target, operation, count,
   * or generating tech at all.
   */
  function psPrologue(ctx, extraFields) {
    const fields = [
      ["Object type", ctx.typeLabel],
      ["Target", ctx.targetDisplay + " <" + ctx.target + ">"],
      ["Operation", ctx.opLabel],
    ]
      .concat(extraFields || [])
      .concat([
        ["Generated", ctx.timestamp],
        ["Generated by", ctx.tech],
      ]);

    const labelWidth = fields.reduce((w, f) => Math.max(w, f[0].length), 0);
    const pad = label => label + " ".repeat(labelWidth - label.length);

    const header = fields.map(f => "#  " + pad(f[0]) + " : " + f[1]).join("\n");
    const runDetails = fields
      .map(f => "Write-Detail " + psStr(pad(f[0]) + " : " + f[1]))
      .join("\n");
```

- [ ] **Step 2: Emit the run details after `Start-Transcript`**

Still in `psPrologue`, find the tail of the returned template:

```javascript
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $PSScriptRoot (${psStr(ctx.logBase)} + "-" + $stamp + ".log")
Start-Transcript -Path $transcript | Out-Null
`;
```

Replace with:

```javascript
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $PSScriptRoot (${psStr(ctx.logBase)} + "-" + $stamp + ".log")
Start-Transcript -Path $transcript | Out-Null

# --- Run details --------------------------------------------------
# The banner at the top of this file is a comment block and never executes, so
# this is the only record of the run's provenance inside the transcript.
Write-Host ""
Write-Host ("  " + ${psStr(ctx.title)}) -ForegroundColor Cyan
${runDetails}
`;
```

- [ ] **Step 3: Update the group-member write call site**

Find:

```javascript
    return psPrologue(ctx, ["#  Members     : " + ctx.identities.length]) +
```

Replace with:

```javascript
    return psPrologue(ctx, [["Members", String(ctx.identities.length)]]) +
```

- [ ] **Step 4: Update the mailbox write call site**

Find:

```javascript
    const extraHeader = [
      "#  Permissions : " + (permNames.length ? permNames.join(", ") : "none selected"),
      "#  Users       : " + ctx.identities.length,
    ];
```

Replace with:

```javascript
    const extraHeader = [
      ["Permissions", permNames.length ? permNames.join(", ") : "none selected"],
      ["Users", String(ctx.identities.length)],
    ];
```

The `psPrologue(ctx, extraHeader)` call itself needs no change.

- [ ] **Step 5: Confirm the two export call sites need no change**

```bash
grep -n "psPrologue(ctx, \[\])" /c/dev/projects/it-tools/tools/group-import/exo-scripts.js
```

Expected: `2` hits, the group export and mailbox export branches. An empty array is still a valid
`extraFields`, so these are correct as they stand. Do not edit them.

- [ ] **Step 6: Run the four gates**

Expected: all clean. This step is the one most likely to produce a parse error, because
`runDetails` injects generated PowerShell into the template.

- [ ] **Step 7: Read the top of a rendered script**

```bash
head -32 "$TEMP/gi-shared-mailbox-grant-small.ps1"
```

Expected: the comment banner unchanged in appearance, with colons still aligned, and `Permissions`
and `Users` still present.

```bash
grep -n "Run details" -A 10 "$TEMP/gi-shared-mailbox-grant-small.ps1"
```

Expected: the title line, then one `Write-Detail` per field, with labels padded so the colons line
up: `Object type`, `Target`, `Operation`, `Permissions`, `Users`, `Generated`, `Generated by`.

- [ ] **Step 8: Confirm export scripts now log provenance**

```bash
grep -c "^Write-Detail '" "$TEMP/gi-distribution-list-export-small.ps1"
```

Expected: `5`. Export has no extra fields, so it gets the five base ones. This is the shape that
previously logged almost nothing.

- [ ] **Step 9: Confirm the banner and the logged copy cannot disagree**

```bash
grep -c "Generated by :" "$TEMP/gi-distribution-list-add-small.ps1"
```

Expected: `2`, one comment line and one `Write-Detail`, both from the same `fields` array. If this
is `1`, one of the two renderings is not being emitted.

**Match on `Generated by :` with the space and colon, not on `Generated by`.** The banner's own
title line reads `#  Generated by IT Tools Hub, Group Administration`, so the looser pattern
returns 3 and looks like a duplicate that is not there.

- [ ] **Step 10: Run the stub, all three scenarios**

Expected: unchanged. The stub extracts the helper block by anchoring on the `$stamp` line, and this
task adds content **after** `Start-Transcript`, which is after that anchor. Confirm the stub still
finds its helpers rather than throwing `helper block not found`.

- [ ] **Step 11: Commit**

```bash
git add tools/group-import/exo-scripts.js
git commit -m "Group Admin: echo the run header into the transcript for audit"
```

---

## Task 7: Full regression, changelog, and push

**Files:**
- Modify: `changelog.json`

- [ ] **Step 1: Run every gate one final time, together**

```bash
/c/dev/tools/nodejs/node.exe --check /c/dev/projects/it-tools/tools/group-import/exo-scripts.js
/c/dev/tools/nodejs/node.exe "$TEMP/gi-sweep.js"
pwsh -NoProfile -File "$TEMP/gi-parse.ps1"
pwsh -NoProfile -File "$TEMP/gi-helpers.ps1"
pwsh -NoProfile -File "$TEMP/gi-redraw.ps1"
pwsh -NoProfile -File "$TEMP/gi-whatif.ps1"
pwsh -NoProfile -File "$TEMP/gi-align.ps1"
pwsh -NoProfile -File "$TEMP/gi-stub-incident.ps1" -Scenario recover
pwsh -NoProfile -File "$TEMP/gi-stub-incident.ps1" -Scenario permadead
pwsh -NoProfile -File "$TEMP/gi-stub-incident.ps1" -Scenario badlist
```

Expected, all in one pass:

| Gate | Expected |
|---|---|
| `node --check` | silent, exit 0 |
| sweep | `rendered 20 scripts` |
| parse | `files with parse errors: 0` |
| helpers | `undefined-helper scan done`, no red |
| redraw | `Write-Progress` under 200 |
| whatif | three `YES` |
| align | `aligned : YES` |
| stub recover | 1896 ok, 0 failed, 1 reconnect, 0 rows |
| stub permadead | 612 ok, 3 reconnects, aborted True |
| stub badlist | 10 ok, 10 failed, **0 reconnects**, aborted False |

- [ ] **Step 2: Append one note to the existing 2.4.3 changelog entry**

Hub v2.4.3 has not reached production, so this does **not** get a new version. Open
`changelog.json`, find the `2.4.3` entry at the top of `entries`, and append one item to its
`notes` array, after the existing four:

```json
        "Group Administration: cleaner script output, with aligned progress milestones, a steadier progress bar, and the run details now recorded in the log for audit"
```

No em dashes in hub-facing copy. Do not touch the `index.html` footer version; it is already
`v2.4.3`.

- [ ] **Step 3: Verify the JSON still parses**

```bash
cd /c/dev/projects/it-tools
/c/dev/tools/nodejs/node.exe -e 'const c=require("./changelog.json"); console.log("parses, 2.4.3 notes:", c.entries[0].version, c.entries[0].notes.length);'
```

Expected: `parses, 2.4.3 notes: 2.4.3 5`

- [ ] **Step 4: Commit and push to `testing`**

```bash
git add changelog.json
git commit -m "Group Admin: changelog note for the script output polish"
git push origin testing
```

- [ ] **Step 5: Confirm the two-hop preview deploy by `head_sha`**

Match on `head_sha`, never on newest-run. `gh` is not installed on this machine; use the API.

```bash
SHA=$(git rev-parse HEAD)
curl -s -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/jgdev-ch/it-tools/actions/runs?branch=testing&per_page=15" \
  | /c/dev/tools/nodejs/node.exe -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const sha=process.argv[1];JSON.parse(s).workflow_runs.filter(r=>r.head_sha===sha).forEach(r=>console.log(r.name,r.status,r.conclusion))})' "$SHA"
```

Expected: `Deploy to Preview completed success`.

Then confirm hop two on `it-tools-preview`. Its mirror commit message names our sha explicitly, so
check that the newest commit there ends with our sha and that its Pages build reports `success`:

```bash
curl -s -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/jgdev-ch/it-tools-preview/commits?per_page=1" | grep -o "it-tools@[0-9a-f]*"
curl -s -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/jgdev-ch/it-tools-preview/actions/runs?per_page=1" | grep -o '"conclusion": *"[a-z]*"'
```

Expected: the sha printed matches `$SHA`, and the conclusion is `success`. If the run is still
`in_progress`, poll until it completes.

- [ ] **Step 6: Confirm the served file carries the changes**

```bash
curl -s "https://jgdev-ch.github.io/it-tools-preview/tools/group-import/exo-scripts.js" \
  | grep -c "ProgressBackgroundColor\|EtaBucket\|LastState\|Confirmed. Applying to\|Run details"
```

Expected: at least `5`. If this is `0`, the Pages CDN has not caught up; re-request rather than
assuming failure.

---

## Task 8: Visual confirmation and promotion to `main`

Not automatable, and Josh's call. The colour is the one item no gate can verify.

**Files:**
- No changes; verification and promotion only.

- [ ] **Step 1: Eyeball the bar on a real run**

Generate a Distribution List add script from the **preview** hub
(`https://jgdev-ch.github.io/it-tools-preview/tools/group-import/`), run it against a small test
list, and confirm by eye:

| Check | Expected |
|---|---|
| Bar colour | Teal block with dark text, not yellow |
| Bar position | Still pinned to the top of the console |
| Bar steadiness | Counter advances in visible steps rather than ticking every entry, and the bar does not appear to flicker |
| No raw `What if:` line | Phase 3 shows only "Permission check passed." |
| Confirm gate | "Confirmed. Applying to N entries now." appears after typing YES |
| Run details | Target, operation, count and generating tech appear near the top |
| Blank lines | One blank line at each phase boundary, not two |

The bar's fill character is still `o`. That is hardcoded in PowerShell's Classic renderer and is
not configurable; see the spec for why the two alternatives were rejected.

- [ ] **Step 2: Confirm alignment on a run with more than one chunk**

Needs over 150 entries to produce a second chunk line. Confirm the `(chunk` text starts at the
same column on every milestone line.

- [ ] **Step 3: Promote `testing` to `main`**

Josh has already approved promotion pending this polish work. The DL and mail-enabled SG paths
were proven at scale by the 2026-09-09 run of 1284 adds; the shared-mailbox path has still never
run against a tenant, which was a known and accepted risk at the time promotion was agreed.

```bash
cd /c/dev/projects/it-tools
git checkout main
git pull
git merge testing
git push origin main
git checkout testing
```

- [ ] **Step 4: Confirm production**

Confirm the `it-tools` Pages build for `main` reports `success` on the merge commit's `head_sha`,
then check the live hub footer reads `v2.4.3`:

```bash
curl -s "https://jgdev-ch.github.io/it-tools/" | grep -o "Built by Josh Garrett[^<]*"
```

Expected: `Built by Josh Garrett &middot; v2.4.3`

---

## Self-review

**Spec coverage.**

| Spec section | Task |
|---|---|
| Change 1, content-driven redraw, ETA buckets, gate on pct/ETA/state not the status string | 1 |
| Change 1, `DrawEveryMs` floor raised to 500, `LastDraw` stamped only on real draws | 1 |
| Change 2, teal via `$Host.PrivateData`, one code path, guarded, no dead `Progress.Style` | 2 |
| Change 2, fill character not configurable, recorded not implemented | 8 step 1 |
| Change 3, `*> $null` on the probe, throw preserved, group path only | 3 |
| Change 4, computed field widths from `RunTotal` and `chunkCount`, both generators | 4 |
| Change 5, `Confirm-Apply` records approval | 5 |
| Change 6, label/value pairs rendered twice, all nine shapes | 6 |
| Verification: four existing gates | every task |
| Verification: WhatIf harness, alignment harness, redraw harness | 3, 4, 1 |
| Verification: stub stays green | 1, 4, 6, 7 |
| Changelog folded into existing 2.4.3, no version bump | 7 |
| Colour confirmed by eye | 8 |

No spec requirement is unassigned.

**Placeholder scan.** No `TBD`, no `TODO`, no "add error handling", no "similar to Task N". Every
code step carries complete code. Task 4 step 4 says to apply "the same" replacement, but the full
code appears immediately above in step 3 on the same screen, and the reason both copies exist is
stated.

**Type and name consistency.** Checked across tasks: new state is `$script:LastPct`,
`$script:LastLeft`, `$script:LastState` (Task 1 step 4) and every consumer in the rewritten
`Update-Run` (Task 1 step 6) reads exactly those three. The new tunable is `$script:EtaBucket`
(step 5), consumed once (step 6). `psPrologue`'s second parameter is renamed
`extraHeaderLines` to `extraFields` in Task 6 step 1, and both non-empty call sites are converted
to `[label, value]` pairs in steps 3 and 4, with the two empty-array call sites explicitly checked
in step 5. `pad()` and `labelWidth` are defined and used only inside `psPrologue`. `$w`, `$cw` and
`$fmt` in Task 4 are local to the `if (-not $aborted)` block in both generators and do not collide
with anything: the file has no other `$w`.

**One risk worth stating.** Task 6 is the only task that changes a function signature, and it
injects generated PowerShell (`runDetails`) into a template literal. `node --check` cannot catch a
malformed injection; only the parse sweep will. Run the four gates after step 2 of that task before
touching the call sites, so a template error is not confused with a call-site error.
