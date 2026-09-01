# User Creation — India Universal Security Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two universal India security groups (AVD Global O365 Access, P-SG-CAP-DeviceAccess) to every India-region account the User Creation tool creates, with a checkbox opt-out per batch and per-user Added/Skipped/Failed/N-A status columns in the exported `Credentials.csv`.

**Architecture:** `tools/user-creation/index.html` is a single-file browser tool with no build step and no test framework — client-side vanilla JS calling Microsoft Graph directly. This plan touches only that one file: (1) a new constant + state field for the two group IDs and their checkbox state, (2) a new "Security Groups" collapsible panel in the Step 2 markup, reusing the existing `.bulk-bar`/`.bulk-toggle-row`/`.tog` CSS classes already defined for "Bulk Settings" rather than adding new CSS, (3) an extension of the existing per-user group-add loop in `createUser()` to add the two groups and record a per-row result, and (4) two new trailing columns in `buildCredentialsCsv()`. Per `CLAUDE.md` and this tool's own prior plans (`docs/superpowers/plans/2026-07-31-user-creation-csv-error-detail.md`), verification is manual (open the file in a browser) plus a scratch Node harness for the pure Graph-call logic — there is no Jest/pytest-style suite to extend.

**Tech Stack:** Vanilla JS, HTML, CSS (no framework, no build step). Spec: `docs/superpowers/specs/2026-09-01-user-creation-india-security-groups-design.md`.

---

### Task 1: Add the group constant and state field

**Files:**
- Modify: `tools/user-creation/index.html:394-409` (`INDIA_GROUPS`/`US_GROUPS` constants)
- Modify: `tools/user-creation/index.html:430-436` (`st` object)

- [ ] **Step 1: Add `INDIA_UNIVERSAL_GROUPS`**

Find (right after the `US_GROUPS` constant closes):

```javascript
const US_GROUPS = {
  subContractor: "TBD_US_SUBCONTRACTOR_GROUP",
  teamMember:    "TBD_US_TEAM_MEMBER_GROUP",
  disableOutlook:"TBD_US_DISABLE_OUTLOOK_GROUP"
};
```

Add directly after it:

```javascript
// Universal India-only groups, added to every India-region account regardless
// of CSV content, unless unchecked in the Step 2 "Security Groups" panel.
// IDs are hardcoded (not resolved by display-name filter like INDIA_GROUPS)
// because the exact Object IDs are already known — skips a Graph round-trip
// and avoids a display-name filter matching the wrong group.
const INDIA_UNIVERSAL_GROUPS = {
  avdAccess:    { name: "AVD Global O365 Access", id: "70987d56-bc6d-4938-a7ec-b4fea45def92" },
  deviceAccess: { name: "P-SG-CAP-DeviceAccess",   id: "75e46ff9-bd5a-4121-8b74-f2934f7e8837" }
};
```

- [ ] **Step 2: Add `indiaUniversalGroups` to the `st` object**

Find:

```javascript
const st = {
  rows:    [],     // enriched row objects (see parseAndRender)
  region:  "India",
  skus:    {},     // { f3, f3archive, e3, appsEnt } — SkuId GUIDs
  groups:  {},     // { subContractor, teamMember, o365Login, internalEmail, disableOutlook } — Group IDs
  created: []      // rows that succeeded creation (with .password)
};
```

Change to:

```javascript
const st = {
  rows:    [],     // enriched row objects (see parseAndRender)
  region:  "India",
  skus:    {},     // { f3, f3archive, e3, appsEnt } — SkuId GUIDs
  groups:  {},     // { subContractor, teamMember, o365Login, internalEmail, disableOutlook } — Group IDs
  indiaUniversalGroups: { avdAccess: true, deviceAccess: true }, // Step 2 checkbox state, snapshotted at Step 3 start
  created: []      // rows that succeeded creation (with .password)
};
```

- [ ] **Step 3: Commit**

This is data-only with no visible effect until Task 2 adds the UI and Task 4 wires it into account creation. Leave staged and continue to Task 2 — commit together at the end of Task 2.

---

### Task 2: Add the "Security Groups" collapsible panel

**Files:**
- Modify: `tools/user-creation/index.html:278` (Step 2 markup, directly after the existing Bulk Settings `.bulk-bar` block)
- Modify: `tools/user-creation/index.html:765-769` (`setRegion`)
- Create (new function, place directly after `toggleBulk()`, currently ending at line 778): `toggleSecGroups()`

- [ ] **Step 1: Add the panel markup**

Find (end of the existing Bulk Settings block):

