//
//  BallInCourtBar.swift
//  OPS
//
//  Floating bar above the stage strip showing "ball in your court" leads.
//  Severity-tiered leading rail color (red overdue / amber stale / blue
//  untouched). Tap toggles in-place filter across the carousel. Hidden when
//  count == 0.
//

import SwiftUI

struct BallInCourtBar: View {
    let count: Int
    let buckets: PipelineViewModel.InCourtBuckets
    let totalValue: Double
    let filterActive: Bool
    let isOffline: Bool
    let onToggleFilter: () -> Void

    private var railColor: Color {
        if buckets.overdue > 0 { return OPSStyle.Colors.errorStatus }
        if buckets.stale > 0 { return OPSStyle.Colors.warningStatus }
        return OPSStyle.Colors.primaryAccent
    }

    private var stakeText: String? {
        guard totalValue > 0 else { return nil }
        if totalValue >= 10_000 {
            let thousands = Int((totalValue / 1_000).rounded())
            return "$\(thousands)K STAKE"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        let s = formatter.string(from: NSNumber(value: totalValue)) ?? "$0"
        return "\(s) STAKE"
    }

    var body: some View {
        if count == 0 {
            EmptyView()
        } else {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggleFilter()
            }) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(railColor)
                        .frame(width: 3)
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if filterActive {
                            Text("FILTER ON · \(count) LEADS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("CLEAR")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Text("\(count)")
                                    .font(OPSStyle.Typography.dataValue)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                Text("IN COURT")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            if buckets.overdue > 0 {
                                separatorDot
                                Text("\(buckets.overdue) OVERDUE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            }
                            if buckets.stale > 0 {
                                separatorDot
                                Text("\(buckets.stale) STALE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                            }
                            if buckets.untouched > 0 {
                                separatorDot
                                Text("\(buckets.untouched) UNTOUCHED")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            if let stake = stakeText {
                                separatorDot
                                Text(stake)
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            if isOffline {
                                separatorDot
                                Text("OFFLINE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: filterActive ? "xmark" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(OPSStyle.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .accessibilityLabel(filterActive
                ? "Filter on, \(count) in-court leads. Tap to clear filter."
                : "\(count) leads in your court. Tap to filter."
            )
        }
    }

    private var separatorDot: some View {
        Text("·").foregroundColor(OPSStyle.Colors.tertiaryText)
    }
}
