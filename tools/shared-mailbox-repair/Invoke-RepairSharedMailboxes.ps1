param(
    [Parameter(Mandatory, HelpMessage = "UPN of the affected user, e.g. john.doe@corrohealth.com")]
    [string]$Mailbox
)

# --- Module install/update (requires v3.9.0+ for Get-EXOMailboxPermission) ---
$minVersion = [Version]"3.9.0"
$installed = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
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

# --- State ---
$allMailboxes    = @()
$toRefresh       = @()
$results         = @()
$failureCount    = 0
$reportTime      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- Helpers ---
function Write-Step {
    param([int]$Step, [string]$Message)
    Write-Host "`n[$Step/4] $Message" -ForegroundColor Cyan
}

function Write-Detail {
    param([string]$Message, [string]$Color = 'White')
    Write-Host "      $Message" -ForegroundColor $Color
}

# --- Banner ---
Write-Host ""
Write-Host "  ================================================" -ForegroundColor DarkCyan
Write-Host "   Shared Mailbox Repair Tool" -ForegroundColor White
Write-Host "  ================================================" -ForegroundColor DarkCyan
Write-Host "   Target: $Mailbox" -ForegroundColor Gray
Write-Host ""

# --- Phase 1: Connect to Exchange Online ---
Write-Step 1 "Connecting to Exchange Online..."
try {
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Detail "Exchange Online: connected" Green
} catch {
    Write-Host "ERROR: Could not connect to Exchange Online. $_" -ForegroundColor Red
    exit 1
}

# --- Phase 2: Shared mailbox status ---
Write-Step 2 "Shared mailbox status: $Mailbox"

# Verify target user exists
try {
    $null = Get-EXOMailbox -Identity $Mailbox -ErrorAction Stop
} catch {
    Write-Host "ERROR: Mailbox '$Mailbox' not found. Check the UPN and try again." -ForegroundColor Red
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 1
}

Write-Detail "Scanning shared mailboxes for $Mailbox ..." Gray

$sharedMailboxes = Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -ErrorAction Stop

$allMailboxes = @()
foreach ($mbx in $sharedMailboxes) {
    $perm = Get-EXOMailboxPermission -Identity $mbx.Identity -User $Mailbox -ErrorAction SilentlyContinue |
        Where-Object { $_.AccessRights -contains 'FullAccess' -and -not $_.Deny }
    if ($perm) {
        $autoMap = if ($null -ne $perm.AutoMapping) { [bool]$perm.AutoMapping } else { $true }
        $allMailboxes += [PSCustomObject]@{
            Address     = $mbx.PrimarySmtpAddress
            DisplayName = $mbx.DisplayName
            AutoMapping = $autoMap
        }
    }
}

# --- Exit: no shared mailboxes found ---
if ($allMailboxes.Count -eq 0) {
    Write-Host ""
    Write-Detail "No shared mailbox access found for $Mailbox." Yellow
    Write-Detail "If mailboxes should be present, verify Full Access grants in Exchange admin." Gray
    Write-Detail "This is a permissions issue, not an AutoMapping issue." Gray
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
    exit 0
}

$toRefresh = $allMailboxes | Where-Object { $_.AutoMapping -eq $true }
$skipped   = $allMailboxes | Where-Object { $_.AutoMapping -eq $false }

# --- Display table ---
Write-Host ""
Write-Detail ("{0,-50} {1}" -f 'Mailbox', 'AutoMapping') Gray
Write-Detail ("{0,-50} {1}" -f '-------', '-----------') Gray

foreach ($mbx in $allMailboxes) {
    if ($mbx.AutoMapping) {
        Write-Detail ("{0,-50} {1}" -f $mbx.Address, 'Enabled') Green
    } else {
        Write-Detail ("{0,-50} {1,-10}  (manually added, will be skipped)" -f $mbx.Address, 'Disabled') Gray
    }
}

Write-Host ""
Write-Detail ("{0} mailbox(es) found — {1} will be refreshed" -f $allMailboxes.Count, $toRefresh.Count) White

# --- Exit: all mailboxes have AutoMapping disabled ---
if ($toRefresh.Count -eq 0) {
    Write-Host ""
    Write-Detail "All shared mailboxes use manual mapping — AutoMapping is not the likely cause." Yellow
    Write-Detail "Consider rebuilding the Outlook profile:" Gray
    Write-Detail "  Control Panel > Mail > Show Profiles > Add (create new profile)" Gray
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
    exit 0
}

# --- Confirm ---
Write-Host ""
$go = Read-Host "      Proceed with refresh? [Y/N]"
Write-Host ""
if ($go -notmatch '^[Yy]') {
    Write-Host "  No changes made.`n" -ForegroundColor Cyan
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 0
}

# --- Phase 3: Permission refresh ---
Write-Step 3 "Refreshing permissions..."
Write-Host ""

$results = @()
$i = 0
foreach ($mbx in $toRefresh) {
    $label = "[{0}/{1}] {2}" -f ($i + 1), $toRefresh.Count, $mbx.Address
    Write-Host ("      {0,-68}" -f $label) -NoNewline

    try {
        Remove-MailboxPermission -Identity $mbx.Address -User $Mailbox `
            -AccessRights FullAccess -Confirm:$false -ErrorAction Stop
        Add-MailboxPermission -Identity $mbx.Address -User $Mailbox `
            -AccessRights FullAccess -AutoMapping $true -ErrorAction Stop | Out-Null

        Write-Host "Done" -ForegroundColor Green
        $results += [PSCustomObject]@{
            Address = $mbx.Address
            Outcome = 'Refreshed'
            Reason  = ''
        }
    } catch {
        $errMsg = $_.Exception.Message
        Write-Host "Failed" -ForegroundColor Red
        Write-Detail "    $errMsg" Red
        $results += [PSCustomObject]@{
            Address = $mbx.Address
            Outcome = 'Failed'
            Reason  = $errMsg
        }
        $failureCount++
    }
    $i++
}

# Add skipped mailboxes to results for reporting
foreach ($mbx in $skipped) {
    $results += [PSCustomObject]@{
        Address = $mbx.Address
        Outcome = 'Skipped'
        Reason  = 'AutoMapping disabled'
    }
}
