# OPS Decks — Phase 2: Framing Model + Auto-Framing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Before editing any complex file, READ the cited line ranges first — several tasks anchor to current code rather than restating whole files.
>
> **HEADER NOTE — bite-sized TDD finalization:** This plan is authored *before* Phase 1 lands. It targets the Phase 1 contract surfaces (`DeckKit` package, `DeckStore`/`ImageUploader`/`OCRService`/`CodePackageLoader` seams, `DeckCapabilities`, the `unknownBlocks` passthrough, the relocated `DeckDrawingData`/engines). **Bite-sized TDD steps with literal code are finalized at phase start once predecessors exist** — when Phase 1 is merged, re-read the actual relocated file paths + the real `DeckCapabilities`/`CapabilityProvider` signatures, then decompose each Task below into red/green/refactor commits. Signatures quoted from the architecture contract are LOCKED and adopted verbatim; signatures for *Phase-1-introduced* types are consumed as-is and must not be re-declared here.

---

## Goal

Deliver the **framing foundation** — the critical-path block on which every later engineering phase (P3 sizing, P4 footings, P6 overhead, P7 compliance/permit) depends. Concretely, Phase 2 ships, for **BOTH** tiers:

1. A first-class, additive **`FramingPlan`** block inside `DeckDrawingData` (schema version → 2): joist / beam / post / ledger / rim-band / blocking / bridging / cantilever members, per-level, with species/grade + load preset.
2. A **species/grade + load-preset selector** UI (`LoadPreset`) — drives sizing later; in Phase 2 it only stamps assumptions onto the plan.
3. An **auto-framing engine** that derives a *plausible* default frame from the existing outline + `EdgeType.houseEdge` + resolved elevation, mirroring `DeckTemplateEngine`'s **auto-then-preserve** contract (`FramingSource.autoThenEdited` + per-member `locked`). **No code claim** — every member's `sizing` stays `nil` in Phase 2.
4. A **real framing 3D render** with **layer toggles** (decking / joists / beams / posts / footings / rim) replacing the decorative fixed-geometry frame in `DeckSceneBuilder` (the hardcoded 6×6 posts / 11″×5″ footing box / 9.25″ rim — `DeckSceneBuilder.swift:462-524`).
5. A **rough framing BOM** — lumber + rough hardware + (visual) footing counts emitted additively through `ComponentEmitter` and threaded into `EstimateGeneratorService` (waste-aware, reusing the P1 `WasteSettings` path).
6. **Ground-type selection** + a **textured 3D ground** render — `GroundCover` zones (grass/dirt/gravel/rock/concrete/pavers) on a `TerrainModel` ground-cover-only subset, replacing the flat 30%-alpha green tint.

**Out of scope (explicitly deferred):** any span/sizing/load number (`FramingMember.sizing` is P3); grade/slope math, footing sizing, frost/soil (P4 — Phase 2 ships `GroundCover` *only*, not `gradePoints`/footing engine); any compliance/"no code failures detected" output (P7). Phase 2 makes **zero** engineering assertions. The frame is for *visualization + scoping*, gated by `.plausibleFrame`; ground cover gated by `.groundCover`.

## Architecture

