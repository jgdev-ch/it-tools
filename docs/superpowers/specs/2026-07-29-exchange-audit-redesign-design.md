# Exchange Audit — Redesign Spec (real RI sizing + offenders-only + login gating)

**Date:** 2026-07-29
**Status:** Approved (design) — supersedes the data-pipeline and access model of `2026-05-22-exchange-audit-design.md`
**Supersedes/amends:** the original spec's Pass 1 (`Get-Mailbox` for size) and the public-SAS access model.

## Why this redesign

The original Exchange Audit shipped and ran end-to-end, but the first real-tenant run exposed two problems:

1. **The size data is wrong — everyone reads 0 GB.** Verified against the real blob (2026-07-29): 15,948 / 15,948 mailboxes have a correct `recoverableQuotaBytes` but **0 / 15,948** have any `recoverableUsedBytes`. Root cause: the runbook read used size from `Get-Mailbox`, which returns the Recoverable Items **quota** but **not** the used size (there is no `RecoverableItemsSize` property on `Get-Mailbox`). It came back null → 0 for every mailbox, so nobody crossed the 80 GB deep-scan threshold and Pass 2 never ran.
2. **Scale + exposure.** The tenant has ~16k mailboxes. Dumping all of them (a) is heavy in the browser (~176k DOM nodes, ~300 ms per search keystroke) and (b) exposed the entire employee mailbox directory via a public read SAS in client JS with no login.

This redesign fixes the data pipeline, narrows output to actionable "offenders," and puts the tool behind Entra sign-in with no public data path.

## Goals

- Report **accurate** Recoverable Items used size per mailbox.
- Surface **only offenders** — mailboxes that are at/over threshold or in a reclamation-blocking state — not the whole directory.
- **No publicly reachable data path.** Data reaches the browser only after Entra sign-in.
- Preserve the existing tool UX (summary strip, table, side-panel diagnostics incl. the ElcProcessingDisabled callout, copy-cleanup-command) — it just renders a focused list now.

## Offender criteria (what the runbook keeps)

