I have everything I need — I've traced the full flow as Northside Plumbing, confirmed the routing logic in code, and verified the cold-start unit/SKU reality against live prod. Changing nothing. Here's the audit.

---

# Guided Catalog Setup — Cold-Start Audit
**Operator:** owner, Northside Plumbing · **Role:** account holder, first time in the app · **Mode:** read-only trace of the worktree code

---

## 1. Who I am and what I'm trying to build

I run a plumbing shop. Service calls, repairs, fixture swaps. I bill **time + parts**, with a few flat-rate jobs. I am not going to sit at a desk and "configure a catalog." I want my prices in, and I want to get back to work. Here's the catalog I actually have:

| Bucket | Reality | Volume |
|---|---|---|
| **Services — flat** | Diagnostic/service call $129; "install customer-supplied toilet" $190 | a handful |
| **Services — hourly** | Journeyman $145/hr · Apprentice $85/hr (**two rates**) | 2 rates |
| **Goods — fixtures** | Faucets, toilets, water heaters — **brand/model SKUs**, resold at ~**2× cost** | **40+ models** |
| **Goods — fittings/parts** | Elbows, couplings, valves, supply lines | **dozens of small SKUs** |
| **Goods — pipe** | Copper ½"/¾", PEX, ABS — sold/used **per linear foot** | several |
| **Truck stock** | Solder, flux, Teflon tape, pipe dope — **consumed on jobs, not sold**, tracked loosely | ~handful |

Watch items going in: are my **units** there? Can I separate **my cost from the customer price** and just say "×2"? Does the **two-rate labor** model fit? Can I record a **model number (SKU)**? Is **pipe-by-the-foot** a thing? And does the survey actually route a **service-first shop that also sells parts** to the right place?

---

## 2. Step-by-step trace

### Entry — Catalog tab → ⋯ → "Set up your catalog"
Found it. [CatalogView.swift:231](OPS/Views/Catalog/CatalogView.swift:231), opens full-screen ([CatalogView.swift:126](OPS/Views/Catalog/CatalogView.swift:126)). Gated on `catalog.products.manage` — I'm the account holder, so I'm in ([GuidedCatalogSetupFlow.swift:61](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift:61)). One row down in that **same menu** is **"Import…"** ([CatalogView.swift:239](OPS/Views/Catalog/CatalogView.swift:239)) — hold that thought, it matters a lot later.

### Phase 1 — Survey (5 taps for me)
Driver: [SurveyQuestion.swift](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift). One question per screen, tap to advance, BACK to revise. Clean, fast, plain-English. My answers:

| Q | Screen | What I tap | Why |
|---|---|---|---|
| Q1 sells | "What do customers pay you for?" | **Both** | I sell my time and the parts |
| Q2 pricing | "How do you price a job?" | **Depends on the job** | Honest answer — some flat, mostly hourly + parts |
| Q3 materials | "Do your jobs burn through materials?" | **Yes, lots of parts** | fittings everywhere |
| Q4 stock | "Want OPS to count your stock?" | **Just my costs** | I don't count solder. I eyeball the truck |
| Q5 margins | "Track your costs and margins?" | **Track both** | I mark up 2×, I want margin |

**First friction is invisible and it's in Q2.** My honest answer — "Depends on the job" (`.mixed`) — silently flips on the assembly builder: `runAssemblies = pricing == .fixedJob || pricing == .mixed` ([BusinessProfile.swift:64](OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift:64)). Had I tapped **"By the hour,"** I'd get a clean services+goods path with no packages. So the *truthful* answer routes me into the wrong tool, and nothing on screen tells me that's what just happened. A time-poor operator will not feel that fork — they'll just wonder later why the app keeps pushing "packages."

### Phase 2 — Plan ("Here's the plan")
[GuidedSetupPlanView.swift](OPS/Views/Catalog/GuidedSetup/GuidedSetupPlanView.swift). Because `.mixed` turned on assemblies, and `setupModules` puts assembly **first** ([BusinessProfile.swift:71-81](OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift:71)), my plan reads:

