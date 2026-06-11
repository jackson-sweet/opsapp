# Guided Catalog Setup — Iteration 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Guided Catalog Setup flow from a demo into a lifeline for the four trades the cold-start audit role-played, by fixing mis-routing, making units first-class, allowing per-unit / piecework pricing, and repairing the two regressions the audit caught — without any database schema change.

**Architecture:** Pure UI/flow + client-logic changes against the existing `feat/guided-catalog-setup` branch. The data model already supports everything here (`ProductPricingUnit.linearFoot/.sqft/.each/.hour/.day`, `catalog_units` with `volume`/`mass` dimensions, `CreateProductDTO.pricingUnit`/`unitId`, the bundle + recipe repos). We only stop the flow from discarding capability it already has, and seed the one thing cold-start companies lack: a starter unit pack. No `products.pricing_unit` value is written that the services module doesn't already write today, so there is zero cross-platform / iOS-sync risk (CLAUDE.md additive-only constraint respected).

**Tech Stack:** Swift / SwiftUI / SwiftData, `OPSStyle` tokens, `CatalogRepository` / `ProductRepository` / `ProductBundleItemRepository` / `ProductRichnessRepository`, XCTest (OPSTests).

---

## Audit → fix traceability

The four raw reports (`docs/superpowers/audits/2026-06-10-guided-catalog-onboarding/`) and the consolidated hub define this iteration. Mapping:

| Audit item | Severity | Company(s) | This iteration | Task |
|---|---|---|---|---|
| Survey mis-routes services-only into assemblies | P0 | Auto Detailing | **Fixed** — gate `runAssemblies` on `sells != .services` | T1 |
| Assembly can't save a price-only / empty package | P0 | Auto Detailing | **Fixed** — drop `!isEmptyContents` from `canSave` | T2 |
| Assembly ignores `trackCost` (forces cost) | P0 | Auto Detailing | **Fixed** — honor `trackCost` in module + both sheets | T3 |
| Create-new material lost its unit picker (REGRESSION) | P0 | Landscaping, Plumbing | **Fixed** — re-add `UnitPickerField` to create-new | T4 |
| No seeded units; cold-start is unitless | P0/P1 | Plumbing, Landscaping | **Fixed** — seed a starter unit pack on entry | T5 |
| No per-unit package pricing ($70/ft, per-area) | P0/P1 | Deck & Rail, Landscaping | **Fixed** — unit picker on package price | T6 |
| Labor can't be piecework (per-ft / per-sq-ft) | P0/P1 | Deck & Rail, Landscaping | **Fixed** — unit picker on labor sheet | T7 |
| BACK from plan wipes the survey (REGRESSION) | P2 | Auto Detailing | **Fixed** — lift survey state into the model | T8 |
| No labeled SKIP on optional modules | P1 | Plumbing, Auto Detailing | **Fixed** — adaptive SKIP/NEXT/FINISH | T9 |
| Finish never clears the draft; re-fires notification | P2 | Deck & Rail | **Fixed** — clear draft on finish/view | T10 |
| Offline banner lies (saves hard-blocked) | P1/P2 | 3 of 4 | **Fixed (honesty)** — tell the truth in copy | T11 |
| Volume/mass available in the catalog modules | P0 (catalog half) | Landscaping | **Fixed** — seed CU YD + TON; picker already groups them | T5 |
| **Variants / tiers on a line** (Sedan/SUV/Truck; black/white; 24 vinyl) | P0/P1 | all four | **DEFERRED — next slice** (see Deferred) | — |
| **Volume/mass in the *stock-counting* flow** | P0 (stock half) | Landscaping | **DEFERRED — ships with the stock-module slice** | — |
| **CSV importer surfaced in Goods**; bulk SKU; markup mode | P0/P1 | Plumbing | **DEFERRED — next slice** | — |
| **Stock handoff inline / return-to-Done payoff**; permission-gate align | P1 | Deck & Rail, Landscaping | **DEFERRED — stock-module slice** | — |

Everything in the "build now" half is items 1–3 of the hub's suggested fix order **plus both regressions**, plus the cheap, low-risk wins from item 5 (SKIP, finish-clears-draft, offline honesty). Item 4 (variants/tiers) and the heavier item-5 work are deferred with rationale below.

---

## File structure

| File | Responsibility | Change |
|---|---|---|
| `OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift` | Survey → module derivation (pure) | Gate `runAssemblies` on `sells != .services` |
| `OPS/Services/Catalog/GuidedCatalogSetup/AssemblyDraft.swift` | Assembly working state | Add `priceUnitId` to `AssemblyDraft`; `unitId` to `AssemblyLaborDraft` |
| `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift` | Flow state machine + commit + persistence | trackCost-aware margin; per-unit package + piecework labor commit; **unit seeder**; lifted survey state; schema bump |
| `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift` | Codable resume snapshot | Persist survey state; `currentSchemaVersion` 2 → 3 |
| `OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift` | Survey data + branching | `SurveyAnswers`/`SurveyQuestionID` become `Codable`; **offline-honest copy is in the Flow, not here** |
| `OPS/Views/Catalog/GuidedSetup/Survey/GuidedSetupSurveyView.swift` | Survey UI | Bind to model's lifted survey state (fixes BACK regression) |
| `OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift` | Container shell | Adaptive SKIP/NEXT/FINISH; finish clears draft; offline-honest banner copy; trigger unit seeding |
| `OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift` | Assembly builder UI | Price-only save; honor trackCost; package unit picker; pass units + trackCost to sheets |
| `OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift` | Add-material sheet | Re-add create-new `UnitPickerField`; trackCost-aware cost; cost optional |
| `OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyLaborSheet.swift` | Add-labor sheet | Unit picker + dynamic labels; trackCost-aware; cost optional |
| `OPSTests/GuidedCatalogSetupProfileTests.swift` | Routing tests | Add services-only fixedJob/mixed → no assembly |
| `OPSTests/GuidedCatalogSetupModelTests.swift` | Model tests | Add seeder key-diff + trackCost margin display tests |

