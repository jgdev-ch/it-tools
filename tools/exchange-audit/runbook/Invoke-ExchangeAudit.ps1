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
# Thresholds $DEEP_SCAN_THRESHOLD_GB (=80), $STATUS_CRITICAL_PCT (=90), $STATUS_WARNING_PCT (=70)
# come from the Config block at the top of the file.

# ── Pass A: bulk flags + quota (fast; Get-Mailbox has quota but NOT used size) ──
Write-Output "Pass A: fetching all user mailboxes (flags + quota)..."
$allMailboxes = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Select-Object UserPrincipalName, DisplayName, ExchangeGuid,
                  RecoverableItemsQuota,
                  SingleItemRecoveryEnabled, ElcProcessingDisabled,
                  RetentionHoldEnabled, LitigationHoldEnabled,
                  DelayHoldApplied, InPlaceHolds
Write-Output "Pass A complete — $($allMailboxes.Count) mailboxes"

# ── Pass B: per-mailbox real Recoverable Items used size (the slow part) ──
Write-Output "Pass B: measuring Recoverable Items used size per mailbox..."
$offenders  = [System.Collections.Generic.List[hashtable]]::new()
$scanErrors = 0
$i = 0
foreach ($mbx in $allMailboxes) {
    $i++
    if ($i % 1000 -eq 0) { Write-Output "  ...$i / $($allMailboxes.Count)  (offenders so far: $($offenders.Count), errors: $scanErrors)" }

    $usedBytes = [long]0
    $ok = $false
    for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
        try {
            $stats = Get-EXOMailboxStatistics -Identity $mbx.ExchangeGuid.ToString() -Properties TotalDeletedItemSize -ErrorAction Stop
            $usedBytes = ConvertTo-Bytes $stats.TotalDeletedItemSize
            $ok = $true
        } catch {
            if ($attempt -eq 3) { $scanErrors++; Write-Warning "stats failed for $($mbx.UserPrincipalName): $_" }
            else { Start-Sleep -Milliseconds (500 * $attempt) }   # back off then retry
        }
    }
    Start-Sleep -Milliseconds 25   # pacing to stay under EXO throttling

    $quotaBytes = ConvertTo-Bytes $mbx.RecoverableItemsQuota
    $pct = if ($quotaBytes -gt 0) { [int][Math]::Round(($usedBytes / $quotaBytes) * 100) } else { 0 }

    $elcBlocked = [bool]$mbx.ElcProcessingDisabled
    $retHold    = [bool]$mbx.RetentionHoldEnabled
    $isOffender = ($usedBytes -ge ($DEEP_SCAN_THRESHOLD_GB * 1GB)) -or $elcBlocked -or $retHold
    if (-not $isOffender) { continue }

    $status = if     ($pct -ge $STATUS_CRITICAL_PCT) { 'critical' }
              elseif ($pct -ge $STATUS_WARNING_PCT)  { 'warning'  }
              else                                    { 'ok'       }

    $offenders.Add(@{
        upn                  = $mbx.UserPrincipalName
        displayName          = $mbx.DisplayName
        exchangeGuid         = $mbx.ExchangeGuid.ToString()
        recoverableUsedBytes = $usedBytes
        recoverableQuotaBytes= $quotaBytes
        recoverablePct       = $pct
        status               = $status
        sirEnabled           = [bool]$mbx.SingleItemRecoveryEnabled
        elcProcessingDisabled= $elcBlocked
        retentionHoldEnabled = $retHold
        litigationHold       = [bool]$mbx.LitigationHoldEnabled
        delayHoldApplied     = [bool]$mbx.DelayHoldApplied
        inPlaceHoldsCount    = if ($mbx.InPlaceHolds) { $mbx.InPlaceHolds.Count } else { 0 }
        hasDetailStats       = $false
    })
}
Write-Output "Pass B complete — scanned $($allMailboxes.Count), offenders $($offenders.Count), errors $scanErrors"

# ── Pass C: folder detail on offenders only ──
Write-Output "Pass C: folder breakdown on $($offenders.Count) offenders..."
foreach ($obj in $offenders) {
    try {
        $folders = Get-MailboxFolderStatistics -Identity $obj.exchangeGuid -FolderScope RecoverableItems |
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
        Write-Warning "Pass C failed for $($obj.upn): $_"
    }
}
Write-Output "Pass C complete"

# ── Build output JSON ──────────────────────────────────────────────────────
$runDuration = [int]((Get-Date) - $runStart).TotalSeconds

$output = @{
    lastScan           = (Get-Date).ToUniversalTime().ToString('o')
    runDurationSeconds = $runDuration
    totalScanned       = $allMailboxes.Count
    offenderCount      = $offenders.Count
    scanErrors         = $scanErrors
    mailboxes          = @($offenders)
} | ConvertTo-Json -Depth 5 -Compress

Write-Output "JSON built — $($output.Length) bytes, $($offenders.Count) offenders of $($allMailboxes.Count) scanned"

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
