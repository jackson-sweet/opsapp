//
//  ProductsServicesSettingsView.swift
//  OPS
//
//  Settings wrapper for the Products catalog. `CatalogProductsListView` is
//  also mounted inside the CATALOG tab, which provides its own page header.
//  When the same list is reached from Settings → Products & Services it needs
//  a SettingsHeader so the user can navigate back. Keeping the wrapper here
//  avoids polluting `CatalogProductsListView` with a settings-only flag.
//

import SwiftUI

struct ProductsServicesSettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Products & Services",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, OPSStyle.Layout.spacing2)

                CatalogProductsListView()
                    .environmentObject(dataController)
            }
        }
        .navigationBarHidden(true)
    }
}
