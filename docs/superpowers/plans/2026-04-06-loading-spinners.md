# Loading Spinners — Universal Visual Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ITTools.ui.withButtonSpinner()` to `shared/auth.js` and wire it into all relevant async operations across the 6 IT Tools.

**Architecture:** One new method added to the existing `ITTools.ui` IIFE in `shared/auth.js`. Each tool's `index.html` gets targeted call-site edits — either wrapping existing async functions or replacing manual button-state logic. No new files.

**Tech Stack:** Vanilla JavaScript, HTML, CSS. No build step. Changes are live immediately when files are saved. Preview at `jgdev-ch.github.io/it-tools-preview/` (push `testing` branch → preview site auto-deploys).

---

## File Map

| File | Change |
|------|--------|
| `shared/auth.js` | Add `withButtonSpinner` inside `ITTools.ui` IIFE; add to return object |
| `tools/license-audit/index.html` | Replace manual btn-state in `confirmRemoval()` + `confirmManageRemoval()`; update `doSignIn()` |
| `tools/mfa-status/index.html` | Update `doSignIn()` + button `onclick` |
| `tools/guest-audit/index.html` | Update `doSignIn()` + button `onclick` |
| `tools/name-resolver/index.html` | Update `doSignIn()` + button `onclick` |
| `tools/group-import/index.html` | Refactor `lookupGroup()` to use `withButtonSpinner` |

**Finance Dashboard** is excluded — it redirects unauthenticated users to the hub and its `loadDashboard()` button already has full loading state via the existing `setPhase()` mechanism.

---

## Task 1: Add `withButtonSpinner` to `shared/auth.js`

**Files:**
- Modify: `shared/auth.js` — `ITTools.ui` IIFE (lines 220–308)

- [ ] **Step 1: Add the method inside the `ITTools.ui` IIFE**

  Open `shared/auth.js`. Find the `ITTools.ui` IIFE. It currently ends with:
  ```js
    function spinner(show, labelId, msg = "") { ... }

    return { renderTopbar, syncThemeIcon, setUser, clearUser, banner, spinner };
  })();
  ```

  Insert the new function **before** the `return` statement, after `spinner`:

  ```js
    /**
     * withButtonSpinner(btn, asyncFn, loadingText?, disableEls?)
     * Wraps an async call with button loading state.
     *   btn         — the button element to animate
     *   asyncFn     — async function to await; return value is passed through
     *   loadingText — label shown while in flight (default: "Loading…")
     *   disableEls  — extra elements to disable during the call (e.g. paired inputs)
     */
    async function withButtonSpinner(btn, asyncFn, loadingText = "Loading…", disableEls = []) {
      const orig = btn.innerHTML;
      btn.disabled = true;
      btn.innerHTML = `<span style="display:inline-flex;align-items:center;gap:6px;pointer-events:none"><span class="spinner" style="width:12px;height:12px;border-width:2px"></span>${loadingText}</span>`;
      disableEls.forEach(el => (el.disabled = true));
      try {
        return await asyncFn();
      } finally {
        btn.innerHTML = orig;
        btn.disabled  = false;
        disableEls.forEach(el => (el.disabled = false));
      }
    }
  ```

- [ ] **Step 2: Add `withButtonSpinner` to the `return` statement**

  Change:
  ```js
    return { renderTopbar, syncThemeIcon, setUser, clearUser, banner, spinner };
  ```
  To:
  ```js
    return { renderTopbar, syncThemeIcon, setUser, clearUser, banner, spinner, withButtonSpinner };
  ```

- [ ] **Step 3: Verify in browser**

  Open any tool (e.g. `tools/license-audit/index.html`) in a browser. Open DevTools console. Run:
  ```js
  typeof ITTools.ui.withButtonSpinner
  ```
  Expected output: `"function"`

- [ ] **Step 4: Commit**

  ```bash
  cd /c/dev/projects/it-tools
  git add shared/auth.js
  git commit -m "feat: add ITTools.ui.withButtonSpinner shared helper"
  ```

