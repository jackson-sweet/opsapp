# BOOKS Tab — Phase 2 Design Spec (Ship-Ready Completion)

> ⚠️ **STATUS: DEFERRED — pending rewrite (2026-05-11, user choice — option B).**
>
> This spec was written assuming Phase 1's 4-segment Books hub stays in place. After it landed, two parallel-session designs surfaced:
> - `2026-05-11-books-ui-reconstruction-design.md` — replaces the 4-segment hub with a swipeable 5-card hero carousel + 3 segments (Invoices/Estimates/Expenses); **removes Pipeline from Books entirely**.
> - `2026-05-11-pipeline-tab-design.md` — promotes Pipeline to a standalone top-level LEADS tab.
>
> User picked option B: **Pipeline-tab → Reconstruction → leaner Phase 2.** When this spec is resumed:
> 1. Verify HEAD has both Pipeline-tab + Reconstruction merged. The Books shell will look fundamentally different.
> 2. Chunks 2A (InvoiceFormSheet), 2B (PaymentRecordSheet refactor), 2F (segment-scoped search) survive mostly intact — they touch the Books Invoices/Estimates segments which exist in both shapes.
> 3. Chunks 2C (per-company stages), 2D (AI lead fields), 2E (lead images + lat/lng), 2G (import contacts) need their file paths retargeted from `OPS/Views/Books/Pipeline/` to `OPS/Views/Leads/` and view-model paths checked against the post-Reconstruction `MoneyDashboardViewModel`.
> 4. Chunk 2C's `MoneyDashboardViewModel` extension to load opportunities is mooted — Reconstruction reshapes that VM and Pipeline data goes elsewhere. The per-company `pipeline_stage_configs` refactor itself stays valid (slug-based storage, registry pattern, server-side seed trigger).
>
> Do NOT execute this spec or its plan until the rewrite is complete. The plan file (`2026-05-11-books-tab-phase-2-implementation.md`) carries the same warning.

| | |
|---|---|
| **Date** | 2026-05-11 |
| **Status** | Deferred pending rewrite (see banner above) |
| **Scope** | iOS only (`ops-ios/`) |
| **Builds on** | Phase 1 spec (`2026-05-07-books-tab-design.md`) — assumes all Phase 1 commits in HEAD |
| **Phase** | 2 of 2 — final phase before customer-facing release |
| **Goal** | Bring the BOOKS tab to **100% feature-complete** for ship: close the dead FAB TODOs, retrofit per-company stage customization, and ship the deferred Pipeline UX surfaces (AI fields, images, location, search, contact import). |

## 1. Summary

Phase 1 shipped the BOOKS hub shell + Pipeline section + dashboard extensions but deferred 6 surface items per spec §16, plus left drift item #15 (per-company `pipeline_stage_configs`) explicitly unresolved as "Phase 3 work." Phase 2 collapses the timeline: ship 100% of those surfaces in a single phase, broken into **7 sequential chunks** sized for fresh-agent worktree sessions (~500k tokens each).

The defining constraint: this is the last code phase before customer launch. Anything left half-built becomes a launch blocker, not a follow-up.

## 2. Why one big phase, not three small ones

The earlier "Phase 2 / Phase 3" framing assumed shippable iteration — Phase 2 launches BOOKS, Phase 3 retrofits per-company stages later. The user's directive ("100% before we ship, regardless of how long it takes") inverts that: **nothing customer-facing ships until everything is done**.

That makes the Phase 2/Phase 3 split artificial. Customers who use stage customization on web today (a verified live feature per `pipeline_stage_configs`) cannot encounter an iOS app that ignores their customization. So the per-company stages refactor MUST land before launch — which means it's "Phase 2" by definition.

Result: one Phase 2 spec covering everything; one implementation plan; sequential chunks each spawned as a fresh agent worktree.

## 3. Chunk overview

