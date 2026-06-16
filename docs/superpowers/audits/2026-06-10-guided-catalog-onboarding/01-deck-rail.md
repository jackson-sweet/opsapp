I have everything I need — I've traced the full path and confirmed every probe against the actual code. One last confirmation captured: the stock handoff listener gates on `catalog.manage` (CatalogView.swift:145) while the flow itself gates on `catalog.products.manage` (Flow:39, 61) — a permission mismatch — and finishing the flow never calls `clearDraft()` (only START OVER and survey-exit do). Now the report.

---

# Guided Catalog Setup — Cold-Start Audit
### Operator: **Canpro Deck & Rail** · railing + vinyl installer · 15 yrs in the field, allergic to software

> Audited by reading the iOS source in `ops-ios/.worktrees/guided-catalog-setup` (branch `feat/guided-catalog-setup`, working-tree state incl. uncommitted WIP). Read-only — nothing changed.

---

## 1. Who I am and what I'm trying to build

I install **railings and vinyl decking**. I sell **three packages**, each at one fixed price the customer sees — but I price the *backend* per unit and I track cost on everything:

| What I sell | Customer sees | My backend rate | Labor | Materials |
|---|---|---|---|---|
| Picket railing install | one total | **$70 / linear ft** (mat + install) | piecework **$/ft** | ~10 stocked pieces, **black & white** |
| Glass railing install | one total | **$90 / linear ft** | piecework **$/ft** | **same ~10 pieces**, black & white |
| Vinyl deck install | one total | **$11 / sq ft** | piecework **$/sq ft** | membrane **ordered per job** (12 colors × 2 thick = **24 variants**), + glue/flashing stocked, + offcut stock tracked |

The two railing systems **share the exact same pieces** (posts, top/bottom rail, brackets, connectors…). Every piece comes in **black and white**. I stock pieces and track cost on each. Vinyl membrane I **don't** stock — I order it per job — but I **do** keep and track the leftover offcuts. Labor is **piecework per foot**, and I track labor cost.

So what I need the catalog to hold: **per-unit-priced packages**, **shared multi-color piece library**, **piecework labor**, and a **stock vs. order-per-job** distinction. Let's see how far I get.

---

## 2. Step-by-step trace