---

## Task 2: Wire License Audit — Action Buttons

The existing `confirmRemoval()` and `confirmManageRemoval()` already have manual button-state logic (disable + text swap). This task replaces that with `withButtonSpinner`, which also adds the animated spinner.

**Files:**
- Modify: `tools/license-audit/index.html` — `confirmRemoval()` (~line 1103) and `confirmManageRemoval()` (~line 1463)

- [ ] **Step 1: Replace `confirmRemoval()` with the version below**

  Find the full `confirmRemoval()` function and replace it entirely:

  ```js
  async function confirmRemoval() {
    if (!_pendingRemoval) return;
    const user       = _pendingRemoval;
    const confirmBtn = document.getElementById("modalConfirmBtn");
    try {
      await ITTools.ui.withButtonSpinner(confirmBtn, async () => {
        const token = await ITTools.auth.getToken();
        const res   = await fetch(`https://graph.microsoft.com/v1.0/users/${user.id}/assignLicense`, {
          method:  "POST",
          headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
          body:    JSON.stringify({ addLicenses: [], removeLicenses: [user.skuId] })
        });
        if (!res.ok) {
          const body = await res.json().catch(() => ({}));
          const msg  = body?.error?.message || `Graph error ${res.status}`;
          if (res.status === 403) throw new Error("Permission denied — ensure User.ReadWrite.All is consented.");
          throw new Error(msg);
        }
        user.removed = true;
        _removalCount++;
        const row = document.getElementById(`row-${user.id}`);
        if (row) {
          row.style.opacity = "0.55";
          const cells = row.querySelectorAll("td");
          cells[cells.length - 1].innerHTML = `<span class="removed-badge">✓ Removed</span>`;
        }
        updateRemovalSummary();
        closeModal();
      }, "Removing…");
    } catch(e) {
      let errEl = document.getElementById("modalErr");
      if (!errEl) {
        errEl = document.createElement("div");
        errEl.id = "modalErr";
        errEl.className = "banner error";
        errEl.style.marginBottom = "1rem";
        document.querySelector(".modal-actions").before(errEl);
      }
      errEl.textContent   = "Error: " + e.message;
      errEl.style.display = "block";
    }
  }
  ```

  Key changes from the original:
  - Removed `confirmBtn.disabled = true; confirmBtn.textContent = "Removing…"` at the top
  - Removed `confirmBtn.disabled = false; confirmBtn.textContent = "Remove license"` from catch
  - Wrapped the async body in `withButtonSpinner(..., "Removing…")`

- [ ] **Step 2: Replace `confirmManageRemoval()` with the version below**

  Find the full `confirmManageRemoval()` function and replace it entirely:

  ```js
  async function confirmManageRemoval() {
    if (!_pendingManage) return;
    const user       = _pendingManage;
    const confirmBtn = document.getElementById("manageConfirmBtn");

    const selected = [...document.querySelectorAll(".manage-lic-check:checked:not(:disabled)")]
      .map(cb => cb.value);

    if (!selected.length) {
      let errEl = document.getElementById("manageErr");
      if (!errEl) {
        errEl = Object.assign(document.createElement("div"), { id: "manageErr", className: "banner error" });
        errEl.style.marginBottom = "1rem";
        document.querySelector("#manageModal .modal-actions").before(errEl);
      }
      errEl.textContent   = "Please select at least one license to remove.";
      errEl.style.display = "block";
      return;
    }

    try {
      await ITTools.ui.withButtonSpinner(confirmBtn, async () => {
        const token = await ITTools.auth.getToken();
        const res   = await fetch(`https://graph.microsoft.com/v1.0/users/${user.id}/assignLicense`, {
          method:  "POST",
          headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
          body:    JSON.stringify({ addLicenses: [], removeLicenses: selected })
        });
        if (!res.ok) {
          const body = await res.json().catch(() => ({}));
          const msg  = body?.error?.message || `Graph error ${res.status}`;
          if (res.status === 403) throw new Error("Permission denied — ensure User.ReadWrite.All is consented.");
          throw new Error(msg);
        }
        user.removedSkuIds.push(...selected);
        _multiRemovalCount += selected.length;
        const row = document.getElementById(`multirow-${user.id}`);
        if (row) row.outerHTML = multiUserRow(user, _hasFinanceAccess);
        updateMultiRemovalSummary();
        closeManageModal();
      }, "Removing…");
    } catch(e) {
      let errEl = document.getElementById("manageErr");
      if (!errEl) {
        errEl = Object.assign(document.createElement("div"), { id: "manageErr", className: "banner error" });
        errEl.style.marginBottom = "1rem";
        document.querySelector("#manageModal .modal-actions").before(errEl);
      }
      errEl.textContent   = "Error: " + e.message;
      errEl.style.display = "block";
    }
  }
  ```

  Key changes from the original:
  - Removed `confirmBtn.disabled = true; confirmBtn.textContent = "Removing…"` at the top
  - Removed `confirmBtn.disabled = false; confirmBtn.textContent = "Remove selected"` from catch
  - Wrapped the async body in `withButtonSpinner(..., "Removing…")`

- [ ] **Step 3: Verify in browser**

  Open License Audit in the browser and sign in. Run the audit, open a user's removal modal. Click "Remove license". Verify:
  - The button immediately shows a spinner + "Removing…" text
  - The button is disabled (cannot be clicked again)
  - On success: button restores, modal closes
  - On error (e.g. network off): button restores to "Remove license", error banner appears

- [ ] **Step 4: Commit**

  ```bash
  git add tools/license-audit/index.html
  git commit -m "feat: wire withButtonSpinner to license-audit confirm buttons"
  ```

---

## Task 3: Wire Sign-In Buttons

Four tools have a sign-in button with `onclick="doSignIn()"`. The pattern for all four is the same: change `onclick` to pass `this`, update `doSignIn` to accept `btn`, and wrap the body with `withButtonSpinner`.

This gives feedback during the MSAL popup wait and prevents double-clicks.

**Files:**
- Modify: `tools/license-audit/index.html`
- Modify: `tools/mfa-status/index.html`
- Modify: `tools/guest-audit/index.html`
- Modify: `tools/name-resolver/index.html`

### License Audit

- [ ] **Step 1: Update the sign-in button HTML**

  Find (around line 241):
  ```html
  <button class="btn-ms" onclick="doSignIn()">
  ```
  Change to:
  ```html
  <button class="btn-ms" onclick="doSignIn(this)">
  ```

- [ ] **Step 2: Replace `doSignIn()` in License Audit**

  Find the full `doSignIn()` function and replace it:

  ```js
  async function doSignIn(btn) {
    try {
      await ITTools.ui.withButtonSpinner(btn, async () => {
        const acct = await ITTools.auth.signIn();
        document.getElementById("authScreen").style.display = "none";
        document.getElementById("appScreen").style.display  = "block";
        ITTools.ui.setUser(acct);
        await Promise.all([checkFinanceAccess(), loadSkus(), loadCosts()]);
        if (_hasFinanceAccess) {
          document.getElementById("financeIndicator").style.display = "inline-flex";
          rebuildDropdown();
        }
      }, "Signing in…");
    } catch(e) {
      const el = document.getElementById("authErr");
      el.textContent = e.message; el.style.display = "block";
    }
  }
  ```

### MFA Status

- [ ] **Step 3: Update the sign-in button HTML in MFA Status**

  Find (around line 121):
  ```html
  <button class="btn-ms" onclick="doSignIn()">
  ```
  Change to:
  ```html
  <button class="btn-ms" onclick="doSignIn(this)">
  ```

- [ ] **Step 4: Replace `doSignIn()` in MFA Status**

  ```js
  async function doSignIn(btn) {
    try {
      await ITTools.ui.withButtonSpinner(btn, async () => {
        const acct = await ITTools.auth.signIn();
        document.getElementById("authScreen").style.display = "none";
        document.getElementById("appScreen").style.display  = "block";
        ITTools.ui.setUser(acct);
      }, "Signing in…");
    } catch(e) {
      const el = document.getElementById("authErr");
      el.textContent = e.message; el.style.display = "block";
    }
  }
  ```

### Guest Audit

- [ ] **Step 5: Update the sign-in button HTML in Guest Audit**

  Find (around line 216):
  ```html
  <button class="btn-ms" onclick="doSignIn()">
  ```
  Change to:
  ```html
  <button class="btn-ms" onclick="doSignIn(this)">
  ```

- [ ] **Step 6: Replace `doSignIn()` in Guest Audit**

  ```js
  async function doSignIn(btn) {
    const errEl = document.getElementById("authErr");
    errEl.style.display = "none";
    try {
      await ITTools.ui.withButtonSpinner(btn, async () => {
        const acct = await ITTools.auth.signIn();
        document.getElementById("authScreen").style.display = "none";
        document.getElementById("appScreen").style.display  = "block";
        ITTools.ui.setUser(acct);
      }, "Signing in…");
    } catch(e) {
      errEl.textContent   = e.message;
      errEl.style.display = "block";
    }
  }
  ```

### Name Resolver

- [ ] **Step 7: Update the sign-in button HTML in Name Resolver**

  Find (around line 144):
  ```html
  <button class="btn-ms" onclick="doSignIn()">
  ```
  Change to:
  ```html
  <button class="btn-ms" onclick="doSignIn(this)">
  ```

- [ ] **Step 8: Replace `doSignIn()` in Name Resolver**

  ```js
  async function doSignIn(btn) {
    try {
      await ITTools.ui.withButtonSpinner(btn, async () => {
        const acct = await ITTools.auth.signIn();
        document.getElementById("authScreen").style.display = "none";
        document.getElementById("appScreen").style.display  = "block";
        ITTools.ui.setUser(acct);
      }, "Signing in…");
    } catch(e) {
      const el = document.getElementById("authErr");
      el.textContent = e.message; el.style.display = "block";
    }
  }
  ```

- [ ] **Step 9: Verify in browser**

  Open any of the four tools locally (serve the files via a local HTTP server or open from the it-tools-preview repo). Navigate to the tool's auth screen. Click the "Sign in with Microsoft" button. Verify:
  - The button immediately changes to a spinner + "Signing in…"
  - The button is disabled while the MSAL popup is open
  - On successful sign-in: button restores momentarily, then the auth screen hides
  - On cancel (close popup): button restores to original state, no error shown (MSAL returns a cancelled error — verify the authErr element shows the cancellation message or stays hidden depending on error type)

- [ ] **Step 10: Commit**

  ```bash
  git add tools/license-audit/index.html tools/mfa-status/index.html tools/guest-audit/index.html tools/name-resolver/index.html
  git commit -m "feat: wire withButtonSpinner to sign-in buttons across 4 tools"
  ```

---

## Task 4: Wire Group Import — Lookup Button

`lookupGroup()` already manually disables `lookupBtn` and shows `#lookupPhase` text. This task replaces the manual button-state with `withButtonSpinner` (adds animated spinner to the button itself) while keeping the existing `#lookupPhase` text line for the lookup status message.

