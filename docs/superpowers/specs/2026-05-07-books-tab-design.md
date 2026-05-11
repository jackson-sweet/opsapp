# BOOKS Tab — Design Spec (Phase 1)

| | |
|---|---|
| **Date** | 2026-05-07 |
| **Status** | Brainstorming complete; pending implementation plan |
| **Scope** | iOS only (`ops-ios/`) |
| **Replaces** | The current "Pipeline" tab slot in `MainTabView` (which today renders `MoneyTabView`) |
| **Phase** | 1 of 2 — see "Out of scope (Phase 2)" at the bottom |

## 1. Summary

Replace the mislabeled "Pipeline" tab (icon `chart.line.uptrend.xyaxis`) with a single hub tab named **BOOKS**. The hub contains a financial dashboard at the top and a 4-segment underline control: **PIPELINE · ESTIMATES · INVOICES · EXPENSES**. The Pipeline segment is the only genuinely new surface — Estimates / Invoices / Expenses reuse existing list views. This spec is grounded in real competitor research (FieldPulse "Sales" tab, Housecall Pro "My Money") plus verified Supabase schema and live permission queries.

## 2. Why this shape

- **No mainstream FSM mobile app puts Pipeline as its own bottom tab.** FieldPulse, Housecall Pro, Jobber, QuickBooks all consolidate. Splitting Pipeline + Accounting into two tabs would be novel ground costing 2 of 5 prized tab slots.
- **The OPS owner does sales + AR + dispatch + expenses on one phone** — they don't think in terms of "is this a sales-side problem or a money-side problem." One BOOKS hub avoids that cognitive question.
- **The current tab is misleading** — labeled Pipeline, contains Money. Rename + add the actual Pipeline UI.

## 3. Personas & entry points

| Role | Sees BOOKS tab? | Lands on… |
|---|---|---|
| Owner | Yes | Hub (full dashboard + 4 segments) |
| Admin | Yes | Hub (full dashboard + 4 segments) |
| Office | Yes | Hub (full dashboard + 4 segments) |
| Operator | Yes | Hub (no dashboard or pipeline; Estimates + Expenses segments only) |
| Crew | Yes (single-segment route) | Direct to `MyExpensesView`, skipping the hub |

Tab is hidden entirely if the user has none of: `pipeline.view`, `finances.view`, `estimates.view`, `expenses.view`.

**Entry points:** bottom tab tap (primary). Deep links from notifications / Spotlight to specific entities (lead, estimate, invoice, expense) bypass the hub and open the entity sheet on top of the BOOKS context.

## 4. Information architecture

### 4.1 Tab placement

```
[home] [BOOKS] [job board] [catalog?] [schedule] [settings]
```

`MainTabView.swift:226` currently renders `MoneyTabView()` when `selectedTab == pipelineTabIndex`. Rename slot to BOOKS — render `BooksTabView()`. Tab icon: keep `chart.line.uptrend.xyaxis` (existing).

### 4.2 Hub structure

```
┌─────────────────────────────────┐
│ AppHeader (.books)              │  ← title "BOOKS", existing magnifying glass
├─────────────────────────────────┤
│ MoneyDashboardHeader            │  ← scrolls away on vertical scroll
│   PeriodToggle                  │
│   FinancialHealthBar            │
│   SmartStatCarousel             │
├─────────────────────────────────┤
│ PIPELINE · ESTIMATES · INVOICES · EXPENSES │  ← pins below header on collapse
├─────────────────────────────────┤
│ [Pipeline]                      │
│   stage strip (pinned below)    │
│   list of leads in active stage │
└─────────────────────────────────┘
```

### 4.3 Permission matrix & adaptive routing

Verified from live Supabase `role_permissions` query (2026-05-07):

| Permission | Owner | Admin | Office | Operator | Crew |
|---|---|---|---|---|---|
| `pipeline.view` | ✓ | ✓ | ✓ | — | — |
| `pipeline.manage` | ✓ | ✓ | ✓ | — | — |
| `finances.view` | ✓ | ✓ | ✓ | — | — |
| `estimates.view` / `.create` | ✓ | ✓ | ✓ | ✓ | — |
| `expenses.view` (scope) | all | all | all | own | own |
| `expenses.create` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `expenses.approve` | ✓ | ✓ | ✓ | — | — |

**Routing rules:**

1. **Tab visibility** — show BOOKS if user has ANY of `pipeline.view` / `finances.view` / `estimates.view` / `expenses.view`. Hide if none.
2. **Single-permission auto-skip** — when only one of the four segment-view permissions is granted, skip the hub landing screen and route directly to that segment (`MyExpensesView` for Crew, `EstimatesListView` for a hypothetical estimates-only role).
3. **Per-segment visibility** — each segment renders only if its permission is present. Operator without `pipeline.view` / `finances.view` sees a 2-segment control (Estimates · Expenses), no dashboard.
4. **Action gating** — "ADD LEAD" hidden without `pipeline.manage`; "Approve expense" hidden without `expenses.approve`; FAB items already gate by their own permission keys.

## 5. Dashboard (top of hub) — extend MoneyDashboardHeader

**Decision: KEEP `MoneyDashboardHeader.swift` and `MoneyDashboardViewModel.swift`. Extend, don't replace.**

The existing dashboard is sophisticated: PeriodToggle (30D / 90D / 6M / 1Y), `FinancialHealthBar` (totalSales / totalPayments / totalExpenses / netCash + tap-to-`BreakdownSheet`), and `SmartStatCarousel` (overdueInvoicesCount/value, pendingEstimatesCount/value, closeRate, avgDaysToPayment, expensesTrend, topUnpaidInvoices).

**Phase 1 changes:**

- **Pipeline-aware carousel slots** — extend `MoneyDashboardViewModel` to load `OpportunityDTO` data when `pipeline.view` is granted. Surface three new pipeline stats:
  - `activeLeadCount` + `weightedForecastValue` (sum of `estimatedValue * winProbability/100` across active stages) — accent: `OPSStyle.Colors.accountingRevenue` (amber gold)
  - `staleLeadsCount` (leads exceeding `PipelineStage.staleThresholdDays`) — accent: `OPSStyle.Colors.accountingOverdue` (deep red)
  - `nextFollowUpDue` (closest pending follow-up across all leads) — accent: `OPSStyle.Colors.accountingReceivables` (warm amber)
