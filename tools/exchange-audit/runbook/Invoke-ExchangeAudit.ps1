<#
.SYNOPSIS
    Exchange Online Recoverable Items audit runbook for IT Tools Hub.
    Runs weekly via Azure Automation managed identity.
    Outputs exchange-audit.json to Azure Blob Storage.

.NOTES
    Requires (same Automation account as the Mailbox Cleanup SIR Watchdog):
      - System-assigned managed identity with Exchange RBAC (Mail Recipients / View-Only Recipients
        is sufficient for read) + Exchange.ManageAsApp granted to the MI service principal
      - Storage Blob Data Contributor on the storage account for the MI
      - Az.Accounts, Az.Storage, and ExchangeOnlineManagement modules imported into the Automation account
    Connection mirrors Invoke-SIRWatchdog.ps1 exactly (access-token path — the -ManagedIdentity
    switch is unreliable on the PS 7.2 runtime this Automation account uses).
#>

# ── Constants ──────────────────────────────────────────────────────────────
$STORAGE_ACCOUNT         = "pcorpsambcleanupazuc01"
$CONTAINER_NAME          = "exchange-audit"
$BLOB_NAME               = "exchange-audit.json"
$ORGANIZATION            = "trusthcs0.onmicrosoft.com"
$DEEP_SCAN_THRESHOLD_GB  = 80    # Run Pass 2 only on mailboxes >= this value
$STATUS_CRITICAL_PCT     = 90    # Recoverable Items % threshold for "critical"
$STATUS_WARNING_PCT      = 70    # Recoverable Items % threshold for "warning"

# ── Helper: parse Exchange Online size strings to bytes ───────────────────
function ConvertTo-Bytes {
    param($Value)
    if ($null -eq $Value) { return [long]0 }
    if ($Value.GetType().Name -eq 'ByteQuantifiedSize') { return $Value.ToBytes() }
    if ($Value -is [string] -and $Value -match '\((\d[\d,]*)\s+bytes?\)') {
        return [long]($Matches[1] -replace ',', '')
    }
    try { return [long]$Value } catch { return [long]0 }
}

# ── Connect: Azure (managed identity) → Exchange Online (access token) ────
Import-Module ExchangeOnlineManagement -ErrorAction Stop

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-Output "Azure: connected via managed identity."
} catch {
    throw "Failed to connect to Azure. Ensure the system-assigned managed identity is enabled. $_"
}

try {
    $exoToken    = Get-AzAccessToken -ResourceUrl "https://outlook.office365.com" -ErrorAction Stop
    $tokenString = [string]$exoToken.Token
    Connect-ExchangeOnline -AccessToken $tokenString -Organization $ORGANIZATION -ShowBanner:$false -ErrorAction Stop
    Write-Output "Exchange Online: connected."
} catch {
    throw "Failed to connect to Exchange Online. Managed identity may be missing Exchange RBAC / Exchange.ManageAsApp. $_"
}

$runStart = Get-Date

# ── Pass 1: All mailboxes ─────────────────────────────────────────────────
Write-Output "Pass 1: fetching all user mailboxes..."
$allMailboxes = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Select-Object UserPrincipalName, DisplayName,
                  RecoverableItemsQuota, RecoverableItemsSize,
                  SingleItemRecoveryEnabled, ElcProcessingDisabled,
                  RetentionHoldEnabled, LitigationHoldEnabled,
                  DelayHoldApplied, InPlaceHolds

Write-Output "Pass 1 complete — $($allMailboxes.Count) mailboxes retrieved"

$mailboxObjects = [System.Collections.Generic.List[hashtable]]::new()

