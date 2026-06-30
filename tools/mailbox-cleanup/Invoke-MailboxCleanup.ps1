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
$SCRIPT_VERSION                = "2.0"
$RETENTION_POLICY_NAME         = "3 Year Email Retention Policy"
$PROPAGATION_WAIT_SECONDS      = 120
$POLL_INTERVAL_SECONDS         = 30
$DISCOVERY_HOLDS_SIR_THRESHOLD = 1GB
$PRIMARY_FOLDER_SIZE_THRESHOLD = 1GB
$ASYNC_HOLD_CHECK_WAIT         = 90   # seconds — Exchange applies DelayHoldApplied asynchronously
$ARCHIVE_SIZE_ADVISORY_THRESHOLD = 10GB

# --- Blob tracking (SIR watchdog runbook) ---
# Generate a container-level SAS on pcorpsambcleanupazuc01:
#   Resource type: Object | Permissions: Read, Write, Delete, Create | Expiry: 2 years
# Paste the full token (starting with ?) below. Rotate with each distributed script version.
$BLOB_STORAGE_ACCOUNT = "pcorpsambcleanupazuc01"
$BLOB_CONTAINER       = "mailbox-cleanup-audit"
$BLOB_SAS_TOKEN       = "?sv=2026-02-06&ss=b&srt=o&sp=rwdlctfx&se=2028-06-10T19:48:48Z&st=2026-06-10T11:33:48Z&spr=https&sig=%2BewTmW443ISRw1XYUcaPiW0FIaA3FlIck6Ak35eSUDA%3D"

# --- State ---
$policy                  = $null
$searchName              = $null
$search                  = $null
$aborted                 = $false
$errorOccurred           = $false
$policyRestored          = $false
$delayHoldCleared        = $false
$delayReleaseHoldCleared = $false
$lateDelayHoldCleared    = $false
$mfaTriggered            = $false
$mfaRetriggered          = $false
$disableSIR              = $false
$sirWasDisabledByScript  = $false
$sirRestored             = $false
$mfaOnlyMode             = $false
$statusOnlyMode          = $false
$folderCleanupMode       = $false
$folderCleanupResults    = @()
$archiveCleanupMode      = $false
$archiveCleanupResults   = @()
$mfaWait                 = ""
$purviewExceptionActive  = $false
$reportTime              = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportTimestamp         = Get-Date -Format 'yyyyMMdd-HHmmss'

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

function Get-MfaWaitEstimate {
    param([bool]$SirDisabled, [long]$DiscHoldsBytes)
    if (-not $SirDisabled)              { return "typically within 1 hour" }
    if ($DiscHoldsBytes -gt 50GB)       { return "24-72 hours (very large DiscoveryHolds backlog — >50 GB)" }
    if ($DiscHoldsBytes -gt 20GB)       { return "12-24 hours (large DiscoveryHolds backlog)" }
    return "2-4 hours (large DiscoveryHolds backlog)"
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

function Get-BlobKey {
    param([string]$Upn)
    return ($Upn -replace '@', '_at_' -replace '\.', '-').ToLower()
}

function Set-TrackingBlob {
    param([string]$BlobPath, [hashtable]$Data)
    if (-not $BLOB_SAS_TOKEN) { return $false }
    $uri   = "https://$BLOB_STORAGE_ACCOUNT.blob.core.windows.net/$BLOB_CONTAINER/$BlobPath$BLOB_SAS_TOKEN"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Data | ConvertTo-Json -Depth 5 -Compress))
    try {
        Invoke-RestMethod -Method Put -Uri $uri -Body $bytes -ContentType 'application/json' `
            -Headers @{ 'x-ms-blob-type' = 'BlockBlob'; 'x-ms-version' = '2020-04-08' } `
            -ErrorAction Stop | Out-Null
        return $true
    } catch { return $false }
}

function Remove-TrackingBlob {
    param([string]$BlobPath)
    if (-not $BLOB_SAS_TOKEN) { return }
    $uri = "https://$BLOB_STORAGE_ACCOUNT.blob.core.windows.net/$BLOB_CONTAINER/$BlobPath$BLOB_SAS_TOKEN"
    try {
        Invoke-RestMethod -Method Delete -Uri $uri `
            -Headers @{ 'x-ms-version' = '2020-04-08' } -ErrorAction Stop | Out-Null
    } catch { }
}

function Get-TrackingBlob {
    param([string]$BlobPath)
    if (-not $BLOB_SAS_TOKEN) { return $null }
    $uri = "https://$BLOB_STORAGE_ACCOUNT.blob.core.windows.net/$BLOB_CONTAINER/$BlobPath$BLOB_SAS_TOKEN"
    try {
        return Invoke-RestMethod -Method Get -Uri $uri `
            -Headers @{ 'x-ms-version' = '2020-04-08' } -ErrorAction Stop
    } catch { return $null }
}

function ConvertTo-ComplianceFolderId {
    param([string]$FolderId)
    if ([string]::IsNullOrWhiteSpace($FolderId)) { return $null }
    try {
        $folderIdPart  = $FolderId.Split("-")[0]
        $encoding      = [System.Text.Encoding]::GetEncoding("us-ascii")
        $nibbler       = $encoding.GetBytes("0123456789ABCDEF")
        $folderIdBytes = [Convert]::FromBase64String($folderIdPart)
        if ($folderIdBytes.Length -lt 47) { return $null }
        $indexIdBytes  = New-Object byte[] 48
        $indexIdIdx    = 0
        $folderIdBytes | Select-Object -Skip 23 -First 24 | ForEach-Object {
            $indexIdBytes[$indexIdIdx++] = $nibbler[$_ -shr 4]
            $indexIdBytes[$indexIdIdx++] = $nibbler[$_ -band 0xf]
        }
        return $encoding.GetString($indexIdBytes)
    } catch {
        return $null
    }
}

