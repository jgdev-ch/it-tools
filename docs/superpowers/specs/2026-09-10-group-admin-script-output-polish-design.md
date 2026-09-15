# Group Administration Generated-Script Output Polish

**Date:** 2026-09-10
**Scope:** `tools/group-import/exo-scripts.js` only
**Status:** design approved 2026-09-10, ready for an implementation plan

## Goal

Tighten the visual formatting of the console output the generated Exchange scripts produce, and
stop the progress bar flickering. The script's *logic* is proven; this is about what the tech
reads while it runs and what the transcript preserves afterwards.

## Background

Ellis ran the hardened `Add-DistributionListMembers.ps1` against `zGlobalProviderAll` on
2026-09-09: **1284 added, 0 failed, 0 reconnects, 38.4 minutes**, against 612 added / 1284 failed
/ 62 minutes on 2026-09-08. The logic works. Reviewing that transcript and Josh's screenshot
surfaced five presentation defects and no logic defects.

Two facts from that run drive the design:

- **The run finished in 38.4 minutes, under the (then) 40-minute refresh threshold**, so the
  reconnect never fired. `RefreshMinutes` was lowered to 30 in `f19f6ae` as a separate change.
- **Throughput was ~1.68 s per member.** This is what makes the existing progress throttle inert
  and is the root of the flicker.

## Non-goals

- **The `.ps1` source formatting.** Reviewed and already correct: 4-space indents, aligned
  assignment operators, consistent throughout. No changes.
- **The hub UI.** The launcher, wizard, and step rail are all fine as they stand.
- **A house-wide PowerShell console standard.** Deferred deliberately, see "Deferred" below.
- **Any change to the run logic**: the diff, chunking, retry, breaker, reconnect and failures CSV
  are all untouched.

## Change 1: progress bar redraws become content-driven

**Problem.** `Update-Run` gates on wall-clock time via `$script:DrawEveryMs = 250`. At 1.68 s per
member every call clears that gate, so the throttle suppresses nothing and the run performs one
full `Write-Progress` redraw per member, each interleaved with a `Write-Host` line that scrolls
the console underneath the bar. Roughly 1284 redraws. That is the flicker.

**Fix.** Decide whether to draw from the values that change slowly, then compose the display text
fresh at draw time.

Draw when **any** of these differ from the last actual draw, or when `-Force` is passed:

| Signal | Changes per 1284-member run |
|---|---|
| Integer percent complete | ~100 |
| ETA, quantised to 30-second buckets | ~72 |
| `$script:RunStatus` (`Connected` / `Reconnecting...` / `Disconnected`) | 0 to a handful |

**Critical detail, and the reason this is stated so explicitly:** the gate must **not** compare
the composed status string. That string contains `$script:RunCurrent`, which increments on every
entry, so comparing it would never match and the redraw rate would be unchanged. Gate on percent,
ETA bucket and connection state; recompute the text at draw time.

The consequence is deliberate: the on-screen counter advances in steps of roughly 13 members
rather than 1. That is the trade being made for a stable bar.

Also:

- `$script:DrawEveryMs` rises 250 to 500 and becomes a floor, not the primary gate.
- `$script:LastDraw` is stamped only when a draw actually happens, so the floor measures time
  since the last real draw.
- New tunables: `$script:EtaBucket = 30`, plus `$script:LastPct` / `$script:LastLeft` /
  `$script:LastState` alongside the existing `$script:LastDraw`.
- Bar *content* is unchanged: activity, connection state, counts, percent, ETA.

**Expected result:** roughly 160 to 175 redraws instead of ~1284, about a 7x reduction.

**Honest limitation.** Classic-view progress redraws its region whenever host output scrolls
beneath it, and that is host behaviour we do not control. This substantially reduces flicker; it
cannot guarantee zero. If it still reads badly on the next real run, dropping `Write-Progress`
entirely and relying on the chunk milestones is a small, clean retreat.

## Change 2: progress bar colour becomes teal

**Problem.** The bar inherits PowerShell's default bright yellow. Yellow is already this script's
**warning** colour, used for the refresh notice, reconnect messages and abort text, so an
always-on bar wears the same colour as "something needs attention."

**Decision: teal.** Chosen over hub blue specifically because it renders consistently across both
hosts, which was the deciding factor.

**One mechanism, both hosts.** Verified against pwsh 7.6.5 on 2026-09-10 by enumerating the
renderer's properties:

```
$PSStyle.Progress  ->  MaxWidth, Style, UseOSCIndicator, View
$Host.PrivateData  ->  ProgressBackgroundColor, ProgressForegroundColor
```

`$Host.PrivateData` reports `ProgressBackgroundColor = Yellow` / `ProgressForegroundColor = Black`,
which is exactly the yellow block with dark text in the 2026-09-09 screenshot. `$PSStyle.Progress.Style`
is `ESC[33;1m`, bright yellow *foreground*, which would render as yellow text rather than a block.
**Classic view therefore takes its colours from `PrivateData`, and `$PSStyle.Progress.Style` applies
only to Minimal view.** Since the script already pins `View = 'Classic'` on PowerShell 7, both hosts
run the same renderer and read the same two properties.

