I've traced the entire flow end to end. I have everything I need — entry point, survey branching, module derivation, both modules, the forced sub-sheets, the gates, and the supporting models. Here's my audit, in character.

---

# Guided Catalog Setup — Cold-Start Audit
### Operator: owner, **Apex Auto Detailing** · services-only · the simple end of the spectrum

---

## 1. Who I am & what I'm trying to build

I run a detailing shop. Me + one tech. I sell a short menu of **flat-price service packages**, and that's basically it. My catalog is:

- **Express Wash** — flat price, 3 vehicle sizes (Sedan / SUV / Truck)
- **Full Interior** — flat, 3 sizes
- **Full Detail** — flat, 3 sizes ($180 / $230 / $280)
- **Ceramic Coating** — flat, 3 sizes
- **Add-ons:** pet hair $40 · engine bay $35 · headlight restore $60
- **Materials/stock:** none I sell. Wax, microfiber, chemicals are consumed, not tracked. **I do not want inventory.**
- **Labor:** baked into the package price. **I do not track it separately.**

So what I need is dead simple: ~4 services (each with 3 size prices) + 3 add-ons. Flat prices. No cost, no margin, no parts, no counting. The design's own §4.5 "cleaning company" worked example is literally me — it promises *"two survey taps, done in under two minutes."* Let's see if I get that.

---

## 2. Step-by-step trace (what I tapped, what fought me)

### Entry — Catalog → kebab → "Set up your catalog"
- **Tap 1:** ellipsis (top-right of CATALOG header) — [CatalogView.swift:247](OPS/Views/Catalog/CatalogView.swift)
- **Tap 2:** SETUP → **"Set up your catalog"** — [CatalogView.swift:230‑232](OPS/Views/Catalog/CatalogView.swift). Opens full-screen at the survey. Gated on `catalog.products.manage` ([GuidedCatalogSetupFlow.swift:39,61](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift)); as owner I'm fine.
- *Friction:* none. Clean entry. Good.

### Phase 1 — Survey (one question per screen, tap = answer + advance)
Driver: [GuidedSetupSurveyView.swift:107‑120](OPS/Views/Catalog/GuidedSetup/Survey/GuidedSetupSurveyView.swift); content/branching: [SurveyQuestion.swift](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift).

- **Tap 3 — Q1 "What do customers pay you for?"** → I tap **"Our time"** (`Labor, service calls, know-how.`) — [SurveyQuestion.swift:58‑65](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift). `sells = .services`.
- **Tap 4 — Q2 "How do you price a job?"** → Options at [SurveyQuestion.swift:66‑76](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift). My Full Detail is **$280, all in** — so I tap **"One price for the whole job"** whose sublabel is *"All in. Materials and labor included."* `pricing = .fixedJob`.
  - **This is the trap, and the copy walked me right into it.** That sublabel describes my mental model exactly, so it's the obvious pick. But `.fixedJob` is the one answer that flips on the assembly builder (next section).
- **Branch:** `next(after: .pricing)` returns `.trackCost` because `sells == .services` — [SurveyQuestion.swift:119‑120](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift). So it **correctly skips** the materials (Q3) and stock (Q4) questions. Good — the survey itself doesn't over-ask me about parts.
- **Tap 5 — Q5 "Track your costs and margins?"** → I tap **"Just set prices"** (`Add your costs later.`) — [SurveyQuestion.swift:93‑99](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift). `trackCost = false`. Survey ends, `completeSurvey` → plan ([GuidedCatalogSetupModel.swift:56‑60](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift)).

**3 questions, 3 taps. The survey is genuinely short.** No complaint here. The problem is what it *derives*.

### The derivation — what my 3 answers route me into
[BusinessProfile.swift:62‑81](OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift). My profile = `services / fixedJob / none / nil / trackCost:false`:

