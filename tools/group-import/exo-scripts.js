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
      // Export is read-only: connect, verify, read, complete. Write ops add a
      // compare phase and an apply phase between verify and complete. psEpilogue
      // numbers "Complete" as ctx.phases, so Complete is counted here.
      // Step numbering must never be hardcoded.
      phases: op === "export" ? 4 : 5,
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

  // ── Shared script blocks ──────────────────────────────────────
  /** Header comment + error preference + logging helpers + transcript start. */
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
          "#    3. Reads the current state and shows you exactly what will change.",
          "#    4. Waits for you to type YES, then applies the changes for real.",
          "#    5. Retries transient errors, and reconnects by itself if the",
          "#       Exchange session drops part-way through a long run.",
          "#    6. Writes a failures CSV next to this script if anything fails,",
          "#       so you can finish the job by re-uploading just those entries.",
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
$script:LastPct       = -1
$script:LastLeft      = -1
$script:LastState     = ""

# --- Tunables -----------------------------------------------------
$script:ChunkSize      = 150
$script:MaxAttempts    = 3
$script:Backoff        = @(2, 6)
$script:BreakerLimit   = 10
$script:MaxReconnects  = 3
$script:RefreshMinutes = 30
$script:EtaBucket      = 30
$script:DrawEveryMs    = 500

# --- Console helpers ----------------------------------------------
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
    # PowerShell does not record the Read-Host prompt in the transcript, so without
    # this line the log shows changes being applied with no evidence anyone was asked,
    # and the reader sees a doubled blank line where the prompt should have been.
    Write-Detail ("Confirmed. Applying to " + $Count + " " + $What + " now.") Green
}

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
    "already exists",
    "already present",
    "already has",
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
  }

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
    // Export is read-only: no dry run, no confirmation gate, writes a CSV next to the script.
    if (ctx.op === "export") {
      const exportBody = `
# --- Export members -----------------------------------------------
Write-Step 3 ${ctx.phases} "Reading current members..."
$outFile = Join-Path $PSScriptRoot (${psStr(ctx.logBase + "-" + ctx.targetSlug)} + "-" + $stamp + ".csv")
$count = 0
try {
    $members = Get-DistributionGroupMember -Identity $Target -ResultSize Unlimited -ErrorAction Stop
    $count = @($members).Count
    if ($count -eq 0) {
        Write-Detail "This group has no members. No CSV was written." Yellow
    } else {
        $members | Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails, Alias | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
        Write-Detail ("Exported " + $count + " members to:") Green
        Write-Detail $outFile
    }
} catch {
    Write-Detail ("ERROR: Could not read members. " + $_.Exception.Message) Red
}
`;
      return psPrologue(ctx, []) + inputs + psConnect(ctx) + verify + exportBody +
             psEpilogue(ctx, 'Write-Detail ("Members read: " + $count)\n');
    }

    const isAdd     = ctx.op === "add";
    const cmdlet    = isAdd ? "Add-DistributionGroupMember" : "Remove-DistributionGroupMember";
    const liveArgs  = isAdd ? "-BypassSecurityGroupManagerCheck" : "-BypassSecurityGroupManagerCheck -Confirm:$false";
    const didWord   = isAdd ? "ADDED" : "REMOVED";

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
} catch {
    Write-Detail ("ERROR: This account cannot modify '$Target'. " + $_.Exception.Message) Red
    Write-Detail "You need a role with write access to this group, for example Recipient Management." Yellow
    Stop-Run "" Red 1
}

