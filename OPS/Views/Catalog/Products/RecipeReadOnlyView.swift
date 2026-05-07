//
//  RecipeReadOnlyView.swift
//  OPS
//
//  Read-only renderer for ProductMaterial recipe rows. Each row resolves
//  to a one-liner like "Composite Board (color = $color) — 1.05/ft" or
//  "Galvanized Anchor (variant) — 4 (scaled by Corners)" depending on
//  whether it's family-pinned with a selector or hard-pinned to a
//  specific variant.
//

import SwiftUI
import SwiftData

struct RecipeReadOnlyView: View {
    let materials: [ProductMaterial]
    let options: [ProductOption]

    @Query private var allFamilies: [CatalogItem]
    @Query private var allVariants: [CatalogVariant]
    @Query private var allUnits: [CatalogUnit]

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            ForEach(materials) { material in
                row(material)
            }
        }
    }

    @ViewBuilder
    private func row(_ material: ProductMaterial) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(displayLine(material))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.leading)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                pinChip(material)
                if let scaledLabel = scaledByLabel(material) {
                    metadataChip(scaledLabel)
                }
                Spacer()
            }
            if let notes = material.notes, !notes.isEmpty {
                Text(notes)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Display

    private func displayLine(_ material: ProductMaterial) -> String {
        let qty = formatQuantity(material.quantityPerUnit)
        let unit = unitDisplay(material)
        let qtyClause = unit.isEmpty ? qty : "\(qty)/\(unit)"

        if let variantId = material.catalogVariantId,
           let variant = allVariants.first(where: { $0.id == variantId }),
           let family = allFamilies.first(where: { $0.id == variant.catalogItemId }) {
            let sku = variant.sku ?? ""
            let suffix = sku.isEmpty ? "(variant)" : "(\(sku))"
            return "\(family.name) \(suffix) — \(qtyClause)"
        }

        if let itemId = material.catalogItemId,
           let family = allFamilies.first(where: { $0.id == itemId }) {
            let selectorClause = selectorPhrase(material)
            return selectorClause.isEmpty
                ? "\(family.name) — \(qtyClause)"
                : "\(family.name) (\(selectorClause)) — \(qtyClause)"
        }

        return "Unresolved item — \(qtyClause)"
    }

    private func selectorPhrase(_ material: ProductMaterial) -> String {
        guard
            let json = material.variantSelectorJSON,
            let data = json.data(using: .utf8),
            let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return ""
        }
        let parts = raw
            .map { key, value -> String in
                "\(key) = \(stringify(value))"
            }
            .sorted()
        return parts.joined(separator: ", ")
    }

    private func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let b = value as? Bool { return b ? "true" : "false" }
        return "\(value)"
    }

    private func pinChip(_ material: ProductMaterial) -> some View {
        let label: String = {
            if material.catalogVariantId != nil { return "VARIANT" }
            if material.catalogItemId != nil { return "FAMILY" }
            return "UNRESOLVED"
        }()
        return Text(label)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private func scaledByLabel(_ material: ProductMaterial) -> String? {
        guard let optionId = material.scaledByOptionId,
              let option = options.first(where: { $0.id == optionId }) else { return nil }
        return "SCALED BY \(option.name.uppercased())"
    }

    private func unitDisplay(_ material: ProductMaterial) -> String {
        if let unitId = material.unitId,
           let unit = allUnits.first(where: { $0.id == unitId }) {
            return unit.display
        }
        return ""
    }

    private func formatQuantity(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func metadataChip(_ label: String) -> some View {
        Text(label)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}
