# On-Call Rotation Backend Wiring and Hardening

**Date:** 2026-09-10
**Scope:** `tools/on-call/`, the `p-corp-fa-ittools-azuc-01` Function App, and one Entra group
**Status:** design approved 2026-09-10, ready for an implementation plan

> **This file contains infrastructure identifiers** (app registration IDs, resource names, group
> names) and **no credentials, no personal data, and no phone numbers.** `docs/` is served
> world-readable from the preview GitHub Pages mirror, see
> [[finding_pages_public_data_exposure]] — do not add secrets or contact data to this file.

## Goal

Move the On-Call Rotation tool off its committed `data.json` and onto the blob behind the Function
App, so real contact data stops living in a world-readable repo. Along the way, gate read access
to the team, put the function source under version control, and remove dead weight.

## Why now

Giorgi granted the RBAC role on 2026-09-08 (ticket 1009929, change 5428): the managed identity for
`p-corp-fa-ittools-azuc-01` now holds **Storage Blob Data Contributor on the `oncall-rotation`
container only**. That was the last blocker for the backend path.

## Verified current state, 2026-09-10

Audited before designing. This is the baseline; do not redo these.

| Component | State |
|---|---|
| RBAC grant | `Storage Blob Data Contributor`, scoped to the container only. Correct least privilege. |
| Storage | `pcorpsambcleanupazuc01`, container `oncall-rotation`, blob `data.json`. Container private, `allowBlobPublicAccess: False` on the account. |
| `OnCallGet` | Deployed. Reads the correct account/container/blob, hardcoded, via `DefaultAzureCredential`. **No group check at all.** |
| `OnCallSave` | Deployed. **Already enforces** `SG-IT-Tools-OnCall-Admin` via Graph, and validates the payload shape `{ schedule, rotationTechs, otherContacts }`. |
| MI Graph permission | `GroupMember.Read.All` (application), id `98830695-27a2-44f7-8c18-0c3ebc9698f6`, granted 2026-09-02. Only Graph permission held. |
| EasyAuth | `platform.enabled: true`, `requireAuthentication: true`, `unauthenticatedClientAction: Return401`, `requireHttps: true`. **Anonymous `GET /api/OnCallGet` returns 401, verified.** |
| API app registration | "IT Tools - On-Call Function", `cd473454-19a7-4b77-b639-8f11f08e9f77`, `identifierUris: api://cd473454-…`, exposes `OnCall.ReadWrite` (scope id `00c323f7-abd2-48e5-9e12-6695b8f184d9`), enabled, admin-consent type. |
| Hub client | "IT Tools (GitHub Pages)", `6d881af5-d626-4df6-8969-69f1f0292772`, declares the `OnCall.ReadWrite` scope. **Admin consent granted, `AllPrincipals`.** |
| Function App plan | Flex Consumption, Node 22, Central US, RG `P-RG-CORP-EUS-AdobeLicenseMonitor-AZUC-01`. |
| Blob vs repo | **Diverged.** Blob 18,010 bytes dated 2026-09-02; repo copy 19,008 bytes and newer. Both hold 16 real numbers. |

**The Azure CLI cannot test these endpoints.** `AADSTS650057` — the CLI is not pre-authorized on
this custom API. Only the hub SPA can mint a token for this audience, and its registered redirect
URIs are all `https://jgdev-ch.github.io/…` with no localhost, so the end-to-end test must happen
in a browser. **The test is the last step of the wiring, not a precursor to it.**

## Non-goals

- **Azure topology restructure.** Three tools' data, the runtime secrets and the deployment package
  all share `pcorpsambcleanupazuc01`, and two Function Apps sit in the Adobe resource group.
  Deliberately out of scope, decision 2026-09-10: "a long game organization project... it's not
  needed as it's not user facing." Tracked in [[project_backend_infra_architecture_idea]].
- **Retro-scrubbing git history.** The 16 numbers persist in prior commits and remain fetchable
  from the preview Pages mirror of those commits. This work stops *further* exposure; it does not
  undo the disclosure already recorded in the finding.
- **Promoting On-Call to production.** Out of scope. Section 4 adds the production redirect URI so
  it is not a later surprise, but the tool stays preview-gated.

## 1. Backend: one shared group check, under version control

