# Guided Catalog Setup — Design

**Date:** 2026-06-09
**Status:** Draft for review (brainstorming output — not yet planned or built)
**Surface:** iOS app — Catalog tab
**Author context:** Redesign of the products/assembly setup experience, unified with stock setup under a single adaptive, survey-driven guide.

**Related specs**
- `2026-05-06-ios-catalog-variant-model-design.md` — the catalog/variant schema this builds on.
- `2026-05-10-products-taxonomy-redesign-design.md` — the service/good/bundle/fee taxonomy.
- `2026-06-05-catalog-inventory-quality-pass-design.md` — quality pass that tightened the **stock** guided setup (exit affordance, floating footer, capture prompt). This spec **complements** that work and **supersedes** the products guided setup (`GuidedProductSetupFlow`).

---

## 1. Problem & Context

The Catalog tab has two guided flows today:

- **Stock guided setup** — `OPS/Views/Catalog/Stock/GuidedStockSetup/GuidedStockSetupFlow.swift`. Clean architecture (container + `GuidedStockSetupModel` + 5 stage views), draft resume, batch commit, a real "done" stage. This is the quality bar.
- **Products guided setup** — `OPS/Views/Catalog/Products/GuidedProductSetupFlow.swift`. A single ~2,800-line struct with inline `@State`. It is competently styled (OPSStyle tokens, progress bar, haptics, validation, a §14 completion notification) but has real problems:
  - It is a **long, linear, parts-first wizard** (prime → mix → service → good → bundle → recipe → review). Users tap through "X skipped" pass-through screens for types they didn't choose.
  - The **recipe (BOM) step requires stock to already exist** and lives in its own stage. There is no way to create a material as you build the product. (`AddProductMaterialSheet` only *picks* existing variants.)
  - **Labor cost is never captured.** The service step asks for one ambiguous "Price" and hard-codes `unitCost: nil` (`GuidedProductSetupFlow.swift:2109`). The user cannot tell whether they are entering the customer-facing sell rate or their own cost.
  - It loses in-progress field state on quit (no draft persistence).

### The real insight

Trades businesses don't think in "services, goods, bundles, recipes." They sell **a fixed-price assembly** — e.g., Canpro's "Rail Install" at one price, which silently includes rail (by length), line/end/corner posts, top/bottom sleeves, fasteners, **and labor**, mapped to the rail-install task type. But not every business works that way: some sell **services only** (cleaning, consulting, repair labor), some sell **goods with no materials behind them**, some **don't track stock at all**.

So the setup must not be one fixed builder. It must be an **adaptive, multiple-choice diagnostic** that learns how the business works and then sets up **only what fits** — handling services-only, goods-only, no-assemblies, no-consumables, and full materials-plus-stock as different paths through the same guide. This is the on-brand "do the work for them / lifeline, not a tech demo" experience.

---

## 2. Goals / Non-Goals

### Goals
1. A single front door — **"Set up your catalog"** — that diagnoses the business via plain-language multiple-choice questions and routes into only the relevant setup modules.
2. Make **sell rate vs. your cost** explicit on every line (services/labor included), with live margin.
3. Let users **build an assembly and its recipe inline** — including creating materials on the fly, with no requirement that stock already exists.
4. Gracefully handle every business shape: services-only, goods-only, mix, no-assemblies, no-materials, cost-only vs. stock-tracked.
5. Reuse the polished **stock guided setup** as the stock module rather than duplicating it.
6. Clean architecture (coordinator + profile model + per-module views), draft resume, no dead screens, a real "done" payoff.

### Non-Goals (this initiative)
- **No database schema changes.** The schema already supports everything here (see §3). Confirmed against the bible and live Supabase.
- **No per-trade templates** (pre-built starter assemblies). Explicitly deferred; the architecture leaves room to add them as a survey front-door later.
- **No free-text / natural-language input.** Decision: multiple-choice only — free text is too much effort for a field user. Plain-English MCQ is the backbone.
- Not changing the stock guided setup's internals (the 2026-06-05 quality pass owns that). We only *call into* it.

---

## 3. Schema Grounding (no DB changes)

