//
//  JobsCard.swift
//  OPS
//
//  Books Phase 3 (Mission Deck) — Card 5 of the hero carousel.
//  Diverging profit/loss bars from a center axis for the period's top jobs.
//  "Which jobs made me money? Which lost it?"
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 5.5
//

import SwiftUI

struct JobsCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapProfitable: () -> Void
    var onTapLosers: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Derived

    /// Worst-case bar magnitude on the row (positive or negative). Drives the
    /// diverging-bar width ratio so the longest job — winner or loser — fills
    /// 50% of the row. `max(_, 1)` guards against an all-zero data set.
    private var maxAbsNet: Double {
        max(viewModel.topProjectsByNet.map { abs($0.net) }.max() ?? 0, 1)
    }

    private var isEmpty: Bool {
        viewModel.topProjectsByNet.isEmpty
    }

    private var isSkeleton: Bool {
        !viewModel.hasEverLoaded && viewModel.isLoading
    }

    // MARK: - Body

    var body: some View {
        if isSkeleton {
            skeletonView.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        } else if viewModel.cardError(.jobs) {
            BooksCardError(onRetry: { Task { await viewModel.retry(.jobs) } })
        } else if isEmpty {
            emptyView.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        } else {
            normalBody.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    // MARK: - Normal body

    private var normalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TOP 5 JOBS BY NET")
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(2.0)  // 0.20em at 10pt
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            VStack(spacing: 14) {
                ForEach(viewModel.topProjectsByNet) { job in
                    jobRow(job)
                }
            }
            .padding(.top, 18)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksDrillTile(
                    label: "PROFITABLE",
                    value: "\(viewModel.profitableProjectCount)",
                    sub: "JOBS",
                    valueColor: OPSStyle.Colors.olive,
                    onTap: onTapProfitable
                )
                BooksDrillTile(
                    label: "AVG MARGIN",
                    value: "\(Int((viewModel.avgProjectMargin * 100).rounded()))%",
                    sub: "MEAN",
                    valueColor: OPSStyle.Colors.primaryText
                )
                BooksDrillTile(
                    label: "LOSERS",
                    value: "\(viewModel.losersProjectCount)",
                    sub: "JOBS",
                    valueColor: OPSStyle.Colors.rose,
                    onTap: onTapLosers
                )
            }
            .padding(.top, 22)
        }
    }

    private func jobRow(_ job: MoneyDashboardViewModel.JobNet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(job.title)
                    .font(.custom("Mohave-Medium", size: 14))
                    .tracking(0.56)  // 0.04em at 14pt
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(marginString(job))
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .tracking(0.95)  // 0.10em at 9.5pt
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .monospacedDigit()
                Text(netString(job.net))
                    .font(.custom("JetBrainsMono-Medium", size: 14))
                    .tracking(-0.14)  // -0.01em at 14pt
                    .foregroundColor(job.net >= 0 ? OPSStyle.Colors.oliveMobile : OPSStyle.Colors.roseMobile)
                    .monospacedDigit()
            }
            divergingBar(job)
        }
    }

    private func divergingBar(_ job: MoneyDashboardViewModel.JobNet) -> some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let center = totalWidth / 2
            let ratio = CGFloat(abs(job.net) / maxAbsNet)
            let barWidth = totalWidth * 0.5 * ratio
            let isPositive = job.net >= 0
            let barX = isPositive ? center : center - barWidth

            ZStack(alignment: .topLeading) {
                // Center axis hairline — drawn first, so the fill bar sits over it.
                Rectangle()
                    .fill(OPSStyle.Colors.line)
                    .frame(width: 1, height: 5)
                    .offset(x: center - 0.5)
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(isPositive ? OPSStyle.Colors.olive : OPSStyle.Colors.rose)
                    .frame(width: barWidth, height: 5)
                    .offset(x: barX)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("// NO COMPLETE JOBS THIS PERIOD")
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(1.76)  // 0.16em at 11pt
                .foregroundColor(OPSStyle.Colors.inactiveText)
                .padding(.top, OPSStyle.Layout.spacing3)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksDrillTile(
                    label: "PROFITABLE",
                    value: "0",
                    sub: "JOBS",
                    valueColor: OPSStyle.Colors.tertiaryText
                )
                BooksDrillTile(
                    label: "AVG MARGIN",
                    value: "—",
                    sub: "MEAN",
                    valueColor: OPSStyle.Colors.tertiaryText
                )
                BooksDrillTile(
                    label: "LOSERS",
                    value: "0",
                    sub: "JOBS",
                    valueColor: OPSStyle.Colors.tertiaryText
                )
            }
            .padding(.top, 22)
        }
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 0) {
            BooksSkeleton.bar(width: 180, height: 10)
            VStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            BooksSkeleton.bar(width: 120, height: 14)
                            Spacer()
                            BooksSkeleton.bar(width: 36, height: 9)
                            BooksSkeleton.bar(width: 72, height: 14)
                        }
                        BooksSkeleton.bar(width: nil, height: 5)
                    }
                }
            }
            .padding(.top, 18)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksSkeleton.tile()
                BooksSkeleton.tile()
                BooksSkeleton.tile()
            }
            .padding(.top, 22)
        }
    }

    // MARK: - Format helpers

    /// Signed integer-percent margin: "+82%", "-32%", or "0%". Uses raw net/revenue
    /// (not `viewModel.avgProjectMargin`, which is the across-jobs mean).
    private func marginString(_ job: MoneyDashboardViewModel.JobNet) -> String {
        guard job.revenue > 0 else { return "0%" }
        let pct = Int((job.net / job.revenue * 100).rounded())
        if pct > 0 { return "+\(pct)%" }
        return "\(pct)%"  // negative case carries its own minus; zero shows as "0%"
    }

    /// Signed currency: "+$19,500" or "−$2,600" (U+2212 minus sign).
    /// Zero formats as "+$0" since `net >= 0` is the positive branch.
    private func netString(_ net: Double) -> String {
        let formatted = abs(net).formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return (net >= 0 ? "+" : "\u{2212}") + formatted
    }
}

#if DEBUG
#Preview("JobsCard — seeded") {
    JobsCard(viewModel: .previewStub(), onTapProfitable: {}, onTapLosers: {})
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}

#Preview("JobsCard — empty") {
    JobsCard(viewModel: .previewEmpty(), onTapProfitable: {}, onTapLosers: {})
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}
#endif
