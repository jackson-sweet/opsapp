# Deck Materials List Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` (OPS-tuned) to implement this plan task-by-task. NOT `superpowers:executing-plans`.

**Goal:** Auto-calculated vinyl materials list (cuts, drip edge, clip, 90 flash, glue) on the project Deck tab, with a frozen "ordered" snapshot written by MARK ORDERED.

**Architecture:** Pure calculation engine (`DeckMaterialsEngine`) beside the existing `VinylCutListEngine`; all new persisted state rides inside `DeckDrawingData` JSON (`deck_designs.drawing_data` jsonb — zero DB migration); one shared order service snapshots from both MARK ORDERED entry points; one new SwiftUI section in `DeckTabView`.

**Spec (read first, top to bottom):** `docs/superpowers/specs/2026-07-06-deck-materials-list-design.md`

**Tech Stack:** Swift / SwiftUI / SwiftData, XCTest. iOS deployment target 17.6 — no iOS-18-only APIs.

**Design System:** `ops-design-system/project/DESIGN.md` + `ops-design-system/project/mobile/MOBILE.md` (read both before UI tasks). iOS tokens: `OPS/Styles/OPSStyle.swift`. Zero hardcoded color/spacing/radius/font values.

**Required Skills (executor loads before starting):** `ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:audit-design-system` (before UI done), `superpowers:verification-before-completion`. All user-facing copy is pre-written in this plan (ops-copywriter register); if you must invent ANY new string, load `ops-copywriter:ops-copywriter` first.

**Working rules (non-negotiable):**
- Branch: create `feat/deck-materials-list` off `main` before Task 1. Commit per task, conventional commits, **no AI attribution**.
- Worktree builds: copy `OPS/Utilities/Secrets.xcconfig` from the primary checkout into the worktree first, and ALWAYS pass `-clonedSourcePackagesDirPath .spm-local` to xcodebuild. Check `ps aux | grep xcodebuild` before builds (parallel sessions).
- Many Swift files are CRLF/mixed line endings — preserve exactly (edit surgically; never let tooling normalize a file).
- Build verification: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local build` (NEVER simulator for plain build). Tests: `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`.
- `UUID().uuidString` is UPPERCASE — lowercase any id that will hit Postgres (none expected in this feature; snapshot ids are not rows).
- Follow `DeckGeometry.swift` Codable house style: explicit `CodingKeys`, custom `init(from:)`, `decodeIfPresent` + default for EVERY field. Never `let x: T? = nil` in a Codable struct (drops from memberwise init AND decode).

**Test target/run commands** (used throughout; substitute the test class):

```bash
xcodebuild test -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -clonedSourcePackagesDirPath .spm-local \
  -only-testing:OPSTests/DeckMaterialsEngineTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` (or the named failure in red steps).

---

## Task 1: Codable models + JSON nodes

**Files:**
- Create: `OPS/DeckBuilder/Models/DeckMaterials.swift`
- Modify: `OPS/DeckBuilder/Engine/VinylCutListEngine.swift` (Codable conformance on `VinylOrderSettings` + `VinylLayoutDirection`)
- Modify: `OPS/DeckBuilder/Models/DeckGeometry.swift` (`DeckDrawingData`: two new optional nodes)
- Test: `OPSTests/DeckBuilder/DeckMaterialsCodableTests.swift`

**Step 1 — failing tests** (create test file):

```swift
import XCTest
@testable import OPS

final class DeckMaterialsCodableTests: XCTestCase {

    func testLegacyJSONDecodesWithNilMaterialsNodes() throws {
        let legacy = #"{"vertices":[],"edges":[]}"#
        let data = try XCTUnwrap(DeckDrawingData.fromJSON(legacy))
        XCTAssertNil(data.materialsSettings)
        XCTAssertNil(data.orderedMaterials)
    }

    func testMaterialsSettingsDefaults() {
        let s = DeckMaterialsSettings()
        XCTAssertEqual(s.glueCoverageSqFt, 400)
        XCTAssertEqual(s.dripStickFeet, 8)
        XCTAssertEqual(s.ninetyStickFeet, 8)
        XCTAssertEqual(s.clipStickFeet, 10)
    }

