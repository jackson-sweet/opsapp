# OPS Decks — Phase 6 Implementation Plan: Surface Features, Patterns & Overhead (FULL)

**Date:** 2026-06-24
**Status:** Phase plan — conforms verbatim to `docs/superpowers/plans/2026-06-24-ops-decks-architecture-contract.md`
**Companions (read first):**
- Architecture contract (LOCKED): `docs/superpowers/plans/2026-06-24-ops-decks-architecture-contract.md`
- Feature roadmap: `docs/superpowers/specs/2026-06-24-ops-decks-feature-roadmap.md` (§2.6, §2.7, §2.3)
- Phase 1 foundation spec: `docs/superpowers/specs/2026-06-24-ops-decks-standalone-app-design.md`

> **Header note — bite-sized TDD steps with literal code are finalized at phase start once predecessors exist.** This phase builds on types that P1–P5 introduce (`DeckKit` package layout, `WasteSettings`, `FramingPlan`/`FramingMember`, `StructuralSizingEngine`, `CodePackage`/`CodePackageLoader`, `DeckCapabilities`, the `unknownBlocks` passthrough). Those types do **not** exist in the tree today (only their contract signatures do). Therefore the tasks below specify **interfaces verbatim from the contract** and **describe** the TDD steps + assertions, with concrete test code only where the contract makes a signature literal. When Phase 6 actually starts, each task is decomposed into red/green/refactor commits against the *real* predecessor code, and any signature drift discovered in P2–P5 is reconciled against this contract before a line is written.

---

## Goal

Ship the **FULL-tier surface, pattern, and overhead layer** of OPS Decks: everything a power-user designs *on top of and around* the structural frame, with the engineering rigor the FULL tier demands. Concretely, Phase 6 delivers:

1. **Decking pattern + board-direction engine + picture-frame** — per-surface pattern (parallel / diagonal / picture-frame / herringbone / chevron), board angle, and picture-frame border courses, with the substrate-blocking implications each pattern triggers (DCA6 diagonal blocking 12″ o.c., perimeter blocking for picture-frame).
2. **Generalized board-nesting cut optimizer** — `BoardNestingEngine`, lifting the proven offcut/lane internals out of `VinylCutListEngine` so *all* board families (decking, fascia, skirting, fastener-coupled boards) get optimized cut lists with offcut banking. The vinyl path stays byte-for-byte untouched.
3. **Fastener + finish takeoff** — hidden-clip vs face-screw counts coupled to joist layout/board run; stain/sealant/paint quantities from coated surface area.
4. **Railing component breakdown + material families** — rail/infill/post/sleeve/cap decomposition and frame-material families (aluminum/composite/PVC/wood/cable/glass) as additive `ComponentEmitter` rows.
5. **Advanced stairs** — tread types (open/closed riser, tread material, nosing), stringer count/spacing/sizing, landings, winders, and mandatory-handrail logic — *around* the unchanged `StairCalculator`.
6. **Fascia / skirting** and **built-in benches / planters / privacy walls**.
7. **Pergolas / covers / roofs** — `OverheadStructurePlan`, reusing the **same** `FramingMember` model and the **same** `StructuralSizingEngine` from P2/P3 (build the structural engine once).
8. **Deck lighting + basic electrical** — low-voltage fixture layout + transformer sizing + receptacle/GFCI notes.

Every assertion of a member size, a transformer wattage that claims code adequacy, or a stair-geometry pass is a **FULL compliance claim** and obeys §6 of the contract (objective-negative only, disclaimer-gated, out-of-envelope hard-stop, assumptions surfaced). Phase 6 itself ships **no new compliance *report* engine** (that is P7's `ComplianceEngine`); it produces the *data* (patterns, members, fixtures, fastener counts) and reuses P3's `StructuralSizingEngine` for the only structural sizing it performs (overhead members + stringer sizing). Pattern/fixture/finish layout that asserts no code value is BOTH-safe data; the *engineering* of overhead members and stringers is gated behind `.structuralSizing` / `.overhead` / `.surfacePatterns`.

---

## Architecture

Phase 6 adds **two additive top-level blocks** to `DeckDrawingData` (contract §2.7) — `surfaceFeatures: SurfaceFeaturePlan?` and `overhead: OverheadStructurePlan?` — and bumps `DeckDesign.version` to **6**. It introduces **one new engine** (`BoardNestingEngine`, contract §3.6 — generalizes `VinylCutListEngine`), **three new pure derivation engines** (`DeckingPatternEngine`, `StairDetailEngine`, `LightingTakeoffEngine`) that follow the StairCalculator precedent, and **reuses P3's `StructuralSizingEngine`** verbatim for overhead/stringer sizing. All engines are pure `enum`/`struct` namespaces in `DeckKit/Sources/DeckKit/Engine/`. No new protocol seams; no new `CodePackage` table types beyond what P3 ships — Phase 6 *reads* `CodePackage.stairRules` (R311.7 rise/run/handrail), `CodePackage.guardRules` (R312 — bench-as-guard), and the existing span tables (overhead members).

**Capability gating (contract §4):**
- `.surfacePatterns` (1 << 15, FULL) gates the pattern engine, board-nesting cut optimizer surfaces, fastener/finish takeoff surfaces, advanced stairs, fascia/skirting, built-ins, and lighting.
- `.overhead` (1 << 16, FULL) gates the pergola/cover/roof surfaces + overhead structural sizing.
- The blocks are **always preserved** regardless of capability (contract §1.4 `unknownBlocks` passthrough); a `.light` build opening a Phase-6 design renders the geometry it understands, prices the rough BOM it can, and round-trips `surfaceFeatures` + `overhead` untouched.
- Engines are **never invoked** without their capability. A `.light` build physically cannot emit an overhead member size or a stringer-sizing number.

**Compliance line (contract §6):** Pattern selection, fixture placement, finish coats, fascia/skirting quantities, board-nesting cut lists — these assert **no code value** and are pure takeoff/visualization → safe data, surfaced in FULL but harmless in LIGHT. The two places Phase 6 crosses the compliance line: (a) **overhead member sizing** and (b) **stringer sizing** — both route through P3's `StructuralSizingEngine.joistSpan`/`beamSizing`/`postSizing`/`sizeAll`, inherit its `EngineOutcome` envelope (result + limiting check + cited section + assumptions + edition), and inherit its out-of-envelope hard-stop. **§6.8 caution is binding:** IRC Appendix H (overhead-structure code) is paywalled/unverified — Phase 6 emits **no roof-cover compliance claim** against App. H; solid-roof/louvered members are sized only where they map to validated `CodePackage` beam/post tables, otherwise `EngineOutcome.outOfEnvelope(reason: "overhead roof load path requires a licensed engineer", …)`.

**3D render budget (roadmap §6):** A patterned deck surface + a pergola is an order of magnitude more SceneKit nodes than today's props on 3-year-old phones in sunlight. Phase 6 renders patterns as a **single textured/striped mesh per surface** (not per-board geometry) and overhead structures behind a **layer toggle** (the Chief Architect pattern, mirroring P2's framing-layer toggle), with instanced rafter geometry. Per-board geometry is never generated for rendering — board count comes from the engine, not the scene graph.

**Units (contract §5.1):** inches unless the property name says otherwise (`Feet`, `Degrees`, `PSF`, `SqFt`, `Watts`). `boardAngleDegrees` is degrees; `heightInches` is inches; transformer is `Watts`. Metric jurisdictions convert at the engine boundary via `CodePackage.unitSystem` (only the overhead/stringer sizing path touches code units; pattern/fixture/finish takeoff is unit-agnostic geometry).

---

## Tech Stack

