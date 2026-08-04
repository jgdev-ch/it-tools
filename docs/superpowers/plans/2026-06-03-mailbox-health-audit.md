# Mailbox Health Audit Script — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Invoke-MailboxHealthAudit.ps1` — a read-only PowerShell wizard that scans all Exchange Online mailboxes, scores each on 4 diagnostic flags, and surfaces at-risk mailboxes before they become cleanup tickets.

**Architecture:** Single-file PowerShell script (~600–700 lines). Helper and check functions defined at the top, dot-sourceable for standalone use. Main wizard body runs Phases 1–5: connect → scan config → scan execution → overview display → mode menu (individual deep-dive, batch checks, export). No compliance session required — Exchange Online only.

**Tech Stack:** PowerShell 5.1+, ExchangeOnlineManagement v3.9.0+. No external dependencies beyond the module already used by `Invoke-MailboxCleanup.ps1`.

**Spec:** `docs/superpowers/specs/2026-06-02-mailbox-health-audit-design.md`

**Branch:** `testing`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1` | Create | Main wizard script |
| `tools/mailbox-health-audit/Install-Prerequisites.ps1` | Create | One-time module installer |

---

## Syntax Validation Command

Run after each task to catch errors early (no Exchange connection required):

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-health-audit\Invoke-MailboxHealthAudit.ps1',
    [ref]$null,
    [ref]$errors
)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host ("Line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) -ForegroundColor Red }
} else { Write-Host "Syntax OK — 0 errors." -ForegroundColor Green }
```

---

## Task 1: Scaffold — param, module install, constants, helpers, banner

**Files:**
- Create: `tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1`

- [ ] **Step 1: Create the directory and write the scaffold**

Create `C:\dev\projects\it-tools\tools\mailbox-health-audit\Invoke-MailboxHealthAudit.ps1` with this content:

```powershell
param(
    [string]$TenantDomain
)

# --- Module install/update (requires v3.9.0+ for REST mode) ---
$minVersion = [Version]"3.9.0"
$installed  = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
    Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $installed -or $installed.Version -lt $minVersion) {
    Write-Host "Installing/updating ExchangeOnlineManagement to v3.9.0+..." -ForegroundColor Yellow
    Install-Module ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser
}
try {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
} catch {
    Write-Host "ERROR: Failed to load ExchangeOnlineManagement module. $_" -ForegroundColor Red
    exit 1
}

# --- Constants ---
$SCRIPT_VERSION               = "1.0"
$DEFAULT_RI_THRESHOLD_GB      = 20
$DEFAULT_PRIMARY_THRESHOLD_GB = 80
$RI_QUOTA_GB                  = 100

# --- Script-scope threshold state (set in Phase 2, read by check functions) ---
$Script:PrimaryThresholdGB = [decimal]$DEFAULT_PRIMARY_THRESHOLD_GB
$Script:RiThresholdGB      = [decimal]$DEFAULT_RI_THRESHOLD_GB
$Script:FullScan           = $false

# --- Helpers ---
function Write-Step {
    param([int]$Step, [int]$Total, [string]$Message)
    Write-Host "`n  [$Step/$Total] $Message" -ForegroundColor Cyan
}

function Write-Detail {
    param([string]$Message, [string]$Color = 'White')
    Write-Host "      $Message" -ForegroundColor $Color
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "{0:N0} B" -f $Bytes
}

function ConvertTo-Bytes {
    param($Value)
    if ($null -eq $Value) { return [long]0 }
    if ($Value.GetType().Name -eq 'ByteQuantifiedSize') { return $Value.ToBytes() }
    if ($Value -is [string] -and $Value -match '\((\d[\d,]*)\s+bytes?\)') {
        return [long]($Matches[1] -replace ',', '')
    }
    try { return [long]$Value } catch { return [long]0 }
}

function Get-HoldType {
    param([string]$Guid)
    if ($Guid -match '^UniH') { return 'Compliance Policy (UniH — expected)' }
    return 'LEGACY HOLD — review with compliance team'
}

# --- Banner ---
Write-Host ""
Write-Host "  ════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "   Mailbox Health Audit  v$SCRIPT_VERSION" -ForegroundColor White
Write-Host "  ════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "   Read-only diagnostic — no mailbox changes made" -ForegroundColor Gray
Write-Host ""
```

- [ ] **Step 2: Syntax check**

Run the syntax validation command above.
Expected: `Syntax OK — 0 errors.`

- [ ] **Step 3: Commit**

```
git add tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1
git commit -m "feat(mailbox-health-audit): scaffold — param, module check, constants, helpers, banner"
```

---

## Task 2: Check Functions

**Files:**
- Modify: `tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1` (append after banner)

- [ ] **Step 1: Append all 6 check functions**

Append this block after the banner section:

```powershell
# --- Check Functions ---
# All functions accept the raw $allMailboxes array from Get-Mailbox (or $results for SIR check).
# Each returns a filtered subset. Get-MailboxRiskScore accepts a single result object.

function Get-ElcDisabledMailboxes {
    # ElcProcessingDisabled = $true: MFA completely skips this mailbox.
    # Retention policies never fire; Recoverable Items never gets processed.
    # Commonly set during on-prem migrations and never cleared.
    # Safe to bulk-clear with Set-Mailbox -ElcProcessingDisabled $false — no compliance review required.
    param([object[]]$Mailboxes)
    $Mailboxes | Where-Object { $_.ElcProcessingDisabled -eq $true }
}

