# Hub Icon Glass Treatment + Unique Color Palette

**Date:** 2026-08-03
**Status:** Approved (via visual companion mockups)

## Problem

The hub landing page renders each tool's icon as a flat, solid-color 40px square (`.tool-icon-sq` in `index.html`). Two issues:

1. It's flat and doesn't match the "Glass Control Center" material used everywhere else on the hub (glass cards, dropdowns, badges) — see [[project_design_system]].
2. Only 5 accent colors exist (`--accent-blue/green/purple/amber/red`) for 9 tools, so 4 tools currently share a color with another tool: `name-resolver` (blue, also used by `license-audit` and `exchange-audit`), `guest-audit` (purple, also `user-creation`), `finance-dashboard` (amber, also `mfa-status`), and `exchange-audit` (blue, also `license-audit` and `name-resolver`).

## Decision

### Visual treatment: "Tinted glass" badge (Option A of 3 mocked)

Keep the icon square's own accent color (don't flatten to one neutral color for all tools — that was Option B, explicitly rejected in favor of keeping color-as-category-cue). Change the flat fill to a frosted, lifted glass tile:

- Background: a soft white gradient glaze over a tint of the tool's own accent color (~22% strength)
- Border: same accent at ~35% strength
- Icon glyph: drawn in a darkened shade of the tool's own accent (not white) — reads clearly against the light tinted background
- Depth: subtle drop shadow + inset top highlight, consistent across every tool (only the hue changes, not the depth treatment)

This only changes `.tool-icon-sq` on the hub landing page (`index.html`). Per-tool page headers (e.g. Adobe's own brand badge inside `tools/adobe-license-monitor/index.html`) are out of scope — those are brand marks, not category-color icons.

### Palette: 9 unique accent colors, no repeats

The 5 colors already shipped keep their current tool and hex value unchanged. 4 new colors are introduced for the tools that were duplicating another tool's color:

| Tool | Accent | Hex | Status |
|---|---|---|---|
| M365 License Audit | Blue | `#4c8dff` | unchanged |
| Group Administration | Green | `#34c76f` | unchanged |
| User Creation | Purple | `#a878f0` | unchanged |
| MFA Status Report | Amber | `#e2a13d` | unchanged |
| Adobe License Monitor | Red | `#ea6a60` | unchanged |
| Name Resolver | Rose (new) | `#e56590` | was Blue |
| Guest Access Audit | Magenta (new) | `#d066c4` | was Purple |
| Exchange Audit | Teal (new) | `#2fb0b8` | was Blue |
| License Spend (finance-dashboard) | Olive (new) | `#a4ad3a` | was Amber |

All 9 hues were checked for angular separation on the color wheel (minimum ~32° apart) to avoid any two reading as "the same color" at a glance, matching the saturation/lightness band of the 5 existing colors so the new ones don't look out of place.

Josh approved this exact assignment via the rendered mockup at `.superpowers/brainstorm/4834-1785766232/content/palette.html` (session artifact, not committed — see Implementation Notes).

## Implementation Notes

- Add 4 new CSS custom properties alongside the existing `--accent-*` set in `index.html`'s `:root` (theme-invariant, same as the existing 5 — they are NOT redefined under `[data-theme="dark"]`): `--accent-rose: #e56590`, `--accent-magenta: #d066c4`, `--accent-teal: #2fb0b8`, `--accent-olive: #a4ad3a`.
- Update `config.json` `accent` field for `name-resolver`, `guest-audit`, `exchange-audit`, `finance-dashboard` to their new `var(--accent-*)`.
- Rework `.tool-icon-sq` CSS: derive the tint background, tint border, and darkened icon stroke from the single `--tool-accent` custom property already set inline per-card (`style="--tool-accent:${accent}"`), rather than hand-maintaining three hardcoded shades per color. Prefer CSS `color-mix()` (background tint = accent mixed toward white ~22%, border = accent mixed toward white ~35%/kept more saturated, icon stroke = accent mixed toward black ~35-40%) so future new tool colors only need one hex value, not three. Fall back to hand-picked per-color values (as prototyped in the mockup) only if `color-mix()` rendering doesn't visually match the approved mockup closely enough — this hub already relies on modern-only CSS (`backdrop-filter`), so browser support isn't a concern in this environment.
- The same `.tool-icon-sq` class is shared by `buildLiveCard`, `buildComingSoonCard`, and `buildLockedCard` (see `index.html`) — verify the new glass treatment renders correctly (and still reads at the `.no-hover`/`.locked` reduced opacity) for all three card states, not just the default clickable one.
- No changes needed to `unlockCard`/`lockCard` logic — they already pass `accent` through unchanged.

## Out of Scope

- Per-tool page headers/brand marks (e.g. Adobe's own "A" logo badge).
- Dark mode tuning pass beyond verifying the existing glass-card dark-mode pattern (blur + border-alpha swap) still reads correctly — no dark-mode-specific mockup was reviewed, so flag if it looks off and iterate.
- Any icon *glyph* changes beyond the Adobe monitor-check swap already shipped separately.
