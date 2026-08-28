/*
 * exo-scripts.js — Exchange Online script generator for the Group Administration tool.
 *
 * Pure string building: no DOM, no network, no ITTools dependency. Loadable in node
 * for verification (see docs/superpowers/plans/2026-08-28-group-admin-expansion-v2.md).
 *
 * TEMPLATE ESCAPING RULES (violating these silently corrupts generated scripts):
 *   - Never emit PowerShell ${var} syntax — "${" interpolates in JS template literals.
 *   - Write "\\" for every literal backslash (a lone "\" eats the next character).
 *   - Never emit PowerShell backticks: no line continuations, no `n. One line per cmdlet.
 *   - Every injected value goes through psStr().
 */
(function (root) {
  "use strict";

  // ── Low-level helpers ─────────────────────────────────────────
  /** Single-quoted PowerShell string literal, with '' doubling. */
  function psStr(value) {
    return "'" + String(value == null ? "" : value).replace(/'/g, "''") + "'";
  }

  /** Filename-safe slug for output names. */
  function slug(value) {
    const s = String(value == null ? "" : value)
      .replace(/[^A-Za-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 40);
    return s || "target";
  }

  /** Normalise to CRLF so the .ps1 and .bat behave on Windows. */
  function crlf(text) {
    return String(text).replace(/\r?\n/g, "\r\n");
  }

  // ── Operation labels + output filenames ───────────────────────
  const OP_LABELS = {
    members:     { add: "Add members", remove: "Remove members", export: "Export members" },
    permissions: { grant: "Grant access", remove: "Remove access", export: "Export access list" },
  };

  const SCRIPT_BASE = {
    "distribution-list": {
      add:    "Add-DistributionListMembers",
      remove: "Remove-DistributionListMembers",
      export: "Export-DistributionListMembers",
    },
    "mail-security-group": {
      add:    "Add-MailSecurityGroupMembers",
      remove: "Remove-MailSecurityGroupMembers",
      export: "Export-MailSecurityGroupMembers",
    },
    "shared-mailbox": {
      grant:  "Grant-SharedMailboxAccess",
      remove: "Remove-SharedMailboxAccess",
      export: "Export-SharedMailboxAccess",
    },
  };

  function isMailbox(typeId) { return typeId === "shared-mailbox"; }

  /**
   * buildContext({ typeId, typeLabel, op, target, targetDisplay, identities,
   *                perms:{full,sendAs,onBehalf}, autoMapping, tech }) -> ctx
   */
  function buildContext(input) {
    const typeId = input.typeId;
    const op     = input.op;
    const model  = isMailbox(typeId) ? "permissions" : "members";
    const base   = (SCRIPT_BASE[typeId] || {})[op];
    if (!base) throw new Error("Unsupported object type / operation: " + typeId + " / " + op);

    const now     = new Date();
    const target  = String(input.target || "").trim();
    const display = input.targetDisplay || target;
    const label   = input.typeLabel || typeId;
    const opLabel = OP_LABELS[model][op];

    return {
      typeId: typeId,
      op: op,
      model: model,
      opLabel: opLabel,
      typeLabel: label,
      title: label + ": " + opLabel.toLowerCase(),
      target: target,
      targetDisplay: display,
      targetSlug: slug(display),
      identities: (input.identities || []).slice(),
      perms: {
        full:     !!(input.perms && input.perms.full),
        sendAs:   !!(input.perms && input.perms.sendAs),
        onBehalf: !!(input.perms && input.perms.onBehalf),
      },
      autoMapping: input.autoMapping !== false,
      tech: input.tech || "unknown",
      timestamp: now.toISOString().replace("T", " ").slice(0, 19) + " UTC",
      dateOnly: now.toISOString().slice(0, 10),
      scriptName: base + ".ps1",
      batName: "Run-" + base + ".bat",
      zipName: base + "-" + slug(display) + "-" + now.toISOString().slice(0, 10) + ".zip",
      logBase: base,
    };
  }

  root.ExoScripts = {
    buildContext: buildContext,
    _psStr: psStr,
    _slug: slug,
    _crlf: crlf,
  };
})(typeof window !== "undefined" ? window : globalThis);
