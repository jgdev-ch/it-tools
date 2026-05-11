param(
    [Parameter(Mandatory, HelpMessage = "UPN of the affected user, e.g. john.doe@corrohealth.com")]
    [string]$Mailbox
)

# --- Module install/update (requires v3.9.0+ for EnableSearchOnlySession) ---
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

# --- Constants ---
$RETENTION_POLICY_NAME    = "3 Year Email Retention Policy"
$PROPAGATION_WAIT_SECONDS = 120
$POLL_INTERVAL_SECONDS    = 30

# --- State ---
$searchName       = $null
$search           = $null
$aborted          = $false
$errorOccurred    = $false
$policyRestored   = $false
$delayHoldCleared        = $false
$delayReleaseHoldCleared = $false
$mfaTriggered            = $false
$reportTime       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportTimestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- Helpers ---
function Write-Step {
    param([int]$Step, [string]$Message)
    Write-Host "`n[$Step/6] $Message" -ForegroundColor Cyan
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
    # ByteQuantifiedSize object (legacy RPS mode)
    if ($Value.GetType().Name -eq 'ByteQuantifiedSize') { return $Value.ToBytes() }
    # REST module returns strings like "28.4 GB (30,480,000,000 bytes)"
    if ($Value -is [string] -and $Value -match '\((\d[\d,]*)\s+bytes?\)') {
        return [long]($Matches[1] -replace ',', '')
    }
    # Numeric fallback (already bytes)
    try { return [long]$Value } catch { return [long]0 }
}

function Get-RecoverableStats {
    param([string]$MailboxAddress)
    Get-MailboxFolderStatistics -Identity $MailboxAddress -FolderScope RecoverableItems |
        Where-Object { $_.FolderType -eq 'RecoverableItemsRoot' }
}

function Confirm-Continue {
    param([string]$Prompt)
    Write-Host ""
    $response = Read-Host "      $Prompt [Y/N]"
    Write-Host ""
    if ($response -notmatch '^[Yy]') {
        Write-Host "      Aborted. Cleaning up..." -ForegroundColor Yellow
        throw "Aborted by user."
    }
}

# --- Main ---
Write-Host ""
Write-Host "  ================================================" -ForegroundColor DarkCyan
Write-Host "   Mailbox Cleanup Tool" -ForegroundColor White
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

# --- Phase 2: Mailbox status check ---
Write-Step 2 "Mailbox status: $Mailbox"
$mbx = $null
try {
    $mbx = Get-Mailbox -Identity $Mailbox -ErrorAction Stop
} catch {
    Write-Host "ERROR: Mailbox '$Mailbox' not found. Check the UPN and try again." -ForegroundColor Red
    exit 1
}

$statsBefore = Get-RecoverableStats -MailboxAddress $Mailbox
$usedBytes   = ConvertTo-Bytes $statsBefore.FolderAndSubfolderSize
$limitBytes  = ConvertTo-Bytes $mbx.RecoverableItemsQuota
$pct         = if ($limitBytes -gt 0) { [int](($usedBytes / $limitBytes) * 100) } else { 0 }