Confirm-Apply $ToApply.Count "entries"
`;

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

    $end = [Math]::Min($i + $script:ChunkSize, $script:RunTotal)
    while ($i -lt $end) {
        # Proactive refresh. The 2026-09-08 run died at 62 minutes because the access
        # token needed renewing and the module's own claims handler crashed. Refreshing
        # before the token ages out means that path is never reached. Checked per entry,
        # not per chunk: a chunk of 150 can span 10 minutes, which would let the token
        # age out well past the refresh threshold before the next boundary arrived.
        if (((Get-Date) - $script:ConnectedAt).TotalMinutes -ge $script:RefreshMinutes) {
            Write-Detail ("Session has been open " + $script:RefreshMinutes + "+ minutes. Refreshing before the next entry.") Yellow
            if (-not (Reset-Session)) { $aborted = $true; break }
        }

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
        # Field widths come from the run's own totals, so the columns hold whether
        # this is 20 entries or 20,000. The previous version separated fields with a
        # fixed run of spaces, which drifted the moment a counter gained a digit.
        $w   = $script:RunTotal.ToString().Length
        $cw  = $chunkCount.ToString().Length
        $fmt = "{0,$w}/{1}   {2,$w} ok, {3,$w} failed   (chunk {4,$cw} of {5} done, session ok)"
        Write-Detail ($fmt -f $script:RunCurrent, $script:RunTotal, $script:RunOk, $script:RunFailed, $c, $chunkCount) Cyan
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

    const summary =
      'Write-Detail ("' + didWord.padEnd(10) + ' : " + $script:RunOk)\n' +
      'Write-Detail ("Skipped    : " + $script:RunSkipped + "   (' + haveWord + ')")\n' +
      'Write-Detail ("Failed     : " + $script:RunFailed)\n' +
      'Write-Detail ("Reconnects : " + $script:RunReconnects)\n' +
      'if ($failFile) { Write-Detail ("Failures   : " + $failFile) Yellow }\n';

    return psPrologue(ctx, [["Members", String(ctx.identities.length)]]) +
           inputs + psConnect(ctx) + verify + phase3 + body + psEpilogue(ctx, summary);
  }

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

    // Export branch: combines Get-MailboxPermission, Get-RecipientPermission, and
    // GrantSendOnBehalfTo into one CSV. Read-only, no dry run, no confirmation gate.
    if (ctx.op === "export") {
      const exportBody = `
# --- Export access list -------------------------------------------
Write-Step 3 ${ctx.phases} "Reading access permissions..."
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
    Write-Detail "Mailbox permissions read." Green
} catch {
    Write-Detail ("Could not read mailbox permissions. " + $_.Exception.Message) Red
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
    Write-Detail "Send As permissions read." Green
} catch {
    Write-Detail ("Could not read Send As permissions. " + $_.Exception.Message) Red
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
    Write-Detail "Send on Behalf permissions read." Green
} catch {
    Write-Detail ("Could not read Send on Behalf permissions. " + $_.Exception.Message) Red
}

