# Deck Materials List — Design Spec

**Date:** 2026-07-06
**Status:** Approved by Jackson (product design approved in session; spec not user-reviewed per working contract — correctness verified against code + live schema)
**Surfaces:** ops-ios (crew-facing Deck tab + Vinyl Order sheet)

## 1. Overview

Vinyl deck jobs get an auto-calculated **materials list** on the project Deck tab: the vinyl cut list, drip edge flashing, clip, 90° angle flashing, and glue buckets. In the Vinyl Order sheet (and the Details-tab marker), **MARK ORDERED** freezes the full materials list as an ordered snapshot. Crew can adjust three consumable presets (stick lengths, glue coverage) with live recalculation.

Non-vinyl projects see zero change.

## 2. Approved Product Decisions

| Decision | Ruling |
|---|---|
| Which surfaces count as vinyl | Smart auto-detect. Surface with a vinyl material assigned → vinyl. Surface with a non-vinyl area material → excluded. Surfaces with no area material → vinyl **iff** the project has a job-level vinyl signal: a task whose TaskType display name contains "vinyl" (case-insensitive), OR `drawingData.config.vinylCatalogItemId` is set. No signals → no materials section. |
| Flashing presentation | **Totals + stick counts only. No per-run cut lengths.** e.g. `46 FT · 6 STICKS @ 8'`. |
| Stick length presets | Drip edge **8'**, 90 flash **8'**, clip **10'** — each independently editable in the materials list UI with live recalculation. |
| Stairs | No bearing on flashing. A stair-carrying edge gets drip edge across its full span like any open edge. Stair treads excluded from vinyl area and glue. |
| Clip | 1:1 with drip edge — same edge set, same total feet, its own stick length/count. |
| Glue | `ceil(actual vinyl surface area ÷ coverage)` buckets. Coverage default **400 sq ft/bucket**, crew-adjustable. Surface area, NOT ordered-with-waste area. |
| Interior seams | An edge shared by two detected surfaces is interior — no flashing of any kind. |
| Drift after ordering | Materials list keeps showing the ordered snapshot; a quiet `DESIGN CHANGED SINCE ORDER` flag appears when a recompute (using the snapshot's settings) no longer matches the snapshot. Presets are locked while ordered. |
| Mark-ordered entry points | Both existing MARK ORDERED surfaces (VinylOrderSheet PROJECT MARKER section + DetailsTabView `VinylOrderMarkerSection`) snapshot identically via one shared service. CLEAR ORDERED deletes the snapshot. |

## 3. Existing Infrastructure (verified 2026-07-06)

- `DeckEdge.edgeType` ∈ {`house_edge`, `deck_edge`}; parapet exists as `RailingConfig.railingType == .parapetWall` (on deck edges) and as `HouseEdgeMaterial.parapet` (house-edge cladding). [`OPS/DeckBuilder/Models/DeckGeometry.swift`]
- `VinylCutListEngine.makePlan(surfaces:settings:availableOffcuts:)` — pure planner; already consumes per-surface `VinylOrderSurfaceEdge` (with `edgeType`). [`OPS/DeckBuilder/Engine/VinylCutListEngine.swift`]
- Surface inputs built in `DeckBuilderViewModel.vinylOrderSurfaceInputs(scope:)` via persisted `DeckSurface` ↔ `DetectedSurface` Jaccard matching (`SurfaceReconciler.rebindThreshold`); strict scale via `vinylOrderEffectiveScale` (stale-dimension guard → `scaleFactor` → all-`.scale` prescale fallback → inference from confirmed dims). [`OPS/DeckBuilder/DeckBuilderViewModel.swift:2640-2809`]
- MARK ORDERED writes `projects.vinyl_order_status/vinyl_ordered_at/vinyl_ordered_by` (columns verified live) via `DataController.updateProjectFields`; local projection `ProjectVinylOrderMarker`. [`OPS/DataModels/Project.swift:538-607`]
- `deck_designs.drawing_data` is **jsonb** (verified live) — new persisted fields ride inside `DeckDrawingData` JSON with zero schema migration. Sync via existing `DeckDesign` needsSync pipeline.
- Deck tab: `DeckTabView` (viewer + level chips), `@Query`-driven, project-scoped. [`OPS/Views/Components/Project/Tabs/DeckTabView.swift`]
- Job tasks: `ProjectTask.taskType` → `TaskType.display`. [`OPS/DataModels/TaskType.swift`, `ProjectTask.swift`]
- `BuiltInMaterial.areaStandards` currently has **no vinyl entry**. [`OPS/DeckBuilder/Models/BuiltInMaterial.swift`]

## 4. Data Model Additions (all inside `DeckDrawingData` JSON — no DB migration)

### 4.1 `DeckMaterialsSettings` (new top-level optional node `materialsSettings`)

```swift
struct DeckMaterialsSettings: Codable, Equatable {
    var glueCoverageSqFt: Double = 400   // clamp 100...1000, step 25
    var dripStickFeet: Double = 8        // clamp 4...20, step 1
    var ninetyStickFeet: Double = 8      // clamp 4...20, step 1
    var clipStickFeet: Double = 10       // clamp 4...20, step 1
}
```

### 4.2 `DeckMaterialsSnapshot` (new top-level optional node `orderedMaterials`)

Frozen at mark-ordered time:

```swift
struct DeckMaterialsSnapshot: Codable, Equatable {
    var orderedAt: Date
    var orderedBy: String?
    var settings: DeckMaterialsSettings          // presets as they stood
    var vinylSettings: VinylOrderSettings        // roll width / seam / wrap / direction as ordered
    var vinylColor: String                       // "" → FIELD CONFIRM
    var vinylOrderedSqFt: Int
    var vinylSurfaceAreaSqFt: Double
    var cutGroups: [CutGroup]                    // {surfaceLabel, count, lengthInches, rollWidthInches}
    var dripEdgeFeet: Double; var dripSticks: Int
    var clipFeet: Double;     var clipSticks: Int
    var ninetyFeet: Double;   var ninetySticks: Int
    var glueAreaSqFt: Double; var glueBuckets: Int
}
```

**Decoding discipline:** follow `DeckGeometry.swift` house style exactly — explicit `CodingKeys`, custom `init(from:)` with `decodeIfPresent` + defaults on EVERY field, no `let x: T? = nil` (breaks memberwise init AND decode — known gotcha). Both nodes decode as `decodeIfPresent(...) ?? nil` on `DeckDrawingData` so all legacy JSON round-trips. Encode-side: `toJSON()` includes them when non-nil; `.sortedKeys` already set.

`VinylOrderSettings` (and `VinylLayoutDirection`) gain `Codable` conformance — all-scalar struct + String-raw enum, synthesizable, additive.

## 5. Vinyl Detection

New pure resolver (with the input builder, § 7):

1. Build surface inputs (per level when multi-level) from persisted `surfaces` matched to `detectedSurfaces` (extracted matcher, § 7). When the persisted store is empty (legacy design never opened in the builder since DECK-NEW-1), fall back to detected faces directly, labels `Surface N`.
2. Classify each surface's **area** `assignedItems`:
   - *vinyl-ish*: `id == "std.decking.vinyl"` (new standard), OR `name` contains "vinyl" (case-insensitive), OR its `productId` resolves to a CatalogItem whose name/description contains "vinyl".
   - Surface with ≥1 vinyl-ish area item → **vinyl**.
   - Surface with area items, none vinyl-ish → **excluded**.
   - Surface with no area items → **unassigned**.
3. Job-level vinyl signal := (any non-deleted `ProjectTask` on this project whose `taskType.display` contains "vinyl", case-insensitive) OR (`config.vinylCatalogItemId` non-nil, non-blank after trim).
4. Vinyl set := explicit vinyl surfaces ∪ (unassigned surfaces iff job-level signal).
5. Materials section renders iff vinyl set non-empty. Catalog lookup for 2's product resolution is injected (the resolver stays pure; DeckTabView supplies a `[String: CatalogItem]` id-map from its model context; VinylOrderSheet likewise).

Add `BuiltInMaterial(id: "std.decking.vinyl", name: "Vinyl Membrane", subtitle: "Duradek, Tufdek style sheet vinyl", icon: "square.grid.3x3")` to `areaStandards` (additive-only file contract respected).

## 6. Quantity Math

### 6.1 Edge classification (per vinyl surface face)

For each boundary segment (consecutive vertex pair in face order), matched to a `DeckEdge` bidirectionally (same rule as `vinylOrderSurfaceEdges`):

| Condition (first match wins) | Class |
|---|---|
| Segment's vertex pair bounded by ≥2 detected faces (interior seam) | none |
| Matched edge `edgeType == .houseEdge` | 90 flash |
| Matched edge `railingConfig?.railingType == .parapetWall` | 90 flash |
| Otherwise (incl. unmatched segments, stair-carrying edges, full span) | drip edge + clip |

Interior test runs against ALL detected faces on the level (vinyl or not) — a seam is interior regardless of the neighbor's material.

Length per segment: matched `edge.dimension` when `> 0`, else canvas length ÷ scale (mirrors `DeckTabView.edgeLengthInches`). Multi-level: classify per level, sum across levels.

### 6.2 Totals, sticks, glue

- `dripFeet = clipFeet = Σ(open segments) / 12`; `ninetyFeet = Σ(house+parapet segments) / 12` — exact sums.
- Display totals as whole feet, rounded **up** (`ceil`), JetBrains Mono.
- `sticks(class) = max(0, Int(ceil(exactFeet / stickFeet)))` from the exact (pre-display) sum. Zero-length class → row shows `—` per empty-state convention (never "N/A").
- `glueAreaSqFt = Σ vinyl-face PolygonMath.realWorldArea / 144` (self-intersecting faces skipped, matching `totalRealWorldArea`); `buckets = Int(ceil(glueAreaSqFt / glueCoverageSqFt))`.
- Vinyl block: `VinylCutListEngine.makePlan` over the vinyl set with settings seeded exactly like VinylOrderSheet's defaults path (`VinylOrderSettings.default` + `applyConfiguredCatalogProduct` catalog-config resolution; no banked-offcut seeds in the tab's read-only context). Rendered as color/product line, grouped cuts (`VinylCutGroup` lines — the vinyl cut list IS shown; only flashing omits per-run lengths), ordered sq ft.

