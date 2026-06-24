# OPS Decks — Phase 7: Compliance, As-Built Audit & Permit Outputs (FULL)

**Date:** 2026-06-24
**Status:** Implementation plan (P7). Authored against the LOCKED architecture contract `docs/superpowers/plans/2026-06-24-ops-decks-architecture-contract.md`, the feature roadmap `docs/superpowers/specs/2026-06-24-ops-decks-feature-roadmap.md` §3/§7, and the foundation spec `docs/superpowers/specs/2026-06-24-ops-decks-standalone-app-design.md`.

> **HEADER NOTE — bite-sized TDD steps with literal code are finalized at phase start once predecessors exist.** P7 consumes types that P1–P6 create (`DeckDrawingData` new blocks, `FramingPlan`, `FootingPlan`, `HouseModel`, `CodePackage`, `StructuralSizingEngine`, `FootingEngine`, `CodePackageLoader`, `DeckCapabilities`). Those files do **not** exist yet. This plan fixes the public interface verbatim from the contract, the test strategy, the dependency edges, the code/standard references, and the risks — but the exact red→green→refactor micro-steps (literal fixture cells, literal assertion values, exact view-body Swift) are pinned at the **start of P7 execution**, after P1–P6 have landed and their real signatures are in the tree. Do not fabricate predecessor signatures beyond what the contract states.

---

## Goal

Fulfill the product's reason to exist: **design → engineer → code-check → permit.** Phase 7 turns an engineered deck (framing sized in P3, footings sized in P4, house/openings in P5, surface/overhead in P6) into three legally-weighted deliverables, plus the flagship as-built audit:

1. **`ComplianceEngine`** — one pure engine, two directions (`.design` / `.asBuilt`). Evaluates the deck's geometry + structural outputs against the user-selected jurisdiction `CodePackage` and returns a `ComplianceReport`: objective pass/fail per cited code section, out-of-envelope hard-stops, and the single LOCKED summary phrasing `"no code failures detected"` (never "safe"/"compliant"/"will pass").
2. **As-built CURRENT→TARGET audit** — capture an *existing* deck (AR/LiDAR + photos + manual entry), auto-check the **visible** geometry, run a **guided wizard** for hidden-but-knowable structure, and tag truly-hidden elements `.notAssessable`. **Never a clean pass.** Produces a remediation report (CURRENT vs TARGET, severity-tiered, evidence-linked).
3. **Structural calc report** — engineer-reviewable per-member output (DCA6-style), surfacing every assumption (`EngineAssumptions`) + the `CodePackage.edition` in force.
4. **Drafting / plan-set engine (`PlanSetEngine`)** — purpose-built (NOT an extension of `DeckShareRenderer`): dimensioned plan view, framing plan, elevations, cross-section, detail callouts, site plan, assembled into a **multi-sheet permit set with a compliant title block** for export to the city.
5. **PE-stamp workflow** — `PEStampRequest`; the app never self-certifies; out-of-envelope conditions route here.
6. **Full BOM / schedule** — lumber + fastener + hardware + concrete schedule, derived from the now-engineered model via additive `ComponentEmitter` rows.
7. **CAD / vector PDF export** — vector PDF on-device; **DWG/DXF cost-flagged** (3rd-party lib / server converter — not committed without an explicit cost decision).

Phase 7 is the last phase; it depends on nearly everything. It introduces the **`compliance` / `permitPlanSet` / `peStamp` capabilities** (FULL-only) and completes the `PermitMeta` schema block.

---

## Architecture

