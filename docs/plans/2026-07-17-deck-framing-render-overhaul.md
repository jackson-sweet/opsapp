# Deck Framing Render Overhaul Implementation Plan

> **For the executing agent:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Replace the embedded OPS Deck Designer's decorative perimeter supports with a trustworthy, topology-aware framing display for persisted and legacy deck drawings.

**Architecture:** `DeckDrawingData` will preserve the shared DeckKit framing contract and every unknown top-level block across both local JSON and direct Supabase Codable paths. The embedded LIGHT app will render persisted framing when present; legacy drawings will receive a deterministic in-memory preview derived from detected surface loops without persisting or exposing framing authoring. One resolved member plan will drive the 3D scene so joists, beams, ledgers, rim members, posts, and footings agree.

**Tech Stack:** Swift 5/6, SwiftUI data models, CoreGraphics geometry, SceneKit, XCTest, Supabase JSONB.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`, and `OPS/Styles/OPSStyle.swift`.

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`.

**Approved design baseline:** `docs/superpowers/specs/2026-06-23-deck-designer-overhaul-design.md` and the completed Phase 2 framing plan on historical branch `ops-decks/p2-framing`. Current standalone source of truth: `/Users/jacksonsweet/Projects/OPS/ops-decks-ios/Packages/DeckKit`.

**Live regression:** Supabase bug `6dd8dcac-373e-42b0-a012-c29e69a647be`, design `2305b905-b1d0-4299-a38f-7ddc47670ff8` (`2114 Central Ave`). Its ten vertices and edges are intentionally stored out of perimeter order, and edge `I-J` is the house edge.

---

## Visual intent

- **Human:** A trades owner reviewing a deck in the field on an iPhone, often outdoors, who must be able to trust what the model is showing without reading an engineering diagram.
- **Primary task:** Confirm that the deck's load path reads coherently: decking to joists, joists to beams/ledger, beams to posts, posts to grade.
- **Feel:** A quiet technical model, not decorative 3D. Every visible member must explain the structure.
- **Domain:** ledger, rim band, joist bay, beam line, post bearing, footing, grade, house attachment.
- **Signature:** The support hierarchy is visually legible from any low perspective, with posts appearing only beneath beam lines and never marching around a house wall.
- **Rejected defaults:** perimeter posts as visual filler; raw vertex-order polygon assumptions; hardcoded decorative wood colors; duplicated supports on shared boundaries.
- **Palette/depth:** Use `OPSStyle.Colors.text2`, `text3`, and `textMute` for structural hierarchy and footing separation. No new raw colors, UI chrome, shadows, typography, spacing, or motion.
- **Layout/wireframe:** Not applicable. This change modifies an existing SceneKit model inside the current viewer and adds no screen, controls, copy, gestures, or navigation.

---

### Task 1: Preserve shared framing and future deck JSON

**Skills:** `superpowers:test-driven-development`, `superpowers:systematic-debugging`.

**Files:**

- Create: `OPSTests/DeckBuilder/FramingPlanCodableTests.swift`
- Create: `OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift`
- Modify: `OPSTests/Network/DeckDesignSyncTests.swift`
- Create: `OPS/DeckBuilder/Models/FramingPlan.swift`
- Create: `OPS/DeckBuilder/Models/DeckDrawingFutureBlocks.swift`
- Modify: `OPS/DeckBuilder/Models/DeckGeometry.swift`

**Step 1: Write failing contract tests**

- Assert a DeckKit-compatible persisted `framing` block decodes and re-encodes without changing member roles, positions, nominal size, ply count, load preset, generation source, or sizing payload.
- Assert malformed member rows are skipped without failing the whole plan.
- Assert unknown top-level blocks and nested values survive `DeckDrawingData.fromJSON(...).toJSON()`.
- Assert the direct Supabase path (`JSONDecoder` -> `SupabaseDeckDesignDTO` -> model -> DTO/encoder) preserves `framing` and an unknown future block.
- Assert future blocks cannot overwrite known geometry keys.

**Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -clonedSourcePackagesDirPath .spm-local \
  -derivedDataPath .dd-local/framing-overhaul \
  -only-testing:OPSTests/FramingPlanCodableTests \
  -only-testing:OPSTests/DeckDrawingFutureBlocksTests \
  -only-testing:OPSTests/DeckDesignSyncTests
