# Exchange Audit Redesign — Phase B Implementation Plan (login gating + go live)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan. Some tasks are Azure/Entra portal steps (marked **[infra]**) executed by Josh with Claude guiding; the rest are code. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Put Exchange Audit behind Entra sign-in with no public data path — an authenticated Function App proxy reads the private blob via its managed identity; the tool signs in (MSAL) and calls the Function with a bearer token; the SAS is removed. Then run the real scan and ship to production.

**Architecture:** New Node Function App (matches the `adobe-func` `.js` precedent) with a system-assigned managed identity granted **Storage Blob Data Reader** on the `exchange-audit` container, gated by **App Service Easy Auth** (Microsoft/Entra). The tool acquires a token for a scope exposed on the **existing hub app registration** (`6d881af5-d626-4df6-8969-69f1f0292772`) and calls `GET /api/exchange-audit`. Blob container stays fully private (no SAS, no anonymous).

**Tech Stack:** Node Azure Functions (v4 model; **Node 22 LTS** or latest supported LTS — *not* Node 20, which is EOL) with `@azure/storage-blob` + `@azure/identity`; MSAL via shared `auth.js`; Az.Storage/Automation for the run.

**Spec:** `docs/superpowers/specs/2026-07-29-exchange-audit-redesign-design.md`
**Depends on:** Phase A (built) — offenders-only runbook + tool schema already in place on `testing`.

## Fill-when-provisioned values

These are unknown until infra exists; treated like the SAS was (constants filled at deploy):
- `FUNCTION_URL` — e.g. `https://<funcapp>.azurewebsites.net/api/exchange-audit`
- `FUNCTION_SCOPE` — the exposed scope, e.g. `api://6d881af5-d626-4df6-8969-69f1f0292772/access_as_user`

---

### Task 1: Provision the Function App [infra]

- [ ] **Step 1: Create the Function App**
  - Portal → Create Function App → **Flex Consumption**, **Runtime: Node.js 22 LTS** (or latest supported LTS — not 20, EOL), Linux, same region as the storage account.
  - After create: **Identity → System assigned → On**. Note the MI's object/principal ID.

- [ ] **Step 2: Grant the MI read on the blob container**
  - Storage account `pcorpsambcleanupazuc01` → Access Control (IAM) → Add role assignment → **Storage Blob Data Reader** → assign to the Function App's managed identity. (Scope to the `exchange-audit` container if you prefer least-privilege; account scope is fine.)

- [ ] **Step 3: Verify**
  - Function App shows a system-assigned identity; the role assignment appears under the storage account's IAM. (Deeper verification happens when the function runs in Task 3.)

---

### Task 2: Entra — expose the API scope + configure Easy Auth [infra, Claude-guided]

- [ ] **Step 1: Expose an API scope on the existing hub app registration**
  - Entra → App registrations → the hub app (`6d881af5-d626-4df6-8969-69f1f0292772`) → **Expose an API**.
  - Set Application ID URI to `api://6d881af5-d626-4df6-8969-69f1f0292772` (accept default).
  - **Add a scope:** name `access_as_user`, admins+users consent, enabled. (This yields `FUNCTION_SCOPE = api://6d881af5-.../access_as_user`.)
  - Because the SPA and API are the **same** app registration, no separate client→API permission grant is needed; a one-time admin consent for the scope is enough.

- [ ] **Step 2: Enable Easy Auth on the Function App**
  - Function App → **Authentication → Add identity provider → Microsoft**.
  - **Use existing app registration:** enter the hub app's **client ID** `6d881af5-...` and tenant `683d57e7-70bf-4bc4-b88d-bd8905a0c39a`.
  - **Allowed token audiences:** add `api://6d881af5-d626-4df6-8969-69f1f0292772` **and** the client ID `6d881af5-...` (belt-and-suspenders for how MSAL stamps the audience).
  - **Restrict access: Require authentication.** Unauthenticated requests → **HTTP 401** (NOT redirect — this is an API called by fetch, not a browsed page).
  - *(Optional hardening, deferred:* require the reporting Entra group via an app-role assignment on the app / a groups-claim check.*)*

