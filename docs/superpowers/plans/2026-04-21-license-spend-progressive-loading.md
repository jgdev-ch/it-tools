# License Spend Progressive Loading — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `loadDashboard()` into two rendering stages so the License Spend dashboard displays immediately after user analysis, then progressively refines inactive-cost figures and populates tables as audit-log batches complete.

**Architecture:** Stage 1 fires after step 3 (in-memory user processing) — renders the full dashboard shape with exact values where possible and "Refining" badges on audit-dependent KPI cards plus shimmer skeleton rows in both tables. Stage 2 runs the existing audit batch loop, calling `updateBatchProgress()` after each batch to tick the progress bar and update KPI values in-place. `finaliseDashboard()` replaces skeletons with real table rows and clears badges when all batches complete.

**Tech Stack:** Vanilla JS, HTML/CSS — single file `tools/finance-dashboard/index.html`. No new dependencies.

---

## File Map

| File | Change |
|---|---|
| `tools/finance-dashboard/index.html` | All changes — CSS additions, HTML additions, new JS functions, `loadDashboard()` refactor |

---

### Task 1: Add CSS — shimmer, badges, step tracker, progress bar

**Files:**
- Modify: `tools/finance-dashboard/index.html` — local `<style>` block

Add the following CSS block to the local `<style>` tag, immediately before the `/* ══ PRINT / PDF ══ */` comment (around line 308). This block introduces all new visual primitives needed by later tasks.

- [ ] **Step 1: Insert CSS block**

Find this line in `<style>`:
```css
  /* ══════════════════════════════════════════════════════
     PRINT / PDF
  ══════════════════════════════════════════════════════ */
```

Insert the following block immediately before it:

```css
  /* ── Progressive loading — shimmer skeleton ── */
  @keyframes shimmer {
    0%   { background-position: -200% 0; }
    100% { background-position:  200% 0; }
  }
  .skel {
    border-radius: var(--radius-xs);
    background: linear-gradient(90deg, var(--surface2) 25%, var(--surface3) 50%, var(--surface2) 75%);
    background-size: 200% 100%;
    animation: shimmer 1.4s ease-in-out infinite;
    display: block;
  }
  .skel-sm { height: 10px; width: 55%; margin-top: 5px; }
  .skel-md { height: 13px; width: 80%; }
  .skel-lg { height: 16px; width: 90%; }

  /* ── Refine / Confirmed badge (injected onto KPI cards during fine-tune pass) ── */
  .refine-badge {
    position: absolute; top: 6px; right: 6px;
    display: inline-flex; align-items: center; gap: 3px;
    background: var(--amber-light); color: var(--amber);
    border: 1px solid var(--amber-border);
    border-radius: 20px; padding: 1px 7px;
    font-size: 9px; font-weight: 700;
    pointer-events: none;
    transition: opacity .4s, background .2s, color .2s, border-color .2s;
  }
  .refine-badge .badge-spin {
    width: 8px; height: 8px;
    border: 1.5px solid currentColor; border-top-color: transparent;
    border-radius: 50%; animation: spin .7s linear infinite; flex-shrink: 0;
  }
  .refine-badge.confirmed {
    background: var(--green-light); color: var(--green);
    border-color: var(--green-border);
  }
  .refine-badge.fade-out { opacity: 0; }

  /* ── Step tracker ── */
  .step-tracker {
    display: none;
    align-items: center;
    background: var(--surface); border: 1px solid var(--border);
    border-radius: var(--radius-sm); padding: 7px 14px;
    margin-bottom: .75rem;
  }
  .step-tracker.visible { display: flex; }
  .step-item { display: flex; align-items: center; gap: 4px; font-size: 10px; font-weight: 600; white-space: nowrap; }
  .step-item.done   { color: var(--green); }
  .step-item.active { color: var(--blue); }
  .step-item.wait   { color: var(--muted); }
  .step-sep { flex: 1; height: 1px; background: var(--border); margin: 0 8px; min-width: 8px; }
  .step-spin {
    width: 9px; height: 9px;
    border: 1.5px solid var(--blue); border-top-color: transparent;
    border-radius: 50%; animation: spin .7s linear infinite; flex-shrink: 0;
  }

  /* ── Fine-tune progress bar ── */
  .finetune-bar {
    display: none;
    background: var(--surface); border: 1px solid var(--border);
    border-radius: var(--radius-sm); padding: 10px 14px;
    margin-bottom: .75rem;
  }
  .finetune-bar.visible { display: block; }
  .finetune-top { display: flex; align-items: center; gap: 8px; margin-bottom: 5px; }
  .finetune-title { font-size: 11px; font-weight: 700; color: var(--text); flex: 1; }
  .finetune-pct   { font-family: 'JetBrains Mono', monospace; font-size: 10px; color: var(--muted2); }
  .finetune-detail { font-size: 10px; color: var(--muted2); margin-bottom: 6px; }
  .finetune-track { height: 5px; background: var(--border); border-radius: 3px; overflow: hidden; }
  .finetune-fill  { height: 100%; border-radius: 3px; background: var(--amber); transition: width .3s ease; }
```

