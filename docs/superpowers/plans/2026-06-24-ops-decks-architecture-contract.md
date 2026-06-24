# OPS Decks — Authoritative Architecture Contract

**Date:** 2026-06-24
**Status:** LOCKED contract — the single source of truth every phase plan (P1–P7) cites
**Companions (read first):**
- Feature roadmap: `docs/superpowers/specs/2026-06-24-ops-decks-feature-roadmap.md`
- Phase 1 foundation spec: `docs/superpowers/specs/2026-06-24-ops-decks-standalone-app-design.md`

**Purpose.** This document fixes the cross-phase contracts — module layout, protocol seams, the versioned `drawing_data` schema (with the exact additive block each phase contributes), the engine catalog (exact pure-function signatures), the LIGHT/FULL capability-flag mechanism, naming + testing conventions, and the compliance liability rules — so that seven independently-authored phase plans line up at the type and signature level. **Where a name or signature appears here, the phase plan adopts it verbatim.** Deviations require amending this contract first.

**Grounding.** All "existing" types/signatures below were read directly from the live code (`OPS/DataModels/DeckDesign.swift`, `OPS/DeckBuilder/` 73 files) on 2026-06-24. New types are proposed to fit the existing additive-Codable pattern exactly.

---

## 0. Bedrock invariants (every phase obeys)

1. **One blob, additive, backward-decodable.** The entire deck serializes to `DeckDesign.drawingDataJSON` via `DeckDrawingData.toJSON()` / `.fromJSON()`. Every subsystem grows *inside* `DeckDrawingData` as a new **optional** field. Each phase's block is a sibling key, never a breaking rename.
2. **Unknown / failed sub-block must never fail the whole-design decode.** `DeckDrawingData.init(from:)` decodes every field with `decodeIfPresent` + default. A FULL-authored block that a LIGHT build cannot parse must (a) decode to `nil` without throwing, AND (b) be **preserved on re-encode** (see §1.4 round-trip rule). This is the §1/§6 graceful-degradation guarantee and directly addresses the crew-blackout + stale-overwrite incidents (poisoned cursor / last-writer-wins) recorded in memory.
3. **`DeckDesign.version` becomes live** (memory flags it dead today). It is the *schema* version, monotonically bumped per phase that adds a block (P1=1 baseline, P2=2, … P7=7). It gates **migration/backfill**, never rendering — rendering is gated by *capability flags* (§4), not version.
4. **Engines are pure, table-driven, offline, unit-tested.** Precedent: `StairCalculator` encodes IRC R311.7 as a pure function. Every new engine takes value inputs → returns a result struct that carries (result + the limiting check + the cited code section + the package edition). No I/O, no network, no `ModelContext`, no singletons.
5. **Code rules are DATA, not code.** Span/footing/connection tables live in downloadable, versioned, jurisdiction-keyed packages stored in Supabase + delivered via ops-web, cached offline. Engines consume a loaded `CodePackage`; they never hard-code table cells.
6. **Compliance posture is LOCKED (§6).** Objective-negative claims only ("no code failures detected"), jurisdiction-selectable, disclaimer-gated, out-of-envelope hard-stops to "requires a licensed engineer." Every compliance-touching phase obeys §6 as a shared constraint.
7. **DeckKit knows nothing about OPS.** No `Project`, `Company`, `AppState`, `AuthManager`, `SyncEngine`, `DataController`, `ImageSyncManager`. Everything app-specific enters through `companyId: String` / `projectId: String?` primitives and the four protocol seams (§1.3).

---

## 1. Module / target layout

### 1.1 Packages and targets

```
OPS.xcworkspace
├─ OPSDesignKit  (Swift package)   ← OPSStyle tokens + Styles/Components/* (shared styling, no domain logic)
├─ DeckKit       (Swift package)   ← the entire deck designer, app-agnostic
│     depends on: OPSDesignKit
│     exposes:    DeckStore, ImageUploader, OCRService, CodePackageLoader  (protocol seams)
│     knows NOTHING about Project / Company / AppState / OPS SyncEngine
├─ OPS           (app target)      ← existing app; depends on DeckKit; supplies OPS-flavored seam impls
└─ OPS Decks     (app target)      ← NEW thin shell; depends on DeckKit; supplies lean seam impls
```

**Decision (resolved here, from spec §14):** `OPSDesignKit` is a **separate package**, not vendored into DeckKit. Both app targets and DeckKit depend on it, giving one token source. `OPSStyle` and `Styles/Components/*` move into `OPSDesignKit` unchanged (34/73 DeckBuilder files reference `OPSStyle` — styling is shared, not a coupling blocker).

### 1.2 What moves into DeckKit (Phase 1 carve-out — mechanical, not a rewrite)

All of `OPS/DeckBuilder/` (73 files) moves into `DeckKit/Sources/DeckKit/`, **plus** the model `OPS/DataModels/DeckDesign.swift`. The extraction work is (a) relocate, (b) replace global reaches with injected seams/params, (c) confirm `DeckDesign` + sync models reachable from both targets.

| DeckKit submodule | Contents (existing files, moved as-is) |
|---|---|
| `Models/` | `DeckGeometry.swift` (the `DeckDrawingData` blob + all sub-structs), `DeckLevel.swift`, `DeckDrawingState.swift`, `BuiltInMaterial.swift`, `ProductUnitDimension.swift`, `SketchScanResult.swift`, `PhotoOverlayState.swift`, `DeckTemplateDefinitions.swift`, + `DeckDesign` (the SwiftData `@Model`) |
| `Engine/` | `StairCalculator`, `VinylCutListEngine`, `ComponentEmitter`, `EstimateGeneratorService`, `SurfaceDetector`, `DeckTemplateEngine`, `PolygonMath`, `DimensionEngine`, `SnapEngine`, `ScaleInference`, `SketchScanPipeline` + OCR helpers, `ContourExtractor`, `GridDetector`, `AccuracyModel`, `DimensionAssociator` |
| `Rendering/` | `DeckRenderer`, `DeckOverlayRenderer`, `DeckShareRenderer`, `DeckStairRenderPlanner` |
| `Scene3D/` | `DeckSceneBuilder`, `DeckScene3DView`, `DeckMeshGenerator`, `DeckSurfaceEdgeResolver`, `CameraPresetBar` |
| `AR/` | all `AR/*` |
| `Views/` | all `Views/*` + `DeckBuilderViewModel` |
| `Compliance/` (NEW, grows P3–P7) | code-package model + loader + sizing/footing/compliance/drafting engines |