Verified against `ops-software-bible/03_DATA_ARCHITECTURE.md` §21 (Product) + §31 (Catalog) and live Supabase. Key facts the design relies on:

**Sell vs. cost (the two-level model):**
- `products.base_price` = customer-facing sell price; `products.unit_cost` = what the company pays. **Both exist on every `kind`, including `service`/labor.** There is no separate labor-rate field anywhere (confirmed — `task_types` carries no rate/cost columns).
- **Standalone products** (a service or good sold directly): track sell + cost → margin per line.
- **Assemblies** (fixed-price packages): carry one customer-facing sell price; their components contribute **cost**. Margin = sell − (Σ material cost + labor cost).

**Taxonomy** — iOS `ProductCategory` (`OPS/DataModels/Supabase/Product.swift`):

| Case | displayLabel | derivedKindRaw (`products.kind`) | derivedType (`products.type`) | defaultTaxable |
| --- | --- | --- | --- | --- |
| `.service` | SERVICE | `service` | `labor` | true |
| `.material` | GOOD | `material` | `material` | true |
| `.bundle` | BUNDLE | `package` | `other` | true |
| `.fee` | FEE | `service` | `other` | false |

**Assembly composition — two distinct mechanisms:**
- `product_bundle_items` — child **products** inside a package (`bundle_product_id`, `child_product_id`, `quantity`, `relationship_kind`, `display_order`). Pricing rolls up via `products.bundle_pricing_mode` (`auto` = sum children, `override` = fixed). iOS `BundlePricingMode { .auto, .override }`.
- `product_materials` — **recipe / BOM** rows pointing at stock (`product_id`, `catalog_variant_id` *xor* `catalog_item_id`, `quantity_per_unit`, `unit_id`, `notes`). Drives material cost, the crew's cut-list (`task_materials`), and — when enabled — inventory deduction. Constraint: exactly one of `catalog_variant_id` / `catalog_item_id` is set. **There is no cost-only material type** — every recipe row points at a real `catalog_variants` row (a cost-only material is just a variant with `unit_cost` and zero on-hand).

**Labor inside an assembly:** labor is **not** a `product_materials` row (that table is stock-only). It is a `kind=service` product. See §10 Decision D2 for how it attaches.

**Inventory toggle:** `company_inventory_settings.inventory_mode` (default `'off'`). The whole stock/deduction subsystem is gated on this. ⚠️ The exact "on" value (e.g. `'tracked'` vs `'on'`) **must be read from the live CHECK constraint before writing it** — sources disagreed; do not guess.

**Inline-creation primitives that already exist (no new backend needed):**
- `CatalogRepository.createDefaultItemForProduct(companyId:productName:categoryId:defaultPrice:defaultUnitCost:defaultUnitId:) -> CatalogItemDTO` — creates a family **+ default variant** in one call. This is the inline-material primitive.
- `CatalogRepository.createFamily / createVariant / createCategory / createUnit`.
- `ProductRichnessRepository.createMaterial(CreateProductMaterialDTO) -> ProductMaterialDTO`.
- `ProductRepository(companyId).create(CreateProductDTO)`, `ProductBundleItemRepository.create(CreateProductBundleItemDTO)`.
- `GuidedStockUnitResolver(companyId:modelContext:createUnit:).resolveUnitId(for: GuidedMeasurement)` — find-or-create a unit.
- `InlineCreateCategorySheet`, `InlineCreateUnitSheet` (write immediately, return the new id).

**What must be built (UI only):** an inline "add a material by name + cost" affordance inside the assembly module. The plumbing (repos above) exists; the orchestration + UI do not.

---

## 4. The Experience

### 4.0 Entry points
- Primary: a **"Set up your catalog"** action — the Catalog header ellipsis (replacing the separate PRODUCTS "Guided Setup" entry) and an empty-state CTA in `StockView` / `CatalogProductsListView` (the products list already exposes `onStartSetup`).
- The **stock guided setup remains directly reachable** (kebab → STOCK → Guided Setup) for users who explicitly want it; the unified guide *reuses* it as a module.
- Presented as a `.fullScreenCover` from `CatalogView`, like today's flows.

