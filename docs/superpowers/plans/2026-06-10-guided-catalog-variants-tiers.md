# Guided Catalog Setup — Option-Priced Variants & Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a guided-catalog line carry **option-priced tiers** entered as ONE line (Sedan/SUV/Truck, lot-size small/med/large, model/finish) instead of N near-duplicate lines, and let a create-new assembly **material define option axes** (Color → black/white; Color × Thickness → a 24-variant matrix) that generate a properly **labeled** variant family — closing the single highest-value unmet wish from all four cold-start audits.

**Architecture:** Pure UI/flow + client-logic changes on `feat/guided-catalog-variants-tiers` (child of `feat/guided-catalog-setup`). **Zero schema change** — every primitive already exists in prod and is already consumed by a live read path:
- **Tiers (services/goods)** are written as `product_options` (one `select` option) + `product_option_values` (one per tier) + `product_pricing_modifiers` (an `add_flat` delta per non-default tier). The estimate builder **already reads these**: `ProductPickerSheet` routes any product with `optionCount > 0` to `LineItemEditSheet`, which `seedDefaultsForOptions()` pre-selects the default and `ProductConfigurationResolver.resolve()` prices via `base_price + Σ fired modifiers`, snapshotting `resolved_unit_price`/`configured_options`/`resolved_options_label` onto the line item. **No estimate-builder logic changes** (one read-side display addition: render the chosen tier on the estimate row).
- **Material variants** are written as `catalog_options` + `catalog_option_values` + `catalog_variants` + `catalog_variant_option_values` on a `catalog_item` family. Stock browse (`StockListView`/`Grid`/`Table` via `EnrichedVariantRow.variantLabel`) **already labels** these by option value. The recipe row is **variant-pinned to the first generated variant** (RecipeResolver requires a variant pin or a `$option` selector; a nil-selector family-pin is silently dropped from the cut list).

**Tech Stack:** Swift / SwiftUI / SwiftData, `OPSStyle` tokens, `ProductRepository` / `ProductRichnessRepository` / `CatalogRepository` / `ProductBundleItemRepository`, `ProductConfigurationResolver`, XCTest (OPSTests). All repo methods + DTOs used below **already exist** (verified) — **zero net-new repo methods, zero net-new DTOs, zero migration.**

---

## Critical gate — verified before any code (do not re-litigate)

| Concern | Verdict | Evidence |
|---|---|---|
| Does the estimate builder **read** option-priced pricing? | **YES** | `ProductPickerSheet.handleSelection` (`optionCount > 0` → `LineItemEditSheet`); `ProductConfigurationResolver.resolve` (`price = basePrice`; `add_flat`/`add_per_unit` → `price += amount`); snapshot at `LineItemEditSheet.save` (`resolvedUnitPrice`/`configuredOptionsJSON`/`resolvedOptionsLabel`). |
| Do tier modifiers actually **fire**? | **YES** | `ProductConfigurationResolver.fires()` returns true when `triggerValueId` matches the selected value id. Our modifiers are **always** `triggerValueId`-pinned; a single `select` option means **at most one** modifier fires per line, so the resolver's modifier ordering is irrelevant and the nil-trigger dead path (a real pre-existing gap for bare `add_flat`) is **never exercised**. |
| `products.tiered_pricing_json`? | **DO NOT USE** | Column **does not exist** in prod (Swift-only field, never read). Writing it would be a no-op half-feature. |
| Write path for product options? | **EXISTS** | `ProductRichnessRepository.createOption/createOptionValue/createPricingModifier` + `CreateProductOptionDTO/CreateProductOptionValueDTO/CreateProductPricingModifierDTO`. |
| Write path for catalog options? | **EXISTS** | `CatalogRepository.createOption/createOptionValue/createVariantOptionValue(variantId:optionValueId:)` + `CreateCatalogOptionDTO/CreateCatalogOptionValueDTO`. |
| RLS / anon-write? | **OK** | Every target table has one `company_isolation` policy, `roles={public}` (anon+authenticated), `cmd=ALL`, predicate `company_id = private.get_user_company_id()` — identical to `products`/`catalog_items`/`catalog_variants` which the shipped flow already writes. Insert **parent before child**. |
| `product_materials` family-pin? | **VALID but cut-list drops it** | `chk_product_materials_pin_xor_family` allows `catalog_item_id`-only rows, BUT `RecipeResolver.swift` skips a family-pin with nil `variant_selector` (`guard let variantId else { continue }`). → **Pin the multi-variant recipe to the first generated variant.** |
| Generated variants visible/labeled in stock? | **YES, already** | `StockView.EnrichedVariantRow.variantLabel` = `optionPairs.map(\.value.value).joined(" · ")`; `StockListView`/`StockGridView`/`StockTableView` render it; fallback to family name. No extra work needed there. |
| CHECK constraints satisfied | **YES** | `product_options.kind ∈ {select,…}`; `modifier_kind ∈ {add_flat,…}`; `products.kind ∈ {service,material,package}`, `pricing_unit ∈ {each,flat_rate,linear_foot,sqft,hour,day}`, `type ∈ {LABOR,MATERIAL,OTHER}`. |

---

## Audit → wish traceability

| Audit wish | Company | Built by |
|---|---|---|
| Sedan/SUV/Truck tiers on one service line | Auto Detailing (P1-1) | Scope 1 (T1–T6) |
| Lot-size tiered services (small/med/large) | Landscaping (P1) | Scope 1 (T1–T6) |
| Model/SKU + sizes tiers on a good | Plumbing (P0-2, tier half) | Scope 1 (T1–T6) |
| Black/white piece variants, **labeled by option value not SKU** | Deck & Rail (P0-3) | Scope 2 (T7–T11) |
| 24-variant vinyl matrix (12 colors × 2 thicknesses) | Deck & Rail (P0-3) | Scope 2 (T7–T11) — generate-variants matrix |