**Coupling to sever at the boundary** (counts from spec §3): `companyId` (14 files) and `projectId`/`Project` (8 files) → become **parameters**; `SyncEngine` (2 files) + `DataController` (1 file) → behind `DeckStore`; thumbnail/photo upload → behind `ImageUploader`; OCR/AI → behind `OCRService`. There are **zero** references to `AppState`/`AuthManager`/`ImageSyncManager`, so no app-wide-state seam is needed.

### 1.3 Protocol seams (exact signatures)

These four protocols are the *only* way DeckKit reaches the host app. They are defined in `DeckKit`; each app target supplies a conforming impl. All are `Sendable` and async where I/O is involved.

```swift
// DeckKit/Sources/DeckKit/Seams/DeckStore.swift
//
// Persistence + sync seam. Replaces direct ModelContext + SyncEngine use.
// BOTH apps back this with the SAME SwiftData models + the SAME Supabase
// backend — the protocol exists for testability + app-agnosticism, NOT to
// create two storage systems (spec §4.1).
public protocol DeckStore: Sendable {
    /// All non-deleted decks for the active company (RLS-scoped server-side).
    func listDecks(companyId: String) async throws -> [DeckDesign]
    /// One deck by id, or nil if missing / soft-deleted.
    func loadDeck(id: String) async throws -> DeckDesign?
    /// Upsert. Sets needsSync; the host's sync layer drains opportunistically.
    func saveDeck(_ deck: DeckDesign) async throws
    /// Soft delete (sets deletedAt, marks needsSync).
    func deleteDeck(id: String) async throws
    /// Count of non-deleted decks for the company — drives the free 1-deck gate.
    func savedDeckCount(companyId: String) async throws -> Int
    /// Change stream so the library view repaints on inbound sync merges
    /// (mirrors the OPS InboundChangeSignal pattern).
    func deckChanges(companyId: String) -> AsyncStream<[DeckDesign]>
}

// DeckKit/Sources/DeckKit/Seams/ImageUploader.swift
//
// Thumbnail + photo-overlay uploads. S3 is server-mediated via ops-web
// presign endpoints — the app holds NO AWS keys (memory: ios-aws-credential-removal).
public protocol ImageUploader: Sendable {
    /// Upload a rendered thumbnail; returns the public/CDN URL to store in
    /// DeckDesign.thumbnailURL. Throws on network failure (caller queues retry).
    func uploadThumbnail(_ data: Data, deckId: String, companyId: String) async throws -> URL
    /// Upload a photo-overlay source image; returns its URL.
    func uploadOverlayImage(_ data: Data, deckId: String, companyId: String) async throws -> URL
    /// Delete a previously-uploaded asset (note: server-mediated; on iOS this
    /// also requires the caller to prune any CSV/row references — see memory
    /// ios-deleteimage-local-cache-only for the OPS analogue).
    func deleteAsset(url: URL, companyId: String) async throws
}

// DeckKit/Sources/DeckKit/Seams/OCRService.swift
//
// Scan-to-plan OCR/AI path (wraps SketchOCR + SketchAIFallback). Injected so
// the standalone reaches the same backend service or degrades gracefully offline.
public protocol OCRService: Sendable {
    /// Recognized text + bounding boxes from a captured sketch image.
    func recognizeText(in image: CGImage) async throws -> [SketchOCRObservation]
    /// AI fallback that returns a structured scan result when on-device OCR
    /// is insufficient. Throws OCRServiceError.unavailable when offline.
    func interpretSketch(_ image: CGImage, hints: SketchScanHints) async throws -> SketchScanResult
}

// DeckKit/Sources/DeckKit/Seams/CodePackageLoader.swift  (introduced P1 as a stub, lit up P3)
//
// Loads downloadable, versioned, jurisdiction-keyed code-rule packages
// (Supabase-stored, ops-web-delivered, offline-cached). Engines consume the
// loaded CodePackage; they never hold the loader. (§3.4, §5, §6.4)
public protocol CodePackageLoader: Sendable {
    /// Jurisdictions available to download (catalog fetched/cached from ops-web).
    func availableJurisdictions() async throws -> [JurisdictionDescriptor]
    /// Returns a cached package if present (offline-first), else downloads it.
    func loadPackage(jurisdictionId: String, edition: String?) async throws -> CodePackage
    /// The package currently selected for a deck (resolved from drawing_data
    /// permitMeta.jurisdictionId), or nil if none chosen yet.
    func activePackage(for deck: DeckDesign) async throws -> CodePackage?
    /// Force-refresh the catalog + any updatable packages (no App Store release
    /// needed to push a code revision).
    func refreshCatalog() async throws
}
```

Supporting seam value types (defined in DeckKit): `SketchOCRObservation` (text + `CGRect` box + confidence — wraps the existing `SketchOCR` output), `SketchScanHints`, `OCRServiceError` (`.unavailable`, `.lowConfidence`, `.failed(Error)`). `SketchScanResult` already exists.

**Phase 1 supplies:** `OPSDeckStore` / `OPSImageUploader` / `OPSOCRService` (backed by the existing `SyncEngine` / ops-web presign / `SketchOCR`) for the OPS target; lean equivalents for the OPS Decks target. `CodePackageLoader` ships in P1 as a **no-op stub** (`availableJurisdictions` → `[]`) and is implemented in P3.

### 1.4 The round-trip preservation rule (critical, all phases)

`DeckDrawingData.toJSON()` currently re-encodes the whole struct (and recomputes `components` via `ComponentEmitter.emit`). Because Swift's synthesized `Codable` only round-trips declared properties, **a block a build doesn't know about would be silently dropped on save** — violating invariant §0.2. Contract:

- Every phase that adds a block adds it as a **declared optional property** with `decodeIfPresent` in `init(from:)` (so older blocks survive a newer build trivially — the forward direction).
- For the **backward** direction (a LIGHT build must preserve FULL-only blocks it can't meaningfully edit), DeckKit adds, in Phase 1, an **`unknownBlocks: [String: AnyCodable]` passthrough** captured in `init(from:)` from any top-level key not in `CodingKeys`, and re-emitted in `encode(to:)`. This guarantees a LIGHT build round-trips a FULL design without stripping framing/terrain/permit blocks. (`AnyCodable` already exists in `ComponentEmitter.swift`; it is extended P1 to also carry nested object/array values, since today it is scalar-only.)

---

## 2. `drawing_data` versioned schema

### 2.1 Existing shape (verbatim, schema version 1 — baseline)

`DeckDrawingData` (in `Models/DeckGeometry.swift`) today declares:

```swift
struct DeckDrawingData: Codable {
    var vertices: [DeckVertex] = []
    var edges: [DeckEdge] = []
    var footprint: DeckFootprint = DeckFootprint()     // legacy single-surface
    var surfaces: [DeckSurface] = []                   // per-surface materials/labels
    var config: DrawingConfig = DrawingConfig()
    var overallElevation: Double?
    var scaleFactor: Double?
    var poolDiameter: Double?
    var photoOverlay: PhotoOverlayState?
    var levels: [DeckLevel] = []
    var levelConnections: [LevelConnection] = []
    var components: [DesignComponentRow]? = nil         // derived projection (ComponentEmitter)
}
```

Key existing sub-types (do not rename; extend additively): `DeckVertex { id, position: CGPoint, elevation: Double?, elevationSource: ElevationSource, footingType: FootingType?, postType: String? }`, `DeckEdge { id, startVertexId, endVertexId, edgeType: EdgeType, dimension: Double?, dimensionSource, railingConfig: RailingConfig?, stairConfig: StairConfig?, assignedItems: [AssignedItem], accuracyPercent, dimensionStale, label, houseEdgeMaterial: HouseEdgeMaterial? }`, `RailingConfig`, `StairConfig`, `AssignedItem { id, productId, name, unitType: UnitType, unitPrice, taskTypeId, taskTypeColor, isGate }`, `DeckSurface { id, vertexIds: Set<String>, assignedItems, label, color, boardMaterial }`, `DeckLevel`, `LevelConnection`, `FootingType { helicalPile, sonoTube, concretePad }`, `EdgeType { houseEdge, deckEdge }`, `HouseEdgeMaterial { stucco, hardie, woodVertical, brick, stone, vinyl, parapet }`.

Every existing sub-struct already implements a **defensive `init(from:)`** with `decodeIfPresent` + defaults (see `RailingConfig`, `StairConfig`, `DeckSurface`, `DeckLevel`). **New blocks follow this exact pattern.**

### 2.2 Additive-block rule (the cross-phase contract)

Each phase adds **one new optional top-level property** to `DeckDrawingData` (plus its sub-types), wires it into `CodingKeys` + `init(from:)` with `decodeIfPresent`, and bumps `DeckDesign.version`. The property is the phase's *namespace*; nothing outside that phase touches it. A build without the phase's capability flag (§4) preserves the block via §1.4 passthrough.

| Schema ver | Phase | New top-level property on `DeckDrawingData` | Type | Backward-decodable |
|---|---|---|---|---|
| 1 | P1 | *(baseline above)* + `var schemaVersion: Int? = nil` (mirror of `DeckDesign.version` inside the blob, for self-describing JSON) + `var wasteSettings: WasteSettings? = nil` (P1 waste fix) + `var unknownBlocks: [String: AnyCodable]? = nil` (passthrough) | — | n/a |
| 2 | P2 | `var framing: FramingPlan? = nil`, `var terrain: TerrainModel? = nil` | structs | yes |
| 3 | P3 | *(no new block — P3 fills `FramingMember.sizing` results + reads `permitMeta.jurisdictionId`)* | — | yes |
| 4 | P4 | `var footings: FootingPlan? = nil` | `FootingPlan` | yes |
| 5 | P5 | `var house: HouseModel? = nil` | `HouseModel` | yes |
| 6 | P6 | `var surfaceFeatures: SurfaceFeaturePlan? = nil`, `var overhead: OverheadStructurePlan? = nil` | structs | yes |
| 7 | P7 | `var permitMeta: PermitMeta? = nil` | `PermitMeta` | yes |

> **Sequencing note:** `permitMeta.jurisdictionId` is read by P3's engines, but the *block* is introduced in P1 (jurisdiction selection has to exist before P3 can size anything). Listed under P7 above for "where its full shape lands"; P1 ships the minimal `PermitMeta { jurisdictionId: String?, codeEdition: String?, disclaimerAcknowledgedAt: Date? }` so jurisdiction can be chosen and the compliance disclaimer acknowledged early. The compliance result/setbacks/PE-stamp fields are completed in P7. **Phase plans: treat `PermitMeta` as P1-introduced (all three minimal fields), P7-completed.**

### 2.3 P1 additive block — `WasteSettings` (the waste-factor fix)

Fixes the zero-waste under-ordering bug (`EstimateGeneratorService` bills raw footage). LIGHT exposes a single tunable % per pattern; FULL refines per-pattern.

```swift
public struct WasteSettings: Codable, Equatable {
    /// Single global waste % applied to area-based takeoff when no per-pattern
    /// override exists. Default 10% (industry standard for straight-lay).
    public var defaultWastePercent: Double = 10.0
    /// Per-decking-pattern overrides (raw DeckingPattern value -> percent).
    /// Diagonal ~15%, herringbone/chevron ~20%, picture-frame +border allowance.
    public var perPatternWastePercent: [String: Double] = [:]
    // defensive init(from:) with decodeIfPresent + defaults (pattern of §2.1)
}
```

### 2.4 P2 additive block — `FramingPlan` (framing members)

The critical-path block. First-class joist/beam/post/ledger/rim/blocking, derived by the auto-framing engine and edited by the manual editor. Per-level (mirrors geometry living on `DeckLevel`).

```swift
public struct FramingPlan: Codable, Equatable {
    /// Keyed by DeckLevel.id ("" sentinel for single-level designs).
    public var members: [FramingMemberSet]
    /// Load + species presets that drive sizing (P3 consumes these).
    public var loadPreset: LoadPreset?
    public var generationSource: FramingSource   // .auto | .manual | .autoThenEdited
    public var generatedAtSchemaVersion: Int?
}

public struct FramingMemberSet: Codable, Equatable {
    public var levelId: String
    public var members: [FramingMember]
}

public struct FramingMember: Codable, Equatable, Identifiable {
    public let id: String
    public var role: FramingRole          // joist|beam|post|ledger|rimBand|blocking|bridging
    /// Endpoints in canvas coordinates (same space as DeckVertex.position).
    public var start: CGPoint
    public var end: CGPoint
    public var nominalSize: LumberSize?    // e.g. .twoByTen — nil until sized
    public var plyCount: Int = 1           // doubled beam = 2, triple = 3
    public var spacingInchesOC: Double?    // joists/blocking
    public var species: WoodSpecies?
    public var grade: LumberGrade?
    /// FILLED BY P3 StructuralSizingEngine; nil = not yet engineered (LIGHT).
    public var sizing: MemberSizingResult?
    public var locked: Bool = false        // manual editor: exclude from re-derive
}

public enum FramingRole: String, Codable, CaseIterable {
    case joist, beam, post, ledger, rimBand, blocking, bridging, cantilever
}
public enum LumberSize: String, Codable, CaseIterable {
    case twoBySix = "2x6", twoByEight = "2x8", twoByTen = "2x10", twoByTwelve = "2x12"
    case fourByFour = "4x4", fourBySix = "4x6", sixBySix = "6x6"
    // additive: never remove a shipped case
}
public enum WoodSpecies: String, Codable, CaseIterable {
    case southernPine = "southern_pine", douglasFirLarch = "df_l"
    case hemFir = "hem_fir", sprucePineFir = "spf", redwoodCedar = "redwood_cedar"
}
public enum LumberGrade: String, Codable, CaseIterable { case select = "select_structural", no1 = "no1", no2 = "no2" }
public enum FramingSource: String, Codable { case auto, manual, autoThenEdited }

public struct LoadPreset: Codable, Equatable {
    public var liveLoadPSF: Double = 40       // IRC residential deck default
    public var deadLoadPSF: Double = 10
    public var snowLoadPSF: Double?           // 50/60/70 etc. — overrides live where governing
    public var species: WoodSpecies = .sprucePineFir
    public var grade: LumberGrade = .no2
}
```

> P2 ships `FramingPlan` with `sizing == nil` on every member (LIGHT auto-derives a *plausible* frame for visualization + rough BOM, **no code claim** — §1 of roadmap). P3 fills `sizing`.

### 2.5 P4 additive block — `FootingPlan` (+ `TerrainModel`, introduced P2)

> **Phase ownership:** `FootingPlan` is the P4 block (schema ver 4). `TerrainModel` is **introduced in P2** (schema ver 2, alongside `FramingPlan`) populating only `groundCover`; **P4 completes it** by filling `gradePoints`/`slopeSource` additively inside the SAME struct — no rename, no new top-level key. The struct definition below is the full shape both phases share.

```swift
public struct FootingPlan: Codable, Equatable {
    public var footings: [Footing]
    public var soil: SoilInput?
    public var frost: FrostInput?
}
public struct Footing: Codable, Equatable, Identifiable {
    public let id: String
    /// Anchors to a vertex (perimeter) OR a free canvas point (interior/beam-line pier).
    public var vertexId: String?
    public var position: CGPoint
    public var type: FootingType          // existing enum — extend additively if needed
    public var diameterInches: Double?
    public var depthInches: Double?
    public var helicalTorqueFtLb: Double?
    public var connection: PostFootingConnection?   // uplift hardware (Simpson) — P4
    /// FILLED BY P4 FootingEngine; nil = not yet sized.
    public var sizing: FootingSizingResult?
}
public struct SoilInput: Codable, Equatable {
    public var bearingCapacityPSF: Double = 1500   // IRC R401.4 presumptive; BCBC uses kPa
    public var source: SoilSource                  // .presumptive | .geotechReport
}
public struct FrostInput: Codable, Equatable {
    public var depthInches: Double?                // AHJ/zip-derived; "verify with AHJ"
    public var source: FrostSource                 // .bundledTable | .userEntered | .ahjVerified
}
public enum SoilSource: String, Codable { case presumptive, geotechReport }
public enum FrostSource: String, Codable { case bundledTable, userEntered, ahjVerified }

public struct TerrainModel: Codable, Equatable {
    /// Grade samples in canvas space with height-below-deck-datum (feet).
    public var gradePoints: [GradePoint]
    /// Per-zone ground surface cover (grass/dirt/gravel/rock/concrete/pavers).
    public var groundCover: [GroundZone]
    public var slopeSource: ElevationSource         // existing enum (.manual | .ar)
}
public struct GradePoint: Codable, Equatable { public var position: CGPoint; public var dropFeet: Double }
public struct GroundZone: Codable, Equatable, Identifiable {
    public let id: String; public var polygon: [CGPoint]; public var cover: GroundCover
}
public enum GroundCover: String, Codable, CaseIterable { case grass, dirt, gravel, rock, concrete, pavers }
public struct PostFootingConnection: Codable, Equatable { public var hardwareModel: String?; public var upliftRated: Bool }
```

### 2.6 P5 additive block — `HouseModel`

```swift
public struct HouseModel: Codable, Equatable {
    /// Floor-line datum (feet) the deck attaches to; story heights for elevation views.
    public var floorLineFeet: Double?
    public var storyHeights: [Double]
    /// Openings (doors/windows) placed on house edges — drives wall cutouts +
    /// elevation views + door/window schedule.
    public var openings: [WallOpening]
    /// Ledger attachment detail (cladding-driven; brick/stone -> freestanding fallback).
    public var ledger: LedgerDetail?
}
public struct WallOpening: Codable, Equatable, Identifiable {
    public let id: String
    public var edgeId: String              // the houseEdge it sits on
    public var kind: OpeningKind           // patioDoor|frenchDoor|sliderDoor|window
    public var widthInches: Double
    public var heightInches: Double
    public var sillHeightInches: Double    // 0 for floor-level doors
    public var offsetAlongEdgeInches: Double
}
public enum OpeningKind: String, Codable, CaseIterable { case patioDoor, frenchDoor, sliderDoor, window }
public struct LedgerDetail: Codable, Equatable {
    public var cladding: HouseEdgeMaterial    // existing enum
    public var attachmentAllowed: Bool        // false for brick/stone -> freestanding
    public var fastenerSchedule: String?      // P7 detail callout
    public var lateralConnectors: Int?        // IRC R507.9.2 hold-downs
}
```

### 2.7 P6 additive blocks — `SurfaceFeaturePlan` + `OverheadStructurePlan`

```swift
public struct SurfaceFeaturePlan: Codable, Equatable {
    /// Per-surface decking pattern + board direction (keyed by DeckSurface.id).
    public var patterns: [SurfacePatternSpec]
    public var fastenerSystem: FastenerSystem?       // hidden clips vs face screws
    public var finishes: [FinishSpec]                // stain/sealant/paint takeoff
    public var fascia: Bool = false
    public var skirting: SkirtingSpec?
    public var builtIns: [BuiltInFeature]            // benches/planters/privacy walls
    public var lighting: LightingPlan?               // low-voltage + transformer sizing
}
public struct SurfacePatternSpec: Codable, Equatable {
    public var surfaceId: String
    public var pattern: DeckingPattern               // parallel|diagonal|pictureFrame|herringbone|chevron
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

public struct OverheadStructurePlan: Codable, Equatable {
    public var structures: [OverheadStructure]
}
public struct OverheadStructure: Codable, Equatable, Identifiable {
    public let id: String
    public var kind: OverheadKind                    // pergola|louveredRoof|solidRoof
    public var roofShape: RoofShape?                 // shed|gable|hip (solidRoof)
    public var footprint: [CGPoint]
    /// Reuses the SAME FramingMember model (build the structural engine once).
    public var framing: [FramingMember]
    public var shadePercent: Double?                 // pergola open shade
    public var productModel: String?                 // StruXure/Azenco catalog (louvered)
}
public enum OverheadKind: String, Codable, CaseIterable { case pergola, louveredRoof = "louvered_roof", solidRoof = "solid_roof" }
public enum RoofShape: String, Codable, CaseIterable { case shed, gable, hip }
```

### 2.8 P7 additive block — `PermitMeta` (introduced P1, completed P7)

`PermitMeta` is **introduced in P1**: P1 ships ALL THREE minimal fields — `jurisdictionId`, `codeEdition`, and `disclaimerAcknowledgedAt` — so jurisdiction can be chosen and the compliance disclaimer acknowledged before P3 sizing runs. The remaining fields (compliance result/run timestamp, setbacks, PE-stamp workflow) are **completed in P7**. It is no longer a "stub for P3+"; the minimal shape is real and round-trips from P1.

```swift
public struct PermitMeta: Codable, Equatable {
    // --- P1 minimal (jurisdiction selectable + disclaimer acked before P3 sizing) ---
    public var jurisdictionId: String?       // CodePackage key (country + province/state)
    public var codeEdition: String?          // "IRC 2021", "BCBC 2024", etc.
    public var disclaimerAcknowledgedAt: Date?    // §6.2 gate — P1 minimal
    // --- P7 full ---
    public var setbacks: SetbackInput?       // site-plan / property-line overlay
    public var lastComplianceRunAt: Date?
    public var lastComplianceResult: ComplianceReport?   // cached audit/design result (§3.3)
    public var peStampRequest: PEStampRequest?           // engineer seal workflow (§3.5)
}
public struct SetbackInput: Codable, Equatable {
    public var propertyLines: [CGPoint]; public var requiredSetbackFeet: Double?; public var ahjVerified: Bool
}
public struct PEStampRequest: Codable, Equatable {
    public var requested: Bool; public var reason: String?; public var requestedAt: Date?
}
```

---

## 3. Engine catalog (exact pure-function signatures)

All engines live in `DeckKit/Sources/DeckKit/Engine/` (or `/Compliance/`). All are pure `enum`/`struct` namespaces with `static func`s — no stored state, no I/O. Every result struct carries **result + limiting check + cited code section + package edition** (§0.4). The shared result envelope:

> **Phase ownership:** `EngineOutcome<T>`, `EngineCitation`, `EngineAssumptions`, `SizedMember`, and `MemberSizingResult` are **introduced in P2** — P2 is their first consumer via `FramingMember.sizing: MemberSizingResult?` (it sets `sizing = nil` everywhere, but the TYPES must exist for the schema to compile). P3+ engines (`StructuralSizingEngine`, `FootingEngine`, compliance) reuse them and fill `sizing`. The engine result structs that are P3-specific (`JoistSpanResult`/`BeamSizingResult`/`PostSizingResult`/`CantileverResult`/`PostReaction`) are introduced in P3.

```swift
/// Shared envelope every sizing/compliance engine returns. `limiting` names the
/// check that governed the result; `codeSection` cites the package rule; `edition`
/// stamps the CodePackage version in force (§6.6). `outOfEnvelope == true` is a
/// HARD STOP — the UI must show "requires a licensed engineer" and emit NO number (§6.5).
public struct EngineCitation: Codable, Equatable {
    public var limitingCheck: String      // e.g. "deflection L/360", "bearing 1.5\" wood"
    public var codeSection: String        // e.g. "IRC R507.6", "AWC DCA6 Table 4", "BCBC 9.12.2.2"
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
```

### 3.1 `StructuralSizingEngine` (P3)

```swift
public enum StructuralSizingEngine {
    // Joist: allowable span given size/species/spacing/load, with deflection check.
    public static func joistSpan(
        size: LumberSize, species: WoodSpecies, grade: LumberGrade,
        spacingInchesOC: Double, load: LoadPreset, package: CodePackage
    ) -> EngineOutcome<JoistSpanResult>

    // Beam: back-solve size + max post spacing for a given tributary width + span.
    public static func beamSizing(
        tributaryWidthFeet: Double, beamSpanFeet: Double,
        species: WoodSpecies, grade: LumberGrade, load: LoadPreset, package: CodePackage
    ) -> EngineOutcome<BeamSizingResult>

    // Post: size + max height for an applied axial load.
    public static func postSizing(
        axialLoadLb: Double, unbracedHeightFeet: Double,
        species: WoodSpecies, grade: LumberGrade, package: CodePackage
    ) -> EngineOutcome<PostSizingResult>

    // Tributary load -> per-post / per-beam reactions (IRC R507.1 / Table R301.5).
    public static func tributaryLoads(
        framing: FramingPlan, geometry: DeckDrawingData, load: LoadPreset
    ) -> [PostReaction]

    // Cantilever check (2021 adjacent-span limits, IRC R507.6).
    public static func cantilever(
        backspanFeet: Double, cantileverFeet: Double, joist: JoistSpanResult, package: CodePackage
    ) -> EngineOutcome<CantileverResult>

    /// Convenience: size every unlocked member in a FramingPlan, writing
    /// MemberSizingResult back. Locked members (manual editor) are untouched.
    public static func sizeAll(
        _ framing: FramingPlan, geometry: DeckDrawingData, package: CodePackage
    ) -> FramingPlan
}

public struct MemberSizingResult: Codable, Equatable {
    public var outcome: EngineOutcome<SizedMember>   // .outOfEnvelope -> PE hard stop
}
public struct SizedMember: Codable, Equatable {
    public var size: LumberSize; public var plyCount: Int
    public var allowableSpanFeet: Double; public var actualSpanFeet: Double; public var utilization: Double
}
public struct JoistSpanResult: Codable, Equatable { public var allowableSpanFeet: Double; public var deflectionRatio: String }
public struct BeamSizingResult: Codable, Equatable { public var size: LumberSize; public var plyCount: Int; public var maxPostSpacingFeet: Double }
public struct PostSizingResult: Codable, Equatable { public var size: LumberSize; public var maxHeightFeet: Double }
public struct CantileverResult: Codable, Equatable { public var allowedFeet: Double; public var ok: Bool }
public struct PostReaction: Codable, Equatable { public var footingOrPostId: String; public var reactionLb: Double; public var tributaryAreaSqFt: Double }
```

### 3.2 `FootingEngine` (P4)

```swift
public enum FootingEngine {
    /// Size a single footing from its post reaction + soil + frost + type.
    public static func sizeFooting(
        reactionLb: Double, soil: SoilInput, frost: FrostInput,
        type: FootingType, package: CodePackage
    ) -> EngineOutcome<FootingSizingResult>

    /// Concrete volume / bag takeoff for a sized footing.
    public static func concreteTakeoff(_ result: FootingSizingResult) -> ConcreteTakeoff

    /// Size every footing in a plan from the tributary reactions (P3 output).
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

### 3.3 `ComplianceEngine` (P7) — design-time check + as-built audit

One engine, two directions (build once, run both ways — roadmap §3).

```swift
public enum ComplianceEngine {
    public enum Mode: String, Codable { case design, asBuilt }

    /// Evaluate a design (or as-built capture) against the selected package.
    /// In .asBuilt mode, hidden elements are tagged .notAssessable (§6.7).
    public static func evaluate(
        _ data: DeckDrawingData, mode: Mode, package: CodePackage
    ) -> ComplianceReport
}

public struct ComplianceReport: Codable, Equatable {
    public var mode: ComplianceEngine.Mode
    public var packageEdition: String
    public var generatedAt: Date
    public var findings: [ComplianceFinding]
    /// LOCKED COPY (§6.1): when findings has no .fail in assessable items, this
    /// reads EXACTLY "no code failures detected" — NEVER "safe"/"compliant"/"will pass".
    public var summaryStatement: String
    public var disclaimer: String        // §6.2 verbatim
}
public struct ComplianceFinding: Codable, Equatable, Identifiable {
    public let id: String
    public var item: String              // "Guard height", "Stair rise uniformity", "Ledger fasteners"
    public var severity: Severity        // safetyHazard|marginal|minor|notAssessable
    public var currentValue: String?     // measured/entered (nil when not assessable)
    public var targetValue: String?      // code value
    public var codeSection: String
    public var fix: String?
    public var confidence: Confidence    // high|medium|low (photo-assisted near threshold)
    public var evidence: Evidence?       // photo / 3D ref
    public var source: FindingSource     // measured|userEntered|notAssessable
}
public enum Severity: String, Codable { case safetyHazard, marginal, minor, notAssessable }
public enum Confidence: String, Codable { case high, medium, low }
public enum FindingSource: String, Codable { case measured, userEntered, notAssessable }
public struct Evidence: Codable, Equatable { public var photoURL: URL?; public var sceneRef: String? }
```

### 3.4 Code-package format + `CodePackageLoader`

The package is **data** (§0.5). Ingested verbatim from the adopted edition's actual tables; versioned; jurisdiction-keyed; stored in Supabase, delivered via ops-web, cached offline.

```swift
public struct CodePackage: Codable, Equatable, Sendable {
    public var jurisdictionId: String            // "US-IRC", "CA-BC", "CA-AB", ...
    public var edition: String                   // "IRC 2021 / DCA6-12", "BCBC 2024 Part 9"
    public var publishedDate: Date               // stamps reports "code data current to [date]"
    public var unitSystem: PackageUnits          // imperial (psf) | metric (kPa)
    public var joistSpanTable: SpanTable
    public var beamSpanTable: SpanTable
    public var postHeightTable: PostTable
    public var footingTable: FootingTable
    public var cantileverRules: CantileverRules
    public var guardRules: GuardRules            // R312: 36" guard, 30" trigger, 4" opening
    public var stairRules: StairRules            // R311.7: 7.75" rise / 10" run / handrail
    public var ledgerRules: LedgerRules          // R507.9
    public var presumptiveSoilPSF: Double        // R401.4 default (or kPa)
    public var envelopeLimits: EnvelopeLimits    // out-of-envelope hard-stop thresholds (§6.5)
}
public enum PackageUnits: String, Codable, Sendable { case imperial, metric }
// SpanTable/PostTable/FootingTable/etc. are plain Codable lookup structs:
//   public struct SpanTable: Codable, Equatable, Sendable {
//       public var rows: [SpanRow]   // { size, species, grade, spacingOC, liveLoad, allowableSpanInches }
//       func lookup(...) -> SpanRow?
//   }
// EnvelopeLimits e.g. maxTributarySqFt, minSoilPSF (1500 / 75 kPa), maxPostHeightFeet,
// maxSpanInTable — exceeding any -> EngineOutcome.outOfEnvelope.
```

`CodePackageLoader` protocol signature: see §1.3. **Phase plans must not invent a parallel loader** — engines receive a `CodePackage` value; the loader hands it to them.

### 3.5 Drafting / plan-set engine (P7)

Purpose-built; **does NOT extend `DeckShareRenderer`** (that 2-page marketing artifact stays the LIGHT deliverable — roadmap §6). PDFKit/Core Graphics, on-device.

```swift
public enum PlanSetEngine {
    /// Render a multi-sheet permit plan set to a single PDF.
    public static func renderPermitSet(
        _ data: DeckDrawingData, compliance: ComplianceReport,
        sheets: [PlanSheetKind], titleBlock: TitleBlock, package: CodePackage
    ) -> Data   // PDF bytes

    /// Single dimensioned, to-scale sheet (plan/framing/elevation/section/site/detail).
    public static func renderSheet(
        _ kind: PlanSheetKind, data: DeckDrawingData, scale: DrawingScale, titleBlock: TitleBlock
    ) -> Data

    /// Structural calc report (engineer-reviewable; per-member output, DCA6 style).
    public static func renderCalcReport(_ framing: FramingPlan, footings: FootingPlan, package: CodePackage) -> Data
}
public enum PlanSheetKind: String, Codable, CaseIterable {
    case planView, framingPlan, elevation, crossSection, sitePlan, detailCallout
}
public struct TitleBlock: Codable, Equatable {
    public var projectName: String; public var address: String?
    public var packageEdition: String; public var generatedDate: Date
    public var disclaimer: String              // §6.2 stamped on every sheet
    public var peStamp: PEStampRequest?
}
public struct DrawingScale: Codable, Equatable { public var inchesPerFoot: Double }   // e.g. 1/4" = 1'
```

### 3.6 Existing engines (carry forward unchanged, generalized later)

- `StairCalculator.calculate(totalRise:width:risePerStep:runPerTread:treadCountOverride:) -> StairSpec` — **the precedent; signature unchanged.** P6 advanced stairs add tread types / stringer sizing / landings *around* it, not by changing it.
- `VinylCutListEngine.makePlan(surfaces:settings:availableOffcuts:) -> VinylCutPlan` — unchanged. P6 board-nesting optimizer **generalizes** this to all board families (new `BoardNestingEngine` reusing the same offcut/lane internals; vinyl path untouched).
- `EstimateGeneratorService.generateLineItems(from:) -> [GeneratedLineItem]` — P1 threads `WasteSettings` through the area-takeoff path (the waste fix). P2+ feed framing/fastener/finish takeoff in as new categories.
- `ComponentEmitter.emit(_:) -> [DesignComponentRow]` — unchanged; new component types (`joist`, `beam`, `post`, `footing`, `pattern`) are **additive** rows (renaming an existing `component_type` is a contract break — see the doc comment in `ComponentEmitter.swift`).
- `DeckTemplateEngine.generate(template:dimensions:config:) -> DeckDrawingData?` — unchanged; the auto-framing engine mirrors its **auto-then-preserve** pattern (`FramingSource.autoThenEdited`, `FramingMember.locked`).
- `SurfaceDetector.detect(vertices:edges:) -> [DetectedSurface]` — unchanged; the substrate framing/pattern engines build on.

---

## 4. LIGHT / FULL capability-flag mechanism

**One schema, capability-gated *rendering* and *engine exposure* — never capability-gated data (§0.2, roadmap §6).** The line is *compliance*: LIGHT may visualize + price; the instant the app asserts a member size, span, footing dimension, code pass, or permit-readiness, that is FULL.

```swift
// DeckKit/Sources/DeckKit/Capability/DeckCapabilities.swift
public struct DeckCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    // Shared (BOTH tiers)
    public static let drawing        = DeckCapabilities(rawValue: 1 << 0)  // 2D/AR/sketch/multi-level
    public static let materials      = DeckCapabilities(rawValue: 1 << 1)  // catalog + assignment
    public static let vinylCutList   = DeckCapabilities(rawValue: 1 << 2)
    public static let wasteFactor    = DeckCapabilities(rawValue: 1 << 3)  // P1 single-% (BOTH)
    public static let plausibleFrame = DeckCapabilities(rawValue: 1 << 4)  // P2 visual frame, NO code claim
    public static let groundCover    = DeckCapabilities(rawValue: 1 << 5)
    public static let shareRender    = DeckCapabilities(rawValue: 1 << 6)  // DeckShareRenderer + proposal

    // FULL-only (engineering = compliance line)
    public static let structuralSizing = DeckCapabilities(rawValue: 1 << 10) // P3
    public static let loadCalc          = DeckCapabilities(rawValue: 1 << 11)
    public static let footingEngine     = DeckCapabilities(rawValue: 1 << 12) // P4
    public static let terrainGrade      = DeckCapabilities(rawValue: 1 << 13)
    public static let houseOpenings     = DeckCapabilities(rawValue: 1 << 14) // P5
    public static let surfacePatterns   = DeckCapabilities(rawValue: 1 << 15) // P6
    public static let overhead          = DeckCapabilities(rawValue: 1 << 16)
    public static let compliance        = DeckCapabilities(rawValue: 1 << 17) // P7 engine + as-built audit
    public static let permitPlanSet     = DeckCapabilities(rawValue: 1 << 18)
    public static let peStamp           = DeckCapabilities(rawValue: 1 << 19)

    public static let light: DeckCapabilities = [
        .drawing, .materials, .vinylCutList, .wasteFactor, .plausibleFrame, .groundCover, .shareRender
    ]
    public static let full: DeckCapabilities = {
        var c: DeckCapabilities = .light
        c.formUnion([.structuralSizing, .loadCalc, .footingEngine, .terrainGrade,
                     .houseOpenings, .surfacePatterns, .overhead, .compliance,
                     .permitPlanSet, .peStamp])
        return c
    }()
}

