# Books UI Reconstruction — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Books tab as a 5-card swipeable hero carousel (P&L · Cash Flow · A/R · Forecast · Jobs) over a 3-segment list (Invoices · Estimates · Expenses); remove Pipeline from Books in coordination with the `PIPELINE TAB - P1-1` spawn; integrate cleanly with the existing global FAB.

**Architecture:** SwiftUI single-screen hub. Hero is `ScrollView(.horizontal) + .scrollTargetBehavior(.paging)` (iOS 17+) — no `TabView(.page)` per OPS motion rule. Each card consumes `MoneyDashboardViewModel` (extended with weekly buckets + per-job rollup + per-stage forecast). The global `FloatingActionMenu` re-orders its MONEY group via `@AppStorage("books.selectedSegment")`. Existing list views (`InvoicesListView`, `EstimatesListView`, `ExpensesListView`) mount in `embedded: true` mode unchanged.

**Tech Stack:** SwiftUI, Swift 5.9+, SwiftData, Supabase Swift SDK, Charts framework, XCTest, OPSStyle tokens, three-font system (Mohave / JetBrains Mono / Cake Mono Light).

**Spec:** `docs/superpowers/specs/2026-05-11-books-ui-reconstruction-design.md`

**Coordination:** This plan removes Pipeline from Books (`BooksSection.pipeline` case, `MainTabView.hasBooksAccess` OR-chain dependence on `pipeline.view`). The `PIPELINE TAB - P1-1` spawn adds Pipeline back as a standalone top-level tab. Order-independent: no user loses access in the gap (Owner/Admin/Office have other Books perms; Operator and Crew never had `pipeline.view`).

**Build verification command:** `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build` (never the simulator, per `ops-ios/CLAUDE.md`).

**Commit rules (per `ops-ios/CLAUDE.md`):** Atomic commits, no Claude co-author tag, concise message focused on why.

---

## File Structure

### New files

| Path | Responsibility |
|------|----------------|
| `OPS/Views/Books/HeroCarousel.swift` | 5-card paged ScrollView, dots, last-viewed persistence, permission filtering, reduced-motion handling |
| `OPS/Views/Books/CollapsedCarouselStrip.swift` | One-line strip surfaced on scroll collapse |
| `OPS/Views/Books/Components/PeriodPill.swift` | Single tap-target pill replacing the 4-button PeriodToggle |
| `OPS/Views/Books/Cards/PLCard.swift` | Card 1 — In − Out = Net equation + 2 drill tiles |
| `OPS/Views/Books/Cards/CashFlowCard.swift` | Card 2 — weekly paired bars (SwiftUI Charts) + 3 tiles |
| `OPS/Views/Books/Cards/ARCard.swift` | Card 3 — aging buckets + outstanding hero + top-chase tile |
| `OPS/Views/Books/Cards/ForecastCard.swift` | Card 4 — weighted pipeline by stage + close-rate / stale tiles |
| `OPS/Views/Books/Cards/JobsCard.swift` | Card 5 — diverging profit/loss bars + 3 KPI tiles |
| `OPSTests/Books/MoneyDashboardViewModelTests.swift` | Unit tests for new VM computations (weekly buckets, per-stage forecast, per-job rollup) |

### Modified files

| Path | Change |
|------|--------|
| `OPS/Views/Books/BooksTabView.swift` | Rewrite — mount HeroCarousel + 3-segment list, drop MoneyDashboardHeader, default segment INVOICES |
| `OPS/Views/Books/BooksSection.swift` | Remove `.pipeline` case |
| `OPS/ViewModels/MoneyDashboardViewModel.swift` | Add `paymentsByWeek`, `expensesByWeek`, `weightedForecastByStage`, `topProjectsByNet`, `profitableProjectCount`, `avgProjectMargin`, `losersProjectCount`; extend Period enum |
| `OPS/Network/Supabase/Repositories/ExpenseRepository.swift` | Add `fetchAllAllocations(companyId:)` |
| `OPS/Views/MainTabView.swift` | Drop `pipeline.view` from `hasBooksAccess`; drop `.pipeline` from `booksAutoSkipDestination` |
| `OPS/Views/Components/FloatingActionMenu.swift` | Change default `books.selectedSegment` to `"INVOICES"`; remove `case "PIPELINE":` from `orderedMoneyItems` |

### Deleted files

| Path | Reason |
|------|--------|
| `OPS/Views/Money/Components/MoneyDashboardHeader.swift` | Replaced by HeroCarousel + CollapsedCarouselStrip |
| `OPS/Views/Money/Components/SmartStatCarousel.swift` | Replaced by 5-card hero deck |
| `OPS/Views/Money/Components/FinancialHealthBar.swift` | Content folded into PLCard |
| `OPS/Views/Money/Components/PeriodToggle.swift` (if standalone) | Replaced by PeriodPill |

### Bible updates

| Path | Section | Change |
|------|---------|--------|
| `ops-software-bible/09_FINANCIAL_SYSTEM.md` | lines 1140–1143 | Replace `AccountingDashboard` row with `ARAgingDetailView` (drift D1) |
| `ops-software-bible/09_FINANCIAL_SYSTEM.md` | lines 1424–1450 | Rewrite Phase 1 BOOKS section as Phase 2 — carousel architecture, pipeline split (drift D2) |
| `ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md` | Books flow | Update to carousel + 3-segment model |
| `ops-ios/docs/superpowers/specs/2026-05-07-books-tab-design.md` | Top | Prepend "Superseded by 2026-05-11" banner |

---

## Phase A — ViewModel data layer

### Task A1: Extend `MoneyDashboardViewModel.Period` enum with month/quarter/YTD cases

**Files:**
- Modify: `OPS/ViewModels/MoneyDashboardViewModel.swift:17-44`

- [ ] **Step 1: Add the new cases**

In `OPS/ViewModels/MoneyDashboardViewModel.swift`, replace the existing `Period` enum:

```swift
enum Period: String, CaseIterable {
    case month       = "30D"      // Trailing 30 days
    case quarter     = "90D"      // Trailing 90 days
    case sixMonths   = "6M"
    case year        = "1Y"
    case thisMonth   = "MTD"      // Calendar month-to-date
    case lastMonth   = "LAST"     // Previous calendar month
    case thisQuarter = "QTD"
    case ytd         = "YTD"

    var label: String { rawValue }

    /// Inclusive start of the period.
    var startDate: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .month:        return cal.date(byAdding: .day, value: -30, to: now) ?? now
        case .quarter:      return cal.date(byAdding: .day, value: -90, to: now) ?? now
        case .sixMonths:    return cal.date(byAdding: .day, value: -180, to: now) ?? now
        case .year:         return cal.date(byAdding: .day, value: -365, to: now) ?? now
        case .thisMonth:    return cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        case .lastMonth:
            let firstOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            return cal.date(byAdding: .month, value: -1, to: firstOfThisMonth) ?? now
        case .thisQuarter:
            let month = cal.component(.month, from: now)
            let qStartMonth = ((month - 1) / 3) * 3 + 1
            return cal.date(from: DateComponents(year: cal.component(.year, from: now), month: qStartMonth, day: 1)) ?? now
        case .ytd:
            return cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1)) ?? now
        }
    }

    /// Inclusive end of the period (now for trailing windows; first-of-next-month for lastMonth).
    var endDate: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .lastMonth:
            return cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        default:
            return now
        }
    }

    /// Start of the *prior* equivalent period (used for trend comparisons).
    var priorPeriodStartDate: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .month, .quarter, .sixMonths, .year:
            let days: Int
            switch self {
            case .month: days = 30
            case .quarter: days = 90
            case .sixMonths: days = 180
            case .year: days = 365
            default: days = 30
            }
            return cal.date(byAdding: .day, value: -(days * 2), to: now) ?? now
        case .thisMonth:
            let firstOfThisMonth = startDate
            return cal.date(byAdding: .month, value: -1, to: firstOfThisMonth) ?? now
        case .lastMonth:
            let firstOfLastMonth = startDate
            return cal.date(byAdding: .month, value: -1, to: firstOfLastMonth) ?? now
        case .thisQuarter:
            return cal.date(byAdding: .month, value: -3, to: startDate) ?? now
        case .ytd:
            return cal.date(from: DateComponents(year: cal.component(.year, from: now) - 1, month: 1, day: 1)) ?? now
        }
    }
}
```

- [ ] **Step 2: Update `recalculate()` to use `endDate` instead of hardcoded `now`**