```html
            <button class="btn btn-primary" onclick="showBulkModal()">Apply to All →</button>
            <div class="bulk-note"><svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-2px"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg> Overwrites per-row values. Individual rows can still be adjusted after applying.</div>
          </div>
        </div>

        <!-- Review table -->
```

Change to:

```html
            <button class="btn btn-primary" onclick="showBulkModal()">Apply to All →</button>
            <div class="bulk-note"><svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-2px"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg> Overwrites per-row values. Individual rows can still be adjusted after applying.</div>
          </div>
        </div>

        <!-- Security Groups (India only) -->
        <div class="bulk-bar" id="secGroupsBar">
          <div class="bulk-header" onclick="toggleSecGroups()">
            <span id="secGroupsChevron" class="bulk-chevron">
              <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
            </span>
            <span class="bulk-title">Security Groups</span>
            <span class="bulk-subtitle">Universal India group assignments (on by default)</span>
          </div>
          <div class="bulk-body" id="secGroupsBody" style="display:none">
            <div class="bulk-field">
              <div class="bulk-toggle-row">
                <label class="tog"><input type="checkbox" id="secAvdAccess" checked/><div class="track"></div></label>
                <span>Add to AVD Global O365 Access</span>
              </div>
              <div class="bulk-toggle-row">
                <label class="tog"><input type="checkbox" id="secDeviceAccess" checked/><div class="track"></div></label>
                <span>Add to P-SG-CAP-DeviceAccess</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Review table -->
```

`secGroupsBar` has no inline `display:none` of its own — the default region is India (`st.region: "India"` in the `st` object), so the panel is visible on load, matching the Region toggle buttons which also default to India's button carrying the `active` class directly in markup.

- [ ] **Step 2: Add `toggleSecGroups()`**

Find:

```javascript
function toggleBulk() {
  const body    = document.getElementById("bulkBody");
  const chevron = document.getElementById("bulkChevron");
  const open    = body.style.display !== "none";
  body.style.display = open ? "none" : "flex";
  chevron.classList.toggle("open", !open);
}
```

Add directly after it:

```javascript

function toggleSecGroups() {
  const body    = document.getElementById("secGroupsBody");
  const chevron = document.getElementById("secGroupsChevron");
  const open    = body.style.display !== "none";
  body.style.display = open ? "none" : "flex";
  chevron.classList.toggle("open", !open);
}
```

- [ ] **Step 3: Gate panel visibility and reset checkboxes in `setRegion()`**

Find:

```javascript
function setRegion(r) {
  st.region = r;
  document.getElementById("modeIndia").classList.toggle("active", r === "India");
  document.getElementById("modeUS").classList.toggle("active",    r === "US");
}
```

Change to:

```javascript
function setRegion(r) {
  st.region = r;
  document.getElementById("modeIndia").classList.toggle("active", r === "India");
  document.getElementById("modeUS").classList.toggle("active",    r === "US");
  document.getElementById("secGroupsBar").style.display = r === "India" ? "block" : "none";
  if (r === "India") {
    document.getElementById("secAvdAccess").checked    = true;
    document.getElementById("secDeviceAccess").checked = true;
  }
}
```

