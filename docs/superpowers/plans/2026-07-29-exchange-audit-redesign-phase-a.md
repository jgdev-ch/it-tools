# Exchange Audit Redesign — Phase A Implementation Plan (data fix + offenders-only + CSV export)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Exchange Audit data pipeline so it reports real Recoverable Items used size, narrow output to offenders only (≥80 GB or ElcProcessingDisabled or RetentionHold), and add CSV export — all validated via the local-sample path with no real-data exposure. (Login gating is Phase B.)

**Architecture:** Rewrite the runbook's scan (bulk flags via `Get-Mailbox`; real used size via per-mailbox `Get-EXOMailboxStatistics`; offender selection; folder detail on offenders only) and update the static tool to the new offenders-only JSON schema (summary line, reason badges, CSV export). Phase A keeps the existing local-file/SAS fetch path; it does **not** run the real runbook against a public blob (that waits for Phase B gating).

**Tech Stack:** PowerShell 7.2 + ExchangeOnlineManagement + Az.Storage (runbook); vanilla JS + `shared/styles.css` + `ITTools.csv.download()` (tool).

**Spec:** `docs/superpowers/specs/2026-07-29-exchange-audit-redesign-design.md`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `tools/exchange-audit/runbook/Invoke-ExchangeAudit.ps1` | Rewrite scan logic | Real size, offenders-only, throttle-resilient |
| `tools/exchange-audit/index.html` | Modify `<script>` | New schema, summary line, reason badges, CSV export |
| `tools/exchange-audit/sample-data.json` | Replace | New-schema realistic multi-offender sample for local validation |

---

### Task 1: Rewrite the runbook scan — real size + offenders-only + throttle resilience

**Files:**
- Modify: `tools/exchange-audit/runbook/Invoke-ExchangeAudit.ps1`

- [ ] **Step 1: Replace the Pass 1/Pass 2 section with the new three-pass scan**

Replace everything from `$runStart = Get-Date` through the end of "Pass 2 complete" (the current Pass 1 `Get-Mailbox … Select RecoverableItemsSize` block and the old Pass 2) with:

```powershell
$runStart = Get-Date
# Thresholds $DEEP_SCAN_THRESHOLD_GB (=80), $STATUS_CRITICAL_PCT (=90), $STATUS_WARNING_PCT (=70)
# already exist in the Config block at the top of the file — reuse them, don't re-declare.

# ── Pass A: bulk flags + quota (fast; no used-size here — Get-Mailbox doesn't have it) ──
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
    if ($i % 1000 -eq 0) { Write-Output "  …$i / $($allMailboxes.Count)  (offenders so far: $($offenders.Count), errors: $scanErrors)" }

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
            Where-Object { $_.FolderPath -in @('/DiscoveryHolds','/Purges','/Versions','/SubstrateHolds') }
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
    } catch { Write-Warning "Pass C failed for $($obj.upn): $_" }
}
Write-Output "Pass C complete"
```

- [ ] **Step 2: Replace the output-JSON block with the new schema**

Replace the `$output = @{ … totalMailboxes … mailboxes = @($mailboxObjects) }` block with:

```powershell
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
```

The blob-upload block below it is unchanged (writes `$output` to `exchange-audit/exchange-audit.json` via MI).

- [ ] **Step 3: Parse-check the runbook**

Run:
```bash
pwsh -NoProfile -Command "\$e=\$null;\$null=[System.Management.Automation.Language.Parser]::ParseFile('tools/exchange-audit/runbook/Invoke-ExchangeAudit.ps1',[ref]\$null,[ref]\$e); if(\$e){\$e;exit 1}else{'parse OK'}"
```
Expected: `parse OK`.

- [ ] **Step 4: Commit**

```bash
git add tools/exchange-audit/runbook/Invoke-ExchangeAudit.ps1
git commit -m "feat(exchange-audit): runbook rewrite — real RI size via Get-EXOMailboxStatistics, offenders-only, throttle-resilient"
```

---

### Task 2: New-schema sample data (multi-offender, for local validation)

**Files:**
- Modify: `tools/exchange-audit/sample-data.json`