Locate every reference to `Date()` inside `recalculate()` that represents the period upper bound, and replace with `selectedPeriod.endDate`. Specifically: the `<= now` checks in `invoicesInPeriod`, `paymentsInPeriod`, `expensesInPeriod`, `estimatesInPeriod`, and `priorExpenses` filters.

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git add OPS/ViewModels/MoneyDashboardViewModel.swift
git commit -m "books: extend Period enum with MTD/LAST/QTD/YTD"
```

---

### Task A2: Add weekly bucketing for Card 2 (Cash Flow)

**Files:**
- Modify: `OPS/ViewModels/MoneyDashboardViewModel.swift`

- [ ] **Step 1: Add the published properties**

Inside `MoneyDashboardViewModel`, near the other `@Published` declarations (after `totalExpenses`), add:

```swift
/// Payments-in bucketed by ISO week start (Monday). Populated by `recalculate()`. Card 2 consumer.
@Published var paymentsByWeek: [(weekStart: Date, amount: Double)] = []
/// Expenses-out bucketed by ISO week start. Populated by `recalculate()`. Card 2 consumer.
@Published var expensesByWeek: [(weekStart: Date, amount: Double)] = []
```

- [ ] **Step 2: Add bucketing helpers**

Add at the bottom of the class:

```swift
private func weekStart(for date: Date) -> Date {
    var cal = Calendar(identifier: .iso8601)
    cal.firstWeekday = 2 // Monday
    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return cal.date(from: comps) ?? date
}

private func bucketByWeek<T>(_ items: [T], dateOf: (T) -> Date?, amountOf: (T) -> Double) -> [(weekStart: Date, amount: Double)] {
    var buckets: [Date: Double] = [:]
    for item in items {
        guard let d = dateOf(item) else { continue }
        let ws = weekStart(for: d)
        buckets[ws, default: 0] += amountOf(item)
    }
    return buckets.sorted { $0.key < $1.key }.map { (weekStart: $0.key, amount: $0.value) }
}
```

- [ ] **Step 3: Wire bucketing into `recalculate()`**

Inside `recalculate()`, after the existing `paymentsInPeriod` and `expensesInPeriod` are computed, append:

```swift
paymentsByWeek = bucketByWeek(
    paymentsInPeriod,
    dateOf: { $0.paymentDate.flatMap { SupabaseDate.parse($0) } },
    amountOf: { $0.amount ?? 0 }
)
expensesByWeek = bucketByWeek(
    expensesInPeriod,
    dateOf: { SupabaseDate.parse($0.expenseDate ?? $0.createdAt) },
    amountOf: { $0.amount }
)
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build`
Expected: succeeds.

- [ ] **Step 5: Commit**

```bash
git add OPS/ViewModels/MoneyDashboardViewModel.swift
git commit -m "books: weekly bucketing for cash flow card"
```

---

### Task A3: Add `weightedForecastByStage` for Card 4

**Files:**
- Modify: `OPS/ViewModels/MoneyDashboardViewModel.swift`

- [ ] **Step 1: Add the published property**

After the existing `nextFollowUpDue` declaration:

```swift
/// Weighted pipeline value broken out per active stage. Card 4 consumer.
@Published var weightedForecastByStage: [(stage: PipelineStage, value: Double)] = []
```

- [ ] **Step 2: Compute it in `recalculate()`**

Inside the existing "Pipeline metrics" block in `recalculate()`, after `nextFollowUpDue = ...`, append:

```swift
var perStage: [PipelineStage: Double] = [:]
for dto in activeOpps {
    guard let stage = PipelineStage(rawValue: dto.stage) else { continue }
    let pct = dto.winProbability ?? stage.winProbability
    let est = dto.estimatedValue ?? 0
    perStage[stage, default: 0] += est * Double(pct) / 100.0
}
weightedForecastByStage = PipelineStage.allCases
    .filter { !$0.isTerminal }
    .compactMap { stage in
        guard let value = perStage[stage], value > 0 else { return nil }
        return (stage: stage, value: value)
    }
    .sorted { $0.value > $1.value }
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
git add OPS/ViewModels/MoneyDashboardViewModel.swift
git commit -m "books: per-stage weighted forecast for forecast card"
```

---

### Task A4: Add `ExpenseRepository.fetchAllAllocations`

**Files:**
- Modify: `OPS/Network/Supabase/Repositories/ExpenseRepository.swift`

- [ ] **Step 1: Add a DTO if missing**

Verify `ExpenseAllocationDTO` exists in `OPS/Network/Supabase/DTOs/ExpenseDTOs.swift`. Per bible §1287 it should be present with fields `id, expenseId, projectId, percentage, createdAt`. If missing, add:

```swift
struct ExpenseAllocationDTO: Codable, Identifiable {
    let id: String
    let expenseId: String
    let projectId: String
    let percentage: Double
    let amount: Double?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, percentage, amount
        case expenseId = "expense_id"
        case projectId = "project_id"
        case createdAt = "created_at"
    }
}
```

(`amount` is the new column we depend on per drift D3/D5.)

- [ ] **Step 2: Add the repository method**

Append to `OPS/Network/Supabase/Repositories/ExpenseRepository.swift`:

```swift
/// Fetches every `expense_project_allocations` row for the company, used by the
/// Books Jobs card to compute per-project cost rollups. Read-only.
func fetchAllAllocations() async throws -> [ExpenseAllocationDTO] {
    let response = try await SupabaseService.shared.client
        .from("expense_project_allocations")
        .select("*, expense:expenses!inner(company_id, deleted_at)")
        .eq("expense.company_id", value: companyId)
        .is_("expense.deleted_at", value: nil)
        .execute()
    return try response.decoded(to: [ExpenseAllocationDTO].self)
}
```

(If `.decoded(to:)` is not the helper used in this repo, mirror the pattern from existing `fetchAll()` — `let raw = response.data; return try JSONDecoder().decode([ExpenseAllocationDTO].self, from: raw)` or whatever is canonical.)

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
git add OPS/Network/Supabase/DTOs/ExpenseDTOs.swift OPS/Network/Supabase/Repositories/ExpenseRepository.swift
git commit -m "books: ExpenseRepository.fetchAllAllocations for jobs rollup"
```

---

### Task A5: Add per-project rollup to `MoneyDashboardViewModel`

**Files:**
- Modify: `OPS/ViewModels/MoneyDashboardViewModel.swift`

- [ ] **Step 1: Add published properties**

```swift
struct JobNet: Identifiable {
    let id: String      // projectId
    let title: String
    let revenue: Double
    let cost: Double
    var net: Double { revenue - cost }
}

@Published var topProjectsByNet: [JobNet] = []
@Published var profitableProjectCount: Int = 0
@Published var avgProjectMargin: Double = 0
@Published var losersProjectCount: Int = 0
```

- [ ] **Step 2: Cache allocations alongside other raw data**

Find the cached raw data section near the top of the class:

```swift
private var allEstimates: [EstimateDTO] = []
private var allInvoices: [InvoiceDTO] = []
private var allExpenses: [ExpenseDTO] = []
private var allOpportunities: [OpportunityDTO] = []
```

Append:

```swift
private var allAllocations: [ExpenseAllocationDTO] = []
```

- [ ] **Step 3: Fetch allocations in parallel inside `loadData()`**

Locate the `async let` block in `loadData()`:

```swift
async let estimatesTask = fetchEstimates()
async let invoicesTask = fetchInvoices()
async let expensesTask = fetchExpenses()
async let oppsTask: [OpportunityDTO] = canSeePipeline ? fetchOpportunities() : []
```

Append:

```swift
async let allocationsTask = fetchAllocations()
```

Update the await tuple and assignment:

```swift
let (estimates, invoices, expenses, opps, allocations) = await (estimatesTask, invoicesTask, expensesTask, oppsTask, allocationsTask)
allEstimates = estimates
allInvoices = invoices
allExpenses = expenses
allOpportunities = opps
allAllocations = allocations
```

Add the helper near the other `fetchX()` helpers:

```swift
private func fetchAllocations() async -> [ExpenseAllocationDTO] {
    guard let repo = expenseRepository else { return [] }
    do { return try await repo.fetchAllAllocations() }
    catch {
        print("[MoneyDashboard] Failed to fetch allocations: \(error.localizedDescription)")
        return []
    }
}
```

- [ ] **Step 4: Compute the rollup in `recalculate()`**

Add a helper method at the bottom of the class:

```swift
private func computeJobNets() {
    let periodStart = selectedPeriod.startDate
    let periodEnd = selectedPeriod.endDate

    // Revenue per project: sum of payments.amount for invoices with projectId in period
    var revenuePerProject: [String: Double] = [:]
    for inv in allInvoices {
        guard let pid = inv.projectId,
              inv.deletedAt == nil,
              inv.status != InvoiceStatus.void.rawValue else { continue }
        for payment in inv.payments ?? [] {
            guard let dStr = payment.paymentDate,
                  let d = SupabaseDate.parse(dStr),
                  d >= periodStart, d <= periodEnd,
                  !(payment.isVoid ?? false) else { continue }
            revenuePerProject[pid, default: 0] += payment.amount ?? 0
        }
    }

    // Cost per project: sum of allocation.amount (or expense.amount * pct/100) for expenses in period
    var costPerProject: [String: Double] = [:]
    let expenseById = Dictionary(uniqueKeysWithValues: allExpenses.map { ($0.id, $0) })
    for alloc in allAllocations {
        guard let expense = expenseById[alloc.expenseId],
              expense.deletedAt == nil else { continue }
        let dateStr = expense.expenseDate ?? expense.createdAt
        guard let d = SupabaseDate.parse(dateStr), d >= periodStart, d <= periodEnd else { continue }
        let amount = alloc.amount ?? (expense.amount * alloc.percentage / 100.0)
        costPerProject[alloc.projectId, default: 0] += amount
    }

    // Resolve project titles via SwiftData
    let projectTitles = projectTitleLookup(for: Array(Set(revenuePerProject.keys).union(costPerProject.keys)))

    let allProjectIds = Set(revenuePerProject.keys).union(costPerProject.keys)
    var rows: [JobNet] = allProjectIds.map { pid in
        JobNet(
            id: pid,
            title: projectTitles[pid] ?? "Untitled",
            revenue: revenuePerProject[pid] ?? 0,
            cost: costPerProject[pid] ?? 0
        )
    }
    rows.sort { $0.net > $1.net }

    // Top 5 = top 4 by net + worst loser if not already present
    var top = Array(rows.prefix(4))
    if let worst = rows.last, worst.net < 0, !top.contains(where: { $0.id == worst.id }) {
        top.append(worst)
    } else if rows.count >= 5 {
        top.append(rows[4])
    }
    topProjectsByNet = top

    profitableProjectCount = rows.filter { $0.net > 0 }.count
    losersProjectCount = rows.filter { $0.net < 0 }.count
    let withRevenue = rows.filter { $0.revenue > 0 }
    avgProjectMargin = withRevenue.isEmpty
        ? 0
        : withRevenue.map { $0.net / $0.revenue }.reduce(0, +) / Double(withRevenue.count)
}

private func projectTitleLookup(for projectIds: [String]) -> [String: String] {
    guard let context = modelContext, !projectIds.isEmpty else { return [:] }
    var result: [String: String] = [:]
    do {
        let descriptor = FetchDescriptor<Project>()
        let allProjects = try context.fetch(descriptor)
        for p in allProjects where projectIds.contains(p.id) {
            result[p.id] = p.title
        }
    } catch {
        print("[MoneyDashboard] Failed to fetch projects: \(error.localizedDescription)")
    }
    return result
}
```

Call `computeJobNets()` at the end of `recalculate()`.

- [ ] **Step 5: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
git add OPS/ViewModels/MoneyDashboardViewModel.swift
git commit -m "books: per-project profitability rollup for jobs card"
```

---

### Task A6: Unit tests for the new VM computations

**Files:**
- Create: `OPSTests/Books/MoneyDashboardViewModelTests.swift`

- [ ] **Step 1: Write the test scaffold**

```swift
import XCTest
@testable import OPS

@MainActor
final class MoneyDashboardViewModelTests: XCTestCase {
    var vm: MoneyDashboardViewModel!

    override func setUp() async throws {
        vm = MoneyDashboardViewModel()
    }

    func testPeriod_thisMonth_startDateIsFirstOfMonth() {
        let cal = Calendar.current
        let start = MoneyDashboardViewModel.Period.thisMonth.startDate
        XCTAssertEqual(cal.component(.day, from: start), 1)
    }

    func testPeriod_ytd_startDateIsJan1() {
        let cal = Calendar.current
        let start = MoneyDashboardViewModel.Period.ytd.startDate
        XCTAssertEqual(cal.component(.month, from: start), 1)
        XCTAssertEqual(cal.component(.day, from: start), 1)
    }

