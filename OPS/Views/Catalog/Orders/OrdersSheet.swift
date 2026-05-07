//
//  OrdersSheet.swift
//  OPS
//
//  Stub placeholder for the catalog orders sheet (kebab → Orders).
//

// FIXME(catalog): replace in Phase 9 Task 57

import SwiftUI

struct OrdersSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("// ORDERS")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("[Coming in Phase 9]")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("ORDERS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
    }
}
