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
$SCRIPT_VERSION                = "1.4"
$RETENTION_POLICY_NAME         = "3 Year Email Retention Policy"
$PROPAGATION_WAIT_SECONDS      = 120
$POLL_INTERVAL_SECONDS         = 30
$DISCOVERY_HOLDS_SIR_THRESHOLD = 1GB
$PRIMARY_FOLDER_SIZE_THRESHOLD = 1GB
$ASYNC_HOLD_CHECK_WAIT         = 90   # seconds — Exchange applies DelayHoldApplied asynchronously

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

function ConvertTo-FolderQueryString {
    param([string]$FolderId)
    $encoding   = [System.Text.Encoding]::GetEncoding("us-ascii")
    $nibbler    = $encoding.GetBytes("0123456789ABCDEF")
    $idBytes    = [Convert]::FromBase64String($FolderId)
    $indexBytes = New-Object byte[] 48
    $indexBytes[0] = 1
    [System.Buffer]::BlockCopy($idBytes, 0, $indexBytes, 1, 24)
    $query = "folderid:"
    for ($i = 0; $i -lt 25; $i++) {
        $query += [char]$nibbler[$indexBytes[$i] -shr 4]
        $query += [char]$nibbler[$indexBytes[$i] -band 0x0F]
    }
    return $query
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

# --- SIR already disabled: prompt to re-enable before mode selection ---
if (-not $sirEnabled) {
    Write-Host ""
    Write-Host "      ================================================" -ForegroundColor Yellow
    Write-Host "       SingleItemRecovery is currently DISABLED" -ForegroundColor Yellow
    Write-Host "       This was likely cleared during a previous cleanup run." -ForegroundColor White
    Write-Host "       Re-enable it once the mailbox quota has recovered." -ForegroundColor White
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
    }
}