- **Where these slots render — implementation plan to decide:** `SmartStatCarousel` is currently a struct with 6 hard-coded StatType cases (`overdue`, `pendingEstimates`, `closeRate`, `avgPayment`, `expensesTrend`, `topUnpaid`) and fixed init parameters. Two options:
  - (a) **Extend** SmartStatCarousel — add 3 new StatType cases + 3 new optional init params; carousel keeps a single horizontal scroll for both financial and pipeline stats. Cleaner UX, more change blast-radius.
  - (b) **New sibling** `PipelineStatCarousel` — same visual pattern, separate component, rendered above or below SmartStatCarousel when `pipeline.view` is granted. Smaller blast-radius, two scroll regions.
  - **Recommend (a)** — single carousel feels more cohesive; plus the existing `orderedCards` priority logic already conditionally hides empty stats, which is the same pattern we want for pipeline stats.
- **Adaptive financial slots** — when `finances.view` is absent, the financial stats should be omitted from `MoneyDashboardViewModel`'s outputs entirely (don't compute), so the carousel shows only pipeline stats.
- **Tap "OVERDUE" stat → AR aging drill-down view** (replaces orphan `AccountingDashboard.swift`; see §9).

**Loading:** existing `TacticalLoadingBarAnimated` pattern used by `AccountingDashboard.swift`.

**Empty:** when carousel has no slots to show (e.g. user has only `expenses.view (own)`), the entire dashboard area collapses to height 0. The auto-skip rule means this edge case shouldn't manifest — single-permission users skip the hub.

## 6. Pipeline section — Stage-Pager (the new surface)