- **Swift 5.10+ / Swift Package** — all code lands in the `DeckKit` package (`DeckKit/Sources/DeckKit/`), per contract §1.1–§1.2. No app-target code in Phase 6 except wiring the new editor surfaces into the existing `DeckBuilderViewModel` flow (which already lives in `DeckKit/Views/`).
- **Models:** additive `Codable` structs inside `DeckKit/Sources/DeckKit/Models/DeckGeometry.swift` (the `DeckDrawingData` blob) following the existing defensive `init(from:)` + `decodeIfPresent` pattern verbatim (precedent: `RailingConfig`, `StairConfig`, `DeckSurface`).
- **Engines:** pure `enum` namespaces, `static func`, `CoreGraphics` + `Foundation` only. No I/O, no `ModelContext`, no network. Precedent: `StairCalculator`, `VinylCutListEngine` (both pure today).
- **Geometry:** `PolygonMath` (existing — area, perimeter, point-in-polygon, scanline) and `DimensionEngine` (existing — post counts). Pattern board-count math reuses the scanline/band internals proven in `VinylCutListEngine`.
- **3D:** SceneKit via `DeckSceneBuilder` / `DeckMeshGenerator` (existing, in `DeckKit/Scene3D/`), extended additively with a pattern-texture path + overhead nodes behind a layer toggle.
- **Tests:** XCTest, table-driven, simulator destination `iPhone 17, OS 26.5`. Build verify device `generic/platform=iOS`. `xcodebuild -scheme OPS` (the OPS app target depends on `DeckKit`, so its test bundle exercises `DeckKit`). Grep logs for `BUILD SUCCEEDED` / `TEST SUCCEEDED` (memory: `xcodebuild-exit-code-masking`). Copy `Secrets.xcconfig` into any worktree first.
- **Design tokens:** `OPSStyle` / `OPSDesignKit` for every editor surface — no hardcoded color/spacing/radius/font. Numbers in UI = JetBrains Mono, tabular, formatted; empty state `—` (contract §5.1).
- **Skills at phase start:** `ops-copywriter` (every label/empty-state/error in the new editor sheets), `animation-studio:ios-animations` (any pattern-preview transition / layer-toggle motion — one easing curve, no spring), `mobile-ux-design` + `wireframe` (the pattern/stair/overhead editor sheet layouts — reason every element from the contractor's situation, §"Design Judgment"), `brainstorming` (before the editor UX).

---

## File Structure

### New files (all under `DeckKit/Sources/DeckKit/`)

| File | One-line responsibility |
|---|---|
| `Models/SurfaceFeaturePlan.swift` | The `SurfaceFeaturePlan` block + all P6 surface sub-types (`SurfacePatternSpec`, `DeckingPattern`, `FastenerSystem`, `FinishSpec`, `SkirtingSpec`, `BuiltInFeature`, `BuiltInKind`, `LightingPlan`) — defensive `Codable`, contract §2.7. |
| `Models/OverheadStructurePlan.swift` | The `OverheadStructurePlan` block + `OverheadStructure`, `OverheadKind`, `RoofShape` — reuses `FramingMember` from P2, defensive `Codable`, contract §2.7. |
| `Engine/DeckingPatternEngine.swift` | Pure engine: per-surface board layout (count, direction, length, miters), picture-frame border courses, and the substrate-blocking requirement each pattern triggers (DCA6). |
| `Engine/BoardNestingEngine.swift` | Pure engine: generalized board-nesting cut optimizer for all board families — offcut/lane internals lifted from `VinylCutListEngine`, family-parameterized stock lengths, kerf, grain. |
| `Engine/StairDetailEngine.swift` | Pure engine: tread types, stringer count/spacing/sizing (delegates structural sizing to `StructuralSizingEngine`), landings, winders, mandatory-handrail logic — *around* the unchanged `StairCalculator`. |
| `Engine/FastenerFinishTakeoff.swift` | Pure engine: fastener (hidden-clip vs face-screw) counts coupled to joist spacing + board run; finish/coating quantities from coated area + coats. |
| `Engine/LightingTakeoffEngine.swift` | Pure engine: low-voltage fixture wattage sum → transformer sizing (with headroom), wire-run estimate, receptacle/GFCI note generation. |
| `Engine/RailingComponentBreakdown.swift` | Pure helper: rail/infill/post/sleeve/cap decomposition + frame-material family rows (consumed by the `ComponentEmitter` additive rows). |
| `Engine/OverheadSizingCoordinator.swift` | Pure coordinator: maps an `OverheadStructure`'s members onto `StructuralSizingEngine` calls (reuse, not reimplement) with the §6.8 App-H hard-stop guard. |
| `Views/SurfacePatternSheet.swift` | FULL editor: per-surface pattern + board-angle + picture-frame courses picker (gated `.surfacePatterns`). |
| `Views/StairDetailSheet.swift` | FULL editor: tread type / stringer / landing / winder / handrail editor (gated `.surfacePatterns`). |
| `Views/SurfaceFeaturesSheet.swift` | FULL editor: fastener system, finishes, fascia/skirting, built-ins, lighting (gated `.surfacePatterns`). |
| `Views/OverheadStructureSheet.swift` | FULL editor: pergola/cover/roof placement + sizing trigger (gated `.overhead`). |
| `Scene3D/DeckPatternMeshBuilder.swift` | Pure-ish builder: a single striped/textured mesh per surface for the chosen pattern (no per-board nodes). |
| `Scene3D/OverheadSceneNodes.swift` | Builds overhead-structure SceneKit nodes (instanced rafters) behind a layer toggle. |

### Modified files

| File | Change |
|---|---|
| `Models/DeckGeometry.swift` | Add `var surfaceFeatures: SurfaceFeaturePlan? = nil` + `var overhead: OverheadStructurePlan? = nil` to `DeckDrawingData`; wire `CodingKeys` + `init(from:)` (`decodeIfPresent`); bump `DeckDesign.version` semantic to 6. Confirm both survive the §1.4 round-trip. |
| `Engine/ComponentEmitter.swift` | **Additive only.** New `component_type` rows: `decking_pattern`, `fascia`, `skirting`, `built_in`, `lighting_fixture`, `transformer`, `fastener`, `finish`, `railing_part` (rail/infill/sleeve/cap), `overhead_member`, `stair_detail`. Never rename a shipped `component_type`. |
| `Engine/EstimateGeneratorService.swift` | Feed P6 takeoff as new line-item categories: "Decking" (pattern board count × waste), "Fasteners", "Finishes", "Fascia/Skirting", "Built-Ins", "Lighting/Electrical", "Overhead". Threads `WasteSettings` (P1) into the pattern board-count path. |
| `Scene3D/DeckSceneBuilder.swift` | Call `DeckPatternMeshBuilder` for surface fill + `OverheadSceneNodes` for overhead; add the overhead layer toggle alongside P2's framing-layer toggle. |
| `DeckDesign.swift` (model) | `version` bump to 6 on save when a P6 block is present (the schema-version monotonic bump, contract §0.3). |

### New test files (under `OPSTests/DeckBuilder/`)

| File | Covers |
|---|---|
| `DeckingPatternEngineTests.swift` | Board count/direction/miters per pattern; DCA6 blocking requirements; picture-frame courses. |
| `BoardNestingEngineTests.swift` | Generalized nesting parity with vinyl internals; multi-family stock lengths; offcut banking; kerf. |
| `StairDetailEngineTests.swift` | Stringer count/spacing/sizing; tread types; landing insertion; winder geometry; handrail-required trigger. |
| `FastenerFinishTakeoffTests.swift` | Clip vs screw counts vs joist spacing; finish area × coats. |
| `LightingTakeoffEngineTests.swift` | Transformer sizing + headroom; GFCI/receptacle note. |
| `OverheadSizingCoordinatorTests.swift` | Reuse of `StructuralSizingEngine`; App-H hard-stop; outcome envelope. |
| `SurfaceFeaturePlanCodableTests.swift` | Defensive decode + **round-trip + LIGHT-preservation + malformed-sub-block** (contract §5.2 mandatory). |
| `OverheadStructurePlanCodableTests.swift` | Same mandatory round-trip suite for the overhead block. |
| `ComponentEmitterPhase6Tests.swift` | Additive rows emitted; no existing `component_type` renamed; level_id traceability. |

---

## Tasks

> Dependency legend — **[P1]** = consumes a Phase-1 contract type; **[P2]** = Phase-2; **[P3]** = Phase-3; etc. **[C§x]** = architecture-contract section.

---

### Task 1 — `SurfaceFeaturePlan` schema block + round-trip

**What:** Add the `surfaceFeatures: SurfaceFeaturePlan?` top-level property to `DeckDrawingData` and all its sub-types, verbatim from contract §2.7. Wire `CodingKeys` + defensive `init(from:)`. Bump `DeckDesign.version` to 6 when present.

**Interface (verbatim, C§2.7):**
```swift
public struct SurfaceFeaturePlan: Codable, Equatable {
    public var patterns: [SurfacePatternSpec]          // keyed by DeckSurface.id
    public var fastenerSystem: FastenerSystem?
    public var finishes: [FinishSpec]
    public var fascia: Bool = false
    public var skirting: SkirtingSpec?
    public var builtIns: [BuiltInFeature]
    public var lighting: LightingPlan?
}
public struct SurfacePatternSpec: Codable, Equatable {
    public var surfaceId: String
    public var pattern: DeckingPattern
    public var boardAngleDegrees: Double = 0
    public var pictureFrameCourses: Int = 0
}
public enum DeckingPattern: String, Codable, CaseIterable {
    case parallel, diagonal, pictureFrame = "picture_frame", herringbone, chevron
}
public enum FastenerSystem: String, Codable, CaseIterable { case hiddenClip = "hidden_clip", faceScrew = "face_screw" }
public struct FinishSpec: Codable, Equatable { public var kind: String; public var coats: Int }
public struct SkirtingSpec: Codable, Equatable { public var material: String; public var ventilated: Bool }
public struct BuiltInFeature: Codable, Equatable, Identifiable {
    public let id: String; public var kind: BuiltInKind; public var polygon: [CGPoint]; public var heightInches: Double
}
public enum BuiltInKind: String, Codable, CaseIterable { case bench, planter, privacyWall }
public struct LightingPlan: Codable, Equatable {
    public var fixtures: [CGPoint]; public var transformerWatts: Double?; public var receptacles: [CGPoint]
}
```

Add to `DeckDrawingData`:
```swift
var surfaceFeatures: SurfaceFeaturePlan? = nil   // C§2.2 additive
// CodingKeys: add `case surfaceFeatures`
// init(from:): self.surfaceFeatures = try c.decodeIfPresent(SurfaceFeaturePlan.self, forKey: .surfaceFeatures)
```

**Test strategy** (`SurfaceFeaturePlanCodableTests.swift`) — mirrors `StairConfigCodableTests`:
- `testDecode_missingBlock_isNil` — decode a baseline (P1) JSON with no `surfaceFeatures` key → `data.surfaceFeatures == nil`, whole-design decode succeeds (C§0.2).
- `testDecode_partialSpec_appliesDefaults` — a `SurfacePatternSpec` JSON with only `surfaceId` + `pattern` → `boardAngleDegrees == 0`, `pictureFrameCourses == 0` (defensive `init(from:)`).
- `testRoundTrip_stable` — encode→decode→encode produces byte-identical JSON for a fully-populated block (C§5.2.1).
- `testRoundTrip_lightBuildPreservesBlock` — a fully-populated `surfaceFeatures` JSON, decoded with `.light` capabilities, re-encoded → block present and equal (C§5.2.2; the §1.4 `unknownBlocks` path is exercised because LIGHT *does* declare the property if it shares the schema — assert via the `DeckCapabilities`-injected encode path that nothing is stripped).
- `testMalformedSubBlock_decodesToNilWithoutFailingDesign` — a `surfaceFeatures` with a garbage `lighting` value → `surfaceFeatures.lighting == nil` (or block nil) but `vertices`/`edges` still decode (C§0.2).
- `testVersionBump_setsSixWhenPresent` — saving a design carrying a P6 block sets `DeckDesign.version >= 6`.

Key assertions: missing-key tolerance, default application, round-trip stability, LIGHT non-stripping.

**Dependencies:** `DeckDrawingData` baseline + `unknownBlocks` passthrough **[P1, C§1.4]**; `DeckCapabilities`/`CapabilityProvider` **[P1, C§4]**; `DeckSurface.id` (existing) for `patterns` keying.

**References:** C§2.7, C§2.2 additive rule, C§0.2/§1.4 round-trip; existing defensive decoders (`RailingConfig`/`StairConfig`/`DeckSurface` in `DeckGeometry.swift`).

**Risks:** `CGPoint` already has a retroactive `Codable` conformance in `DeckGeometry.swift` (lines 1241–1258) — `BuiltInFeature.polygon: [CGPoint]` and `LightingPlan.fixtures: [CGPoint]` reuse it; do **not** redeclare it (would be a duplicate-conformance error). The `pictureFrame` raw value is `"picture_frame"` (snake_case multi-word, C§5.1) — must match exactly or web/other readers drift.

**Implementation status (2026-06-30):** Complete. Added `Models/SurfaceFeaturePlan.swift`, wired `DeckDrawingData.surfaceFeatures`, bumped `DeckSchemaMigration.currentSchemaVersion` to 6, and covered missing-key tolerance, defaulted pattern specs, stable round-trip, LIGHT preservation, malformed lighting isolation, and version-6 stamping in `SurfaceFeaturePlanCodableTests`.

**Verification (2026-06-30):** `swift test --package-path Packages/DeckKit --filter SurfaceFeaturePlanCodableTests` (6 tests), `swift test --package-path Packages/DeckKit` (401 tests), `scripts/verify-ops-decks-style-tokens.sh .`, `git diff --check`, and `xcodebuild -project OPS.xcodeproj -scheme OPSDecks -destination generic/platform=iOS -derivedDataPath /private/tmp/ops-decks-p6-task1-OPSDecks-dd CODE_SIGNING_ALLOWED=NO build` all passed.

---

### Task 2 — `OverheadStructurePlan` schema block + round-trip

**What:** Add `overhead: OverheadStructurePlan?` top-level property + sub-types, verbatim from C§2.7. The structure **reuses the P2 `FramingMember`** model (build the structural engine once).

**Interface (verbatim, C§2.7):**
```swift
public struct OverheadStructurePlan: Codable, Equatable {
    public var structures: [OverheadStructure]
}
public struct OverheadStructure: Codable, Equatable, Identifiable {
    public let id: String
    public var kind: OverheadKind                    // pergola|louveredRoof|solidRoof
    public var roofShape: RoofShape?                 // shed|gable|hip (solidRoof)
    public var footprint: [CGPoint]
    public var framing: [FramingMember]              // REUSES the P2 FramingMember
    public var shadePercent: Double?                 // pergola open shade
    public var productModel: String?                 // StruXure/Azenco catalog (louvered)
}
public enum OverheadKind: String, Codable, CaseIterable { case pergola, louveredRoof = "louvered_roof", solidRoof = "solid_roof" }
public enum RoofShape: String, Codable, CaseIterable { case shed, gable, hip }
```

Add to `DeckDrawingData`:
```swift
var overhead: OverheadStructurePlan? = nil
// CodingKeys: add `case overhead`
// init(from:): self.overhead = try c.decodeIfPresent(OverheadStructurePlan.self, forKey: .overhead)
```

**Test strategy** (`OverheadStructurePlanCodableTests.swift`): same mandatory round-trip suite as Task 1 — missing-block nil, partial-decode defaults (`roofShape == nil` for pergola; `shadePercent == nil`), round-trip stable, LIGHT preserves, malformed `framing` element → that member nil without failing the design. Plus `testFramingMemberReused` — assert an `OverheadStructure.framing` element decodes to a `FramingMember` with the same `role`/`nominalSize`/`sizing` shape P2 defined (compile-time proves reuse; runtime asserts a sized member survives the round-trip).

**Dependencies:** `FramingMember`, `LumberSize`, `WoodSpecies`, `LumberGrade`, `FramingRole`, `MemberSizingResult` **[P2/P3, C§2.4]**; `DeckDrawingData` baseline **[P1]**.

**References:** C§2.7, C§2.4 (`FramingMember`), C§5.2 round-trip.

**Risks:** `OverheadStructure.framing` carrying `FramingMember.sizing` couples this block to P3's `MemberSizingResult` shape — if P3 ever changes `MemberSizingResult`, the overhead block inherits it (acceptable, it's the *same* type by design). The `louveredRoof` raw value `"louvered_roof"` must match exactly.