### 4.1 Phase 1 — Diagnose (the survey)

Plain-language multiple choice, branching, 2–5 questions. Produces a `BusinessProfile`. **Copy below is DRAFT — final copy goes through `ops-copywriter` before ship.**

1. **What do your customers pay you for?**
   `our time & expertise` · `products we supply & install` · `a mix of both`
   → sets whether services, goods, or both are in play.
2. **When you quote a job, how do you usually price it?**
   `one all-in price for the whole job` · `line by line` · `by the hour` · `it depends`
   → decides whether assemblies exist at all.
3. *(only if products are in play)* **On a typical job, do you go through materials or parts?**
   `lots of parts` · `a few key materials` · `no, I don't track materials`
   → decides whether materials/recipes are set up.
4. *(only if materials)* **Should OPS keep count of your stock — or just track what jobs cost you?**
   `count it & warn me to reorder` · `just costs & margins`
   → sets `inventory_mode` and whether the stock module runs.
5. **Track your costs & margins, or just set prices for now?**
   `track both` · `just prices`
   → decides whether "Your cost" + margin appear on every line.

### 4.2 Phase 2 — Plan

From the profile, render a short **"Here's your setup"** map: the ordered list of modules that apply, each labelled optional with a rough time. This sets expectations and builds momentum (fixes "endless wizard with dead screens"). This screen is where `company_inventory_settings.inventory_mode` is written based on Q4 — but only on a materials/stock path; the services-only path never touches it (Slice 3 owns that write, gated on `catalog.manage`).

### 4.3 Phase 3 — Build (only applicable modules)

- **Services module** — a list of service lines: name, sell rate, unit (hour/flat/visit), category, *your cost* (if `trackCost`) → live margin. Inline-create unit/category. Add as many as wanted, save each immediately.
- **Goods module** — same pattern for physical products sold directly on an estimate.
- **Assembly module** *(hero; when `usesAssemblies`)* — name + task-type link ("Rail Install" → rail install task type); set the **fixed all-in price** (default; `bundle_pricing_mode = override`) or roll up from parts (`auto`); then build **"what's in it"** in one inline list — add **labor** (hours + your cost) and **materials** (name + cost + qty, **created on the fly**, or picked from stock when tracked), with **margin updating live**. Save → "build another" or move on.
- **Stock module** *(only if `inventory_mode` tracked)* — routes into the existing `GuidedStockSetupFlow`. Materials created in the assembly step appear here to receive quantities + thresholds; nothing is created twice (see §10 D3).

### 4.4 Phase 4 — Done

A real payoff: *"Rail Install — $1,500 · 62% margin · 7 materials + labor · ready for estimates,"* a count of everything created, and one clear next action (View catalog / Build an estimate). Fires a §14 completion notification (`NotificationRepository.shared.createNotification`, `deepLinkType: catalog_products`/`catalog_stock`, `actionUrl: /catalog?...`).

### 4.5 Worked examples (the whole point)

- **Cleaning company:** Q1 `our time` → Q5 `track both`. Skips goods/materials/stock entirely. Sets up 3 service lines with sell + cost. Two survey taps, done in under two minutes.
- **Fencing company (Canpro):** Q1 `a mix` → Q2 `all-in price` → Q3 `lots of parts` → Q4 `count it` → Q5 `track both`. Runs the assembly builder (build "Rail Install" with labor + materials inline + live margin), then flows into stock counting for those materials. Neither business ever sees a step that doesn't apply.

---

## 5. Cross-Cutting Requirements