// Injected at the DeckKit boundary (env value / VM init param). The OPS app
// supplies `.light`; the OPS Decks app supplies `.full` (gated further by the
// RevenueCat `deck_pro` entitlement for the saved-deck cap — spec §6).
public protocol CapabilityProvider: Sendable {
    var capabilities: DeckCapabilities { get }
}
```

**Rules every phase obeys:**
- A surface (tab/sheet/toolbar entry) for a FULL feature is **hidden** (not disabled-with-lock) when its capability is absent — except a single, tasteful "available in OPS Decks Pro / standalone" upsell stub (roadmap allows one entry point).
- An **engine is never invoked** without its capability; LIGHT physically cannot produce a sizing/footing/compliance number. (`plausibleFrame` derives geometry only — `FramingMember.sizing` stays `nil` in LIGHT.)
- Data is **always preserved** regardless of capability (§1.4 passthrough). A LIGHT build opening a FULL design renders what it understands, edits what it can, and round-trips the rest untouched.
- Capability is **runtime**, decoupled from schema `version`. A v7 design opens in a `.light` build; the build reads the blocks its capabilities cover and preserves the rest.

---

## 5. Naming conventions + testing strategy

### 5.1 Naming
- **Module prefixes:** types public from DeckKit are unprefixed domain nouns (`FramingPlan`, `FootingEngine`) — the module *is* the namespace. App-side seam impls are prefixed by app (`OPSDeckStore`, `DecksAppDeckStore`).
- **Engines:** `enum` namespace + `static func`; pure; verb-first methods (`joistSpan`, `sizeFooting`, `evaluate`, `renderPermitSet`).
- **Schema blocks:** noun `Plan`/`Model`/`Meta` (`FramingPlan`, `TerrainModel`, `PermitMeta`); members are `Identifiable` with `let id: String` (UUID string, matches existing `DeckVertex`/`DeckEdge`).
- **Enums:** `String`-raw + `CaseIterable`; raw values snake_case where multi-word (`"house_edge"`, matches existing `EdgeType`). **Never remove or rename a shipped case** (additive-only — see `BuiltInMaterial` doc comment).
- **Units:** dimensions in **inches** unless the property name says otherwise (`Feet`, `PSF`, `Degrees`, `SqFt`) — matches existing `StairConfig.totalRiseInches`, `RailingConfig.postHeight`. Metric jurisdictions convert at the engine boundary via `CodePackage.unitSystem`.
- **Numbers in UI:** JetBrains Mono, tabular, formatted; empty state `—` (CLAUDE.md). Engine results are raw `Double`; formatting happens in views.

### 5.2 Testing
- **Pure engines → unit tests**, table-driven. Test target compiles + runs on the **simulator destination** per `OPS/CLAUDE.md`: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` (`build-for-testing` to verify compile, `test` to run). Device-target build verification uses `-destination 'generic/platform=iOS'`. (Copy `Secrets.xcconfig` into any worktree first.)
- **Code tables as data fixtures:** each `CodePackage` ships a checked-in test fixture (JSON) with a *known* subset of the real edition's table cells; sizing/footing/compliance tests assert against hand-computed expected values + the cited section. **Never hand-type table cells into UI** (§0.5) — fixtures are the test mirror of the production package.
- **Date brittleness:** any test touching schedule/elevation math anchors off computed dates, never literals (memory: `ios-autoschedule-tests-date-brittleness`).
- **Snapshot harness:** 3D/2D render + plan-set output verified via the `ImageRenderer → XCTAttachment` harness (memory: `ops-ios-swiftui-snapshot-harness`); interactive visual QA stays a human step.
- **Round-trip tests (mandatory, every phase):** (1) encode→decode→encode is stable; (2) a FULL-authored JSON decoded by a `.light` capability build re-encodes **without dropping** any FULL block (§1.4); (3) a malformed/unknown sub-block decodes to `nil` without failing the whole-design decode (§0.2).
- **`xcodebuild` exit-code gotcha:** background builds report the trailing echo's exit code, not the build's — grep the log for `BUILD SUCCEEDED` / `TEST SUCCEEDED` (memory: `xcodebuild-exit-code-masking`).
- **Worktree SourceKit lag:** "Cannot find type X" in fresh worktrees/newly-written files is index noise — trust `xcodebuild` (memory: `ops-ios-worktree-sourcekit-lag`).