    func testSettingsPartialJSONFillsDefaults() throws {
        let json = #"{"glueCoverageSqFt":350}"#
        let s = try JSONDecoder().decode(DeckMaterialsSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.glueCoverageSqFt, 350)
        XCTAssertEqual(s.clipStickFeet, 10)
    }

    func testSnapshotRoundTripsThroughDrawingData() throws {
        var data = DeckDrawingData()
        data.materialsSettings = DeckMaterialsSettings(glueCoverageSqFt: 350, dripStickFeet: 10, ninetyStickFeet: 8, clipStickFeet: 12)
        data.orderedMaterials = DeckMaterialsSnapshot(
            orderedAt: Date(timeIntervalSince1970: 1_780_000_000),
            orderedBy: "user-1",
            settings: data.materialsSettings!,
            vinylSettings: .default,
            vinylColor: "Sandstone",
            vinylOrderedSqFt: 260,
            vinylSurfaceAreaSqFt: 240,
            cutGroups: [DeckMaterialsSnapshot.CutGroup(surfaceLabel: "Main", count: 2, lengthInches: 252, rollWidthInches: 72)],
            dripEdgeFeet: 44, dripSticks: 6,
            clipFeet: 44, clipSticks: 5,
            ninetyFeet: 20, ninetySticks: 3,
            glueAreaSqFt: 240, glueBuckets: 1
        )
        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(data.toJSON()))
        XCTAssertEqual(decoded.materialsSettings, data.materialsSettings)
        XCTAssertEqual(decoded.orderedMaterials, data.orderedMaterials)
    }

    func testVinylOrderSettingsCodableRoundTrip() throws {
        var s = VinylOrderSettings.default
        s.rollWidthInches = 61
        s.direction = .widthwise
        let decoded = try JSONDecoder().decode(VinylOrderSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }
}
```

**Step 2 — run, verify FAIL** (types don't exist). **Step 3 — implement:**

`DeckMaterials.swift` — both structs per spec §4 (house-style Codable: CodingKeys + `init(from:)` with `decodeIfPresent ?? default` per field; snapshot fields with no sane default — `orderedAt`, numeric totals — decode with `decodeIfPresent ?? 0`/`?? Date.distantPast` rather than throwing, EXCEPT keep `orderedAt` required via `decode` so a corrupt snapshot fails decode and `DeckDrawingData`'s `decodeIfPresent` nils the whole node gracefully). Nested `CutGroup: Codable, Equatable {surfaceLabel, count, lengthInches, rollWidthInches}`.

`VinylCutListEngine.swift`: add `Codable` to `VinylLayoutDirection` (String raw — synthesized) and to `VinylOrderSettings` with explicit CodingKeys + custom `init(from:)` defaulting every field to `.default`'s values (this struct has a custom memberwise init already — synthesis unaffected).

`DeckGeometry.swift` (`DeckDrawingData`): add `var materialsSettings: DeckMaterialsSettings? = nil` and `var orderedMaterials: DeckMaterialsSnapshot? = nil`, two CodingKeys, two `decodeIfPresent` lines in `init(from:)`. `toJSON()` needs no change (Encodable synthesis covers optionals).

**Step 4 — run, verify PASS. Step 5 — commit** `feat(deck): materials settings + ordered snapshot models in drawing JSON`

---

## Task 2: Extract `VinylOrderScaleResolver` (behavior-preserving)

**Files:**
- Create: `OPS/DeckBuilder/Engine/VinylOrderScaleResolver.swift`
- Modify: `OPS/DeckBuilder/DeckBuilderViewModel.swift:2746-2809+` (delegate; delete moved privates)
- Test: `OPSTests/DeckBuilder/VinylOrderScaleResolverTests.swift`

**Step 1 — failing tests.** Build fixtures with a tiny factory (top of test file):

```swift
private func edge(_ a: DeckVertex, _ b: DeckVertex, dim: Double?, source: DimensionSource, stale: Bool = false) -> DeckEdge {
    DeckEdge(startVertexId: a.id, endVertexId: b.id, dimension: dim, dimensionSource: source, dimensionStale: stale)
}
private func square(_ side: CGFloat) -> [DeckVertex] {
    [CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0), CGPoint(x: side, y: side), CGPoint(x: 0, y: side)].map { DeckVertex(position: $0) }
}
```

Cases (assert against `VinylOrderScaleResolver.resolve(data)`):
1. Any `dimensionStale` edge → nil.
2. `scaleFactor = 2.0` set → 2.0 (wins over everything).
3. No scaleFactor, ALL edges `.scale` source → `DeckBuilderViewModel.prescaleFallbackScale`.
4. No scaleFactor, manual-confirmed dims agreeing (100pt edge, dim 50" → scale 2.0 on all four) → 2.0.
5. Same but one dim disagreeing beyond tolerance → nil.

**Step 2 — FAIL. Step 3:** relocate `vinylOrderEffectiveScale`, `canUsePrescaleFallbackForVinylOrder`, `VinylOrderScaleMeasurement`, `inferredVinylOrderScaleFromConfirmedDimensions`, `vinylOrderScaleMeasurements(...)`, `isConfirmedVinylDimensionSource`, `vinylOrderScaleToleranceInches` into `enum VinylOrderScaleResolver { static func resolve(_ data: DeckDrawingData) -> Double? }` — code moved verbatim (operating on `data` instead of `drawingData`). View model's `vinylOrderEffectiveScale` becomes `VinylOrderScaleResolver.resolve(drawingData)`. Grep for other callers of the moved privates first (`grep -n "vinylOrderScaleMeasurements\|canUsePrescaleFallback" OPS -r`).

**Step 4 — PASS + full OPSTests suite green (regression). Step 5 — commit** `refactor(deck): extract vinyl order scale resolution into pure resolver`

---

## Task 3: `DeckMaterialsInputBuilder` (read-only surface inputs)

**Files:**
- Create: `OPS/DeckBuilder/Engine/DeckMaterialsInputBuilder.swift`
- Test: `OPSTests/DeckBuilder/DeckMaterialsInputBuilderTests.swift`

Non-mutating equivalent of `DeckBuilderViewModel.vinylOrderSurfaceInputs(scope: .allSurfaces)` (`DeckBuilderViewModel.swift:2648-2744` is the reference — copy the matching logic, do NOT call `reconcileSurfaces`):

```swift
enum DeckMaterialsInputBuilder {
    /// Read-only surface inputs for the materials list. Persisted surfaces are
    /// matched to detected faces (exact vertex set, else best Jaccard ≥
    /// SurfaceReconciler.rebindThreshold). When the persisted store is EMPTY,
    /// every detected face becomes an input directly (legacy designs never
    /// reconciled since DECK-NEW-1) with labels "Surface N".
    static func surfaceInputs(for data: DeckDrawingData, scale: Double) -> [VinylOrderSurfaceInput]
}
```

Per level when multi-level (levelName threaded). Edges built exactly like `vinylOrderSurfaceEdges` (bidirectional vertex-pair match, fallback `.deckEdge`). **Also return, per input, the persisted surface's `assignedItems`** — extend the return to `[(input: VinylOrderSurfaceInput, assignedItems: [AssignedItem])]` (empty for detected-fallback faces).

**Tests:** matched persisted surface uses its label; empty persisted store + one closed detected face → 1 input labeled "Surface 1" with empty items; edge types carried (mark one edge `.houseEdge`, assert it lands on the matching `VinylOrderSurfaceEdge`).

TDD steps as Task 1. **Commit** `feat(deck): read-only materials surface input builder`

---

## Task 4: Vinyl detection

**Files:**
- Create: `OPS/DeckBuilder/Engine/DeckVinylDetection.swift`
- Modify: `OPS/DeckBuilder/Models/BuiltInMaterial.swift` (append to `areaStandards`)
- Test: `OPSTests/DeckBuilder/DeckVinylDetectionTests.swift`

```swift
enum DeckVinylDetection {
    static let vinylStandardId = "std.decking.vinyl"

