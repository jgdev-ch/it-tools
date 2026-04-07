# Friendly Error Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ITTools.graph.friendlyError(err)` to `shared/auth.js` and wire it into every Graph API catch block across all 6 tools, replacing raw `e.message` strings with consistent, actionable user-facing text.

**Architecture:** One new function in the `ITTools.graph` IIFE classifies thrown values by type/message and returns a friendly string; all tool catch blocks call it instead of using `e.message` directly. No new files, no new UI elements — the existing `#errBanner` and `showErr()` infrastructure is unchanged.

**Tech Stack:** Vanilla JS, no build tools, no test framework — verification uses console assertions pasted into a browser tab running the tool.

---

## File Map

| File | Change |
|------|--------|
| `shared/auth.js` | Add `friendlyError` function inside `ITTools.graph` IIFE; expose in return object |
| `tools/license-audit/index.html` | 2 catch blocks (`runAudit`, `runMultiLicenseAudit`) |
| `tools/finance-dashboard/index.html` | 1 catch block (`loadDashboard`) |
| `tools/mfa-status/index.html` | 1 catch block (`startScan`) |
| `tools/guest-audit/index.html` | 1 catch block (`startScan` — else branch only; 403 custom text preserved) |
| `tools/group-import/index.html` | 2 catch blocks (`lookupGroup`, `runImport`) |
| `tools/name-resolver/index.html` | 1 new catch block wrapping `resolveBatch()` in `startResolve` |

---

### Task 1: Add `ITTools.graph.friendlyError` to `shared/auth.js`

**Files:**
- Modify: `shared/auth.js` (around line 186 — end of `ITTools.graph` IIFE)

- [ ] **Step 1: Write console verification script**

  Save this snippet to the clipboard — you'll paste it into a browser console in Step 4 to verify the function works.

  ```js
  const fe = ITTools.graph.friendlyError;
  console.assert(fe(new TypeError("Failed to fetch")).includes("internet connection"),      "FAIL: network TypeError");
  console.assert(fe(new Error("NetworkError when attempting to fetch resource")).includes("internet connection"), "FAIL: NetworkError msg");
  console.assert(fe(new Error("Load failed")).includes("internet connection"),              "FAIL: Load failed");
  console.assert(fe(new Error("Graph error 503")).includes("temporarily unavailable"),      "FAIL: 503");
  console.assert(fe(new Error("502 Bad Gateway")).includes("temporarily unavailable"),      "FAIL: 502");
  console.assert(fe(new Error("Rate limited by Microsoft Graph. Try again in a moment.")).includes("rate limiting"), "FAIL: rate limited msg");
  console.assert(fe(new Error("429 Too Many Requests")).includes("rate limiting"),          "FAIL: 429");
  console.assert(fe(new Error("401 Unauthorized")).includes("session has expired"),         "FAIL: 401");
  console.assert(fe(new Error("Not signed in")).includes("session has expired"),            "FAIL: not signed in");
  console.assert(fe(new Error("Permission denied — you need User.Read.All")).includes("Permission denied"), "FAIL: passthrough");
  console.assert(fe("some raw string") === "some raw string",                              "FAIL: raw string passthrough");
  console.assert(fe(null) === "An unexpected error occurred.",                             "FAIL: null returns fallback");
  console.log("✓ All friendlyError assertions passed");
  ```

- [ ] **Step 2: Implement `friendlyError` in `shared/auth.js`**

  In `shared/auth.js`, find the end of the `ITTools.graph` IIFE (currently around line 186):

  ```js
    return { get, getAll, post, patch, del };
  })();
  ```

  Replace it with:

  ```js
    function friendlyError(err) {
      const msg = err instanceof Error ? err.message : (typeof err === "string" ? err : "");
      if (err instanceof TypeError || /Failed to fetch|NetworkError|Load failed/i.test(msg)) {
        return "Unable to reach Microsoft Graph — check your internet connection and try again.";
      }
      if (/503|502|Service Unavailable/i.test(msg)) {
        return "Microsoft Graph is temporarily unavailable. Try again in a few minutes.";
      }
      if (/429|Rate limited|Too Many Requests/i.test(msg)) {
        return "Microsoft Graph is rate limiting requests. Wait a moment and try again.";
      }
      if (/401|Not signed in/i.test(msg)) {
        return "Your session has expired. Please sign out and sign in again.";
      }
      return msg;
    }

    return { get, getAll, post, patch, del, friendlyError };
  })();
  ```