---

## 6. Compliance liability rules (LOCKED 2026-06-24 — shared constraint)

Every compliance-touching phase (P3 sizing, P4 footings, P7 compliance/audit/permit) obeys these. From roadmap §7; reproduced here as the binding contract:

1. **Objective negative claims only.** The app flags what *objectively fails* the selected jurisdiction's code and reports **exactly** `"no code failures detected"` when it finds none in assessable items. It NEVER emits "safe," "compliant," "guaranteed," or "will pass." (`ComplianceReport.summaryStatement` is the single sanctioned output string; tests assert it is one of the locked phrasings.)
2. **Disclaimer on every compliance/structural output**, acknowledged in-app before generation: *"This is not a guarantee of full code adherence. Have plans reviewed by a licensed engineer in your jurisdiction."* (`PermitMeta.disclaimerAcknowledgedAt` gates; `TitleBlock.disclaimer` + `ComplianceReport.disclaimer` stamp it.)
3. **Jurisdiction selection drives the ruleset.** User picks country + province/state; engines evaluate *that* `CodePackage`. IRC/DCA6 (US, psf) vs NBC/BCBC Part 9 (Canada, kPa). Frost/setbacks are AHJ-delegated — any bundled table is "verify with your AHJ."
4. **Downloadable, versioned packages** (§3.4): code rules are data, Supabase-stored, ops-web-delivered, offline-cached → push code-revision updates **without an App Store release**; stamp every report **"code data current to [edition/date]"** (`CodePackage.publishedDate`).
5. **Out-of-envelope = hard stop.** Exceeding any `EnvelopeLimits` threshold (tributary/area, soil < 1500 psf / < 75 kPa, unusual/elevated geometry) returns `EngineOutcome.outOfEnvelope` → UI shows "requires a licensed engineer," emits **no number**. The PE-stamp workflow (`PEStampRequest`) makes explicit the app never self-certifies.
6. **Every structural/footing output surfaces its assumptions** — assumed load, species, soil, and the code-package edition in force (`EngineAssumptions` rides every `EngineOutcome.ok`).
7. **As-built audit never outputs a clean pass.** Hidden elements (footing depth/size, concealed ledger fasteners/lateral connectors) are tagged `severity: .notAssessable` / `source: .notAssessable` ("verify on site"). The report never implies the app saw something it can't.
8. **Tables ingested verbatim, versioned, treated as data** — built from the adopted edition's actual tables, not transcribed cell-by-cell from research. IRC Appendix H (overhead-structure code) is paywalled/unverified — no roof-cover compliance claims against it until the text is validated (roadmap §8).