function Get-LegacyHoldMailboxes {
    # Non-UniH GUIDs in InPlaceHolds = legacy Exchange in-place holds from on-prem migration.
    # No expiration, no visible owner in EAC or Purview; pins items in /DiscoveryHolds indefinitely.
    # Removal requires compliance team review.
    param([object[]]$Mailboxes)
    $Mailboxes | Where-Object {
        ($_.InPlaceHolds | Where-Object { $_ -notmatch '^UniH' }).Count -gt 0
    }
}

function Get-LitigationHoldMailboxes {
    # LitigationHoldEnabled with no TTL preserves all content indefinitely.
    # Causes continuous Recoverable Items growth. Requires legal/compliance sign-off to modify.
    param([object[]]$Mailboxes)
    $Mailboxes | Where-Object {
        $_.LitigationHoldEnabled -eq $true -and
        ($_.LitigationHoldDuration -eq 'Unlimited' -or $null -eq $_.LitigationHoldDuration)
    }
}

function Get-SIRRiskMailboxes {
    # SIR + large Recoverable Items = stalled cleanup: MFA cannot reclaim /DiscoveryHolds when SIR is on.
    # Accepts enriched $Results array (RecoverableItems_GB populated). Full scan only.
    param([object[]]$Results, [decimal]$ThresholdGB)
    $Results | Where-Object {
        $_.SIREnabled -eq $true -and
        $null -ne $_.RecoverableItems_GB -and
        $_.RecoverableItems_GB -ge $ThresholdGB
    }
}

function Get-RecoverableItemsStats {
    # Returns the Recoverable Items root folder size in GB for one mailbox.
    # Called per mailbox in Phase 3 full scan path only.
    param([string]$UPN)
    $folder = Get-MailboxFolderStatistics -Identity $UPN -FolderScope RecoverableItems |
        Where-Object { $_.FolderType -eq 'RecoverableItemsRoot' } |
        Select-Object -First 1
    if ($null -eq $folder) { return [decimal]0 }
    return [Math]::Round((ConvertTo-Bytes $folder.FolderAndSubfolderSize) / 1GB, 2)
}

function Get-MailboxRiskScore {
    # Returns 0–4 risk score: +1 per flag.
    # Reads $Script:RiThresholdGB for the SIR+RI check.
    param([PSCustomObject]$Result)
    $score = 0
    if ($Result.ElcProcessingDisabled)                                       { $score++ }
    if ($Result.LegacyHoldCount -gt 0)                                       { $score++ }
    if ($Result.LitigationHold -and
        ($Result.LitigationHoldDuration -eq 'Unlimited' -or
         $null -eq $Result.LitigationHoldDuration))                          { $score++ }
    if ($Result.SIREnabled -and
        $null -ne $Result.RecoverableItems_GB -and
        $Result.RecoverableItems_GB -ge $Script:RiThresholdGB)               { $score++ }
    return $score
}
```

- [ ] **Step 2: Syntax check**

Run the syntax validation command.
Expected: `Syntax OK — 0 errors.`

- [ ] **Step 3: Commit**

```
git add tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1
git commit -m "feat(mailbox-health-audit): add check functions (ElcDisabled, LegacyHold, LitigHold, SIR, RecovItems, RiskScore)"
```

---

## Task 3: Phase 1 (Connect) + Phase 2 (Scan Config)

**Files:**
- Modify: `tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1` (append after check functions)

- [ ] **Step 1: Append Phase 1 and Phase 2**

```powershell
# --- Phase 1: Connect to Exchange Online ---
Write-Step 1 5 "Connecting to Exchange Online..."

if (-not $TenantDomain) {
    $TenantDomain = Read-Host "      Tenant domain (e.g. corrohealth.com)"
    Write-Host ""
}

try {
    Connect-ExchangeOnline -Organization $TenantDomain -ShowBanner:$false -ErrorAction Stop
    Write-Detail "Exchange Online: connected ($TenantDomain)" Green
} catch {
    Write-Host "ERROR: Could not connect to Exchange Online. $_" -ForegroundColor Red
    exit 1
}

# --- Phase 2: Scan Configuration ---
Write-Step 2 5 "Scan configuration..."

Write-Host ""
Write-Host "      Scan depth:" -ForegroundColor White
Write-Host "        [F] Fast  — mailbox properties only (1-3 min)" -ForegroundColor Gray
Write-Host "        [R] Full  — + Recoverable Items folder size per mailbox" -ForegroundColor Gray
Write-Host "              ⚠  May take 20-40 min on large tenants." -ForegroundColor DarkYellow
Write-Host ""
$depthChoice     = Read-Host "      Scan depth [F]"
$Script:FullScan = $depthChoice -match '^[Rr]'
Write-Host ""

Write-Host "      Size thresholds (press Enter to keep default):" -ForegroundColor White
$primaryInput = Read-Host ("      Primary mailbox threshold GB [{0}]" -f $DEFAULT_PRIMARY_THRESHOLD_GB)
$Script:PrimaryThresholdGB = if ($primaryInput -match '^\d+(\.\d+)?$') { [decimal]$primaryInput } else { [decimal]$DEFAULT_PRIMARY_THRESHOLD_GB }