    /// Spec §5. `catalogNameById` maps CatalogItem.id → name+description blob
    /// (lowercased) supplied by the caller; pure otherwise.
    static func vinylSurfaceIds(
        surfaces: [(input: VinylOrderSurfaceInput, assignedItems: [AssignedItem])],
        jobHasVinylSignal: Bool,
        catalogNameById: [String: String]
    ) -> Set<String>

    /// True when any task-type display name contains "vinyl" (case/diacritic-
    /// insensitive) or the design's configured vinyl product is set.
    static func jobHasVinylSignal(taskTypeDisplays: [String], vinylCatalogItemId: String?) -> Bool
}
```

Area-item classification per spec §5.2 (`id == vinylStandardId` OR `name.localizedCaseInsensitiveContains("vinyl")` OR catalog blob contains "vinyl"). NOTE: `AssignedItem` has no unitType filter need here — surfaces only carry area items, but defensively ignore items whose `unitType` is not `.squareFoot`/`.squareMeter`.

`BuiltInMaterial.areaStandards` append:
```swift
BuiltInMaterial(id: "std.decking.vinyl", name: "Vinyl Membrane", subtitle: "Duradek, Tufdek style sheet vinyl", icon: "square.grid.3x3")
```

**Tests (spec §10 matrix):** explicit vinyl by name / by standard id / by catalog blob; non-vinyl-assigned excluded even with job signal; unassigned + task signal ("VINYL INSTALL", "Vinyl Removal + Install") included; unassigned + config signal included; no signals → empty; mixed job (one composite-assigned, one unassigned, signal on) → only unassigned id.

TDD steps, then **commit** `feat(deck): vinyl surface auto-detection + Vinyl Membrane standard`

---

## Task 5: `DeckMaterialsEngine`

**Files:**
- Create: `OPS/DeckBuilder/Engine/DeckMaterialsEngine.swift`
- Test: `OPSTests/DeckBuilder/DeckMaterialsEngineTests.swift`

```swift
struct DeckMaterialsList: Equatable {
    struct FlashingLine: Equatable {
        var exactFeet: Double        // pre-rounding sum
        var displayFeet: Int         // Int(ceil(exactFeet)), 0 → row shows "—"
        var stickFeet: Double
        var sticks: Int              // Int(ceil(exactFeet / stickFeet)), 0 when exactFeet == 0
    }
    var vinylPlan: VinylCutPlan
    var vinylSurfaceIds: Set<String>
    var dripEdge: FlashingLine
    var clip: FlashingLine           // same exactFeet as dripEdge, own stick math
    var ninetyFlash: FlashingLine
    var glueAreaSqFt: Double
    var glueBuckets: Int             // Int(ceil(glueAreaSqFt / settings.glueCoverageSqFt))
    /// Seed/label-independent drift key: sorted (lengthInches, rollWidthInches)
    /// pairs of ALL cuts + flashing exact feet + glue area + surface count.
    var driftKey: DeckMaterialsDriftKey
}