```

Expected: compile/test failure because the framing and future-block contracts do not exist.

**Step 3: Implement the minimal compatible contract**

- Port the shared framing types, retaining lossy member decoding.
- Model `sizing` as an opaque `DeckJSONValue?` in the LIGHT client so current and future sizing output survives without invoking engineering logic.
- Add a Codable dynamic JSON value and coding key for direct Supabase capture.
- Add `schemaVersion`, typed `framing`, opaque `futureBlocks`, and raw-token overlays to `DeckDrawingData`.
- Known keys win all collisions. A LIGHT save must never delete framing, terrain, house, footings, overhead, zoning, compliance, or future blocks it does not understand.

**Step 4: Run tests and verify GREEN**

Run the exact command from Step 2. Expected: all selected tests pass.

**Step 5: Commit**

```bash
git add OPS/DeckBuilder/Models/FramingPlan.swift \
  OPS/DeckBuilder/Models/DeckDrawingFutureBlocks.swift \
  OPS/DeckBuilder/Models/DeckGeometry.swift \
  OPSTests/DeckBuilder/FramingPlanCodableTests.swift \
  OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift \
  OPSTests/Network/DeckDesignSyncTests.swift
git commit -m "fix(deck-builder): preserve shared framing data"
```

---

### Task 2: Resolve a topology-safe display frame

**Skills:** `superpowers:test-driven-development`, `superpowers:systematic-debugging`.

**Files:**

- Create: `OPSTests/DeckBuilder/DeckFramingPreviewPlannerTests.swift`
- Modify: `OPS/DeckBuilder/Engine/SurfaceDetector.swift`
- Create: `OPS/DeckBuilder/Engine/FramingGeometry.swift`
- Create: `OPS/DeckBuilder/Engine/DeckFramingPreviewPlanner.swift`

**Step 1: Write the exact live regression fixture and failing tests**

- Reproduce the reported ten-vertex `2114 Central Ave` outline with the same shuffled vertex/edge storage and `I-J` house edge.
- Assert shuffling raw vertex and edge arrays does not change the resolved member geometry.
- Assert `I-J` resolves as a ledger and never receives support posts.
- Assert joists, rim members, at least one beam, and beam-supported posts exist.
- Assert every post lies on a beam and no post exists only because a perimeter corner exists.
- Add concave, freestanding, adjoining-surface/shared-edge, and multi-level fixtures.
- Assert shared boundaries and coincident beam/post points do not duplicate members.
- Assert valid persisted framing wins unchanged; missing level sets may receive transient display members without mutating `DeckDrawingData`.

**Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -clonedSourcePackagesDirPath .spm-local \
  -derivedDataPath .dd-local/framing-overhaul \
  -only-testing:OPSTests/DeckFramingPreviewPlannerTests
```

Expected: compile/test failure because no preview planner exists.

**Step 3: Implement the minimal pure planner**

- Add ordered boundary-edge resolution that matches every consecutive detected-surface vertex pair bidirectionally.
- Generate geometry from `SurfaceDetector.detect`, never from raw array order.
- Select the longest house boundary as the axis reference for each face; otherwise use the longest exterior boundary.
- Clip joists, beams, and blocking to concave polygons.
- Classify every exterior house edge as ledger, every other exterior edge as rim, and omit shared interior edges from both.
- Place posts only along generated beams at deterministic maximum spacing.
- Deduplicate members by role and normalized geometry within each level.
- Build deterministic IDs from level, role, sorted face vertex IDs, and rounded coordinates; never use randomized Swift `hashValue`.
- Prefer persisted member sets and derive transient sets only for legacy/missing display data. Never assign previews back to the drawing.

**Step 4: Run tests and verify GREEN**

Run the exact command from Step 2. Expected: all planner tests pass.

**Step 5: Commit**

```bash
git add OPS/DeckBuilder/Engine/SurfaceDetector.swift \
  OPS/DeckBuilder/Engine/FramingGeometry.swift \
  OPS/DeckBuilder/Engine/DeckFramingPreviewPlanner.swift \
  OPSTests/DeckBuilder/DeckFramingPreviewPlannerTests.swift
git commit -m "fix(deck-builder): derive framing from surface topology"
```

---

### Task 3: Replace decorative SceneKit supports

**Skills:** `superpowers:test-driven-development`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`.

**Files:**

- Create: `OPSTests/DeckBuilder/FramingSceneBuilderTests.swift`
- Create: `OPSTests/DeckBuilder/DeckFramingSceneIntegrationTests.swift`
- Modify: `OPSTests/DeckBuilder/DeckSceneSnapshotTests.swift`
- Create: `OPS/DeckBuilder/3D/FramingSceneBuilder.swift`
- Modify: `OPS/DeckBuilder/3D/DeckSceneBuilder.swift`

**Design tokens:** `OPSStyle.Colors.text2`, `OPSStyle.Colors.text3`, `OPSStyle.Colors.textMute`. Physical lumber/footing dimensions are domain measurements, not UI styling tokens.

**Step 1: Write failing scene assertions**

- Assert each linear member produces one named SceneKit node with actual nominal lumber width/depth and correct elevation.
- Assert post tops seat beneath beam bottoms and post coordinates match beam-supported planner points.
- Assert `helical_pile`, `sono_tube`, and `concrete_pad` vertex assignments produce distinct named footing geometry when a post coincides with that vertex.
- Assert the full deck scene contains `framing.joist`, `framing.beam`, `framing.post`, `framing.ledger`, and `framing.rimBand` nodes for the live legacy fixture.
- Assert no legacy `supportPost` or generic perimeter `footing` nodes remain when a resolved frame exists.
- Assert persisted framing node counts match persisted member counts.

**Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -clonedSourcePackagesDirPath .spm-local \
  -derivedDataPath .dd-local/framing-overhaul \
  -only-testing:OPSTests/FramingSceneBuilderTests \
  -only-testing:OPSTests/DeckFramingSceneIntegrationTests
```

