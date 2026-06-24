# OPS Decks — Standalone App (Phase 1: Foundation / Carve-Out)

**Date:** 2026-06-24
**Status:** Approved direction (Jackson, 2026-06-24); Phase 1 spec for implementation planning
**Surface:** New standalone iOS app ("OPS Decks") + extraction of the existing deck designer into a shared module + backend (Supabase) reuse
**Related:** `docs/superpowers/specs/2026-06-23-deck-designer-overhaul-design.md` §8 (Future direction); memory `deck-designer-standalone-spinoff`

---

## 1. Context & goal

The OPS iOS app contains a full deck designer (`OPS/DeckBuilder/`, 73 Swift files): a 2D drawing canvas, a JSON geometry model, a SceneKit 3D viewer, AR measuring, photo/sketch scan-to-plan, material assignment, an estimate engine, and a cut-list engine. Today it is reachable only inside a full OPS company workspace, hanging off a `Project`.

**Decision (Jackson):** spin the deck designer out as **OPS Decks** — a standalone iOS app with its own cheaper subscription, usable *without* a full OPS subscription. Two goals at once: (1) a standalone revenue product, and (2) a top-of-funnel wedge that upsells deck contractors into full OPS.

**Why this is fundamentally a re-housing, not a new build:** the deck functionality already exists and works. The novel, risky engineering is the *carve-out* — extracting the designer into a shared module, standing up a second app target, and wiring standalone auth, a "company of one", billing, offline, and the upgrade path. This spec covers **only that foundation (Phase 1)**. Designing the standalone app's actual screens, flows, gating UX, and output polish is **Phase 2** (its own spec → plan cycle, §13).

**Phase 1 success definition:** the *existing* deck designer runs end-to-end as a standalone, signed-in, billed iOS app — a user installs OPS Decks, designs a deck, signs in with Apple, saves it (as their own one-person company), and is correctly gated at the free/Pro boundary — with their data living in the same Supabase backend a full-OPS customer's would, ready to light up the rest of OPS on upgrade.

---

## 2. Locked product decisions (Jackson, 2026-06-24)

| Topic | Decision |
|-------|----------|
| **Brand / listing** | **"OPS Decks"** — an OPS sub-brand with its own App Store listing. Name contains "deck" for App Store search. |
| **Price** | **Free tier:** full functionality, **1 saved deck**. **Pro:** **$14.99/mo or ~$99–119/yr**, unlimited decks. |
| **What's gated** | Gating is purely the **saved-deck count** — the free tier is *fully featured* (design, 3D, AR, priced estimate, cut list, permit PDF) for its 1 deck. No feature is crippled. |
| **Audience** | **Contractors-first**; homeowners (typically one deck) are served by — and convert installs through — the free tier. |
| **Architecture** | One codebase, **two app targets** sharing a module. **No fork.** |
| **Accounts/data** | **"Company of one"** — reuse Firebase auth + the existing Supabase backend + company RLS as-is. |
| **Billing** | **RevenueCat on top of StoreKit 2**, kept distinct from the OPS company subscription. |
| **Onboarding** | Design immediately with **no account**; require **Sign in with Apple** only at first *save* or at the paywall. |
| **Sequencing** | Phase 1 = foundation (this spec). Phase 2 = standalone experience/UX. |

---

## 3. Verified ground truth (live Supabase + code, 2026-06-24)

**`deck_designs` table** (the spine — one row per deck, fully self-contained):

| Column | Type | Null | Note |
|--------|------|------|------|
| `id` | uuid | no | |
| `company_id` | uuid | **no** | scopes the row to a company |
| `project_id` | uuid | **yes** | nil for standalone sketches — already supported |
| `title` | text | no | |
| `drawing_data` | jsonb | no | the entire deck geometry/levels/materials serialized |
| `thumbnail_url` | text | yes | rendered PNG (S3) |
| `version` | int | no | |
| `created_by` | uuid | yes | user id |
| `deleted_at` | timestamptz | yes | soft delete |
| `created_at` | timestamptz | no | |
| `updated_at` | timestamptz | yes | |

**RLS on `deck_designs`:** a single policy `company_isolation` `FOR ALL` with `company_id = private.get_user_company_id()`. A user sees exactly their company's decks — so a company-of-one sees only their own.

**Identity → company resolution** (`private.get_user_company_id()`, `SECURITY DEFINER STABLE`):
```sql
SELECT company_id FROM public.users
WHERE (auth_id = (auth.jwt() ->> 'sub') OR firebase_uid = (auth.jwt() ->> 'sub'))
  AND company_id IS NOT NULL AND deleted_at IS NULL
LIMIT 1
```
So: Firebase `sub` (JWT) → `users` row (`auth_id` or `firebase_uid`) → `users.company_id` → drives every company-scoped RLS policy across the app.