**Design-system compliance (mobile-ux-design Step 7, as acceptance criteria for every UI task):** every new control reuses an existing OPSStyle-traced pattern — `UnitPickerField`, `CatalogTextFieldStyle`, `CatalogFieldLabel`, `OPSFloatingButtonBar`, `nestedCard()`, `ops*ButtonStyle()`. No hardcoded color/spacing/radius. Touch targets stay ≥ `OPSStyle.Layout.touchTargetStandard` (44pt+). Numbers use `OPSStyle.Typography.dataValue`/`.metadata` (JetBrains Mono, tabular). Motion stays on the existing `OPSStyle.Animation.page` curve with the reduced-motion fallback already in place — **no new animation is introduced**, so the animation-studio skills do not apply. All new user-facing strings go through `ops-copywriter` (T11 + label review).

---

## Task 1 — Routing gate: services-only never sees assemblies

**Files:**
- Modify: `OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift:64`
- Test: `OPSTests/GuidedCatalogSetupProfileTests.swift`

- [ ] **Step 1: Write the failing test** (append to `GuidedCatalogSetupProfileTests`)

```swift
    // Auto Detailing: services-only, one all-in price, just set prices.
    // Must NOT be routed into the assembly builder.
    func test_servicesOnly_fixedJob_skipsAssembly() {
        let p = BusinessProfile(sells: .services, pricing: .fixedJob,
                                materialUse: .none, inventory: nil, trackCost: false)
        XCTAssertFalse(p.runAssemblies)
        XCTAssertEqual(p.setupModules, [.services])
    }

    // Services-only that "depends on the job" also skips assemblies.
    func test_servicesOnly_mixed_skipsAssembly() {
        let p = BusinessProfile(sells: .services, pricing: .mixed,
                                materialUse: .none, inventory: nil, trackCost: true)
        XCTAssertFalse(p.runAssemblies)
        XCTAssertEqual(p.setupModules, [.services])
    }

    // Regression guard: a true fixed-job MIX shop still leads with assemblies.
    func test_mixFixedJob_stillRunsAssembly() {
        let p = BusinessProfile(sells: .mix, pricing: .fixedJob,
                                materialUse: .heavy, inventory: .tracked, trackCost: true)
        XCTAssertTrue(p.runAssemblies)
        XCTAssertEqual(p.setupModules.first, .assembly)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/GuidedCatalogSetupProfileTests -derivedDataPath ./DerivedData`
Expected: `test_servicesOnly_fixedJob_skipsAssembly` FAILS (currently `runAssemblies == true`).

- [ ] **Step 3: Implement** — `BusinessProfile.swift`, replace line 64:

```swift
    var runAssemblies: Bool { (pricing == .fixedJob || pricing == .mixed) && sells != .services }
```

- [ ] **Step 4: Run to verify pass** — same command; all `GuidedCatalogSetupProfileTests` PASS (the four pre-existing tests are unaffected; none used a services + fixedJob/mixed combo).

- [ ] **Step 5: Commit**

```bash
git add OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift OPSTests/GuidedCatalogSetupProfileTests.swift
git commit -m "fix(catalog-setup): gate assemblies on sells != services so services-only shops skip the package builder"
```

---

## Task 2 — Allow a price-only / empty package to save

**Files:**
- Modify: `OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift:45-62`