- [ ] **Step 2: Verify CSS loaded**

Open `http://localhost:5500/tools/finance-dashboard/index.html` (or your local server). Open DevTools → Elements. Confirm `.skel`, `.refine-badge`, `.step-tracker`, `.finetune-bar` rules are present in the Styles panel with no parse errors shown in the Console.

- [ ] **Step 3: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "style: add shimmer skeleton, refine badge, step tracker, and fine-tune progress bar CSS"
```

---

### Task 2: Add HTML — step tracker and fine-tune progress bar elements

**Files:**
- Modify: `tools/finance-dashboard/index.html` — HTML body

Both elements start hidden and are shown programmatically in later tasks.

- [ ] **Step 1: Insert HTML after the Configure card**

Find:
```html
    <div class="phase-line" id="phaseLine"><div class="spinner"></div><span id="phaseText"></span></div>
  </div>

  <div class="banner error" id="errBanner"></div>
```

Replace with:
```html
    <div class="phase-line" id="phaseLine"><div class="spinner"></div><span id="phaseText"></span></div>
  </div>

  <!-- Step tracker — shown during loadDashboard, hidden when complete -->
  <div class="step-tracker" id="stepTracker">
    <div class="step-item wait" id="stepLicenses">Licenses</div>
    <div class="step-sep"></div>
    <div class="step-item wait" id="stepUsers">Users</div>
    <div class="step-sep"></div>
    <div class="step-item wait" id="stepAnalysis">Analysis</div>
    <div class="step-sep"></div>
    <div class="step-item wait" id="stepFinetune">Fine-tune</div>
  </div>

  <!-- Fine-tune progress bar — shown during audit batch pass -->
  <div class="finetune-bar" id="finetuneBar">
    <div class="finetune-top">
      <div class="step-spin" id="finetuneSpinner"></div>
      <div class="finetune-title" id="finetuneTitle">Fine-tune pass — verifying inactive users</div>
      <div class="finetune-pct" id="finetunePct">0%</div>
    </div>
    <div class="finetune-detail" id="finetuneDetail">Checking audit logs for inactive candidates…</div>
    <div class="finetune-track">
      <div class="finetune-fill" id="finetuneFill" style="width:0%"></div>
    </div>
  </div>

  <div class="banner error" id="errBanner"></div>
```

- [ ] **Step 2: Verify elements exist in DOM**

Reload the page. In DevTools Console run:
```js
document.getElementById('stepTracker')   // → <div class="step-tracker" ...>
document.getElementById('finetuneBar')   // → <div class="finetune-bar" ...>
```
Both should return elements (not null). Neither should be visible on the page yet.

- [ ] **Step 3: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat: add step tracker and fine-tune progress bar HTML elements"
```

---

### Task 3: Add `renderTableSkeletons()` and step tracker helpers

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `<script>` block

Add three new functions. Insert them after the closing brace of `setPhase()` (around line 784, after `function setPhase(msg) { ... }`).

- [ ] **Step 1: Insert helper functions**

Find:
```js
async function loadDashboard() {
```

Insert the following block immediately before it:

```js
// ── Progressive loading helpers ────────────────────────────────────────────────

function setStep(stepId) {
  // stepId: "licenses" | "users" | "analysis" | "finetune" | "done"
  const steps = ["stepLicenses", "stepUsers", "stepAnalysis", "stepFinetune"];
  const order = ["licenses", "users", "analysis", "finetune"];
  const idx   = order.indexOf(stepId);
  steps.forEach((id, i) => {
    const el = document.getElementById(id);
    if (!el) return;
    el.className = "step-item " + (i < idx ? "done" : i === idx ? "active" : "wait");
    if (i < idx) {
      el.innerHTML = "✓ " + el.textContent.replace(/^[✓⟳]\s*/, "");
    } else if (i === idx && stepId !== "done") {
      el.innerHTML = `<div class="step-spin"></div> ${el.textContent.replace(/^[✓⟳]\s*/, "")}`;
    }
  });
  if (stepId === "done") {
    steps.forEach(id => {
      const el = document.getElementById(id);
      if (el) { el.className = "step-item done"; el.innerHTML = "✓ " + el.textContent.replace(/^[✓⟳]\s*/, ""); }
    });
    const spinner = document.getElementById("finetuneSpinner");
    if (spinner) spinner.style.display = "none";
  }
}

function showStepTracker() {
  const el = document.getElementById("stepTracker");
  if (el) el.classList.add("visible");
}

function hideStepTracker() {
  const el = document.getElementById("stepTracker");
  if (el) el.classList.remove("visible");
}

function renderTableSkeletons() {
  const skeletonRow = `
    <tr>
      <td><div class="skel skel-md"></div></td>
      <td><div class="skel skel-sm"></div></td>
      <td><div class="skel skel-sm"></div></td>
      <td><div class="skel skel-sm"></div></td>
      <td><div class="skel skel-sm"></div></td>
    </tr>`;
  const rows = skeletonRow.repeat(5);

  // Inactive table skeleton
  document.getElementById("inactiveTableWrap").innerHTML = `
    <table style="width:100%;border-collapse:collapse;table-layout:fixed">
      <thead>
        <tr style="font-size:10px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;background:var(--surface2);border-bottom:1px solid var(--border)">
          <th style="padding:9px 12px;text-align:left">User</th>
          <th style="padding:9px 12px;text-align:left">Last Sign-in</th>
          <th style="padding:9px 12px;text-align:left">Days Inactive</th>
          <th style="padding:9px 12px;text-align:left">Licenses</th>
          <th style="padding:9px 12px;text-align:left">Monthly Cost</th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>`;

  // Active table skeleton
  document.getElementById("activeTableWrap").innerHTML = `
    <table style="width:100%;border-collapse:collapse;table-layout:fixed">
      <thead>
        <tr style="font-size:10px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;background:var(--surface2);border-bottom:1px solid var(--border)">
          <th style="padding:9px 12px;text-align:left">User</th>
          <th style="padding:9px 12px;text-align:left">Department</th>
          <th style="padding:9px 12px;text-align:left">Last Sign-in</th>
          <th style="padding:9px 12px;text-align:left">Licenses</th>
          <th style="padding:9px 12px;text-align:left">Monthly Cost</th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>`;
}
```

- [ ] **Step 2: Verify in console**

Reload the page and sign in to load the tool. In DevTools Console run:
```js
renderTableSkeletons();
document.getElementById("inactiveCard").style.display = "block";
document.getElementById("activeCard").style.display  = "block";
```
Both cards should appear with shimmer skeleton rows. Columns should match the table structure.

- [ ] **Step 3: Revert the console test**

```js
document.getElementById("inactiveCard").style.display = "none";
document.getElementById("activeCard").style.display  = "none";
```

- [ ] **Step 4: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat: add renderTableSkeletons, setStep, showStepTracker helpers"
```

---

### Task 4: Add KPI badge injection functions

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `kpiCard()` function + new badge helpers

The three audit-dependent KPI cards are "Active Seats", "Savings Found", and "Inactive Cost". We add a `data-kpi` attribute to each card so badge functions can target them.

- [ ] **Step 1: Add `data-kpi` attribute to `kpiCard()`**

Find:
```js
function kpiCard(accent, label, value, sub, trend) {
  const trendCls = trend.startsWith("▲") ? "up" : trend.startsWith("▼") ? "down" : "neutral";
  return `<div class="kpi-card ${accent}">
    <div class="kpi-label">${label}</div>
    <div class="kpi-value">${value}</div>
    <div class="kpi-sub">
      <span>${sub}</span>
      <span class="kpi-trend ${trendCls}">${trend}</span>
    </div>
  </div>`;
}
```

Replace with:
```js
function kpiCard(accent, label, value, sub, trend) {
  const trendCls = trend.startsWith("▲") ? "up" : trend.startsWith("▼") ? "down" : "neutral";
  const slug     = label.toLowerCase().replace(/\s+/g, "-");
  return `<div class="kpi-card ${accent}" data-kpi="${slug}" style="position:relative">
    <div class="kpi-label">${label}</div>
    <div class="kpi-value" data-kpi-value>${value}</div>
    <div class="kpi-sub">
      <span data-kpi-sub>${sub}</span>
      <span class="kpi-trend ${trendCls}" data-kpi-trend>${trend}</span>
    </div>
  </div>`;
}
```

- [ ] **Step 2: Add `injectRefineBadges()` and `injectConfirmedBadges()` functions**

Add these functions directly after the `kpiCard()` function:

```js
function injectRefineBadges() {
  ["active-seats", "savings-found", "inactive-cost"].forEach(slug => {
    const card = document.querySelector(`[data-kpi="${slug}"]`);
    if (!card || card.querySelector(".refine-badge")) return;
    const badge = document.createElement("span");
    badge.className = "refine-badge";
    badge.innerHTML = `<span class="badge-spin"></span> Refining`;
    card.appendChild(badge);
  });
}

