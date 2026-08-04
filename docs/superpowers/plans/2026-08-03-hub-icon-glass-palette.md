# Hub Icon Glass Treatment + Unique Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hub landing page's flat solid-color tool icon squares with a frosted "tinted glass" badge, and give all 9 tools a unique accent color (no two tools sharing a hue).

**Architecture:** Pure CSS + JSON config change, no JS logic changes. `index.html` gains 4 new theme-invariant `--accent-*` custom properties and a reworked `.tool-icon-sq` rule that derives the tint background, tint border, and icon stroke color from the existing per-card `--tool-accent` variable via `color-mix()`. `config.json` gets 4 tools repointed to their new accent variable. No changes to `unlockCard`/`lockCard`/`loadTools` JS — they already pass `accent` straight through to the CSS custom property.

**Tech Stack:** Static HTML/CSS/JS (no build step, no test framework). Verification is via Node syntax-check of inline `<script>` blocks (existing convention this session) and visual confirmation in a real browser (Playwright) on the `testing`/preview deploy, since this repo's landing page renders publicly without sign-in.

**Spec:** `docs/superpowers/specs/2026-08-03-hub-icon-glass-palette-design.md` (approved by Josh 2026-08-03)

---

### Task 1: Add the 4 new accent CSS variables

**Files:**
- Modify: `index.html:41-45` (the `:root` block containing the existing 5 `--accent-*` variables)

- [ ] **Step 1: Add the new variables**

Current block (`index.html:41-45`):
```css
  --accent-blue:   #4c8dff;
  --accent-green:  #34c76f;
  --accent-purple: #a878f0;
  --accent-amber:  #e2a13d;
  --accent-red:    #ea6a60;
```

Replace with:
```css
  --accent-blue:    #4c8dff;
  --accent-green:   #34c76f;
  --accent-purple:  #a878f0;
  --accent-amber:   #e2a13d;
  --accent-red:     #ea6a60;
  --accent-teal:    #2fb0b8;
  --accent-rose:    #e56590;
  --accent-magenta: #d066c4;
  --accent-olive:   #a4ad3a;
```

These are theme-invariant, matching the existing 5 (they are not redefined under `[data-theme="dark"]` — confirmed by checking that block, which only redefines `--blue/--green/--purple/--amber/--red/--ink/...`, never `--accent-*`).

- [ ] **Step 2: Verify no syntax errors**