- [ ] **Step 3: Verify the function exists**

  Open any tool in the preview browser (e.g., license-audit). Open DevTools console. Type:

  ```
  typeof ITTools.graph.friendlyError
  ```

  Expected: `"function"`

  If it shows `undefined`, check that the edit was saved and the page refreshed.

- [ ] **Step 4: Run verification script**

  Paste the full snippet from Step 1 into the console.

  Expected output (no assertion errors):
  ```
  ✓ All friendlyError assertions passed
  ```

  If any assertion fires, re-read the function body and fix the regex or condition that failed.

- [ ] **Step 5: Commit**

  ```bash
  cd /c/dev/projects/it-tools
  git add shared/auth.js
  git commit -m "feat: add ITTools.graph.friendlyError() for user-friendly Graph error classification"
  ```

---

### Task 2: Wire `#errBanner` tools — license-audit, finance-dashboard, mfa-status, guest-audit

**Files:**
- Modify: `tools/license-audit/index.html`
- Modify: `tools/finance-dashboard/index.html`
- Modify: `tools/mfa-status/index.html`
- Modify: `tools/guest-audit/index.html`

**Context:** Each of these tools has a `<div class="banner error" id="errBanner">` element. Their main scan catch blocks set `errBanner.textContent = e.message`. Replace with `ITTools.graph.friendlyError(e)`.

- [ ] **Step 1: Edit `tools/license-audit/index.html` — `runAudit()` catch**

  Find (around line 889):
  ```js
    } catch(e) {
      document.getElementById("errBanner").textContent   = e.message;
      document.getElementById("errBanner").style.display = "block";
    } finally {
      setPhase(null);
  ```

  Replace with:
  ```js
    } catch(e) {
      document.getElementById("errBanner").textContent   = ITTools.graph.friendlyError(e);
      document.getElementById("errBanner").style.display = "block";
    } finally {
      setPhase(null);
  ```

- [ ] **Step 2: Edit `tools/license-audit/index.html` — `runMultiLicenseAudit()` catch**

  Find (around line 1253):
  ```js
    } catch(e) {
      document.getElementById("errBanner").textContent   = e.message;
      document.getElementById("errBanner").style.display = "block";
    } finally {
      setPhase(null);
  ```

  Replace with:
  ```js
    } catch(e) {
      document.getElementById("errBanner").textContent   = ITTools.graph.friendlyError(e);
      document.getElementById("errBanner").style.display = "block";
    } finally {
      setPhase(null);
  ```

- [ ] **Step 3: Edit `tools/finance-dashboard/index.html` — `loadDashboard()` catch**

  Find (around line 979):
  ```js
    } catch(e) {
      document.getElementById("errBanner").textContent   = e.message;
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
    }
  ```

- [ ] **Step 4: Edit `tools/mfa-status/index.html` — `startScan()` catch**

  Find (around line 621):
  ```js
    } catch(e) {
      document.getElementById("errBanner").textContent   = e.message;
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
    }
  ```