(Plumbing's bulk CSV/markup and the volume/mass stock-counter remain in the deferred backlog from iteration-2 — out of scope here.)

---

## File structure

| File | Responsibility | Change |
|---|---|---|
| `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift` | Drafts + resume snapshot | + `ProductTierRow`, `ProductLineTiers`; `ProductLineDraft.tiers`; `SavedProductLine.tierCount`/`tierAxisLabel`; snapshot `currentSchemaVersion` 3→4 |
| `OPS/Services/Catalog/GuidedCatalogSetup/AssemblyDraft.swift` | Assembly working state | + `AssemblyMaterialAxis`; `AssemblyMaterialDraft.axes` + pure `cleanAxes`/`variantComboCount`/`hasUsableAxes`/`variantCombos` |
| `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift` | Commit logic + pure derivation | + `TierSpec` pure derivation; `saveTieredProductLine`; tiered branch in `saveProductLine`; `commitMaterialMatrix` + matrix branch in `saveAssembly`; local-insert fix on the no-axis material path |
| `OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift` | Services/Goods module UI | + tier disclosure + editor; gate the sell/cost row on `tiers == nil`; tier suffix in added-list |
| `OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift` | Add-material sheet | + `// VARIANTS` create-new disclosure; pick-existing labeling via `CatalogVariantLabeler` |
| `OPS/Views/Catalog/Shared/CatalogVariantLabeler.swift` | **NEW** shared variant labeler | extract the canonical option-value label (from `AddProductMaterialSheet.variantLabel`) into one reusable enum |
| `OPS/Views/Estimates/EstimateDetailView.swift` | Estimate read display | render `resolvedOptionsLabel` on the line-item row (so the chosen tier shows) |
| `OPSTests/GuidedCatalogSetupTierTests.swift` | **NEW** tier derivation + resolver-fires tests | pure `TierSpec` math + a resolver round-trip proving the written tier prices correctly |
| `OPSTests/GuidedCatalogSetupVariantTests.swift` | **NEW** matrix derivation + label tests | pure `cleanAxes`/`variantCombos`/cap + `CatalogVariantLabeler` |
| `OPSTests/GuidedCatalogSetupModelTests.swift` | draft round-trip | extend `test_draftStore_roundTripsAndClears` fixture with a tiered line (v4) |

**Design-system & copy compliance (acceptance criteria for every UI task):** every new control reuses an existing OPSStyle-traced pattern — `nestedCard()`, `CatalogFieldLabel`, `CatalogSectionHeader`, `CatalogTextFieldStyle`, `UnitPickerField`, `opsPrimaryButtonStyle`, `OPSStyle.Colors.*`/`Layout.spacing*`/`Typography.*`. No hardcoded color/spacing/radius/font. Touch targets ≥ 44pt. Numbers use `.monospacedDigit()` (JetBrains Mono tabular). Motion stays on `OPSStyle.Animation.page` with the reduced-motion fallback already in the flow — **no new animation introduced**, so the animation-studio skills do not apply. All new strings are the **ops-copywriter-approved** copy in the "Approved copy" block below — no improvisation.

### Approved copy (ops-copywriter pass complete)

**Scope 1 (tiers):** turn-on `// PRICE BY OPTION` · turn-off `// BACK TO ONE PRICE` · helper `Same item, different sizes or grades — a price for each.` · axis label `Option name` · axis placeholder `Size` · rows header = axis name uppercased (fallback `OPTIONS`) · tier label placeholder `e.g. Sedan` · add button `ADD <AXIS>` (fallback `ADD OPTION`) · validation `// EACH OPTION NEEDS A NAME`, `// EACH OPTION NEEDS A PRICE`, `// OPTION NAMES MUST BE UNIQUE` (reuse existing `// MUST BE A NUMBER`, `// OFFLINE — SAVES PAUSED`, `// NAME ALREADY USED`) · added-line suffix `3 sizes` (derived; fallback `3 options`).

**Scope 2 (variants):** header `// VARIANTS` · helper `Comes in colors or sizes? List them — you get a variant for each.` · `Add an option` / `Add a second option` · placeholders `e.g. Color` / `e.g. Black` · `Add value` · a11y `Remove option` / `Remove value` · count `24 variants` / `1 variant` / `12 × 2 = 24 variants` · over-cap `Too many. Keep it under 100 — trim a few values.`

---

## Verified write signatures (use verbatim — do not guess)

```swift
// CreateProductDTO — positional order (synthesized Codable init):
// companyId, name, description, basePrice, unitCost, unit, pricingUnit, unitId,
// category, categoryId, sku, thumbnailUrl, kind, type, isTaxable,
// taskTypeId, taskTypeRef, linkedCatalogItemId, [var bundlePricingMode = nil]

// ProductRichnessRepository (companyId:):
func createOption(_ dto: CreateProductOptionDTO) async throws -> ProductOptionDTO
func createOptionValue(_ dto: CreateProductOptionValueDTO) async throws -> ProductOptionValueDTO
func createPricingModifier(_ dto: CreateProductPricingModifierDTO) async throws -> ProductPricingModifierDTO
// CreateProductOptionDTO(productId,name,kind,affectsPrice,affectsRecipe,required,defaultValue,optionDefaultSource,sortOrder)
// CreateProductOptionValueDTO(optionId,value,sortOrder)
// CreateProductPricingModifierDTO(productId,optionId,triggerValueId,triggerIntMin,triggerIntMax,modifierKind,amount)
// .toModel() exists on all three DTOs; it does NOT set lastSyncedAt/needsSync (match existing insert pattern).

// CatalogRepository (companyId:):
func createFamily(_ dto: CreateCatalogItemDTO) async throws -> CatalogItemDTO
func createVariant(_ dto: CreateCatalogVariantDTO) async throws -> CatalogVariantDTO
func createOption(_ dto: CreateCatalogOptionDTO) async throws -> CatalogOptionDTO
func createOptionValue(_ dto: CreateCatalogOptionValueDTO) async throws -> CatalogOptionValueDTO
func createVariantOptionValue(variantId: String, optionValueId: String) async throws   // loose params, returns Void
// CreateCatalogOptionDTO(catalogItemId,name,sortOrder)
// CreateCatalogOptionValueDTO(optionId,value,sortOrder)
// CatalogVariantOptionValue local insert: CatalogVariantOptionValue(variantId:optionValueId:) then set lastSyncedAt = Date()  (NO id/companyId param)

// ProductConfigurationResolver.resolve: price = product.basePrice; per fired modifier add_flat -> price += amount.
// EstimateLineItem.resolvedOptionsLabel: String?
```

---

## Task 1 — Tier draft model + snapshot bump

**Files:** Modify `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift`; Test `OPSTests/GuidedCatalogSetupModelTests.swift`

- [ ] **Step 1: Add the tier models + draft field** (top of `GuidedCatalogSetupDraft.swift`, after `ProductLineKind`)

```swift
/// One priced tier inside a tiered product line, e.g. {label:"Sedan", priceText:"180"}.
struct ProductTierRow: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var priceText: String
    init(id: String = UUID().uuidString, label: String = "", priceText: String = "") {
        self.id = id; self.label = label; self.priceText = priceText
    }
}

/// Option-priced tiers attached to one product line. nil on the draft => flat line (fast path).
struct ProductLineTiers: Codable, Equatable {
    var axisName: String
    var rows: [ProductTierRow]
    init(axisName: String = "", rows: [ProductTierRow] = [ProductTierRow(), ProductTierRow()]) {
        self.axisName = axisName; self.rows = rows
    }
}
```

Add `var tiers: ProductLineTiers?` as the **last** stored property of `ProductLineDraft` and add `tiers: ProductLineTiers? = nil` as the **last** init param (default nil keeps `ProductLineDraft(kind:)` source-compatible).

- [ ] **Step 2: Add tier summary fields to `SavedProductLine`**

```swift
struct SavedProductLine: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var kind: ProductLineKind
    var sell: Double
    var tierCount: Int? = nil       // nil = flat line
    var tierAxisLabel: String? = nil // e.g. "Size"
}
```

(Defaults keep the existing `SavedProductLine(id:name:kind:sell:)` call sites + the `GuidedCatalogSetupModelTests` fixture compiling.)

- [ ] **Step 3: Bump the snapshot schema version** — `GuidedCatalogSetupDraftSnapshot.currentSchemaVersion = 4` (was 3). `load()` already rejects mismatched versions → pre-tier drafts are cleanly discarded, zero migration.

- [ ] **Step 4: Extend the draft round-trip test** (in `GuidedCatalogSetupModelTests.test_draftStore_roundTripsAndClears`, add a tiered line to `productLines`):

```swift
            productLines: [ProductLineDraft(id: "d1", kind: .service, name: "Full Detail",
                            tiers: ProductLineTiers(axisName: "Size",
                                rows: [ProductTierRow(id: "r1", label: "Sedan", priceText: "180"),
                                       ProductTierRow(id: "r2", label: "SUV", priceText: "230")]))],
```

- [ ] **Step 5: Build + run test** (commands in "Build & test verification"). Expected: PASS (snapshot round-trips with v4 + tiers).

- [ ] **Step 6: Commit**

```bash
git add OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift OPSTests/GuidedCatalogSetupModelTests.swift
git commit -m "feat(catalog-setup): tier draft model + snapshot v4 for option-priced lines"
```

---

## Task 2 — Pure tier derivation (`TierSpec`) + tests

This is the testable core: turn tier rows into the exact option/value/modifier shape the resolver consumes. Pure, no network — mirrors the existing `missingDefaultUnits` pattern.

**Files:** Modify `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift`; Create `OPSTests/GuidedCatalogSetupTierTests.swift`

- [ ] **Step 1: Write the failing test** (`GuidedCatalogSetupTierTests`)

```swift
import XCTest
@testable import OPS

final class GuidedCatalogSetupTierTests: XCTestCase {

    func test_tierSpec_baseIsLowest_deltasFromBase() {
        let tiers = ProductLineTiers(axisName: "Size", rows: [
            ProductTierRow(label: "Sedan", priceText: "180"),
            ProductTierRow(label: "SUV",   priceText: "230"),
            ProductTierRow(label: "Truck", priceText: "280"),
        ])
        let spec = TierSpec.derive(from: tiers, parseMoney: { Double($0) })!
        XCTAssertEqual(spec.basePrice, 180, accuracy: 0.001)        // lowest tier
        XCTAssertEqual(spec.defaultLabel, "Sedan")                  // lowest tier label
        XCTAssertEqual(spec.values.map(\.label), ["Sedan", "SUV", "Truck"]) // entry order
        // one modifier per non-default tier, delta = price - base
        XCTAssertEqual(spec.modifiers.count, 2)
        XCTAssertEqual(spec.modifiers.first { $0.label == "SUV" }?.delta, 50, accuracy: 0.001)
        XCTAssertEqual(spec.modifiers.first { $0.label == "Truck" }?.delta, 100, accuracy: 0.001)
    }

    func test_tierSpec_singleValidRow_returnsNil_degradesToFlat() {
        let tiers = ProductLineTiers(axisName: "Size", rows: [
            ProductTierRow(label: "Standard", priceText: "99"),
            ProductTierRow(label: "", priceText: ""),     // blank row dropped
        ])
        XCTAssertNil(TierSpec.derive(from: tiers, parseMoney: { Double($0) }))
    }

    func test_tierSpec_outOfOrderEntry_baseStillLowest() {
        let tiers = ProductLineTiers(axisName: "Grade", rows: [
            ProductTierRow(label: "Premium", priceText: "400"),
            ProductTierRow(label: "Basic",   priceText: "250"),
        ])
        let spec = TierSpec.derive(from: tiers, parseMoney: { Double($0) })!
        XCTAssertEqual(spec.basePrice, 250, accuracy: 0.001)
        XCTAssertEqual(spec.defaultLabel, "Basic")
        XCTAssertEqual(spec.modifiers.count, 1)                      // only Premium gets a +150 modifier
        XCTAssertEqual(spec.modifiers.first?.delta, 150, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `TierSpec` undefined.

- [ ] **Step 3: Implement `TierSpec`** (new MARK section in `GuidedCatalogSetupModel.swift`, nonisolated/pure)

```swift
    // MARK: - Tier derivation (option-priced lines; pure, testable)

    /// The exact shape `saveTieredProductLine` writes: a base price, a default
    /// tier, ordered option values, and one add_flat delta per non-default tier.
    /// Derived purely from the draft so it is unit-testable without the network.
    struct TierSpec: Equatable {
        struct Value: Equatable { let label: String; let sortOrder: Int }
        struct Modifier: Equatable { let label: String; let delta: Double }
        let axisName: String
        let basePrice: Double
        let defaultLabel: String
        let values: [Value]
        let modifiers: [Modifier]

        /// nil when fewer than 2 tiers parse to a price (caller degrades to a flat line).
        static func derive(from tiers: ProductLineTiers,
                           parseMoney: (String) -> Double?) -> TierSpec? {
            let clean: [(label: String, price: Double)] = tiers.rows.compactMap { row in
                let label = row.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty, let price = parseMoney(row.priceText) else { return nil }
                return (label, price)
            }
            guard clean.count >= 2 else { return nil }
            let base = clean.map(\.price).min()!
            let defaultLabel = clean.first { $0.price == base }!.label
            let values = clean.enumerated().map { Value(label: $1.label, sortOrder: $0) }
            let modifiers = clean
                .filter { $0.label != defaultLabel && $0.price != base }
                .map { Modifier(label: $0.label, delta: $0.price - base) }
            let axis = tiers.axisName.trimmingCharacters(in: .whitespacesAndNewlines)
            return TierSpec(axisName: axis.isEmpty ? "Option" : axis,
                            basePrice: base, defaultLabel: defaultLabel,
                            values: values, modifiers: modifiers)
        }
    }
```

> Note on `defaultLabel` ties: if two tiers share the min price, `first` wins and the second becomes a `delta == 0` tier — excluded from modifiers (`$0.price != base`), so it correctly resolves to base. Distinct tier *labels* are enforced in the UI gate (T4), so the resolver's `defaultValue`-by-string match stays deterministic.

- [ ] **Step 4: Run to verify pass** — all three `GuidedCatalogSetupTierTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift OPSTests/GuidedCatalogSetupTierTests.swift
git commit -m "feat(catalog-setup): pure TierSpec derivation (base=lowest tier, add_flat deltas)"
```

---

## Task 3 — Commit a tiered product line (`saveTieredProductLine`)

**Files:** Modify `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift`

- [ ] **Step 1: Branch `saveProductLine` at the top** (after the existing `trimmedName` guard, before the flat-line body). If tiers derive to ≥2, route to the tiered writer; otherwise fall through to today's flat body unchanged. When a 1-tier line is enabled, copy its single price into `sellText` so the flat body prices it:

```swift
        // Tiered branch: ≥2 valid tiers become a configurable product the estimate
        // builder reads via ProductConfigurationResolver. 0/1 valid tier degrades to flat.
        if let tiers = draft.tiers {
            if let spec = TierSpec.derive(from: tiers, parseMoney: parseMoney) {
                await saveTieredProductLine(draft, spec: spec, units: units,
                                            categories: categories, modelContext: modelContext)
                return
            }
            // single/blank tier → flat line at that one price
            if let only = tiers.rows.compactMap({ r -> String? in
                let l = r.label.trimmingCharacters(in: .whitespacesAndNewlines)
                return (!l.isEmpty && parseMoney(r.priceText) != nil) ? r.priceText : nil
            }).first {
                var flat = draft; flat.tiers = nil; flat.sellText = only
                await saveProductLine(flat, trackCost: trackCost, units: units,
                                      categories: categories, modelContext: modelContext)
                return
            }
        }
```

- [ ] **Step 2: Implement `saveTieredProductLine`** (product → option → values → modifiers, parent before child; price-only, no per-tier cost in v1)

```swift
    private func saveTieredProductLine(_ draft: ProductLineDraft,
                                       spec: TierSpec,
                                       units: [CatalogUnit],
                                       categories: [CatalogCategory],
                                       modelContext: ModelContext) async {
        guard !isSaving else { return }
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        isSaving = true; defer { isSaving = false }
        errorMessage = nil

        let category = draft.kind.productCategory
        let unit = units.first { $0.id == draft.unitId }
        let productRepo = ProductRepository(companyId: companyId)
        let richnessRepo = ProductRichnessRepository(companyId: companyId)

        let dto = CreateProductDTO(
            companyId: companyId, name: trimmedName, description: nil,
            basePrice: spec.basePrice, unitCost: nil, unit: unit?.display,
            pricingUnit: pricingUnit(for: unit).rawValue, unitId: unit?.id,
            category: categories.first { $0.id == draft.categoryId }?.name,
            categoryId: draft.categoryId, sku: nil, thumbnailUrl: nil,
            kind: category.derivedKindRaw, type: category.derivedType.rawValue,
            isTaxable: category.defaultTaxable,
            taskTypeId: nil, taskTypeRef: nil, linkedCatalogItemId: nil)

        do {
            let created = try await productRepo.create(dto)
            modelContext.insert(created.toModel())

            // one select option, default = lowest tier label
            let option = try await richnessRepo.createOption(CreateProductOptionDTO(
                productId: created.id, name: spec.axisName, kind: "select",
                affectsPrice: true, affectsRecipe: false, required: true,
                defaultValue: spec.defaultLabel, optionDefaultSource: nil, sortOrder: 0))
            modelContext.insert(option.toModel())

            var valueIdByLabel: [String: String] = [:]
            for v in spec.values {
                let value = try await richnessRepo.createOptionValue(CreateProductOptionValueDTO(
                    optionId: option.id, value: v.label, sortOrder: v.sortOrder))
                modelContext.insert(value.toModel())
                valueIdByLabel[v.label] = value.id
            }
            for mod in spec.modifiers {
                guard let valueId = valueIdByLabel[mod.label] else { continue }
                let m = try await richnessRepo.createPricingModifier(CreateProductPricingModifierDTO(
                    productId: created.id, optionId: option.id, triggerValueId: valueId,
                    triggerIntMin: nil, triggerIntMax: nil, modifierKind: "add_flat", amount: mod.delta))
                modelContext.insert(m.toModel())
            }
            try? modelContext.save()

            savedLines.append(SavedProductLine(id: created.id, name: created.name,
                kind: draft.kind, sell: created.basePrice,
                tierCount: spec.values.count, tierAxisLabel: spec.axisName))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            persist()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 2b: Make `parseMoney` usable as the `TierSpec.derive` arg** — it is already an instance method `func parseMoney(_:) -> Double?`; passing `parseMoney` (a method reference) satisfies `(String) -> Double?`. No change needed.

- [ ] **Step 3: Verify** — build green (device-generic). The tiered branch compiles and `saveProductLine` still handles the flat path identically.

- [ ] **Step 4: Commit**

```bash
git add OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift
git commit -m "feat(catalog-setup): commit tiered lines as product option + values + add_flat modifiers"
```

---

## Task 4 — Tier UI in the services/goods module

**Files:** Modify `OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift`

- [ ] **Step 1: Gate the existing Sell/cost row on `draft.tiers == nil`.** Extract the current `HStack(alignment: .top)` block (Sell rate / Your cost, lines ~151-169) into a `@ViewBuilder private var sellAndCostRow` and the margin readout (line ~171-173) into the same gate. In `formCard`, render:

```swift
            if draft.tiers == nil {
                sellAndCostRow
                if trackCost, let margin = model.marginPercent(sellText: draft.sellText, costText: draft.costText) {
                    marginReadout(margin)
                }
            }
            tierSection           // new — see Step 2
```

- [ ] **Step 2: Add `tierSection`** (the affordance + editor). Place it before the Unit field. Uses approved copy; OPSStyle-traced; 44pt targets; mono prices.

```swift
    @ViewBuilder private var tierSection: some View {
        Button {
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) {
                draft.tiers = (draft.tiers == nil) ? ProductLineTiers() : nil
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: draft.tiers == nil ? "plus.circle" : "minus.circle")
                Text(draft.tiers == nil ? "// PRICE BY OPTION" : "// BACK TO ONE PRICE")
                    .font(OPSStyle.Typography.metadata)
                Spacer()
            }
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(draft.tiers == nil ? "Price by option" : "Back to one price")

        if draft.tiers != nil {
            Text("Same item, different sizes or grades — a price for each.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            tierEditor
        }
    }
```

- [ ] **Step 3: Add `tierEditor`** with axis field + rows + add/remove + validation. Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion`. Bindings index into `draft.tiers!`.

```swift
    private var axisSingular: String {
        let a = (draft.tiers?.axisName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return a.isEmpty ? "Option" : a
    }

    @ViewBuilder private var tierEditor: some View {
        CatalogFieldLabel("Option name")
        TextField("Size", text: Binding(
            get: { draft.tiers?.axisName ?? "" },
            set: { draft.tiers?.axisName = $0 }))
            .textFieldStyle(CatalogTextFieldStyle())

        CatalogFieldLabel(axisSingular.uppercased())
        ForEach(draft.tiers?.rows ?? []) { row in
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                TextField("e.g. Sedan", text: bindingLabel(row.id))
                    .textFieldStyle(CatalogTextFieldStyle())
                TextField("0", text: bindingPrice(row.id))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(CatalogTextFieldStyle())
                    .frame(width: 96)
                    .monospacedDigit()
                Button { removeTier(row.id) } label: {
                    Image(systemName: "minus.circle.fill")
                        .frame(width: OPSStyle.Layout.touchTargetStandard,
                               height: OPSStyle.Layout.touchTargetStandard)
                }
                .buttonStyle(.plain)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .disabled((draft.tiers?.rows.count ?? 0) <= 1)
                .accessibilityLabel("Remove \(axisSingular.lowercased())")
            }
        }

        Button { addTier() } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "plus.circle")
                Text("ADD \(axisSingular.uppercased())")
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(OPSStyle.Colors.secondaryText)
    }

    private func bindingLabel(_ id: String) -> Binding<String> {
        Binding(get: { draft.tiers?.rows.first { $0.id == id }?.label ?? "" },
                set: { v in if let i = draft.tiers?.rows.firstIndex(where: { $0.id == id }) { draft.tiers?.rows[i].label = v } })
    }
    private func bindingPrice(_ id: String) -> Binding<String> {
        Binding(get: { draft.tiers?.rows.first { $0.id == id }?.priceText ?? "" },
                set: { v in if let i = draft.tiers?.rows.firstIndex(where: { $0.id == id }) { draft.tiers?.rows[i].priceText = v } })
    }
    private func addTier() {
        withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) { draft.tiers?.rows.append(ProductTierRow()) }
    }
    private func removeTier(_ id: String) {
        guard (draft.tiers?.rows.count ?? 0) > 1 else { return }
        withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) { draft.tiers?.rows.removeAll { $0.id == id } }
    }
