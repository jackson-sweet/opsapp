# Vinyl Order Workspace Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Rebuild the full-screen vinyl ORDER LAYOUT as a workspace — full-bleed drawing with deck dimensions, no zoom rail, no header hairline, and the order settings adjustable in place with a live re-plan.

**Architecture:** `VinylOrderFullscreenLayout` becomes `VinylOrderWorkspace` (drawing + header + FIT chip + a resident settings sheet). Geometry drops the rail. The annotation planner gains dimension labels the `Canvas` draws. The order sheet's setting controls move into a shared `VinylOrderSettingsControls`. Both callers pass `plan`, `Binding<VinylOrderSettings>`, and a re-plan callback; the parents keep owning the plan.

**Tech Stack:** SwiftUI (`Canvas`, `.sheet` with `presentationDetents` / `presentationBackgroundInteraction` — iOS 17.6 floor is fine), XCTest, `FixedSizeSnapshot`.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md` (§2.1 nav bar, §3 surfaces, §6 bottom sheets); tokens in `OPS/Styles/OPSStyle.swift`.

**Spec:** `docs/superpowers/specs/2026-09-08-vinyl-order-workspace-design.md` — read it first. Read `OPS/DeckBuilder/Views/VinylCutPreview.swift` and `VinylPreviewAnnotationPlanner.swift` end to end, then `VinylOrderSheet.swift:300-800` and `VinylBulkOrderWizardView.swift:280-345, 515-560`.

**Required Skills:** `ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:interface-design`, `animation-studio:animation-architect` then `animation-studio:ios-animations` (the crossfade and sheet motion), `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`

**Non-negotiables:** verdicts from `.xcresult`; every value an `OPSStyle` token; no `git push`; no AI attribution; keep the existing single-project sheet behaviour byte-for-byte where this plan does not touch it.

---

### Task 1: Geometry without the rail

**Files:**
- Modify: `OPS/DeckBuilder/Views/VinylCutPreview.swift` (`VinylOrderFullscreenGeometry` → `VinylOrderWorkspaceGeometry`: `headerHeight`, `sheetPeekHeight = OPSStyle.Layout.touchTargetLarge + OPSStyle.Layout.spacing4` (≈80pt), `fitChipInset`; `drawingSize` = full width × (height − header − peek); `fitChipCenter`)
- Test: `OPSTests/…VinylOrderWorkspaceGeometryTests.swift` (rename/extend any existing `VinylOrderFullscreenGeometry` tests — `grep -rn "VinylOrderFullscreenGeometry" OPSTests`)

Steps: failing test (`drawingSize.width == container.width`; chip rect ∩ drawing interactive rect is empty; peek band sits above the home indicator) → implement → pass → commit `refactor(vinyl): workspace geometry — the drawing owns the full width`.

### Task 2: Dimension labels in the planner and the canvas

**Files:**
- Modify: `OPS/DeckBuilder/Views/VinylPreviewAnnotationPlanner.swift` (`VinylPreviewDimensionLabel { edgeId, text, point }`; `VinylPreviewAnnotationPlan.dimensionLabels`; built in `plan(…)` from `edgeLayouts(for:)` — midpoint + outwardNormal × `labelOffset`; length from `edge.dimensionInches` when > 0 else canvas length ÷ `scaleFactor`; skip < 24")
- Modify: `OPS/DeckBuilder/Views/VinylCutPreview.swift` (`drawDimensionLabels` after `drawCuts`, `OPSStyle.Typography.microLabel`, `OPSStyle.Colors.text2`)
- Modify: header context line composition (bounding `boundingWidthInches × boundingHeightInches` via `DimensionFormatter`)
- Test: `OPSTests/…VinylPreviewDimensionLabelTests.swift`

Read `DimensionFormatter.string(...)` and find how the measurement screens obtain the unit preference; reuse that exact call. Commit `feat(vinyl): draw the deck's dimensions on the order layout`.

### Task 3: Shared settings controls