- [ ] **Step 5: Edit `tools/guest-audit/index.html` — `startScan()` catch, else branch only**

  Find (around line 484):
  ```js
    } catch(e) {
      if (e.message === "Scan cancelled") { setPhase(null); return; }
      const banner = document.getElementById("errBanner");
      if (e.message && e.message.includes("403")) {
        banner.textContent = "Permission denied — check Graph API consents in your Entra app registration (User.Read.All, User.ReadWrite.All, Directory.Read.All, AuditLog.Read.All).";
      } else {
        banner.textContent = e.message || "An unexpected error occurred.";
      }
      banner.className     = "banner error";
      banner.style.display = "block";
      setPhase(null);
    }
  ```

  Replace **only the `else` branch** (`e.message || "An unexpected error occurred."`) — leave the 403 branch and all surrounding code exactly as-is:
  ```js
    } catch(e) {
      if (e.message === "Scan cancelled") { setPhase(null); return; }
      const banner = document.getElementById("errBanner");
      if (e.message && e.message.includes("403")) {
        banner.textContent = "Permission denied — check Graph API consents in your Entra app registration (User.Read.All, User.ReadWrite.All, Directory.Read.All, AuditLog.Read.All).";
      } else {
        banner.textContent = ITTools.graph.friendlyError(e);
      }
      banner.className     = "banner error";
      banner.style.display = "block";
      setPhase(null);
    }
  ```

- [ ] **Step 6: Smoke test in preview browser**

  Open each of the 4 tools in the preview. Open DevTools, Network tab. To simulate a network error without breaking auth:

  1. Sign in normally.
  2. In DevTools Network tab, block the Graph API domain: right-click any `graph.microsoft.com` request → Block request domain.
  3. Click Scan/Run.
  4. Verify `#errBanner` shows: `"Unable to reach Microsoft Graph — check your internet connection and try again."`
  5. Un-block the domain when done.

  If the banner shows a raw JS error string instead, check that the edit in the catch block is correct and the page has been reloaded.

- [ ] **Step 7: Commit**

  ```bash
  cd /c/dev/projects/it-tools
  git add tools/license-audit/index.html tools/finance-dashboard/index.html tools/mfa-status/index.html tools/guest-audit/index.html
  git commit -m "feat: wire friendlyError into errBanner catch blocks — license-audit, finance-dashboard, mfa-status, guest-audit"
  ```

---

### Task 3: Wire group-import and name-resolver

**Files:**
- Modify: `tools/group-import/index.html`
- Modify: `tools/name-resolver/index.html`

**Context:** Group Import uses `showErr(id, msg)` instead of `#errBanner` directly. Name Resolver's `startResolve()` currently has no catch around `resolveBatch()` — a thrown error propagates unhandled. This task adds the missing catch and wires both files.

- [ ] **Step 1: Edit `tools/group-import/index.html` — `lookupGroup()` catch**

  Find (around line 459):
  ```js
    } catch(e) {
      showErr("s2Err", e.message);
      st.groupId = "";
    }
  ```

  Replace with:
  ```js
    } catch(e) {
      showErr("s2Err", ITTools.graph.friendlyError(e));
      st.groupId = "";
    }
  ```

- [ ] **Step 2: Edit `tools/group-import/index.html` — `runImport()` catch**

  Find (around line 514):
  ```js
    } catch(e) { showErr("s3Err","Could not load existing members: "+e.message); }
  ```

  Replace with:
  ```js
    } catch(e) { showErr("s3Err","Could not load existing members: "+ITTools.graph.friendlyError(e)); }
  ```