- [ ] **Step 1: Replace sample-data.json with the new schema + a realistic offender mix**

Include: one size-critical, one size-warning, one **flag-only** offender (ElcProcessingDisabled at low %), one RetentionHold offender. This exercises the reason-badge + "green bar in offenders list" case.

```json
{
  "lastScan": "2026-07-29T02:00:00Z",
  "runDurationSeconds": 3180,
  "totalScanned": 15948,
  "offenderCount": 4,
  "scanErrors": 0,
  "mailboxes": [
    { "upn": "hrconnect@corrohealth.com", "displayName": "HR Connect", "recoverableUsedBytes": 128586891264, "recoverableQuotaBytes": 107374182400, "recoverablePct": 120, "status": "critical", "sirEnabled": false, "elcProcessingDisabled": false, "retentionHoldEnabled": false, "litigationHold": false, "delayHoldApplied": false, "inPlaceHoldsCount": 0, "hasDetailStats": true, "folders": { "discoveryHoldsBytes": 128449339392, "discoveryHoldsItems": 55712, "purgesBytes": 0, "purgesItems": 0, "versionsBytes": 19456, "substrateHoldsBytes": 19456 } },
    { "upn": "divyalakshmi.palanivel@corrohealth.com", "displayName": "Divyalakshmi Palanivel", "recoverableUsedBytes": 89370009600, "recoverableQuotaBytes": 107374182400, "recoverablePct": 83, "status": "warning", "sirEnabled": true, "elcProcessingDisabled": false, "retentionHoldEnabled": false, "litigationHold": false, "delayHoldApplied": false, "inPlaceHoldsCount": 1, "hasDetailStats": true, "folders": { "discoveryHoldsBytes": 85899345920, "discoveryHoldsItems": 402000, "purgesBytes": 2147483648, "purgesItems": 1200, "versionsBytes": 0, "substrateHoldsBytes": 1048576 } },
    { "upn": "blocked.elc@corrohealth.com", "displayName": "Blocked ELC User", "recoverableUsedBytes": 42949672960, "recoverableQuotaBytes": 107374182400, "recoverablePct": 40, "status": "ok", "sirEnabled": true, "elcProcessingDisabled": true, "retentionHoldEnabled": false, "litigationHold": false, "delayHoldApplied": false, "inPlaceHoldsCount": 0, "hasDetailStats": true, "folders": { "discoveryHoldsBytes": 42949672960, "discoveryHoldsItems": 300000, "purgesBytes": 0, "purgesItems": 0, "versionsBytes": 0, "substrateHoldsBytes": 0 } },
    { "upn": "held.user@corrohealth.com", "displayName": "Held User", "recoverableUsedBytes": 32212254720, "recoverableQuotaBytes": 107374182400, "recoverablePct": 30, "status": "ok", "sirEnabled": true, "elcProcessingDisabled": false, "retentionHoldEnabled": true, "litigationHold": true, "delayHoldApplied": false, "inPlaceHoldsCount": 2, "hasDetailStats": true, "folders": { "discoveryHoldsBytes": 32212254720, "discoveryHoldsItems": 150000, "purgesBytes": 0, "purgesItems": 0, "versionsBytes": 0, "substrateHoldsBytes": 0 } }
  ]
}
```

- [ ] **Step 2: Commit**

```bash
git add tools/exchange-audit/sample-data.json
git commit -m "test(exchange-audit): new-schema multi-offender sample (size + flag-only offenders)"
```

---

### Task 3: Tool — new schema, summary line, reason badges

**Files:**
- Modify: `tools/exchange-audit/index.html` (`<script>` + a little CSS/markup)

- [ ] **Step 1: Update `renderStrip` for the new schema + summary line**

Replace `renderStrip` with:

```javascript
function renderStrip(data, filtered) {
  const offenders = data.mailboxes.length;
  const critical  = data.mailboxes.filter(m => m.status === 'critical').length;
  const warning   = data.mailboxes.filter(m => m.status === 'warning').length;

  const daysAgo  = dateDaysAgo(data.lastScan);
  const scanDate = new Date(data.lastScan).toLocaleDateString('en-US', { weekday:'short', month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' });
  const meta = document.getElementById('scanMeta');
  meta.innerHTML = `Scanned <strong>${(data.totalScanned ?? 0).toLocaleString()}</strong> mailboxes &nbsp;·&nbsp; <strong>${offenders}</strong> at risk &nbsp;·&nbsp; Last scan: <strong>${scanDate}</strong>`;
  meta.className = 'strip-scan' + (daysAgo > AGE_ERR_DAYS ? ' expired' : daysAgo > AGE_WARN_DAYS ? ' stale' : '');

  document.getElementById('pillTotal').textContent    = `${offenders} at risk`;
  document.getElementById('pillCritical').textContent = `${critical} critical`;
  document.getElementById('pillWarning').textContent  = `${warning} warning`;
}
```

- [ ] **Step 2: Add reason badges in `renderTable`**

In `renderTable`, replace the `badge` computation with one that appends BLOCKED/HOLD reason badges alongside the size status:

```javascript
    const badges = [];
    if (m.status === 'critical') badges.push(`<span class="status-badge badge-critical">Critical</span>`);
    else if (m.status === 'warning') badges.push(`<span class="status-badge badge-warning">Warning</span>`);
    if (m.elcProcessingDisabled) badges.push(`<span class="status-badge badge-blocked" title="ElcProcessingDisabled — MFA cannot reclaim space">Blocked</span>`);
    if (m.retentionHoldEnabled)  badges.push(`<span class="status-badge badge-hold" title="RetentionHold on — MFA skips this mailbox">Hold</span>`);
    const badge = badges.join(' ');
```

Add the two badge styles to the `<style>` block (next to `.badge-critical`):

```css
  .badge-blocked { background: var(--red-light);   color: var(--red);   border-color: var(--red-border); }
  .badge-hold    { background: var(--amber-light); color: var(--amber); border-color: var(--amber-border); }
```

- [ ] **Step 3: Verify schema + badges via local file**

Start the dev server, open the tool, and load `sample-data.json` via the file picker (AUDIT_BLOB_URL is still SAS/blank — the local-file fallback is the Phase A test path). Confirm:
- Strip reads "Scanned 15,948 · 4 at risk"
- 4 rows; hrconnect Critical, Divyalakshmi Warning, `blocked.elc` green bar + **Blocked** badge, `held.user` green bar + **Hold** badge
- Clicking each shows the correct side panel (blocked.elc → MFA BLOCKED red with fix; held.user → Retention Hold ENABLED + holds)

- [ ] **Step 4: Commit**

```bash
git add tools/exchange-audit/index.html
git commit -m "feat(exchange-audit): offenders-only schema, scanned/at-risk summary, Blocked/Hold reason badges"
```

---

### Task 4: Tool — CSV export

**Files:**
- Modify: `tools/exchange-audit/index.html` (`<script>` + strip markup)

- [ ] **Step 1: Add the Export button to the summary strip**

In the `audit-strip` markup, after the `sortSel` select, add:

```html
    <button id="exportBtn" class="strip-select" style="cursor:pointer;font-weight:600" onclick="exportCsv()">⬇ Export CSV</button>
```

- [ ] **Step 2: Add `exportCsv()` using the shared helper**

Add to the `<script>` block:

```javascript
function exportCsv() {
  if (!filteredList.length) return;
  const gb = b => (b / 1073741824).toFixed(2);
  const rows = filteredList.map(m => ({
    UPN:               m.upn,
    DisplayName:       m.displayName,
    RecoverableUsedGB: gb(m.recoverableUsedBytes),
    RecoverableQuotaGB:gb(m.recoverableQuotaBytes),
    UsagePct:          m.recoverablePct,
    Status:            m.status,
    ListingReason:     [
                         m.recoverableUsedBytes >= 80 * 1073741824 ? '>=80GB' : null,
                         m.elcProcessingDisabled ? 'ElcProcessingDisabled' : null,
                         m.retentionHoldEnabled ? 'RetentionHold' : null
                       ].filter(Boolean).join('; '),
    SIR:               m.sirEnabled ? 'Enabled' : 'DISABLED',
    MFAProcessing:     m.elcProcessingDisabled ? 'BLOCKED' : 'Allowed',
    RetentionHold:     m.retentionHoldEnabled ? 'ENABLED' : 'False',
    HoldsActive:       [ m.litigationHold ? 'Litigation' : null, m.delayHoldApplied ? 'DelayHold' : null,
                         m.inPlaceHoldsCount > 0 ? m.inPlaceHoldsCount + ' policy' : null ].filter(Boolean).join('; ') || 'None',
    DiscoveryHoldsGB:  m.hasDetailStats && m.folders ? gb(m.folders.discoveryHoldsBytes) : '',
    PurgesGB:          m.hasDetailStats && m.folders ? gb(m.folders.purgesBytes) : ''
  }));
  ITTools.csv.download('exchange-audit-offenders-' + new Date().toISOString().slice(0,10) + '.csv', rows);
}
```

- [ ] **Step 3: Verify export**

Load `sample-data.json`, click **Export CSV**. Confirm the file downloads as `exchange-audit-offenders-YYYY-MM-DD.csv` with 4 data rows, **UPN first column**, and `ListingReason` showing `>=80GB` for the big ones and `ElcProcessingDisabled` / `RetentionHold` for the flag-only ones. Apply the "Critical only" filter, export again, confirm it exports just the filtered rows.

- [ ] **Step 4: Commit**

```bash
git add tools/exchange-audit/index.html
git commit -m "feat(exchange-audit): CSV export of (filtered) offender list via ITTools.csv.download"
```

---

### Task 5: Validate end-to-end (local) + push testing

**Files:** none (verification + push)

- [ ] **Step 1: Full local walkthrough**

With the dev server, load `sample-data.json`:
- Summary line correct; 4 offenders; badges correct (Critical / Warning / Blocked / Hold)
- Filter/search/sort work within the offender set; side panels correct; copy-cleanup-command works
- Export CSV (all + filtered) correct

- [ ] **Step 2: Extract + syntax-check inline JS**

```bash
node -e 'const fs=require("fs");const h=fs.readFileSync("tools/exchange-audit/index.html","utf8");const m=h.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/);fs.writeFileSync(process.env.TEMP+"/ea_a.js",m[1]);' && node --check "$TEMP/ea_a.js" && echo "JS OK"
```

- [ ] **Step 3: Push testing**

```bash
git push origin testing
```

**⚠ Do NOT run the real runbook or point the tool at real blob data in Phase A.** Preview validation is local-sample only. Real-data run + gating happens in Phase B (after the Function App is provisioned and the SAS is removed), so real offender data is never written to a public-SAS blob. If the current preview blob (old all-0 schema) makes the deployed preview tool look wrong, either ignore it (local-file is the Phase A test path) or upload this new `sample-data.json` as `exchange-audit.json` to keep preview coherent with fictional data.

---

## Self-Review Against Spec

| Spec requirement | Task |
|---|---|
| Real RI used size via per-mailbox stats (fix the 0 GB bug) | Task 1 (Pass B, `Get-EXOMailboxStatistics.TotalDeletedItemSize`) |
| Offender = ≥80 GB or ElcProcessingDisabled or RetentionHold | Task 1 (`$isOffender`) |
| Throttle-resilient full scan (retry, pacing, progress, error count) | Task 1 (retry loop, `Start-Sleep`, `%1000` progress, `$scanErrors`) |
| Folder detail on offenders only | Task 1 (Pass C) |
| New JSON schema (totalScanned/offenderCount/scanErrors, mailboxes=offenders) | Task 1 Step 2 + Task 2 |
| "Scanned N · M at risk" summary | Task 3 (`renderStrip`) |
| Reason badges (BLOCKED/HOLD) so flag-only offenders read intentionally | Task 3 Step 2 |
| CSV export (filtered, UPN-first, defined columns) via shared helper | Task 4 |
| No real-data exposure in Phase A (local-sample validation only) | Task 5 Step 3 guardrail |
| Login gating / Function App / SAS removal | **Phase B — separate plan** |