```
01  JOB PACKAGES   Fixed-price jobs — materials and labor, all in.   ~5 min
02  YOUR SERVICES  Name them and set your rates.                     ~2 min
03  YOUR GOODS     The products you sell.                            ~2 min
```

The screen leads with the one thing I **don't** do — fixed-price packages — and stamps it "~5 min, the big one" ([GuidedSetupPlanView.swift:82](OPS/Views/Catalog/GuidedSetup/GuidedSetupPlanView.swift:82)). My truck-stock consumables aren't here at all (I said "just my costs," so `runStock=false` — [BusinessProfile.swift:66](OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift:66)). First impression: *this was built for somebody who sells "a Rail Install," not a plumber.*

### Phase 3, Module 01 — JOB PACKAGES (the hero I didn't ask for)
[AssemblyModuleView.swift](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift). "PACKAGE YOUR JOBS — one price, everything in it." It wants a name, a task-type link, **one all-in price**, and then forces me to add contents — save is blocked until I do: `isEmptyContents` → `// ADD WHAT'S IN IT` ([AssemblyModuleView.swift:43-60](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift:43)).

I bill time + parts at line level. I don't have a fixed "$X, all in" for a repair — that's the whole point, every job's different. To get past this screen I either fake a package or tap **NEXT** to skip. But the bar only says **NEXT/FINISH** ([GuidedCatalogSetupFlow.swift:224-231](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift:224)) — there's no **SKIP** label, so a cautious operator doesn't even know skipping is allowed. (Credit where due: if I *did* want a package, the inline labor sheet lets me stack Journeyman and Apprentice as two lines with separate sell/cost/hours — [AddAssemblyLaborSheet.swift](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyLaborSheet.swift), looped at [GuidedCatalogSetupModel.swift:257](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:257). The two-rate model is fine here. I just don't need this module.)

### Phase 3, Module 02 — YOUR SERVICES
[ProductLineModuleView.swift](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift), `kind: .service`. One line at a time: Name · Sell rate · Your cost · Unit · Category → **ADD SERVICE** → form clears, name refocuses ([ProductLineModuleView.swift:272-281](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:272)). This part actually fits me:

- **Two labor rates → two lines.** "Journeyman labor" $145, "Apprentice labor" $85. Unlimited lines, so both go in. Works.
- **Flat-rate jobs → flat unit.** $129 diagnostic, $190 toilet install — the unit picker offers "Flat rate" by default ([UnitPickerField.swift:25](OPS/Views/Catalog/Products/Shared/UnitPickerField.swift:25)). Works.

But here's the snag the moment I want "/hr": **I have no units.** The picker only shows `companyUnits` — units that already exist for my company ([ProductLineModuleView.swift:37-41](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:37)). I verified against production: **50 of 55 companies have zero `catalog_units`, and there is no trigger that seeds them on signup** (the `companies` table seeds default project/opportunity views and a trial — not units). So as a new shop, my Unit menu is **just "Flat rate" + "New unit…"**. To say "$145 **per hour**" I have to stop, open the New-unit sheet, type "HR", pick the "Time" dimension, save ([InlineCreateUnitSheet — CatalogManageHelpers.swift:187](OPS/Views/Catalog/Manage/CatalogManageHelpers.swift:187)), then come back. I build my own vocabulary — hour, each, foot — one detour at a time. Nothing seeded the obvious ones.

And the **markup** problem, which for me is the whole job: there are two separate boxes, **Sell rate** and **Your cost**, and no way to say "cost × 2." The margin line is **read-only output** ([ProductLineModuleView.swift:171](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:171), [model.marginPercent:312](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:312)) — I can't drive price *from* cost. I think in cost + markup. The app makes me do the multiplication in my head and type both numbers.

### Phase 3, Module 03 — YOUR GOODS — *this is where I quit*
Same screen, `kind: .good`. Placeholder even reads "e.g. Composite deck board" ([ProductLineModuleView.swift:146](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:146)) — decking, not plumbing; another little signal this wasn't built for me.

