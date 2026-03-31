# Guest Audit — CorroHealth Account Match & Email Tooltip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CorroHealth account match column to the Guest Access Audit table, and add hover tooltips to truncated UPN and Company cells.

**Architecture:** All changes live in `tools/guest-audit/index.html`. The scan gains a second phase that batch-queries Graph for matching `@corrohealth.com` member accounts (20 per batch request). Results are stored on each guest object and rendered into a new table column. Tooltips are pure CSS via `[data-tooltip]` attribute.

**Tech Stack:** Vanilla JS, `ITTools.graph.post()` for batch, CSS pseudo-elements for tooltips, existing `graphWithRetry()` for rate-limit safety.

---

## File Map

| File | Change |
|---|---|
| `tools/guest-audit/index.html` | All changes — CSS, JS logic, table rendering, CSV |

---

## Task 1: CSS — Tooltip styles and column width update

**Files:**
- Modify: `tools/guest-audit/index.html` (the `<style>` block, lines ~9–186)

The Actions column currently uses `nth-child(9)`. Insert CorroHealth as the new col 9 and shift Actions to col 10.

- [ ] **Step 1: Update the Actions column nth-child selector and add CorroHealth column width**

Find this line in the `<style>` block:
```css
  table th:nth-child(9), table td:nth-child(9) { width: 148px; }      /* Actions */
```

Replace with:
```css
  table th:nth-child(9), table td:nth-child(9)   { width: 100px; }      /* CorroHealth Acct */
  table th:nth-child(10), table td:nth-child(10) { width: 148px; }      /* Actions */
```

- [ ] **Step 2: Add the CSS tooltip rule**

After the `.row-error` rule (around line 107), add:

```css
  /* ── Tooltip ── */
  [data-tooltip] { position: relative; }
  [data-tooltip]::after {
    content: attr(data-tooltip);
    position: absolute; bottom: calc(100% + 6px); left: 50%;
    transform: translateX(-50%);
    background: #1e1e2e; color: #f0f0f0;
    font-size: 11px; padding: 4px 8px; border-radius: 5px;
    white-space: nowrap; pointer-events: none;
    opacity: 0; transition: opacity .12s;
    z-index: 50;
  }
  [data-tooltip]:hover::after { opacity: 1; }
```

- [ ] **Step 3: Verify in browser**

Open `tools/guest-audit/index.html` in the browser. Before running a scan, confirm the page loads without console errors.

- [ ] **Step 4: Commit**

```bash
cd /c/dev/projects/it-tools
git add tools/guest-audit/index.html
git commit -m "style(guest-audit): add tooltip CSS and shift Actions to col 10"
```

---

## Task 2: UPN parser + corroMatch initialization

**Files:**
- Modify: `tools/guest-audit/index.html` (JS section, after the `esc()` function and inside `runScan()`)

- [ ] **Step 1: Add `parseCorroUpn()` function**

After the `esc()` function (around line 281), add:

```js
function parseCorroUpn(upn) {
  if (!upn.includes("#EXT#")) return null;
  const localPart = upn.split("#EXT#")[0]; // e.g. "john.smith_gmail.com"
  const namePart  = localPart.split("_")[0]; // e.g. "john.smith"
  if (!namePart) return null;
  return namePart + "@corrohealth.com";
}
```

- [ ] **Step 2: Initialize `corroMatch` on each guest object in `runScan()`**

Inside the `.map(u => { ... })` block in `runScan()` (around line 484), the return object currently ends with `threshold,`. Add `corroMatch` to the end of that object:

```js
    return {
      id:            u.id,
      displayName:   u.displayName || "",
      upn:           u.userPrincipalName || "",
      companyName:   u.companyName || "",
      department:    u.department || "",
      accountEnabled: u.accountEnabled !== false,
      licenseCount:  (u.assignedLicenses || []).length,
      lastSignIn,
      daysInactive,
      created,
      createdDaysAgo,
      isNever,
      isStale,
      isLicensed,
      isOldInvite,
      threshold,
      corroMatch: { found: null, displayName: null, accountEnabled: null, pending: true },
    };
```

- [ ] **Step 3: Verify in browser console**

Run a scan. In DevTools console, type `allGuests[0].corroMatch`. Expected output:
```
{found: null, displayName: null, accountEnabled: null, pending: true}
```

Also verify: `parseCorroUpn("john.smith_gmail.com#EXT#@corrohealth.onmicrosoft.com")` → `"john.smith@corrohealth.com"`

And: `parseCorroUpn("john.smith@corrohealth.com")` → `null`