### Entry → Survey
Catalog tab → `…` → **SETUP → "Set up your catalog"** (`CatalogView.swift:230`) opens the flow full-screen (`CatalogView.swift:126`). Gated on `catalog.products.manage` (`GuidedCatalogSetupFlow.swift:39,61`). I'm the owner, so I'm in. *(Note for later: the kebab also lists "Stock Setup" right below it — that's a different mapping sheet, not the stock counter. Mild clutter.)*

Five plain-language taps (`SurveyQuestion.swift:55-128`). My honest answers:

| Q | I tap | Why |
|---|---|---|
| What do customers pay you for? | **Both** (`.mix`) | time + the goods to do the job |
| How do you price a job? | **One price for the whole job** (`.fixedJob`) | customer sees one total |
| Do your jobs burn through materials? | **Yes, lots of parts** (`.heavy`) | ~10 pieces a system |
| Want OPS to count your stock? | **Count it** (`.tracked`) | I stock pieces |
| Track your costs and margins? | **Track both** (`true`) | I track cost on everything |

This is the **best part of the whole flow** — fast, no jargon, reads like a foreman talking. No complaints.

**Friction #1 — the plan it builds me.** `BusinessProfile.setupModules` (`BusinessProfile.swift:71-81`) gives me **all four**: `[assembly, services, goods, stock]` → plan shows JOB PACKAGES ~5m, **YOUR SERVICES ~2m**, **YOUR GOODS ~2m**, YOUR STOCK ~3m (`GuidedSetupPlanView.swift:82-86`). I don't sell standalone services or standalone goods — I sell **three packages**. Two of my four "modules" are dead weight I have to tap past. The survey told it I price one-fixed-total and sell a mix, but it still routes me through line-item modules I'll never use.

**Friction #2 — the progress bar runs backward.** During all 5 survey questions the bar is pinned (`progressFraction` returns step 1 the whole survey, `GuidedCatalogSetupFlow.swift:124-134`) because `modules` is empty until the survey finalizes. Survey = 1/3 ≈ 33%. Then I hit the plan and the denominator becomes 3+4=7 → 2/7 ≈ 29%. **The bar visibly jumps backward** the moment I commit. Small thing, but it reads as "wait, did I just lose progress?"

### Module 01 — JOB PACKAGES (the hero, and where I get hurt)

This is the only module that matters to me. I tap START and land in `AssemblyModuleView.swift`.

**Name + task type:** "Picket railing install," link a task type (`AssemblyModuleView.swift:113-153`). The task-type picker is clean — search + "NEW TASK TYPE" inline (`TaskTypePickerSheet.swift:131`). No issue.

**ALL-IN PRICE — first wall.** The price card is a **single flat field, "What the customer pays"** (`AssemblyModuleView.swift:155-179`; `AssemblyDraft.priceText` is one flat string, `AssemblyDraft.swift:44`). There is **no unit, no per-foot rate**. My picket package is **$70/linear foot** — there is nowhere to type that. My choices:
- Type a total for *one imaginary job* (say 50 ft → $3,500). Then every real estimate that isn't 50 ft is wrong.
- Mentally redefine the package as "1 linear foot" and type $70 — but there's no unit label anywhere to make that legible, and at commit it's saved as **flat-rate** (`GuidedCatalogSetupModel.swift:210`, `pricingUnit: .flatRate`, `unitId: nil`), so on an estimate it lands as a fixed $70 line with no footage scaling.

The gut-punch: **the platform already supports this.** `ProductPricingUnit` has `.linearFoot` and `.sqft` (`Product.swift:16-17`) and `pricingUnit(for:)` maps length→linearFoot, area→sqft (`CatalogManageHelpers.swift:354-356`). The services/goods module even uses it (`GuidedCatalogSetupModel.swift:153`). The assembly builder just **throws it away and hard-codes flat-rate.** This is my #1 blocker.

**WHAT'S IN IT — building a 10-piece package.** I tap **ADD MATERIAL** (`AssemblyModuleView.swift:208`), which opens a sheet (`AddAssemblyMaterialSheet.swift`). On the first package, no stock exists yet (stock module runs *after* this), so the sheet defaults to **Create new** (`AddAssemblyMaterialSheet.swift:162`). Create-new captures **name + your cost only** (`:271-280`) — **no unit picker is even rendered** (the `unitId`/`showingUnitCreate` state exists but nothing shows the field; my "Top rail" gets no "ft"), and **no color**. I type the piece, my cost, qty-per-job, ADD, sheet dismisses. Then I do it **again. And again.** Ten sheets, open-fill-add-dismiss, for one package. There's **no multi-add, no piece library, no duplicate rows** — `contentsCard` just lists what I've added. Building two railing systems = up to 20 of these cycles.

**Shared pieces across picket + glass — half a win.** When I build the glass package second, the sheet now defaults to **Pick existing** (`:162`), I pick the family → variant (`:206-267`), and commit **references** the same `catalogVariantId` instead of duplicating (`GuidedCatalogSetupModel.swift:230-231`). That part genuinely works — no duplicate stock. **But:** the create-new path has **no dedup whatsoever** (only assembly *names* are deduped, `:183`); if I forget to switch to "Pick existing" and re-type "Top rail," I get a **second "Top rail" family + variant** (`:235-244`). And I still have to hand-find each of 10 pieces in a flat menu for the second package. Sharing is *possible* but it's on me to not screw it up, ten times.

**Black & white — can't do it.** Create-new makes exactly **one variant, no SKU, no options** (`GuidedCatalogSetupModel.swift:240-243`). There is no way to say "this piece comes in black and white." The platform has the whole machinery — `CatalogOption`, `CatalogOptionValue`, `CatalogVariantOptionValue` are real models — but the guide never touches them. Pick-existing *does* reach variant level, but the variant menu labels by **SKU only** (`AddAssemblyMaterialSheet.swift:81-85`); a black and a white "Top rail" with no SKU show as two identical "Top rail" rows. So to get color I'd have to **leave this flow, build each family with a Color option + two values + SKUs in the full catalog editor, then come back and pick.** That's not setup-by-a-guide; that's homework.

**Labor — wrong model.** ADD LABOR opens a per-hour sheet: **"Sell / hr," "Your cost / hr," "Hours per job"** (`AddAssemblyLaborSheet.swift:61,67,87`), committed as `pricingUnit: .hour` with bundle quantity = hours (`GuidedCatalogSetupModel.swift:264,275`). My labor is **$/linear foot piecework.** To enter it honestly I can't. I'd have to lie to the form — put my per-foot cost in "cost/hr" and my footage in "Hours per job" — and now every label in my catalog says "hours" when I mean feet. (Also: why am I entering a labor *sell* rate at all when the customer sees one fixed package price? In an override-priced package it doesn't roll up — it's a confusing extra field.)

**Margin readout — this part's good.** `marginCard` shows YOUR COST (Σ materials + labor) vs MARGIN live (`AssemblyModuleView.swift:268-293`). Sell-vs-cost separation at the package level is exactly right. Credit where due.

**Vinyl package — I basically can't.** 24 membrane variants (12 colors × 2 thicknesses): no matrix generation, I'd hand-type 24 create-new rows or pre-build them elsewhere. And the membrane is **ordered per job, not stocked**, while my **offcuts are stocked** — the flow has **no per-material "I stock this / I buy this per job" distinction** at all. Q3/Q4 are company-wide, one-time answers; every material I create inline becomes a stock-backed catalog variant regardless. The membrane-vs-offcut reality is invisible to this guide.

### Modules 02–03 — SERVICES / GOODS
I don't need these. I tap **NEXT** twice (`GuidedCatalogSetupFlow.swift:224-231`) past two modules. (If I *did* use them, they're actually the most complete part: name, sell, your cost, live margin, **unit picker grouped by Length/Area/Count** with inline "New unit…", category — `ProductLineModuleView.swift:141-195`, `UnitPickerField.swift:67,82-90`. The irony: the unit support I desperately need on packages lives here, in the modules I skip.)