## 7. Shared Extraction (no behavior change)

Two pieces of `DeckBuilderViewModel` become pure, reusable helpers so `DeckTabView` never instantiates the builder view model:

1. **Scale:** `VinylOrderScaleResolver.resolve(_ data: DeckDrawingData) -> Double?` — verbatim relocation of `vinylOrderEffectiveScale` + `canUsePrescaleFallbackForVinylOrder` + `inferredVinylOrderScaleFromConfirmedDimensions` + `vinylOrderScaleMeasurements` + tolerance constants. View model delegates to it (existing call sites unchanged in behavior; unit-test parity).
2. **Inputs:** `DeckMaterialsInputBuilder.surfaceInputs(for data: DeckDrawingData, scale: Double) -> [VinylOrderSurfaceInput]` — read-only equivalent of `vinylOrderSurfaceInputs(scope: .allSurfaces)`: persisted↔detected Jaccard matching (reuse `SurfaceReconciler.rebindThreshold`) WITHOUT calling `reconcileSurfaces()` (no mutation from a read-only tab), plus the empty-store detected-faces fallback (§ 5.1). The view model keeps its mutating reconcile-then-build path; the matcher core is shared.

New engine: `DeckMaterialsEngine.compute(data:settings:vinylPlan:vinylSurfaces:) -> DeckMaterialsList` — pure, in `OPS/DeckBuilder/Engine/DeckMaterialsEngine.swift`, alongside `VinylCutListEngine`. `DeckMaterialsList` carries everything § 6 produces plus per-class exact feet for tests.

