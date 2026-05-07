//
//  TagsManageSheet.swift
//  OPS
//
//  Stub placeholder for the catalog tags management sheet.
//  Replaced fully in Task 45 of this phase.
//

// FIXME(catalog): replace in Phase 5 Task 45

import SwiftUI

struct TagsManageSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("// TAGS")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("[Coming in Task 45]")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("TAGS")
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