# --- Mode loop — allows [F] post-purge [M] to return here ---
$modeLoopActive = $true
while ($modeLoopActive) {
    $modeLoopActive    = $false
    $mfaOnlyMode       = $false
    $statusOnlyMode    = $false
    $folderCleanupMode = $false

    # --- Mode selection ---
    Write-Host ""
    Write-Host "      What would you like to do?" -ForegroundColor White
    Write-Host "        [C] Full cleanup   — compliance search, purge, and MFA" -ForegroundColor Gray
    Write-Host "        [M] MFA only       — re-check SIR, clear delay holds, and re-trigger MFA" -ForegroundColor Gray
    Write-Host "        [F] Folder cleanup — permanently purge contents of a primary mailbox folder" -ForegroundColor Gray
    Write-Host "        [S] Status only    — exit here, no changes made" -ForegroundColor Gray
    Write-Host "        [Q] Quit" -ForegroundColor Gray
    Write-Host ""
    $modeChoice = Read-Host "      Choice"
    Write-Host ""

    switch -Regex ($modeChoice) {
        '^[Ss]' { $statusOnlyMode    = $true }
        '^[Mm]' { $mfaOnlyMode       = $true }
        '^[Cc]' { }
        '^[Ff]' { $folderCleanupMode = $true }
        default {
            $exitMsg = if ($sirRestored) { "SingleItemRecovery re-enabled. Exited." } else { "Exited. No changes were made." }
            Write-Host "  $exitMsg`n" -ForegroundColor Cyan
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            exit 0
        }
    }

# --- Status only: exit cleanly ---
if ($statusOnlyMode) {
    $exitMsg = if ($sirRestored) { "SingleItemRecovery re-enabled. Status check complete." } else { "Status check complete. No changes were made." }
    Write-Host "  $exitMsg`n" -ForegroundColor Cyan
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 0
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

        # Primary mailbox quota display
        $primaryStats      = $null
        $primaryUsedBytes  = [long]0
        $primaryLimitBytes = ConvertTo-Bytes $mbx.ProhibitSendReceiveQuota
        try {
            $primaryStats     = Get-MailboxStatistics -Identity $Mailbox -ErrorAction Stop
            $primaryUsedBytes = ConvertTo-Bytes $primaryStats.TotalItemSize
        } catch {
            Write-Detail "WARNING: Could not fetch primary mailbox size. $_" Yellow
        }
        $primaryPct = if ($primaryLimitBytes -gt 0) { [int](($primaryUsedBytes / $primaryLimitBytes) * 100) } else { 0 }

        Write-Host ""
        Write-Detail ("Primary Mailbox    : {0} / {1} ({2}% full)" -f `
            (Format-Size $primaryUsedBytes), (Format-Size $primaryLimitBytes), $primaryPct) `
            $(if ($primaryPct -ge 90) { 'Red' } elseif ($primaryPct -ge 70) { 'Yellow' } else { 'Green' })
        Write-Host ""

        # Primary folder list — exclude Recoverable Items and root; filter > 1 GB; sort largest first
        $primaryFolders = Get-MailboxFolderStatistics -Identity $Mailbox |
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

        Write-Detail "Select a folder to purge:" White
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

        # Folder selection with validation
        $selectedFolder = $null
        while ($null -eq $selectedFolder) {
            $folderChoice = Read-Host "      Enter folder number"
            $folderIndex  = 0
            if ([int]::TryParse($folderChoice, [ref]$folderIndex) -and
                $folderIndex -ge 1 -and $folderIndex -le $primaryFolders.Count) {
                $selectedFolder = $primaryFolders[$folderIndex - 1]
            } else {
                Write-Detail "Invalid selection. Enter a number between 1 and $($primaryFolders.Count)." Yellow
            }
        }

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
            $folderQuery      = ConvertTo-FolderQueryString -FolderId $selectedFolder.FolderId

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
        Write-Host "  Status check complete. No changes were made.`n" -ForegroundColor Cyan
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        exit 0
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

    if ($disableSIR) {
        try {
            Set-Mailbox -Identity $Mailbox -SingleItemRecoveryEnabled $false -ErrorAction Stop
            Write-Detail "SingleItemRecovery disabled (MFA can now fully reclaim DiscoveryHolds)." Yellow
            $sirWasDisabledByScript = $true
        } catch {
            Write-Detail "WARNING: Could not disable SingleItemRecovery. Run manually: Set-Mailbox -Identity '$Mailbox' -SingleItemRecoveryEnabled `$false" Yellow
        }
    }

    try {
        Start-ManagedFolderAssistant -Identity $Mailbox -FullCrawl -AggMailboxCleanup -ErrorAction Stop
        Write-Detail "Managed Folder Assistant triggered." Green
        $mfaTriggered = $true
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
    Write-Host "       MFA triggered. Allow $mfaWait." -ForegroundColor White
    Write-Host "       Re-run this script on $Mailbox once" -ForegroundColor White
    Write-Host "       quota recovers to re-enable SingleItemRecovery." -ForegroundColor White
    Write-Host "      ================================================`n" -ForegroundColor Yellow
}

} # end mode loop

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
        " Mode   : $(if ($mfaOnlyMode) { 'MFA Only' } elseif ($folderCleanupMode) { 'Folder Cleanup' } else { 'Full Cleanup' })"
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
        (" Purview policy exception removed : {0}" -f $(if ($policyRestored)          { 'Yes' } else { 'No' }))
        (" Delay hold cleared               : {0}" -f $(if ($delayHoldCleared)        { 'Yes' } else { 'No (not present)' }))
        (" Delay release hold cleared       : {0}" -f $(if ($delayReleaseHoldCleared) { 'Yes' } else { 'No (not present)' }))
        (" Late delay hold cleared          : {0}" -f $(if ($lateDelayHoldCleared)    { 'Yes — Exchange applied async after policy exception removed' } else { 'No' }))
        (" SIR disabled this run            : {0}" -f $(if ($sirWasDisabledByScript)  { 'Yes — re-enable after quota recovers' } else { 'No' }))
        (" SIR re-enabled this run          : {0}" -f $(if ($sirRestored)             { 'Yes' } else { 'No' }))
        (" Managed Folder Assistant triggered: {0}" -f $(if ($mfaTriggered)           { 'Yes' } else { 'No' }))
        (" MFA re-triggered (late hold)     : {0}" -f $(if ($mfaRetriggered)          { 'Yes' } else { 'No' }))
        ""
        $dash
        " OUTCOME"
        $dash
    )
    if (-not $aborted -and -not $errorOccurred) {
        $actionLabel = if ($mfaOnlyMode) { "MFA re-triggered." } else { "Purge complete. MFA triggered." }
        $report += " $actionLabel Space reclaims within $mfaWait."
        if ($sirWasDisabledByScript) {
            $report += " Re-run script on $Mailbox to re-enable SingleItemRecovery once quota recovers."
        }
    } elseif ($aborted) {
        $report += " Aborted by operator. No items were purged."
    } else {
        $report += " Completed with errors. Review console output for details."
    }
    if ($folderCleanupResults.Count -gt 0) {
        $report += @(
            ""
            $dash
            " FOLDER CLEANUP"
            $dash
        )
        foreach ($r in $folderCleanupResults) {
            if ($r.Status -eq 'Purged') {
                $report += (" {0,-30} : {1:N0} items purged  ({2}) — HardDelete" -f `
                    $r.FolderName, $r.Items, (Format-Size $r.SizeBytes))
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