enum DeckMaterialsEngine {
    static func compute(
        vinylInputs: [VinylOrderSurfaceInput],       // vinyl set only
        allDetectedFacesByLevel: [[DetectedSurface]],// interior-seam test (ALL faces, vinyl or not)
        settings: DeckMaterialsSettings,
        vinylSettings: VinylOrderSettings
    ) -> DeckMaterialsList
}
```

**Classification** (spec §6.1, first match wins) per vinyl input's edges (`VinylOrderSurfaceEdge` already ordered around the face):
1. Interior: the segment's unordered vertex-id pair occurs in ≥2 detected faces on the same level → skip. Implementation: build a `[String: Int]` count of canonical `"minId|maxId"` pair keys across all faces per level; edges carry their matched `DeckEdge.id` — but unmatched segments have synthetic ids, so ALSO pass the vertex-id pair through `VinylOrderSurfaceEdge`… **it doesn't carry vertex ids.** Extend `VinylOrderSurfaceEdge` with `let startVertexId: String?` / `let endVertexId: String?` (optional, defaulted nil in the two existing construction sites — `DeckBuilderViewModel.vinylOrderSurfaceEdges` fills them from `face.vertexIds`; `VinylCutPreview.previewEdges` fallback leaves nil). Interior test uses the pair when present; nil pair → never interior.
2. Segment's matched `edgeType == .houseEdge` → ninety.
3. Matched edge's `railingConfig?.railingType == .parapetWall` → ninety. **`VinylOrderSurfaceEdge` doesn't carry railing either — add `let isParapet: Bool` (default false)**, filled at construction from the matched `DeckEdge`.
4. Else → drip (+clip). Stairs deliberately ignored.
Segment length: matched edge `dimension` when `> 0` else euclidean(start,end)/scale — **the input builder already resolves positions in canvas points and carries `scaleFactor`; add `let dimensionInches: Double?` to `VinylOrderSurfaceEdge`** (filled from matched edge), engine falls back to canvas math.

`vinylPlan` = `VinylCutListEngine.makePlan(surfaces: vinylInputs, settings: vinylSettings)` (no offcut seeds). `glueAreaSqFt` = Σ per-input `PolygonMath.realWorldArea(vertices:scaleFactor:)/144` skipping self-intersecting faces (mirror `totalRealWorldArea`).

**Tests (exact numbers):**
- *Rect 12'×20', scale 1pt=1", one 20' house edge:* drip/clip exactFeet 44, displayFeet 44, dripSticks(8') 6, clipSticks(10') 5; ninety 20 ft, 3 sticks; glue area 240, buckets(400) 1.
- *Parapet railing:* same rect, house edge → deckEdge but with `RailingConfig(railingType: .parapetWall, maxPostSpacing: 96)` → identical ninety numbers.
- *Interior seam:* two 10'×10' squares sharing an edge (5 vertices shared pair) — drip 60 ft total, shared segment contributes 0.
- *Stair edge:* rect with `stairConfig` width 48 on one open edge → drip unchanged (full span).
- *Stick rounding:* 24' exact @ 8' → 3 sticks; 24'1" (289") → 4 sticks. Glue: 400 sq ft → 1 bucket; 401 → 2.
- *Zero ninety:* no house/parapet → ninetyFlash.sticks == 0, displayFeet == 0.
- *Multi-level:* two levels' rects sum.
- *Drift key:* recompute after relabeling a surface → equal keys; after moving a vertex (length change) → different keys.

TDD steps; run FULL OPSTests (VinylOrderSurfaceEdge change touches existing tests). **Commit** `feat(deck): materials engine — flashing classification, sticks, glue`

---

## Task 6: `DeckMaterialsOrderService` + wiring both MARK ORDERED paths

**Files:**
- Create: `OPS/DeckBuilder/Services/DeckMaterialsOrderService.swift`
- Modify: `OPS/DeckBuilder/Views/VinylOrderSheet.swift` (`setProjectVinylOrdered`)
- Modify: `OPS/Views/Components/Project/ProjectDetailsViewModel.swift` (`setVinylOrdered`)
- Test: `OPSTests/DeckBuilder/DeckMaterialsOrderServiceTests.swift`

Service (`@MainActor struct`, mirrors `VinylOffcutInventoryService` shape). Injected updater for testability:

```swift
@MainActor
struct DeckMaterialsOrderService {
    let userId: String
    /// DataController.updateProjectFields in production; injected for tests.
    let updateProjectFields: (String, [String: AnyJSON]) async throws -> Void

