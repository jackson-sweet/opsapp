# BOOKS — UI Reconstruction Design Spec

|   |   |
|---|---|
| **Date** | 2026-05-11 |
| **Status** | Self-reviewed against bible + Supabase + codebase + design system; ready for implementation planning |
| **Scope** | iOS app (`ops-ios/`) — Books tab reconstruction |
| **Bug** | `1b038315-fb4a-44a1-b118-8e5e67578980` — filed against `screen_name=Invoices`, `category=ui_issue`, `status=new`. Description: "Need to do complete reconstruction of Books UI". Operator escalated from the Invoices surface into a full-tab reconstruction. Verified via `SELECT id, screen_name, category, status FROM bug_reports WHERE id='1b038315-...'` on project `ijeekuhbatykdomumfjx`. |
| **Supersedes** | [`2026-05-07-books-tab-design.md`](2026-05-07-books-tab-design.md) — Phase 1 hub-with-4-segments; that shape is being replaced. The original consolidated all financial work into one tab; this reconstruction splits Pipeline out and elevates the financial dashboard to a swipeable hero carousel. |
| **Related spawns** | `PIPELINE TAB - P1-1` (separate top-level tab), `CASHFLOW FORECAST - P1-1` (future 6th carousel card) |

## 0. Drift register (caught during self-review)

Documented deviations between bible / prior spec / current code. Each will be reconciled as part of this work.

| # | Source of truth | Current state | Action |
|---|----------------|---------------|--------|
| D1 | Bible `09_FINANCIAL_SYSTEM.md` § "Accounting Views" (lines 1140–1143) describes `AccountingDashboard.swift` | File does not exist on disk — was replaced by `ARAgingDetailView.swift` in a prior session. Bible is stale. | Rewrite bible § 1140–1143 to describe `ARAgingDetailView` (only AR drill-down surface; aging buckets + top outstanding clients). |
| D2 | Bible `09_FINANCIAL_SYSTEM.md` § "iOS BOOKS Tab (Phase 1, May 2026)" (lines 1424–1450) describes the 4-segment hub with `SmartStatCarousel` + `FinancialHealthBar` + Pipeline-in-Books | Implementation matches bible; this spec replaces both. | Rewrite bible § 1424–1450 after implementation lands. Mark Phase 1 as superseded; document the new carousel architecture and the Pipeline-tab split. |
| D3 | `expense_project_allocations.project_id` (Supabase) | Column type is `text NOT NULL`, while `invoices.project_id` and `projects.id` are `uuid`. Bubble-legacy artifact. | Card 5 (Jobs) join must cast: `WHERE epa.project_id::uuid = inv.project_id` (or both sides to text). Spec § 5 records this. |
| D4 | `EstimateViewModel.EstimateFilter` enum | Cases are `.all, .draft, .sent, .approved` — no `.viewed` filter (viewed-but-not-approved estimates surface inside `.sent` by status). | Card 1 "Forecast" tile drills to `EstimateFilter.sent`, not "sent + viewed." Spec § 4.3 updated. |
| D5 | `Project` SwiftData model (`OPS/DataModels/Project.swift`) | No `estimatedAmount` field. Closest signals are `Opportunity.actualValue` (when a project converted from a won deal) and `sum(invoices.total)` for the project. | Card 5 uses `sum(invoices.amount_paid)` for revenue (already-paid only — conservative net) and `sum(expense_project_allocations.amount)` for cost. Spec § 5 records the formula. |
| D6 | `FloatingActionMenu` (global FAB) | One global instance in `MainTabView.swift:383` adapts MONEY-group ordering via `@AppStorage("books.selectedSegment")` and `orderedMoneyItems(rawItems:)`. There is no per-tab FAB and no scan-receipt FAB component. | Spec § 4.6 rewritten to describe FAB integration (not a new FAB). Default `booksSelectedSegmentRaw` must change from `"PIPELINE"` to `"INVOICES"`. The MONEY-group default fallback in `orderedMoneyItems` (`default: primaryId = "new-estimate"`) is retained. |
| D7 | `ops-design-system/project/SKILL.md` § "Three fonts" | iOS uses **three** font families (Mohave / JetBrains Mono / Cake Mono Light) per `OPSStyle.swift`. My initial spec only cited Mohave + JetBrains Mono. | Spec § 7 updated — `sectionLabel`, `pageTitle`, `displayHeading`, `buttonLabel`, `badge` use Cake Mono Light. |
| D8 | `ops-design-system/project/SKILL.md` motion rule | "No spring physics, no bounce, one easing curve: `cubic-bezier(0.22, 1, 0.36, 1)`." SwiftUI's default `TabView(.page)` uses spring physics for page transitions. | Card carousel uses a custom paginated `ScrollView(.horizontal)` with `.scrollTargetBehavior(.paging)` (iOS 17+) and explicit `OPSStyle.Animation.standard` easing on programmatic snap. Drag-and-drop reorder remains the only allowed spring exception per `CLAUDE.md`. Spec § 6 records this. |
| D9 | Bug `1b038315` row | `status='new'`, `resolved_at=NULL`, `fix_notes=NULL` as of 2026-05-11 12:00 UTC. | Resolution SQL in § 13 uses real columns: `status`, `resolved_at`, `fixed_at`, `fix_notes`. (Bug table has no `screen` column — `screen_name` is the correct column.) |

