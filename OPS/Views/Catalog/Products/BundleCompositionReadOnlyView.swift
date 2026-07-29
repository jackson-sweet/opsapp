//
//  BundleCompositionReadOnlyView.swift
//  OPS
//
//  Read-only renderer for a bundle's composition. Embedded into
//  ProductDetailView when the product is a bundle (kind=.package). Mirrors
//  the row visuals from NewBundleSheet so the operator sees one consistent
//  shape across create + detail.
//

import SwiftUI

struct BundleCompositionReadOnlyView: View {
    let bundleProduct: Product
    let bundleItems: [ProductBundleItem]
    let childProductsById: [String: Product]

    private var groupedItems: ProductBundleCompositionGroups {
        ProductBundleCompositionGrouping.group(bundleItems)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if groupedItems.required.isEmpty && groupedItems.suggested.isEmpty {
                Text("// NO CHILDREN YET — TAP EDIT TO BUILD THE BUNDLE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(OPSStyle.Layout.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No bundle children")
                    .accessibilityValue("Tap edit to build the bundle.")
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    if !groupedItems.required.isEmpty {
                        groupLabel("// REQUIRED")
                        ForEach(groupedItems.required) { item in
                            row(item: item, participatesInPrice: true)
                        }
                        rolledRow
                        if bundleProduct.bundlePricingMode == BundlePricingMode.override.rawValue {
                            overrideRow
                        }
                    }
                    if !groupedItems.suggested.isEmpty {
                        if !groupedItems.required.isEmpty {
                            Divider().background(OPSStyle.Colors.separator)
                        }
                        groupLabel("// SUGGESTED ADD-ONS")
                        ForEach(groupedItems.suggested) { item in
                            row(item: item, participatesInPrice: false)
                        }
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface()
            }
        }
    }

    private func groupLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .padding(.top, OPSStyle.Layout.spacing1)
    }

    private func row(item: ProductBundleItem, participatesInPrice: Bool) -> some View {
        let child = childProductsById[item.childProductId]
        let unitPrice = child?.basePrice ?? 0
        let lineTotal = unitPrice * item.quantity
        return HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: child?.category3Way.iconName ?? "questionmark.circle")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(child?.name ?? "—")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(2)
                Text("× \(Int(item.quantity)) · \(BooksFormat.price(unitPrice)) ea")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Text(participatesInPrice ? BooksFormat.price(lineTotal) : "+ \(BooksFormat.price(lineTotal))")
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(participatesInPrice
                                 ? OPSStyle.Colors.primaryText
                                 : OPSStyle.Colors.tertiaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(child?.name ?? "Bundle child")
        .accessibilityValue(
            "\(participatesInPrice ? "Required" : "Suggested add-on"), quantity \(Int(item.quantity)), unit \(BooksFormat.price(unitPrice)), total \(BooksFormat.price(lineTotal))"
        )
    }

    private var rolledTotal: Double {
        ProductBundleCompositionGrouping.requiredRollupTotal(
            bundleItems,
            productsById: childProductsById
        )
    }

    private var rolledRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// ROLLED")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text(BooksFormat.price(rolledTotal))
                .font(OPSStyle.Typography.bodyBold)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(.top, OPSStyle.Layout.spacing1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rolled total")
        .accessibilityValue(BooksFormat.price(rolledTotal))
    }

    @ViewBuilder
    private var overrideRow: some View {
        let price = bundleProduct.basePrice
        let margin: Double? = {
            guard price > 0 else { return nil }
            return ((price - rolledTotal) / price) * 100
        }()
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// OVERRIDE")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text(BooksFormat.price(price))
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
            if let margin {
                Text("· \(Int(margin.rounded()))%")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(margin >= 0
                                     ? OPSStyle.Colors.tertiaryText
                                     : OPSStyle.Colors.errorText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Override price")
        .accessibilityValue(
            margin.map { "\(BooksFormat.price(price)), margin \(Int($0.rounded())) percent" } ?? BooksFormat.price(price)
        )
    }
}