## 8. Mark-Ordered Snapshot

New `DeckMaterialsOrderService` (follows `VinylOffcutInventoryService` shape: `@MainActor struct`, companyId/userId/modelContext):

- `markOrdered(projectId:design:plan:settings:...)`:
  1. Compute `DeckMaterialsSnapshot` from the current materials list.
  2. Write it into `design.drawingData.orderedMaterials` (local-first; `needsSync` via existing accessor).
  3. `updateProjectFields` with the existing `ProjectVinylOrderFields` trio.
  4. If (3) throws → revert (2) locally, rethrow. (2) is local-only so cannot fail remotely at this point.
- `clearOrdered(projectId:design:)` — remove snapshot node, clear project fields, same compensation order.
- **VinylOrderSheet path:** snapshot computed from the sheet's live `plan` + current `settings` + the design's `materialsSettings` presets.
- **DetailsTabView path** (`ProjectDetailsViewModel.setVinylOrdered`): design := `DeckDesign.displayCandidate(in:forProjectId:)`. Materials computed with default-seeded vinyl settings (§ 6.2). No design / no renderable geometry / no vinyl set → marker toggles exactly as today, no snapshot (materials section absent anyway).
- **Drift:** recompute live materials using `snapshot.settings` + `snapshot.vinylSettings`; drift := any **seed- and label-independent** value differs — the multiset of ALL cut pieces by `(lengthInches, rollWidthInches)` (purchased + reused together: offcut seeding only re-labels provenance, never changes the cut geometry, so this comparison is stable whether or not banked offcuts existed at order time), flashing exact feet ±0.1', glueAreaSqFt ±0.1, vinyl surface count. Surface renames and stock changes do NOT flag drift; geometry/classification/scale changes do. Snapshot's stored `cutGroups` remain purchased-only (they display "what was ordered").
- While a snapshot exists: materials list renders snapshot values, presets read-only, `ORDERED <DATE>` stamp (+ `DESIGN CHANGED SINCE ORDER` when drifted).

