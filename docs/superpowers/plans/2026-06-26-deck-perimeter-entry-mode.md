# Deck Perimeter Entry Mode Implementation Plan

**Date:** 2026-06-26
**Source spec:** `docs/superpowers/specs/2026-06-26-deck-perimeter-entry-design.md`
**Scope:** OPS iOS Deck Builder, 2D perimeter entry only
**Outcome:** Operators can long-press a blank canvas or existing vertex, choose direction, enter exact length in a centered floating control, and continue the perimeter chain without bottom sheets.

## Product Decision

Build this as a command-entry drawing mode layered on the existing deck geometry engine. The finger selects intent. The measurement is authoritative. Keep the existing freehand draw and selection workflows intact.

## Existing Code Anchors

- `OPS/DeckBuilder/Views/DeckCanvasView.swift`
  - `drawGesture(size:)` handles current long-press-drag drawing.
  - `longPressGesture(size:)` already routes canvas long press into the view model.
- `OPS/DeckBuilder/DeckBuilderViewModel.swift`
  - `beginLine(from:)`, `updateLine(to:)`, and `endLine(at:)` already handle snap, commit, close detection, haptics, undo, and save.
  - `handleLongPress(at:hitThreshold:)` currently has no meaningful competing long-press-on-vertex behavior.
  - `setEdgeDimension(_:inches:source:)` already preserves manual dimensions as authoritative.
  - `prescaleFallbackScale` already defines pre-calibration canvas points per inch.
- `OPS/DeckBuilder/Views/DimensionInputView.swift`
  - Existing sheet-based dimension editor remains for selected edges.
- `OPS/DeckBuilder/Views/VoiceDimensionInput.swift`
  - Reuse speech parsing for dictation, with a measurement-system-aware initializer.
- `OPS/DeckBuilder/Views/DeckToolbar.swift`
  - Single-vertex context toolbar gets the backup `DRAW FROM HERE` action.

## Build Steps

1. Add perimeter state models.
   - Add `OPS/DeckBuilder/Models/PerimeterEntryState.swift`.
   - Define `PerimeterEntryMode`, `PerimeterEntryAnchor`, `PerimeterDirection`, and `PerimeterLengthDraft`.
   - Keep geometry helpers pure and testable: direction resolution, inches-to-canvas conversion, endpoint calculation, and unit normalization.

2. Add view-model commands.
   - Add `@Published var perimeterEntry: PerimeterEntryMode = .idle`.
   - Add `beginPerimeterEntry(at:hitThreshold:)` for empty-canvas and vertex long press.
   - Add `beginPerimeterEntry(fromVertexId:)` for the vertex toolbar backup.
   - Add `selectPerimeterDirection(_:)`, `updatePerimeterLength(_:)`, `commitPerimeterLength()`, `stepBackPerimeterEntry()`, and `cancelPerimeterEntry()`.
   - Commit edges through one internal mutation path that mirrors `endLine(at:)`, but stores `dimensionSource = .manual` and uses the wheel/dictated length as the edge dimension.
   - Reuse existing snap-to-existing-vertex and close-shape rules so a perimeter can close onto its starting point without duplicate vertices.

3. Wire gestures.
   - Update `DeckCanvasView.longPressGesture(size:)` so:
     - long-press existing vertex starts perimeter entry from that vertex;
     - long-press empty canvas creates/snaps the first anchor and opens the direction wheel;
     - long-press edge/footprint keeps existing selection behavior.
   - Leave tap selection, marquee, lasso, and freehand draw behavior unchanged.

4. Add the floating direction wheel.
   - Add `OPS/DeckBuilder/Views/PerimeterDirectionWheelView.swift`.
   - Render at the active vertex screen position when practical, with viewport clamping so wedges remain reachable on small iPhones.
   - Support drag-through-release and direct tap.
   - Use existing OPS tokens, 44 pt minimum targets, terse labels, and reduced-motion opacity fallback.

5. Add the centered length control.
   - Add `OPS/DeckBuilder/Views/PerimeterLengthControlView.swift`.
   - Center over the canvas; do not use a bottom sheet.
   - Imperial controls: feet, inches, fraction.
   - Metric controls: meters, centimeters, millimeters.
   - Unit toggle preserves total inches while changing wheel display.
   - Dictation button populates wheels only; right arrow commits.
   - Left arrow returns to direction selection or undoes the last perimeter-entry commit depending on state.

6. Integrate canvas overlays.
   - Add a `perimeterEntryOverlay` to `DeckBuilderView`.
   - Ensure it does not collide with the floating title/header, edit cluster, assignment wheel, or bottom toolbar on iPhone SE and modern Dynamic Island sizes.
   - Disable hit-testing behind the active floating control only where needed.

7. Add the vertex toolbar backup.
   - In `DeckToolbar.vertexTools`, show `DRAW FROM HERE` when exactly one vertex is selected.
   - Use a directional/line icon and OPS copy style.

8. Preserve system behavior.
   - Keep `DimensionInputView` for existing selected-edge editing.
   - Keep `VoiceDimensionInput` authorization and failure behavior intact.
   - Avoid schema or persistence changes; perimeter entry writes normal vertices/edges into existing `DeckDrawingData`.
   - Update `ops-software-bible` Deck Builder docs after implementation because this changes a user-facing drawing workflow.

## Test Plan

1. Unit tests.
   - Add `OPSTests/DeckBuilder/PerimeterEntryTests.swift`.
   - Verify direction endpoint math for absolute and relative directions.
   - Verify pre-scale conversion uses `DeckBuilderViewModel.prescaleFallbackScale`.
   - Verify committed perimeter edges store manual dimensions in inches.
   - Verify closing onto an existing vertex reuses that vertex id.
   - Add explicit `DimensionEngine` coverage for `2' 48"` normalizing to `72` inches.

2. Focused iOS test commands.
   - `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/PerimeterEntryTests`
   - `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DimensionEngineTests`

3. Build verification.
   - `xcodebuild build -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16'`

4. Runtime verification.
   - Launch on iPhone simulator.
   - Draw a four-side perimeter using only long press, direction wheel, and centered length control.
   - Verify no bottom sheet appears.
   - Verify dictation result populates wheels without auto-commit when authorization is available.
   - Verify long-press existing vertex starts from that vertex.
   - Verify single selected vertex toolbar can start `DRAW FROM HERE`.

## Acceptance Bar

- Perimeter entry works one-handed with no bottom sheet.
- Every committed command edge displays the chosen length, not a finger-drag approximation.
- Existing drawing and selection flows still work.
- The flow survives cancellation, undo/back, close-shape, multi-level active level, and no-scale drawings.
- Build and focused tests pass.
