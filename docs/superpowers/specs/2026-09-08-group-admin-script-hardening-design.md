# Group Administration: Generated Script Hardening Design Spec

**Status:** approved 2026-09-08. Follows the v2 Exchange script-gen work in
`2026-07-14-group-admin-expansion-design.md` and its plan
`2026-08-28-group-admin-expansion-v2.md`.

## Overview

The Exchange script-gen half of Group Administration went to production on 2026-09-01 without
Task 18 (the live functional matrix) ever being ticked off. On 2026-09-08 a tech ran the first
real job through it: 1896 members into the `zGlobalProviderAll` distribution list. It added 612
and failed 1284, and burned 62 minutes doing it.

The core generator is sound. Every failure traces to missing resilience in the generated
PowerShell, not to wrong cmdlets. This spec hardens that generated script.

## The incident, from the transcript

Source: `Add-DistributionListMembers-20260908-142540.log`, 1.4 MB, 10868 lines, run on
pwsh **7.6.5**, 14:25:40 to 15:27:17.

Two distinct failures, and only the second one mattered:

1. **Member 374** hit a transient Exchange error: "A server side error has occurred because of
   which the operation could not be completed. Please try again after some time." The run
   recovered on its own and added 239 more members. Microsoft's message explicitly says to
   retry; the script did not, so that member was silently lost.

2. **Member 614** killed the session permanently. **Zero** members succeeded afterwards. 1283
   consecutive, byte-identical failures followed:

   ```
   TerminatingError(Invoke-WebRequest): "<50 bytes, never flushed to disk>"
   TerminatingError(Get-ClaimsFromExceptionDetails):
     "[System.Net.Http.HttpResponseMessage] does not contain a method named 'GetResponseHeader'"
   ```

### Root cause

`Get-ClaimsFromExceptionDetails` is the ExchangeOnlineManagement module's **claims-challenge
parser**, the code path invoked when Exchange demands re-authentication. It calls
`GetResponseHeader()`, a method on .NET Framework's `HttpWebResponse` that does **not** exist on
.NET Core's `HttpResponseMessage`.

So roughly an hour into the session, Exchange required re-auth, the module's own recovery path
threw while trying to read the challenge, and the session became permanently unusable. Every
remaining member then failed inside that same broken handler.

This is a module bug in Microsoft's code. It cannot be fixed from the generated script. The
script must instead **detect the dead session and establish a new one.**

**Runtime note.** `buildBat` prefers `pwsh.exe` and falls back to `powershell.exe` only when PS7
is absent, printing a warning telling the tech to install PS7. On Windows PowerShell 5.1
`Invoke-WebRequest` yields a response object that *does* carry `GetResponseHeader`, so 5.1
likely avoids this specific crash. That is a well-grounded inference from the error signature,
**not verified against live Exchange.** Decision: leave the PS7 preference alone and make the
script survive re-auth on either host. Nothing here depends on the inference being right.

### Four further defects the log exposes

- **No circuit breaker.** 1283 doomed attempts ran across most of an hour, producing nothing.
- **The dry run consumes the session's healthy window before any work starts.** It issues 1896
  real `-WhatIf` API calls, then the live run issues 1896 more.
- **No membership pre-check.** `SKIPPED` and `ALREADY` are both 0 across the whole log because
  the concept does not exist in the Exchange path, though the Graph path has had one since
  commit `b0960d5`. Re-running re-attempts everyone.
- **The dry-run console is unreadable.** Every member prints twice: PowerShell's own wrapping
  `What if: Adding distribution group member "x" on distribution group Identity:"y"` plus the
  script's `WOULD ADD: x`. About 3800 lines before the confirm prompt.

## Scope

All changes are in **`tools/group-import/exo-scripts.js`** only. Two generators are affected:

| Generator | Target types | Ops |
|---|---|---|
| `buildGroupMemberScript` | distribution list, mail-enabled security group | add, remove, export |
| `buildMailboxPermissionScript` | shared mailbox | grant, remove, export |

Shared helpers `psPrologue`, `psConnect` and `psEpilogue` are also touched, so every generated
shape inherits the new primitives.

