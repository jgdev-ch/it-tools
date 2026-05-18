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
$skipped         = @()
$toProcess       = @()
$results         = @()
$failureCount    = 0
$reportTime      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- Helpers ---
function Write-Step {
    param([int]$Step, [string]$Message)
    Write-Host "`n[$Step/5] $Message" -ForegroundColor Cyan
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
            Action      = if ($autoMap) { 'Repair' } else { 'Skip' }
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
Write-Detail ("{0} mailbox(es) found — {1} automapped, {2} already disabled" -f $allMailboxes.Count, $toRefresh.Count, $skipped.Count) White

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

# --- Phase 3: Action Selection ---
Write-Step 3 "Action Selection"
Write-Host ""
Write-Host "      NOTE: Repair refreshes the AutoMapping pointer. If Phase 4 reports" -ForegroundColor DarkGray
Write-Host "            an ACE anomaly, the pointer may not hold — re-run and choose" -ForegroundColor DarkGray
Write-Host "            Disable for those mailboxes if they disappear again." -ForegroundColor DarkGray
Write-Host ""

$disableChoice = Read-Host "      Disable AutoMapping on any automapped mailboxes? [Y/N]"
Write-Host ""

if ($disableChoice -match '^[Yy]') {
    $bulkChoice = Read-Host "      Apply to all [A] or one at a time [O]?"
    Write-Host ""

    if ($bulkChoice -match '^[Aa]') {
        foreach ($mbx in $allMailboxes | Where-Object { $_.Action -eq 'Repair' }) {
            $mbx.Action = 'Disable'
        }
    } else {
        $automapped = @($allMailboxes | Where-Object { $_.Action -eq 'Repair' })
        for ($i = 0; $i -lt $automapped.Count; $i++) {
            $mbx    = $automapped[$i]
            $prompt = "      [{0}/{1}] {2,-46} [R]epair / [D]isable / [S]kip" -f ($i + 1), $automapped.Count, $mbx.Address
            do {
                $choice = Read-Host $prompt
            } while ($choice -notmatch '^[RrDdSs]$')
            switch -Regex ($choice) {
                '^[Dd]$' { $mbx.Action = 'Disable' }
                '^[Ss]$' { $mbx.Action = 'Skip'    }
            }
        }
        Write-Host ""
    }
}

# --- Action plan table ---
Write-Host ""
Write-Detail ("{0,-50} {1}" -f 'Mailbox', 'Action') Gray
Write-Detail ("{0,-50} {1}" -f '-------', '------') Gray
foreach ($mbx in $allMailboxes) {
    $actionLabel = switch ($mbx.Action) {
        'Repair'  { 'Repair  (refresh AutoMapping pointer)' }
        'Disable' { 'Disable AutoMapping'                   }
        'Skip'    { 'Skip  (already disabled / orphaned)'   }
    }
    $actionColor = switch ($mbx.Action) {
        'Repair'  { 'Green'  }
        'Disable' { 'Yellow' }
        'Skip'    { 'Gray'   }
    }
    Write-Detail ("{0,-50} {1}" -f $mbx.Address, $actionLabel) $actionColor
}
Write-Host ""

$toProcess = @($allMailboxes | Where-Object { $_.Action -in 'Repair', 'Disable' })

if ($toProcess.Count -eq 0) {
    Write-Detail "No changes selected — all mailboxes skipped." Yellow
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Exchange Online session disconnected.`n" -ForegroundColor DarkGray
    exit 0
}

$go = Read-Host "      Proceed? [Y/N]"
Write-Host ""
if ($go -notmatch '^[Yy]') {
    Write-Host "  No changes made.`n" -ForegroundColor Cyan
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 0
}

# --- Phase 4: Permission refresh ---
Write-Step 4 "Permission Operations..."
Write-Host ""

$results = @()
$i       = 0
foreach ($mbx in $toProcess) {
    $label = "[{0}/{1}] {2}" -f ($i + 1), $toProcess.Count, $mbx.Address
    Write-Host ("      {0,-68}" -f $label) -NoNewline

    try {
        $removeWarn = @()
        Remove-MailboxPermission -Identity $mbx.Address -User $Mailbox `
            -AccessRights FullAccess -Confirm:$false `
            -WarningAction SilentlyContinue -WarningVariable removeWarn -ErrorAction Stop
        $hasAce = [bool]($removeWarn | Where-Object { $_ -match 'ACE|not present|nothing' })
        Add-MailboxPermission -Identity $mbx.Address -User $Mailbox `
            -AccessRights FullAccess -AutoMapping ($mbx.Action -eq 'Repair') -ErrorAction Stop | Out-Null

        if ($mbx.Action -eq 'Repair' -and $hasAce) {
            $outcome      = 'Refreshed*'
            $outcomeColor = 'Yellow'
        } else {
            $outcome      = if ($mbx.Action -eq 'Repair') { 'Refreshed' } else { 'Disabled' }
            $outcomeColor = if ($mbx.Action -eq 'Repair') { 'Green' }     else { 'Yellow' }
        }
        Write-Host $outcome -ForegroundColor $outcomeColor
        if ($hasAce -and $mbx.Action -eq 'Repair') {
            Write-Detail "    ACE anomaly — pointer may not hold. Re-run with Disable if mailbox reappears." Yellow
        }
        $results += [PSCustomObject]@{
            Address = $mbx.Address
            Action  = $mbx.Action
            Outcome = $outcome
            Reason  = ''
        }
    } catch {
        $errMsg = $_.Exception.Message
        Write-Host "Failed" -ForegroundColor Red
        Write-Detail "    $errMsg" Red
        $results += [PSCustomObject]@{
            Address = $mbx.Address
            Action  = $mbx.Action
            Outcome = 'Failed'
            Reason  = $errMsg
        }
        $failureCount++
    }
    $i++
}

# Add skipped mailboxes to results
foreach ($mbx in $allMailboxes | Where-Object { $_.Action -eq 'Skip' }) {
    $skipReason = if (-not $mbx.AutoMapping) { 'AutoMapping already disabled' } else { 'Skipped by tech' }
    $results += [PSCustomObject]@{
        Address = $mbx.Address
        Action  = 'Skip'
        Outcome = 'Skipped'
        Reason  = $skipReason
    }
}

# --- Phase 5: Verify and summarise ---
Write-Step 5 "Verifying and summarising..."
Write-Host ""

# Re-query to confirm each refresh landed
foreach ($r in $results | Where-Object { $_.Outcome -in 'Refreshed', 'Disabled' }) {
    $verify = Get-EXOMailboxPermission -Identity $r.Address -User $Mailbox -ErrorAction SilentlyContinue |
        Where-Object { $_.AccessRights -contains 'FullAccess' -and -not $_.Deny }
    if (-not $verify) {
        $r.Outcome = 'Failed'
        $r.Reason  = 'Permission not found after operation — verify manually in Exchange admin'
        $failureCount++
    } elseif ($null -ne $verify.AutoMapping -and $verify.AutoMapping -ne ($r.Action -eq 'Repair')) {
        $r.Outcome = 'Failed'
        $r.Reason  = 'AutoMapping flag mismatch after operation — verify manually in Exchange admin'
        $failureCount++
    }
}

# Result table
Write-Host "      ================================================" -ForegroundColor DarkCyan
Write-Host "       Results" -ForegroundColor White
foreach ($r in $results) {
    $color = switch ($r.Outcome) {
        'Refreshed'  { 'Green'  }
        'Refreshed*' { 'Yellow' }
        'Disabled'   { 'Yellow' }
        'Skipped'    { 'Gray'   }
        'Failed'     { 'Red'    }
        default      { 'White'  }
    }
    $suffix = if ($r.Outcome -eq 'Skipped') { "  ($($r.Reason))" } `
              elseif ($r.Outcome -eq 'Refreshed*') { "  (ACE anomaly — re-run with Disable if mailbox reappears)" } `
              elseif ($r.Outcome -eq 'Failed') { "  — $($r.Reason)" } `
              else { '' }
    Write-Detail ("  {0,-50} {1}{2}" -f $r.Address, $r.Outcome, $suffix) $color
}
Write-Host "      ================================================" -ForegroundColor DarkCyan
Write-Host ""

$refreshedCount = ($results | Where-Object { $_.Outcome -in 'Refreshed', 'Refreshed*' }).Count
$aceCount       = ($results | Where-Object { $_.Outcome -eq 'Refreshed*' }).Count
$disabledCount  = ($results | Where-Object { $_.Outcome -eq 'Disabled'   }).Count
$skippedCount   = ($results | Where-Object { $_.Outcome -eq 'Skipped'    }).Count
$failedCount    = ($results | Where-Object { $_.Outcome -eq 'Failed'     }).Count

# Failure callout
if ($failedCount -gt 0) {
    Write-Detail "$failedCount mailbox(es) failed — manual remediation required." Red
    Write-Detail "Check Exchange admin permissions and re-run, or grant Full Access manually." Gray
    Write-Host ""
}

# Conditional Next Steps
$alias = ($Mailbox -split '@')[0]
$step  = 1
Write-Host "      ================================================" -ForegroundColor DarkCyan
Write-Host "       Next Steps" -ForegroundColor White
if ($refreshedCount -gt 0) {
    Write-Detail "  Step $step — Ask $alias to close and reopen Outlook." White
    Write-Detail "           Repaired mailboxes should reappear within a few minutes." Gray
    $step++
}
if ($disabledCount -gt 0) {
    Write-Detail "  Step $step — Manually add disabled mailboxes in Outlook:" White
    Write-Detail "           Classic: File > Account Settings > Change > More Settings" Gray
    Write-Detail "                    > Advanced > add shared mailbox address" Gray
    Write-Detail "           New Outlook: Right-click Folders > Add shared folder" Gray
    $step++
}
if ($refreshedCount -gt 0) {
    Write-Detail "  Step $step — If repaired mailboxes still missing after restart," White
    Write-Detail "           rebuild the Outlook profile: Control Panel > Mail > Show Profiles." Gray
    $step++
}
if ($aceCount -gt 0) {
    Write-Detail "  Step $step — If a repaired mailbox reappears but then vanishes again," White
    Write-Detail "           re-run this tool and choose Disable for that mailbox." Gray
    Write-Detail "           (ACE anomaly detected — AutoMapping pointer may not hold.)" DarkGray
}
Write-Host "      ================================================" -ForegroundColor DarkCyan
Write-Host ""

# --- Ticket export ---
Write-Host ""
$export = Read-Host "      Export summary report for ticket? [Y/N]"
if ($export -match '^[Yy]') {
    $reportAlias = ($Mailbox -split '@')[0]
    $reportFile  = "$([System.Environment]::GetFolderPath('Desktop'))\SharedMailboxRepair-$reportAlias-$reportTimestamp.txt"

    $sep  = "=" * 60
    $dash = "-" * 60

    $report = @(
        $sep
        " SHARED MAILBOX REPAIR REPORT"
        $sep
        " Date   : $reportTime"
        " Target : $Mailbox"
        ""
        $dash
        " PRE-FLIGHT"
        $dash
        (" Shared mailboxes found : {0}" -f $allMailboxes.Count)
        (" To be repaired         : {0} (AutoMapping pointer refresh)"         -f (($toProcess | Where-Object { $_.Action -eq 'Repair'  }).Count))
        (" To be disabled         : {0} (AutoMapping will be set to disabled)" -f (($toProcess | Where-Object { $_.Action -eq 'Disable' }).Count))
        (" Skipped                : {0} (AutoMapping already disabled)"         -f ($allMailboxes | Where-Object { $_.Action -eq 'Skip' }).Count)
        ""
        $dash
        " RESULTS"
        $dash
    )

    foreach ($r in $results) {
        $suffix = switch ($r.Outcome) {
            'Skipped'    { " ($($r.Reason))" }
            'Refreshed*' { ' (ACE anomaly — re-run with Disable if mailbox reappears)' }
            'Disabled'   { ' (AutoMapping disabled — manually add in Outlook)' }
            'Failed'     { " — $($r.Reason)" }
            default      { '' }
        }
        $report += (" {0,-50} {1}{2}" -f $r.Address, $r.Outcome, $suffix)
    }

    $report += @(
        ""
        $dash
        " OUTCOME"
        $dash
    )

    if ($failedCount -eq 0) {
        $report += " Operation complete."
    } else {
        $report += " Operation complete with $failedCount failure(s) — manual follow-up required."
    }

    $rStep = 1
    if ($refreshedCount -gt 0) {
        $report += " Step ${rStep}: Ask user to close and reopen Outlook."
        $report += "         Repaired mailboxes should reappear within a few minutes."
        $rStep++
    }
    if ($disabledCount -gt 0) {
        $report += " Step ${rStep}: Manually add disabled mailboxes in Outlook:"
        $report += "         Classic: File > Account Settings > Change > More Settings > Advanced"
        $report += "         New Outlook: Right-click Folders > Add shared folder"
        $rStep++
    }
    if ($refreshedCount -gt 0) {
        $report += " Step ${rStep}: If repaired mailboxes still missing after restart, rebuild"
        $report += "         the Outlook profile via Control Panel > Mail > Show Profiles."
        $rStep++
    }
    if ($aceCount -gt 0) {
        $report += " Step ${rStep}: If a repaired mailbox reappears but then vanishes again on restart,"
        $report += "         re-run this tool and choose Disable for that mailbox."
        $report += "         (ACE anomaly detected — AutoMapping pointer may not hold.)"
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
