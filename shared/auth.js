/**
 * shared/auth.js
 * Centralised MSAL auth + Microsoft Graph helpers for it-tools.
 * All tools import this file — never duplicate auth logic per tool.
 *
 * Usage:
 *   <script src="../../shared/auth.js"></script>
 *   Then call: ITTools.auth.init(config)
 *              ITTools.auth.signIn()
 *              ITTools.graph.get(url)   // auto-attaches token
 *              ITTools.graph.getAll(url)
 *              ITTools.graph.post(url, body)
 *              ITTools.graph.del(url)
 */

window.ITTools = window.ITTools || {};

// ─────────────────────────────────────────────────────────────
//  CONSTANTS
// ─────────────────────────────────────────────────────────────
ITTools.TENANT_ID  = "683d57e7-70bf-4bc4-b88d-bd8905a0c39a";
ITTools.CLIENT_ID  = "6d881af5-d626-4df6-8969-69f1f0292772";
ITTools.BASE_SCOPES = ["User.Read"];

// ─────────────────────────────────────────────────────────────
//  AUTH MODULE
// ─────────────────────────────────────────────────────────────
ITTools.auth = (() => {
  let _msal    = null;
  let _account = null;
  let _scopes  = [];

  /**
   * init({ scopes, onSignIn, onSignOut })
   * Call once on page load. Handles popup callback detection,
   * restores cached session, and calls onSignIn if already logged in.
   */
  async function init({ scopes = [], onSignIn, onSignOut } = {}) {
    _scopes = [...ITTools.BASE_SCOPES, ...scopes];

    // If we're inside an MSAL popup callback, hand off and stop
    if (window.opener && window.opener !== window) {
      const tmp = new msal.PublicClientApplication({
        auth: {
          clientId:    ITTools.CLIENT_ID,
          authority:   `https://login.microsoftonline.com/${ITTools.TENANT_ID}`,
          redirectUri: window.location.origin + window.location.pathname,
        },
        cache: { cacheLocation: "localStorage" }
      });
      await tmp.initialize();
      await tmp.handleRedirectPromise();
      throw new Error("MSAL popup callback — stopping render.");
    }

    _msal = new msal.PublicClientApplication({
      auth: {
        clientId:    ITTools.CLIENT_ID,
        authority:   `https://login.microsoftonline.com/${ITTools.TENANT_ID}`,
        redirectUri: window.location.origin + window.location.pathname,
      },
      cache: { cacheLocation: "localStorage", storeAuthStateInCookie: false }
    });

    await _msal.initialize();

    try {
      const r = await _msal.handleRedirectPromise();
      if (r) {
        _account = r.account;
        onSignIn?.(_account);
        ITTools.auth._onSignOut = onSignOut;
        return;
      }
    } catch (e) {
      console.warn("[ITTools.auth] handleRedirectPromise error:", e);
    }

    const accounts = _msal.getAllAccounts();
    if (accounts.length > 0) {
      _account = accounts[0];
      onSignIn?.(_account);
    }

    // Expose sign-out callback for later use
    ITTools.auth._onSignOut = onSignOut;
  }

  async function signIn() {
    const r = await _msal.loginPopup({ scopes: _scopes });
    _account = r.account;
    return _account;
  }

  async function signOut() {
    await _msal.logoutPopup({ account: _account });
    _account = null;
    ITTools.auth._onSignOut?.();
  }

  async function getToken() {
    if (!_account) throw new Error("Not signed in.");
    try {
      const r = await _msal.acquireTokenSilent({ scopes: _scopes, account: _account });
      return r.accessToken;
    } catch (silentErr) {
      try {
        const r = await _msal.acquireTokenPopup({ scopes: _scopes, account: _account });
        return r.accessToken;
      } catch (popupErr) {
        throw popupErr;
      }
    }
  }

  function getAccount()   { return _account; }
  function isSignedIn()   { return !!_account; }
  function redirectUri()  { return window.location.origin + window.location.pathname; }

  return { init, signIn, signOut, getToken, getAccount, isSignedIn, redirectUri };
})();

