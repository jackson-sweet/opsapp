//
//  ARCard.swift
//  OPS
//
//  Books Phase 2 — Card 3 of the hero carousel.
//  A/R aging buckets (period-independent, always all-open).
//  "Who do I need to chase?"
//

import SwiftUI

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
        let fraction: Double
    }

    private var buckets: [Bucket] {
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
        let labels = ["0–30d", "31–60d", "61–90d", "90d+"]
        let colors = [
            OPSStyle.Colors.successStatus,
            OPSStyle.Colors.accountingReceivables,
            OPSStyle.Colors.warningStatus,
            OPSStyle.Colors.accountingOverdue
        ]
        return (0..<4).map { i in
            Bucket(label: labels[i], amount: amounts[i], color: colors[i], fraction: amounts[i] / maxV)
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

            ForEach(Array(buckets.enumerated()), id: \.element.id) { idx, bucket in
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(bucket.label)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: 56, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bucket.color)
                            .frame(width: appeared ? geo.size.width * bucket.fraction : 0, height: 8)
                            .animation(reduceMotion ? .none : OPSStyle.Animation.standard.delay(0.05 * Double(idx)), value: appeared)
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
