# User Creation Tool — India Universal Security Groups
**Date:** 2026-09-01
**Status:** Approved
**Builds on:** `docs/superpowers/specs/2026-05-19-user-creation-design.md` (Steps 1–4, region handling, Graph-managed group logic)

## Overview

Every India-region account created by the User Creation tool needs to be added to two additional Entra security groups that are universal standards for the India team, on top of the existing `subContractor`/`teamMember`/`disableOutlook` groups:

| Group | Object ID |
|---|---|
| AVD Global O365 Access | `70987d56-bc6d-4938-a7ec-b4fea45def92` |
| P-SG-CAP-DeviceAccess | `75e46ff9-bd5a-4121-8b74-f2934f7e8837` |

These are near-universal for India hires, but a checkbox opt-out is kept as a failsafe for the rare exception, rather than hardcoding them as unconditional.

**Explicitly out of scope:** no duplicate/delta-checking step against existing group membership — these are brand-new accounts, so there is nothing to reconcile against at creation time.

## Data & Constants

`tools/user-creation/index.html`, near the existing `INDIA_GROUPS` constant:

```js
const INDIA_UNIVERSAL_GROUPS = {
  avdAccess:    { name: "AVD Global O365 Access", id: "70987d56-bc6d-4938-a7ec-b4fea45def92" },
  deviceAccess: { name: "P-SG-CAP-DeviceAccess",   id: "75e46ff9-bd5a-4121-8b74-f2934f7e8837" }
};
```

Object IDs are hardcoded directly — unlike `INDIA_GROUPS`, which resolves group IDs at runtime via a Graph display-name filter (`resolveGroups()`), these two skip that lookup entirely since the exact IDs are already known. One less Graph round-trip, and no risk of a display-name filter matching the wrong group.

State (`st` object): add `indiaUniversalGroups: { avdAccess: true, deviceAccess: true }`. Reset to `{ true, true }` whenever region is switched to India (mirrors how other India-only state should behave on region change).

## UI: Step 2, new "Security Groups" collapsible panel

A second collapsible bar, styled and behaving identically to the existing "Bulk Settings" panel (same header/chevron/expand-collapse pattern via `toggleBulk()`-style logic), placed directly after it:

```
▸ Bulk Settings
  Apply the same license & flags to all users at once

▸ Security Groups
  Universal India group assignments (on by default)
    ☑ Add to AVD Global O365 Access
    ☑ Add to P-SG-CAP-DeviceAccess
```

- Both checkboxes default to checked.
- The entire "Security Groups" panel only renders when `st.region === "India"` — it is hidden when Region is toggled to US, since these groups don't apply there. No disabled/greyed-out state; it simply isn't shown.
- Unchecking a box before continuing to Step 3 means that group is skipped for **every** row in the batch (batch-level flag, not per-row — matches how these groups are described as a near-universal standard, and keeps the UI simple until a real per-row need shows up).

## Group-add logic: Step 3, `createUser()`

Extends the existing non-fatal group-add block (`tools/user-creation/index.html`, ~line 993–1004). The existing loop adds `subContractor`/`teamMember`/`disableOutlook` from a plain array of group IDs with one shared, generic warning message. For the two universal groups we need a **per-group, per-row result** (to populate the CSV columns below), so those two are tracked individually rather than folded into the same anonymous array:

```js
if (st.region === "India") {
  for (const [key, grp] of Object.entries(INDIA_UNIVERSAL_GROUPS)) {
    if (!st.indiaUniversalGroups[key]) { row[key + "Result"] = "Skipped"; continue; }
    try {
      await ITTools.graph.post(`/groups/${grp.id}/members/$ref`, {
        "@odata.id": `https://graph.microsoft.com/v1.0/directoryObjects/${userId}`
      });
      row[key + "Result"] = "Added";
    } catch(e) {
      row[key + "Result"] = "Failed";
      warnings.push(`${grp.name} add failed: ` + ITTools.graph.friendlyError(e));
    }
  }
} else {
  for (const key of Object.keys(INDIA_UNIVERSAL_GROUPS)) row[key + "Result"] = "N/A";
}
```

This runs alongside (not instead of) the existing `subContractor`/`teamMember`/`disableOutlook` loop, which is untouched — those three still share the generic warning message since they don't get their own CSV columns. A failed add on either universal group still surfaces as a warning on that row and does not discard the created account, matching the existing non-fatal pattern.

`row.avdAccessResult` / `row.deviceAccessResult` end up one of: `"Added"`, `"Skipped"` (checkbox was unchecked for the batch), `"Failed"` (Graph error — detail is in the row's warning text), or `"N/A"` (US region, group doesn't apply).

## CSV export: two new result columns

`buildCredentialsCsv()` (`tools/user-creation/index.html`, ~line 1159) currently emits `DisplayName,UPN,TempPassword`. Add two trailing columns so a tech can see, per newly created user, whether each universal group add actually succeeded — without having to scroll back through the Step 3 progress list:

```js
function buildCredentialsCsv() {
  const lines = ["DisplayName,UPN,TempPassword,AVD Global O365 Access,P-SG-CAP-DeviceAccess"];
  st.created.forEach(r => {
    const display = `${r.fn} ${r.ln}`.replace(/,/g, "");
    lines.push(`${display},${r.upn},${r.password},${r.avdAccessResult},${r.deviceAccessResult}`);
  });
  return lines.join("\r\n");
}
```

Both the ZIP path and the direct-download path (`downloadCredentialsCsv()`) share this function, so both pick up the new columns automatically — no separate change needed for either.

## Testing Notes

- Verify both checkboxes default checked, and the panel disappears on toggling to US region and reappears (reset to checked) on toggling back to India.
- Verify an India-mode account created with both boxes checked ends up in `subContractor`/`teamMember` (as today) plus both universal groups.
- Verify unchecking one box before Step 3 results in that group being skipped for all rows in the batch, with the other group and existing groups unaffected.
- Verify the exported `Credentials.csv` (both the ZIP path and the direct-download path) has the two new trailing columns populated with the correct value (`Added`/`Skipped`/`Failed`/`N/A`) for every row in `st.created`.
- No live-test path exists for a failed add on these two groups specifically (would require simulating a Graph error) — rely on the existing shared try/catch already proven for `disableOutlook`.