---

## 1. Summary

Rebuild the Books tab as a **money command center**. The tab opens to a swipeable 5-card hero carousel that answers the five questions a stressed trades business owner asks at 7am about their money. Below the carousel sits a 3-segment list of underlying documents (Invoices · Estimates · Expenses). Pipeline is removed from this tab entirely — it moves to its own top-level tab.

**Mental model:** _"Am I making money? Who owes me? What's coming? What did I make on each job?"_ — those questions are the carousel; the lists are the evidence.

## 2. Why this shape

The May 7 hub-with-4-segments shape solved tab-slot scarcity but mixed two distinct mental models — sales/lead chasing (pipeline) and money/accounting (invoices/expenses/AR). The user's gut-feel framing during this session: **"Books and Pipeline should be separate tabs. Books is a money command center."**

The carousel resolves a second tension: there is no single "right" first view of finances. Net cash, A/R aging, cash flow, forecast, and job profitability are all valid first-glance questions depending on the day. A static dashboard picks one and demotes the rest. A swipeable carousel of five focused lenses lets the operator choose without re-architecting the view.

Pipeline gets elevated to a top-level tab because:

1. It is not "money" — it is sales activity, deserving its own attention scope.
2. Tab-slot scarcity is mitigated by hiding Pipeline for roles without `pipeline.view` (crew/operator), keeping the visible tab count at 4–6 for any single user.
3. The existing `PipelineSectionView` already works as a primary surface; coordination details live in the `PIPELINE TAB - P1-1` spawn.

## 3. Personas & entry points

| Role | Sees Books? | Lands on… |
|---|---|---|
| Owner | Yes | Full Books (carousel + 3 segments) |
| Admin | Yes | Full Books (carousel + 3 segments) |
| Office | Yes | Full Books (carousel + 3 segments) |
| Operator | Yes | Books with 2 segments (Estimates + Expenses); carousel hidden entirely (all five cards require `finances.view` or `pipeline.view`, neither of which Operators have — see §4.5) |
| Crew | Single-segment route — direct to `MyExpensesView`, no hub or carousel |

Tab is hidden if user has none of: `finances.view`, `estimates.view`, `expenses.view`. (`pipeline.view` no longer gates Books — it gates the new Pipeline tab.)

**Entry points:**
- Bottom tab tap (primary).
- Deep links from notification rail / Spotlight to entity sheets (Invoice, Estimate, Expense) bypass the hub.
- Carousel tile taps drill to filtered list views (e.g., A/R tile → Invoices segment filtered to overdue).

## 4. Information architecture

### 4.1 Tab placement

```
[home] [BOOKS] [PIPELINE] [job board] [catalog?] [schedule] [settings]
```

- Books retains the `chart.line.uptrend.xyaxis` icon (existing).
- Pipeline gets its own icon — decision deferred to `PIPELINE TAB - P1-1` spawn.
- Tab order: Books sits immediately after Home (financial command), Pipeline sits next (sales feed), Job Board next (active operations). Order reflects daily workflow: check money → check leads → check today's jobs.
- For roles without `pipeline.view`, Pipeline tab is hidden (existing pattern). Total visible tab count stays within 4–6.

### 4.2 Books tab structure

```
┌─────────────────────────────────────────┐
│ AppHeader (.books)                       │  ← "BOOKS" title + search/notification icons
├─────────────────────────────────────────┤
│ Period strip: [NOV 2025 ▾]    ↑12% MoM   │
├─────────────────────────────────────────┤
│ ┌───────────── HERO CAROUSEL ─────────┐ │
│ │ Card 1 of 5 — P&L                    │ │
│ │   payments in / expenses out / net   │ │
│ │   margin %, MoM trend                │ │
│ │   2 tiles: Outstanding · Forecast    │ │
│ │ ● ○ ○ ○ ○                            │ │
│ └──────────────────────────────────────┘ │
├─────────────────────────────────────────┤
│ INVOICES · ESTIMATES · EXPENSES         │  ← sticky on scroll collapse
├─────────────────────────────────────────┤
│ [Active segment list]                    │
│   row · row · row · row · row            │
└─────────────────────────────────────────┘
  ⊕ global FAB (MONEY group reordered per active segment — §4.6)
```