**Files:**
- Create: `OPS/DeckBuilder/Views/VinylOrderSettingsControls.swift` (`struct VinylOrderSettingsControls: View { @Binding var settings: VinylOrderSettings; let onChange: () -> Void }` — RUN, PATTERN, LOCK RUN (solid only), ROLL/SEAM/WRAP steppers moved verbatim from `VinylOrderSheet` incl. haptics; `formatInchesForSheet` moves to a shared helper)
- Modify: `OPS/DeckBuilder/Views/VinylOrderSheet.swift` (`controlsSection` uses the shared view; unchanged look)
- Test: `OPSTests/…VinylOrderSettingsControlsTests.swift` (binding mutation + one callback per change), plus the sheet's existing tests stay green

Commit `refactor(vinyl): share the order setting controls`.

### Task 4: The workspace view

**Skills:** `ops-design`, `custom-skills:mobile-ux-design`, `animation-studio:animation-architect`, `animation-studio:ios-animations`, `ops-copywriter:ops-copywriter`

**Files:**
- Modify: `OPS/DeckBuilder/Views/VinylCutPreview.swift` — `VinylOrderFullscreenLayout` → `struct VinylOrderWorkspace` (internal, testable): header (no hairline, `glassDense` wash), `drawingViewport` full-bleed with pinch/pan/double-tap (`viewport.toggleFit(at:viewportSize:)` on `VinylOrderViewportState`), FIT chip (`glassDense`, `OPSStyle.Icons.fit`, label `FIT`, visible iff `viewport != VinylOrderViewportState()`), `accessibilityAdjustableAction` zoom, resident `.sheet` (`.opsSheet(detents: [.height(peek), .medium])`, `.presentationBackgroundInteraction(.enabled(upThrough: .medium))`, `.interactiveDismissDisabled()`), crossfade on plan change (`.id(planIdentity)` + `.transition(.opacity)` under `OPSStyle.Animation.panel`; opacity-only when Reduce Motion)
- Create: `OPS/DeckBuilder/Views/VinylOrderSettingsSheet.swift` (handle, summary line `<cuts> CUTS · <rolls> ROLLS · <sq ft> SQ FT` in `OPSStyle.Typography.dataValue`, `VinylOrderSettingsControls`, CUT LIST rows reused from the sheet's `cutListSection` body)
- Modify: `VinylOrderLayoutWindow` (new inputs `settings: Binding<VinylOrderSettings>`, `onSettingsChanged: () -> Void`; drop the card header hairline)
- Modify: `VinylOrderSheet.swift:347` and `VinylBulkOrderWizardView.swift:542` (pass `$settings` + `recomputePlan` / `$state.vinylSettings` + `onPlanInputChange`)
- Test: viewport toggle test; chip visibility test; snapshot tests (Task 6)

Copy through `ops-copywriter`: `FIT`, `// ORDER LAYOUT`, summary line, section labels `SETTINGS` / `CUT LIST`. Commit `feat(vinyl): order layout workspace — full-bleed drawing, dimensions, settings in place`.

### Task 5: QA launch gate for live driving

**Files:**
- Create: `OPS/Utilities/VinylOrderQARuntime.swift` (`-OPS_VINYL_ORDER_QA`, DEBUG only, mirroring `SiteVisitCaptureQARuntime`), `OPS/Utilities/VinylOrderQAHost.swift` (renders `VinylOrderWorkspace` with `VinylOrderQAFixture.lShapedSixCutPlan()` and local settings state that re-plans through `VinylCutListEngine.makePlan`)
- Modify: `OPS/OPSApp.swift` (add the gate to the existing DEBUG chain in `init()`, `storeConfiguration()`, and `rootView`)
- Modify: `OPS/DataModels/Migrations/OPSSchemaCurrent.swift` is NOT touched; the host uses the in-memory store path like the others

Commit `test(vinyl): QA launch gate renders the order workspace with a synthetic plan`.

### Task 6: Proof

- `OPSTests/Views/VinylOrderWorkspaceSnapshotTests.swift` with `FixedSizeSnapshot` at 393×852: fitted + peek; zoomed (chip); half sheet; Reduce Motion. Save PNGs under `docs/artifacts/vinyl-order-workspace-20260908/`.
- Run every vinyl/deck test class that exists (`grep -rln "Vinyl" OPSTests | xargs -n1 basename`) plus the new ones; verdict from the xcresult.
- `custom-skills:audit-design-system` over every touched file.
- Report: commits, xcresult totals, PNG paths with one line each, the QA launch argument, anything open.