**Files:**
- Modify: `tools/group-import/index.html` — `lookupGroup()` (~line 425)

- [ ] **Step 1: Replace `lookupGroup()` with the version below**

  Find the full `lookupGroup()` function and replace it entirely:

  ```js
  async function lookupGroup() {
    const input = document.getElementById("groupIn").value.trim();
    if (!input) { showErr("s2Err", "Enter a group name or GUID."); return; }
    document.getElementById("s2Err").style.display     = "none";
    document.getElementById("groupOk").style.display    = "none";
    document.getElementById("resolveCard").style.display = "none";
    document.getElementById("s2Btn").disabled            = true;
    document.getElementById("lookupPhase").classList.add("show");
    try {
      await ITTools.ui.withButtonSpinner(
        document.getElementById("lookupBtn"),
        async () => {
          let group;
          if (/^[0-9a-f-]{36}$/i.test(input)) {
            group = await ITTools.graph.get(`/groups/${input}`);
          } else {
            const escaped = input.replace(/'/g, "''");
            const res = await ITTools.graph.get(
              `/groups?$filter=displayName eq '${encodeURIComponent(escaped)}'&$count=true&$top=5`
            );
            if (!res.value?.length) throw new Error(`No group found named "${input}".`);
            group = res.value[0];
          }
          st.groupId   = group.id;
          st.groupName = group.displayName;
          document.getElementById("groupOkName").textContent   = group.displayName;
          document.getElementById("groupOkId").textContent     = group.id;
          document.getElementById("groupOk").style.display     = "block";
          document.getElementById("resolveCard").style.display = "block";
          document.getElementById("s2Btn").disabled            = false;
        },
        "Looking up…",
        [document.getElementById("groupIn")]
      );
    } catch(e) {
      showErr("s2Err", e.message);
      st.groupId = "";
    } finally {
      document.getElementById("lookupPhase").classList.remove("show");
    }
  }
  ```

  Key changes from the original:
  - Removed `document.getElementById("lookupBtn").disabled = true/false` from outer function — `withButtonSpinner` handles button state
  - `groupIn` (the input field) is passed as `disableEls` so it's disabled during the lookup
  - `#lookupPhase` show/hide remains in the outer try/finally — it provides the text status alongside the button spinner
  - The `finally` block no longer manually re-enables `lookupBtn` (handled by `withButtonSpinner`)