**Where the work lives.** All new engines and value types live in **`DeckKit/Sources/DeckKit/Compliance/`** (the contract's NEW submodule, §1.2). All are pure `enum` namespaces with `static func`s — no I/O, no `ModelContext`, no singletons, fully unit-testable offline (the `StairCalculator` precedent, contract §0.4). Views live in `DeckKit/Sources/DeckKit/Views/Compliance/` and are capability-gated (§4): hidden when `.compliance` / `.permitPlanSet` / `.peStamp` are absent, with exactly one tasteful upsell stub.

**Schema growth.** P7 completes the single additive top-level property `permitMeta: PermitMeta?` on `DeckDrawingData` (introduced minimal in P1, completed here), bumps `DeckDesign.version` to **7**, and obeys the round-trip preservation rule (contract §1.4): a LIGHT build that can't render a P7 block round-trips it untouched via `unknownBlocks` passthrough. **`ComplianceReport` is cached *inside* `PermitMeta.lastComplianceResult`** so a re-opened deck shows its last audit without re-running — and so a LIGHT build preserves it.

**The two-directions engine.** `ComplianceEngine.evaluate(_:mode:package:)` is the single entry point. `.design` mode trusts the model's engineered values (P3 sizing, P4 footings). `.asBuilt` mode treats the same `DeckDrawingData` as a *capture*: visible geometry is auto-checked, hidden structural members the user entered via the audit wizard are `source: .userEntered`, and anything the phone cannot verify (footing depth, concealed ledger fasteners, lateral hold-downs) is forced to `severity: .notAssessable` / `source: .notAssessable`. Build once, run both ways (roadmap §3).

**Drafting is its own pipeline.** `PlanSetEngine` uses `UIGraphicsPDFRenderer` + Core Graphics on-device (the exact mechanism `DeckShareRenderer.renderPDF` uses today — `UIGraphicsPDFRenderer(bounds:)`, `pdfData { ctx in ... }`, `beginPage`), but it is a **separate type with viewport/scale/annotation/title-block machinery** that `DeckShareRenderer` does not have. The contract is explicit: do NOT extend `DeckShareRenderer` (that 2-page marketing artifact is the LIGHT deliverable, roadmap §6). A shared internal `DraftingCanvas` helper (true-scale coordinate transform, dimension strings, leader/callout primitives) is the reusable core; each `PlanSheetKind` is a renderer over that canvas.

**Compliance posture is law.** Every compliance/structural/permit output obeys contract §6 verbatim: objective-negative claims only, disclaimer acknowledged (`PermitMeta.disclaimerAcknowledgedAt`) before generation, jurisdiction drives the ruleset (`CodePackage`), out-of-envelope → `EngineOutcome.outOfEnvelope` → "requires a licensed engineer" with **no number**, assumptions surfaced on every result, as-built never a clean pass, code tables are data (`CodePackage`) stamped "code data current to [date]". The one sanctioned summary string is asserted by test.

**Capability gating.** `.compliance`, `.permitPlanSet`, `.peStamp` are FULL-only (`DeckCapabilities`, contract §4). An engine is **never invoked** without its capability — a LIGHT build physically cannot produce a compliance finding, a permit sheet, or a stamp request. Data is always preserved regardless of capability.

---

## Tech Stack

- **Swift / SwiftUI**, `DeckKit` Swift package (depends on `OPSDesignKit` for tokens).
- **Pure engines:** `enum` + `static func`, `Codable & Equatable` result types, the `EngineOutcome<T>` / `EngineCitation` / `EngineAssumptions` envelope (contract §3 preamble).
- **Drafting / PDF:** `UIGraphicsPDFRenderer` + `CoreGraphics` (raster-backed vector PDF), on-device. `CoreText` for title-block + schedule typography. PDF page geometry mirrors `DeckShareRenderer` (letter 612×792 / landscape 792×612), extended to ANSI/ARCH permit sheet sizes via `DrawingScale`.
- **As-built capture:** reuses the existing `AR/` measure path (perimeter + height) and `OCRService` seam (photo-of-fastener hints); NO new AR engine.
- **Code rules:** consumed as `CodePackage` *data* loaded via `CodePackageLoader` (real impl from P3). Engines never hard-code table cells.
- **Tests:** XCTest, table-driven, simulator destination `iPhone 17, OS 26.5`. Snapshot harness (`ImageRenderer`/`UIGraphicsImageRenderer` → `XCTAttachment`) for plan-set/report visual QA. Code-package **test fixtures** (checked-in JSON) mirror a known subset of real edition cells.
- **Build:** device verification `xcodebuild -scheme OPS -destination 'generic/platform=iOS'`; test compile/run on the sim destination. Copy `Secrets.xcconfig` into any worktree first. Grep logs for `BUILD SUCCEEDED` / `TEST SUCCEEDED` (exit-code masking, memory `xcodebuild-exit-code-masking`).
- **Design tokens:** `OPSStyle` / `OPSDesignKit` only — no hardcoded color/spacing/radius/font. Numbers in UI: JetBrains Mono, tabular, formatted; empty state `—`. Copy is terse/tactical, drafted with the `ops-copywriter` skill, no emoji/exclamation. Any motion in the report/wizard surfaces uses the single OPS easing curve and honors reduced-motion (load `animation-studio:animation-architect` then `ios-animations` before any transition work). Haptics: medium impact on commit (run audit, generate permit set, submit PE request), success notification on report ready.

---

## File Structure

### New files (DeckKit — engines & value types)

| File | Responsibility |
|---|---|
| `DeckKit/Sources/DeckKit/Compliance/ComplianceEngine.swift` | The `ComplianceEngine` enum + `evaluate(_:mode:package:)`; orchestrates per-domain check functions; emits `ComplianceReport`. |
| `DeckKit/Sources/DeckKit/Compliance/ComplianceModels.swift` | `ComplianceReport`, `ComplianceFinding`, `Severity`, `Confidence`, `FindingSource`, `Evidence` (contract §3.3). Locked summary/disclaimer string constants. |
| `DeckKit/Sources/DeckKit/Compliance/ComplianceChecks/GuardChecks.swift` | Guard height (R312, 36"), 30"-guard-required trigger (height-above-grade), baluster/opening 4" spacing (+ photo-assist confidence). Pure functions returning `[ComplianceFinding]`. |
| `DeckKit/Sources/DeckKit/Compliance/ComplianceChecks/StairChecks.swift` | Stair rise/run + uniformity (R311.7, 7.75"/10"/⅜" uniformity), handrail height/graspability (4+ risers), landing checks. Consumes `StairConfig` + `StairCalculator`. |
| `DeckKit/Sources/DeckKit/Compliance/ComplianceChecks/LedgerChecks.swift` | Ledger fastener schedule + lateral-connector presence (R507.9). In `.asBuilt`, forced `.notAssessable` when concealed. Reads `HouseModel.ledger` / `HouseEdgeMaterial`. |
| `DeckKit/Sources/DeckKit/Compliance/ComplianceChecks/StructuralChecks.swift` | Reconciles P3 `MemberSizingResult` / P4 `FootingSizingResult` into findings: any `.outOfEnvelope` member → safety-hazard / PE; utilization > 1.0 → fail; missing sizing → `.notAssessable` (LIGHT-authored). |
| `DeckKit/Sources/DeckKit/Compliance/ComplianceChecks/GeometryChecks.swift` | Footprint, post spacing, deck-height-above-grade, guard-trigger geometry — the purely-visible auto-checks shared by `.design` and `.asBuilt`. |
| `DeckKit/Sources/DeckKit/Compliance/AsBuiltAuditModel.swift` | `AsBuiltCapture` value type (the wizard's accumulating answers) + mapping into a `DeckDrawingData` overlay the engine evaluates. Tags hidden answers `source`. |
| `DeckKit/Sources/DeckKit/Compliance/PlanSetEngine.swift` | `PlanSetEngine` enum: `renderPermitSet`, `renderSheet`, `renderCalcReport` (contract §3.5). Page assembly, title block, sheet ordering, disclaimer stamp. |
| `DeckKit/Sources/DeckKit/Compliance/PlanSheets/DraftingCanvas.swift` | Shared CG drawing core: true-scale transform (`DrawingScale.inchesPerFoot`), dimension strings, leaders, callout bubbles, north arrow, scale bar, hatching. |
| `DeckKit/Sources/DeckKit/Compliance/PlanSheets/PlanViewSheet.swift` | Dimensioned to-scale plan-view sheet renderer. |
| `DeckKit/Sources/DeckKit/Compliance/PlanSheets/FramingPlanSheet.swift` | Framing plan: joist/beam/post/ledger/blocking callouts from `FramingPlan`. |
| `DeckKit/Sources/DeckKit/Compliance/PlanSheets/ElevationSheet.swift` | Front/rear/side elevation from `HouseModel` (floor datum/story heights) + `TerrainModel` grade. |
| `DeckKit/Sources/DeckKit/Compliance/PlanSheets/CrossSectionSheet.swift` | Footing→post→beam→joist→decking→guard section (DCA6 detail). |
| `DeckKit/Sources/DeckKit/Compliance/PlanSheets/SitePlanSheet.swift` | Deck vs property lines / setbacks (`SetbackInput`); AHJ-verify note. |
| `DeckKit/Sources/DeckKit/Compliance/PlanSheets/DetailCalloutSheet.swift` | Footing + connection detail callouts (fastener schedule, Simpson hardware). |
| `DeckKit/Sources/DeckKit/Compliance/TitleBlockRenderer.swift` | NCS-style title block: project/address/edition/date/disclaimer/PE stamp area. |
| `DeckKit/Sources/DeckKit/Compliance/CADExporter.swift` | Vector-PDF export façade + DWG/DXF **cost-flag stub** (`CADExportFormat` with `.vectorPDF` shipping, `.dwg`/`.dxf` returning `.requiresPaidConverter`). |
| `DeckKit/Sources/DeckKit/Engine/PermitBOMEmitter.swift` | Additive `DesignComponentRow` rows (`joist`/`beam`/`post`/`footing`/`fastener`/`concrete`) from the engineered model — the full schedule. **Does not** rename existing component types. |

### New files (DeckKit — views, capability-gated)

| File | Responsibility |
|---|---|
| `DeckKit/Sources/DeckKit/Views/Compliance/JurisdictionPickerView.swift` | Country + province/state selection → `PermitMeta.jurisdictionId` + `codeEdition`; download via `CodePackageLoader`. (Groundwork exists from P1/P3; P7 finalizes the report-entry surface.) |
| `DeckKit/Sources/DeckKit/Views/Compliance/ComplianceDisclaimerGate.swift` | The §6.2 disclaimer acknowledgement sheet; sets `PermitMeta.disclaimerAcknowledgedAt`; blocks report/permit generation until accepted. |
| `DeckKit/Sources/DeckKit/Views/Compliance/ComplianceReportView.swift` | Summary-first, severity-tiered findings list (`ITEM · SEVERITY · CURRENT · TARGET · CODE § · FIX · CONFIDENCE · EVIDENCE`). Renders `summaryStatement` + disclaimer. |
| `DeckKit/Sources/DeckKit/Views/Compliance/ComplianceFindingRow.swift` | One finding row; severity color from tokens; `.notAssessable` styled as a distinct "verify on site" state. |
| `DeckKit/Sources/DeckKit/Views/Compliance/AsBuiltAuditWizardView.swift` | Guided wizard: capture geometry → auto-check → ask hidden-but-knowable (joist/beam/fastener/connector) with photo-of-fastener hints → flag truly-hidden. |
| `DeckKit/Sources/DeckKit/Views/Compliance/CalcReportPreviewView.swift` | Preview + share of the structural calc report PDF. |
| `DeckKit/Sources/DeckKit/Views/Compliance/PermitPlanSetView.swift` | Sheet-selection (`PlanSheetKind` set) + title-block entry + scale + generate/preview/share of the permit set. |
| `DeckKit/Sources/DeckKit/Views/Compliance/PEStampRequestView.swift` | PE-stamp request workflow; sets `PermitMeta.peStampRequest`; surfaced automatically on any out-of-envelope finding. |
| `DeckKit/Sources/DeckKit/Views/Compliance/ComplianceUpsellStub.swift` | The single tasteful "available in OPS Decks Pro" entry point shown when `.compliance` capability absent. |

### Modified files

| File | Change |
|---|---|
| `DeckKit/Sources/DeckKit/Models/DeckGeometry.swift` (was `OPS/DeckBuilder/Models/DeckGeometry.swift`) | Complete `PermitMeta` (P1 minimal → P7 full: `setbacks`, `disclaimerAcknowledgedAt`, `lastComplianceRunAt`, `lastComplianceResult`, `peStampRequest`) + `SetbackInput` + `PEStampRequest`. Wire `permitMeta` into `DeckDrawingData.CodingKeys` + `init(from:)` `decodeIfPresent` (already present from P1; extend the struct's own decoder). |
| `DeckKit/Sources/DeckKit/Models/DeckDesign.swift` | Bump default `version` mapping logic so P7-authored decks stamp schema version 7 on save (the migration/backfill gate; rendering stays capability-gated). |
| `DeckKit/Sources/DeckKit/Engine/ComponentEmitter.swift` | Call `PermitBOMEmitter` to append engineered rows when framing/footings exist; **additive only** (never rename `railing`/`deck_board`/`stair_set`/`gate`/`post_set`). |
| `DeckKit/Sources/DeckKit/Capability/DeckCapabilities.swift` | (Defined P1; no change — P7 only *consumes* `.compliance`/`.permitPlanSet`/`.peStamp`. Listed for traceability.) |
| `DeckKit/Sources/DeckKit/Views/DeckBuilderViewModel.swift` | Add capability-gated entry points: run compliance, open as-built wizard, generate permit set, request PE stamp. Route out-of-envelope → PE stub. Persist `permitMeta` via `DeckStore.saveDeck`. |

### New test files

| File | Responsibility |
|---|---|
| `OPSTests/DeckBuilder/Compliance/ComplianceEngineDesignTests.swift` | `.design` mode: pass/fail per section against fixture `CodePackage`; locked summary string; disclaimer presence. |
| `OPSTests/DeckBuilder/Compliance/ComplianceEngineAsBuiltTests.swift` | `.asBuilt` mode: hidden elements forced `.notAssessable`; never a clean pass; `source` tagging. |
| `OPSTests/DeckBuilder/Compliance/GuardChecksTests.swift` | Guard height, 30" trigger, 4" opening (incl. photo-assist confidence boundaries). |
| `OPSTests/DeckBuilder/Compliance/StairChecksTests.swift` | Rise/run/uniformity, handrail trigger; reuse `StairCalculator`. |
| `OPSTests/DeckBuilder/Compliance/LedgerChecksTests.swift` | Ledger fastener/lateral-connector; brick/stone → freestanding; `.notAssessable` when concealed. |
| `OPSTests/DeckBuilder/Compliance/StructuralChecksTests.swift` | `.outOfEnvelope` propagation; utilization>1 fail; missing sizing → `.notAssessable`. |
| `OPSTests/DeckBuilder/Compliance/OutOfEnvelopeTests.swift` | Envelope-limit breaches → `.outOfEnvelope` finding, no number, PE route, locked phrasing. |
| `OPSTests/DeckBuilder/Compliance/PermitMetaRoundTripTests.swift` | encode→decode→encode stable; LIGHT preserves P7 block; malformed sub-block → nil without failing whole decode. |
| `OPSTests/DeckBuilder/Compliance/PlanSetEngineTests.swift` | PDF bytes non-empty + valid; sheet count == requested; title-block disclaimer stamped on every page; calc-report per-member rows. |
| `OPSTests/DeckBuilder/Compliance/PlanSetSnapshotTests.swift` | Snapshot each `PlanSheetKind` + assembled set via `ImageRenderer → XCTAttachment`. |
| `OPSTests/DeckBuilder/Compliance/PermitBOMEmitterTests.swift` | Engineered rows additive; existing component types unchanged. |
| `OPSTests/DeckBuilder/Compliance/CADExporterTests.swift` | `.vectorPDF` returns data; `.dwg`/`.dxf` returns `.requiresPaidConverter` (no silent paid path). |
| `OPSTests/DeckBuilder/Compliance/CapabilityGatingTests.swift` | `.light` cannot invoke compliance/permit/PE; `.full` can. |
| `OPSTests/Fixtures/CodePackages/US-IRC-2021.test.json` | Known-subset fixture mirroring real IRC/DCA6 cells (joist/beam/post/footing/guard/stair/ledger/envelope). |
| `OPSTests/Fixtures/CodePackages/CA-BC-2024.test.json` | Known-subset BCBC Part 9 (metric, kPa) fixture — unit-system divergence coverage. |

---

## Tasks

> Dependency legend: **[P1]** P1 carve-out + `PermitMeta` minimal + `unknownBlocks` passthrough + `DeckCapabilities`; **[P2]** `FramingPlan`/`FramingMember`/`LoadPreset`; **[P3]** `StructuralSizingEngine`/`MemberSizingResult`/`CodePackage`/`CodePackageLoader`/`EngineOutcome`/`EngineCitation`/`EngineAssumptions`; **[P4]** `FootingPlan`/`Footing`/`FootingSizingResult`/`FootingEngine`/`TerrainModel`; **[P5]** `HouseModel`/`LedgerDetail`/`WallOpening`; **[P6]** `SurfaceFeaturePlan`/`OverheadStructurePlan`/`DeckingPattern`.

---

### Task 1 — Complete the `PermitMeta` schema block + round-trip safety

**Goal.** Extend P1's minimal `PermitMeta` to its full P7 shape, wire it through `DeckDrawingData`, bump schema version to 7, and prove round-trip preservation.

**Interface (verbatim from contract §2.8):**
```swift
public struct PermitMeta: Codable, Equatable {
    // --- P1 minimal ---
    public var jurisdictionId: String?
    public var codeEdition: String?
    // --- P7 full ---
    public var setbacks: SetbackInput?
    public var disclaimerAcknowledgedAt: Date?
    public var lastComplianceRunAt: Date?
    public var lastComplianceResult: ComplianceReport?
    public var peStampRequest: PEStampRequest?
}
public struct SetbackInput: Codable, Equatable {
    public var propertyLines: [CGPoint]; public var requiredSetbackFeet: Double?; public var ahjVerified: Bool
}
public struct PEStampRequest: Codable, Equatable {
    public var requested: Bool; public var reason: String?; public var requestedAt: Date?
}
```
- `DeckDrawingData.permitMeta: PermitMeta? = nil` (the P7 top-level property — introduced minimal P1, completed here). Wire into `CodingKeys` + `init(from:)` with `decodeIfPresent` (mirrors the existing `RailingConfig`/`StairConfig` defensive-decoder pattern in `DeckGeometry.swift`).
- `PermitMeta` itself gets a defensive `init(from:)` (every sub-key `decodeIfPresent`) so a P1-authored minimal block decodes into the full struct with the P7 fields nil.
- Bump `DeckDesign.version` stamping to **7** on P7-authored save.

**Test strategy (`PermitMetaRoundTripTests`):** the three mandatory round-trip tests (contract §5.2). Concrete because signatures are pinned:
```swift
func testEncodeDecodeStable() throws {
    var data = DeckDrawingData()            // baseline
    data.permitMeta = PermitMeta(jurisdictionId: "US-IRC", codeEdition: "IRC 2021 / DCA6-12",
                                 disclaimerAcknowledgedAt: anchorDate)
    let json1 = try data.toJSON()
    let back  = try DeckDrawingData.fromJSON(json1)
    let json2 = try back.toJSON()
    XCTAssertEqual(json1, json2)            // stable
    XCTAssertEqual(back.permitMeta?.jurisdictionId, "US-IRC")
}
func testLightBuildPreservesP7Block() throws {
    // Decode a P7 JSON, re-encode under a build whose CodingKeys lacked permitMeta
    // at P1 — guaranteed preserved via unknownBlocks passthrough (§1.4).
    let p7JSON = try fixtureJSON("deck_v7_with_permitMeta")
    let decoded = try DeckDrawingData.fromJSON(p7JSON)   // simulated light decode path
    let reencoded = try decoded.toJSON()
    XCTAssertTrue(reencoded.contains("\"permitMeta\""))  // NOT stripped
}
func testMalformedPermitMetaDecodesNil() throws {
    let bad = try fixtureJSON("deck_v7_permitMeta_corrupt")  // garbage in permitMeta
    let decoded = try DeckDrawingData.fromJSON(bad)          // must NOT throw
    XCTAssertNil(decoded.permitMeta)                          // sub-block nil, design survives
    XCTAssertFalse(decoded.vertices.isEmpty)                  // rest of design intact
}
```
**Dependencies:** [P1] `DeckDrawingData`, `unknownBlocks`/`AnyCodable` passthrough, `DeckDesign.version`. `ComplianceReport` (Task 4) is referenced by `lastComplianceResult` — author `ComplianceModels.swift` first or land both in one step.
**Code/standard refs:** contract §0.1–0.3, §1.4, §2.2, §2.8, §8.1–8.2. Memory: `crew-deck-blackout-poisoned-cursor`, `deck-sync-stale-overwrite-revert` (why backward-decode preservation is load-bearing).
**Risks:** `CGPoint` Codable round-trip (already used across the model — reuse the existing `CGPoint` coding); `Date` precision drift in `disclaimerAcknowledgedAt` (use the model's existing date coding strategy, anchor tests on a computed date, never a literal — memory `ios-autoschedule-tests-date-brittleness`). `ComplianceReport` nested in the blob means a stale cached result must never be treated as fresh — Task 4 stamps `generatedAt` + `packageEdition` so the UI can show "recomputed needed" when the package edition changed.

---

### Task 2 — Compliance models + LOCKED strings

**Goal.** Define the `ComplianceReport` family and the single sanctioned output strings.

**Interface (verbatim from contract §3.3):**
```swift
public struct ComplianceReport: Codable, Equatable {
    public var mode: ComplianceEngine.Mode
    public var packageEdition: String
    public var generatedAt: Date
    public var findings: [ComplianceFinding]
    public var summaryStatement: String   // LOCKED phrasing (§6.1)
    public var disclaimer: String         // §6.2 verbatim
}
public struct ComplianceFinding: Codable, Equatable, Identifiable {
    public let id: String
    public var item: String
    public var severity: Severity
    public var currentValue: String?
    public var targetValue: String?
    public var codeSection: String
    public var fix: String?
    public var confidence: Confidence
    public var evidence: Evidence?
    public var source: FindingSource
}
public enum Severity: String, Codable { case safetyHazard, marginal, minor, notAssessable }
public enum Confidence: String, Codable { case high, medium, low }
public enum FindingSource: String, Codable { case measured, userEntered, notAssessable }
public struct Evidence: Codable, Equatable { public var photoURL: URL?; public var sceneRef: String? }
```
- Locked string constants (drafted via `ops-copywriter`, but the *clean-pass* phrasing is contractually fixed): `ComplianceStrings.noFailures = "no code failures detected"` and `ComplianceStrings.disclaimer = "This is not a guarantee of full code adherence. Have plans reviewed by a licensed engineer in your jurisdiction."` (contract §6.1, §6.2 verbatim).

**Test strategy:** unit assert the constants equal the contract phrasing exactly (a guard test so no future edit drifts the legal copy). Assert `summaryStatement` is only ever set from the locked-string set (Task 4 covers behavior; here we lock the constants).
**Dependencies:** [P3] none directly, but `ComplianceEngine.Mode` (Task 4) must exist — define `Mode` in `ComplianceEngine.swift` and import.
**Code/standard refs:** contract §3.3, §6.1, §6.2. Roadmap §3 report UX (`ITEM · SEVERITY · CURRENT · TARGET · CODE § · FIX · CONFIDENCE · EVIDENCE`).
**Risks:** legal-copy drift — mitigated by the guard test. `URL` Codable in `Evidence` (standard). Keep `summaryStatement` a stored string (not computed) so the cached report is self-describing.

---

### Task 3 — Per-domain compliance check functions (pure)

**Goal.** Implement the visible-geometry + structural-reconciliation checks as pure functions returning `[ComplianceFinding]`, each reading the `CodePackage` rules (never hard-coded cells).

**Interface (internal to `Compliance/ComplianceChecks/`; called by Task 4):**
```swift
enum GuardChecks {
    static func evaluate(_ data: DeckDrawingData, mode: ComplianceEngine.Mode, package: CodePackage) -> [ComplianceFinding]
}
enum StairChecks   { static func evaluate(_ data: DeckDrawingData, mode: ..., package: CodePackage) -> [ComplianceFinding] }
enum LedgerChecks  { static func evaluate(_ data: DeckDrawingData, mode: ..., package: CodePackage) -> [ComplianceFinding] }
enum StructuralChecks { static func evaluate(_ data: DeckDrawingData, mode: ..., package: CodePackage) -> [ComplianceFinding] }
enum GeometryChecks   { static func evaluate(_ data: DeckDrawingData, mode: ..., package: CodePackage) -> [ComplianceFinding] }
```
Behavior per check:
- **GuardChecks:** reads `RailingConfig.postHeight` (default 36" — IRC R312, drives guard-height finding), `maxPostSpacing`, and `package.guardRules` (36" guard / 30" trigger / 4" opening). The **30"-guard-required trigger** computes deck-height-above-grade from `overallElevation` / per-vertex `elevation` (+ `TerrainModel` grade when present, [P4]); if height ≥ 30" and no guard present → `safetyHazard`. 4" baluster opening near threshold → `confidence: .medium` (photo-assisted in `.asBuilt`).
- **StairChecks:** reads `StairConfig.risePerStep`/`runPerTread`/`treadCount` + `package.stairRules`; uses `StairCalculator.calculate(...)` for uniformity (max rise − min rise ≤ ⅜"); handrail required at 4+ risers (R311.7.8).
- **LedgerChecks:** reads `HouseModel.ledger` ([P5]) — `cladding`/`attachmentAllowed`/`fastenerSchedule`/`lateralConnectors` vs `package.ledgerRules` (R507.9). brick/stone → `attachmentAllowed == false` → finding "ledger attachment not permitted on this cladding — freestanding required". In `.asBuilt`, concealed fasteners/connectors are forced `.notAssessable`.
- **StructuralChecks:** maps [P3] `FramingMember.sizing.outcome` and [P4] `Footing.sizing` into findings — `.outOfEnvelope` → `safetyHazard` + PE; `utilization > 1.0` → fail; `sizing == nil` (LIGHT-authored / not engineered) → `.notAssessable` "not engineered".
- **GeometryChecks:** footprint sanity, post spacing vs beam table envelope, deck-height-above-grade reporting. Shared by both modes.

**Test strategy (one file per check, table-driven against fixtures):**
```swift
func testGuardHeightFailsBelow36() {
    let pkg = try loadFixture("US-IRC-2021")          // guardRules.minGuardHeightInches == 36
    var d = DeckDrawingData(); d.edges = [edge(railingPostHeight: 34)]   // below
    let findings = GuardChecks.evaluate(d, mode: .design, package: pkg)
    let f = findings.first { $0.item == "Guard height" }!
    XCTAssertEqual(f.severity, .safetyHazard)
    XCTAssertEqual(f.targetValue, "36\"")
    XCTAssertEqual(f.codeSection, pkg.guardRules.codeSection)   // cited from package, not literal
}
func testGuardRequiredAt30InAboveGrade() { /* height 32", no guard → safetyHazard, R312 trigger */ }
func testStairRiseUniformity() { /* mixed rise > 3/8" spread → finding via StairCalculator */ }
func testLedgerBrickForcesFreestanding() { /* cladding == .brick → attachment-not-permitted finding */ }
func testAsBuiltConcealedLedgerIsNotAssessable() { /* mode .asBuilt + concealed → severity/source .notAssessable */ }
func testMissingSizingIsNotAssessable() { /* FramingMember.sizing == nil → .notAssessable, not a pass */ }
func testOutOfEnvelopeMemberBecomesSafetyHazard() { /* sizing.outcome == .outOfEnvelope → safetyHazard + PE flag */ }
```
All `codeSection`/`targetValue` assertions read from the **fixture package**, never hard-typed literals — proves the engine is table-driven (§0.5).
**Dependencies:** [P3] `MemberSizingResult`/`EngineOutcome`; [P4] `Footing.sizing`/`TerrainModel`; [P5] `HouseModel.ledger`; existing `StairCalculator`, `RailingConfig`, `StairConfig`, `EdgeType`, `HouseEdgeMaterial`. Fixture `CodePackage` shape from [P3] (`guardRules`/`stairRules`/`ledgerRules`/`envelopeLimits`).
**Code/standard refs:** IRC R312 (guards, 36"/30"/4"), R311.7 (stairs, 7.75"/10"/uniformity/handrail), R507.9 (ledger/lateral). DCA6. BCBC Part 9 (metric). Roadmap §2.6, §3. Contract §6.7 (as-built `.notAssessable`).
**Risks:** photo-assist confidence near the 4" threshold is heuristic — keep it `confidence: .medium/.low`, never auto-fail on an inferred measurement in `.asBuilt`. Metric jurisdictions: convert at the engine boundary via `CodePackage.unitSystem` (contract §5.1) — fixture `CA-BC-2024` exercises this so no imperial assumption leaks. Guard against a `.design`-mode false clean pass when sizing is absent (must be `.notAssessable`, not silently omitted).

---

### Task 4 — `ComplianceEngine` (the two-direction orchestrator)

**Goal.** The single pure entry point that runs every check, assembles findings, sets the LOCKED summary statement, stamps disclaimer/edition/date.

**Interface (verbatim, contract §3.3):**
```swift
public enum ComplianceEngine {
    public enum Mode: String, Codable { case design, asBuilt }
    public static func evaluate(_ data: DeckDrawingData, mode: Mode, package: CodePackage) -> ComplianceReport
}
```
Behavior:
- Run `GeometryChecks`, `GuardChecks`, `StairChecks`, `LedgerChecks`, `StructuralChecks` (Task 3); concat findings.
- **Summary statement (LOCKED, §6.1):** if no `.safetyHazard`/fail finding among **assessable** items (i.e. ignoring `.notAssessable`), `summaryStatement = ComplianceStrings.noFailures` ("no code failures detected"). Otherwise a neutral count phrasing ("N code concerns identified") — **never** "safe"/"compliant"/"will pass".
- **As-built guarantee (§6.7):** in `.asBuilt`, the report ALWAYS contains at least the truly-hidden `.notAssessable` rows (footings, concealed ledger/connectors), so it can never read as a fully clean pass. Assert this in test.
- Stamp `packageEdition = package.edition`, `generatedAt = Date()`, `disclaimer = ComplianceStrings.disclaimer`.

**Test strategy (`ComplianceEngineDesignTests`, `ComplianceEngineAsBuiltTests`, `OutOfEnvelopeTests`):**
```swift
func testCleanDesignSaysNoFailures() {
    let report = ComplianceEngine.evaluate(fullyCompliantDeck, mode: .design, package: pkg)
    XCTAssertEqual(report.summaryStatement, "no code failures detected")
    XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("safe"))
    XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("compliant"))
    XCTAssertEqual(report.disclaimer, ComplianceStrings.disclaimer)
}
func testAsBuiltNeverCleanPass() {
    let report = ComplianceEngine.evaluate(perfectVisibleDeck, mode: .asBuilt, package: pkg)
    XCTAssertNotEqual(report.summaryStatement, "no code failures detected") // hidden rows present
    XCTAssertTrue(report.findings.contains { $0.source == .notAssessable })
}
func testOutOfEnvelopeEmitsNoNumberAndRoutesPE() {
    let report = ComplianceEngine.evaluate(oversizedSpanDeck, mode: .design, package: pkg)
    let f = report.findings.first { $0.severity == .safetyHazard }!
    XCTAssertNil(f.targetValue)         // no fabricated number
    XCTAssertTrue(f.fix?.localizedCaseInsensitiveContains("licensed engineer") ?? false)
}
```
**Dependencies:** Task 2 (models/strings), Task 3 (checks), [P3] `CodePackage`/`EngineOutcome`, [P4] footings, [P5] house.
**Code/standard refs:** contract §3.3, §6.1, §6.5, §6.7. Roadmap §3, §7.
**Risks:** the clean-pass logic is the single highest-liability line in the product — a bug that prints "no code failures detected" when a member is out-of-envelope is unacceptable. Mitigate: the summary derives ONLY from assessable failures and the test suite covers the exact boundary (one out-of-envelope, one notAssessable-only, one fully-clean). Performance: evaluate is O(members+edges); fine on-device.

---

### Task 5 — As-built capture model + guided wizard mapping

**Goal.** The `.asBuilt` data path: an `AsBuiltCapture` value type accumulating wizard answers, mapped onto a `DeckDrawingData` overlay the engine evaluates, with correct `source` tagging.

**Interface (internal):**
```swift
public struct AsBuiltCapture: Codable, Equatable {
    public var measuredGeometry: DeckDrawingData     // from AR/manual (visible)
    public var enteredJoist: FramingMember?          // user-entered hidden structure ([P2] model)
    public var enteredBeam: FramingMember?
    public var fastenerHint: Evidence?               // photo-of-fastener
    public var lateralConnectorsPresent: Bool?
    public var flashingPresent: Bool?
    // mapping
    public func asEvaluableDesign() -> DeckDrawingData   // injects entered members tagged source
}
```
- `asEvaluableDesign()` returns a `DeckDrawingData` where user-entered hidden members are present (so `StructuralChecks` can size/check them) but the audit layer marks their findings `source: .userEntered`; truly-hidden items (footing depth/size) are NOT fabricated — they remain absent so `GeometryChecks`/`StructuralChecks` emit `.notAssessable`.
**Test strategy (`AsBuiltAuditModelTests`):** entered joist 2x8@24" + a span that fails → finding `source: .userEntered`, severity per table; no entered footing depth → footing finding `.notAssessable`; `asEvaluableDesign()` never invents a value the user didn't supply.
**Dependencies:** [P2] `FramingMember`; existing `AR/` measure path + `OCRService` seam (photo hints); Task 2 `Evidence`.
**Code/standard refs:** roadmap §3 (auto-check / ask-user / punt tiers). Contract §6.7.
**Risks:** the wizard must never let a "don't know" answer become a pass — default unknown → `.notAssessable`. Reuse existing AR; do not build a new capture engine (roadmap scope). Wizard edge-cases (back/skip/abandon) audited with the `wizard-audit` skill before shipping.

---

### Task 6 — `DraftingCanvas` (shared true-scale CG core)

**Goal.** The reusable drawing core every plan sheet renders over — true-scale coordinate transform, dimension strings, leaders, callouts, scale bar, north arrow, hatch fills. The thing `DeckShareRenderer` does NOT have and the contract forbids bolting on.

**Interface (internal):**
```swift
struct DraftingCanvas {
    let scale: DrawingScale                 // inchesPerFoot (contract §3.5)
    let pageRect: CGRect
    func modelToPage(_ p: CGPoint) -> CGPoint                 // canvas→sheet at scale
    func drawDimension(from: CGPoint, to: CGPoint, in ctx: CGContext, label: String)
    func drawLeaderCallout(at: CGPoint, text: String, in ctx: CGContext)
    func drawScaleBar(in ctx: CGContext); func drawNorthArrow(in ctx: CGContext)
    func hatch(_ poly: [CGPoint], pattern: HatchPattern, in ctx: CGContext)
}
public struct DrawingScale: Codable, Equatable { public var inchesPerFoot: Double }  // verbatim
```
**Test strategy:** pure-math tests for `modelToPage` at known scales (1/4"=1' → 12 model-inches maps to 0.25 page-inch×72pt). Snapshot a reference sheet with one dimension + one callout + scale bar; compare via `ImageRenderer → XCTAttachment`.
**Dependencies:** existing `DeckShareRenderer` CG patterns (learn from, don't extend); `PolygonMath`/`DimensionEngine` for real-world lengths; `effectiveScaleFactor`.
**Code/standard refs:** contract §3.5, roadmap §6 ("permit set needs its own viewport/scale/annotation/title-block engine"). NCS sheet conventions.
**Risks:** coordinate-space confusion (canvas points vs real inches vs page points) — `DeckVertex.position` is canvas space, `effectiveScaleFactor` converts to real inches; centralize all three transforms here so no sheet re-derives them. Raster-backed PDF means hairlines must be ≥ 0.5pt to survive (DeckShareRenderer uses 0.5).

---

### Task 7 — Plan sheets + `TitleBlockRenderer`

**Goal.** One renderer per `PlanSheetKind`, plus the compliant title block stamped on every sheet.

**Interface (verbatim, contract §3.5):**
```swift
public enum PlanSheetKind: String, Codable, CaseIterable {
    case planView, framingPlan, elevation, crossSection, sitePlan, detailCallout
}
public struct TitleBlock: Codable, Equatable {
    public var projectName: String; public var address: String?
    public var packageEdition: String; public var generatedDate: Date
    public var disclaimer: String; public var peStamp: PEStampRequest?
}
```
- **PlanViewSheet** — to-scale footprint + dimension strings (reads `DeckDrawingData` geometry).
- **FramingPlanSheet** — joists/beams/posts/ledger/blocking from [P2] `FramingPlan`, with member callouts (size/spacing) when [P3] sizing present; "NOT ENGINEERED" watermark when `sizing == nil`.
- **ElevationSheet** — from [P5] `HouseModel.floorLineFeet`/`storyHeights` + [P4] `TerrainModel` grade; front/rear/side.
- **CrossSectionSheet** — footing→post→beam→joist→decking→guard stack (DCA6 typical section).
- **SitePlanSheet** — deck vs [P7] `SetbackInput.propertyLines`; "verify setbacks with AHJ" note.
- **DetailCalloutSheet** — footing + post-base connection details (Simpson hardware from [P4] `PostFootingConnection`).
- **TitleBlockRenderer** — NCS-style block; `disclaimer` (§6.2) stamped on EVERY sheet; PE-stamp area when `peStamp.requested`.

**Test strategy (`PlanSetSnapshotTests`):** one snapshot per sheet kind from a fully-engineered fixture deck; assert the title-block disclaimer text appears (render to image, but primarily assert the data path produces a sheet > min byte size and the right page size). `FramingPlanSheet` with `sizing == nil` → asserts "NOT ENGINEERED" path taken.
**Dependencies:** Task 6 `DraftingCanvas`; [P2]/[P3]/[P4]/[P5]/[P7] blocks; existing geometry + `PolygonMath`.
**Code/standard refs:** contract §3.5; roadmap §2.8 (framing plan/elevation/cross-section/site plan/detail); NCS title block; DCA6 section detail.
**Risks:** elevation/section need house + terrain; if [P5]/[P4] blocks are absent the sheet must render a labeled "house model not provided" placeholder rather than a wrong drawing. Sheet sizes: support letter + ARCH-D via `DrawingScale`; keep within `UIGraphicsPDFRenderer` page bounds.

---

### Task 8 — `PlanSetEngine` (assembly: permit set, single sheet, calc report)

**Goal.** Assemble selected sheets into a single multi-page PDF; render the structural calc report; render a single sheet.

**Interface (verbatim, contract §3.5):**
```swift
public enum PlanSetEngine {
    public static func renderPermitSet(_ data: DeckDrawingData, compliance: ComplianceReport,
        sheets: [PlanSheetKind], titleBlock: TitleBlock, package: CodePackage) -> Data
    public static func renderSheet(_ kind: PlanSheetKind, data: DeckDrawingData,
        scale: DrawingScale, titleBlock: TitleBlock) -> Data
    public static func renderCalcReport(_ framing: FramingPlan, footings: FootingPlan, package: CodePackage) -> Data
}
```
- `renderPermitSet` — `UIGraphicsPDFRenderer`, one `beginPage` per `PlanSheetKind` in canonical order, title block + disclaimer per page; embeds a compliance-summary page from the passed `ComplianceReport`.
- `renderCalcReport` — per-member table (DCA6 style): each `FramingMember` → size, span, allowable, **utilization**, limiting check, cited section, plus the `EngineAssumptions` block (load/species/grade/soil/edition) printed up front (§6.6). Footings similarly.

**Test strategy (`PlanSetEngineTests`):**
```swift
func testPermitSetPageCountMatchesSheets() {
    let pdf = PlanSetEngine.renderPermitSet(deck, compliance: report,
        sheets: [.planView, .framingPlan, .crossSection], titleBlock: tb, package: pkg)
    let doc = PDFDocument(data: pdf)!
    XCTAssertEqual(doc.pageCount, 4)   // 3 sheets + 1 compliance summary page
}
func testEverySheetStampsDisclaimer() { /* extract page text, assert §6.2 string on each */ }
func testCalcReportSurfacesAssumptions() {
    let pdf = PlanSetEngine.renderCalcReport(framing, footings: footings, package: pkg)
    let text = PDFDocument(data: pdf)!.string!
    XCTAssertTrue(text.contains(pkg.edition))           // edition stamped
    XCTAssertTrue(text.localizedCaseInsensitiveContains("live load"))  // assumptions surfaced
}
func testEmptyDataReturnsValidNonEmptyPDF() { /* graceful: still a valid PDF, placeholder content */ }
```
Plus `PlanSetSnapshotTests` attaches rendered pages.
**Dependencies:** Task 6, Task 7; Task 4 `ComplianceReport`; [P2] `FramingPlan`, [P4] `FootingPlan`, [P3] `CodePackage`/`EngineAssumptions`.
**Code/standard refs:** contract §3.5, §6.2, §6.4 ("code data current to [date]" from `package.publishedDate`), §6.6; roadmap §2.8.
**Risks:** large engineered decks → many CG nodes per page; render off the main actor and show progress (heavy-draw on 3-year-old phones — roadmap §6). `PDFDocument` text extraction in tests depends on `CoreText` drawing real glyphs (it does via `drawText`). Memory spikes on multi-page renders — render sequentially, release per-page contexts.

---

### Task 9 — Full BOM via `PermitBOMEmitter` (additive `ComponentEmitter` rows)

**Goal.** Emit the full schedule (lumber + fastener + hardware + concrete) as additive `DesignComponentRow`s, without renaming any existing component type.

**Interface (internal; called from `ComponentEmitter.emit`):**
```swift
enum PermitBOMEmitter {
    static func emit(_ data: DeckDrawingData) -> [DesignComponentRow]   // joist|beam|post|footing|fastener|concrete rows
}
```
- New `component_type` strings only: `joist`, `beam`, `post`, `footing`, `fastener`, `concrete`. Metadata via the existing `AnyCodable` (extended P1 to nested values). Concrete volume from [P4] `ConcreteTakeoff`.
**Test strategy (`PermitBOMEmitterTests`):** engineered fixture → asserts new rows present with correct counts/sizes; **regression assert** that the existing `railing`/`deck_board`/`stair_set`/`gate`/`post_set` rows are byte-identical to pre-P7 `ComponentEmitter` output (no rename/break — contract §3.6 doc comment in `ComponentEmitter.swift`).
**Dependencies:** existing `ComponentEmitter`/`DesignComponentRow`/`AnyCodable`; [P2] `FramingPlan`, [P4] `FootingPlan`/`ConcreteTakeoff`.
**Code/standard refs:** contract §3.6 (additive component rows), roadmap §2.1 (framing takeoff), §2.8 (full schedule).
**Risks:** `AnyCodable` nested-value support is a P1 deliverable — verify it landed before emitting nested metadata; fall back to scalar keys if not. Do not double-count members already represented by legacy rows.

---

### Task 10 — `CADExporter` (vector PDF ships; DWG/DXF cost-flagged)

**Goal.** Vector-PDF export façade; DWG/DXF explicitly gated behind a cost decision, never silently invoking a paid path.

**Interface (internal):**
```swift
public enum CADExportFormat: String, CaseIterable { case vectorPDF, dwg, dxf }
public enum CADExportResult { case data(Data); case requiresPaidConverter(format: CADExportFormat, note: String) }
public enum CADExporter {
    public static func export(_ data: DeckDrawingData, format: CADExportFormat,
        sheets: [PlanSheetKind], titleBlock: TitleBlock, package: CodePackage) -> CADExportResult
}
```
- `.vectorPDF` → `.data(PlanSetEngine.renderPermitSet(...))`.
- `.dwg` / `.dxf` → `.requiresPaidConverter` (3rd-party lib/server cost TBD — roadmap §8, foundation spec §11). Surface the cost note in UI; do NOT commit a converter without an explicit cost decision (CLAUDE.md cost-transparency rule).
**Test strategy (`CADExporterTests`):** `.vectorPDF` returns `.data` non-empty; `.dwg`/`.dxf` return `.requiresPaidConverter` (no network, no silent paid call).
**Dependencies:** Task 8.
**Code/standard refs:** roadmap §8 (DWG/DXF cost flag), §2.8. Contract §6 (no over-claim).
**Risks:** scope creep into a real DWG path — explicitly OUT until cost-approved. `UIGraphicsPDFRenderer` is raster-backed; "vector PDF" here means CG vector primitives (lines/text are vector in the PDF), which is the on-device ceiling — true CAD vector needs the flagged converter. State this honestly in the UI.

---

### Task 11 — Capability-gated views + ViewModel wiring

**Goal.** Surface compliance/audit/permit/PE in the UI, gated by `.compliance`/`.permitPlanSet`/`.peStamp`, disclaimer-gated, with the single upsell stub in LIGHT.

**Interface / behavior:**
- `DeckBuilderViewModel` gains capability-checked methods: `runCompliance(mode:)`, `openAsBuiltWizard()`, `generatePermitSet(sheets:scale:)`, `requestPEStamp(reason:)`. Each first checks `capabilities.contains(.compliance)` etc.; if absent, the surface is hidden and only `ComplianceUpsellStub` is reachable.
- `ComplianceDisclaimerGate` must be acknowledged (sets `PermitMeta.disclaimerAcknowledgedAt`) before any report/permit generates (§6.2).
- Out-of-envelope findings auto-surface `PEStampRequestView`.
- Persist `permitMeta` (incl. cached `lastComplianceResult`) via `DeckStore.saveDeck`.
- Views consume `OPSStyle`/`OPSDesignKit` tokens; numbers JetBrains Mono tabular; empty `—`; copy via `ops-copywriter`; report list summary-first + severity-tiered (roadmap §3 UX).
**Test strategy (`CapabilityGatingTests`):** with `.light` provider, the VM's compliance/permit/PE methods are no-ops/throw-gated and the views report hidden; with `.full`, they invoke the engines. ViewModel-level (no interactive UI test — visual QA is a human step per contract §5.2). Wizard flows audited via `wizard-audit` skill.
**Dependencies:** [P1] `DeckCapabilities`/`CapabilityProvider`/`DeckStore`; Tasks 4/5/8; `OPSDesignKit`.
**Code/standard refs:** contract §4 (gating rules), §6.2; roadmap §3 (report UX). CLAUDE.md design-judgment (state-aware layout; once-ever setup like jurisdiction never owns prime space — put it behind the report entry, not a permanent tab).
**Risks:** the disclaimer gate must be unskippable for generation but must not nag on every open (acknowledge once, stamp the date, re-prompt only if the package edition changed). Global-modal presentation over open sheets may need the dedicated-`UIWindow` pattern (memory `ios-global-modal-dedicated-window`) for the disclaimer.

---

### Task 12 — Code-package test fixtures

**Goal.** Checked-in JSON fixtures mirroring a known subset of real edition cells, so every sizing/compliance assertion has a hand-verifiable expected value (contract §5.2, §0.5).

**Deliverable:** `OPSTests/Fixtures/CodePackages/US-IRC-2021.test.json` (imperial/psf: joist/beam/post/footing rows, guard/stair/ledger rules, `envelopeLimits`) and `CA-BC-2024.test.json` (metric/kPa). Each decodes to [P3] `CodePackage`. These are the **test mirror** of the production Supabase-delivered package — never hand-typed into UI.
**Test strategy:** a fixture-integrity test decodes both into `CodePackage` and asserts the known cells (e.g. 2x8 SPF #2 @16"oc → known allowable span; min soil 1500 psf / 75 kPa). These values back every Task 3/4/8 assertion.
**Dependencies:** [P3] `CodePackage`/`SpanTable`/`PostTable`/`FootingTable`/`GuardRules`/`StairRules`/`LedgerRules`/`EnvelopeLimits` Codable shapes.
**Code/standard refs:** IRC 2021 / AWC DCA6-12; BCBC 2024 Part 9. Contract §3.4, §5.2, §6.8 (tables ingested verbatim, versioned; App. H paywalled → no roof-cover claims).
**Risks:** fixture cells must come from the actual adopted-edition tables, not invented; mark each fixture with its source edition + the subset scope. Keep fixtures small (a handful of representative rows) — they verify the engine, not the production package's completeness.

---

## Cross-cutting verification & sequencing

- **Build/test:** device build `xcodebuild -scheme OPS -destination 'generic/platform=iOS'`; tests on `iPhone 17, OS 26.5`; `build-for-testing` to confirm compile, `test` to run. Copy `Secrets.xcconfig` into the worktree first. Grep logs for `SUCCEEDED` (exit-code masking). New-file SourceKit "cannot find type" is index noise — trust `xcodebuild`.
- **Suggested order:** Task 12 (fixtures) + Task 2 (models) → Task 1 (schema) → Task 3 (checks) → Task 4 (engine) → Task 5 (as-built) → Task 6 (canvas) → Task 7 (sheets) → Task 8 (plan-set) → Task 9 (BOM) → Task 10 (CAD) → Task 11 (views). Tasks 5, 9, 10 are independent of the drafting chain and can parallelize.
- **Mandatory per-phase round-trip tests** (contract §5.2) covered by Task 1; every new block decode-tested.
- **Bible update:** on landing P7, update `ops-software-bible` deck-designer/compliance section (engines, schema v7, compliance posture) per CLAUDE.md.
- **Commits:** atomic, conventional (`feat(decks): ComplianceEngine …`), staged by name, no AI attribution; new branch only if P7 is a large multi-step buildout (it is — `feat/ios-decks-phase7-compliance` is appropriate). Pushes require explicit permission.

## Risks (phase-level)

1. **Liability correctness is paramount.** A false "no code failures detected" is the worst possible bug. The summary derives only from assessable failures; out-of-envelope and notAssessable paths are tested at the boundary; the locked strings are guard-tested. As-built can never read clean.
2. **Predecessor drift.** P7 consumes P2–P5 schema and P3/P4 engines. If a predecessor's real signature diverges from the contract, **amend the contract first** (contract preamble) — do not silently adapt. The literal TDD steps are finalized at phase start against the real tree.
3. **Heavy on-device rendering** of large engineered decks (multi-page permit sets) on old phones — render off-main, sequential pages, progress UI, release contexts.
4. **DWG/DXF cost** — explicitly flagged and OUT until a cost decision; vector-PDF is the shipped ceiling.
5. **IRC Appendix H** (overhead roof-cover code) is paywalled/unverified — no roof-cover compliance claims (contract §6.8); overhead structures (P6) get geometry + structural reuse, not Appendix-H compliance findings, until the text is validated.
6. **Metric jurisdictions** — convert at the engine boundary via `CodePackage.unitSystem`; the BCBC fixture exercises it so no imperial assumption leaks into findings or sheets.
