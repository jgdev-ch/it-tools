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
    ITTools.ui.clearUser?.();
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
    return msg || "An unexpected error occurred.";
  }

  return { get, getAll, post, patch, del, friendlyError };
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

  let _listenersAdded = false;

  const GROUP_GATE_IDS = {
    finance:           "ff9c3232-251f-4570-9564-340039d17aa9",
    reporting:         "cea8f0fe-a3d5-4f8a-9f77-e9ce6fdf7b8d",
    gsd:               "3e1a4757-8189-4908-a611-b6029399e69e",
    "license-modify":  "d98cbaa9-da66-4d1a-8a31-2442b7cc0ca8",
  };

  const PILL_DEFS = {
    finance: {
      label: "Finance View",
      cls:   "account-pill--amber",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8"/><path d="M12 18V6"/></svg>`,
    },
    reporting: {
      label: "Reporting View",
      cls:   "account-pill--blue",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>`,
    },
    gsd: {
      label: "GSD Access",
      cls:   "account-pill--blue",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>`,
    },
    "license-modify": {
      label: "License Admin",
      cls:   "account-pill--amber",
      icon:  `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/></svg>`,
    },
  };

  function _toggleAccountDropdown() {
    const dropdown = document.getElementById("accountDropdown");
    const btn      = document.getElementById("accountBtn");
    if (!dropdown || !btn) return;
    const isOpen   = dropdown.style.display !== "none";
    dropdown.style.display = isOpen ? "none" : "block";
    btn.classList.toggle("open", !isOpen);
    btn.setAttribute("aria-expanded", String(!isOpen));
  }

  async function _loadGatePills() {
    try {
      const token = await ITTools.auth.getToken();
      const res = await fetch("https://graph.microsoft.com/v1.0/me/checkMemberObjects", {
        method:  "POST",
        headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
        body:    JSON.stringify({ ids: Object.values(GROUP_GATE_IDS) }),
      });
      if (!res.ok) return;
      const data        = await res.json();
      const unlockedIds = new Set(data.value || []);
      const unlockedKeys = Object.entries(GROUP_GATE_IDS)
        .filter(([, id]) => unlockedIds.has(id))
        .map(([key]) => key);
      _renderPills(unlockedKeys);
    } catch (err) { console.warn("[ITTools.ui] _loadGatePills failed:", err); }
  }

  function _renderPills(keys) {
    const pillsEl  = document.getElementById("accountPanelPills");
    const accessEl = document.getElementById("accountPanelAccess");
    if (!pillsEl || !accessEl) return;
    const pills = keys.filter(k => PILL_DEFS[k])
                      .sort((a, b) => PILL_DEFS[a].cls.localeCompare(PILL_DEFS[b].cls));
    if (!pills.length) { accessEl.style.display = "none"; return; }
    pillsEl.innerHTML = pills
      .map(k => `<span class="account-pill ${PILL_DEFS[k].cls}">${PILL_DEFS[k].icon} ${PILL_DEFS[k].label}</span>`)
      .join("");
    accessEl.style.display = "block";
  }

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
        <div style="position:relative" id="accountWrap">
          <button type="button" class="account-btn" id="accountBtn"
            style="display:none" aria-label="Account menu"
            aria-expanded="false" aria-controls="accountDropdown">
            <span id="accountInitials"></span>
          </button>
          <div class="account-dropdown" id="accountDropdown" style="display:none">
            <div class="account-panel-head">
              <div class="account-panel-avatar" id="accountPanelAvatar"></div>
              <div>
                <div class="account-panel-name" id="accountPanelName"></div>
                <div class="account-panel-email" id="accountPanelEmail"></div>
              </div>
            </div>
            <div class="account-panel-access" id="accountPanelAccess" style="display:none">
              <div class="account-panel-access-label">Access</div>
              <div class="account-panel-pills" id="accountPanelPills"></div>
            </div>
            <div class="account-panel-divider"></div>
            <button type="button" class="account-panel-signout" id="accountSignOutBtn">
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
              Sign out
            </button>
          </div>
        </div>
      </div>
    `;

    syncThemeIcon();

    document.getElementById("accountBtn").addEventListener("click", _toggleAccountDropdown);
    document.getElementById("accountSignOutBtn").addEventListener("click", () => ITTools.auth.signOut());
    if (!_listenersAdded) {
      _listenersAdded = true;
      document.addEventListener("click", e => {
        const dropdown = document.getElementById("accountDropdown");
        const btn      = document.getElementById("accountBtn");
        if (!dropdown || dropdown.style.display === "none") return;
        if (!dropdown.contains(e.target) && !btn.contains(e.target)) {
          dropdown.style.display = "none";
          btn.classList.remove("open");
          btn.setAttribute("aria-expanded", "false");
        }
      });
      document.addEventListener("keydown", e => {
        if (e.key !== "Escape") return;
        const dropdown = document.getElementById("accountDropdown");
        if (!dropdown || dropdown.style.display === "none") return;
        const btn = document.getElementById("accountBtn");
        dropdown.style.display = "none";
        if (btn) { btn.classList.remove("open"); btn.setAttribute("aria-expanded", "false"); }
      });
    }
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
    const btn = document.getElementById("accountBtn");
    if (!btn) return;
    const name     = account.name || account.username || "User";
    const email    = account.username || "";
    const initials = name.split(" ").map(n => n[0]).join("").slice(0, 2).toUpperCase();
    document.getElementById("accountInitials").textContent    = initials;
    document.getElementById("accountPanelAvatar").textContent = initials;
    document.getElementById("accountPanelName").textContent   = name;
    document.getElementById("accountPanelEmail").textContent  = email;
    btn.style.display = "flex";
    _loadGatePills();
  }

  function clearUser() {
    const btn      = document.getElementById("accountBtn");
    const dropdown = document.getElementById("accountDropdown");
    if (!btn) return;
    btn.style.display = "none";
    btn.classList.remove("open");
    btn.setAttribute("aria-expanded", "false");
    if (dropdown) dropdown.style.display = "none";
    const pillsEl  = document.getElementById("accountPanelPills");
    const accessEl = document.getElementById("accountPanelAccess");
    if (pillsEl)  pillsEl.innerHTML      = "";
    if (accessEl) accessEl.style.display = "none";
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
