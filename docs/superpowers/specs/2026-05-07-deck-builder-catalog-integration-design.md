# Deck Builder ↔ Catalog Integration — Design Spec

**Date:** 2026-05-07
**Author:** Jackson Sweet (with Claude)
**Status:** Pending review
**Origin bugs:** `6192bcc5` (re-opened — see § 1.2)
**Predecessor spec:** `docs/superpowers/specs/2026-05-06-ios-catalog-variant-model-design.md` (the catalog model)
**Related code (catalog side, already shipped):**
`OPS/Services/DesignToEstimateAdapter.swift` · `OPS/Services/ProductConfigurationResolver.swift` · `OPS/Services/RecipeResolver.swift` · `OPS/Services/CutListMaterializer.swift` · `OPS/DataModels/Supabase/Catalog/CompanyDefaultProduct.swift`
**Related code (deck side, target of this spec):**
`OPS/DeckBuilder/Models/DeckGeometry.swift` · `OPS/DeckBuilder/Models/DeckLevel.swift` · `OPS/DeckBuilder/Models/DeckDrawingState.swift` · `OPS/DeckBuilder/DeckBuilderViewModel.swift` · `OPS/DeckBuilder/Views/AssignmentWheelView.swift` · `OPS/DeckBuilder/Views/PropertySheetView.swift` · `OPS/DeckBuilder/Views/MaterialPickerSheet.swift` · `OPS/DeckBuilder/Engine/EstimateGeneratorService.swift` · `OPS/DataModels/DeckDesign.swift`

---

## 1. Problem

### 1.1 The contract gap

Catalog Phase 10–11 shipped the **billing & cut-list resolution loop** without the **drawing input** that feeds it.

`DesignToEstimateAdapter.generate(...)` (`OPS/Services/DesignToEstimateAdapter.swift:46-93`) parses a deck design's `drawingDataJSON` and looks for a top-level array:

```json
{
  "components": [
    { "component_type": "railing",     "metadata": { "linear_feet": 24, "corners_count": 4, "color": "Black", "mount_type": "Topmount", "mount_surface": "Concrete" } },
    { "component_type": "deck_board",  "metadata": { "sqft": 312,        "color": "Brown",  "material": "composite" } },
    { "component_type": "stair_set",   "metadata": { "tread_count": 6,   "width": 48,      "color": "Black",  "mount_type": "Surface" } }
  ]
}
```

The deck builder **does not emit this array**. `DeckDesign.drawingDataJSON` serializes `DeckDrawingData` (vertices/edges/footprint/surfaces/levels/levelConnections only). There is no `components` key, no `component_type` discriminator, and none of the metadata keys the adapter queries (`color`, `mount_type`, `mount_surface`, `material`, `corners_count`, `tread_count`, `width`, `count`, `height`, `hours`, `days`).

The adapter's parser falls through silently — the comment on line 178-181 acknowledges this:

> The existing `DeckDrawingData` Codable struct does not yet carry a `components: [{component_type, metadata}]` array — that's coming from the Deck Builder agent in a separate session. For now we parse the JSON manually with `JSONSerialization` looking for an optional `"components"` key, and gracefully no-op if it's missing.

Until the deck side emits the vocabulary, **every existing design generates zero adapter line items** and the catalog cut-list pipeline (`RecipeResolver` → `CutListMaterializer` → `task_materials`) never fires. The user reports estimates that "look right" because `EstimateGeneratorService` (the legacy path) keeps working — but the new richness (configurable products, modifiers, recipes, installer cut lists) is dead on arrival.

### 1.2 Why bug `6192bcc5` is re-opened

The catalog commits (`983df08`, `64c2973`) that "close" `6192bcc5` shipped the recipe → cut-list infrastructure correctly, but the drawing-side emission half — without which the recipes are unreachable — was explicitly out of scope and deferred to "the deck builder agent in a separate session" (per the adapter source). The bug stays open until the deck side closes the loop.

### 1.3 Adjacent legacy path

`EstimateGeneratorService.generateLineItems(from: drawingData)` is the **current** estimate path: it walks `DeckDrawingData` directly and emits flat `GeneratedLineItem` rows with `category: "Surface"|"Railing"|"Stairs"|"Substructure"|"Other"` and `productId` as taken from the assigned `Product`. It does not invoke `DesignToEstimateAdapter`, does not consume `CompanyDefaultProduct`, does not snapshot `configured_options`, and does not resolve recipes. Both paths must coexist during migration; this spec defines how they coexist and when each fires.

