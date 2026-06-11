I have traced the entire flow end-to-end as the operator, verified the data model and the seeding path, and hit the boundary of the reused stock module. The decisive evidence is all in. Here is the audit.

---

# Guided Catalog Setup — Cold-Start Audit
**Operator:** owner, *Evergreen Grounds* (landscape install + recurring maintenance) · **Branch:** `feat/guided-catalog-setup` (worktree, uncommitted WIP) · **Mode:** read-only, nothing changed.

> Verification note: the Supabase MCP query tools weren't available in this session, so the exact default-unit seed set (`initialize_company_defaults`) is inferred from migrations + onboarding code, not a live query. Every conclusion below holds regardless of that seed's contents; I flag the one spot where it matters.

---

## 1. Who I am & the catalog I'm trying to build

I run a 4-truck landscaping outfit. I install and I maintain. My catalog isn't "products" — it's **dirt, plants, crews, and routes**:

| What I sell | How I price it | Unit |
|---|---|---|
| Mulch (supply + install) | by volume | **cubic yard** |
| Topsoil / gravel | by weight | **ton** |
| Sod | by area | **square foot** |
| Plants | each, by size | 1-gal / 5-gal / B&B (each) |
| Pavers / hardscape | area + each | **sq ft**, each |
| Install labor | crew rate **or** per area | **$65/hr** OR **$/sq ft** |
| Mowing / maintenance | **recurring, per visit**, tiered by lot size | **per visit** (small/med/large) or per **1,000 sq ft** |
| Seasonal cleanup | flat per job | flat |
| Install packages | one customer price, materials + labor bundled | flat (backend per-sq-ft) |
| Stock | bulk piles + plant inventory + pallets | **yards, tons**, each |

So I need: **volume + weight + area units**, **per-area + per-visit + hourly** pricing, **recurring** maintenance, **tiered** mowing, **bulk decimal stock**, and an **install package** that's material + labor at one price. Let's see how far I get.

---

## 2. Step-by-step trace

### Entry — Catalog → kebab → "Set up your catalog"
Found it. Kebab → SETUP → **"Set up your catalog"** (checklist icon) opens the full-screen flow ([CatalogView.swift:231](OPS/Views/Catalog/CatalogView.swift:231), [:126](OPS/Views/Catalog/CatalogView.swift:126)). Flow gates on `catalog.products.manage` ([GuidedCatalogSetupFlow.swift:61](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift:61)) — fine, I'm the owner. Clean progress bar + BACK/EXIT, exit persists my draft ([:331](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift:331)). Good first impression.

### Phase 1 — Survey (5 taps)
- **Q1 "What do customers pay you for?"** → **Both** ([SurveyQuestion.swift:63](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift:63)). Good — I'm not forced to pick a lane.
- **Q2 "How do you price a job?"** → **Depends on the job** ([:74](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift:74)). Sublabel reads *"Some fixed, some hourly"* — but most of my pricing is **per-visit and per-area**, which it doesn't mention. Mildly off.
- **Q3 "Do your jobs burn through materials?"** → **Yes, lots of parts** ([:79](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift:79)). Sublabel *"Fasteners, lumber, fittings, the works"* — that's a framing/fencing shop, not mulch and sod. Made me hesitate that this app is "for me."
- **Q4 "Want OPS to count your stock?"** → **Count it** ([:88](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift:88)).
- **Q5 "Track your costs and margins?"** → **Track both** ([:95](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift:95)).

Routing is correct: `.mix` + `.mixed` + `.heavy` + `.tracked` + trackCost → **all four modules `[assembly, services, goods, stock]`**, assembly first ([BusinessProfile.swift:71-81](OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift:71)). **The survey never once asks about recurring/repeat work** — the thing that defines half my revenue ([SurveyQuestion.swift:55-101](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift:55)).

### Phase 2 — Plan
Clean. "HERE'S THE PLAN": JOB PACKAGES ~5m, YOUR SERVICES ~2m, YOUR GOODS ~2m, YOUR STOCK ~3m ([GuidedSetupPlanView.swift:82-86](OPS/Views/Catalog/GuidedSetup/GuidedSetupPlanView.swift:82)). ~12 minutes. Fair. Momentum is good here.

