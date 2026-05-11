//
//  SmartStatCarousel.swift
//  OPS
//
//  Horizontal scrolling row of context-prioritized financial stat cards.
//

import SwiftUI

struct SmartStatCarousel: View {
    let overdueCount: Int
    let overdueValue: Double
    let pendingEstimatesCount: Int
    let pendingEstimatesValue: Double
    let closeRate: Double
    let avgDaysToPayment: Double
    let expensesTrend: Double
    let topUnpaid: [(clientName: String, amount: Double, daysOverdue: Int)]

    var activeLeadCount: Int = 0
    var weightedForecastValue: Double = 0
    var staleLeadsCount: Int = 0
    var nextFollowUpDue: Date? = nil

    var onStatTap: ((StatType) -> Void)?

    enum StatType {
        case overdue, pendingEstimates, closeRate, avgPayment, expensesTrend, topUnpaid
        case activeLeads, staleLeads, nextFollowUp
    }

    private var orderedCards: [CardData] {
        var cards: [CardData] = []

        // Priority: overdue first if they exist
        if overdueCount > 0 {
            cards.append(CardData(
                type: .overdue,
                value: "\(overdueCount)",
                label: "OVERDUE",
                detail: formatCurrency(overdueValue),
                accentColor: OPSStyle.Colors.accountingOverdue
            ))
        }

        // Always show pending estimates
        cards.append(CardData(
            type: .pendingEstimates,
            value: "\(pendingEstimatesCount)",
            label: "PENDING EST.",
            detail: formatCurrency(pendingEstimatesValue),
            accentColor: OPSStyle.Colors.accountingReceivables
        ))

        // Pipeline stats — financial first, pipeline second per spec §5
        if activeLeadCount > 0 {
            cards.append(CardData(
                type: .activeLeads,
                value: "\(activeLeadCount)",
                label: "ACTIVE LEADS",
                detail: formatCurrency(weightedForecastValue),
                accentColor: OPSStyle.Colors.accountingProfit
            ))
        }

        if staleLeadsCount > 0 {
            cards.append(CardData(
                type: .staleLeads,
                value: "\(staleLeadsCount)",
                label: "STALE LEADS",
                detail: nil,
                accentColor: OPSStyle.Colors.accountingOverdue
            ))
        }

        if let next = nextFollowUpDue {
            cards.append(CardData(
                type: .nextFollowUp,
                value: shortDate(next),
                label: "NEXT FOLLOW-UP",
                detail: nil,
                accentColor: OPSStyle.Colors.accountingReceivables
            ))
        }

        // Top unpaid if exists
        if let top = topUnpaid.first {
            cards.append(CardData(
                type: .topUnpaid,
                value: formatCurrency(top.amount),
                label: "LARGEST UNPAID",
                detail: top.clientName,
                accentColor: OPSStyle.Colors.accountingRevenue
            ))
        }

        // Close rate
        cards.append(CardData(
            type: .closeRate,
            value: String(format: "%.0f%%", closeRate),
            label: "CLOSE RATE",
            detail: nil,
            accentColor: OPSStyle.Colors.accountingProfit
        ))

        // Avg days to payment
        if avgDaysToPayment > 0 {
            cards.append(CardData(
                type: .avgPayment,
                value: String(format: "%.0f", avgDaysToPayment),
                label: "AVG DAYS PAY",
                detail: nil,
                accentColor: OPSStyle.Colors.primaryAccent
            ))
        }

        return cards
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(Array(orderedCards.enumerated()), id: \.offset) { index, card in
                    StatCardView(card: card)
                        .onTapGesture { onStatTap?(card.type) }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1000 {
            return String(format: "$%.1fK", absValue / 1000)
        }
        return String(format: "$%.0f", absValue)
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

private struct CardData {
    let type: SmartStatCarousel.StatType
    let value: String
    let label: String
    let detail: String?
    let accentColor: Color
}

private struct StatCardView: View {
    let card: CardData

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(card.value)
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(card.label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if let detail = card.detail {
                Text(detail)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(card.accentColor)
                    .lineLimit(1)
            }
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .frame(width: 100, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}