So the implementation is:

```
$Host.PrivateData.ProgressBackgroundColor = 'Cyan'
$Host.PrivateData.ProgressForegroundColor = 'Black'
```

wrapped in `try/catch`, because `PrivateData` is absent or differently shaped on non-console hosts.
No `$PSStyle.Progress.Style` assignment: it would be dead code while Classic is pinned.

This is stronger than the originally specced two-path approach. Using the named console colour
`Cyan` rather than a 24-bit RGB value means both hosts resolve through the same terminal palette,
so the result is genuinely identical rather than approximately matching, which was the deciding
factor in choosing teal.

**Confirm visually once.** Progress output cannot be captured from a piped session, so the colour
change is the one item in this spec that no automated gate can verify. Eyeball it on the first run
after implementation.

**Known cosmetic consequence:** step headers and chunk milestone lines are already cyan, so the
screen leans one colour. Accepted, because the bar is a filled *block* and does not compete with
cyan *text* the way two text colours would. If it reads busy on the next real run, dropping the
chunk milestone lines to white is the adjustment; not doing that pre-emptively.

**The bar's fill character is not configurable.** The `o` glyph in `[oooooooo    ]` is hardcoded
in the Classic renderer; no glyph, character or fill property exists on `$PSStyle.Progress` or
`$Host.PrivateData`. Asked and checked 2026-09-10. The two ways to change it were both rejected:
`View = 'Minimal'` uses a solid-block renderer but pins the bar to the bottom of the console and
does not exist on 5.1, losing both the top placement and cross-version parity; hand-rolling a bar
with `Write-Host` plus cursor positioning allows any glyph but breaks on console resize and line
wrapping, and would write ~160 bar redraws into the transcript, bloating the audit log for
cosmetics. Keeping `o` also means the bar looks like every other PowerShell tool a tech has used.

## Change 3: label the `-WhatIf` leak (revised 2026-09-10 during implementation)

> **Revised.** This section originally specified suppressing the line with `*> $null`. That was
> tested before editing and **does not work**; see "What was actually implemented" below. The
> problem statement stands; the fix changed, with Josh's approval.

**Problem.** The phase 3 capability probe runs the real cmdlet with `-WhatIf`. PowerShell prints
its own "What if: Adding distribution group member ..." straight to the host at column zero,
breaking the six-space indent every other line follows, and it lands *above*
"Permission check passed." so it reads as though something failed.

**Why it cannot be suppressed.** `ShouldProcess` writes its WhatIf announcement directly to the
host UI, past all six PowerShell streams. Three mechanisms were tested on pwsh 7.6.5 on
2026-09-10, before any code was edited:

| Mechanism | Result |
|---|---|
| `*> $null` (all six streams) | No effect. Line still printed. |
| `-InformationAction Ignore` | No effect. Confirms it is not on the information stream. |
| `[Console]::SetOut([TextWriter]::Null)` | Suppresses the line, but **permanently silences the host for the rest of the run**, even after the writer is restored, because ConsoleHost caches its output stream. A following `Write-Host` marker never appeared. Unusable in a script a tech runs unattended. |

**What was actually implemented.** The line is labelled rather than hidden. One `Write-Detail`
before the probe tells the reader the line is coming:

```
      Checking write permission. The "What if" line below is expected.
What if: Adding distribution group member "..." on distribution group Identity:"...".
      Permission check passed.
```

The generated script carries a comment recording all three failed mechanisms, so nobody attempts
the suppression again.

**Known limit, accepted.** This stops the line reading as a failure. It does **not** fix the
column-zero indentation, because the column PowerShell writes at is not controllable. Josh
accepted that trade on 2026-09-10 over the alternative of deleting the probe entirely.

**Rejected alternative.** Dropping the `-WhatIf` probe and instead aborting on a permission
failure from the first real add would remove the line completely. Rejected for this change because
it converts a formatting fix into a run-logic change, moves the permission check to after the
confirm gate, and would need a fourth stub scenario. Worth revisiting with the deferred house
standard.

**Group-member path only.** The mailbox path's probe is a `Get-MailboxPermission` read and never
had this problem.

## Change 4: chunk milestone columns align at any magnitude

**Problem.** The chunk milestone line separates its fields with hardcoded runs of spaces:

```
      150/1284   150 ok, 0 failed        (chunk 1 of 9 done, session ok)
      1050/1284   1050 ok, 0 failed        (chunk 7 of 9 done, session ok)
      1284/1284   1284 ok, 0 failed        (chunk 9 of 9 done, session ok)
```

Once a counter gains a digit every field shifts right, so the parenthetical never lines up. Nine
lines in the 2026-09-09 log, three different alignments.

**Fix.** Compute field widths from the known totals and build the line with the `-f` format
operator rather than string concatenation with padding baked in:

- Counter width from `$script:RunTotal.ToString().Length`
- Chunk-number width from `$chunkCount.ToString().Length`

Columns then hold whether the run is 20 members or 20,000, and no magic space runs remain.

## Change 5: the confirm gate records its own approval