### Phase 3a — Assembly module (first, the hero) → "Mulch Bed Install"
Name, optional task-type link, **all-in price**, "WHAT'S IN IT" (materials + labor), live cost/margin ([AssemblyModuleView.swift](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift)). The shape is genuinely good. Then I try to add my mulch:
- Tap **ADD MATERIAL**. Because I'm brand-new with zero stock, the sheet forces me into **"Create new"** mode ([AddAssemblyMaterialSheet.swift:162](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift:162)). Create-new shows **Name + Your cost + Qty per job — and no unit field at all** ([:271-280](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift:271)). So I enter "Mulch / $45 / 3" and there is **no way to say 3 *cubic yards***. The `unitId`/`showingUnitCreate` plumbing exists but is **wired to nothing** — `showingUnitCreate = true` is never called ([:38](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift:38), [:157](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift:157)). My mulch lands in the catalog **unitless**.
- Tap **ADD LABOR**. It's **per-hour only**: "Sell / hr", "Your cost / hr", "Hours per job" ([AddAssemblyLaborSheet.swift:61-90](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyLaborSheet.swift:61)). My paver-install labor is **$/sq ft**. I can't say that. I either fake an hourly number or bury it in the flat price. The model hard-codes labor to `ProductPricingUnit.hour` ([GuidedCatalogSetupModel.swift:264](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:264)).
- The package price is a **single flat number** ([AssemblyModuleView.swift:163](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift:163)). For "$12/sq ft × 400 sq ft" I have to pre-compute $4,800 on my phone calculator and type the total.

Margin math and inline material→stock reconciliation are solid ([GuidedCatalogSetupModel.swift:227-298](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:227)) — but I've already had to fake two of the three numbers that matter.

### Phase 3b — Services → mowing, install labor, cleanup
Form: Name, Sell rate, Your cost (optional), **Unit**, Category, save each ([ProductLineModuleView.swift:141-195](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:141)). The unit picker groups by dimension (Count/Length/Area/Volume/**Weight**/Time) and offers **Flat rate** ([UnitPickerField.swift:33-90](OPS/Views/Catalog/Products/Shared/UnitPickerField.swift:33)). Good bones. But:
- **My units don't exist.** A cold-start company has no `catalog_units` for sod-sqft, cubic-yard, ton, visit, or per-1,000-sq-ft. To enter *one* mowing line I must stop, tap Unit → "New unit…", type "visit", **pick a dimension** (defaults to **Count** — so "visit" becomes "each"), SAVE (a **network round-trip**), come back ([InlineCreateUnitSheet.swift:196-333](OPS/Views/Catalog/Manage/CatalogManageHelpers.swift:196)). Repeat for every unit I own. That's the slow part.
- **Mowing is tiered by lot size** — small/med/large. There's one `sellText`. So I create **three separate services** ("Mowing — small/med/large"); the per-run duplicate guard ([GuidedCatalogSetupModel.swift:121](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:121)) is fine with distinct names but there's no tier UI (the `tieredPricingJSON` column exists but the guided flow never populates it).
- **Mowing is recurring (weekly/biweekly).** Nowhere — at all — can I say that. `ProductLineDraft` is name/sell/cost/unit/category; no recurrence ([GuidedCatalogSetupDraft.swift:37-61](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift:37)). Confirmed: no recurrence/frequency/interval field anywhere in the product or catalog data model. The best I can do is "Mowing — small / $40 / per visit" and remember the cadence in my head.
- Typo a price? Once I tap ADD it's in the catalog and the in-flow list is **read-only** — no edit, no remove ([ProductLineModuleView.swift:217-251](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:217)). I'd have to fix it later in the catalog proper.

### Phase 3c — Goods → mulch, topsoil, sod, plants, pavers
Same form. I *can* create a "cubic yard" unit with dimension **Volume** and a "ton" with **Mass**, and they'll group correctly in the picker. **But** `pricingUnit(for:)` maps both volume and mass to **`.flatRate`** ([CatalogManageHelpers.swift:354-363](OPS/Views/Catalog/Manage/CatalogManageHelpers.swift:354)) — only area→sqft and length→linearFoot survive as real pricing units. So "Mulch — $45 / cu yd" stores the cubic-yard label but the app's canonical pricing semantics treat it as flat-rate; my volume/weight pricing is second-class on every estimate line downstream.