A mailbox is kept in the output if **any** of:
- `recoverableUsedBytes ≥ 80 GB` (flat threshold — the team's mental model; ≈73–80% of the 100/105/110 GB quota tiers), **or**
- `ElcProcessingDisabled = true` (MFA will never reclaim space — silent time-bomb regardless of current size), **or**
- `RetentionHoldEnabled = true` (MFA skips the mailbox — reclamation blocked).

All other mailboxes are measured but **discarded** from the output.

## Architecture

Three components; data flows one direction and never reaches a browser unauthenticated.

```
Azure Automation (weekly, MI)                 Azure Blob (private container)        New Function App (MI + Easy Auth)     Hub tool (MSAL)
Invoke-ExchangeAudit.ps1                       exchange-audit/exchange-audit.json    GET /api/exchange-audit               tools/exchange-audit/index.html
  Pass A: Get-Mailbox (bulk) → quota+flags        ▲ write (MI, no SAS)                  ▲ read (MI, Storage Blob Data Reader)   ▲ fetch w/ bearer token
  Pass B: Get-EXOMailboxStatistics per mbx ───────┘                                     │ Easy Auth validates Entra sign-in     │ (MSAL sign-in, like Graph tools)
          → real RI used size, pick offenders                                           └────────────── returns JSON ──────────┘
  Pass C: Get-MailboxFolderStatistics on offenders → folder detail
```

### Component 1 — Runbook `Invoke-ExchangeAudit.ps1` (rewrite of the scan)

Same connection pattern as today (proven SIR-Watchdog managed-identity path: `Connect-AzAccount -Identity` → `Get-AzAccessToken` → `Connect-ExchangeOnline -AccessToken -Organization trusthcs0.onmicrosoft.com`). New scan logic:

- **Pass A — bulk flags + quota (fast):** `Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox` → UPN, DisplayName, ExchangeGuid, RecoverableItemsQuota, SingleItemRecoveryEnabled, ElcProcessingDisabled, RetentionHoldEnabled, LitigationHoldEnabled, DelayHoldApplied, InPlaceHolds. Build a lookup keyed by ExchangeGuid.
- **Pass B — per-mailbox used size (the slow part, ~30–90 min):** for each mailbox, `Get-EXOMailboxStatistics -Identity <ExchangeGuid> -Properties TotalDeletedItemSize` → parse `TotalDeletedItemSize` to bytes = Recoverable Items used size. Compute `recoverablePct = used / quota`.
  - **Throttle-resilient:** small pacing delay between calls; on a throttling/transient error, exponential back-off + limited retry; `Get-EXOMailboxStatistics` (REST) not the legacy cmdlet. Progress `Write-Output` every ~1,000 mailboxes. Wrap each call in try/catch so one bad mailbox doesn't abort the run (record it as `scanError` and continue).
  - **Job-limit guard:** Automation cloud jobs cap at 3 h; expected runtime is well under. Log elapsed time; if it ever approaches the cap, finish writing what's been collected rather than dying with nothing.
- **Offender selection:** keep only mailboxes meeting the offender criteria above.
- **Pass C — folder detail on offenders only:** `Get-MailboxFolderStatistics -Identity <guid> -FolderScope RecoverableItems` on each offender → DiscoveryHolds / Purges / Versions / SubstrateHolds bytes + item counts; set `hasDetailStats = true`. Cheap because offenders are few.
- **Write** `exchange-audit.json` to the private `exchange-audit` container via the runbook MI (`New-AzStorageContext -UseConnectedAccount`). No SAS.
- **Status thresholds** (server-side, unchanged): `critical` ≥90%, `warning` ≥70%, else `ok` (offenders that are kept only due to a risk flag but low % show as e.g. `ok` but appear because of the flag).

### Component 2 — New Function App (authenticated backend)

- New Azure Function App (Consumption), **system-assigned managed identity**.
- Grant the MI **Storage Blob Data Reader** on the `exchange-audit` container (account `pcorpsambcleanupazuc01`).
- One HTTP-triggered function: **`GET /api/exchange-audit`** — reads `exchange-audit/exchange-audit.json` via the MI and returns it as `application/json`.
- **Auth: App Service "Easy Auth"** (App Service Authentication) with the Microsoft/Entra provider, tenant-restricted. v1 requires a valid tenant sign-in; unauthenticated requests are rejected by the platform before the function runs.
  - **Optional hardening (documented, config-toggle):** additionally restrict to the hub reporting Entra group (the same group behind `reportingOnly`) — either via an app-role assignment requirement on the Function App's Entra app, or an in-code group-claim check. Recommended given the data sensitivity; left as a fast-follow so v1 isn't blocked on group plumbing.
- **CORS** on the Function App: allow the hub origins (`https://jgdev-ch.github.io`), `GET`.
- **Fallback:** if provisioning a new Function App is blocked, add this function to the existing `adobe-func` Function App instead (grant *its* MI read on the container). Same design, different host.

### Component 3 — Tool `tools/exchange-audit/index.html`

- **Add MSAL sign-in** (load `shared/msal-browser.min.js` + `shared/auth.js`, auth screen like the Graph tools; reuse the shared anti-flash pattern). Acquire a token for the Function App's exposed API scope.
- **Replace** the blob+SAS fetch with `fetch(FUNCTION_URL, { headers: { Authorization: 'Bearer ' + token } })`. **Remove the `AUDIT_BLOB_URL` SAS constant entirely.**
- Render the offenders list (small). Add a summary line from the JSON: **"Scanned N mailboxes · M at risk."** Keep the local-file fallback for dev, the data-age banner, and all existing side-panel diagnostics.
- **Show the listing reason.** Because an offender can be present due to a risk flag rather than size, a mailbox may be listed while still showing a low/green usage bar (e.g., ElcProcessingDisabled at 40 GB). The table must make that legible — add a reason indicator on the row (e.g., a `BLOCKED` badge for ElcProcessingDisabled and a `HOLD` badge for RetentionHold, alongside the existing Critical/Warning status), so a green-bar row in an "offenders" list reads as intentional. The side panel already explains the specifics.
- Topbar/theme already via `renderTopbar` — now the account menu actually populates (post sign-in), consistent with the Graph tools.

## Data model (output JSON)

```json
{
  "lastScan": "2026-07-29T02:00:00Z",
  "runDurationSeconds": 3120,
  "totalScanned": 15948,
  "offenderCount": 7,
  "scanErrors": 0,
  "mailboxes": [ { /* offender objects — same shape as today: upn, displayName,
                      recoverableUsedBytes, recoverableQuotaBytes, recoverablePct,
                      status, sirEnabled, elcProcessingDisabled, retentionHoldEnabled,
                      litigationHold, delayHoldApplied, inPlaceHoldsCount,
                      hasDetailStats, folders{...} */ } ]
}
```

New top-level fields vs today: `totalScanned`, `offenderCount`, `scanErrors` (was `totalMailboxes`). `mailboxes` now contains offenders only.

## Security model

- **Blob container:** private; no anonymous access, **no SAS**. Only the runbook MI (write) and Function MI (read) touch it.
- **Data path:** browser → Function (Entra sign-in required, Easy Auth) → blob (MI). No unauthenticated path to the data.
- **Output minimization:** the blob holds only offenders (a short list), not the ~16k directory — smaller blast radius even behind auth.
- This is the reusable **gated-reporting pattern** the On-Call Rotation Phase 2 live-save can also adopt.

## Implementation phasing (for writing-plans)

Two phases; each independently testable:

- **Phase A — runbook data fix + offenders-only.** Rewrite the scan (real size, offender selection, Pass C on offenders), new JSON fields, tool renders the offenders list + summary line. Validate via the local-file fallback with a realistic multi-offender sample. *No prod/preview exposure of real data in this phase — dev uses local sample only.*
- **Phase B — gating.** Stand up the Function App (MI + Easy Auth + CORS), add MSAL sign-in to the tool, switch the fetch to the Function, **remove the SAS**, make the blob container fully private. Then run the real scan → validate end-to-end → merge to `main`.

**Ordering guardrail:** the fixed runbook must not write **real** offender data into a SAS-readable blob on public preview. So Phase B's SAS removal + gating lands **before** the first real-data run. The current preview blob (all-0 garbage) is harmless in the interim.

## Out of scope

- Historical trending / retention of past scans (single current-snapshot blob, overwritten weekly — soft-delete keeps 7 days).
- Remediation actions from the tool (it links to `Invoke-MailboxCleanup.ps1` via copy-command; no direct action).
- Primary-mailbox (non-Recoverable-Items) quota auditing.

## Decisions locked

- Offender = ≥80 GB flat **or** ElcProcessingDisabled **or** RetentionHold-blocking.
- Full weekly scan (Mon 02:00 ET), ~30–90 min, throttle-resilient; accept the runtime.
- Login-gated via a **new** Function App (adobe-func fallback); Easy Auth, tenant sign-in required; reporting-group restriction documented as optional hardening.
- Threshold is flat GB (not %-of-quota).
