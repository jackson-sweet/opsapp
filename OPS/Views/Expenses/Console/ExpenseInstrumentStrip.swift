//
//  ExpenseInstrumentStrip.swift
//  OPS
//
//  The console's instrument tier — macro spend awareness plus the bucket
//  switcher, one structure serving both. A spend hero card answers "how much
//  are we spending on job expenses" at a glance; the three money tiles
//  (TO REVIEW / TO PAY / PAID) are simultaneously the console's simple
//  metrics AND the segmented control for the queue below — tap a state of
//  money, see its queue. Pure presentation: hand it metrics + selection.
//

import SwiftUI

struct ExpenseInstrumentStrip: View {
    let metrics: ExpenseConsoleMetrics
    @Binding var selectedBucket: ExpenseBucket
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            spendHero
            tileRow
        }
    }

    // MARK: - Spend hero

    private var spendHero: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Text("//")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.textMute)
                        Text("SPEND · THIS MONTH")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .tracking(1.2)
                    }

                    Text(BooksFormat.currency(metrics.spendMTD))
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer()

                VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing1) {
                    monthBars
                    trendLine
                }
            }

            // Jobs vs overhead split — where this month's money went.
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text("JOBS")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(BooksFormat.currency(metrics.jobSpendMTD))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .monospacedDigit()
                Text("·")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("OVERHEAD")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(BooksFormat.currency(metrics.overheadSpendMTD))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .monospacedDigit()
                Spacer()
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    /// Six months of spend as quiet micro bars, oldest → newest. Neutral fills
    /// only — data bars never take accent. The current month reads brighter.
    private var monthBars: some View {
        let maxSpend = max(metrics.spendByMonth.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(metrics.spendByMonth.enumerated()), id: \.offset) { index, value in
                let isCurrent = index == metrics.spendByMonth.count - 1
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(isCurrent ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.fillNeutral)
                    .frame(width: 6, height: max(3, CGFloat(value / maxSpend) * 24))
            }
        }
        .frame(height: 24, alignment: .bottom)
        .accessibilityLabel("Six month spend trend")
    }

    /// Month-over-month delta. Spend going UP is cost-negative (rose);
    /// DOWN is good (olive). No last-month base → no trend shown.
    @ViewBuilder
    private var trendLine: some View {
        if let trend = metrics.spendTrendPct {
            let rising = trend >= 0
            HStack(spacing: 2) {
                Image(systemName: rising ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                Text("\(abs(Int(trend.rounded())))% VS LAST MO")
                    .font(OPSStyle.Typography.smallCaption)
                    .tracking(0.5)
            }
            .foregroundColor(rising ? OPSStyle.Colors.rose : OPSStyle.Colors.olive)
        }
    }

    // MARK: - Bucket tiles

    private var tileRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            bucketTile(
                .review,
                label: "TO REVIEW",
                amount: metrics.reviewTotal,
                subline: countSubline(metrics.reviewCount, noun: "BATCH", plural: "BATCHES"),
                tone: metrics.reviewCount > 0 ? OPSStyle.Colors.tan : nil
            )
            bucketTile(
                .pay,
                label: "TO PAY",
                amount: metrics.payTotal,
                subline: countSubline(metrics.payPeople, noun: "PERSON", plural: "PEOPLE"),
                tone: nil
            )
            bucketTile(
                .paid,
                label: "PAID",
                amount: metrics.paidMTDTotal,
                subline: "THIS MONTH",
                tone: nil
            )
        }
    }

    private func countSubline(_ count: Int, noun: String, plural: String) -> String {
        count == 0 ? "NONE" : "\(count) \(count == 1 ? noun : plural)"
    }

    /// A stat tile that is also a segment. Selected = the segmented-control
    /// active treatment (brighter surface + brighter hairline, never accent).
    private func bucketTile(
        _ bucket: ExpenseBucket,
        label: String,
        amount: Double,
        subline: String,
        tone: Color?
    ) -> some View {
        let isSelected = selectedBucket == bucket
        return Button {
            guard selectedBucket != bucket else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.fast) {
                selectedBucket = bucket
            }
        } label: {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(
                        isSelected
                            ? OPSStyle.Colors.primaryText
                            : (tone ?? OPSStyle.Colors.tertiaryText)
                    )
                    .tracking(1.0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(BooksFormat.currency(amount))
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(amount > 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(subline)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetLarge)
            .background(isSelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                    .stroke(
                        isSelected ? OPSStyle.Colors.inputFieldBorderFocus : OPSStyle.Colors.cardBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(label), \(BooksFormat.currency(amount)), \(subline)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
