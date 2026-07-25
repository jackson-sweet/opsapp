# MULTIPLE VINYL ORDER SHEET — Design Spec

**Date:** 2026-07-25
**Surface:** OPS iOS · VINYL ORDERS bulk-order wizard
**Status:** Approved through Jackson's reported bug direction and explicit continuation
**Supersedes:** The affected layout/copy details in the 2026-07-16 VINYL ORDERS spec

## Outcome

The bulk-order review becomes a focused field workflow:

1. The current job and progress live in the navigation header, eliminating the empty second header band.
2. The page scrolls behind one standard OPS floating action bar containing BACK and CONFIRM.
3. The large `USE FIELD CONFIRM` button is removed. An empty color remains valid and is rendered as `FIELD CONFIRM` by the existing order composer.
4. A shared, tokenized `VinylOrderLayoutWindow` replaces the static preview in both the single and bulk order sheets.
5. Tapping the layout window opens a true fullscreen canvas with pinch-to-zoom, drag-to-pan, and floating zoom/fit/close controls.
6. Full-roll mode shows every calculated roll with its assigned cuts, feet used, and feet left. Overlength cuts remain explicitly blocked/warned and never appear in a roll.

## Information hierarchy

### Navigation header

- Authority line: `ORDER · i OF n` or `ORDER · SEND`
- Primary title: current project title, or `FLASHING + GLUE + MESSAGE`
- Trailing action: `CANCEL`

The title is navigation chrome, not scroll content. It stays visible while reviewing a long order.

### Review body

1. Blocking condition, when present
2. Color
3. PO
4. Order quantity and per-roll utilization
5. Order layout window
6. Layout settings

### Floating actions

- BACK is neutral.
- CONFIRM is the single primary action.
- The bar overlays the scroll surface with reserved content clearance and safe-area handling.

## Shared order layout window

The existing `VinylCutPreview` remains the authoritative renderer. A shared wrapper owns presentation and interaction:

- Inline card title: `// ORDER LAYOUT`
- Inline expand control: full-screen icon with a minimum 44 pt target
- Fullscreen header: project title + `ORDER LAYOUT`
- Direct manipulation: pinch to zoom; drag to pan once zoomed
- Floating rail: zoom in, zoom out, fit
- Close control: floating, top trailing
- Fit always returns to the complete auto-fitted drawing
- Scale and pan are bounded so the drawing cannot be irretrievably lost
- Reduce Motion makes discrete transform controls immediate; continuous gestures produce no haptics
- Discrete expand, zoom, fit, and close actions use restrained haptics

All visual values trace to `OPSStyle` colors, typography, spacing, radii, borders, icons, touch targets, and animation tokens.

## Full-roll utilization

The existing first-fit-decreasing behavior stays unchanged. The packer additionally retains each bin:

- assigned strip lengths
- used feet (`sum(strip lengths)`)
- leftover feet (`roll capacity - used feet`)

Presentation per roll:

```text
ROLL 01
CUTS 40' + 30'
USED 70'   LEFT 5'
```

Values use the shared feet-and-inches formatter. Full-width roll tail is not mislabeled as the existing cut waste or produced width offcut.

## Copy

- Remove: `USE FIELD CONFIRM`
- Add: `// ORDER LAYOUT`, `FULL SCREEN`, `ROLL 01`, `CUTS`, `USED`, `LEFT`, `FIT LAYOUT`
- Keep: `FIELD CONFIRM` as the empty-color order value

Copy remains terse, tactical, uppercase for authority, and uses `—` for empty values.

## Verification

- Pure tests prove per-roll assignments, used/left math, exact fits, overlength exclusion, invalid capacity, and deterministic input ordering.
- Pure viewport tests prove scale bounds, pan bounds, and fit reset.
- One focused red test run precedes implementation.
- One focused green run compiles the changed SwiftUI surface and executes only the relevant vinyl tests.
- A final design-system audit rejects hardcoded colors, spacing, radii, fonts, or non-token motion in touched UI.
