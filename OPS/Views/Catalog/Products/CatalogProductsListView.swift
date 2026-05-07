//
//  CatalogProductsListView.swift
//  OPS
//
//  Stub placeholder for the PRODUCTS segment of the CATALOG tab.
//  Filename and struct prefixed `Catalog` to avoid colliding with the
//  legacy Views/Products/ProductsListView.swift (Xcode build artifacts
//  are keyed by basename, so two ProductsListView.swift files in the
//  target collide on the .stringsdata phase). When the legacy folder is
//  deleted in Phase 7 Task 53 this can be renamed to ProductsListView
//  and the legacy declaration removed.
//

// FIXME(catalog): replace in Phase 7 Task 50

import SwiftUI

struct CatalogProductsListView: View {
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
            VStack(spacing: OPSStyle.Layout.spacing2) {
                Text("// PRODUCTS")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("[Coming in Phase 7]")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
