# Auth Screen Consistency Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all 4 broken tool pages show their auth card when opened without a cached session, and standardize auth card icon backgrounds to `var(--blue-light)`.

**Architecture:** Each tool's `init()` function is patched with a `_sessionFound` flag that is set inside `onSignIn`. After `await ITTools.auth.init(...)` resolves, a fallback check shows `#authScreen` if the flag was never set. No changes to shared code.

**Tech Stack:** Vanilla HTML/JS. No build step. Open files directly in browser to verify.

---

### Task 1: Fix Group Import — `_sessionFound` guard + icon background

**Files:**
- Modify: `tools/group-import/index.html:72` (icon bg color)
- Modify: `tools/group-import/index.html:283-301` (init function)

- [ ] **Step 1: Fix the icon background color (line 72)**

Find this exact string on line 72:
```
background:var(--green-light);border-radius:11px;
```
Replace with:
```
background:var(--blue-light);border-radius:11px;
```

- [ ] **Step 2: Add `_sessionFound` guard to `init()` (lines 283–301)**

Find this exact block:
```js
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: acct => {
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
    }
  });
}
```

Replace with:
```js
  let _sessionFound = false;
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: acct => {
      _sessionFound = true;
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
    }
  });
  if (!_sessionFound) {
    document.getElementById("authScreen").style.display = "flex";
  }
}
```

- [ ] **Step 3: Verify manually**

Open `tools/group-import/index.html` directly in a browser (no cached session).
Expected: topbar visible, centered auth card visible with blue icon background, "Sign in with Microsoft" button present.
Expected: signing in from the card transitions to the app screen.

---

### Task 2: Fix License Audit — `_sessionFound` guard only

**Files:**
- Modify: `tools/license-audit/index.html:457-476` (init function)

- [ ] **Step 1: Add `_sessionFound` guard to `init()`**

Find this exact block:
```js
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: async acct => {
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
      await Promise.all([checkFinanceAccess(), loadSkus(), loadCosts()]);
      if (_hasFinanceAccess) {
        document.getElementById("financeIndicator").style.display = "inline-flex";
        rebuildDropdown();
      }
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
      _hasFinanceAccess = false;
    }
  });
}
```

Replace with:
```js
  let _sessionFound = false;
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: async acct => {
      _sessionFound = true;
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
      await Promise.all([checkFinanceAccess(), loadSkus(), loadCosts()]);
      if (_hasFinanceAccess) {
        document.getElementById("financeIndicator").style.display = "inline-flex";
        rebuildDropdown();
      }
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
      _hasFinanceAccess = false;
    }
  });
  if (!_sessionFound) {
    document.getElementById("authScreen").style.display = "flex";
  }
}
```

- [ ] **Step 2: Verify manually**

Open `tools/license-audit/index.html` directly in a browser (no cached session).
Expected: topbar visible, centered auth card visible with blue icon background (already was blue — no change), "Sign in with Microsoft" button present.
Expected: signing in from the card loads the license table.

---

### Task 3: Fix MFA Status — `_sessionFound` guard + icon background

**Files:**
- Modify: `tools/mfa-status/index.html:114` (icon bg color)
- Modify: `tools/mfa-status/index.html:334-347` (init function)

- [ ] **Step 1: Fix the icon background color (line 114)**

Find this exact string on line 114:
```
background:var(--red-light);border-radius:11px;display:flex;align-items:center;justify-content:center;margin:0 auto 1.25rem;font-size:22px
```
Replace with:
```
background:var(--blue-light);border-radius:11px;display:flex;align-items:center;justify-content:center;margin:0 auto 1.25rem;font-size:22px
```

- [ ] **Step 2: Add `_sessionFound` guard to `init()`**

Find this exact block:
```js
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: acct => {
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
    }
  });
}
```

Replace with:
```js
  let _sessionFound = false;
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: acct => {
      _sessionFound = true;
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
    }
  });
  if (!_sessionFound) {
    document.getElementById("authScreen").style.display = "flex";
  }
}
```

- [ ] **Step 3: Verify manually**

Open `tools/mfa-status/index.html` directly in a browser (no cached session).
Expected: topbar visible, centered auth card visible with blue icon background (🔑 emoji on blue, not red), "Sign in with Microsoft" button present.
Expected: signing in from the card loads the MFA report controls.

---

### Task 4: Fix Name Resolver — `_sessionFound` guard + opacity fallback

**Files:**
- Modify: `tools/name-resolver/index.html:379-394` (init function)

- [ ] **Step 1: Add `_sessionFound` guard and opacity reset to `init()`**

Find this exact block:
```js
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: acct => {
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
      document.body.style.opacity = "1";
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
      document.body.style.opacity = "1";
    }
  });
}
```

Replace with:
```js
  let _sessionFound = false;
  await ITTools.auth.init({
    scopes: TOOL_SCOPES,
    onSignIn: acct => {
      _sessionFound = true;
      document.getElementById("authScreen").style.display = "none";
      document.getElementById("appScreen").style.display  = "block";
      ITTools.ui.setUser(acct);
      document.body.style.opacity = "1";
    },
    onSignOut: () => {
      document.getElementById("appScreen").style.display  = "none";
      document.getElementById("authScreen").style.display = "flex";
      ITTools.ui.clearUser();
      document.body.style.opacity = "1";
    }
  });
  if (!_sessionFound) {
    document.getElementById("authScreen").style.display = "flex";
    document.body.style.opacity = "1";
  }
}
```

- [ ] **Step 2: Verify manually**

Open `tools/name-resolver/index.html` directly in a browser (no cached session).
Expected: page is visible immediately (no invisible flash), topbar present, centered auth card visible with blue icon background, "Sign in with Microsoft" button present.
Expected: signing in from the card loads the step sidebar and main content area.

---

### Task 5: Regression check + commit

- [ ] **Step 1: Regression check — sign in at hub first**

Open `index.html` (the hub), sign in, then click through to each of the 4 fixed tools.
Expected for each: auth card is NOT shown — app screen loads directly because the MSAL session is already cached.

- [ ] **Step 2: Commit**

```bash
git add tools/group-import/index.html \
        tools/license-audit/index.html \
        tools/mfa-status/index.html \
        tools/name-resolver/index.html
git commit -m "fix: show auth screen when tools opened without a session

All four tools were missing the post-init _sessionFound check that
Guest Access Audit already had. Without it, authScreen stayed hidden
when no MSAL session was cached, leaving users with a blank page.

Name Resolver also needed body opacity reset in the fallback.

Auth card icon backgrounds standardised to --blue-light across all tools."
```
