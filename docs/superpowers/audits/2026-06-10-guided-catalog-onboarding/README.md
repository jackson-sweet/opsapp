# Guided Catalog Setup — Cold-Start Onboarding Audit (2026-06-10)

Consolidated review hub for four simulated-company audits of the iOS **Guided Catalog Setup**
flow (branch `feat/guided-catalog-setup`; audited against the current worktree state, including
the uncommitted add-existing / `$` / unit-grouping / back-nav work).

Each audit role-plays a real trade business doing a **cold-start catalog setup**, traces the flow
through the code, and logs blockers, gaps, and improvement wishes.

## Simulated companies

| File | Company | Trade | What it stresses |
|------|---------|-------|------------------|
| [`01-deck-rail.md`](01-deck-rail.md) | Canpro Deck & Rail | Railing + vinyl installer | Assemblies, pieces shared across glass/picket, black/white variants, per-ft backend vs fixed customer price, piecework labor, vinyl offcut stock |
| [`02-plumbing.md`](02-plumbing.md) | Northside Plumbing | Service + parts | Bulk goods entry, two hourly rates, markup, per-ft pipe, truck-stock consumables |
| [`03-landscaping.md`](03-landscaping.md) | Evergreen Grounds | Landscape install + maintenance | Volume/weight units (yard/ton), per-area + per-visit pricing, recurring maintenance, bulk stock |
| [`04-auto-detailing.md`](04-auto-detailing.md) | Apex Auto Detailing | Services-only | Minimal "skip everything" path, tiered-by-size pricing, no inventory, over-ask check |

## Status — all four complete (2026-06-10)

- [x] **01 — Deck & Rail** — verdict: **can't onboard.** No per-unit pricing, no piecework labor, no color/24-variant support.
- [x] **02 — Plumbing** — verdict: **can't onboard.** Bails in Goods: 70–100 SKUs one-at-a-time, no SKU field, no bulk path.
- [x] **03 — Landscaping** — verdict: **partial & dishonest.** No volume/mass units, unitless materials, recurring has no home.
- [x] **04 — Auto Detailing** — verdict: **yes — but only by dodging the assembly screen the flow pushed first.**

## Consolidated synthesis

### The headline all four share
Two things decide whether this flow is a lifeline or a demo: **(1) units must be first-class — seeded, creatable everywhere, and allowed to drive pricing; and (2) the survey must stop routing fixed-price & service-only shops into the assembly builder.** Every report's #1 fix is one of those two.

### Universal blockers (3–4 of 4)
1. **Survey mis-routes fixed-price & service shops into assemblies.** `BusinessProfile.swift:64` = `runAssemblies = fixedJob || mixed` with **no `sells` condition** — flagged by Auto Detailing (P0: services-only can't even save a price-only package), Plumbing (P1: time+parts gets the package builder), Deck & Rail (P2). **Fix:** `runAssemblies = (fixedJob || mixed) && sells != .services`; lead service/parts shops with Services/Goods.
2. **Units aren't first-class or seeded.** Cold-start companies have ~zero units (50/55 per the plumbing trace); the picker only shows what already exists; no volume/mass for landscaping; package & labor pricing hard-code flat-rate and discard the unit. **Fix:** seed a default unit pack (hour, day, each, ft, sq ft) on first catalog entry; add volume/mass; carry the unit through `pricingUnit(for:)`.
3. **No per-unit / piecework pricing on packages & labor.** Deck & Rail ($70/ft, piecework) and Landscaping (per-area, per-sq-ft labor) are both blocked; the data model supports `linearFoot`/`sqft` but the assembly builder hard-codes `.flatRate`. **Fix:** unit picker on the package price card + the labor sheet; drive `pricingUnit` from it.
4. **No variants / tiers on a line.** All four: black/white + 24 vinyl (Deck & Rail), SKU + sizes (Plumbing), Sedan/SUV/Truck (Auto Detailing), lot-size (Landscaping). **Fix:** let a service/good carry option-priced tiers; let create-material attach an option and label variants by option value, not raw SKU.
5. **The offline banner lies.** "Keep moving, saves when back" — but ADD/SAVE is hard-gated on `isOnline` with no queue (Plumbing, Landscaping, Auto Detailing). Field-first violation. **Fix:** queue offline, or change the copy.

### Common gaps (2 of 4)
- **No labeled SKIP** on optional modules (only primary NEXT/FINISH) → users think assembly is mandatory. *(Plumbing, Auto Detailing)*
- **Stock handoff skips the Done payoff + §14 completion notification**, and never clears the draft → next open says "resume?" and re-fires the notification. *(Deck & Rail, Landscaping)*
- **Bulk entry is one-at-a-time; the existing CSV importer isn't surfaced in-flow.** *(Plumbing P0, Deck & Rail P2)*

### Trade-specific
- **Deck & Rail:** stock-vs-ordered-per-job flag; shared-piece dedup (don't duplicate "Top rail" across packages).
- **Plumbing:** SKU field on goods; markup mode (cost ×2); a consumables-only ("shop supplies") bucket.
- **Landscaping:** recurring maintenance has no home — likely belongs in scheduling/contracts, so route out honestly rather than fake it; volume/mass in the stock module.
- **Auto Detailing:** assembly module must honor `trackCost=false` (hide cost/margin); allow a price-only empty package.

### ⚠️ Regressions the audits caught in the current WIP
- **Create-new lost its unit picker.** My add-existing rewrite of `AddAssemblyMaterialSheet` dropped `UnitPickerField` from the "Create new" path — `unitId`/`showingUnitCreate` are now dead and inline materials save **unitless**. *(Landscaping P0-2, Plumbing P3.)* → re-add the picker to `newFields`.
- **BACK from the plan wipes the survey.** The new `goBack()` sends `.plan → .survey(questionIndex: 0)`, and the survey view re-inits fresh `@State`, clearing all answers. *(Auto Detailing P2-2.)* → preserve survey answers, or send plan-back to the last question.

### Suggested fix order
1. **Routing gate** (`sells != .services`) + allow a **price-only package** + **honor `trackCost`** — unblocks the simplest customer and stops mis-routing 3 of 4.
2. **Seed default units** + **re-add the create-new unit picker** (my regression) + carry units through pricing.
3. **Per-unit package & piecework labor** — unblocks Deck & Rail + Landscaping.
4. **Variants / tiers on a line** — wanted by all four.
5. **Offline honesty + labeled SKIP + stock-handoff payoff + finish-clears-draft.**