**Not in scope:** the wizard UI in `index.html`. "Pretty up the wizard choices" is real and
requested, but it is HTML/CSS verified by screenshots while this is PowerShell generation
verified by `pwsh` parsing. It gets its own brainstorm and spec.

## 1. Shared script primitives

Adopt Mailbox Cleanup's console vocabulary (`tools/mailbox-cleanup/Invoke-MailboxCleanup.ps1`)
so generated scripts and hand-written scripts read as one family.

| Primitive | Behaviour | Source |
|---|---|---|
| `Write-Step -Step N -Total T -Message` | Blank line, then two-space `[N/T] Message` in Cyan | Adapted from Mailbox Cleanup, which hardcodes `/6` |
| `Write-Detail -Message -Color` | Six-space indent, colored | Verbatim from Mailbox Cleanup |
| `Confirm-Continue -Prompt` | `[Y/N]`, throws "Aborted by user." on anything but Y/y | Verbatim from Mailbox Cleanup |
| `Confirm-Apply -Count` | The strong gate: requires typing `YES` | New |
| `Update-Run -Status -Current -Total` | Wraps `Write-Progress`, carrying connection state | New |

`Write-Head` and `Write-Item` are removed; every call site moves to `Write-Step` /
`Write-Detail`. The existing four-space `Write-Item` indent becomes Mailbox Cleanup's six.

**Confirm gates.** The one irreversible moment, applying writes to real mailboxes, keeps the
deliberate `Type YES` gate via `Confirm-Apply`. Every lesser prompt uses `Confirm-Continue`'s
`[Y/N]`. Universal formatting without weakening the guard on the only step that can do damage.

### Progress bar

A single fixed bar at the top of the console, carrying session health in its own status line:

```
 Adding members to zGlobalProviderAll
  Connected  |  612/1896  |  610 added, 2 failed  |  chunk 5/13
  [oooooooooooooooo                                      ]  32%  ~14 min remaining
```

- Implemented with `Write-Progress`. It writes to the progress stream, so it **never enters the
  transcript** and the audit log stays clean.
- `$PSStyle.Progress.View = 'Classic'` is set so the bar renders at the **top**. PowerShell 7
  defaults to `Minimal`, which pins it to the bottom. The assignment must be guarded
  (`if ($null -ne $PSStyle)`) because `$PSStyle` does not exist on 5.1.
- The `Status` field carries `Connected`, `Reconnecting...`, or `Reconnected`, so the tech
  watches one spot for both progress and session state.
- Throttled: redrawn at most every 250ms, and always on the final member. `Classic` redraws the
  whole block, so 1896 unthrottled updates would flicker badly. Counters are still tracked per
  member; only the redraw is rate-limited.
- `-SecondsRemaining` is computed from mean elapsed time per completed member.

**Deliberate deviation from the reference.** Mailbox Cleanup's `[####----]` bar uses carriage
return plus `-NoNewline` to count down a fixed propagation wait. Reused across 1896 members it
would write about 1896 redraw lines into the transcript and destroy the audit record. Same
intent, different mechanism, for a different problem.

## 2. Phase structure

Every generated script gains numbered phases. **Step totals are computed per shape, not
hardcoded** — an export has fewer phases than an add.

Add / remove / grant (5 phases):

1. Connect to Exchange Online
2. Verify the target
3. Compare against current state
4. Apply changes
5. Complete

Export (3 phases): connect, verify, export.

## 3. Phase 3 replaces the dry run

Delete the per-member `-WhatIf` loop. Replace it with one read of current state plus a local
diff.

**Group members** (`buildGroupMemberScript`): one
`Get-DistributionGroupMember -Identity $Target -ResultSize Unlimited`, compared
case-insensitively on primary SMTP address, producing:

| Bucket | Add run | Remove run |
|---|---|---|
| Actionable | `toAdd` | `toRemove` |
| Already in desired state | `alreadyMember` | `notAMember` |
| Unresolved | `unresolved` | `unresolved` |

**Shared mailbox** (`buildMailboxPermissionScript`): `Get-MailboxPermission` for FullAccess and
SendAs, and the mailbox's `GrantSendOnBehalfTo` for SendOnBehalf. Same three buckets per
permission type.

Output is **counts plus up to 10 example addresses per bucket**, then "and N more" — never one
line per member:

