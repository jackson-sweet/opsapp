//
//  CatalogToolbarTitle.swift
//  OPS
//
//  Shared OPS-styled navigation titles for Catalog sheets.
//

import SwiftUI

struct CatalogToolbarTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
    }
}

extension View {
    func catalogNavigationTitle(_ title: String) -> some View {
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CatalogToolbarTitle(title: title)
                }
            }
    }
}