### Module 04 — STOCK — the fork and the disappearing payoff
The stock "module" isn't a module — it's a **handoff screen** (`GuidedCatalogSetupFlow.swift:103-106`). Now I'm staring at **two buttons that do opposite things**:
- The screen's **"SET UP STOCK"** → `routeToStock()` **dismisses the entire flow** and posts `OpenGuidedStockSetup` (`:318-324`).
- The container's bottom bar shows **"FINISH"** (last module, `:227`) → goes to the Done screen.

Whichever I pick, I lose something:
- **SET UP STOCK:** the whole guide closes. I **never see the Done payoff** ("here's everything you built, ready for estimates"), and the **§14 completion notification never fires** — it only fires from `GuidedSetupDoneView.onAppear` (`GuidedSetupDoneView.swift:34`), which I just skipped. The most-invested user (me) gets the most abrupt exit.
- **FINISH:** I get the nice Done screen — but I **skipped stock entirely**, so the 10 pieces I just created have no quantities or reorder points.

And a landmine I'd hit but the owner wouldn't: the stock listener gates on **`catalog.manage`** (`CatalogView.swift:145`), a *different* permission than the flow's `catalog.products.manage`. A manager with product access but not `catalog.manage` taps SET UP STOCK, the flow dismisses, and **nothing opens — silent dead-end.**

---

## 3. P0 — BLOCKERS (I cannot represent my business)

1. **No per-unit package pricing.** Packages are flat-rate only; I can't enter "$70/linear ft" or "$11/sq ft." `priceCard` is one flat field (`AssemblyModuleView.swift:155-179`), saved hard-coded flat-rate (`GuidedCatalogSetupModel.swift:210`). **The platform supports `linearFoot`/`sqft` (`Product.swift:16-17`) — the flow just refuses to use it.** Every job I quote is a different size; a fixed package price is wrong for all of them. *Fix: add a unit picker to the package (Flat rate / per linear ft / per sq ft / each) like the services module already has, and pass `pricingUnit(for: unit)` instead of `.flatRate`.*

2. **Labor can't be piecework.** Labor is per-hour only (`AddAssemblyLaborSheet.swift:61-87`; committed `.hour`, `GuidedCatalogSetupModel.swift:264`). My $/ft piecework can only be entered by lying to the "hours" labels. *Fix: give the labor sheet the same unit choice (per hour / per linear ft / per sq ft / flat), drive `pricingUnit` from it, and rename "Hours per job" to "Qty per job" with the unit shown.*

3. **No color/size variants — and no way to even see them.** Inline create makes one flat, SKU-less, option-less variant (`GuidedCatalogSetupModel.swift:240-243`); the variant picker labels by SKU only and never shows option values (`AddAssemblyMaterialSheet.swift:81-85`). My black/white pieces and 24 vinyl variants are impossible here, even though `CatalogOption`/`CatalogOptionValue`/`CatalogVariantOptionValue` exist. *Fix: let create-new attach an option (e.g. Color → black/white) and label variants by their option values, not raw SKU; add a "generate variants" matrix for color × thickness.*

---

## 4. P1 / P2 — GAPS & WISHES