- **Sell + cost on every line** when `trackCost`, with live margin (`(sell − cost) / sell`). Resolves the labor-cost ambiguity everywhere.
- **Every module/step skippable**; "add more later from the Catalog menu."
- **Resume on quit** — mirror `GuidedStockSetupModel` (`OPS/Services/Catalog/GuidedStockSetupModel.swift`): `persist()` / `restoreIfAvailable()` / `clearDraft()` / `hasDraftToResume`, backed by a Codable draft snapshot keyed through `CatalogSetupDraftContext` with a dedicated `scope` (e.g. `"catalog-guided"`). Persist after every phase/step transition. The products flow's lack of this is the known defect we are not repeating. **No `WizardState` / overlay-wizard coupling** — see the Architecture note in §6.
- **No dead screens** — only applicable modules render; nothing to "tap through."
- **Motion** — single OPS easing (`OPSStyle.Animation.page`); honor `accessibilityReduceMotion` (linear fallback), as both existing flows do.
- **Haptics** — light on transitions, medium on commits, success on completion. No spam.
- **Field-first** — 44pt+ targets, high contrast, offline-safe (offline banner + saves blocked with clear reason, matching existing flows), legible numbers in JetBrains Mono (`OPSStyle.Typography.dataValue`, tabular).
- **Tokens** — every value via `OPSStyle`; reuse `OPSFloatingButtonBar`, `nestedCard()`, `ops*ButtonStyle()`, the existing `mixCard` / `taskTypeLinkCard` / recipe-row patterns salvaged from `GuidedProductSetupFlow`.
- **Copy** — terse, tactical OPS voice; final pass via `ops-copywriter`.
- **Notification** — §14 completion notification on finish.

---

## 6. Architecture & File Plan

**Architecture note (important).** This is a **self-contained full-screen flow** in the mold of `GuidedStockSetupFlow` — bespoke UI presented via `.fullScreenCover`. It is **not** part of the OPS overlay **Wizard System** (`OPS/Wizard/`: `WizardStateManager`, `.wizardTarget()` glow, instruction bar, `WizardTriggerService`). Consequently it uses the normal steel-blue `OPSStyle.Colors.primaryAccent` — **never** the wizard-only orange `wizardAccent` — applies no `.wizardTarget()` modifiers, and registers no `Wizard/Definitions/` entry. The transferable wizard-audit lessons (per-module permission gating, prerequisites, offline safety, lifecycle/resume, double-submit guards) still apply and are folded into §5 and the implementation plan.

**State model** — `GuidedCatalogSetupModel: ObservableObject` owns: `BusinessProfile`, derived `SetupPlan`, current phase/module, per-module drafts, persistence (`persist`/`restore`), and commit orchestration (reusing the repos in §3). Mirrors the `GuidedStockSetupModel` pattern.

**New files** (under `OPS/Views/Catalog/GuidedSetup/`):
- `GuidedCatalogSetupFlow.swift` — container shell: progress, phase routing, offline banner, exit + resume dialog, bottom-bar orchestration.
- `GuidedCatalogSetupModel.swift` — the ObservableObject above.
- `Survey/GuidedSetupSurveyView.swift` + `Survey/SurveyQuestion.swift` — the MCQ engine (question list, options, branching).
- `GuidedSetupPlanView.swift` — the plan screen.
- `Modules/ServicesModuleView.swift`, `Modules/GoodsModuleView.swift`, `Modules/AssemblyModuleView.swift` (+ inline material/labor builder).
- `GuidedSetupDoneView.swift`.
- `Models/BusinessProfile.swift`, `Models/SetupPlan.swift`.

**Reused as-is:** `GuidedStockSetupFlow` (stock module), all repositories, `GuidedStockUnitResolver`, `OPSStyle` + components, `InlineCreate*Sheet`, `NotificationRepository`, `WizardState`.

**Modified:** `CatalogView.swift` — entry points (unified guide replaces the products guided-setup presentation; add empty-state CTAs; keep stock guided as both a module and a direct entry).

**Superseded / retired:** `GuidedProductSetupFlow.swift` — replaced by the survey + product/assembly modules. Salvage reusable view code (mix cards, task-type link card, bundle child picker, recipe rows, save/validation logic) into the new modules, then remove it once slices 2–3 cover its functionality.

---

## 7. Flow State Model (sketch)

