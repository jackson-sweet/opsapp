# OPS Decks — Phase 4 Implementation Plan: Footings, Terrain & Connections (FULL)

**Date:** 2026-06-24
**Status:** Phase plan — conforms verbatim to `docs/superpowers/plans/2026-06-24-ops-decks-architecture-contract.md`
**Companions (read first):**
- Architecture contract (LOCKED): `docs/superpowers/plans/2026-06-24-ops-decks-architecture-contract.md`
- Feature roadmap: `docs/superpowers/specs/2026-06-24-ops-decks-feature-roadmap.md` (§2.2 Footings, §2.5 Site/terrain, §4 engines #5/#7, §5 Phase 4, §7 liability)
- Phase 1 foundation spec: `docs/superpowers/specs/2026-06-24-ops-decks-standalone-app-design.md`

> **HEADER NOTE — bite-sized TDD steps with literal code are finalized at phase start once predecessors exist.** This phase builds on `DeckKit` (P1), `FramingPlan` + auto-framing (P2), and `StructuralSizingEngine` + `CodePackage`/`CodePackageLoader` + per-post `tributaryLoads` (P3) — none of which exist in the tree yet. The contract pins the public types and signatures this phase consumes and emits; everything below adopts those verbatim. Where the contract makes a signature concrete, the TEST STRATEGY shows literal assertions. Where a predecessor's *internal* shape is not yet pinned (e.g. the exact rows inside `CodePackage.footingTable`, the canvas-space units P2 chose for `FramingMember.start/end`), the plan flags the dependency and the literal test bodies + fixture cells are finalized in the first TDD step of the phase, against the real predecessor code. Do **not** fabricate predecessor signatures beyond the contract.

---

## Goal

Make every footing, post height, and house attachment in an OPS Decks design **engineered, code-cited, and offline-verifiable** — and capture the one piece of field reality that unlocks all of it: **yard grade**. Concretely, by end of phase a FULL user can:

1. Capture yard grade/slope (the keystone) via AR height + manual sample points, producing a `TerrainModel`.
2. See **post heights computed from grade** per support point, with the **30″ guard-required threshold auto-flagged** (IRC R312.1.1).
3. Pick a footing type per support, enter sizing fields (diameter/depth/helical torque), and place interior/beam-line piers manually.
4. Run the **auto-footing sizing engine**: per-post tributary reaction (from P3) + soil bearing + frost depth → required footing diameter/depth, with the limiting check and cited code section, or a hard-stop to "requires a licensed engineer."
5. Get **post-to-footing/uplift hardware** and a **ledger + lateral-load connection design** with Simpson hardware selection (IRC R507.9.2 hold-downs), with the brick/stone → freestanding fallback.
6. Get a **full lumber + hardware + concrete BOM** (footings as real concrete volume / bag count, not count-at-$0), and a **drainage / grade-fall check** (IRC R401.3).

**The compliance line (contract §6) is absolute here:** terrain capture and footing *placement* are BOTH-tier-feasible data, but every *sizing number, frost depth, soil bearing assertion, connection rating, and code citation* is FULL-only and obeys §6 verbatim — objective-negative only, disclaimer-gated, jurisdiction-driven, out-of-envelope → PE hard stop, assumptions surfaced, frost/soil "verify with your AHJ."

## Architecture

- **One new additive top-level property; one P2-owned block completed in place.** Per contract §2.5, this phase adds exactly `var footings: FootingPlan? = nil` to `DeckDrawingData` (`decodeIfPresent` + default-nil, wired into `CodingKeys` + the defensive `init(from:)`) and bumps `DeckDesign.version` to **4** (P3 = 3). The `terrain: TerrainModel?` property is **already introduced in P2** (schema ver 2, populating `groundCover`); P4 does NOT re-add the property — it **fills** `terrain.gradePoints`/`terrain.slopeSource` additively inside the P2-owned struct. Nothing in the blob is renamed or removed (contract §8.1).
- **Two pure engines, contract signatures verbatim.** `FootingEngine` (contract §3.2) sizes footings from reaction + soil + frost + type and computes concrete takeoff. A new **`TerrainEngine`** (this phase introduces it; not in the contract's named engine catalog but permitted under §3 as a pure `enum` namespace in `DeckKit/Sources/DeckKit/Engine/`) derives post heights from grade, the 30″ guard flag, and the drainage/grade-fall check. A new **`ConnectionEngine`** designs ledger + lateral connections and selects Simpson hardware. All return the shared `EngineOutcome<T>` / `EngineCitation` / `EngineAssumptions` envelope (contract §3) and consume a loaded `CodePackage` — never hard-coded table cells (contract §0.5, §8.4).
- **Capabilities gate surfaces + engine invocation, never data.** `.footingEngine` and `.terrainGrade` (contract §4) gate the footing-sizing and terrain-grade surfaces and the engine calls. LIGHT may render terrain ground-cover and footing *placement* it understands and **round-trips the FULL `footings`/`terrain` blocks untouched** via the P1 `unknownBlocks` passthrough (contract §1.4) — LIGHT physically cannot emit a footing dimension or frost depth.
- **Reuses P3 load output.** `FootingEngine.sizeAll(_:reactions:package:)` consumes `[PostReaction]` from `StructuralSizingEngine.tributaryLoads(...)` (P3, contract §3.1). This phase does not recompute loads — it sizes the foundation under them.
- **The AR height pipeline is the capture substrate.** Grade capture reuses the existing `ARHeightViewModel` two-point (deck-surface → ground) flow and `ElevationSource.ar`, extended to drop multiple grade samples into `TerrainModel.gradePoints` rather than one elevation onto a vertex.
- **3D replaces the fake box.** Today `DeckSceneBuilder.buildSupportPosts` hardcodes an 11″×5″ `SCNBox` footing and a 6×6 post (`DeckSceneBuilder.swift:478-521`). FULL renders real footing geometry (cylinder for sonotube/pad, helix-stub for helical pile) and posts sized/seated from the engine result + terrain grade. This is capability-gated; LIGHT keeps the prop box.

## Tech Stack

- **Swift package:** `DeckKit` (engines in `Engine/` + `Compliance/`, models in `Models/`, seam-backed UI in `Views/`), depending on `OPSDesignKit` for `OPSStyle` tokens. No app coupling (contract §1, §8.5) — terrain/footings touch the host only through `companyId`/`projectId` primitives + the `DeckStore`/`CodePackageLoader`/`CapabilityProvider` seams.
- **Code rules as data:** `CodePackage.footingTable` (P3-introduced struct), `presumptiveSoilPSF`, `envelopeLimits`, plus **two new package sub-tables this phase adds to the `CodePackage` schema** (see Task 0): a frost-depth dataset and a connection-hardware table. Packages are Supabase-stored, ops-web-delivered, offline-cached (contract §3.4, §6.4); engines receive a loaded value.
- **AR:** ARKit / RealityKit via existing `AR/*` (`ARHeightViewModel`, `ARCoordinateConverter`, `AccuracyModel`).
- **3D:** SceneKit via existing `Scene3D/*` (`DeckSceneBuilder`, `DeckMeshGenerator`).
- **Testing:** XCTest, table-driven, on the simulator destination `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` (`build-for-testing` to verify compile, `test` to run); device-build verification `-destination 'generic/platform=iOS'`. Code-package test fixtures are checked-in JSON with a known subset of real table cells (contract §5.2). Grep build logs for `BUILD SUCCEEDED` / `TEST SUCCEEDED` (memory `xcodebuild-exit-code-masking`). Copy `Secrets.xcconfig` into any worktree first.

---

## File Structure

### New files — schema (`DeckKit/Sources/DeckKit/Models/`)
| File | Responsibility |
|---|---|
| `FootingPlan.swift` | `FootingPlan`, `Footing`, `SoilInput`, `FrostInput`, `SoilSource`, `FrostSource`, `PostFootingConnection`, `FootingSizingResult`, `ConcreteTakeoff` — contract §2.5/§3.2 verbatim, each with defensive `init(from:)`. |
| `ConnectionPlan.swift` | `LedgerConnectionResult`, `LateralConnectionResult`, `SimpsonHardware`, `ConnectionTakeoffRow` — connection-design result types (this phase; see Task 6 interface). |

### New files — engines (`DeckKit/Sources/DeckKit/Engine/` and `/Compliance/`)
| File | Responsibility |
|---|---|
| `Engine/FootingEngine.swift` | Pure `enum FootingEngine` — `sizeFooting`, `concreteTakeoff`, `sizeAll` (contract §3.2 verbatim). |
| `Engine/TerrainEngine.swift` | Pure `enum TerrainEngine` — post-height-above-grade, 30″ guard auto-flag, drainage/grade-fall check, grade interpolation. |
| `Compliance/ConnectionEngine.swift` | Pure `enum ConnectionEngine` — ledger attachment + lateral-load connection design + Simpson hardware selection; brick/stone → freestanding fallback. |
| `Engine/FoundationBOM.swift` | Pure `enum FoundationBOM` — emits lumber/hardware/concrete BOM rows (joins `FootingPlan` + `ConnectionPlan` + framing posts), feeding `ComponentEmitter` + `EstimateGeneratorService` as additive component types. |

### New files — code-package sub-tables (`DeckKit/Sources/DeckKit/Compliance/`)
| File | Responsibility |
|---|---|
| `CodePackage+Footings.swift` | `FrostDepthTable`, `FrostDepthRow`, `ConnectionHardwareTable`, `ConnectionRule` — extends the P3 `CodePackage` additively with the frost dataset + connection-hardware rules (Task 0). |

### New files — UI (`DeckKit/Sources/DeckKit/Views/`)
| File | Responsibility |
|---|---|
| `Views/TerrainCaptureView.swift` | Grade-sample capture surface (AR + manual taps), gated by `.terrainGrade`; writes `TerrainModel`. |
| `Views/FootingInspectorSheet.swift` | Per-footing type/sizing fields + manual interior/beam-line pier placement, gated by `.footingEngine`; shows engine result + citation + assumptions + disclaimer. |
| `Views/ConnectionDetailSheet.swift` | Ledger + lateral connection design surface; Simpson hardware callout; freestanding-fallback notice. |
| `Views/FoundationBOMSection.swift` | Lumber/hardware/concrete BOM section in the estimate/takeoff surface. |

### Modified files
| File | Change |
|---|---|
| `DeckKit/Sources/DeckKit/Models/DeckGeometry.swift` (`DeckDrawingData`) | Add ONLY `var footings: FootingPlan? = nil` (extend `CodingKeys` + `init(from:)` with `decodeIfPresent`). The `var terrain: TerrainModel? = nil` property is **already present from P2** — do NOT re-add it. |
| `DeckKit/Sources/DeckKit/Models/TerrainModel.swift` (P2-owned) | **Modify, do not create.** P2 introduced the whole `TerrainModel { gradePoints, groundCover, slopeSource }` struct (populating only `groundCover`). P4 FILLS `gradePoints` + `slopeSource` (terrain capture writes them); no field is renamed, no new top-level key — additive within the same P2-owned block (contract §2.5). |
| `DeckKit/Sources/DeckKit/Models/DeckGeometry.swift` (`FootingType`) | Additively extend the 3-case enum if the package's footing-type catalog needs more cases (`deckBlock`, `pier`) — **append only**, never rename `helical_pile`/`sono_tube`/`concrete_pad` (contract §8.1). |
| `DeckKit/Sources/DeckKit/DataModels/DeckDesign.swift` | Bump default `version` semantics to 4 on first save of a terrain/footing-bearing design (migration gate, contract §0.3). |
| `DeckKit/Sources/DeckKit/Compliance/CodePackage.swift` (P3) | Add `frostTable: FrostDepthTable`, `connectionTable: ConnectionHardwareTable` properties (additive; Task 0). |
| `DeckKit/Sources/DeckKit/Engine/ComponentEmitter.swift` | Add additive `component_type` rows: `footing`, `post_to_footing`, `ledger`, `lateral_connector`, `concrete` (never rename existing — contract §3.6, §8.1). Extend `AnyCodable` already done in P1 for nested values. |
| `DeckKit/Sources/DeckKit/Engine/EstimateGeneratorService.swift` | Thread `FoundationBOM` rows into takeoff categories (lumber/hardware/concrete). |
| `DeckKit/Sources/DeckKit/Scene3D/DeckSceneBuilder.swift` | Behind `.footingEngine`: replace the hardcoded `buildSupportPosts` 11″×5″ box + 6×6 post with engine-sized footing geometry + grade-seated posts; LIGHT keeps the prop. |
| `DeckKit/Sources/DeckKit/Capability/DeckCapabilities.swift` (P1) | No new flags (`.footingEngine`, `.terrainGrade` already defined in contract §4) — wire the new surfaces to them. |
| `DeckKit/Sources/DeckKit/AR/ARHeightViewModel.swift` | Extend to accumulate multiple grade samples into a terrain-capture callback (additive; existing single-elevation flow untouched). |

### New test files (`DeckKitTests/`)
| File | Responsibility |
|---|---|
| `FootingEngineTests.swift` | Table-driven sizing + concrete takeoff + out-of-envelope, against a checked-in `CodePackage` fixture. |
| `TerrainEngineTests.swift` | Post-height-above-grade, 30″ guard flag, grade-fall/drainage check, grade interpolation. |
| `ConnectionEngineTests.swift` | Ledger/lateral selection, brick/stone freestanding fallback, Simpson hardware lookup, disclaimer. |
| `FoundationBOMTests.swift` | Concrete volume → bag count, hardware counts, lumber post counts. |
| `Phase4SchemaRoundTripTests.swift` | The 3 mandatory round-trip tests (contract §5.2) for `footings`/`terrain`. |
| `Fixtures/CodePackage-IRC2021-test.json` | Known subset of IRC 2021 / DCA6 footing + frost + connection cells with hand-computed expected values. |
| `Fixtures/CodePackage-BCBC2024-test.json` | Metric (kPa) subset for unit-conversion-at-boundary tests. |

---

## Tasks

> Dependency legend: **[C]** = type/signature from the contract; **[P1]/[P2]/[P3]** = consumed from an earlier phase; **[E]** = existing code in the tree today.

### Task 0 — Extend `CodePackage` with frost + connection sub-tables (foundation for all sizing here)

**Why first:** every sizing/connection number in this phase is table-driven (contract §0.5, §8.4). P3 introduces `CodePackage` with `footingTable: FootingTable`, `presumptiveSoilPSF`, `envelopeLimits`. This phase needs two more data tables that P3 did not add. They are **additive properties** on `CodePackage` (a `Codable` value type), so adding them does not break P3's loader or fixtures.

**Interface (this phase adds to `CodePackage`, alongside the P3 `footingTable`):**
```swift
// DeckKit/Sources/DeckKit/Compliance/CodePackage+Footings.swift
public struct FrostDepthTable: Codable, Equatable, Sendable {
    public var rows: [FrostDepthRow]            // keyed by region/zip-prefix/zone id
    public func depthInches(forRegionId id: String) -> FrostDepthRow?
}
public struct FrostDepthRow: Codable, Equatable, Sendable {
    public var regionId: String                 // AHJ region key (zip-prefix / climate zone / province)
    public var frostDepthInches: Double
    public var note: String                     // ALWAYS surfaced as "verify with your AHJ" (§6.3)
}
public struct ConnectionHardwareTable: Codable, Equatable, Sendable {
    public var rules: [ConnectionRule]
    public func rule(for role: ConnectionRole, demandLb: Double) -> ConnectionRule?
}
public struct ConnectionRule: Codable, Equatable, Sendable {
    public var role: ConnectionRole             // .ledgerLateral | .postToFooting | .postToBeam
    public var hardwareModel: String            // catalog model string (e.g. "DTT2Z", "ABU66")
    public var ratedLoadLb: Double
    public var codeSection: String              // "IRC R507.9.2", "IRC R507.4"
    public var upliftRated: Bool
}
public enum ConnectionRole: String, Codable, Sendable, CaseIterable {
    case ledgerLateral, postToFooting, postToBeam
}
```
Plus on `CodePackage`: `public var frostTable: FrostDepthTable`, `public var connectionTable: ConnectionHardwareTable` (additive Codable properties; defensive `decodeIfPresent` with empty-table defaults so a P3-vintage package still decodes).

**TEST STRATEGY:** in `FootingEngineTests`/`ConnectionEngineTests` fixture-load tests: decode `Fixtures/CodePackage-IRC2021-test.json` and assert `frostTable.depthInches(forRegionId: "MN-north")?.frostDepthInches == 60` (hand-set fixture cell), `connectionTable.rule(for: .ledgerLateral, demandLb: 1500)?.hardwareModel == "DTT2Z"`, and that a **P3-vintage package JSON without `frostTable`/`connectionTable`** decodes to empty tables without throwing (additive backward-decode). Assert `frostTable.rows.first?.note` is non-empty (AHJ caveat must exist in data).

**Dependencies:** `CodePackage` **[P3, C §3.4]**, `EnvelopeLimits` **[P3, C §3.4]**.

**Code/standard references:** IRC R403.1.4 (frost-depth footing requirement), IRC R507.9.2 (lateral connection / hold-downs), IRC R507.4 (post-to-footing). Frost is AHJ-delegated — the bundled table is a convenience, always "verify with your AHJ" (contract §6.3).

**Risks:** (a) P3's `CodePackage` internal property layout is not pinned by the contract beyond §3.4's commented sketch — finalize the exact additive insertion at phase start against P3's real file. (b) Frost-region keying (zip-prefix vs climate-zone) is a data-modeling choice; keep `regionId` a free string so the dataset shape can evolve without a code change. (c) The connection-hardware model strings must stay catalog-neutral data, not hard-coded (contract §0.5).

---

### Task 1 — Schema: new `FootingPlan` block + fill the P2-owned `TerrainModel` grade fields (additive, backward-decodable)

> **Ownership:** `FootingPlan` is the NEW P4 block (new top-level property on `DeckDrawingData`). `TerrainModel` is **P2-owned** — P2 introduced the whole struct + the `terrain` property; P4 does NOT re-add the property or re-declare the struct. P4 only FILLS `terrain.gradePoints` + `terrain.slopeSource` (which P2 declared but left empty/`.manual`). The `TerrainModel` shape below is restated as a consumed reference, not a new declaration.

**Interface (contract §2.5 verbatim — adopt exactly):**
```swift
// DeckKit/Sources/DeckKit/Models/FootingPlan.swift
public struct FootingPlan: Codable, Equatable {
    public var footings: [Footing]
    public var soil: SoilInput?
    public var frost: FrostInput?
}
public struct Footing: Codable, Equatable, Identifiable {
    public let id: String
    public var vertexId: String?                 // anchors to a perimeter vertex OR nil = free pier
    public var position: CGPoint
    public var type: FootingType                 // existing enum — extend additively if needed
    public var diameterInches: Double?
    public var depthInches: Double?
    public var helicalTorqueFtLb: Double?
    public var connection: PostFootingConnection?
    public var sizing: FootingSizingResult?      // FILLED BY FootingEngine; nil = not yet sized
}
public struct SoilInput: Codable, Equatable {
    public var bearingCapacityPSF: Double = 1500 // IRC R401.4 presumptive; BCBC kPa
    public var source: SoilSource
}
public struct FrostInput: Codable, Equatable {
    public var depthInches: Double?
    public var source: FrostSource
}
public enum SoilSource: String, Codable { case presumptive, geotechReport }
public enum FrostSource: String, Codable { case bundledTable, userEntered, ahjVerified }
public struct PostFootingConnection: Codable, Equatable {
    public var hardwareModel: String?; public var upliftRated: Bool
}

// DeckKit/Sources/DeckKit/Models/TerrainModel.swift — P2-OWNED (consumed reference; do NOT re-declare).
// P2 shipped this whole struct + the `terrain` property, populating only `groundCover`.
// P4 fills `gradePoints` + `slopeSource` inside it (additive — no rename, no new key).
public struct TerrainModel: Codable, Equatable {
    public var gradePoints: [GradePoint]         // P2 left this empty; P4 FILLS it
    public var groundCover: [GroundZone]         // P2-populated
    public var slopeSource: ElevationSource      // P2 defaulted .manual; P4 sets .ar/.manual from capture
}
public struct GradePoint: Codable, Equatable { public var position: CGPoint; public var dropFeet: Double }
public struct GroundZone: Codable, Equatable, Identifiable {
    public let id: String; public var polygon: [CGPoint]; public var cover: GroundCover
}
public enum GroundCover: String, Codable, CaseIterable { case grass, dirt, gravel, rock, concrete, pavers }
```
`FootingSizingResult` / `ConcreteTakeoff` are declared with `FootingEngine` (Task 4, contract §3.2). The NEW `FootingPlan` struct + sub-types each get a **defensive `init(from:)`** with `decodeIfPresent` + defaults, exactly matching the existing `DeckVertex`/`DeckEdge`/`RailingConfig` pattern (`DeckGeometry.swift:144`, `:239`, `:363`). `CGPoint`/`[CGPoint]` already round-trip in this blob (`DeckVertex.position`, `GroundZone.polygon` mirror `DeckSurface`/footprint usage).

**Wire into `DeckDrawingData`** (`DeckGeometry.swift:696`): add ONLY `var footings: FootingPlan? = nil`, add it to `CodingKeys`, add it as `decodeIfPresent` in `init(from:)`. The `terrain` property is already wired by P2 — do NOT re-add it. Bump `DeckDesign.version` migration target to 4.

**Note on `FootingType`:** the existing enum (`DeckGeometry.swift`) is 3-case (`helical_pile`, `sono_tube`, `concrete_pad`). The roadmap §2.2 footing catalog wants pier/deck-block too. If the package's footing-type catalog requires them, **append** `case pier` / `case deckBlock` (raw `"pier"`/`"deck_block"`) — never rename a shipped case (contract §8.1).

**TEST STRATEGY (`Phase4SchemaRoundTripTests` — contract §5.2 mandatory three):**
1. **Stable round-trip:** build a `DeckDrawingData` with a populated `footings` (2 footings, one perimeter `vertexId`, one free pier `vertexId == nil`, soil presumptive, frost bundledTable) and a `terrain` (3 grade points, 2 ground zones). `let json = data.toJSON(); let back = DeckDrawingData.fromJSON(json)!; let json2 = back.toJSON()` — assert `back.footings == data.footings`, `back.terrain == data.terrain`, and `json == json2` (idempotent).
2. **LIGHT preserves FULL blocks:** decode the FULL JSON above with a `.light` capability build path (simulate by decoding into `DeckDrawingData` and re-encoding — the model itself declares the properties, so the real LIGHT guarantee is exercised at the rendering/engine layer; the round-trip here asserts the `unknownBlocks` passthrough is unnecessary *because the properties are declared*, AND that a hypothetical pre-P4 build's passthrough would carry them). Concretely: take a JSON string that ALSO contains a fabricated unknown top-level key `"futureBlockXYZ": {...}`; decode→encode; assert `futureBlockXYZ` survives in the output (proves the P1 `unknownBlocks` passthrough still protects P4-unknown blocks).
3. **Malformed sub-block → nil, whole decode survives:** corrupt the `footings` JSON (e.g. `"footings": {"footings": "not-an-array"}`) and assert `DeckDrawingData.fromJSON` still returns a non-nil design with `vertices`/`edges` intact and `footings == nil` (graceful per-field degradation, contract §0.2). Use `decodeIfPresent` semantics — verify the whole-design decode does not throw.

Plus: assert `FootingType` round-trips all cases including any appended ones; assert default-nil when JSON omits the keys (legacy P1–P3 design loads with `footings == nil`).

**Dependencies:** `DeckDrawingData` **[E + P1 `unknownBlocks` passthrough, C §1.4]**, `ElevationSource` **[E]**, `FootingType` **[E]**, `CGPoint` Codable **[E]**.

**Code/standard references:** contract §2.5, §0.2, §1.4, §8.1, §8.2. Existing defensive-decode precedent `DeckGeometry.swift:144/239/363`.

**Risks:** (a) `CGPoint` Codable already works in this blob, but `[CGPoint]` arrays in `GroundZone.polygon` must be verified to round-trip (they do via synthesized `Codable`; the round-trip test catches any regression). (b) `Footing.position` in canvas coordinates must share the same space as `DeckVertex.position` (contract comment on `FramingMember.start`) — finalize the unit/space against P2's choice at phase start. (c) `version` bump must not retro-flag every legacy design as needing migration — gate the bump on first FULL save that actually writes a `footings`/`terrain` block.

---

### Task 2 — `TerrainEngine`: grade capture math, post-height-above-grade, 30″ guard auto-flag

**Why:** grade is the keystone (roadmap §2.5, §5 Phase 4 "grade capture first"). Post height = deck datum − interpolated grade at the support point; the 30″ rule (IRC R312.1.1) auto-flags any deck surface > 30″ above grade as guard-required.

**Interface (this phase introduces — pure `enum`, returns the shared envelope where it makes a *compliance* claim, plain results where it's pure geometry):**
```swift
// DeckKit/Sources/DeckKit/Engine/TerrainEngine.swift
public enum TerrainEngine {
    /// Interpolate ground drop (feet, below deck datum) at an arbitrary canvas point
    /// from the captured grade samples (nearest-sample / inverse-distance weighting).
    public static func gradeDrop(at point: CGPoint, terrain: TerrainModel) -> Double

    /// Post height (inches) at a support point = deck elevation (inches) minus
    /// interpolated grade drop. Pure geometry — no code claim.
    public static func postHeightInches(
        at point: CGPoint, deckElevationInches: Double, terrain: TerrainModel
    ) -> Double

    /// 30" guard-required auto-flag (IRC R312.1.1). Returns a finding-shaped
    /// result carrying the threshold + cited section + the measured height.
    public static func guardRequirement(
        deckElevationInches: Double, terrain: TerrainModel, package: CodePackage
    ) -> EngineOutcome<GuardRequirement>

    /// Drainage / grade-fall check (IRC R401.3): 6" fall in first 10', 2% on
    /// impervious. Objective-negative only.
    public static func gradeFallCheck(
        terrain: TerrainModel, package: CodePackage
    ) -> EngineOutcome<GradeFallResult>
}
public struct GuardRequirement: Codable, Equatable {
    public var guardRequired: Bool          // true when maxHeightAboveGradeInches > thresholdInches
    public var maxHeightAboveGradeInches: Double
    public var thresholdInches: Double      // from CodePackage.guardRules (30")
}
public struct GradeFallResult: Codable, Equatable {
    public var fallInchesPer10Ft: Double
    public var meetsMinimum: Bool
}
```

**TEST STRATEGY (`TerrainEngineTests`, table-driven, anchored on computed values — memory `ios-autoschedule-tests-date-brittleness`):**
- **gradeDrop interpolation:** terrain with grade points at known canvas coords + drops (e.g. (0,0)→0 ft, (100,0)→2 ft); assert `gradeDrop(at: (50,0))` ≈ 1 ft within tolerance; assert exact-sample points return their own drop.
- **postHeight:** `postHeightInches(at: (100,0), deckElevationInches: 36, terrain:)` with 2 ft drop → `36 + 24 == 60`″. Assert a point on a downhill corner is taller than one on the high side.
- **30″ guard flag:** with `package.guardRules.guardThresholdInches == 30` (fixture cell), a deck whose max height above grade is 29″ → `guardRequired == false`; 31″ → `guardRequired == true`, `.codeSection == "IRC R312.1.1"`. Assert the `EngineOutcome.ok` carries `EngineAssumptions` and the citation.
- **gradeFall:** terrain with 6″ fall over first 10′ → `meetsMinimum == true` (IRC R401.3); 2″ fall → `false`. Assert objective-negative: the result is a boolean + measured value, never the string "safe".
- **Empty/degenerate terrain:** no grade points → `gradeDrop` returns 0 (flat assumption), `guardRequirement` uses `deckElevationInches` directly. Assert no crash.

**Dependencies:** `TerrainModel` **[Task 1]**, `CodePackage.guardRules` (`GuardRules` — 30″ trigger) **[P3, C §3.4]**, `EngineOutcome`/`EngineCitation`/`EngineAssumptions` **[P3, C §3]**.

**Code/standard references:** IRC R312.1.1 (30″ guard trigger), R401.3 (drainage/grade-fall 6″-in-10′, 2% impervious). The 30″ value comes from `CodePackage.guardRules`, not a literal (contract §0.5).

**Risks:** (a) Interpolation method (nearest vs IDW vs triangulated) affects accuracy on irregular yards — pick IDW for v1, document it as an assumption surfaced in the UI; survey/contour TIN import is explicitly EXCLUDED (roadmap §8). (b) `GuardRules` field names from P3 are not pinned beyond "36" guard, 30" trigger, 4" opening" — finalize accessor names at phase start. (c) Grade samples are `dropFeet` but post heights are inches (contract §5.1 units) — convert at the engine boundary; a unit test must pin ×12.

---

### Task 3 — Terrain capture UI: AR grade sampling + manual ground zones (`.terrainGrade`)

**Interface:** `TerrainCaptureView` (SwiftUI, in `DeckKit/Views/`), gated by `.terrainGrade`. Reuses `ARHeightViewModel` extended to accumulate multiple deck-surface→ground samples (each → a `GradePoint` with `dropFeet` from the AR Y-delta and `accuracyPercent`), plus a manual tap mode to place grade samples and draw `GroundZone` polygons with a `GroundCover` picker. Writes `DeckDrawingData.terrain`; persists via the `DeckStore` seam.

`ARHeightViewModel` extension (additive — existing single-elevation `placePoint2` flow untouched):
```swift
extension ARHeightViewModel {
    /// Capture-and-continue: record the current deck→ground delta as a terrain
    /// grade sample (canvas position supplied by the host mapping AR→canvas),
    /// then reset to capture the next, instead of finalizing one elevation.
    func captureGradeSample(at canvasPoint: CGPoint, onSample: (GradePoint) -> Void)
}
```

**TEST STRATEGY:** AR/SwiftUI interaction is human visual QA (contract §5.2 — interactive QA stays a human step). Automated coverage:
- **Snapshot harness** (memory `ops-ios-swiftui-snapshot-harness`, `ImageRenderer → XCTAttachment`): render `TerrainCaptureView` with a seeded `TerrainModel` (grade points + 2 ground zones) and attach for visual review; assert it renders without throwing.
- **VM unit test:** drive `captureGradeSample` with two synthetic AR deltas at two canvas points; assert two `GradePoint`s with correct `dropFeet` (Y-delta × 39.3701 / 12) and that `accuracyPercent` is carried through; assert `slopeSource == .ar` when AR-captured, `.manual` when tapped.
- **Capability gate:** assert the surface is hidden when `.terrainGrade` is absent (the view's presence is decided by `CapabilityProvider`), and that a `.light` build opening a terrain-bearing design still round-trips `terrain` (covered by Task 1 test 2).

**Dependencies:** `ARHeightViewModel`/`ARCoordinateConverter`/`AccuracyModel` **[E]**, `TerrainModel`/`GradePoint`/`GroundZone`/`GroundCover` **[Task 1]**, `DeckStore` **[P1, C §1.3]**, `CapabilityProvider` + `.terrainGrade` **[P1, C §4]**, `OPSStyle` tokens via `OPSDesignKit` **[P1]**.

**Code/standard references:** existing AR two-point flow `ARHeightViewModel.swift:67` (`placePoint2`), `:72` (`calculateElevation`). Ground-cover render is roadmap §2.5 BOTH-tier (cosmetic, no grade math) — but the grade *capture* itself is FULL.

**Risks:** (a) Mapping an AR-space ground point back to a 2D canvas coordinate needs a host-supplied transform (the existing flow only produces one scalar height) — flag as a design decision; v1 may let the user tap the canvas to place each sample's location and use AR only for the height delta. (b) Haptics are mandatory (CLAUDE.md): medium impact on each captured sample, success notification on finalize. (c) Outdoor contrast / 44pt targets (mobile MOBILE.md) for field use.

---

### Task 4 — `FootingEngine`: auto-footing sizing + concrete takeoff (`.footingEngine`)

**Interface (contract §3.2 verbatim):**
```swift
// DeckKit/Sources/DeckKit/Engine/FootingEngine.swift
public enum FootingEngine {
    public static func sizeFooting(
        reactionLb: Double, soil: SoilInput, frost: FrostInput,
        type: FootingType, package: CodePackage
    ) -> EngineOutcome<FootingSizingResult>

    public static func concreteTakeoff(_ result: FootingSizingResult) -> ConcreteTakeoff

    public static func sizeAll(
        _ plan: FootingPlan, reactions: [PostReaction], package: CodePackage
    ) -> FootingPlan
}
public struct FootingSizingResult: Codable, Equatable {
    public var diameterInches: Double; public var depthInches: Double
    public var bearingAreaSqIn: Double; public var requiredFrostDepthInches: Double
    public var citation: EngineCitation
}
public struct ConcreteTakeoff: Codable, Equatable { public var cubicFeet: Double; public var bagCount: Int; public var bagSizeLb: Int }
```
`sizeFooting` computes required bearing area = reaction / soil bearing, looks the result up in `package.footingTable` for the footing type, sets `requiredFrostDepthInches` from `frost.depthInches` (or `package.frostTable` when `frost.source == .bundledTable`), and returns `.outOfEnvelope` when reaction/area exceeds `package.envelopeLimits` or soil < `envelopeLimits.minSoilPSF` (1500 psf / 75 kPa) — emitting **no number** (contract §6.5). Every `.ok` carries `EngineAssumptions` (load, species, soil, edition). `sizeAll` writes `FootingSizingResult` back per footing by matching `PostReaction.footingOrPostId` to `Footing.id` (locked/manual footings with a user-entered size are respected — mirror `FramingMember.locked` semantics).

**TEST STRATEGY (`FootingEngineTests`, table-driven against `Fixtures/CodePackage-IRC2021-test.json`):**
- **sizeFooting nominal (imperial):** reaction 4000 lb, soil 1500 psf presumptive → required bearing area = 4000/1500 = 2.667 sqft = 384 sqin; assert the result's `bearingAreaSqIn >= 384`, `diameterInches`/`depthInches` match the hand-set fixture row for `sono_tube`, `citation.codeSection == "IRC R507.3.1"`, `citation.packageEdition == "IRC 2021 / DCA6-12"`. Assert `EngineAssumptions.soilBearingPSF == 1500`.
- **Frost:** `frost.source == .bundledTable` with `package.frostTable` region 60″ → `requiredFrostDepthInches == 60`; `frost.source == .userEntered, depthInches: 48` → 48.
- **Out-of-envelope (soil):** soil 1000 psf (< `minSoilPSF` 1500) → `.outOfEnvelope(reason:, citation:)`; assert NO `FootingSizingResult` is produced (pattern-match the enum; the UI shows "requires a licensed engineer"). Same for reaction exceeding `envelopeLimits` max.
- **Metric boundary:** load `Fixtures/CodePackage-BCBC2024-test.json` (`unitSystem == .metric`), soil 75 kPa, assert the engine converts at the boundary and the result's units/citation read BCBC 9.12.2.2 (contract §5.1 metric-at-boundary).
- **concreteTakeoff:** a 12″-dia × 48″-deep sonotube → cylinder volume π r² h = π(0.5 ft)²(4 ft) ≈ 3.14 ft³; assert `cubicFeet` within tolerance and `bagCount == ceil(cubicFeet / yieldPerBag)` for the fixture `bagSizeLb` (e.g. 0.6 ft³ per 80 lb bag → 6 bags). Assert helical pile → `cubicFeet == 0` (no concrete), only torque.
- **sizeAll:** a `FootingPlan` of 3 footings + matching `[PostReaction]` → all three get `sizing != nil` matched by id; a footing with no matching reaction stays `sizing == nil`; a `.outOfEnvelope` footing carries the hard-stop, not a fabricated size.

**Dependencies:** `FootingPlan`/`Footing`/`SoilInput`/`FrostInput`/`FootingType` **[Task 1]**, `PostReaction` **[P3, C §3.1]**, `CodePackage.footingTable`/`presumptiveSoilPSF`/`envelopeLimits` **[P3, C §3.4]** + `frostTable` **[Task 0]**, `EngineOutcome`/`EngineCitation`/`EngineAssumptions` **[P3, C §3]**.

**Code/standard references:** IRC R401.4 (1500 psf presumptive), R403.1.4 (frost depth), R507.3.1 (footing sizing), DCA6 Table 4, NBC/BCBC 9.12.2.2 (kPa). Contract §6.5 (out-of-envelope hard stop), §6.6 (assumptions).

**Risks:** (a) `CodePackage.footingTable` row shape is sketched but not pinned by the contract — finalize the lookup signature against P3's real `FootingTable` at phase start (the contract forbids inventing a parallel loader, §3.4). (b) Bag yield is package data, not a literal — must live in the package, not the engine. (c) `PostReaction.footingOrPostId` must key to `Footing.id`; confirm the id convention P3 emits matches the footing ids this phase assigns (assumption Task is keyed correctly — see Assumptions).

---

### Task 5 — Footing inspector UI: type catalog, sizing fields, manual pier placement (`.footingEngine`)

**Interface:** `FootingInspectorSheet` (SwiftUI), gated by `.footingEngine`. Per footing: `FootingType` picker (catalog), diameter/depth fields, helical torque field (shown only for `.helicalPile`), soil input (presumptive/geotech), frost input (bundled/user/AHJ). A "place pier" mode appends interior/beam-line `Footing`s with `vertexId == nil` at tapped canvas points (roadmap §2.2 "manual footing placement", precedent `PropertySheetView`). Shows the `FootingEngine` result inline: sized diameter/depth, the `EngineCitation`, the `EngineAssumptions`, and — on `.outOfEnvelope` — the "requires a licensed engineer" hard stop with **no number**. Disclaimer (contract §6.2) acknowledged before sizing runs; sets `PermitMeta.disclaimerAcknowledgedAt`.

**TEST STRATEGY:**
- **Snapshot harness:** render the sheet in three states — unsized, sized (`.ok` with citation + assumptions visible), and `.outOfEnvelope` (PE hard-stop, no number) — attach for visual review; assert each renders.
- **VM unit test:** assert helical-torque field is present iff `type == .helicalPile`; assert placing a pier appends a `Footing` with `vertexId == nil` and the tapped `position`; assert the disclaimer gate blocks the sizing call until acknowledged (the VM must refuse to invoke `FootingEngine` with `disclaimerAcknowledgedAt == nil`).
- **Number formatting:** assert sized values render via JetBrains Mono tabular, formatted (e.g. `12″`, `48″`), empty state `—` (CLAUDE.md, contract §5.1) — assertable on the formatted string the VM exposes.
- **Capability gate:** surface hidden when `.footingEngine` absent.

**Dependencies:** `FootingEngine` **[Task 4]**, `FootingPlan`/`Footing` **[Task 1]**, `PermitMeta.disclaimerAcknowledgedAt` **[P1 minimal / P7, C §2.8]**, `CapabilityProvider` + `.footingEngine` **[P1, C §4]**, `DeckStore` **[P1]**, `OPSStyle` **[P1]**.

**Code/standard references:** roadmap §2.2; precedent `PropertySheetView.swift`. Contract §6.2 disclaimer, §6.5 hard stop, §6.6 assumptions.

**Risks:** (a) The disclaimer-acknowledged gate uses `PermitMeta`, introduced in P1 minimal — confirm `disclaimerAcknowledgedAt` exists in P1's minimal `PermitMeta` or stage it (contract §2.8 says P1-introduced/P7-completed; the gate field may need to land here if P1 only shipped `jurisdictionId`/`codeEdition`). Flag as an Assumption. (b) Touch targets 44pt for field use with gloves.

---

### Task 6 — `ConnectionEngine`: ledger + lateral-load connection design + Simpson hardware (`.footingEngine`)

**Interface (this phase introduces — pure `enum`, in `Compliance/`):**
```swift
// DeckKit/Sources/DeckKit/Compliance/ConnectionEngine.swift
public enum ConnectionEngine {
    /// Ledger attachment design from cladding + tributary demand. Brick/stone →
    /// attachmentAllowed == false → freestanding fallback (no ledger hardware).
    public static func ledgerConnection(
        cladding: HouseEdgeMaterial, tributaryReactionLb: Double, package: CodePackage
    ) -> EngineOutcome<LedgerConnectionResult>

    /// Lateral-load hold-down selection (IRC R507.9.2): count + Simpson model.
    public static func lateralConnection(
        deckAreaSqFt: Double, package: CodePackage
    ) -> EngineOutcome<LateralConnectionResult>

    /// Post-to-footing / uplift hardware selection from reaction + footing type.
    public static func postFootingHardware(
        reactionLb: Double, footingType: FootingType, package: CodePackage
    ) -> EngineOutcome<PostFootingConnection>
}
public struct LedgerConnectionResult: Codable, Equatable {
    public var attachmentAllowed: Bool      // false for brick/stone → freestanding
    public var fastenerSchedule: String?    // e.g. "1/2\" lag @ 16\" o.c."
    public var hardware: SimpsonHardware?
    public var citation: EngineCitation
}
public struct LateralConnectionResult: Codable, Equatable {
    public var holdDownCount: Int           // IRC R507.9.2 (2 min)
    public var hardware: SimpsonHardware
    public var citation: EngineCitation
}
public struct SimpsonHardware: Codable, Equatable {
    public var model: String                // from CodePackage.connectionTable (catalog data)
    public var ratedLoadLb: Double
    public var upliftRated: Bool
}
```

**TEST STRATEGY (`ConnectionEngineTests`, against the package fixture):**
- **Ledger by cladding:** `cladding: .stucco`, demand 2000 lb → `attachmentAllowed == true`, `fastenerSchedule != nil`, `citation.codeSection == "IRC R507.9"`. `cladding: .brick` → `attachmentAllowed == false`, `hardware == nil`, result instructs freestanding fallback (assert via a dedicated field/flag). Same for `.stone`. `.parapet` → freestanding.
- **Lateral hold-downs:** `deckAreaSqFt: 200` → `holdDownCount >= 2` (IRC R507.9.2 minimum), `hardware.model == "DTT2Z"` (fixture), `citation.codeSection == "IRC R507.9.2"`. Assert count scales with area per the rule data.
- **Post-to-footing uplift:** reaction 1500 lb, `.sonoTube` → `upliftRated == true`, `hardware model from connectionTable.rule(for: .postToFooting, ...)`. `.helicalPile` → torque-rated bracket model.
- **Out-of-envelope:** demand exceeding the largest `ConnectionRule.ratedLoadLb` → `.outOfEnvelope` (no fabricated hardware), PE hard stop.
- **Objective-negative + assumptions:** every `.ok` carries `EngineAssumptions` + citation; no result string says "safe".

**Dependencies:** `HouseEdgeMaterial` **[E]**, `FootingType` **[Task 1]**, `PostFootingConnection` **[Task 1]**, `CodePackage.connectionTable`/`ledgerRules` **[Task 0 + P3, C §3.4]**, `EngineOutcome`/`EngineCitation`/`EngineAssumptions` **[P3, C §3]**.

**Code/standard references:** IRC R507.9 (ledger), R507.9.2 (lateral hold-downs, 2 min), R507.4 (post-to-footing). NADRA: ~90% of collapses are ledger failures (roadmap §3) — this is the highest-liability engine; §6 applies in full. Brick/stone → freestanding fallback is roadmap §2.4 + contract §2.6 `LedgerDetail.attachmentAllowed`.

**Risks:** (a) `LedgerDetail` (the *schema* block holding `cladding`/`attachmentAllowed`/`fastenerSchedule`/`lateralConnectors`) is a **P5 `HouseModel` block** (contract §2.6), not P4. P4 computes the connection *design* and surfaces it; persisting it into `LedgerDetail` may need a P4-local holding field or wait for P5. **Resolve at phase start:** either stash the ledger result in the `footings`/connection block this phase owns, or surface compute-only and persist in P5. Flag as an Assumption. (b) Simpson model strings must be package data (contract §0.5), never literals in the engine.

---

### Task 7 — `FoundationBOM`: full lumber + hardware + concrete takeoff (BOTH where it's a count, FULL where it's engineered)

**Interface (this phase introduces — pure `enum`, emits additive `DesignComponentRow`s + estimate categories):**
```swift
// DeckKit/Sources/DeckKit/Engine/FoundationBOM.swift
public enum FoundationBOM {
    /// Concrete rows (cubic feet + bag count per footing), hardware rows
    /// (post-to-footing brackets, ledger fasteners, lateral hold-downs), and
    /// support-post lumber rows — joined from the sized FootingPlan + the
    /// connection results + the framing posts.
    public static func rows(
        footings: FootingPlan, connections: [ConnectionTakeoffRow], framing: FramingPlan?
    ) -> [DesignComponentRow]
}
public struct ConnectionTakeoffRow: Codable, Equatable {
    public var role: ConnectionRole; public var model: String; public var count: Int
}
```
New additive `component_type` strings emitted (contract §3.6 — additive, never rename): `footing`, `concrete`, `post_to_footing`, `ledger`, `lateral_connector`. `EstimateGeneratorService` consumes these as new takeoff categories (lumber/hardware/concrete). This finally fixes the "footings counted at $0" gap (roadmap §2.2).

**TEST STRATEGY (`FoundationBOMTests`):**
- **Concrete rows:** a `FootingPlan` of 4 sized sonotubes (each 3.14 ft³, 6 bags) → one `concrete` row totaling 12.56 ft³ / 24 bags (or per-footing rows summing to that) — assert the `AnyCodable` metadata carries `cubic_feet` and `bag_count` (P1 extended `AnyCodable` to nested values — contract §1.4); helical piles emit zero concrete.
- **Hardware rows:** connection results with 4 post-to-footing brackets + 2 lateral hold-downs → `post_to_footing` count 4, `lateral_connector` count 2, with the Simpson `model` in metadata.
- **Lumber posts:** support-post count from `framing` posts × height → `post` lumber rows (defer to P2's framing post emission where it exists; this phase adds the foundation-side rows only).
- **No double-count:** assert footings already emitted by P2/legacy are not duplicated (reconcile by `Footing.id` / `edge_id`).
- **component_type additivity:** assert none of the existing `railing`/`deck_board`/`stair_set`/`gate`/`post_set` rows are renamed (contract §3.6 break check — snapshot the emitted type set and diff against the pre-P4 baseline).

**Dependencies:** `FootingPlan` + `FootingSizingResult`/`ConcreteTakeoff` **[Task 1/4]**, `ConnectionEngine` results **[Task 6]**, `FramingPlan` **[P2, C §2.4]**, `ComponentEmitter`/`DesignComponentRow`/`AnyCodable` **[E + P1 nested extension]**, `EstimateGeneratorService` **[E]**.

**Code/standard references:** roadmap §2.2 (concrete volume/bag takeoff), §4 #5. Existing `ComponentEmitter.swift:268` footprint-row pattern; `AnyCodable` scalar-only today (`ComponentEmitter.swift:343`) → P1 extends to nested (contract §1.4) — **verify P1 landed the nested-value extension before emitting object metadata here**.

**Risks:** (a) `AnyCodable` is scalar-only in the current tree (`ComponentEmitter.swift:363` "Unsupported AnyCodable scalar type") — the contract says P1 extends it to nested values; if P1 has not, this phase must keep BOM metadata scalar (flatten to `cubic_feet`/`bag_count`/`model` scalars). (b) `EstimateGeneratorService` waste-factor path is P1's `WasteSettings` — concrete/hardware are not area-waste items; ensure they bypass the decking waste multiplier.

---

### Task 8 — Real 3D footing + grade-seated post geometry (`.footingEngine`)

**Interface:** behind `.footingEngine`, replace `DeckSceneBuilder.buildSupportPosts` (`DeckSceneBuilder.swift:466-521`) hardcoded 11″×5″ `SCNBox` footing + 6×6 `SCNBox` post with engine-driven geometry: cylinder (`SCNCylinder`) for `.sonoTube`/`.concretePad` sized from `FootingSizingResult.diameterInches`, a helix-stub for `.helicalPile`, posts sized from the sized footing and **seated on terrain grade** (post bottom Y = interpolated grade, not Y=0). LIGHT keeps the existing prop box (capability-gated branch). Add a footings layer toggle (roadmap §6 Chief-Architect layer pattern).

**TEST STRATEGY:**
- **Snapshot harness** (`ImageRenderer → XCTAttachment`): render a raised deck on a sloped terrain with sized footings; attach for human visual QA (interactive 3D QA stays human — contract §5.2).
- **Geometry unit test (pure helpers):** factor the footing-node geometry choice into a pure function `footingGeometryKind(for: FootingType) -> ...` and assert sonotube → cylinder, helical → helix-stub, pad → cylinder/box; assert post bottom Y equals `TerrainEngine.gradeDrop` at the post's canvas point (no float-in-air, no buried-in-ground).
- **Capability branch:** assert LIGHT path returns the legacy box; FULL path returns engine geometry (assertable on the pure selector, not the SCNNode).

**Dependencies:** `FootingPlan`/`FootingSizingResult` **[Task 1/4]**, `TerrainEngine.gradeDrop` **[Task 2]**, `DeckSceneBuilder`/`DeckMeshGenerator` **[E]**, `CapabilityProvider` + `.footingEngine` **[P1, C §4]**.

**Code/standard references:** existing fake box `DeckSceneBuilder.swift:478` (`footingH = 5.0″`, `footingW = 11.0″`), `:519` `name = "footing"`. Roadmap §2.2 "real 3D footing geometry (cylinder/helix/pad)", §6 mobile 3D mitigation (layer toggles, LOD, instancing) — instance footings on 3-year-old phones.

**Risks:** (a) Real engineered footings = many more SCNNodes than props on old devices in sunlight (roadmap §6) — use instanced geometry + a layer toggle so footings can be hidden. (b) Helical-pile visual is a stylized stub, not a true helix mesh (cost/perf) — acceptable; flag as a render simplification, not an engineering claim.

---

## Cross-cutting compliance conformance (contract §6 — applies to Tasks 2, 4, 5, 6, 8)

- **Objective-negative only:** `gradeFallCheck`, footing sizing, and connection design report measured values + booleans + cited sections; never "safe"/"compliant"/"guaranteed" (assert in each engine test that no result string contains those words).
- **Disclaimer-gated:** Task 5 blocks sizing until `PermitMeta.disclaimerAcknowledgedAt` is set; the disclaimer text is contract §6.2 verbatim.
- **Jurisdiction-driven:** every engine takes a `CodePackage`; the metric BCBC fixture test (Task 4) proves kPa conversion at the boundary.
- **Out-of-envelope hard stops:** Tasks 4 + 6 return `.outOfEnvelope` (no number) below 1500 psf / 75 kPa or above table/envelope limits → "requires a licensed engineer."
- **Assumptions surfaced:** every `.ok` carries `EngineAssumptions` (load, species, soil, edition); Task 5 renders them.
- **Frost/soil are AHJ-delegated:** the bundled `frostTable` is a convenience; `FrostDepthRow.note` and the UI always say "verify with your AHJ."
- **Copy:** all user-facing strings (field labels, the freestanding-fallback notice, the PE hard-stop, the disclaimer) go through the `ops-copywriter` skill before finalizing (CLAUDE.md mandatory skill usage).

---

## Build & verification

- Per phase, after each TDD step: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing` then `test`; device build `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`. Grep logs for `BUILD SUCCEEDED` / `TEST SUCCEEDED` (memory `xcodebuild-exit-code-masking`). Copy `Secrets.xcconfig` into any worktree first (`OPS/CLAUDE.md`).
- New Swift files auto-include via Xcode 16 synchronized groups (memory `ops-ios-xcode16-synchronized-groups`) — no `.pbxproj` edits for the package sources.
- "Cannot find type X" in freshly written files is SourceKit index lag — trust `xcodebuild` (memory `ops-ios-worktree-sourcekit-lag`).
- Update `ops-software-bible/` (deck/`drawing_data` schema section + the new `CodePackage` sub-tables) in the same session the blocks land (CLAUDE.md "keep the bible updated").

---

## Open dependencies to resolve at phase start (must not be fabricated now)

1. **`CodePackage` internal table shapes** (`FootingTable` rows, `GuardRules` field names, `EnvelopeLimits.minSoilPSF`/`maxTributarySqFt`) — pinned by P3's real code, only sketched in the contract. Finalize lookups against P3 before writing literal fixture cells.
2. **`PostReaction.footingOrPostId` id convention** — must key to `Footing.id`; confirm P3's emitted id matches the footing ids this phase assigns.
3. **Canvas-space units for `Footing.position` / grade-point positions** — must match P2's `FramingMember.start/end` space; confirm before interpolation math.
4. **`PermitMeta.disclaimerAcknowledgedAt`** — RESOLVED: P1 ships all three minimal fields (`jurisdictionId`, `codeEdition`, `disclaimerAcknowledgedAt`) per contract §2.8; the disclaimer-ack gate field is available from P1, no staging needed here. P4 reads/writes it as the compliance-disclaimer gate for footing-sizing surfaces.
5. **`LedgerDetail` ownership** — the schema block lives in P5's `HouseModel`; P4 computes the connection design. Decide: persist into a P4-owned holding field or compute-only-then-P5-persist.
6. **`AnyCodable` nested-value extension** — contract assigns it to P1; verify it landed before emitting object-valued BOM metadata, else flatten to scalars.
