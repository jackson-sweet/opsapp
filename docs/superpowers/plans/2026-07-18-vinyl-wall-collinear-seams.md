# Vinyl Wall-Collinear Seams Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use custom-skills:executing-plans to implement this plan task-by-task.

**Goal:** Guarantee that every vinyl direction-change seam follows the supporting line of a classified house wall, and prevent every outbound order path from consuming an invalid mixed plan.

**Architecture:** `VinylCutListEngine` generates explicit direction regions and wall-derived transitions with `PolygonSplitter`; `VinylCutPlan` carries geometry issues and one `isOrderable` decision; preview and all order/materials paths consume that same plan data. The existing arbitrary rectilinear optimizer becomes detection-only and can never emit mixed cuts.

**Tech Stack:** Swift 6, SwiftUI, CoreGraphics, XCTest, Xcode 26.5 simulator tooling.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`; `.interface-design/system.md` is absent, so existing `OPSStyle` tokens are authoritative.

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:executing-plans`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:ops-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, and `superpowers:verification-before-completion`.

---

## Task 1: Lock the wall-collinearity contract in RED

**Files:**

- Modify: `OPSTests/DeckBuilder/VinylCutListEngineTests.swift`

1. Replace the existing permissive mixed-axis fixture with an L-shaped surface whose real `houseEdge` supporting line crosses the deck interior.
2. Assert the plan exposes two direction regions, one transition tied to that house edge, and a seam collinear with the wall line.
3. Assert all mixed cuts carry a valid direction-region id and the plan is orderable.
4. Run only the new test:

   ```bash
   xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd-local/vinyl-wall-collinear-red test -only-testing:OPSTests/VinylCutListEngineTests/testUnlockedMixedRunUsesOnlyHouseCollinearSeamEvenWhenInvalidSplitIsCheaper CODE_SIGNING_ALLOWED=NO
   ```

5. Confirm RED because transition/region/orderability model does not exist, not because of simulator or dependency failure.

## Task 2: Add explicit region, transition, and issue models

**Files:**

- Modify: `OPS/DeckBuilder/Engine/VinylCutListEngine.swift`
- Modify: `OPSTests/DeckBuilder/VinylCutListEngineTests.swift`

1. Add `VinylDirectionRegion`, `VinylSeamSegment`, `VinylDirectionTransition`, and `VinylPlanIssue`.
2. Add direction-region identity to `VinylCutPiece`, preserving it through offcut reassignment.
3. Add regions/transitions to surface plans and issues plus `isOrderable` to the aggregate plan.
4. Make every existing single-direction candidate emit one region with no transition.
5. Run the Task 1 test and the full `VinylCutListEngineTests`; keep the new behavior RED until the geometry generator lands, while restoring compilation for existing tests.

## Task 3: Generate only house-wall-derived mixed candidates

**Files:**

- Modify: `OPS/DeckBuilder/Engine/VinylCutListEngine.swift`
- Modify: `OPS/DeckBuilder/Engine/PolygonSplitter.swift` only if a reusable tolerance helper is required
- Modify: `OPSTests/DeckBuilder/VinylCutListEngineTests.swift`
- Modify: `OPSTests/DeckBuilder/PolygonSplitterTests.swift` only if splitter behavior changes

1. Add a failing horizontal-wall fixture and a 30-degree rotated fixture.
2. For each `.houseEdge`, split the original canvas polygon by the edge's infinite line.
3. Filter splitter chords with two-sided interior probes so the exterior house boundary itself cannot masquerade as a seam.
4. Build region-specific surface inputs, generate cuts per region, and compare legal direction assignments by purchased area then cut count.
5. Normalize angles when determining whether a candidate is genuinely mixed.
6. Remove arbitrary mixed output from candidate selection; retain it only as a private lower-cost-turn detector.
7. Run each new focused test to GREEN, then all `VinylCutListEngineTests` and `PolygonSplitterTests`.

## Task 4: Block requested turns that have no legal wall split

**Files:**

- Modify: `OPS/DeckBuilder/Engine/VinylCutListEngine.swift`
- Modify: `OPSTests/DeckBuilder/VinylCutListEngineTests.swift`

