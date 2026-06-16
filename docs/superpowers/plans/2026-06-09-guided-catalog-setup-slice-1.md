# Guided Catalog Setup — Slice 1 (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the adaptive spine of the catalog setup guide — a plain-language survey that produces a `BusinessProfile`, a tailored plan, a reusable **product-line module** (services + goods, each with sell rate + your cost + live margin), draft resume, and a done summary — fully serving any business that doesn't use assemblies or stock tracking.

**Architecture:** Self-contained full-screen flow (`.fullScreenCover`) in the mold of `GuidedStockSetupFlow` — **not** the overlay Wizard System (`OPS/Wizard/`). Steel-blue `OPSStyle.Colors.primaryAccent`, no `.wizardTarget()`. A `@MainActor ObservableObject` (`GuidedCatalogSetupModel`) owns phase/profile/plan/drafts and persists via a Codable snapshot keyed through `CatalogSetupDraftContext(scope:)`, mirroring `GuidedStockSetupModel`. Pure logic (profile→plan derivation, margin math, summary) is TDD'd with XCTest; SwiftUI views are verified by device build + `#Preview`.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest, Supabase repositories (`ProductRepository`, `CatalogRepository`), `NotificationRepository`.

**Spec:** `docs/superpowers/specs/2026-06-09-guided-catalog-setup-design.md`

**Rollout note:** Slices are build-verified increments. Existing entries (products/stock guided setup, new-bundle) stay live and untouched through Slices 1–2. The Catalog entry-point cutover to the unified guide + retirement of `GuidedProductSetupFlow` happen once in **Slice 3**. Slice 1 ships no user-facing entry; it is verified via unit tests + `#Preview`. This keeps real users on a working flow until the guide is complete — no stubs reach production. (This refines the spec: the **goods** module moves from Slice 3 into Slice 1, since it is the same form as services.)

**Reference files (read before/while implementing — they establish every pattern reused here):**
- `OPS/Views/Catalog/Stock/GuidedStockSetup/GuidedStockSetupFlow.swift` — flow shell: progress bar, offline banner, exit, bottom bar, reduced-motion, haptics.
- `OPS/Services/Catalog/GuidedStockSetupModel.swift` — model + draft persist/restore pattern.
- `OPS/Views/Catalog/Products/GuidedProductSetupFlow.swift` — product save (`CreateProductDTO` shape `:2104`, `createProduct` `:2164`), pickers, validation (`serviceCanSave` `:1924`), `formatMoney`/`parseMoney` `:2704`, completion notification `:2382`.
- `OPS/Styles/OPSStyle.swift` + `OPS/Styles/Components/` — tokens, `OPSFloatingButtonBar`, `ops*ButtonStyle()`, `nestedCard()`.

---

## File Structure (Slice 1)

**Create:**
- `OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift` — profile + enums + derived module flags + `SetupPlan` (pure, Codable). One responsibility: the diagnostic data + derivation.
- `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift` — `ObservableObject` state machine + persistence + save action.
- `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift` — `Codable` draft snapshot + store glue (reuses `CatalogSetupDraftContext`).
- `OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift` — container shell.
- `OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift` — question/option model + branching.
- `OPS/Views/Catalog/GuidedSetup/Survey/GuidedSetupSurveyView.swift` — the MCQ UI.
- `OPS/Views/Catalog/GuidedSetup/GuidedSetupPlanView.swift` — the plan screen.
- `OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift` — services + goods (parameterized by kind).
- `OPS/Views/Catalog/GuidedSetup/GuidedSetupDoneView.swift` — done summary.
- `OPSTests/Catalog/GuidedCatalogSetupProfileTests.swift` — profile→plan derivation tests.
- `OPSTests/Catalog/GuidedCatalogSetupModelTests.swift` — navigation, persistence round-trip, summary tests.

**Modify (Slice 1):** none in the live app graph — Slice 1 is additive. (`CatalogView.swift` wiring is Slice 3.)

---

## Task 1: BusinessProfile + SetupPlan (pure logic, TDD)