**Problem.** `OnCallGet` has no authorization at all beyond EasyAuth's "any authenticated caller".
`allowedPrincipals` is `{}` and consent is `AllPrincipals`, so any Corro employee who signs into
the hub can call it directly and read numbers labelled Personal. The client-side `denyGate: gsd`
is UI curation, not a security boundary.

**Also a problem:** the function source exists **only** inside
`app-package-pcorpfaittoolsazuc01-7955280/released-package.zip`. It is not in the repo, unlike
`tools/exchange-audit/function/`. A portal edit or a lost package would leave no source.

**Design.**

1. Recover the source from the package and commit it to `tools/on-call/function/`, matching the
   `exchange-audit/function/` precedent: `host.json`, `package.json`, `src/functions/*.js`.
2. Extract `OnCallSave`'s `isCallerAdmin` into a shared helper, `hasGroup(request, credential,
   groupName)`, so there is exactly one enforcement mechanism in the codebase.
3. `OnCallSave` keeps requiring `SG-IT-Tools-OnCall-Admin`.
4. `OnCallGet` requires `SG-IT-Tools-OnCall-User` **or** `SG-IT-Tools-OnCall-Admin`. Admins must
   pass read; requiring only the user group would lock out an admin who is not also in it.
5. Both return **403** with a message naming the required group, distinct from EasyAuth's 401.

**Enforcement mechanism: Graph, reusing the deployed pattern.** Chosen 2026-09-10 over a
`groupMembershipClaims` token claim. The Graph route needs no registration change, no new
permission and no licence, because `OnCallSave` already does exactly this and the MI already holds
`GroupMember.Read.All`. The claims route would have left two different mechanisms in one file. Cost
is one Graph round trip per call, negligible for a page load.

## 2. Client wiring

Three changes in `tools/on-call/index.html`:

1. Set `ONCALL_GET_URL` and `ONCALL_SAVE_URL` to
   `https://p-corp-fa-ittools-azuc-01.azurewebsites.net/api/OnCallGet` and `.../OnCallSave`.
2. **Fix the token audience.** `loadData()` currently calls `ITTools.auth.getToken()` with no
   argument, which returns a token for `_scopes` — `BASE_SCOPES = ["User.Read"]`, a **Microsoft
   Graph** audience. EasyAuth requires `api://cd473454-…`, so as written every call would 401.
   Change to `getToken(["api://cd473454-19a7-4b77-b639-8f11f08e9f77/OnCall.ReadWrite"])`. The same
   fix applies to the save path.
3. Distinguish 403 from other failures in the UI, so a non-member sees "you do not have access to
   the on-call directory" rather than a generic load error.

## 3. New Entra group

Create **`SG-IT-Tools-OnCall-User`**, matching the existing `SG-IT-Tools-GSD` /
`SG-IT-Tools-OnCall-Admin` convention, and populate it with the rotation techs. Josh's step; the
hub's own Group Administration tool can do it.

Referenced **by display name**, not by object ID, consistent with how `OnCallSave` already resolves
`SG-IT-Tools-OnCall-Admin`. Note the tradeoff accepted here: renaming the group silently breaks
enforcement, and because the check fails closed the symptom is a 403 rather than an error. The
existing code already carries this property; this design does not make it worse, and the shared
helper means the group names appear exactly once each.

## 4. Azure configuration

| Change | Detail |
|---|---|
| CORS | Add `https://jgdev-ch.github.io` to `p-corp-fa-ittools-azuc-01`. Currently **empty** — this app has never served browser traffic, because the live Adobe tool calls `p-corp-fa-adobelicmon-azuc-01` instead. **One origin covers both sites.** A CORS origin is scheme + host + port; the path is not part of it, so production and preview share the single origin `https://jgdev-ch.github.io`. Do not add two entries with paths, they will not match. This differs from redirect URIs, which *are* per-path. |
| Production redirect URI | Add `https://jgdev-ch.github.io/it-tools/tools/on-call/` to the hub app registration's SPA URIs. Only the preview URI is registered, so production would throw `AADSTS50011`. Per-tool-page, per the known gotcha. |
| Unused identity providers | Disable apple, facebook, gitHub, google, legacyMicrosoftAccount, twitter on the Function App's auth config. All six are `enabled: true` with empty `registration`, so they cannot currently mint tokens and this is hygiene rather than a live hole. |

## 5. Data migration, and the order is load-bearing