**Implementation status (2026-06-30):** Complete. Added `Models/OverheadStructurePlan.swift`, wired `DeckDrawingData.overhead`, added `DeckSchemaMigration.overheadSchemaVersion`, and covered missing-key tolerance, partial defaults, stable round-trip, LIGHT preservation, malformed framing-member isolation, `FramingMember`/`MemberSizingResult` reuse, and version-6 stamping in `OverheadStructurePlanCodableTests`.

**Verification (2026-06-30):** `swift test --package-path Packages/DeckKit --filter OverheadStructurePlanCodableTests` (7 tests), `swift test --package-path Packages/DeckKit` (408 tests), `scripts/verify-ops-decks-style-tokens.sh .`, `git diff --check`, and `xcodebuild -project OPS.xcodeproj -scheme OPSDecks -destination generic/platform=iOS -derivedDataPath /private/tmp/ops-decks-p6-task2-OPSDecks-dd CODE_SIGNING_ALLOWED=NO build` all passed.

---

### Task 3 — `DeckingPatternEngine` (pattern + board-direction + picture-frame)

**What:** A pure engine that, for a given surface polygon + `SurfacePatternSpec` + board profile (width/length from the catalog model), computes the **board layout**: board count, run direction, per-board length (with miter cuts for diagonal/herringbone/chevron/picture-frame), picture-frame border course rectangles, and the **substrate-blocking requirement** the pattern triggers (DCA6: diagonal needs blocking ≤ 12″ o.c.; picture-frame needs perimeter blocking). It asserts **no code pass** — it produces takeoff geometry + a blocking *requirement flag* the framing layer (P2) consumes.