- **One additive block, backward-decodable.** `FramingPlan?` becomes a new optional top-level property on `DeckDrawingData` (contract §2.4), decoded with `decodeIfPresent`, wired into `CodingKeys` + the defensive `init(from:)`, and `DeckDesign.version` bumps to **2** (contract §0.3, §2.2). A LIGHT build (OPS) and a FULL build (OPS Decks) share the schema; both render + edit the frame (`.plausibleFrame` is in `DeckCapabilities.light`). Any older build that predates Phase 2 round-trips the `framing` block untouched via the Phase 1 `unknownBlocks` passthrough (contract §1.4).
- **Pure, table-light engine.** `AutoFramingEngine` is an `enum` namespace of `static func`s (the `DeckTemplateEngine` / `StairCalculator` precedent) — value in, `FramingPlan` out. No I/O, no `ModelContext`, no network, no singletons (contract §0.4). It derives geometry only; it never touches `CodePackage` (that's P3).
- **Auto-then-preserve.** Re-deriving a frame after the outline changes must NOT clobber members the user hand-edited. `FramingSource` (`.auto` / `.manual` / `.autoThenEdited`) + per-member `locked: Bool` mirror `DeckTemplateEngine.copyDrawingData`'s id-preserving regeneration and the `DimensionSource`-authoritative-preserve pattern already in `DeckEdge`.
- **Capability-gated rendering, never data.** Framing data is always present + always round-tripped. The framing 3D layer + the framing editor surface + the framing BOM rows render only when `.plausibleFrame` is in the active `DeckCapabilities`; ground-cover render + picker gate on `.groundCover`. Both are in `.light`, so OPS and OPS Decks both light up. A future build lacking the flag still preserves the block.
- **DeckKit-internal.** Everything lands inside `DeckKit/Sources/DeckKit/` (relocated in P1). No reach into `Project`/`Company`/`AppState`/`SyncEngine`. Styling via `OPSStyle` (now in `OPSDesignKit`).

## Tech Stack

Swift 6 / SwiftUI / SceneKit (3D) / SwiftData (persistence via `DeckStore`). `Codable` blob schema. XCTest for the pure engine + round-trip + emitter tests; `ImageRenderer → XCTAttachment` snapshot harness for 3D/2D render verification (memory `ops-ios-swiftui-snapshot-harness`). Build per `ops-ios/CLAUDE.md`:

- **Device-target build verify (every code task):** `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
- **Test compile:** `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing`
- **Run tests:** `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test`
- **Worktree:** `cp OPS/Utilities/Secrets.xcconfig <worktree>/OPS/Utilities/Secrets.xcconfig`; append `-clonedSourcePackagesDirPath .spm-local`. Grep the log for `BUILD SUCCEEDED` / `TEST SUCCEEDED` (memory `xcodebuild-exit-code-masking`). "Cannot find type X" in a fresh worktree/new file is SourceKit index lag — trust `xcodebuild` (memory `ops-ios-worktree-sourcekit-lag`).

---

## File Structure

> Paths assume the Phase 1 carve-out has moved `DeckBuilder/` → `DeckKit/Sources/DeckKit/`. If P1 ships a different internal subfolder name, adopt that at phase start.

### Create

| File | Responsibility |
|---|---|
| `DeckKit/Sources/DeckKit/Models/FramingPlan.swift` | The `FramingPlan` block + all sub-types (`FramingMemberSet`, `FramingMember`, `FramingRole`, `LumberSize`, `WoodSpecies`, `LumberGrade`, `FramingSource`, `LoadPreset`) — Codable, additive, defensive `init(from:)`. Contract §2.4. |
| `DeckKit/Sources/DeckKit/Engine/EngineEnvelope.swift` | The shared engine result envelope — `EngineOutcome<T>`, `EngineCitation`, `EngineAssumptions`, `SizedMember`, `MemberSizingResult` (contract §3 / §3.1 shapes). P2 OWNS these (first consumer via `FramingMember.sizing`); P3+ reuse them. P2 sets `sizing = nil` everywhere but the types must exist. |
| `DeckKit/Sources/DeckKit/Engine/AutoFramingEngine.swift` | Pure auto-framing engine — derives joists/beams/posts/ledger/rim/blocking from outline + house edge + elevation; auto-then-preserve merge. |
| `DeckKit/Sources/DeckKit/Engine/FramingGeometry.swift` | Pure geometry helpers shared by the engine + renderer: joist-direction inference, joist run layout, beam-line placement, post spacing, span-segmentation. (Split out so both engine + 3D builder consume one source of truth; no I/O.) |
| `DeckKit/Sources/DeckKit/Models/GroundCoverModel.swift` | The full `TerrainModel` block (P2 introduces the WHOLE struct, contract §2.5) + `GroundZone` + `GradePoint` + the `GroundCover` enum. P2 populates ONLY `groundCover`; `gradePoints`/`slopeSource` are declared from day one and filled by P4 — no rename, additive within the same block. Contract §2.5. |
| `DeckKit/Sources/DeckKit/Scene3D/FramingSceneBuilder.swift` | Builds real per-member SCNNodes (joists/beams/posts/rim/blocking) from a `FramingPlan`, grouped into named layer nodes for toggling. Replaces `DeckSceneBuilder.buildSupportPosts`'s decorative props. |
| `DeckKit/Sources/DeckKit/Scene3D/FramingLayerToggle.swift` | `FramingLayer` OptionSet + the SCNNode show/hide applicator (decking/joists/beams/posts/footings/rim). |
| `DeckKit/Sources/DeckKit/Scene3D/GroundTextureFactory.swift` | Maps `GroundCover` → SceneKit material (texture/normal/tiling) for the textured ground plane. |
| `DeckKit/Sources/DeckKit/Engine/FramingTakeoff.swift` | Pure rough-BOM projection: `FramingPlan` → lumber-length + hardware + footing-count rows (waste-aware via `WasteSettings`). |
| `DeckKit/Sources/DeckKit/Views/FramingControlsView.swift` | The framing UI: load-preset/species/grade selector, "Generate frame" action, layer-toggle bar, ground-cover picker. Gated by capability. |
| `DeckKit/Tests/DeckKitTests/FramingPlanCodableTests.swift` | Round-trip + backward-decode + capability-preserve tests for the new block. |
| `DeckKit/Tests/DeckKitTests/AutoFramingEngineTests.swift` | Table-driven engine tests (member derivation, auto-then-preserve, locked-member preservation). |
| `DeckKit/Tests/DeckKitTests/FramingGeometryTests.swift` | Joist-direction/layout/post-spacing math tests. |
| `DeckKit/Tests/DeckKitTests/FramingTakeoffTests.swift` | Rough-BOM count/length/waste assertions. |
| `DeckKit/Tests/DeckKitTests/FramingSnapshotTests.swift` | `ImageRenderer → XCTAttachment` 3D framing-layer + ground render snapshots. |

### Modify

| File | Change |
|---|---|
| `DeckKit/Sources/DeckKit/Models/DeckGeometry.swift` | Add `var framing: FramingPlan? = nil` + `var terrain: TerrainModel? = nil` to `DeckDrawingData`; add both to `CodingKeys` + `init(from:)` with `decodeIfPresent`. Keep `toJSON()`/`fromJSON()` round-tripping them. (Contract §2.2/§2.4/§2.5.) |
| `DeckKit/Sources/DeckKit/DataModels/DeckDesign.swift` | Bump default `version` semantics: a design carrying a non-nil `framing` is schema-version 2; the migration/backfill helper stamps `drawingData.schemaVersion` + `DeckDesign.version`. |
| `DeckKit/Sources/DeckKit/Engine/ComponentEmitter.swift` | Add additive component rows (`joist`, `beam`, `post`, `rim_joist`, `blocking`) emitted from `FramingPlan` — never rename existing types (doc-comment contract). |
| `DeckKit/Sources/DeckKit/Engine/EstimateGeneratorService.swift` | Add a framing line-item category fed by `FramingTakeoff`, threaded through the same `WasteSettings` path P1 introduced. |
| `DeckKit/Sources/DeckKit/3D/DeckSceneBuilder.swift` | Delegate substructure to `FramingSceneBuilder` when `framing != nil` + `.plausibleFrame` present; otherwise keep the legacy decorative fallback (degrade-safe). Swap flat ground for `GroundTextureFactory`. Group nodes into toggle layers. |
| `DeckKit/Sources/DeckKit/Capability/DeckCapabilities.swift` | (Defined P1.) Phase 2 *consumes* `.plausibleFrame` + `.groundCover`; if P1 did not yet add those bits, add them here per contract §4 (both belong to `.light`). |
| `DeckKit/Sources/DeckKit/Views/DeckBuilderViewModel.swift` | Add `generateFraming()` / `regenerateFramingPreservingEdits()` / `setLoadPreset(_:)` / `setGroundCover(_:for:)` action methods + a `framingLayerVisibility` published state; route through `DeckStore.saveDeck`. |
| `ops-software-bible/` (relevant deck/section) | Document the `framing` + `terrain.groundCover` blocks, the auto-framing contract, and the new `component_type` rows. (CLAUDE.md: keep the bible current in the same session.) |

---

## Tasks

> Sequence rationale: schema first (everything serializes through it), then the pure engines (TDD against fixtures), then the projections (BOM/emitter), then rendering, then UI/VM wiring, then the bible. Pure-logic tasks (1–5) are fully testable without the simulator; render tasks (6–8) use the snapshot harness; UI (9) is human visual-QA.

### Task 1 — `FramingPlan` schema block + sub-types

**Depends on (Phase 1):** the relocated `DeckDrawingData` (`DeckGeometry.swift`), the `unknownBlocks: [String: AnyCodable]?` passthrough + the nested-capable `AnyCodable` (P1 extended it beyond scalars), `DeckDesign.version`, and the existing `DeckVertex.position: CGPoint` coordinate space.

**Interface (verbatim from contract §2.4 — adopt exactly, do not rename):**

```swift
public struct FramingPlan: Codable, Equatable {
    public var members: [FramingMemberSet]           // keyed by DeckLevel.id ("" sentinel = single-level)
    public var loadPreset: LoadPreset?
    public var generationSource: FramingSource        // .auto | .manual | .autoThenEdited
    public var generatedAtSchemaVersion: Int?
}
public struct FramingMemberSet: Codable, Equatable {
    public var levelId: String
    public var members: [FramingMember]
}
public struct FramingMember: Codable, Equatable, Identifiable {
    public let id: String
    public var role: FramingRole          // joist|beam|post|ledger|rimBand|blocking|bridging|cantilever
    public var start: CGPoint             // canvas coords — same space as DeckVertex.position
    public var end: CGPoint
    public var nominalSize: LumberSize?    // nil until sized
    public var plyCount: Int = 1
    public var spacingInchesOC: Double?    // joists/blocking
    public var species: WoodSpecies?
    public var grade: LumberGrade?
    public var sizing: MemberSizingResult?  // FILLED BY P3; nil = not engineered (LIGHT)
    public var locked: Bool = false         // manual editor: exclude from re-derive
}
public enum FramingRole: String, Codable, CaseIterable {
    case joist, beam, post, ledger, rimBand, blocking, bridging, cantilever
}
public enum LumberSize: String, Codable, CaseIterable {
    case twoBySix = "2x6", twoByEight = "2x8", twoByTen = "2x10", twoByTwelve = "2x12"
    case fourByFour = "4x4", fourBySix = "4x6", sixBySix = "6x6"
}
public enum WoodSpecies: String, Codable, CaseIterable {
    case southernPine = "southern_pine", douglasFirLarch = "df_l"
    case hemFir = "hem_fir", sprucePineFir = "spf", redwoodCedar = "redwood_cedar"
}
public enum LumberGrade: String, Codable, CaseIterable { case select = "select_structural", no1 = "no1", no2 = "no2" }
public enum FramingSource: String, Codable { case auto, manual, autoThenEdited }
public struct LoadPreset: Codable, Equatable {
    public var liveLoadPSF: Double = 40
    public var deadLoadPSF: Double = 10
    public var snowLoadPSF: Double?
    public var species: WoodSpecies = .sprucePineFir
    public var grade: LumberGrade = .no2
}
```

> **`MemberSizingResult` + its envelope are introduced in P2** (contract §3, "Phase ownership" note). P2 is the first consumer of `EngineOutcome<T>`, `EngineCitation`, `EngineAssumptions`, `SizedMember`, and `MemberSizingResult` — via this `FramingMember.sizing: MemberSizingResult?` property. P2 **DEFINES** these types (Task 1b, `EngineEnvelope.swift`) so the schema compiles, and sets `sizing = nil` on every member. P3 reuses them verbatim and fills `sizing`; **P3 must NOT re-declare them.** The P3-specific engine result structs (`JoistSpanResult`/`BeamSizingResult`/`PostSizingResult`/`CantileverResult`/`PostReaction`) are P3's. (See Assumptions.)

**Implementation notes:**
- Every type gets a **defensive `init(from:)`** with `decodeIfPresent` + defaults, mirroring `RailingConfig`/`StairConfig`/`DeckSurface` (`DeckGeometry.swift:363-377`, `496-513`, `683-691`). Use `decodeLegacyBoolIfPresent` for `locked` (the established legacy-Bool helper, `DeckGeometry.swift:6-51`).
- `CGPoint` already has retroactive `Codable` conformance (`DeckGeometry.swift:1241`) — reuse it.
- The `""` `levelId` sentinel maps single-level designs (whose geometry lives in top-level `vertices`/`edges`, not `levels`).
- Add to `DeckDrawingData`: `var framing: FramingPlan? = nil` + the two new `CodingKeys` cases + the two `decodeIfPresent` lines in `init(from:)` (after `components`, `DeckGeometry.swift:757`).

**TEST STRATEGY** (`FramingPlanCodableTests.swift`, runs on sim):
- `test_framingPlan_roundTrips_stable`: build a `FramingPlan` with 1 joist + 1 beam + 2 posts + a `LoadPreset`, attach to a `DeckDrawingData`, `toJSON()` → `fromJSON()` → `toJSON()`; assert the two JSON strings are byte-equal (encoder uses `.sortedKeys`, `DeckGeometry.swift:1162`). Assert decoded `framing` `Equatable`-equals the original.
- `test_legacyJSON_withoutFraming_decodesToNilFraming`: feed a pre-P2 fixture (no `framing` key) → assert `data.framing == nil` and the whole decode succeeds (no throw). This is the §0.2 forward-compat guarantee.
- `test_lightBuild_preservesFramingBlock_onReEncode`: decode a FULL-authored JSON containing `framing`, re-encode through a build configured `.light` (capability does not gate data) → assert `framing` survives byte-for-byte. Pairs with the §1.4 `unknownBlocks` guarantee for builds that predate the declared property.
- `test_malformedFramingMember_doesNotFailWholeDecode`: corrupt one member's `role` to an unknown raw value in the fixture → assert `DeckDrawingData.fromJSON` returns non-nil and the rest of the geometry survives (the unknown enum case must decode-to-skip or the member is dropped, never a whole-design throw — §0.2). Key assertion: `data.vertices.count` unchanged.
- `test_decodeIfPresent_defaults`: a member JSON missing `plyCount`/`locked` → `plyCount == 1`, `locked == false`.

**References:** contract §2.2/§2.4, §0.2, §1.4, §5.1 (naming/units — inches default, `Feet`/`PSF` suffixes). Existing defensive-decoder precedent: `DeckGeometry.swift` `RailingConfig`/`StairConfig`/`DeckSurface`.

**Risks:** (a) `FramingMember.sizing` references `MemberSizingResult`, which Task 1b defines in the SAME phase — sequence Task 1b before/with Task 1's compile (the envelope types must exist for `FramingPlan.swift` to build). (b) `AnyCodable` must already carry nested objects (P1 work) for the `unknownBlocks` passthrough of *other* phases' blocks to round-trip; if P1 left it scalar-only, this is a P1 gap to flag, not re-fix here. (c) CRLF edit churn — preserve existing line endings in `DeckGeometry.swift` (memory `ops-ios-crlf-edit-churn`).

---

### Task 1b — Engine result envelope (`EngineEnvelope.swift`) — P2 DEFINES it

**Why here:** `FramingMember.sizing: MemberSizingResult?` (Task 1) is the **first consumer** of the shared engine envelope, so P2 owns and defines it (contract §3 "Phase ownership" note). P3+ engines reuse these types verbatim and fill `sizing`; they must NOT re-declare them. P2 writes `sizing = nil` everywhere — the TYPES exist from P2, the VALUES arrive in P3.

**Interface (verbatim from contract §3 / §3.1 — adopt exactly, do not rename):**
```swift
public struct EngineCitation: Codable, Equatable {
    public var limitingCheck: String      // e.g. "deflection L/360"
    public var codeSection: String        // e.g. "IRC R507.6", "AWC DCA6 Table 4"
    public var packageEdition: String     // e.g. "IRC 2021 / DCA6-12"
}
public enum EngineOutcome<T: Codable & Equatable>: Codable, Equatable {
    case ok(value: T, citation: EngineCitation, assumptions: EngineAssumptions)
    case outOfEnvelope(reason: String, citation: EngineCitation)   // hard stop -> PE
}
public struct EngineAssumptions: Codable, Equatable {
    public var liveLoadPSF: Double; public var deadLoadPSF: Double; public var snowLoadPSF: Double?
    public var species: WoodSpecies; public var grade: LumberGrade
    public var soilBearingPSF: Double?; public var packageEdition: String
}
public struct SizedMember: Codable, Equatable {
    public var size: LumberSize; public var plyCount: Int
    public var allowableSpanFeet: Double; public var actualSpanFeet: Double; public var utilization: Double
}
public struct MemberSizingResult: Codable, Equatable {
    public var outcome: EngineOutcome<SizedMember>   // .outOfEnvelope -> PE hard stop
}
```

**Implementation notes:**
- Lives in `DeckKit/Sources/DeckKit/Engine/EngineEnvelope.swift`. Consumes `WoodSpecies`/`LumberGrade`/`LumberSize` from `FramingPlan.swift` (Task 1).
- The generic enum `EngineOutcome<T>` needs an **explicit `CodingKeys`/`init(from:)`/`encode(to:)`** with a case discriminator — Swift's synthesized `Codable` for a generic enum with associated values is fragile; pin the discriminator so `.outOfEnvelope` never silently mis-decodes.
- P2 ships these types ONLY so `FramingMember.sizing` compiles and round-trips as `nil`. No P2 engine constructs a non-nil `MemberSizingResult` — that is P3's `StructuralSizingEngine.sizeAll`.

**TEST STRATEGY** (`EngineEnvelopeCodableTests.swift`, runs on sim):
- `test_engineOutcome_ok_roundTrips`: an `.ok(value: SizedMember, citation:, assumptions:)` encodes→decodes stable; discriminator key present in JSON.
- `test_engineOutcome_outOfEnvelope_roundTrips`: `.outOfEnvelope(reason:citation:)` round-trips reason + citation.
- `test_memberSizingResult_nil_inFramingMember_roundTrips`: a `FramingMember` with `sizing == nil` round-trips (the P2 LIGHT no-claim path); a `FramingMember` with a hand-built `MemberSizingResult` round-trips equal (proves the type is wired into the schema).

**References:** contract §3 (Phase ownership note), §3.1, §0.4 (result + limiting check + cited section + edition).

**Risks:** Generic-enum `Codable` discriminator (above) — get it right here, before P3 builds engines on top. Covered by the two round-trip tests.

---

### Task 2 — Schema version bump + backfill stamping

**Depends on:** Task 1; `DeckDesign.version` (contract §0.3 makes it *live*); whatever P1 migration/backfill hook exists (P1 introduces `schemaVersion` mirror inside the blob, contract §2.2 row 1).

**Interface:**
```swift
// In DeckDrawingData (additive, P1 baseline already adds schemaVersion):
//   var schemaVersion: Int? = nil   // mirror of DeckDesign.version inside the blob
// P2 helper (DeckKit-internal, pure):
enum DeckSchemaMigration {
    /// Stamp the design as schema-version 2 once a framing block is present.
    /// Idempotent; never downgrades. Pure: returns a new value.
    static func stampFramingVersion(_ data: DeckDrawingData) -> DeckDrawingData
}
```

**Implementation notes:**
- `version` is the **schema** version (monotonic, P2 = 2), gates migration/backfill, NEVER rendering (contract §0.3). Rendering gates on capability flags only.
- When `framing != nil` and `schemaVersion < 2`, stamp `schemaVersion = 2`, `generatedAtSchemaVersion` on the plan, and bump `DeckDesign.version`. Do not touch designs without a framing block.

**TEST STRATEGY** (in `FramingPlanCodableTests.swift`):
- `test_stamp_setsSchemaVersion2_whenFramingPresent`: framing present, `schemaVersion == nil` → after stamp, `== 2`.
- `test_stamp_isIdempotent_neverDowngrades`: `schemaVersion == 7` (a future design) opened by P2 → stamp leaves it `7` (never downgrade — §0.3 monotonic). Critical: a v7 design must open + round-trip in this build.
- `test_stamp_noOp_whenNoFraming`: no framing → `schemaVersion` unchanged.

**References:** contract §0.3, §2.2, §8.1. Memory: the "version is a dead field" note (`deck-sync-stale-overwrite-revert`) — P2 is precisely where it becomes live; do NOT use it for inbound recency (that's `updatedAt`/`needsSync`, already handled in `applyServerSnapshot`).

**Risks:** Conflating schema `version` with the inbound stale-overwrite guard (`updatedAt`/`needsSync`) would reintroduce the LUPIN data-loss class — keep them orthogonal.

---

### Task 3 — `FramingGeometry` pure helpers

**Depends on:** Task 1 (member types). Consumes existing `DeckDrawingData.orderedPositions`, `detectedSurfaces` (`SurfaceDetector`), `effectiveScaleFactor`, `EdgeType.houseEdge`, `PolygonMath` (area/bbox/signed-area), `DimensionEngine.postCount` (`ComponentEmitter.swift:135`).

**Interface (P2-owned, pure `enum` namespace):**
```swift
enum FramingGeometry {
    /// Infer joist run direction for a surface: joists run PERPENDICULAR to the
    /// ledger/house edge when one exists, else perpendicular to the longest edge.
    /// Returns a unit vector in canvas space + the beam-line axis (parallel to ledger).
    static func joistAxis(forSurface positions: [CGPoint], edges: [DeckEdge],
                          houseEdge: DeckEdge?, scaleFactor: Double) -> (joist: CGVector, beam: CGVector)
    /// Lay out joist centerlines across a surface at `spacingInchesOC`, clipped to the polygon.
    static func joistLines(surface positions: [CGPoint], axis: CGVector,
                           spacingInchesOC: Double, scaleFactor: Double) -> [(start: CGPoint, end: CGPoint)]
    /// Place beam line(s) parallel to the ledger at the back-span position (and at
    /// the free edge for freestanding). Returns canvas-space segments.
    static func beamLines(surface positions: [CGPoint], joistAxis: CGVector,
                          houseEdge: DeckEdge?, scaleFactor: Double) -> [(start: CGPoint, end: CGPoint)]
    /// Post drop points along a beam line at <= maxSpacingInches o.c.
    static func postPoints(alongBeam start: CGPoint, end: CGPoint,
                           maxSpacingInches: Double, scaleFactor: Double) -> [CGPoint]
    /// Perimeter segments classified as rim (non-house, non-beam) vs ledger (house edge).
    static func rimAndLedgerSegments(surface positions: [CGPoint], edges: [DeckEdge])
        -> (rim: [(CGPoint, CGPoint)], ledger: [(CGPoint, CGPoint)])
    /// Mid-span blocking rows when joist span exceeds the cap (default 8' — DCA6).
    static func blockingRows(joistSpanInches: Double, surface positions: [CGPoint],
                            joistAxis: CGVector, capInches: Double, scaleFactor: Double) -> [(CGPoint, CGPoint)]
}
```

**Implementation notes:**
- Pure functions; canvas coordinates throughout (members store canvas-space `start`/`end`, contract §2.4). Convert to inches via `scaleFactor` only for spacing/cap thresholds.
- Joist-direction heuristic: prefer perpendicular to a `houseEdge`; else perpendicular to the longest perimeter edge (matches how a framer lays joists across the short span off the ledger).
- The 8′ blocking cap is a *geometry default* with NO code claim (contract row "Rim/band joist, blocking & bridging | BOTH | DCA6 (8′ cap w/o blocking)"). It is a plausible-frame heuristic, not an engineered limit.

**TEST STRATEGY** (`FramingGeometryTests.swift`, table-driven):
- `test_joistAxis_perpendicularToHouseEdge`: 12′×10′ rectangle, house edge on top (matches `DeckTemplateEngine.generateRectangle` houseEdgeIndices `[0]`) → joist axis perpendicular to top edge (assert dot-product with house-edge direction ≈ 0, tol 1e-6).
- `test_joistLines_count_matchesSpacing`: 12′-wide surface, 16″ o.c. → expect `floor(144/16)+1 = 10` joist lines (assert count + endpoints lie on the polygon, within tol).
- `test_postPoints_spacing`: 12′ beam, 72″ max o.c. → `ceil(144/72)+1 = 3` posts (mirror `DimensionEngine.postCount` semantics so beam-post + railing-post logic agree).
- `test_blockingRows_belowCap_returnsEmpty`: 7′ span, 8′ cap → no blocking. `test_blockingRows_aboveCap_addsRow`: 12′ span → ≥1 blocking row near mid-span.
- `test_rimAndLedger_classification`: rectangle w/ one house edge → 3 rim segments + 1 ledger segment.
- **Date-brittleness N/A** (no temporal math) but anchor all geometry off computed dimensions, never magic canvas pixels — derive expected counts from inputs (the AutoSchedule lesson applied to geometry).

**References:** contract §2.4 (canvas-space members), §5.1 (units). Existing math: `PolygonMath.swift`, `DimensionEngine.postCount`, `SurfaceDetector.detect`.

**Risks:** Concave/L-shape/T-shape surfaces (the `DeckTemplateEngine` shapes) — joist lines must clip to the actual polygon, not the bounding box. Self-intersecting polygons are already guarded by `PolygonMath.isSelfIntersecting` (used in `ComponentEmitter`/`totalRealWorldArea`); reuse it to skip degenerate faces.

---

### Task 4 — `AutoFramingEngine` (derive + auto-then-preserve)

**Depends on:** Tasks 1, 3. Consumes `DeckDrawingData` (vertices/edges/surfaces/levels), `DeckDrawingData.renderElevationFeetSingleLevel` / `renderElevationFeet(for:levelIndex:)` (`DeckGeometry.swift:1057,1086`), `SurfaceDetector`, `DeckTemplateEngine.copyDrawingData` id-remap precedent (`DeckTemplateEngine.swift:476`).

**Interface (P2-owned, pure — mirrors `DeckTemplateEngine.generate` shape):**
```swift
enum AutoFramingEngine {
    /// Derive a plausible FramingPlan from geometry + a load preset. Members carry
    /// nominalSize/species/grade hints for VISUALIZATION ONLY; `sizing` stays nil
    /// (no code claim — P2). generationSource = .auto.
    static func generate(from data: DeckDrawingData, preset: LoadPreset) -> FramingPlan

    /// Re-derive after a geometry change WITHOUT clobbering manual edits.
    /// Locked members (locked == true) and any member in a level the user touched
    /// are carried through verbatim; the rest are regenerated. Sets
    /// generationSource = .autoThenEdited when any member survived from `existing`.
    static func regenerate(from data: DeckDrawingData, existing: FramingPlan, preset: LoadPreset) -> FramingPlan
}
```

**Implementation notes:**
- **Per-level.** Single-level → one `FramingMemberSet(levelId: "")`; multi-level → one set per `DeckLevel.id`, deriving each level's surface(s) independently (mirror `ComponentEmitter.emitLevel`, `ComponentEmitter.swift:67`).
- **Derivation order per surface:** ledger (house edge) → rim band (other perimeter) → beam line(s) (`FramingGeometry.beamLines`) → posts (`postPoints`) → joists (`joistLines` at preset-implied default spacing, 16″ o.c.) → blocking (`blockingRows`). `cantilever` members are NOT auto-emitted in P2 (introduced as a role for P3).
- **Default sizes are *plausible*, not engineered:** joists `2x8`, beams doubled `2x10` (`plyCount = 2`), posts `6x6`, ledger `2x10`, rim `2x8`. `nominalSize` set for render scale; `sizing` stays `nil`. Stamp `species`/`grade` from the preset. (Contract §2.4: "LIGHT auto-derives a *plausible* frame … no code claim.")
- **Auto-then-preserve** (`regenerate`): for each level, keep every `existing` member with `locked == true`; for unlocked members, regenerate from geometry. If any member was kept, set `generationSource = .autoThenEdited`. Preserve member `id`s where a regenerated member maps 1:1 to an existing one (stable id by role+endpoint proximity), mirroring `DeckTemplateEngine.copyDrawingData`'s id-stability intent so 3D node identity + selection survive re-derive.

**TEST STRATEGY** (`AutoFramingEngineTests.swift`, table-driven; build the inputs via `DeckTemplateEngine.generate(template:dimensions:)` so geometry is real, not hand-stubbed):
- `test_generate_rectangle_memberCounts`: 12′×10′ rectangle w/ house edge, 16″ o.c. → assert 1 ledger, 3 rim segments, ≥1 beam, ≥2 posts, ~8 joists (`floor(120/16)+1` across the 10′ span), `generationSource == .auto`, every `member.sizing == nil`.
- `test_generate_freestanding_twoBeams`: freestanding rectangle (no house edge) → 2 beam lines (front + back), no ledger member.
- `test_generate_multiLevel_perLevelSets`: `DeckTemplateEngine.multiLevel` input → `members.count == 2` member sets keyed by the two `DeckLevel.id`s; neither set empty.
- `test_regenerate_preservesLockedMember`: generate, lock one beam (`locked = true`, change its `nominalSize` to `4x6`), nudge a vertex, `regenerate` → the locked beam survives verbatim (`4x6`, same id), unlocked members re-derived, `generationSource == .autoThenEdited`.
- `test_regenerate_allUnlocked_isPureAuto`: nothing locked → behaves like `generate` (`.auto`-equivalent member set), no stale members.
- `test_generate_lShape_clipsToPolygon`: L-shape → no joist line crosses the notch (every endpoint inside-or-on the polygon via `PolygonMath`).
- `test_generate_neverSetsSizing`: across all fixtures, assert `flatMap members → allSatisfy { $0.sizing == nil }` (the LIGHT no-claim invariant).

**References:** contract §2.4, §3.6 (`DeckTemplateEngine` auto-then-preserve precedent), roadmap §2.1 ("Auto-framing engine … mirrors `DeckTemplateEngine` auto-then-preserve"). Memory `deckbuilder-test-decks-need-edges` — `fromJSON` prunes orphan vertices, so build VM/engine test decks through `DeckTemplateEngine` or with fully-edged polygons, never edgeless vertices.

**Risks:** (a) Re-derive flicker — if `regenerate` reassigns ids on every call, 3D node identity churns and selection breaks; the id-stability mapping is load-bearing. (b) Multi-level: top-level `vertices`/`edges` are EMPTY in multi-level mode (`DeckGeometry.swift:1129-1148`) — derive from `levels`, exactly as `ComponentEmitter` does, or every multi-level frame comes out empty.

---

### Task 5 — `GroundCover` model (Terrain P2 subset)

**Depends on:** Task 1 pattern. Consumes existing `ElevationSource` enum (`DeckGeometry.swift:155`), `CGPoint` Codable.

**Interface (verbatim from contract §2.5 — P2 ships `groundCover` only; `gradePoints`/`slopeSource` are P4, declared but unused):**
```swift
public struct TerrainModel: Codable, Equatable {
    public var gradePoints: [GradePoint]        // P4 — empty in P2
    public var groundCover: [GroundZone]        // P2 — the only populated field
    public var slopeSource: ElevationSource     // P4 — defaults .manual in P2
}
public struct GroundZone: Codable, Equatable, Identifiable {
    public let id: String; public var polygon: [CGPoint]; public var cover: GroundCover
}
public enum GroundCover: String, Codable, CaseIterable { case grass, dirt, gravel, rock, concrete, pavers }
public struct GradePoint: Codable, Equatable { public var position: CGPoint; public var dropFeet: Double }  // P4, here for forward-decode
```

**Implementation notes:**
- Add `var terrain: TerrainModel? = nil` to `DeckDrawingData` (Task 1 already adds it alongside `framing`). P2 only ever writes `terrain.groundCover`; leaves `gradePoints` empty and `slopeSource = .manual`.
- Declaring the *full* `TerrainModel` shape now (not a P2-only subset struct) means P4 fills `gradePoints` without a schema rename — additive within the same block (contract §8.1). Defensive `init(from:)` defaults `gradePoints` to `[]`, `slopeSource` to `.manual`.
- A single default `GroundZone` (cover `.grass`) covering the deck's bounding region is the implicit start state; explicit zones are user-painted polygons (Phase 2 ground-type selection).

**TEST STRATEGY** (in `FramingPlanCodableTests.swift` or a sibling):
- `test_terrain_groundCover_roundTrips`: 2 zones (grass + gravel) → encode/decode stable + Equatable.
- `test_terrain_legacy_decodesNilThenDefaults`: pre-P2 JSON → `terrain == nil`; a JSON with `groundCover` only → `gradePoints == []`, `slopeSource == .manual` (forward-compat for P4).
- `test_groundCover_allCases_decodable`: every `GroundCover` raw value round-trips (CaseIterable guard against accidental rename — additive-only, §5.1).

**References:** contract §2.5, §4 (`.groundCover` capability, in `.light`), roadmap §2.5 ("Per-zone ground-type selection | BOTH"). Note §2.5 keeps `groundCover` and `gradePoints` in ONE `TerrainModel` block — P2 introduces the block, P4 completes it (same pattern as `PermitMeta` P1→P7).

**Risks:** Tempting to make a P2-only `GroundCoverPlan` struct — DON'T; that forces a rename when P4 adds grade. Use the full contract `TerrainModel` from day one.

---

### Task 6 — `ComponentEmitter` + `FramingTakeoff` rough BOM

**Depends on:** Tasks 1, 3, 4. Consumes `ComponentEmitter.emit` (`ComponentEmitter.swift:31`), `AnyCodable`, `DesignComponentRow` (additive `component_type` only — renaming is a contract break, `ComponentEmitter.swift:317-322`), `EstimateGeneratorService.GeneratedLineItem` (`EstimateGeneratorService.swift:8`), the P1 `WasteSettings` block + the waste-threaded area takeoff path.

**Interface (P2-owned):**
```swift
enum FramingTakeoff {
    struct LumberRow: Equatable { let role: FramingRole; let nominalSize: LumberSize; let plyCount: Int
                                  let totalLinearFeet: Double; let pieceCount: Int }
    struct HardwareRow: Equatable { let kind: String; let count: Int }   // joist hangers, post bases (rough, visual)
    struct Takeoff: Equatable { let lumber: [LumberRow]; let hardware: [HardwareRow]; let footingCount: Int }
    /// Pure rough takeoff from a FramingPlan. Waste applied to lumber linear-footage
    /// via WasteSettings (default 10%). NO sizing claim — uses each member's
    /// plausible nominalSize as-authored.
    static func takeoff(_ framing: FramingPlan, waste: WasteSettings, scaleFactor: Double) -> Takeoff
}
// ComponentEmitter additive rows (new component_type strings — never rename existing):
//   "joist", "beam", "post", "rim_joist", "blocking"
```

**Implementation notes:**
- **Additive only.** New `component_type` strings: `joist`, `beam`, `post`, `rim_joist`, `blocking`. Metadata keys: `linear_feet`, `nominal_size`, `ply_count`, `count`, `species`, `grade`, `level_id`, `member_id`. Existing `railing`/`deck_board`/`stair_set`/`gate`/`post_set` rows untouched — `post_set` (rail posts) is DISTINCT from the new `post` (structural support posts); do not merge.
- `FramingTakeoff` converts member canvas lengths → feet via `scaleFactor`, sums per (role, size, ply), applies the global waste %; emits a plausible hardware count (1 hanger per joist end on a ledger/rim, 1 post base per post). **Rough** — no connector model, no uplift hardware (that's P4).
- `EstimateGeneratorService`: add a "Framing" category fed by `FramingTakeoff`, threaded through the SAME waste path P1 introduced (do not re-implement waste). Members with no `nominalSize` (shouldn't happen post-auto, but defensive) are skipped, not priced at $0.

**TEST STRATEGY** (`FramingTakeoffTests.swift`):
- `test_takeoff_sumsLinearFeet_perSizeRole`: a plan of 8 joists (12′ each `2x8`) + 1 doubled-ply beam → one `LumberRow{joist,2x8,ply1,96 lf×waste,8}`, one `LumberRow{beam,2x10,ply2,...}`; assert `totalLinearFeet == 96 * 1.10` (default 10% waste) and `pieceCount == 8`.
- `test_takeoff_appliesPerPattern-agnostic_globalWaste`: framing uses `WasteSettings.defaultWastePercent` only (per-pattern waste is decking, not framing) — assert global % applied, per-pattern map ignored.
- `test_takeoff_footingCount_matchesPosts`: 3 posts → `footingCount == 3`.
- `test_takeoff_skips_unsizedMember`: inject a member with `nominalSize == nil` → not in any row; total unchanged.
- `test_emitter_addsFramingRows_additively`: `ComponentEmitter.emit` on a framed design → contains `joist`/`beam`/`post`/`rim_joist` rows AND still contains the legacy `deck_board`/`railing` rows (assert both sets present; no existing `component_type` renamed).
- `test_emitter_noFraming_unchanged`: design with `framing == nil` → emitter output byte-identical to pre-P2 (regression guard for LIGHT designs and the catalog adapter).

**References:** contract §2.4, §3.6 (`ComponentEmitter` additive, `EstimateGeneratorService` waste thread), roadmap §2.1 ("Framing takeoff/BOM | BOTH | `ComponentEmitter`"). Memory `ios-outbound-field-allowlist-drift` — the `components` projection is local-only (recomputed on `toJSON`), so no outbound-column allowlist concern here; but the bible's component-type vocabulary must list the new rows so `DesignToEstimateAdapter` (web) tolerates them.

**Risks:** (a) `DesignToEstimateAdapter` on ops-web may reject unknown `component_type` — confirm it ignores-unknown (graceful) before shipping; flag to web if it hard-fails. (b) Double-counting posts: structural `post` rows vs rail `post_set` rows must stay separate categories in the estimate so the BOM doesn't inflate.

---

### Task 7 — `FramingSceneBuilder` + layer toggles (real 3D frame)

**Depends on:** Tasks 1, 3, 4. Consumes `DeckSceneBuilder` (`DeckSceneBuilder.swift`), `DeckMeshGenerator.createBox`/`boundingRect` (`DeckMeshGenerator.swift`), `inchesToMeters`, the existing material factory, `DeckCapabilities.plausibleFrame`.

**Interface (P2-owned):**
```swift
enum FramingSceneBuilder {
    /// Build a parent SCNNode with child layer-group nodes (named for toggling):
    /// "layer.joists", "layer.beams", "layer.posts", "layer.rim", "layer.blocking".
    /// Member box dimensions come from nominalSize (visual scale), positioned in
    /// meters under the deck surface at the resolved elevation.
    static func buildFramingNode(framing: FramingPlan, levelId: String,
                                 elevationMeters: Float, scaleFactor: Double) -> SCNNode
}
struct FramingLayer: OptionSet {
    let rawValue: Int
    static let decking = FramingLayer(rawValue: 1 << 0)
    static let joists   = FramingLayer(rawValue: 1 << 1)
    static let beams    = FramingLayer(rawValue: 1 << 2)
    static let posts    = FramingLayer(rawValue: 1 << 3)
    static let footings = FramingLayer(rawValue: 1 << 4)
    static let rim      = FramingLayer(rawValue: 1 << 5)
    static let all: FramingLayer = [.decking, .joists, .beams, .posts, .footings, .rim]
}
enum FramingLayerToggle {
    /// Show/hide named layer groups under a scene root per the visible set.
    static func apply(_ visible: FramingLayer, to root: SCNNode)
}
```

**Implementation notes:**
- **Replace** the decorative substructure: `DeckSceneBuilder.buildSupportPosts` (`DeckSceneBuilder.swift:467-524`) hardcodes 6×6 posts on an 11″×5″ footing box dropped at perimeter corners; the rim is hardcoded 9.25″ (`buildRimJoist`). When `framing != nil` AND `.plausibleFrame` is active, `buildDeckLevel` (`DeckSceneBuilder.swift:342`) delegates substructure to `FramingSceneBuilder.buildFramingNode`. When absent (no framing block, or a build without the flag), keep the legacy decorative fallback so old designs still render (degrade-safe).
- Member box sizes from `nominalSize` (e.g. `2x8` → 1.5″×7.25″ actual), oriented along the member's canvas vector projected into the XZ plane, seated under the deck surface at `elevationMeters` minus member depth. Posts run from beam underside to grade. Reuse `DeckMeshGenerator.createBox` + the existing wood materials.
- **Layer grouping** (Chief Architect pattern, roadmap §6 "3D complexity on mobile"): each member type goes into a named child group so `FramingLayerToggle.apply` flips `.isHidden`. Use **instanced/cloned geometry** for the joist array (one `SCNGeometry`, N nodes) to keep node count sane on 3-year-old phones (roadmap §6).
- Decking surface + footings are existing nodes from `DeckSceneBuilder`; the toggle hides/shows them too (decking layer wraps the existing `deckSurface` node; footings keep the existing footing node but Phase 2 leaves footing GEOMETRY as-is — real footing geometry is P4).

**TEST STRATEGY** (`FramingSnapshotTests.swift`, `ImageRenderer → XCTAttachment` harness — memory `ops-ios-swiftui-snapshot-harness`):
- `test_buildFramingNode_layerGroupsPresent`: build from an auto-framed 12′×10′ deck → assert child nodes named `layer.joists`/`layer.beams`/`layer.posts`/`layer.rim` exist and each has ≥1 child (structural assertion, no rendering).
- `test_joistCount_matchesPlan`: node count under `layer.joists` == joist member count.
- `test_layerToggle_hidesGroup`: `apply([.decking, .posts], to: root)` → `layer.joists.isHidden == true`, `layer.posts.isHidden == false`.
- `test_snapshot_framedDeck_attachesImage`: render the scene to an image via the harness, attach for human visual QA (3D fidelity is a human step — contract §5.2; the test asserts non-empty image + node-count sanity, not pixels).
- `test_noFraming_usesLegacyFallback`: design with `framing == nil` → scene still builds (legacy `buildSupportPosts` path), no crash, ≥1 `supportPost` node.

**References:** contract §3.6 (`DeckMeshGenerator` carry-forward), §4 (capability-gated rendering), §5.2 (snapshot harness, human visual QA), roadmap §2.1 ("Framing-layer 3D render | BOTH | `DeckMeshGenerator`") + §6 (layer toggles / instancing / LOD). Existing code: `DeckSceneBuilder.swift:342-524`.

**Risks:** (a) Node-count blowup — a real frame is ~10× the props (roadmap §6); instancing the joist array + lazy layer building is mandatory, verify frame rate isn't tanked (human QA on a 3-year-old device). (b) Coordinate mismatch — members are canvas-space; the scene is meters in the XZ plane. Reuse `DeckSceneBuilder`'s existing `convertToMeters`/`vertexPositionsInMetersById` mapping so the frame lines up with the surface exactly. (c) Multi-level: build one framing node per level at each level's resolved elevation (`renderElevationFeet(for:levelIndex:)`).

---

### Task 8 — `GroundTextureFactory` + textured ground render

**Depends on:** Task 5. Consumes `DeckSceneBuilder` ground node (`DeckSceneBuilder.swift:215-222`, the flat `groundColor` 30%-alpha plane), `DeckMeshGenerator.boundingRect`.

**Interface (P2-owned):**
```swift
enum GroundTextureFactory {
    /// SceneKit material for a ground cover. Uses bundled tiled textures
    /// (diffuse + optional normal) for grass/gravel/rock/pavers; flat tinted
    /// material for dirt/concrete. Tiling scaled to the deck span.
    static func material(for cover: GroundCover, spanMeters: Float) -> SCNMaterial
}
```

**Implementation notes:**
- Replace the single flat `groundColor` plane with a ground node textured per the design's `terrain.groundCover` (gated by `.groundCover`, in `.light`). When `terrain == nil` (legacy/no selection), default to a grass material (cosmetic upgrade over the old flat tint, no behavior break).
- Phase 2 renders ONE cover for the whole ground plane derived from the dominant `GroundZone` (per-zone polygon clipping of the ground texture is a polish follow-up; the *data* supports zones now). Bundle a small set of tiled, color-correct textures in the package resources (OPSStyle earth-tone palette; no decorative excess).
- Texture tiling scaled so blades/stones read at a believable real-world size against `spanMeters` (the existing `deckSpanM` calc, `DeckSceneBuilder.swift:222`).

**TEST STRATEGY** (in `FramingSnapshotTests.swift`):
- `test_groundMaterial_perCover_distinct`: assert `material(for: .grass)` vs `.gravel` differ (different diffuse contents) — guards the mapping table.
- `test_groundMaterial_concrete_isFlatTint`: concrete/dirt → solid color material (no image), confirming the flat-vs-textured split.
- `test_snapshot_groundCover_attaches`: render a deck over gravel → attach image for human QA + assert the ground node has the gravel material.
- `test_noTerrain_defaultsGrass`: `terrain == nil` → ground node uses the grass material, scene builds.

**References:** contract §2.5, §4 (`.groundCover`), roadmap §2.5 ("Textured 3D ground render | BOTH | `DeckMeshGenerator`"). Existing flat-ground code: `DeckSceneBuilder.swift:215-222`. CLAUDE.md: OPSStyle earth-tone semantics; no hardcoded colors outside the texture assets.

**Risks:** Bundled texture assets bloat the package — keep them small/tiled; this is cosmetic, not load-bearing. Package-resource bundling differs from the app target's asset catalog — verify `Bundle.module` resource access works in DeckKit (SPM resource declaration in `Package.swift`).

---

### Task 9 — VM wiring + `FramingControlsView` UI

**Depends on:** Tasks 1–8. Consumes `DeckBuilderViewModel` (relocated), `DeckStore.saveDeck` (P1 seam), `CapabilityProvider`/`DeckCapabilities` (P1), `OPSStyle` (OPSDesignKit).

**Interface (P2-owned, additive to the VM):**
```swift
// DeckBuilderViewModel additions:
func generateFraming()                          // AutoFramingEngine.generate → save
func regenerateFramingPreservingEdits()         // AutoFramingEngine.regenerate → save
func setLoadPreset(_ preset: LoadPreset)         // restamp + (optionally) re-derive
func setGroundCover(_ cover: GroundCover, forZoneId: String?)  // paint a zone / set default
@Published var framingLayerVisibility: FramingLayer  // drives the 3D toggle bar
var canFrame: Bool { capabilities.contains(.plausibleFrame) }
var canPickGround: Bool { capabilities.contains(.groundCover) }
```

**Implementation notes:**
- **Capability-gated surfaces, hidden not disabled** (contract §4): the framing controls + layer-toggle bar + ground picker render only when the flag is present. Both `.plausibleFrame`/`.groundCover` are in `.light`, so OPS and OPS Decks both show them — but the gate is written correctly so a future flagless build hides cleanly.
- All writes go through `drawingData` setter → `DeckStore.saveDeck` (which sets `needsSync`); never touch `ModelContext`/`SyncEngine` directly (contract §1.3).
- Auto-derive trigger: offer an explicit "Generate frame" action (not silent-on-every-edit, to avoid clobbering manual work mid-draw); after a generate, subsequent geometry edits prompt `regenerateFramingPreservingEdits` (auto-then-preserve). Copy via `ops-copywriter` skill (terse, tactical: e.g. `GENERATE FRAMING`, layer labels `JOISTS`/`BEAMS`/`POSTS`).
- Numbers in UI: JetBrains Mono, tabular, formatted (e.g. spacing `16" O.C.`), per CLAUDE.md.

**TEST STRATEGY:** UI is human visual QA (interactive, needs Jackson — contract §5.2, memory `ios-design-system-conformance-pass`). VM logic gets unit coverage where pure:
- `test_generateFraming_setsBlock_andMarksSync`: call `generateFraming()` on a VM with a closed rectangle → `drawingData.framing != nil`, `DeckStore.saveDeck` invoked (spy), `needsSync` set.
- `test_setLoadPreset_restamps_existingMembers`: change preset species → existing members' `species` updated, `sizing` still nil.
- `test_canFrame_falseWithoutCapability`: VM built with a `.materials`-only capability set → `canFrame == false`, `generateFraming()` is a no-op (defense even though `.light` includes it).
- Build verification: device-target `xcodebuild build` green; `build-for-testing` + `test` green on sim.

**References:** contract §4 (capability gating, hidden surfaces), §1.3 (`DeckStore`), §5.1 (numbers/UI). CLAUDE.md skills: `ops-copywriter` (all labels), `ops-design`/`mobile-ux-design` (controls layout — touch targets ≥44pt, field-first), `animation-studio:ios-animations` (layer-toggle transition; single OPS easing curve, honor reduced motion).

**Risks:** Over-prominence — a once-per-design "generate frame" must not own permanent prime canvas space (CLAUDE.md design-judgment: prominence proportional to frequency). Place it behind a framing-mode entry, with the layer toggle bar appearing only in the 3D framing view. Get the layout in front of Jackson before polishing.

---

### Task 10 — Bible update

**Depends on:** Tasks 1–9 landed + build-green.

**Change:** Update the relevant `ops-software-bible/` deck section to document: the `framing` block (full sub-type table), the `terrain.groundCover` block, the auto-framing auto-then-preserve contract, the new `component_type` rows (`joist`/`beam`/`post`/`rim_joist`/`blocking`) + their metadata keys, and the schema-version-2 bump. Note the LIGHT/FULL split (both render the plausible frame; sizing is P3-only). Per CLAUDE.md, the bible must stay current in the same session.

**TEST STRATEGY:** N/A (docs). Cross-check the documented `component_type` vocabulary against `ComponentEmitter` output + flag to the ops-web `DesignToEstimateAdapter` owner.

**References:** CLAUDE.md "Keep the bible updated"; `ops-software-bible/07_SPECIALIZED_FEATURES.md` / the deck section.

---

## Cross-phase invariants checklist (every task obeys)

- [ ] New schema = ONE-block-region additive (`framing` + `terrain`), `decodeIfPresent` + defaults, `version` → 2. No rename/removal of any shipped field, enum case, or `component_type` (contract §8.1).
- [ ] Unknown/failed sub-block decodes to nil + preserved on re-encode; round-trip + light-preserve + malformed tests present (contract §8.2, §0.2, §1.4).
- [ ] Engines pure, offline, no I/O (`AutoFramingEngine`, `FramingGeometry`, `FramingTakeoff`, `GroundTextureFactory.material`) — contract §8.3. (No `EngineOutcome` in P2 — no sizing claim; `sizing` stays nil.)
- [ ] NO code rule / `CodePackage` consumption — P2 makes zero engineering assertions (roadmap §1, contract §7 P2 row "none (no claim)").
- [ ] DeckKit reaches host only via primitives + P1 seams + `CapabilityProvider`. No `Project`/`Company`/`AppState`/`SyncEngine`/`DataController` (contract §8.5).
- [ ] Capability gates surfaces + render, never data presence; `.plausibleFrame`/`.groundCover` in `.light` (contract §8.6).
- [ ] Build: device `generic/platform=iOS`; tests on iPhone 17 / OS 26.5 sim; grep for `SUCCEEDED`; styling via OPSStyle (contract §8.8).

## Verification gate (before "done")

1. `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → `BUILD SUCCEEDED`.
2. `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing` → `BUILD SUCCEEDED`.
3. `xcodebuild ... test` → all new test files green; round-trip/auto-then-preserve/no-sizing/emitter-additive assertions pass.
4. Snapshot attachments extracted + eyeballed (framed deck, each layer toggle, ground covers).
5. Human visual QA with Jackson: framing controls layout, 3D fidelity on a 3-year-old device, ground textures, reduced-motion toggle behavior.
6. Bible updated; ops-web `DesignToEstimateAdapter` confirmed tolerant of the new `component_type` rows.

## Assumptions other phases must honor

- **`MemberSizingResult` + envelope ownership.** P2 **OWNS and DEFINES** the engine envelope — `EngineOutcome<T>`, `EngineCitation`, `EngineAssumptions`, `SizedMember`, and `MemberSizingResult` (contract §3 "Phase ownership" note) — because P2 is their first consumer via `FramingMember.sizing: MemberSizingResult?`. P2 declares `FramingMember.sizing: MemberSizingResult?` (contract §2.4 requires the property now) and sets it to `nil` everywhere; the TYPES live in `EngineEnvelope.swift` (Task 1b). P3 reuses them verbatim and fills `sizing` — **P3 must NOT re-declare or rename them.** The P3-specific result structs (`JoistSpanResult`/`BeamSizingResult`/`PostSizingResult`/`CantileverResult`/`PostReaction`) are P3's.
- **`TerrainModel` is introduced whole in P2** (contract §2.5 shape), with only `groundCover` populated. P4 fills `gradePoints`/`slopeSource` additively inside the SAME block — no rename, no new top-level key.
- **`component_type` vocabulary grows by `joist`/`beam`/`post`/`rim_joist`/`blocking`.** Later phases (P4 footings, P6 fasteners/patterns) add MORE rows additively; none rename these. Structural `post` is distinct from rail `post_set`.
- **`FramingMember` is reused verbatim by P6 overhead structures** (`OverheadStructure.framing: [FramingMember]`, contract §2.7) — keep the type free of deck-only assumptions.
- **`generationSource`/`locked` auto-then-preserve semantics are the contract** every later re-derive (P3 sizing writes `sizing` into existing members; P4 footings key off post members) must respect: never clobber `locked` members; never strip `sizing` once P3 fills it.
- **Schema `version` is now live and monotonic** (P2 = 2). It gates migration only, never rendering. The inbound stale-overwrite guard remains `updatedAt`/`needsSync` (orthogonal — do not couple).