function injectConfirmedBadges() {
  document.querySelectorAll(".refine-badge").forEach(b => {
    b.classList.add("confirmed");
    b.innerHTML = "✓ Confirmed";
  });
  setTimeout(() => {
    document.querySelectorAll(".refine-badge").forEach(b => {
      b.classList.add("fade-out");
      setTimeout(() => b.remove(), 400);
    });
  }, 2500);
}
```

- [ ] **Step 3: Verify badges in console**

Reload and load the dashboard fully. In DevTools Console run:
```js
injectRefineBadges();
```
Three small amber "⟳ Refining" badges should appear in the top-right corner of each KPI card. Then run:
```js
injectConfirmedBadges();
```
Badges should turn green "✓ Confirmed", then fade out after 2.5 seconds.

- [ ] **Step 4: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat: add data-kpi attributes and injectRefineBadges/injectConfirmedBadges helpers"
```

---

### Task 5: Add `updateBatchProgress()` function

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `<script>` block

This function is called after each audit batch to tick the progress bar and refresh the three audit-dependent KPI values in-place without re-rendering the full row.

- [ ] **Step 1: Insert `updateBatchProgress()` after `injectConfirmedBadges()`**

```js
function updateBatchProgress(batchNum, totalBatches, processedUsers, waste) {
  const pct     = Math.round((batchNum / totalBatches) * 100);
  const fill    = document.getElementById("finetuneFill");
  const pctEl   = document.getElementById("finetunePct");
  const detail  = document.getElementById("finetuneDetail");
  if (fill)   fill.style.width  = pct + "%";
  if (pctEl)  pctEl.textContent = pct + "%";
  if (detail) detail.textContent =
    `Batch ${batchNum} of ${totalBatches} — cross-checking sign-in audit logs…`;

  // Recalculate and update the three audit-dependent KPI values in-place
  const inactiveU    = processedUsers.filter(u => u.inactive && u.totalCost > 0);
  const activeSeats  = processedUsers.filter(u => !u.inactive && u.totalCost > 0).length;
  const inactiveCost = inactiveU.reduce((s, u) => s + u.totalCost, 0);
  const saveable     = waste + inactiveCost;
  const inactiveCount = inactiveU.length;

  const update = (slug, value, sub) => {
    const card = document.querySelector(`[data-kpi="${slug}"]`);
    if (!card) return;
    const vEl = card.querySelector("[data-kpi-value]");
    const sEl = card.querySelector("[data-kpi-sub]");
    if (vEl) vEl.textContent = value;
    if (sEl) sEl.textContent = sub;
  };

  update("active-seats",  activeSeats.toLocaleString(),      `of — total`);
  update("savings-found", fmt(saveable, true) + "/mo",       `${inactiveCount} inactive users`);
  update("inactive-cost", fmt(inactiveCost, true) + "/mo",   `>${_data ? _data.days : 90}-day threshold`);
}
```

- [ ] **Step 2: Verify the function signature is callable**

In DevTools Console (after a full load):
```js
typeof updateBatchProgress  // → "function"
```