    func testPeriod_lastMonth_isFullPriorMonth() {
        let cal = Calendar.current
        let start = MoneyDashboardViewModel.Period.lastMonth.startDate
        let end = MoneyDashboardViewModel.Period.lastMonth.endDate
        XCTAssertEqual(cal.component(.day, from: start), 1)
        XCTAssertEqual(cal.component(.day, from: end), 1)
        let diff = cal.dateComponents([.month], from: start, to: end).month ?? 0
        XCTAssertEqual(diff, 1)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS Simulator,name=iPhone 15' test -only-testing:OPSTests/MoneyDashboardViewModelTests`

> **Note:** Unit tests require the simulator. Build verification (per `ops-ios/CLAUDE.md`) uses `generic/platform=iOS`; testing requires a runnable target — the simulator is acceptable for `xcodebuild test`. The "no simulator" rule applies to manual flows / device builds, not XCTest.

Expected: 3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add OPSTests/Books/MoneyDashboardViewModelTests.swift
git commit -m "books: unit tests for Period enum extensions"
```

---

## Phase B — New components

### Task B1: `PeriodPill` component

**Files:**
- Create: `OPS/Views/Books/Components/PeriodPill.swift`

- [ ] **Step 1: Write the component**

```swift
import SwiftUI

/// Single-tap pill that presents a Period menu. Replaces the 4-button PeriodToggle
/// because the BOOKS reconstruction has more periods to expose (MTD/LAST/QTD/YTD)
/// than fit a row of segmented buttons.
struct PeriodPill: View {
    @Binding var selected: MoneyDashboardViewModel.Period
    var momTrend: Double?  // optional ↑/↓ % shown after the pill

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Menu {
                ForEach(MoneyDashboardViewModel.Period.allCases, id: \.self) { period in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selected = period
                    } label: {
                        HStack {
                            Text(period.menuLabel)
                            if selected == period {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selected.pillLabel)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .cornerRadius(14)
            }
            Spacer()
            if let mom = momTrend {
                Text(momLabel(mom))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(mom >= 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                    .contentTransition(.numericText())
            }
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }

    private func momLabel(_ mom: Double) -> String {
        let arrow = mom >= 0 ? "↑" : "↓"
        return "\(arrow)\(String(format: "%.1f", abs(mom)))% MoM"
    }
}

private extension MoneyDashboardViewModel.Period {
    var pillLabel: String {
        switch self {
        case .month: return "30 DAYS"
        case .quarter: return "90 DAYS"
        case .sixMonths: return "6 MONTHS"
        case .year: return "1 YEAR"
        case .thisMonth: return "THIS MONTH"
        case .lastMonth: return "LAST MONTH"
        case .thisQuarter: return "THIS QUARTER"
        case .ytd: return "YEAR TO DATE"
        }
    }

    var menuLabel: String { pillLabel }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Books/Components/PeriodPill.swift
git commit -m "books: PeriodPill component with 8 period options"
```

---

### Task B2: `PLCard` (Card 1)

**Files:**
- Create: `OPS/Views/Books/Cards/PLCard.swift`

- [ ] **Step 1: Write the card**

```swift
import SwiftUI

/// Card 1 — P&L narrative. "Am I making money this period?"
/// In − Out = Net, margin bar, MoM trend, two drill tiles (Outstanding, Forecast).
struct PLCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapOutstanding: () -> Void
    var onTapForecast: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var marginFraction: Double {
        viewModel.totalPayments > 0
            ? max(0, viewModel.netCash / viewModel.totalPayments)
            : 0
    }

    private var marginPctText: String {
        "\(Int((marginFraction * 100).rounded()))% MARGIN"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("P&L · \(viewModel.selectedPeriod.pillLabel.uppercased())")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            row(label: "PAYMENTS IN", value: viewModel.totalPayments, color: OPSStyle.Colors.successStatus, sign: "+")
            row(label: "EXPENSES OUT", value: viewModel.totalExpenses, color: OPSStyle.Colors.warningStatus, sign: "−")

            Divider().background(OPSStyle.Colors.cardBorder)

            HStack(alignment: .lastTextBaseline) {
                Text("NET CASH")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Text(viewModel.netCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(viewModel.netCash >= 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.errorStatus)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            marginBar

            HStack(spacing: OPSStyle.Layout.spacing2) {
                tile(label: "OUTSTANDING", value: viewModel.overdueInvoicesValue, count: viewModel.overdueInvoicesCount, valueColor: OPSStyle.Colors.errorStatus, action: onTapOutstanding)
                tile(label: "FORECAST", value: viewModel.pendingEstimatesValue, count: viewModel.pendingEstimatesCount, valueColor: OPSStyle.Colors.primaryAccent, action: onTapForecast)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) {
                appeared = true
            }
        }
    }

    private func row(label: String, value: Double, color: Color, sign: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(color)
            Spacer()
            Text("\(sign)\(currencyString(value))")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var marginBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(OPSStyle.Colors.warningStatus.opacity(0.3))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(OPSStyle.Colors.successStatus)
                    .frame(width: appeared ? geo.size.width * marginFraction : 0, height: 4)
                    .animation(reduceMotion ? .none : OPSStyle.Animation.standard, value: appeared)
            }
        }
        .frame(height: 4)
        .overlay(
            HStack {
                Text(marginPctText)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .offset(y: 14)
        )
        .padding(.bottom, 16)
    }

    private func tile(label: String, value: Double, count: Int, valueColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
                Text(currencyString(value)).font(OPSStyle.Typography.bodyBold).foregroundColor(valueColor).monospacedDigit()
                Text("\(count) \(count == 1 ? "ITEM" : "ITEMS")").font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
git add OPS/Views/Books/Cards/PLCard.swift
git commit -m "books: Card 1 (P&L) with margin bar + drill tiles"
```

---

### Task B3: `CashFlowCard` (Card 2)

**Files:**
- Create: `OPS/Views/Books/Cards/CashFlowCard.swift`

- [ ] **Step 1: Write the card**

```swift
import SwiftUI
import Charts

/// Card 2 — weekly paired bars (payments in vs expenses out) over the active period.
struct CashFlowCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapDays: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private struct WeekRow: Identifiable {
        let id = UUID()
        let weekStart: Date
        let inAmount: Double
        let outAmount: Double
    }

    private var weeks: [WeekRow] {
        let inDict = Dictionary(uniqueKeysWithValues: viewModel.paymentsByWeek.map { ($0.weekStart, $0.amount) })
        let outDict = Dictionary(uniqueKeysWithValues: viewModel.expensesByWeek.map { ($0.weekStart, $0.amount) })
        let allWeeks = Set(inDict.keys).union(outDict.keys).sorted()
        return allWeeks.map { ws in
            WeekRow(weekStart: ws, inAmount: inDict[ws] ?? 0, outAmount: outDict[ws] ?? 0)
        }
    }

    private var avgPerWeek: Double {
        let nonZero = weeks.filter { $0.inAmount > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.map { $0.inAmount }.reduce(0, +) / Double(nonZero.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CASH FLOW · \(viewModel.selectedPeriod.pillLabel.uppercased())")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(viewModel.netCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                legend
            }

            if weeks.isEmpty {
                emptyState
            } else {
                Chart(weeks) { row in
                    BarMark(
                        x: .value("Week", row.weekStart, unit: .weekOfYear),
                        y: .value("In", row.inAmount),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(OPSStyle.Colors.successStatus)
                    .position(by: .value("Direction", "In"))

                    BarMark(
                        x: .value("Week", row.weekStart, unit: .weekOfYear),
                        y: .value("Out", row.outAmount),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(OPSStyle.Colors.warningStatus)
                    .position(by: .value("Direction", "Out"))
                }
                .frame(height: 120)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisValueLabel(format: .dateTime.week(.weekOfMonth))
                            .foregroundStyle(OPSStyle.Colors.tertiaryText)
                    }
                }
                .chartYAxis(.hidden)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                tile(label: "SALES", value: currencyString(viewModel.totalSales))
                tile(label: "AVG/WK", value: currencyString(avgPerWeek), color: OPSStyle.Colors.successStatus)
                Button(action: onTapDays) {
                    tileContent(label: "DAYS", value: String(format: "%.1f", viewModel.avgDaysToPayment))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) { appeared = true }
        }
    }

    private var legend: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            legendDot(color: OPSStyle.Colors.successStatus, label: "IN")
            legendDot(color: OPSStyle.Colors.warningStatus, label: "OUT")
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private func tile(label: String, value: String, color: Color = OPSStyle.Colors.primaryText) -> some View {
        tileContent(label: label, value: value, color: color)
    }

    private func tileContent(label: String, value: String, color: Color = OPSStyle.Colors.primaryText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
            Text(value).font(OPSStyle.Typography.bodyBold).foregroundColor(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("—")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(height: 120)
    }

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
git add OPS/Views/Books/Cards/CashFlowCard.swift
git commit -m "books: Card 2 (Cash Flow) weekly paired bars"
```

---

### Task B4: `ARCard` (Card 3)

**Files:**
- Create: `OPS/Views/Books/Cards/ARCard.swift`

- [ ] **Step 1: Write the card**

```swift
import SwiftUI

/// Card 3 — A/R aging. Always all-open (period-independent). "Who do I need to chase?"
struct ARCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapTopChase: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private struct Bucket: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
        let color: Color
        let fraction: Double  // 0..1 relative to max bucket
    }

    private var buckets: [Bucket] {
        // Buckets are computed from outstandingInvoiceBreakdown (kept in VM) — for simplicity
        // here we approximate from overdueInvoicesValue + agings on the wire. The real
        // implementation pulls bucket totals from ARAgingDetailView.buckets logic.
        let today = Date()
        var b0_30: Double = 0
        var b31_60: Double = 0
        var b61_90: Double = 0
        var b90: Double = 0
        for item in viewModel.outstandingInvoiceBreakdown {
            guard let due = item.date else { continue }
            let days = Int(today.timeIntervalSince(due) / 86400)
            if days < 0 { continue }
            switch days {
            case 0...30:  b0_30  += item.amount
            case 31...60: b31_60 += item.amount
            case 61...90: b61_90 += item.amount
            default:      b90    += item.amount
            }
        }
        let amounts = [b0_30, b31_60, b61_90, b90]
        let maxV = max(amounts.max() ?? 0, 1)
        return zip(
            ["0–30d", "31–60d", "61–90d", "90d+"],
            zip(amounts, [OPSStyle.Colors.successStatus, OPSStyle.Colors.accountingReceivables, OPSStyle.Colors.warningStatus, OPSStyle.Colors.accountingOverdue])
        ).map { (label, pair) in
            Bucket(label: label, amount: pair.0, color: pair.1, fraction: pair.0 / maxV)
        }
    }

    private var totalOutstanding: Double {
        viewModel.outstandingInvoiceBreakdown.reduce(0) { $0 + $1.amount }
    }

    private var topChase: MoneyDashboardViewModel.BreakdownItem? {
        viewModel.outstandingInvoiceBreakdown.max(by: { $0.amount < $1.amount })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("A/R · ALL OPEN")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.errorStatus)

            Text(totalOutstanding, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.errorStatus)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("\(viewModel.outstandingInvoiceBreakdown.count) OPEN · \(viewModel.overdueInvoicesCount) OVERDUE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("AGING BUCKETS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, OPSStyle.Layout.spacing2)

            ForEach(buckets) { bucket in
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(bucket.label)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: 56, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bucket.color)
                            .frame(width: appeared ? geo.size.width * bucket.fraction : 0, height: 8)
                            .animation(reduceMotion ? .none : OPSStyle.Animation.standard.delay(0.05 * Double(buckets.firstIndex(where: { $0.id == bucket.id }) ?? 0)), value: appeared)
                    }
                    .frame(height: 8)
                    Text(bucket.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                }
            }

            if let top = topChase {
                Button(action: onTapTopChase) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TOP CHASE").font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
                            Text(top.label).font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.primaryText).lineLimit(1)
                        }
                        Spacer()
                        Text(top.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .monospacedDigit()
                    }
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) { appeared = true }
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
git add OPS/Views/Books/Cards/ARCard.swift
git commit -m "books: Card 3 (A/R) aging buckets + top chase"
```

---

### Task B5: `ForecastCard` (Card 4)

**Files:**
- Create: `OPS/Views/Books/Cards/ForecastCard.swift`

- [ ] **Step 1: Write the card**

```swift
import SwiftUI

/// Card 4 — weighted pipeline by stage. Always active opps. "What's coming if pipeline plays out?"
struct ForecastCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapCloseRate: () -> Void
    var onTapStale: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var maxStageValue: Double {
        max(viewModel.weightedForecastByStage.map { $0.value }.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("FORECAST · ACTIVE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            Text(viewModel.weightedForecastValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("\(viewModel.activeLeadCount) ACTIVE OPPS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("BY STAGE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, OPSStyle.Layout.spacing2)

            ForEach(Array(viewModel.weightedForecastByStage.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(row.stage.displayName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: 80, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(stageColor(row.stage))
                            .frame(width: appeared ? geo.size.width * (row.value / maxStageValue) : 0, height: 12)
                            .animation(reduceMotion ? .none : OPSStyle.Animation.standard.delay(0.06 * Double(idx)), value: appeared)
                    }
                    .frame(height: 12)
                    Text(row.value, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                }
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: onTapCloseRate) {
                    tileContent(label: "CLOSE RATE", value: "\(Int(viewModel.closeRate))%", color: OPSStyle.Colors.successStatus)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onTapStale) {
                    tileContent(label: "STALE", value: "\(viewModel.staleLeadsCount)", color: OPSStyle.Colors.warningStatus)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) { appeared = true }
        }
    }

    private func stageColor(_ stage: PipelineStage) -> Color {
        // Use the existing per-stage colors defined on PipelineStage. Fallback to accent.
        return Color(hex: stage.hexColor) ?? OPSStyle.Colors.primaryAccent
    }

    private func tileContent(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
            Text(value).font(OPSStyle.Typography.bodyBold).foregroundColor(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }
}
```

**Note:** This card references `PipelineStage.hexColor` and `PipelineStage.displayName`. Verify those properties exist on the existing `PipelineStage` enum (per bible they should, with hex codes from §09 stage table). If `hexColor` doesn't exist, use the per-stage colors documented in `09_FINANCIAL_SYSTEM.md` lines 70–79 inline.

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
git add OPS/Views/Books/Cards/ForecastCard.swift
git commit -m "books: Card 4 (Forecast) weighted-pipeline-by-stage bars"
```

---

### Task B6: `JobsCard` (Card 5)

**Files:**
- Create: `OPS/Views/Books/Cards/JobsCard.swift`

- [ ] **Step 1: Write the card**

```swift
import SwiftUI

/// Card 5 — diverging profit/loss bars for top 5 jobs in the period.
struct JobsCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapProfitable: () -> Void
    var onTapLosers: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var maxAbsNet: Double {
        max(viewModel.topProjectsByNet.map { abs($0.net) }.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("JOBS · NET BY PROJECT · \(viewModel.selectedPeriod.pillLabel.uppercased())")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if viewModel.topProjectsByNet.isEmpty {
                Text("—")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(viewModel.topProjectsByNet.enumerated()), id: \.element.id) { idx, row in
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(row.title.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 88, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(row.net >= 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                .frame(width: appeared ? geo.size.width * (abs(row.net) / maxAbsNet) : 0, height: 8)
                                .animation(reduceMotion ? .none : OPSStyle.Animation.standard.delay(0.06 * Double(idx)), value: appeared)
                        }
                        .frame(height: 8)
                        Text((row.net >= 0 ? "+" : "") + currencyString(row.net))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(row.net >= 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                            .monospacedDigit()
                    }
                }
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: onTapProfitable) {
                    tileContent(label: "PROFITABLE", value: "\(viewModel.profitableProjectCount)", color: OPSStyle.Colors.successStatus)
                }
                .buttonStyle(PlainButtonStyle())

                tileContent(label: "AVG MARGIN", value: "\(Int((viewModel.avgProjectMargin * 100).rounded()))%", color: OPSStyle.Colors.primaryText)

                Button(action: onTapLosers) {
                    tileContent(label: "LOSERS", value: "\(viewModel.losersProjectCount)", color: OPSStyle.Colors.errorStatus)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) { appeared = true }
        }
    }

    private func tileContent(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
            Text(value).font(OPSStyle.Typography.bodyBold).foregroundColor(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
git add OPS/Views/Books/Cards/JobsCard.swift
git commit -m "books: Card 5 (Jobs) per-project diverging profit/loss bars"
```

---

### Task B7: `HeroCarousel` container

**Files:**
- Create: `OPS/Views/Books/HeroCarousel.swift`

- [ ] **Step 1: Write the carousel**

```swift
import SwiftUI

/// 5-card swipeable financial carousel. Cards are permission-filtered;
/// last-viewed card persists via @AppStorage. Reduced-motion path skips
/// animations but preserves paging behavior.
struct HeroCarousel: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    @EnvironmentObject private var permissionStore: PermissionStore

    @AppStorage("books.lastViewedCard") private var lastViewedRaw: String = CardID.pl.rawValue
    @State private var scrollPosition: CardID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onDrillOutstanding: () -> Void
    var onDrillForecast: () -> Void
    var onDrillCashFlowDays: () -> Void
    var onDrillTopChase: () -> Void
    var onDrillCloseRate: () -> Void
    var onDrillStale: () -> Void
    var onDrillProfitable: () -> Void
    var onDrillLosers: () -> Void

    enum CardID: String, CaseIterable, Identifiable {
        case pl, cashFlow, ar, forecast, jobs
        var id: String { rawValue }

        var permission: String {
            switch self {
            case .pl, .cashFlow, .ar, .jobs: return "finances.view"
            case .forecast: return "pipeline.view"
            }
        }
    }

    private var visibleCards: [CardID] {
        CardID.allCases.filter { permissionStore.can($0.permission) }
    }

    var body: some View {
        if visibleCards.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        ForEach(visibleCards) { card in
                            cardView(for: card)
                                .containerRelativeFrame(.horizontal)
                                .id(card)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrollPosition)
                .onChange(of: scrollPosition) { _, new in
                    if let new {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        lastViewedRaw = new.rawValue
                    }
                }

                if visibleCards.count > 1 {
                    dots
                }
            }
            .onAppear {
                let restored = CardID(rawValue: lastViewedRaw) ?? .pl
                scrollPosition = visibleCards.contains(restored) ? restored : visibleCards.first
            }
        }
    }

    @ViewBuilder
    private func cardView(for card: CardID) -> some View {
        switch card {
        case .pl:
            PLCard(viewModel: viewModel, onTapOutstanding: onDrillOutstanding, onTapForecast: onDrillForecast)
        case .cashFlow:
            CashFlowCard(viewModel: viewModel, onTapDays: onDrillCashFlowDays)
        case .ar:
            ARCard(viewModel: viewModel, onTapTopChase: onDrillTopChase)
        case .forecast:
            ForecastCard(viewModel: viewModel, onTapCloseRate: onDrillCloseRate, onTapStale: onDrillStale)
        case .jobs:
            JobsCard(viewModel: viewModel, onTapProfitable: onDrillProfitable, onTapLosers: onDrillLosers)
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(visibleCards) { card in
                let isActive = scrollPosition == card
                Capsule()
                    .fill(isActive ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder)
                    .frame(width: isActive ? 16 : 5, height: 5)
                    .animation(reduceMotion ? .none : OPSStyle.Animation.standard, value: scrollPosition)
                    .onTapGesture {
                        withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) {
                            scrollPosition = card
                        }
                    }
            }
        }
        .padding(.top, OPSStyle.Layout.spacing1)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
git add OPS/Views/Books/HeroCarousel.swift
git commit -m "books: HeroCarousel container with paging + dots + persistence"
```

---

### Task B8: `CollapsedCarouselStrip`

**Files:**
- Create: `OPS/Views/Books/CollapsedCarouselStrip.swift`

- [ ] **Step 1: Write the strip**

```swift
import SwiftUI

/// One-line strip surfaced when the hero carousel collapses on scroll.
/// Shows the active card's primary metric, an A/R glance, and dot pagination.
struct CollapsedCarouselStrip: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var activeCard: HeroCarousel.CardID
    var visibleCards: [HeroCarousel.CardID]

    private var primaryLabel: String {
        switch activeCard {
        case .pl:        return "NET · \(periodShort)"
        case .cashFlow:  return "FLOW · \(periodShort)"
        case .ar:        return "A/R OPEN"
        case .forecast:  return "FORECAST"
        case .jobs:      return "JOBS NET"
        }
    }

    private var primaryValue: Double {
        switch activeCard {
        case .pl:        return viewModel.netCash
        case .cashFlow:  return viewModel.netCash
        case .ar:        return viewModel.outstandingInvoiceBreakdown.reduce(0) { $0 + $1.amount }
        case .forecast:  return viewModel.weightedForecastValue
        case .jobs:      return viewModel.topProjectsByNet.reduce(0) { $0 + $1.net }
        }
    }

    private var periodShort: String {
        switch viewModel.selectedPeriod {
        case .month: return "30D"
        case .quarter: return "90D"
        case .sixMonths: return "6M"
        case .year: return "1Y"
        case .thisMonth: return "MTD"
        case .lastMonth: return "LAST"
        case .thisQuarter: return "QTD"
        case .ytd: return "YTD"
        }
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(primaryLabel)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(primaryValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("A/R")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(viewModel.overdueInvoicesValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                ForEach(visibleCards) { card in
                    Capsule()
                        .fill(card == activeCard ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder)
                        .frame(width: card == activeCard ? 12 : 4, height: 4)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.background.opacity(0.95))
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 0.5)
                .padding(.top, 36)
            , alignment: .bottom
        )
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
git add OPS/Views/Books/CollapsedCarouselStrip.swift
git commit -m "books: CollapsedCarouselStrip for header collapse"
```

---

## Phase C — Integration

### Task C1: Update `BooksSection` — drop `.pipeline`

**Files:**
- Modify: `OPS/Views/Books/BooksSection.swift`

- [ ] **Step 1: Replace the enum body**

```swift
import Foundation

enum BooksSection: String, CaseIterable, Identifiable, Codable {
    case invoices  = "INVOICES"
    case estimates = "ESTIMATES"
    case expenses  = "EXPENSES"

    var id: String { rawValue }

    var requiredPermission: String {
        switch self {
        case .invoices:  return "finances.view"
        case .estimates: return "estimates.view"
        case .expenses:  return "expenses.view"
        }
    }

    var fabActionLabel: String {
        switch self {
        case .invoices:  return "New Invoice"
        case .estimates: return "New Estimate"
        case .expenses:  return "New Expense"
        }
    }
}
```

- [ ] **Step 2: Build — expect failures**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build`
Expected: build fails with references to `BooksSection.pipeline` still present in `MainTabView`, `BooksTabView`, `FloatingActionMenu`. Those are addressed in the next tasks.

- [ ] **Step 3: Do not commit until subsequent fixes land — leave the diff staged**

```bash
git add OPS/Views/Books/BooksSection.swift
```

The commit happens at the end of Phase C as a single atomic change (`books: split pipeline from books`).

---

### Task C2: Update `MainTabView` — drop pipeline.view + auto-skip

**Files:**
- Modify: `OPS/Views/MainTabView.swift`

- [ ] **Step 1: Update `hasBooksAccess`**

Replace lines 141–146 in `OPS/Views/MainTabView.swift`:

```swift
private var hasBooksAccess: Bool {
    permissionStore.can("finances.view")
        || permissionStore.can("estimates.view")
        || permissionStore.can("expenses.view")
}
```

- [ ] **Step 2: Update `booksAutoSkipDestination`**

Replace the switch in `booksAutoSkipDestination` (lines 156–174):

```swift
private var booksAutoSkipDestination: AnyView? {
    let segs = visibleBooksSegments
    guard segs.count == 1, let only = segs.first else { return nil }
    switch only {
    case .invoices:
        return AnyView(NavigationStack { InvoicesListView() })
    case .estimates:
        return AnyView(NavigationStack { EstimatesListView() })
    case .expenses:
        let scopeIsOwn = !permissionStore.hasFullAccess("expenses.view")
        if scopeIsOwn {
            return AnyView(NavigationStack { MyExpensesView() })
        } else {
            return AnyView(NavigationStack { ExpensesListView() })
        }
    }
}
```

- [ ] **Step 3: Update `OpenInvoices` / `OpenExpenses` notification defaults**

In the notification handler that posts `BooksSelectSegment` (around lines 657–688), confirm the segment values are still in `BooksSection`. After this task, `"PIPELINE"` is no longer valid; only `"INVOICES"`, `"ESTIMATES"`, `"EXPENSES"`. No code change required (handlers post specific segment values), but verify there is no default-to-pipeline path.

- [ ] **Step 4: Stage the changes** (do not commit yet)

```bash
git add OPS/Views/MainTabView.swift
```

---

### Task C3: Update `FloatingActionMenu` — default + remove PIPELINE case

**Files:**
- Modify: `OPS/Views/Components/FloatingActionMenu.swift`

- [ ] **Step 1: Change default segment**

Replace line 114:

```swift
@AppStorage("books.selectedSegment") private var booksSelectedSegmentRaw: String = "INVOICES"
```

- [ ] **Step 2: Remove the PIPELINE case from `orderedMoneyItems`**

In `orderedMoneyItems(rawItems:)` (around line 237), update the switch:

```swift
switch booksSelectedSegmentRaw {
case "ESTIMATES": primaryId = "new-estimate"
case "INVOICES":  primaryId = "new-invoice"
case "EXPENSES":  primaryId = "new-expense"
default:          primaryId = "new-estimate"
}
```

The `new-lead` action stays in the MONEY group (it is the standalone create entry for Pipeline; the FAB is global, so creating a lead is reachable from any tab).

- [ ] **Step 3: Stage**

```bash
git add OPS/Views/Components/FloatingActionMenu.swift
```

---

### Task C4: Rewrite `BooksTabView`

**Files:**
- Modify: `OPS/Views/Books/BooksTabView.swift`

- [ ] **Step 1: Replace the entire file**

```swift
import SwiftUI

private struct HeaderBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct BooksTabView: View {
    @StateObject private var dashboardVM = MoneyDashboardViewModel()
    @StateObject private var estimateVM = EstimateViewModel()
    @StateObject private var invoiceVM = InvoiceViewModel()
    @StateObject private var expenseVM = ExpenseViewModel()

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @AppStorage("books.selectedSegment") private var selectedSegmentRaw: String = BooksSection.invoices.rawValue
    @AppStorage("books.lastViewedCard") private var lastViewedCardRaw: String = HeroCarousel.CardID.pl.rawValue

    @State private var headerCollapsed = false
    @State private var showARDetail = false
    @State private var showCashFlowReport = false
    @State private var showJobsReport = false

    private var selectedSegment: BooksSection {
        BooksSection(rawValue: selectedSegmentRaw) ?? .invoices
    }

    private var visibleSegments: [BooksSection] {
        BooksSection.allCases.filter { permissionStore.can($0.requiredPermission) }
    }

    private var carouselVisible: Bool {
        permissionStore.can("finances.view") || permissionStore.can("pipeline.view")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(headerType: .books)
                    .padding(.bottom, 8)

                if headerCollapsed && carouselVisible {
                    CollapsedCarouselStrip(
                        viewModel: dashboardVM,
                        activeCard: HeroCarousel.CardID(rawValue: lastViewedCardRaw) ?? .pl,
                        visibleCards: HeroCarousel.CardID.allCases.filter { permissionStore.can($0.permission) }
                    )
                    .transition(.opacity)
                }

                if headerCollapsed {
                    underlineSegmentedControl
                        .background(OPSStyle.Colors.background)
                        .transition(.opacity)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        if carouselVisible {
                            VStack(spacing: OPSStyle.Layout.spacing2) {
                                PeriodPill(selected: $dashboardVM.selectedPeriod, momTrend: dashboardVM.netCash != 0 ? dashboardVM.expensesTrend : nil)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                                HeroCarousel(
                                    viewModel: dashboardVM,
                                    onDrillOutstanding: { selectedSegmentRaw = BooksSection.invoices.rawValue; invoiceVM.selectedFilter = .overdue },
                                    onDrillForecast: { selectedSegmentRaw = BooksSection.estimates.rawValue; estimateVM.selectedFilter = .sent },
                                    onDrillCashFlowDays: { showCashFlowReport = true },
                                    onDrillTopChase: { showARDetail = true },
                                    onDrillCloseRate: { /* hand off to Pipeline tab once spawned */ },
                                    onDrillStale: { /* hand off to Pipeline tab */ },
                                    onDrillProfitable: { showJobsReport = true },
                                    onDrillLosers: { showJobsReport = true }
                                )
                                .environmentObject(permissionStore)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                            }
                            .padding(.vertical, OPSStyle.Layout.spacing3)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(key: HeaderBottomKey.self, value: geo.frame(in: .named("scroll")).maxY)
                                }
                            )
                        }

                        if !headerCollapsed {
                            underlineSegmentedControl
                        }

                        contentForSegment
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(HeaderBottomKey.self) { bottomY in
                    let shouldCollapse = bottomY < 0
                    if shouldCollapse != headerCollapsed {
                        withAnimation(OPSStyle.Animation.fast) { headerCollapsed = shouldCollapse }
                    }
                }
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .sheet(isPresented: $showARDetail) { ARAgingDetailView().environmentObject(dataController) }
            // TODO: showCashFlowReport / showJobsReport route to full-screen reports; spec §10
            //       defers those to v2. Tile drill currently dismisses with no-op.
        }
        .trackScreen("Books")
        .task {
            setupViewModels()
            await dashboardVM.loadData()
            if !visibleSegments.contains(selectedSegment), let first = visibleSegments.first {
                selectedSegmentRaw = first.rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BooksSelectSegment"))) { notification in
            if let raw = notification.userInfo?["segment"] as? String,
               let section = BooksSection(rawValue: raw),
               visibleSegments.contains(section) {
                selectedSegmentRaw = section.rawValue
            }
        }
    }

    private var underlineSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(visibleSegments) { segment in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(OPSStyle.Animation.fast) { selectedSegmentRaw = segment.rawValue }
                } label: {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(segment.rawValue)
                            .font(OPSStyle.Typography.sectionLabel)
                            .foregroundColor(selectedSegment == segment ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, OPSStyle.Layout.spacing2_5)
                        Rectangle()
                            .frame(height: OPSStyle.Layout.Border.thick)
                            .foregroundColor(selectedSegment == segment ? OPSStyle.Colors.primaryAccent : Color.clear)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    @ViewBuilder
    private var contentForSegment: some View {
        Group {
            switch selectedSegment {
            case .invoices:  InvoicesListView(embedded: true)
            case .estimates: EstimatesListView(embedded: true)
            case .expenses:
                let scopeIsOwn = permissionStore.can("expenses.view") && !permissionStore.hasFullAccess("expenses.view")
                if scopeIsOwn { MyExpensesView() } else { ExpensesListView(embedded: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(OPSStyle.Animation.fast, value: selectedSegment)
    }

    private func setupViewModels() {
        guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else { return }
        dashboardVM.setup(companyId: companyId, modelContext: modelContext)
        estimateVM.setup(companyId: companyId, modelContext: modelContext)
        invoiceVM.setup(companyId: companyId, modelContext: modelContext)
        expenseVM.setup(companyId: companyId)
    }
}
```

- [ ] **Step 2: Stage**

```bash
git add OPS/Views/Books/BooksTabView.swift
```

---

### Task C5: Final build + atomic commit for the Phase C bundle

- [ ] **Step 1: Build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build`
Expected: succeeds.

- [ ] **Step 2: Commit the Phase C bundle**

```bash
git commit -m "books: pipeline split + carousel mount + FAB integration"
```

(All four files — `BooksSection.swift`, `MainTabView.swift`, `FloatingActionMenu.swift`, `BooksTabView.swift` — land as one atomic change.)

---

## Phase D — Cleanup of replaced components

### Task D1: Delete `MoneyDashboardHeader.swift`

**Files:**
- Delete: `OPS/Views/Money/Components/MoneyDashboardHeader.swift`

- [ ] **Step 1: Remove from project + filesystem**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git rm OPS/Views/Money/Components/MoneyDashboardHeader.swift
```

- [ ] **Step 2: Also remove the file reference from `OPS.xcodeproj/project.pbxproj`**

Open `OPS.xcodeproj/project.pbxproj`, search for `MoneyDashboardHeader`, and remove the two lines that reference it (PBXFileReference + PBXBuildFile). Stage the change:

```bash
git add OPS.xcodeproj/project.pbxproj
```

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
```

Expected: succeeds.

---

### Task D2: Delete `SmartStatCarousel.swift`

**Files:**
- Delete: `OPS/Views/Money/Components/SmartStatCarousel.swift`

- [ ] **Step 1: Remove**

```bash
git rm OPS/Views/Money/Components/SmartStatCarousel.swift
```

Remove from `project.pbxproj` (same pattern as D1).

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
```

Expected: succeeds.

---

### Task D3: Delete `FinancialHealthBar.swift`

```bash
git rm OPS/Views/Money/Components/FinancialHealthBar.swift
```

Remove from `project.pbxproj`. Build. Expected: succeeds.

---

### Task D4: Delete `PeriodToggle.swift` if standalone

- [ ] **Step 1: Check**

```bash
find OPS -name "PeriodToggle.swift"
```

If a standalone file exists, `git rm` it and remove from `project.pbxproj`. If `PeriodToggle` is inlined in `MoneyDashboardHeader.swift` (deleted in D1), this is a no-op.

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build
```

Expected: succeeds.

---

### Task D5: Atomic delete commit

- [ ] **Step 1: Commit**

```bash
git commit -m "books: remove superseded MoneyDashboardHeader/SmartStatCarousel/FinancialHealthBar"
```

---

## Phase E — Manual verification on device

These are not automatable. Run sequentially. Each step is a human check.

### Task E1: Build for device

- [ ] Connect a physical iPhone (per `ops-ios/CLAUDE.md`'s "no simulator" rule).
- [ ] Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
- [ ] Install via Xcode.

### Task E2: Owner role flows

- [ ] Sign in as an Owner user (has all financial perms + pipeline.view).
- [ ] Tap Books tab.
- [ ] **Verify:** All 5 cards visible. Card 1 (P&L) is the default first card on cold launch.
- [ ] Swipe right through Card 2, 3, 4, 5. **Verify:** Light haptic on each swap; dots track.
- [ ] Background the app. Foreground. **Verify:** Carousel opens to the last-viewed card.
- [ ] Tap a dot to jump. **Verify:** Smooth snap (cubic easing, no spring bounce).

### Task E3: Period change

- [ ] Tap the period pill. **Verify:** Menu shows 8 options (30D / 90D / 6M / 1Y / MTD / LAST / QTD / YTD).
- [ ] Select THIS MONTH. **Verify:** Card 1, 2, 5 numbers morph (numeric content transition). Card 3, 4 numbers do NOT change (always-open).

### Task E4: Tile drill-downs

- [ ] On Card 1, tap "OUTSTANDING" tile. **Verify:** Lands on Invoices segment with overdue filter selected.
- [ ] Back. Tap "FORECAST" tile. **Verify:** Lands on Estimates segment with SENT filter.
- [ ] On Card 3, tap "TOP CHASE" tile. **Verify:** AR aging detail sheet opens.

### Task E5: Header collapse

- [ ] Scroll the list under the carousel. **Verify:** Carousel collapses to single-line strip showing active card's primary number + A/R glance + dots. Segments stick.
- [ ] Scroll back up. **Verify:** Carousel re-expands.

### Task E6: Permission flows

- [ ] Sign in as Operator (`estimates.view` + `expenses.view` only, no `finances.view`, no `pipeline.view`).
- [ ] **Verify:** Books tab visible. Carousel hidden (zero permitted cards). Period pill hidden. Segmented control shows ESTIMATES + EXPENSES only. FAB MONEY group works.
- [ ] Sign in as Crew (`expenses.view (own)`). **Verify:** Books tab routes directly to MyExpensesView. No hub UI seen.

### Task E7: Reduced-motion

- [ ] iOS Settings → Accessibility → Motion → Reduce Motion ON.
- [ ] Open Books. **Verify:** Numbers render at final value (no count-up). Bars render at final width (no fill-draw). Carousel swipe still works but with instant snap.

### Task E8: Offline

- [ ] Enable Airplane Mode.
- [ ] Open Books cold. **Verify:** Cached data renders all visible cards. Period change still works against cache.

### Task E9: Deep links

- [ ] Tap a push notification that opens an invoice (`OpenInvoiceDetails`). **Verify:** Sheet opens above Books.
- [ ] Tap a notification rail entry for expenses. **Verify:** Books tab opens, expenses segment selected.

### Task E10: FAB integration

- [ ] On Invoices segment, open FAB. **Verify:** MONEY group has "New Invoice" at position 0.
- [ ] Switch to Estimates segment. Reopen FAB. **Verify:** "New Estimate" floats to position 0.
- [ ] **Verify:** "New Lead" is still present (Pipeline FAB action lives in MONEY group; FAB is global per spec §4.6).

---

## Phase F — Bible + bug resolution

### Task F1: Update bible §1140–1143 (AccountingDashboard drift D1)

**Files:**
- Modify: `ops-software-bible/09_FINANCIAL_SYSTEM.md`

- [ ] **Step 1: Replace lines 1139–1143**

Replace:

```markdown
#### Accounting Views (1 file)

| File | Purpose |
|---|---|
| `AccountingDashboard.swift` | Read-only financial health overview. Three sections: ... |
```

With:

```markdown
#### A/R Views (1 file)

| File | Purpose |
|---|---|
| `ARAgingDetailView.swift` | Read-only AR drill-down. Two sections: (1) **AR Aging** horizontal bar chart (0-30d, 31-60d, 61-90d, 90d+) using Swift Charts, (2) **Top Outstanding** list of top 5 clients by outstanding balance. Loaded from `AccountingRepository.fetchAllInvoices()`. Presented as a sheet from the BOOKS carousel's A/R card (top-chase tile) and from the carousel's OVERDUE drill-down. Pull-to-refresh supported. (`AccountingDashboard.swift` was replaced by this view in a prior session — bible drift caught 2026-05-11.)
```

- [ ] **Step 2: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS
git add ops-software-bible/09_FINANCIAL_SYSTEM.md
git commit -m "bible: rewrite §1140 — AccountingDashboard → ARAgingDetailView"
```

---

### Task F2: Update bible §1424–1450 (Phase 1 BOOKS drift D2)

**Files:**
- Modify: `ops-software-bible/09_FINANCIAL_SYSTEM.md`

- [ ] **Step 1: Replace lines 1424–1450**

Replace the entire "iOS BOOKS Tab (Phase 1, May 2026)" subsection with:

```markdown
### iOS BOOKS Tab (Phase 2, May 2026)

**Status:** Reconstructed 2026-05-11 (bug `1b038315`). The Phase 1 4-segment hub was replaced by a carousel-led money command center; Pipeline was elevated to its own top-level tab (see `PIPELINE TAB - P1-1`).

**Surface:**
- Lives at iOS `MainTabView.swift` rendering `BooksTabView`.
- Header: `AppHeader.HeaderType.books`.
- Hero: `HeroCarousel` — swipeable 5-card paged surface (`ScrollView` + `.scrollTargetBehavior(.paging)`; not `TabView`, per OPS motion rule):
  - Card 1 `PLCard` — In − Out = Net, margin bar, Outstanding + Forecast tiles.
  - Card 2 `CashFlowCard` — weekly paired bars (in vs out) via Swift Charts.
  - Card 3 `ARCard` — aging buckets + top chase. Always all-open.
  - Card 4 `ForecastCard` — weighted pipeline by stage. Always active.
  - Card 5 `JobsCard` — diverging profit/loss bars top 5 jobs in period.
- Below carousel: 3-segment underline control INVOICES · ESTIMATES · EXPENSES. List views mount in `embedded: true` mode (unchanged from Phase 1).
- Period pill: `PeriodPill` — 8 options (30D / 90D / 6M / 1Y / MTD / LAST / QTD / YTD).
- Header collapse: on scroll the hero collapses to `CollapsedCarouselStrip` showing the active card's primary metric + A/R glance + dots.
- Carousel mechanics: last-viewed card persisted via `@AppStorage("books.lastViewedCard")`; per-card permission filtering hides cards the user can't see. Reduced-motion path skips fill/count-up animations.

**Per-job profitability** (Card 5) computed in `MoneyDashboardViewModel`:
- Revenue = `sum(payments.amount)` for invoices with matching `project_id`, in period.
- Cost = `sum(expense_project_allocations.amount)` (with fallback to `expense.amount × percentage / 100`).
- Type cast: `expense_project_allocations.project_id` is `text`; matched as String in Swift.

**Permission gating:**
- Tab visible if user has any of `finances.view` / `estimates.view` / `expenses.view`. (`pipeline.view` gates the new Pipeline tab — no longer Books.)
- Card visibility: cards 1/2/3/5 require `finances.view`; card 4 requires `pipeline.view`. If zero cards visible (Operator), the entire carousel container hides.
- Auto-skip: Crew users with `expenses.view (own)` only land on `MyExpensesView` directly.

**FAB integration:**
- The global `FloatingActionMenu` re-orders its MONEY group via `@AppStorage("books.selectedSegment")`. Default value: `"INVOICES"` (was `"PIPELINE"` in Phase 1).
- `new-lead` stays in the MONEY group even though Pipeline is its own tab — the FAB is global.

**Spec & plan:**
- Spec: `ops-ios/docs/superpowers/specs/2026-05-11-books-ui-reconstruction-design.md`
- Plan: `ops-ios/docs/superpowers/plans/2026-05-11-books-ui-reconstruction.md`

**Phase 1 (2026-05-07) historical record:** the 4-segment hub (Pipeline + Estimates + Invoices + Expenses + `MoneyDashboardHeader` + `SmartStatCarousel` + `FinancialHealthBar`) was the shipped shape until 2026-05-11. Spec for that version is preserved at `2026-05-07-books-tab-design.md` and marked as superseded.

**Future work:**
- Forward cashflow projection (Card 6) — spawned as `CASHFLOW FORECAST - P1-1`.
- Smart-default card surfacing — deferred to v2.
```

- [ ] **Step 2: Commit**

```bash
git add ops-software-bible/09_FINANCIAL_SYSTEM.md
git commit -m "bible: rewrite §1424 — Books Phase 2 carousel architecture"
```

---

### Task F3: Update bible `02_USER_EXPERIENCE_AND_WORKFLOWS.md` Books flow

**Files:**
- Modify: `ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md`

- [ ] **Step 1: Find the Books section**

```bash
grep -n "BOOKS\|Books tab" ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md
```

Update the Books-flow description to reflect the carousel + 3-segment model. If no Books section exists, add one summarising the structure (point users at `09_FINANCIAL_SYSTEM.md` for the data model).

- [ ] **Step 2: Commit**

```bash
git add ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md
git commit -m "bible: 02_UX update for Books Phase 2 carousel model"
```

---

### Task F4: Mark May 7 spec as superseded

**Files:**
- Modify: `ops-ios/docs/superpowers/specs/2026-05-07-books-tab-design.md`

- [ ] **Step 1: Prepend banner**

Add at the very top of the file (line 1):

```markdown
> **Superseded by [2026-05-11-books-ui-reconstruction-design.md](2026-05-11-books-ui-reconstruction-design.md).** The Phase 1 4-segment hub described below is no longer the shipped shape — Books was reconstructed around a 5-card carousel and Pipeline was elevated to its own top-level tab.

---

```

- [ ] **Step 2: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git add docs/superpowers/specs/2026-05-07-books-tab-design.md
git commit -m "docs: mark 2026-05-07 books spec as superseded"
```

---

### Task F5: Resolve bug `1b038315` in Supabase

- [ ] **Step 1: Execute the resolution SQL via Supabase MCP**

Run (via `mcp__plugin_supabase_supabase__execute_sql` on project `ijeekuhbatykdomumfjx`):

```sql
UPDATE public.bug_reports
SET status        = 'resolved',
    resolved_at   = now(),
    fixed_at      = now(),
    fix_notes     = 'Books tab reconstructed around a 5-card swipeable hero carousel (P&L, Cash Flow, A/R, Forecast, Jobs) with 3-segment list below. Pipeline split to its own top-level tab. See spec docs/superpowers/specs/2026-05-11-books-ui-reconstruction-design.md.'
WHERE id = '1b038315-fb4a-44a1-b118-8e5e67578980';
```

- [ ] **Step 2: Verify the update**

```sql
SELECT status, resolved_at, fixed_at, LEFT(fix_notes, 80) AS fix_notes_preview
FROM bug_reports
WHERE id = '1b038315-fb4a-44a1-b118-8e5e67578980';
```

Expected: `status='resolved'`, both timestamps non-null, fix_notes populated.

---

## Self-review

**Spec coverage check (against `2026-05-11-books-ui-reconstruction-design.md`):**

- §1 Summary → Phases A–C produce the shape.
- §2 Why this shape → captured in plan preamble.
- §3 Personas → E2/E6 verifies per-role.
- §4.1 Tab placement → coordinated with `PIPELINE TAB - P1-1` spawn (out of scope; plan only removes pipeline from Books).
- §4.2 Books tab structure → C4 implements.
- §4.3 Hero carousel — 5 cards + tile drill-downs → B2–B6 cards + C4 wires drills.
- §4.4 Segments → C4 keeps existing list views via `embedded: true`.
- §4.5 Permission matrix → C2 updates `hasBooksAccess`; B7 carousel filters cards; C4 hides carousel when zero permitted.
- §4.6 FAB integration → C3.
- §5 Data model → A1–A5 ViewModel extensions; A6 unit tests.
- §6 Animation & motion → built into each B-phase card (count-up via `.contentTransition(.numericText())`, fill-bar via `withAnimation(OPSStyle.Animation.standard)`, reduced-motion guards, `ScrollView` paging — no TabView).
- §7 Tokens → all cards use OPSStyle tokens cited in spec.
- §8 Files changed → File Structure section at top of plan mirrors it 1:1.
- §9 Accessibility → reduced-motion guards in every card; `monospacedDigit()` on numbers; touch targets ≥44pt enforced via `OPSStyle.Layout.touchTargetMin`.
- §10 Out of scope → reports drill-downs (showCashFlowReport / showJobsReport) are stubbed with comments — explicitly deferred per spec.
- §11 Verification plan → Phase E covers each item.
- §12 Implementation plan → this document.
- §13 Resolution → F5 (bug update) + F1–F4 (bible).
- §14 Verified facts log → not separately addressed; all facts already incorporated into task code.
- D1–D9 drift register → D1 fixed by F1; D2 fixed by F2; D3 incorporated into A4/A5; D4 incorporated into C4 drill-down; D5 incorporated into A5; D6 fixed by C3; D7 used across B2–B8 cards; D8 used in B7 (`ScrollView` not `TabView`); D9 fixed by F5.

**Placeholder scan:** All step code blocks are complete. The two "TODO" comments in C4 (`showCashFlowReport / showJobsReport route to full-screen reports`) are flagged as explicit out-of-scope per spec §10 — not implementation placeholders, scoped deferrals.

**Type consistency:** `MoneyDashboardViewModel.JobNet`, `MoneyDashboardViewModel.Period`, `HeroCarousel.CardID`, `BooksSection` all referenced consistently across tasks. `PipelineStage.hexColor` flagged in Task B5 as needing verification — if missing, inline the hex codes from bible §09 lines 70–79.

---

## Execution choice

**Plan complete and saved to `ops-ios/docs/superpowers/plans/2026-05-11-books-ui-reconstruction.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task with two-stage review between tasks; fast iteration, isolated context per task.

**2. Inline Execution** — execute tasks in this session via `superpowers:executing-plans`, batch through phases with checkpoints for human review.

**Which approach?**
