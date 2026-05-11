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

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if bundleItems.isEmpty {
                Text("// NO CHILDREN YET — TAP EDIT TO BUILD THE BUNDLE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(OPSStyle.Layout.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(bundleItems) { item in
                        row(item: item)
                    }
                    rolledRow
                    if bundleProduct.bundlePricingMode == BundlePricingMode.override.rawValue {
                        overrideRow
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
        }
    }

    private func row(item: ProductBundleItem) -> some View {
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
                    .lineLimit(1)
                Text("× \(Int(item.quantity)) · \(formattedPrice(unitPrice)) ea")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Text(formattedPrice(lineTotal))
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    private var rolledTotal: Double {
        bundleItems.reduce(0) { acc, item in
            let unit = childProductsById[item.childProductId]?.basePrice ?? 0
            return acc + unit * item.quantity
        }
    }

    private var rolledRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// ROLLED")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text(formattedPrice(rolledTotal))
                .font(OPSStyle.Typography.bodyBold)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(.top, OPSStyle.Layout.spacing1)
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
            Text(formattedPrice(price))
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
    }

    private func formattedPrice(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}