1. Add a failing L-shaped fixture where the arbitrary mixed optimizer wins but the only house edge cannot split the deck interior.
2. Assert the engine emits no mixed candidate, records `mixedRunMissingHouseAlignedTransition`, and returns `isOrderable == false`.
3. Add LENGTH and WIDTH unlocked fixtures proving manual selection cannot bypass the invariant or silently ignore legal wall-derived regions.
4. Implement the issue decision and selected-axis behavior without blocking an ordinary single-direction layout that does not request or benefit from a turn.
5. Run the focused blocker/manual tests, then the full engine suite.

## Task 5: Make preview render authoritative geometry

**Files:**

- Modify: `OPS/DeckBuilder/Views/VinylOrderSheet.swift`
- Modify: `OPS/DeckBuilder/Views/VinylPreviewAnnotationPlanner.swift`
- Modify: `OPSTests/DeckBuilder/VinylPreviewAnnotationPlannerTests.swift`

1. Add failing pure-planner tests proving exactly the plan's transition segments are rendered and cuts use their own region polygon.
2. Clip each cut to its `VinylDirectionRegion` rather than the entire surface.
3. Draw the explicit seam with existing `OPSStyle` hairline/semantic tokens and no decorative region fill.
4. Render no invented transition for a single-direction or blocked plan.
5. Run the preview-planner tests and the engine tests.

## Task 6: Enforce one readiness guard across every outbound path

**Files:**

- Modify: `OPS/DeckBuilder/Views/VinylOrderSheet.swift`
- Modify: `OPS/DeckBuilder/Engine/DeckMaterialsEngine.swift`
- Modify: `OPS/DeckBuilder/Models/DeckMaterials.swift`
- Modify: `OPS/DeckBuilder/Services/DeckMaterialsOrderService.swift`
- Modify: `OPS/Views/Components/Project/ProjectDetailsViewModel.swift`
- Modify: `OPS/Views/Components/Project/Tabs/DeckMaterialsSection.swift`
- Modify: `OPS/Views/JobBoard/JobBoardProjectListView.swift`
- Modify: `OPS/Views/JobBoard/VinylOrderFilter.swift`
- Modify: `OPSTests/DeckBuilder/DeckMaterialsEngineTests.swift`
- Modify: `OPSTests/DeckBuilder/DeckMaterialsCodableTests.swift`
- Modify: `OPSTests/DeckBuilder/DeckMaterialsOrderServiceTests.swift`

1. Add failing readiness/service tests for blocked-plan copy/create/note/snapshot/MARK ORDERED behavior.
2. Gate TEXT/COPY, CREATE ORDER + NOTE, create-order defensive entry, project marker confirmation, and materials snapshot persistence on `plan.isOrderable`.
3. Surface the copywriter-approved validation line: `NO HOUSE-WALL SPLIT · LOCK RUN OR MARK WALL`.
4. Include region directions and transition segments in the vinyl order drift fingerprint.
5. Ensure a blocked plan never falls back to the plain project marker path.
6. Run each focused service/readiness suite to GREEN.

## Task 7: Update the OPS Software Bible

**Files:**

- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md`

1. Replace the claim that rectilinear subregions may rotate solely for lower waste.
2. Document the house-wall supporting-line invariant, explicit transition geometry, blocked state, and downstream readiness guard.
3. Verify the documented screen labels and persistence behavior against the implementation.

## Task 8: Design-system audit and full verification

**Files:**

- Inspect all modified SwiftUI and style call sites

1. Run the `custom-skills:audit-design-system` checks: zero hardcoded color, spacing, radius, or font values in the new UI.
2. Run `git diff --check` and inspect the complete focused diff.
3. Run focused suites:

   ```bash
   xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd-local/vinyl-wall-collinear-final test -only-testing:OPSTests/VinylCutListEngineTests -only-testing:OPSTests/PolygonSplitterTests -only-testing:OPSTests/VinylPreviewAnnotationPlannerTests -only-testing:OPSTests/DeckMaterialsOrderServiceTests CODE_SIGNING_ALLOWED=NO
   ```

4. Run a clean app build using a worktree-local DerivedData path.
5. Inspect the Vinyl Order sheet in the simulator with a legal wall split and a blocked split; save any proof under `docs/artifacts/`, not the repo root.
6. Use `superpowers:verification-before-completion`, request a read-only code review, and fix every material finding.
7. Commit the implementation atomically without pushing.
8. Update the live Supabase bug row with branch, commit, verification notes, and `requires_human_review=true`; leave it `in_progress` until Jackson verifies.

## Stop condition

Stop after the focused bug is implemented, committed, verified, and written back for human review. Do not begin another bug and do not push. Ask Jackson to verify the Deck Designer behavior.
