//
//  ProductDetailView.swift
//  OPS
//
//  Detail screen for a single Product. Combines a lightweight in-place
//  editor for base fields with read-only sub-views that surface the
//  product's options, pricing modifiers, and recipe rows.
//

// FIXME(catalog): replace in Phase 7 Task 52

import SwiftUI

struct ProductDetailView: View {
    let product: Product

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
            VStack(spacing: OPSStyle.Layout.spacing2) {
                Text("// PRODUCT DETAIL")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(product.name)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("PRODUCT")
        .navigationBarTitleDisplayMode(.inline)
    }
}