On scroll, the carousel collapses into a single-line strip showing the active card's primary number + an A/R glance + dot indicators. Segments stick. Pull-to-top or pull-down re-expands the carousel.

### 4.3 Hero carousel — 5 cards

| # | Card | Question answered | Period scope | Primary visual |
|---|------|-------------------|--------------|----------------|
| 1 | **P&L** | "Am I making money this month?" | Follows selector | In − Out = Net equation, margin bar |
| 2 | **Cash flow** | "What's my cash rhythm?" | Follows selector | Weekly paired bars (in/out) |
| 3 | **A/R aging** | "Who do I need to chase?" | Always ALL-OPEN | Aging buckets (0–30, 31–60, 61–90, 90+) |
| 4 | **Forecast** | "What's coming if pipeline plays out?" | Always ACTIVE | Weighted-pipeline bars by stage |
| 5 | **Jobs** | "Which jobs make me money?" | Follows selector | Diverging profit/loss bars top 5 |
| 6 _(future)_ | **Forward cashflow** | "What's my projected cash over 4-12 weeks?" | 4/8/12 wk horizon | Spawn: `CASHFLOW FORECAST - P1-1` |

**Persistence:** last-viewed card remembered across app launches (default Card 1 on first launch). Smart-default surfacing (open the most urgent card by data condition) is a v2 enhancement, explicitly deferred.

**Tile drill-downs (per card):**

| Card | Tile | Drill to |
|------|------|----------|
| 1 | Outstanding | Invoices segment, filter = overdue |
| 1 | Forecast | Estimates segment, `EstimateFilter.sent` (D4 — `.viewed` is data not a filter) |
| 2 | Avg/wk | Cash flow report (full-screen drill) |
| 2 | Days-to-pay | A/R health report |
| 3 | Top chase | Invoice detail (top-overdue client) |
| 4 | Close rate | Pipeline tab, stage filter = won (last 90d) |
| 4 | Stale | Pipeline tab, filter = stale |
| 5 | Profitable / Losers | Job profitability report |

### 4.4 Segments below carousel

3-segment underline control: **INVOICES · ESTIMATES · EXPENSES** (in that order — invoices is the most-trafficked surface).

Each segment renders the existing list view (`InvoicesListView`, `EstimatesListView`, `ExpensesListView` / `MyExpensesView`) with `embedded: true`. No changes to those list views in this spec — they already work.

**Removed:** the `pipeline` case from `BooksSection` enum and the `.pipeline` segment from the underline control.

### 4.5 Permission matrix (post-reconstruction)

| Permission | Owner | Admin | Office | Operator | Crew |
|---|---|---|---|---|---|
| `pipeline.view` | ✓ | ✓ | ✓ | — | — |
| `finances.view` | ✓ | ✓ | ✓ | — | — |
| `estimates.view` | ✓ | ✓ | ✓ | ✓ | — |
| `expenses.view` (scope) | all | all | all | own | own |
| `expenses.create` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `expenses.approve` | ✓ | ✓ | ✓ | — | — |

Verified from live Supabase `role_permissions` query (parent spec). No changes from May 7.

**Carousel card visibility by permission:**

| Card | Permission required |
|------|---------------------|
| 1 P&L | `finances.view` |
| 2 Cash flow | `finances.view` |
| 3 A/R | `finances.view` |
| 4 Forecast | `pipeline.view` |
| 5 Jobs | `finances.view` |

Carousel renders only the cards the user can see. If only one card is visible, dots are hidden and the swipe affordance is suppressed. If zero cards are visible, the entire carousel container (including the period strip) is hidden — the user lands directly on the segmented control + list. (This is the Operator path; Crew bypasses Books entirely via `booksAutoSkipDestination`.)

### 4.6 FAB / create flow

**Integration with the existing global FAB — no new FAB component.** (D6)

The OPS app has a single global `FloatingActionMenu` in `MainTabView.swift:383`. It renders across all tabs except Settings and exposes a multi-section action menu (PROJECTS, MONEY, EVENTS, etc.). The MONEY section already contains: `new-estimate`, `new-invoice`, `new-expense`, `new-lead`, `record-payment`. The Books tab influences the MONEY group's **order** via `@AppStorage("books.selectedSegment")` and the `orderedMoneyItems(rawItems:)` function (`FloatingActionMenu.swift:237`) — the create action matching the active segment floats to position 0.

This spec changes:

1. **Default segment value** — `@AppStorage("books.selectedSegment")` default changes from `"PIPELINE"` to `"INVOICES"`. Affects both `BooksTabView.swift:32` and `FloatingActionMenu.swift:114`.
2. **MONEY ordering fallback** — `orderedMoneyItems` `default:` branch keeps `primaryId = "new-estimate"` (sensible: Estimates is the gateway to all financial flow). The `case "PIPELINE":` branch is removed (no segment to match).
3. **Receipt scan entry point** — receipt scan stays inside `ExpenseFormSheet` (camera button + OCR auto-fill, already implemented per bible § 1133). The `new-expense` FAB action opens that sheet. No separate "scan FAB" surface is added — the spec § 4.6 draft v1 proposed one; abandoned after verifying the existing FAB pattern. If a faster scan path is wanted, it belongs in a follow-up that adjusts the FAB menu (e.g., a "scan-receipt" item adjacent to `new-expense`) — out of scope here.

All existing FAB behavior (hide-on-scroll, haptics, edit mode, hidden items, custom order via `fabItemOrder`) is preserved.

## 5. Data model

No new schema. All data already exists. Schema verified against `ijeekuhbatykdomumfjx` on 2026-05-11.

**Entities consumed (read-only):**

| Entity | Source | Carousel cards |
|--------|--------|----------------|
| `invoices` (id, project_id `uuid`, total, amount_paid, balance_due, status, due_date, paid_at, deleted_at) | Supabase | 1, 2, 3, 5 |
| `payments` (id, invoice_id, amount, payment_date, voided_at) | Supabase | 1, 2 |
| `estimates` (id, total, status, sent_at, viewed_at, approved_at, deleted_at) | Supabase | 1 (forecast tile), 4 |
| `expenses` (id, amount, expense_date, status, deleted_at) | Supabase | 1, 2 |
| `expense_project_allocations` (id, expense_id, project_id `text`, percentage, amount) | Supabase | **5 only** — per-project rollup |
| `opportunities` (id, stage, estimated_value, win_probability, archived_at, deleted_at) | Supabase | 4 |
| `projects` (id `uuid`, title, status, deleted_at) | Supabase / SwiftData mirror | 5 (display name) |

**No new tables, no new columns, no migrations.**

`MoneyDashboardViewModel` already computes Cards 1–4 inputs. Required additions:

### 5.1 Card 5 (Jobs) — per-project profitability rollup

Per-project net = (revenue actually collected) − (expense allocations applied). Reasons:

- **Revenue** uses `amount_paid` not `total` — only money already collected counts as profit. Booked-but-unpaid revenue lives in the A/R card, not Jobs.
- **Cost** uses `expense_project_allocations.amount` (pre-computed) with fallback to `expenses.amount × percentage/100` if `amount` is null. (`amount` column was added later; some legacy rows have only `percentage`.)
- **Type cast required (D3):** `expense_project_allocations.project_id` is `text`; `invoices.project_id` and `projects.id` are `uuid`. Casts on the iOS side after fetch — both are decoded as `String` in Swift DTOs, so comparison is string-on-string after normalising.

Algorithm (executed in Swift after the existing `MoneyDashboardViewModel.loadData()` parallel fetch):

```
for each project p where p.deletedAt == nil:
  revenue[p.id] = sum( invoice.amountPaid
                       where invoice.projectId == p.id
                       and invoice.deletedAt == nil
                       and invoice.status != .void
                       and (filter to period: invoice.paidAt in period or invoice.createdAt in period — match period selector card scope)
                     )
  cost[p.id]    = sum( allocation.amount ?? (expense.amount × allocation.percentage / 100)
                       where allocation.projectId == p.id
                       and expense.deletedAt == nil
                       and expense.expenseDate in period
                     )
  net[p.id] = revenue[p.id] − cost[p.id]

topProjects = projects sorted by net descending, take 5 (with worst-net loser inserted if not already in top-5)
```

Profitable count = `projects.filter { net[p.id] > 0 }.count`. Avg margin = `mean(net[p.id] / max(revenue[p.id], 1))` over projects with revenue > 0. Losers count = `projects.filter { net[p.id] < 0 }.count`.

The query reuses the existing `ExpenseRepository.fetchAll()` plus a new lightweight `ExpenseRepository.fetchAllAllocations(companyId:)` — joins not required since both sets are small (~80 expenses, ~50 allocations on the live project).

### 5.2 Card 4 (Forecast) — already in ViewModel

`MoneyDashboardViewModel.activeLeadCount`, `weightedForecastValue`, `staleLeadsCount`, `nextFollowUpDue` already exist. Card 4 also needs the per-stage breakdown for the visual bars — add `weightedForecastByStage: [PipelineStage: Double]` to the ViewModel.

### 5.3 Card 2 (Cash flow) — weekly bucketing

