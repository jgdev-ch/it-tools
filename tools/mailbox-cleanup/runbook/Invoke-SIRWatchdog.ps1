<#
.SYNOPSIS
    SIR Watchdog — monitors in-progress mailbox cleanups and re-disables
    SingleItemRecovery if Exchange re-enables it, keeping the gates open for MFA.

.DESCRIPTION
    Runs on a 2-hour schedule via Azure Automation.
    Reads in-progress tracking blobs from the mailbox-cleanup-audit container,
    checks SIR status on each mailbox, re-disables SIR and re-triggers MFA
    if Exchange has flipped it back on, and updates the tracking blob with
    the check result.

    Identity   : p-corp-aa-mailboxcleanup-azuc-01 (system-assigned managed identity)
    Storage    : pcorpsambcleanupazuc01 / mailbox-cleanup-audit
    Org        : corrohealth.com

.NOTES
    Prerequisites (M365 — separate from Azure RBAC, must be granted by Exchange admin):
      - Exchange Online RBAC role with: Get-Mailbox, Set-Mailbox, Start-ManagedFolderAssistant
      - Assign via: New-ManagementRoleAssignment or Exchange admin center
      - Service principal object ID of the managed identity is needed for the role assignment
#>

$STORAGE_ACCOUNT = "pcorpsambcleanupazuc01"
$CONTAINER       = "mailbox-cleanup-audit"
$ORGANIZATION    = "corrohealth.com"

# --- Connect ---
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-Output "Azure: connected via managed identity."
} catch {
    Write-Error "ERROR: Could not connect to Azure. Ensure system-assigned managed identity is enabled. $_"
    exit 1
}

try {
    Connect-ExchangeOnline -ManagedIdentity -Organization $ORGANIZATION -ShowBanner:$false -ErrorAction Stop
    Write-Output "Exchange Online: connected."
} catch {
    Write-Error "ERROR: Could not connect to Exchange Online. Managed identity may be missing Exchange RBAC. $_"
    exit 1
}

$storageCtx = New-AzStorageContext -StorageAccountName $STORAGE_ACCOUNT -UseConnectedAccount

# --- List in-progress mailboxes ---
try {
    $inProgressBlobs = Get-AzStorageBlob -Container $CONTAINER -Prefix "in-progress/" -Context $storageCtx |
        Where-Object { $_.Name -ne "in-progress/" }
} catch {
    Write-Error "ERROR: Could not list blobs from storage. $_"
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 1
}

if (-not $inProgressBlobs -or @($inProgressBlobs).Count -eq 0) {
    Write-Output "No in-progress mailboxes to check. Exiting."
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 0
}

Write-Output "Found $(@($inProgressBlobs).Count) in-progress mailbox(es)."
Write-Output ""

# --- Process each mailbox ---
foreach ($blob in $inProgressBlobs) {
    $tempFile = [System.IO.Path]::GetTempFileName()
    $state    = $null

    try {
        Get-AzStorageBlobContent -Container $CONTAINER -Blob $blob.Name `
            -Destination $tempFile -Context $storageCtx -Force | Out-Null
        $state = Get-Content $tempFile -Raw | ConvertFrom-Json
    } catch {
        Write-Output "ERROR: Could not read blob '$($blob.Name)': $_ — skipping."
        continue
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }

    $mailbox   = $state.mailbox
    $checkTime = Get-Date -Format 'o'
    Write-Output "Checking: $mailbox"

    # --- Check SIR status ---
    try {
        $mbx = Get-Mailbox -Identity $mailbox -ErrorAction Stop
    } catch {
        Write-Output "  WARNING: Could not retrieve mailbox '$mailbox': $_ — skipping."
        continue
    }

    $sirWasReEnabled = $mbx.SingleItemRecoveryEnabled
    $actionTaken     = "none"

    if ($sirWasReEnabled) {
        Write-Output "  SIR was re-enabled by Exchange. Re-disabling..."

        try {
            Set-Mailbox -Identity $mailbox -SingleItemRecoveryEnabled $false -ErrorAction Stop
            Write-Output "  SIR re-disabled."
            $actionTaken = "sir-re-disabled"
        } catch {
            Write-Output "  ERROR: Could not re-disable SIR: $_"
            $actionTaken = "sir-redisable-failed"
        }

        # Clear any delay holds Exchange may have re-applied
        $freshMbx = Get-Mailbox -Identity $mailbox -ErrorAction SilentlyContinue
        if ($freshMbx) {
            if ($freshMbx.DelayHoldApplied) {
                try {
                    Set-Mailbox -Identity $mailbox -RemoveDelayHoldApplied -ErrorAction Stop
                    Write-Output "  DelayHoldApplied cleared."
                } catch { Write-Output "  WARNING: Could not clear DelayHoldApplied." }
            }
            if ($freshMbx.DelayReleaseHoldApplied) {
                try {
                    Set-Mailbox -Identity $mailbox -RemoveDelayReleaseHoldApplied -ErrorAction Stop
                    Write-Output "  DelayReleaseHoldApplied cleared."
                } catch { Write-Output "  WARNING: Could not clear DelayReleaseHoldApplied." }
            }
        }

        # Re-trigger MFA so it runs with SIR disabled
        try {
            Start-ManagedFolderAssistant -Identity $mailbox -FullCrawl -AggMailboxCleanup -ErrorAction Stop
            Write-Output "  Managed Folder Assistant re-triggered."
            if ($actionTaken -eq "sir-re-disabled") { $actionTaken = "sir-re-disabled-mfa-retriggered" }
        } catch {
            Write-Output "  WARNING: Could not re-trigger MFA: $_"
        }

    } else {
        Write-Output "  SIR still disabled — no action needed."
    }

    # --- Update tracking blob ---
    $recheckCount = if ($state.runbookRecheckCount) { [int]$state.runbookRecheckCount + 1 } else { 1 }

    $existingChecks = if ($state.runbookChecks) {
        @($state.runbookChecks) + @([PSCustomObject]@{
            checkedAt       = $checkTime
            sirWasReEnabled = $sirWasReEnabled
            actionTaken     = $actionTaken
        })
    } else {
        @([PSCustomObject]@{
            checkedAt       = $checkTime
            sirWasReEnabled = $sirWasReEnabled
            actionTaken     = $actionTaken
        })
    }

    $updatedState = [ordered]@{
        mailbox                 = $state.mailbox
        status                  = 'in-progress'
        sirDisabledAt           = $state.sirDisabledAt
        scriptVersion           = $state.scriptVersion
        techAccount             = $state.techAccount
        discoveryHoldsGbAtStart = $state.discoveryHoldsGbAtStart
        lastMfaTriggered        = $state.lastMfaTriggered
        runbookRecheckCount     = $recheckCount
        lastRunbookCheck        = $checkTime
        runbookChecks           = $existingChecks
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        ($updatedState | ConvertTo-Json -Depth 5 -Compress) |
            Set-Content $tempFile -Encoding UTF8 -NoNewline
        Set-AzStorageBlobContent -Container $CONTAINER -Blob $blob.Name `
            -File $tempFile -Context $storageCtx -Force | Out-Null
        Write-Output "  Tracking state updated (recheck #$recheckCount)."
    } catch {
        Write-Output "  WARNING: Could not update tracking blob: $_"
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }

    Write-Output ""
}

# --- Done ---
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Write-Output "SIR Watchdog complete."