Expected: compile/test failure because the real member scene builder is absent and the old synthetic nodes still exist.

**Step 3: Implement real member rendering**

- Build token-colored SceneKit nodes for ledgers, rim members, joists, blocking, beams, posts, and footings.
- Seat joists/rim/ledger immediately below decking, beams below joists, and posts below beams.
- Resolve post metadata from the closest exact deck vertex only; do not smear a vertex's footing choice onto unrelated intermediate supports.
- Integrate one resolved display plan at `DeckSceneBuilder.buildScene` and pass the shared canvas center/scale/elevation into each level.
- Remove synthetic perimeter posts and duplicate legacy rim stand-ins whenever framing is resolved.
- Keep the same scene pipeline for Project Details, builder 3D, thumbnails, sharing, and calibrated previews.
- Add no framing controls, writes, user-facing copy, or capability escalation to embedded OPS.

**Step 4: Run tests and verify GREEN**

Run the exact command from Step 2, then rerun the baseline scene tests. Expected: all pass.

**Step 5: Add visual proof**

- Add the live irregular fixture to `DeckSceneSnapshotTests`.
- Render low side, perspective, and bird's-eye attachments with the surface, real frame, house wall, and grade visible.
- Store exported verification images under `docs/artifacts/deck-framing-overhaul/`, never the project root.

**Step 6: Commit**

```bash
git add OPS/DeckBuilder/3D/FramingSceneBuilder.swift \
  OPS/DeckBuilder/3D/DeckSceneBuilder.swift \
  OPSTests/DeckBuilder/FramingSceneBuilderTests.swift \
  OPSTests/DeckBuilder/DeckFramingSceneIntegrationTests.swift \
  OPSTests/DeckBuilder/DeckSceneSnapshotTests.swift \
  docs/artifacts/deck-framing-overhaul
git commit -m "fix(deck-builder): render real framing and supports"
```

---

### Task 4: Audit, document, and verify the full fix

**Skills:** `custom-skills:audit-design-system`, `superpowers:verification-before-completion`.

**Files:**

- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/03_DATA_ARCHITECTURE.md`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md`

**Step 1: Run the design-system audit**

- Scan only new/touched framing files for raw `Color(...)`, `UIColor(...)`, hex, UI spacing, font, radius, shadow, and motion values.
- Physical member dimensions and numeric geometry tolerances are allowed and must be named by domain purpose.
- Expected: zero new UI token violations.

**Step 2: Run focused and regression tests**

Run all new framing/data tests plus:

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -clonedSourcePackagesDirPath .spm-local \
  -derivedDataPath .dd-local/framing-overhaul \
  -only-testing:OPSTests/DeckCanvasSceneCalibrationTests \
  -only-testing:OPSTests/DeckSurfaceEdgeResolverTests \
  -only-testing:OPSTests/DeckBuilderRegressionTests
```

Expected: all selected tests pass.

**Step 3: Build the device target**

Run:

```bash
xcodebuild -project OPS.xcodeproj -scheme OPS \
  -destination 'generic/platform=iOS' \
  -clonedSourcePackagesDirPath .spm-local \
  -derivedDataPath .dd-local/framing-overhaul-device \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

**Step 4: Update the Bible**

- Document embedded direct-Codable future-block preservation.
- Document that LIGHT displays persisted framing and uses a non-persisted topology-safe visualization for legacy rows.
- Document that embedded OPS still cannot author, regenerate, size, or persist framing.
- Document the live regression and render-node contract.

**Step 5: Commit the documentation**

Commit the Bible in its own repository/worktree only after verifying its existing dirty state and staging only the two touched files.

**Step 6: Final live-state handoff**

- Keep Supabase bug `6dd8dcac-373e-42b0-a012-c29e69a647be` open/in progress until Jackson verifies the result.
- Do not start another bug.
- Report the local branch/commits, exact test/build proof, and the one visual check Jackson should perform on `2114 Central Ave`.
