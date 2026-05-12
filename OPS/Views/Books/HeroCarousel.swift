//
//  HeroCarousel.swift
//  OPS
//
//  Books Phase 2 — 5-card swipeable financial carousel.
//  Uses ScrollView(.horizontal) + scrollTargetBehavior(.paging) (iOS 17+)
//  instead of TabView(.page) so we keep the OPS canonical easing curve
//  and avoid spring physics per the design system motion rule.
//
//  Cards are permission-filtered; the last-viewed card persists across
//  app launches via @AppStorage. Reduced-motion skips fill/count-up.
//

import SwiftUI

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