// ─────────────────────────────────────────────────────────────
//  GRAPH MODULE
// ─────────────────────────────────────────────────────────────
ITTools.graph = (() => {
  const BASE = "https://graph.microsoft.com/v1.0";

  async function _headers(extra = {}) {
    const token = await ITTools.auth.getToken();
    return { Authorization: "Bearer " + token, ConsistencyLevel: "eventual", ...extra };
  }

  async function _checkResponse(res) {
    if (res.status === 204) return null;
    if (res.ok) return res.json().catch(() => null);
    const body = await res.json().catch(() => ({}));
    const msg  = body?.error?.message || `Graph error ${res.status}`;
    if (res.status === 403) throw new Error("Permission denied — " + msg + ". Check your Entra app registration consents.");
    if (res.status === 429) throw new Error("Rate limited by Microsoft Graph. Try again in a moment.");
    throw new Error(msg);
  }

  async function get(url) {
    const res = await fetch(url.startsWith("http") ? url : BASE + url, { headers: await _headers() });
    return _checkResponse(res);
  }

  /** Follows @odata.nextLink until all pages are loaded */
  async function getAll(url) {
    let items = [], next = url.startsWith("http") ? url : BASE + url;
    while (next) {
      const page = await get(next);
      items = items.concat(page?.value || []);
      next  = page?.["@odata.nextLink"] || null;
    }
    return items;
  }

  async function post(url, body) {
    const res = await fetch(url.startsWith("http") ? url : BASE + url, {
      method:  "POST",
      headers: await _headers({ "Content-Type": "application/json" }),
      body:    JSON.stringify(body),
    });
    return _checkResponse(res);
  }

  async function patch(url, body) {
    const res = await fetch(url.startsWith("http") ? url : BASE + url, {
      method:  "PATCH",
      headers: await _headers({ "Content-Type": "application/json" }),
      body:    JSON.stringify(body),
    });
    return _checkResponse(res);
  }

  async function del(url) {
    const res = await fetch(url.startsWith("http") ? url : BASE + url, {
      method:  "DELETE",
      headers: await _headers(),
    });
    return _checkResponse(res);
  }

  return { get, getAll, post, patch, del };
})();

// ─────────────────────────────────────────────────────────────
//  THEME MODULE
// ─────────────────────────────────────────────────────────────
ITTools.theme = (() => {
  function init() {
    const saved = localStorage.getItem("it-tools-theme") ||
      (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    apply(saved);
  }

  function apply(t) {
    document.documentElement.setAttribute("data-theme", t);
    localStorage.setItem("it-tools-theme", t);
  }

  function toggle() {
    const cur = document.documentElement.getAttribute("data-theme");
    apply(cur === "dark" ? "light" : "dark");
    return cur === "dark" ? "light" : "dark";
  }

  function current() {
    return document.documentElement.getAttribute("data-theme") || "light";
  }

  return { init, apply, toggle, current };
})();

// ─────────────────────────────────────────────────────────────
//  UI HELPERS
// ─────────────────────────────────────────────────────────────
ITTools.ui = (() => {

  /** Render the standard topbar into #topbar.
   *  Expects: <div id="topbar"></div> in the page.
   *  toolName: short display name e.g. "License Audit"
   *  hubRelPath: relative path back to index.html e.g. "../../"
   */
  function renderTopbar({ toolName, hubRelPath = "../../", status = "", scopes = [], onReady } = {}) {
    const el = document.getElementById("topbar");
    if (!el) return;

    const betaBadge = status === "beta"
      ? `<span class="tool-beta-badge">Beta</span>`
      : "";

    el.innerHTML = `
      <div class="topbar-brand">
        <a href="${hubRelPath}" class="brand-hub-link" title="Back to IT Tools hub">
          <svg viewBox="0 0 23 23" width="20" height="20" fill="none">
            <rect x="1"  y="1"  width="10" height="10" fill="#f25022"/>
            <rect x="12" y="1"  width="10" height="10" fill="#7fba00"/>
            <rect x="1"  y="12" width="10" height="10" fill="#00a4ef"/>
            <rect x="12" y="12" width="10" height="10" fill="#ffb900"/>
          </svg>
          <span class="brand-hub-text">IT Tools</span>
        </a>
        <span class="brand-separator">/</span>
        <span class="brand-tool">${toolName}</span>
        ${betaBadge}
      </div>
      <div class="topbar-right">
        <button class="btn-icon" id="themeBtn" title="Toggle theme" onclick="ITTools.theme.toggle(); ITTools.ui.syncThemeIcon()">
          <svg id="themeIcon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16"></svg>
        </button>
        <div class="user-chip" id="userChip" style="display:none">
          <div class="user-avatar" id="userInitials"></div>
          <span id="userName"></span>
        </div>
        <button class="btn-sm-ghost" id="signOutBtn" onclick="ITTools.auth.signOut()" style="display:none">Sign out</button>
      </div>
    `;

    syncThemeIcon();
  }

  function syncThemeIcon() {
    const icon = document.getElementById("themeIcon");
    if (!icon) return;
    if (ITTools.theme.current() === "dark") {
      icon.innerHTML = `<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" stroke="currentColor" stroke-width="2" fill="none"/>`;
    } else {
      icon.innerHTML = `<circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>`;
    }
  }

  function setUser(account) {
    if (!account) return;
    const name = account.name || account.username || "User";
    const initials = name.split(" ").map(n => n[0]).join("").slice(0, 2).toUpperCase();
    const chip = document.getElementById("userChip");
    const btn  = document.getElementById("signOutBtn");
    if (chip) { document.getElementById("userInitials").textContent = initials; document.getElementById("userName").textContent = name; chip.style.display = "flex"; }
    if (btn)  btn.style.display = "block";
  }

  function clearUser() {
    const chip = document.getElementById("userChip");
    const btn  = document.getElementById("signOutBtn");
    if (chip) chip.style.display = "none";
    if (btn)  btn.style.display  = "none";
  }

  /** Show/hide a banner element. type: "error"|"warn"|"info"|"success" */
  function banner(id, msg, type = "error") {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent  = msg;
    el.className    = "banner " + type;
    el.style.display = msg ? "block" : "none";
  }

  function spinner(show, labelId, msg = "") {
    const el = document.getElementById(labelId);
    if (!el) return;
    el.textContent  = msg;
    el.style.display = show ? "flex" : "none";
  }

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
    const wrap = document.createElement("span");
    wrap.style.cssText = "display:inline-flex;align-items:center;gap:6px";
    const spin = document.createElement("span");
    spin.className = "spinner";
    spin.style.cssText = "width:12px;height:12px;border-width:2px";
    wrap.appendChild(spin);
    wrap.appendChild(document.createTextNode(loadingText));
    btn.innerHTML = "";
    btn.appendChild(wrap);
    disableEls.forEach(el => (el.disabled = true));
    try {
      return await asyncFn();
    } finally {
      btn.innerHTML = orig;
      btn.disabled  = false;
      disableEls.forEach(el => (el.disabled = false));
    }
  }

  return { renderTopbar, syncThemeIcon, setUser, clearUser, banner, spinner, withButtonSpinner };
})();