---

## 7. Phase → contract mapping (quick index for plan authors)

| Phase | Adds to schema (§2) | New engines (§3) | Capabilities (§4) | Liability (§6) |
|---|---|---|---|---|
| **P1** | `schemaVersion`, `WasteSettings`, `unknownBlocks` passthrough, `PermitMeta` (minimal), brand-neutral catalog model | — (waste threaded into `EstimateGeneratorService`); `CodePackageLoader` **stub**; `DeckStore`/`ImageUploader`/`OCRService` seams + impls | `.light` (OPS) / base `.full` shell (Decks) | jurisdiction *selectable* groundwork |
| **P2** | `FramingPlan` (members, `sizing == nil`) | auto-framing (mirrors `DeckTemplateEngine` auto-then-preserve) | `.plausibleFrame`, `.groundCover` (BOTH) | none (no claim) |
| **P3** | fills `FramingMember.sizing`; reads `PermitMeta.jurisdictionId` | `StructuralSizingEngine`; real `CodePackageLoader` + `CodePackage` | `.structuralSizing`, `.loadCalc` (FULL) | §6.1,2,3,4,5,6 |
| **P4** | `FootingPlan`, `TerrainModel` | `FootingEngine` | `.footingEngine`, `.terrainGrade` (FULL) | §6.3,4,5,6 |
| **P5** | `HouseModel` | (drafting elevation prep) | `.houseOpenings` (FULL) | §6.2 (ledger detail) |
| **P6** | `SurfaceFeaturePlan`, `OverheadStructurePlan` | `BoardNestingEngine` (generalizes `VinylCutListEngine`); overhead reuses `StructuralSizingEngine` | `.surfacePatterns`, `.overhead` (FULL) | §6.8 (App. H caution) |
| **P7** | completes `PermitMeta` (compliance result, setbacks, PE stamp) | `ComplianceEngine` (design + as-built), `PlanSetEngine` | `.compliance`, `.permitPlanSet`, `.peStamp` (FULL) | ALL of §6 |

