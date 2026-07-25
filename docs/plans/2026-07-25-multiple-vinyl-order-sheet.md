# Multiple Vinyl Order Sheet — Implementation Plan

> Execute with the OPS design system, mobile UX, interface-design, UI/UX, copy, motion, TDD, systematic-debugging, and verification disciplines already loaded for this task.

## 1. Lock the behavior with focused tests

- Extend `OPSTests/DeckBuilder/VinylRollPackerTests.swift`.
- Name the failures: losing per-roll assignments, incorrect used/left math, admitting overlength cuts, and nondeterministic packing.
- Extend the existing vinyl preview test file with viewport-state bounds/reset behavior.
- Run one focused red invocation and verify it fails only because the new behavior is absent.

## 2. Retain the roll packing layout

- Extend `OPS/DeckBuilder/Engine/VinylRollPacker.swift` with a pure detailed packing result while preserving the existing aggregate API and algorithm.
- Keep purchased-strip inputs, one-strip-per-roll semantics, epsilon handling, overlength reporting, and deterministic FFD ordering unchanged.
- Make used/left values derived from retained assignments so UI cannot disagree with the packer.

## 3. Build the shared tokenized layout window

- Add `VinylOrderLayoutWindow`, fullscreen presentation, and pure viewport state beside the existing renderer in `OPS/DeckBuilder/Views/VinylCutPreview.swift`.
- Leave cut geometry, clipping, annotations, colors, and wall-transition rendering untouched.
- Use only `OPSStyle` tokens and current iOS/SF Symbol icon conventions.
- Add bounded pan, bounded zoom, fit reset, accessibility labels, minimum touch targets, reduced-motion-safe discrete transitions, and no continuous-gesture haptics.

## 4. Recompose the bulk wizard

- Move progress + project title from body content into navigation header chrome.
- Remove `USE FIELD CONFIRM`.
- Allow CONFIRM with an empty color because the composer already renders it as `FIELD CONFIRM`.
- Replace the static preview with the shared layout window.
- Replace docked action bars with `OPSFloatingButtonBar`; reserve scroll clearance.
- Show detailed roll utilization and the existing overlength warning in full-roll mode.
- Persist confirmed layout settings through the same drawing-data path as the standard sheet.

## 5. Keep the standard order sheet in parity

- Replace its static preview with the same layout window.
- Show the same per-roll utilization in full-roll mode.
- Do not change order creation, inventory, snapshot, wall-alignment, or outbound-refresh behavior.

## 6. Document and verify

- Patch only the vinyl-order section of the Software Bible; preserve unrelated dirty work.
- Run the single focused green invocation.
- Run `git diff --check` and a touched-file token audit.
- Request an independent read-only code/design review.
- Commit atomically, integrate into unchanged local `main`, update the exact live bug row with proof, and stop for Jackson's manual UI verification.