**Interface (new — fits the StairCalculator pure-namespace precedent):**
```swift
public enum DeckingPatternEngine {
    /// Lay boards across a surface polygon for the chosen pattern.
    /// `boardWidthInches`/`boardLengthInches` come from the catalog board profile (P1 model).
    /// `gapInches` is the standard decking gap (e.g. 0.1875). Pure; no I/O.
    public static func layout(
        surfacePolygon: [CGPoint],
        scaleFactor: Double,
        spec: SurfacePatternSpec,
        boardWidthInches: Double,
        boardLengthInches: Double,
        gapInches: Double
    ) -> DeckingLayoutResult
}

public struct DeckingLayoutResult: Codable, Equatable {
    public var boards: [DeckBoardCut]            // one per physical board piece
    public var boardCount: Int
    public var coveredAreaSqFt: Double
    public var pictureFrameCourses: [PictureFrameCourse]
    /// What the substrate must provide for THIS pattern to be code-buildable.
    /// Consumed by the P2 framing layer; Phase 6 does NOT assert it is satisfied.
    public var blockingRequirement: BlockingRequirement
}
public struct DeckBoardCut: Codable, Equatable, Identifiable {
    public let id: String
    public var lengthInches: Double
    public var startMiterDegrees: Double         // 0 = square cut
    public var endMiterDegrees: Double
    public var runAxisDegrees: Double            // board direction
    public var isBorder: Bool                    // picture-frame perimeter course
}
public struct PictureFrameCourse: Codable, Equatable { public var ringIndex: Int; public var perimeterFeet: Double }
public struct BlockingRequirement: Codable, Equatable {
    public var maxBlockingSpacingInchesOC: Double?   // nil = no extra blocking beyond field default
    public var perimeterBlockingRequired: Bool
    public var codeSection: String                    // e.g. "AWC DCA6 — diagonal blocking"
}
```

**Test strategy** (`DeckingPatternEngineTests.swift`) — table-driven, hand-computed expecteds:
- `testParallel_rectangle_boardCount` — a 12ft × 16ft surface, 5.5″ boards + 0.1875″ gap, parallel along the 16ft axis → boards run 16ft, count = `ceil(144 / (5.5+0.1875))` = 26; all `startMiterDegrees == 0`. Assert `boardCount`, all-square cuts, `coveredAreaSqFt ≈ 192`.
- `testDiagonal_triggersBlocking` — `pattern == .diagonal`, `boardAngleDegrees == 45` → `blockingRequirement.maxBlockingSpacingInchesOC == 12`, `codeSection` cites DCA6 diagonal blocking; boards carry 45° run axis and mitered ends at the perimeter.
- `testPictureFrame_courses_andPerimeterBlocking` — `pattern == .pictureFrame`, `pictureFrameCourses == 2` → `pictureFrameCourses.count == 2`, border boards `isBorder == true` with 45° miters at corners, `blockingRequirement.perimeterBlockingRequired == true`.
- `testHerringbone_chevron_miters` — assert 45°/complementary miters and that board count scales with the diagonal tiling (hand-computed for a small square).
- `testWasteFedSeparately` — engine returns raw board count; waste is applied by `EstimateGeneratorService` (Task 9) via `WasteSettings.perPatternWastePercent` — assert the engine does **not** inflate count itself.
- Anchor any test that touches a non-rectangular polygon on `PolygonMath` outputs, not hardcoded geometry literals.

Key assertions: board count math, miter angles, blocking-requirement flag + cited section, no waste baked in.

**Dependencies:** `SurfacePatternSpec`/`DeckingPattern` (Task 1); catalog board profile (width/length/coverage) from the **brand-neutral catalog model [P1, roadmap §2.7]**; `PolygonMath` (existing); `WasteSettings.perPatternWastePercent` **[P1, C§2.3]** (read by the estimate layer, not here).

**References:** roadmap §2.6 (pattern + picture-frame), §2.7 (board-nesting); AWC DCA6 (diagonal blocking 12″ o.c., perimeter blocking for picture-frame); `StairCalculator` pure-function precedent.

**Risks:** Herringbone/chevron board-count on a non-rectangular polygon is genuinely hard (tiling a concave face) — scope the v1 to convex/rectilinear faces and `blockingRequirement` flags; flag non-rectilinear herringbone as a known approximation with a confidence note rather than asserting an exact count. The blocking requirement is a *requirement*, never a *pass* — keep it data the P2/P7 layer reasons about, never a §6 claim here.

---

### Task 4 — `BoardNestingEngine` (generalize `VinylCutListEngine`)

**What:** Lift the offcut/lane + scanline cut internals out of `VinylCutListEngine` into a **board-family-parameterized** nesting engine for decking, fascia, skirting, and any linear board family — stock-length-based (not roll-width), with kerf and optional grain/direction constraint. **The vinyl path stays byte-for-byte untouched** (C§3.6: "vinyl path untouched"); `BoardNestingEngine` is a *new* engine reusing the same internals, not a refactor of the vinyl one.

**Interface (new — mirrors `VinylCutListEngine.makePlan` shape, C§3.6 "new `BoardNestingEngine` reusing the same offcut/lane internals"):**
```swift
public enum BoardNestingEngine {
    /// Nest required board cuts against purchasable stock lengths + on-hand
    /// offcuts, banking new remnants. Family-agnostic (decking/fascia/skirting).
    public static func makePlan(
        cuts: [BoardCutRequirement],
        stock: BoardStock,
        availableOffcuts: [BoardOffcut] = []
    ) -> BoardNestingPlan
}
public struct BoardCutRequirement: Identifiable, Equatable {
    public let id: String
    public var family: BoardFamily               // decking | fascia | skirting
    public var lengthInches: Double
    public var grainLocked: Bool                 // true = cannot rotate/flip (decking color run)
}
public enum BoardFamily: String, Codable, CaseIterable { case decking, fascia, skirting }
public struct BoardStock: Equatable {
    public var stockLengthsInches: [Double]      // e.g. [144, 192, 240] (12/16/20 ft)
    public var kerfInches: Double                // saw kerf, e.g. 0.125
    public var offcutMinLengthInches: Double     // below this a remnant is scrap
}
public struct BoardOffcut: Identifiable, Equatable {
    public let id: String; public var lengthInches: Double; public var family: BoardFamily
}
public struct BoardNestingPlan: Equatable {
    public var stockPieces: [BoardStockPiece]    // each purchased stock + the cuts taken from it
    public var producedOffcuts: [BoardOffcut]
    public var reuseNotes: [String]
    public var totalStockCount: Int
    public var totalWasteLinearFeet: Double
}
public struct BoardStockPiece: Identifiable, Equatable {
    public let id: String; public var stockLengthInches: Double; public var cuts: [BoardCutRequirement]
    public var remainderInches: Double
}
```