| Chunk | Surface | Est. tasks | Risk | Depends on |
|---|---|---|---|---|
| **2A** | InvoiceFormSheet | ~10 | Low (mirrors EstimateFormSheet) | Phase 1 only |
| **2B** | PaymentRecordSheet refactor (FAB-spawn variant) | ~5 | Low | Phase 1 only |
| **2C** | Per-company `pipeline_stage_configs` (drift #15 retrofit) | ~10 | **High** (PipelineStage refactor across many consumers) | 2A, 2B |
| **2D** | AI lead fields read-side | ~4 | Low (additive) | 2C |
| **2E** | Lead images + lat/lng | ~6 | Medium (Storage upload + CoreLocation) | 2C |
| **2F** | Segment-scoped search | ~3 | Low | Phase 1 only |
| **2G** | Import contacts → leads | ~5 | Low–Medium (bulk create flow) | 2C |

**Ordering rationale:**
- **2A and 2B first** — visible wins, unblock the dead FAB TODOs, no Pipeline coupling
- **2C in the middle** — refactor the stage data layer BEFORE 2D/2E/2G build on top of it. Doing 2C last would force re-touching every Pipeline-data consumer added in 2D/2E/2G
- **2D, 2E, 2G after 2C** — they extend Opportunity-related UI that may reference stage data
- **2F can slot anywhere** — independent of Pipeline; placed at low-risk position late in sequence

Each chunk produces shippable, testable software on its own (excepting 2C, which is a single coherent refactor — no partial state).

## 4. Chunk 2A — InvoiceFormSheet

### 4.1 Scope

Build a modal sheet for creating new invoices, mirroring `EstimateFormSheet.swift` (the established pattern). Wire into FAB MONEY group's currently-dead `// TODO: Wire up when InvoiceFormSheet is implemented` slot.

### 4.2 Schema parity (verified live 2026-05-11)

`invoices` table NOT NULL columns: `id, company_id, client_id, invoice_number, issue_date, due_date, status, amount_paid, balance_due, deposit_applied, discount_amount, tax_amount, total, subtotal, created_at, updated_at`.

**Invoice number generation:** Verified — `get_next_document_number(p_company_id uuid, p_type text)` RPC exists, supports `'invoice'`, returns format `INV-YYYY-NNNNN`. Atomic via UPDATE...RETURNING. iOS calls this before insert.

### 4.3 Files to create

| Path | Responsibility |
|---|---|
| `OPS/Views/Invoices/InvoiceFormSheet.swift` | Modal form: client picker, line items, discount/tax, due date, payment terms, internal notes. Mirror EstimateFormSheet structure. |
| `OPS/Views/Invoices/InvoiceLineItemEditSheet.swift` | Per-line-item editor (only if EstimateFormSheet's `LineItemEditSheet` isn't reusable; verify first). |

### 4.4 Files to modify

| Path | Change |
|---|---|
| `OPS/Network/Supabase/DTOs/InvoiceDTOs.swift` | **Add `CreateInvoiceDTO`** (does NOT exist today — verified 2026-05-11 grep). Required-field set matches schema NOT NULLs. Pre-compute `subtotal`, `tax_amount`, `discount_amount`, `total`, `balance_due` client-side; server triggers handle `amount_paid`/`deposit_applied`. Mirror `CreateEstimateDTO`'s shape. Also add `CreateInvoiceLineItemDTO` (line items table is the same `line_items` used by estimates — verify the existing `CreateLineItemDTO` works for both contexts; if not, add a parallel `CreateInvoiceLineItemDTO`). |
| `OPS/Network/Supabase/Repositories/InvoiceRepository.swift` | **Add `create(_:)`** (does NOT exist today — verified; current methods are `fetchAll/fetchDeletedIds/fetchOne/recordPayment/updateStatus/voidInvoice` only). Two-step: (1) RPC `get_next_document_number(companyId, "invoice")`, (2) INSERT invoice row with returned number. Then INSERT line items in a follow-up batch. **Note:** `EstimateRepository.create()` does a one-step insert today (no number RPC call) — investigate whether estimates rely on a database default we missed, an undocumented trigger, or a silent-bug situation. Chunk 2A's first task must resolve this before mirroring the pattern. |
| `OPS/Views/Components/FloatingActionMenu.swift:832-833` | Replace `// TODO: Wire up when InvoiceFormSheet is implemented` + commented `.sheet(...)` with active wiring: `.sheet(isPresented: $showingCreateInvoice) { InvoiceFormSheet(viewModel: invoiceViewModel) }`. |

### 4.5 Form fields

Same field set as `EstimateFormSheet` minus payment milestones (invoices are billed-upon-creation, not staged):

| Section | Fields |
|---|---|
| Client | Picker (existing `ContactPicker` for clients) — required |
| Project link | Optional picker — defaults to nil |
| Estimate link | Optional — if user is creating from an estimate context, prefill |
| Line items | Use existing `LineItemEditSheet` + `ProductPickerSheet` from estimates |
| Pricing | Subtotal (computed), discount (% or fixed), tax rate, total (computed) |
| Dates | Issue date (default today), due date (default today + payment_terms days) |
| Payment terms | Picker from existing `PaymentTerms` enum (Net 15 / Net 30 / Net 60 / Due on receipt / custom) |
| Notes | Subject, client_message, internal_notes |
| Footer / Terms | Free text |

### 4.6 States

- **Loading:** standard `TacticalLoadingBarAnimated` while submitting.
- **Empty (no clients):** "ADD A CLIENT FIRST" empty state with CTA to existing client-create flow.
- **Validation errors:** inline red helper text under offending field; submit button disabled until valid.
- **Save error:** inline error banner with retry.
- **Offline:** queue insert via existing `SyncEngine`; show pending in top status indicator.

### 4.7 Interactions

- Submit → calls `InvoiceRepository.create(...)` → on success post `Notification("InvoiceCreatedSuccess")` and dismiss.
- `BooksTabView` Pipeline-section pattern: subscribe to that notification → reload `InvoiceViewModel` if Invoices segment active.

### 4.8 Acceptance criteria (chunk-level)

- [ ] FAB → New Invoice opens the sheet (no longer commented-out)
- [ ] Submit creates a row in `invoices` with auto-numbered `invoice_number` (verify in Supabase)
- [ ] All NOT NULL columns populated
- [ ] Line items written to `line_items` linked by `invoice_id`
- [ ] InvoicesListView (BOOKS Invoices segment) refreshes to show the new row
- [ ] All visual tokens use OPSStyle (no `cardBackgroundDark`)
- [ ] No `OPSStyle.Animation.spring` use

---

## 5. Chunk 2B — PaymentRecordSheet refactor

### 5.1 Scope

Refactor existing `PaymentRecordSheet.swift` to support **two contexts**:
1. **Invoice-context** (existing) — invoked from `InvoiceDetailView` with a known `Invoice`
2. **No-context** (new) — invoked from FAB "New Payment" action; user picks invoice first, then enters payment

Single sheet, single struct. The FAB TODO comment that referenced "RecordPaymentSheet" was misleading — there's no separate struct needed.

### 5.2 Schema parity (verified live)

`payments` table NOT NULL: `id, invoice_id, client_id, company_id, amount, payment_date, created_at`. `invoice_id` NOT NULL means we MUST have an invoice before insert — no "orphan payment" support.

### 5.3 Files to modify

| Path | Change |
|---|---|
| `OPS/Views/Invoices/PaymentRecordSheet.swift` | Change `let invoice: Invoice` → `let invoice: Invoice?` (optional). When nil, render `InvoicePickerSection` first; once user picks, transition into the existing form. Wire dismiss + cancel correctly across both states. |
| `OPS/Views/Components/FloatingActionMenu.swift:834-835` | Replace `// TODO: Wire up when RecordPaymentSheet is implemented` with active wiring: `.sheet(isPresented: $showingRecordPayment) { PaymentRecordSheet(invoice: nil, viewModel: invoiceViewModel) }`. |

### 5.4 New invoice-picker section

When `invoice == nil`:

```
┌─────────────────────────────────┐
│  PICK AN INVOICE                │
│  ┌───────────────────────────┐  │
│  │ search … (existing)        │  │
│  └───────────────────────────┘  │
│  • INV-2026-00012  Devlin       │
│    Balance: $24,000              │
│  • INV-2026-00010  Anderson     │
│    Balance: $8,500               │
│  • [more, scrollable]           │
└─────────────────────────────────┘
```

Source: filter `InvoiceViewModel.invoices` to `balance_due > 0 && status != .void && status != .paid`. Sorted: largest balance first.

Tap a row → transitions to the existing form, prefilled with that invoice. Back button returns to picker.

### 5.5 Acceptance criteria

- [ ] InvoiceDetailView "Record Payment" still opens the sheet with invoice prefilled (no regression)
- [ ] FAB → New Payment opens the sheet with invoice picker first
- [ ] Picker excludes paid/void invoices and zero-balance invoices
- [ ] After payment recorded, both contexts dismiss correctly + post `Notification("PaymentRecordedSuccess")`
- [ ] BOOKS Invoices segment refreshes balance counts after payment
- [ ] All visual tokens use OPSStyle

---

## 6. Chunk 2C — Per-company `pipeline_stage_configs` retrofit (drift #15)

### 6.1 Scope

Replace the hardcoded `PipelineStage` enum with a **data-driven stage model** loaded from `pipeline_stage_configs` per company. Touches every consumer of `PipelineStage` across iOS:
- `OPS/DataModels/Enums/PipelineStage.swift` — refactor target
- `OPS/Views/Books/Pipeline/StageStripView.swift` — consumer
- `OPS/Views/Books/Pipeline/PipelineSectionView.swift` — consumer
- `OPS/Views/Books/Pipeline/LeadCardView.swift` — consumer
- `OPS/Views/Books/Pipeline/LeadDetailView.swift` — consumer
- `OPS/Views/Books/Pipeline/EditLeadSheet.swift` — consumer
- `OPS/Views/Books/Pipeline/LeadActionSheet.swift` — consumer
- `OPS/Views/Books/Pipeline/AddLeadSheet.swift` — initial stage
- `OPS/ViewModels/PipelineViewModel.swift` — counts, weighted forecast, stale checks
- `OPS/ViewModels/MoneyDashboardViewModel.swift` — pipeline carousel stats
- `OPS/DataModels/Supabase/Opportunity.swift` — `weightedValue`, `daysInStage`, `isStale`
- `OPS/DataModels/Supabase/StageTransition.swift` — fromStage/toStage
- `OPS/Network/Supabase/Repositories/OpportunityRepository.swift` — moveToStage, markWon, markLost
- `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift` — toModel mapping
- `OPSTests/Pipeline/PipelineViewModelTests.swift` — fixture stages

### 6.2 Schema (verified live)

`pipeline_stage_configs` per company: `id, company_id, slug (NOT NULL), name (NOT NULL), color (NOT NULL), icon, sort_order (NOT NULL), default_win_probability, stale_threshold_days, auto_follow_up_days, auto_follow_up_type, is_won_stage, is_lost_stage, is_default, deleted_at, created_at`.

A company that hasn't customized has 8 default rows seeded matching the current hardcoded enum (`new_lead, qualifying, quoting, quoted, follow_up, negotiation, won, lost`).

### 6.3 New iOS architecture

Replace the **enum** with a **struct + repository** pattern:

```swift
struct PipelineStage: Identifiable, Hashable, Codable {
    let id: String                       // pipeline_stage_configs.id (UUID)
    let companyId: String
    let slug: String                     // "new_lead" etc — stable identifier for transitions
    let name: String                     // display name — may differ from slug
    let color: String                    // hex
    let icon: String?
    let sortOrder: Int
    let defaultWinProbability: Int       // 0..100
    let staleThresholdDays: Int
    let autoFollowUpDays: Int?
    let autoFollowUpType: String?
    let isWonStage: Bool
    let isLostStage: Bool

    var displayName: String { name.uppercased() }
    var isTerminal: Bool { isWonStage || isLostStage }
    var winProbability: Int { defaultWinProbability }
}
```

**`PipelineStageRegistry`** — singleton-style cache on `DataController` or a new `StageConfigRepository`:

```swift
@MainActor
final class PipelineStageRegistry: ObservableObject {
    @Published private(set) var stages: [PipelineStage] = []

    func load(for companyId: String) async throws { ... }   // SELECT from pipeline_stage_configs
    func stage(slug: String) -> PipelineStage?
    func stage(id: String) -> PipelineStage?
    func activeStages() -> [PipelineStage]                  // !isTerminal, sorted by sortOrder
    func terminalStages() -> [PipelineStage]                // isWonStage || isLostStage
    func wonStage() -> PipelineStage?                       // first isWonStage
    func lostStage() -> PipelineStage?                      // first isLostStage
    func nextStage(after slug: String) -> PipelineStage?    // by sortOrder
}
```

Refresh strategy: load on app launch (after auth), cache for the session. Invalidate + reload on:
- App foregrounded (if last load > 5min ago)
- Realtime subscription event on `pipeline_stage_configs`
- Manual user action (pull-to-refresh)

### 6.4 Migration of consumers

Every existing reference to `PipelineStage.someCase` becomes:
- For static slug lookup: `stageRegistry.stage(slug: "new_lead")` (returns optional)
- For "next stage": `stageRegistry.nextStage(after: opportunity.stage.slug)`
- For terminal check: `opportunity.stage.isTerminal` (now stored on the struct)

`Opportunity.stage` storage: change from `var stage: PipelineStage` (enum) to `var stageSlug: String` (the durable identifier from `pipeline_stage_configs.slug`). Computed accessor:

```swift
extension Opportunity {
    var stage: PipelineStage? { PipelineStageRegistry.shared.stage(slug: stageSlug) }
}
```

Why slug-as-storage: stages can be renamed (config row updated) without rewriting opportunity rows. The slug is the stable join key; the display name is mutable.

`StageTransition.fromStage`/`toStage`: same — store as slug strings, not enum.

### 6.5 Default-stages seeding (one-time)

For companies that have NO `pipeline_stage_configs` rows, the registry must seed the 8 defaults. Two places this can happen:
1. Server-side: a trigger on `companies` INSERT that seeds the 8 defaults (clean, but needs a migration)
2. Client-side: registry detects empty result, INSERTs 8 default rows on first load

**Decision: server-side trigger.** Cleaner, atomic, doesn't race across concurrent client logins. Requires a new migration (Chunk 2C task).

### 6.6 Files

| Action | Path |
|---|---|
| **Create** | `OPS/DataModels/Pipeline/PipelineStageRegistry.swift` |
| **Create** | `OPS/DataModels/Pipeline/PipelineStage.swift` (replaces existing enum) |
| **Create** | `OPS/Network/Supabase/Repositories/PipelineStageConfigRepository.swift` |
| **Create** | `OPS/Network/Supabase/DTOs/PipelineStageConfigDTOs.swift` |
| **Create** | `ops-software-bible/migrations/2026-05-11-01-seed-default-pipeline-stages.sql` (trigger + backfill for existing companies that lack rows) |
| **Delete** | `OPS/DataModels/Enums/PipelineStage.swift` (old enum file) |
| **Modify** | All 13 consumers listed in §6.1 |
| **Modify** | `OPS/Utilities/DataController.swift` — add `stageRegistry` property + invoke `load()` after auth |

### 6.7 States & errors

- **Stage data fails to load:** show a banner "STAGES UNAVAILABLE — RETRY" at the top of Pipeline section. All Pipeline UI gated on `!stageRegistry.stages.isEmpty` to avoid empty-strip rendering.
- **Won/Lost both unset:** if a customized config has no `is_won_stage = true` row, "Mark Won" action is disabled with a tooltip "No 'Won' stage configured". Same for Lost.
- **Stage reordered while user is mid-task:** re-sort visible UI on next render; in-progress stage move continues against the slug (which is stable).

### 6.8 Acceptance criteria

- [ ] Hardcoded `PipelineStage` enum is gone
- [ ] iOS reads `pipeline_stage_configs` from Supabase on app launch
- [ ] Default-companies (no custom stages) get the 8 seeded defaults via server trigger
- [ ] Stage strip renders custom stage names + colors when company has customized
- [ ] Stage move via inline chip uses slug for atomic RPC (the `move_opportunity_stage` RPC's `to_stage` arg is a slug string — no enum coupling)
- [ ] Stale threshold respects per-stage `stale_threshold_days` (per-company override)
- [ ] Win probability respects per-stage `default_win_probability`
- [ ] All Phase 1 tests still pass (PipelineViewModelTests adapted to new model)
- [ ] No regression: a company that hasn't customized sees identical behavior to Phase 1

---

## 7. Chunk 2D — AI lead fields (read-side)

### 7.1 Scope

Display the AI-generated fields that web populates on opportunities. iOS does NOT run AI itself — purely read + display.

### 7.2 Fields (additive to Opportunity model)

Per Supabase schema verified in Phase 1 §10.1 deferred items:
- `ai_summary: String?` (text)
- `ai_stage_confidence: Double?` (double precision; 0..1)
- `ai_stage_signals: [String]?` (text array)
- `detected_value: Int?` (integer)

### 7.3 Files

| Action | Path |
|---|---|
| Modify | `OPS/DataModels/Supabase/Opportunity.swift` — add 4 properties |
| Modify | `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift` — add to `OpportunityDTO` + `toModel()` |
| Modify | `OPS/Views/Books/Pipeline/LeadDetailView.swift` — add "AI SUMMARY" section between header and quick actions when `aiSummary != nil` |
| Modify | `OPS/Views/Books/Pipeline/LeadCardView.swift` — add a small confidence badge next to the stage (e.g. "92%" pill, only when `aiStageConfidence > 0.7`) |

### 7.4 Visual treatment

AI summary section:

```
┌─────────────────────────────────┐
│ 🤖 AI SUMMARY                    │
│ ┌─────────────────────────────┐ │
│ │ Customer is comparing 3      │ │
│ │ quotes; price-sensitive;    │ │
│ │ wants completion by Jun 15. │ │
│ │                              │ │
│ │ Confidence: 92% · Signals:  │ │
│ │ price, urgency, alternatives│ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

- AI-summary card uses `OPSStyle.Colors.cardBackground` + a 1pt left border in `OPSStyle.Colors.primaryAccent` to mark it as AI-generated content (subtle distinction from user-authored notes).
- Confidence + signals shown as inline metadata.
- "🤖" emoji is the only allowed visual marker for AI content (matches OPS brand: "Numbers always JetBrains Mono, no decorative icons" — but emoji as content type signal is permitted in this constrained case; note: confirm during spec review whether to use emoji or a Lucide icon instead).

### 7.5 Acceptance criteria

- [ ] LeadDetailView shows AI summary section when `aiSummary` is non-nil
- [ ] Section hides cleanly when nil (no empty card)
- [ ] LeadCardView shows confidence badge when `aiStageConfidence > 0.7`
- [ ] All visual tokens use OPSStyle
- [ ] iOS does NOT write to any AI field (read-only)

---

## 8. Chunk 2E — Lead images + lat/lng

### 8.1 Scope

Add image attachment + geolocation to leads. Used for: site visit photos, address marker on map, etc.

### 8.2 Fields (additive)

- `images: [String]` (text array of Supabase Storage paths) — defaults to `[]`
- `latitude: Double?` (double precision)
- `longitude: Double?` (double precision)

### 8.3 Files to create

| Path | Responsibility |
|---|---|
| `OPS/Services/LeadImageUploader.swift` | Mirror `ProductThumbnailUploader.swift` pattern — upload to Supabase Storage bucket, return path. |
| `OPS/Views/Books/Pipeline/LeadImageGallery.swift` | Horizontal-scroll gallery on LeadDetailView; tap → full-screen viewer (existing `FullScreenReceiptViewer` pattern). |
| `OPS/Views/Books/Pipeline/LeadLocationMap.swift` | Mini map view on LeadDetailView showing pin at lead's lat/lng. Uses `MapKit` (already imported in MainTabView). |

### 8.4 Files to modify

| Path | Change |
|---|---|
| `OPS/DataModels/Supabase/Opportunity.swift` | Add `images: [String]`, `latitude: Double?`, `longitude: Double?` |
| `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift` | Add to DTOs + `toModel()` mapping |
| `OPS/Views/Books/Pipeline/AddLeadSheet.swift` | Add image picker section + "Capture Location" button |
| `OPS/Views/Books/Pipeline/EditLeadSheet.swift` | Same |
| `OPS/Views/Books/Pipeline/LeadDetailView.swift` | Add gallery + map sections (between AI summary and quick actions) |

### 8.5 Image upload flow

1. User taps "+ ADD IMAGE" in AddLeadSheet — `PHPickerViewController` opens
2. User selects 1+ images
3. Each is uploaded via `LeadImageUploader.upload(image:)` → returns Storage path
4. Paths are appended to local `images: [String]` state
5. On submit, `images` is included in `CreateOpportunityDTO`

**Mirror the verified `ProductThumbnailUploader.swift` pattern (2026-05-11):**
- New bucket: `lead-images` — Chunk 2E task creates the migration with read/write policies (mirror `2026-05-08-product-thumbnails-storage-policy.sql`)
- Object naming: `{companyId}/{opportunityId}/{UUID().uuidString}.jpg`
- Resize to max 1024px long edge before upload
- JPEG quality 0.85
- Static `.shared` singleton with its own `LeadImageUploadError` enum
- Note for the new-lead case: opportunity ID isn't yet known on Add — solution: upload images AFTER the opportunity is created (two-step: create opp → upload images → PATCH `images` column with the returned paths). Edit-flow has the opp ID already, no two-step needed.

### 8.6 Location capture flow

`LocationManager` API verified — exposes `requestPermissionIfNeeded(requestAlways:completion:)` + `var location: CLLocation?` (no `requestLocation()` async function). Flow:

1. User taps "📍 CAPTURE LOCATION" in AddLeadSheet
2. Call `LocationManager.shared.requestPermissionIfNeeded(requestAlways: false) { granted in ... }`
3. On grant, observe `locationManager.location` (or use a small async wrapper that awaits a published-value change with timeout)
4. Pull latitude/longitude from `CLLocation.coordinate`
5. Visible feedback: "Location captured: 37.7749, -122.4194" with a small map preview
6. Manual override: tap the captured-location row → opens a new `MapPickerSheet` (no existing precedent — Chunk 2E task creates a minimal one using `MapKit`'s `Map` with a draggable annotation)
7. On submit, lat/lng included in `CreateOpportunityDTO`

### 8.7 LeadDetailView additions

After AI summary, before quick actions:

```
┌─────────────────────────────────┐
│ IMAGES (3)                       │
│ [img] [img] [img] [+]           │  ← horizontal scroll, tap → fullscreen
├─────────────────────────────────┤
│ LOCATION                         │
│ 🗺  ┌──────────────────────────┐ │  ← MapKit Map view, ~120pt tall
│    │  [pin]                    │ │
│    └──────────────────────────┘ │
│ 123 Main St (if address set)    │  ← address text below map
└─────────────────────────────────┘
```

### 8.8 Acceptance criteria

- [ ] Add Lead sheet supports adding 1+ images via `PHPickerViewController`
- [ ] Add Lead sheet supports capturing current location via `LocationManager`
- [ ] LeadDetailView shows image gallery (horizontal scroll) when `images.isNotEmpty`
- [ ] LeadDetailView shows map with pin when `lat/lng` set
- [ ] Edit Lead sheet supports adding/removing images + re-capturing location
- [ ] Image upload progress shown via `OPSStyle.Animation.standard` opacity transitions; no spring
- [ ] All visual tokens use OPSStyle

---

## 9. Chunk 2F — Segment-scoped search

### 9.1 Scope

Today: AppHeader's magnifying glass calls `appState.showingUniversalSearch = true` → `UniversalSearchSheet` opens with global scope. Inside BOOKS, this should narrow to the active segment's data only.

### 9.2 Files to modify

| Path | Change |
|---|---|
| `OPS/Views/JobBoard/UniversalSearchSheet.swift` | Add `var scope: SearchScope = .global` parameter. `enum SearchScope { case global, books(BooksSection) }`. Filter results by scope. |
| `OPS/Utilities/AppState.swift` | Add `var pendingSearchScope: SearchScope?` so the AppHeader → AppState → BooksTabView path can pass scope. |
| `OPS/Views/Books/BooksTabView.swift` | Override the magnifying glass tap — set `appState.pendingSearchScope = .books(currentSegment)` before triggering `showingUniversalSearch`. |
| `OPS/Views/Components/Common/AppHeader.swift` | Read `pendingSearchScope` and pass into the sheet on present. |

### 9.3 Search routing per segment

| Segment | Searches |
|---|---|
| Pipeline | Opportunities (title, contact_name, contact_email, contact_phone, address, ai_summary) |
| Estimates | Estimates (estimate_number, title, client_message, internal_notes) |
| Invoices | Invoices (invoice_number, subject, internal_notes) |
| Expenses | Expenses (description, merchant_name, notes) |

### 9.4 Acceptance criteria

- [ ] AppHeader magnifying glass on BOOKS tab opens search scoped to active segment
- [ ] Same magnifying glass on other tabs still opens global search (no regression)
- [ ] Scope indicator visible in search sheet header (e.g. "Searching Pipeline…")
- [ ] All other tabs and entry points unchanged

---

## 10. Chunk 2G — Import contacts → leads

### 10.1 Scope

Bulk-create leads from device Contacts. Surfaced as the previously-greyed CTA in Pipeline-empty state, AND as a button in AddLeadSheet's overflow menu for mid-pipeline imports.

### 10.2 Files to create

| Path | Responsibility |
|---|---|
| `OPS/Views/Books/Pipeline/ImportContactsSheet.swift` | Multi-select contact picker → preview → bulk create |
| `OPS/ViewModels/ContactImportViewModel.swift` | Orchestrate batch CreateOpportunityDTO inserts with progress |

### 10.3 Files to modify

| Path | Change |
|---|---|
| `OPS/Views/Books/Pipeline/PipelineSectionView.swift` | Activate the "import contacts" CTA in the Pipeline-empty state (was greyed in Phase 1) |
| `OPS/Views/Books/Pipeline/AddLeadSheet.swift` | Add a "📲 Import from Contacts" button in the toolbar |
| `OPS/Info.plist` | Add `NSContactsUsageDescription` if not already present |

### 10.4 Flow

1. User taps "Import from Contacts"
2. `CNContactStore.requestAccess` — if denied, show actionable error with link to Settings
3. Open existing `ContactPicker` (or a new multi-select variant)
4. User selects N contacts → preview list of "leads to create" with editable contact name + estimated value
5. Tap "CREATE N LEADS" → batch insert via `OpportunityRepository.create(_:)` in a loop with progress indicator
6. On completion, dismiss + post `Notification("LeadCreatedSuccess")` (one notification per insert OR a single batch notification — pick one)

### 10.5 Bulk-create error handling

- Each lead creation is independent — if one fails, the rest continue
- Failed leads accumulate in a "X COULD NOT IMPORT" footer with retry option
- Progress: "Creating 3 of 10…" with `TacticalLoadingBarAnimated`

### 10.6 Acceptance criteria

- [ ] Pipeline-empty state's "Import contacts" CTA is now active (was greyed in Phase 1)
- [ ] AddLeadSheet has "Import from Contacts" toolbar button
- [ ] Contacts permission requested with clear NSContactsUsageDescription
- [ ] Multi-select picker allows selecting any number of contacts
- [ ] Preview step is editable
- [ ] Bulk create writes all opportunities in the **company's first non-terminal stage** by `sortOrder` (typically the seeded "new_lead" — but registry-resolved, not hardcoded post-2C)
- [ ] Pipeline section refreshes on completion
- [ ] All visual tokens use OPSStyle

---

## 11. Schema parity & RPC additions (consolidated)

| New | Purpose | Applies to chunk |
|---|---|---|
| Migration `2026-05-11-01-seed-default-pipeline-stages.sql` — trigger on `companies` INSERT to seed 8 defaults; backfill existing companies with no rows | Per-company stage retrofit | 2C |
| (No new RPCs) — existing `get_next_document_number`, `move_opportunity_stage`, `recordPayment` cover everything | — | All |

| Verified live (no work needed) |
|---|
| `invoices` table — 39 cols including all NOT NULL needed for InvoiceFormSheet |
| `payments` table — 15 cols, `invoice_id` NOT NULL constrains payment-without-invoice |
| `pipeline_stage_configs` — 15 cols, full per-company customization surface |
| `opportunities.images` (text[]), `latitude`/`longitude` (double precision) — additive iOS read |
| `opportunities.ai_summary`, `ai_stage_confidence`, `ai_stage_signals`, `detected_value` — exist; iOS additive read |
| `get_next_document_number(p_company_id, p_type)` RPC — covers `'invoice'` |

## 12. Drift register (Phase 2)

Tracked here so a future PM/agent knows what was discovered during this spec.

| # | Drift | Resolution |
|---|---|---|
| 1 | iOS `Opportunity.stage` is a Swift enum; should be a slug-based reference to per-company config | RESOLVES in 2C — refactor to `stageSlug: String` + registry lookup |
| 2 | iOS hardcodes 8 stages; web supports per-company custom stages via `pipeline_stage_configs` | RESOLVES in 2C |
| 3 | `PaymentRecordSheet.invoice` is required; FAB needs no-context variant | RESOLVES in 2B — make optional + add picker |
| 4 | Opportunity model lacks AI fields, images, lat/lng | RESOLVES in 2D + 2E |
| 5 | UniversalSearchSheet is global-scope only; no segment narrowing | RESOLVES in 2F |
| 6 | Pipeline-empty state's "import contacts" CTA was greyed in Phase 1 | RESOLVES in 2G |
| 7 | FAB `// TODO: Wire up when InvoiceFormSheet is implemented` | RESOLVES in 2A |
| 8 | FAB `// TODO: Wire up when RecordPaymentSheet is implemented` | RESOLVES in 2B |
| 9 | iOS `archive`/`unarchive` opportunity API has no web parity | **STAYS OPEN** — flag for web team; not iOS scope |
| 10 | `pipeline_stage_configs` lacks server-side seed trigger for new companies | RESOLVES in 2C migration |

## 13. Bible updates required (when this ships)

When Phase 2 lands, update `ops-software-bible/09_FINANCIAL_SYSTEM.md`:

- §9.85 (Opportunity Entity, line 85) — append AI fields, images, lat/lng to the iOS-parity paragraph
- §9.66 (Pipeline Stages, line 66) — note iOS now reads `pipeline_stage_configs` per-company; rewrite the static "8 ordered stages" paragraph to reference the registry pattern
- §9.83 (Per-company stage configuration, around the same area) — note iOS parity achieved, link to migration `2026-05-11-01`
- §9.174 (Stage Transitions, line 174) — note slug-based storage on iOS post-2C
- §9 InvoiceService — add iOS `InvoiceRepository.create(...)` to equivalence table (added in 2A)
- §9 PaymentService — note iOS `PaymentRecordSheet` now supports both invoice-context and standalone modes
- New "iOS BOOKS Phase 2 (May 2026)" subsection summarizing all 7 chunks

## 14. Animation & motion

Most of Phase 2 is form sheets + read-side displays — minimal new motion. Constraints same as Phase 1:

- Only `OPSStyle.Animation.standard` (cubic-bezier curve) and `.fast` (easeInOut 0.2)
- **No `.spring`** — no exception in this phase
- Form-sheet presentations use SwiftUI's default sheet transitions (no override)
- Image upload progress: opacity crossfade only
- Map appearance in LeadDetailView: implicit MapKit rendering (no custom animation)
- Stage-strip refresh after registry reload: implicit `withAnimation(.standard)` re-render
- Honor `prefers-reduced-motion` everywhere

For Chunk 2C specifically: when stages reorder due to a config update, animate the strip with `.standard`. When stages are added/removed, no transition (just re-render — keeps semantics clear).

## 15. Accessibility & field constraints

Same as Phase 1 spec §14. Specific Phase 2 callouts:

- **InvoiceFormSheet line items:** swipe-to-delete must require min 60pt swipe distance (glove-friendly).
- **PaymentRecordSheet invoice picker rows:** ≥ 88pt tall (matches lead card minimum).
- **Stage registry banner ("Stages unavailable"):** persistent + dismissible only when retry succeeds — not a transient toast.
- **AI summary card:** body text ≥ 16pt; the "🤖" marker is decoration, not the only state signal (also has "AI SUMMARY" label).
- **Map pin:** include text address below the map for users with reduced vision; map is not the only locator.
- **Image gallery:** each thumbnail ≥ 80pt; tap target ≥ 44pt.
- **Contacts permission denial:** error state has a button to open Settings.app (not a dead end).

## 16. Acceptance criteria (phase-level)

Per chunk § criteria above. Plus:

- [ ] All 7 chunks shipped
- [ ] BOOKS tab is feature-complete: every FAB action wired, every Pipeline surface populated (AI/images/location/import), every search scoped, every customer's stage config respected
- [ ] No regressions in Phase 1 functionality
- [ ] Phase 1 acceptance criteria (spec §15) all still pass
- [ ] Bible updates committed
- [ ] Drift register updated

## 17. Out of scope (Phase 3+, post-launch)

Genuinely deferred — not blocking ship:

1. **iOS-side AI inference** — currently web computes AI fields; iOS only reads. If we later want offline AI summaries, that's a separate phase.
2. **Multi-image edit operations** — Phase 2 ships add/remove only. Crop, rotate, reorder = post-ship.
3. **Pipeline stage drag-to-reorder on iOS** — admins customize on web; iOS reads. Post-ship if demand emerges.
4. **Contact-import deduplication** — Phase 2 creates leads even if a contact's email already matches an existing lead. Post-ship: prompt "Looks like this contact already has a lead — link instead?"
5. **Invoice PDF generation on iOS** — currently web generates; iOS reads `pdf_storage_path`. Post-ship.
6. **Payment refund flow** — Phase 2 records payments; doesn't refund. `payments.voided_at` exists but no UI. Post-ship.

## 18. Open questions & risks

| # | Item | Resolution path |
|---|---|---|
| 1 | **AI summary visual marker** — emoji "🤖" or a Lucide icon? Spec proposes emoji; OPS brand discourages decorative icons but allows for content-type signaling. | Confirm during spec review. Default: emoji (unique to AI, fits the chat-like context). |
| 2 | **Image upload bucket** — reuse existing OPS Storage bucket vs new `lead-images` bucket? | Read existing `ProductThumbnailUploader.swift` to see the pattern; mirror. Likely a new bucket per entity-type. |
| 3 | **Bulk import notification** — one notification per imported lead OR a single "X leads imported" notification? | Single batch notification preferred (less noise). Confirm during spec review. |
| 4 | **Per-company stages cache TTL** — 5 min suggested. Too aggressive? Too conservative? | 5min is fine for a first cut. Realtime subscription on `pipeline_stage_configs` if available will obviate TTL eventually. |
| 5 | **Stage registry empty state** — what if a company actually has zero `pipeline_stage_configs` rows AND the seed trigger failed? | Render Pipeline section's full empty state with "STAGES NOT CONFIGURED — CONTACT SUPPORT" message. Edge case but worth handling. |
| 6 | **InvoiceFormSheet payment milestones** — bible §9.340 mentions payment milestones for estimates; should invoices also support them? | Out of scope Phase 2 — invoices are billed-on-creation by default. Fold into a future "invoice scheduling" phase if customers ask. |

## 19. Verification log

Audit trail for the spec's claims (live verification on 2026-05-11).

**Files read:**
- `OPS/Views/Invoices/PaymentRecordSheet.swift` (top 80 lines) — confirmed invoice-required signature
- `OPS/Network/Supabase/Repositories/EstimateRepository.swift` (excerpts) — confirmed two-step create pattern (RPC + insert), but neither estimate nor invoice repo currently calls `get_next_document_number` directly — investigation hint that current iOS code may not yet create estimates/invoices from device, only reads them. Worth a verification step in Chunk 2A's first task.

**Files grep-verified:**
- `OPS/Views/Components/FloatingActionMenu.swift:832-835` — TODO comments + `showingCreateInvoice`/`showingRecordPayment` state vars exist
- `OPS/Network/Supabase/DTOs/InvoiceDTOs.swift:191` — `CreatePaymentDTO` exists
- `OPS/Network/Supabase/Repositories/InvoiceRepository.swift:66` — `recordPayment(_:)` exists
- `OPS/Services/ProductThumbnailUploader.swift` — image upload precedent (121 lines)
- `OPS/Utilities/LocationManager.swift` — CoreLocation precedent
- `OPS/Views/Components/Contact/ContactPicker.swift` — Contacts framework precedent

**Supabase queries executed (live `ops-app` project, 2026-05-11):**
- `invoices` columns (39 cols including NOT NULL set)
- `payments` columns (15 cols, `invoice_id` NOT NULL)
- `pg_proc` for document-number RPCs — found `get_next_document_number` (function body verified to support `'estimate'` + `'invoice'`)
- `information_schema.triggers` on `estimates`, `invoices` — only audit + timestamp triggers; no number-backfill trigger (so iOS must call the RPC explicitly)
- `pipeline_stage_configs` columns — 15 cols, all customization surfaces present

**Files NOT read but referenced (worth re-reading during the chunk that uses them):**
- `OPS/Views/Estimates/EstimateFormSheet.swift` — 382 lines, the pattern InvoiceFormSheet mirrors. Implementation plan should re-read in full at the start of Chunk 2A.
- `OPS/Network/Supabase/DTOs/InvoiceDTOs.swift` full body — `CreatePaymentDTO` confirmed at line 191, `CreateInvoiceDTO` confirmed **MISSING** (must be created in 2A).
- `OPS/Network/Supabase/Repositories/InvoiceRepository.swift` full body — current methods: `fetchAll/fetchDeletedIds/fetchOne/recordPayment/updateStatus/voidInvoice`. `create(_:)` confirmed **MISSING** (must be created in 2A).
- `OPS/Network/Supabase/Repositories/EstimateRepository.swift` full body — `create(_:)` exists as a one-step insert with NO `get_next_document_number` call. Either the DTO carries a number (need to check `CreateEstimateDTO`), or there's a database default we missed, or estimate creation from iOS is silently broken. **Chunk 2A's first task must resolve this** before mirroring the pattern for invoices.
- `OPS/Utilities/LocationManager.swift` — partial API confirmed (`requestPermissionIfNeeded(...)`, `var location: CLLocation?`). Spec §8.6 updated to use the verified API.
- `OPS/Services/ProductThumbnailUploader.swift` — verified pattern (bucket `product-thumbnails`, `{companyId}/{entityId}/{UUID}.jpg`, 1024px max edge, 0.85 JPEG). Spec §8.5 updated with concrete mirror instructions.
- `OPS/Views/Components/Contact/ContactPicker.swift` — confirmed `UIViewControllerRepresentable` wrapping `CNContactPickerViewController`. Multi-select variant may need to be built in Chunk 2G if existing supports single-select only.
- `PipelineStage` consumer count: **13 files** confirmed via grep (`grep -rln PipelineStage OPS --include='*.swift' | wc -l`). Matches Chunk 2C blast-radius estimate exactly.

## 20. References

- Phase 1 spec: `docs/superpowers/specs/2026-05-07-books-tab-design.md`
- Phase 1 plan: `docs/superpowers/plans/2026-05-07-books-tab-implementation.md`
- Bible: `ops-software-bible/09_FINANCIAL_SYSTEM.md` §9 Pipeline / CRM, Estimates, Invoices, Payments, Products
- Phase 1 commit range: `acfa284..06bfbea` (33 commits)
- Phase 1 closeout: `9ee7089` (bible) + `5ce55cf` (plan + spec) + drift register edits in `2a089c0`
- Existing UI precedents:
  - `OPS/Views/Estimates/EstimateFormSheet.swift` — invoice form mirror
  - `OPS/Views/Invoices/PaymentRecordSheet.swift` — refactor target for 2B
  - `OPS/Services/ProductThumbnailUploader.swift` — image upload pattern
  - `OPS/Utilities/LocationManager.swift` — CoreLocation
  - `OPS/Views/Components/Contact/ContactPicker.swift` — Contacts framework
- Design system: `ops-design-system/project/`, `OPS/OPS/Styles/OPSStyle.swift`