`MoneyDashboardViewModel` currently computes `totalPayments` / `totalExpenses` for the whole period. Card 2 needs weekly buckets — add `paymentsByWeek: [(weekStart: Date, amount: Double)]` and `expensesByWeek: [(weekStart: Date, amount: Double)]`. Bucketing uses `Calendar.current.dateInterval(of: .weekOfYear, for:)`.

### 5.4 Period scope behaviour

- Cards 1, 2, 5 — recompute on `selectedPeriod` change via the existing `recalculate()` flow.
- Cards 3, 4 — period-independent. Their inputs (`overdueInvoicesValue`, `topUnpaidInvoices`, `activeLeadCount`, `weightedForecastValue`) are already all-time in the existing VM. Confirmed.

## 6. Animation & motion

Per `animation-studio:data-visualization` skill + the OPS design system motion rule ("no spring physics, no bounce, one easing curve `cubic-bezier(0.22, 1, 0.36, 1)`"; see D8).

- **Card carousel** — implemented via `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)` (iOS 17+). **Not** `TabView(.page)` because the default TabView page transition uses spring physics. Programmatic snap on dot-tap uses `withAnimation(OPSStyle.Animation.standard)` which resolves to the canonical `cubic-bezier(0.22, 1, 0.36, 1)`. Light haptic on each swap via `UIImpactFeedbackGenerator(style: .light)`.
- **Card entry on first paint** — staggered: numeric values count up via `.contentTransition(.numericText())` with `withAnimation(.easeOut(duration: 0.8))`; bars/aging buckets fill left-to-right with 60ms stagger between bars using `.animation(OPSStyle.Animation.standard.delay(Double(index) * 0.06), value: hasAppeared)`.
- **Period change** — numbers morph via `.contentTransition(.numericText())`; bars `withAnimation(OPSStyle.Animation.standard)` re-tween to new heights (~500ms).
- **Header collapse** — `OPSStyle.Animation.fast` (matches existing `MoneyDashboardHeader` pattern at `BooksTabView.swift:100`); carousel opacity → 0, height → `collapsedStripHeight`, segments stick.
- **Reduced-motion fallback** — `@Environment(\.accessibilityReduceMotion)`. All `.animation(...)` modifiers conditioned on `reduceMotion ? .none : OPSStyle.Animation.standard`. Numbers render at final value immediately (no count-up). Bars render at final height (no fill-draw). Card swap on swipe becomes instant snap (still respects `.scrollTargetBehavior(.paging)`).

**Exception explicitly NOT taken:** drag-to-reorder is the only allowed spring use per `CLAUDE.md`. The carousel has no reorder gesture — strictly horizontal pagination — so no spring is admitted anywhere in this surface.

## 7. Tokens & visual system

All colors, spacing, radii, fonts trace to `OPS/Styles/OPSStyle.swift` and `ops-design-system/`. Tokens verified against `OPSStyle.swift` on 2026-05-11.

### 7.1 Colors

| Role | Token | Hex |
|------|-------|-----|
| Background | `OPSStyle.Colors.background` | #000000 (Color asset `Background`) |
| Card panel | `OPSStyle.Colors.cardBackground` | #191919 (Color asset `CardBackground`) |
| Card border | `OPSStyle.Colors.cardBorder` | `Color.white.opacity(0.2)` (consolidated standard) |
| Card border subtle | `OPSStyle.Colors.cardBorderSubtle` | `Color.white.opacity(0.05)` (use for less-prominent panels inside the carousel) |
| Primary text | `OPSStyle.Colors.primaryText` | #EDEDED |
| Secondary text | `OPSStyle.Colors.secondaryText` | #B5B5B5 |
| Tertiary text | `OPSStyle.Colors.tertiaryText` | #8A8A8A (axis labels, week labels under bars) |
| Accent | `OPSStyle.Colors.primaryAccent` | #6F94B0 steel blue (active dot, weighted-pipeline bars, focus rings) |
| Money in / positive / profit | `OPSStyle.Colors.successStatus` | #9DB582 olive |
| Attention / pending | `OPSStyle.Colors.warningStatus` | #C4A868 tan |
| Overdue / loss / destructive | `OPSStyle.Colors.errorStatus` | #93321A brick |
| A/R receivables (Card 3, 0–30d and 31–60d buckets) | `OPSStyle.Colors.accountingReceivables` | #D4A574 warm amber |
| A/R overdue (Card 3, 90d+ bucket) | `OPSStyle.Colors.accountingOverdue` | #93321A (same as errorStatus) |

### 7.2 Typography — three-font system (D7)

iOS uses all three OPS fonts. Source: `OPSStyle.swift` § Typography.