    /// Spec §8: snapshot into the design FIRST (local-only, cannot fail
    /// remotely), then the project marker write; revert the snapshot if the
    /// marker write throws so the two never disagree.
    func markOrdered(projectId: String, design: DeckDesign, materials: DeckMaterialsList, settings: DeckMaterialsSettings, vinylSettings: VinylOrderSettings) async throws
    func clearOrdered(projectId: String, design: DeckDesign?) async throws
}
```

`markOrdered` builds `DeckMaterialsSnapshot` (cutGroups = PURCHASED `VinylCutGroup`s from `materials.vinylPlan`; vinylOrderedSqFt = `totalOrderedSqFt`; color from `vinylSettings.color`), assigns via `design.drawingData` accessor (marks needsSync), then calls updater with the exact `ProjectVinylOrderFields` trio VinylOrderSheet builds today (`Project.swift:538-542`; ordered: status/.ordered + orderedAt now + orderedBy userId). On throw: restore prior `orderedMaterials` (captured before mutation) and rethrow. `clearOrdered`: nil the node (when design non-nil), clear fields (`.null`s), same compensation.

**Call-site wiring (keep every existing gate, status message, and haptic exactly as-is):**
- `VinylOrderSheet.setProjectVinylOrdered(true)`: compute `DeckMaterialsList` from the sheet's live `plan`… the sheet's plan is already the vinyl half; flashing/glue need the engine — compute via the Task-3/4/5 pipeline over the sheet's `viewModel.drawingData` with the design's `materialsSettings ?? .init()` and the sheet's current `settings`. Then `service.markOrdered(...)`. `false` → `service.clearOrdered(...)` with `viewModel.deckDesign`.
- `ProjectDetailsViewModel.setVinylOrdered`: read the current implementation FIRST (`grep -n "setVinylOrdered" OPS/Views/Components/Project/ProjectDetailsViewModel.swift`). Wrap its field write with the service; design := `DeckDesign.displayCandidate(in:forProjectId:)` fetched from its modelContext; when design nil / no vinyl set / scale nil → call updater directly exactly as today (marker without snapshot — materials section is absent for those projects anyway).

**Tests:** happy markOrdered (spy updater captures trio; snapshot lands in design JSON, cutGroups purchased-only); updater throws → `orderedMaterials` reverted to prior value + error propagated; clearOrdered clears node + sends `.null` fields; clearOrdered with nil design still clears fields.

TDD; **commit** `feat(deck): shared mark-ordered service snapshots materials into design JSON`

---

## Task 7: `DeckMaterialsSection` UI + DeckTabView integration

**Skills:** `ops-design` + `custom-skills:mobile-ux-design` loaded; `custom-skills:audit-design-system` before calling this done. Copy below is final (ops-copywriter register) — do not invent strings.

**Files:**
- Create: `OPS/Views/Components/Project/Tabs/DeckMaterialsSection.swift`
- Modify: `OPS/Views/Components/Project/Tabs/DeckTabView.swift` (compose below viewport inside `designViewer`'s VStack, `.padding(.horizontal, OPSStyle.Layout.spacing3)`)

**Design tokens (exclusively):** section header `OPSStyle.Typography.metadata` + `.tracking(1.1)` + `OPSStyle.Colors.secondaryText`; row labels `Typography.smallCaption`/`tertiaryText`; values `Typography.dataValue`/`primaryText` + `.monospacedDigit()`; cards `Colors.cardBackgroundDark` + `RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)` + `Colors.cardBorder` stroke `Layout.Border.standard`; spacing `Layout.spacing1/2/3`; ordered stamp `Colors.successStatus`; drift + confirm-dims banners reuse VinylOrderSheet's `banner(text:color:)` pattern (`warningStatus`); steppers clone `VinylOrderSheet.settingStepper` (label width pattern, `.tint(OPSStyle.Colors.secondaryText)`) + `UIImpactFeedbackGenerator(style: .light)` on value change. Empty value = `—`. Numbers always formatted (`vinylFormatFeetAndInches` for sticks label, whole-ft ints elsewhere).

**Copy (final):** header `// MATERIALS`; rows `VINYL`, `DRIP EDGE`, `CLIP`, `90 FLASH`, `GLUE`; value patterns `46 FT · 6 STICKS @ 8'`, `3 BUCKETS · 1 PER 400 SQ FT`; vinyl block: color line (`FIELD CONFIRM` when empty), cut group lines via `VinylCutGroup.orderFragment`, `ORDER 260 SQ FT`; stamps `ORDERED JUN 12` (DateHelper.simpleDateString uppercased — match VinylOrderSheet:837), `DESIGN CHANGED SINCE ORDER`, scale-missing banner `CONFIRM ONE EDGE LENGTH` (verbatim reuse); stepper labels `DRIP STICK`, `90 STICK`, `CLIP STICK`, `COVERAGE`.

