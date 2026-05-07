param(
    [Parameter(Mandatory, HelpMessage = "UPN of the affected user, e.g. john.doe@corrohealth.com")]
    [string]$Mailbox
)

# --- Module auto-install (runs silently on machines that already have it) ---
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Host "ExchangeOnlineManagement module not found. Installing..." -ForegroundColor Yellow
    Install-Module ExchangeOnlineManagement -Force -Scope CurrentUser
}
try {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
} catch {
    Write-Host "ERROR: Failed to load ExchangeOnlineManagement module. $_" -ForegroundColor Red
    exit 1
}

# --- Constants (update $RETENTION_POLICY_NAME if policy is renamed) ---
$RETENTION_POLICY_NAME    = "3 Year Retention Policy"
$PROPAGATION_WAIT_SECONDS = 120
$POLL_INTERVAL_SECONDS    = 30

# --- State (initialized before try block so finally can reference them) ---
$searchName = $null

# --- Helpers ---
function Write-Step {
    param([int]$Step, [string]$Message)
    Write-Host "`n[$Step/5] $Message" -ForegroundColor Cyan
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

function Get-RecoverableStats {
    param([string]$MailboxAddress)
    Get-MailboxFolderStatistics -Identity $MailboxAddress -FolderScope RecoverableItems |
        Where-Object { $_.FolderType -eq 'RecoverableItemsRoot' }
}

# --- Main ---
Write-Host "`nMailbox Cleanup" -ForegroundColor White
Write-Host "Target: $Mailbox`n" -ForegroundColor Gray

# --- Phase 1: Connect ---
Write-Step 1 "Connecting to Exchange Online and Security & Compliance..."
try {
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Detail "Exchange Online: connected" Green
} catch {
    Write-Host "ERROR: Could not connect to Exchange Online. $_" -ForegroundColor Red
    exit 1
}
try {
    Connect-IPPSSession -ErrorAction Stop
    Write-Detail "Security & Compliance: connected" Green
} catch {
    Write-Host "ERROR: Could not connect to Security & Compliance (IPPSSession). $_" -ForegroundColor Red
    exit 1
}