| Role | Token | Font |
|------|-------|------|
| Hero number (Card 1 net cash) | `OPSStyle.Typography.title` (32pt) | Mohave Light |
| Section labels (`P&L · NOV 2025`, dot pagination labels) | `OPSStyle.Typography.sectionLabel` | **Cake Mono Light** 11–14pt |
| Page title (`BOOKS` in AppHeader) | (existing AppHeader) | Cake Mono Light 22pt |
| Tile labels (`OUTSTANDING`, `FORECAST`) | `OPSStyle.Typography.captionBold` | JetBrains Mono Medium 14pt |
| Numeric values inside tiles | `OPSStyle.Typography.bodyBold` | JetBrains Mono Medium |
| Small captions (week labels, "12 inv") | `OPSStyle.Typography.smallCaption` | JetBrains Mono 12pt |
| Body copy | `OPSStyle.Typography.body` | Mohave |
| FAB action labels | `OPSStyle.Typography.buttonLabel` | Cake Mono Light 14pt |

All numbers render with `.monospacedDigit()` (tabular-lining built into JetBrains Mono).

### 7.3 Voice

Terse, tactical. UPPERCASE for authority labels; sentence case for content. "NET CASH" not "Net Cash This Month". `—` (em-dash) for empty states, never "N/A". No emoji. Copy follows `ops-design-system/project/README.md` § CONTENT FUNDAMENTALS and `ops-copywriter` skill.

## 8. Files changed

All paths verified to exist (or planned-to-exist) on 2026-05-11.

### 8.1 iOS source

| File | Op | Change |
|------|----|--------|
| `OPS/Views/Books/BooksTabView.swift` | Rewrite | New carousel-centric layout. Drops `MoneyDashboardHeader` mount. Drops `selectedSegmentRaw` default of `"PIPELINE"` → new default `"INVOICES"`. Removes the underline-segmented control's `.pipeline` case-handling. Mounts the new `HeroCarousel` + 3-segment list. Existing collapse-on-scroll preference-key wiring kept. |
| `OPS/Views/Books/BooksSection.swift` | Edit | Remove `.pipeline` case. Down from 4 to 3 cases (`.estimates`, `.invoices`, `.expenses`). Update `requiredPermission` switch and `fabActionLabel` switch accordingly. |
| `OPS/Views/Books/HeroCarousel.swift` | New | `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)` (D8 — not `TabView`). 5-card paged carousel with dot indicators, last-viewed persistence via `@AppStorage("books.lastViewedCard")`, permission filtering, reduced-motion handling. |
| `OPS/Views/Books/Cards/PLCard.swift` | New | Card 1 — In − Out = Net equation, margin progress bar, two drill-down tiles (Outstanding, Forecast). |
| `OPS/Views/Books/Cards/CashFlowCard.swift` | New | Card 2 — weekly paired bars using SwiftUI `Charts`, three tiles (Sales, Avg/wk, Days). Requires `paymentsByWeek` / `expensesByWeek` from ViewModel (§5.3). |
| `OPS/Views/Books/Cards/ARCard.swift` | New | Card 3 — aging-bucket horizontal bars, total outstanding hero, top-chase tile. Reuses bucket logic from existing `ARAgingDetailView.buckets`. |
| `OPS/Views/Books/Cards/ForecastCard.swift` | New | Card 4 — weighted pipeline bars by stage, close-rate tile, stale-count tile. Requires `weightedForecastByStage` from ViewModel (§5.2). |
| `OPS/Views/Books/Cards/JobsCard.swift` | New | Card 5 — diverging profit/loss bars for top 5 jobs, three tiles (Profitable count, Avg margin, Losers). Requires per-job rollup (§5.1). |
| `OPS/Views/Books/CollapsedCarouselStrip.swift` | New | One-line strip surfaced when scroll position collapses the hero. Shows active card's primary number + A/R glance + dot indicators. |
| `OPS/Views/Books/Components/PeriodPill.swift` | New | Single tappable pill (replaces existing `PeriodToggle` segmented row). Opens a period menu (30D / 90D / 6M / 1Y, plus This Month / Last Month / This Quarter / YTD additions — confirmed scope; existing `MoneyDashboardViewModel.Period` enum extended). |
| `OPS/ViewModels/MoneyDashboardViewModel.swift` | Edit | Add `paymentsByWeek`, `expensesByWeek`, `weightedForecastByStage`, `topProjectsByNet`, `profitableProjectCount`, `avgProjectMargin`, `losersProjectCount`. Period enum gains This-Month / Last-Month / This-Quarter / YTD cases (additive). Existing `topUnpaidInvoices` retained for Card 3 fall-back display. |
| `OPS/Network/Supabase/Repositories/ExpenseRepository.swift` | Edit | Add `fetchAllAllocations(companyId:)` — fetches `expense_project_allocations` rows for the company, used by Card 5 rollup. Read-only addition; no behavioural change to existing methods. |
| `OPS/Views/MainTabView.swift` | Edit | Coordinated with `PIPELINE TAB - P1-1`: `hasBooksAccess` drops `pipeline.view` from the OR-chain (books now gates only on `finances.view`/`estimates.view`/`expenses.view`). `booksAutoSkipDestination` loses the `.pipeline` case. New `pipelineTabIndex` is owned by the Pipeline-tab spawn — the rename to `booksTabIndex` here is coordinated with that spawn. |
| `OPS/Views/Components/FloatingActionMenu.swift` | Edit | (D6) Change `@AppStorage("books.selectedSegment")` default `"PIPELINE"` → `"INVOICES"`. Remove `case "PIPELINE":` from `orderedMoneyItems` switch. Retain `default: primaryId = "new-estimate"` fallback. Existing `new-lead` MONEY-group item stays (still authored from this menu even after Pipeline becomes its own tab; the FAB is global). |
| `OPS/Views/Money/Components/MoneyDashboardHeader.swift` | Delete | Replaced by `HeroCarousel` + `CollapsedCarouselStrip`. |
| `OPS/Views/Money/Components/SmartStatCarousel.swift` | Delete | Superseded by the new 5-card hero deck. |
| `OPS/Views/Money/Components/FinancialHealthBar.swift` | Delete | Content folded into `PLCard`. |
| `OPS/Views/Money/Components/PeriodToggle.swift` | Delete (if standalone) | Replaced by `PeriodPill`. Verify path before delete — may be inlined in `MoneyDashboardHeader`. |
| `OPS/Views/Money/Components/BreakdownSheet.swift` | Keep | Still reachable as the deep-detail drill from any tile that opens it; behaviour unchanged. |
| `OPS/Views/Books/ARAgingDetailView.swift` | Keep | "See all" destination from Card 3 tile. Behaviour unchanged. |
| `OPS/Views/Books/Pipeline/` directory | Move | All files (`PipelineSectionView.swift` and friends) move out to the new top-level tab under `PIPELINE TAB - P1-1`. Coordinated diff. |