**Problem.** There are two blank lines between "Permission check passed." and `[4/5]`, where every
other phase boundary has one. The cause is that PowerShell does not record the `Read-Host` prompt
in the transcript, so `Confirm-Apply`'s leading `Write-Host ""` leaves a hole with nothing in it.

**Fix.** `Confirm-Apply` emits a confirmation line via `Write-Detail` after the gate passes. This
fills the gap for the reader and, more usefully, puts the approval itself into the audit record,
which it currently is not: today a transcript shows changes being applied with no evidence anyone
was asked.

Shared by both generators, so both benefit.

## Change 6: run provenance reaches the transcript

**Problem.** `psPrologue` emits the run header as a `#` comment banner at the top of the `.ps1`.
Comments never execute, so **none of it reaches the transcript**: no target, no operation, no
intended count, no generating tech, no generation timestamp. For a file whose stated purpose is
audit, provenance is the one thing absent. Export scripts suffer most, since they log almost
nothing else.

**Fix.** Refactor the header from an array of pre-formatted `#  Label : value` strings into
label/value pairs, rendered twice from that one source:

1. As the comment banner at the top of the file, exactly as today.
2. As `Write-Detail` lines emitted immediately after `Start-Transcript`.

One source of truth, so the banner and the logged copy cannot drift apart. All injected values go
through `psStr()` as usual. Applies to all nine script shapes (three object types x three
operations).

## Verification

No test framework in this repo; do not invent one. Every existing gate must still pass:

- `node --check tools/group-import/exo-scripts.js`
- The render-and-parse sweep: 20 shapes rendered, each parsed with `[Parser]::ParseFile`, expecting
  `files with parse errors: 0`
- The undefined-helper scan across all rendered scripts
- The stub harness, all three scenarios, unchanged results: `recover` 1896 ok / 0 failed / 1
  reconnect, `permadead` 3 reconnects / aborted, `badlist` 0 reconnects / not aborted

Three new gates, all runnable without a tenant:

1. **WhatIf suppression.** A local advanced function with `[CmdletBinding(SupportsShouldProcess)]`
   called with `-WhatIf` and `*> $null`, asserting the "What if:" text is absent from captured
   output **and** that `-ErrorAction Stop` still throws into `catch`.
   **Outcome: this gate failed by design and produced the Change 3 revision.** It proved case 1
   (the stub reproduces the leak) and case 3 (the throw survives) but not case 2 (suppression),
   which is how the unsuppressible behaviour was found before any code was edited. Retained in
   `%TEMP%\gi-whatif.ps1` as the evidence for why the line is labelled instead of hidden; it is
   not a passing gate and should not be treated as one.
2. **Column alignment.** Render chunk milestone lines at 2-, 3- and 4-digit totals and assert the
   character index of `(chunk` is identical across all three. This is the regression that existed.
3. **Redraw count.** Instrument `Update-Run` with a counting stub for `Write-Progress`, drive it
   through a simulated 1284-entry run at the observed 1.68 s cadence, and assert the call count is
   **under 200**, against ~1284 today. Turns "the flicker should be better" into a number.

## Changelog and version

Hub v2.4.3 has not reached production, so this folds into the **existing 2.4.3 entry** with one
added note about clearer script output. No new version. The hub version lives in the `index.html`
footer, not `config.json`.

## Template escaping rules

`exo-scripts.js` builds PowerShell inside JS template literals. Violating these silently corrupts
output and `node --check` will not catch it:

- Never emit PowerShell `${var}`; `${` interpolates in a JS template literal. Use `$var` and
  `$(...)`.
- Write `\\` for every literal backslash.
- Never emit PowerShell backticks. One line per cmdlet.
- Every injected value goes through `psStr()`.

Note the format strings in Change 4 use `{0,$w}` style width specifiers. These contain no `${`
sequence and are safe, but they must be checked by eye during implementation.

## Deferred: a house-wide PowerShell console standard

Josh's intent is for this console vocabulary to become the pattern for all their PowerShell work
as scripts are created and updated. Deliberately **not** in this spec, and not scheduled for
today. It gets its own brainstorm so it can codify something already proven in production rather
than on paper.

The retrofit surface is eight hand-written scripts across four tools:

```
tools/exchange-audit/runbook/Invoke-ExchangeAudit.ps1
tools/mailbox-cleanup/Install-Prerequisites.ps1
tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1          <- the vocabulary already aligned to
tools/mailbox-cleanup/runbook/Invoke-SIRWatchdog.ps1
tools/mailbox-health-audit/Install-Prerequisites.ps1
tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1
tools/shared-mailbox-repair/Install-Prerequisites.ps1
tools/shared-mailbox-repair/Invoke-RepairSharedMailboxes.ps1
```

The unresolved design question for that brainstorm: how to share console primitives between a JS
string generator and eight standalone `.ps1` files when there is no build step and the tech
downloads a single self-contained script. A dot-sourced shared module conflicts with the
single-file download model; a documented canonical snippet duplicates code but keeps zero
coupling. That trade needs deciding, plus whether existing scripts get retrofitted or only new
ones adopt it.
