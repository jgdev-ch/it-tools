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