Switching to US hides the panel entirely (these groups don't apply there); switching back to India resets both checkboxes to checked, so a tech can't accidentally carry an unchecked state across an India → US → India round-trip within the same session.

- [ ] **Step 4: Manually verify in a browser**

Open `tools/user-creation/index.html` directly in a browser (double-click, or `file://` path — no sign-in needed to view Step 1/2 markup; upload a valid CSV like `tools/user-creation/NewAccountsTemplate.csv` and click through to Step 2 to see the panel).

Expected:
- A "Security Groups" bar appears directly below "Bulk Settings", collapsed by default, subtitle reads "Universal India group assignments (on by default)".
- Clicking it expands to show two checked checkboxes: "Add to AVD Global O365 Access" and "Add to P-SG-CAP-DeviceAccess".
- Clicking the "US" region button hides the Security Groups bar entirely.
- Clicking "India" again shows it, and both checkboxes are checked (even if you unchecked one before switching to US).

If any of this doesn't match, fix before proceeding.

- [ ] **Step 5: Commit**

```bash
git add tools/user-creation/index.html
git commit -m "Add India universal security groups constant, state, and Step 2 UI panel"
```

---

### Task 3: Snapshot checkbox state at Step 3 start

**Files:**
- Modify: `tools/user-creation/index.html:896-902` (`createAccounts`, the `fetchSkus`/`resolveGroups` setup block)

- [ ] **Step 1: Read the checkboxes into `st.indiaUniversalGroups` before the per-row loop**

Find:

```javascript
  try {
    await fetchSkus();
    await resolveGroups();
  } catch(e) {
    showErr("s3Err", "Setup failed: " + ITTools.graph.friendlyError(e));
    return;
  }
```

Change to:

```javascript
  try {
    await fetchSkus();
    await resolveGroups();
  } catch(e) {
    showErr("s3Err", "Setup failed: " + ITTools.graph.friendlyError(e));
    return;
  }

  st.indiaUniversalGroups = {
    avdAccess:    document.getElementById("secAvdAccess").checked,
    deviceAccess: document.getElementById("secDeviceAccess").checked
  };
```

This mirrors how `resolveGroups()` already runs once at the top of `createAccounts()` to prep shared state before the per-row loop — the checkbox values are read once here, not re-read per row, since they are a batch-level setting for the whole run.

- [ ] **Step 2: Commit**

No visible effect until Task 4 reads `st.indiaUniversalGroups` inside `createUser()`. Leave staged and continue to Task 4 — commit together at the end of Task 4.

---

### Task 4: Extend `createUser()` group-add logic

**Files:**
- Modify: `tools/user-creation/index.html:993-1007` (`createUser`, the Graph-managed group-add block)

- [ ] **Step 1: Add the per-group universal-group loop**

Find:

```javascript
  setProgStatus(row.num, "Adding to security group…", "var(--muted)");
  const warnings  = [];
  const groupIds  = [row.subContractor ? st.groups.subContractor : st.groups.teamMember];
  if (row.internalEmail) groupIds.push(st.groups.disableOutlook);
  for (const gid of groupIds) {
    if (!gid) continue;
    try {
      await ITTools.graph.post(`/groups/${gid}/members/$ref`, {
        "@odata.id": `https://graph.microsoft.com/v1.0/directoryObjects/${userId}`
      });
    } catch(e) {
      warnings.push("security group add failed: " + ITTools.graph.friendlyError(e));
    }
  }
  return warnings;
}
```

Change to:

```javascript
  setProgStatus(row.num, "Adding to security group…", "var(--muted)");
  const warnings  = [];
  const groupIds  = [row.subContractor ? st.groups.subContractor : st.groups.teamMember];
  if (row.internalEmail) groupIds.push(st.groups.disableOutlook);
  for (const gid of groupIds) {
    if (!gid) continue;
    try {
      await ITTools.graph.post(`/groups/${gid}/members/$ref`, {
        "@odata.id": `https://graph.microsoft.com/v1.0/directoryObjects/${userId}`
      });
    } catch(e) {
      warnings.push("security group add failed: " + ITTools.graph.friendlyError(e));
    }
  }

  // Universal India groups: tracked per-group (not folded into groupIds above)
  // because each needs its own Added/Skipped/Failed/N-A result for the
  // Credentials.csv export (see buildCredentialsCsv).
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

  return warnings;
}
```

- [ ] **Step 2: Write a scratch Node harness to verify the logic**

Create `C:\Users\JOSHUA~1\AppData\Local\Temp\claude\C--dev\767580f2-0a2b-489a-a6cd-a11d230ff1d9\scratchpad\verify-universal-groups.js`. This reproduces just the new loop in isolation (the real file is browser-only — no DOM/Graph client available in Node — so this checks the logic is correct, not the live file):

```javascript
const INDIA_UNIVERSAL_GROUPS = {
  avdAccess:    { name: "AVD Global O365 Access", id: "70987d56-bc6d-4938-a7ec-b4fea45def92" },
  deviceAccess: { name: "P-SG-CAP-DeviceAccess",   id: "75e46ff9-bd5a-4121-8b74-f2934f7e8837" }
};

async function addUniversalGroups(row, region, checkboxState, graphPost, warnings) {
  if (region === "India") {
    for (const [key, grp] of Object.entries(INDIA_UNIVERSAL_GROUPS)) {
      if (!checkboxState[key]) { row[key + "Result"] = "Skipped"; continue; }
      try {
        await graphPost(grp.id);
        row[key + "Result"] = "Added";
      } catch (e) {
        row[key + "Result"] = "Failed";
        warnings.push(`${grp.name} add failed: ` + e.message);
      }
    }
  } else {
    for (const key of Object.keys(INDIA_UNIVERSAL_GROUPS)) row[key + "Result"] = "N/A";
  }
}