- [ ] **Step 2b: Report values back to Claude:** the `FUNCTION_URL` and confirm `FUNCTION_SCOPE`. Claude fills them in Task 5.

---

### Task 3: Function code + deploy

**Files:**
- Create: `tools/exchange-audit/function/exchangeAudit.js`
- Create: `tools/exchange-audit/function/package.json`
- Create: `tools/exchange-audit/function/host.json`

- [ ] **Step 1: Write the function (Node v4 model)**

`tools/exchange-audit/function/exchangeAudit.js`:

```javascript
const { app } = require('@azure/functions');
const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');

const ACCOUNT   = 'pcorpsambcleanupazuc01';
const CONTAINER = 'exchange-audit';
const BLOB      = 'exchange-audit.json';

// Auth is enforced by App Service Easy Auth at the platform layer (unauthenticated
// requests never reach here), so the function itself is authLevel 'anonymous'.
app.http('exchange-audit', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'exchange-audit',
  handler: async (request, context) => {
    try {
      const svc  = new BlobServiceClient(`https://${ACCOUNT}.blob.core.windows.net`, new DefaultAzureCredential());
      const blob = svc.getContainerClient(CONTAINER).getBlobClient(BLOB);
      const dl   = await blob.download();
      const body = await streamToString(dl.readableStreamBody);
      return { status: 200, headers: { 'Content-Type': 'application/json' }, body };
    } catch (e) {
      context.error('exchange-audit blob read failed', e);
      return { status: 502, jsonBody: { error: 'Could not read audit data from storage.' } };
    }
  }
});

async function streamToString(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  return Buffer.concat(chunks).toString('utf8');
}
```

`tools/exchange-audit/function/package.json`:

```json
{
  "name": "exchange-audit-function",
  "version": "1.0.0",
  "main": "exchangeAudit.js",
  "dependencies": {
    "@azure/functions": "^4.5.0",
    "@azure/storage-blob": "^12.24.0",
    "@azure/identity": "^4.4.1"
  }
}
```

`tools/exchange-audit/function/host.json`:

```json
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
```

- [ ] **Step 2: Deploy [infra]** — deploy the `function/` folder to the Function App (VS Code Azure Functions extension, `func azure functionapp publish <name>`, or zip deploy). `npm install` runs on deploy to pull the three packages.

- [ ] **Step 3: Verify the function reads the blob (with a test blob present)**
  - Ensure a blob exists (the sample or a real run). Signed-in test in Task 8; for now confirm the deploy succeeded and the function appears in the portal.

- [ ] **Step 4: Commit**

```bash
git add tools/exchange-audit/function/
git commit -m "feat(exchange-audit): Node Function proxy — reads private blob via managed identity (Easy Auth gated)"
```

---

### Task 4: Function App CORS + preflight validation [infra + verify]

- [ ] **Step 1: Configure CORS on the Function App**
  - Function App → **CORS** → add allowed origin `https://jgdev-ch.github.io`. (Leave "Enable Access-Control-Allow-Credentials" off — we use a bearer token, not cookies.)

- [ ] **Step 2: Verify the CORS preflight passes *through Easy Auth*** ⚠ known gotcha

  The tool sends an `Authorization` header → the browser issues a preflight `OPTIONS`. Easy Auth in "require authentication" mode can 401 the unauthenticated preflight and break CORS. Test it:

```bash
curl -s -D - -o /dev/null -X OPTIONS \
  -H "Origin: https://jgdev-ch.github.io" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: authorization" \
  "https://<funcapp>.azurewebsites.net/api/exchange-audit" | grep -i -e "^HTTP" -e "access-control-"
```
  Expected: `200` + `Access-Control-Allow-Origin: https://jgdev-ch.github.io`. If it returns **401**, apply the fix: in the Function App Authentication settings, ensure the platform handles CORS before auth (App Service processes CORS for OPTIONS ahead of Easy Auth in current config); if still failing, set the auth setting to allow unauthenticated `OPTIONS` (or add the `/api/exchange-audit` preflight to an unauthenticated path). Re-test until it returns 200.

- [ ] **Step 3: Verify an unauthenticated GET is rejected**

```bash
curl -s -o /dev/null -w "%{http_code}\n" "https://<funcapp>.azurewebsites.net/api/exchange-audit"
```
  Expected: **401** (Easy Auth blocks it) — confirms no public data path.

---

### Task 5: Tool — MSAL sign-in + Function fetch + remove SAS

**Files:**
- Modify: `tools/exchange-audit/index.html`

- [ ] **Step 1: Load MSAL + add the auth screen**
  - In `<head>`, add before `auth.js`: `<script src="../../shared/msal-browser.min.js"></script>`.
  - Add an auth-screen card (same pattern/markup as the Graph tools, e.g. user-creation's `#authScreen`), with a "Sign in with Microsoft" button calling `doSignIn()`, and the shared anti-flash CSS (`#authScreen{display:none}` + `body{opacity:0}`).

- [ ] **Step 2: Replace the blob/SAS constants + fetch with the Function call**

Replace the `AUDIT_BLOB_URL` constant with:

```javascript
const FUNCTION_URL   = '';  // fill: https://<funcapp>.azurewebsites.net/api/exchange-audit
const FUNCTION_SCOPE = '';  // fill: api://6d881af5-d626-4df6-8969-69f1f0292772/access_as_user
```

Replace `loadAuditData()` with:

```javascript
async function loadAuditData() {
  if (!FUNCTION_URL || !FUNCTION_SCOPE) {
    showError('Backend not configured yet. Load a local JSON file to test.', null);
    return;
  }
  showLoading();
  try {
    const token = await ITTools.auth.getToken([FUNCTION_SCOPE]);
    const res = await fetch(FUNCTION_URL, { headers: { Authorization: 'Bearer ' + token } });
    if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`);
    onDataLoaded(await res.json());
  } catch (e) {
    showError('Could not load audit data (' + (e.message || e) + '). Try sign out / in, or load a local JSON file.', null);
  }
}
```

- [ ] **Step 3: Wire init() to sign-in (like the Graph tools)**

```javascript
async function init() {
  ITTools.theme.init();
  ITTools.ui.renderTopbar({ toolName: "Exchange Audit", hubRelPath: "../../", status: "beta" });
  ITTools.ui.syncThemeIcon();
  let _session = false;
  await ITTools.auth.init({
    scopes: [FUNCTION_SCOPE],
    onSignIn: async acct => { _session = true;
      document.getElementById('authScreen').style.display='none';
      document.getElementById('appScreen').style.display='block';
      ITTools.ui.setUser(acct); document.body.style.opacity='1'; loadAuditData(); },
    onSignOut: () => {
      document.getElementById('appScreen').style.display='none';
      document.getElementById('authScreen').style.display='flex';
      ITTools.ui.clearUser(); document.body.style.opacity='1'; }
  });
  if (!_session) { document.getElementById('authScreen').style.display='flex'; document.body.style.opacity='1'; }
}
async function doSignIn() {
  try { const acct = await ITTools.auth.signIn();
    document.getElementById('authScreen').style.display='none';
    document.getElementById('appScreen').style.display='block';
    ITTools.ui.setUser(acct); loadAuditData();
  } catch(e){ const el=document.getElementById('authErr'); el.textContent=e.message; el.style.display='block'; }
}
```
  Wrap the existing `.audit-wrap` content in an `#appScreen` container (hidden until sign-in) so the topbar+auth screen show first. Keep the local-file fallback wired inside `showError`.
  Change the load trigger from `document.addEventListener('DOMContentLoaded', init)` — unchanged (still calls `init`).