**Test strategy** (`BoardNestingEngineTests.swift`):
- `testSingleStock_packsLongestFirst` — cuts [60, 50, 40] into 144″ stock with 0.125 kerf → all three fit in one 144″ piece (60+50+40+2 kerfs = 150.25 > 144? → recompute: needs 2 pieces), assert exact stock count + remainder math. Hand-compute the kerf-inclusive packing.
- `testOffcutBankedAndReused` — a job leaves a 70″ decking offcut ≥ `offcutMinLengthInches` → `producedOffcuts` contains it; a second `makePlan` seeded with it consumes it before buying stock (mirrors `VinylOffcutInventoryTests`).
- `testFamilyIsolation` — a `fascia` cut never nests into a `decking` offcut and vice versa (family-matched lanes).
- `testGrainLocked_noRotation` — `grainLocked == true` cuts are placed without flipping (decking color run preserved).
- `testParityWithVinylInternals` — feed a degenerate single-family, single-stock case and assert the packing decision matches the equivalent `VinylCutListEngine` offcut-lane decision (proves the lifted internals behave identically); **also** assert `VinylCutListEngine.makePlan` output is unchanged by running the existing `VinylCutListEngineTests` suite green (regression gate, C§3.6).
- `testMultipleStockLengths_minimizesWaste` — given [144, 192, 240] stock, a 200″ run prefers one 240″ over two 144″ (waste-minimizing choice).

Key assertions: kerf-correct packing, family isolation, offcut banking/reuse across jobs, vinyl-path regression untouched.

**Dependencies:** the `VinylCutListEngine` offcut/lane + scanline internals (existing, lifted/shared — **not** modified); `DeckBoardCut` from `DeckingPatternEngine` (Task 3) feeds `BoardCutRequirement`; `WasteSettings` **[P1]** informs `offcutMinLengthInches` defaults at the call site.

**References:** C§3.6 (generalize `VinylCutListEngine`, vinyl untouched); roadmap §2.7 (board-nesting cut optimizer, all board families); existing `VinylOffcutInventoryTests` / `VinylCutListEngineTests` as the parity oracle.

**Risks:** **Do not refactor `VinylCutListEngine`'s public surface** — it has a battery of tests (`VinylCutListEngineTests`, `VinylOffcutInventoryTests`, `VinylOrderSelectionTests`, `VinylPreviewAnnotationPlannerTests`) and a documented dual-path sync trap (memory `vinyl-offcut-inventory-shipped`). Lift the *private* lane/scanline logic into a shared internal helper, leave the vinyl public API and its area-based (roll-width) model exactly as-is. 1D linear nesting (boards) is a *simpler* problem than vinyl's 2D roll-width packing — extract the 1D first-fit-decreasing + offcut-banking core, not the 2D rectangle-tiling.

---

### Task 5 — `StairDetailEngine` (tread types, stringers, landings, winders, handrail)

**What:** Advanced stair detailing **around** the unchanged `StairCalculator` (C§3.6: "P6 advanced stairs add tread types / stringer sizing / landings *around* it, not by changing it"). Computes: stringer count + spacing + **member sizing** (delegated to `StructuralSizingEngine`), tread type (open/closed riser, tread material, nosing per R311.7.5), landing insertion when a flight exceeds the max vertical rise (R311.7.6), winder geometry (R311.7.5.2.1), and the mandatory-handrail trigger (≥ 4 risers → graspable handrail required, R311.7.8). Reads `CodePackage.stairRules`.

**Interface (new — `StairCalculator.calculate(...)` is the unchanged input, C§3.6 keeps its signature):**
```swift
public enum StairDetailEngine {
    /// Detail a stair flight: stringers, treads, landings, winders, handrail.
    /// `base` is the result of the UNCHANGED StairCalculator.calculate(...).
    public static func detail(
        base: StairCalculator.StairSpec,
        treadType: TreadType,
        treadMaterial: String,
        stringerSpacingInchesOC: Double,
        species: WoodSpecies,
        grade: LumberGrade,
        package: CodePackage
    ) -> StairDetailResult
}
public enum TreadType: String, Codable, CaseIterable { case openRiser = "open_riser", closedRiser = "closed_riser" }
public struct StairDetailResult: Codable, Equatable {
    public var stringerCount: Int
    public var stringerSpacingInchesOC: Double
    /// Stringer member sizing — delegated to StructuralSizingEngine; carries the
    /// EngineOutcome envelope (result + limiting check + cited section + edition).
    public var stringerSizing: MemberSizingResult?
    public var treadType: TreadType
    public var noseProjectionInches: Double          // R311.7.5.3 (≥ 0.75", ≤ 1.25")
    public var landings: [StairLanding]              // R311.7.6 — empty if none required
    public var winders: [WinderTread]                // R311.7.5.2.1 — empty if straight flight
    public var handrailRequired: Bool                // R311.7.8 — true when riserCount >= 4
    public var handrailCodeSection: String
}
public struct StairLanding: Codable, Equatable { public var afterRiserIndex: Int; public var depthInches: Double }
public struct WinderTread: Codable, Equatable {
    public var index: Int; public var innerRunInches: Double; public var walklineRunInches: Double
}
```

**Test strategy** (`StairDetailEngineTests.swift`) — anchor on `StairCalculator.calculate` output, hand-computed code thresholds from a fixture `CodePackage.stairRules`:
- `testStringerCount_delegatesToStairCalculator` — `base` from `StairCalculator.calculate(totalRise: 30, width: 48)` → `stringerCount == 3` (matches `StairCalculator.StairConfig.stringerCount`, the unchanged precedent); assert `StairCalculator` itself is **not** modified (its existing tests stay green).
- `testStringerSizing_routesThroughStructuralEngine` — assert `stringerSizing` is a `MemberSizingResult` produced by `StructuralSizingEngine` (not a hand-rolled number); for an out-of-envelope stair (e.g. excessive total rise) assert `stringerSizing.outcome` is `.outOfEnvelope` → no size emitted (C§6.5).
- `testHandrailRequired_fourRisers` — a 4-riser stair → `handrailRequired == true`, `handrailCodeSection` cites R311.7.8; a 3-riser stair → `false`.
- `testLandingInserted_whenRiseExceedsMax` — a total rise exceeding the package's max single-flight vertical (e.g. 147″ per R311.7.3) → exactly one `StairLanding` at the correct riser index with `depthInches >= width` (≥ 36″ min).
- `testWinderGeometry_walkline` — a winder flight → `walklineRunInches` measured 12″ from the narrow end ≥ the package min run; `innerRunInches >= 6` (R311.7.5.2.1).
- `testNosing_withinRange` — `noseProjectionInches` between 0.75 and 1.25 for closed-riser; open-riser has its own rule (4″ sphere).
- Date/dimension brittleness: never hardcode; derive expecteds from the fixture `CodePackage.stairRules` cells.

Key assertions: `StairCalculator` untouched + reused; stringer sizing routed through `StructuralSizingEngine` (inherits hard-stop); handrail/landing/winder code triggers + cited sections.

**Dependencies:** `StairCalculator.StairSpec`/`StairConfig` (existing, **unchanged**); `StructuralSizingEngine.postSizing`/`beamSizing`/`sizeAll` + `MemberSizingResult` + `EngineOutcome` **[P3, C§3.1]**; `CodePackage.stairRules` **[P3, C§3.4]**; `WoodSpecies`/`LumberGrade` **[P2]**.

**References:** C§3.6 (`StairCalculator` unchanged, detail around it); IRC R311.7.5 (treads/nosing), R311.7.5.2.1 (winders), R311.7.6 (landings), R311.7.8 (handrails); DCA6 stair guidance (stringer sizing).

**Risks:** Winder geometry is `VH` complexity (roadmap §2.6) — the walkline + inner-radius math must be exact or it's a safety claim that's wrong. Scope v1 winders to the common 90° L-turn winder set, hard-stop curved/spiral to PE (`outOfEnvelope`). Stringer sizing as a notched member is *not* a plain joist span — model the net section (notch reduces depth); if the package lacks a notched-stringer table, hard-stop rather than mis-applying the joist table (§6.5).