| Flag | Value | Why |
|---|---|---|
| `runServices` | ✅ | `sells != .goods` |
| `runGoods` | ❌ | `sells == .services` |
| **`runAssemblies`** | **✅** | **`pricing == .fixedJob`** — line 64 |
| `runMaterials` | ❌ | `materialUse == .none` |
| `runStock` | ❌ | no materials |

→ **`setupModules = [.assembly, .services]`** ([BusinessProfile.swift:71‑81](OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift)). Assembly is the **hero**, so it leads.

> The survey just decided that because I said "I charge one price per job," I must be building **fixed-price packages of materials and labor** — i.e. a fencing contractor. I'm a detailer. There is **no path** for "I sell flat-price services with nothing inside them." The only Q2 answers that avoid the assembly module are "Line by line" or "By the hour" — and both are **lies** about how I price. An honest services-only shop *cannot* avoid the assembly builder.

### Phase 2 — Plan ("HERE'S THE PLAN")
[GuidedSetupPlanView.swift:80‑87](OPS/Views/Catalog/GuidedSetup/GuidedSetupPlanView.swift). My plan renders:

```
01  JOB PACKAGES   Fixed-price jobs — materials and labor, all in.   ~5 min
02  YOUR SERVICES  Name them and set your rates.                      ~2 min
```

- Header says *"Built for how you work. Skip anything. Add more later."* — [GuidedSetupPlanView.swift:41](OPS/Views/Catalog/GuidedSetup/GuidedSetupPlanView.swift). Good intent.
- But the **#1, biggest, longest (~5 min) item is the module I can't use**, and it's described in fencing-contractor language ("materials and labor, all in"). My first impression of "my" plan is that this tool is for somebody else. The promised "~2 min" cleaner experience is now a "~7 min" plan led by parts-and-labor.
- **Tap 6:** START — [GuidedCatalogSetupFlow.swift:219‑223](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift).

### Phase 3, Module 01 — Assembly builder ("PACKAGE YOUR JOBS") — where I hit the wall
[AssemblyModuleView.swift](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift). Header: *"One price, everything in it — materials and labor."* ([:105](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift)).

I do the natural thing — this screen literally has a section **"ALL-IN PRICE / What the customer pays"** ([:157‑158](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift)), which is exactly my Full Detail:
- Type name **"Full Detail"** (name auto-focuses, [:90‑92](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift))
- Type price **280**
- Look for save → **"SAVE PACKAGE" is disabled**, and underneath: **"// ADD WHAT'S IN IT"**

**Why I'm blocked** — [AssemblyModuleView.swift:43‑61](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift):
```swift
private var isEmptyContents: Bool { draft.materials.isEmpty && draft.labor.isEmpty }
private var canSave: Bool {
    ...
    guard priceAmount != nil, !isEmptyContents else { return false }   // ← blocks me
    ...
}
// disabledReason: if isEmptyContents { return "// ADD WHAT'S IN IT" }
```

I have no materials and no tracked labor. So I try to humor it — tap **ADD MATERIAL**:
- [AddAssemblyMaterialSheet.swift:94‑102](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift): to add anything I must enter a **name + your cost + qty-per-job**. It wants me to itemize wax with a per-unit cost and a quantity. That's the exact inventory/BOM thinking I came here to avoid.

Tap **ADD LABOR** instead:
- [AddAssemblyLaborSheet.swift:33‑36](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyLaborSheet.swift): requires **name + your cost/hr + hours/job**. I told the survey *"just set prices, I don't track cost"* — and this sheet **forces a cost number** before it'll let me add the line.

So: **I cannot save my flat-price package without inventing cost data I explicitly opted out of.** The marginCard ([:268‑293](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift)) is also shown the whole time — "YOUR COST / MARGIN" — even though I chose "just set prices." This module never reads `trackCost` at all.

