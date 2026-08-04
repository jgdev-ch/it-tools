# Account Lockdown — Security Incident Response Tool

**Date:** 2026-08-04
**Status:** Approved

## Problem

Security periodically flags a user's credentials as compromised (phishing click, credential stuffing hit, suspicious sign-in, etc.) and asks IT to roll the account. Today this is done manually and inconsistently in the Entra admin center: revoke sessions, reset password, sometimes MFA, sometimes disable the account, with no single repeatable flow and no record of exactly what was done beyond Entra's own audit log.

This is a materially higher-stakes action than any existing hub tool — it can act on any user in the tenant, not just stale guests (the closest existing precedent, Guest Access Audit's disable/delete). It needs its own care in scope, confirmation, and access control.

## Decision

Build **Account Lockdown**, a new tool in a new **Security** category, gated behind its own dedicated Entra security group (not reusing Finance/Reporting/GSD/License-Admin gates).

### Scope

- Handles **one account or several at once** — a single flagged user is the common case, but a phishing incident that compromises multiple mailboxes needs to be actionable as one batch.
- **Primary users are IT/help-desk**, acting on a report from Security, but the gating group includes **both IT and Security team members** so either can use it directly as the tool matures.
- **Approval is a process, not a feature.** Whatever sign-off a lockdown needs (verbal, ticket, manager) happens before the tech opens the tool. The tool has no built-in second-person approval step — its own safety gate is the type-to-confirm step below.

### The Lockdown action

A single "Lockdown" button per account queue — no picking and choosing sub-actions. Running it performs, per account, in this order:

1. **Revoke all sign-in sessions** — invalidates active tokens immediately.
2. **Reset password** — generates a strong random temporary password, sets `forceChangePasswordNextSignIn: true`. (This is largely defensive: with sign-in blocked in step 4, the temp password isn't usable until the account is re-enabled later, but it ensures the old, possibly-known password is dead by then too.)
3. **Reset MFA** — removes the account's registered authentication methods. Note for implementation: Graph has no single "reset MFA" call; this requires enumerating `/users/{id}/authentication/methods` and deleting each registered method by its specific type endpoint. This is a real implementation detail to get right, but doesn't change the tool's behavior — it's still one step inside the single Lockdown action.
4. **Block sign-in** — sets `accountEnabled: false`, so the account can't be used regardless of how the other three steps went.

**Each action's outcome is tracked independently, per account** (success / failed / skipped) — a partial failure (e.g., MFA reset fails due to a permissions edge case) must be visible, not hidden behind an overall success/fail flag.

### Workflow — 3-step wizard

Same shape as the User Creation tool's step wizard:

1. **Add Accounts** — build the target queue two ways: search-and-add (Graph lookup by name/UPN, confirm the right person, add to queue — like Name Resolver), or paste/upload a list of UPNs/emails (like Group Import's CSV flow). Both are available together; a queue can be built from either or both. Entries that fail to resolve to a real account are flagged and excluded from the queue rather than silently dropped.
2. **Review & Confirm** — shows the full queue (name + UPN per account). The execute button stays disabled until the tech types the literal word `LOCKDOWN` (all caps) into a confirmation field — required regardless of queue size (1 account or 10).
3. **Results** — a table with one row per account and a status column per action (revoke sessions / reset password / reset MFA / block sign-in), plus an overall "Fully locked down" vs "Partial — needs attention" badge. Any account with a failed action gets a **"Retry failed actions"** control (rotate/loop icon) that re-runs *only the failed actions* for that account — never re-running actions that already succeeded.

### Output

A CSV export from the Results step: one row per account with UPN, display name, per-action outcome, the generated temp password (included only if the password reset actually succeeded), and a timestamp. This is what the tech uses later, out-of-band, to hand a working credential back to the user once the incident is resolved and the account is re-enabled.

### Accountability

Entra's own directory audit log is the system of record for every Graph action this tool performs (each call is already attributed to the signed-in tech automatically). **No Teams notification and no ticket creation in this build** — deliberately deferred, since a SOAR-side automated response (password-spray auto-lockdown) is already designed separately and may end up covering overlapping ground; revisit notification/ticketing once that direction is clearer. The CSV export plus Entra's audit log are the only records this tool produces.

### Gating

- New Entra security group: **`SG-IT-Tools-Security-Lockdown`** (created by Josh outside this codebase; its object ID gets wired into `shared/auth.js` once it exists — not before).
- New `GROUP_GATE_IDS` key: `security`.
- New `PILL_DEFS` entry: label "Security Access", using the new `--accent-slate` color (see Visual Treatment below) — same pattern as the existing Finance/Reporting/GSD/License-Admin pills in the account dropdown.
- New `config.json` category: `security`. Requires adding a `{ key: "security", label: "Security" }` entry to the categories array in `index.html` (currently holds `daily-ops`/`reporting-audit`) — no other layout work needed, since collapsible category sections already shipped 2026-08-03 specifically as groundwork for this.

### Permissions

`User.ReadWrite.All` (revoke sessions, reset password, block sign-in) and `UserAuthenticationMethod.ReadWrite.All` (MFA method reset), in addition to whatever read scope the search-and-add lookup needs (`User.Read.All` / `Directory.Read.All`, consistent with Name Resolver). The signed-in tech's own Entra role must also actually permit these actions — the tool's group gate controls who can *reach* the tool, not what Entra itself will allow them to do, and that distinction should be called out in the tool's own UI copy if a Graph call fails due to insufficient role (surfaced the same way as any other per-action failure in the Results table).

### Visual Treatment

The tool should read as more serious than the rest of the hub, without turning the whole thing red/alarming (explicitly rejected — wrong message for a tool used calmly and often).

- **Hub landing page card**: completely normal — the standard tinted-glass icon square, Lucide `lock` icon, using a new `--accent-slate` accent color (a restrained steel/slate tone, distinct from the 9 existing tool hues). No special treatment on the hub grid itself.
- **Inside the tool**: the wizard header and step indicator use a **"Rounded Dark Glass"** treatment — same blur/saturate/radius recipe as every other glass tile in the hub (22px radius, `backdrop-filter: blur(16px) saturate(140%)`), but built on a dark slate fill (`#1c1f26`-based, theme-independent — same in light or dark mode) instead of the tinted-white glass used everywhere else. A small Lucide `lock` icon plus a "RESTRICTED ACCESS" label sits above the tool title; step indicators are pill-shaped and match the hub's existing badge language, just rendered light-on-dark.
- **Everything else in the wizard body** (search box, queue table, buttons, the Results table) stays on the **normal light/dark hub glass** — only the header chrome carries the distinct tone, so the tool still feels like part of the hub rather than a bolted-on separate app.

## Implementation Notes

- MFA reset has no bulk/single Graph endpoint — plan for enumerating and deleting per authentication-method-type. Flag this explicitly in the implementation plan as a step needing its own verification.
- Password generation must produce a value that satisfies Entra's default complexity policy; generate client-side, never log it anywhere except the final CSV.
- Retry must only touch the specific failed action(s) for a specific account — implementation should track state per (account, action) pair, not just a queue of accounts, so retry can target precisely.
- No dry-run/preview mode is in scope for this build (unlike Group Import) — the type-to-confirm gate is the deliberate-action safeguard instead. Not building a preview mode is intentional, not an oversight.

## Testing

Given the blast radius, this tool must be validated end-to-end against a small set of designated test/dummy accounts before any real incident use — the same discipline applied to the User Creation tool's first live test. This is a required step in the implementation plan, not optional polish.

## Out of Scope

- Teams webhook notification or FreshService ticket creation (deferred — see Accountability).
- Built-in second-person/dual-control approval workflow (approval is a process outside the tool).
- Dry-run/preview mode.
- Re-enabling a locked-down account or handing back the temp password — that's a separate future step/tool, not part of this one.
- Reusing any existing `GROUP_GATES` entry for access control.
