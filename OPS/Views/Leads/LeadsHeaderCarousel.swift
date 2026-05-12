//
//  LeadsHeaderCarousel.swift
//  OPS
//
//  5-card swipeable stat carousel for the LEADS tab.
//  Forked from SmartStatCarousel because Pipeline metrics differ from
//  Books's financial metrics; a future refactor may unify both behind a
//  config-driven base.
//

import SwiftUI

struct LeadsHeaderCarousel: View {
    let weightedForecast: Double
    let weightedForecastDelta: Double?
    let activeLeadCount: Int
    let activePerStage: [(stage: PipelineStage, count: Int)]
    let closeRate: Double?
    let closeRateWonCount: Int
    let closeRateLostCount: Int
    let avgVelocityDays: Int?
    let avgVelocityDelta: Int?
    let staleLeadsCount: Int
    let staleLeadsTotalValue: Double
    let oldestStaleDescription: String?

    var onForecastTap: (() -> Void)?
    var onActivePipelineTap: (() -> Void)?
    var onStaleRiskTap: (() -> Void)?

    @State private var selectedCard = 0

    private var visibleCards: [Card] {
        var cards: [Card] = [.weightedForecast, .activePipeline, .closeRate, .velocity]
        if staleLeadsCount > 0 { cards.append(.staleRisk) }
        return cards
    }

    enum Card: Hashable {
        case weightedForecast, activePipeline, closeRate, velocity, staleRisk
    }

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            TabView(selection: $selectedCard) {
                ForEach(Array(visibleCards.enumerated()), id: \.element) { index, card in
                    cardView(for: card)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 100)
            .animation(OPSStyle.Animation.standard, value: selectedCard)

            HStack(spacing: 8) {
                ForEach(Array(visibleCards.enumerated()), id: \.element) { index, _ in
                    Circle()
                        .fill(index == selectedCard ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .onChange(of: selectedCard) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @ViewBuilder
    private func cardView(for card: Card) -> some View {
        switch card {
        case .weightedForecast: forecastCard
        case .activePipeline:   activePipelineCard
        case .closeRate:        closeRateCard
        case .velocity:         velocityCard
        case .staleRisk:        staleRiskCard
        }
    }

    // MARK: - Cards

    private var forecastCard: some View {
        Button { onForecastTap?() } label: {
            cardChrome {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("WEIGHTED FORECAST")
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(formatCurrency(weightedForecast))
                        .font(OPSStyle.Typography.dataValueLg)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    if let delta = weightedForecastDelta {
                        deltaLine(amount: delta, label: "vs LAST 30D")
                    } else {
                        Text("LAST 30D")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Weighted forecast \(formatCurrency(weightedForecast))")
    }

    private var activePipelineCard: some View {
        Button { onActivePipelineTap?() } label: {
            cardChrome {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("ACTIVE PIPELINE")
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    HStack(spacing: 6) {
                        Text("\(activeLeadCount)")
                            .font(OPSStyle.Typography.dataValueLg)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("LEADS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    miniStackedBar
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(activeLeadCount) active leads across pipeline")
    }

    private var miniStackedBar: some View {
        let totalCount = max(activePerStage.reduce(0) { $0 + $1.count }, 1)
        return GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(activePerStage, id: \.stage) { entry in
                    Rectangle()
                        .fill(entry.stage.color)
                        .frame(width: max(2, geo.size.width * CGFloat(entry.count) / CGFloat(totalCount)))
                }
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var closeRateCard: some View {
        cardChrome {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("CLOSE RATE")
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                if let rate = closeRate {
                    Text("\(Int((rate * 100).rounded()))%")
                        .font(OPSStyle.Typography.dataValueLg)
                        .foregroundColor(closeRateColor(rate))
                    Text("\(closeRateWonCount) WON · \(closeRateLostCount) LOST · LAST 90D")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                } else {
                    Text("—")
                        .font(OPSStyle.Typography.dataValueLg)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("INSUFFICIENT DATA · LAST 90D")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
    }

    private func closeRateColor(_ rate: Double) -> Color {
        if rate >= 0.40 { return OPSStyle.Colors.successStatus }
        if rate >= 0.20 { return OPSStyle.Colors.warningStatus }
        return OPSStyle.Colors.errorStatus
    }

    private var velocityCard: some View {
        cardChrome {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("VELOCITY")
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                if let days = avgVelocityDays {
                    HStack(spacing: 4) {
                        Text("\(days)")
                            .font(OPSStyle.Typography.dataValueLg)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("D AVG")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Text("NEW → WON · LAST 90D")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    if let delta = avgVelocityDelta, delta != 0 {
                        let isFaster = delta < 0
                        Text("\(isFaster ? "▼" : "▲") \(abs(delta))D vs PRIOR 90D")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(isFaster ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                    }
                } else {
                    Text("—")
                        .font(OPSStyle.Typography.dataValueLg)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("INSUFFICIENT DATA")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
    }

    private var staleRiskCard: some View {
        Button { onStaleRiskTap?() } label: {
            cardChrome(railColor: OPSStyle.Colors.warningStatus) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("STALE RISK")
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    HStack(spacing: 4) {
                        Text("\(staleLeadsCount)")
                            .font(OPSStyle.Typography.dataValueLg)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("LEADS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        if staleLeadsTotalValue > 0 {
                            Text("·")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(formatCurrency(staleLeadsTotalValue))
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }
                    if let oldest = oldestStaleDescription {
                        Text("OLDEST: \(oldest)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Chrome

    @ViewBuilder
    private func cardChrome<Content: View>(
        railColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            if let rail = railColor {
                Rectangle().fill(rail).frame(width: 3)
            }
            content()
                .padding(OPSStyle.Layout.spacing3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 88)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    @ViewBuilder
    private func deltaLine(amount: Double, label: String) -> some View {
        let isUp = amount > 0
        let isFlat = amount == 0
        HStack(spacing: 4) {
            Text(isFlat ? "—" : (isUp ? "▲" : "▼"))
                .font(OPSStyle.Typography.smallCaption)
            Text("\(formatCurrency(abs(amount))) \(label)")
                .font(OPSStyle.Typography.smallCaption)
        }
        .foregroundColor(
            isFlat ? OPSStyle.Colors.tertiaryText :
            (isUp ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
        )
    }
}