---

### Task 6 — `FastenerFinishTakeoff` (fastener + finish takeoff)

**What:** Two pure takeoffs. **Fasteners:** hidden-clip count vs face-screw count, coupled to joist spacing (P2 framing) + board run length + board count (Task 3) — clips are per board-per-joist-crossing; face screws are 2 per crossing. **Finishes:** stain/sealant/paint quantity from coated surface area (deck + fascia + skirting + rail) × coats ÷ coverage-per-unit. Asserts no code value — pure quantity takeoff.

**Interface (new):**
```swift
public enum FastenerFinishTakeoff {
    public static func fasteners(
        system: FastenerSystem,
        boards: [DeckBoardCut],
        joistSpacingInchesOC: Double,
        surfacePolygon: [CGPoint],
        scaleFactor: Double
    ) -> FastenerTakeoff

    public static func finishes(
        specs: [FinishSpec],
        coatedAreaSqFt: Double,
        coveragePerUnitSqFt: Double
    ) -> [FinishTakeoff]
}
public struct FastenerTakeoff: Codable, Equatable {
    public var system: FastenerSystem
    public var clipCount: Int            // 0 for face-screw system
    public var screwCount: Int           // 0 for hidden-clip system (excl. starter/fascia)
    public var boardToJoistCrossings: Int
}
public struct FinishTakeoff: Codable, Equatable {
    public var kind: String; public var coats: Int; public var unitsRequired: Double  // gallons/units, ceil at call site
}
```

**Test strategy** (`FastenerFinishTakeoffTests.swift`):
- `testHiddenClip_perCrossing` — N boards crossing M joists (joist spacing 16″ o.c. over a 16ft run → 13 joists) → `clipCount == boardCount * crossings`, `screwCount == 0`. Hand-compute crossings from spacing + run.
- `testFaceScrew_twoPerCrossing` — same geometry, `.faceScrew` → `screwCount == 2 * crossings`, `clipCount == 0`.
- `testFinish_areaTimesCoatsOverCoverage` — 200 sqft × 2 coats ÷ 250 sqft/gal coverage → 1.6 units (caller ceils to 2). Assert raw `unitsRequired == 1.6`.
- `testZeroBoards_zeroFasteners` — empty board layout → zero counts (defensive).

Key assertions: crossing math from joist spacing, clip-vs-screw exclusivity, finish quantity = area × coats ÷ coverage (raw, un-ceiled).

**Dependencies:** `FastenerSystem`/`FinishSpec` (Task 1); `DeckBoardCut` (Task 3); joist spacing from `FramingPlan`/`FramingMember.spacingInchesOC` **[P2, C§2.4]**; `PolygonMath` (existing).

**References:** roadmap §2.7 (fastener takeoff coupled to joist layout; finish takeoff); no code-claim — pure takeoff.

**Risks:** Fastener count "couples to joist layout" (roadmap §2.7) — if P2's `FramingPlan` isn't populated (LIGHT plausible-frame may have members but no engineered spacing), fall back to the field default spacing (16″ o.c.) and tag the takeoff as estimate-grade, never code-grade. Keep this a quantity, never a structural claim.

---

### Task 7 — `LightingTakeoffEngine` (deck lighting + basic electrical)

**What:** Pure engine: sum fixture wattage → size a low-voltage transformer with headroom (NEC Art. 411 context; transformer sized to ~80% load max), estimate total wire run, and generate the receptacle/GFCI note (NEC 210.52(E) outdoor receptacle, 210.8(A)(3) GFCI). Wattage/transformer is an objective sizing; the GFCI/receptacle requirement is a **note**, not a compliance pass.

**Interface (new):**
```swift
public enum LightingTakeoffEngine {
    public static func size(
        plan: LightingPlan,
        fixtureWatts: Double,
        scaleFactor: Double
    ) -> LightingTakeoffResult
}
public struct LightingTakeoffResult: Codable, Equatable {
    public var fixtureCount: Int
    public var totalConnectedWatts: Double
    public var recommendedTransformerWatts: Double   // next standard size at <=80% load
    public var estimatedWireRunFeet: Double
    public var receptacleCount: Int
    /// Advisory note string, NOT a compliance pass (C§6 — objective negative only).
    public var electricalNote: String                // e.g. "Outdoor receptacles require GFCI per NEC 210.8(A)(3) — verify with a licensed electrician."
}
```

**Test strategy** (`LightingTakeoffEngineTests.swift`):
- `testTransformerSized_at80PercentLoad` — 10 fixtures × 4W = 40W connected → recommended transformer ≥ 50W (40 / 0.8), snapped to the next standard size (e.g. 60W). Assert `totalConnectedWatts == 40`, `recommendedTransformerWatts == 60`.
- `testWireRun_fromFixturePositions` — fixtures at known canvas points + scaleFactor → `estimatedWireRunFeet` matches the hand-computed nearest-neighbor/MST run (or a documented simpler perimeter-run heuristic).
- `testReceptacleCount_fromPlan` — `plan.receptacles.count` echoed; `electricalNote` contains the GFCI advisory and **never** the word "compliant"/"safe" (assert the string is advisory-framed, C§6.1).
- `testEmptyPlan_zeroes` — no fixtures → zero watts, no transformer recommendation, note still advisory.

Key assertions: 80%-load transformer sizing snapped to standard sizes, wire-run estimate, GFCI note is advisory (no positive code claim).

**Dependencies:** `LightingPlan` (Task 1); `PolygonMath` for wire-run distance (existing).

**References:** roadmap §2.6 (lighting low-voltage + transformer sizing; basic electrical receptacle + GFCI note); NEC Art. 411, 210.52(E), 210.8(A)(3); C§6.1 (objective-negative — the GFCI line is a note, not a pass).

**Risks:** Transformer "standard sizes" are product-dependent — keep the standard-size ladder a parameter/constant set, documented, not hardcoded as a code value. The GFCI note must be advisory only; electrical is out of the deck code packages' scope — never imply the app verified electrical code.

---

### Task 8 — `OverheadSizingCoordinator` (pergolas/covers reuse `StructuralSizingEngine`)

**What:** Map an `OverheadStructure`'s `framing: [FramingMember]` onto **P3's `StructuralSizingEngine`** (build the structural engine once — C§3.6, roadmap §2.3) to size rafters/beams/posts, with the **§6.8 App-H hard-stop**: solid-roof and louvered-roof load paths that depend on roof-cover/snow-on-roof rules from IRC Appendix H (paywalled/unverified) return `EngineOutcome.outOfEnvelope`. Pergola (open shade, no roof load) sizes via the standard beam/post tables.

**Interface (new — a coordinator, not a new sizing algorithm):**
```swift
public enum OverheadSizingCoordinator {
    /// Size every member of an overhead structure by delegating to
    /// StructuralSizingEngine. Returns the structure with FramingMember.sizing
    /// filled. App-H-dependent roof load paths hard-stop to PE (C§6.8).
    public static func size(
        _ structure: OverheadStructure,
        load: LoadPreset,
        package: CodePackage
    ) -> OverheadSizingOutcome
}
public struct OverheadSizingOutcome: Codable, Equatable {
    public var structure: OverheadStructure           // framing members with .sizing filled
    /// .outOfEnvelope when the kind/roofShape requires App-H rules we cannot assert.
    public var blocked: EngineCitation?               // non-nil => hard stop, no sizes emitted
    public var assumptions: EngineAssumptions
}
```

**Test strategy** (`OverheadSizingCoordinatorTests.swift`):
- `testPergola_sizesViaStructuralEngine` — a pergola (open shade, snow not on solid roof) → each `framing` member gets a `sizing` from `StructuralSizingEngine.sizeAll` (assert the result carries the `EngineOutcome.ok` citation + `EngineAssumptions` with the package edition, C§3 envelope). `blocked == nil`.
- `testSolidRoof_hardStopsAppendixH` — `kind == .solidRoof` with a snow load that requires App-H roof rules → `blocked != nil`, `blocked.codeSection` references the App-H limitation, every member `sizing == nil` (no number emitted, C§6.5/§6.8).
- `testLouveredRoof_productModelNoSelfCertify` — `kind == .louveredRoof` with a `productModel` (StruXure/Azenco) → `blocked != nil` citing "manufacturer-engineered product — refer to manufacturer's stamped tables" (the app never self-certifies a proprietary aluminum system).
- `testAssumptionsSurfaced` — `assumptions` carries load/species/grade/edition for any non-blocked result (C§6.6).
- `testReusesP3Engine_noParallelSizing` — assert (by construction/compile + a spy fixture `CodePackage`) that sizing values match `StructuralSizingEngine.beamSizing`/`postSizing` outputs for identical inputs — proving no parallel sizing logic (C§3.4 "must not invent a parallel loader/engine").