```
struct BusinessProfile {
    enum Sells { case services, goods, mix }           // Q1
    enum Pricing { case fixedJob, lineItem, hourly, mixed } // Q2
    enum MaterialUse { case heavy, some, none }         // Q3
    enum InventoryChoice { case tracked, costOnly }     // Q4 (only if materials != none)
    var sells: Sells
    var pricing: Pricing
    var materialUse: MaterialUse
    var inventory: InventoryChoice?
    var trackCost: Bool                                 // Q5
}

// Derived module selection (pricing only gates assemblies; selling a thing
// always offers its module, so no answer combo yields a zero-module plan):
runServices   = (sells != .goods) || pricing == .hourly
runGoods      = sells != .services
runAssemblies = pricing == .fixedJob || pricing == .mixed
runMaterials  = materialUse != .none
runStock      = runMaterials && inventory == .tracked
inventoryMode = (inventory == .tracked) ? <ON_VALUE: read from schema, see D1> : "off"
```

`SetupPlan` = ordered `[SetupModule {id, title, subtitle, estMinutes, isOptional}]`. Default order: Services → Goods → Assemblies → Stock. Plan-driven; only included modules appear, every module is skippable, and the plan leads with the most relevant module for the profile (assemblies first for fixed-job businesses). Safety floor: if a profile somehow selects no module, fall back to offering Services + Goods.

---

## 8. Slicing Plan

**Slice 1 — Foundation (ship first).** Survey engine + `BusinessProfile` + plan screen + coordinator/model + persistence/resume + module router + done summary + the **Services module** + entry-point wiring + empty states + §14 notification + bible stub. Proves the adaptive spine end-to-end for the simplest business (services-only) and the "skip everything" minimal path. Fully shippable alone. **No dependency on the labor-modeling decision.**

**Slice 2 — Assembly module.** Fixed/rolled pricing + inline labor + inline material creation (`createDefaultItemForProduct` + unit resolver) + live margin + task-type link. Finalize Decision D2 before building. Salvage from `GuidedProductSetupFlow`.

**Slice 3 — Goods + Stock integration.** Goods module; clean hand-off into `GuidedStockSetupFlow`; reconcile cost-only vs. tracked materials (no double-creation, D3); retire `GuidedProductSetupFlow`.

Templates deferred indefinitely (would be in-app content, no schema change) — architecture leaves a survey front-door seam.

---

## 9. Testing & Verification

- **Unit tests** (high value, pure logic): `BusinessProfile` → `SetupPlan` derivation for every answer combination; module inclusion; `inventory_mode` mapping; margin math.
- **Build:** `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` (per ops-ios CLAUDE.md). Tests via simulator destination.
- **Manual / path verification:** the two worked examples (cleaner, fencing co); offline behavior; resume after force-quit; reduced-motion; VoiceOver labels on all controls.

---

## 10. Open Decisions

- **D1 — `inventory_mode` "on" value.** Read the live CHECK constraint before writing (`'tracked'` vs `'on'`). Blocks the plan screen's write. *(Resolve before Slice 1 ships.)*
- **D2 — Labor persistence in an assembly.** Recommended: labor = a `kind=service` child product attached via `product_bundle_items` (quantity = hours), carrying its own `base_price` (optional) + `unit_cost` — reusable, itemizable, uses the schema's intended bundle mechanism; margin roll-up sums material costs (`product_materials`) + child costs (`product_bundle_items`). Fallback: fold labor cost into the assembly's own `unit_cost` (simpler, but no breakdown, not reusable). *(Resolve before Slice 2.)*
- **D3 — Cost-only vs. tracked material reconciliation.** When `inventory_mode = tracked`, materials created inline in the assembly module must be the same `catalog_variants` the stock module then counts — define create-or-reference so nothing is duplicated. *(Resolve before Slice 3.)*
- **D4 — First-run trigger.** Recommended: surface via empty-state CTA + kebab, not a forced onboarding gate.
- **D5 — Copy.** All user-facing strings (survey, modules, done) go through `ops-copywriter` before ship.

---

## 11. Bible Update Plan

No schema change, but add a **"Guided Catalog Setup"** subsection (likely `07_SPECIALIZED_FEATURES.md`) documenting: the diagnostic questions, the `BusinessProfile` → configuration mapping, that it writes `company_inventory_settings.inventory_mode` and creates products/materials/stock via existing repositories, and that it reuses `GuidedStockSetupFlow`. Update per slice as it lands (CLAUDE.md: keep the bible current in the same session).