---

## 8. Hard rules summary (do-not-violate checklist for every phase plan)

1. New schema = **one optional top-level property** on `DeckDrawingData`, `decodeIfPresent` + default, bump `DeckDesign.version`. Never rename/remove a shipped field, enum case, or `component_type`.
2. Unknown/failed sub-block **decodes to nil + is preserved on re-encode** (`unknownBlocks` passthrough). Round-trip tests mandatory.
3. Engines are **pure, table-driven, offline**; return `EngineOutcome` carrying result + limiting check + cited section + assumptions + package edition.
4. **Code rules are data** in a `CodePackage`; engines never hard-code cells; loaded via `CodePackageLoader`.
5. DeckKit touches the host app **only** through `companyId`/`projectId` primitives + `DeckStore`/`ImageUploader`/`OCRService`/`CodePackageLoader` + `CapabilityProvider`. No `Project`/`Company`/`AppState`/`SyncEngine`/`DataController`.
6. Capability gates **surfaces + engine invocation**, never data presence. LIGHT cannot emit a sizing/footing/compliance number.
7. Compliance output obeys **§6 verbatim**: objective-negative only, disclaimer-gated, jurisdiction-driven, out-of-envelope hard-stops to PE, assumptions surfaced, as-built never a clean pass.
8. Build verification: device `generic/platform=iOS`; tests on `iPhone 17, OS 26.5` sim. Grep logs for `SUCCEEDED`. Styling via `OPSStyle`/`OPSDesignKit` tokens — no hardcoded design values.