## 9. UI — Deck Tab `// MATERIALS` Section

Below the viewer inside `designViewer`'s VStack (page scrolls via ProjectDetailsView's ScrollView). Visual language: existing project-tab section pattern (section header `// MATERIALS` in `OPSStyle.Typography.metadata` + tracking, card surfaces, `OPSStyle` tokens only, JetBrains Mono numbers via `dataValue`/`monospacedDigit`). States:

1. **Hidden** — no vinyl set (non-vinyl jobs: tab byte-identical to today).
2. **Confirm dimensions** — vinyl set non-empty but `VinylOrderScaleResolver` returns nil → single banner row `CONFIRM ONE EDGE LENGTH` (existing copy, existing warning banner pattern), no numbers.
3. **Live** — VINYL (color line, cut groups, `ORDER <N> SQ FT`), DRIP EDGE / CLIP / 90 FLASH rows (`46 FT · 6 STICKS @ 8'`), GLUE row (`3 BUCKETS · 1 PER 400 SQ FT`). Inline steppers (VinylOrderSheet `settingStepper` pattern; light haptic on change) for the three stick lengths + coverage. Empty class → `—`.
4. **Ordered** — snapshot values, `ORDERED <DATE>` stamp (`successStatus`), presets locked (steppers hidden, values inline), drift flag line when applicable (`warningStatus`).

Preset edits persist to `drawingData.materialsSettings` (design write → syncs company-wide). Gate: visible with the tab (existing `deck_builder` feature + `deck_builder.view` assigned-scope gating via ProjectDetailsView); preset editing allowed at `deck_builder.view` (calculator preference, not geometry — approved product call); MARK ORDERED gates unchanged (`projects.edit` + marker rules).

All user-facing copy through `ops-copywriter` register: terse, UPPERCASE labels, no exclamation points.

## 10. Verification

- **Engine unit tests** (`OPSTests`): classification matrix — house edge, parapet-railing edge, open edge, interior seam (two faces), stair-carrying edge (full span), unmatched segment, multi-level sum, per-class stick rounding (exact-multiple and +1" over), glue rounding (exact multiple, +1 sq ft), zero-class `—` semantics, detection matrix (explicit vinyl / excluded / unassigned+task-signal / unassigned+config-signal / no signal), legacy-JSON decode (no new keys), snapshot round-trip, drift true/false, scale-resolver parity with pre-extraction behavior.
- **Snapshot proofs**: BooksSnapshotTests-style harness (UIHostingController + UIWindow + drawHierarchy) rendering states 2–4 → PNGs to `docs/artifacts/`.
- **Build**: `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` (never simulator for plain build); tests on the simulator destination. Check for parallel xcodebuild sessions first; worktree builds pass `-clonedSourcePackagesDirPath .spm-local` + copy `Secrets.xcconfig`.
- **audit-design-system** pass before UI is called done (zero hardcoded color/spacing/radius/font).

## 11. Bible Updates (same session as implementation)

- `ops-software-bible/07_SPECIALIZED_FEATURES.md` — Deck Builder section: materials list, detection rules, snapshot semantics, new JSON nodes.
- `ops-software-bible/03_DATA_ARCHITECTURE.md` — `deck_designs.drawing_data` new optional keys (`materialsSettings`, `orderedMaterials`); note additive-only JSON discipline.

## 12. Out of Scope

- Stair tread vinyl / nosing flashing (explicitly excluded).
- Termination-bar / transition hardware at vinyl↔non-vinyl seams (interior seams get nothing).
- Web surfacing of the materials list (data is readable in `drawing_data` when web wants it).
- Flashing stock/inventory integration (glue/flashing are not `catalog_stock_units` citizens in this pass).
- Changes to CREATE ORDER + NOTE (catalog draft order flow untouched).
- Per-run flashing cut lists (totals + sticks only, per approved decision).
