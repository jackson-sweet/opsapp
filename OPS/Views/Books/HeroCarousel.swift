//
//  HeroCarousel.swift
//  OPS
//
//  Books P6 — 5-card swipeable financial carousel, condensed-card edition.
//  Each lens renders a uniform CONDENSED tile (headline metric + signature
//  mini-viz); tapping expands the lens's full content into a half-sheet
//  (`ExpandedCardSheet`). Uses ScrollView(.horizontal) + scrollTargetBehavior
//  (.paging) (iOS 17+) instead of TabView(.page) so we keep the OPS canonical
//  easing curve and avoid spring physics per the design system motion rule.
//
//  The shared header (active label + scope badge + period pill) and dot
//  pagination sit outside the paging strip and reflect the active card. The
//  last-viewed card persists across launches via @AppStorage.
//

import SwiftUI

struct HeroCarousel: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject private var dataController: DataController

    @AppStorage("books.lastViewedCard") private var lastViewedRaw: String = CardID.pl.rawValue
    @State private var scrollPosition: CardID?
    @State private var expandedCard: CardID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// P&L OUTSTANDING tile → Invoices/overdue (fired from inside the sheet).
    var onDrillOutstanding: () -> Void
    /// P&L FORECAST tile → Estimates/sent (fired from inside the sheet).
    var onDrillForecast: () -> Void

    enum CardID: String, CaseIterable, Identifiable {
        case pl, cashFlow, ar, forecast, jobs
        var id: String { rawValue }

        /// Permission gate. Cards 1/2/3/5 require `finances.view`; Card 4 requires `pipeline.view`.
        var permission: String {
            switch self {
            case .pl, .cashFlow, .ar, .jobs: return "finances.view"
            case .forecast:                  return "pipeline.view"
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
                inlineHeader

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        ForEach(visibleCards) { card in
                            cardView(for: card)
                                // Paging width must account for the inter-card
                                // gap, otherwise every page accumulates a
                                // `spacing3` rightward drift (P6 bleed fix).
                                .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: OPSStyle.Layout.spacing3)
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
            .onChange(of: visibleCards.map(\.rawValue).joined(separator: "|")) { _, _ in
                let restored = scrollPosition ?? CardID(rawValue: lastViewedRaw) ?? .pl
                let next = visibleCards.contains(restored) ? restored : visibleCards.first
                scrollPosition = next
                if let next {
                    lastViewedRaw = next.rawValue
                }
            }
            // Tap a condensed card → expand its full content into the reused
            // half-sheet (mirrors the A/R aging detail presentation).
            .sheet(item: $expandedCard) { card in
                ExpandedCardSheet(
                    card: card,
                    viewModel: viewModel,
                    onDrillOutstanding: onDrillOutstanding,
                    onDrillForecast: onDrillForecast
                )
                .environmentObject(dataController)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            // § 8.1 — carousel container: heading-rotor entry + orientation label.
            // `.contain` keeps every card, tile, and chrome control individually
            // navigable inside the container. Count is permission-filtered, never
            // hardcoded to 5.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Books dashboard, \(visibleCards.count) cards")
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// Top line of the hero: active card's label on the left, period pill on the right.
    /// Cards 3 (A/R) and 4 (Forecast) render a colored scope-hint badge beside the label
    /// (ALL OPEN / ACTIVE) so the user understands why those cards don't respond to the pill.
    private var inlineHeader: some View {
        let active = scrollPosition ?? visibleCards.first ?? .pl
        return HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            Text(headerLabel(for: active))
                .font(.custom("JetBrainsMono-Medium", size: 11).weight(.semibold))
                .tracking(1.76)  // 0.16em at 11pt
                .foregroundColor(OPSStyle.Colors.primaryText)
                .textCase(.uppercase)
                .lineLimit(2)  // § 8.4 — wrap, never clip, above the type floor
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)  // § 8.4 — card-header label clamped
                .booksOpacityContentTransition(reduceMotion: reduceMotion)
            if let badge = scopeBadge(for: active) {
                badge
            }
            Spacer()
            PeriodPill(selected: $viewModel.selectedPeriod)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    private func headerLabel(for card: CardID) -> String {
        switch card {
        case .pl:       return "P&L"
        case .cashFlow: return "CASH FLOW"
        case .ar:       return "A/R"
        case .forecast: return "FORECAST"
        case .jobs:     return "JOBS"
        }
    }

    private func scopeBadge(for card: CardID) -> BooksScopeHintBadge? {
        switch card {
        case .ar:       return BooksScopeHintBadge(variant: .allOpen)
        case .forecast: return BooksScopeHintBadge(variant: .active)
        default:        return nil
        }
    }

    @ViewBuilder
    private func cardView(for card: CardID) -> some View {
        let expand = { expandedCard = card }
        switch card {
        case .pl:
            PLCard(viewModel: viewModel, style: .condensed, onExpand: expand,
                   onTapOutstanding: onDrillOutstanding, onTapForecast: onDrillForecast)
        case .cashFlow:
            CashFlowCard(viewModel: viewModel, style: .condensed, onExpand: expand)
        case .ar:
            ARCard(viewModel: viewModel, style: .condensed, onExpand: expand, onTapTopChase: {})
        case .forecast:
            ForecastCard(viewModel: viewModel, style: .condensed, onExpand: expand)
        case .jobs:
            JobsCard(viewModel: viewModel, style: .condensed, onExpand: expand)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Array(visibleCards.enumerated()), id: \.element) { index, card in
                let isActive = scrollPosition == card
                Capsule()
                    .fill(isActive ? OPSStyle.Colors.primaryText
                                   : OPSStyle.Colors.textMute.opacity(0.5))
                    .frame(width: isActive ? 22 : 6, height: 6)
                    .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: scrollPosition)
                    .frame(minWidth: 44, minHeight: 44)  // 44pt hit target — visible dot stays centered
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                            scrollPosition = card
                        }
                    }
                    .accessibilityLabel("Card \(index + 1) of \(visibleCards.count)")
                    .accessibilityHint("Double-tap to jump to card \(index + 1)")
            }
        }
        .padding(.top, OPSStyle.Layout.spacing1)
    }
}

#if DEBUG
#Preview("HeroCarousel — Owner (all 5 cards)") {
    HeroCarousel(
        viewModel: .previewStub(),
        onDrillOutstanding: {}, onDrillForecast: {}
    )
    .environmentObject(PermissionStore.previewOwner())
    .environmentObject(DataController())
    .padding(.vertical, 24)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}

#Preview("HeroCarousel — empty data") {
    HeroCarousel(
        viewModel: .previewEmpty(),
        onDrillOutstanding: {}, onDrillForecast: {}
    )
    .environmentObject(PermissionStore.previewOwner())
    .environmentObject(DataController())
    .padding(.vertical, 24)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