- [ ] **Step 4: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat(guest-audit): add parseCorroUpn helper and corroMatch init on guest objects"
```

---

## Task 3: Graph batch lookup function

**Files:**
- Modify: `tools/guest-audit/index.html` (JS section, after `cancelScan()`)

- [ ] **Step 1: Add `fetchCorroMatches()` function**

After the `cancelScan()` function (around line 362), add:

```js
async function fetchCorroMatches(guests) {
  const eligible = guests.filter(g => parseCorroUpn(g.upn) !== null);
  const total    = eligible.length;
  if (!total) return;

  let done = 0;
  for (let i = 0; i < eligible.length; i += 20) {
    if (_cancelled) return;

    const batch    = eligible.slice(i, i + 20);
    const requests = batch.map((g, idx) => ({
      id:     String(idx),
      method: "GET",
      url:    `/users/${encodeURIComponent(parseCorroUpn(g.upn))}?$select=id,displayName,userPrincipalName,accountEnabled`,
    }));

    try {
      const res = await graphWithRetry(() =>
        ITTools.graph.post("https://graph.microsoft.com/v1.0/$batch", { requests })
      );
      for (const resp of (res?.responses || [])) {
        const g = batch[parseInt(resp.id, 10)];
        if (!g) continue;
        if (resp.status === 200) {
          g.corroMatch = { found: true,  displayName: resp.body.displayName, accountEnabled: resp.body.accountEnabled, pending: false };
        } else {
          g.corroMatch = { found: false, displayName: null, accountEnabled: null, pending: false };
        }
      }
    } catch(e) {
      for (const g of batch) {
        g.corroMatch = { found: false, displayName: null, accountEnabled: null, pending: false };
      }
    }

    done += batch.length;
    setPhase(`Checking CorroHealth accounts… (${done}/${total})`);
  }

  // Clear any remaining pending flags (covers cancelled mid-batch + ineligible guests)
  for (const g of guests) {
    if (g.corroMatch.pending) g.corroMatch.pending = false;
  }
}
```

- [ ] **Step 2: Verify function exists in browser**

In DevTools console type `typeof fetchCorroMatches`. Expected: `"function"`

- [ ] **Step 3: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat(guest-audit): add fetchCorroMatches batch Graph lookup function"
```

---

## Task 4: Wire batch into runScan()

**Files:**
- Modify: `tools/guest-audit/index.html` (inside `runScan()`, around lines 504–508)

Currently `runScan()` ends with:
```js
  if (_cancelled) { setPhase(null); return; }
  renderStats(allGuests, threshold);
  renderTable(allGuests);
  setPhase(null);
```

- [ ] **Step 1: Replace the tail of `runScan()` to call fetchCorroMatches and re-render**

Replace those four lines with:

```js
  if (_cancelled) { setPhase(null); return; }
  renderStats(allGuests, threshold);
  renderTable(allGuests);                          // first render — CorroHealth cells show spinner

  await fetchCorroMatches(allGuests);              // second phase — batch Graph lookups
                                                   // (fetchCorroMatches clears all pending flags on return,
                                                   //  even if cancelled mid-batch)
  renderTable(allGuests);                          // always re-render — clears spinners, shows partial results on cancel
  setPhase(null);
```

- [ ] **Step 2: Verify in browser**

Run a scan. Observe the phase line shows:
1. `"Fetching guest accounts…"`
2. `"Checking CorroHealth accounts… (20/N)"` (or similar)
3. Phase line disappears when complete

After scan, open DevTools console and type `allGuests[0].corroMatch`. Confirm `pending: false` and `found` is `true` or `false`.

- [ ] **Step 3: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat(guest-audit): wire fetchCorroMatches into runScan with double render"
```

---

## Task 5: Table rendering — column, risk badge, sort, tooltips

**Files:**
- Modify: `tools/guest-audit/index.html` (JS section — `riskBadges`, `sortGuests`, `renderTable`)

- [ ] **Step 1: Add `corroMatchCell()` render helper**

After the `ageBadge()` function (around line 553), add:

```js
function corroMatchCell(g) {
  const m = g.corroMatch;
  if (m.pending)         return `<div class="spinner" style="width:14px;height:14px;border-width:2px;margin:auto"></div>`;
  if (m.found === null)  return `<span style="color:var(--muted2)">—</span>`;
  if (!m.found)          return `<span style="color:var(--muted2)">None</span>`;
  if (!m.accountEnabled) return `<span class="pill-active" style="background:var(--amber-light);color:var(--amber)">Disabled</span>`;
  return `<span class="pill-active">Matched</span>`;
}
```

- [ ] **Step 2: Add "Internal account exists" risk badge in `riskBadges()`**

In `riskBadges()`, after the last `if (g.isOldInvite)` line, add:

```js
  if (g.corroMatch?.found === true) html += `<span class="risk-badge risk-licensed">Internal account exists</span>`;