function Write-TicketReport {
    $reportAlias = ($Mailbox -split '@')[0]
    $reportFile  = "$([System.Environment]::GetFolderPath('Desktop'))\MailboxCleanup-$reportAlias-$reportTimestamp.txt"

    $modeLabel = if     ($mfaOnlyMode)       { 'MFA Only' }
                 elseif ($folderCleanupMode)  { 'Folder Cleanup' }
                 elseif ($archiveCleanupMode) { 'Archive Cleanup' }
                 elseif ($statusOnlyMode)     { 'Status Only' }
                 else                          { 'Full Cleanup' }

    $sep  = "=" * 60
    $dash = "-" * 60
    $report = @(
        $sep
        " MAILBOX CLEANUP REPORT"
        $sep
        " Date   : $reportTime"
        " Target : $Mailbox"
        " Mode   : $modeLabel"
        ""
        $dash
        " PRE-FLIGHT"
        $dash
        (" Recoverable Items  : {0} / {1} ({2}% full)" -f (Format-Size $usedBytes), (Format-Size $limitBytes), $pct)
        (" SingleItemRecovery : {0}" -f $(if ($sirEnabledOriginal) { 'Enabled' } else { 'DISABLED' }))
        (" RetentionHold      : {0}" -f $(if ($retentionHoldEnabled) { 'ENABLED (MFA will not reclaim space while active)' } else { 'False' }))
        (" Holds active       : {0}" -f $holdDisplay)
    )
    if ($mbx.InPlaceHolds -and $mbx.InPlaceHolds.Count -gt 0) {
        $mbx.InPlaceHolds | ForEach-Object { $report += "     - $_" }
    }
    $report += " Folder breakdown   :"
    if ($folderBreakdown) {
        $rptColWidth = [Math]::Max(($folderBreakdown | ForEach-Object { $_.FolderPath.Length } | Measure-Object -Maximum).Maximum + 2, 30)
        $folderBreakdown | ForEach-Object {
            $report += ("   {0} {1,8} items   {2}" -f $_.FolderPath.PadRight($rptColWidth), $_.ItemsInFolder, $_.FolderAndSubfolderSize)
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
        (" Purview exception left in place  : {0}" -f $(if ($purviewExceptionActive)   { 'Yes — remove when cleanup confirmed' } else { 'No / N-A' }))
        (" Purview exception removed        : {0}" -f $(if ($policyRestored)           { 'Yes' } else { 'No' }))
        (" Delay hold cleared               : {0}" -f $(if ($delayHoldCleared)         { 'Yes' } else { 'No (not present)' }))
        (" Delay release hold cleared       : {0}" -f $(if ($delayReleaseHoldCleared)  { 'Yes' } else { 'No (not present)' }))
        (" Late delay hold cleared          : {0}" -f $(if ($lateDelayHoldCleared)     { 'Yes — Exchange applied async after policy exception removed' } else { 'No' }))
        (" SIR disabled this run            : {0}" -f $(if ($sirWasDisabledByScript)   { 'Yes — re-enable after quota recovers' } else { 'No' }))
        (" SIR re-enabled this run          : {0}" -f $(if ($sirRestored)              { 'Yes' } else { 'No' }))
        (" Managed Folder Assistant triggered: {0}" -f $(if ($mfaTriggered)            { 'Yes' } else { 'No' }))
        (" MFA re-triggered (late hold)     : {0}" -f $(if ($mfaRetriggered)           { 'Yes' } else { 'No' }))
        ""
        $dash
        " OUTCOME"
        $dash
    )
    if (-not $aborted -and -not $errorOccurred) {
        if ($statusOnlyMode) {
            $report += " Status check complete. No changes made."
        } elseif ($folderCleanupMode -or $archiveCleanupMode) {
            $report += " Cleanup complete. See folder/archive sections above for details."
        } else {
            $actionLabel = if ($mfaOnlyMode) { "MFA re-triggered." } else { "Purge complete. MFA triggered." }
            $waitStr     = if ($mfaWait)     { " Space reclaims within $mfaWait." } else { "" }
            $report += " $actionLabel$waitStr"
            if ($sirWasDisabledByScript) {
                $report += " Re-run script on $Mailbox to re-enable SingleItemRecovery once quota recovers."
            }
        }
    } elseif ($aborted) {
        $report += " Aborted by operator. No items were purged."
    } else {
        $report += " Completed with errors. Review console output for details."
    }
    if ($folderCleanupResults.Count -gt 0) {
        $report += @("", $dash, " FOLDER CLEANUP", $dash)
        foreach ($r in $folderCleanupResults) {
            if ($r.Status -eq 'Purged') {
                $report += (" {0,-30} : {1:N0} items purged  ({2}) — HardDelete" -f `
                    $r.FolderName, $r.Items, (Format-Size $r.SizeBytes))
            } else {
                $report += (" {0,-30} : Failed — check console output" -f $r.FolderName)
            }
        }
    }
    if ($archiveCleanupResults.Count -gt 0) {
        $report += @("", $dash, " ARCHIVE CLEANUP", $dash)
        foreach ($r in $archiveCleanupResults) {
            if ($r.Status -eq 'Purged') {
                $report += (" {0,-30} : {1:N0} items purged  ({2}) — HardDelete" -f `
                    $r.FolderName, $r.Items, (Format-Size $r.SizeBytes))
            } elseif ($r.Status -eq 'NoItems') {
                $report += (" {0,-30} : 0 items found — folder may be hold-protected or folderid conversion failed" -f $r.FolderName)
            } else {
                $report += (" {0,-30} : Failed — check console output" -f $r.FolderName)
            }
        }
    }
    $report += $sep

    $report | Out-File -FilePath $reportFile -Encoding UTF8
    Write-Host ""
    Write-Host "      Report saved to: $reportFile" -ForegroundColor Green
    Write-Host ""
}

# --- Main ---
Write-Host ""
Write-Host "  ================================================" -ForegroundColor DarkCyan
Write-Host "   Mailbox Cleanup Tool  v$SCRIPT_VERSION" -ForegroundColor White
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
Write-Host ""
Write-Host "  --- [Active Mailbox] ---" -ForegroundColor DarkCyan
$mbx = $null
try {
    $mbx = Get-Mailbox -Identity $Mailbox -ErrorAction Stop
} catch {
    Write-Host "ERROR: Mailbox '$Mailbox' not found. Check the UPN and try again." -ForegroundColor Red
    exit 1
}

$statsBefore          = Get-RecoverableStats -MailboxAddress $Mailbox
$usedBytes            = ConvertTo-Bytes $statsBefore.FolderAndSubfolderSize
$limitBytes           = ConvertTo-Bytes $mbx.RecoverableItemsQuota
$pct                  = if ($limitBytes -gt 0) { [int](($usedBytes / $limitBytes) * 100) } else { 0 }
$sirEnabled           = $mbx.SingleItemRecoveryEnabled
$sirEnabledOriginal   = $sirEnabled   # preserved — $sirEnabled may be updated by re-enable block below
$retentionHoldEnabled = $mbx.RetentionHoldEnabled

Write-Detail ("Recoverable Items  : {0} / {1} ({2}% full)" -f `
    (Format-Size $usedBytes), (Format-Size $limitBytes), $pct) `
    $(if ($pct -ge 90) { 'Red' } elseif ($pct -ge 70) { 'Yellow' } else { 'Green' })

Write-Detail ("SingleItemRecovery : {0}" -f $(if ($sirEnabled) { 'Enabled' } else { 'DISABLED' })) `
    $(if ($sirEnabled) { 'Green' } else { 'Yellow' })

Write-Detail ("RetentionHold      : {0}" -f $(if ($retentionHoldEnabled) { 'ENABLED' } else { 'False' })) `
    $(if ($retentionHoldEnabled) { 'Yellow' } else { 'Green' })
if ($retentionHoldEnabled) {
    Write-Detail "                     MFA will not reclaim freed space while this is active." Yellow
    Write-Detail "                     Clear with: Set-Mailbox '$Mailbox' -RetentionHoldEnabled `$false" Gray
}

$elcDisabled = $mbx.ElcProcessingDisabled
Write-Detail ("MFA Processing     : {0}" -f $(if ($elcDisabled) { 'BLOCKED — ElcProcessingDisabled is set on this mailbox' } else { 'Allowed' })) `
    $(if ($elcDisabled) { 'Red' } else { 'Green' })
if ($elcDisabled) {
    Write-Detail "                     Fix with: Set-Mailbox '$Mailbox' -ElcProcessingDisabled `$false" Gray
}

# Hold status
$holdFlags = @()
if ($mbx.LitigationHoldEnabled)                            { $holdFlags += "Litigation Hold" }
if ($mbx.DelayHoldApplied)                                 { $holdFlags += "Delay Hold (will be cleared)" }
if ($mbx.ComplianceTagHoldApplied)                         { $holdFlags += "Compliance Tag Hold" }
if ($mbx.InPlaceHolds -and $mbx.InPlaceHolds.Count -gt 0) { $holdFlags += "$($mbx.InPlaceHolds.Count) policy/eDiscovery hold(s)" }
$holdDisplay = if ($holdFlags.Count -gt 0) { $holdFlags -join ', ' } else { 'None' }
$holdColor   = if ($mbx.LitigationHoldEnabled) { 'Red' } `
               elseif ($mbx.DelayHoldApplied -or $mbx.ComplianceTagHoldApplied -or ($mbx.InPlaceHolds -and $mbx.InPlaceHolds.Count -gt 0)) { 'Yellow' } `
               else { 'Green' }
Write-Detail ("Holds active       : {0}" -f $holdDisplay) $holdColor

# InPlaceHolds enumeration — list GUIDs so tech can identify what policies are holding items
if ($mbx.InPlaceHolds -and $mbx.InPlaceHolds.Count -gt 0) {
    $mbx.InPlaceHolds | ForEach-Object { Write-Detail "                       - $_" Gray }
}

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

# Folder breakdown — only folders that contain items; track DiscoveryHolds size for SIR prompt
$folderBreakdown     = Get-MailboxFolderStatistics -Identity $Mailbox -FolderScope RecoverableItems |
    Where-Object { $_.ItemsInFolder -gt 0 }
$discoveryHoldsBytes = 0
if ($folderBreakdown) {
    Write-Detail "Folder breakdown   :" Gray
    $pathColWidth = [Math]::Max(($folderBreakdown | ForEach-Object { $_.FolderPath.Length } | Measure-Object -Maximum).Maximum + 2, 30)
    $folderBreakdown | ForEach-Object {
        $folderBytes = ConvertTo-Bytes $_.FolderAndSubfolderSize
        $folderPct   = if ($limitBytes -gt 0) { ($folderBytes / $limitBytes) * 100 } else { 0 }
        $folderColor = if     ($folderPct -ge 60) { 'Red' }
                       elseif ($folderPct -ge 20) { 'DarkYellow' }
                       elseif ($folderPct -ge 5)  { 'Yellow' }
                       else                        { 'Gray' }

        $note = ''
        if ($_.FolderType -eq 'RecoverableItemsPurges') {
            $note = '  <- queued for deletion, pending MFA'
        } elseif ($_.FolderPath -eq '/SubstrateHolds') {
            $note = '  (Teams/Skype hold area — handled by -AggMailboxCleanup)'
        } elseif ($_.FolderPath -eq '/Deletions' -and $folderPct -ge 20) {
            $note = '  <- large soft-delete backlog'
        }

        if ($_.FolderPath -eq '/DiscoveryHolds') { $discoveryHoldsBytes = $folderBytes }
        Write-Detail ("    {0} {1,8} items   {2}{3}" -f $_.FolderPath.PadRight($pathColWidth), $_.ItemsInFolder, (Format-Size $folderBytes), $note) $folderColor
    }
}

# MFA trigger history — read from local state file written each time this script triggers MFA
$mfaStateFile = "$env:LOCALAPPDATA\MailboxCleanupTool\mfa-state.json"
if (Test-Path $mfaStateFile) {
    try {
        $mfaState = Get-Content $mfaStateFile -Raw | ConvertFrom-Json -AsHashtable
        if ($mfaState.ContainsKey($Mailbox)) {
            $mfaEntry    = $mfaState[$Mailbox]
            $mfaTime     = Get-Date $mfaEntry.LastTriggered
            $mfaElapsed  = (Get-Date) - $mfaTime
            $mfaElapsedStr = if     ($mfaElapsed.TotalMinutes -lt 60)  { "{0}m ago"        -f [int]$mfaElapsed.TotalMinutes }
                             elseif ($mfaElapsed.TotalHours   -lt 24)  { "{0}h {1}m ago"   -f [int]$mfaElapsed.Hours, $mfaElapsed.Minutes }
                             else                                        { "{0}d {1}h ago"   -f [int]$mfaElapsed.TotalDays, $mfaElapsed.Hours }
            $mfaSIRStr   = if ($mfaEntry.SIRDisabledAtTrigger) { 'SIR=Disabled' } else { 'SIR=Enabled' }
            $mfaDHStr    = if ($mfaEntry.DiscoveryHoldsGB -gt 0) { ", DiscoveryHolds={0:N1} GB at trigger" -f $mfaEntry.DiscoveryHoldsGB } else { '' }
            Write-Detail ""
            Write-Detail ("MFA last triggered : {0}  ({1})" -f $mfaTime.ToString('yyyy-MM-dd HH:mm'), $mfaElapsedStr) Cyan
            Write-Detail ("                     $mfaSIRStr$mfaDHStr") Gray
        } else {
            Write-Detail ""
            Write-Detail "MFA last triggered : no history for this mailbox on this machine" Gray
        }
    } catch {
        # State file read is non-critical — silently skip on parse error
    }
} else {
    Write-Detail ""
    Write-Detail "MFA last triggered : no history on this machine" Gray
}

# Purview exception status — read from tracking blob set during last [C] run
$blobData = Get-TrackingBlob -BlobPath "in-progress/$(Get-BlobKey $Mailbox).json"
if ($blobData -and $blobData.purviewExceptionActive) {
    Write-Detail ""
    Write-Detail "Purview exception  : ACTIVE — mailbox is excluded from the 3-Year Retention Policy" Yellow
    Write-Detail "                     Remove when cleanup is confirmed (answer Y to Purview prompt after re-enabling SIR)" Gray
}

# --- In-Place Archive status ---
Write-Host ""
Write-Host "  --- [In-Place Archive] ---" -ForegroundColor DarkCyan
$archiveStats       = $null
$archiveFolderStats = $null
try {
    $archiveStats = Get-MailboxStatistics -Identity $Mailbox -Archive -ErrorAction Stop
} catch { }

if ($null -eq $archiveStats) {
    Write-Detail "No In-Place Archive provisioned." Gray
} else {
    $archiveItemCount  = $archiveStats.ItemCount

    try {
        $rawArchiveFolders = Get-MailboxFolderStatistics -Identity $Mailbox -Archive -ErrorAction Stop
        $archiveTotalBytes = ($rawArchiveFolders |
            Where-Object { $_.FolderType -eq 'Root' } |
            ForEach-Object { ConvertTo-Bytes $_.FolderAndSubfolderSize } |
            Select-Object -First 1)
        if (-not $archiveTotalBytes) { $archiveTotalBytes = 0 }
        Write-Detail ("Total size         : {0}  ({1:N0} items)" -f (Format-Size $archiveTotalBytes), $archiveItemCount) `
            $(if ($archiveTotalBytes -ge 50GB) { 'Red' } elseif ($archiveTotalBytes -ge 10GB) { 'Yellow' } else { 'Green' })

        $archiveFolderStats = $rawArchiveFolders |
            Where-Object { $_.FolderType -ne 'Root' -and $_.ItemsInFolderAndSubfolders -gt 0 } |
            Sort-Object { ConvertTo-Bytes $_.FolderAndSubfolderSize } -Descending

        if ($archiveFolderStats) {
            Write-Detail "Folder breakdown   :" Gray
            $archColWidth = [Math]::Max(($archiveFolderStats | ForEach-Object { $_.FolderPath.Length } | Measure-Object -Maximum).Maximum + 2, 30)
            $archiveFolderStats | ForEach-Object {
                $aBytes = ConvertTo-Bytes $_.FolderAndSubfolderSize
                $aPct   = if ($archiveTotalBytes -gt 0) { ($aBytes / $archiveTotalBytes) * 100 } else { 0 }
                $aColor = if     ($aPct -ge 60) { 'Red' }
                           elseif ($aPct -ge 20) { 'DarkYellow' }
                           elseif ($aPct -ge 5)  { 'Yellow' }
                           else                   { 'Gray' }
                Write-Detail ("    {0} {1,8} items   {2}" -f $_.FolderPath.PadRight($archColWidth), $_.ItemsInFolderAndSubfolders, (Format-Size $aBytes)) $aColor
            }
        }
    } catch {
        Write-Detail "Folder breakdown unavailable — $_" Yellow
    }

    if ($archiveTotalBytes -ge $ARCHIVE_SIZE_ADVISORY_THRESHOLD) {
        Write-Host ""
        Write-Detail "Archive is large — consider [A] Archive Cleanup from the main menu." Yellow
    }
}

# --- SIR already disabled: prompt to re-enable before mode selection ---
if (-not $sirEnabled) {
    Write-Host ""
    Write-Host "      ================================================" -ForegroundColor Yellow
    Write-Host "       SingleItemRecovery is currently DISABLED" -ForegroundColor Yellow
    Write-Host "       This was likely cleared during a previous cleanup run." -ForegroundColor White
    Write-Host "       Re-enable it once the mailbox quota has recovered." -ForegroundColor White
    Write-Host "       Also remove the Purview exception in the same session." -ForegroundColor White
    Write-Host "      ================================================" -ForegroundColor Yellow
    Write-Host ""
    $reEnable = Read-Host "      Re-enable SingleItemRecovery? [Y/N]"
    Write-Host ""
    if ($reEnable -match '^[Yy]') {
        try {
            Set-Mailbox -Identity $Mailbox -SingleItemRecoveryEnabled $true -ErrorAction Stop
            Write-Detail "SingleItemRecovery re-enabled." Green
            $sirRestored = $true
            $sirEnabled  = $true
        } catch {
            Write-Detail "WARNING: Could not re-enable SingleItemRecovery. Run manually: Set-Mailbox -Identity '$Mailbox' -SingleItemRecoveryEnabled `$true" Yellow
        }

        if ($sirRestored) {
            # Purview exception removal — offer to remove the exception left in place from the [C] run.
            # This reconnects S&C briefly; the exception must stay in place until quota confirms clear.
            Write-Host ""
            $removePurview = Read-Host "      Remove Purview policy exception? [Y/N]"
            Write-Host ""
            if ($removePurview -match '^[Yy]') {
                try {
                    Connect-IPPSSession -ErrorAction Stop -WarningAction SilentlyContinue 6>$null
                    Set-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME `
                        -RemoveExchangeLocationException $Mailbox -ErrorAction Stop
                    Write-Detail "Purview exception removed. Mailbox is back under the 3-Year Retention Policy." Green
                    $policyRestored = $true
                } catch {
                    Write-Detail "WARNING: Could not remove Purview exception. Remove '$Mailbox' from '$RETENTION_POLICY_NAME' exceptions in Purview manually." Yellow
                } finally {
                    try { Disconnect-IPPSSession -Confirm:$false -ErrorAction SilentlyContinue } catch {}
                }
            }

            $blobKey = Get-BlobKey $Mailbox
            Set-TrackingBlob -BlobPath "completed/$blobKey.json" -Data @{
                mailbox                 = $Mailbox
                completedAt             = (Get-Date -Format 'o')
                completedByTech         = $env:USERNAME
                scriptVersion           = $SCRIPT_VERSION
                status                  = 'completed'
                purviewExceptionRemoved = $policyRestored
            } | Out-Null
            Remove-TrackingBlob -BlobPath "in-progress/$blobKey.json"
        }
    }
}

# --- Outer loop — allows post-action [M] to return to mode selection ---
$continueScript = $true
while ($continueScript) {
    $continueScript = $false
    $reportTime      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $reportTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- Mode loop — allows [F]/[A] post-purge [M] to return here ---
$modeLoopActive = $true
while ($modeLoopActive) {
    $modeLoopActive     = $false
    $mfaOnlyMode        = $false
    $statusOnlyMode     = $false
    $folderCleanupMode  = $false
    $archiveCleanupMode = $false
    $quitRequested      = $false

    # --- Mode selection ---
    Write-Host ""
    Write-Host "      What would you like to do?" -ForegroundColor White
    Write-Host "        [C] Full cleanup     — compliance search, purge, and MFA" -ForegroundColor Gray
    Write-Host "        [M] MFA only         — re-check SIR, clear delay holds, and re-trigger MFA" -ForegroundColor Gray
    Write-Host "        [F] Folder cleanup   — permanently purge contents of a primary mailbox folder" -ForegroundColor Gray
    Write-Host "        [A] Archive cleanup  — permanently purge contents of an In-Place Archive folder" -ForegroundColor Gray
    Write-Host "        [S] Status only      — view status, no changes" -ForegroundColor Gray
    Write-Host "        [Q] Quit" -ForegroundColor Gray
    Write-Host ""
    $modeChoice = Read-Host "      Choice"
    Write-Host ""

    switch -Regex ($modeChoice) {
        '^[Ss]' { $statusOnlyMode     = $true }
        '^[Mm]' { $mfaOnlyMode        = $true }
        '^[Cc]' { }
        '^[Ff]' { $folderCleanupMode  = $true }
        '^[Aa]' { $archiveCleanupMode = $true }
        default {
            $exitMsg = if ($sirRestored) { "SingleItemRecovery re-enabled. Exited." } `
                       elseif ($folderCleanupResults.Count -gt 0) { "Session ended." } `
                       else { "Exited. No changes were made." }
            Write-Host "  $exitMsg`n" -ForegroundColor Cyan
            $quitRequested = $true
        }
    }
    if ($quitRequested) { continue }  # exits mode loop; falls through to post-action menu

# --- Status only: exit cleanly ---
if ($statusOnlyMode) {
    $exitMsg = if ($sirRestored) { "SingleItemRecovery re-enabled. Status check complete." } else { "Status check complete. No changes were made." }
    Write-Host "  $exitMsg`n" -ForegroundColor Cyan
}

# --- Folder cleanup mode ---
if ($folderCleanupMode) {
    Write-Host ""
    Write-Host "      ================================================" -ForegroundColor Red
    Write-Host "       PERMANENT DELETE — Folder Cleanup" -ForegroundColor Red
    Write-Host "       This action will hard-delete ALL items in the" -ForegroundColor White
    Write-Host "       selected folder. They cannot be recovered." -ForegroundColor White
    Write-Host ""
    Write-Host "       Confirm with the user that the folder contents" -ForegroundColor White
    Write-Host "       are safe to permanently delete before proceeding." -ForegroundColor White
    Write-Host "      ================================================" -ForegroundColor Red
    Write-Host ""
    $warnResponse = Read-Host "      Understood — proceed to folder selection? [Y/N]"
    Write-Host ""
    if ($warnResponse -notmatch '^[Yy]') {
        Write-Host "  Folder cleanup cancelled. No changes made.`n" -ForegroundColor Cyan
        continue
    }

    Write-Host ""
    Write-Detail "Connecting to Security & Compliance..." Cyan
    try {
        Connect-IPPSSession -EnableSearchOnlySession -ErrorAction Stop -WarningAction SilentlyContinue 6>$null
        Write-Detail "Security & Compliance: connected" Green
    } catch {
        Write-Detail "ERROR: Could not connect to Security & Compliance. $_" Red
        continue
    }

    $folderLoopActive = $true
    while ($folderLoopActive) {
        $folderLoopActive = $false

        # Fetch all primary folders once — Root folder gives total size; rest used for the display list
        $primaryLimitBytes = ConvertTo-Bytes $mbx.ProhibitSendReceiveQuota
        $allPrimaryFolders = Get-MailboxFolderStatistics -Identity $Mailbox
        $rootFolder        = $allPrimaryFolders | Where-Object { $_.FolderType -eq 'Root' } | Select-Object -First 1
        $primaryUsedBytes  = if ($rootFolder) { ConvertTo-Bytes $rootFolder.FolderAndSubfolderSize } else { [long]0 }
        $primaryPct        = if ($primaryLimitBytes -gt 0) { [int](($primaryUsedBytes / $primaryLimitBytes) * 100) } else { 0 }

        Write-Host ""
        Write-Detail ("Primary Mailbox    : {0} / {1} ({2}% full)" -f `
            (Format-Size $primaryUsedBytes), (Format-Size $primaryLimitBytes), $primaryPct) `
            $(if ($primaryPct -ge 90) { 'Red' } elseif ($primaryPct -ge 70) { 'Yellow' } else { 'Green' })
        Write-Host ""

        # Primary folder list — exclude Recoverable Items and root; filter > 1 GB; sort largest first
        $primaryFolders = $allPrimaryFolders |
            Where-Object {
                $_.FolderType -notlike 'RecoverableItems*' -and
                $_.FolderType -ne 'Root' -and
                (ConvertTo-Bytes $_.FolderAndSubfolderSize) -gt $PRIMARY_FOLDER_SIZE_THRESHOLD
            } |
            Sort-Object { ConvertTo-Bytes $_.FolderAndSubfolderSize } -Descending

        if (-not $primaryFolders -or $primaryFolders.Count -eq 0) {
            Write-Detail "No primary folders exceed 1 GB. Nothing to target." Yellow
            Write-Host ""
            continue
        }

        Write-Detail "Select a folder to purge (or [Q] to return to main menu):" White
        Write-Host ""
        $nameColWidth = [Math]::Max(($primaryFolders | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum + 2, 20)
        $idx = 1
        foreach ($f in $primaryFolders) {
            $fBytes = ConvertTo-Bytes $f.FolderAndSubfolderSize
            $fPct   = if ($primaryLimitBytes -gt 0) { ($fBytes / $primaryLimitBytes) * 100 } else { 0 }
            $fColor = if     ($fPct -ge 60) { 'Red' }
                      elseif ($fPct -ge 20) { 'DarkYellow' }
                      elseif ($fPct -ge 5)  { 'Yellow' }
                      else                   { 'Gray' }
            Write-Host ("      [{0}]  {1} {2,8} items   {3}" -f $idx, $f.Name.PadRight($nameColWidth), $f.ItemsInFolder, (Format-Size $fBytes)) -ForegroundColor $fColor
            $idx++
        }
        Write-Host ""

        # Folder selection with validation (Q returns to main menu)
        $selectedFolder = $null
        while ($null -eq $selectedFolder) {
            $folderChoice = Read-Host "      Choice"
            if ($folderChoice -match '^[Qq]') {
                Write-Host ""
                $modeLoopActive = $true
                break
            }
            $folderIndex = 0
            if ([int]::TryParse($folderChoice, [ref]$folderIndex) -and
                $folderIndex -ge 1 -and $folderIndex -le $primaryFolders.Count) {
                $selectedFolder = $primaryFolders[$folderIndex - 1]
            } else {
                Write-Detail "Invalid selection. Enter a number between 1 and $($primaryFolders.Count), or Q to return." Yellow
            }
        }
        if ($null -eq $selectedFolder) { continue }  # Q was entered — exit folder loop

        $selBytes = ConvertTo-Bytes $selectedFolder.FolderAndSubfolderSize
        Write-Host ""
        Write-Detail ("Selected: {0}  ({1:N0} items / {2})" -f `
            $selectedFolder.Name, $selectedFolder.ItemsInFolder, (Format-Size $selBytes)) White
        $purgeConfirm = Read-Host "      Proceed with HardDelete purge of all items in this folder? [Y/N]"
        Write-Host ""
        if ($purgeConfirm -notmatch '^[Yy]') {
            Write-Detail "Purge cancelled. Returning to folder list." Yellow
            $folderLoopActive = $true
            continue
        }

        # Compliance search + HardDelete purge
        $folderSearchName = $null
        $folderSearch     = $null
        $folderPurgeError = $false
        try {
            $folderAlias      = ($Mailbox -split '@')[0]
            $folderSafeName   = $selectedFolder.Name -replace '[^A-Za-z0-9]', ''
            $folderTimestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
            $folderSearchName = "FolderCleanup-$folderAlias-$folderSafeName-$folderTimestamp"
            $folderQuery      = "folderpath:`"$($selectedFolder.Name)`""

            Write-Detail "Compliance search: $folderSearchName" Gray

            New-ComplianceSearch -Name $folderSearchName `
                -ExchangeLocation $Mailbox `
                -ContentMatchQuery $folderQuery `
                -ErrorAction Stop | Out-Null

            Start-ComplianceSearch -Identity $folderSearchName -ErrorAction Stop

            $elapsed = 0
            do {
                Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
                $elapsed += $POLL_INTERVAL_SECONDS
                $folderSearch = Get-ComplianceSearch -Identity $folderSearchName
                Write-Detail "Searching... (${elapsed}s) - $($folderSearch.Status)"
            } while ($folderSearch.Status -notin @('Completed', 'Failed'))

            if ($folderSearch.Status -eq 'Failed') {
                throw "Compliance search '$folderSearchName' failed. Check the Security & Compliance portal."
            }

            Write-Detail ("Search complete — {0:N0} items found ({1})" -f `
                $folderSearch.Items, (Format-Size $folderSearch.Size)) Green

            Write-Detail "Running purge (HardDelete)..." Yellow

            New-ComplianceSearchAction -SearchName $folderSearchName `
                -Purge -PurgeType HardDelete -Confirm:$false -ErrorAction Stop | Out-Null

            $folderActionName = "$folderSearchName`_Purge"
            $elapsed = 0
            do {
                Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
                $elapsed += $POLL_INTERVAL_SECONDS
                $folderAction = Get-ComplianceSearchAction -Identity $folderActionName
                Write-Detail "Purging... (${elapsed}s) - $($folderAction.Status)"
            } while ($folderAction.Status -notin @('Completed', 'Failed'))

            if ($folderAction.Status -eq 'Failed') {
                throw "Compliance purge '$folderActionName' failed. Check the Security & Compliance portal."
            }

            Write-Detail "Purge complete." Green

            Write-Host ""
            Write-Host "      ================================================" -ForegroundColor DarkCyan
            Write-Host "       Results" -ForegroundColor White
            Write-Detail ("  Folder : {0}" -f $selectedFolder.Name) White
            Write-Detail ("  Purged : {0:N0} items  ({1})" -f $folderSearch.Items, (Format-Size $folderSearch.Size)) Green
            Write-Host "      ================================================" -ForegroundColor DarkCyan
            Write-Host ""

            $folderCleanupResults += [PSCustomObject]@{
                FolderName = $selectedFolder.Name
                Items      = $folderSearch.Items
                SizeBytes  = $folderSearch.Size
                Status     = 'Purged'
            }

        } catch {
            Write-Host "`n      ERROR: $_" -ForegroundColor Red
            $folderPurgeError = $true
            $folderCleanupResults += [PSCustomObject]@{
                FolderName = if ($selectedFolder) { $selectedFolder.Name } else { 'Unknown' }
                Items      = 0
                SizeBytes  = 0
                Status     = 'Failed'
            }
        } finally {
            if ($folderSearchName) {
                try {
                    Remove-ComplianceSearch -Identity $folderSearchName -Confirm:$false -ErrorAction Stop
                    Write-Detail "Compliance search deleted." Green
                } catch {
                    Write-Detail "WARNING: Could not delete compliance search '$folderSearchName'. Delete it from the Security & Compliance portal." Yellow
                }
            }
        }

        Write-Host ""
        Write-Host "      What would you like to do next?" -ForegroundColor White
        Write-Host "        [A] Target another folder" -ForegroundColor Gray
        Write-Host "        [M] Back to main menu" -ForegroundColor Gray
        Write-Host "        [Q] Quit" -ForegroundColor Gray
        Write-Host ""
        $loopChoice = Read-Host "      Choice"
        Write-Host ""

        switch -Regex ($loopChoice) {
            '^[Aa]' { $folderLoopActive = $true }
            '^[Mm]' { $modeLoopActive   = $true }
            default { }
        }

    } # end folder loop

    continue
} # end folderCleanupMode

# --- Archive cleanup mode ---
if ($archiveCleanupMode) {

    # Hard block: litigation hold covers entire mailbox including archive
    if ($mbx.LitigationHoldEnabled) {
        Write-Host ""
        Write-Host "      ================================================" -ForegroundColor Red
        Write-Host "       BLOCKED — Litigation Hold Detected" -ForegroundColor Red
        Write-Host "       This mailbox is under an active litigation hold." -ForegroundColor White
        Write-Host "       Purging archive items may violate legal" -ForegroundColor White
        Write-Host "       preservation requirements." -ForegroundColor White
        Write-Host "       Contact your compliance team before proceeding." -ForegroundColor White
        Write-Host "      ================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Archive cleanup blocked. Returning to main menu.`n" -ForegroundColor Yellow
        $modeLoopActive = $true
        continue
    }

    # Advisory: active holds may protect some items — not a hard block
    if ($mbx.InPlaceHolds -and $mbx.InPlaceHolds.Count -gt 0) {
        Write-Host ""
        Write-Host "      ================================================" -ForegroundColor Yellow
        Write-Host "       WARNING — Active Retention Holds Detected" -ForegroundColor Yellow
        Write-Host "       Items under active holds may be protected." -ForegroundColor White
        Write-Host "       Compliance search results may be partial." -ForegroundColor White
        Write-Host "       Confirm folder contents before proceeding." -ForegroundColor White
        Write-Host "      ================================================" -ForegroundColor Yellow
        Write-Host ""
    }

    # Verify archive exists (fetched in Phase 2)
    if ($null -eq $archiveStats) {
        Write-Host ""
        Write-Detail "No In-Place Archive provisioned for $Mailbox. Nothing to clean." Yellow
        $modeLoopActive = $true
        continue
    }

    # PERMANENT DELETE warning gate — identical to [F] mode
    Write-Host ""
    Write-Host "      ================================================" -ForegroundColor Red
    Write-Host "       PERMANENT DELETE — Archive Folder Cleanup" -ForegroundColor Red
    Write-Host "       This action will hard-delete ALL items in the" -ForegroundColor White
    Write-Host "       selected archive folder. They cannot be recovered." -ForegroundColor White
    Write-Host ""
    Write-Host "       Only the selected archive folder is targeted." -ForegroundColor White
    Write-Host "       Primary mailbox folders are never touched." -ForegroundColor White
    Write-Host "      ================================================" -ForegroundColor Red
    Write-Host ""
    $archWarnResponse = Read-Host "      Understood — proceed to archive folder selection? [Y/N]"
    Write-Host ""
    if ($archWarnResponse -notmatch '^[Yy]') {
        Write-Host "  Archive cleanup cancelled. No changes made.`n" -ForegroundColor Cyan
        $modeLoopActive = $true
        continue
    }

    Write-Detail "Connecting to Security & Compliance..." Cyan
    try {
        Connect-IPPSSession -EnableSearchOnlySession -ErrorAction Stop -WarningAction SilentlyContinue 6>$null
        Write-Detail "Security & Compliance: connected" Green
    } catch {
        Write-Detail "ERROR: Could not connect to Security & Compliance. $_" Red
        $modeLoopActive = $true
        continue
    }

    $archiveLoopActive = $true
    while ($archiveLoopActive) {
        $archiveLoopActive = $false

        # Refresh archive folder stats each loop so sizes reflect previous purge
        $allArchiveFolders = Get-MailboxFolderStatistics -Identity $Mailbox -Archive
        $archiveTotalBytes = ($allArchiveFolders |
            Where-Object { $_.FolderType -eq 'Root' } |
            ForEach-Object { ConvertTo-Bytes $_.FolderAndSubfolderSize } |
            Select-Object -First 1)
        if (-not $archiveTotalBytes) { $archiveTotalBytes = 0 }
        $archiveItemCount = ($allArchiveFolders | Measure-Object -Property ItemsInFolderAndSubfolders -Sum).Sum
        if (-not $archiveItemCount) { $archiveItemCount = 0 }

        Write-Host ""
        Write-Detail ("In-Place Archive   : {0}  ({1:N0} items)" -f (Format-Size $archiveTotalBytes), $archiveItemCount) `
            $(if ($archiveTotalBytes -ge 50GB) { 'Red' } elseif ($archiveTotalBytes -ge 10GB) { 'Yellow' } else { 'Green' })
        Write-Host ""

        # Archive folder list — exclude root and RecoverableItems; filter > 1 GB; sort largest first
        $archiveFolders = $allArchiveFolders |
            Where-Object {
                $_.FolderType -ne 'Root' -and
                $_.FolderType -notlike 'RecoverableItems*' -and
                $_.FolderPath -notlike '/Recoverable Items*' -and
                $_.FolderPath -notlike '/DiscoveryHolds*' -and
                $_.FolderPath -notlike '/Deletions*' -and
                $_.FolderPath -notlike '/Purges*' -and
                $_.FolderPath -notlike '/Versions*' -and
                $_.FolderPath -notlike '/SubstrateHolds*' -and
                (ConvertTo-Bytes $_.FolderAndSubfolderSize) -gt $PRIMARY_FOLDER_SIZE_THRESHOLD
            } |
            Sort-Object { ConvertTo-Bytes $_.FolderAndSubfolderSize } -Descending

        if (-not $archiveFolders -or $archiveFolders.Count -eq 0) {
            Write-Detail "No archive folders exceed 1 GB. Nothing to target." Yellow
            Write-Host ""
            $modeLoopActive = $true
            continue
        }

        Write-Detail "Select an archive folder to purge (or [Q] to return to main menu):" White
        Write-Host ""
        $archNameColWidth = [Math]::Max(($archiveFolders | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum + 2, 20)
        $idx = 1
        foreach ($f in $archiveFolders) {
            $fBytes = ConvertTo-Bytes $f.FolderAndSubfolderSize
            $fPct   = if ($archiveTotalBytes -gt 0) { ($fBytes / $archiveTotalBytes) * 100 } else { 0 }
            $fColor = if     ($fPct -ge 60) { 'Red' }
                      elseif ($fPct -ge 20) { 'DarkYellow' }
                      elseif ($fPct -ge 5)  { 'Yellow' }
                      else                   { 'Gray' }
            Write-Host ("      [{0}]  {1} {2,8} items   {3}" -f $idx, $f.Name.PadRight($archNameColWidth), $f.ItemsInFolderAndSubfolders, (Format-Size $fBytes)) -ForegroundColor $fColor
            $idx++
        }
        Write-Host ""

        $selectedArchiveFolder = $null
        while ($null -eq $selectedArchiveFolder) {
            $archiveChoice = Read-Host "      Choice"
            if ($archiveChoice -match '^[Qq]') {
                Write-Host ""
                $modeLoopActive = $true
                break
            }
            $archiveIndex = 0
            if ([int]::TryParse($archiveChoice, [ref]$archiveIndex) -and
                $archiveIndex -ge 1 -and $archiveIndex -le $archiveFolders.Count) {
                $selectedArchiveFolder = $archiveFolders[$archiveIndex - 1]
            } else {
                Write-Detail "Invalid selection. Enter a number between 1 and $($archiveFolders.Count), or Q to return." Yellow
            }
        }
        if ($null -eq $selectedArchiveFolder) { continue }

        $selArchiveBytes = ConvertTo-Bytes $selectedArchiveFolder.FolderAndSubfolderSize
        Write-Host ""
        Write-Detail ("Selected: {0}  ({1:N0} items / {2})" -f `
            $selectedArchiveFolder.Name, $selectedArchiveFolder.ItemsInFolderAndSubfolders, (Format-Size $selArchiveBytes)) White
        $archivePurgeConfirm = Read-Host "      Proceed with HardDelete purge of all items in this archive folder? [Y/N]"
        Write-Host ""
        if ($archivePurgeConfirm -notmatch '^[Yy]') {
            Write-Detail "Purge cancelled. Returning to archive folder list." Yellow
            $archiveLoopActive = $true
            continue
        }

        # folderid: compliance search — archive-only, never touches primary mailbox
        $archiveSearchName = $null
        $archiveSearch     = $null
        try {
            $archiveAlias      = ($Mailbox -split '@')[0]
            $archiveSafeName   = $selectedArchiveFolder.Name -replace '[^A-Za-z0-9]', ''
            $archiveTimestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
            $archiveSearchName = "ArchiveCleanup-$archiveAlias-$archiveSafeName-$archiveTimestamp"

            $convertedFolderId = ConvertTo-ComplianceFolderId -FolderId $selectedArchiveFolder.FolderId
            if ($null -eq $convertedFolderId) {
                throw "Could not convert archive folder ID for '$($selectedArchiveFolder.Name)' to compliance search format. Archive cleanup aborted — primary mailbox is unaffected."
            }

            Write-Detail "Archive folder ID  : verified — targeting archive folder exclusively" Green
            Write-Detail "Compliance search  : $archiveSearchName" Gray

            New-ComplianceSearch -Name $archiveSearchName `
                -ExchangeLocation $Mailbox `
                -ContentMatchQuery "folderid:$convertedFolderId" `
                -ErrorAction Stop | Out-Null

            Start-ComplianceSearch -Identity $archiveSearchName -ErrorAction Stop

            $elapsed = 0
            do {
                Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
                $elapsed += $POLL_INTERVAL_SECONDS
                $archiveSearch = Get-ComplianceSearch -Identity $archiveSearchName
                Write-Detail "Searching... (${elapsed}s) - $($archiveSearch.Status)" Gray
            } while ($archiveSearch.Status -notin @('Completed', 'Failed'))

            if ($archiveSearch.Status -eq 'Failed') {
                throw "Compliance search '$archiveSearchName' failed. Check the Security & Compliance portal."
            }

            Write-Detail ("Search complete — {0:N0} items found ({1})" -f `
                $archiveSearch.Items, (Format-Size $archiveSearch.Size)) Green

            if ($archiveSearch.Items -eq 0) {
                Write-Host ""
                Write-Detail "0 items found. The folder may be protected by an active hold," Yellow
                Write-Detail "or the folderid conversion may not match this module version." Yellow
                Write-Detail "No purge action will run — primary mailbox is unaffected." Gray
                $archiveCleanupResults += [PSCustomObject]@{
                    FolderName = $selectedArchiveFolder.Name
                    Items      = 0
                    SizeBytes  = 0
                    Status     = 'NoItems'
                }
            } else {
                Write-Detail "Running purge (HardDelete)..." Yellow

                New-ComplianceSearchAction -SearchName $archiveSearchName `
                    -Purge -PurgeType HardDelete -Confirm:$false -ErrorAction Stop | Out-Null

                $archiveActionName = "${archiveSearchName}_Purge"
                $elapsed = 0
                do {
                    Start-Sleep -Seconds $POLL_INTERVAL_SECONDS
                    $elapsed += $POLL_INTERVAL_SECONDS
                    $archiveAction = Get-ComplianceSearchAction -Identity $archiveActionName
                    Write-Detail "Purging... (${elapsed}s) - $($archiveAction.Status)" Gray
                } while ($archiveAction.Status -notin @('Completed', 'Failed'))

                if ($archiveAction.Status -eq 'Failed') {
                    throw "Compliance purge '$archiveActionName' failed. Check the Security & Compliance portal."
                }

                Write-Detail "Purge complete." Green

                Write-Host ""
                Write-Host "      ================================================" -ForegroundColor DarkCyan
                Write-Host "       Results" -ForegroundColor White
                Write-Detail ("  Folder : {0} (Archive)" -f $selectedArchiveFolder.Name) White
                Write-Detail ("  Purged : {0:N0} items  ({1})" -f $archiveSearch.Items, (Format-Size $archiveSearch.Size)) Green
                Write-Host "      ================================================" -ForegroundColor DarkCyan
                Write-Host ""

                $archiveCleanupResults += [PSCustomObject]@{
                    FolderName = $selectedArchiveFolder.Name
                    Items      = $archiveSearch.Items
                    SizeBytes  = $archiveSearch.Size
                    Status     = 'Purged'
                }
            }

        } catch {
            Write-Host "`n      ERROR: $_" -ForegroundColor Red
            $archiveCleanupResults += [PSCustomObject]@{
                FolderName = if ($selectedArchiveFolder) { $selectedArchiveFolder.Name } else { 'Unknown' }
                Items      = 0
                SizeBytes  = 0
                Status     = 'Failed'
            }
        } finally {
            if ($archiveSearchName) {
                try {
                    Remove-ComplianceSearch -Identity $archiveSearchName -Confirm:$false -ErrorAction Stop
                    Write-Detail "Compliance search deleted." Green
                } catch {
                    Write-Detail "WARNING: Could not delete compliance search '$archiveSearchName'. Delete it from the Security & Compliance portal." Yellow
                }
            }
        }

        Write-Host ""
        Write-Host "      What would you like to do next?" -ForegroundColor White
        Write-Host "        [A] Target another archive folder" -ForegroundColor Gray
        Write-Host "        [M] Back to main menu" -ForegroundColor Gray
        Write-Host "        [Q] Quit" -ForegroundColor Gray
        Write-Host ""
        $archiveLoopChoice = Read-Host "      Choice"
        Write-Host ""

        switch -Regex ($archiveLoopChoice) {
            '^[Aa]' { $archiveLoopActive = $true }
            '^[Mm]' { $modeLoopActive    = $true }
            default { }
        }

    } # end archive loop

    continue
} # end archiveCleanupMode

# --- MFA only: confirm intent, then fall through to Phase 6 via empty try ---
if ($mfaOnlyMode) {
    Write-Detail "MFA-only mode: will clear delay holds and re-trigger Managed Folder Assistant." Yellow
    Write-Detail "No compliance search or purge will run." Gray

    # SIR re-enable check — Exchange compliance engine can flip SIR back on after a cleanup run.
    # Offer to re-disable so MFA can continue reclaiming space unblocked.
    if ($sirEnabled -and $usedBytes -gt $DISCOVERY_HOLDS_SIR_THRESHOLD) {
        Write-Host ""
        Write-Detail ("SingleItemRecovery is Enabled and Recoverable Items is {0}." -f (Format-Size $usedBytes)) Yellow
        Write-Detail "Exchange may have re-enabled SIR since the last cleanup run." Gray
        Write-Detail "Disabling it allows MFA to more aggressively reclaim space." Gray
        $disableSIRChoice = Read-Host "      Disable SingleItemRecovery before triggering MFA? [Y/N]"
        Write-Host ""
        if ($disableSIRChoice -match '^[Yy]') {
            $disableSIR = $true
            Write-Detail "SingleItemRecovery will be disabled before MFA is triggered." Yellow
        }
    }
}

# --- Full cleanup only: SIR disable offer + final confirmation ---
if (-not $mfaOnlyMode) {
    if ($sirEnabled -and $usedBytes -gt $DISCOVERY_HOLDS_SIR_THRESHOLD) {
        Write-Host ""
        Write-Detail ("Recoverable Items is {0}. Disabling SingleItemRecovery temporarily" -f (Format-Size $usedBytes)) Gray
        Write-Detail "allows MFA to more aggressively reclaim space after cleanup." Gray
        $disableSIRChoice = Read-Host "      Disable SingleItemRecovery for this cleanup? [Y/N]"
        Write-Host ""
        if ($disableSIRChoice -match '^[Yy]') {
            $disableSIR = $true
            Write-Detail "SingleItemRecovery will be disabled before MFA is triggered." Yellow
        }
    }

    Write-Host ""
    $go = Read-Host "      Proceed with cleanup? [Y/N]"
    Write-Host ""
    if ($go -notmatch '^[Yy]') {
        Write-Host "  Cleanup cancelled. No changes were made.`n" -ForegroundColor Cyan
        $modeLoopActive = $false
        continue
    }
}

# --- Phases 3-5 (full cleanup path) or empty try (MFA-only — falls straight to finally) ---
try {
    if (-not $mfaOnlyMode) {
        # --- Phase 3: Connect to Security & Compliance ---
        Write-Step 3 "Connecting to Security & Compliance..."
        try {
            Connect-IPPSSession -EnableSearchOnlySession -ErrorAction Stop -WarningAction SilentlyContinue 6>$null
            Write-Detail "Security & Compliance: connected" Green
        } catch {
            throw "Could not connect to Security & Compliance (IPPSSession). $_"
        }

        # --- Phase 4: Purview policy exclusion ---
        Write-Step 4 "Adding Purview policy exclusion..."
        try {
            $policy = Get-RetentionCompliancePolicy -Identity $RETENTION_POLICY_NAME -ErrorAction Stop
        } catch {
            throw "Retention policy '$RETENTION_POLICY_NAME' not found. Update `$RETENTION_POLICY_NAME in the script constants."
        }

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

        if ($search.Items -eq 0 -and $usedBytes -gt 5GB) {
            Write-Host ""
            Write-Detail "NOTE: 0 items found, but Recoverable Items is $(Format-Size $usedBytes)." Yellow
            Write-Detail "Items in DiscoveryHolds may have been released by a previous cleanup run but" Gray
            Write-Detail "not yet reclaimed by Exchange. MFA (triggered at end) is the cleanup path." Gray
            Write-Detail "Use [M] MFA only on re-runs while waiting for space reclamation." Gray
        }

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
    }

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
        $purviewExceptionActive = $true
        Write-Detail "Purview exception left in place — retention policy will not re-populate DiscoveryHolds while MFA reclaims space." Yellow
        Write-Detail "Re-run this script once quota recovers to re-enable SIR and remove the exception." Gray
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

    if ($disableSIR) {
        try {
            Set-Mailbox -Identity $Mailbox -SingleItemRecoveryEnabled $false -ErrorAction Stop
            Write-Detail "SingleItemRecovery disabled (MFA can now fully reclaim DiscoveryHolds)." Yellow
            $sirWasDisabledByScript = $true
            $blobWritten = Set-TrackingBlob -BlobPath "in-progress/$(Get-BlobKey $Mailbox).json" -Data @{
                mailbox                 = $Mailbox
                sirDisabledAt           = (Get-Date -Format 'o')
                scriptVersion           = $SCRIPT_VERSION
                techAccount             = $env:USERNAME
                discoveryHoldsGbAtStart = [Math]::Round($discoveryHoldsBytes / 1GB, 1)
                lastMfaTriggered        = (Get-Date -Format 'o')
                status                  = 'in-progress'
                runbookRecheckCount     = 0
                purviewExceptionActive  = $true
            }
            if ($blobWritten) {
                Write-Detail "Runbook monitoring enabled — SIR watchdog will keep gates open." Gray
            } else {
                Write-Detail "NOTE: Blob tracking unavailable — set `$BLOB_SAS_TOKEN to enable runbook monitoring." Yellow
            }
        } catch {
            Write-Detail "WARNING: Could not disable SingleItemRecovery. Run manually: Set-Mailbox -Identity '$Mailbox' -SingleItemRecoveryEnabled `$false" Yellow
        }
    }

    try {
        Start-ManagedFolderAssistant -Identity $Mailbox -FullCrawl -AggMailboxCleanup -ErrorAction Stop
        Write-Detail "Managed Folder Assistant triggered." Green
        $mfaTriggered = $true
        try {
            $mfaStateDir = "$env:LOCALAPPDATA\MailboxCleanupTool"
            if (-not (Test-Path $mfaStateDir)) { New-Item -ItemType Directory -Path $mfaStateDir -Force | Out-Null }
            $mfaStateFile = "$mfaStateDir\mfa-state.json"
            $mfaState = if (Test-Path $mfaStateFile) { Get-Content $mfaStateFile -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
            $mfaState[$Mailbox] = @{
                LastTriggered        = (Get-Date -Format 'o')
                SIRDisabledAtTrigger = $sirWasDisabledByScript -or (-not $sirEnabledOriginal -and -not $sirRestored)
                DiscoveryHoldsGB     = [Math]::Round($discoveryHoldsBytes / 1GB, 1)
            }
            $mfaState | ConvertTo-Json | Set-Content $mfaStateFile -Encoding UTF8
        } catch { }
    } catch {
        Write-Detail "WARNING: Could not trigger Managed Folder Assistant. Quota reclamation may take longer." Yellow
    }

    # Async delay hold re-check — Exchange applies DelayHoldApplied asynchronously after a hold
    # change (e.g., removing the policy exception). The initial check above can miss it.
    # Wait, re-check, clear any late-applied hold, and re-trigger MFA so it runs clean.
    # Only relevant on full cleanup path — MFA-only makes no policy changes.
    if ($mfaTriggered -and -not $mfaOnlyMode) {
        Write-Detail "Waiting ${ASYNC_HOLD_CHECK_WAIT}s for async delay hold check..." Gray
        Start-Sleep -Seconds $ASYNC_HOLD_CHECK_WAIT
        $asyncMbx      = Get-Mailbox -Identity $Mailbox -ErrorAction SilentlyContinue
        $lateHoldFound = $false
        if ($asyncMbx -and $asyncMbx.DelayHoldApplied) {
            try {
                Set-Mailbox -Identity $Mailbox -RemoveDelayHoldApplied -ErrorAction Stop
                Write-Detail "Late-applied delay hold cleared (Exchange applied this after policy exception was removed)." Yellow
                $lateDelayHoldCleared = $true
                $lateHoldFound        = $true
            } catch {
                Write-Detail "WARNING: Could not clear late delay hold. Run manually: Set-Mailbox -Identity '$Mailbox' -RemoveDelayHoldApplied" Yellow
            }
        }
        if ($asyncMbx -and $asyncMbx.DelayReleaseHoldApplied) {
            try {
                Set-Mailbox -Identity $Mailbox -RemoveDelayReleaseHoldApplied -ErrorAction Stop
                Write-Detail "Late-applied delay release hold cleared." Yellow
                $lateHoldFound = $true
            } catch {
                Write-Detail "WARNING: Could not clear late delay release hold. Run manually: Set-Mailbox -Identity '$Mailbox' -RemoveDelayReleaseHoldApplied" Yellow
            }
        }
        if ($lateHoldFound) {
            try {
                Start-ManagedFolderAssistant -Identity $Mailbox -FullCrawl -AggMailboxCleanup -ErrorAction Stop
                Write-Detail "Managed Folder Assistant re-triggered (late hold cleared — MFA now runs clean)." Green
                $mfaRetriggered = $true
                try {
                    $mfaStateFile = "$env:LOCALAPPDATA\MailboxCleanupTool\mfa-state.json"
                    $mfaState = if (Test-Path $mfaStateFile) { Get-Content $mfaStateFile -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
                    $mfaState[$Mailbox] = @{
                        LastTriggered        = (Get-Date -Format 'o')
                        SIRDisabledAtTrigger = $sirWasDisabledByScript -or (-not $sirEnabledOriginal -and -not $sirRestored)
                        DiscoveryHoldsGB     = [Math]::Round($discoveryHoldsBytes / 1GB, 1)
                    }
                    $mfaState | ConvertTo-Json | Set-Content $mfaStateFile -Encoding UTF8
                } catch { }
            } catch {
                Write-Detail "WARNING: Could not re-trigger Managed Folder Assistant." Yellow
            }
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

# SIR is effectively disabled for MFA if this run disabled it, or it was already disabled and not re-enabled
$sirDisabledForMfa = $sirWasDisabledByScript -or (-not $sirEnabledOriginal -and -not $sirRestored)
$mfaWait           = Get-MfaWaitEstimate -SirDisabled $sirDisabledForMfa -DiscHoldsBytes $discoveryHoldsBytes

if (-not $aborted -and -not $errorOccurred) {
    $actionLabel = if ($mfaOnlyMode) { "MFA re-triggered" } else { "Purge complete" }
    Write-Host "`nDone. $actionLabel for $Mailbox." -ForegroundColor Green
    Write-Host "      Managed Folder Assistant has been triggered. The user can send and receive once Exchange reclaims the purged space ($mfaWait).`n" -ForegroundColor Gray
} elseif ($aborted) {
    Write-Host "`nAborted. No items were purged. Policy exception and compliance search have been cleaned up.`n" -ForegroundColor Yellow
}

if ($sirWasDisabledByScript) {
    Write-Host "      ================================================" -ForegroundColor Yellow
    Write-Host "       SingleItemRecovery is now DISABLED" -ForegroundColor Yellow
    Write-Host "       Purview exception left in place." -ForegroundColor White
    Write-Host "       MFA triggered. Allow $mfaWait." -ForegroundColor White
    Write-Host "       Re-run this script on $Mailbox once quota" -ForegroundColor White
    Write-Host "       recovers to re-enable SIR and remove the" -ForegroundColor White
    Write-Host "       Purview exception." -ForegroundColor White
    Write-Host "      ================================================`n" -ForegroundColor Yellow
}

} # end mode loop

# --- Post-action menu ---
Write-Host ""
Write-Host "      What would you like to do next?" -ForegroundColor White
Write-Host "        [R] Export report and quit" -ForegroundColor Gray
Write-Host "        [M] Back to main menu" -ForegroundColor Gray
Write-Host "        [Q] Quit without exporting" -ForegroundColor Gray
Write-Host ""
$postChoice = Read-Host "      Choice"
Write-Host ""

switch -Regex ($postChoice) {
    '^[Rr]' {
        Write-TicketReport
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
    }
    '^[Mm]' {
        $continueScript = $true
    }
    default {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
    }
}

} # end outer continueScript loop

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