- [ ] **Step 3: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat: add updateBatchProgress function for in-place KPI updates during audit pass"
```

---

### Task 6: Add `renderInitial()` function

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `<script>` block

`renderInitial()` shows the full dashboard after step 3, before any audit batches. It calls the existing render functions, shows the step tracker and progress bar, injects Refining badges, and renders skeleton rows into both tables.

- [ ] **Step 1: Insert `renderInitial()` after `updateBatchProgress()`**

```js
function renderInitial(processedUsers, skuList, deptMap, skuStats, days) {
  // Store globally so renderAll() and dept filter work correctly
  _data = { skuList, processedUsers, deptMap, skuStats, days };

  // Show all the sections that were hidden on page load
  document.getElementById("spendHero").style.display  = "flex";
  document.getElementById("statsRow").style.display   = "";
  document.getElementById("row1").style.display       = "";
  document.getElementById("deptCard").style.display   = "";
  document.getElementById("projCard").style.display   = "";
  document.getElementById("inactiveCard").style.display = "block";
  document.getElementById("activeCard").style.display   = "block";
  document.getElementById("exportProjBtn").style.display = "";

  // Run all existing render functions using current (pre-audit) data
  const filtered = processedUsers; // no dept filter applied yet
  const inactiveU    = filtered.filter(u => u.inactive && u.totalCost > 0);
  const activeU      = filtered.filter(u => !u.inactive && u.totalCost > 0);
  const monthly      = skuList.reduce((s, sk) => s + sk.assignedCost, 0);
  const waste        = skuList.reduce((s, sk) => s + sk.wasteCost,    0);
  const inactiveCost = inactiveU.reduce((s, u) => s + u.totalCost, 0);
  const assignedSeats = filtered.filter(u => u.totalCost > 0).length;
  const totalSeats   = skuList.reduce((s, sk) => s + sk.total, 0);

  renderStats(monthly, waste, inactiveCost, skuList.length, inactiveU.length, days, assignedSeats, totalSeats);
  renderCallout(monthly, waste, inactiveCost, inactiveU.length, days);
  renderDonut(skuList);
  renderUtilisation(skuList);
  renderDeptChart(deptMap, "");
  renderProjections(monthly, inactiveCost, waste);

  // Skeleton rows replace table bodies while batches run
  renderTableSkeletons();
  document.getElementById("inactiveCountBadge").textContent = "Verifying…";

  // Badges on audit-dependent KPI cards
  injectRefineBadges();

  // Step tracker: analysis done, fine-tune starting
  showStepTracker();
  setStep("finetune");

  // Fine-tune progress bar
  const bar = document.getElementById("finetuneBar");
  if (bar) {
    bar.classList.add("visible");
    document.getElementById("finetuneDetail").textContent =
      "Checking audit logs for inactive candidates…";
    document.getElementById("finetuneFill").style.width = "0%";
    document.getElementById("finetunePct").textContent  = "0%";
  }
}
```

- [ ] **Step 2: Verify the function is callable**

In DevTools Console:
```js
typeof renderInitial  // → "function"
```

- [ ] **Step 3: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat: add renderInitial function — stage 1 dashboard render before audit batches"
```

---

### Task 7: Add `finaliseDashboard()` function

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `<script>` block

Called once all batches complete. Calls `renderAll()` to replace skeletons with real data, injects Confirmed badges that fade out, updates the step tracker, and hides the progress bar.

- [ ] **Step 1: Insert `finaliseDashboard()` after `renderInitial()`**

```js
function finaliseDashboard(reclaimedAudit) {
  // Re-render everything with final verified data (replaces skeleton rows)
  renderAll();

  // Inject confirmed badges immediately after renderAll re-creates the KPI cards
  injectConfirmedBadges();

  // Step tracker → all done
  setStep("done");

  // Hide progress bar
  const bar = document.getElementById("finetuneBar");
  if (bar) bar.classList.remove("visible");

  // Hide phaseLine spinner
  setPhase(null);

  // Show completion banner if users were reclassified
  if (reclaimedAudit > 0) {
    ITTools.ui.banner("errBanner",
      `Audit scan complete — ${reclaimedAudit} user${reclaimedAudit !== 1 ? "s were" : " was"} reclassified as active. All figures confirmed.`,
      "info"
    );
  }
}
```

- [ ] **Step 2: Verify the function is callable**

```js
typeof finaliseDashboard  // → "function"
```