**Pattern reasoning:** Pipedrive validates stage-pager on mobile. Web-mirror Kanban is phone-hostile (cards too small, drag-across-columns rough on a 6.1" screen). Stage-Pager preserves the bible's Kanban semantics while respecting iOS gesture conventions.

### 6.1 Stage strip

Horizontal scroll strip below the segmented control. One pill per stage, in order:

```
NEW LEAD · QUALIFYING · QUOTING · QUOTED · FOLLOW-UP · NEGOTIATION │ WON · LOST
```

- Active stage: underlined accent (`OPSStyle.Colors.primaryAccent`), bold label, count badge (e.g. "QUOTING · 4").
- Inactive stages: secondary text color, count badge if non-zero.
- Vertical divider between Negotiation and Won (matches the bible's web pattern). Won/Lost render at lower opacity (terminal stages — for review, not active work).
- Tap a stage to focus the list below. Strip itself is horizontally scrollable when stages overflow viewport width.
- Stage strip pins to top of the scroll view (sticky below the segmented control) so the user always knows what stage they're viewing while scrolling the lead list.

### 6.2 Lead card (per stage list)

Full-width card per lead, using `OPSStyle.Colors.cardBackground` + `OPSStyle.Colors.cardBorder` (≡ `Color.white.opacity(0.2)`). **Note:** existing `AccountingDashboard.swift` uses the deprecated `cardBackgroundDark.opacity(0.6)` token; new BOOKS code should use `cardBackground` (the deprecation comment in `OPSStyle.swift:58` directs migration to glass surfaces or the standard `cardBackground`).

```
┌────────────────────────────────────┐
│ Devlin Roofing                     │  ← title (or contact_name if title default)
│ $24,000 · 5d in stage  ⚠ STALE    │  ← value · days · stale indicator
│ [→ QUOTED] [WON] [LOST] [⋯]       │  ← inline action chips (advance, won, lost, more)
└────────────────────────────────────┘
```

- **Tap card body** → opens lead detail sheet (full screen, NavigationLink push).
- **Tap action chip** → executes immediately with haptic confirmation (light impact for advance, success notification for won, medium impact for lost). "⋯" opens the bottom-sheet action menu (see §6.3) for less-common actions.
- **Inline chips visible only with `pipeline.manage`** — read-only users see the card without action chips.
- **Stale lead treatment** — left-edge accent (3pt, `OPSStyle.Colors.errorStatus.opacity(0.6)`) plus "⚠ STALE · Xd" text on second line. Stale leads bubble to the top of their stage list (sort: stale first, then by `lastActivityAt` desc).
- **Touch target** — entire card minimum 88pt tall (44pt action chip row + 44pt content). Glove-friendly per OPS field standards.

### 6.3 Stage transition flow

Two paths to advance/close a deal:

**Inline action chips (primary, fastest):**
- "→ NEXT_STAGE" advances to `PipelineStage.next`. If next is Won, it triggers the same flow as the WON chip below.
- "WON" → marks won. Optionally prompts for `actualValue` (default `estimatedValue`); writes `actual_close_date = today`.
- "LOST" → opens a modal sheet to capture `lost_reason` (from `LOSS_REASONS` enum: Price / Timing / Competition / Scope / No Response / Other) plus optional `lost_notes`. Confirms and writes `actual_close_date = today`.

**"⋯" bottom sheet (less-common actions):**
- Move to specific stage (pick from list)
- Edit lead
- Log activity (note / call / email / SMS)
- Add follow-up
- Open detail
- Archive (sets `archived_at`)
- Delete (soft-delete; sets `deleted_at`)

**Stage move side effects** (must be atomic from the user's perspective):
1. UPDATE `opportunities.stage` to new value
2. UPDATE `opportunities.stage_entered_at` to `now()`
3. UPDATE `opportunities.stage_manually_set` to `true`
4. INSERT `stage_transitions` row with `from_stage`, `to_stage`, `transitioned_at = now()`, `transitioned_by = current_user_id`, `duration_in_stage = now() - prior_stage_entered_at`

Currently `OpportunityRepository.advanceStage` does only step 1. Steps 2–4 are missing. New repo method `moveToStage(opportunityId, toStage, transitionedBy)` must do all four. **Implementation plan to decide** between (a) a Postgres RPC `move_opportunity_stage(opportunity_id, to_stage, user_id)` that wraps all four in a transaction (preferred — atomic), or (b) two-step PATCH+INSERT from iOS (accepts partial-failure risk if the second write fails). Recommend (a).

### 6.4 Won/Lost terminal stages

- Visually de-emphasized in the stage strip (lower opacity, no count if zero).
- Tappable for review (e.g. "show me what we won this month").
- "Add Lead" FAB action is hidden when viewing Won or Lost stages.
- No inline action chips on cards in Won/Lost stages — only the "⋯" menu (re-open as Negotiation, edit, view detail).

### 6.5 Stale-lead treatment

Per-stage thresholds already defined in `PipelineStage.staleThresholdDays`:

| Stage | Threshold |
|---|---|
| New Lead | 3d |
| Qualifying | 7d |
| Quoting | 5d |
| Quoted | 7d |
| Follow-Up | 3d |
| Negotiation | 2d |

Lead is stale if `daysInStage > threshold`. Daily count surfaces in `SmartStatCarousel` as the new "STALE LEADS" stat. Within a stage view, stale leads sort first.

### 6.6 Add Lead sheet

Triggered from FAB → MONEY group → "ADD LEAD" (gated by `pipeline.manage`). Modal sheet, `presentationDetents([.large])`.

Fields:

| Field | Required | Notes |
|---|---|---|
| Title | No (DB trigger backfills) | Free text. **Verified trigger behavior** (`opportunities_default_title()`): if title is null/empty, sets to `contact_name` (trimmed) or `'New Lead'`. Form should still expose title input so users can name the deal explicitly (e.g. "Devlin roof replacement"). |
| Contact name | Yes | Required by iOS `CreateOpportunityDTO.contactName` (NOT NULL Swift, nullable in DB but used as the title fallback). |
| Contact email | No | |
| Contact phone | No | |
| Estimated value | No | Numeric input, currency formatter. |
| Source | No | Picker. **Verify:** `OpportunitySource` enum doesn't appear in iOS code yet (grep returned no results); needs to be added in Phase 1. Bible §9.85 lists values: `referral`, `website`, `email`, `phone`, `walk_in`, `social_media`, `repeat_client`, `other`. |
| Description | No | Multi-line. |
| Link existing client | No | Optional; uses contact picker, sets `client_id`. |

Submit → `OpportunityRepository.create()` → success toast "LEAD ADDED" → returns to Pipeline section, jumps to NEW LEAD stage, scrolls to new card.

Initial stage is always `new_lead`. `stage_entered_at` = `now()` (server default). No `stage_transitions` row written on create (that's the convention — only stage MOVES are recorded, not the initial stage).

### 6.7 Lead detail sheet

NavigationLink push (not modal) — sufficient depth that users need a back nav.

Sections (top to bottom):

1. **Header** — title, contact name, current stage pill, "$X estimated" (or actual if Won)
2. **Quick actions row** — Call, SMS, Email (uses `tel:`, `sms:`, `mailto:` URLs)
3. **Stage actions** — same as inline chips (advance / won / lost) for users with `pipeline.manage`
4. **Activity log** — list of `Activity` rows (notes, calls, emails, system events). "+ LOG ACTIVITY" button at bottom of section.
5. **Follow-ups** — list of pending `FollowUp` rows. "+ ADD FOLLOW-UP" button.
6. **Stage history** — list of `StageTransition` rows showing the deal's path (read-only).
7. **Edit** — opens edit sheet (same field set as Add Lead, plus stage picker for force-move).

### 6.8 States

| State | Treatment |
|---|---|
| Loading (initial) | `TacticalLoadingBarAnimated` centered (matches `AccountingDashboard.swift:36`). |
| Loading (stage swipe) | Skeleton cards (3 placeholder shapes) for the new stage's list. |
| Empty (no leads in active stage) | Centered text "NO LEADS IN [STAGE]" + secondary CTA "ADD LEAD" wired to FAB action. Different copy per terminal stage: "NO WINS YET — KEEP MOVING" for Won, "NO LOSSES" for Lost. |
| Empty (no leads anywhere) | Pipeline-wide empty state (only when ALL stages are empty): big CTA "ADD YOUR FIRST LEAD". Optional secondary link to "import contacts" (out of scope Phase 1; show greyed). |
| Error (load failed) | Inline error banner matching `AccountingDashboard:42-65` pattern: alert icon, "COULD NOT LOAD LEADS", error text, "TAP TO RETRY". |
| Offline | Local SwiftData read works (cards render from cache). Stage moves queue via existing `SyncEngine`. Top-of-screen sync-status indicator already shows pending queue count. No special treatment in Pipeline section beyond what the rest of the app does. |

## 7. Estimates / Invoices / Expenses sections — reuse existing

| Segment | Renders | ViewModel |
|---|---|---|
| Estimates | `EstimatesListView(embedded: true)` | `EstimateViewModel` (existing) |
| Invoices | `InvoicesListView(embedded: true)` | `InvoiceViewModel` (existing) |
| Expenses | `ExpensesListView(embedded: true)` if `expenses.view` scope is "all", `MyExpensesView()` if scope is "own" | `ExpenseViewModel` (existing) |

No changes to these views in Phase 1 beyond verifying the `embedded: true` pattern still works inside the new `BooksTabView` shell.

## 8. FAB integration

Mirror the existing Catalog precedent (`@AppStorage("catalog.selectedSegment")`) for segment-aware actions:

1. **New AppStorage key** — `@AppStorage("books.selectedSegment")` of type `String` (default = `BooksSection.pipeline.rawValue`). Read by both `BooksTabView` and `FloatingActionMenu`.

2. **New FAB MONEY group item** — "Add Lead" (icon: `person.badge.plus`, permission: `pipeline.manage`). Action opens `AddLeadSheet`.

3. **MONEY group ordering when on BOOKS tab** — promote the action matching the active segment to the top of the MONEY group. Pipeline → "Add Lead" first; Estimates → "New Estimate" first; Invoices → "New Invoice" first (still TODO in Phase 2); Expenses → handled by existing EXPENSES group.

4. **`canShowFAB` adjustment** — add `pipeline.manage` (already there, line 221).

Universal menu still shows all permitted items regardless of active segment — segment-awareness is just visual prominence ordering.

## 9. AR aging drill-down view (replaces AccountingDashboard.swift)

**Decision: delete `AccountingDashboard.swift` (orphan, 324 lines). Build a smaller `ARAgingDetailView.swift` accessed by tapping the "OVERDUE" stat in `SmartStatCarousel`.**

`ARAgingDetailView` keeps the unique value of the orphan view (per-bucket AR aging chart + top outstanding clients) without the redundant status tiles (those live in `SmartStatCarousel` already).

Layout:

1. AR aging Chart (BarMark by bucket: 0-30d / 31-60d / 61-90d / 90d+) — same component pattern from `AccountingDashboard:96-118`.
2. Top outstanding clients list (5 max) — same logic as `AccountingDashboard:182-223`.
3. Tap a row → opens that client's invoice list (filtered to balance > 0).

Gated by `finances.view` — sheet won't open for users without it (the OVERDUE stat won't render in their carousel either).

## 10. Schema & data layer changes

### 10.1 `Opportunity` SwiftData model — additive rebuild

Per memory rule: only additive iOS changes are safe. The Supabase `opportunities` table already has all 47 columns. iOS just needs to start reading them.

**Add these stored properties to `Opportunity.swift`** (all optional / with defaults to preserve existing initializers):

```swift
var title: String?              // server defaults via trigger; we still send when known
var assignedTo: String?         // user UUID
var priority: String?           // "low" | "medium" | "high"
var actualValue: Double?
var winProbabilityOverride: Int? // server-stored override; computed from stage if nil
var expectedCloseDate: Date?
var actualCloseDate: Date?
var stageEnteredAt: Date         // existed server-side; surface on iOS for daysInStage accuracy
var lostNotes: String?
var address: String?
var nextFollowUpAt: Date?
var tags: [String] = []
var deletedAt: Date?             // for soft-delete
var archivedAt: Date?
var stageManuallySet: Bool = false
var sourceEmailId: String?
var correspondenceCount: Int = 0
var outboundCount: Int = 0
var inboundCount: Int = 0
var lastInboundAt: Date?
var lastOutboundAt: Date?
var lastMessageDirection: String?
// Defer in Phase 1: aiSummary, aiStageConfidence, aiStageSignals, detectedValue, latitude, longitude, images
```

**Migration:** SwiftData will add the columns to the local store. All optional / defaulted, so existing rows are valid. No data migration needed.

### 10.2 `OpportunityDTO` rebuild

Mirror the same fields above with `CodingKeys` mapping snake_case → camelCase. Update `toModel()` to populate all new fields. `CreateOpportunityDTO` adds optional `title` (sent when known; trigger backfills when omitted).

### 10.3 `OpportunityRepository` rebuild

Replace methods:

| Method | Change |
|---|---|
| `delete(_ opportunityId: String)` | Replace hard delete with soft delete: UPDATE `opportunities` SET `deleted_at` = now() WHERE id = $1 |
| `advanceStage(opportunityId, to:, lostReason:)` | Deprecate — calls `moveToStage` for backward compatibility, no `stage_transitions` insert |
| **NEW** `moveToStage(opportunityId, to:, transitionedBy:)` | Performs the four-step atomic flow from §6.3. Uses Postgres function or two-step PATCH + INSERT. |
| **NEW** `archive(opportunityId:)` | UPDATE `archived_at` = now() |
| **NEW** `fetchStageTransitions(for opportunityId)` | SELECT from `stage_transitions` table, ordered by `transitioned_at` desc |
| `fetchAll()` | Add `eq("deleted_at", value: nil as String?)` filter (or use `.is("deleted_at", value: nil)`) — exclude soft-deleted |

### 10.4 `StageTransition` SwiftData model — additive rebuild

Add: `companyId: String` (NOT NULL), `transitionedAt: Date` (rename existing `createdAt`? No — add new, keep `createdAt` for compatibility), `durationInStage: TimeInterval?` (decode from Postgres `interval` type).

### 10.5 `Activity` model + `ActivityDTO` reconciliation

iOS `Activity.swift` has 8 fields (`body`, `metadata`, etc.); Supabase `activities` has 33. Phase 1 needs only basic activity logging for the lead detail timeline (notes, calls, emails inbound/outbound, stage changes). Out-of-scope-this-phase: classification fields, attachment arrays, suggested-client matching.

**Required additive changes:**

| iOS field | DB column | Action |
|---|---|---|
| `body: String?` | `body_text` (text) AND `content` (text) — DB has BOTH | **Drift to resolve.** Pick `body_text` as primary (matches the column the email-thread system uses). Map iOS `body` → DB `body_text` in DTO `CodingKeys`. |
| (none) | `subject` (text, NOT NULL — backfilled by `trg_activities_default_subject`) | Add optional `subject` to `ActivityDTO` and `CreateActivityDTO`. iOS can omit on create (trigger backfills); should display when present. |
| (none) | `direction` (text) | Add optional. Used to render inbound vs outbound in the timeline. |
| (none) | `outcome` (text) | Add optional (call outcomes etc.). |
| (none) | `duration_minutes` (int) | Add optional. |
| (none) | `is_read`, `has_attachments`, `attachment_count` (NOT NULL with defaults) | Add optional with defaults. Affect timeline rendering. |
| **Defer** | email_*, classified_*, match_*, sent_by_agent, suggested_client_id, attachment_ids/attachments arrays, site_visit_id, estimate_id, invoice_id, project_id, client_id, from_email, to_emails, cc_emails, classifier_version | Phase 1 does not need these for the lead detail timeline. |

### 10.6 `FollowUp` model + `FollowUpDTO` — BUG FIX REQUIRED

Two real bugs verified during this spec's authority pass:

**Bug 1:** iOS `FollowUpDTO.notes` (`OpportunityDTOs.swift:200`) maps to DB column `notes` — but the actual `follow_ups` table has NO `notes` column. The actual column is `description`. Codable silently leaves `notes` as nil on read; insert with `notes` field will be ignored or error depending on Supabase config. **Fix:** rename `FollowUpDTO.notes` → `description` (or keep iOS field name `notes` but map `CodingKeys.notes = "description"`).

**Bug 2:** iOS `CreateFollowUpDTO` (`OpportunityDTOs.swift:231`) doesn't send `title` — but `follow_ups.title` is NOT NULL with NO backfill trigger (verified: only triggers on `opportunities` and `activities`, not `follow_ups`). Follow-up creation will fail server-side today. **Fix:** add `title: String` (required) to `CreateFollowUpDTO` and `FollowUpDTO`. Form should expose the field (e.g. "Follow up with Devlin re quote").

Also additive (not bugs):
- `description: String?` (renamed from notes — see bug 1)
- `completed_at: Date?` + `completion_notes: String?`
- `created_by: String?` (uuid)
- `is_auto_generated: Bool?`
- `reminder_at: Date?`
- `trigger_source: String?`

### 10.7 `MoneyDashboardViewModel` extension

Add:

```swift
private var opportunityRepository: OpportunityRepository?
private var allOpportunities: [OpportunityDTO] = []

@Published var activeLeadCount: Int = 0
@Published var weightedForecastValue: Double = 0
@Published var staleLeadsCount: Int = 0
@Published var nextFollowUpDue: Date?
```

In `loadData()` add a 4th parallel fetch when `pipeline.view` is granted. In `recalculate()` add the four computations. Pass them through to `SmartStatCarousel`.

## 11. Drift register (verified)

Items found during code + Supabase verification that need to be reconciled. The bible (`ops-software-bible/`) MUST be updated when this work ships.

| # | Drift | Where |
|---|---|---|
| 1 | iOS `Opportunity` model has 16 fields; Supabase has 47. | `OPS/DataModels/Supabase/Opportunity.swift` vs `opportunities` table |
| 2 | iOS `CreateOpportunityDTO` omits `title`. DB-side trigger `trg_opportunities_default_title` backfills it — works today, but iOS should send explicit `title` when known. | `OpportunityDTOs.swift:70-119` |
| 3 | iOS `OpportunityRepository.delete()` does HARD delete; DB has `deleted_at`. | `OpportunityRepository.swift:130` |
| 4 | iOS `OpportunityRepository.advanceStage()` updates only `stage`; should also touch `stage_entered_at`, `stage_manually_set`, and INSERT a `stage_transitions` row. | `OpportunityRepository.swift:102-114` |
| 5 | iOS `StageTransition` model missing `companyId`, `transitionedAt`, `durationInStage`. | `StageTransition.swift` |
| 6 | `InvoiceFormSheet` and `RecordPaymentSheet` are TODOs in `FloatingActionMenu.swift:765-768` — "New Invoice" and "Record Payment" FAB items currently non-functional. (Out of scope Phase 1 — Phase 2.) | `FloatingActionMenu.swift` |
| 7 | `AccountingDashboard.swift` (324 lines) is unwired in any tab today. Replace with smaller `ARAgingDetailView` (this spec). | `OPS/Views/Accounting/AccountingDashboard.swift` |
| 8 | `AppHeader.HeaderType.pipeline` exists with title "PIPELINE". Need new `.books` case (don't repurpose to avoid confusion). | `AppHeader.swift:64,124` |
| 9 | `AppHeader` magnifying glass opens universal `UniversalSearchSheet`, not segment-scoped. Segment-scoped search is deferred. | `AppHeader.swift:518-540` |
| 10 | Bible §9.85 `Opportunity` interface lists fields the iOS model doesn't have (`assignedTo`, `priority`, `actualValue`, `winProbability`, `expectedCloseDate`, `actualCloseDate`, `stageEnteredAt`, `lostNotes`, `address`, `lastActivityAt`, `nextFollowUpAt`, `tags`). | `ops-software-bible/09_FINANCIAL_SYSTEM.md:85-132` |
| 11 | **REAL BUG.** iOS `FollowUpDTO.notes` references a DB column that doesn't exist. Actual column is `follow_ups.description`. Silent data loss on existing follow-ups + insert errors. | `OpportunityDTOs.swift:200` — **RESOLVED in `902e773`** |
| 12 | **REAL BUG.** iOS `CreateFollowUpDTO` omits `title` — NOT NULL on `follow_ups` with no backfill trigger. Follow-up creation fails today. | `OpportunityDTOs.swift:231-244` — **RESOLVED in `902e773`** |
| 13 | iOS `Activity.body` field maps to DB column that may not exist; DB has both `body_text` and `content` columns. iOS picks `content` per `CreateActivityDTO`. Recommend reconciling on `body_text` (matches email-thread system) and renaming iOS `body` → `bodyText`. | `Activity.swift:17`, `OpportunityDTOs.swift:178-190` — **RESOLVED in `902e773`** (renamed iOS field to `bodyText`, primary DB column `body_text`) |
| 14 | `OPSStyle.Colors.cardBackgroundDark` is **deprecated** (per inline comment at `OPSStyle.swift:58` — "legacy — deprecated"). Existing `AccountingDashboard.swift` uses it; new BOOKS code should use `cardBackground` or migrate to glass surfaces (`surfaceInput` / `surfaceHover` / `surfaceActive` + `glassBorder`). | `OPSStyle.swift:58`, `AccountingDashboard.swift:152,172,215` — **RESOLVED in `9a77eac`, `4a82d79`, `f76f457`, `abd2817`, `461f243`, `e753f74`, `54c9b2f`, `2333e38`, `dd705a1`, `c951d3a`** (every new BOOKS file uses `cardBackground`) |
| 15 | `pipeline_stage_configs` table exists with per-company stage customization (color, icon, sort_order, default_win_probability, stale_threshold_days, is_won_stage, is_lost_stage). iOS uses hardcoded `PipelineStage` enum + helpers — companies that customize stages on web will see iOS render the defaults. | DB `pipeline_stage_configs`, `PipelineStage.swift` — **STAYS OPEN** (out of scope per §17 #5; tracked as Phase 3 work) |
| 16 | iOS `OpportunitySource` enum doesn't exist (grep returned no match). Bible §9.85 specifies values; need to add as part of Add Lead sheet work. | `Add Lead` form spec §6.6 — **RESOLVED in `1526f56`** |
| 17 | iOS `StageTransition` doesn't exist as a write path (no DTO, no repo create method). Web-equivalent inserts on every stage move per bible §9.172. | `StageTransition.swift`, `OpportunityRepository.swift` — **RESOLVED in `bf26423`** (added `moveToStage` via `move_opportunity_stage` RPC) + **`b8db1aa`** in ops-software-bible (the RPC migration) |

## 12. Bible updates required (when this ships)

When Phase 1 lands, update `ops-software-bible/09_FINANCIAL_SYSTEM.md`:

- §9.85 (Opportunity Entity) — note that iOS now models the full schema (additive, no DB change).
- §9.151 (Opportunity Helpers) — add iOS-specific equivalents (`PipelineStage.staleThresholdDays`, `PipelineStage.next`, etc.).
- §9.172 (Stage Transitions) — note that iOS now writes transitions on stage move (parity with web).
- §9.189 (OpportunityService) — add iOS `OpportunityRepository.moveToStage()` to the equivalence table.
- New §9 subsection — "iOS BOOKS Tab" describing the hub structure and segment routing.

Update `ops-software-bible/05_DESIGN_SYSTEM.md` (or 02 UX) — note the new tab IA pattern (hub with adaptive-permission segments) for future tabs that may follow the same shape.

## 13. Animation & motion

Per OPSStyle conventions (verified against `OPSStyle.swift:522-556`):

- **`OPSStyle.Animation.standard`** = `cubic-bezier(0.22, 1, 0.36, 1, 0.250)` — matches the OPS brand single-easing-curve standard from CLAUDE.md ("One easing curve cubic-bezier(0.22, 1, 0.36, 1)"). Use for stage strip pill scroll-to-active, segment underline slide.
- **`OPSStyle.Animation.fast`** = `easeInOut(0.2)`. Use for action chip tap dim, card list crossfade between stages.
- **`OPSStyle.Animation.spring`** = `spring(response: 0.3, dampingFraction: 0.7)`. Reserved per CLAUDE.md ("No spring physics, no bounce — exception: drag-and-drop reorder"). **Do not use** for stage transitions; the only legitimate use here is if we add lead-card reorder within a stage (out of scope Phase 1).
- **Won celebration** — success haptic + brief tint flash on the card before it animates out of the active stage (use `Animation.standard`, not spring).
- **Stale indicator** — static red-edge accent only. No pulse, no shimmer (avoid alarm fatigue per the OPS brand).
- **Honor `prefers-reduced-motion`** — fall back to opacity crossfades only; disable spring entirely.

## 14. Accessibility & field constraints

- Touch targets: lead card ≥ 88pt total height; action chips ≥ 44pt; stage strip pills ≥ 44pt tap area.
- Text: lead title 18pt minimum; metadata 14pt minimum.
- Contrast: stale red accent passes 4.5:1 against `cardBackgroundDark`.
- Glove test: stage strip horizontal scroll must work with reduced precision (8pt minimum tap activation distance — match existing `@dnd-kit` PointerSensor analog).
- Sunlight test: stage pills + action chips remain readable at full screen brightness; test with iPhone outdoor mode.
- Offline test: load a stage list, kill connectivity, advance a lead's stage — confirm queues to `SyncEngine` and shows pending in top status indicator.
- Color is never the only signal — stale leads use icon (⚠) AND text AND color; Won/Lost use opacity AND label position.

## 15. Acceptance criteria (pre-implementation checklist)

**Design system compliance:**
- [ ] All colors use `OPSStyle.Colors.*` tokens — zero hardcoded hex.
- [ ] No new uses of deprecated `cardBackgroundDark` — use `cardBackground` (or glass surfaces).
- [ ] Pipeline carousel cards use `accountingRevenue` / `accountingProfit` / `accountingOverdue` / `accountingReceivables` for accents, matching the existing financial cards' semantic-color pattern.
- [ ] All typography uses `OPSStyle.Typography.*` tokens (verified available: `body`, `bodyBold`, `caption`, `captionBold`, `smallCaption`, `title`, `subtitle`, `sectionLabel`, `panelTitle`).
- [ ] Stage strip pills use `OPSStyle.Layout.cardCornerRadius` (10pt) and `OPSStyle.Layout.Border.standard` (1pt).
- [ ] Action chips use `OPSStyle.Layout.spacing*` tokens (`spacing1`=4, `spacing2`=8, `spacing2_5`=12, `spacing3`=16, `spacing3_5`=20, `spacing4`=24, `spacing5`=32).
- [ ] All animations use only `OPSStyle.Animation.standard` or `.fast` — no `.spring` (per CLAUDE.md no-bounce rule).
- [ ] Reduced-motion fallback in place for all transitions.

**Information architecture:**
- [ ] BOOKS tab hidden when user has no relevant permission.
- [ ] Single-permission users skip the hub and route directly to their one segment.
- [ ] Segments hide when their permission is absent.
- [ ] Pipeline / Estimates / Invoices / Expenses each load without errors for permitted users.

**Pipeline section:**
- [ ] Stage strip horizontal scroll works one-handed.
- [ ] Tap card → opens detail; tap action chip → executes with haptic.
- [ ] Won/Lost terminal stages visually de-emphasized.
- [ ] Stale leads bubble to top of stage list with red-edge accent.
- [ ] Add Lead sheet creates lead in `new_lead` stage; new card appears in NEW LEAD stage immediately.
- [ ] Stage move writes `stage_transitions` row (verify in Supabase after a test move).
- [ ] Soft-delete via `⋯` → Delete sets `deleted_at` (not hard delete; verify row still exists in Supabase).

**Dashboard:**
- [ ] Existing financial stats render unchanged for users with `finances.view`.
- [ ] New pipeline stats (active leads, weighted forecast, stale count, next follow-up) render for users with `pipeline.view`.
- [ ] Carousel hides financial slots for users without `finances.view`.
- [ ] Tap "OVERDUE" stat → opens `ARAgingDetailView`.

**FAB:**
- [ ] Add Lead item appears in MONEY group when user has `pipeline.manage`.
- [ ] Active BOOKS segment promotes the matching create action to top of MONEY group.

**States:**
- [ ] Loading shows `TacticalLoadingBarAnimated`.
- [ ] Empty stage shows centered "NO LEADS IN [STAGE]" + ADD LEAD CTA.
- [ ] Pipeline-wide empty (no leads anywhere) shows full empty state with primary CTA.
- [ ] Error shows inline retry banner.
- [ ] Offline: cards still render from cache; stage moves queue.

**Field constraints:**
- [ ] All touch targets ≥ 44pt; lead cards ≥ 88pt total.
- [ ] All text ≥ 16pt body, ≥ 18pt for primary content.
- [ ] Reduced-motion fallback in place.

## 16. Out of scope (Phase 2)

Tracked here so they don't get forgotten. New spec to follow.

1. **`InvoiceFormSheet`** — new, replaces TODO at `FloatingActionMenu.swift:766`.
2. **`RecordPaymentSheet`** — new, replaces TODO at `FloatingActionMenu.swift:768`.
3. **Wire FAB MONEY group's "New Invoice" + "New Payment" actions** to those sheets.
4. **Segment-scoped search** — extend `UniversalSearchSheet` with a scope parameter so AppHeader search can be scoped to BOOKS or further to the active segment.
5. **AI-generated lead fields on iOS** — `aiSummary`, `aiStageConfidence`, `aiStageSignals`, `detectedValue` (deferred from §10.1 model).
6. **Lead images, latitude/longitude** — deferred from §10.1.
7. **Import contacts → leads** — Pipeline-wide empty-state secondary CTA (greyed in Phase 1).

## 17. Open questions & risks

| # | Item | Resolution path |
|---|---|---|
| 1 | **Atomic stage move** — Postgres RPC vs two-step PATCH+INSERT (see §6.3). | Implementation plan picks; recommend RPC. — **RESOLVED via Postgres RPC** (commit `b8db1aa` in ops-software-bible + `bf26423` in ops-ios) |
| 2 | ~~`opportunities_default_title` trigger body unverified~~ — **RESOLVED:** trigger source confirmed to be `IF NEW.title IS NULL OR btrim(NEW.title) = '' THEN NEW.title := COALESCE(NULLIF(btrim(NEW.contact_name), ''), 'New Lead'); END IF;` Safe to omit `title` on insert. Form should still expose it for explicit deal naming. | Closed. |
| 3 | **Novel IA pattern** — no comparable mobile app puts pipeline + AR + estimates + invoices + expenses in one tab for a single owner persona. Real-user testing required after first build before declaring victory. | Schedule 5-user test sessions with trades-business-owner participants within 30 days of Phase 1 ship. |
| 4 | **`expenses.view` "own" scope routing** — the spec assumes the existing `MyExpensesView` is appropriate for Operator/Crew. Need to confirm `MyExpensesView`'s feature set covers the Expenses segment requirements (filters, date scope, sort). | Implementation plan reviews `MyExpensesView` capabilities and notes any gaps. — **RESOLVED** — `MyExpensesView` confirmed appropriate; auto-skip routes Crew users to it (commit `06bfbea`) |
| 5 | **`pipeline_stage_configs` per-company stages** — table verified to exist with full per-company customization (color, icon, sort_order, default_win_probability, stale_threshold_days, is_won_stage, is_lost_stage). iOS uses hard-coded `PipelineStage` enum. Customized companies will see iOS render the defaults. | Out of scope Phase 1 — Phase 3 work. Tracked in drift #15. |
| 6 | **Bible drift correction** — bible web `Opportunity` interface (§9.85) lists fields like `actualValue`, `priority`, `assignedTo` that iOS now adds in §10.1. Bible should be updated to confirm iOS parity. | Update bible §9 when Phase 1 lands. |
| 7 | **`SmartStatCarousel` modification approach** — extend the existing struct vs build a sibling `PipelineStatCarousel` (see §5). | Implementation plan picks; recommend extending. — **RESOLVED** — extended the existing struct (commit `bf23031`) |
| 8 | **`Activity` body field reconciliation** — DB has both `body_text` and `content`. Pick `body_text` as primary on iOS for the lead detail timeline (matches email-thread system); leave `content` reads as fallback when `body_text` is null on legacy rows. | Resolve at implementation. — **RESOLVED** — picked `body_text` as primary (commit `902e773`) |
| 9 | **Glass surface migration** — `cardBackgroundDark` is deprecated and the comment says "migrate to glass". The glass system (`surfaceInput`/`surfaceHover`/`surfaceActive` + `glassBorder`) exists. Should new BOOKS cards adopt the glass system, or stay on `cardBackground` for visual parity with current Money/Estimates lists? | Resolve at implementation; safe default is `cardBackground` (matches existing list rows). — **RESOLVED** — used `cardBackground` (matches existing list rows; glass system migration deferred to a future visual polish pass) |
| 10 | **Pipeline form schemas** — Add Lead form needs `OpportunitySource` enum (doesn't exist in iOS — drift #16) and `LossReason` enum (referenced in spec; existence unverified). | Read or create both as Phase 1 work. — **RESOLVED** — both added in commit `1526f56` |

## 18. Verification log

Audit trail for the spec's claims. Anything cited that's not in this list was either inferred from CLAUDE.md or is flagged as an open question in §17.

**Files read in full:**
- `OPS/ContentView.swift`
- `OPS/Views/Money/MoneyTabView.swift`
- `OPS/Views/Money/Components/MoneyDashboardHeader.swift`
- `OPS/Views/Money/Components/SmartStatCarousel.swift` (lines 1-120)
- `OPS/ViewModels/MoneyDashboardViewModel.swift`
- `OPS/Views/Accounting/AccountingDashboard.swift`
- `OPS/DataModels/Supabase/Opportunity.swift`
- `OPS/DataModels/Supabase/Activity.swift`
- `OPS/DataModels/Supabase/FollowUp.swift`
- `OPS/DataModels/Supabase/StageTransition.swift`
- `OPS/DataModels/Enums/PipelineStage.swift`
- `OPS/DataModels/Enums/ActivityType.swift`
- `OPS/Network/Supabase/Repositories/OpportunityRepository.swift`
- `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift`
- `OPS/Views/Components/FloatingActionMenu.swift`
- `OPS/Views/Components/Common/AppHeader.swift`

**Files grep-verified (specific tokens / parameters cited):**
- `OPS/Styles/OPSStyle.swift` — color tokens (cardBackground, cardBorder, primaryAccent, accountingRevenue/Profit/Cost/Receivables/Overdue, status colors, text tokens, button text, glass surfaces); spacing tokens (spacing1–5, spacing2_5, spacing3_5, touchTargetMin/Standard); radii (panelRadius, cornerRadius, cardCornerRadius); typography (body, bodyBold, caption, captionBold, smallCaption, title, subtitle, sectionLabel, panelTitle); Border (standard, thick); IconSize (md, xl); Animation (standard, fast, spring) — all verified to exist with values matching cited usage.
- `OPS/Views/Estimates/EstimatesListView.swift:11` — `var embedded: Bool = false` confirmed.
- `OPS/Views/Invoices/InvoicesListView.swift:11` — `var embedded: Bool = false` confirmed.
- `OPS/Views/Expenses/ExpensesListView.swift:13` — `var embedded: Bool = false` confirmed.
- Permission keys grep across `OPS/Views/` — confirmed existence of pipeline.view/manage, finances.view, estimates.view/create, expenses.view/create/approve.

**Files NOT read but referenced in spec** (called out so the implementation plan can fill gaps):
- `OPS/Views/Estimates/EstimatesListView.swift` (full body — only embedded param verified) — implementation plan should re-read for embedded-mode behaviors before slotting into BOOKS.
- `OPS/Views/Invoices/InvoicesListView.swift` (full body)
- `OPS/Views/Expenses/ExpensesListView.swift` and `MyExpensesView.swift` (full body)
- `OPS/Views/Money/Components/FinancialHealthBar.swift`, `PeriodToggle.swift`, `BreakdownSheet.swift` (used by MoneyDashboardHeader; treated as black boxes in the spec)
- `OPS/Views/Components/Common/TacticalLoadingBar.swift` (cited as loading pattern; the exact symbol `TacticalLoadingBarAnimated` is what's used in `AccountingDashboard.swift:36` — assumed to be in this file based on naming)
- `ops-design-system/project/README.md` and `uploads/system.md` — referenced via CLAUDE.md as the brand canon, but for an iOS-only spec `OPSStyle.swift` is the operational source of truth. They should be cross-checked when this work touches cross-platform brand decisions.
- `ops-software-bible/05_DESIGN_SYSTEM.md` — only the table of contents was read. iOS-side design is satisfied by OPSStyle verification; bible §05 is the cross-platform doc.

**Bible sections read:**
- §9 (Financial System) — lines 1-280 covering Pipeline / CRM and the start of Estimates. The remainder of §9 (Estimates internals, Invoices, Products, Expenses) was not read and is not load-bearing for this spec.

**Supabase queries executed (live `ops-app` project, ID `ijeekuhbatykdomumfjx`, on 2026-05-07):**
- Full column list for `opportunities` (47 columns) — used to build §10.1.
- Full column list for `activities` (33 columns) — used to build §10.5.
- Full column list for `follow_ups` (17 columns) — used to find the bug in §10.6.
- Full column list for `pipeline_stage_configs` (15 columns) — used for §17 #5 / drift #15.
- Full column list for `stage_transitions` — used to confirm bible §9.172 schema.
- Triggers on `opportunities` — found `trg_opp_timestamp`, `trg_opportunities_default_title`.
- Triggers on `activities` and `follow_ups` — found `trg_activities_default_subject`; confirmed NO trigger exists on `follow_ups` (informs bug §10.6 #2).
- Function body for `opportunities_default_title()` — confirmed backfill logic for §17 #2.
- `role_permissions` rows for all 8 financial permissions across all 5 roles — used to build §4.3 permission matrix.

## 19. References

- Brainstorming session: `.superpowers/brainstorm/51681-1778204481/content/`
- Real competitor research: `tasks/ac2800f3c3d1d1f02.output` (FieldPulse "Sales" tab + HCP "My Money" patterns)
- Bible: `ops-software-bible/09_FINANCIAL_SYSTEM.md` §9 Pipeline / CRM System
- Existing code:
  - `OPS/Views/MainTabView.swift:226` (current Pipeline tab slot)
  - `OPS/Views/Money/MoneyTabView.swift` (existing segmented container)
  - `OPS/Views/Money/Components/MoneyDashboardHeader.swift`
  - `OPS/ViewModels/MoneyDashboardViewModel.swift`
  - `OPS/Views/Accounting/AccountingDashboard.swift` (orphan, to be replaced)
  - `OPS/DataModels/Supabase/Opportunity.swift`
  - `OPS/DataModels/Supabase/StageTransition.swift`
  - `OPS/Network/Supabase/Repositories/OpportunityRepository.swift`
  - `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift`
  - `OPS/Views/Components/FloatingActionMenu.swift`
  - `OPS/Views/Components/Common/AppHeader.swift`
- Design system: `ops-design-system/project/`, `OPS/OPS/Styles/OPSStyle.swift`