if ($rows.Count -eq 0) {
    Write-Detail "No explicit access entries found. No CSV was written." Yellow
} else {
    $rows | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
    Write-Detail ("Exported " + $rows.Count + " access entries to:") Green
    Write-Detail $outFile
}
`;
      return psPrologue(ctx, []) + inputs + psConnect(ctx) + verify + exportBody +
             psEpilogue(ctx, 'Write-Detail ("Access entries: " + $rows.Count)\n');
    }

    // Per-permission blocks. No -WhatIf half and no per-block try/catch:
    // Invoke-WithRetry owns error handling, and a throw from any block fails the
    // whole trustee, which is correct. A trustee who got FullAccess but failed
    // SendAs is reported as failed and appears in the failures CSV.
    const fullBlock = isGrant
      ? `    if ($DoFullAccess) {
        Add-MailboxPermission -Identity $Mailbox -User $Trustee -AccessRights FullAccess -AutoMapping $AutoMapping -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Detail ("GRANTED FullAccess (AutoMapping " + $AutoMapping + "): " + $Trustee) Green
    }`
      : `    if ($DoFullAccess) {
        Remove-MailboxPermission -Identity $Mailbox -User $Trustee -AccessRights FullAccess -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Detail ("REMOVED FullAccess: " + $Trustee) Green
    }`;

    const sendAsBlock = isGrant
      ? `    if ($DoSendAs) {
        Add-RecipientPermission -Identity $Mailbox -Trustee $Trustee -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Detail ("GRANTED SendAs: " + $Trustee) Green
    }`
      : `    if ($DoSendAs) {
        Remove-RecipientPermission -Identity $Mailbox -Trustee $Trustee -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Detail ("REMOVED SendAs: " + $Trustee) Green
    }`;

    const onBehalfBlock = isGrant
      ? `    if ($DoSendOnBehalf) {
        Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Add=$Trustee} -ErrorAction Stop
        Write-Detail ("GRANTED SendOnBehalf: " + $Trustee) Green
    }`
      : `    if ($DoSendOnBehalf) {
        Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Remove=$Trustee} -ErrorAction Stop
        Write-Detail ("REMOVED SendOnBehalf: " + $Trustee) Green
    }`;

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

    $end = [Math]::Min($i + $script:ChunkSize, $script:RunTotal)
    while ($i -lt $end) {
        # Checked per entry, not per chunk, so a long run cannot sail past the
        # refresh threshold waiting for the next chunk boundary.
        if (((Get-Date) - $script:ConnectedAt).TotalMinutes -ge $script:RefreshMinutes) {
            Write-Detail ("Session has been open " + $script:RefreshMinutes + "+ minutes. Refreshing before the next entry.") Yellow
            if (-not (Reset-Session)) { $aborted = $true; break }
        }

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
        # Field widths come from the run's own totals, so the columns hold whether
        # this is 20 entries or 20,000. The previous version separated fields with a
        # fixed run of spaces, which drifted the moment a counter gained a digit.
        $w   = $script:RunTotal.ToString().Length
        $cw  = $chunkCount.ToString().Length
        $fmt = "{0,$w}/{1}   {2,$w} ok, {3,$w} failed   (chunk {4,$cw} of {5} done, session ok)"
        Write-Detail ($fmt -f $script:RunCurrent, $script:RunTotal, $script:RunOk, $script:RunFailed, $c, $chunkCount) Cyan
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

    const permNames = [];
    if (ctx.perms.full)     permNames.push("Full Access" + (ctx.autoMapping ? " (AutoMapping on)" : " (AutoMapping off)"));
    if (ctx.perms.sendAs)   permNames.push("Send As");
    if (ctx.perms.onBehalf) permNames.push("Send on Behalf");

    const extraHeader = [
      ["Permissions", permNames.length ? permNames.join(", ") : "none selected"],
      ["Users", String(ctx.identities.length)],
    ];

    const summary =
      'Write-Detail ("' + didWord.padEnd(10) + ' : " + $script:RunOk)\n' +
      'Write-Detail ("Failed     : " + $script:RunFailed)\n' +
      'Write-Detail ("Reconnects : " + $script:RunReconnects)\n' +
      'if ($failFile) { Write-Detail ("Failures   : " + $failFile) Yellow }\n';

    return psPrologue(ctx, extraHeader) + inputs + psConnect(ctx) + verify + body + psEpilogue(ctx, summary);
  }

  /** Dispatch on object type. */
  function buildScript(ctx) {
    if (ctx.typeId === "distribution-list" || ctx.typeId === "mail-security-group") {
      return crlf(buildGroupMemberScript(ctx));
    }
    if (ctx.typeId === "shared-mailbox") {
      return crlf(buildMailboxPermissionScript(ctx));
    }
    throw new Error("Script generation is not implemented for object type: " + ctx.typeId);
  }

  // ── Self-running batch launcher ───────────────────────────────
  function buildBat(ctx) {
    const readOnly = ctx.op === "export";
    const blurb = readOnly
      ? [
          "echo  This connects to Exchange Online and writes a CSV",
          "echo  next to this file. It does not change anything.",
        ]
      : [
          "echo  This connects to Exchange Online, shows you exactly what",
          "echo  will change, then asks you to type YES before changing anything.",
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
})(typeof window !== "undefined" ? window : globalThis);
