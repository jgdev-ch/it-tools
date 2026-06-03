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
    $folder = Get-MailboxFolderStatistics -Identity $UPN -FolderScope RecoverableItems -ErrorAction SilentlyContinue |
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