$riInput = Read-Host ("      Recoverable Items threshold GB [{0}]" -f $DEFAULT_RI_THRESHOLD_GB)
$Script:RiThresholdGB = if ($riInput -match '^\d+(\.\d+)?$') { [decimal]$riInput } else { [decimal]$DEFAULT_RI_THRESHOLD_GB }

$scanLabel = if ($Script:FullScan) { 'Full' } else { 'Fast' }
Write-Host ""
Write-Detail ("Scan type          : {0}" -f $scanLabel) Cyan
Write-Detail ("Primary threshold  : {0} GB" -f $Script:PrimaryThresholdGB) Gray
Write-Detail ("RI threshold       : {0} GB" -f $Script:RiThresholdGB) Gray
```

- [ ] **Step 2: Syntax check**

Run the syntax validation command.
Expected: `Syntax OK — 0 errors.`

- [ ] **Step 3: Commit**

```
git add tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1
git commit -m "feat(mailbox-health-audit): Phase 1 (connect) + Phase 2 (scan config)"
```

---

## Task 4: Phase 3 — Scan Execution

**Files:**
- Modify: `tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1` (append after Phase 2)

- [ ] **Step 1: Append Phase 3**

```powershell
# --- Phase 3: Scan Execution ---
Write-Step 3 5 "Scanning mailboxes..."

$allMailboxes = Get-Mailbox -ResultSize Unlimited
$total        = $allMailboxes.Count
Write-Host ""
Write-Detail ("Retrieved {0:N0} mailboxes." -f $total) Cyan
Write-Host ""

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$idx     = 0

foreach ($mbx in $allMailboxes) {
    $idx++
    Write-Host "`r      Scanning mailboxes... [$idx / $total]   " -NoNewline -ForegroundColor Gray

    $stats     = Get-MailboxStatistics -Identity $mbx.UserPrincipalName -ErrorAction SilentlyContinue
    $primaryGB = if ($stats) {
        [Math]::Round((ConvertTo-Bytes $stats.TotalItemSize) / 1GB, 2)
    } else { [decimal]0 }

    $legacyGuids = if ($mbx.InPlaceHolds) {
        @($mbx.InPlaceHolds | Where-Object { $_ -notmatch '^UniH' })
    } else { @() }

    $allHoldGuids = if ($mbx.InPlaceHolds) { @($mbx.InPlaceHolds) } else { @() }

    $litDuration = $null
    if ($mbx.LitigationHoldEnabled) {
        $litDuration = if ($mbx.LitigationHoldDuration) { $mbx.LitigationHoldDuration.ToString() } else { 'Unlimited' }
    }

    $results.Add([PSCustomObject]@{
        DisplayName            = $mbx.DisplayName
        UPN                    = $mbx.UserPrincipalName
        PrimarySize_GB         = $primaryGB
        RecoverableItems_GB    = $null
        ElcProcessingDisabled  = [bool]$mbx.ElcProcessingDisabled
        LitigationHold         = [bool]$mbx.LitigationHoldEnabled
        LitigationHoldDuration = $litDuration
        LegacyHoldCount        = $legacyGuids.Count
        LegacyHoldGUIDs        = $legacyGuids
        AllHoldGUIDs           = $allHoldGuids
        SIREnabled             = [bool]$mbx.SingleItemRecoveryEnabled
        RiskScore              = 0
    })
}
Write-Host ""

if ($Script:FullScan) {
    Write-Detail "Full scan: collecting Recoverable Items folder stats..." Cyan
    Write-Host ""
    $idx = 0
    foreach ($r in $results) {
        $idx++
        Write-Host "`r      Collecting RI stats... [$idx / $total]   " -NoNewline -ForegroundColor Gray
        $r.RecoverableItems_GB = Get-RecoverableItemsStats -UPN $r.UPN
    }
    Write-Host ""
}

foreach ($r in $results) {
    $r.RiskScore = Get-MailboxRiskScore -Result $r
}

$flagged = @($results | Where-Object {
    $_.RiskScore -gt 0 -or
    $_.PrimarySize_GB -ge $Script:PrimaryThresholdGB -or
    ($null -ne $_.RecoverableItems_GB -and $_.RecoverableItems_GB -ge $Script:RiThresholdGB)
} | Sort-Object RiskScore -Descending)

$scanTime      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$scanTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
```

- [ ] **Step 2: Syntax check**

Run the syntax validation command.
Expected: `Syntax OK — 0 errors.`

- [ ] **Step 3: Commit**

```
git add tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1
git commit -m "feat(mailbox-health-audit): Phase 3 — scan execution (fast + full paths, progress, results array)"
```

---

## Task 5: Phase 4 — Overview Results Display

**Files:**
- Modify: `tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1` (append after Phase 3)

- [ ] **Step 1: Append Phase 4**

```powershell
# --- Phase 4: Overview Results ---
Write-Step 4 5 "Results overview..."