```
  [3/5] Comparing your CSV against current membership...
        1896 in CSV  |  0 already members  |  1896 to add  |  0 unresolved
```

Only actionable members are attempted in phase 4. `alreadyMember` and `notAMember` are counted
as `SKIPPED` and never touched.

**This is what makes a re-run cheap, and it is why there is no `-Resume` switch and no state
file.** A re-run after a dead job reads actual group membership, sees the 612 already added, and
attempts only the remainder. That is strictly more reliable than replaying a previous run's
beliefs about what it did.

**Known asymmetry, accepted:** a remove run cannot distinguish "already removed by the dead run"
from "never a member." Both land in `notAMember` and are reported as `SKIPPED`. This is correct
behaviour, not a defect, and it is why remove runs are also safe to re-run.

### Capability probe

The `-WhatIf` loop had one accidental virtue: it proved the account could write to the target
before doing real work. A local diff cannot. So phase 3 ends with **exactly one** `-WhatIf` call
against the first actionable member. On failure the script aborts with actionable remediation
text rather than discovering the problem mid-run. This mirrors Mailbox Cleanup's
`Test-PurgeCapability` / `Write-PurgePermissionError` pattern.

## 4. Phase 4: chunked apply with retry

Actionable members are processed in chunks of **150** (`$CHUNK_SIZE`, one constant). Chunking
buys three things: a bounded place to verify session health, a natural progress milestone, and
structural limits on token exposure. It does **not** batch API calls; Exchange still takes one
member per call.

**Per member:** on a transient failure, sleep and retry, up to 3 attempts with 2s / 6s / 15s
backoff. A failure is **transient** if its message matches server-side-error, "try again",
throttling/429, or timeout signatures. Everything else (unknown recipient, invalid address, not
licensed) is **permanent** and fails immediately without burning retries.

**Between chunks:** probe the session with a cheap read, write a milestone `Write-Detail` line,
update progress.

```
  [4/5] Applying changes...
        150/1896   150 added, 0 failed        (chunk 1 done, session ok)
        300/1896   300 added, 0 failed        (chunk 2 done, session ok)
        450/1896   448 added, 2 failed        (chunk 3 done, session ok)
```

## 5. Session recovery

**Detection.** The breaker trips on either signal:

- **Signature match** on the known-fatal module failure: `GetResponseHeader`,
  `Get-ClaimsFromExceptionDetails`, or an explicit session-state error.
- **10 consecutive non-permanent failures.** Both qualifiers are load-bearing.

  *Consecutive*: the counter resets on any success, so failures scattered across 1896 members
  never trip it.

  *Non-permanent*: only transient and unclassified failures increment the counter. A **permanent**
  per-member failure (unknown recipient, invalid address, unlicensed user) is a data problem, not
  a session problem, and must **not** count. Without this, a 12-row CSV containing 10 typo'd
  addresses would declare a perfectly healthy session dead and abort with rows unprocessed. The
  breaker's only job is detecting a poisoned session.

  Ten is small enough to catch a poisoned session in seconds and large enough to ride out a short
  cluster of genuinely transient errors.

**Response.** `Disconnect-ExchangeOnline`, `Connect-ExchangeOnline`, re-verify the target, reset
the consecutive counter, and continue **at the member that failed** so nothing is skipped. This
is in-run continuation, a different mechanism from the cross-run re-run behaviour in section 3.
The progress status moves `Connected` to `Reconnecting...` to `Reconnected`.

If the reconnect itself fails, **abort immediately** and report the exact position reached.

**Proactive refresh at 40 minutes elapsed.** The breaker is a safety net; this is the actual fix
for a roughly one-hour token life. Before starting a chunk, if elapsed time since the last
connect exceeds 40 minutes, reconnect first. The 2026-09-08 run died at 62 minutes; a refresh at
40 would very likely have prevented it entirely.

**Cap of 3 successful reconnects per run**, then abort with the exact position. Without a cap, a
flapping session ping-pongs between recovery and failure indefinitely, which is the unlimited-
retry behaviour this design explicitly rejects.

### Behaviour on an ordinary small run

Everything above targets the 1800-member outlier. On a typical 20-member job none of it should be
perceptible, and that is a design requirement, not a hope:

| Mechanism | On a 20-member run |
|---|---|
| Chunking | One chunk. One session probe, one milestone line. |
| Proactive 40-minute refresh | Never fires. The run finishes in well under a minute. |
| Circuit breaker | Cannot fire on bad data at all, per the non-permanent rule above. |
| Retry backoff | Only pays its 2s cost on an actual transient error. |
| Progress bar | Fills and clears. Throttling makes it a handful of redraws. |
| Failures CSV | Only written when something actually failed. |

If any of these becomes visible noise on a small run, that is a defect. Verification includes a
20-member render to confirm the console output stays short and quiet.

## 6. Phase 5: summary and failures CSV

The summary reports every bucket, not just two counters:

```
  [5/5] Complete
        Added      : 1894
        Skipped    : 0     (already members)
        Failed     : 2
        Unresolved : 0
        Reconnects : 1
        Transcript : ...\Add-DistributionListMembers-20260908-142540.log
        Failures   : ...\Add-DistributionListMembers-20260908-142540-failures.csv
```

When anything failed, write **`<logBase>-<stamp>-failures.csv`** next to the transcript, with one
row per failed member: the address, the final error message, and the attempt count. The tech
re-runs by dragging that one file back into the wizard, instead of extracting 1284 addresses
from a 1.4 MB transcript.

The CSV uses the same single-column header the wizard already accepts, so it round-trips with no
wizard change.

## 7. Verification

No JS or PowerShell test framework exists in this repo. Verification is the existing pattern from
the v2 plan, plus one addition that is genuinely new.

**Static, every task:**

- `node --check exo-scripts.js`.
- Render **all** script shapes to `$TEMP` with a throwaway node harness (written to `$TEMP`,
  never committed) and parse each with `pwsh` `[Parser]::ParseFile`. Both generators, every op.
- Re-read the escaping rules in the v2 plan before touching any template literal: never
  PowerShell `${var}` inside a JS template literal, always a doubled backslash for a literal
  backslash, no PowerShell backticks at all, every injected value through `psStr()`.

**Behavioural, new and the important one.** The resilience logic can be verified locally with no
Exchange tenant at all. Generate a test variant in `$TEMP` where `Add-DistributionGroupMember` is
replaced by a stub that:

1. succeeds for members 1 to 613,
2. throws the real transient server-side-error message once at member 374,
3. throws the genuine `GetResponseHeader` message from member 614 onward until a reconnect stub
   is called.

Then assert against the run: the transient error retried and recovered, the breaker tripped
within 10 members of 614 rather than after 1283, the reconnect ran, processing resumed at the
correct member, the reconnect cap holds, and the failures CSV contains exactly the right rows.
This reproduces the production incident deterministically and proves the fix, which nothing in
the original v2 plan could do.

**Manual, still required.** A live functional pass against a disposable test DL and test shared
mailbox, as Task 18 always specified. The stub harness proves the resilience logic; only a real
tenant proves the cmdlets. Task 18 has never been run and this does not substitute for it.

## 8. Out of scope

- The wizard UI in `index.html`, including the object-type and action card polish. Separate spec.
- Flipping the `.bat` runtime preference to `powershell.exe`. Rejected: the script is being made
  host-independent instead.
- Any change to the Graph-live half (security groups, M365 groups). It runs in-browser, has its
  own membership pre-check already, and is not affected by EXO session expiry.
- Patching `Get-ClaimsFromExceptionDetails`. It is Microsoft's module code.
- A `-Resume` switch or run state file. Superseded by the phase 3 membership diff, per section 3.
- Multi-group bulk operations, still parked from 2026-07-15.

## 9. Changelog

Unlike On-Call Rotation, this tool **is** live in production, so the changelog-in-parallel rule
applies: a `changelog.json` entry ships in the same push as the code, worded for techs rather
than in terms of internals. Draft:

- Group Administration: Exchange scripts now compare your CSV against current membership first,
  so people already in the group are skipped instead of re-attempted.
- Group Administration: Exchange scripts now show a progress bar with a running count and time
  remaining, and recover automatically if the Exchange session drops mid-run.
- Group Administration: a failures CSV is now saved next to the log so a partial run can be
  finished by re-uploading just the members that did not go through.