A services-only / flat-price shop must be able to save "Full Detail — $280, nothing inside." The model already persists this correctly (the materials/labor loops just don't run; the product is a valid `kind=package`, `bundle_pricing_mode=override`, zero children). Only the UI gate forbids it.

- [ ] **Step 1: Implement** — drop the `!isEmptyContents` requirement from `canSave` and remove its `disabledReason` branch:

```swift
    private var canSave: Bool {
        guard isOnline, !model.isSaving else { return false }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard priceAmount != nil else { return false }
        guard !model.isDuplicateAssemblyName(draft.name) else { return false }
        return true
    }

    private var disabledReason: String? {
        if model.isSaving { return nil }
        if !isOnline { return "// OFFLINE — SAVE PAUSED" }   // honest copy, see T11
        if model.isDuplicateAssemblyName(draft.name) { return "// NAME ALREADY USED" }
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || priceAmount == nil {
            return "// NAME AND PRICE REQUIRED"
        }
        return nil
    }
```

(`isEmptyContents` stays — it's still used by `contentsCard` and by the trackCost-aware margin in T3.)

- [ ] **Step 2: Verify** — build (device-generic, see "Build verification" at the end). Manual: a package with only name+price now shows an enabled SAVE PACKAGE.

- [ ] **Step 3: Commit** (folded with T3 — same file, one logical "assembly handles the simplest shop" change). Hold the commit until T3 lands.

---

## Task 3 — Honor `trackCost` in the assembly module + sheets

**Files:**
- Modify: `OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift`
- Modify: `OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift`
- Modify: `OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyLaborSheet.swift`

When the operator chose "just set prices" (`trackCost == false`), the assembly module must not show or demand cost data — mirroring the services module, which already honors it.

- [ ] **Step 1: AssemblyModuleView — add a `trackCost` read + a no-false-100% margin**

Add near the other computed props:

```swift
    private var trackCost: Bool { model.profile?.trackCost ?? true }
    /// Margin is meaningful only when we're tracking cost AND there's something in the package.
    private var showMarginCard: Bool { trackCost && !isEmptyContents }
```

In `body`, render the margin card conditionally:

```swift
                contentsCard
                if showMarginCard { marginCard }
                saveButton
```

- [ ] **Step 2: AssemblyModuleView — pass `trackCost` to the sheets**

```swift
        .sheet(isPresented: $showingMaterialSheet) {
            AddAssemblyMaterialSheet(companyId: model.companyId,
                                     units: companyUnits,
                                     trackCost: trackCost) { draft.materials.append($0) }
        }
        .sheet(isPresented: $showingLaborSheet) {
            AddAssemblyLaborSheet(companyId: model.companyId,
                                  units: companyUnits,
                                  trackCost: trackCost) { draft.labor.append($0) }
        }
```

(`companyUnits` is added in T6. If implementing T3 before T6, temporarily pass `units: []`; T6 wires the real array. Recommended order is T6→T7→T3, or land them in one pass since they share these files.)

- [ ] **Step 3: AddAssemblyMaterialSheet — accept the new params, make cost optional + trackCost-aware**

Replace the stored-prop header:

```swift
struct AddAssemblyMaterialSheet: View {
    let companyId: String
    let units: [CatalogUnit]
    let trackCost: Bool
    let onAdd: (AssemblyMaterialDraft) -> Void
```

Make cost optional in `canAdd` (cost is never required; qty still is):

```swift
    private var canAdd: Bool {
        switch mode {
        case .new:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && isNumber(qtyText)
                && (costText.trimmingCharacters(in: .whitespaces).isEmpty || isNumber(costText))
        case .existing:
            return selectedVariantId != nil && isNumber(qtyText)
        }
    }
```

Show the cost field only when tracking cost (T4 adds the unit picker into `newFields`):

```swift
    @ViewBuilder
    private var newFields: some View {
        CatalogFieldLabel("Name")
        TextField("e.g. Top rail", text: $name)
            .textFieldStyle(CatalogTextFieldStyle())
            .focused($nameFocused)

        if trackCost {
            CatalogFieldLabel("Your cost (optional)")
            moneyField($costText, placeholder: "0")
        }

        CatalogFieldLabel("Unit")
        UnitPickerField(
            selectedUnitId: $unitId,
            companyUnits: units,
            canCreateNew: true,
            onCreateRequested: { showingUnitCreate = true },
            allowFlatRate: true
        )
    }
```

Replace the now-unused local `companyUnits` computed prop (it filtered `allUnits`); the sheet now receives `units` from the parent. Keep `@Query private var allUnits`/`allFamilies`/`allVariants` for the pick-existing path **only if still needed** — `allUnits` is no longer used (units come in as a param), so delete `@Query private var allUnits` and its `companyUnits` helper to avoid dead state. `allFamilies`/`allVariants` stay (pick-existing).

- [ ] **Step 4: AddAssemblyLaborSheet — accept params, unit + trackCost-aware** (full rewrite in T7; the trackCost gating lands there). For T3's scope here, the labor sheet's new signature is:

```swift
struct AddAssemblyLaborSheet: View {
    let companyId: String
    let units: [CatalogUnit]
    let trackCost: Bool
    let onAdd: (AssemblyLaborDraft) -> Void
```

- [ ] **Step 5: Verify** — build green; manual: as a `trackCost==false` operator, the assembly module shows no margin card, the material sheet shows no "Your cost" field, and a price-only package saves.

- [ ] **Step 6: Commit** (after T2, T6, T7 — these four all touch the assembly trio; commit as one coherent change):

```bash
git add OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift \
        OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift \
        OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyLaborSheet.swift \
        OPS/Services/Catalog/GuidedCatalogSetup/AssemblyDraft.swift \
        OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift
git commit -m "feat(catalog-setup): per-unit package + piecework labor, price-only packages, honor trackCost"
```

> Note: T2, T3, T6, T7 are one atomic "the assembly module now fits real trades" change across the assembly trio + draft + model. They are described as separate tasks for clarity but commit together. T4 (material unit-picker regression) and T5 (seeding) commit separately.

---

## Task 4 — Re-add the create-new unit picker (REGRESSION)

**Files:**
- Modify: `OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift`

Last round's add-existing rewrite dropped `UnitPickerField` from the create-new path; `unitId`/`showingUnitCreate` became dead state and inline materials save **unitless**. The fix is folded into T3 Step 3 (the `UnitPickerField` block in `newFields`) plus the already-present `.sheet(isPresented: $showingUnitCreate) { InlineCreateUnitSheet(...) }`. This task is the dedicated verification + commit of the regression repair.

- [ ] **Step 1: Confirm wiring** — `newFields` renders `UnitPickerField` (T3 Step 3); `$showingUnitCreate` opens `InlineCreateUnitSheet`; `buildDraft()` already passes `unitId: unitId` for the `.new` case. The commit (`saveAssembly`) already forwards `material.unitId` to both the scaffolded variant and the recipe row.

- [ ] **Step 2: Verify** — build green; manual: create-new "Mulch" → pick/create "CU YD" → ADD → the contents row + the committed `catalog_variant`/`product_material` carry the unit (no longer unitless).

- [ ] **Step 3: Commit** (separate from the assembly-trio commit — this is the regression fix specifically):

```bash
git add OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift
git commit -m "fix(catalog-setup): restore the unit picker on the create-new material path (was saving unitless)"
```

> If T3 and T4 land in the same edit pass on this file, fold into a single commit with the message above (it's the headline change to that file).

---

## Task 5 — Seed a starter unit pack on first catalog entry

**Files:**
- Modify: `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift`
- Modify: `OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift`
- Test: `OPSTests/GuidedCatalogSetupModelTests.swift`

Verified against prod (audit): there is **no** client- or server-side seeder for `catalog_units` (the `initialize_company_defaults` RPC seeds views/trial, not units; `InventoryRepository.createDefaultUnits` is the legacy InventoryUnit table). 50/55 companies have zero units. Cold-start operators must invent hour/each/foot one detour at a time. We seed a sensible pack — **HR, DAY, EA, FT, SQ FT, CU YD, TON** — the moment they commit to setup (START), idempotently, online only.

The pack maps cleanly through the existing `pricingUnit(for:)`: `HR`→`.hour`, `DAY`→`.day`, `EA`(count)→`.each`, `FT`(length)→`.linearFoot`, `SQ FT`(area)→`.sqft`. `CU YD`(volume) + `TON`(mass) carry their `unitId`/display on the product (label preserved on estimates); their `pricing_unit` stays `flat_rate` because `ProductPricingUnit` has no volume/mass case and adding one is a cross-platform schema-risk deferred to its own slice. `UnitPickerField` already renders Volume + Weight sections, so seeded CU YD/TON appear grouped.

- [ ] **Step 1: Add the seeder to the model** (`GuidedCatalogSetupModel`, new MARK section):

```swift
    // MARK: - Default unit seeding (cold-start companies have none)

    /// The starter unit pack: (display, dimension, abbreviation). Mapped through
    /// `pricingUnit(for:)` where an enum case exists; volume/mass carry the unit
    /// id + label on the product (pricing stays flat-rate, no enum case yet).
    static let defaultUnitPack: [(display: String, dimension: String, abbreviation: String)] = [
        ("HR",    "time",   "hr"),
        ("DAY",   "time",   "day"),
        ("EA",    "count",  "ea"),
        ("FT",    "length", "ft"),
        ("SQ FT", "area",   "sq ft"),
        ("CU YD", "volume", "cu yd"),
        ("TON",   "mass",   "ton")
    ]

    /// Which pack entries are missing for this company (case-insensitive match on
    /// dimension + display, so an existing "ft" is never duplicated by "FT").
    static func missingDefaultUnits(existing: [CatalogUnit])
        -> [(display: String, dimension: String, abbreviation: String)] {
        let have = Set(existing.map { "\($0.dimension.lowercased())|\($0.display.lowercased())" })
        return defaultUnitPack.filter { !have.contains("\($0.dimension.lowercased())|\($0.display.lowercased())") }
    }

    private var didSeedUnits = false

    /// Idempotent, online-only. Creates any missing starter units remotely and
    /// inserts them locally so the modules' @Query pickers refresh immediately.
    func seedDefaultUnitsIfNeeded(existing: [CatalogUnit], modelContext: ModelContext) {
        guard !didSeedUnits, !companyId.isEmpty else { return }
        let missing = Self.missingDefaultUnits(existing: existing)
        guard !missing.isEmpty else { didSeedUnits = true; return }
        didSeedUnits = true
        let companyId = self.companyId
        let baseSort = (existing.map(\.sortOrder).max() ?? 0)
        let repo = CatalogRepository(companyId: companyId)
        Task {
            for (offset, spec) in missing.enumerated() {
                do {
                    let dto = CreateCatalogUnitDTO(
                        companyId: companyId, display: spec.display,
                        abbreviation: spec.abbreviation, dimension: spec.dimension,
                        isDefault: false, sortOrder: baseSort + offset + 1)
                    let created = try await repo.createUnit(dto)
                    let model = created.toModel()
                    model.lastSyncedAt = Date()
                    model.needsSync = false
                    modelContext.insert(model)
                } catch {
                    print("[GuidedCatalogSetupModel] unit seed failed for \(spec.display): \(error)")
                }
            }
            try? modelContext.save()
        }
    }
```

- [ ] **Step 2: Trigger seeding from the flow on START** (`GuidedCatalogSetupFlow`)

Add to the flow:

```swift
    @Environment(\.modelContext) private var modelContext
    @Query private var allUnits: [CatalogUnit]
```

(and `import SwiftData` at the top). Add a `companyUnits` helper filtered by `model.companyId` + `deletedAt == nil`. In `startPlan()`, seed when online:

```swift
    private func startPlan() {
        if dataController.isConnected {
            model.seedDefaultUnitsIfNeeded(existing: companyUnits, modelContext: modelContext)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(flowAnimation) { model.confirmPlan() }
    }
```

> Offline edge: if they START offline, units don't seed this session (a known limitation, surfaced honestly by the offline banner in T11 — saves are paused offline anyway). The stock-module slice will revisit offline queueing holistically.

- [ ] **Step 3: Test the pure key-diff** (append to `GuidedCatalogSetupModelTests`):

```swift
    func test_missingDefaultUnits_skipsExistingCaseInsensitive() {
        let ft = CatalogUnit(companyId: "c", display: "ft", dimension: "length")
        let missing = GuidedCatalogSetupModel.missingDefaultUnits(existing: [ft])
        XCTAssertFalse(missing.contains { $0.display == "FT" })          // existing ft not re-seeded
        XCTAssertTrue(missing.contains { $0.display == "HR" })           // still seeds the rest
        XCTAssertEqual(missing.count, GuidedCatalogSetupModel.defaultUnitPack.count - 1)
    }

    func test_missingDefaultUnits_emptyCompany_seedsWholePack() {
        XCTAssertEqual(GuidedCatalogSetupModel.missingDefaultUnits(existing: []).count,
                       GuidedCatalogSetupModel.defaultUnitPack.count)
    }
```

- [ ] **Step 4: Run** — `-only-testing:OPSTests/GuidedCatalogSetupModelTests`; PASS.

- [ ] **Step 5: Commit**

```bash
git add OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift \
        OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift \
        OPSTests/GuidedCatalogSetupModelTests.swift
git commit -m "feat(catalog-setup): seed a starter unit pack (hr, day, ea, ft, sq ft, cu yd, ton) on first entry"
```

---

## Task 6 — Per-unit package pricing

**Files:**
- Modify: `OPS/Services/Catalog/GuidedCatalogSetup/AssemblyDraft.swift`
- Modify: `OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift`
- Modify: `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift`

Deck & Rail prices packages **$70/linear ft** / **$11/sq ft**; Landscaping prices per area. The model already throws this away (`pricingUnit: .flatRate, unitId: nil`). Give the package a unit and drive `pricingUnit(for:)` from it.

- [ ] **Step 1: `AssemblyDraft` — add the package unit**

```swift
struct AssemblyDraft: Codable, Equatable {
    var name: String = ""
    var taskTypeId: String?
    var priceText: String = ""              // fixed all-in sell price (per unit when priceUnitId set)
    var priceUnitId: String?                // nil = flat rate (whole job)
    var materials: [AssemblyMaterialDraft] = []
    var labor: [AssemblyLaborDraft] = []
}
```

- [ ] **Step 2: `AssemblyModuleView` — units source + unit picker on the price card**

Add the SwiftData query + filtered units (mirrors `ProductLineModuleView`):

```swift
    @Query private var allUnits: [CatalogUnit]

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == model.companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }
```

Add the unit picker to `priceCard`, under the money field:

```swift
            CatalogFieldLabel("Unit")
            UnitPickerField(
                selectedUnitId: $draft.priceUnitId,
                companyUnits: companyUnits,
                canCreateNew: true,
                onCreateRequested: { showingUnitCreate = true },
                allowFlatRate: true
            )
```

Add `@State private var showingUnitCreate = false` and the sheet:

```swift
        .sheet(isPresented: $showingUnitCreate) {
            InlineCreateUnitSheet(companyId: model.companyId) { draft.priceUnitId = $0 }
        }
```

- [ ] **Step 3: `save()` passes units; `saveAssembly` resolves the unit**

```swift
    private func save() async {
        await model.saveAssembly(draft, units: companyUnits, modelContext: modelContext)
        ...
    }
```

In `GuidedCatalogSetupModel.saveAssembly`, change the signature to `saveAssembly(_ draft: AssemblyDraft, units: [CatalogUnit], modelContext: ModelContext)` and resolve the package unit:

```swift
        let priceUnit = units.first { $0.id == draft.priceUnitId }
        var packageDTO = CreateProductDTO(
            companyId: companyId, name: name, description: nil,
            basePrice: price, unitCost: nil, unit: priceUnit?.display,
            pricingUnit: pricingUnit(for: priceUnit).rawValue, unitId: priceUnit?.id,
            category: nil, categoryId: nil, sku: nil, thumbnailUrl: nil,
            kind: ProductCategory.bundle.derivedKindRaw,
            type: ProductCategory.bundle.derivedType.rawValue,
            isTaxable: ProductCategory.bundle.defaultTaxable,
            taskTypeId: draft.taskTypeId, taskTypeRef: draft.taskTypeId, linkedCatalogItemId: nil)
        packageDTO.bundlePricingMode = BundlePricingMode.override.rawValue
```

- [ ] **Step 4: Verify** — build green; manual: package "Picket railing install" priced 70, unit FT → committed product has `pricing_unit = linear_foot`, `unit_id = <ft>`. Folds into the T2/T3/T7 assembly commit.

---

## Task 7 — Piecework labor (per-ft / per-sq-ft / per-day)

**Files:**
- Modify: `OPS/Services/Catalog/GuidedCatalogSetup/AssemblyDraft.swift`
- Modify: `OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyLaborSheet.swift`
- Modify: `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift`

Labor is hard-coded `.hour`. Deck & Rail's labor is **$/linear ft** piecework; Landscaping's paver labor is **$/sq ft**. Give the labor sheet a unit + dynamic labels, and drive `pricingUnit` from it.

- [ ] **Step 1: `AssemblyLaborDraft` — add the labor unit**

```swift
struct AssemblyLaborDraft: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var sellText: String = ""   // labor sell rate (per chosen unit)
    var costText: String = ""   // your labor cost (per chosen unit)
    var hoursText: String = ""  // quantity per assembly (hours, ft, sq ft…)
    var unitId: String?         // nil = hour-style flat; resolved via pricingUnit(for:)
}
```

- [ ] **Step 2: Rewrite `AddAssemblyLaborSheet`** — accept `companyId`/`units`/`trackCost` (T3), add a `UnitPickerField` (default to the company's HR unit when present), derive a `unitSuffix` for the rate labels and a `qtyLabel`, gate cost/margin on `trackCost`, and make cost optional:

```swift
struct AddAssemblyLaborSheet: View {
    let companyId: String
    let units: [CatalogUnit]
    let trackCost: Bool
    let onAdd: (AssemblyLaborDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = AssemblyLaborDraft()
    @State private var showingUnitCreate = false
    @FocusState private var nameFocused: Bool

    private var selectedUnit: CatalogUnit? { units.first { $0.id == draft.unitId } }
    /// "hr" / "ft" / "sq ft" — drives the rate-field labels. Defaults to "hr".
    private var unitSuffix: String { selectedUnit?.display.lowercased() ?? "hr" }
    /// "Hours per job" for hourly; "Qty per job (ft)" otherwise.
    private var qtyLabel: String {
        guard let u = selectedUnit, u.dimension != "time" else { return "Hours per job" }
        return "Qty per job (\(u.display.lowercased()))"
    }
    private var canAdd: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isNumber(draft.hoursText)
            && (draft.costText.trimmingCharacters(in: .whitespaces).isEmpty || isNumber(draft.costText))
            && (draft.sellText.trimmingCharacters(in: .whitespaces).isEmpty || isNumber(draft.sellText))
    }
    // ... isNumber + marginPercent unchanged ...
```

Body changes: rate labels read `"Sell / \(unitSuffix)"` and `"Your cost / \(unitSuffix)"`; the cost field + margin readout render only `if trackCost`; add the unit picker (`CatalogFieldLabel("Unit")` + `UnitPickerField(selectedUnitId: $draft.unitId, companyUnits: units, canCreateNew: true, onCreateRequested: { showingUnitCreate = true }, allowFlatRate: false)`); the qty field label is `qtyLabel`. Default the unit on appear:

```swift
        .sheet(isPresented: $showingUnitCreate) {
            InlineCreateUnitSheet(companyId: companyId) { draft.unitId = $0 }
        }
        .onAppear {
            if draft.unitId == nil {
                draft.unitId = units.first { $0.dimension == "time" && $0.display.lowercased() == "hr" }?.id
                    ?? units.first { $0.dimension == "time" }?.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { nameFocused = true }
        }
```

- [ ] **Step 3: `saveAssembly` labor loop drives pricingUnit from the unit**

```swift
            for (index, labor) in draft.labor.enumerated() {
                let labName = labor.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !labName.isEmpty else { continue }
                let laborUnit = units.first { $0.id == labor.unitId }
                do {
                    let laborDTO = CreateProductDTO(
                        companyId: companyId, name: labName, description: nil,
                        basePrice: parseMoney(labor.sellText) ?? 0, unitCost: parseMoney(labor.costText),
                        unit: laborUnit?.display, pricingUnit: pricingUnit(for: laborUnit).rawValue,
                        unitId: laborUnit?.id,
                        category: nil, categoryId: nil, sku: nil, thumbnailUrl: nil,
                        kind: ProductCategory.service.derivedKindRaw,
                        type: ProductCategory.service.derivedType.rawValue,
                        isTaxable: ProductCategory.service.defaultTaxable,
                        taskTypeId: nil, taskTypeRef: nil, linkedCatalogItemId: nil)
                    let laborProduct = try await productRepo.create(laborDTO)
                    modelContext.insert(laborProduct.toModel())
                    _ = try await bundleRepo.create(CreateProductBundleItemDTO(
                        id: UUID().uuidString, companyId: companyId,
                        bundleProductId: package.id, childProductId: laborProduct.id,
                        quantity: parseMoney(labor.hoursText) ?? 1, displayOrder: index))
                } catch { ... }
            }
```

- [ ] **Step 4: Verify** — build green; manual: labor "Rail install labor" unit FT, $/ft → committed labor service has `pricing_unit = linear_foot`. Labels read "Sell / ft", "Qty per job (ft)". With `trackCost==false`, no cost/margin fields. Folds into the assembly commit.

---

## Task 8 — BACK from the plan must not wipe the survey (REGRESSION)

**Files:**
- Modify: `OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift`
- Modify: `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift`
- Modify: `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift`
- Modify: `OPS/Views/Catalog/GuidedSetup/Survey/GuidedSetupSurveyView.swift`

`goBack()` sends `.plan → .survey(...)`; the survey view re-inits fresh `@State` and clears every answer. Fix by lifting survey progress into the model (also fixes resume-mid-survey for free) and persisting it.

- [ ] **Step 1: `SurveyAnswers` + `SurveyQuestionID` become Codable** (`SurveyQuestion.swift`):

```swift
enum SurveyQuestionID: String, CaseIterable, Equatable, Codable { ... }   // add Codable
struct SurveyAnswers: Equatable, Codable { ... }                          // add Codable
```

(All fields are optionals of already-Codable enums — synthesis is automatic.)

- [ ] **Step 2: Lift survey state into the model** (`GuidedCatalogSetupModel`):

```swift
    @Published var surveyAnswers = SurveyAnswers()
    @Published var surveyQuestion: SurveyQuestionID = SurveyFlow.firstQuestion
    @Published var surveyHistory: [SurveyQuestionID] = []
```

`completeSurvey` is unchanged (it sets `profile` + `phase = .plan` + `persist()`) — crucially it does **not** reset the survey state, so a later `goBack()` to `.survey` finds it intact. Reset the survey state only in the "START OVER" branch.

- [ ] **Step 3: Persist survey state** (`GuidedCatalogSetupDraft.swift`): bump `currentSchemaVersion` to `3`; add `surveyAnswers`/`surveyQuestion`/`surveyHistory` to `GuidedCatalogSetupDraftSnapshot` (with defaulted init params for backward-safe construction); write them in `persist()` and read them in `restoreIfAvailable()`.

- [ ] **Step 4: Bind the survey view to the model** (`GuidedSetupSurveyView.swift`): delete the three local `@State` (`answers`, `current`, `history`); read `model.surveyQuestion` for the current question, `model.surveyHistory` for the back affordance, and mutate `model.surveyAnswers`/`surveyQuestion`/`surveyHistory` in `select`/`goBack`:

```swift
    var body: some View {
        let q = SurveyFlow.content(model.surveyQuestion)
        ...
                if !model.surveyHistory.isEmpty { backButton }
        ...
    }

    private func select(_ option: SurveyOption) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SurveyFlow.apply(option.value, to: &model.surveyAnswers)
        if let next = SurveyFlow.next(after: model.surveyQuestion, answers: model.surveyAnswers) {
            model.surveyHistory.append(model.surveyQuestion)
            withAnimation(flowAnimation) { model.surveyQuestion = next }
        } else if let profile = SurveyFlow.finalize(model.surveyAnswers) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.completeSurvey(with: profile)
        }
    }

    private func goBack() {
        guard let previous = model.surveyHistory.popLast() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(flowAnimation) { model.surveyQuestion = previous }
    }
```

- [ ] **Step 5: Reset on START OVER** (`GuidedCatalogSetupFlow.swift`, the confirmationDialog "START OVER" button): also clear `model.surveyAnswers = SurveyAnswers()`, `model.surveyQuestion = SurveyFlow.firstQuestion`, `model.surveyHistory = []`.

- [ ] **Step 6: Verify** — build green; existing `GuidedCatalogSetupSurveyTests` (pure `SurveyFlow`) still pass. Manual: answer the survey, reach the plan, tap BACK → the last question shows with all prior answers intact; BACK again steps back through the real history.

- [ ] **Step 7: Commit**

```bash
git add OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift \
        OPS/Views/Catalog/GuidedSetup/Survey/GuidedSetupSurveyView.swift \
        OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift \
        OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift
git commit -m "fix(catalog-setup): preserve survey answers when stepping back from the plan"
```

---

## Task 9 — Labeled SKIP on optional modules

**Files:**
- Modify: `OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift`

Every module is optional, but the only control reads NEXT/FINISH (primary), so cautious operators think the assembly module is mandatory. Make the primary advance label honest: **last module → FINISH; otherwise "SKIP" when the current module has nothing committed, "NEXT" once it does.** No redundant buttons; the word itself tells the user they may leave it empty.

- [ ] **Step 1: Add a "current module has items" read** (`GuidedCatalogSetupFlow`):

```swift
    private var currentModuleHasItems: Bool {
        switch model.currentModule {
        case .services: return model.savedLines.contains { $0.kind == .service }
        case .goods:    return model.savedLines.contains { $0.kind == .good }
        case .assembly: return !model.savedAssemblies.isEmpty
        case .stock, .none: return false
        }
    }

    private func advanceLabel(isLast: Bool) -> String {
        if isLast { return "FINISH" }
        return currentModuleHasItems ? "NEXT" : "SKIP"
    }
```

- [ ] **Step 2: Use it in the module bottom bar**:

```swift
        case .module(let index):
            let isLast = index >= model.modules.count - 1
            OPSFloatingButtonBar {
                Button { advance() } label: { Text(advanceLabel(isLast: isLast)) }
                    .opsPrimaryButtonStyle()
                    .accessibilityLabel(isLast ? "Finish setup"
                                                : (currentModuleHasItems ? "Next step" : "Skip this step"))
            }
```

- [ ] **Step 3: Verify** — build green; manual: assembly module with nothing added shows "SKIP"; after saving a package it reads "NEXT"; the last module reads "FINISH".

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift
git commit -m "feat(catalog-setup): label the advance action SKIP on empty optional modules"
```

> Copy note: "SKIP", "NEXT", "FINISH" are existing single-word OPS-voice button labels — no new copy. The accessibility hints are reviewed in the T11 copy pass.

---

## Task 10 — Finish clears the draft (and stops the re-fired notification)

**Files:**
- Modify: `OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift`

`finish()`/`viewCatalog()` only `dismiss()`; the `catalog-guided` draft survives, so next open prompts "resume?" for a completed run, and resuming re-fires the §14 completion notification (a fresh model resets `didPostCompletion`). Clear the draft on a successful finish.

- [ ] **Step 1: Implement**

```swift
    private func viewCatalog() {
        model.clearDraft()
        selectedSegmentRaw = "PRODUCTS"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }

    private func finish() {
        model.clearDraft()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }
```

- [ ] **Step 2: Verify** — build green; manual: complete a run → DONE → reopen "Set up your catalog" → no "resume?" prompt, no duplicate notification.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift
git commit -m "fix(catalog-setup): clear the draft on finish so completed runs don't prompt resume or re-fire the notification"
```

---

## Task 11 — Make the offline banner honest (copy)

**Files:**
- Modify: `OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift`
- (already referenced) `disabledReason` strings in `AssemblyModuleView.swift` / `ProductLineModuleView.swift`

Saving is hard-blocked offline with no queue, but the banner says "You can keep moving. Saving starts when the connection is back." Queueing the whole catalog write path is a large, separate effort (deferred to the stock-module/offline slice); the honest, zero-risk fix now is to tell the truth. **All strings below are drafts — run the `ops-copywriter` skill and use its output.**

- [ ] **Step 1: Replace the banner body** (`offlineBanner`): draft —

```
// OFFLINE
Adding pauses until you're back on. Your place is saved.
```

- [ ] **Step 2: Align the inline disabled reasons** — `AssemblyModuleView`/`ProductLineModuleView` `disabledReason` for offline reads `"// OFFLINE — SAVE PAUSED"` (consistent with the banner; the current "SAVE BLOCKED" reads as an error, "PAUSED" reads as a wait).

- [ ] **Step 3: Run `ops-copywriter`** on the banner body, the two disabled reasons, and the T9 accessibility hint; replace drafts with approved copy.

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift \
        OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift \
        OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift
git commit -m "fix(catalog-setup): tell the truth in the offline banner — adds pause, place is saved"
```

---

## Deferred — the next slice (clearly out of scope, with rationale)

These are real audit findings intentionally **not** built this iteration. Half-building them would violate the OPS perfection bar; each deserves its own verified slice.

1. **Variants / tiers on a line** (Sedan/SUV/Truck; black/white; the 24-variant vinyl matrix) — wanted by all four. Requires wiring `CatalogOption` / `CatalogOptionValue` / `CatalogVariantOptionValue` (and/or `products.tiered_pricing_json`) on create **and verifying the full downstream read path** (how estimate lines consume option-priced tiers). The columns exist (no migration), but writing tier data that the estimate builder doesn't yet read would be a half-feature. **Dedicated slice: "PIPELINE-adjacent CATALOG VARIANTS".** This is the single highest-value next item.
2. **Volume/mass in the stock-*counting* flow** (`GuidedStockUnitResolver` / `GuidedMeasurement` only know piece/length/area). The catalog modules now have CU YD/TON via seeding (T5); the stock counter does not. It lives in the reused `GuidedStockSetupFlow`, owned by the 2026-06-05 stock quality pass — changing it belongs with the **stock-module slice** to avoid stepping on that work.
3. **Stock handoff inline / return-to-Done payoff + completion-fires-regardless-of-path + permission-gate alignment** (`catalog.products.manage` vs `catalog.manage`). Architectural change to how the stock module is reached. **Stock-module slice.**
4. **Surface the existing CSV importer (`CatalogImportSheet`, PRODUCTS tab) inside the Goods module**, plus clone-last-line / keep-keyboard-up bulk entry, and a SKU field on goods. The importer exists one menu-row away; wiring it in-flow + SKU is a focused **bulk-entry slice**.
5. **Markup mode** (type cost, set "×2", price auto-fills) — Plumbing's whole job. A pricing-input affordance across services/goods/assembly. **Bulk-entry slice.**
6. **Recurring maintenance routing** (Landscaping) — likely belongs in scheduling/contracts; the honest move is to route out, not fake it in the catalog. **Needs product decision; not a catalog change.**
7. **Per-material "I stock this / I buy per job" flag** (Deck & Rail membrane vs offcuts); **shared-piece dedup** on create-new; **in-flow edit/remove** of saved lines; **progress-bar-jumps-backward** survey→plan polish. Backlog — none blocks onboarding.

---

## Build & test verification (run after each task; final gate)

- **Device-generic build (the gate, per ops-ios CLAUDE.md — never the simulator for a plain build):**
  ```
  cd /Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/guided-catalog-setup
  xcodebuild -scheme OPS -destination 'generic/platform=iOS' -derivedDataPath ./DerivedData -quiet build
  ```
  Iterate to **0 errors**. SourceKit may report phantom "cannot find type" — `xcodebuild` is the source of truth.
- **Unit tests (simulator destination):**
  ```
  xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
    -derivedDataPath ./DerivedData \
    -only-testing:OPSTests/GuidedCatalogSetupProfileTests \
    -only-testing:OPSTests/GuidedCatalogSetupModelTests \
    -only-testing:OPSTests/GuidedCatalogSetupAssemblyTests \
    -only-testing:OPSTests/GuidedCatalogSetupSurveyTests
  ```
- Check `ps aux | grep xcodebuild` first — a sibling worktree may be mid-build on a different DerivedData path; use the worktree-local `./DerivedData` so they never collide.

## Bible / spec update (same session, per CLAUDE.md)

No schema change. After the build is green, update **in the same session**:
- `docs/superpowers/specs/2026-06-09-guided-catalog-setup-design.md` — note iteration-2: `runAssemblies` gate, price-only packages, trackCost in the assembly module, per-unit package + piecework labor, the seeded starter unit pack, and the lifted/persisted survey state (snapshot schema v3).
- `ops-software-bible/07_SPECIALIZED_FEATURES.md` — if/when a Guided Catalog Setup subsection exists, record the starter-unit seeding behavior and the per-unit/piecework assembly pricing. (Confirm the subsection exists before editing; the design spec §11 plans it but it may not be written yet — if absent, leave a note rather than inventing a section out of scope.)

---

## Self-review

**Spec coverage:** Items 1–3 of the hub's fix order (T1/T2/T3 routing+price-only+trackCost; T5/T4 units; T6/T7 per-unit+piecework) + both regressions (T4 create-new unit picker; T8 BACK-preserves-survey) + the cheap item-5 wins (T9 SKIP, T10 finish-clears-draft, T11 offline honesty) are all present. Item 4 (variants) and the heavy item-5 work are deferred with rationale — matching the brief's "build 1–3 + both regressions; leave 4–5 in the plan."

**Placeholder scan:** No TBD/TODO. Every code step shows real code grounded in the read source. Copy strings in T11 are explicitly marked draft-pending-`ops-copywriter`, not placeholders for logic.

**Type consistency:** `priceUnitId` (AssemblyDraft), `unitId` (AssemblyLaborDraft), `units:` parameter threaded through `saveAssembly` + the two sheets, `pricingUnit(for:)` (existing free function), `companyUnits` (filtered) — names are consistent across T3/T6/T7. `seedDefaultUnitsIfNeeded`/`missingDefaultUnits`/`defaultUnitPack` consistent across T5 + its tests. Survey state `surveyAnswers`/`surveyQuestion`/`surveyHistory` consistent across T8 model/view/snapshot. `currentModuleHasItems`/`advanceLabel` consistent in T9. No undefined symbol referenced.

**Sync-constraint check:** Every `pricing_unit` value written (`flat_rate`, `linear_foot`, `sqft`, `each`, `hour`, `day`) is an existing `ProductPricingUnit` case already written by the services module today — no new enum case, no schema change, no risk to old App Store builds or the web app. Seeding only inserts `catalog_units` rows (additive). ✅
