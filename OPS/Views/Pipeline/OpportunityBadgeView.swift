//
//  OpportunityBadgeView.swift
//  OPS
//
//  Compact badge showing a linked pipeline opportunity — tappable to navigate to detail.
//

import SwiftUI

struct OpportunityBadgeView: View {
    let opportunityId: String
    @EnvironmentObject private var dataController: DataController
    @State private var opportunity: Opportunity? = nil

    var body: some View {
        Group {
            if let opp = opportunity {
                NavigationLink(value: opp) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: OPSStyle.Icons.opportunity)
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LINKED OPPORTUNITY")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryAccent)
                            if !opp.contactName.isEmpty {
                                Text("\(opp.contactName) — \(opp.stage.displayName)")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }
                        Spacer()
                        Image(systemName: OPSStyle.Icons.forward)
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
        .task {
            await loadOpportunity()
        }
    }

    private func loadOpportunity() async {
        guard let companyId = dataController.currentUser?.companyId else { return }
        let repo = OpportunityRepository(companyId: companyId)
        do {
            let dto = try await repo.fetchOne(opportunityId)
            opportunity = dto.toModel()
        } catch {
            // Badge silently fails — non-critical UI element
        }
    }
}
