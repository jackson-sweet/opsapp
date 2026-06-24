# OPS Decks — Phase 5: House Attachment & Openings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **HEADER NOTE — read first.** This plan is authored **before its predecessor phases (P1–P4) exist in code.** It therefore decomposes Phase 5 into the exact files, public types, and engine contracts mandated by the Architecture Contract (`docs/superpowers/plans/2026-06-24-ops-decks-architecture-contract.md`), but **the bite-sized TDD steps with literal, runnable Swift are finalized at phase start once predecessors exist.** Where the contract pins a type or signature, it is reproduced **verbatim** below and is binding. Where a step depends on a P1–P4 type whose *body* is not yet written (e.g. `DeckKit`'s `unknownBlocks` passthrough, `CapabilityProvider` injection point, the elevation/terrain datum from P4), the step states the dependency and the assertion it must satisfy, and leaves the literal call site to be filled at execution time against the real predecessor signature. **Do not fabricate predecessor signatures beyond what the contract fixes.**

**Goal:** Add the house wall as a real modeled object — floor-line datum + per-story heights, door/window placement & sizing, wall-opening cutouts in 2D and 3D, cladding-driven ledger strategy (brick/stone → freestanding fallback that generates a house-side beam line reusing Phase 4 footings/framing), a front-on elevation drawing view, a door/window schedule with plan callouts, and multi-story decks with stairs to grade — all as one additive `HouseModel` block on `DeckDrawingData`, FULL-tier capability-gated, round-trip-preserving for LIGHT.

**Architecture:** One new optional top-level property `house: HouseModel?` on `DeckDrawingData` (schema version 5), following the existing defensive-`init(from:)` + `decodeIfPresent` pattern verbatim. Pure, offline, table-free geometry engines in `DeckKit/Sources/DeckKit/Engine/` (`WallOpeningGeometry`, `HouseElevationProjector`, `LedgerStrategyEngine`, `StairsToGradeEngine`); rendering grows the existing `DeckSceneBuilder.buildHouseWall` (3D cutout) and a new `HouseElevationRenderer` (2D ortho). All FULL-only surfaces are hidden behind `DeckCapabilities.houseOpenings`; LIGHT preserves the block untouched via the P1 `unknownBlocks` passthrough. The ledger detail consumes — never re-implements — the Phase 4 footing/beam-line machinery: brick/stone cladding flips `LedgerDetail.attachmentAllowed = false` and the engine emits a freestanding house-side beam line for the Phase 4 `FootingEngine`/`FramingPlan` to size.

**Tech Stack:** Swift 5.10 / Swift Concurrency (`Sendable`), SwiftData (`DeckDesign` blob persistence), SceneKit (3D cutout via `SCNShape`/`SCNGeometry`), Core Graphics + `UIGraphicsImageRenderer`/PDFKit (2D elevation + schedule), `OPSStyle`/`OPSDesignKit` tokens, XCTest table-driven engine tests + the `ImageRenderer → XCTAttachment` snapshot harness. Build verification: device `xcodebuild -scheme OPS -destination 'generic/platform=iOS'`; tests on `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`. Grep build logs for `BUILD SUCCEEDED` / `TEST SUCCEEDED` (background-build exit codes are unreliable). Copy `OPS/Utilities/Secrets.xcconfig` into any worktree before testing.

---

## How Phase 5 sits in the contract

| Contract anchor | Phase 5 obligation |
|---|---|
| §2.2 additive-block rule | Add exactly **one** new top-level optional property `house: HouseModel?` to `DeckDrawingData`; wire `CodingKeys` + `init(from:)` with `decodeIfPresent`; bump `DeckDesign.version` to **5**. |
| §2.6 | `HouseModel`, `WallOpening`, `OpeningKind`, `LedgerDetail` defined **verbatim** as below — no field renames, no enum-case removal. |
| §0.2 / §1.4 | A `.light` build must decode a Phase-5 design with `house == nil` (capability absent → block not parsed into editable state) **and re-encode it without dropping the `house` block** (P1 `unknownBlocks` passthrough). Round-trip tests mandatory (§5.2). |
| §4 | All P5 surfaces + the elevation/schedule/cutout editors are gated behind `DeckCapabilities.houseOpenings` (bit `1 << 14`). LIGHT hides them; the engines are never invoked in LIGHT. |
| §6.2 | The ledger-attachment detail is a **compliance-touching** surface (IRC R507.9). It carries the §6.2 disclaimer and makes **only objective-negative claims** ("attachment to brick/stone cladding is not a code-recognized ledger condition" → freestanding fallback), never "safe"/"compliant". No span/sizing number is asserted here — sizing belongs to P3/P4 engines this phase **feeds**, not duplicates. |
| §0.7 / §5 | DeckKit touches the host only through primitives + the four seams; no `Project`/`Company`/`AppState`. Units in **inches** unless the name says `Feet`/`Degrees`. Members are `Identifiable` with `let id: String`. Enums are `String`-raw + `CaseIterable`, snake_case multiword raw values, additive-only. |
| §7 mapping | P5 adds `HouseModel`; new engines do drafting/elevation prep + ledger strategy; capability `.houseOpenings` (FULL); liability §6.2. |

---

## Dependencies on earlier phases (consumed, never redefined)

Phase 5 **consumes** these predecessor types. Their full signatures are fixed by the contract; their *bodies* land in P1–P4. Where a body is not yet written, the step names the dependency and the behavior it relies on.

| From | Type / surface | How P5 uses it |
|---|---|---|
| **Existing (baseline, today)** | `DeckEdge { id, startVertexId, endVertexId, edgeType: EdgeType, dimension, houseEdgeMaterial: HouseEdgeMaterial?, … }` (`Models/DeckGeometry.swift:166`) | `WallOpening.edgeId` references a `houseEdge`. `LedgerDetail.cladding` reads the edge's `houseEdgeMaterial`. |
| **Existing** | `EdgeType.houseEdge = "house_edge"` (`DeckGeometry.swift:262`) | The only edge kind an opening / ledger attaches to. |
| **Existing** | `HouseEdgeMaterial { stucco, hardie, woodVertical, brick, stone, vinyl, parapet }` (`DeckGeometry.swift:272`) | Drives `LedgerStrategyEngine` (brick/stone → freestanding). **Do not add cases**; consume as-is. |
| **Existing** | `DeckLevel { id, vertices, edges, elevation: Double?, … }`, `LevelConnection { upperLevelId, lowerLevelId, stairConfig: StairConfig, … }` (`Models/DeckLevel.swift`) | Multi-story: a level whose `elevation` sits at an upper floor needs stairs **to grade** (not just level-to-level). |
| **Existing** | `StairCalculator.calculate(totalRise:width:risePerStep:runPerTread:treadCountOverride:) -> StairSpec` (`Engine/StairCalculator.swift`) | `StairsToGradeEngine` calls it **unchanged** to size the run from floor datum to grade. |
| **Existing** | `DeckSceneBuilder.buildHouseWall(parent:start:end:deckElevationM:maxHeightM:material:)` (`3D/DeckSceneBuilder.swift:1177`) | Extended to punch opening cutouts; not replaced. |
| **Existing** | `DeckDrawingData` blob + `toJSON()`/`fromJSON()`, defensive `init(from:)` pattern (`DeckGeometry.swift:696`) | `house` block added here. |
| **Existing** | `DesignComponentRow { componentType: String, metadata: [String: AnyCodable] }` + `ComponentEmitter.emit` (`Engine/ComponentEmitter.swift:31,322`) | New **additive** component rows: `door`, `window`, `ledger`, `freestanding_beam_line`. Never rename a shipped `component_type`. |
| **P1** | `DeckCapabilities` OptionSet incl. `.houseOpenings = 1 << 14`; `CapabilityProvider { var capabilities }`; injected at DeckKit boundary (env value / VM init param). | Gates every P5 surface + engine invocation. |
| **P1** | `unknownBlocks: [String: AnyCodable]?` passthrough on `DeckDrawingData`; `AnyCodable` extended to nested objects/arrays. | Guarantees a LIGHT build round-trips the `house` block. **This is the backward-direction half of §1.4 — P5 depends on it existing; P5 does not build it.** |
| **P1** | `DeckDesign.version` is live (schema version). | Bumped to 5. |
| **P1** | `PermitMeta { jurisdictionId, codeEdition }` (minimal) + `EngineCitation`/`EngineOutcome`/`CodePackage`/`CodePackageLoader` stub. | Ledger detail's disclaimer + (optional) `ledgerRules` lookup keys off the active package edition. P5 does **not** require P3/P4 packages to be populated — it degrades to "no package selected" gracefully. |
| **P4** | `FootingPlan`, `Footing`, `FramingPlan`, `FramingMember { role: FramingRole, start, end, … }`, `FramingRole.beam`, `FootingEngine.sizeAll`, `StructuralSizingEngine.tributaryLoads`. | The freestanding-fallback ledger emits a **house-side beam line** as `FramingMember`s (role `.beam`) + perimeter `Footing`s that P4 engines then size. P5 **produces the geometry**, P4 **sizes it**. If P4 is not yet present at execution, the beam-line geometry is still emitted and the sizing call is wired behind `#if`/availability per the real P4 signature. |
| **P2** | `FramingPlan` block lives on `DeckDrawingData.framing`. | The fallback writes its house-side beam members into the existing per-level `FramingMemberSet`, not a parallel store. |

> **Worktree SourceKit caveat:** "Cannot find type X" on freshly-written files or in a worktree is index noise — trust `xcodebuild`, not the editor (memory `ops-ios-worktree-sourcekit-lag`).

---

## File Structure

All paths are inside the post-P1 layout `DeckKit/Sources/DeckKit/` (the carve-out relocated `OPS/DeckBuilder/*` and `OPS/DataModels/DeckDesign.swift` into the package). Until the P1 carve-out lands, mirror these under `OPS/DeckBuilder/` and relocate during execution — the relative submodule layout is identical.