```

- [ ] **Step 4: Add tier validation to `canAdd` / `disabledReason`.** Add a `tiersValid` computed var; when `draft.tiers != nil`, replace the `sellAmount != nil && !costInvalid` requirement with `tiersValid`, and add the disabled reasons.

```swift
    private var tiersValid: Bool {
        guard let t = draft.tiers else { return true }
        let labels = t.rows.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard t.rows.count >= 1, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        guard Set(labels.map { $0.lowercased() }).count == labels.count else { return false }
        return t.rows.allSatisfy { (model.parseMoney($0.priceText) ?? 0) > 0 }
    }
```

In `canAdd`: keep `isOnline`, `!model.isSaving`, name non-empty, `!isDuplicateName`; then `if draft.tiers == nil { guard sellAmount != nil, !costInvalid else { return false } } else { guard tiersValid else { return false } }`.
In `disabledReason` add (before the generic name/price branch):

```swift
        if let t = draft.tiers {
            if t.rows.contains(where: { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return "// EACH OPTION NEEDS A NAME" }
            let labels = t.rows.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            if Set(labels).count != labels.count { return "// OPTION NAMES MUST BE UNIQUE" }
            if t.rows.contains(where: { (model.parseMoney($0.priceText) ?? 0) <= 0 }) { return "// EACH OPTION NEEDS A PRICE" }
        }
```

- [ ] **Step 5: Tier suffix in `addedListCard`.** After `Text(line.name)`, append the count when present:

```swift
                    if let n = line.tierCount, n > 0 {
                        Text("· \(n) \((line.tierAxisLabel.map { $0.lowercased() } ?? "option"))\(n == 1 ? "" : "s")")
                            .font(OPSStyle.Typography.metadata).monospacedDigit()
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
```

(`sell` shown = `created.basePrice` = lowest tier, already passed in T3.)

- [ ] **Step 6: Verify** — build green; manual: enable PRICE BY OPTION, the flat Sell/cost row hides, two seeded rows appear, ADD disabled with the right reason until each row has a unique name + positive price; saving lists "Full Detail · 3 sizes … $180".

- [ ] **Step 7: Commit**

```bash
git add OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift
git commit -m "feat(catalog-setup): price-by-option tier editor on service and good lines"
```

---

## Task 5 — Prove the written tier prices on an estimate (resolver round-trip test)

This closes the gate with an executable proof: the exact option/value/modifier shape T3 writes resolves to the right tier price.

**Files:** Modify `OPSTests/GuidedCatalogSetupTierTests.swift`

- [ ] **Step 1: Add the resolver round-trip test**

```swift
    func test_resolver_pricesEachTier_fromTierSpecShape() {
        // Build the in-memory option/value/modifier graph exactly as saveTieredProductLine writes it.
        let product = Product(id: "p", companyId: "c", name: "Full Detail",
                              basePrice: 180, pricingUnit: .flatRate)
        let option = ProductOption(id: "o", productId: "p", name: "Size",
                                   kind: .select, affectsPrice: true, required: true, defaultValue: "Sedan")
        let sedan = ProductOptionValue(id: "v1", optionId: "o", value: "Sedan", sortOrder: 0)
        let suv   = ProductOptionValue(id: "v2", optionId: "o", value: "SUV", sortOrder: 1)
        let truck = ProductOptionValue(id: "v3", optionId: "o", value: "Truck", sortOrder: 2)
        let mSUV   = ProductPricingModifier(productId: "p", optionId: "o", triggerValueId: "v2",
                                            modifierKind: .addFlat, amount: 50)
        let mTruck = ProductPricingModifier(productId: "p", optionId: "o", triggerValueId: "v3",
                                            modifierKind: .addFlat, amount: 100)
        let resolver = ProductConfigurationResolver()
        func price(_ valueId: String) -> Double {
            resolver.resolve(product: product, options: [option],
                optionValues: [sedan, suv, truck], modifiers: [mSUV, mTruck],
                configured: ["o": .selectId(valueId)]).unitPrice
        }
        XCTAssertEqual(price("v1"), 180, accuracy: 0.001) // Sedan = base
        XCTAssertEqual(price("v2"), 230, accuracy: 0.001) // SUV = base + 50
        XCTAssertEqual(price("v3"), 280, accuracy: 0.001) // Truck = base + 100
    }
```

> Verify the `Product` / `ProductOption` / `ProductOptionValue` / `ProductPricingModifier` initializers against the real models before running (read them; adjust arg labels to match). The init shapes are documented in "Verified write signatures" and the model files.

- [ ] **Step 2: Run** — PASS, proving the tier shape is consumed correctly by the live resolver.

- [ ] **Step 3: Commit**

```bash
git add OPSTests/GuidedCatalogSetupTierTests.swift
git commit -m "test(catalog-setup): resolver round-trip proves tier shape prices each tier"
```

---

## Task 6 — Show the chosen tier on the estimate row (read-side completion)

Without this, a tiered line prices correctly but the estimate line reads just "Full Detail" with no indication of which tier — a visible half-feature. `resolvedOptionsLabel` is already snapshotted; surface it.

**Files:** Modify `OPS/Views/Estimates/EstimateDetailView.swift`

- [ ] **Step 1: Parent row** — in `parentLineItemRow`, append the resolved label to the metadata HStack (after the `TYPE` chip, ~line 372):

```swift
                if let label = item.resolvedOptionsLabel, !label.isEmpty {
                    Text("· \(label)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
```

- [ ] **Step 2: Child row** — in `childLineItemRow`, append to the qty/price line (~line 400-402) when present:

```swift
                if let label = item.resolvedOptionsLabel, !label.isEmpty {
                    Text("\(formatQuantity(item.quantity)) \(item.unit ?? "") · \(label) · \(item.unitPrice, format: .currency(code: \"USD\"))")
                } else {
                    Text("\(formatQuantity(item.quantity)) \(item.unit ?? "") · \(item.unitPrice, format: .currency(code: \"USD\"))")
                }
```

(Keep the existing font/color modifiers on whichever branch renders.)

- [ ] **Step 3: Verify** — build green; the estimate row now reads e.g. `SERVICE · SUV` with the correct `$230` total.

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Estimates/EstimateDetailView.swift
git commit -m "feat(estimates): show the chosen option/tier on estimate line rows"
```

---

## Task 7 — Material option-axes draft model + pure helpers

**Files:** Modify `OPS/Services/Catalog/GuidedCatalogSetup/AssemblyDraft.swift`; Create `OPSTests/GuidedCatalogSetupVariantTests.swift`

- [ ] **Step 1: Add the axis model + draft field + pure helpers**

```swift
/// One option axis on an inline-created material (Color → [Black, White]).
struct AssemblyMaterialAxis: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var values: [String] = [""]
}

// On AssemblyMaterialDraft, add:
    var axes: [AssemblyMaterialAxis] = []   // 0…2; empty => legacy single-variant scaffold

extension AssemblyMaterialDraft {
    static let maxVariants = 100

    /// Axes with a non-blank name and ≥1 non-blank, case-insensitively de-duped value
    /// (first occurrence wins, order preserved).
    var cleanAxes: [AssemblyMaterialAxis] {
        axes.compactMap { axis in
            let n = axis.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else { return nil }
            var seen = Set<String>(); var out: [String] = []
            for v in axis.values {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
                out.append(t)
            }
            guard !out.isEmpty else { return nil }
            return AssemblyMaterialAxis(id: axis.id, name: n, values: out)
        }
    }
    var hasUsableAxes: Bool { !cleanAxes.isEmpty }
    var variantComboCount: Int { cleanAxes.reduce(1) { $0 * $1.values.count } }

    /// Cartesian product of clean axis values as ordered tuples for the variant walk.
    /// [["Black","White"],["45mil","60mil"]] -> [["Black","45mil"],["Black","60mil"],["White","45mil"],["White","60mil"]]
    var variantCombos: [[String]] {
        cleanAxes.map(\.values).reduce([[]]) { acc, vals in acc.flatMap { row in vals.map { row + [$0] } } }
    }
}
```

- [ ] **Step 2: Write the failing tests** (`GuidedCatalogSetupVariantTests`)

```swift
import XCTest
@testable import OPS

final class GuidedCatalogSetupVariantTests: XCTestCase {

    func test_cleanAxes_dropsBlankAndDuplicateValues() {
        var d = AssemblyMaterialDraft(name: "Top rail")
        d.axes = [AssemblyMaterialAxis(name: "Color", values: ["Black", "", "black", "White"])]
        let clean = d.cleanAxes
        XCTAssertEqual(clean.count, 1)
        XCTAssertEqual(clean[0].values, ["Black", "White"])   // blank + dup-ci dropped, order kept
    }

    func test_variantCombos_cartesianProduct() {
        var d = AssemblyMaterialDraft(name: "Membrane")
        d.axes = [AssemblyMaterialAxis(name: "Color", values: ["Tan", "Gray", "Slate"]),
                  AssemblyMaterialAxis(name: "Thickness", values: ["45mil", "60mil"])]
        XCTAssertEqual(d.variantComboCount, 6)
        XCTAssertEqual(d.variantCombos.count, 6)
        XCTAssertEqual(d.variantCombos.first, ["Tan", "45mil"])
        XCTAssertEqual(d.variantCombos.last,  ["Slate", "60mil"])
    }

    func test_noUsableAxes_whenAxisNameBlank() {
        var d = AssemblyMaterialDraft(name: "Screws")
        d.axes = [AssemblyMaterialAxis(name: "  ", values: ["Black"])]
        XCTAssertFalse(d.hasUsableAxes)
        XCTAssertEqual(d.variantComboCount, 1)
    }
}
```

- [ ] **Step 3: Run** — PASS.

- [ ] **Step 4: Commit**

```bash
git add OPS/Services/Catalog/GuidedCatalogSetup/AssemblyDraft.swift OPSTests/GuidedCatalogSetupVariantTests.swift
git commit -m "feat(catalog-setup): material option-axes draft + pure matrix derivation"
```

---

## Task 8 — Shared `CatalogVariantLabeler`

Extract the canonical option-value labeler (from `AddProductMaterialSheet.variantLabel`, lines 407-440) so the assembly pick-existing picker (and future surfaces) label by option value instead of SKU.

**Files:** Create `OPS/Views/Catalog/Shared/CatalogVariantLabeler.swift`; Modify `OPSTests/GuidedCatalogSetupVariantTests.swift`

- [ ] **Step 1: Create the shared labeler** (note OPS variant labels join family + values with `" · "`, matching `EnrichedVariantRow`/`AddProductMaterialSheet`)

```swift
import Foundation

/// Composes a human label for a CatalogVariant from its option values, e.g.
/// "Top rail · Black · 60mil". Falls back to "family · SKU", then bare family.
/// One canonical implementation shared across stock + recipe pickers.
enum CatalogVariantLabeler {
    static func label(for variant: CatalogVariant,
                      families: [CatalogItem],
                      options: [CatalogOption],
                      optionValues: [CatalogOptionValue],
                      variantOptionValues: [CatalogVariantOptionValue]) -> String {
        let familyName = families.first { $0.id == variant.catalogItemId }?.name ?? ""
        let familyOptions = options
            .filter { $0.catalogItemId == variant.catalogItemId }
            .sorted { $0.sortOrder < $1.sortOrder }
        let myValueIds = Set(variantOptionValues.filter { $0.variantId == variant.id }.map(\.optionValueId))
        let valuesById = Dictionary(optionValues.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var parts: [String] = []
        for option in familyOptions {
            if let v = myValueIds.compactMap({ valuesById[$0] }).first(where: { $0.optionId == option.id }) {
                parts.append(v.value)
            }
        }
        if !parts.isEmpty { return parts.isEmpty || familyName.isEmpty ? parts.joined(separator: " · ") : "\(familyName) · \(parts.joined(separator: " · "))" }
        if let sku = variant.sku, !sku.isEmpty { return familyName.isEmpty ? sku : "\(familyName) · \(sku)" }
        return familyName
    }
}
```

- [ ] **Step 2: Add a label test** (build a tiny in-memory graph). Verify the exact model initializers first.

```swift
    func test_variantLabeler_composesOptionValues() {
        let family = CatalogItem(id: "f", companyId: "c", name: "Top rail")
        let color = CatalogOption(id: "o", catalogItemId: "f", name: "Color", sortOrder: 0)
        let black = CatalogOptionValue(id: "v", optionId: "o", value: "Black", sortOrder: 0)
        let variant = CatalogVariant(id: "var", companyId: "c", catalogItemId: "f")
        let link = CatalogVariantOptionValue(variantId: "var", optionValueId: "v")
        let label = CatalogVariantLabeler.label(for: variant, families: [family],
            options: [color], optionValues: [black], variantOptionValues: [link])
        XCTAssertEqual(label, "Top rail · Black")
    }
```

- [ ] **Step 3: Run** — PASS.

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Catalog/Shared/CatalogVariantLabeler.swift OPSTests/GuidedCatalogSetupVariantTests.swift
git commit -m "feat(catalog): shared CatalogVariantLabeler (option-value labels, not raw SKU)"
```

---

## Task 9 — Generate the variant matrix on commit (`commitMaterialMatrix`)

**Files:** Modify `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift`

- [ ] **Step 1: Branch the material loop** in `saveAssembly` (inside `for material in draft.materials`). Multi-axis create-new routes to the matrix writer; everything else keeps the current variant-pinned path **plus** the missing local inserts for the scaffolded family/variant (so they appear immediately + are pick-able):

```swift
                if material.hasUsableAxes && material.catalogVariantId == nil {
                    try await commitMaterialMatrix(material, package: package,
                        catalogRepo: catalogRepo, richnessRepo: richnessRepo, modelContext: modelContext)
                    continue
                }
                let variantId: String
                if let existingVariantId = material.catalogVariantId {
                    variantId = existingVariantId
                } else {
                    let matName = material.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !matName.isEmpty else { continue }
                    let family = try await catalogRepo.createFamily(CreateCatalogItemDTO(
                        companyId: companyId, categoryId: nil, name: matName, description: nil,
                        defaultPrice: nil, defaultUnitCost: parseMoney(material.costText),
                        defaultWarningThreshold: nil, defaultCriticalThreshold: nil,
                        defaultUnitId: material.unitId))
                    modelContext.insert(family.toModel())                       // NEW local insert
                    let variant = try await catalogRepo.createVariant(CreateCatalogVariantDTO(
                        companyId: companyId, catalogItemId: family.id, sku: nil, quantity: 0,
                        priceOverride: nil, unitCostOverride: nil,
                        warningThreshold: nil, criticalThreshold: nil, unitId: material.unitId))
                    modelContext.insert(variant.toModel())                      // NEW local insert
                    variantId = variant.id
                }
                _ = try await richnessRepo.createMaterial(CreateProductMaterialDTO(
                    productId: package.id, catalogVariantId: variantId, catalogItemId: nil,
                    variantSelector: nil, quantityPerUnit: parseMoney(material.qtyText) ?? 1,
                    scaledByOptionId: nil, unitId: material.unitId, notes: nil))
```

- [ ] **Step 2: Implement `commitMaterialMatrix`** — family → options → values → variants (cartesian) → links → recipe pinned to the **first** variant (RecipeResolver consumes a variant pin; a nil-selector family-pin is silently dropped). Parent-before-child throughout.

```swift
    private func commitMaterialMatrix(_ material: AssemblyMaterialDraft,
                                      package: ProductDTO,
                                      catalogRepo: CatalogRepository,
                                      richnessRepo: ProductRichnessRepository,
                                      modelContext: ModelContext) async throws {
        let matName = material.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !matName.isEmpty else { return }
        let axes = material.cleanAxes
        let qty  = parseMoney(material.qtyText) ?? 1
        let cost = parseMoney(material.costText)

        let family = try await catalogRepo.createFamily(CreateCatalogItemDTO(
            companyId: companyId, categoryId: nil, name: matName, description: nil,
            defaultPrice: nil, defaultUnitCost: cost,
            defaultWarningThreshold: nil, defaultCriticalThreshold: nil,
            defaultUnitId: material.unitId))
        modelContext.insert(family.toModel())

        // options + values; keep ordered value ids per axis for the cartesian walk
        var valueIdsPerAxis: [[String]] = []
        for (axisIdx, axis) in axes.enumerated() {
            let option = try await catalogRepo.createOption(CreateCatalogOptionDTO(
                catalogItemId: family.id, name: axis.name, sortOrder: axisIdx))
            modelContext.insert(option.toModel())
            var ids: [String] = []
            for (valIdx, value) in axis.values.enumerated() {
                let ov = try await catalogRepo.createOptionValue(CreateCatalogOptionValueDTO(
                    optionId: option.id, value: value, sortOrder: valIdx))
                modelContext.insert(ov.toModel())
                ids.append(ov.id)
            }
            valueIdsPerAxis.append(ids)
        }

        let combos = valueIdsPerAxis.reduce([[]] as [[String]]) { acc, ids in
            acc.flatMap { row in ids.map { row + [$0] } }
        }

        var firstVariantId: String?
        for combo in combos {
            let variant = try await catalogRepo.createVariant(CreateCatalogVariantDTO(
                companyId: companyId, catalogItemId: family.id, sku: nil, quantity: 0,
                priceOverride: nil, unitCostOverride: nil,
                warningThreshold: nil, criticalThreshold: nil, unitId: material.unitId))
            modelContext.insert(variant.toModel())
            for ovId in combo {
                try await catalogRepo.createVariantOptionValue(variantId: variant.id, optionValueId: ovId)
                let link = CatalogVariantOptionValue(variantId: variant.id, optionValueId: ovId)
                link.lastSyncedAt = Date()
                modelContext.insert(link)
            }
            if firstVariantId == nil { firstVariantId = variant.id }
        }
        guard let recipeVariantId = firstVariantId else { return }

        // Recipe is variant-pinned (RecipeResolver requires it); the full labeled family
        // lives in stock for counting + future per-variant packages.
        _ = try await richnessRepo.createMaterial(CreateProductMaterialDTO(
            productId: package.id, catalogVariantId: recipeVariantId, catalogItemId: nil,
            variantSelector: nil, quantityPerUnit: qty,
            scaledByOptionId: nil, unitId: material.unitId, notes: nil))
    }
```

(The whole call is inside the existing `do { … } catch { failures += 1; … }` per-material isolation, so a matrix failure counts like any material failure and never aborts the package.)

- [ ] **Step 3: Verify** — build green. Confirm `package` is a `ProductDTO` (it is: `let package = try await productRepo.create(packageDTO)`), so the `package:` param type is correct.

- [ ] **Step 4: Commit**

```bash
git add OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift
git commit -m "feat(catalog-setup): generate labeled variant matrix for create-new materials"
```

---

## Task 10 — Variant UI + pick-existing labeling in the material sheet

**Files:** Modify `OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift`

- [ ] **Step 1: Add option-value `@Query`s + state.** Add:

```swift
    @Query private var allOptions: [CatalogOption]
    @Query private var allOptionValues: [CatalogOptionValue]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]
    @State private var variantsExpanded = false
    @State private var axes: [AssemblyMaterialAxis] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

- [ ] **Step 2: Replace the pick-existing label** with the shared labeler (the sheet already `@Query`s `allFamilies`/`allVariants`):

```swift
    private func variantLabel(_ variant: CatalogVariant) -> String {
        CatalogVariantLabeler.label(for: variant, families: allFamilies,
            options: allOptions, optionValues: allOptionValues,
            variantOptionValues: allVariantOptionValues)
    }
```

(Confirm the picker `Menu`/`ForEach` and the `.existing` `buildDraft()` already call `variantLabel(variant)`; they do — only the body changes.)

- [ ] **Step 3: Add the `// VARIANTS` disclosure** in the create-new (`.new`) branch only, below the Unit field. Uses approved copy; OPSStyle-traced; mono count.

```swift
    @ViewBuilder private var variantsDisclosure: some View {
        DisclosureGroup(isExpanded: $variantsExpanded) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                Text("Comes in colors or sizes? List them — you get a variant for each.")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach($axes) { $axis in axisEditor($axis) }
                if axes.count < 2 {
                    Button {
                        withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) { axes.append(AssemblyMaterialAxis()) }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: "plus.circle")
                            Text(axes.isEmpty ? "Add an option" : "Add a second option")
                        }
                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                if !cleanAxesLocal.isEmpty { variantCountReadout }
            }
            .padding(.top, OPSStyle.Layout.spacing2)
        } label: {
            Text("// VARIANTS").font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .tint(OPSStyle.Colors.secondaryText)
    }
```

`axisEditor($axis)`: axis-name `TextField("e.g. Color", …)` with a trailing "Remove option" button (`accessibilityLabel("Remove option")`, 44pt), then `ForEach($axis.values)` of value rows (`TextField("e.g. Black", …)` + 44pt remove with `accessibilityLabel("Remove value")`), then an `Add value` button. All spacing/colors via `OPSStyle`.

`cleanAxesLocal` mirrors `AssemblyMaterialDraft.cleanAxes` over the local `axes`. Count readout (mono, tabular; over-cap turns errorStatus):

```swift
    @ViewBuilder private var variantCountReadout: some View {
        let counts = cleanAxesLocal.map(\.values.count)
        let product = counts.reduce(1, *)
        let over = product > AssemblyMaterialDraft.maxVariants
        let expr = counts.count > 1 ? "\(counts.map(String.init).joined(separator: " × ")) = \(product) variants"
                                    : "\(product) variant\(product == 1 ? "" : "s")"
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(expr).font(OPSStyle.Typography.bodyBold).monospacedDigit()
                .foregroundColor(over ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
            if over {
                Text("Too many. Keep it under \(AssemblyMaterialDraft.maxVariants) — trim a few values.")
                    .font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.errorStatus)
            }
        }
    }
```

- [ ] **Step 4: Wire into `canAdd` + `buildDraft()`.** In the `.new` branch of `canAdd`, add `&& localComboCount <= AssemblyMaterialDraft.maxVariants` (where `localComboCount` = product of `cleanAxesLocal` value counts). In `buildDraft()` `.new` case, pass `axes: axes` into the `AssemblyMaterialDraft(...)` initializer. The `.existing` case is unchanged.

- [ ] **Step 5: Render `variantsDisclosure`** inside the `.new` field group (after Unit), and confirm the single-variant flow is visually unchanged when the disclosure stays collapsed.

- [ ] **Step 6: Verify** — build green; manual: create-new "Top rail" → expand VARIANTS → Color: Black/White → ADD; package commits a "Top rail" family with 2 labeled variants (visible in stock as "Top rail · Black/White") + a recipe pinned to the first. Add a 2nd axis → live "12 × 2 = 24" count; over 100 disables ADD with the cap copy. Pick-existing now shows "Top rail · Black", not a bare SKU-less row.

- [ ] **Step 7: Commit**

```bash
git add OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift
git commit -m "feat(catalog-setup): variant-matrix builder + option-value labels in the material sheet"
```

---

## Task 11 — Bible + design-spec updates (same session, per CLAUDE.md)

No schema change, but a new guided-flow capability + a new estimate-row behavior.

**Files:** Modify the guided-catalog design spec; `ops-software-bible/07_SPECIALIZED_FEATURES.md` (Guided Catalog Setup subsection, if present); `ops-software-bible/09_FINANCIAL_SYSTEM.md` (Products & options / configurable products).

- [ ] **Step 1:** In `docs/superpowers/specs/2026-06-09-guided-catalog-setup-design.md` (or the iteration-2 plan's spec reference), add a "Variants & Tiers slice" note: tiers written as `product_options` + `add_flat` modifiers (base = lowest tier), consumed by `ProductConfigurationResolver`; material matrices written as `catalog_options`/values/variants + variant-pinned recipe; estimate rows show `resolved_options_label`.

- [ ] **Step 2:** In the bible, document (a) guided setup can now author option-priced tiers on services/goods and variant matrices on assembly materials, (b) the estimate line row surfaces the configured option label. Confirm the subsection exists before editing; if absent, add a concise note rather than inventing a section.

- [ ] **Step 3: Commit** (docs separate from code per atomic-commit rule)

```bash
git add docs/superpowers/specs/2026-06-09-guided-catalog-setup-design.md ops-software-bible/07_SPECIALIZED_FEATURES.md ops-software-bible/09_FINANCIAL_SYSTEM.md
git commit -m "docs(catalog): document option-priced tiers + material variant matrix in guided setup"
```

---

## Build & test verification (run after each task; final gate)

- **Device-generic build (the gate — never the simulator for plain build):**
  ```
  cd /Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/guided-catalog-setup
  xcodebuild -scheme OPS -destination 'generic/platform=iOS' \
    -derivedDataPath ./DerivedData -clonedSourcePackagesDirPath .spm-local -quiet build
  ```
  Iterate to **0 errors**. SourceKit may report phantom "cannot find type" — `xcodebuild` is the source of truth.
- **Unit tests (simulator destination, idle sim):**
  ```
  xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
    -derivedDataPath ./DerivedData -clonedSourcePackagesDirPath .spm-local \
    -only-testing:OPSTests/GuidedCatalogSetupTierTests \
    -only-testing:OPSTests/GuidedCatalogSetupVariantTests \
    -only-testing:OPSTests/GuidedCatalogSetupModelTests \
    -only-testing:OPSTests/GuidedCatalogSetupAssemblyTests \
    -only-testing:OPSTests/GuidedCatalogSetupProfileTests \
    -only-testing:OPSTests/GuidedCatalogSetupSurveyTests
  ```
- Check `ps aux | grep xcodebuild` first — a sibling worktree may be mid-build; the worktree-local `./DerivedData` keeps them from colliding.

---

## Self-review

**Spec coverage:** Auto Detailing/Landscaping/Plumbing tier wishes → Scope 1 (T1–T6). Deck & Rail color variants + 24-matrix + label-by-option-value → Scope 2 (T7–T10). Estimate visibility of the chosen tier → T6. Bible/spec → T11. Every audit variant wish maps to a task.

**Placeholder scan:** No TBD/TODO; every code step shows real code grounded in verified signatures. Copy is the approved ops-copywriter output.

**Type consistency:** `TierSpec`/`saveTieredProductLine` (T2/T3); `ProductLineTiers`/`ProductTierRow`/`tiers` (T1/T3/T4); `SavedProductLine.tierCount`/`tierAxisLabel` (T1/T3/T4); `AssemblyMaterialAxis`/`axes`/`cleanAxes`/`variantCombos`/`maxVariants` (T7/T9/T10); `CatalogVariantLabeler.label(for:families:options:optionValues:variantOptionValues:)` (T8/T10); `commitMaterialMatrix(_:package:catalogRepo:richnessRepo:modelContext:)` (T9). Names are consistent across tasks.

**Sync-constraint check:** Every value written is an existing CHECK-valid value (`kind=select`, `modifier_kind=add_flat`, `pricing_unit` per the line's unit, product `kind/type` per category). All rows are inserts into existing tables — additive, no schema change, no risk to old App Store builds (which never query the option tables) or the web app (reads `base_price`). ✅

**Pre-implementation checklist (mobile-ux-design Step 7):** tokens-only ✅ · accent sparing (icons/add affordances) ✅ · 44pt targets ✅ · one-handed primary action (existing bottom button) ✅ · motion = `OPSStyle.Animation.page`, reduce-motion honored ✅ · all states (default/incomplete/valid/over-cap/offline/saved) ✅ · contrast via tokens ✅ · labels not icon-only (accessibilityLabels) ✅ · color not sole signal (`//` text + color) ✅.