**`companies`** (subscription-relevant): `id`, `name`, `admin_ids[]`, `seated_employee_ids[]`, `max_seats`, `subscription_status`, `subscription_plan`, `subscription_end`, `subscription_period`, `trial_start_date`, `trial_end_date`, `seat_grace_start_date`, `subscription_ids_json`, `created_at`. *(OPS lockout is computed from `trial_end_date`; `subscription_status` is client-immutable; `seated_employee_ids` is admin-guarded — see memory `companies-rls-escalation-fix`.)*

**`users`:** `id`, `company_id` (nullable), `email`, `role`, `auth_id`, `firebase_uid`, `created_at`.

**`DeckDesign` SwiftData model** (`OPS/DataModels/DeckDesign.swift`): mirrors the table + local sync fields (`needsSync`, `lastSyncedAt`, `syncPriority`, `localThumbnailPath`). `projectId` comment literally reads *"nil for standalone sketches."*

**Entry point** (`OPS/DeckBuilder/Views/DeckBuilderView.swift:52`): `init(deckDesign: DeckDesign, modelContext: ModelContext, syncEngine: SyncEngine? = nil)`.

**Coupling surface inside `DeckBuilder/`** (the carve-out work): `companyId` referenced in 14 files, `Project` in 8, `SyncEngine` in 2, `DataController` in 1, `OPSStyle` in 34/73 (styling — shared, not a blocker). **Zero** references to `AppState`, `AuthManager`, `ImageSyncManager` — no app-wide-state coupling.

---

## 4. Architecture: one codebase, two apps

```
OPS.xcworkspace
├─ OPSDesignKit  (Swift package)   ← OPSStyle tokens/components (shared styling)
├─ DeckKit       (Swift package)   ← the entire deck designer, app-agnostic
│     depends on OPSDesignKit
│     exposes protocol seams (DeckStore, ImageUploader, OCRService)
│     knows NOTHING about Project / Company / AppState / the OPS sync engine
├─ OPS           (app target)      ← existing app; depends on DeckKit, supplies OPS-flavored seams
└─ OPS Decks     (app target)      ← NEW thin shell; depends on DeckKit, supplies lean seams
```