### Create

| File | Responsibility (one line) |
|---|---|
| `DeckKit/Sources/DeckKit/Models/HouseModel.swift` | The `HouseModel` block + `WallOpening`, `OpeningKind`, `LedgerDetail` value types, each with the defensive `init(from:)` + `decodeIfPresent` pattern. |
| `DeckKit/Sources/DeckKit/Engine/WallOpeningGeometry.swift` | Pure: place/validate openings along a `houseEdge` (clamp to wall length, no overlap, sill/head within story height); produce 2D cutout rects + 3D cutout profiles. |
| `DeckKit/Sources/DeckKit/Engine/HouseElevationProjector.swift` | Pure: project the deck + house wall + openings + grade datum into a front-on orthographic 2D coordinate set per house edge (the math behind the elevation view; no drawing). |
| `DeckKit/Sources/DeckKit/Engine/LedgerStrategyEngine.swift` | Pure, compliance-touching (§6.2 objective-negative only): from cladding + package, decide ledger attachment vs freestanding fallback; when freestanding, emit the house-side beam-line `FramingMember`s + perimeter `Footing` anchors for P4 to size. |
| `DeckKit/Sources/DeckKit/Engine/StairsToGradeEngine.swift` | Pure: for a multi-story / elevated deck, compute total rise from floor-line datum to grade and produce the stairs-to-grade spec via `StairCalculator` (unchanged) + landing insertion when a single flight exceeds the code single-rise limit. |
| `DeckKit/Sources/DeckKit/Engine/HouseOpeningSchedule.swift` | Pure: build the door/window schedule rows (mark, kind, size, sill, count, callout tag) + stable callout-tag assignment (D1/D2/W1…) from `HouseModel.openings`. |
| `DeckKit/Sources/DeckKit/Rendering/HouseElevationRenderer.swift` | 2D Core Graphics renderer for the front-on elevation sheet (deck face, wall, openings, grade line, dimension strings, callout bubbles) consuming `HouseElevationProjector` output. |
| `DeckKit/Sources/DeckKit/Views/HouseModelSheet.swift` | FULL-only editor: set floor-line datum + story heights for the selected house edge / level. Gated by `.houseOpenings`. |
| `DeckKit/Sources/DeckKit/Views/WallOpeningEditorView.swift` | FULL-only editor: add/move/size a door or window on a `houseEdge`; live 2D preview of the cutout + overlap/clamp validation. |
| `DeckKit/Sources/DeckKit/Views/HouseElevationView.swift` | FULL-only screen hosting the elevation render (per house edge, swipe between faces) + the door/window schedule table. |
| `DeckKit/Sources/DeckKit/Views/LedgerDetailSheet.swift` | FULL-only: shows the ledger strategy result (attach vs freestanding-fallback), the §6.2 disclaimer, fastener-schedule/lateral-connector callout fields. |
| `DeckKit/Sources/DeckKit/Views/HouseOpeningScheduleView.swift` | FULL-only schedule table component (reused in `HouseElevationView` + the eventual P7 plan set). |
| `DeckKit/Tests/DeckKitTests/HouseModelCodableTests.swift` | Round-trip + backward-decode + malformed-sub-block tests for the `house` block (§5.2 mandatory three). |
| `DeckKit/Tests/DeckKitTests/WallOpeningGeometryTests.swift` | Table-driven placement/clamp/overlap/cutout-rect assertions. |
| `DeckKit/Tests/DeckKitTests/HouseElevationProjectorTests.swift` | Ortho-projection coordinate assertions (deck face, opening rects, grade datum) for known geometries. |
| `DeckKit/Tests/DeckKitTests/LedgerStrategyEngineTests.swift` | Cladding → attach/freestanding decision; freestanding emits correct beam-line members + footings; objective-negative copy assertion. |
| `DeckKit/Tests/DeckKitTests/StairsToGradeEngineTests.swift` | Total-rise-to-grade + landing insertion; `StairCalculator` reuse; date-free, geometry-anchored. |
| `DeckKit/Tests/DeckKitTests/HouseOpeningScheduleTests.swift` | Callout-tag assignment stability + schedule row correctness. |
| `DeckKit/Tests/DeckKitTests/HouseElevationSnapshotTests.swift` | `ImageRenderer → XCTAttachment` snapshot of `HouseElevationRenderer` for visual QA. |

### Modify

| File | Change (one line) |
|---|---|
| `DeckKit/Sources/DeckKit/Models/DeckGeometry.swift:696` (`DeckDrawingData`) | Add `var house: HouseModel? = nil`; add `case house` to `CodingKeys`; decode with `decodeIfPresent` in `init(from:)`. |
| `DeckKit/Sources/DeckKit/Models/DeckDesign.swift` (post-carve-out) | Bump schema: new designs created in this build set `version = 5`; migration backfills `house == nil` on older blobs (no-op decode). |
| `DeckKit/Sources/DeckKit/3D/DeckSceneBuilder.swift:1177` (`buildHouseWall`) | Punch opening cutouts: replace the solid spanning box for a wall segment carrying openings with an `SCNShape` whose path subtracts each opening rect (door = full-height void to sill 0, window = void at sill..head). |
| `DeckKit/Sources/DeckKit/Engine/ComponentEmitter.swift:31` (`emit`) | Emit additive `door`, `window`, `ledger`, `freestanding_beam_line` component rows from `data.house` (gated so LIGHT, which has `house == nil` in editable state, simply emits none). |
| `DeckKit/Sources/DeckKit/Rendering/DeckRenderer.swift` | Add an opening overlay pass on the 2D plan view (door swing arc / window mullion glyph + callout tag on the house edge). |
| `DeckKit/Sources/DeckKit/Views/DeckToolbar.swift` + the FULL tool surface | Add capability-gated entry points: "House & openings", "Elevation", "Schedule" — hidden when `.houseOpenings` absent. |

---

## TASK GRAPH (execution order)

```
T1  HouseModel block + Codable (schema v5)            ← foundation; everything imports it
T2  Round-trip / backward-decode / malformed tests    ← §5.2 gate, runs against T1
T3  WallOpeningGeometry engine (place/validate/cutout) ← pure, no predecessors beyond baseline
T4  HouseElevationProjector engine (ortho math)        ← consumes T1 + baseline geometry
T5  LedgerStrategyEngine (attach vs freestanding)      ← consumes T1 + P4 framing/footing types
T6  StairsToGradeEngine (floor datum → grade)          ← consumes T1 + StairCalculator + DeckLevel
T7  HouseOpeningSchedule (rows + callout tags)         ← consumes T1
T8  3D cutout in DeckSceneBuilder.buildHouseWall       ← consumes T3
T9  HouseElevationRenderer (2D draw) + snapshot test   ← consumes T4 + T7
T10 ComponentEmitter additive rows                     ← consumes T1 + T5
T11 DeckRenderer plan-view opening overlay             ← consumes T1 + T7
T12 Editor views (HouseModel/WallOpening/Ledger)       ← consumes T1,T3,T5; capability-gated
T13 HouseElevationView + ScheduleView screens          ← consumes T9,T7; capability-gated
T14 Capability gating + toolbar entry points           ← consumes P1 CapabilityProvider
T15 Full-design integration + multi-story acceptance   ← consumes all
```

---

### Task 1: `HouseModel` schema block (verbatim contract types) + wire into `DeckDrawingData`

**Files:**
- Create: `DeckKit/Sources/DeckKit/Models/HouseModel.swift`
- Modify: `DeckKit/Sources/DeckKit/Models/DeckGeometry.swift:696` (`DeckDrawingData` — add property, CodingKey, decode)
- Modify: `DeckKit/Sources/DeckKit/Models/DeckDesign.swift` (`version = 5` for new designs)
- Test: `DeckKit/Tests/DeckKitTests/HouseModelCodableTests.swift` (Task 2)

**Interface (verbatim from contract §2.6 — binding, do not alter field names/order/raw values):**

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

> **Pattern obligation (§2.1):** every sub-struct gets a memberwise `public init(...)` **and** a defensive `public init(from decoder:)` that uses `decodeIfPresent(...) ?? default`. `storyHeights`/`openings` default to `[]`; `floorLineFeet`/`ledger` decode to `nil`. `WallOpening.id`/`edgeId`/`kind` decode (id/edgeId required, `kind` defaults to `.window`); numeric fields default to `0`. `LedgerDetail.cladding` defaults to `.stucco`, `attachmentAllowed` defaults to `true`, `lateralConnectors`/`fastenerSchedule` to `nil`. Mirror exactly the style at `DeckGeometry.swift:144` / `:239` / `:363`.

- [ ] **Step 1 — Write `HouseModel.swift` with the verbatim types + defensive Codable.** Reproduce the struct/enum block above. Add for each: a `public init` with defaulted args, and `public init(from decoder: Decoder) throws` matching the existing defensive pattern. `OpeningKind` already conforms `String, Codable, CaseIterable` — no custom decode needed. Add a `public var displayName: String` on `OpeningKind` (`patioDoor → "Patio door"`, `frenchDoor → "French door"`, `sliderDoor → "Sliding door"`, `window → "Window"`) — copy via `ops-copywriter` (sentence case, no exclamation).

- [ ] **Step 2 — Add the property to `DeckDrawingData`** at `DeckGeometry.swift:725` (after `components`):

```swift
    /// House-attachment model (Phase 5): floor-line datum + story heights, wall
    /// openings (doors/windows) + cladding-driven ledger strategy. Drives wall
    /// cutouts (2D/3D), the elevation view, and the door/window schedule.
    /// nil in LIGHT (capability `.houseOpenings` absent) — preserved untouched
    /// on re-encode via the P1 `unknownBlocks` passthrough (contract §1.4).
    public var house: HouseModel? = nil
```