### Phase 3d — Stock → my bulk piles
The plan promised "YOUR STOCK — count what's on hand." Tapping in, the catalog flow **dismisses itself entirely** and posts `OpenGuidedStockSetup` to launch the separate stock flow ([GuidedCatalogSetupFlow.swift:103-107](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift:103), [:318](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift:318)). Two problems land at once:
1. That reused stock flow only understands **piece / length / area** measurements — `.piece→ea`, `.length→ft`, `.area→sq ft`. **There is no volume or mass** ([GuidedStockUnitResolver.swift:29-35](OPS/Services/Catalog/GuidedStockUnitResolver.swift:29)). My mulch piles (yards) and gravel (tons) — **my entire bulk inventory** — cannot be counted in their real units.
2. Because the flow dismissed, I **never reach the catalog "done" payoff** and the **§14 completion notification never fires** (it's posted in `GuidedSetupDoneView.onAppear` ([GuidedSetupDoneView.swift:34](OPS/Views/Catalog/GuidedSetup/GuidedSetupDoneView.swift:34)) / [GuidedCatalogSetupModel.swift:396](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:396)). The only way to *see* "done" is to hit **FINISH** in the bottom bar — which **skips stock entirely** ([GuidedCatalogSetupFlow.swift:226-230](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift:226)). So: do my stock and lose the finish line, or get the finish line and skip my stock. There's no path that does both.

### Phase 4 — Done (if I FINISH instead of stock)
Clean summary: "1 package · 4 services · 5 goods", per-item list with margin, completion notification, VIEW CATALOG / DONE ([GuidedSetupDoneView.swift](OPS/Views/Catalog/GuidedSetup/GuidedSetupDoneView.swift)). Honest payoff, slightly lighter than the spec's "$1,500 · 62% margin · 7 materials" vision, but fine.

---

## 3. P0 — Blockers (can't represent my business without faking data)

**P0-1 · I cannot count my bulk stock in its real units.** The reused stock module supports only piece/length/area; **no volume (cubic yard), no mass (ton)** ([GuidedStockUnitResolver.swift:29-35](OPS/Services/Catalog/GuidedStockUnitResolver.swift:29)). Bulk piles are the heart of a landscaper's inventory. → *Fix: add `.volume`/`.mass` measurement types to the stock flow (cu yd, ton), or let the stock step reuse units already created in the catalog modules.*

**P0-2 · Inline-created assembly materials have no unit.** "Create new" material in a package captures only name + cost + qty — the unit control was never wired in, and cold-start operators are forced into create-new because they have no stock yet ([AddAssemblyMaterialSheet.swift:162](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift:162), [:271-280](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift:271)). Every material in my first packages is born unitless ("3 of Mulch"). This reads as an unfinished feature in the current WIP (the `showingUnitCreate`/`unitId` state is dead). → *Fix: surface `UnitPickerField` + "New unit…" in create-new mode (the same control the service/goods module already uses); default qty unit sensibly.*

**P0-3 · Recurring maintenance can't be expressed.** No recurrence anywhere — not in the survey, not in `ProductLineDraft`, not in the product model. Weekly/biweekly mowing — a whole revenue line — collapses to a static "per visit" price with the cadence living in my head. → *Fix: either add a recurrence attribute to service lines, or explicitly acknowledge recurring lives in scheduling/contracts and hand off there so I'm not left thinking the catalog captured it.*

> I call these P0 not because the wizard traps me — it's skippable end to end — but because for *this* business they force fake or lost data on my core operations, which the OPS perfection bar treats as failure.

## 4. P1 / P2 — Gaps & wishes

**P1 · Assembly labor is hour-only.** Can't price sod/paver install labor per sq ft ([AddAssemblyLaborSheet.swift:61-90](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyLaborSheet.swift:61), [GuidedCatalogSetupModel.swift:264](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:264)). → *Give labor lines a unit picker (hour / day / sq ft) like product lines have.*

**P1 · Tiered pricing isn't surfaced.** Lot-size mowing = 3 hand-built services; `tieredPricingJSON` exists in schema but no module exposes it. → *Add price tiers/variants on one service line, or at minimum a "duplicate line" button to make 3 tiers fast.*

**P1 · Stock handoff breaks the flow.** Choosing stock ejects me to a separate flow, skips the done payoff, and suppresses the completion notification; FINISH skips stock. → *Inline the stock module, or on return re-enter the catalog "done" and fire the notification regardless of path.*

**P1 · Volume/mass lose pricing semantics.** Cubic-yard and ton flatten to `flatRate` in `pricingUnit(for:)` ([CatalogManageHelpers.swift:362](OPS/Views/Catalog/Manage/CatalogManageHelpers.swift:362)). → *Add volume/mass cases (or carry the unit label through to estimate-line formatting).*

**P2 · Offline lies.** The container banner says *"You can keep moving. Saving starts when the connection is back"* ([GuidedCatalogSetupFlow.swift:194](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift:194)), but every ADD/SAVE is hard-disabled offline and even inline unit creation is a live network call that fails ([ProductLineModuleView.swift:68](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:68), [InlineCreateUnitSheet.save](OPS/Views/Catalog/Manage/CatalogManageHelpers.swift:300)). A field-first product that no-ops in the field. → *Either queue saves locally (match the banner) or change the banner to tell the truth.*

**P2 · No per-area package pricing.** Flat total only; I pre-compute $/sq ft × area by hand. → *Optional qty × rate on the package.*

**P2 · No in-flow edit/remove of saved lines.** A fat-fingered price is stuck until I leave and edit it in the catalog ([ProductLineModuleView.swift:217](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:217), [AssemblyModuleView.swift:331](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift:331)). → *Tap-to-edit / swipe-to-remove on the added list.*

## 5. P3 — Copy / UX nits
- Q2 sublabel "Some fixed, some hourly" and Q3 "Fasteners, lumber, fittings" are framing/fencing-flavored — add per-visit/per-area and landscaping nouns (mulch, soil, sod, plants) so I feel seen.
- Inline unit dimension **defaults to "Count"** — easy to file "cubic yard" under Count by accident. → *No default, or infer from the typed display ("yard"→volume, "ton"→mass).*
- Label drift: the picker calls dimension `mass` **"Weight"** ([UnitPickerField.swift:86](OPS/Views/Catalog/Products/Shared/UnitPickerField.swift:86)) but the create sheet calls it **"Mass"** ([CatalogManageHelpers.swift:211](OPS/Views/Catalog/Manage/CatalogManageHelpers.swift:211)). Pick one (a landscaper says "weight").
- Assembly-first ordering throws me into the most complex module before the easy wins (services/goods). Consider leading mixed/per-area businesses with services.
- A dangling `catalog-guided` draft persists after the stock handoff, so next open prompts "resume?" for a setup I effectively finished.

---

## 6. Verdict

**Could I onboard today? Partially — and not honestly.** The adaptive spine is genuinely strong: the survey routed me into all four modules without forcing a lane, the plan built momentum, the assembly builder's shape and live margin are exactly right, and draft-resume works. For a cleaner or a fencing shop this would feel like a lifeline.

But I sell **dirt by the yard and the ton, mowing by the week, and labor by the foot** — and this flow makes me **fake or drop all three**: I can't count bulk stock in yards/tons at all (P0-1), my package materials are born unitless (P0-2), and recurring maintenance simply doesn't exist (P0-3). I'd walk away thinking "this is built for someone who installs fences, not someone who maintains landscapes."

**The single most important fix: units must be first-class across the whole flow — volume and mass included — seeded or trivially creatable, and never silently dropped.** P0-1 and P0-2 are both unit failures, P1's pricing-semantics gap is a unit failure, and the per-area/per-visit friction all trace back to "the unit I need isn't there." Fix units end-to-end (seed sensible defaults, wire the missing material-unit picker, carry volume/mass through pricing, and teach the stock step volume/mass) and Evergreen goes from *faking it* to *finally found the thing.* Recurring maintenance (P0-3) is the close second — but it's arguably a different system (scheduling/contracts), so the honest move there is to route me out, not pretend the catalog holds it.
