# Exchange Audit — Phase B Infra Request (Function App + gating)

**Requested by:** Josh Garrett · **Date:** 2026-07-29
**Purpose:** Stand up an Entra-authenticated backend for the IT Tools Hub "Exchange Audit" reporting tool. A weekly Automation runbook already writes `exchange-audit.json` to a private blob; this Function App serves that blob to signed-in users only (no public/SAS access).

## What we need provisioned

### 1. Function App
- **Create** a Function App:
  - Plan: **Flex Consumption**  ·  Runtime: **Node.js 22 LTS** (Linux)
  - Subscription: **Corporate**  ·  Resource group: **P-RG-CORP-EUS-MailboxCleanup-AZUC-01**  ·  Region: **East US** (same as the storage account)
  - Suggested name: **`p-corp-fa-ittools-azuc-01`** (will host hub-tool backends)
- **Enable system-assigned managed identity** on the Function App.

### 2. Storage role (managed identity → data blob)
- Grant the Function App's **system-assigned managed identity** the role **Storage Blob Data Reader** on storage account **`pcorpsambcleanupazuc01`**, container **`exchange-audit`** (container scope preferred; account scope acceptable). *(This is the read-only data access; the runbook MI already has write.)*

### 3. Entra app registration — expose an API scope
- On the **existing hub app registration** `6d881af5-d626-4df6-8969-69f1f0292772` (tenant `683d57e7-70bf-4bc4-b88d-bd8905a0c39a`):
  - **Expose an API** → Application ID URI `api://6d881af5-d626-4df6-8969-69f1f0292772`
  - **Add scope** `access_as_user` (admins + users can consent; enabled). Admin-consent it.

### 4. Easy Auth on the Function App
- Function App → **Authentication → Add identity provider → Microsoft**:
  - **Use existing app registration**: client ID `6d881af5-d626-4df6-8969-69f1f0292772`, tenant `683d57e7-70bf-4bc4-b88d-bd8905a0c39a`
  - **Allowed token audiences:** `api://6d881af5-d626-4df6-8969-69f1f0292772` **and** `6d881af5-d626-4df6-8969-69f1f0292772`
  - **Restrict access: Require authentication** → unauthenticated requests return **HTTP 401** (unauthenticated clients: "Return HTTP 401", not redirect — this is an API).

### 5. CORS on the Function App
- Function App → **CORS** → allowed origin **`https://jgdev-ch.github.io`**. Leave "Access-Control-Allow-Credentials" **off** (bearer-token, not cookies).

### 6. Deployment + access for Josh
- The function code is in the IT Tools repo at **`tools/exchange-audit/function/`** (Node v4 model: `exchangeAudit.js`, `package.json`, `host.json`). Either:
  - deploy it for us (zip deploy / `func azure functionapp publish p-corp-fa-ittools-azuc-01`), **or**
  - grant Josh **Website Contributor** on the Function App so he can deploy + finish config/validation.
- Please hand back the **Function URL** (`https://<name>.azurewebsites.net/api/exchange-audit`).

## Notes
- No inbound secrets: the Function reads the blob via its managed identity (`DefaultAzureCredential`); no keys/SAS stored.
- Low traffic: called only when a tech opens the tool (scale-to-zero is fine).
- This same Function App can later host the On-Call Rotation Phase 2 backend.