The only way out is the bottom bar — **Tap 7: NEXT** ([GuidedCatalogSetupFlow.swift:224‑231,302‑305](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift)). It's styled as the **primary** button and says "NEXT," not "skip." When I tap it, my typed "Full Detail / $280" is **discarded** (the assembly `@State draft` dies; only committed packages persist). I just wasted that entry and I'm not sure I did the right thing.

### Phase 3, Module 02 — Services ("ADD YOUR SERVICES") — finally, my screen
[ProductLineModuleView.swift](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift). **This module is correct for me.** Because `trackCost == false`:
- The "Your cost" field is **hidden** ([:160](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift)) and margin is **hidden** ([:171](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift)). 
- Minimal required = **name + sell price**; unit defaults to **"Flat rate"** (no unit required — [UnitPickerField.swift:25‑31,109](OPS/Views/Catalog/Products/Shared/UnitPickerField.swift)), category optional. Gate: [ProductLineModuleView.swift:67‑73](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift).
- Per line: name is auto-focused, type it → tap **Sell rate**, type price → tap **ADD SERVICE**. After save, the form resets and refocuses the name field ([:277‑280](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift)). ~2 taps + 2 text entries per line. Smooth.

**But the tiered-pricing tax hits here.** There is no size/tier/variant concept on a service line — `ProductLineDraft` has only name/sell/cost/unit/category ([GuidedCatalogSetupDraft.swift:37‑61](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupDraft.swift)). `CatalogVariant` exists but it's a **stock SKU** bound to `catalogItemId` with quantity/thresholds ([CatalogVariant.swift:17‑29](OPS/DataModels/Supabase/Catalog/CatalogVariant.swift)) — not a price tier for a service. So "Full Detail, 3 sizes" must be entered as **three separate lines**:
- `Full Detail – Sedan` 180 · `Full Detail – SUV` 230 · `Full Detail – Truck` 280

My 4 services × 3 sizes = **12 lines**, + 3 add-ons = **15 service lines** for what is really 4 services and 3 extras. (If I tried to name all three sizes "Full Detail," the dup-name guard blocks me — *"// NAME ALREADY USED"*, [ProductLineModuleView.swift:78](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift).) Add-ons are just more flat lines — there's no "optional extra attached to a service" concept anywhere.