- [ ] **Step 3 — Add `case house` to `DeckDrawingData.CodingKeys`** (`:739`) and decode it in `init(from:)` (`:757`):

```swift
        self.house = try c.decodeIfPresent(HouseModel.self, forKey: .house)
```

- [ ] **Step 4 — Bump `DeckDesign.version`.** New designs created in this build set `version = 5`. Confirm `fromJSON` does NOT down-version an opened blob (it never has — version lives on the SwiftData row, not in the blob; `schemaVersion` inside the blob is the P1 self-describing mirror). Set the constructor default per the real P1 `version` plumbing.

- [ ] **Step 5 — Build (device target).**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | grep -E 'BUILD SUCCEEDED|error:'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6 — Commit.**

```bash
git add DeckKit/Sources/DeckKit/Models/HouseModel.swift \
        DeckKit/Sources/DeckKit/Models/DeckGeometry.swift \
        DeckKit/Sources/DeckKit/Models/DeckDesign.swift
git commit -m "feat(decks-p5): add HouseModel block to drawing_data (schema v5)"
```

**Dependencies:** baseline `HouseEdgeMaterial`; P1 `version` plumbing + `unknownBlocks` (for the round-trip guarantee tested in T2).
**References:** contract §2.6, §2.1, §2.2; `DeckGeometry.swift:144/239/363/696`.
**Risks:** (a) forgetting the defensive `init(from:)` makes a partially-written blob throw and fail the whole-design decode — violates §0.2; T2 Step 3 catches it. (b) `CGPoint` is NOT used in `HouseModel` (openings are 1-D offsets along an edge), so no `CGPoint` Codable concern here. (c) The `public` access level is required because DeckKit is a package boundary — baseline types are currently internal; the P1 carve-out makes the consumed ones `public`. If P1 hasn't yet promoted `HouseEdgeMaterial` to `public`, this task is **blocked on P1** and must not lower `HouseModel` to internal to compensate.

---

### Task 2: Mandatory round-trip / backward-decode / malformed tests (§5.2 gate)

**Files:**
- Create: `DeckKit/Tests/DeckKitTests/HouseModelCodableTests.swift`

**Interface:** uses `DeckDrawingData.toJSON()` / `.fromJSON(_:)` (existing), a `.light`-capability decode path (P1 `CapabilityProvider`), and the P1 `unknownBlocks` passthrough.

**TEST STRATEGY (the three §5.2-mandated tests, plus block-level specifics):**

- **`test_house_block_roundtrips_stably()`** — build a `DeckDrawingData` with a populated `house` (floor datum 9.0 ft, two storyHeights, one `patioDoor` + one `window` on edge `"E1"`, a `LedgerDetail` with cladding `.brick`, `attachmentAllowed = false`, `lateralConnectors = 4`). Assert `fromJSON(d.toJSON())?.house == d.house` (Equatable). Then encode→decode→encode and assert the two JSON strings are byte-identical (`.sortedKeys` is already set in `toJSON`). Key assertion: **no field is dropped or reordered across two encode passes.**

