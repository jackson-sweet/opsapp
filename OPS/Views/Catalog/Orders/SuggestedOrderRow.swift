//
//  SuggestedOrderRow.swift
//  OPS
//
//  One row in the SUGGESTED sub-segment of OrdersSheet. Surfaces a single
//  variant whose effective on-hand has fallen at or below its warning
//  threshold, and offers a single-tap "+" to add it to a working draft
//  order.
//

import SwiftUI

struct SuggestedOrderRow: View {
    let suggestion: OrderSuggestionEngine.Suggestion
    let isAdded: Bool
    /// Optional — `nil` hides the add button (read-only viewer).
    let addAction: (() -> Void)?

    private var quantityFormatted: String {
        formatNumber(suggestion.currentQuantity)
    }

    private var recommendedFormatted: String {
        formatNumber(suggestion.recommendedQuantity)
    }

    private var thresholdFormatted: String {
        formatNumber(suggestion.warningThreshold)
    }

    private var statusColor: Color {
        if let critical = suggestion.criticalThreshold,
           suggestion.currentQuantity <= critical {
            return OPSStyle.Colors.errorText
        }
        return OPSStyle.Colors.warningText
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(suggestion.familyName.uppercased())
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                if !suggestion.variantLabel.isEmpty {
                    Text(suggestion.variantLabel)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    HStack(spacing: 2) {
                        Text(quantityFormatted)
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(statusColor)
                        Text("/ \(thresholdFormatted)")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    Text("→")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(recommendedFormatted)
                        .font(OPSStyle.Typography.dataValue)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            Spacer()
            if let addAction = addAction {
                Button(action: {
                    guard !isAdded else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    addAction()
                }) {
                    Image(systemName: isAdded ? "checkmark" : "plus")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                    .foregroundColor(
                        isAdded ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryText
                    )
                    .frame(
                        width: OPSStyle.Layout.touchTargetMin,
                        height: OPSStyle.Layout.touchTargetMin
                    )
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(
                                isAdded
                                    ? OPSStyle.Colors.successStatus.opacity(0.12)
                                    : OPSStyle.Colors.subtleBackground
                            )
                    )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(
                                    isAdded
                                        ? OPSStyle.Colors.successStatus.opacity(0.3)
                                        : OPSStyle.Colors.cardBorder,
                                    lineWidth: OPSStyle.Layout.Border.standard
                                )
                        )
                }
                .accessibilityLabel(isAdded ? "Added to draft" : "Add to draft order")
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
