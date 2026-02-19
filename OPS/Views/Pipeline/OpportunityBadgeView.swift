//
//  OpportunityBadgeView.swift
//  OPS
//
//  Compact badge showing a linked pipeline opportunity — tappable to navigate to detail.
//

import SwiftUI

struct OpportunityBadgeView: View {
    let opportunityId: String
    @State private var opportunity: Opportunity? = nil

    var body: some View {
        if let opp = opportunity {
            NavigationLink(value: opp) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LINKED OPPORTUNITY")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryAccent)
                        if let name = opp.contactName, !name.isEmpty {
                            Text("\(name) — \(opp.stage.displayName)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.secondaryAccent.opacity(0.1))
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.secondaryAccent.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