async function run() {
  // Case 1: India, both checked, both succeed → both "Added"
  let row = {}, warnings = [];
  await addUniversalGroups(row, "India", { avdAccess: true, deviceAccess: true }, async () => {}, warnings);
  console.assert(row.avdAccessResult === "Added" && row.deviceAccessResult === "Added" && warnings.length === 0,
    "Case 1 failed:", row, warnings);

  // Case 2: India, deviceAccess unchecked → avd "Added", device "Skipped"
  row = {}; warnings = [];
  await addUniversalGroups(row, "India", { avdAccess: true, deviceAccess: false }, async () => {}, warnings);
  console.assert(row.avdAccessResult === "Added" && row.deviceAccessResult === "Skipped" && warnings.length === 0,
    "Case 2 failed:", row, warnings);

  // Case 3: India, both checked, avd's Graph call throws → avd "Failed" (warning pushed), device "Added"
  row = {}; warnings = [];
  await addUniversalGroups(row, "India", { avdAccess: true, deviceAccess: true },
    async (id) => { if (id === INDIA_UNIVERSAL_GROUPS.avdAccess.id) throw new Error("object not found"); }, warnings);
  console.assert(row.avdAccessResult === "Failed" && row.deviceAccessResult === "Added" && warnings.length === 1,
    "Case 3 failed:", row, warnings);

  // Case 4: US region → both "N/A" regardless of checkbox state, no Graph calls, no warnings
  row = {}; warnings = [];
  await addUniversalGroups(row, "US", { avdAccess: true, deviceAccess: true }, async () => {}, warnings);
  console.assert(row.avdAccessResult === "N/A" && row.deviceAccessResult === "N/A" && warnings.length === 0,
    "Case 4 failed:", row, warnings);

  console.log("All 4 cases passed.");
}

run();
```

Run: `/c/dev/tools/nodejs/node.exe verify-universal-groups.js` (from the scratchpad directory)
Expected output: `All 4 cases passed.` with no assertion failures printed above it.

- [ ] **Step 3: Commit**

```bash
git add tools/user-creation/index.html
git commit -m "Add universal India group assignment with per-row result tracking"
```

---

### Task 5: Add the two CSV result columns

**Files:**
- Modify: `tools/user-creation/index.html:1159-1166` (`buildCredentialsCsv`)

- [ ] **Step 1: Add the two trailing columns**

Find:

```javascript
function buildCredentialsCsv() {
  const lines = ["DisplayName,UPN,TempPassword"];
  st.created.forEach(r => {
    const display = `${r.fn} ${r.ln}`.replace(/,/g, "");
    lines.push(`${display},${r.upn},${r.password}`);
  });
  return lines.join("\r\n");
}
```

Change to:

```javascript
function buildCredentialsCsv() {
  const lines = ["DisplayName,UPN,TempPassword,AVD Global O365 Access,P-SG-CAP-DeviceAccess"];
  st.created.forEach(r => {
    const display = `${r.fn} ${r.ln}`.replace(/,/g, "");
    lines.push(`${display},${r.upn},${r.password},${r.avdAccessResult},${r.deviceAccessResult}`);
  });
  return lines.join("\r\n");
}
```

Both `downloadCredentialsCsv()` (direct-download path) and `downloadZip()` (ZIP path) call `buildCredentialsCsv()` directly — no other call site changes needed.

- [ ] **Step 2: Manually verify in a browser**

Open `tools/user-creation/index.html`, sign in, and run a real (or test) India-mode account creation through to Step 4 — or, if you don't want to create a live account right now, temporarily set a breakpoint / `console.log(buildCredentialsCsv())` after a creation run and inspect the string before downloading.

Expected: the CSV header row reads
`DisplayName,UPN,TempPassword,AVD Global O365 Access,P-SG-CAP-DeviceAccess`
and each data row has 5 comma-separated values, with the last two being `Added`, `Skipped`, `Failed`, or `N/A` per the Task 4 logic.

- [ ] **Step 3: Commit**

```bash
git add tools/user-creation/index.html
git commit -m "Add per-group result columns to Credentials.csv export"
```

---

## Out of Scope

- No duplicate/delta-checking step against existing group membership — confirmed with Josh during brainstorming that this isn't needed for brand-new accounts (see spec, "Explicitly out of scope").
- No per-row checkbox override — batch-level only, per Josh's explicit choice during brainstorming ("Lets do 1 for now").
- No change to the existing `subContractor`/`teamMember`/`disableOutlook` group-add block, its shared warning message, or its CSV representation (they don't get their own columns).
- No change to US-mode group logic — `US_GROUPS` and its `TBD_*` placeholders are untouched.