$elcCount = @($results | Where-Object { $_.ElcProcessingDisabled }).Count
$legCount = @($results | Where-Object { $_.LegacyHoldCount -gt 0 }).Count
$litCount = @($results | Where-Object {
    $_.LitigationHold -and
    ($_.LitigationHoldDuration -eq 'Unlimited' -or $null -eq $_.LitigationHoldDuration)
}).Count
$priCount = @($results | Where-Object { $_.PrimarySize_GB -ge $Script:PrimaryThresholdGB }).Count
$sirCount = if ($Script:FullScan) { @(Get-SIRRiskMailboxes -Results $results -ThresholdGB $Script:RiThresholdGB).Count } else { 0 }
$riCount  = if ($Script:FullScan) { @($results | Where-Object { $null -ne $_.RecoverableItems_GB -and $_.RecoverableItems_GB -ge $Script:RiThresholdGB }).Count } else { 0 }

Write-Host ""
Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ("   MAILBOX HEALTH OVERVIEW — {0}" -f ($scanTime -split ' ')[0]) -ForegroundColor White
Write-Host ("   Scanned: {0:N0} mailboxes   Flagged: {1}" -f $total, $flagged.Count) -ForegroundColor Gray
Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""
Write-Host ("   {0,-34} : {1,4}" -f "ElcProcessingDisabled", $elcCount) -ForegroundColor $(if ($elcCount -gt 0) { 'Red' } else { 'Green' })
Write-Host ("   {0,-34} : {1,4}" -f "Legacy holds (non-UniH)", $legCount) -ForegroundColor $(if ($legCount -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ("   {0,-34} : {1,4}" -f "Litigation hold (no TTL)", $litCount) -ForegroundColor $(if ($litCount -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ("   {0,-34} : {1,4}" -f ("Primary size >= {0} GB" -f $Script:PrimaryThresholdGB), $priCount) -ForegroundColor $(if ($priCount -gt 0) { 'Yellow' } else { 'Green' })
if ($Script:FullScan) {
    Write-Host ("   {0,-34} : {1,4}" -f "SIR + high RI risk", $sirCount) -ForegroundColor $(if ($sirCount -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host ("   {0,-34} : {1,4}  [Full scan]" -f ("Recoverable Items >= {0} GB" -f $Script:RiThresholdGB), $riCount) -ForegroundColor $(if ($riCount -gt 0) { 'Yellow' } else { 'Green' })
}
Write-Host ""

if ($flagged.Count -eq 0) {
    Write-Host "   No mailboxes flagged. All within thresholds." -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "  ────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    $nameWidth = [Math]::Min(([int]($flagged | ForEach-Object { $_.DisplayName.Length } | Measure-Object -Maximum).Maximum), 30)
    Write-Host ("   {0,-4}  {1,-4}  {2}  {3,-10}  {4,-10}" -f '#', 'Risk', 'DisplayName'.PadRight($nameWidth), 'Primary', 'Rec.Items') -ForegroundColor DarkGray
    Write-Host "  ────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    $rank = 1
    foreach ($r in $flagged) {
        $bar      = [string]('█' * $r.RiskScore) + [string]('░' * (4 - $r.RiskScore))
        $barColor = if     ($r.RiskScore -ge 3) { 'Red' }
                    elseif ($r.RiskScore -ge 2) { 'Yellow' }
                    elseif ($r.RiskScore -ge 1) { 'White' }
                    else                         { 'DarkGray' }
        $riStr    = if ($null -ne $r.RecoverableItems_GB) { "{0:N1} GB" -f $r.RecoverableItems_GB } else { '—' }
        $nameStr  = if ($r.DisplayName.Length -gt $nameWidth) { $r.DisplayName.Substring(0, $nameWidth - 1) + '…' } else { $r.DisplayName.PadRight($nameWidth) }

        Write-Host ("   {0,-4}  " -f $rank) -NoNewline -ForegroundColor DarkGray
        Write-Host ("{0}  " -f $bar) -NoNewline -ForegroundColor $barColor
        Write-Host ("{0}  {1,-10}  {2}" -f $nameStr, ("{0:N1} GB" -f $r.PrimarySize_GB), $riStr) -ForegroundColor White
        $rank++
    }
    Write-Host ""
}
```

- [ ] **Step 2: Syntax check**

Run the syntax validation command.
Expected: `Syntax OK — 0 errors.`

- [ ] **Step 3: Commit**

```
git add tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1
git commit -m "feat(mailbox-health-audit): Phase 4 — overview display (flag counts + ranked table)"
```

---

## Task 6: Phase 5 — Mode Menu + [U] Individual Deep-Dive

**Files:**
- Modify: `tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1` (append after Phase 4)

- [ ] **Step 1: Append Phase 5 mode menu and [U] deep-dive**

```powershell
# --- Phase 5: Mode Menu ---
Write-Step 5 5 "Analysis menu..."

$doExport   = $false
$menuActive = $true
while ($menuActive) {
    Write-Host ""
    Write-Host "  ────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "   [U] Individual user deep-dive" -ForegroundColor Gray
    Write-Host "   [B] Batch check across flagged set" -ForegroundColor Gray
    Write-Host "   [X] Export results and exit" -ForegroundColor Gray
    Write-Host "   [Q] Exit without export" -ForegroundColor Gray
    Write-Host ""
    $menuChoice = Read-Host "      Choice"
    Write-Host ""

    switch -Regex ($menuChoice) {
        '^[Uu]' {
            $input = Read-Host "      Enter UPN or result # "
            Write-Host ""

            $target  = $null
            $rankNum = 0
            if ([int]::TryParse($input, [ref]$rankNum) -and $rankNum -ge 1 -and $rankNum -le $flagged.Count) {
                $target = $flagged[$rankNum - 1]
            } else {
                $target = $results | Where-Object { $_.UPN -ieq $input } | Select-Object -First 1
                if ($null -eq $target) {
                    Write-Detail "UPN not found in scan results. Enter an exact UPN or a result number." Yellow
                    break
                }
            }

            Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
            Write-Host ("   USER DIAGNOSTIC — {0}" -f $target.UPN) -ForegroundColor White
            Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
            Write-Host ""
            Write-Detail ("Display Name          : {0}" -f $target.DisplayName) White
            Write-Detail ("Primary Size          : {0:N1} GB" -f $target.PrimarySize_GB) $(if ($target.PrimarySize_GB -ge $Script:PrimaryThresholdGB) { 'Yellow' } else { 'White' })

            if ($null -ne $target.RecoverableItems_GB) {
                $riPct = if ($RI_QUOTA_GB -gt 0) { [int](($target.RecoverableItems_GB / $RI_QUOTA_GB) * 100) } else { 0 }
                Write-Detail ("Recoverable Items     : {0:N1} GB / {1} GB  ({2}%)" -f $target.RecoverableItems_GB, $RI_QUOTA_GB, $riPct) $(
                    if ($riPct -ge 90) { 'Red' } elseif ($riPct -ge 70) { 'Yellow' } else { 'White' }
                )
            } else {
                Write-Detail "Recoverable Items     : (run Full scan for RI data)" DarkGray
            }

            Write-Detail ("ElcProcessingDisabled : {0}" -f $(
                if ($target.ElcProcessingDisabled) { 'TRUE  ← MFA is skipped entirely for this mailbox' } else { 'False' }
            )) $(if ($target.ElcProcessingDisabled) { 'Red' } else { 'Green' })
            if ($target.ElcProcessingDisabled) {
                Write-Detail ("                        Fix: Set-Mailbox '{0}' -ElcProcessingDisabled `$false" -f $target.UPN) Gray
            }

            Write-Detail ("SingleItemRecovery    : {0}" -f $(if ($target.SIREnabled) { 'Enabled' } else { 'DISABLED' })) $(if ($target.SIREnabled) { 'Green' } else { 'Yellow' })

            Write-Detail ("LitigationHold        : {0}" -f $(
                if ($target.LitigationHold) { "Enabled  (Duration: {0})" -f $target.LitigationHoldDuration } else { 'Disabled' }
            )) $(if ($target.LitigationHold) { 'Yellow' } else { 'Green' })

            if ($target.AllHoldGUIDs.Count -gt 0) {
                Write-Detail "InPlaceHolds          :" Gray
                foreach ($guid in $target.AllHoldGUIDs) {
                    $holdLabel = Get-HoldType $guid
                    Write-Detail ("  {0}  ← {1}" -f $guid, $holdLabel) $(if ($guid -notmatch '^UniH') { 'Yellow' } else { 'Gray' })
                }
            } else {
                Write-Detail "InPlaceHolds          : None" Green
            }

            $riskLabel = if     ($target.RiskScore -ge 3) { 'HIGH' }
                         elseif ($target.RiskScore -ge 2) { 'MEDIUM' }
                         elseif ($target.RiskScore -ge 1) { 'LOW' }
                         else                              { 'OK' }
            Write-Detail ("Risk Score            : {0} / 4  ({1})" -f $target.RiskScore, $riskLabel) $(
                if ($target.RiskScore -ge 3) { 'Red' } elseif ($target.RiskScore -ge 2) { 'Yellow' } else { 'White' }
            )
            Write-Host ""
            Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
        }
        '^[Xx]' {
            $doExport   = $true
            $menuActive = $false
        }
        '^[Qq]' {
            $menuActive = $false
        }
        default {
            if ($menuChoice -notmatch '^[Bb]') {
                Write-Detail "Invalid choice. Enter U, B, X, or Q." Yellow
            }
        }
    }
}
```

Note: The `[B]` batch handler will be added in Task 7 inside this same switch. For now the default handles unknown input. Task 7 inserts the `'^[Bb]'` case.

- [ ] **Step 2: Syntax check**

Run the syntax validation command.
Expected: `Syntax OK — 0 errors.`

- [ ] **Step 3: Commit**

```
git add tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1
git commit -m "feat(mailbox-health-audit): Phase 5 — mode menu + [U] individual deep-dive"
```

---

## Task 7: [B] Batch Sub-Modes

**Files:**
- Modify: `tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1`

The `switch -Regex` block in Phase 5 needs a `'^[Bb]'` case inserted before the `'^[Xx]'` case. Use Edit tool to insert between the closing `}` of the `'^[Uu]'` block and the `'^[Xx]'` case.

- [ ] **Step 1: Insert the [B] batch case into the switch statement**

Find the line `        '^[Xx]' {` in the switch block and insert this block immediately before it:

```powershell
        '^[Bb]' {
            $batchActive = $true
            while ($batchActive) {
                Write-Host ""
                Write-Host "  ────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                Write-Host "   [E] ElcProcessingDisabled — list affected mailboxes + fix guidance" -ForegroundColor Gray
                Write-Host "   [H] Hold analysis         — hold type breakdown across flagged mailboxes" -ForegroundColor Gray
                Write-Host "   [S] SIR risk matrix        — SIR state + Recoverable Items side by side" -ForegroundColor Gray
                Write-Host "   [Q] Back to main menu" -ForegroundColor Gray
                Write-Host ""
                $batchChoice = Read-Host "      Choice"
                Write-Host ""

                switch -Regex ($batchChoice) {
                    '^[Ee]' {
                        Write-Host ""
                        Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
                        Write-Host "   ElcProcessingDisabled — MFA Skip Audit" -ForegroundColor White
                        Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
                        Write-Host ""
                        Write-Detail "When ElcProcessingDisabled = `$true, the Managed Folder Assistant" Gray
                        Write-Detail "completely skips the mailbox. Retention policies never fire and" Gray
                        Write-Detail "Recoverable Items never gets processed, regardless of SIR or hold state." Gray
                        Write-Detail "Safe to clear in bulk — no compliance review required." Gray
                        Write-Host ""

                        $elcMailboxes = @(Get-ElcDisabledMailboxes -Mailboxes $allMailboxes)
                        if ($elcMailboxes.Count -eq 0) {
                            Write-Detail "No mailboxes with ElcProcessingDisabled = `$true found." Green
                        } else {
                            $nameW = [Math]::Min(([int]($elcMailboxes | ForEach-Object { $_.DisplayName.Length } | Measure-Object -Maximum).Maximum), 30)
                            Write-Host ("   {0}  {1}" -f 'DisplayName'.PadRight($nameW), 'UPN') -ForegroundColor DarkGray
                            Write-Host "  ────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                            foreach ($m in $elcMailboxes) {
                                $nameStr = if ($m.DisplayName.Length -gt $nameW) { $m.DisplayName.Substring(0, $nameW - 1) + '…' } else { $m.DisplayName.PadRight($nameW) }
                                Write-Host ("   {0}  {1}" -f $nameStr, $m.UserPrincipalName) -ForegroundColor White
                            }
                            Write-Host ""
                            Write-Detail "Bulk fix — run for each mailbox after verifying no active migration:" Gray
                            Write-Host ""
                            foreach ($m in $elcMailboxes) {
                                Write-Host ("   Set-Mailbox -Identity '{0}' -ElcProcessingDisabled `$false" -f $m.UserPrincipalName) -ForegroundColor Cyan
                            }
                        }
                        Write-Host ""
                    }
                    '^[Hh]' {
                        Write-Host ""
                        Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
                        Write-Host "   Hold Analysis" -ForegroundColor White
                        Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
                        Write-Host ""
                        Write-Detail "UniH-prefixed GUIDs are Unified Compliance Policy holds (expected)." Gray
                        Write-Detail "Non-UniH GUIDs are legacy in-place holds from on-prem migration —" Gray
                        Write-Detail "no expiration, no visible owner, pin items in /DiscoveryHolds indefinitely." Gray
                        Write-Detail "Requires compliance team review before removal." Gray
                        Write-Host ""

                        $holdMailboxes = @($flagged | Where-Object { $_.LegacyHoldCount -gt 0 -or $_.LitigationHold })
                        if ($holdMailboxes.Count -eq 0) {
                            Write-Detail "No flagged mailboxes with notable holds." Green
                        } else {
                            foreach ($r in $holdMailboxes) {
                                Write-Host ("   {0}  ({1})" -f $r.UPN, $r.DisplayName) -ForegroundColor White
                                if ($r.LitigationHold) {
                                    Write-Host ("     LitigationHold  : Enabled  (Duration: {0})" -f $r.LitigationHoldDuration) -ForegroundColor Yellow
                                }
                                foreach ($guid in $r.AllHoldGUIDs) {
                                    $holdLabel = Get-HoldType $guid
                                    Write-Host ("     {0}  ← {1}" -f $guid, $holdLabel) -ForegroundColor $(if ($guid -notmatch '^UniH') { 'Yellow' } else { 'Gray' })
                                }
                                Write-Host ""
                            }
                        }
                    }
                    '^[Ss]' {
                        Write-Host ""
                        Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
                        Write-Host "   SIR Risk Matrix" -ForegroundColor White
                        Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
                        Write-Host ""
                        if (-not $Script:FullScan) {
                            Write-Detail "SIR risk matrix requires Full scan (Recoverable Items GB)." Yellow
                            Write-Detail "Re-run the script and choose [R] Full scan to enable this view." Gray
                        } else {
                            Write-Detail "SIR + large Recoverable Items = stalled cleanup." Gray
                            Write-Detail "MFA cannot reclaim /DiscoveryHolds when SIR is enabled." Gray
                            Write-Detail "Use Invoke-MailboxCleanup.ps1 [C] mode for remediation." Gray
                            Write-Host ""
                            $sirMailboxes = @($results | Where-Object { $null -ne $_.RecoverableItems_GB } |
                                Sort-Object RecoverableItems_GB -Descending)

                            if ($sirMailboxes.Count -eq 0) {
                                Write-Detail "No Recoverable Items data available." Gray
                            } else {
                                $upnW = [Math]::Min(([int]($sirMailboxes | ForEach-Object { $_.UPN.Length } | Measure-Object -Maximum).Maximum), 45)
                                Write-Host ("   {0}  {1,-12}  {2,-14}  {3}" -f 'UPN'.PadRight($upnW), 'SIR State', 'Rec.Items GB', 'Risk') -ForegroundColor DarkGray
                                Write-Host "  ────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                                foreach ($r in $sirMailboxes) {
                                    $sirLabel = if ($r.SIREnabled) { 'Enabled' } else { 'DISABLED' }
                                    $sirColor = if ($r.SIREnabled) { 'Green' } else { 'Yellow' }
                                    $riColor  = if ($r.RecoverableItems_GB -ge 90) { 'Red' } elseif ($r.RecoverableItems_GB -ge $Script:RiThresholdGB) { 'Yellow' } else { 'White' }
                                    $upnStr   = if ($r.UPN.Length -gt $upnW) { $r.UPN.Substring(0, $upnW - 1) + '…' } else { $r.UPN.PadRight($upnW) }
                                    Write-Host ("   {0}  " -f $upnStr) -NoNewline -ForegroundColor White
                                    Write-Host ("{0,-12}  " -f $sirLabel) -NoNewline -ForegroundColor $sirColor
                                    Write-Host ("{0,-14}  " -f ("{0:N1} GB" -f $r.RecoverableItems_GB)) -NoNewline -ForegroundColor $riColor
                                    Write-Host ("{0}" -f $r.RiskScore) -ForegroundColor $(if ($r.RiskScore -ge 3) { 'Red' } elseif ($r.RiskScore -ge 2) { 'Yellow' } else { 'White' })
                                }
                            }
                        }
                        Write-Host ""
                    }
                    '^[Qq]' { $batchActive = $false }
                    default  { Write-Detail "Invalid choice. Enter E, H, S, or Q." Yellow }
                }
            }
        }
```

- [ ] **Step 2: Syntax check**

Run the syntax validation command.
Expected: `Syntax OK — 0 errors.`

- [ ] **Step 3: Commit**

```
git add tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1
git commit -m "feat(mailbox-health-audit): [B] batch sub-modes — ElcDisabled list, hold analysis, SIR matrix"
```

---

## Task 8: Export + Disconnect + Install-Prerequisites.ps1

**Files:**
- Modify: `tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1` (append after the menu loop)
- Create: `tools/mailbox-health-audit/Install-Prerequisites.ps1`

- [ ] **Step 1: Append export handler and disconnect to the main script**

```powershell
# --- Export ---
if ($doExport) {
    $sep  = '=' * 60
    $dash = '-' * 60

    $highCount = @($flagged | Where-Object { $_.RiskScore -ge 3 }).Count
    $medCount  = @($flagged | Where-Object { $_.RiskScore -eq 2 }).Count
    $lowCount  = @($flagged | Where-Object { $_.RiskScore -eq 1 }).Count

    # CSV — one row per scanned mailbox
    $csvFile = "$([System.Environment]::GetFolderPath('Desktop'))\MailboxHealthAudit-$scanTimestamp.csv"
    $results | Select-Object DisplayName, UPN, PrimarySize_GB, RecoverableItems_GB,
        ElcProcessingDisabled, LitigationHold, LitigationHoldDuration, LegacyHoldCount,
        @{ Name = 'LegacyHoldGUIDs'; Expression = { $_.LegacyHoldGUIDs -join '; ' } },
        SIREnabled, RiskScore |
        Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

    # TXT summary
    $txtFile = "$([System.Environment]::GetFolderPath('Desktop'))\MailboxHealthAudit-$scanTimestamp.txt"
    $report  = @(
        $sep
        " MAILBOX HEALTH AUDIT SUMMARY"
        $sep
        (" Date        : {0}" -f $scanTime)
        (" Scan Type   : {0}" -f $(if ($Script:FullScan) { 'Full' } else { 'Fast' }))
        (" Thresholds  : Primary >= {0} GB | Recoverable Items >= {1} GB" -f $Script:PrimaryThresholdGB, $Script:RiThresholdGB)
        (" Scanned     : {0:N0} mailboxes" -f $total)
        (" Flagged     : {0} mailboxes" -f $flagged.Count)
        ""
        $dash
        " FLAG BREAKDOWN"
        $dash
        (" ElcProcessingDisabled     : {0,-4}  Safe to clear — no compliance review needed" -f $elcCount)
        (" Legacy holds (non-UniH)   : {0,-4}  Requires compliance team review before removal" -f $legCount)
        (" Litigation hold (no TTL)  : {0,-4}  Requires legal sign-off" -f $litCount)
        (" Primary size >= {0} GB  : {1,-4}" -f $Script:PrimaryThresholdGB, $priCount)
    )
    if ($Script:FullScan) {
        $report += (" SIR + high RI risk        : {0,-4}  Candidates for Invoke-MailboxCleanup.ps1" -f $sirCount)
        $report += (" Recoverable Items >= {0} GB: {1,-4}  [Full scan]" -f $Script:RiThresholdGB, $riCount)
    }
    $report += @(
        ""
        $dash
        " RISK TIER BREAKDOWN"
        $dash
        (" HIGH   (score 3-4) : {0} mailboxes" -f $highCount)
        (" MEDIUM (score 2)   : {0} mailboxes" -f $medCount)
        (" LOW    (score 1)   : {0} mailboxes" -f $lowCount)
        ""
        $dash
        " RECOMMENDED ACTIONS"
        $dash
        " 1. ElcProcessingDisabled = True"
        "    Run: Set-Mailbox -Identity <UPN> -ElcProcessingDisabled `$false"
        "    Effect: MFA resumes processing — mailbox rejoins normal retention cycle."
        "    Approval: None required."
        ""
        " 2. Legacy in-place holds (non-UniH GUIDs)"
        "    Review each GUID with the compliance team to confirm the hold is still needed."
        "    If stale: Remove-MailboxSearch or close the eDiscovery case that created it."
        "    Approval: Compliance team sign-off required."
        ""
        " 3. Litigation hold with no duration"
        "    Confirm with legal whether an expiry date can be set."
        "    If no longer needed: Set-Mailbox '<UPN>' -LitigationHoldEnabled `$false"
        "    Approval: Legal sign-off required."
        ""
        " 4. SIR + high Recoverable Items"
        "    These mailboxes are candidates for Invoke-MailboxCleanup.ps1 [C] mode."
        "    See: tools\mailbox-cleanup\Invoke-MailboxCleanup.ps1"
        $sep
    )
    $report | Out-File -FilePath $txtFile -Encoding UTF8

    Write-Host ""
    Write-Host "  Exports saved to Desktop:" -ForegroundColor Green
    Write-Host ("    {0}" -f $csvFile) -ForegroundColor Cyan
    Write-Host ("    {0}" -f $txtFile) -ForegroundColor Cyan
    Write-Host ""
}

# --- Session cleanup ---
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
```

- [ ] **Step 2: Create Install-Prerequisites.ps1**

Create `C:\dev\projects\it-tools\tools\mailbox-health-audit\Install-Prerequisites.ps1`:

```powershell
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  ERR $msg" -ForegroundColor Red }

Write-Host ""

Write-Step "Trusting PSGallery..."
try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Write-OK "PSGallery trusted"
} catch {
    Write-Fail "Could not trust PSGallery: $_"
    exit 1
}

Write-Step "Installing PowerShellGet..."
try {
    Install-Module PowerShellGet -Scope CurrentUser -Force -AllowClobber
    $v = (Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-OK "PowerShellGet v$v"
} catch {
    Write-Fail "PowerShellGet failed: $_"
    exit 1
}

Write-Step "Installing ExchangeOnlineManagement..."
try {
    Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
    $v = (Get-Module ExchangeOnlineManagement -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-OK "ExchangeOnlineManagement v$v"
} catch {
    Write-Fail "ExchangeOnlineManagement failed: $_"
    exit 1
}

Write-Host ""
Write-Host "  All prerequisites installed. You are ready to run the Mailbox Health Audit." -ForegroundColor Green
Write-Host ""
```

- [ ] **Step 3: Final syntax check on both files**

```powershell
# Check main script
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-health-audit\Invoke-MailboxHealthAudit.ps1',
    [ref]$null, [ref]$errors
)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host ("Line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) -ForegroundColor Red }
} else { Write-Host "Main script: Syntax OK" -ForegroundColor Green }

# Check install script
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'C:\dev\projects\it-tools\tools\mailbox-health-audit\Install-Prerequisites.ps1',
    [ref]$null, [ref]$errors
)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host ("Line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) -ForegroundColor Red }
} else { Write-Host "Install script: Syntax OK" -ForegroundColor Green }
```

Expected:
```
Main script: Syntax OK
Install script: Syntax OK
```

- [ ] **Step 4: Commit**

```
git add tools/mailbox-health-audit/Invoke-MailboxHealthAudit.ps1
git add tools/mailbox-health-audit/Install-Prerequisites.ps1
git commit -m "feat(mailbox-health-audit): export (CSV + TXT), disconnect, Install-Prerequisites.ps1 — v1.0 complete"
```

---

## Post-Build Smoke Test

After all 8 tasks are committed, verify the script is runnable before first live use:

1. Open PowerShell as the admin account that has Exchange Administrator role
2. `cd C:\dev\projects\it-tools\tools\mailbox-health-audit`
3. `.\Invoke-MailboxHealthAudit.ps1 -TenantDomain corrohealth.com`
4. Choose **[F] Fast** scan, accept default thresholds
5. Confirm the overview table renders and the mode menu accepts input
6. Choose **[U]**, enter a known UPN, verify the diagnostic panel displays correctly
7. Choose **[X]**, confirm CSV and TXT files land on the Desktop

---

## Spec Coverage Check

| Spec Section | Covered By |
|---|---|
| Phase 1 — Connect | Task 3 |
| Phase 2 — Scan depth [F]/[R] + threshold prompts | Task 3 |
| Phase 3 — Bulk Get-Mailbox + per-mailbox stats + progress | Task 4 |
| Phase 3 — Full scan RI folder stats | Task 4 |
| Phase 3 — Risk score calculation | Task 4 |
| Phase 4 — Summary strip (counts per flag) | Task 5 |
| Phase 4 — Ranked table with risk bars | Task 5 |
| [U] — Individual deep-dive panel | Task 6 |
| [B][E] — ElcProcessingDisabled batch + fix commands | Task 7 |
| [B][H] — Hold analysis with GUID classification | Task 7 |
| [B][S] — SIR risk matrix (Full scan gate) | Task 7 |
| [X] — CSV export (all mailboxes) | Task 8 |
| [X] — TXT summary with recommended actions | Task 8 |
| [Q] — Exit without export | Task 6 |
| Install-Prerequisites.ps1 | Task 8 |
| Dot-source / standalone check function usage | Task 2 (functions defined top-level) |