foreach ($mbx in $allMailboxes) {
    $usedBytes  = ConvertTo-Bytes $mbx.RecoverableItemsSize
    $quotaBytes = ConvertTo-Bytes $mbx.RecoverableItemsQuota

    $pct = if ($quotaBytes -gt 0) { [int][Math]::Round(($usedBytes / $quotaBytes) * 100) } else { 0 }

    $status = if     ($pct -ge $STATUS_CRITICAL_PCT) { 'critical' }
              elseif ($pct -ge $STATUS_WARNING_PCT)  { 'warning'  }
              else                                    { 'ok'       }

    $obj = @{
        upn                  = $mbx.UserPrincipalName
        displayName          = $mbx.DisplayName
        recoverableUsedBytes = $usedBytes
        recoverableQuotaBytes= $quotaBytes
        recoverablePct       = $pct
        status               = $status
        sirEnabled           = [bool]$mbx.SingleItemRecoveryEnabled
        elcProcessingDisabled= [bool]$mbx.ElcProcessingDisabled
        retentionHoldEnabled = [bool]$mbx.RetentionHoldEnabled
        litigationHold       = [bool]$mbx.LitigationHoldEnabled
        delayHoldApplied     = [bool]$mbx.DelayHoldApplied
        inPlaceHoldsCount    = if ($mbx.InPlaceHolds) { $mbx.InPlaceHolds.Count } else { 0 }
        hasDetailStats       = $false
    }

    $mailboxObjects.Add($obj)
}

# ── Pass 2: Deep scan for flagged mailboxes ────────────────────────────────
$flagged = $mailboxObjects | Where-Object { $_.recoverableUsedBytes -ge ($DEEP_SCAN_THRESHOLD_GB * 1GB) }
Write-Output "Pass 2: deep scan on $($flagged.Count) mailboxes >= ${DEEP_SCAN_THRESHOLD_GB} GB..."

foreach ($obj in $flagged) {
    try {
        $folders = Get-MailboxFolderStatistics -Identity $obj.upn -FolderScope RecoverableItems |
            Where-Object { $_.FolderPath -in @('/DiscoveryHolds', '/Purges', '/Versions', '/SubstrateHolds') }

        $dh = $folders | Where-Object { $_.FolderPath -eq '/DiscoveryHolds' }
        $pu = $folders | Where-Object { $_.FolderPath -eq '/Purges' }
        $ve = $folders | Where-Object { $_.FolderPath -eq '/Versions' }
        $su = $folders | Where-Object { $_.FolderPath -eq '/SubstrateHolds' }

        $obj.hasDetailStats = $true
        $obj.folders = @{
            discoveryHoldsBytes = if ($dh) { ConvertTo-Bytes $dh.FolderAndSubfolderSize } else { [long]0 }
            discoveryHoldsItems = if ($dh) { [int]$dh.ItemsInFolder } else { 0 }
            purgesBytes         = if ($pu) { ConvertTo-Bytes $pu.FolderAndSubfolderSize } else { [long]0 }
            purgesItems         = if ($pu) { [int]$pu.ItemsInFolder } else { 0 }
            versionsBytes       = if ($ve) { ConvertTo-Bytes $ve.FolderAndSubfolderSize } else { [long]0 }
            substrateHoldsBytes = if ($su) { ConvertTo-Bytes $su.FolderAndSubfolderSize } else { [long]0 }
        }
    } catch {
        Write-Warning "Pass 2 failed for $($obj.upn): $_"
    }
}

Write-Output "Pass 2 complete"

# ── Build output JSON ──────────────────────────────────────────────────────
$runDuration = [int]((Get-Date) - $runStart).TotalSeconds

$output = @{
    lastScan           = (Get-Date).ToUniversalTime().ToString('o')
    runDurationSeconds = $runDuration
    totalMailboxes     = $mailboxObjects.Count
    mailboxes          = @($mailboxObjects)
} | ConvertTo-Json -Depth 5 -Compress

Write-Output "JSON built — $($output.Length) bytes, $($mailboxObjects.Count) mailboxes"

# ── Upload to Azure Blob Storage ───────────────────────────────────────────
Write-Output "Uploading to Blob Storage: $STORAGE_ACCOUNT/$CONTAINER_NAME/$BLOB_NAME..."

try {
    $storageCtx = New-AzStorageContext -StorageAccountName $STORAGE_ACCOUNT -UseConnectedAccount

    $tempFile = [System.IO.Path]::GetTempFileName() + '.json'
    $output | Out-File $tempFile -Encoding UTF8 -NoNewline

    Set-AzStorageBlobContent -Container $CONTAINER_NAME `
        -Blob $BLOB_NAME `
        -File $tempFile `
        -Context $storageCtx `
        -Properties @{ ContentType = 'application/json' } `
        -Force | Out-Null

    Remove-Item $tempFile -Force
    Write-Output "Upload complete — exchange-audit.json updated in $CONTAINER_NAME"
} catch {
    throw "Blob upload failed: $_"
} finally {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Output "Exchange Audit runbook complete. Duration: ${runDuration}s"