Key assertions: delegation to P3 (no parallel sizing), App-H solid-roof hard-stop, louvered-product no-self-certify, assumptions surfaced.

**Dependencies:** `OverheadStructure`/`OverheadKind`/`RoofShape` (Task 2); `StructuralSizingEngine.beamSizing`/`postSizing`/`sizeAll` + `EngineOutcome`/`EngineCitation`/`EngineAssumptions` **[P3, C§3.1, C§3]**; `CodePackage` beam/post tables + `EnvelopeLimits` **[P3, C§3.4]**; `LoadPreset` **[P2, C§2.4]**.

**References:** C§3.6 (overhead reuses `StructuralSizingEngine`), C§6.5 (out-of-envelope hard-stop), **C§6.8 (App-H unverified → no roof-cover compliance claim)**; roadmap §2.3 (overhead via shared structural engine; App. H paywalled).

**Risks:** This is the single highest-liability task in Phase 6. The temptation is to "just size the roof rafters" — but snow-on-roof + App-H rules are *unverified* (roadmap §8). The safe default is **hard-stop solid/louvered roofs to PE** and only fully size pergolas (open shade, no accumulated roof load). Do not emit any roof-cover code claim. Reusing P3's engine is mandatory — any parallel sizing path violates C§3.4/§8.3.

---

### Task 9 — Estimate + component integration (additive only)

**What:** Wire all Phase-6 takeoff into the estimate + the catalog `components` projection — **additively**.
- `ComponentEmitter`: emit new `component_type` rows (`decking_pattern`, `fascia`, `skirting`, `built_in`, `lighting_fixture`, `transformer`, `fastener`, `finish`, `railing_part`, `overhead_member`, `stair_detail`) with `level_id` traceability. **Never rename a shipped `component_type`** (C§8.1 — the `ComponentEmitter` doc comment is binding).
- `EstimateGeneratorService`: add line-item categories ("Decking", "Fasteners", "Finishes", "Fascia/Skirting", "Built-Ins", "Lighting/Electrical", "Overhead"); thread `WasteSettings.perPatternWastePercent` **[P1]** into the pattern board-count → quantity path (the waste fix lands per-pattern here).
- `RailingComponentBreakdown`: decompose each railing into rail/infill/post/sleeve/cap rows + frame-material family.

**Interface (additive helper):**
```swift
public enum RailingComponentBreakdown {
    /// Decompose a railing edge into part rows (rail/infill/post/sleeve/cap)
    /// tagged with the frame-material family. Additive ComponentEmitter rows.
    public static func parts(
        railing: RailingConfig,
        edgeLengthInches: Double,
        family: RailingMaterialFamily
    ) -> [RailingPart]
}
public enum RailingMaterialFamily: String, Codable, CaseIterable {
    case aluminum, composite, pvc, wood, cable, glass
}
public struct RailingPart: Codable, Equatable {
    public var part: String          // "rail" | "infill" | "post" | "sleeve" | "cap"
    public var quantity: Double; public var unit: String; public var family: RailingMaterialFamily
}
```

**Test strategy** (`ComponentEmitterPhase6Tests.swift`):
- `testAdditiveRowsEmitted` — a design with `surfaceFeatures` + `overhead` → `ComponentEmitter.emit` produces the new `component_type` rows; assert each new type is present with correct metadata + `level_id` on multi-level.
- `testNoExistingComponentTypeRenamed` — assert the legacy rows (`railing`, `deck_board`, `stair_set`, `gate`, `post_set`) still emit with identical `component_type` strings (regression — run the existing `ComponentEmitter` expectations). This is the C§8.1 contract gate.
- `testWasteThreaded_perPattern` — a diagonal surface with `perPatternWastePercent["diagonal"] == 15` → the "Decking" line quantity = raw board count × 1.15 (assert the waste multiplier is applied at the estimate layer, not the pattern engine).
- `testRailingBreakdown_familyTagged` — a glass railing edge → rail/infill/post/sleeve/cap rows each tagged `.glass`; a cable railing → `.cable`; quantities scale with edge length.
- `testEstimateCategories_present` — generated line items include the seven new categories when their data exists; absent categories produce no rows (state-aware, no empty placeholders — §"Design Judgment").

Key assertions: additive `component_type` rows, **zero renames** of shipped types, per-pattern waste applied at the estimate layer, railing part decomposition + family tagging.

**Dependencies:** `ComponentEmitter`/`DesignComponentRow`/`AnyCodable` (existing — additive); `EstimateGeneratorService` (existing — new categories); `WasteSettings.perPatternWastePercent` **[P1, C§2.3]**; all Phase-6 engine outputs (Tasks 3–8); `RailingConfig` (existing).

**References:** C§3.6 (`ComponentEmitter` additive; `EstimateGeneratorService` waste threading), C§8.1 (never rename `component_type`); roadmap §2.6 (railing breakdown + families), §2.7 (waste-factor engine).

**Risks:** The `AnyCodable` in `ComponentEmitter.swift` is **scalar-only today** (lines 343–390) and C§1.4 says it's extended in P1 to carry nested object/array values. If a Phase-6 component row needs a nested metadata value (e.g. a list of picture-frame courses), it depends on the P1 `AnyCodable` extension being in place — otherwise keep Phase-6 component metadata **scalar** (flatten lists into counts + separate rows) to avoid relying on an unverified extension. Per the outbound-field-allowlist memory (`ios-outbound-field-allowlist-drift`): new component types feeding line items must not trip a column allowlist on the outbound sync — verify the estimate line-item write path tolerates the new categories.

---

### Task 10 — 3D render: pattern mesh + overhead nodes behind a layer toggle