## 2. Goals & Non-Goals

### Goals

- Emit a `components: [{component_type, metadata}]` array into `DeckDesign.drawingDataJSON` on every save, derived deterministically from the existing geometry + assignment state.
- Capture the catalog metadata vocabulary (`color`, `mount_type`, `mount_surface`, `material`, `corners_count`) at the points the user already configures geometry — extending `RailingConfig`, `StairConfig`, `DeckSurface` with typed fields rather than free-form strings.
- Surface those metadata fields in the existing assignment UI (`AssignmentWheelView`, `PropertySheetView`) when the assigned default `Product` has a corresponding `ProductOption`. Don't add a new sheet — add fields to the sheets users already touch.
- Wire a "Generate Estimate" code path that calls `DesignToEstimateAdapter.generate(design:companyId:modelContext:)` and merges its output with `EstimateGeneratorService` output (or replaces it where the adapter has a definitive answer). Behavior is governed by company-level Defaults (presence of `CompanyDefaultProduct` rows) — when no defaults exist, the legacy path runs unchanged.
- Backfill `components` for legacy designs on first load so the adapter and recipe loop work for existing data without a mass migration.
- Keep `EstimateGeneratorService` operational. It remains the source of truth for warning line items (missing elevation, AR accuracy notes, multi-level connections) that the catalog adapter does not produce.

### Non-Goals (this session)