**Files:**
- Create: `OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift`
- Test: `OPSTests/Catalog/GuidedCatalogSetupProfileTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OPS

final class GuidedCatalogSetupProfileTests: XCTestCase {

    // Cleaning company: services-only, hourly, track cost.
    func test_servicesOnly_yieldsServicesModuleOnly() {
        let p = BusinessProfile(sells: .services, pricing: .hourly,
                                materialUse: .none, inventory: nil, trackCost: true)
        XCTAssertEqual(p.setupModules, [.services])
        XCTAssertFalse(p.runStock)
        XCTAssertFalse(p.runAssemblies)
    }

    // Fencing co (Canpro): mix, all-in price, lots of parts, count stock, track cost.
    func test_fencingCo_leadsWithAssembly_includesStock() {
        let p = BusinessProfile(sells: .mix, pricing: .fixedJob,
                                materialUse: .heavy, inventory: .tracked, trackCost: true)
        XCTAssertEqual(p.setupModules.first, .assembly) // hero leads
        XCTAssertTrue(p.setupModules.contains(.stock))
        XCTAssertTrue(p.runMaterials)
    }

    // Goods reseller: goods, line-item, no materials → goods only, no stock.
    func test_goodsLineItem_noMaterials_yieldsGoodsOnly() {
        let p = BusinessProfile(sells: .goods, pricing: .lineItem,
                                materialUse: .none, inventory: nil, trackCost: false)
        XCTAssertEqual(p.setupModules, [.goods])
    }

    // Cost-only materials (not tracked) → no stock module, but materials still on.
    func test_materialsCostOnly_noStockModule() {
        let p = BusinessProfile(sells: .mix, pricing: .fixedJob,
                                materialUse: .some, inventory: .costOnly, trackCost: true)
        XCTAssertTrue(p.runMaterials)
        XCTAssertFalse(p.runStock)
    }

    // Safety floor: an incoherent combo never yields zero modules.
    func test_zeroModuleFloor() {
        let p = BusinessProfile(sells: .goods, pricing: .hourly,
                                materialUse: .none, inventory: nil, trackCost: false)
        XCTAssertFalse(p.setupModules.isEmpty)
    }

    // De-dup: assembly + services + goods never repeat a kind.
    func test_modulesAreUnique() {
        let p = BusinessProfile(sells: .mix, pricing: .mixed,
                                materialUse: .some, inventory: .tracked, trackCost: true)
        XCTAssertEqual(p.setupModules.count, Set(p.setupModules).count)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild build-for-testing -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`
