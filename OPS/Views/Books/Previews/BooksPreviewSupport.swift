//
//  BooksPreviewSupport.swift
//  OPS
//
//  Books Phase 2 — DEBUG-only stub factories for SwiftUI #Preview canvases.
//  Lets each Books view render in Xcode's live preview without Supabase,
//  SwiftData, Keychain, or any other runtime dependency.
//
//  All factories are wrapped in `#if DEBUG` so nothing ships to the App Store.
//

#if DEBUG
import SwiftUI
import Foundation

extension MoneyDashboardViewModel {
    /// Pre-populated VM for SwiftUI previews. Realistic numbers so the cards
    /// render with their bars, percentages, and counts at non-zero values.
    /// Assigns `selectedPeriod` first so the didSet recalculate (which zeroes
    /// everything from empty arrays) doesn't wipe the seeded data.
    @MainActor
    static func previewStub(period: Period = .sixMonths) -> MoneyDashboardViewModel {
        let vm = MoneyDashboardViewModel()
        vm.selectedPeriod = period   // didSet → recalculate() zeroes everything (no repos)

        // Card 1 — P&L
        vm.totalSales = 142_800
        vm.totalPayments = 118_400
        vm.totalExpenses = 76_220
        vm.netCash = vm.totalPayments - vm.totalExpenses
        vm.pendingEstimatesCount = 7
        vm.pendingEstimatesValue = 38_900
        vm.overdueInvoicesCount = 4
        vm.overdueInvoicesValue = 12_640
        vm.expensesTrend = 12.4
        vm.closeRate = 64
        vm.avgDaysToPayment = 18.2

        // Card 2 — weekly buckets (8 weeks)
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let weekStarts: [Date] = (0..<8).reversed().compactMap { i in
            cal.date(byAdding: .weekOfYear, value: -i, to: now)
        }
        let inSeries: [Double]  = [8_200, 14_500, 11_900, 18_700, 9_300, 22_100, 16_800, 17_900]
        let outSeries: [Double] = [4_100,  7_200,  9_800,  6_500, 11_400,  8_900, 12_300, 15_020]
        vm.paymentsByWeek = zip(weekStarts, inSeries).map  { ($0, $1) }
        vm.expensesByWeek = zip(weekStarts, outSeries).map { ($0, $1) }

        // Card 3 — outstanding invoice breakdown (drives A/R aging buckets)
        let day: TimeInterval = 86_400
        vm.outstandingInvoiceBreakdown = [
            .init(label: "ACME ROOFING",     amount: 4_800,  date: now.addingTimeInterval(-10 * day),  entityId: "i1", type: .invoice),
            .init(label: "NORTHWAY HVAC",    amount: 3_200,  date: now.addingTimeInterval(-22 * day),  entityId: "i2", type: .invoice),
            .init(label: "BRIDGEWATER PLBG", amount: 6_400,  date: now.addingTimeInterval(-48 * day),  entityId: "i3", type: .invoice),
            .init(label: "QUARRY ELECTRIC",  amount: 2_900,  date: now.addingTimeInterval(-75 * day),  entityId: "i4", type: .invoice),
            .init(label: "OAKMONT CONTRACT", amount: 5_500,  date: now.addingTimeInterval(-110 * day), entityId: "i5", type: .invoice),
        ]
        vm.topUnpaidInvoices = [
            ("OAKMONT CONTRACT", 5_500, 110),
            ("BRIDGEWATER PLBG", 6_400, 48),
            ("QUARRY ELECTRIC",  2_900, 75),
        ]

        // Card 4 — forecast by stage
        vm.activeLeadCount = 12
        vm.weightedForecastValue = 84_500
        vm.staleLeadsCount = 3
        vm.weightedForecastByStage = [
            .init(id: .qualifying,  value: 18_200, avgProbability: 30, count: 4),
            .init(id: .quoting,     value: 12_400, avgProbability: 45, count: 3),
            .init(id: .quoted,      value: 26_800, avgProbability: 62, count: 2),
            .init(id: .followUp,    value:  9_500, avgProbability: 55, count: 2),
            .init(id: .negotiation, value: 17_600, avgProbability: 78, count: 1),
        ]

        // Card 5 — top jobs by net
        vm.topProjectsByNet = [
            .init(id: "p1", title: "PERRY ST RENO",   revenue: 38_400, cost: 18_900),
            .init(id: "p2", title: "OAK GROVE NEW",   revenue: 51_200, cost: 31_400),
            .init(id: "p3", title: "MILL POND ADDN",  revenue: 22_300, cost: 14_100),
            .init(id: "p4", title: "STATE ST KITCHN", revenue: 18_900, cost: 21_500),
            .init(id: "p5", title: "RIVERVIEW DECK",  revenue: 12_400, cost: 16_800),
        ]
        vm.profitableProjectCount = 9
        vm.avgProjectMargin = 0.32
        vm.losersProjectCount = 2

        return vm
    }

    /// Empty VM — every card renders its em-dash empty state.
    @MainActor
    static func previewEmpty() -> MoneyDashboardViewModel {
        let vm = MoneyDashboardViewModel()
        vm.selectedPeriod = .sixMonths
        return vm
    }
}

extension PermissionStore {
    /// Owner — every Books permission granted at "all" scope.
    @MainActor
    static func previewOwner() -> PermissionStore {
        let store = PermissionStore()
        store.permissions = [
            "finances.view":  "all",
            "pipeline.view":  "all",
            "estimates.view": "all",
            "invoices.view":  "all",
            "expenses.view":  "all",
        ]
        store.roleName = "Owner"
        store.initialized = true
        return store
    }

    /// Operator — no `finances.view` / `pipeline.view` → carousel hides entirely.
    @MainActor
    static func previewOperator() -> PermissionStore {
        let store = PermissionStore()
        store.permissions = [
            "estimates.view": "all",
            "expenses.view":  "own",
        ]
        store.roleName = "Operator"
        store.initialized = true
        return store
    }
}
#endif