// ─────────────────────────────────────────────────────────────
//  CSV HELPERS
// ─────────────────────────────────────────────────────────────
ITTools.csv = (() => {

  function parse(text) {
    const lines = text.split(/\r?\n/).filter(l => l.trim());
    if (lines.length < 2) throw new Error("CSV must have a header row and at least one data row.");
    const headers = parseLine(lines[0]);
    const rows = [];
    for (let i = 1; i < lines.length; i++) {
      const vals = parseLine(lines[i]);
      if (!vals.length) continue;
      const row = {};
      headers.forEach((h, idx) => row[h] = vals[idx] ?? "");
      rows.push(row);
    }
    return { headers, rows };
  }

  function parseLine(line) {
    const result = [];
    let cur = "", inQ = false;
    for (const ch of line) {
      if (ch === '"') inQ = !inQ;
      else if (ch === ',' && !inQ) { result.push(cur.trim()); cur = ""; }
      else cur += ch;
    }
    result.push(cur.trim());
    return result;
  }

  function detectEmailColumn(headers, rows) {
    const emailNames = ["email","mail","userprincipalname","upn","emailaddress","emailid"];
    for (const h of headers) {
      if (emailNames.includes(h.toLowerCase().replace(/\s/g, ""))) return h;
    }
    for (const h of headers) {
      if (rows.slice(0, 10).some(r => String(r[h] || "").includes("@"))) return h;
    }
    return headers[0];
  }

  /** Build and trigger a CSV download from an array of objects */
  function download(filename, rows) {
    if (!rows.length) return;
    const headers = Object.keys(rows[0]);
    const lines   = [headers, ...rows.map(r => headers.map(h => r[h] ?? ""))]
      .map(r => r.map(v => '"' + String(v).replace(/"/g, '""') + '"').join(","))
      .join("\n");
    const a = Object.assign(document.createElement("a"), {
      href:     URL.createObjectURL(new Blob([lines], { type: "text/csv" })),
      download: filename,
    });
    a.click();
  }

  return { parse, parseLine, detectEmailColumn, download };
})();