Now do the math on my reality. **40+ fixtures + dozens of fittings + several pipe types ≈ 70–100 products.** For each one, through this single form, I must:

1. type the name,
2. compute and type the sell price (cost × 2, in my head),
3. type the cost,
4. set the unit (creating "ft"/"each" the first time),
5. set a category,
6. tap ADD, wait for the network save ([ProductLineModuleView.swift:67-68](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:67) — every add is a live round-trip), repeat.

There is **no bulk add, no "add many," no paste, no duplicate-this-line, and no SKU field at all.** The product write hard-codes `sku: nil` ([GuidedCatalogSetupModel.swift:146-165](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:146)) — so my brand/model numbers, the thing that distinguishes a Moen 1234 from a Delta 5678, **cannot be recorded** (and indeed **0 of 22 products in all of production carry a SKU** — the catalog isn't built around them). No **variants** either: "Moen faucet, 3 finishes" is three separate from-scratch entries; the variant model exists in the schema but this flow writes flat `products` rows and never touches it.

Around fixture #6 I'm doing arithmetic in my head, inventing units, and realizing I'm maybe 5% through. **I close the app.** And the bitter part: a **full CSV importer already exists** — `CatalogImportSheet`, a PICK→MAP→PREVIEW→APPLY flow with a dedicated **PRODUCTS** tab ([CatalogImportSheet.swift:1-14](OPS/Views/Catalog/Import/CatalogImportSheet.swift)) — sitting one row away in the same ⋯ menu. The guided flow that just made me type 6 fixtures by hand **never once mentioned it.**

### Phase 4 — Done (not that I got here)
[GuidedSetupDoneView.swift](OPS/Views/Catalog/GuidedSetup/GuidedSetupDoneView.swift) — clean summary, fires a completion notification ([GuidedCatalogSetupModel.swift:396](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:396)). The payoff screen is nice. I just couldn't afford the journey to it.

---

## 3. P0 — Blockers (I cannot onboard today)

**P0-1 · Goods-heavy entry is one-at-a-time, and the existing bulk importer is hidden from the flow.**
~70–100 fixtures/fittings/pipe through a single sequential form ([ProductLineModuleView.swift:141-215](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:141)), each a live network save, no clone/paste/bulk. This is the abandonment point for any reseller. The kicker is that `CatalogImportSheet` (CSV, PRODUCTS tab) already does exactly this ([CatalogImportSheet.swift:5-9](OPS/Views/Catalog/Import/CatalogImportSheet.swift)). **Fix:** surface "Import a list instead" *inside* the Goods module (and the plan card when `materialUse == .heavy`), routing into the existing importer; at minimum add clone-last-line and keep the keyboard up across adds. The plumbing exists — the flow just won't admit it.

**P0-2 · No SKU, no variants — a brand/model reseller can't represent the catalog at all.**
The flow drops SKU on the floor (`sku: nil`, [GuidedCatalogSetupModel.swift:160](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:160)) and writes flat products with no variant axis. "Water heater, model AO-40-G, 3 capacities" has nowhere to live. **Fix:** add an optional SKU field to the goods line, and a "this comes in sizes/finishes" affordance that writes variants — or, if that's Slice-3 scope, route SKU-heavy goods to the importer (which already maps SKU columns).

## 4. P1 / P2 — Gaps & wishes

**P1-1 · Markup is manual on every line.** Two independent boxes, margin read-only ([ProductLineModuleView.swift:152-173](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:152)). *Wish:* a markup mode — type cost, set "×2" (or a company default markup), price auto-fills and stays editable. For a 2× reseller this turns 70 mental multiplications into one setting.

**P1-2 · Cold-start has no units; I must hand-build hour/each/foot.** No seeding (verified: 50/55 companies have none), picker shows only what exists ([UnitPickerField.swift:106-111](OPS/Views/Catalog/Products/Shared/UnitPickerField.swift:106)). Pipe-per-foot *is* supported once a length unit exists (`length → linearFoot`, [CatalogManageHelpers.swift:355](OPS/Views/Catalog/Manage/CatalogManageHelpers.swift:355)) — but I have to create "ft" myself first. *Wish:* seed a sensible default unit pack (hour, day, each, ft, sq ft) on first catalog entry, or pre-offer them in the picker. This is the "do the work for them" moment, and right now it does the opposite.

**P1-3 · The honest pricing answer mis-routes me.** "Depends on the job" → assembly module leads ([BusinessProfile.swift:64,71](OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift:64)). A time-and-materials shop is the *most common* trade shape and it gets the package builder first. *Wish:* don't let `.mixed` alone lead with assemblies — lead with services/goods and offer packages last, or add a Q2 option that says plainly "mostly time + parts, sometimes a flat price" and route that to services-first.

**P1-4 · Truck stock I consume but don't sell has no home.** Pick "just my costs" and there's no stock module at all; pick "count it" and you're handed the sellable-inventory counter (`GuidedStockSetupFlow`). Neither models "solder/flux I burn on jobs." Worse, materials I create inline inside a package silently scaffold a catalog family + variant at **qty 0** ([GuidedCatalogSetupModel.swift:235-245](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:235)) — phantom stock items I never asked for. *Wish:* a lightweight "shop supplies / consumables" bucket (cost-only, no on-hand, no reorder nagging).

**P2-1 · Offline banner makes a promise the module breaks.** Banner: "You can keep moving. Saving starts when the connection is back" ([GuidedCatalogSetupFlow.swift:194](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift:194)). Reality: offline, ADD is disabled — `canAdd` requires `isOnline`, reason "// OFFLINE — SAVE BLOCKED" ([ProductLineModuleView.swift:68,77](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:68)). There is no queue. For a field-first app that promises poor-connectivity tolerance, either queue the saves or tell the truth in the banner.

**P2-2 · Every module is skippable but the only control says NEXT/FINISH.** No SKIP label ([GuidedCatalogSetupFlow.swift:224-231](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift:224)), so a careful operator thinks the assembly module is mandatory and fills it to be safe. Add an explicit SKIP.

## 5. P3 — Copy / UX nits *(directional — final copy should run through `ops-copywriter`, per the spec's own D5)*

- **Goods placeholder "e.g. Composite deck board"** ([ProductLineModuleView.swift:146](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:146)) — decking vocabulary in a plumbing session. Make the example trade-neutral or profile-aware.
- **Positive margin is muted.** Services module paints a healthy margin in `tertiaryText` (gray) ([ProductLineModuleView.swift:268](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift:268)) while the assembly module uses `primaryText` ([AssemblyModuleView.swift:287](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift:287)). The "you make 50%" confidence beat is the one number I care about — don't whisper it, and keep it consistent.
- **Completion deep-link is always `segment=products`** ([GuidedCatalogSetupModel.swift:412](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift:412)) even if I only built packages or stock.
- **Dead code:** the material sheet wires an `InlineCreateUnitSheet` that nothing ever triggers ([AddAssemblyMaterialSheet.swift:38,157,271-280](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift:38)) — inline materials always save with a nil unit.

---

## 6. Verdict

**Could I onboard today? No.** The survey and the services module are genuinely good — two-rate labor and flat-rate calls go in cleanly, and the flow is fast and on-voice. But I am a **service-first shop that sells a lot of parts**, and this flow makes three wrong bets about me: it leads with a **fixed-price package builder** I don't use, it makes me **enter 70–100 SKU-bearing goods one at a time with no SKU field and no bulk path**, and it makes me **invent my own units and do my markup math by hand**. I quit in the Goods module.

**The single most important thing to fix:** **wire the existing CSV importer into the Goods module (P0-1)** and let me record a SKU (P0-2). The bulk machinery is already built and sitting one menu-row away — the guided flow just has to stop pretending it isn't there. Do that, and a parts-heavy trade can actually finish. Leave it, and every reseller who opens this flow closes it the same place I did.

*One routing change rides shotgun and is nearly free: stop letting "Depends on the job" lead with packages (P1-3). The most common trade — time + parts — deserves to land on services and goods first, not on a builder for somebody else's business.*