Write-Detail ("Recoverable Items : {0} / {1} ({2}% full)" -f `
    (Format-Size $usedBytes), (Format-Size $limitBytes), $pct) `
    $(if ($pct -ge 90) { 'Red' } elseif ($pct -ge 70) { 'Yellow' } else { 'Green' })

# Hold status
$holdFlags = @()
if ($mbx.LitigationHoldEnabled)                            { $holdFlags += "Litigation Hold" }
if ($mbx.DelayHoldApplied)                                 { $holdFlags += "Delay Hold (will be cleared)" }
if ($mbx.InPlaceHolds -and $mbx.InPlaceHolds.Count -gt 0) { $holdFlags += "$($mbx.InPlaceHolds.Count) policy/eDiscovery hold(s)" }
$holdDisplay = if ($holdFlags.Count -gt 0) { $holdFlags -join ', ' } else { 'None' }
$holdColor   = if ($mbx.LitigationHoldEnabled) { 'Red' } `
               elseif ($mbx.DelayHoldApplied -or ($mbx.InPlaceHolds -and $mbx.InPlaceHolds.Count -gt 0)) { 'Yellow' } `
               else { 'Green' }
Write-Detail ("Holds active      : {0}" -f $holdDisplay) $holdColor

if ($mbx.LitigationHoldEnabled) {
    Write-Host ""
    Write-Host "      ================================================" -ForegroundColor Red
    Write-Host "       WARNING — Litigation Hold Detected" -ForegroundColor Red
    Write-Host "       This mailbox is under an active litigation hold." -ForegroundColor White
    Write-Host "       Purging Recoverable Items may violate legal" -ForegroundColor White
    Write-Host "       preservation requirements." -ForegroundColor White
    Write-Host "       Contact your compliance team before proceeding." -ForegroundColor White
    Write-Host "      ================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Aborted. No changes were made.`n" -ForegroundColor Red
    exit 1
}

# Folder breakdown — only folders that contain items
$folderBreakdown = Get-MailboxFolderStatistics -Identity $Mailbox -FolderScope RecoverableItems |
    Where-Object { $_.ItemsInFolder -gt 0 }
if ($folderBreakdown) {
    Write-Detail "Folder breakdown  :" Gray
    $folderBreakdown | ForEach-Object {
        Write-Detail ("    {0,-46} {1,8} items   {2}" -f $_.FolderPath, $_.ItemsInFolder, (Format-Size (ConvertTo-Bytes $_.FolderAndSubfolderSize))) Gray
    }
}

# Status-check decision point — tech reviews the above before committing to cleanup
Write-Host ""
$go = Read-Host "      Proceed with cleanup? [Y/N]"
Write-Host ""
if ($go -notmatch '^[Yy]') {
    Write-Host "  Status check complete. No changes were made.`n" -ForegroundColor Cyan
    exit 0
}

# --- Phase 3: Connect to Security & Compliance ---
Write-Step 3 "Connecting to Security & Compliance..."
try {
    Connect-IPPSSession -EnableSearchOnlySession -ErrorAction Stop -WarningAction SilentlyContinue 6>$null
    Write-Detail "Security & Compliance: connected" Green
} catch {
    Write-Host "ERROR: Could not connect to Security & Compliance (IPPSSession). $_" -ForegroundColor Red
    exit 1
}

# --- Phase 4: Purview policy exclusion ---
Write-Step 4 "Adding Purview policy exclusion..."
$policy = $null
try {
    $policy = Get-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME -ErrorAction Stop
} catch {
    Write-Host "ERROR: Retention policy '$RETENTION_POLICY_NAME' not found. Update `$RETENTION_POLICY_NAME in the script constants." -ForegroundColor Red
    exit 1
}

try {
    Set-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME `
        -AddExchangeLocationException $Mailbox -ErrorAction Stop
    Write-Detail "Policy exception added for $Mailbox" Green

    $barWidth = 28
    $elapsed  = 0
    while ($elapsed -lt $PROPAGATION_WAIT_SECONDS) {
        $remaining = $PROPAGATION_WAIT_SECONDS - $elapsed
        $filled    = [int]([Math]::Round(($PROPAGATION_WAIT_SECONDS - $remaining) / $PROPAGATION_WAIT_SECONDS * $barWidth))
        $bar       = ('#' * $filled).PadRight($barWidth, '-')
        Write-Host "`r      [$bar] ${remaining}s remaining " -NoNewline -ForegroundColor Yellow
        $sleep = [Math]::Min($POLL_INTERVAL_SECONDS, $remaining)
        Start-Sleep -Seconds $sleep
        $elapsed += $sleep
    }
    Write-Host "`r      [$('#' * $barWidth)] propagation complete      " -ForegroundColor Green

    Confirm-Continue "Propagation complete. Proceed with compliance search?"

    # --- Phase 5: Compliance search + purge ---
    $alias      = ($Mailbox -split '@')[0]
    $timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $searchName = "RecovItems-$alias-$timestamp"

    Write-Step 5 "Compliance search: $searchName"

    New-ComplianceSearch -Name $searchName `
        -ExchangeLocation $Mailbox `
        -ContentMatchQuery 'folderpath:"recoverable items"' `
        -ErrorAction Stop | Out-Null

    Start-ComplianceSearch -Identity $searchName -ErrorAction Stop

    $elapsed = 0
    do {
        Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
        $elapsed += $POLL_INTERVAL_SECONDS
        $search = Get-ComplianceSearch -Identity $searchName
        Write-Detail "Searching... (${elapsed}s) - $($search.Status)"
    } while ($search.Status -notin @('Completed', 'Failed'))

    if ($search.Status -eq 'Failed') {
        throw "Compliance search '$searchName' failed. Check the Security & Compliance portal for details."
    }

    Write-Detail ("Search complete - {0:N0} items found ({1} compliance-hold storage)" -f `
        $search.Items, (Format-Size ($search.Size))) Green

    Confirm-Continue ("Proceed with HardDelete purge of {0:N0} items ({1})?" -f $search.Items, (Format-Size $search.Size))

    Write-Detail "Running purge (HardDelete)..." Yellow

    New-ComplianceSearchAction -SearchName $searchName `
        -Purge -PurgeType HardDelete -Confirm:$false -ErrorAction Stop | Out-Null

    $actionName = "$searchName`_Purge"
    $elapsed    = 0
    do {
        Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
        $elapsed += $POLL_INTERVAL_SECONDS
        $action = Get-ComplianceSearchAction -Identity $actionName
        Write-Detail "Purging... (${elapsed}s) - $($action.Status)"
    } while ($action.Status -notin @('Completed', 'Failed'))

    if ($action.Status -eq 'Failed') {
        throw "Compliance purge action '$actionName' failed. Check the Security & Compliance portal for details."
    }

    Write-Detail "Purge complete." Green

} catch {
    if ($_.Exception.Message -eq 'Aborted by user.') {
        $aborted = $true
    } else {
        Write-Host "`n      ERROR: $_" -ForegroundColor Red
        $errorOccurred = $true
    }
} finally {
    # --- Phase 6: Verify and restore (always runs) ---
    Write-Step 6 "Verifying and restoring..."

    if ($mbx) {
        $statsAfter = Get-RecoverableStats -MailboxAddress $Mailbox
        $afterBytes = ConvertTo-Bytes $statsAfter.FolderAndSubfolderSize
        $afterPct   = if ($limitBytes -gt 0) { [int](($afterBytes / $limitBytes) * 100) } else { 0 }

        Write-Host ""
        Write-Host "      ================================================" -ForegroundColor DarkCyan
        Write-Host "       Results" -ForegroundColor White
        Write-Detail ("  Before : {0} / {1} ({2}% full)" -f (Format-Size $usedBytes), (Format-Size $limitBytes), $pct) White
        if ($search -and $search.Items -gt 0) {
            Write-Detail ("  Purged : {0:N0} items  ({1} compliance-hold storage freed)" -f $search.Items, (Format-Size $search.Size)) Green
        }
        $afterLabel = if ($afterPct -ge 70) { 'Yellow' } else { 'Green' }
        Write-Detail ("  After  : {0} / {1} ({2}%)*" -f (Format-Size $afterBytes), (Format-Size $limitBytes), $afterPct) $afterLabel
        Write-Detail "  * Exchange reclaims space within ~1h after MFA runs (triggered below)." Gray
        Write-Host "      ================================================" -ForegroundColor DarkCyan
        Write-Host ""
    }

    if ($policy) {
        try {
            Set-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME `
                -RemoveExchangeLocationException $Mailbox -ErrorAction Stop
            Write-Detail "Purview policy exception removed." Green
            $policyRestored = $true
        } catch {
            Write-Detail "WARNING: Could not remove Purview exception. Remove '$Mailbox' from '$RETENTION_POLICY_NAME' exceptions in Purview manually." Yellow
        }
    }

    # Clear delay holds — Exchange sets these automatically when a hold is modified,
    # blocking MFA from reclaiming quota for up to 30 days without this step.
    # DelayHoldApplied covers primary Recoverable Items; DelayReleaseHoldApplied
    # covers cloud-based storage areas (Teams/Skype content in hidden subfolders).
    $freshMbx = Get-Mailbox -Identity $Mailbox -ErrorAction SilentlyContinue
    if ($freshMbx -and $freshMbx.DelayHoldApplied) {
        try {
            Set-Mailbox -Identity $Mailbox -RemoveDelayHoldApplied -ErrorAction Stop
            Write-Detail "Delay hold cleared (DelayHoldApplied)." Green
            $delayHoldCleared = $true
        } catch {
            Write-Detail "WARNING: Could not clear delay hold. Run manually: Set-Mailbox -Identity '$Mailbox' -RemoveDelayHoldApplied" Yellow
        }
    }
    if ($freshMbx -and $freshMbx.DelayReleaseHoldApplied) {
        try {
            Set-Mailbox -Identity $Mailbox -RemoveDelayReleaseHoldApplied -ErrorAction Stop
            Write-Detail "Delay release hold cleared (DelayReleaseHoldApplied)." Green
            $delayReleaseHoldCleared = $true
        } catch {
            Write-Detail "WARNING: Could not clear delay release hold. Run manually: Set-Mailbox -Identity '$Mailbox' -RemoveDelayReleaseHoldApplied" Yellow
        }
    }

    try {
        Start-ManagedFolderAssistant -Identity $Mailbox -ErrorAction Stop
        Write-Detail "Managed Folder Assistant triggered." Green
        $mfaTriggered = $true
    } catch {
        Write-Detail "WARNING: Could not trigger Managed Folder Assistant. Quota reclamation may take longer." Yellow
    }

    if ($searchName) {
        try {
            Remove-ComplianceSearch -Identity $searchName -Confirm:$false -ErrorAction Stop
            Write-Detail "Compliance search deleted." Green
        } catch {
            Write-Detail "WARNING: Could not delete compliance search '$searchName'. Delete it manually from the Security & Compliance portal." Yellow
        }
    }
}

if (-not $aborted -and -not $errorOccurred) {
    Write-Host "`nDone. Purge complete for $Mailbox." -ForegroundColor Green
    Write-Host "      Managed Folder Assistant has been triggered. The user can send and receive once Exchange reclaims the purged space (typically within 1 hour).`n" -ForegroundColor Gray
} elseif ($aborted) {
    Write-Host "`nAborted. No items were purged. Policy exception and compliance search have been cleaned up.`n" -ForegroundColor Yellow
}

# --- Ticket export ---
Write-Host ""
$export = Read-Host "      Export summary report for ticket? [Y/N]"
if ($export -match '^[Yy]') {
    $reportAlias = ($Mailbox -split '@')[0]
    $reportFile  = "$([System.Environment]::GetFolderPath('Desktop'))\MailboxCleanup-$reportAlias-$reportTimestamp.txt"

    $sep  = "=" * 60
    $dash = "-" * 60
    $report = @(
        $sep
        " MAILBOX CLEANUP REPORT"
        $sep
        " Date   : $reportTime"
        " Target : $Mailbox"
        ""
        $dash
        " PRE-FLIGHT"
        $dash
        (" Recoverable Items : {0} / {1} ({2}% full)" -f (Format-Size $usedBytes), (Format-Size $limitBytes), $pct)
        (" Holds active      : {0}" -f $holdDisplay)
        " Folder breakdown  :"
    )
    if ($folderBreakdown) {
        $folderBreakdown | ForEach-Object {
            $report += ("   {0,-50} {1,8} items   {2}" -f $_.FolderPath, $_.ItemsInFolder, $_.FolderAndSubfolderSize)
        }
    }
    $report += @(
        ""
        $dash
        " RESULTS"
        $dash
        (" Before : {0} / {1} ({2}% full)" -f (Format-Size $usedBytes), (Format-Size $limitBytes), $pct)
    )
    if ($search -and $search.Items -gt 0) {
        $report += (" Purged : {0:N0} items  ({1} compliance-hold storage freed)" -f $search.Items, (Format-Size $search.Size))
    }
    if ($null -ne $afterBytes) {
        $report += (" After  : {0} / {1} ({2}%)*" -f (Format-Size $afterBytes), (Format-Size $limitBytes), $afterPct)
        $report += " * Exchange reclaims space within ~1h after MFA runs"
    }
    $report += @(
        ""
        $dash
        " CLEANUP ACTIONS"
        $dash
        (" Purview policy exception removed : {0}" -f $(if ($policyRestored)   { 'Yes' } else { 'No' }))
        (" Delay hold cleared               : {0}" -f $(if ($delayHoldCleared)        { 'Yes' } else { 'No (not present)' }))
        (" Delay release hold cleared       : {0}" -f $(if ($delayReleaseHoldCleared) { 'Yes' } else { 'No (not present)' }))
        (" Managed Folder Assistant triggered: {0}" -f $(if ($mfaTriggered)    { 'Yes' } else { 'No' }))
        ""
        $dash
        " OUTCOME"
        $dash
    )
    if (-not $aborted -and -not $errorOccurred) {
        $report += " Purge complete. MFA triggered. Space reclaims within ~1 hour."
    } elseif ($aborted) {
        $report += " Aborted by operator. No items were purged."
    } else {
        $report += " Completed with errors. Review console output for details."
    }
    $report += $sep

    $report | Out-File -FilePath $reportFile -Encoding UTF8
    Write-Host ""
    Write-Host "      Report saved to: $reportFile" -ForegroundColor Green
    Write-Host ""
}

# --- Session cleanup ---
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray

# --- Future enhancement notes ---
# The following scenarios are not currently handled and may warrant wizard-style
# options if this script needs to expand:
#
# 1. Multiple holds: Script only removes the exception from the named retention
#    policy ($RETENTION_POLICY_NAME). If InPlaceHolds shows additional policies
#    or eDiscovery holds, those still preserve items and the purge may be partial.
#    A future pass could enumerate InPlaceHolds and offer per-hold exception options.
#
# 2. Unindexed items (V2): The compliance search uses a folderpath keyword query,
#    which only reaches indexed items. A second pass with no keyword filter would
#    sweep any unindexed items MFA misses. Low priority — MFA + delay hold clearing
#    handles these in practice, as confirmed in testing.