### 8.2 Bible

| File | Section | Change |
|------|---------|--------|
| `ops-software-bible/09_FINANCIAL_SYSTEM.md` | § "Accounting Views" (lines 1140–1143) | (D1) Replace `AccountingDashboard.swift` row with `ARAgingDetailView.swift` row. Note when AccountingDashboard was removed in prior session. |
| `ops-software-bible/09_FINANCIAL_SYSTEM.md` | § "iOS BOOKS Tab (Phase 1, May 2026)" (lines 1424–1450) | (D2) Rewrite as Phase 2. Document carousel architecture, 5 cards, Pipeline-tab split, FAB integration, new per-job rollup. Reference this spec by path. |
| `ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md` | Books flow | Update to reflect the new "carousel + 3-segment list" mental model. |

### 8.3 Notable non-changes (verified)

- **Supabase schema:** zero migrations. All columns Card 5 needs already exist.
- **Permission rows:** zero changes to `role_permissions`. Permission gating shifts in Swift only.
- **Notification rail wiring:** existing `OpenInvoices` / `OpenExpenses` deep-links continue to land on Books (segment switch via `BooksSelectSegment` notification). `OpenEstimateDetails` and `OpenInvoiceDetails` deep-links continue to present sheets above whatever tab is foregrounded — unchanged.

## 9. Accessibility

- **VoiceOver:** each card has `accessibilityLabel` summarizing the key data point ("P&L for November 2025: net cash 42,180 dollars, up 12% month over month."). Card swap announces card-of-N to a live region.
- **Dynamic Type:** all numbers use OPSStyle font tokens which respect Dynamic Type. JetBrains Mono renders cleanly at all sizes.
- **Reduced motion:** see § 6.
- **Contrast:** all combos meet WCAG 4.5:1 minimum on the OPS dark canvas (verified in `ops-design-system/project/uploads/system.md`).
- **Touch targets:** all interactive elements ≥44pt; primary FAB 56pt.

## 10. Out of scope (explicit)

These belong to follow-up initiatives and must not creep into this implementation:

| Future work | Spawn / Plan |
|-------------|--------------|
| Pipeline tab buildout | `PIPELINE TAB - P1-1` (separately spawned) |
| Forward cashflow projection (Card 6) | `CASHFLOW FORECAST - P1-1` (separately spawned) |
| Smart-default card surfacing (data-driven first-view) | Books v2 |
| What-if scenarios on cards | Books v2 |
| Per-card period overrides (different period per card) | Not planned — anti-pattern |
| Reports as a separate top-level tab | Not planned — drill-from-card is the pattern |

## 11. Verification plan

Per OPS standards (`CLAUDE.md` § Perfection Standard):

