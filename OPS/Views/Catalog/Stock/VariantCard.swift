//
//  VariantCard.swift
//  OPS
//
//  Single-variant cell used by the LIST and GRID stock views. Compact card
//  with family name, variant label (option values), quantity + unit, and
//  a tactical threshold dot when the variant is below its effective
//  warning or critical level.
//

import SwiftUI

struct VariantCard: View {
    let row: EnrichedVariantRow
    let scale: CGFloat

    /// Card padding scales with the pinch-zoom factor so the card stays
    /// proportionally tactile at every zoom level.
    private var paddingV: CGFloat {
        OPSStyle.Layout.spacing2 * scale
    }

    private var paddingH: CGFloat {
        OPSStyle.Layout.spacing3 * scale
    }

    private var quantityString: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let qty = formatter.string(from: NSNumber(value: row.variant.quantity)) ?? "0"
        if let unit = row.unit?.display {
            return "\(qty) \(unit)"
        }
        return qty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing1) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.family.name)
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(2)
                    if !row.variantLabel.isEmpty {
                        Text(row.variantLabel)
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if row.thresholdStatus != .normal {
                    Circle()
                        .fill(row.thresholdStatus.color)
                        .frame(
                            width: OPSStyle.Layout.Indicator.dotMD,
                            height: OPSStyle.Layout.Indicator.dotMD
                        )
                        .accessibilityHidden(true)
                }
            }

            Spacer(minLength: OPSStyle.Layout.spacing1)

            HStack(alignment: .lastTextBaseline, spacing: OPSStyle.Layout.spacing1) {
                Text(quantityString)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(row.thresholdStatus.color)
                Spacer()
                if let sku = row.variant.sku, !sku.isEmpty {
                    Text(sku)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, paddingH)
        .padding(.vertical, paddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(
            borderColor: row.thresholdStatus == .critical
                ? OPSStyle.Colors.errorStatus
                : OPSStyle.Colors.glassBorder
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [row.family.name]
        if !row.variantLabel.isEmpty { parts.append(row.variantLabel) }
        parts.append(quantityString)
        if row.thresholdStatus != .normal, let label = row.thresholdStatus.label {
            parts.append(label)
        }
        return parts.joined(separator: ", ")
    }
}