**Behavior:**
- Input: `design: DeckDesign`, `project: Project`, plus `modelContext`. All computation **memoized in @State**, recomputed ONLY on `.onChange(of: design.drawingDataJSON)` + initial `.task` (the sheet's memo-hooks comment at VinylOrderSheet:46-51 documents why — never compute in body).
- Compute pipeline: decode `drawingData` once → `VinylOrderScaleResolver.resolve` → `DeckMaterialsInputBuilder` → job signal (FetchDescriptor<ProjectTask> on projectId, deletedAt == nil → `taskType?.display`; plus `config.vinylCatalogItemId`) → `DeckVinylDetection` (catalog blob map via FetchDescriptor<CatalogItem> on companyId — on-demand fetch, NOT @Query, to avoid invalidation storms on this perf-sensitive page) → `DeckMaterialsEngine.compute` with `materialsSettings ?? .init()` and default-seeded vinyl settings (apply `config.vinylCatalogItemId` resolution like `applyConfiguredCatalogProduct`).
- States: (1) vinyl set empty → render `EmptyView` (tab byte-identical for non-vinyl); (2) scale nil → header + confirm-dims banner only; (3) live → rows + steppers; (4) `orderedMaterials != nil` → snapshot values, `ORDERED <DATE>` stamp, steppers replaced by inline read-only values, drift banner iff recompute-with-snapshot-settings driftKey ≠ snapshot-derived driftKey.
- Stepper ranges: coverage 100…1000 step 25; sticks 4…20 step 1. Writes: mutate `design.drawingData.materialsSettings` (accessor marks needsSync + updatedAt; syncs company-wide). Preset edit allowed at `deck_builder.view` (product call — calculator preference); no extra gate.
- Reduced motion: no new animation; the section renders statically (matches level-chip precedent, DeckTabView:196-200).

Also verify the `DeckTab2DView`/3D viewport `.aspectRatio` container is untouched and the section scrolls beneath (this tab lives in ProjectDetailsView's ScrollView).

**Verification:** device-target build green; screenshot proofs deferred to Task 8; run `custom-skills:audit-design-system` over the new file — zero hardcoded values. **Commit** `feat(deck): materials list section on project deck tab`

---

## Task 8: Snapshot proofs

**Files:**
- Create: `OPSTests/Views/DeckMaterialsSnapshotTests.swift` (clone the `BooksSnapshotTests` harness — `UIHostingController` + `UIWindow` + `drawHierarchy(afterScreenUpdates: true)`; ImageRenderer is banned: asset colors render yellow, no onAppear)

Render four PNGs — live state, ordered state, ordered+drift, confirm-dimensions — from fixture `DeckDrawingData` (reuse Task 5's rect fixtures; inject precomputed state so no SwiftData needed, e.g. give `DeckMaterialsSection` an internal init accepting resolved state). Write PNGs via the harness's attachment/export path to `docs/artifacts/deck-materials-*.png`.

Run just this class; verify PNGs exist and visually match spec §9 states (open them). **Commit** `test(deck): materials section snapshot proofs`

---

## Task 9: Full verification + bible + wrap-up

1. Full test suite (simulator destination) → `** TEST SUCCEEDED **`.
2. Device-target build (generic/platform=iOS) → `** BUILD SUCCEEDED **`.
3. Bible updates (same session, per spec §11):
   - `ops-software-bible/07_SPECIALIZED_FEATURES.md` Deck Builder section: materials list (detection chain, flashing rules, presets, ordered snapshot + drift, both MARK ORDERED paths).
   - `ops-software-bible/03_DATA_ARCHITECTURE.md`: `deck_designs.drawing_data` gains optional `materialsSettings` + `orderedMaterials` keys; additive-only JSON discipline note.
   - Commit in the BIBLE repo: `docs(deck): materials list — detection, flashing math, ordered snapshot`.
4. Final report back (plain language): what shipped, test/build output tails, the four PNG proofs, audit result. **Do NOT push, do NOT merge** — the branch stays local for Jackson's go.

---

## Execution notes for the operator (parent session)

- Single executor session (files overlap across tasks; no parallel fan-out). Spawn title: `DECK MATERIALS - P1-1`.
- The executor works in a fresh worktree of `ops-ios` — Secrets.xcconfig copy + `.spm-local` are in the working rules above.
- Out of scope guardrails (spec §12): no stair treads, no termination bars, no CREATE ORDER + NOTE changes, no flashing inventory, no per-run flashing cut lists.
