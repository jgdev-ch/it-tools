# User Creation — CSV Error Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the CSV validation error count in the User Creation tool's Step 1 with a table listing every failing row (spreadsheet row number, name, EID, and reason), so a user can locate and fix bad rows without guesswork.

**Architecture:** `tools/user-creation/index.html` is a single-file browser tool with no build step and no test framework — validation happens client-side in vanilla JS against Microsoft Graph. This plan makes two changes in that file: (1) renumber `row.num` to match the literal spreadsheet row (header = row 1), and (2) add a `renderCsvErrorTable()` function wired into the existing error paths, reusing the `.review-tbl` CSS class already defined for the Step 2 review table. There is no automated test suite for this tool (per `CLAUDE.md`, UI changes are verified by exercising the feature in a browser) — verification steps below use a scratch CSV file opened directly in the browser, which does not require Graph sign-in because rows with hard validation errors are never sent to Graph.

**Tech Stack:** Vanilla JS, HTML, CSS (no framework, no build step). Spec: `docs/superpowers/specs/2026-07-31-user-creation-csv-error-detail-design.md`.

---

### Task 1: Renumber rows to match the spreadsheet row number

**Files:**
- Modify: `tools/user-creation/index.html:569` (inside `parseAndRender`, the `st.rows = parsed.rows.map(...)` block)

- [ ] **Step 1: Change the row numbering**

Find this line (currently reads `num: i + 1,`):

```javascript
    return {
      num:             i + 1,
      fn, ln,
```

Change it to:

```javascript
    return {
      num:             i + 2,
      fn, ln,
```

`parsed.rows` contains only data rows (the CSV header is already stripped by `ITTools.csv.parse`), so index `0` is the first data row. In the source file, row 1 is the header and row 2 is that first data row — `i + 2` makes `row.num` equal to the literal row a user would jump to in Excel/Sheets, instead of counting data rows only.

- [ ] **Step 2: Commit**