- [ ] **Step 3: Edit `tools/name-resolver/index.html` — wrap `resolveBatch()` in try/catch**

  In `startResolve()`, find the `await resolveBatch(...)` call and the two lines that follow it (around line 793):
  ```js
    await resolveBatch({
      onProgress: (done, total) => {
        const pct = Math.round(done / total * 100);
        document.getElementById("progFill").style.width = pct + "%";
        document.getElementById("progPct").textContent  = pct + "%";
        document.getElementById("progLabel").textContent = done + " of " + total + " resolved…";
      },
      onThrottle: (secs) => {
        document.getElementById("progLabel").textContent = "Rate limit — retrying in " + secs + "s…";
      },
      onRowDone: (idx) => {
        // Replace just this row (and any expand row) by rebuilding from its id
        const tr = document.getElementById("row-" + idx);
        if (tr) {
          // Remove stale expand row if present
          const exp = document.getElementById("expand-" + idx);
          if (exp) exp.remove();
          tr.outerHTML = renderRow(idx);
        }
      },
      onAuthError: () => {
        showErr("s2Err", "Session expired — please sign out and sign back in to continue.");
      }
    });

    document.getElementById("progLabel").textContent = "Done";
    checkAllResolved();
  ```

  Replace with:
  ```js
    try {
      await resolveBatch({
        onProgress: (done, total) => {
          const pct = Math.round(done / total * 100);
          document.getElementById("progFill").style.width = pct + "%";
          document.getElementById("progPct").textContent  = pct + "%";
          document.getElementById("progLabel").textContent = done + " of " + total + " resolved…";
        },
        onThrottle: (secs) => {
          document.getElementById("progLabel").textContent = "Rate limit — retrying in " + secs + "s…";
        },
        onRowDone: (idx) => {
          // Replace just this row (and any expand row) by rebuilding from its id
          const tr = document.getElementById("row-" + idx);
          if (tr) {
            // Remove stale expand row if present
            const exp = document.getElementById("expand-" + idx);
            if (exp) exp.remove();
            tr.outerHTML = renderRow(idx);
          }
        },
        onAuthError: () => {
          showErr("s2Err", "Session expired — please sign out and sign back in to continue.");
        }
      });
    } catch(e) {
      showErr("s2Err", ITTools.graph.friendlyError(e));
      return;
    }

    document.getElementById("progLabel").textContent = "Done";
    checkAllResolved();
  ```

- [ ] **Step 4: Smoke test group-import**

  Open Group Import in the preview browser. Sign in. In DevTools Network, block `graph.microsoft.com`. Enter a group name and click Find.

  Expected: the Step 2 error banner shows `"Unable to reach Microsoft Graph — check your internet connection and try again."`

  Un-block the domain and verify a normal lookup still works (finds the group correctly).

- [ ] **Step 5: Smoke test name-resolver**

  Open Name Resolver in the preview browser. Sign in and upload a CSV. In DevTools Network, block `graph.microsoft.com`. Click Resolve.

  Expected: the Step 2 banner shows `"Unable to reach Microsoft Graph — check your internet connection and try again."`

  Un-block and verify a normal run still resolves names correctly.

- [ ] **Step 6: Commit**

  ```bash
  cd /c/dev/projects/it-tools
  git add tools/group-import/index.html tools/name-resolver/index.html
  git commit -m "feat: wire friendlyError into catch blocks — group-import and name-resolver"
  ```

---

## Self-Review

**Spec coverage:**
- ✅ `ITTools.graph.friendlyError(err)` added to `shared/auth.js` → Task 1
- ✅ TypeError / "Failed to fetch" / "NetworkError" / "Load failed" → connectivity message → Task 1 Step 2
- ✅ 503 / 502 / "Service Unavailable" → unavailable message → Task 1 Step 2
- ✅ 429 / "Rate limited" / "Too Many Requests" → rate limit message → Task 1 Step 2
- ✅ 401 / "Not signed in" → session expired message → Task 1 Step 2
- ✅ Everything else → passthrough `err.message` → Task 1 Step 2
- ✅ Function never throws; handles non-Error values → Task 1 Step 2 (raw string / null cases)
- ✅ license-audit `runAudit()` → Task 2 Step 1
- ✅ license-audit `runMultiLicenseAudit()` → Task 2 Step 2
- ✅ finance-dashboard `loadDashboard()` → Task 2 Step 3
- ✅ mfa-status `startScan()` → Task 2 Step 4
- ✅ guest-audit `startScan()` 403 branch preserved, else branch wired → Task 2 Step 5
- ✅ group-import `lookupGroup()` → Task 3 Step 1
- ✅ group-import `runImport()` → Task 3 Step 2
- ✅ name-resolver batch error surface → Task 3 Step 3
- ✅ `graphWithRetry` / `gwr` retry logic untouched — not referenced in any task
- ✅ `_checkResponse` untouched — passthrough case returns `err.message` from `_checkResponse`-formatted errors
- ✅ `showErr()` helpers untouched — only the argument changes
- ✅ No HTML changes — `#errBanner` elements and `showErr()` signatures unchanged