- **`test_light_build_preserves_house_block_on_resave()`** — the §1.4 backward-direction guarantee. Take the FULL JSON from above. Decode it through the **`.light` capability path** (P1 supplies a way to construct/decode with capabilities; in `.light`, `house` is parsed into the `unknownBlocks` passthrough rather than the editable `house` property — *or* parsed-but-not-editable, per the real P1 mechanism). Re-encode. Assert the re-encoded JSON **still contains the entire `house` object** (parse it back as FULL and assert `roundTripped.house == original.house`). Key assertion: **a LIGHT build never strips the FULL `house` block on save.** (If P1's mechanism is "decode into `house` but never render/edit it" rather than `unknownBlocks`, this test asserts the same end-state via the FULL re-decode; the literal call site is filled at execution against P1.)

- **`test_malformed_house_subblock_decodes_to_nil_without_failing_whole_design()`** — craft a JSON where `house` is structurally present but corrupt (e.g. `"openings": "not-an-array"`, or `"floorLineFeet": "abc"`). Assert `DeckDrawingData.fromJSON(json)` returns a **non-nil** `DeckDrawingData` whose `vertices`/`edges` decoded fine and whose `house` is `nil` (block failed gracefully). Key assertion: **a bad `house` block must not nuke the whole-design decode** (§0.2). Because Swift's synthesized container decode throws on a single bad key, the defensive `init(from:)` must wrap the `house` decode in `try?`-equivalent (`decodeIfPresent` throws on type mismatch — so the `house` decode in `DeckDrawingData.init(from:)` must be `self.house = (try? c.decodeIfPresent(HouseModel.self, forKey: .house)) ?? nil`). **This adjusts Task 1 Step 3** to the `try?` form; update it.

- **`test_legacy_blob_without_house_decodes_with_nil_house()`** — decode a pre-P5 JSON (no `house` key). Assert `.house == nil` and all baseline fields intact. Forward-direction guarantee.

- [ ] **Step 1 — Write the four tests above** with concrete fixtures (inline JSON string literals for the malformed/legacy cases; programmatic `DeckDrawingData` construction for the round-trip case).
- [ ] **Step 2 — Run, expect FAIL** if Task 1 used `decodeIfPresent` without the `try?` wrapper (the malformed test fails). Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:DeckKitTests/HouseModelCodableTests 2>&1 | grep -E 'TEST SUCCEEDED|TEST FAILED|failed'`
- [ ] **Step 3 — Apply the `try?` wrapper fix** to `DeckDrawingData.init(from:)` for the `house` key (and confirm the same hardening exists for other optional blocks per P1's pattern).
- [ ] **Step 4 — Run, expect `TEST SUCCEEDED`.**
- [ ] **Step 5 — Commit.**

```bash
git add DeckKit/Tests/DeckKitTests/HouseModelCodableTests.swift DeckKit/Sources/DeckKit/Models/DeckGeometry.swift
git commit -m "test(decks-p5): house-block round-trip, light-preserve, malformed-safe decode"
```

**Dependencies:** T1; P1 `CapabilityProvider` + `unknownBlocks`.
**References:** contract §0.2, §1.4, §5.2.
**Risks:** the LIGHT-preserve test is the one most coupled to P1's exact passthrough mechanism — if P1 ships "decode-but-don't-edit" instead of `unknownBlocks`, the assertion (FULL re-decode equality) still holds; only the intermediate inspection changes. Do not weaken the assertion to "house is non-nil after light re-encode" — assert **field-level equality** with the original.

---

### Task 3: `WallOpeningGeometry` engine — placement, validation, cutout profiles

**Files:**
- Create: `DeckKit/Sources/DeckKit/Engine/WallOpeningGeometry.swift`
- Test: `DeckKit/Tests/DeckKitTests/WallOpeningGeometryTests.swift`

**Interface (pure `enum` namespace, contract §3 convention — units inches, all `Sendable`-safe value types):**

```swift
public enum WallOpeningGeometry {

    /// Validation outcome for placing/sizing one opening on a wall segment.
    public enum Validation: Equatable {
        case ok
        case clampedToWall(adjustedOffsetInches: Double)   // pushed inboard to fit
        case overlapsOpening(otherId: String)
        case headExceedsStory(headInches: Double, storyHeightInches: Double)
        case zeroOrNegativeSize
    }

    /// Real-world length (inches) of a houseEdge in this design's effective scale.
    public static func wallLengthInches(
        edge: DeckEdge, in data: DeckDrawingData
    ) -> Double

    /// Validate a single opening against its wall length, the story height, and
    /// the other openings already on the same edge. Pure; no mutation.
    public static func validate(
        _ opening: WallOpening,
        wallLengthInches: Double,
        storyHeightInches: Double,
        existing: [WallOpening]
    ) -> Validation

    /// Clamp an opening's offset so [offset, offset+width] fits within the wall,
    /// returning the adjusted opening (used by the editor on drag-end).
    public static func clamped(
        _ opening: WallOpening, wallLengthInches: Double
    ) -> WallOpening

    /// 2D cutout rect for a wall drawn left-to-right at origin, x along the wall,
    /// y up from the wall base (sill..head). Doors keep sill at 0.
    public static func cutoutRect2D(
        _ opening: WallOpening
    ) -> CGRect

    /// 3D cutout profile: the rectangle (in wall-plane coords, inches) to subtract
    /// from the wall face. Returns nil for openings that fail validation hard
    /// (zero size) so the renderer skips them rather than producing a degenerate hole.
    public static func cutoutProfile3D(
        _ opening: WallOpening, storyHeightInches: Double
    ) -> CGRect?
}
```

**TEST STRATEGY (table-driven; no dates, geometry literals only):**

- `test_wallLength_uses_effectiveScaleFactor()` — a `houseEdge` with `dimension == nil` falls back to canvas length × `effectiveScaleFactor`; one with `dimension == 96` returns `96`. Assert both. (Mirrors the baseline `effectiveScaleFactor` semantics at `DeckGeometry.swift:977`.)
- `test_validate_ok_when_fits()` — width 36, offset 24, wall 120, story 96, head (sill 0 + height 80) ≤ 96 → `.ok`.
- `test_validate_clamps_when_offset_pushes_past_wall_end()` — width 48, offset 90, wall 120 (90+48 = 138 > 120) → `.clampedToWall(adjustedOffsetInches: 72)` (120 − 48). Assert exact adjusted value.
- `test_validate_detects_overlap()` — existing opening at offset 24 width 36 (24..60); new at offset 50 width 30 (50..80) overlaps → `.overlapsOpening(otherId:)` naming the existing id.
- `test_validate_flags_head_exceeds_story()` — window sill 40, height 60 → head 100 > story 96 → `.headExceedsStory(headInches: 100, storyHeightInches: 96)`.
- `test_validate_zero_size()` — width 0 → `.zeroOrNegativeSize`.
- `test_clamped_pushes_inboard()` — returns an opening whose `offsetAlongEdgeInches + widthInches <= wallLengthInches`; assert clamped offset and that width is unchanged.
- `test_cutoutRect2D_door_sits_on_base()` — `patioDoor` height 80 sill 0 → rect `origin.y == 0`, `height == 80`.
- `test_cutoutRect2D_window_floats_at_sill()` — window sill 30 height 48 → rect `origin.y == 30`, `height == 48`, `origin.x == offsetAlongEdgeInches`.
- `test_cutoutProfile3D_nil_for_zero_size()` — width 0 → nil.

- [ ] **Step 1 — Write all tests above** with literal inputs/expected structs.
- [ ] **Step 2 — Run, expect FAIL** ("WallOpeningGeometry not found"). Run the `-only-testing:DeckKitTests/WallOpeningGeometryTests` invocation; grep for `TEST FAILED`.
- [ ] **Step 3 — Implement `WallOpeningGeometry`** to make tests pass. Overlap = interval-intersection on `[offset, offset+width]`. Clamp = `min(offset, wallLength − width)` floored at 0.
- [ ] **Step 4 — Run, expect `TEST SUCCEEDED`.**
- [ ] **Step 5 — Commit** (`feat(decks-p5): wall-opening placement/validation/cutout geometry engine`).

**Dependencies:** T1; baseline `DeckEdge`/`DeckDrawingData.effectiveScaleFactor`.
**References:** contract §3 (pure-engine convention), §5.1 (units inches). IRC R311.7 is *not* invoked here — this is geometry, not code-check; code-checking openings (egress sizing) is out of P5 scope and belongs to P7 if ever.
**Risks:** scale ambiguity — wall length must use the same `effectiveScaleFactor` the canvas uses or openings drift relative to the drawn wall. The `wallLengthInches` test pins this. Overlap must be exclusive at touching edges (offset 60 width X right after a 24..60 opening is OK, not overlap) — assert a touching-but-not-overlapping case.

---

### Task 4: `HouseElevationProjector` engine — front-on orthographic math

**Files:**
- Create: `DeckKit/Sources/DeckKit/Engine/HouseElevationProjector.swift`
- Test: `DeckKit/Tests/DeckKitTests/HouseElevationProjectorTests.swift`

**Interface (pure; produces a coordinate model the 2D renderer draws — separation of math from drawing, per §5.2 snapshot rule):**

```swift
public enum HouseElevationProjector {

    /// A front-on elevation of ONE house edge: everything projected into a 2D
    /// plane (x = distance along the wall in inches, y = height above grade in
    /// inches), ready for a renderer to scale to a sheet. No drawing here.
    public struct Elevation: Equatable {
        public var edgeId: String
        public var wallLengthInches: Double
        public var gradeYInches: Double          // always 0 (datum)
        public var deckSurfaceYInches: Double     // floorLine/elevation projected
        public var wallTopYInches: Double         // deckSurface + governing story height
        public var openings: [ProjectedOpening]
        public var storyLines: [Double]           // y of each floor line for multi-story
    }
    public struct ProjectedOpening: Equatable, Identifiable {
        public var id: String
        public var kind: OpeningKind
        public var rect: CGRect                   // x along wall, y above grade
        public var calloutTag: String             // D1/W1… (from HouseOpeningSchedule)
    }

    /// Project one house edge of the design into an elevation. `levelId` selects
    /// which level's deck surface height is the datum for multi-story designs;
    /// pass nil for single-level.
    public static func project(
        edgeId: String,
        levelId: String?,
        data: DeckDrawingData
    ) -> Elevation?

    /// All house edges that have a wall (edgeType == .houseEdge), each projected,
    /// for the swipe-between-faces elevation screen.
    public static func projectAllFaces(_ data: DeckDrawingData) -> [Elevation]
}
```

**TEST STRATEGY:**

- `test_project_returns_nil_for_non_house_edge()` — passing a `deckEdge` id → nil.
- `test_deck_surface_y_from_floorLine()` — `house.floorLineFeet = 9` → `deckSurfaceYInches == 108` (9 × 12). With `floorLineFeet == nil`, fall back to the level/`overallElevation` (feet) × 12; assert that fallback for a design with `overallElevation == 8` and `house.floorLineFeet == nil` → 96.
- `test_wall_top_y_uses_governing_story_height()` — `storyHeights == [9, 8]` (feet) → wall top above deck surface uses the first story height: `deckSurfaceY + 9*12`. Assert exact.
- `test_projected_opening_rect_offsets_above_grade()` — a window sill 30, height 48 on a wall whose deck surface is at y=108 → the opening rect's `y` is measured **above grade** (sill is relative to the floor line in the editor; projector adds the deck-surface datum): assert `rect.origin.y == 108 + 30 == 138`, `rect.height == 48`. (Pin the sill-reference convention here: `sillHeightInches` is above the **floor line**, so the projector adds `deckSurfaceYInches`. Document this on `WallOpening.sillHeightInches`.)
- `test_door_rect_sits_on_deck_surface()` — `patioDoor` sill 0 → `rect.origin.y == deckSurfaceYInches`.
- `test_storyLines_for_multistory()` — two storyHeights produce two `storyLines` y-values (deckSurface, deckSurface+story1).
- `test_callout_tags_match_schedule()` — projected openings carry the same `calloutTag` `HouseOpeningSchedule` assigns (cross-engine consistency; depends on T7 — order this test after T7 lands or stub the tag input).

- [ ] **Step 1 — Write tests** (geometry literals; no dates).
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement projector.** Pull wall length from `WallOpeningGeometry.wallLengthInches` (T3 reuse — DRY). Datum precedence: `house.floorLineFeet` → level `elevation` → `overallElevation` → 0, all ×12 to inches.
- [ ] **Step 4 — Run, expect `TEST SUCCEEDED`.**
- [ ] **Step 5 — Commit** (`feat(decks-p5): house elevation orthographic projector`).

**Dependencies:** T1, T3; baseline `DeckLevel.elevation`/`DeckDrawingData.overallElevation`. T7 for the callout-tag cross-check.
**References:** contract §3, §5.1; roadmap §2.4 "Elevation (front-on) drawing view" + §2.8 "Elevation drawings (front/rear/side to scale)".
**Risks:** the **sill reference frame** is the subtle correctness trap — `WallOpening.sillHeightInches` is above the floor line (per the contract field comment "0 for floor-level doors"), so the projector must add the deck-surface datum to put openings in grade-relative space. Pin this in T4 and reuse the same convention in T8 (3D) and T9 (2D render) — a mismatch puts the 3D cutout and the 2D elevation at different heights. The convention is asserted in `test_projected_opening_rect_offsets_above_grade`.

---

### Task 5: `LedgerStrategyEngine` — cladding-driven attach vs freestanding (compliance-touching, §6.2)

**Files:**
- Create: `DeckKit/Sources/DeckKit/Engine/LedgerStrategyEngine.swift`
- Test: `DeckKit/Tests/DeckKitTests/LedgerStrategyEngineTests.swift`

**Interface (pure; objective-negative copy only; emits geometry for P4 to size — never asserts a span/footing number itself):**

```swift
public enum LedgerStrategyEngine {

    public enum Strategy: Equatable {
        /// Ledger attachment is a code-recognized condition for this cladding.
        case attach(detail: LedgerDetail)
        /// Cladding (brick/stone) is NOT a recognized ledger-attachment substrate;
        /// fall back to a freestanding deck with a house-side beam line.
        case freestanding(detail: LedgerDetail, fallback: FreestandingFallback)
    }

    /// House-side beam line emitted when attachment isn't allowed. Geometry only:
    /// a beam member spanning the house edge + footing anchors at its ends/interior.
    /// P4's FootingEngine/StructuralSizingEngine SIZE these — this engine never does.
    public struct FreestandingFallback: Equatable {
        public var beamMembers: [FramingMember]   // role == .beam, along the house edge
        public var footingAnchors: [Footing]      // posts carrying the house-side beam
        /// Objective-negative, §6.1/§6.2 — exactly this phrasing class, never "safe".
        public var rationale: String
    }

    /// Decide the strategy for a houseEdge from its cladding (+ optional package
    /// ledger rules). `package == nil` ⇒ no jurisdiction selected yet: still make
    /// the brick/stone freestanding call (it's cladding-objective, not code-table
    /// dependent), but mark the detail's fastenerSchedule nil and surface the
    /// "select a jurisdiction" note in the rationale.
    public static func strategy(
        for edge: DeckEdge,
        houseSideBeamSpanInches: Double,
        package: CodePackage?
    ) -> Strategy

    /// Convenience: resolve the LedgerDetail to persist on HouseModel.ledger from
    /// the strategy (sets attachmentAllowed + cladding; leaves fastenerSchedule/
    /// lateralConnectors for the editor / P7 detail callout).
    public static func resolvedDetail(_ strategy: Strategy) -> LedgerDetail
}
```

**TEST STRATEGY:**

- `test_brick_cladding_forces_freestanding()` — edge `houseEdgeMaterial == .brick` → `.freestanding`, `detail.attachmentAllowed == false`, `detail.cladding == .brick`. Key assertion: brick never returns `.attach`.
- `test_stone_cladding_forces_freestanding()` — same for `.stone`.
- `test_woodVertical_allows_attach()` — `.woodVertical` → `.attach`, `attachmentAllowed == true`.
- `test_stucco_hardie_vinyl_allow_attach()` — table over `[.stucco, .hardie, .vinyl]` → all `.attach`.
- `test_parapet_is_freestanding()` — `.parapet` (a rooftop capped wall, not a house ledger substrate) → `.freestanding` (or `.attach` only if the package explicitly says so; default freestanding). Pin the decision: parapet ⇒ freestanding by default.
- `test_freestanding_emits_beam_along_house_edge()` — fallback `beamMembers` has ≥1 member with `role == .beam` whose `start`/`end` are the house edge's vertex positions; `footingAnchors` count ≥ 2 (both ends). Assert beam endpoints equal the edge vertices.
- `test_freestanding_footings_span_the_beam()` — for `houseSideBeamSpanInches == 144` (12 ft), interior footing count follows a conservative geometry rule (e.g. one interior pier when span > 96"); assert anchor count == 3 for 144". (This is a **geometry placement** rule, not a sizing claim — the actual max post spacing is P4's `StructuralSizingEngine.beamSizing`. P5 places conservative anchors; P4 may consolidate.)
- `test_rationale_is_objective_negative_only()` — assert `fallback.rationale` contains neither "safe", "compliant", "guaranteed", nor "will pass" (case-insensitive), and DOES read as an objective-negative claim (e.g. contains "not a code-recognized ledger" / "freestanding"). Lock the exact string via `ops-copywriter`; assert against the locked constant.
- `test_nil_package_still_decides_cladding_but_notes_jurisdiction()` — `package == nil`, brick → `.freestanding`, `detail.fastenerSchedule == nil`, rationale mentions selecting a jurisdiction.

- [ ] **Step 1 — Write tests.**
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement.** Decision table: `{stucco, hardie, vinyl, woodVertical} → attach`; `{brick, stone, parapet} → freestanding`. Beam line = a single `FramingMember(role: .beam, start: v0, end: v1)` along the edge; footing anchors at both vertices + one interior per `ceil(span/96")−1` (conservative). Set `rationale` from the locked objective-negative constant. **Do NOT size the beam or footing** — leave `nominalSize`/`sizing` nil for P4.
- [ ] **Step 4 — Run, expect `TEST SUCCEEDED`.**
- [ ] **Step 5 — Commit** (`feat(decks-p5): cladding-driven ledger strategy + freestanding beam-line fallback`).

**Dependencies:** T1; P4 `FramingMember`/`FramingRole.beam`/`Footing` (consumed as value types — if P4 not yet present, this task is **blocked on P4's structs landing**; the engine cannot emit `FramingMember`/`Footing` it cannot reference). P1 `CodePackage` (optional arg, nullable). Baseline `HouseEdgeMaterial`, `DeckEdge`.
**References:** contract §2.6 (`LedgerDetail`), §6.1/§6.2; roadmap §2.4 "Ledger attachment detail + code check per cladding; brick/stone → freestanding fallback"; IRC R507.9 (ledger), R507.9.2 (lateral connectors). NADRA: ~90% of deck collapses are ledger failures — this is the highest-liability surface in P5, hence the strict objective-negative test.
**Risks:** (a) **Scope creep into P4 sizing** — the strongest temptation is to emit a *sized* beam. Do not. The test suite asserts `nominalSize == nil` on emitted members. (b) `FramingMember.start/end` are `CGPoint` in canvas coords (contract §2.4) — beam endpoints must use the edge's vertex `position`, same coordinate space, so P4 sizing reads consistent geometry. (c) If P4's `Footing.position` is canvas-space (it is, per §2.5), anchor positions reuse vertex positions directly.

---

### Task 6: `StairsToGradeEngine` — floor datum → grade, landing insertion

**Files:**
- Create: `DeckKit/Sources/DeckKit/Engine/StairsToGradeEngine.swift`
- Test: `DeckKit/Tests/DeckKitTests/StairsToGradeEngineTests.swift`

**Interface (pure; wraps the unchanged `StairCalculator`, adds landings for tall runs):**

```swift
public enum StairsToGradeEngine {

    public struct GradeStairResult: Equatable {
        public var flights: [StairCalculator.StairSpec]   // one per flight (split by landings)
        public var landingCount: Int
        public var totalRiseInches: Double
        /// True when a single uninterrupted flight would exceed the configured
        /// max-rise-without-landing and the engine split it. Geometry, not a code pass.
        public var landingInserted: Bool
    }

    /// Total rise from a level's floor-line datum down to grade, then a stairs
    /// spec (possibly multi-flight with landings). Grade is the terrain datum
    /// (P4) when present, else 0. Uses StairCalculator unchanged for each flight.
    public static func stairsToGrade(
        levelId: String?,
        widthInches: Double,
        data: DeckDrawingData,
        maxRiseWithoutLandingInches: Double = 147   // 12'-3" default (split tall runs)
    ) -> GradeStairResult

    /// Total rise (inches) from the level's floor datum to grade for the given level.
    public static func totalRiseToGradeInches(levelId: String?, data: DeckDrawingData) -> Double
}
```

**TEST STRATEGY (geometry-anchored, no date literals — heed `ios-autoschedule-tests-date-brittleness`):**

- `test_totalRise_from_floorLine_to_zero_grade()` — `house.floorLineFeet = 10`, no terrain → `totalRiseToGradeInches == 120`.
- `test_totalRise_uses_level_elevation_when_no_floorLine()` — multi-level: target level `elevation == 8` ft, `house.floorLineFeet == nil` → 96.
- `test_single_flight_for_short_rise()` — rise 48" → `flights.count == 1`, `landingInserted == false`, and `flights[0]` equals `StairCalculator.calculate(totalRise: 48, width: ...)`.
- `test_landing_inserted_for_tall_rise()` — rise 180" (15 ft) > 147" → `landingInserted == true`, `flights.count == 2`, `landingCount == 1`; assert the two flights' `totalRise` sum to 180 (within rounding) and neither flight exceeds the max.
- `test_each_flight_uses_StairCalculator_unchanged()` — assert a flight's `treadCount`/`stringerLength` equal a direct `StairCalculator.calculate` call with the same per-flight rise/width (proves no re-implementation).
- `test_zero_rise_yields_no_flights()` — rise 0 → empty `flights`, `landingCount == 0`.

- [ ] **Step 1 — Write tests** computing expected per-flight specs by calling `StairCalculator.calculate` in the test itself (so the assertion tracks the real engine, not a hardcoded number).
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement.** `totalRise = datum`. If `totalRise <= max`, one flight via `StairCalculator.calculate`. Else split into `ceil(totalRise / max)` equal flights, `landingCount = flights − 1`, each flight sized via `StairCalculator.calculate`. Grade datum reads P4 `TerrainModel` when present (lowest `gradePoint.dropFeet` under the stair foot) else 0 — wire the P4 read behind availability; default 0 if P4 absent.
- [ ] **Step 4 — Run, expect `TEST SUCCEEDED`.**
- [ ] **Step 5 — Commit** (`feat(decks-p5): stairs-to-grade engine with landing insertion`).

**Dependencies:** T1; existing `StairCalculator`, `DeckLevel`; P4 `TerrainModel` (optional read — degrades to grade 0 if absent).
**References:** contract §3.6 ("`StairCalculator` … signature unchanged"); roadmap §2.4 "Multi-story deck at upper floor + stairs to grade"; IRC R311.7 (rise/run), R311.7.6 (landings). The `147"` (12'-3") split default is a conservative geometry threshold — the real code single-rise limit is jurisdiction-data (P3/P7); P5 uses a safe default and never claims compliance.
**Risks:** the landing-split default is geometry, not a code assertion — keep the doc comment explicit that it's a layout convenience, not a compliance check (avoids a §6 violation by implication). When P7's `ComplianceEngine` lands, it independently checks the run against the package; P5 must not pre-empt that with a "compliant" implication.

---

### Task 7: `HouseOpeningSchedule` — schedule rows + stable callout tags

**Files:**
- Create: `DeckKit/Sources/DeckKit/Engine/HouseOpeningSchedule.swift`
- Test: `DeckKit/Tests/DeckKitTests/HouseOpeningScheduleTests.swift`

**Interface:**

```swift
public enum HouseOpeningSchedule {

    public struct ScheduleRow: Equatable, Identifiable {
        public var id: String                // == opening.id
        public var calloutTag: String        // "D1", "W2", …
        public var kindDisplay: String       // OpeningKind.displayName
        public var widthInches: Double
        public var heightInches: Double
        public var sillHeightInches: Double
        public var edgeId: String
    }

    /// Build the door/window schedule. Doors get D1,D2…; windows W1,W2…, numbered
    /// in stable order: by edgeId, then offsetAlongEdgeInches. Deterministic so
    /// the same design always yields the same tags (callouts must match across the
    /// plan view, elevation, and schedule sheet).
    public static func rows(for data: DeckDrawingData) -> [ScheduleRow]

    /// The callout tag for a single opening within the full design (so the 2D/3D
    /// renderers and elevation projector tag the SAME opening identically).
    public static func calloutTag(for openingId: String, in data: DeckDrawingData) -> String?
}
```

**TEST STRATEGY:**

- `test_doors_get_D_windows_get_W()` — design with one `patioDoor` + one `window` → rows have `D1` and `W1`.
- `test_numbering_is_stable_by_edge_then_offset()` — three openings across two edges; assert tags assigned in (edgeId, offset) order, deterministic across two `rows(for:)` calls.
- `test_calloutTag_matches_rows()` — `calloutTag(for: id, in:)` equals the tag the same opening carries in `rows(for:)`. Cross-method consistency.
- `test_empty_house_yields_no_rows()` — `house == nil` or empty `openings` → `[]`.
- `test_frenchDoor_and_sliderDoor_count_as_doors()` — all three door kinds share the D-sequence (D1, D2, D3), windows separate.

- [ ] **Step 1 — Write tests.**
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement.** Partition `openings` into doors (`patioDoor`/`frenchDoor`/`sliderDoor`) and windows; sort each by `(edgeId, offsetAlongEdgeInches)`; assign `D{n}` / `W{n}`.
- [ ] **Step 4 — Run, expect `TEST SUCCEEDED`.**
- [ ] **Step 5 — Commit** (`feat(decks-p5): door/window schedule + stable callout tags`).

**Dependencies:** T1.
**References:** contract §5.1 (numbers JetBrains Mono, formatted — applied in the VIEW, not here); roadmap §2.4 "Door/window schedule + plan callouts".
**Risks:** tag stability is the whole point — if numbering depended on array insertion order, callouts would renumber on every edit and the plan/elevation/schedule would disagree. The `(edgeId, offset)` sort makes it geometry-deterministic. Re-route T4's `test_callout_tags_match_schedule` to consume `HouseOpeningSchedule.calloutTag` once this lands.

---

### Task 8: 3D wall-opening cutout in `DeckSceneBuilder.buildHouseWall`

**Files:**
- Modify: `DeckKit/Sources/DeckKit/3D/DeckSceneBuilder.swift:1177` (`buildHouseWall`) + its call site (`:445`)
- Test: covered by the integration snapshot in T15 + a focused node-count assertion here.

**Interface (extend the existing private method; keep the public scene-builder entry points unchanged):**

```swift
// New private helper; buildHouseWall delegates to it when the wall carries openings.
private static func buildHouseWallWithOpenings(
    parent: SCNNode,
    start: SCNVector3,
    end: SCNVector3,
    deckElevationM: Float,
    maxHeightM: Float?,
    material: HouseEdgeMaterial?,
    openings: [WallOpening],          // openings on THIS edge
    wallLengthInches: Double,
    storyHeightInches: Double
)
```

**Approach:** the current wall is a single `buildSpanningBox` (a solid `SCNBox`). For a wall carrying openings, build the wall **face** as an `SCNShape` from a `UIBezierPath` rectangle with each opening's `cutoutProfile3D` (T3) subtracted as a sub-path (even-odd fill → holes), extruded to wall thickness (2"), then oriented/positioned to span `start→end` at the correct height. Walls **without** openings keep the existing `buildSpanningBox` fast path (no perf regression on the common case). Convert inches→meters with the existing `inchesToMeters`. Door cutouts run sill 0→head; window cutouts sill→head per `WallOpening`.

**TEST STRATEGY (node-level, since full visual is snapshot in T15):**

- `test_wall_without_openings_uses_spanning_box_fast_path()` — build a scene from a design with a house edge but no openings; assert the wall node's geometry is `SCNBox` (fast path preserved).
- `test_wall_with_one_opening_produces_shape_with_hole()` — design with a `patioDoor` on the house edge; assert the wall node's geometry is `SCNShape` and that the bezier path has > 1 subpath (outer + 1 hole). (Inspect `SCNShape.path.cgPath` element count or expose a testable helper that returns the hole count.)
- `test_two_openings_two_holes()` — door + window → 2 holes.

- [ ] **Step 1 — Add a testable helper** `wallFacePath(wallLengthInches:wallHeightInches:openings:storyHeightInches:) -> UIBezierPath` (pure, no SceneKit) that builds the outer rect + opening sub-rects; unit-test the **path hole count** directly (avoids SceneKit instantiation in tests). Tests above assert against this helper's output + a thin `SCNShape` check.
- [ ] **Step 2 — Write tests, run, expect FAIL.**
- [ ] **Step 3 — Implement** `wallFacePath`, then `buildHouseWallWithOpenings` using it, then branch in `buildHouseWall`: if `openings.isEmpty` keep the existing box; else delegate. Update the `:445` call site to pass the edge's openings (filter `data.house?.openings` by `edgeId`), wall length (T3), and story height (from `HouseModel.storyHeights` / fallback).
- [ ] **Step 4 — Run, expect `TEST SUCCEEDED`.**
- [ ] **Step 5 — Build device target** (`grep BUILD SUCCEEDED`).
- [ ] **Step 6 — Commit** (`feat(decks-p5): punch door/window cutouts in 3D house wall`).

**Dependencies:** T3 (`cutoutProfile3D`), T1; existing `buildHouseWall`/`buildSpanningBox`/`inchesToMeters`.
**References:** `DeckSceneBuilder.swift:1177-1232`; roadmap §2.4 "Wall-opening cutout (2D & 3D)". Memory `deck-tab-3d-unified-renderer` (the unified renderer path), `crew-deck-blackout-poisoned-cursor` (resilient decode — irrelevant to rendering but confirms why `house == nil` must render cleanly).
**Risks:** (a) **Perf on 3-year-old phones** (CLAUDE.md field bar) — `SCNShape` is heavier than `SCNBox`; the fast path for no-opening walls keeps the common case cheap, and a deck rarely has >2–3 doors/windows. (b) **Sill reference frame** must match T4 (sill above floor line) — the cutout's y in wall-local coords starts at `sillHeightInches` measured from the wall base (deck surface), consistent with the projector. (c) SceneKit instantiation in unit tests is flaky on the sim — that is why Step 1 extracts the pure `wallFacePath` for assertions; the `SCNShape` check is a single smoke assertion.

---

### Task 9: `HouseElevationRenderer` — 2D front-on drawing + snapshot test

**Files:**
- Create: `DeckKit/Sources/DeckKit/Rendering/HouseElevationRenderer.swift`
- Test: `DeckKit/Tests/DeckKitTests/HouseElevationSnapshotTests.swift`

**Interface (mirrors the existing `DeckRenderer.renderToPNG` static style; Core Graphics):**

```swift
public enum HouseElevationRenderer {
    /// Render one house-edge elevation to a UIImage at the given size, scaling the
    /// projector's inch-space to the canvas with margins. Draws: grade line, wall
    /// face, deck surface line, openings (door = full-height frame + swing-implied
    /// glyph; window = frame + sill + mullion), story lines, dimension strings,
    /// and callout bubbles (D1/W1…). Numbers in JetBrains Mono, tabular (OPSStyle).
    public static func render(
        _ elevation: HouseElevationProjector.Elevation,
        size: CGSize
    ) -> UIImage
}
```

**TEST STRATEGY (snapshot harness — `ImageRenderer`/CG → `XCTAttachment`, memory `ops-ios-swiftui-snapshot-harness`; visual QA stays human, but assert non-degenerate output):**

- `test_render_produces_nonempty_image_of_requested_size()` — render a known elevation (deck surface 108", wall top 216", one door, one window) at 800×600; assert the returned image `size == CGSize(800,600)` and that it is not blank (sample a few pixels off the white background, or assert the drawn-bounds bounding box is non-zero via a testable `layout(_:size:)` helper that returns the scaled rects).
- `test_layout_scales_inch_space_into_canvas_with_margins()` — extract a pure `layout(_:size:) -> ElevationLayout` (grade y, wall rect, opening rects in **canvas** points) and assert: grade line near the bottom margin, wall top near the top margin, door rect bottom == deck-surface line, window rect floats above. This is the assert-able core; the `render` call is the snapshot.
- `test_callout_tags_drawn_for_each_opening()` — assert `layout` returns one callout anchor per opening with the tag from T7.
- Attach the rendered image via `XCTAttachment` for human review.

- [ ] **Step 1 — Extract a pure `layout(_:size:)`** (projector inch-space → canvas points + callout anchors) and unit-test it (no drawing).
- [ ] **Step 2 — Write the snapshot test + layout asserts; run, expect FAIL.**
- [ ] **Step 3 — Implement `layout` then `render`** (CG strokes/fills with `OPSStyle` tokens — hairline strokes, mono dimension text; grade as a hatched ground line). No hardcoded colors — pull from `OPSStyle`/`OPSDesignKit`.
- [ ] **Step 4 — Run, expect `TEST SUCCEEDED`; inspect the attachment.**
- [ ] **Step 5 — Commit** (`feat(decks-p5): 2D front-on elevation renderer`).

**Dependencies:** T4 (projector), T7 (callout tags); `OPSStyle` tokens; existing `DeckRenderer` as the CG style reference.
**References:** `Rendering/DeckRenderer.swift:13`; contract §5.1 (numbers mono/tabular, empty state `—`), §5.2 (snapshot harness); roadmap §2.8 "Elevation drawings (front/rear/side to scale)". **Note:** this is a standalone elevation surface — it does **not** extend `DeckShareRenderer` (the LIGHT marketing artifact stays separate, contract §3.5 / roadmap §6). The eventual P7 `PlanSetEngine.renderSheet(.elevation, …)` will consume this renderer's layout, not re-implement it.
**Risks:** dimension-string overlap on dense walls — keep dimensions on a leader line below the wall; the layout test pins anchor positions so regressions are caught. Honor `prefers-reduced-motion` is N/A (static render).

---

### Task 10: `ComponentEmitter` additive rows (`door`, `window`, `ledger`, `freestanding_beam_line`)

**Files:**
- Modify: `DeckKit/Sources/DeckKit/Engine/ComponentEmitter.swift:31` (`emit`) — add a `emitHouseComponents(_:)` pass
- Test: `DeckKit/Tests/DeckKitTests/HouseModelCodableTests.swift` (extend) or a focused `ComponentEmitterHouseTests.swift`

**Interface:** no signature change to `emit(_:) -> [DesignComponentRow]`. Add internal:

```swift
private static func emitHouseComponents(_ data: DeckDrawingData) -> [DesignComponentRow]
// component_type values (NEW, additive — never rename a shipped one, §3.6 doc comment):
//   "door"                  metadata: kind, widthInches, heightInches, edgeId, calloutTag
//   "window"                metadata: kind, widthInches, heightInches, sillHeightInches, edgeId, calloutTag
//   "ledger"                metadata: cladding, attachmentAllowed, lateralConnectors
//   "freestanding_beam_line" metadata: spanInches, footingCount   (when ledger fallback)
```

**TEST STRATEGY:**

- `test_emits_door_and_window_rows()` — design with one door + one window → `emit` output contains one `door` and one `window` row with the right metadata (assert `widthInches`, `calloutTag` from T7).
- `test_emits_ledger_row()` — `house.ledger` set → one `ledger` row carrying `cladding`/`attachmentAllowed`.
- `test_emits_beam_line_row_only_when_freestanding()` — `attachmentAllowed == false` → a `freestanding_beam_line` row; `true` → none.
- `test_nil_house_emits_no_house_rows()` — `house == nil` (LIGHT) → none of the four types appear. Guarantees LIGHT (whose editable `house` is nil) emits nothing new.
- `test_does_not_rename_existing_component_types()` — assert `railing`/`deck_board`/`stair_set`/`gate`/`post_set` still emitted unchanged for a geometry that produced them pre-P5 (regression guard on §3.6 contract break).

- [ ] **Step 1 — Write tests; run, expect FAIL.**
- [ ] **Step 2 — Implement `emitHouseComponents`** and append its rows in `emit`. Use `AnyCodable` scalar metadata (the P1-extended `AnyCodable` supports nested, but keep house metadata scalar for `DesignToEstimateAdapter` simplicity).
- [ ] **Step 3 — Run, expect `TEST SUCCEEDED`.**
- [ ] **Step 4 — Commit** (`feat(decks-p5): emit door/window/ledger/beam-line component rows (additive)`).

**Dependencies:** T1, T5, T7.
**References:** `ComponentEmitter.swift:31/322` (the "Adding component_type strings is fine; renaming is a contract break" doc comment); contract §3.6.
**Risks:** the web `DesignToEstimateAdapter` must tolerate unknown `component_type` rows — confirm in the plan that the adapter ignores types it doesn't map (it should, per the additive contract). If it throws on unknown types, that is a **web-side** fix flagged here, not a reason to withhold the rows. New estimate categories (door/window/beam takeoff dollars) are P6/P7 estimate work — P5 only emits the projection rows.

---

### Task 11: `DeckRenderer` plan-view opening overlay

**Files:**
- Modify: `DeckKit/Sources/DeckKit/Rendering/DeckRenderer.swift` (add an opening-overlay pass)
- Test: `DeckKit/Tests/DeckKitTests/HouseElevationSnapshotTests.swift` (add a plan-view snapshot) or extend the renderer's layout tests.

**Interface:** internal pass on the existing `renderToPNG`:

```swift
private static func renderHouseOpenings(
    gc: CGContext,
    data: DeckDrawingData,
    transform: CGAffineTransform   // canvas→image, same as the rest of DeckRenderer
)
```

**Approach:** for each house edge carrying openings, draw a glyph centered at the opening's position along the edge (door = a small swing-arc + gap break in the wall line; window = a double-line mullion break) plus the `calloutTag` (T7) in mono. Reuse `DeckRenderer`'s existing canvas→image transform so the overlay registers with the plan geometry.

**TEST STRATEGY:**
- `test_plan_overlay_places_glyph_at_opening_offset()` — pure `openingGlyphAnchors(data:transform:) -> [(tag:String, point:CGPoint)]` helper; assert anchors land at the projected offset along the edge for a known edge + transform.
- `test_no_openings_no_overlay_anchors()` — empty → `[]`.
- Plan-view snapshot attachment for human review.

- [ ] **Step 1 — Extract `openingGlyphAnchors`; write tests; run, expect FAIL.**
- [ ] **Step 2 — Implement the anchors + the CG overlay pass; wire into `renderToPNG`.**
- [ ] **Step 3 — Run, expect `TEST SUCCEEDED`; inspect snapshot.**
- [ ] **Step 4 — Commit** (`feat(decks-p5): plan-view door/window glyphs + callouts`).

**Dependencies:** T1, T7; existing `DeckRenderer` transform.
**References:** `Rendering/DeckRenderer.swift:13`; roadmap §2.4 "Door/window schedule + plan callouts".
**Risks:** the canvas→image transform must be the **same** one `DeckRenderer` uses for edges or glyphs drift off the wall — reuse, don't recompute. The overlay must be capability-aware at the **call site** only if LIGHT could ever have openings; since LIGHT's editable `house` is nil and `emitHouseComponents` returns none, a `data.house == nil` guard makes the overlay a no-op in LIGHT automatically.

---

### Task 12: Editor views — `HouseModelSheet`, `WallOpeningEditorView`, `LedgerDetailSheet` (FULL, capability-gated)

**Files:**
- Create: `DeckKit/Sources/DeckKit/Views/HouseModelSheet.swift`
- Create: `DeckKit/Sources/DeckKit/Views/WallOpeningEditorView.swift`
- Create: `DeckKit/Sources/DeckKit/Views/LedgerDetailSheet.swift`
- Modify: `DeckBuilderViewModel` (add `house`-mutating intents)
- Test: ViewModel-intent unit tests in `DeckKit/Tests/DeckKitTests/HouseEditingIntentTests.swift` (views themselves are visually QA'd)

**Interface (ViewModel intents — pure-ish, mutate `drawingData.house`, mark `needsSync` via the existing setter):**

```swift
// On DeckBuilderViewModel (or a P5 extension):
func setFloorLine(feet: Double?)                                   // HouseModel.floorLineFeet
func setStoryHeights(_ feet: [Double])                             // HouseModel.storyHeights
func addOpening(_ kind: OpeningKind, onEdge edgeId: String,
                widthInches: Double, heightInches: Double,
                sillHeightInches: Double, offsetAlongEdgeInches: Double) -> WallOpening.Validation
func updateOpening(_ opening: WallOpening) -> WallOpening.Validation
func removeOpening(id: String)
func resolveLedger(forEdge edgeId: String,
                   houseSideBeamSpanInches: Double) -> LedgerStrategyEngine.Strategy
```

Each intent: lazily creates `drawingData.house` if nil (FULL only), validates via `WallOpeningGeometry`/`LedgerStrategyEngine`, writes through `drawingData` (which sets `needsSync`/`updatedAt` per the existing accessor at `DeckDesign.swift:57`), and clamps via T3.

**TEST STRATEGY (ViewModel intents, not pixels):**

- `test_addOpening_appends_validated_opening_and_marks_sync()` — add a fitting door; assert `house.openings.count == 1`, returned `.ok`, and the design `needsSync == true`.
- `test_addOpening_clamps_overflowing_offset()` — add with offset past wall end; assert the persisted opening's offset is clamped (returned `.clampedToWall`).
- `test_updateOpening_rejects_overlap()` — move a window to overlap a door; assert `.overlapsOpening` and the prior value is NOT persisted (editor shows the error, user must resolve).
- `test_resolveLedger_brick_returns_freestanding_and_persists_detail()` — house edge cladding `.brick`; assert `resolveLedger` returns `.freestanding` and `house.ledger.attachmentAllowed == false`.
- `test_setStoryHeights_persists()` — set `[9,8]`; assert round-trips through `toJSON`/`fromJSON`.
- `test_intents_noop_or_unavailable_in_light()` — when `capabilities` lacks `.houseOpenings`, the intents are not reachable (the surfaces are hidden); assert at minimum that a LIGHT-configured VM does not expose the house-editing entry (see T14) — here, assert the VM guards `house` creation behind capability so a misuse can't silently write a FULL block in LIGHT.

- [ ] **Step 1 — Write intent tests; run, expect FAIL.**
- [ ] **Step 2 — Implement the intents** on the ViewModel (guard `.houseOpenings`; lazy-create `house`; validate+clamp; write through `drawingData`).
- [ ] **Step 3 — Build the three SwiftUI sheets** against the intents, all `OPSStyle`-tokenized, 44pt+ touch targets, mono numbers. `WallOpeningEditorView` shows a live 2D wall strip with the cutout (reuse T3's `cutoutRect2D`) and surfaces validation results inline. `LedgerDetailSheet` shows the strategy result + the §6.2 disclaimer text (via `ops-copywriter`) + fastener/lateral-connector fields. Copy for ALL labels/empty-states via `ops-copywriter`.
- [ ] **Step 4 — Run intent tests, expect `TEST SUCCEEDED`; build device target.**
- [ ] **Step 5 — Commit** (`feat(decks-p5): house/opening/ledger editor surfaces + viewmodel intents`).

**Dependencies:** T1, T3, T5; existing `DeckBuilderViewModel` + `drawingData` setter; P1 `CapabilityProvider`; `ops-copywriter` + `ops-design`/`mobile-ux-design` skills for the UI.
**References:** `DeckBuilderViewModel.swift`, `DeckDesign.swift:53-62`; contract §4 (capability gating), §6.2 (ledger disclaimer); CLAUDE.md field-first (44pt, 16pt+ text, haptics on commit).
**Risks:** (a) **Design judgment (CLAUDE.md):** do not render one card per cladding option or a flat list of every field. House-attachment is a once-per-design setup — one entry point ("House & openings"), brief flow, compact state after. The ledger result is state-aware: show the freestanding fallback prominently *only when triggered*, not a permanent "attachment: allowed" badge. Run `mobile-ux-design` before building. (b) Haptics: medium impact on opening-commit, success notification on ledger-resolve. (c) Must not write a `house` block in LIGHT — the capability guard in the intents is the safety net for `test_intents_noop_or_unavailable_in_light`.

---

### Task 13: `HouseElevationView` + `HouseOpeningScheduleView` screens (FULL, capability-gated)

**Files:**
- Create: `DeckKit/Sources/DeckKit/Views/HouseElevationView.swift`
- Create: `DeckKit/Sources/DeckKit/Views/HouseOpeningScheduleView.swift`
- Test: visual QA + a thin `HouseElevationViewModelTests` for the faces list.

**Interface:**

```swift
// HouseElevationView: hosts a paged set of HouseElevationRenderer outputs, one per
// house face, with the schedule table beneath. Reads HouseElevationProjector.projectAllFaces.
public struct HouseElevationView: View {
    public init(data: DeckDrawingData)   // FULL-only; presented behind .houseOpenings
}
// HouseOpeningScheduleView: renders HouseOpeningSchedule.rows as a tactical table
// (mark · kind · W×H · sill · edge), mono numbers, empty state "—".
public struct HouseOpeningScheduleView: View {
    public init(rows: [HouseOpeningSchedule.ScheduleRow])
}
```

**TEST STRATEGY:**
- `test_elevation_view_lists_only_house_faces()` — a design with 2 house edges + 3 deck edges → `projectAllFaces` yields 2 elevations; assert the view's pager has 2 pages (test the backing array, not the view tree).
- `test_schedule_view_empty_state()` — empty rows → renders the `—` empty state (assert via a testable `isEmpty` branch).
- Snapshot attachments of the elevation page + schedule table.

- [ ] **Step 1 — Thin VM/array tests; run, expect FAIL.**
- [ ] **Step 2 — Build the two views** (paged `TabView` of `HouseElevationRenderer.render` images; schedule as a tokenized table). `ops-copywriter` for headers ("DOOR/WINDOW SCHEDULE", uppercase authority), mono numbers, `—` empty state.
- [ ] **Step 3 — Run tests; inspect snapshots; build device target.**
- [ ] **Step 4 — Commit** (`feat(decks-p5): elevation + door/window schedule screens`).

**Dependencies:** T4, T7, T9; `ops-copywriter`, `ops-design`.
**References:** contract §5.1 (mono/tabular numbers, `—` empty state); roadmap §2.4/§2.8.
**Risks:** elevation per-face paging must label which face ("FRONT", "NORTH", or the edge label if set) — use the edge's `label` when present, else a derived compass/ordinal. Don't show a blank page for a design with no house edges — show the empty state ("No house wall on this design").

---

### Task 14: Capability gating + toolbar entry points (`.houseOpenings`)

**Files:**
- Modify: `DeckKit/Sources/DeckKit/Views/DeckToolbar.swift` (+ wherever the FULL tool surface lives post-P1)
- Modify: `DeckBuilderViewModel` (expose `capabilities` from the injected `CapabilityProvider`)
- Test: `DeckKit/Tests/DeckKitTests/HouseCapabilityGatingTests.swift`

**Interface:** consume P1's `CapabilityProvider`/`DeckCapabilities`. Surfaces ("House & openings", "Elevation", "Schedule") render **only** when `capabilities.contains(.houseOpenings)`; otherwise hidden (not disabled-with-lock), except the single allowed upsell stub (contract §4 / roadmap one-entry-point rule).

**TEST STRATEGY:**
- `test_full_capabilities_show_house_entries()` — VM with `.full`; assert the toolbar model lists the three house entries.
- `test_light_capabilities_hide_house_entries()` — VM with `.light`; assert none of the three appear (the menu model excludes them). LIGHT may show **one** "Available in OPS Decks" upsell stub — assert exactly one stub, no functional entry.
- `test_light_vm_never_invokes_house_engines()` — attempt to trigger a house intent on a `.light` VM; assert it is a no-op / unreachable (guards from T12). Engines must never run in LIGHT (contract §4).

- [ ] **Step 1 — Write gating tests; run, expect FAIL.**
- [ ] **Step 2 — Build a `houseToolEntries(for capabilities:)` pure helper** returning the visible entries; drive the toolbar from it; add the single upsell stub for `.light`.
- [ ] **Step 3 — Run tests, expect `TEST SUCCEEDED`; build device target.**
- [ ] **Step 4 — Commit** (`feat(decks-p5): capability-gate house/elevation/schedule surfaces`).

**Dependencies:** P1 `CapabilityProvider`/`DeckCapabilities.houseOpenings`; T12/T13 surfaces.
**References:** contract §4 (hide-not-disable, one upsell stub), §8.6.
**Risks:** the upsell stub copy is user-facing — `ops-copywriter` ("Available in OPS Decks", tactical, no exclamation). Gating must be on **capability**, not schema version — a `.light` build opening a v5 design hides the editors but still round-trips the block (T2). Do not gate on `version >= 5`.

---

### Task 15: Full-design integration + multi-story acceptance

**Files:**
- Test: `DeckKit/Tests/DeckKitTests/HousePhase5IntegrationTests.swift`
- Test: `DeckKit/Tests/DeckKitTests/HouseElevationSnapshotTests.swift` (final multi-story scene + elevation snapshots)

**TEST STRATEGY (end-to-end across the phase):**

- `test_full_house_design_roundtrips_and_renders()` — construct a two-story design (two `DeckLevel`s, upper at floor-line 9 ft, a house edge with `.brick` cladding, one `patioDoor` + two `window`s, a `LedgerDetail` from the freestanding fallback, stairs-to-grade). `toJSON` → `fromJSON` → assert `house` survives intact; build the 3D scene → assert wall has 3 holes + a freestanding beam line is present (via the framing block written by T5/T12); project + render the elevation → snapshot; build the schedule → assert 1 door (D1) + 2 windows (W1,W2).
- `test_light_opens_full_two_story_design_without_loss()` — decode the above via `.light`, re-encode, re-decode via FULL, assert `house == original.house` AND `framing` (the beam-line members) preserved. The full graceful-degradation story (§0.2/§1.4) at design scale.
- `test_stairs_to_grade_present_for_upper_story()` — assert `StairsToGradeEngine.stairsToGrade(levelId: upperLevelId, …)` yields ≥1 flight with total rise == floor-line datum.
- `test_brick_ledger_drives_freestanding_in_the_full_design()` — assert the persisted ledger has `attachmentAllowed == false` and the framing block carries the house-side beam members.

- [ ] **Step 1 — Write the integration + snapshot tests; run, expect FAIL where engines/views not yet integrated.**
- [ ] **Step 2 — Wire any missing integration glue** (e.g. T5's fallback members landing in `data.framing` via the T12 `resolveLedger` intent).
- [ ] **Step 3 — Run full suite** on the simulator destination; grep `TEST SUCCEEDED`. Inspect snapshot attachments.
- [ ] **Step 4 — Build device target** (`grep BUILD SUCCEEDED`).
- [ ] **Step 5 — Commit** (`test(decks-p5): full two-story house + freestanding ledger integration`).

**Dependencies:** ALL prior tasks; P2 `FramingPlan`/`framing` block, P4 footing/framing types.
**References:** contract §0.2, §1.4, §5.2; roadmap §2.4 (entire house-attachment domain).
**Risks:** this task surfaces any cross-engine convention drift (sill frame, callout tags, beam coordinate space). If P2/P4 blocks aren't yet present at execution, scope this test to what exists (house round-trip, openings, elevation, schedule, stairs-to-grade) and gate the framing-block assertions behind P2/P4 availability — but do **not** delete them; mark them `XCTSkip` with a reason so they light up when predecessors land.

---

## Compliance & liability checklist (P5-specific, §6)

- [ ] `LedgerDetailSheet` shows the §6.2 disclaimer ("This is not a guarantee of full code adherence. Have plans reviewed by a licensed engineer in your jurisdiction.") before presenting any ledger decision.
- [ ] `LedgerStrategyEngine.rationale` is **objective-negative only** — asserted by `test_rationale_is_objective_negative_only` (no "safe"/"compliant"/"guaranteed"/"will pass").
- [ ] P5 asserts **no span/footing/sizing number** — the freestanding fallback emits geometry for P4 to size; `nominalSize`/`sizing` stay nil (asserted in T5).
- [ ] Stairs-to-grade landing split is documented as a geometry convenience, not a code pass (T6 doc comment + risk note).
- [ ] All FULL surfaces hidden in LIGHT; engines never invoked in LIGHT (T14).
- [ ] No IRC Appendix H reliance (P5 doesn't touch overhead/roof — that's P6).

## Design-system & field checklist (CLAUDE.md)

- [ ] Every color/spacing/radius/font traces to `OPSStyle`/`OPSDesignKit` tokens — zero hardcoded design values (snapshot review confirms tone).
- [ ] Numbers are JetBrains Mono, tabular, formatted; empty state `—`.
- [ ] Touch targets ≥ 44pt (prefer 60pt for primary); text ≥ 16pt.
- [ ] Haptics: medium on opening-commit / ledger-resolve, light on sheet arrival, success notification on a completed house setup.
- [ ] Copy authored via `ops-copywriter` (labels, the upsell stub, the disclaimer surface, schedule headers, empty states).
- [ ] House-attachment UI is state-aware and progressively disclosed — one "House & openings" entry, freestanding fallback shown only when triggered, no card-per-option dump.

---

## Self-review notes (author)

- **Spec coverage:** every Phase-5 roadmap §2.4 row is covered — house wall datum/story heights (T1, T12), door placement+sizing (T1,T3,T12), window placement+sizing (T1,T3,T12), wall cutout 2D (T11) + 3D (T8), elevation view (T4,T9,T13), ledger detail + cladding code-check w/ brick-stone freestanding fallback (T5,T12), multi-story stairs-to-grade (T6,T15), door/window schedule + callouts (T7,T11,T13).
- **Additive-block discipline:** exactly one new top-level property (`house`); version → 5; defensive decode; round-trip + LIGHT-preserve + malformed tests (T2). No renamed fields/enum cases/component_types.
- **Type consistency:** `HouseModel`/`WallOpening`/`OpeningKind`/`LedgerDetail` used verbatim across T1–T15; `WallOpening.Validation`, `LedgerStrategyEngine.Strategy`, `StairsToGradeEngine.GradeStairResult`, `HouseOpeningSchedule.ScheduleRow`, `HouseElevationProjector.Elevation` named identically wherever referenced. Callout tags flow from one source (`HouseOpeningSchedule`) into projector (T4), 2D overlay (T11), and schedule view (T13).
- **Predecessor honesty:** every P1/P2/P4 dependency is named with the behavior relied on; where a body isn't yet written, the step states the dependency and leaves the literal call site for phase-start finalization (per the header note), without inventing signatures.
```

