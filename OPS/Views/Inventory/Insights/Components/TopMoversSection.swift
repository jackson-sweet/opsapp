//
//  TopMoversSection.swift
//  OPS
//
//  Ranked list of top inventory items by consumption rate.
//  Each row shows rank, item name, sparkline trend, and consumption badge.
//

import SwiftUI

struct TopMoversSection: View {
    let movers: [ConsumptionRank]
    let onItemTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Section header
            sectionHeader

            // Card body
            VStack(spacing: 0) {
                if movers.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(movers.enumerated()), id: \.element.id) { index, mover in
                        moverRow(rank: index + 1, mover: mover)

                        if index < movers.count - 1 {
                            Divider()
                                .background(OPSStyle.Colors.separator)
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .glassSurface()
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("TOP MOVERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    // MARK: - Mover Row

    private func moverRow(rank: Int, mover: ConsumptionRank) -> some View {
        Button {
            onItemTap(mover.id)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                // Rank number
                Text("\(rank)")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 20, alignment: .center)

                // Item name
                Text(mover.name)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Spacer()

                // Sparkline
                SparklineView(
                    points: mover.sparklinePoints,
                    color: Color(hex: mover.colorHex) ?? OPSStyle.Colors.primaryAccent
                )

                // Consumption rate badge
                consumptionBadge(rate: mover.unitsPerMonth)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Consumption Badge

    private func consumptionBadge(rate: Double) -> some View {
        let formatted: String = {
            if rate >= 10 {
                return String(format: "%.0f/mo", rate)
            } else {
                return String(format: "%.1f/mo", rate)
            }
        }()

        return Text(formatted)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 3)
            .background(OPSStyle.Colors.fillNeutral)
            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "flame.slash")
                .font(.system(size: OPSStyle.Layout.IconSize.lg))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("Not enough data to rank movers")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing4)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()

        ScrollView {
            TopMoversSection(
                movers: [
                    ConsumptionRank(
                        id: "1", name: "2\" PVC Pipe",
                        unitsPerMonth: 4.2, unitDisplay: "ft",
                        sparklinePoints: [0.9, 0.8, 0.6, 0.4, 0.2],
                        colorHex: "89C3EB"
                    ),
                    ConsumptionRank(
                        id: "2", name: "Copper Fittings",
                        unitsPerMonth: 3.8, unitDisplay: "ea",
                        sparklinePoints: [1.0, 0.7, 0.5, 0.3, 0.1],
                        colorHex: "C79A95"
                    ),
                    ConsumptionRank(
                        id: "3", name: "Wire Nuts (Red)",
                        unitsPerMonth: 12.0, unitDisplay: "ea",
                        sparklinePoints: [0.8, 0.6, 0.7, 0.4, 0.2],
                        colorHex: "6F9587"
                    ),
                ],
                onItemTap: { _ in }
            )
            .padding()
        }
    }
}