Expected: FAIL — `BusinessProfile` undefined. (Confirm the unit-test target name; default `OPSTests`. If the project's test target differs, place the file in the correct target group.)

- [ ] **Step 3: Implement `BusinessProfile.swift`**

```swift
import Foundation

enum BusinessSells: String, Codable, CaseIterable { case services, goods, mix }
enum BusinessPricing: String, Codable, CaseIterable { case fixedJob, lineItem, hourly, mixed }
enum BusinessMaterialUse: String, Codable, CaseIterable { case heavy, some, none }
enum BusinessInventoryChoice: String, Codable, CaseIterable { case tracked, costOnly }

enum SetupModuleKind: String, Codable, CaseIterable, Identifiable {
    case assembly, services, goods, stock
    var id: String { rawValue }
}

struct BusinessProfile: Codable, Equatable {
    var sells: BusinessSells
    var pricing: BusinessPricing
    var materialUse: BusinessMaterialUse
    var inventory: BusinessInventoryChoice?
    var trackCost: Bool
}

extension BusinessProfile {
    // Pricing only gates assemblies; selling a thing always offers its module.
    var runServices: Bool { sells != .goods || pricing == .hourly }
    var runGoods: Bool { sells != .services }
    var runAssemblies: Bool { pricing == .fixedJob || pricing == .mixed }
    var runMaterials: Bool { materialUse != .none }
    var runStock: Bool { runMaterials && inventory == .tracked }

    /// Ordered, unique modules. Assembly (the hero) leads for fixed-job businesses;
    /// safety floor guarantees a non-empty plan.
    var setupModules: [SetupModuleKind] {
        var mods: [SetupModuleKind] = []
        if runAssemblies { mods.append(.assembly) }
        if runServices { mods.append(.services) }
        if runGoods { mods.append(.goods) }
        if runStock { mods.append(.stock) }
        if mods.isEmpty { mods = [.services, .goods] }
        var seen = Set<SetupModuleKind>()
        return mods.filter { seen.insert($0).inserted }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/GuidedCatalogSetupProfileTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift OPSTests/Catalog/GuidedCatalogSetupProfileTests.swift
git commit -m "feat(catalog-setup): business profile + module derivation"
```

---

## Task 2: Draft persistence (TDD round-trip)

**Files:**
- Create: `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift`
- Test: extend `OPSTests/Catalog/GuidedCatalogSetupModelTests.swift`

- [ ] **Step 1: Read the existing draft store** to reuse its primitives. Inspect `CatalogSetupDraftContext` and `GuidedStockSetupDraftStore` (referenced from `OPS/Services/Catalog/GuidedStockSetupModel.swift:177-188`). Confirm: the context factory `CatalogSetupDraftContext.make(companyId:userId:)`, the `scope` field, and whether the store is generic over a `Codable` snapshot or stock-specific. Record the exact `save/load/clear` signatures.

- [ ] **Step 2: Write the failing round-trip test**

```swift
func test_draftSnapshot_roundTrips() throws {
    let profile = BusinessProfile(sells: .mix, pricing: .fixedJob,
                                  materialUse: .some, inventory: .costOnly, trackCost: true)
    let snapshot = GuidedCatalogSetupDraftSnapshot(
        phase: .module(index: 1),
        profile: profile,
        productLines: [ProductLineDraft(kind: .service, name: "Install labor",
                                        sellText: "120", costText: "60",
                                        unitId: nil, categoryId: nil)],
        savedLineIds: ["abc"]
    )
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(GuidedCatalogSetupDraftSnapshot.self, from: data)
    XCTAssertEqual(decoded, snapshot)
}
```

- [ ] **Step 3: Implement `GuidedCatalogSetupDraft.swift`**

```swift
import Foundation

/// One in-progress service/good line in the product-line module.
struct ProductLineDraft: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var kind: ProductLineKind     // defined in ProductLineModuleView's model (Task 6)
    var name: String = ""
    var sellText: String = ""
    var costText: String = ""
    var unitId: String?
    var categoryId: String?
}

enum GuidedCatalogPhase: Codable, Equatable {
    case survey(questionIndex: Int)
    case plan
    case module(index: Int)
    case done
}

struct GuidedCatalogSetupDraftSnapshot: Codable, Equatable {
    var phase: GuidedCatalogPhase
    var profile: BusinessProfile?
    var productLines: [ProductLineDraft]
    var savedLineIds: [String]
}

/// Persistence facade — mirrors GuidedStockSetupModel's use of the shared draft store
/// with a dedicated scope so guided-catalog drafts never collide with guided-stock drafts.
struct GuidedCatalogSetupDraftStore {
    static let shared = GuidedCatalogSetupDraftStore()
    private let scope = "catalog-guided"
    // Wrap the same store/context primitives confirmed in Step 1.
    // save(_:context:), load(context:), clear(context:) — see GuidedStockSetupModel:263-303.
}
```
(Finalize the store body against the exact primitives found in Step 1 — reuse, do not reinvent, the JSON-file/UserDefaults mechanism the stock store already uses.)

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/GuidedCatalogSetupModelTests/test_draftSnapshot_roundTrips`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift OPSTests/Catalog/GuidedCatalogSetupModelTests.swift
git commit -m "feat(catalog-setup): codable draft snapshot + store glue"
```

---

## Task 3: GuidedCatalogSetupModel (state machine)

**Files:**
- Create: `OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift`
- Test: extend `OPSTests/Catalog/GuidedCatalogSetupModelTests.swift`

Responsibilities: hold `phase`, `profile`, derived `modules`, `productLines`, `savedLineIds`; `advanceSurvey/answer`, `confirmPlan`, `nextModule/skipModule`, `persist/restore/clearDraft`, `saveProductLine(...)` (server create + local insert), `summary`, `postCompletionNotification`.

- [ ] **Step 1: Write failing tests** for navigation + summary:

```swift
@MainActor
func test_confirmPlan_entersFirstModule() {
    let m = GuidedCatalogSetupModel(companyId: "c", userId: "u")
    m.profile = BusinessProfile(sells: .services, pricing: .hourly,
                                materialUse: .none, inventory: nil, trackCost: true)
    m.confirmPlan()
    XCTAssertEqual(m.modules, [.services])
    if case .module(let i) = m.phase { XCTAssertEqual(i, 0) } else { XCTFail() }
}

@MainActor
func test_nextModule_advancesToDoneAfterLast() {
    let m = GuidedCatalogSetupModel(companyId: "c", userId: "u")
    m.profile = BusinessProfile(sells: .services, pricing: .hourly,
                                materialUse: .none, inventory: nil, trackCost: true)
    m.confirmPlan()
    m.advanceModule()
    XCTAssertEqual(m.phase, .done)
}

@MainActor
func test_summaryLine_pluralization() {
    XCTAssertEqual(GuidedCatalogSetupModel.summaryLine(services: 1, goods: 0),
                   "1 service")
    XCTAssertEqual(GuidedCatalogSetupModel.summaryLine(services: 2, goods: 3),
                   "2 services · 3 goods")
}
```

- [ ] **Step 2: Run to verify fail.** Run the model test class; expect FAIL (undefined symbols).

- [ ] **Step 3: Implement the model.** Mirror `GuidedStockSetupModel` structure (`@MainActor final class ... ObservableObject`, `@Published` state, `persist()` after every transition, `restoreIfAvailable()`, `clearDraft()`, `hasDraftToResume`). Key members:

```swift
import Foundation
import SwiftData

@MainActor
final class GuidedCatalogSetupModel: ObservableObject {
    @Published var phase: GuidedCatalogPhase = .survey(questionIndex: 0)
    @Published var profile: BusinessProfile?
    @Published var productLines: [ProductLineDraft] = []   // current module's working set
    @Published var savedLines: [SavedLine] = []            // committed this run
    @Published var isSaving = false
    @Published var errorMessage: String?

    let companyId: String
    let userId: String
    private let draftStore: GuidedCatalogSetupDraftStore

    init(companyId: String, userId: String,
         draftStore: GuidedCatalogSetupDraftStore = .shared) {
        self.companyId = companyId; self.userId = userId; self.draftStore = draftStore
    }

    var modules: [SetupModuleKind] { profile?.setupModules ?? [] }

    func confirmPlan() { phase = .module(index: 0); persist() }

    func advanceModule() {
        guard case .module(let i) = phase else { return }
        let next = i + 1
        phase = next < modules.count ? .module(index: next) : .done
        persist()
    }

    struct SavedLine: Identifiable, Equatable { let id: String; let name: String; let kind: ProductLineKind; let sell: Double }

    static func summaryLine(services: Int, goods: Int) -> String {
        func part(_ n: Int, _ s: String, _ p: String) -> String? { n > 0 ? "\(n) \(n == 1 ? s : p)" : nil }
        let parts = [part(services, "service", "services"), part(goods, "good", "goods")].compactMap { $0 }
        return parts.isEmpty ? "Nothing built" : parts.joined(separator: " · ")
    }

    // saveProductLine, persist/restore, postCompletionNotification — see Steps below.
}
```

- [ ] **Step 4: Implement `saveProductLine`** using the verified product-create path (mirror `GuidedProductSetupFlow.createProduct` `:2164` and the `CreateProductDTO` shape at `:2104`). For a service: `kind = ProductCategory.service.derivedKindRaw`, `type = ProductCategory.service.derivedType.rawValue`, `isTaxable = ProductCategory.service.defaultTaxable`, `basePrice = parseMoney(sellText)`, `unitCost = trackCost ? parseMoney(costText) : nil`. For a good: `ProductCategory.material.*`. Guard `isSaving`, success/error haptics, append to `savedLines`, `errorMessage` on throw.

```swift
@MainActor
func saveProductLine(_ draft: ProductLineDraft, trackCost: Bool,
                     units: [CatalogUnit], categories: [CatalogCategory],
                     modelContext: ModelContext) async {
    guard !isSaving else { return }
    isSaving = true; defer { isSaving = false }
    errorMessage = nil
    let category = ProductCategory(forLineKind: draft.kind)   // .service / .material
    let unit = units.first { $0.id == draft.unitId }
    var dto = CreateProductDTO(
        companyId: companyId,
        name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
        description: nil,
        basePrice: parseMoney(draft.sellText) ?? 0,
        unitCost: trackCost ? parseMoney(draft.costText) : nil,
        unit: unit?.display,
        pricingUnit: pricingUnit(for: unit).rawValue,
        unitId: unit?.id,
        category: categories.first { $0.id == draft.categoryId }?.name,
        categoryId: draft.categoryId,
        sku: nil, thumbnailUrl: nil,
        kind: category.derivedKindRaw,
        type: category.derivedType.rawValue,
        isTaxable: category.defaultTaxable,
        taskTypeId: nil, taskTypeRef: nil, linkedCatalogItemId: nil)
    dto.bundlePricingMode = nil
    do {
        let created = try await ProductRepository(companyId: companyId).create(dto)
        modelContext.insert(created.toModel()); try? modelContext.save()
        savedLines.append(.init(id: created.id, name: created.name, kind: draft.kind, sell: created.basePrice))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    } catch {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorMessage = error.localizedDescription
    }
}
```
(Reuse `parseMoney`/`pricingUnit(for:)` — replicate the small helpers from `GuidedProductSetupFlow.swift:2704` and `:2111` rather than duplicating across files; place them on the model. Confirm `ProductPricingUnit` cases and add a `ProductCategory(forLineKind:)` mapping.)

- [ ] **Step 5: Implement `persist/restore/clearDraft`** exactly mirroring `GuidedStockSetupModel:263-303`, encoding a `GuidedCatalogSetupDraftSnapshot`. Add `postCompletionNotification(services:goods:)` mirroring `GuidedProductSetupFlow.postCompletionNotificationIfNeeded` `:2382` (`type:"standard"`, `title:"CATALOG SETUP COMPLETE"`, `deepLinkType:"catalog_products"`, `actionUrl:"/catalog?segment=products"`, then post `.notificationReceived`).

- [ ] **Step 6: Run tests to verify pass.** Run the model test class; expect PASS.

- [ ] **Step 7: Commit**

```bash
git add OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift OPSTests/Catalog/GuidedCatalogSetupModelTests.swift
git commit -m "feat(catalog-setup): guided setup model — navigation, save, persistence"
```

---

## Task 4: Survey UI + question engine

**Files:**
- Create: `OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift`, `OPS/Views/Catalog/GuidedSetup/Survey/GuidedSetupSurveyView.swift`

- [ ] **Step 1: Model the questions.** `SurveyQuestion { id, eyebrow, prompt, options: [SurveyOption] }`, `SurveyOption { label, sublabel?, apply: (inout BusinessProfile.Partial) -> Void }`. Branching: a function `nextQuestion(after:given partial) -> SurveyQuestion?` implementing the §4.1 branch rules (Q3 only if products in play; Q4 only if materials != none). Hold answers in a `BusinessProfile.Partial` until complete, then finalize to `BusinessProfile`. **Copy is DRAFT — run final strings through `ops-copywriter` before cutover (Slice 3).**

- [ ] **Step 2: Build the view.** One question on screen at a time: `stageHeader` (eyebrow + prompt) + a vertical stack of option cards (mirror `mixCard` styling from `GuidedProductSetupFlow.swift:579` — `nestedCard()`, selected stroke `primaryText.opacity(0.28)`, light haptic on tap). Selecting an option applies it and advances (`withAnimation(OPSStyle.Animation.page)`), honoring `accessibilityReduceMotion`. Back returns to the previous answered question. Add a `#Preview`.

- [ ] **Step 3: Verify build + preview.**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED. Open the `#Preview` and confirm each question renders and branching advances correctly.

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift OPS/Views/Catalog/GuidedSetup/Survey/GuidedSetupSurveyView.swift
git commit -m "feat(catalog-setup): plain-language survey engine + UI"
```

---

## Task 5: Plan screen

**Files:** Create `OPS/Views/Catalog/GuidedSetup/GuidedSetupPlanView.swift`

- [ ] **Step 1: Build.** Header *"Here's your setup"*; render `model.modules` as numbered rows (mirror `flowStepRow` `:508`) with title/subtitle/est-time per `SetupModuleKind`, each marked optional. Primary CTA *"Start"* → `model.confirmPlan()`. Add `#Preview` for a services-only and a fencing-co profile.
- [ ] **Step 2: Verify build + preview** (`xcodebuild ... generic/platform=iOS build` → SUCCEEDED; both previews show correct, ordered module lists).
- [ ] **Step 3: Commit** (`feat(catalog-setup): setup plan screen`).

---

## Task 6: Product-line module (services + goods)

**Files:** Create `OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift`

- [ ] **Step 1: Define `ProductLineKind { case service, good }`** with `displayLabel`, `category: ProductCategory`, `iconName`, `sellLabel` ("Sell rate" / "Sell price"), and whether a unit cost field shows (always when `trackCost`).
- [ ] **Step 2: Build the form** (mirror `serviceStage`/`goodStage` `:634`/`:709`): a list of `ProductLineDraft` rows the user adds; per row — name (`CatalogTextFieldStyle`), **Sell** + **Your cost** side-by-side (cost only when `trackCost`), live **margin** readout (mirror `marginReadout` `:1583`), unit (`UnitPickerField`, `onCreateRequested → InlineCreateUnitSheet`), category (`CategoryPickerField → InlineCreateCategorySheet`). Reuse `CatalogFieldLabel`, `CatalogSectionHeader`, `nestedCard()`. Validation mirrors `serviceCanSave` `:1924` (name non-empty, sell parses, cost parses-or-empty, no duplicate name). SAVE calls `model.saveProductLine(...)`; disabled + reason line when invalid; `isSaving` spinner; offline → blocked with reason (mirror `disabledReason` `:1961`). Add a `#Preview` for each kind.
- [ ] **Step 3: Verify build + preview.**
- [ ] **Step 4: Commit** (`feat(catalog-setup): product-line module (services + goods)`).

---

## Task 7: Done screen + §14 notification

**Files:** Create `OPS/Views/Catalog/GuidedSetup/GuidedSetupDoneView.swift`

- [ ] **Step 1: Build.** Summary headline from `GuidedCatalogSetupModel.summaryLine(...)` (`"3 services · ready for estimates"`), a list of `model.savedLines`, and two actions: *"View catalog"* (dismiss + route to products segment) and *"Done"* (dismiss). Empty-run state (`savedLines.isEmpty`) shows a graceful `—`/"Nothing saved this run — add anytime from the catalog menu." On appear, fire `model.postCompletionNotification(...)` once (guard against re-fire). Add `#Preview`.
- [ ] **Step 2: Verify build + preview.**
- [ ] **Step 3: Commit** (`feat(catalog-setup): done summary + completion notification`).

---

## Task 8: Flow container

**Files:** Create `OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift`

- [ ] **Step 1: Build the shell** (mirror `GuidedStockSetupFlow.swift` closely): `@StateObject` model; `init(companyId:userId:)`; `ZStack { OPSStyle.Colors.backgroundGradient; content }`; top progress (phase-based: survey questions → plan → modules → done), offline banner, EXIT button (persists draft + dismiss), resume confirmation dialog on appear (`model.hasDraftToResume`), phase routing to `GuidedSetupSurveyView` / `GuidedSetupPlanView` / `ProductLineModuleView` / `GuidedSetupDoneView`, bottom `OPSFloatingButtonBar` where appropriate, `flowAnimation` honoring `accessibilityReduceMotion`, light/medium/success haptics, `.trackScreen("Catalog.GuidedSetup")`. Steel-blue `primaryAccent` only — no `wizardAccent`. Add `#Preview`.
- [ ] **Step 2: Verify build + preview** end-to-end: survey → plan → product-line module (save a service against a dev/sim company) → done. Confirm draft resume by backgrounding mid-flow.
- [ ] **Step 3: Commit** (`feat(catalog-setup): full-screen flow container`).

---

## Task 9: Bible stub

**Files:** Modify `ops-software-bible/07_SPECIALIZED_FEATURES.md`

- [ ] **Step 1:** Add a **"Guided Catalog Setup"** subsection: status (Slice 1 landed — survey + plan + product-line module + done; assembly/stock in later slices), the `BusinessProfile` → module mapping, that it is a self-contained flow (not the overlay Wizard System), and that it creates products via `ProductRepository` and (later) writes `company_inventory_settings.inventory_mode`.
- [ ] **Step 2: Commit** (`docs(bible): document guided catalog setup (slice 1)`).

---

## Self-Review

**Spec coverage (Slice 1 scope):** survey (T4) · BusinessProfile (T1) · plan screen (T5) · coordinator/model (T3) · persistence/resume (T2,T3) · module router (T3,T8) · done summary + §14 notification (T7,T3) · services **and goods** module (T6) · sell/cost + live margin (T6) · draft resume (T2,T3,T8) · self-contained/primaryAccent (T8) · bible stub (T9). Entry-point wiring + `GuidedProductSetupFlow` retirement correctly deferred to Slice 3 (rollout note). No Slice-1 gap.

**Placeholder scan:** Two integration points are "read then implement" (T2 draft-store primitives, T3 `ProductPricingUnit`/`pricingUnit(for:)` helpers) rather than invented — these reference exact existing files/lines, not hand-waves. All logic tasks carry full test + impl code.

**Type consistency:** `ProductLineKind` (T6) is used by `ProductLineDraft` (T2) and `saveProductLine` (T3) — define it in T2's file or a shared file referenced by both; ensure the same enum, not two. `GuidedCatalogPhase` is shared by snapshot (T2) and model (T3). `SetupModuleKind` order (assembly, services, goods, stock) is consistent across T1/T3/T5/T8.

**Open decisions referenced:** D1 (`inventory_mode` value) and D2 (labor modeling) are **not** touched by Slice 1 — both belong to Slices 2/3. D5 (copy via `ops-copywriter`) flagged in T4 and resolved at the Slice-3 cutover.
