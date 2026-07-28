//
//  StockListRow.swift
//  OPS
//
//  Dense LIST-mode register row. LIST is the fast scan-and-adjust surface;
//  family browsing belongs to GRID and attribute comparison belongs to TABLE.
//

import SwiftUI

struct StockListRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let row: EnrichedVariantRow

    private var metadata: String {
        var parts: [String] = []
        if !row.variantLabel.isEmpty { parts.append(row.variantLabel) }
        if let sku = row.variant.sku, !sku.isEmpty { parts.append(sku) }
        if parts.isEmpty, let category = row.category?.name { parts.append(category) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                    statusIndicator
                        .padding(.top, OPSStyle.Layout.spacing2)

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        identity
                        quantityAndStatus(alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    disclosureIndicator
                        .padding(.top, OPSStyle.Layout.spacing1)
                }
            } else {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    statusIndicator
                    identity
                    Spacer(minLength: OPSStyle.Layout.spacing2)
                    quantityAndStatus(alignment: .trailing)
                    disclosureIndicator
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("catalog.stock.row.\(row.id)")
    }

    private var statusIndicator: some View {
        Circle()
            .fill(
                row.thresholdStatus == .normal
                    ? OPSStyle.Colors.tertiaryText.opacity(OPSStyle.Layout.Opacity.medium)
                    : row.thresholdStatus.color
            )
            .frame(
                width: OPSStyle.Layout.Indicator.dotSM,
                height: OPSStyle.Layout.Indicator.dotSM
            )
            .accessibilityHidden(true)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(row.family.name)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)

            if !metadata.isEmpty {
                Text(metadata)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
        }
        .layoutPriority(1)
    }

    private func quantityAndStatus(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: OPSStyle.Layout.spacing1) {
            HStack(alignment: .lastTextBaseline, spacing: OPSStyle.Layout.spacing1) {
                Text(StockNumberFormatter.quantity(row.variant.quantity))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(row.thresholdStatus.textColor)
                    .monospacedDigit()
                if let unit = row.unit?.display {
                    Text(unit)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                }
            }

            if let status = row.thresholdStatus.label {
                Text(status)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(row.thresholdStatus.textColor)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: OPSStyle.Icons.forward)
            .font(.system(size: OPSStyle.Layout.IconSize.xs))
            .foregroundColor(OPSStyle.Colors.tertiaryText)
    }

    private var accessibilityLabel: String {
        var parts = [row.variantDisplayName]
        parts.append(StockNumberFormatter.quantity(row.variant.quantity))
        if let unit = row.unit?.display { parts.append(unit) }
        if let status = row.thresholdStatus.label { parts.append(status) }
        if let sku = row.variant.sku, !sku.isEmpty { parts.append("SKU \(sku)") }
        return parts.joined(separator: ", ")
    }
}