- [ ] **Step 3: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat: add finaliseDashboard function — stage 2 completion, badge transition, step tracker"
```

---

### Task 8: Refactor `loadDashboard()` to wire all stages together

**Files:**
- Modify: `tools/finance-dashboard/index.html` — `loadDashboard()` function

This is the integration task. The existing `loadDashboard()` needs three changes:
1. Mark step tracker steps as they complete during the blocking phases (steps 1 & 2)
2. Call `renderInitial()` immediately after step 3 instead of waiting for batches
3. Call `updateBatchProgress()` after each audit batch, then `finaliseDashboard()` when done

- [ ] **Step 1: Show step tracker and mark steps 1 & 2 as they complete**

Find the try block opening inside `loadDashboard()`:
```js
  try {
    // 1 — SKU subscriptions
    setPhase("Fetching license subscriptions…");
    const allSkus  = await gwr(() => ITTools.graph.getAll("/subscribedSkus"));
```

Replace with:
```js
  try {
    // 1 — SKU subscriptions
    showStepTracker();
    setStep("licenses");
    setPhase("Fetching license subscriptions…");
    const allSkus  = await gwr(() => ITTools.graph.getAll("/subscribedSkus"));
```

Then find:
```js
    // 2 — Licensed users with sign-in activity
    setPhase("Fetching licensed users and sign-in data…");
```

Replace with:
```js
    // 2 — Licensed users with sign-in activity
    setStep("users");
    setPhase("Fetching licensed users and sign-in data…");
```

Then find:
```js
    setPhase(`Analysing ${users.length.toLocaleString()} licensed users…`);
```

Replace with:
```js
    setStep("analysis");
    setPhase(`Analysing ${users.length.toLocaleString()} licensed users…`);
```

- [ ] **Step 2: Call `renderInitial()` after step 3, before the batch loop**

Find the comment and line that currently precede the batch loop:
```js
    // 3b — Audit log batch verification for inactive candidates (20 per batch)
    const inactiveCandidates = processedUsers.filter(u => u.inactive && u.totalCost > 0);
```

Insert the call to `renderInitial()` immediately before it. You'll need `skuStats` and `deptMap` which are built in steps 4 & 5 of the original function, so move that block up. Replace the existing flow like this:

Find (lines 864–918, the full batch block including the 3b comment through to the closing `}`):
```js
    // 3b — Audit log batch verification for inactive candidates (20 per batch)
    const inactiveCandidates = processedUsers.filter(u => u.inactive && u.totalCost > 0);
    if (inactiveCandidates.length > 0) {
      const BATCH    = 20;
      const total    = inactiveCandidates.length;
      const batches  = Math.ceil(total / BATCH);
      const auditMap = {}; // userId → ISO date string or null
      let reclaimedAudit = 0;

      for (let i = 0; i < total; i += BATCH) {
        const chunk    = inactiveCandidates.slice(i, i + BATCH);
        const batchNum = Math.floor(i / BATCH) + 1;
        setPhase(`Verifying via audit logs — ${Math.min(i + BATCH, total)} of ${total} users (batch ${batchNum} / ${batches})…`);

        try {
          const batchRes = await gwr(() => ITTools.graph.post(
            "https://graph.microsoft.com/v1.0/$batch",
            {
              requests: chunk.map((u, idx) => ({
                id:     String(idx),
                method: "GET",
                url:    `/auditLogs/signIns?$filter=userId eq '${u.id}'&$top=1&$orderby=createdDateTime desc&$select=createdDateTime`
              }))
            }
          ));
          (batchRes.responses || []).forEach(r => {
            const userId = chunk[parseInt(r.id)].id;
            auditMap[userId] = r.status === 200 ? (r.body?.value?.[0]?.createdDateTime || null) : null;
          });
        } catch(_) {
          chunk.forEach(u => { auditMap[u.id] = null; });
        }
      }

      // Apply results to processedUsers in place
      for (const u of inactiveCandidates) {
        const latest = auditMap[u.id];
        if (latest) {
          const auditDate = new Date(latest);
          if (!u.lastSignIn || auditDate > u.lastSignIn) {
            u.lastSignIn = auditDate;
            u.daysSince  = Math.floor((Date.now() - auditDate.getTime()) / 86400000);
            u.inactive   = auditDate < cutoff;
            if (!u.inactive) reclaimedAudit++;
          }
        }
      }

      if (reclaimedAudit > 0) {
        ITTools.ui.banner("errBanner",
          `Audit log check complete — ${reclaimedAudit} user${reclaimedAudit!==1?" were":" was"} reclassified as active after verifying against sign-in logs. Remaining inactive users are confirmed dormant.`,
          "info"
        );
      }
    }

    // 4 — SKU-level stats
```

Replace with:
```js
    // 4 — SKU-level stats (computed before renderInitial so it can show charts)
```

Wait — this approach requires reordering steps 3b and 4/5. Let me be explicit. The new order is:

1. Build `processedUsers` (existing step 3)
2. Build `skuStats` (existing step 4)
3. Build `deptMap` (existing step 5)
4. Populate dept filter dropdown (existing step 6)
5. **NEW: Call `renderInitial()`** ← insert here
6. Run audit batch loop (existing step 3b, moved after renderInitial)
7. **NEW: Call `finaliseDashboard()`** instead of `renderAll()`

Find the entire block from `// 3b` through `// 4 — SKU-level stats` and replace as follows:

Find:
```js
    // 3b — Audit log batch verification for inactive candidates (20 per batch)
    const inactiveCandidates = processedUsers.filter(u => u.inactive && u.totalCost > 0);
    if (inactiveCandidates.length > 0) {
      const BATCH    = 20;
      const total    = inactiveCandidates.length;
      const batches  = Math.ceil(total / BATCH);
      const auditMap = {}; // userId → ISO date string or null
      let reclaimedAudit = 0;

      for (let i = 0; i < total; i += BATCH) {
        const chunk    = inactiveCandidates.slice(i, i + BATCH);
        const batchNum = Math.floor(i / BATCH) + 1;
        setPhase(`Verifying via audit logs — ${Math.min(i + BATCH, total)} of ${total} users (batch ${batchNum} / ${batches})…`);

        try {
          const batchRes = await gwr(() => ITTools.graph.post(
            "https://graph.microsoft.com/v1.0/$batch",
            {
              requests: chunk.map((u, idx) => ({
                id:     String(idx),
                method: "GET",
                url:    `/auditLogs/signIns?$filter=userId eq '${u.id}'&$top=1&$orderby=createdDateTime desc&$select=createdDateTime`
              }))
            }
          ));
          (batchRes.responses || []).forEach(r => {
            const userId = chunk[parseInt(r.id)].id;
            auditMap[userId] = r.status === 200 ? (r.body?.value?.[0]?.createdDateTime || null) : null;
          });
        } catch(_) {
          chunk.forEach(u => { auditMap[u.id] = null; });
        }
      }

      // Apply results to processedUsers in place
      for (const u of inactiveCandidates) {
        const latest = auditMap[u.id];
        if (latest) {
          const auditDate = new Date(latest);
          if (!u.lastSignIn || auditDate > u.lastSignIn) {
            u.lastSignIn = auditDate;
            u.daysSince  = Math.floor((Date.now() - auditDate.getTime()) / 86400000);
            u.inactive   = auditDate < cutoff;
            if (!u.inactive) reclaimedAudit++;
          }
        }
      }

      if (reclaimedAudit > 0) {
        ITTools.ui.banner("errBanner",
          `Audit log check complete — ${reclaimedAudit} user${reclaimedAudit!==1?" were":" was"} reclassified as active after verifying against sign-in logs. Remaining inactive users are confirmed dormant.`,
          "info"
        );
      }
    }

    // 4 — SKU-level stats
    const skuStats = {};
```

Replace with:
```js
    // 4 — SKU-level stats (built before renderInitial so charts have data)
    const skuStats = {};
```

Then find the block that ends step 6 and the `_data = ...` and `renderAll()` calls:
```js
    // Store globally for re-renders
    _data = { skuList, processedUsers, deptMap, skuStats, days };

    renderAll();
    setPhase(null);
```

Replace with:
```js
    // ── Stage 1: render immediately with pre-audit data ──
    renderInitial(processedUsers, skuList, deptMap, skuStats, days);
    setPhase(null);

    // ── Stage 2: audit batch verification (fine-tune pass) ──
    const inactiveCandidates = processedUsers.filter(u => u.inactive && u.totalCost > 0);
    let reclaimedAudit = 0;

    if (inactiveCandidates.length > 0) {
      const BATCH   = 20;
      const total   = inactiveCandidates.length;
      const batches = Math.ceil(total / BATCH);
      const auditMap = {};

      for (let i = 0; i < total; i += BATCH) {
        const chunk    = inactiveCandidates.slice(i, i + BATCH);
        const batchNum = Math.floor(i / BATCH) + 1;

        try {
          const batchRes = await gwr(() => ITTools.graph.post(
            "https://graph.microsoft.com/v1.0/$batch",
            {
              requests: chunk.map((u, idx) => ({
                id:     String(idx),
                method: "GET",
                url:    `/auditLogs/signIns?$filter=userId eq '${u.id}'&$top=1&$orderby=createdDateTime desc&$select=createdDateTime`
              }))
            }
          ));
          (batchRes.responses || []).forEach(r => {
            const userId = chunk[parseInt(r.id)].id;
            auditMap[userId] = r.status === 200 ? (r.body?.value?.[0]?.createdDateTime || null) : null;
          });
        } catch(_) {
          chunk.forEach(u => { auditMap[u.id] = null; });
        }

        // Apply batch results in place
        for (const u of chunk) {
          const latest = auditMap[u.id];
          if (latest) {
            const auditDate = new Date(latest);
            if (!u.lastSignIn || auditDate > u.lastSignIn) {
              u.lastSignIn = auditDate;
              u.daysSince  = Math.floor((Date.now() - auditDate.getTime()) / 86400000);
              const wasInactive = u.inactive;
              u.inactive   = auditDate < cutoff;
              if (wasInactive && !u.inactive) reclaimedAudit++;
            }
          }
        }

        // Update global data and tick progress bar
        _data.processedUsers = processedUsers;
        const waste = skuList.reduce((s, sk) => s + sk.wasteCost, 0);
        updateBatchProgress(batchNum, batches, processedUsers, waste);
      }
    }

    // ── Stage 2 complete ──
    finaliseDashboard(reclaimedAudit);
```

- [ ] **Step 3: Verify full load flow end-to-end**

Reload the page and click "Load Dashboard". Observe:
1. Phase line shows "Fetching license subscriptions…" then "Fetching licensed users…"
2. Step tracker appears and advances through Licenses → Users → Analysis → Fine-tune
3. Dashboard renders immediately after analysis — hero card, KPI cards, charts all visible
4. "Refining" amber badges appear on Active Seats, Savings Found, Inactive Cost
5. Both tables show shimmer skeleton rows
6. Progress bar shows "Batch X of Y — cross-checking sign-in audit logs…" and fill advances
7. On completion: tables populate with real rows, badges transition to "✓ Confirmed" then fade, step tracker shows all ✓, progress bar hides

- [ ] **Step 4: Verify dept filter still works**

While the dashboard is fully loaded, change the Department filter dropdown. The dashboard should re-render correctly (all tables and charts update, no skeleton rows, no badges).

- [ ] **Step 5: Verify error path**

If sign-in fails or Graph returns an error, the error banner should still appear and the dashboard should not be left in a partial state. Check the catch block at the bottom of `loadDashboard()` — it already calls `setPhase(null)`. Add `hideStepTracker()` and `document.getElementById("finetuneBar").classList.remove("visible")` to clean up:

Find:
```js
  } catch(e) {
    document.getElementById("errBanner").textContent   = ITTools.graph.friendlyError(e);
    document.getElementById("errBanner").style.display = "block";
    setPhase(null);
  }
```

Replace with:
```js
  } catch(e) {
    document.getElementById("errBanner").textContent   = ITTools.graph.friendlyError(e);
    document.getElementById("errBanner").style.display = "block";
    setPhase(null);
    hideStepTracker();
    const bar = document.getElementById("finetuneBar");
    if (bar) bar.classList.remove("visible");
  }
```

- [ ] **Step 6: Commit**

```bash
git add tools/finance-dashboard/index.html
git commit -m "feat: refactor loadDashboard into staged render — instant overview + progressive fine-tune pass"
```

---

### Task 9: Deploy to testing branch and preview verification

**Files:** No code changes — git operations only.

- [ ] **Step 1: Confirm all commits are on `testing`**

```bash
git log --oneline -8
```

Expected: all feature commits from Tasks 1–8 visible on `testing`.

- [ ] **Step 2: Push to origin**

```bash
git push origin testing
```

- [ ] **Step 3: Verify on preview**

Open `https://jgdev-ch.github.io/it-tools-preview/tools/finance-dashboard/` (the preview deployment updates from `testing`). Sign in and run a full load. Confirm all 7 behaviours from Task 8 Step 3.

- [ ] **Step 4: Merge to main when approved**

```bash
git checkout main
git merge testing
git push origin main
```