This is a data-only change with no visible effect until Task 2 adds a place to display `row.num` for error rows (the Step 2 review table already shows `row.num`, but that table isn't reachable while hard errors exist). Commit alongside Task 2 instead of separately — leave this change staged for now and continue to Task 2.

---

### Task 2: Add the CSV errors table

**Files:**
- Modify: `tools/user-creation/index.html:190` (Step 1 markup, add table container)
- Modify: `tools/user-creation/index.html:432-438` (`showErr`, clear the new table when the banner is cleared or replaced with a non-list message)
- Modify: `tools/user-creation/index.html:596-598` (`parseAndRender`, hard-error branch)
- Modify: `tools/user-creation/index.html:629-632` (`checkUpns`, error branch)
- Create (new function, place near `showErr`, e.g. after line 438): `renderCsvErrorTable(rows)`

- [ ] **Step 1: Add the table container to the Step 1 markup**

Find (Step 1 section, right after the existing banner):

```html
        <div class="banner error" id="s1Err" style="display:none"></div>
```

Change to:

```html
        <div class="banner error" id="s1Err" style="display:none"></div>
        <div id="s1ErrTable"></div>
```

- [ ] **Step 2: Write `renderCsvErrorTable()`**

Add this function directly after `showErr` (after line 438):

```javascript
function renderCsvErrorTable(rows) {
  const container = document.getElementById("s1ErrTable");
  if (!container) return;
  const bad = rows.filter(r => r.err);
  if (!bad.length) {
    container.innerHTML = "";
    return;
  }
  container.innerHTML = `
    <table class="review-tbl" style="width:100%;border-collapse:collapse;margin-bottom:14px">
      <thead>
        <tr><th>Row</th><th>Name</th><th>EID</th><th>Error</th></tr>
      </thead>
      <tbody>
        ${bad.map(r => `
          <tr class="row-err">
            <td style="color:var(--muted);font-size:12px">${r.num}</td>
            <td>${(r.fn + " " + r.ln).trim() || "—"}</td>
            <td style="color:var(--muted);font-size:12px">${r.eid || "—"}</td>
            <td>${r.err}</td>
          </tr>
        `).join("")}
      </tbody>
    </table>
  `;
}
```

Row content (`fn`, `ln`, `eid`) is inserted the same way the existing Step 2 review table already renders it (`index.html:657-659`, unescaped) — this matches existing convention in this file rather than introducing a new pattern.

- [ ] **Step 3: Clear the table whenever the banner is cleared elsewhere**

Find `showErr` (line 432-438):

```javascript
function showErr(id, msg) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = msg;
  el.className = "banner error";
  el.style.display = msg ? "block" : "none";
}
```

Change to:

```javascript
function showErr(id, msg) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = msg;
  el.className = "banner error";
  el.style.display = msg ? "block" : "none";
  if (id === "s1Err") {
    const t = document.getElementById("s1ErrTable");
    if (t) t.innerHTML = "";
  }
}
```

This means every existing call to `showErr("s1Err", ...)` — wrong file type, CSV parse failure, missing columns, AV-scan timeout, `clearFile()` — clears the table automatically with no other call sites needing changes. The two call sites that need the table populated (Step 4 below) call `renderCsvErrorTable()` immediately after their `showErr()` call, which repopulates it.

- [ ] **Step 4: Wire the table into the two hard-error branches**

Find in `parseAndRender` (line 596-598):

```javascript
  if (hardErrors) {
    showErr("s1Err", hardErrors + " row(s) have errors — fix the CSV and re-upload.");
  } else {
```

Change to:

```javascript
  if (hardErrors) {
    showErr("s1Err", hardErrors + " row(s) have errors — fix the CSV and re-upload.");
    renderCsvErrorTable(st.rows);
  } else {
```

Find in `checkUpns` (line 629-632):

```javascript
  if (errors > 0) {
    document.getElementById("s1Btn").disabled = true;
    document.getElementById("s1Msg").textContent = "";
    showErr("s1Err", errors + " row(s) have errors — fix the CSV and re-upload.");
  } else {
```

Change to:

```javascript
  if (errors > 0) {
    document.getElementById("s1Btn").disabled = true;
    document.getElementById("s1Msg").textContent = "";
    showErr("s1Err", errors + " row(s) have errors — fix the CSV and re-upload.");
    renderCsvErrorTable(st.rows);
  } else {
```

- [ ] **Step 5: Create a scratch test CSV**

Create `C:\Users\JOSHUA~1\AppData\Local\Temp\claude\C--dev\17de4b31-2e09-4276-9f2a-e450c415e93b\scratchpad\bad-rows-test.csv` with one valid row and four rows that each trip a different validation rule:

```csv
EID,Firstname,Lastname,UserPrincipalName,RequiredMailboxSize,InternalEmailOnly,EntApps,Designation,City,Province,Country,Office,SubContractor
10001,Reddy,Teja,Reddy.Teja@corrohealth.com,50 GB,Y,N,Medical Coder,Hyderabad,Telangana,India,HYD,N
10002,,Sharma,Priya.Sharma@corrohealth.com,2 GB,Y,N,Data Analyst,Chennai,Tamil Nadu,India,MAA,N
10003,Arjun,Nair,arjun.nair.corrohealth.com,E3,N,Y,Team Lead,Bengaluru,Karnataka,India,BLR,N
10004,Sanjay,Kumar,Sanjay.Kumar@corrohealth.com,1 GB,Y,N,QA Specialist,Mumbai,Maharashtra,India,BOM,Y
12345678901234567,Meera,Iyer,Meera.Iyer@corrohealth.com,E3,N,Y,Analyst,Pune,Maharashtra,India,PNQ,N
```

This file is scratch-only (not part of the repo) — it stays out of `tools/user-creation/`.

Expected failing rows and why (data row index → spreadsheet row via `i + 2`):
- Spreadsheet row 3 (`Sharma`, blank first name) → "Missing first or last name"
- Spreadsheet row 4 (`Arjun Nair`, malformed UPN) → "UPN format invalid"
- Spreadsheet row 5 (`Sanjay Kumar`, `1 GB`) → "RequiredMailboxSize must be 2 GB, 50 GB, or E3"
- Spreadsheet row 6 (`Meera Iyer`, 17-character EID) → "EID must be 16 characters or fewer (Entra employeeId limit)"

- [ ] **Step 6: Manually verify in a browser**

Open `tools/user-creation/index.html` directly in a browser (double-click, or `file://` path — no dev server or sign-in needed since hard-error rows never reach the Graph UPN check).

Upload `bad-rows-test.csv` via drag-and-drop or the file browser.

Expected result:
- Red banner reads "4 row(s) have errors — fix the CSV and re-upload."
- A table appears directly below it with exactly 4 rows, matching the spreadsheet row numbers and reasons listed in Step 5 above.
- "Continue →" stays disabled.
- Click the "×" clear button on the loaded file, then re-upload the original unmodified `NewAccountsTemplate.csv` (`tools/user-creation/NewAccountsTemplate.csv`) — the banner and table both disappear, since all 4 rows in that file are valid.

If any row number, name, or reason doesn't match, fix the code before proceeding — do not commit with a failing manual check.

- [ ] **Step 7: Commit**

```bash
git add tools/user-creation/index.html
git commit -m "Show per-row detail for CSV validation errors instead of just a count"
```

---

## Out of Scope

- No change to the block-until-fixed gating behavior — hard errors still prevent proceeding to Step 2.
- No change to warning handling (UPN-already-exists) — unaffected, still surfaced only in the Step 2 review table.
- No HTML-escaping added for CSV-sourced fields — matches the existing unescaped rendering already used in the Step 2 review table (`index.html:657-659`); not introduced or worsened by this change.