The blob is a 2026-09-02 snapshot. The repo copy is newer and is the real source of truth, because
every roster and schedule change since then was committed to git while `ONCALL_SAVE_URL` was empty.

**Required order:**

1. Upload the current repo `data.json` to `oncall-rotation/data.json`.
2. Verify `OnCallGet` returns it, in the browser, as a group member.
3. **Only then** replace the repo copy with placeholder data.

Reversed, or with step 1 skipped, the tool silently regresses the schedule to 2026-09-02.

**Placeholder shape.** Keep `tools/on-call/data.json` as a structurally valid file with invented
names and **555-prefixed numbers**, so the tool still renders if the API is unreachable and the
payload shape stays documented. Decision 2026-09-10: "keep it for records sake and if it has to
remain we redact all actual numbers with the 555 prefix." The `else` branch that fetches it is
retained as the offline/degraded path.

## 6. Cleanup

- **Delete `AdobeMembers` and `AdobeProducts`** from `p-corp-fa-ittools-azuc-01`. Dead clones: the
  live Adobe tool calls `p-corp-fa-adobelicmon-azuc-01`. Confirm against
  `tools/adobe-license-monitor/index.html`, which hardcodes the other host, before deleting.
- **Rename `package.json`** off `adobe-license-proxy` with its Adobe description. That the app was
  cloned from the Adobe proxy is why the dead functions are there.

## 7. Consolidated asks for Giorgi

Josh is keeping ticket **1009929** open and appending. Both items below are **out of scope for this
pass** and must not block it.

1. **Deployment storage to managed identity.** The Flex deployment config authenticates with
   `StorageAccountConnectionString`, so the app holds an account key for
   `pcorpsambcleanupazuc01`. That key grants full data-plane access to **all six containers** —
   including `oncall-rotation`, `mailbox-cleanup-audit`, `exchange-audit` and
   `azure-webjobs-secrets` — which undercuts the container-scoped RBAC grant that was just
   carefully set up. Switching to managed identity requires a blob role for the MI on the
   `app-package-pcorpfaittoolsazuc01-7955280` container. Josh does not hold User Access
   Administrator, so this is a one-off ask.
2. **`User.Read.All` (application) on the MI — only if gate 1 of the verification fails.** See
   below.

## 8. Verification

No test framework for this tool; verification is a local harness plus manual browser testing.

**Gate 1, before anything else: does `checkMemberGroups` work with only `GroupMember.Read.All`?**
`OnCallSave` calls `POST /users/{id}/checkMemberGroups`, and the MI holds no `User.*` permission.
If that call is unauthorized, `isCallerAdmin` returns `false` and **`OnCallSave` returns 403 to
everyone, including admins, silently.** This has never been exercised — the function has never been
successfully called. If it fails, the fix is ask 2 above and the plan's shape changes, so this is
tested first and separately.

Remaining gates:

| Gate | Method | Expected |
|---|---|---|
| JS syntax | `node --check` on each function file and the tool page | clean |
| Group helper logic | local harness with a stubbed Graph, covering member, non-member, group-not-found, and Graph-error | fails closed in all three negative cases |
| Anonymous access | `curl` both endpoints with no token | 401, unchanged |
| Read as group member | browser, preview hub | 200, returns the uploaded payload |
| Read as non-member | browser, an account in neither group | **403**, message names the group |
| Save as admin | browser, edit and save | 200, blob updated, `OnCallGet` reflects it |
| Save as non-admin | browser | **403** |
| Payload shape | save a malformed body | 400, existing validation |

**Rollback.** Every step is reversible: clearing `ONCALL_GET_URL` restores the local-file path, and
the previous package can be redeployed. Do not delete the recovered `released-package.zip` copy
until the new deployment is verified.

## 9. Risks

1. **Gate 1 failing** is the main schedule risk, and it depends on a Giorgi turnaround.
2. **Redeploying the function** is the only irreversible-feeling step. The app is on Flex
   Consumption with `siteUpdateStrategy: Recreate`, and the deployment path is not something this
   repo has exercised before. The plan must establish how to deploy before changing code, not after.
3. **The 403-versus-401 distinction** must be genuinely visible in the UI, or a group
   misconfiguration will look identical to an outage.
4. **Group referenced by display name** — a rename breaks enforcement closed. Accepted, matching
   existing behaviour.
