# Vinyl Order Workspace — Design

**Bugs:** `317da29f` (2026-09-08: "expanded vinyl order preview… totally messed up… cuts off ~48px from the right edge, +/- buttons are redundant, there are no tools to adjust the order") and `1a8e48af` (2026-09-01: "+/- need padding, the title divider doesn't need to be there, need to show the deck dimensions"). One piece of work.
**Status:** approved under the standing contract (spec and plan are the agent's; the founder reviews the built thing).

## What is wrong, exactly

`VinylOrderFullscreenLayout` (`OPS/DeckBuilder/Views/VinylCutPreview.swift`) reserves a 56pt control rail on the right (`VinylOrderFullscreenGeometry.controlRailWidth`) and draws the layout into the remaining width — the dead column reads as the drawing being cut off. The rail holds `+`/`−` zoom buttons that duplicate pinch-to-zoom. The header carries a hairline. The drawing shows cut widths but never the deck's own dimensions. And it is a picture: the direction, pattern, roll width, seam and wrap that *decide* the layout live back on the order sheet, so the operator looks, closes, adjusts, reopens.

## Decision

The full-screen layout becomes the place the order is *worked*, not just viewed:

1. **Full-bleed drawing.** No rail. The drawing owns the full width and the height between the header and the sheet's peek. Pinch zooms, drag pans (existing viewport model), **double-tap toggles fit ↔ 2× at the tap point**. A `FIT` chip appears top-right under the header only while zoomed (glass-dense, ≥44pt). VoiceOver keeps zoom through an adjustable action on the drawing, so removing the buttons removes nothing.
2. **Header without a divider.** Screen title (project) and the context line `// ORDER LAYOUT · <deck> · 6 CUTS` on a glass-dense wash so the drawing can pass beneath it when zoomed. Close `×` in a 44pt target. The inline card's header hairline goes too.
3. **Deck dimensions on the drawing.** Every outer edge ≥ 2' gets a length label outside the outline at its midpoint, offset along the outward normal, in the app's dimension format (`DimensionFormatter`, the measurement preference the rest of the app uses) — JetBrains Mono micro label, `text2`. The context line adds the bounding size (`24' × 12'`; multi-surface plans show the first surface and `+N`).
4. **Settings sheet.** A bottom sheet that is part of the workspace (never dismissable on its own): peek shows one summary line — `6 CUTS · 2 ROLLS · 68 SQ FT` in mono — and pulls to a half sheet holding the same controls the order sheet has (RUN, PATTERN, LOCK RUN when solid, ROLL / SEAM / WRAP steppers) followed by the CUT LIST rows. Every change re-plans immediately in the parent (the sheet already does this; the bulk wizard has `onPlanInputChange`), the drawing crossfades to the new layout (200 ms, the one OPS curve; opacity-only under Reduce Motion), and each step gives a light haptic. The drawing stays interactive beneath the sheet (`presentationBackgroundInteraction`).
5. **Shared controls.** The RUN/PATTERN/LOCK/steppers views are extracted from `VinylOrderSheet` into `VinylOrderSettingsControls` so the sheet and the workspace cannot drift.

Both callers — `VinylOrderSheet` (single project) and `VinylBulkOrderWizardView` (bulk, per page) — pass the same three things: the plan, a binding to the settings, and a re-plan callback.

Out of scope: order mode / roll length (single-sheet concerns), sourcing (bulk wizard), offcut banking.

## Presentation rules

MOBILE.md governs: 44pt targets, outdoor contrast, peek sheet 80pt with the 36×5 handle, half sheet ≤50% height, glass-dense surfaces, no hairlines as decoration, no accent anywhere in the workspace (the only accent on the sheet remains its primary CTA, which is not part of this surface). Numbers are mono, formatted, `—` when empty. Motion: `OPSStyle.Animation` curves only.

## Tests and proof

- Geometry: drawing width equals the container width; header/chip/peek never overlap the drawing's interactive area at 393×852 and at the largest accessibility size.
- Annotation planner: dimension labels sit outside the outline (distance ≥ offset), skip edges under 2', text matches `DimensionFormatter` for a known edge.
- Viewport: double-tap toggles fit ↔ 2× and clamps; the FIT chip's visibility follows `viewport == fitted`.
- Controls: `VinylOrderSettingsControls` mutates the binding and invokes the callback once per change; the sheet's summary line reflects the plan.
- `FixedSizeSnapshot` PNGs with a synthetic L-shaped six-cut plan: fitted + peek; zoomed with the FIT chip; half sheet open; Reduce Motion. A DEBUG launch gate `-OPS_VINYL_ORDER_QA` (mirroring `SiteVisitCaptureQARuntime`) renders the workspace with that plan so the principal can drive it live on the simulator.
- Verdicts from `.xcresult`. Closure is a screenshot from the founder's phone.