- After my last line: **Tap 8: FINISH** (it's the last module, so the button reads FINISH — [GuidedCatalogSetupFlow.swift:227](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift)).

### Phase 4 — Done
[GuidedSetupDoneView.swift](OPS/Views/Catalog/GuidedSetup/GuidedSetupDoneView.swift). "READY FOR ESTIMATES," lists my 15 lines, fires the completion notification ([:34](OPS/Views/Catalog/GuidedSetup/GuidedSetupDoneView.swift), [GuidedCatalogSetupModel.swift:396‑417](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift)). **Tap 9: DONE.** Clean payoff.

### Tap count
- **Spine (nav + survey), honest path:** kebab, "Set up", Q1, Q2, Q5, START, **NEXT-to-escape-assembly**, FINISH, DONE = **~9 taps** — one of which (NEXT) is pure waste, plus the discarded "Full Detail/$280" I typed into the wrong screen.
- **Data entry:** 15 lines × ~2 taps = ~30 taps + 30 text entries, **3× inflated** by tiered pricing having no variant support.
- **If the flow had routed me correctly** (services-only → `[.services]` only): same survey, START drops me straight into Services, no detour, no discard. The assembly module costs me a confusing wrong turn for zero benefit.

---

## 3. P0 — Blockers

**P0‑1 — A services-only, flat-price business is force-routed into the assembly builder, which cannot save a price-only package.**
- Routing: `runAssemblies = pricing == .fixedJob || pricing == .mixed` with **no condition on `sells`** — [BusinessProfile.swift:64](OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift). Any "fixed price" or "depends" answer routes even a pure-service shop into assemblies.
- The wall: `canSave` requires `!isEmptyContents` — [AssemblyModuleView.swift:48](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift) — and both content sheets force a **cost** value to add a line ([AddAssemblyMaterialSheet.swift:94‑102](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyMaterialSheet.swift), [AddAssemblyLaborSheet.swift:33‑36](OPS/Views/Catalog/GuidedSetup/Modules/AddAssemblyLaborSheet.swift)). So my "Full Detail $280, nothing inside" is **unsavable** in the module the flow led with.
- Note the model would happily persist a price-only package (the materials/labor loops simply don't run — [GuidedCatalogSetupModel.swift:227‑280](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift)). **The capability exists; the UI gate forbids it.** A price-only package would even be a valid `kind=package`, `bundle_pricing_mode=override`, zero children ([:207‑217](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift)).
- **Fix (do both):** (1) condition routing — `runAssemblies = (pricing == .fixedJob || pricing == .mixed) && sells != .services`, so services-only never sees assemblies; (2) drop the `!isEmptyContents` requirement from `canSave` so an empty/price-only package is allowed (it's a legitimate fixed-price service). This also reconciles the spec's own contradiction: §7's formula says fixedJob→assembly, but §4.5's cleaner example says services-only skips assemblies. The build shipped the §7 formula; the §4.5 promise is broken.

**P0‑2 — The assembly module ignores `trackCost` and forces cost entry on a "just set prices" operator.**
- I chose "Just set prices" (`trackCost=false`), yet the assembly module always shows the cost/margin card ([AssemblyModuleView.swift:268‑293](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift)) and **both content sheets hard-require a cost number** to add a line. There is no way to engage the assembly module at all without entering cost data I opted out of. (The services module honors `trackCost` correctly — [ProductLineModuleView.swift:160,171](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift) — so the inconsistency is glaring.)
- **Fix:** assembly module must read `model.profile?.trackCost`; when false, hide the cost/margin card, make material/labor cost optional, and let labor be added as "hours only."

> Neither P0 is a *hard* dead-end — I can tap NEXT to skip assembly. But for a non-technical operator who engages the lead module as designed, it's a "why won't this save?" wall on the very first screen of "my" setup, followed by silently discarding what I typed. For a lifeline product, that's a bail moment.

---

## 4. P1 / P2 — Gaps & wishes

**P1‑1 — No price-tier / variant support for service lines (Sedan/SUV/Truck).** My single most common pricing structure can't be modeled. I'm forced into 3 near-duplicate lines per service (12 lines for 4 services), and the dup-name guard ([ProductLineModuleView.swift:78](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift)) means I must hand-disambiguate every name. *Wish:* let a service carry size/tier options with a price each (one "Full Detail" with Sedan/SUV/Truck rows), the way the broader catalog already does variants for stock.

**P1‑2 — The offline banner lies.** It says *"You can keep moving. Saving starts when the connection is back"* ([GuidedCatalogSetupFlow.swift:194](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift)), but every Add/Save **hard-requires `isOnline`** ([ProductLineModuleView.swift:68,77](OPS/Views/Catalog/GuidedSetup/Modules/ProductLineModuleView.swift); [AssemblyModuleView.swift:46,55](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift)). In my metal-roofed detailing bay with no signal, I literally cannot add a single line while being told to "keep moving." For a field-first app, either queue saves offline or change the copy to tell the truth.

**P1‑3 — No labeled "skip" on a module.** The plan promises *"Skip anything,"* but a module's only forward control is the primary-styled **NEXT/FINISH** ([GuidedCatalogSetupFlow.swift:224‑231](OPS/Views/Catalog/GuidedSetup/GuidedCatalogSetupFlow.swift)). Stuck on the disabled SAVE PACKAGE, I'm not told that NEXT = "skip this, it's optional." *Wish:* a secondary "SKIP — not how I work" affordance on optional modules, especially assembly.

**P2‑1 — Typed module drafts are discarded on NEXT.** My "Full Detail/$280" in the assembly screen vanishes when I advance ([AssemblyModuleView.swift:21](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift) `@State draft` is not persisted). At minimum, if I typed a name+price in assembly and skip, offer "add these as simple services instead?"

**P2‑2 — BACK from the plan wipes the survey.** `goBack` sets `phase = .survey(questionIndex: 0)` ([GuidedCatalogSetupModel.swift:94‑95](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift)), and the survey view re-inits fresh `@State` (answers cleared, `current = .sells` — [GuidedSetupSurveyView.swift:18‑20](OPS/Views/Catalog/GuidedSetup/Survey/GuidedSetupSurveyView.swift)). If I reach the plan, dislike "JOB PACKAGES," and hit BACK to change my answer, I restart the whole survey. (The `questionIndex` in the phase is also dead — the view ignores it.)

**P2‑3 — Add-ons have no concept.** Pet hair / engine bay / headlight are just flat service lines, indistinguishable from core services — no "optional extra" grouping. Acceptable for v1, but noted.

---

## 5. P3 — Copy / UX nits

- **Q2 sublabel actively misleads simple shops.** *"One price for the whole job — All in. Materials and labor included."* ([SurveyQuestion.swift:68‑69](OPS/Views/Catalog/GuidedSetup/Survey/SurveyQuestion.swift)) reads as "yes, that's my flat price" to a detailer, then routes to a materials+labor builder. Either soften the sublabel or (better) fix the routing so the words can stay honest.
- **Plan subtitle for assembly** is fencing-shop language — *"Fixed-price jobs — materials and labor, all in."* ([GuidedSetupPlanView.swift:82](OPS/Views/Catalog/GuidedSetup/GuidedSetupPlanView.swift)). A service shop that landed here is told its main module is about parts.
- **Empty-contents margin reads 100%.** With a price and no contents, `assemblyMarginPercent` → `(price‑0)/price = 100%` ([GuidedCatalogSetupModel.swift:329‑335](OPS/Services/Catalog/GuidedCatalogSetup/GuidedCatalogSetupModel.swift)); the card would flash "100%" — meaningless for someone not tracking cost. (Moot once trackCost is honored.)
- **"~5 min" on the assembly row** sets a heavy expectation as item 01 for a shop that needs ~2.
- All copy is otherwise on-voice — terse, lowercase sublabels, `//` eyebrows, no emoji/exclamation. Good. (Per OPS rules this still needs an `ops-copywriter` pass before ship.)

---

## 6. Verdict

**Could I onboard today? Yes — but only by ignoring the screen the flow pushed me to first.** The **Services module is genuinely good** for a simple shop: with "just set prices" it collapses to name + price, flat-rate by default, save-and-repeat. If the flow dropped me straight there, I'd be the "~2 minutes" success story the design promised.

**Instead, because I answered honestly ("one price for the whole job"), the flow led with a fencing-contractor package builder I can't complete** — disabled SAVE behind "// ADD WHAT'S IN IT," cost forced on a "just set prices" operator, and my typed package thrown away when I escape via an unlabeled NEXT. A time-poor detailer hits that wall on screen one of "their" setup and concludes this tool is built for somebody more complicated than them. **That's exactly the "feels like a tech demo, not a lifeline" failure.** And the tiered-pricing reality (Sedan/SUV/Truck) triples my line count with no variant support.

**The single most important fix for a simple service business:** stop equating "I charge one price per job" with "I assemble packages of materials and labor." Gate assemblies on `sells != .services` ([BusinessProfile.swift:64](OPS/Services/Catalog/GuidedCatalogSetup/BusinessProfile.swift)) so a services-only shop goes **straight to the Services module** — and, as a safety net, let the assembly module save a **price-only package** and honor `trackCost` ([AssemblyModuleView.swift:48,268‑293](OPS/Views/Catalog/GuidedSetup/Modules/AssemblyModuleView.swift)). Do that and the detailer gets the under-two-minutes lifeline the design intended. Right now, the simplest customer is the one the flow handles worst.

*(Read-only audit — no code changed.)*
