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

# --- Constants (update $RETENTION_POLICY_NAME if policy is renamed) ---
$RETENTION_POLICY_NAME    = "3 Year Email Retention Policy"
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
    Connect-IPPSSession -EnableSearchOnlySession -ErrorAction Stop
    Write-Detail "Security & Compliance: connected" Green
} catch {
    Write-Host "ERROR: Could not connect to Security & Compliance (IPPSSession). $_" -ForegroundColor Red
    exit 1
}

# --- Phase 2: Pre-flight ---
Write-Step 2 "Pre-flight: $Mailbox"
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

Write-Detail ("Recoverable Items: {0} / {1} ({2}% full)" -f `
    (Format-Size $usedBytes), (Format-Size $limitBytes), $pct) `
    $(if ($pct -ge 90) { 'Red' } elseif ($pct -ge 70) { 'Yellow' } else { 'Green' })

# --- Phase 3: Purview policy exclusion ---
Write-Step 3 "Adding Purview policy exclusion..."
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

    $elapsed = 0
    while ($elapsed -lt $PROPAGATION_WAIT_SECONDS) {
        $remaining = $PROPAGATION_WAIT_SECONDS - $elapsed
        Write-Host "`r      Waiting for propagation: ${remaining}s..." -NoNewline -ForegroundColor Yellow
        $sleep = [Math]::Min($POLL_INTERVAL_SECONDS, $remaining)
        Start-Sleep -Seconds $sleep
        $elapsed += $sleep
    }
    Write-Host "`r      Propagation wait complete.                    " -ForegroundColor Green

    # --- Phase 4: Compliance search ---
    $alias      = ($Mailbox -split '@')[0]
    $timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $searchName = "RecovItems-$alias-$timestamp"

    Write-Step 4 "Compliance search: $searchName"

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

    Write-Detail ("Search complete - {0:N0} items found ({1})" -f `
        $search.Items, (Format-Size ($search.Size))) Green

    # --- Phase 4b: Purge ---
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

} finally {
    # --- Phase 5: Verify and restore (always runs) ---
    Write-Step 5 "Verifying and restoring..."

    if ($mbx) {
        $statsAfter = Get-RecoverableStats -MailboxAddress $Mailbox
        $afterBytes = ConvertTo-Bytes $statsAfter.FolderAndSubfolderSize
        $afterPct   = if ($limitBytes -gt 0) { [int](($afterBytes / $limitBytes) * 100) } else { 0 }
        Write-Detail ("Recoverable Items: {0} / {1} ({2}% full)" -f `
            (Format-Size $afterBytes), (Format-Size $limitBytes), $afterPct) `
            $(if ($afterPct -ge 70) { 'Yellow' } else { 'Green' })
        Write-Detail "Note: quota may still show full — Exchange reclaims space within a few hours as the Managed Folder Assistant runs in the background." White
    }

    if ($policy) {
        try {
            Set-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME `
                -RemoveExchangeLocationException $Mailbox -ErrorAction Stop
            Write-Detail "Purview policy exception removed." Green
        } catch {
            Write-Detail "WARNING: Could not remove Purview exception. Remove '$Mailbox' from '$RETENTION_POLICY_NAME' exceptions in Purview manually." Yellow
        }
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

Write-Host "`nDone. Purge complete for $Mailbox." -ForegroundColor Green
Write-Host "      The user can send and receive once Exchange reclaims the purged space (typically within 1-3 hours).`n" -ForegroundColor Gray
