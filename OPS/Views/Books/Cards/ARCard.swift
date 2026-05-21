//
//  ARCard.swift
//  OPS
//
//  Books Phase 3 (Mission Deck) — Card 3 of the hero carousel.
//  Outstanding receivables with aging ramp meter + bucket grid + chase tile.
//  Period-independent (always all-open). "Who do I need to chase?"
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 5.3
//

import SwiftUI

struct ARCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapTopChase: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Bucket: Identifiable {
        let id: Int
        let label: String       // "0–30d", "31–60d", ...
        let amount: Double
        let color: Color
    }

    // MARK: - Derived

    private var buckets: [Bucket] {
        let today = Date()
        var b0_30: Double = 0
        var b31_60: Double = 0
        var b61_90: Double = 0
        var b90: Double = 0
        for item in viewModel.outstandingInvoiceBreakdown {
            guard let due = item.date else { continue }
            let days = Int(today.timeIntervalSince(due) / 86400)
            switch days {
            case ..<31:   b0_30  += item.amount
            case 31...60: b31_60 += item.amount
            case 61...90: b61_90 += item.amount
            default:      b90    += item.amount
            }
        }
        return [
            Bucket(id: 0, label: "0–30d",  amount: b0_30,  color: OPSStyle.Colors.olive),
            Bucket(id: 1, label: "31–60d", amount: b31_60, color: OPSStyle.Colors.accountingReceivables),
            Bucket(id: 2, label: "61–90d", amount: b61_90, color: OPSStyle.Colors.warningStatus),
            Bucket(id: 3, label: "90d+",   amount: b90,    color: OPSStyle.Colors.accountingOverdue),
        ]
    }

    private var totalOutstanding: Double {
        viewModel.outstandingInvoiceBreakdown.reduce(0) { $0 + $1.amount }
    }

    /// Picks the most-overdue invoice as the chase target — surfaces the
    /// genuinely lingering item, not just the largest balance.
    private var topChase: MoneyDashboardViewModel.BreakdownItem? {
        var best: MoneyDashboardViewModel.BreakdownItem?
        var bestDate: Date = .distantFuture
        for item in viewModel.outstandingInvoiceBreakdown {
            guard let d = item.date else { continue }
            if d < bestDate {
                bestDate = d
                best = item
            }
        }
        return best
    }

    private func daysOverdue(_ item: MoneyDashboardViewModel.BreakdownItem) -> Int {
        guard let due = item.date else { return 0 }
        return max(0, Int(Date().timeIntervalSince(due) / 86400))
    }

    private var isEmpty: Bool {
        viewModel.outstandingInvoiceBreakdown.isEmpty
    }

    private var isSkeleton: Bool {
        !viewModel.hasEverLoaded && viewModel.isLoading
    }

    /// Composed VoiceOver summary for the whole card (spec § 8.1, Card 3).
    private var accessibilityCardLabel: String {
        "Accounts receivable. \(currencyString(totalOutstanding)) outstanding across \(viewModel.outstandingInvoiceBreakdown.count) open invoices, \(viewModel.overdueInvoicesCount) overdue. Always all-open."
    }

    // MARK: - Body

    var body: some View {
        if isSkeleton {
            skeletonView.padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Accounts receivable loading")
        } else if viewModel.cardError(.ar) {
            BooksCardError(onRetry: { Task { await viewModel.retry(.ar) } })
        } else if isEmpty {
            emptyView.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        } else {
            normalBody.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    // MARK: - Normal body

    private var normalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Non-tile content folded into one VoiceOver element (the § 8.1
            // card summary). The TOP CHASE tile below stays its own element.
            VStack(alignment: .leading, spacing: 0) {
                heroBlock
                agingRamp.padding(.top, OPSStyle.Layout.spacing4)
                bucketGrid.padding(.top, 14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityCardLabel)

            if let chase = topChase {
                topChaseTile(for: chase).padding(.top, OPSStyle.Layout.spacing4)
            }
        }
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOTAL OUTSTANDING")
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(2.0)
                .foregroundColor(OPSStyle.Colors.rose)

            Text(totalOutstanding, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.heroNumber)
                .tracking(-1.5)
                .foregroundColor(OPSStyle.Colors.rose)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)  // § 8.4 — hero number clamp
                .booksNumericContentTransition(reduceMotion: reduceMotion)

            subline
        }
    }

    private var subline: some View {
        let openCount = viewModel.outstandingInvoiceBreakdown.count
        let overdueCount = viewModel.overdueInvoicesCount
        return HStack(spacing: 4) {
            Text("\(openCount) OPEN")
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text("·")
                .foregroundColor(OPSStyle.Colors.inactiveText)
            Text("\(overdueCount) OVERDUE")
                .foregroundColor(overdueCount > 0 ? OPSStyle.Colors.rose : OPSStyle.Colors.secondaryText)
        }
        .font(.custom("JetBrainsMono-Medium", size: 11))
        .tracking(1.32)  // 0.12em at 11pt
        .monospacedDigit()
    }

    // MARK: - Aging ramp (single continuous bar of 4 colored segments)

    private var agingRamp: some View {
        let total = max(buckets.reduce(0) { $0 + $1.amount }, 1)
        return GeometryReader { geo in
            let gap: CGFloat = 2
            let visible = buckets.filter { $0.amount > 0 }
            let gapCount = max(visible.count - 1, 0)
            let avail = max(geo.size.width - CGFloat(gapCount) * gap, 0)
            HStack(spacing: gap) {
                ForEach(visible) { b in
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .fill(b.color)
                        .frame(width: avail * CGFloat(b.amount / total), height: 10)
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private var bucketGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(buckets) { b in
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.label)
                        .font(.custom("JetBrainsMono-Medium", size: 9.5).weight(.semibold))
                        .tracking(1.52)  // 0.16em at 9.5pt
                        .foregroundColor(b.color)
                        .textCase(.uppercase)
                    Text(b.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.custom("JetBrainsMono-Medium", size: 13))
                        .tracking(-0.13)  // -0.01em at 13pt
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    // MARK: - TOP CHASE tile (custom — full-width, not BooksDrillTile)

    private func topChaseTile(for item: MoneyDashboardViewModel.BreakdownItem) -> some View {
        Button(action: onTapTopChase) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 0) {
                    Text("TOP CHASE")
                        .font(.custom("JetBrainsMono-Medium", size: 9.5))
                        .tracking(1.9)  // 0.20em at 9.5pt
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.custom("Mohave-Medium", size: 15))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                        Text("\(daysOverdue(item))D OVERDUE")
                            .font(.custom("JetBrainsMono-Regular", size: 10))
                            .tracking(1.2)  // 0.12em at 10pt
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(item.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.custom("JetBrainsMono-Medium", size: 20))
                        .tracking(-0.20)  // -0.01em at 20pt
                        .foregroundColor(OPSStyle.Colors.rose)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(TopChaseButtonStyle(reduceMotion: reduceMotion))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Top chase, \(item.label), \(currencyString(item.amount)), \(daysOverdue(item)) days overdue")
        .accessibilityHint("Double-tap to open chase list")
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOTAL OUTSTANDING")
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(2.0)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("$0")
                .font(OPSStyle.Typography.heroNumber)
                .tracking(-1.5)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .monospacedDigit()
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)  // § 8.4 — hero number clamp
            Text("// NO OPEN INVOICES")
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(1.76)
                .foregroundColor(OPSStyle.Colors.inactiveText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Accounts receivable. No open invoices.")
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                BooksSkeleton.bar(width: 140, height: 10)
                BooksSkeleton.bar(width: 240, height: 60)
                BooksSkeleton.bar(width: 120, height: 11)
            }
            BooksSkeleton.bar(width: nil, height: 10).padding(.top, OPSStyle.Layout.spacing4)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 2) {
                        BooksSkeleton.bar(width: 40, height: 9)
                        BooksSkeleton.bar(width: 60, height: 13)
                    }
                }
            }
            .padding(.top, 14)
            BooksSkeleton.bar(width: nil, height: 80).padding(.top, OPSStyle.Layout.spacing4)
        }
    }

    // MARK: - Format helpers

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

// MARK: - TOP CHASE press style

private struct TopChaseButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let bg: Color = pressed ? Color.white.opacity(0.08) : Color.white.opacity(0.04)
        let border: Color = pressed ? Color.white.opacity(0.18) : Color.white.opacity(0.08)
        return configuration.label
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius)
                    .fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius)
                    .strokeBorder(border, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: pressed)
    }
}

#if DEBUG
#Preview("ARCard — seeded") {
    ARCard(viewModel: .previewStub(), onTapTopChase: {})
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}

#Preview("ARCard — empty") {
    ARCard(viewModel: .previewEmpty(), onTapTopChase: {})
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}
#endif