```

- [ ] **Step 3: Add corroMatch sort in `sortGuests()`**

In `sortGuests()`, after the `if (sortCol === "accountEnabled")` block (around line 522), add:

```js
    if (sortCol === "corroMatch") {
      function corroVal(g) {
        if (g.corroMatch.pending)            return -1;
        if (g.corroMatch.found === null)     return -1;
        if (g.corroMatch.found === false)    return  0;
        if (!g.corroMatch.accountEnabled)    return  1;
        return 2;
      }
      return sortDir * (corroVal(b) - corroVal(a));
    }
```

- [ ] **Step 4: Add data-tooltip to UPN and Company cells in `renderTable()`**

In the `rows` template inside `renderTable()`, make these two changes:

**UPN tooltip** — find the `.user-upn` div:
```js
            <div class="user-upn">${esc(g.upn)}</div>
```
Replace with:
```js
            <div class="user-upn" data-tooltip="${esc(g.upn)}">${esc(g.upn)}</div>
```

**Company tooltip** — find the Company `<td>`:
```js
      <td>${g.companyName ? esc(g.companyName) : `<span style="color:var(--muted2)">—</span>`}</td>
```
Replace with:
```js
      <td${g.companyName ? ` data-tooltip="${esc(g.companyName)}"` : ""}>${g.companyName ? esc(g.companyName) : `<span style="color:var(--muted2)">—</span>`}</td>
```

- [ ] **Step 5: Add CorroHealth Acct column header and cell to `renderTable()`**

In the `thBtn` calls inside `renderTable()`, find:
```js
            ${thBtn("accountEnabled","Account")}
            <th>Actions</th>
```
Replace with:
```js
            ${thBtn("accountEnabled","Account")}
            ${thBtn("corroMatch","CorroHealth Acct")}
            <th>Actions</th>
```

In the `rows` template, find the Account cell followed by the Actions cell:
```js
      <td id="acct-${g.id}">${g.accountEnabled ? `<span class="pill-active">Active</span>` : `<span class="pill-disabled">Disabled</span>`}</td>
      <td>
        <div style="display:flex;gap:6px;flex-wrap:wrap">
```
Add the CorroHealth cell between them:
```js
      <td id="acct-${g.id}">${g.accountEnabled ? `<span class="pill-active">Active</span>` : `<span class="pill-disabled">Disabled</span>`}</td>
      <td style="text-align:center">${corroMatchCell(g)}</td>
      <td>
        <div style="display:flex;gap:6px;flex-wrap:wrap">
```

- [ ] **Step 6: Verify in browser**

Run a full scan. Confirm:
- CorroHealth Acct column appears between Account and Actions
- Spinner shows in CorroHealth cells during the second phase, then resolves to Matched / None / —
- Hovering a long UPN in the Guest cell shows the full email in a dark tooltip
- Hovering a truncated Company name shows the full name
- Clicking "CorroHealth Acct" column header sorts — matched rows float to top
- Guests with a match show a blue "Internal account exists" risk badge in the Guest cell

- [ ] **Step 7: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat(guest-audit): add CorroHealth Acct column, risk badge, sort, and UPN/Company tooltips"
```

---

## Task 6: CSV export — add CorroHealth columns

**Files:**
- Modify: `tools/guest-audit/index.html` (inside `exportCsv()`, around line 683)

- [ ] **Step 1: Add two new columns to the CSV row mapper in `exportCsv()`**

Inside the `.map(g => ({ ... }))` call in `exportCsv()`, after the `"Risk Signals"` entry, add:

```js
      "CorroHealth Account":        g.corroMatch.found === true  ? "Matched"
                                  : g.corroMatch.found === false ? "None"
                                  : "—",
      "CorroHealth Account Status": g.corroMatch.found === true && g.corroMatch.accountEnabled === true  ? "Active"
                                  : g.corroMatch.found === true && g.corroMatch.accountEnabled === false ? "Disabled"
                                  : "—",
```

- [ ] **Step 2: Verify in browser**

Run a scan and click "Export CSV". Open the file in Excel or a text editor. Confirm:
- Two new columns appear at the end: `CorroHealth Account` and `CorroHealth Account Status`
- Matched rows show `Matched` / `Active` or `Disabled`
- Unmatched rows show `None` / `—`
- Rows with no `#EXT#` UPN show `—` / `—`

- [ ] **Step 3: Commit**

```bash
git add tools/guest-audit/index.html
git commit -m "feat(guest-audit): add CorroHealth Account columns to CSV export"
```

---

## Task 7: Push to preview

- [ ] **Step 1: Push testing branch to trigger preview deploy**

```bash
git push
```

- [ ] **Step 2: Verify preview site**

Open `https://jgdev-ch.github.io/it-tools-preview/tools/guest-audit/` (wait ~60s for GitHub Actions). Run a scan and confirm all features work end-to-end with real Graph data.
