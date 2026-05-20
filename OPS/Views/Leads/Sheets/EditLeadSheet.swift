//
//  EditLeadSheet.swift
//  OPS
//
//  PLACEHOLDER — replaced by Phase 4 of the LEADS tab rebuild.
//  Real implementation spec: docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §8.4.
//

import SwiftUI

struct EditLeadSheet: View {
    let opportunity: Opportunity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("// EDIT · \(opportunity.id.prefix(6)) — TO BE BUILT")
                .font(OPSStyle.Typography.metadata)
                .kerning(1.6)
                .foregroundColor(OPSStyle.Colors.text3)
                .textCase(.uppercase)
            Button("CLOSE") { dismiss() }
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
