//
//  LeadDetailView.swift
//  OPS
//
//  PLACEHOLDER — replaced by Phase 3 of the LEADS tab rebuild.
//  Real implementation spec: docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §7.
//
//  Renders a minimal placeholder so the LeadsTabView navigation wires up
//  and compiles. Phase 3 replaces this file's contents with the full detail
//  view (hero, KPI strip, contact card, follow-ups card, activity timeline,
//  stage history, sticky action bar).
//

import SwiftUI

struct LeadDetailView: View {
    let opportunity: Opportunity

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("// LEAD DETAIL — TO BE BUILT")
                    .font(OPSStyle.Typography.metadata)
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .textCase(.uppercase)
                Text(opportunity.contactName.isEmpty ? "Unnamed lead" : opportunity.contactName)
                    .font(OPSStyle.Typography.pageTitle)
                    .foregroundColor(OPSStyle.Colors.text)
            }
        }
        .navigationBarBackButtonHidden(false)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LeadDetailView(opportunity: .preview(contactName: "Helen Calloway", stage: .quoted, estimatedValue: 14_200))
    }
    .preferredColorScheme(.dark)
}
#endif