1. Build with `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` — no simulator.
2. Manual flows on device:
   - Owner role: all 5 cards visible, swipe between, drill from each tile, verify numbers match raw data.
   - Operator role: Books visible with only relevant cards/segments; verify `finances.view` gating works.
   - Crew role: tab routes to `MyExpensesView`, never to hub.
   - Period selector change: numbers + bars animate to new values; cards 3 + 4 do NOT change.
   - Header collapse: scroll down → carousel collapses to strip; scroll up → re-expands.
   - Last-viewed persistence: open Card 3, kill app, relaunch → opens to Card 3.
   - Reduced-motion ON: all animations replaced with instant.
   - Offline: cached data still renders all cards; period change works against cache.
3. Pipeline tab split coordination: verified separately under `PIPELINE TAB - P1-1`. Books spec does not land until Pipeline tab is in place, OR Books lands first and Pipeline tab is built referencing the freed segment slot — coordinate sequence with user.
4. Notification rail integration: every existing notification that deep-links into Books still resolves correctly (invoices, estimates, expenses opens to correct segment + carousel context).

## 12. Implementation plan

After spec sign-off, transition to `superpowers:writing-plans` to produce the step-by-step implementation plan (file-by-file with verification gates).

## 13. Resolution

When the implementation lands and verification passes:

1. Update Supabase `bug_reports` row `1b038315-fb4a-44a1-b118-8e5e67578980` (project `ijeekuhbatykdomumfjx`) using verified columns (D9):

   ```sql
   UPDATE public.bug_reports
   SET status        = 'resolved',
       resolved_at   = now(),
       fixed_at      = now(),
       fix_notes     = 'Books tab reconstructed around a 5-card swipeable hero carousel (P&L, Cash Flow, A/R, Forecast, Jobs) with 3-segment list below. Pipeline split to its own top-level tab. See spec docs/superpowers/specs/2026-05-11-books-ui-reconstruction-design.md.'
   WHERE id = '1b038315-fb4a-44a1-b118-8e5e67578980';
   ```

   Confirm with `SELECT status, resolved_at, fixed_at, fix_notes FROM bug_reports WHERE id = '1b038315-...';` after.

2. Update `ops-software-bible/09_FINANCIAL_SYSTEM.md`:
   - Replace stale lines 1140–1143 (AccountingDashboard) — D1.
   - Rewrite lines 1424–1450 (Phase 1 BOOKS) — D2.
3. Update `ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md` Books flow.
4. Prepend the May 7 spec (`2026-05-07-books-tab-design.md`) with a banner: `> **Superseded by [2026-05-11-books-ui-reconstruction-design.md](2026-05-11-books-ui-reconstruction-design.md).** Phase 1 4-segment hub is no longer the shipped shape.`

## 14. Verified facts log

Recorded so the implementation plan can rely on these without re-verifying:

| Fact | Source | Verified |
|------|--------|----------|
| Supabase `invoices.project_id` is `uuid NULL` | `information_schema.columns` via MCP | 2026-05-11 |
| Supabase `expense_project_allocations.project_id` is `text NOT NULL` (legacy) | same | 2026-05-11 |
| Supabase `payment_milestones` table exists, 0 rows | `list_tables` | 2026-05-11 |
| `EstimateFilter` cases = `.all, .draft, .sent, .approved` | `OPS/ViewModels/EstimateViewModel.swift:23` | 2026-05-11 |
| `InvoiceFilter` cases = `.all, .unpaid, .overdue, .paid` | `OPS/ViewModels/InvoiceViewModel.swift:23` | 2026-05-11 |
| `Project` SwiftData model has no `estimatedAmount` | `OPS/DataModels/Project.swift` | 2026-05-11 |
| `FloatingActionMenu` is global (single instance in `MainTabView.swift:383`) | `OPS/Views/Components/FloatingActionMenu.swift` | 2026-05-11 |
| `@AppStorage("books.selectedSegment")` default `"PIPELINE"` exists in two places | `BooksTabView.swift:32`, `FloatingActionMenu.swift:114` | 2026-05-11 |
| `AccountingDashboard.swift` does not exist | `find ... -name AccountingDashboard*` returns empty | 2026-05-11 |
| `OPSStyle.Colors` tokens cited in §7 all exist | `OPSStyle.swift` grep | 2026-05-11 |
| OPS three-font system (Mohave / JetBrains Mono / Cake Mono Light) | `ops-design-system/project/SKILL.md` + `OPSStyle.swift:254-277` | 2026-05-11 |
| OPS motion rule (single easing curve, no spring except drag-reorder) | `ops-design-system/project/SKILL.md` | 2026-05-11 |
| Bug 1b038315 current state | `SELECT … FROM bug_reports WHERE id = '1b038315-...'` | 2026-05-11 |