- Authoring `CompanyDefaultProduct` rows for any company — UX for "Defaults" management already exists at `DefaultsManageSheet.swift`. Companies set their own defaults; we don't seed.
- Authoring rich `Product` rows (options, modifiers, recipes) for any company — that's hand-crafted SQL, owned by the catalog spec's data migration session.
- Removing `EstimateGeneratorService`. It coexists indefinitely. The line that retires it is the day every design has full catalog coverage *and* every company has Defaults set — neither is true today.
- Web parity. ops-web Deck Builder reads/writes the same `drawingDataJSON`; the components key is forward-compatible (web ignores keys it doesn't know). When ops-web wants the same one-click flow, it implements its own emitter.
- AR snapping redesign, save reliability, stairs cluster, scanner audit, layout/Z-index. Those are separate specs in this series (clusters B–I from the session handoff).

## 3. Architecture overview

### 3.1 Components-as-projection

`components` is a **derived projection** of the existing geometry, not a new source of truth. Every emit is recomputed from the canonical `DeckDrawingData`. This means:

- We do not store components anywhere except in the serialized JSON.
- Edits to vertices/edges/configs flow into the next save's components automatically.
- The adapter contract is one-way: deck → catalog. No round-trip.

The emitter lives at `OPS/DeckBuilder/Engine/ComponentEmitter.swift` (NEW, ~300 lines) and exposes one entry point:

```swift
enum ComponentEmitter {
    /// Returns the `components` array as Codable rows, ready for inclusion
    /// in DeckDrawingData's JSON. Pure function — no I/O, no side effects.
    /// Multi-level designs flatten components across levels with a `level_id`
    /// metadata key for downstream traceability.
    static func emit(_ data: DeckDrawingData) -> [DesignComponentRow]
}

struct DesignComponentRow: Codable {
    let componentType: String              // "railing" | "deck_board" | "stair_set" | "gate" | "post_set"
    let metadata: [String: AnyCodable]     // see § 3.3 per-type schema
    enum CodingKeys: String, CodingKey {
        case componentType = "component_type"
        case metadata
    }
}
```

`AnyCodable` is a thin wrapper that round-trips `Int`, `Double`, `String`, `Bool` through `Codable`. Implementation lives in the same file.

### 3.2 DeckDrawingData carries the projection

```swift
// OPS/DeckBuilder/Models/DeckDrawingState.swift  (existing struct)
struct DeckDrawingData: Codable {
    // ...existing fields preserved...

    /// Catalog-facing projection of the drawing. Recomputed from geometry
    /// on every save via ComponentEmitter.emit(self) — never read for
    /// rendering. The adapter (DesignToEstimateAdapter) is the only consumer.
    /// Absent on legacy JSON; backfilled on first load (see § 6.1).
    var components: [DesignComponentRow]? = nil
}
```

`toJSON()` recomputes `components = ComponentEmitter.emit(self)` immediately before encoding (see § 4.1). `fromJSON()` accepts JSON with or without `components` — the field is `Optional` so legacy decode succeeds.

### 3.3 Per-component-type schema

The metadata keys are **exactly** what `DesignToEstimateAdapter.computeQuantity(unit:metadata:)` (`OPS/Services/DesignToEstimateAdapter.swift:148-173`) and `buildConfigured(...)` (line 97-144) consume. Adding keys is fine; renaming is a contract break.

| `component_type` | Source | Metadata keys (required unless noted) |
|---|---|---|
| `railing` | One per `DeckEdge` with non-nil `railingConfig` | `linear_feet` (Double, edge length minus stair span), `corners_count` (Int, count of vertices on this edge that join two railing-bearing edges with a non-straight angle), `color` (String, from `RailingConfig.color`), `mount_type` (String, from `RailingConfig.mountType`), `mount_surface` (String, from `RailingConfig.mountSurface`), `level_id` (String, multi-level only), `edge_id` (String, traceback) |
| `deck_board` | One per `DeckSurface` with non-empty `assignedItems` *or* footprint when surface store is empty | `sqft` (Double, real-world area of the surface — uses the same per-surface area math as `EstimateGeneratorService.perSurfaceLineItems`), `color` (String, from `DeckSurface.color` — NEW field), `material` (String, from `DeckSurface.boardMaterial` — NEW field), `level_id` (optional), `surface_id` (traceback) |
| `stair_set` | One per `DeckEdge` with non-nil `stairConfig`; one per `LevelConnection` (multi-level) | `tread_count` (Int, computed via `StairConfig.calculateTreadCount` or override), `width` (Double, inches), `color` (String, from `StairConfig.color` — NEW field), `mount_type` (String, derived from edge type — `Surface` for normal, `Top` if connection's upper level matches, etc.), `level_id` (optional), `edge_id` or `connection_id` |
| `gate` | One per `DeckEdge` with `assignedItems` containing an item flagged as a gate (see § 3.5) | `count` (Int, default 1), `width` (Double, inches), `color` (String), `mount_type` (String), `mount_surface` (String), `edge_id` |
| `post_set` | One per railing config; emitted alongside the railing component | `count` (Int, computed via `DimensionEngine.postCount(...)`), `height` (Double, inches — derived from `RailingConfig.postHeight` — NEW field, defaults 36"), `color` (String, mirrors railing color), `mount_type` (String, mirrors railing mount type) |

**Why `post_set` is its own component:** the catalog spec lists it as a distinct `DesignComponentType`. A picket railing's posts and balusters resolve to different recipe variants (posts pin to one family, balusters to another). Emitting them as separate components lets the company's Default-Product mapping route them independently.

**Why `corners_count` lives on `railing`, not on a separate component:** the catalog model treats corners as a configurable Product **option** (`scaled_by_option_id` on the corner-hardware recipe row). A 24-foot railing with 4 corners is one component with `corners_count: 4`, not 4 corner-components. The recipe row `Corner Hardware Kit` scales by the option value.

### 3.4 New typed fields on existing geometry structs

These are the user-facing knobs the metadata projection reads. All non-optional fields default to a sensible per-type value so existing designs continue to round-trip.

```swift
// DeckGeometry.swift — RailingConfig (additions)
struct RailingConfig: Codable, Equatable {
    var railingType: RailingType
    var maxPostSpacing: Double
    var assignedItems: [AssignedItem] = []

    // NEW — catalog metadata vocabulary
    var color: String = "Black"             // free-text; matches Product option values
    var mountType: String = "Topmount"      // "Topmount" | "Sidemount" | "Surface" — see § 3.6 vocabularies
    var mountSurface: String = "Surface"    // "Surface" | "Concrete" | other free-text per company
    var postHeight: Double = 36.0           // inches; drives post_set.height
}

// DeckGeometry.swift — StairConfig (additions)
struct StairConfig: Codable, Equatable {
    // ...existing fields preserved (width, risePerStep, runPerTread, treadCount, etc)...

    // NEW — catalog metadata vocabulary
    var color: String = "Black"
    var mountType: String = "Surface"       // "Surface" | "Top" | "Side" — different vocabulary than railing
}

// DeckGeometry.swift — DeckSurface (additions, in DeckDrawingState.swift today)
struct DeckSurface: Codable, Equatable {
    // ...existing fields preserved (id, label, vertexIds, assignedItems, etc)...

    // NEW — catalog metadata vocabulary
    var color: String = "Brown"
    var boardMaterial: String = "composite"  // "composite" | "pvc" | "cedar" | "treated" | other
}

// DeckGeometry.swift — AssignedItem (one new optional flag)
struct AssignedItem: Identifiable, Codable, Equatable {
    // ...existing fields preserved...

    // NEW — flags an assignment as a gate (drives gate component emission per § 3.3).
    // Defaults false. Surfaced as a "This is a gate" toggle in the assignment sheet
    // when the picked Product's category contains "gate" (case-insensitive).
    var isGate: Bool = false
}
```

**Why free-text strings, not enums:** the catalog allows companies to author option values per Product (`product_option_values.value`). Black/White/Topmount aren't a fixed vocabulary; they're whatever the company sets. Storing strings keeps the deck side decoupled from any one company's vocabulary while letting the assignment sheet *render* a picker over the matching Product's options when one exists. § 4.3 covers the picker UX.

### 3.5 Gate detection

Gates are `assignedItems` on a `DeckEdge` flagged with `isGate: true`. Detection in the assignment sheet: when the user picks a Product whose `Product.category` (or tag) contains "gate" (case-insensitive), the toggle defaults on. Otherwise off. The user can override either way.

The emitter walks each edge's `assignedItems`, collects items where `isGate == true`, and emits one `gate` component per such item. Width = `edge.dimension`; count = number of gate items on the edge (almost always 1).

### 3.6 Default vocabularies

When the user has not picked a Product yet (or the picked Product has no options), the emitter defaults to:

| Field | Default | Rationale |
|---|---|---|
| `color` | "Black" (railing/stair) / "Brown" (deck board) | Matches the most common single-color systems. |
| `mount_type` (railing) | "Topmount" | Most common deck attachment. |
| `mount_surface` (railing) | "Surface" | Wood-frame assumption; user overrides for concrete. |
| `mount_type` (stair) | "Surface" | Stairs land on grade in the typical case. |
| `material` (deck board) | "composite" | Most common new-construction. |
| `post_height` | 36.0 inches | IRC R312 minimum. |

Defaults exist so the emitter can fire even on partially-configured designs. The adapter's option-resolution logic (`buildConfigured` in DesignToEstimateAdapter:97) treats missing/unmatched values as "leave option unset" and the resolver picks the option's `default_value` from `ProductOption.defaultValue`. Result: a barebones drawing still produces line items.

## 4. Integration points

### 4.1 `DeckDrawingData.toJSON` recomputes components

```swift
// DeckDrawingState.swift — existing toJSON()
extension DeckDrawingData {
    func toJSON() -> String {
        var copy = self
        copy.components = ComponentEmitter.emit(self)
        // ... existing encode logic against `copy` ...
    }
}
```

This guarantees every save (autosave, manual save, X-button save — addressed in the save-reliability spec) carries up-to-date components. The runtime cost is single-digit milliseconds for designs of typical size (<100 edges); benchmark on the largest Canpro design as part of verification.

### 4.2 Backfill on legacy load

The first time a legacy design is loaded post-deploy, `fromJSON` decodes with `components == nil`. `DeckBuilderViewModel.load(...)` checks for this case:

```swift
if data.components == nil {
    // Legacy design — recompute components from current geometry. Mark dirty
    // so the next autosave persists the projection.
    data.components = ComponentEmitter.emit(data)
    self.markDirty()
}
```

Designs the user never reopens stay legacy on disk forever — that's fine. The adapter's no-op fallback handles it. Designs the user reopens get projected on next save without any user-visible change.

### 4.3 Assignment sheet metadata UI

`AssignmentWheelView` (the wheel that appears when a vertex/edge/surface is tapped) and `PropertySheetView` (the longer-form editor) both currently expose railing/stair/material configuration. They gain conditional metadata fields:

```
[ASSIGN — RAILING CONFIG]
   Type:           [Picket ▾]
   Spacing:        [84"]
   Color:          [Black ▾]    ← NEW. Picker if Product's "Color" option exists; free-text otherwise.
   Mount type:     [Topmount ▾] ← NEW. Same treatment.
   Mount surface:  [Surface ▾]  ← NEW. Same treatment.
   Post height:    [36"]        ← NEW. Stepper.
   Items:          [ + ADD MATERIAL ]
                   • PICKET — Black — 84" max spacing
```

**Picker vs. free-text logic**: when the user has assigned a default `Product` (via `MaterialPickerSheet` — covered in § 4.4), the field renders as a picker over that Product's `ProductOption` values. When no Product is assigned, the field renders as free-text input with the per-type default pre-filled (§ 3.6). When a Product is assigned but the Product has no matching option, the field collapses to read-only display of the default value (it's not configurable for this Product but the metadata still gets emitted).

This mirrors the catalog spec's § 4.3 line-item form behavior — same form, different fields based on Product richness.

**Why fields appear even without a Product:** the metadata is emitted for the adapter regardless. The user sees "Color: Black ▾" so the data they're committing to is visible, not hidden behind an opaque default.

### 4.4 Default Product hint at assignment time

`MaterialPickerSheet` today queries every active `Product`. When a user is assigning items to a railing on a single-level design, the sheet pre-pins the company's default railing Product (if one exists in `CompanyDefaultProduct`) at the top of the list with a "// DEFAULT" tag. This is purely a UX nudge — the user can pick anything. Mechanism:

```swift
// MaterialPickerSheet.swift — additions
// Pass the surface context in (railing | stair | deck_board | gate | post_set | unspecified)
// from the caller (AssignmentWheelView). Use it to look up the matching default.
@Query private var companyDefaults: [CompanyDefaultProduct]

private var defaultProductId: String? {
    guard let ctx = surfaceContext else { return nil }
    return companyDefaults.first { $0.componentType == ctx }?.productId
}
```

### 4.5 Generate Estimate flow

The Deck Builder gains a `GENERATE ESTIMATE` action (toolbar item or share-sheet action — UX decision in § 7). When tapped:

```swift
// DeckBuilderViewModel.swift — new method
func generateCatalogEstimate() async -> EstimateDraft {
    // 1. Trigger save first so drawingDataJSON is current.
    await save()

    // 2. Adapter pass — produces line items keyed to default Products with
    //    configured_options snapshots ready for line_item insertion.
    let adapter = DesignToEstimateAdapter()
    let adapterItems = adapter.generate(
        design: currentDesign,
        companyId: companyId,
        modelContext: modelContext
    )

    // 3. Legacy pass — produces warning rows (missing elevation, AR accuracy)
    //    and any items the company has not set a default for.
    let legacy = EstimateGeneratorService.generateLineItems(from: drawingData)

    // 4. Merge: adapter wins for component_types where a CompanyDefaultProduct
    //    exists; legacy fills the gap. De-dupe rule below.
    return merge(adapterItems: adapterItems, legacyItems: legacy)
}
```

**Merge / de-dupe rule (§ 4.5.1):**

- For each `component_type` that has a `CompanyDefaultProduct` row → take the adapter's line items for that type. Drop legacy items whose `category` corresponds to the same type (`railing` → `Railing` & `Substructure-Posts`, `stair_set` → `Stairs`, `deck_board` → `Surface`).
- For each `component_type` with no default → keep legacy items.
- Always carry through legacy warning items (`stairs (missing elevation)`, AR accuracy note, level connection items in multi-level mode) — the adapter does not produce them.
- The resulting `EstimateDraft` is what `EstimateFormSheet` opens with, fully populated, user-editable.

`EstimateDraft` is the existing struct that `EstimateFormSheet` consumes; we extend it to carry `configured_options` and `resolved_options_label` per row so the snapshot lands on `line_items` correctly when the user saves the estimate.

### 4.6 Cut list at install task creation

The catalog's `CutListMaterializer` (`OPS/Services/CutListMaterializer.swift`) is already wired to fire when an install task is created from a line item carrying a Product reference. No deck-builder change required — once `line_items.product_id` and `line_items.configured_options` are populated correctly (steps above), the materializer reads them and writes `task_materials` rows pinned to concrete `catalog_variant_id`. Verify by reading CutListMaterializer once and confirming the contract.

## 5. iOS implementation outline (NOT for this session — the writing-plans phase consumes this)

### 5.1 New files

- `OPS/DeckBuilder/Engine/ComponentEmitter.swift` (~300 lines): the projection logic + `DesignComponentRow` + `AnyCodable`.
- `OPS/DeckBuilder/Tests/ComponentEmitterTests.swift` (~400 lines): per-component-type unit tests covering single-level, multi-level, defaults, gate detection, post_set co-emission with railing.

### 5.2 Modified files

- `OPS/DeckBuilder/Models/DeckGeometry.swift`: add typed fields to `RailingConfig`, `StairConfig`, `AssignedItem`. Add `isGate` flag.
- `OPS/DeckBuilder/Models/DeckDrawingState.swift`: add `components: [DesignComponentRow]?` to `DeckDrawingData`. Add `color`, `boardMaterial` to `DeckSurface`.
- `OPS/DeckBuilder/DeckBuilderViewModel.swift`: backfill on legacy load; new `generateCatalogEstimate()` async method.
- `OPS/DeckBuilder/Views/AssignmentWheelView.swift`: conditional metadata fields per § 4.3.
- `OPS/DeckBuilder/Views/PropertySheetView.swift`: same metadata fields, longer-form layout.
- `OPS/DeckBuilder/Views/MaterialPickerSheet.swift`: surface-context-aware default highlighting per § 4.4.
- `OPS/DeckBuilder/Views/DeckToolbar.swift`: add `GENERATE ESTIMATE` action.
- `OPS/DeckBuilder/Engine/EstimateGeneratorService.swift`: zero changes (legacy path stays intact). Verify the merge rule (§ 4.5.1) doesn't double-count.

### 5.3 Bible updates

Same-session-as-code per CLAUDE.md:

- `ops-software-bible/03_DATA_ARCHITECTURE.md`: document the `components` projection in the DeckDesign / drawing_data section. List the per-type metadata schema. Cross-reference the catalog spec.
- `ops-software-bible/07_SPECIALIZED_FEATURES.md`: extend the Deck Builder section with the catalog integration flow, the Generate Estimate action, the metadata vocabulary surface in assignment sheets.
- `ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`: trace drawing → components → adapter → line_items → task_materials end-to-end, replacing today's narrative that ends at line_items.

## 6. Migration

### 6.1 Data migration

None required server-side. `DeckDesign.drawingDataJSON` is text; the components key is additive and forward-compatible. Existing rows stay readable by old clients (web ignores unknown keys). New iOS clients backfill on first load (§ 4.2).

### 6.2 SwiftData migration

Adding fields with defaults to embedded `Codable` structs (RailingConfig, StairConfig, DeckSurface, AssignedItem) does not require a SwiftData schema bump — the parent `DeckDesign` model is unchanged. The structs decode old JSON because every new field has a default value; they re-encode with the new fields populated.

### 6.3 ops-web compatibility

ops-web's Deck Builder reads/writes the same `drawingDataJSON`. Adding the `components` key is no-op for web (it ignores unknown keys). Web's continued saves will *strip* the components key on round-trip if it doesn't preserve unknown fields — this is the one risk to verify. Mitigation: at iOS load time, if `components` is missing **and** the design has a `lastSavedAt` newer than the iOS local cache, assume web stripped it and backfill (§ 4.2). The user-visible behavior is unchanged.

If web does preserve unknown fields (the typical Codable behavior), the components key survives round-trips and no backfill fires on web saves.

### 6.4 Rollback

This change is fully backwards-compatible — the components key is additive. Rollback = revert the iOS commits; legacy `EstimateGeneratorService` was never touched and continues to work. The `CompanyDefaultProduct` rows already in the database are unused but harmless. No SQL revert needed.

## 7. Risks & open questions

### 7.1 Risks

- **Vocabulary drift between deck and catalog.** If a company's Product option value is "Top Mount" (with a space) and the deck builder default is "Topmount" (no space), the resolver sees no match and the recipe falls through to the option's `default_value`. Mitigation: § 4.3's picker reads the actual `ProductOptionValue.value` strings whenever a Product is assigned, so user-driven assignments stay aligned. Free-text editing is the leak — partly mitigated by autocomplete suggestions from the active Product's option values when one is assigned.
- **Multi-level component_type ambiguity.** A `LevelConnection`'s stairs are functionally a `stair_set` but their dimensions come from `connection.stairConfig` (already a `StairConfig`) and the rise is computed from `elevationDifference`. The emitter must include connection stairs as `stair_set` components with `level_id` set to the upper level. Verify in tests.
- **Performance of recompute-on-save.** Every save runs the emitter. For a 100-edge multi-level design the emitter is O(edges + surfaces + connections) — sub-millisecond expected. Verify by running `ComponentEmitter.emit` on the largest design fixture and asserting <5ms wall-clock.
- **Stale projection if save fails.** If autosave fails partway through, the on-disk JSON has stale geometry but possibly fresh components — or vice versa. The fix is the save-reliability spec (cluster B) which ensures atomic save. Until then, the emitter runs at the last possible moment in `toJSON()` so it's always in sync with what's about to be written.

### 7.2 Open questions

- **Where does GENERATE ESTIMATE live?** Toolbar button is most discoverable. Share-sheet action is more conservative. Cleanest is a primary button on the deck-builder share/export sheet alongside the existing "Material Summary" / share actions. **Defer to interface-design pass once flow lands.**
- **Should `corners_count` round-trip from estimate edits back to the design?** No — line-item snapshot is one-way (catalog spec § 3.4). The user editing the corner count on the estimate edits the line item's `configured_options`; the design's corner inference stays as-is.
- **Multi-level deck_board surfaces — one component or one per surface?** One per surface, per § 3.3. Each surface bills against its own area; collapsing them would lose the per-surface material assignments.
- **AR-captured metadata?** The current AR flow (`ARPerimeterView`) records vertices, edges, dimensions. It does not yet record colors or mount types. AR captures geometry only; metadata stays in the assignment sheets. Reconfirm in the AR snapping spec (cluster C).
- **Gates on edges with railing — render relationship?** A gate breaks the railing run. The railing component should subtract the gate width from `linear_feet` (mirroring how `EstimateGeneratorService` already subtracts stair width). Document in the emitter; verify in tests.

## 8. Testing strategy (high-level)

- **Unit (`ComponentEmitterTests`):**
  - Empty drawing → `[]`.
  - Single-level closed quad with railing on every edge + 4 corners → 4 `railing` rows + 4 `post_set` rows, `corners_count: 0` per (corners are at vertices shared between edges, not within an edge).
  - Single-level with one stair edge → 1 `stair_set`, `tread_count` matches `StairConfig.calculateTreadCount`.
  - Multi-level with one connection → 1 connection-derived `stair_set` with `level_id` set to upper level.
  - Surface assignment with `boardMaterial = "pvc"` → `deck_board` carries `material: "pvc"`.
  - Gate assignment on a 12 ft railing edge → 1 `gate` + 1 `railing` with `linear_feet: 9` (gate is 36").
- **Integration (adapter end-to-end):**
  - Hand-crafted `DeckDesign` with components → seed `CompanyDefaultProduct` + Product + options + values → call `DesignToEstimateAdapter.generate(design:companyId:modelContext:)` → assert correct line items, `configuredOptions`, `resolvedUnitPrice`, `resolvedOptionsLabel`.
  - Same design with no `CompanyDefaultProduct` rows → adapter returns `[]`; merge falls back to legacy.
- **Recipe end-to-end:** Adapter line items → save as estimate → install task created → `CutListMaterializer` writes `task_materials` rows pinned to `catalog_variant_id`.
- **Backfill:** Load a legacy design (drawingDataJSON without components) → assert components are computed and the design is marked dirty for next save.
- **Performance:** 100-edge multi-level fixture → emit runs in <5ms.
- **Round-trip with ops-web:** save on iOS → load on web → save on web → reload on iOS → confirm components either survive or get backfilled.

## 9. Approval

This spec assumes the catalog model is correct (per `2026-05-06-ios-catalog-variant-model-design.md`) and only addresses the deck-side input that closes the loop. The contract surface is small (one new key in JSON, one new emitter file, four new typed fields, one new toolbar action), the migration is forward-compatible, and the legacy path stays intact.

Once accepted, the next step is invoking `superpowers:writing-plans` to translate this into a phased implementation plan with explicit sub-tasks, verification commands, and review checkpoints — coordinated with whichever WIP branch the deck builder cluster lands in.