- [ ] **Step 4: Remove every trace of the SAS** — no `AUDIT_BLOB_URL`, no `blob.core.windows.net`, no `?sp=` string anywhere in the file.

- [ ] **Step 5: Verify (local, pre-fill)** — with constants blank, the tool shows the auth screen; the local-file fallback still renders `sample-data.json`. `node --check` the inline JS.

- [ ] **Step 6: Fill values + commit** — once Task 2b provides them, set `FUNCTION_URL`/`FUNCTION_SCOPE`.

```bash
git add tools/exchange-audit/index.html
git commit -m "feat(exchange-audit): MSAL sign-in + authenticated Function fetch; remove public SAS"
```

---

### Task 6: Retire the old read SAS + confirm container private [infra, decision]

- [ ] **Step 1: Confirm the container is private** — no anonymous access (already set), and the tool no longer carries a SAS (Task 5 Step 4).
- [ ] **Step 2: Invalidate the previously-exposed SAS before real data lands.** The earlier read+list SAS (expires 2027) was exposed in the tool's JS on preview. Once real offender data is in the container, anyone who captured that SAS could read it until expiry. Options:
  - **(Recommended) Rotate the storage account key** the SAS was signed with — this immediately invalidates it. ⚠ It also invalidates the **Mailbox Cleanup tracking-blob SAS** on the same account, so **reissue that SAS + re-patch `Invoke-MailboxCleanup.ps1`/`downloads.json`** in the same maintenance window.
  - **(Accept)** If key rotation is too disruptive now, accept the residual — note that the SAS only ever had access to sample/all-0 data during its exposure window, and real data lands only after this point. Decide explicitly.

---

### Task 7: Run the real runbook [infra]

- [ ] **Step 1** — Start `Invoke-ExchangeAudit` on-demand (or wait for the Mon 02:00 schedule). Watch for `Pass B complete — scanned N, offenders M` and `Upload complete`. Runtime ~30–90 min. This writes real offenders-only data to the private blob.

---

### Task 8: End-to-end validation (signed in)

- [ ] **Step 1** — On the preview tool URL, sign in with a tenant account. Confirm: the auth screen → sign-in → the tool fetches via the Function (bearer token) and renders the **real** offenders list, "Scanned N · M at risk", correct badges. No SAS in page source (view-source / network shows only the Function call). CSV export works.
- [ ] **Step 2** — Confirm an unauthenticated/incognito hit on `FUNCTION_URL` returns 401 (from Task 4 Step 3) and the tool shows the auth screen (no data) when signed out.

---

### Task 9: Ship to production

- [ ] **Step 1** — Merge `testing → main`, push (triggers prod deploy). Verify the prod tool: sign-in gate + real data render + hub card present.

```bash
git checkout main && git merge testing --no-ff -m "Release: Exchange Audit v2 — real data, offenders-only, login-gated" && git push origin main && git checkout testing
```

- [ ] **Step 2** — Update memory + Obsidian: Exchange Audit ✅ live in prod, login-gated, real weekly data.

---

## Self-Review Against Spec

| Spec requirement | Task |
|---|---|
| New Function App + MI + Storage Blob Data Reader | Task 1 |
| Easy Auth (Entra) gate; reuse hub app reg + exposed scope | Task 2 |
| Function reads blob via MI, returns JSON | Task 3 |
| CORS for hub origin; preflight-through-EasyAuth verified; unauth = 401 | Task 4 |
| Tool MSAL sign-in + Function fetch (bearer); SAS removed | Task 5 |
| Blob fully private, no public data path; old SAS retired | Task 4 Step 3 + Task 6 |
| Real offenders data via runbook | Task 7 |
| End-to-end signed-in validation | Task 8 |
| Ship to prod | Task 9 |