**Why a shared module, not a fork:** a fork means every deck bug fix and feature is done twice forever. One module, two thin shells, keeps a single source of truth. This also directly serves the modularity constraint already in flight in the deck overhaul work (pass primitives at the boundary, don't deepen `Project`/`companyId` coupling).

### 4.1 The extraction boundary (the real Phase-1 engineering)

`DeckKit` must take **primitives + protocol seams**, never reach for OPS globals:

- **`companyId: String` and `projectId: String?`** become *parameters* passed in at the boundary (the project-less case is `nil`), replacing the 14-file `companyId` reach and 8-file `Project` reach.
- **`DeckStore` protocol** — the persistence/sync seam. Replaces direct `ModelContext` + `SyncEngine` use. Methods: load/list/save/delete decks, observe changes. OPS supplies an impl backed by its existing `SyncEngine`; OPS Decks supplies a lean impl. **Both talk to the same SwiftData models + the same Supabase backend** — the protocol exists for testability and to keep `DeckKit` app-agnostic, not to create two storage systems.
- **`ImageUploader` protocol** — deck thumbnail + photo-overlay uploads currently go through ops-web presign endpoints (S3 is server-mediated; the app holds no AWS keys). Inject it so OPS Decks points at the same endpoints.
- **`OCRService` protocol** — scan-to-plan's OCR/AI path (`SketchOCR`, `SketchAIFallback`) is injected so the standalone can reach the same backend service (or degrade gracefully).
- **`OPSStyle`** moves to `OPSDesignKit` (or is included in `DeckKit`); both apps and the module share one token source.

**Decision — extraction is mechanical, not a rewrite.** The geometry model, engines (estimate, cut list, stairs, surface detection), 3D builder, AR, and views move into `DeckKit` largely as-is. The work is (a) relocating files into the package, (b) replacing global reaches with injected seams/params, (c) confirming `DeckDesign` + sync models are reachable from both targets. The deck overhaul work (Drops 1–6) continues against `DeckKit` once extracted; sequencing with that in-flight work is a plan concern (§12).

---

## 5. Accounts & data — "company of one"

**Each OPS Decks user is silently their own one-person company in the same Supabase backend.** No new backend, no second database, same RLS.

**Provisioning (on first save / first sign-in):**
1. **Sign in with Apple** → Firebase identity (`sub`).
2. Create a `companies` row (name defaults to the user's name or "My Decks"), `admin_ids = [newUserId]`.
3. Create a `users` row: `firebase_uid`/`auth_id` = Firebase `sub`, `company_id` = the new company, `role` set appropriately.
4. From then on, `get_user_company_id()` resolves their company and RLS isolates their decks automatically — **zero deck-specific RLS changes needed.**

**Keeping deck billing OUT of the OPS subscription machinery (important).** The OPS app computes seat/lockout state from `companies.subscription_status` / `trial_end_date` / `seated_employee_ids`. A deck-only company must **not** trip that logic, and the deck Pro entitlement must not be confused with an OPS subscription. Decisions:
- Mark company-of-one origin with **`subscription_plan = 'decks'`** (or a dedicated `origin` flag) so the OPS app, if ever opened by this user pre-upgrade, recognizes a deck-only company and routes to the upgrade flow rather than treating it as a lapsed OPS trial.
- The **deck Pro entitlement is owned by RevenueCat/App Store**, not `companies.subscription_*`. Server-side, mirror it to a **dedicated `deck_subscriptions` record** (company_id, status, product_id, expires_at, store) via a RevenueCat → ops-web webhook, for web/cross-device visibility and analytics. *(This is the one net-new schema object; it lives outside `companies` precisely to avoid entangling the two products' billing.)*

**The free 1-deck cap is a client/business rule**, enforced via the RevenueCat entitlement (works offline against the cached receipt), not RLS. RLS still does the security job (company isolation); the cap does the monetization job.

---

## 6. Billing & entitlement

- **RevenueCat over StoreKit 2.** RevenueCat handles receipt validation, the free-vs-Pro entitlement, trials, and cross-device "restore purchases." Free under ~$2.5k/mo tracked revenue, then ~1% (§11).
- **Products:** one auto-renewing subscription with monthly ($14.99) and annual (~$99–119) options in one subscription group; a free trial length to be set in Phase 2.
- **Entitlement = `deck_pro`.** Absent → 1 saved deck; present → unlimited. Creating a 2nd deck without `deck_pro` triggers the paywall (Phase 2 UX).
- **Source of truth:** RevenueCat client SDK for gating (offline-tolerant); server mirror (§5) for web/analytics and the upgrade path.

---

## 7. Upgrade path to full OPS (the wedge payoff)

Because both apps share one account and one backend, **upgrading loses nothing**:
- Same **Sign in with Apple** identity → same `users` row → same `company` → **every deck is already present** in full OPS. No data migration.
- Upgrading **converts the deck-only company to a full OPS company**: start an OPS subscription, flip the company off the `'decks'` plan, unlock crew/projects/scheduling/invoicing. Decks are untouched.

**Billing limitation (stated honestly):** Apple does not transfer a subscription between two separate apps; subscription groups are per-app. So moving from OPS Decks Pro to a full OPS subscription is **cancel-one / start-the-other**, not a StoreKit cross-grade. Handle it as an in-app **"Upgrade to OPS"** offer that hands off to the OPS app / web checkout, with a **credit/discount equal to the user's remaining OPS Decks time** so they aren't double-charged. The detailed offer UX is Phase 2; Phase 1 only needs the data/account continuity to be real.

---

## 8. Offline behavior

- **Design works offline.** The deck core is SwiftData-local with a sync queue; estimate and cut-list compute **on-device**. This is the reliability moat the research flagged (rivals bleed 1-star reviews for crashes/lost work).
- **Autosave by default**, local-first. Sync opportunistically when online.
- **First-deck pre-account flow:** a user can design offline before any account; the **save** action is what prompts Sign in with Apple (requires network once). Cache the identity thereafter.
- Image upload / OCR (network features) degrade gracefully offline (queue thumbnail upload; OCR requires connectivity).

---

## 9. App Store & marketing groundwork (Phase 1 scope = the plumbing)

Phase 1 stands up what's structurally required; the *creative* (screenshots, copy, ASO keywords) is Phase 2.

- Separate **App Store Connect** app record + bundle id (e.g. `co.opsapp.ops.decks`), its own provisioning/profiles.
- **Sign in with Apple** capability (Apple requires it where third-party sign-in exists; also lowest-friction).
- **Account deletion in-app** (Apple requirement for account-based apps) — deletes the company-of-one + decks.
- **App Privacy** nutrition labels + privacy policy URL covering deck data, photos, and analytics.
- Subscription products configured in App Store Connect + wired to RevenueCat.
- A placeholder in-app **"This is the design layer of OPS"** upsell surface (full design Phase 2).

---

## 10. What this enables vs. what it is not

**In scope (Phase 1):** `OPSDesignKit` + `DeckKit` packages; the extraction/decoupling; the OPS Decks app target booting the existing designer; Sign in with Apple; company-of-one provisioning; RevenueCat entitlement + 1-deck gate enforcement hook; same-backend sync; offline/autosave; the `deck_subscriptions` mirror + RevenueCat webhook; account deletion; the structural upgrade-to-OPS continuity.

**Out of scope (Phase 2, §13):** the standalone deck **library/home** screen, onboarding-to-first-deck flow, the **paywall** and gating UX, estimate/cut-list/permit-PDF output **tuned for a solo contractor**, material breadth/catalog UX, the full **upgrade-to-OPS** offer UX, ASO/screenshots/marketing copy, and any net-new deck *features*.

---

## 11. Costs (transparency required)

| Item | Cost | Note |
|------|------|------|
| **Apple commission** | **15%** under $1M/yr (Small Business Program), 30% above | At $14.99 you net **~$12.74** (15%) / ~$10.49 (30%). Model unit economics on **net**. |
| **RevenueCat** | Free under ~$2.5k/mo tracked revenue, then **~1%** | Negligible early; ~$0.13 per $14.99 sub once it kicks in. |
| **Supabase Pro** | **$25/mo — HARD PREREQUISITE** | Prod is currently **free-tier with NO backups / no PITR** (see memory `supabase-ops-app-free-tier-no-backups`). Putting paying customers' deck data on an un-backed-up project is unacceptable. **Upgrade before any standalone customer data lands.** |
| **Second-product operating cost** | ongoing, non-trivial | Its own App Review, ASO, marketing spend, support load, and review responses. The most-underestimated cost — it is not "flip a switch." |

Rough net contribution per Pro sub: ~$12.74 (Apple 15%) − ~$0.13 (RevenueCat) ≈ **~$12.60/mo** before support/marketing/infra. Price for installs + the OPS upsell, not early margin.

---

## 12. Risks & pre-launch gates

1. **Stability is the whole ballgame.** The category's defining failure is crashes/lost work. Offline + autosave-by-default + a hard QA bar before launch. Non-negotiable.
2. **Supabase Pro upgrade before any customer data.** Hard gate (§11).
3. **`deck_subscriptions` is the only schema addition** — keep deck billing out of `companies.subscription_*` to avoid OPS lockout entanglement; verify the OPS app tolerates `subscription_plan = 'decks'` companies.
4. **ops-web endpoint authorization for company-of-one.** Confirm the presign/upload and any OCR/AI endpoints authorize a valid Firebase token whose company is a deck-only company (they should — same auth model — but verify in the plan).
5. **In-flight deck overhaul (Drops 1–6) targets the same files.** Extraction into `DeckKit` must be sequenced/coordinated so the two efforts don't collide (parallel-session hazard; see memory). Plan must define order: likely land Drop 1 first, then extract, then continue Drops against `DeckKit`.
6. **Competitive window (RedX).** Cheap, deck-native, multi-platform; if they add AR/vinyl the window narrows — move deliberately but don't dawdle.
7. **Cheap insurance:** a manual logged-in pass through r/Decks + deck Facebook groups to confirm demand depth (research's strongest "I want this" quotes were Reddit, which blocks automated reading). Recommended before heavy Phase 2 build; does not block Phase 1 plumbing.
8. **Apple compliance:** Sign in with Apple + in-app account deletion + App Privacy are required for an account-based subscription app.

---

## 13. Phase 2 preview (not part of this spec)

Phase 2 = the standalone **experience**: deck library/home, onboarding-to-first-value, paywall + gating UX, the priced estimate / cut list / permit PDF presented for a solo contractor, material catalog UX, the OPS upsell offer, and all ASO/marketing creative. It gets its own brainstorming → spec → plan cycle (`STANDALONE DECK DESIGNER - P2`) once the Phase 1 foundation stands.

---

## 14. Open questions for the plan (not the spec)

- Exact `DeckStore` / `ImageUploader` / `OCRService` protocol surfaces (derived from a full functionality inventory at plan time).
- Whether `OPSDesignKit` is a separate package or `OPSStyle` is vendored into `DeckKit`.
- Bundle id, App Store Connect setup specifics, subscription group naming.
- `deck_subscriptions` exact columns + the RevenueCat webhook → ops-web endpoint contract.
- Sequencing against the in-flight deck-overhaul Drops.
