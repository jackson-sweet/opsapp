//
//  ExpandedCardSheet.swift
//  OPS
//
//  The half-sheet a command-grid tile expands into. Rebuilt 2026-07-01 for the
//  Command Grid redesign: the system navigation chrome (SF-Pro title + DONE
//  button) is gone — the sheet opens straight into the tactical header
//  (`BooksSheetHeader`) and the lens's rebuilt content (`BooksLensSheets`),
//  dismissing by drag (the call site shows the indicator) per MOBILE.md §6.2.
//  The in-sheet drills still dismiss first, then route the parent ledger.
//
//  Presented with `.presentationDetents([.medium, .large])` +
//  `.presentationDragIndicator(.visible)` at the call site.
//

import SwiftUI

struct ExpandedCardSheet: View {
    let card: HeroCarousel.CardID
    @ObservedObject var viewModel: MoneyDashboardViewModel
    /// P&L OUTSTANDING → Invoices/overdue. Sheet dismisses, then the parent routes.
    var onDrillOutstanding: () -> Void = {}
    /// P&L FORECAST → Estimates/out. Sheet dismisses, then the parent routes.
    var onDrillForecast: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BooksSheetHeader(title: title, tag: periodTag)
                    .padding(.top, OPSStyle.Layout.spacing4)   // clears the drag indicator
                    .padding(.bottom, OPSStyle.Layout.spacing3_5)

                lensContent
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .accessibilityAction(.escape) { dismiss() }
    }

    @ViewBuilder
    private var lensContent: some View {
        switch card {
        case .pl:
            BooksPLSheet(
                viewModel: viewModel,
                onTapOutstanding: { dismiss(); onDrillOutstanding() },
                onTapForecast: { dismiss(); onDrillForecast() }
            )
        case .cashFlow:
            BooksCashFlowSheet(viewModel: viewModel)
        case .cashForecast:
            EmptyView()  // RUNWAY deep-links to its own full screen, never this sheet
        case .ar:
            BooksARSheet(viewModel: viewModel)
        case .forecast:
            BooksForecastSheet(viewModel: viewModel)
        case .jobs:
            BooksJobsSheet(viewModel: viewModel)
        }
    }

    private var title: String {
        switch card {
        case .pl:           return "P&L"
        case .cashFlow:     return "CASH FLOW"
        case .cashForecast: return "RUNWAY"
        case .ar:           return "RECEIVABLES"
        case .forecast:     return "FORECAST"
        case .jobs:         return "JOBS"
        }
    }

    /// Period scope tag — the pill periods for the period-scoped lenses, the
    /// always-on scopes for A/R (all open) and forecast (active pipeline).
    private var periodTag: String {
        switch card {
        case .pl, .cashFlow, .jobs: return viewModel.selectedPeriod.shortLabel
        case .ar:                   return "ALL OPEN"
        case .forecast:             return "ACTIVE"
        case .cashForecast:         return ""
        }
    }
}

#if DEBUG
#Preview("ExpandedCardSheet — P&L") {
    ExpandedCardSheet(card: .pl, viewModel: .previewStub())
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}

#Preview("ExpandedCardSheet — Receivables") {
    ExpandedCardSheet(card: .ar, viewModel: .previewStub())
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
#endif