Run:
```bash
node -e "const fs=require('fs');const html=fs.readFileSync('index.html','utf8');const scripts=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);for(const s of scripts)new Function(s);console.log('OK')"
```
Expected: `OK` (this is a CSS-only change, but confirms the edit didn't accidentally break the surrounding markup enough to corrupt inline script extraction).

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "Add teal, rose, magenta, olive accent colors for unique tool palette"
```

---

### Task 2: Repoint the 4 duplicate-color tools to their new accent

**Files:**
- Modify: `config.json` (4 `accent` fields — for `name-resolver`, `guest-audit`, `exchange-audit`, `finance-dashboard`)

- [ ] **Step 1: Update `name-resolver`**

Find (inside the `name-resolver` tool object):
```json
      "accent": "var(--accent-blue)",
```
Replace with:
```json
      "accent": "var(--accent-rose)",
```

- [ ] **Step 2: Update `guest-audit`**

Find (inside the `guest-audit` tool object):
```json
      "accent": "var(--accent-purple)",
```
Replace with:
```json
      "accent": "var(--accent-magenta)",
```

- [ ] **Step 3: Update `exchange-audit`**

Find (inside the `exchange-audit` tool object):
```json
      "accent": "var(--accent-blue)",
```
Replace with:
```json
      "accent": "var(--accent-teal)",
```

- [ ] **Step 4: Update `finance-dashboard`**

Find (inside the `finance-dashboard` tool object):
```json
      "accent": "var(--accent-amber)",
```
Replace with:
```json
      "accent": "var(--accent-olive)",
```

**Note:** `config.json` has multiple tools using `var(--accent-blue)` (`license-audit`, `name-resolver`, `exchange-audit`) and `var(--accent-purple)` (`user-creation`, `guest-audit`) and `var(--accent-amber)` (`mfa-status`, `finance-dashboard`) before this change — use the `"id"` field on each object to confirm you're editing the right one, don't rely on find/replace-all since the duplicate strings are intentional on the tools that keep their color (`license-audit`, `user-creation`, `mfa-status`, `group-import`, `adobe-license-monitor` are untouched).

- [ ] **Step 5: Verify valid JSON**

Run:
```bash
node -e "const c=JSON.parse(require('fs').readFileSync('config.json','utf8')); for (const t of c.tools) console.log(t.id, t.accent);"
```
Expected output (order may vary, but exactly one line per tool, 9 total, and no two `reporting-audit`/`daily-ops` tools sharing an accent):
```
license-audit var(--accent-blue)
group-import var(--accent-green)
user-creation var(--accent-purple)
name-resolver var(--accent-rose)
mfa-status var(--accent-amber)
guest-audit var(--accent-magenta)
exchange-audit var(--accent-teal)
finance-dashboard var(--accent-olive)
adobe-license-monitor var(--accent-red)
```

- [ ] **Step 6: Commit**

```bash
git add config.json
git commit -m "Give name-resolver, guest-audit, exchange-audit, and finance-dashboard unique accent colors"
```

---

### Task 3: Rework `.tool-icon-sq` into the tinted-glass badge

**Files:**
- Modify: `index.html:333-341` (the `.tool-icon-sq` rule block)

- [ ] **Step 1: Replace the icon square CSS**

Current (`index.html:333-341`):
```css
/* ── Icon square ── */
.tool-icon-sq {
  width: 40px; height: 40px; border-radius: 12px;
  background: var(--tool-accent, var(--blue));
  display: flex; align-items: center; justify-content: center;
  margin-bottom: 12px; flex-shrink: 0;
}
.tool-icon-sq svg { width: 20px; height: 20px; }
.tool-icon-sq svg, .tool-icon-sq svg * { stroke: var(--icon-text) !important; fill: none !important; }
```

Replace with:
```css
/* ── Icon square — tinted glass ── */
.tool-icon-sq {
  width: 40px; height: 40px; border-radius: 12px;
  background:
    linear-gradient(160deg, rgba(255,255,255,.55), rgba(255,255,255,.20)),
    color-mix(in srgb, var(--tool-accent, var(--blue)) 22%, white);
  border: 1px solid color-mix(in srgb, var(--tool-accent, var(--blue)) 35%, white);
  box-shadow: 0 4px 14px rgba(0,0,0,.10), inset 0 1px 0 rgba(255,255,255,.6);
  display: flex; align-items: center; justify-content: center;
  margin-bottom: 12px; flex-shrink: 0;
}
.tool-icon-sq svg { width: 20px; height: 20px; }
.tool-icon-sq svg, .tool-icon-sq svg * {
  stroke: color-mix(in srgb, var(--tool-accent, var(--blue)) 60%, black) !important;
  fill: none !important;
}
```

This keeps the existing 40px/12px sizing (only the spec's approved color/depth treatment changes, not dimensions). The `color-mix()` formula derives the frosted tint, border, and darkened icon stroke from the single `--tool-accent` value already set inline per-card (`style="--tool-accent:${accent}"` in `buildLiveCard`/`buildComingSoonCard`/`buildLockedCard`) — no JS changes needed, and any future tool's accent color automatically gets the same treatment.

- [ ] **Step 2: Verify no syntax errors**

Run the same check as Task 1 Step 2. Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "Replace flat tool icon squares with tinted-glass badges"
```

---

### Task 4: Visual verification on preview (light + dark mode, all 3 card states)

**Why this task exists:** This is a pure visual change with no test framework in this repo. `.tool-icon-sq` is shared by three render paths — `buildLiveCard` (normal clickable card), `buildComingSoonCard` (dimmed `.no-hover`), and `buildLockedCard` (`.locked`, shown pre-sign-in for `reportingOnly`/`financeOnly` tools) — plus both themes. The spec explicitly flagged dark mode as unverified by the approved mockup (the mockup only rendered light mode), so this task must check it for real before calling the work done.

- [ ] **Step 1: Push to `testing` and wait for preview deploy**

```bash
git push
```

Per `[[it-tools-deployment-workflow]]`, `testing` auto-deploys to `https://jgdev-ch.github.io/it-tools-preview/` within about 60 seconds. Confirm the deploy landed by checking the Actions run rather than guessing from timing:

```bash
gh api repos/jgdev-ch/it-tools-preview/actions/runs --jq '.workflow_runs[0].status, .workflow_runs[0].conclusion'
```
Expected: `completed` then `success` (poll every ~15s if it still shows `in_progress`).

- [ ] **Step 2: Screenshot light mode**

Use the Playwright MCP tools:
1. `mcp__plugin_playwright_playwright__browser_navigate` to `https://jgdev-ch.github.io/it-tools-preview/`
2. `mcp__plugin_playwright_playwright__browser_take_screenshot` (full page)

Confirm visually:
- All 9 icon badges show a frosted/tinted background (not flat solid color) with a visible soft shadow and top highlight
- All 9 badges show a distinct hue — no two look like the same color at a glance (this is the main thing the palette change was for)
- Icon glyphs are clearly visible (darkened accent color, not washed out against the tinted background)
- `finance-dashboard`/other `reportingOnly`/`financeOnly` cards (locked, pre-sign-in) still render the badge correctly at reduced opacity, not broken/unstyled

- [ ] **Step 3: Screenshot dark mode**

1. `mcp__plugin_playwright_playwright__browser_evaluate`: `() => document.documentElement.setAttribute('data-theme', 'dark')`
2. `mcp__plugin_playwright_playwright__browser_take_screenshot` (full page)

Confirm visually:
- Badges still read clearly against the dark card background — check specifically that the frosted-white tint isn't so bright it looks like a rendering bug (a stray light chip) against the dark theme. A *deliberate* bright glass chip on dark can look fine (common pattern), but if it looks broken/inconsistent with the rest of the dark-mode glass system, that's the "iterate" case the spec called out.
- Icon glyphs (darkened accent color) are still legible on the frosted background in dark mode — the same `color-mix()` formula is used in both themes, so contrast could theoretically differ; confirm it doesn't look muddy.

- [ ] **Step 4a (if dark mode looks correct): mark done, skip to Step 5**

- [ ] **Step 4b (if dark mode looks off): add a dark-mode override**

Add to `index.html`, immediately after the `.tool-icon-sq` block from Task 3:
```css
[data-theme="dark"] .tool-icon-sq {
  background:
    linear-gradient(160deg, rgba(255,255,255,.10), rgba(255,255,255,.02)),
    color-mix(in srgb, var(--tool-accent, var(--blue)) 30%, var(--page-1));
  border: 1px solid color-mix(in srgb, var(--tool-accent, var(--blue)) 45%, var(--page-1));
}
[data-theme="dark"] .tool-icon-sq svg, [data-theme="dark"] .tool-icon-sq svg * {
  stroke: color-mix(in srgb, var(--tool-accent, var(--blue)) 85%, white) !important;
}
```
This mixes toward the dark page background (`--page-1`, `#0e0f13` in dark mode) instead of white, and brightens the icon stroke toward white instead of black, so the badge reads as a dim-glass tinted chip rather than a light chip on dark. Re-run Steps 1–3 after this change (push, re-screenshot both themes) until it looks right. Commit once satisfied:
```bash
git add index.html
git commit -m "Add dark-mode override for tinted-glass icon badges"
git push
```

- [ ] **Step 5: Report back to Josh**

Summarize what was verified (both themes, all three card states) and link the preview URL for him to eyeball himself before deciding whether to promote `testing` → `main`.

---

## Self-Review Notes

- **Spec coverage:** Visual treatment (Task 3), palette table (Task 2), new CSS vars backing the palette (Task 1), dark-mode flag from spec's "Out of Scope" section (Task 4 Steps 3-4b), all three card-state check from spec's Implementation Notes (Task 4 Step 2) — all covered.
- **No placeholders:** every step has literal code/commands, no "add appropriate styling" type steps.
- **Type/name consistency:** `--tool-accent` (existing var name, unchanged), `--accent-teal`/`--accent-rose`/`--accent-magenta`/`--accent-olive` (new names used identically in Task 1 and Task 2), `.tool-icon-sq` (existing class name, unchanged) — consistent across all tasks.
- **Out of scope confirmed untouched:** per-tool page headers (e.g. Adobe's brand badge) and any icon glyph changes are not touched by any task above.