**What:** Render the surface pattern as a **single textured/striped mesh per surface** (board direction + picture-frame visible, but **not** per-board geometry) and overhead structures as instanced rafter/beam/post nodes, both behind layer toggles (the Chief Architect pattern, mirroring P2's framing toggle). Extend `DeckSceneBuilder` additively; add `DeckPatternMeshBuilder` + `OverheadSceneNodes`.

**Interface (builder, pure where possible):**
```swift
enum DeckPatternMeshBuilder {
    /// A single SCNGeometry textured/striped for the surface's pattern + angle.
    /// No per-board nodes (render budget — roadmap §6).
    static func surfaceMesh(
        polygon: [CGPoint], scaleFactor: Double, spec: SurfacePatternSpec, boardWidthInches: Double
    ) -> SCNGeometry
}
enum OverheadSceneNodes {
    static func nodes(for structure: OverheadStructure, scaleFactor: Double) -> SCNNode  // instanced rafters
}
```

**Test strategy** — uses the existing `ImageRenderer → XCTAttachment` snapshot harness (memory `ops-ios-swiftui-snapshot-harness`; precedent `DeckSceneSnapshotTests` / `DeckMeshGeneratorTests`):
- `testPatternMesh_nodeCountBounded` — a patterned 12×16 surface produces **one** surface-fill geometry, not 26 board nodes (assert node count is O(1) per surface, the render-budget guarantee).
- `testOverheadNodes_instanced` — a pergola with 10 rafters reuses **one** rafter geometry across instances (assert shared geometry reference).
- `testLayerToggle_hidesOverhead` — toggling the overhead layer off removes the overhead node subtree (and the design still renders).
- Snapshot attachments for: parallel, diagonal, picture-frame fills + a pergola — visual verification stays a human step (attach images, interactive QA with Jackson present).

Key assertions: bounded node count per surface (render budget), instanced overhead geometry, layer-toggle correctness; snapshots attached for human review.

**Dependencies:** `DeckSceneBuilder`/`DeckMeshGenerator` (existing, in `DeckKit/Scene3D/`); `SurfacePatternSpec` (Task 1); `OverheadStructure` (Task 2); P2's framing-layer-toggle pattern (mirror it).

**References:** roadmap §6 (3D complexity on mobile — layer toggles, instanced geometry, LOD; per-board geometry is too many nodes); existing `DeckSceneSnapshotTests` harness.

**Risks:** SceneKit on 3-year-old phones in sunlight is the binding constraint (roadmap §6, CLAUDE.md field-first). **Never generate per-board nodes** — a striped texture or a low-poly grooved plane communicates the pattern at a fraction of the node cost. Overhead must be instanced + LOD'd. This task is render-only; it asserts nothing structural (the sizing lives in Task 8). Photoreal is explicitly deferred (roadmap §8) — do not reach for RealityKit/PBR here.

---

### Task 11 — FULL editor surfaces (capability-gated, design-judgment-first)

**What:** The four editor sheets (`SurfacePatternSheet`, `StairDetailSheet`, `SurfaceFeaturesSheet`, `OverheadStructureSheet`), each **hidden** (not disabled-with-lock) when its capability is absent, except a single tasteful "available in OPS Decks Pro" upsell stub (C§4 rules). Every surface reasons from the contractor's situation (§"Design Judgment") — pattern picker shows a live preview, not a raw enum list; stair detail collapses to one entry point per flight; overhead is one CONNECT-style entry, not a card per kind.

**Interface:** SwiftUI views taking the `DeckBuilderViewModel` + a `CapabilityProvider` (C§4). No new public DeckKit types beyond the views; they mutate `DeckDrawingData.surfaceFeatures` / `.overhead` through the VM's existing save path.

**Test strategy:**
- Capability gating is unit-testable: `testSurfaceSheet_hiddenWhenCapabilityAbsent` — with `.light` capabilities, the pattern/stair/features/overhead entry points are absent from the toolbar model (assert the VM's surface list excludes them); the single upsell stub is present.
- `testEngineNeverInvokedInLight` — with `.light`, mutating a surface never calls `OverheadSizingCoordinator`/`StructuralSizingEngine` (assert via a spy seam: sizing is unreachable, `FramingMember.sizing`/overhead sizes stay `nil` — C§4 "LIGHT physically cannot produce a sizing number").
- Visual/interactive QA (layout, copy, motion) is a human step with Jackson present (computer-use), per the DS-conformance-pass precedent.

Key assertions: FULL surfaces hidden (not locked) in LIGHT; engines unreachable in LIGHT; single upsell stub.

**Dependencies:** `DeckCapabilities`/`CapabilityProvider` **[P1, C§4]**; `DeckBuilderViewModel` (existing, in `DeckKit/Views/`); all Phase-6 models + engines; `OPSStyle`/`OPSDesignKit` tokens; `ops-copywriter` for every string.

**References:** C§4 (surfaces hidden when capability absent; one upsell stub; engine never invoked without capability); CLAUDE.md §"Design Judgment" (reason every presentation from the human's situation — either/or collapses to one entry point, verbs behind rows, progressive disclosure); §"Brand & MO" (military tactical minimalist, terse copy).

**Risks:** The canonical design failure (CLAUDE.md: Books shipping side-by-side QuickBooks/Sage cards) applies directly — do **not** render a card per `OverheadKind` or a row per `DeckingPattern` enum case. Collapse to one entry point with progressive disclosure + live preview. Skill usage is mandatory: `mobile-ux-design` + `wireframe` + `brainstorming` before building, `ops-copywriter` for every label. Field-first: 44pt+ touch targets, 16pt+ text, gloves/sunlight.

---

## Build & verification gates (every task)

1. **Compile (device target):** `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → grep `BUILD SUCCEEDED` (C§8.8; memory `xcodebuild-exit-code-masking`).
2. **Tests compile + run (simulator):** `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing` then `test` → grep `TEST SUCCEEDED`. Copy `Secrets.xcconfig` into the worktree first (C§5.2; `OPS/CLAUDE.md`).
3. **Round-trip suite green** for both new blocks (C§5.2 mandatory): encode→decode→encode stable; LIGHT preserves FULL blocks; malformed sub-block → nil without failing the design.
4. **Vinyl regression green** — `VinylCutListEngineTests` + `VinylOffcutInventoryTests` + `VinylOrderSelectionTests` unchanged (Task 4 must not disturb the vinyl path, C§3.6).
5. **`ComponentEmitter` no-rename gate** — existing component-type expectations green (C§8.1).
6. **DerivedData hygiene** — check `ps aux | grep xcodebuild` / `lsof` before kicking off a build if a sibling session may be active; prefer a worktree-local DerivedData (CLAUDE.md parallel-session rules).
7. **Bible update** — on landing, update `ops-software-bible/` deck sections (data model: the two new `drawing_data` blocks; engines: the five new engines; the LIGHT/FULL capability additions). An outdated bible is a broken bible (CLAUDE.md).

## Sequencing within Phase 6

Schema first (Tasks 1–2, the additive blocks + round-trip — everything else writes into them), then the pure engines in dependency order (3 pattern → 4 nesting → 6 fastener/finish, then 5 stairs + 7 lighting + 8 overhead which depend on P3's `StructuralSizingEngine`), then integration (9 estimate/components), then render (10) and editors (11). Tasks 3, 7 are independent of P3 and can land before P3 is fully verified; Tasks 5 and 8 are **blocked on P3's `StructuralSizingEngine` + `CodePackage`** existing and verified.

## Assumptions this phase makes that other phases must honor

(Echoed in the return summary.)

1. **P3 ships `StructuralSizingEngine` with `beamSizing`/`postSizing`/`sizeAll` + the `EngineOutcome`/`EngineCitation`/`EngineAssumptions` envelope, and `CodePackage` carries `beamSpanTable`/`postHeightTable`/`stairRules`/`guardRules` + `EnvelopeLimits`** (C§3.1, §3.4). Phase 6's stair-stringer sizing (Task 5) and overhead sizing (Task 8) call P3 verbatim — they do **not** reimplement sizing.
2. **P2's `FramingMember`/`FramingPlan`/`LoadPreset`/`WoodSpecies`/`LumberGrade`/`LumberSize` are exactly as in C§2.4**, and `FramingMember.spacingInchesOC` is populated for joists (Task 6 fasteners read it; falls back to 16″ o.c. when absent). `OverheadStructure.framing` *is* `[FramingMember]` (the same type, not a copy).
3. **P1's `WasteSettings.perPatternWastePercent` keys are raw `DeckingPattern` string values** (`"parallel"`, `"diagonal"`, `"picture_frame"`, `"herringbone"`, `"chevron"`) — Task 9 threads waste by that key. If P1 keyed it differently, reconcile the key space before Phase 6.
4. **P1's `unknownBlocks` passthrough + `AnyCodable` nested-value extension are in place** (C§1.4). Phase-6 component metadata stays **scalar** if the `AnyCodable` extension is not verified, to avoid depending on an unproven extension.
5. **The `ComponentEmitter` `component_type` namespace is additive forever** (C§8.1) — Phase 6 adds `decking_pattern`/`fascia`/`skirting`/`built_in`/`lighting_fixture`/`transformer`/`fastener`/`finish`/`railing_part`/`overhead_member`/`stair_detail`. No later phase may rename these. The web/adapter side must tolerate unknown component types (forward-compat).
6. **App-H (overhead roof) compliance stays out** until the actual text is validated (C§6.8, roadmap §8). Phase 6 hard-stops solid/louvered roof load paths to PE; if a later phase ingests a validated App-H package, Task 8's hard-stop relaxes to a sizing call — until then, **no roof-cover code claim ships**.
7. **`StairCalculator.calculate(...)` keeps its exact signature** (C§3.6) — Task 5 details *around* it. No phase may change `StairCalculator`'s public surface.
8. **`VinylCutListEngine`'s public API + its tests are untouched** (C§3.6) — `BoardNestingEngine` reuses lifted *private* internals only. No phase may refactor the vinyl public surface under the banner of "generalization."