- **P1 — Stock vs. ordered-per-job is unrepresentable.** No per-material "I stock this / I buy per job" flag; the company-wide Q3/Q4 can't capture that my membrane is ordered-per-job while my offcuts are stocked. *Add a per-material toggle (default from Q4); ordered-per-job items skip on-hand counting but still carry cost.*
- **P1 — Inline materials have no unit.** Create-new renders no unit field (`AddAssemblyMaterialSheet.swift:271-280`), so "20 of Top rail" has no "ft." The `UnitPickerField` that would fix this is already imported elsewhere. *Render it in create-new.*
- **P1 — Duplicate materials are silent.** Create-new never dedups against existing families by name (`GuidedCatalogSetupModel.swift:235-244`); re-typing a shared piece on the second package makes a duplicate stock item. *Match-by-name and offer "use existing 'Top rail'?" before creating.*
- **P1 — The most-invested user loses the payoff.** Stock-as-handoff dismisses the flow, skipping the Done screen **and the §14 completion notification** (`GuidedCatalogSetupFlow.swift:318-324` vs `GuidedSetupDoneView.swift:34`). *Either inline the stock module, or fire completion + return to Done after stock, not dismiss-and-forget.*
- **P1 — Permission mismatch dead-ends the stock step.** Flow gate `catalog.products.manage` vs stock-listener gate `catalog.manage` (`CatalogView.swift:145`). A product-only manager taps SET UP STOCK → silence. *Align the gates or pre-check before showing the button.*
- **P2 — Building a 10-piece package is a slog.** 10 open-fill-add-dismiss sheet cycles per package, ×2 for the shared system. *Add multi-row add and a reusable "piece library" pick-list with quantities.*
- **P2 — Finishing doesn't clear the draft.** `finish()`/`viewCatalog()` never call `clearDraft()` (only START OVER and survey-exit do — `GuidedCatalogSetupFlow.swift:48,333`). Next time I open setup I'm asked "Pick up where you left off?" for a run I *completed*, and resuming re-fires the completion notification (new model instance resets `didPostCompletion`, `GuidedCatalogSetupModel.swift:397`). *Clear the draft on successful finish.*
- **P2 — Survey routes fixed-price businesses through line-item modules.** Mix + fixed-job still yields Services + Goods (`BusinessProfile.swift:71-81`). *For `fixedJob`, lead with assemblies and demote services/goods to an opt-in "also sell items directly?" rather than mandatory steps.*
- **P2 — Partial material failure can show a false margin.** The package is created before materials (`GuidedCatalogSetupModel.swift:219`); if materials fail, the saved margin is still computed from the draft (`:283-286`) while the warning says "add them in the catalog" (`:289`). The "62% margin" can be a lie. *Recompute margin from what actually persisted.*

---

## 5. P3 — copy / UX nits

- **Stale file header.** `GuidedCatalogSetupFlow.swift:10-12` says "the assembly and stock modules hand off to the existing flows" — assembly is now wired inline (`:101`). Misleading to the next dev.
- **Progress bar jumps backward** survey→plan (33% → 29%), §2 above.
- **Two competing CTAs** on the stock step ("SET UP STOCK" vs "FINISH") with no hint which is "right."
- **Labor "Sell / hr"** on a fixed-price package is a confusing field — the customer never sees it.
- **Kebab "Stock Setup"** (mapping sheet) sits directly under "Set up your catalog" (the guide) — easy to confuse two different things.
- **Empty `—` Done state** can be reached: skip every module → Done shows "Nothing saved this run." Fine, but a fixed-job user who only wanted packages and bailed gets a dead-end "ALL SET" that built nothing.

---

## 6. VERDICT

**Could I onboard Canpro today? No.** I can get *names* and *fixed totals* into the catalog, but not my actual business: not my **$70/ft pricing**, not my **piecework labor**, not my **black/white pieces**, not my **24 vinyl variants**, and not the **stock-vs-order-per-job** split. Every one of those forces me to either fake the data (lie to "hours," invent a one-job total) or abandon the guide and go build it by hand in the full catalog editor — which is the exact misery this flow promised to save me from. For a cleaning company this guide is a two-minute lifeline; for a real materials-heavy installer it quietly can't hold the shape of the business.

**The single most important fix: give the package (and labor) a unit so I can price per linear foot / per square foot.** The capability already exists in the data model and in the sibling services/goods module — the assembly builder just hard-codes flat-rate and discards it. Wire `pricingUnit(for: unit)` into `saveAssembly` and put a unit picker on the price card. That one change turns my three packages from "wrong on every job" into "right on every job," and it's the difference between this flow being a demo and being the lifeline.

*Honest credit:* the survey voice, the live margin math, the sell-vs-cost separation, the no-duplicate "pick existing" reference path, offline-safe saves, and draft resume are all genuinely well done. The bones are right. It's the **per-unit pricing, piecework labor, and variants** that aren't there yet — and for an installer, those aren't edge cases, they're the whole job.
