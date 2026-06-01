//
//  ExpandedCardSheet.swift
//  OPS
//
//  Books P6 — UX overhaul. The half-sheet a condensed hero card expands into.
//  Reuses the established half-sheet pattern (NavigationStack + inline title
//  + DONE, presented with `.presentationDetents([.medium, .large])` +
//  `.presentationDragIndicator(.visible)` at the call site). Renders the lens's
//  FULL content; the in-card drill actions live here now (decision 2026-06-01),
//  dismissing the sheet before routing to the relevant segment.
//
//  Spec: docs/superpowers/specs/2026-06-01-books-condensed-cards-ux-overhaul-design.md
//

import SwiftUI

struct ExpandedCardSheet: View {
    let card: HeroCarousel.CardID
    @ObservedObject var viewModel: MoneyDashboardViewModel
    /// P&L OUTSTANDING → Invoices/overdue. Sheet dismisses, then the parent routes.
    var onDrillOutstanding: () -> Void = {}
    /// P&L FORECAST → Estimates/sent. Sheet dismisses, then the parent routes.
    var onDrillForecast: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if card == .ar {
                    // A/R expands into one merged rich sheet (owns its own scroll
                    // + scroll-to-chase). No sheet-over-sheet.
                    ARDetailSheet(viewModel: viewModel)
                } else {
                    ScrollView {
                        cardContent
                            .padding(.vertical, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch card {
        case .pl:
            PLCard(
                viewModel: viewModel,
                style: .full,
                onTapOutstanding: { dismiss(); onDrillOutstanding() },
                onTapForecast: { dismiss(); onDrillForecast() }
            )
        case .cashFlow:
            CashFlowCard(viewModel: viewModel, style: .full)
        case .ar:
            EmptyView()  // handled by ARDetailSheet above
        case .forecast:
            ForecastCard(viewModel: viewModel, style: .full)
        case .jobs:
            JobsCard(viewModel: viewModel, style: .full)
        }
    }

    private var title: String {
        switch card {
        case .pl:       return "P&L"
        case .cashFlow: return "CASH FLOW"
        case .ar:       return "A/R"
        case .forecast: return "FORECAST"
        case .jobs:     return "JOBS"
        }
    }
}

#if DEBUG
#Preview("ExpandedCardSheet — P&L") {
    ExpandedCardSheet(card: .pl, viewModel: .previewStub())
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
#endif