- [ ] **Step 2: Verify in browser**

  Open Group Import, sign in. In Step 2, type a group name and click "Look up". Verify:
  - The button shows spinner + "Looking up…" immediately
  - The group name input is disabled during the lookup
  - On success: button restores, input re-enables, group card appears
  - On not-found error: button restores, input re-enables, error message shows

- [ ] **Step 3: Commit**

  ```bash
  git add tools/group-import/index.html
  git commit -m "feat: wire withButtonSpinner to group-import lookup button"
  ```

---

## Note: Name Resolver Retry Button

The spec listed the per-row retry button (`retryRow()`) as a wiring target. This is intentionally excluded from the plan.

When `retryRow(i)` is called, its first action is `tr.outerHTML = renderRow(i)` — which replaces the entire row (including the retry button) in the DOM before any async work starts. The original `btn` element is immediately detached. `withButtonSpinner` would operate on a detached element and produce no visible effect.

The existing UX is already sufficient: the row is immediately re-rendered to a "pending" state by `renderRow`, giving the user visual feedback that the retry is in progress. No change needed.

---

## Rollup Verification

After all tasks are committed, do a final pass across all affected tools before pushing to the preview branch.

- [ ] **Verify License Audit** — sign in, run an audit, open removal modal, confirm removal on a test user (or cancel to just see the spinner appear and restore)
- [ ] **Verify MFA Status** — sign-out if already signed in, click sign-in, confirm spinner appears on button during popup
- [ ] **Verify Guest Audit** — same sign-in spinner check
- [ ] **Verify Name Resolver** — same sign-in spinner check
- [ ] **Verify Group Import** — look up a known group, confirm button + input disable during lookup
- [ ] **Check dark mode** — toggle theme on any tool and verify the spinner `.spinner` border colors look correct (uses `var(--border)` and `var(--blue)` from shared styles — should theme-adapt automatically)

- [ ] **Push to preview branch and verify live**

  ```bash
  cd /c/dev/projects/it-tools
  git push origin testing
  ```

  Then check the preview site (`jgdev-ch.github.io/it-tools-preview/`) and repeat the key interactions.
