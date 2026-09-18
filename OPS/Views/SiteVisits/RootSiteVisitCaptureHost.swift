//
//  RootSiteVisitCaptureHost.swift
//  OPS
//
//  CREW SITE VISITS · P1 — the app-root capture host for a visit opened
//  WITHOUT the Leads tab.
//
//  The Leads tab owns the capture cover for anyone who has it. A crew member
//  assigned to a visit has no Leads tab (and no lead row), so MainTabView
//  presents the same `SiteVisitCaptureView` from here, resuming the exact
//  visit and showing the lead through a detached brief snapshot. Lead-authority
//  actions inside the console are gated by `SiteVisitAccess`, so CREATE
//  PROJECT is only reachable for someone with convert on the bound lead — the
//  hand-off below exists for that case (a Leads-tab user resuming a leadless
//  walk-up they then link).
//

import SwiftUI

/// One root capture presentation: the visit to resume and the lead display
/// snapshot, if one was resolvable.
struct RootSiteVisitCaptureRequest: Identifiable {
    let visitId: String
    let lead: Opportunity?

    var id: String { visitId }

    /// A detached lead for the console built from the visit-keyed brief. It
    /// carries display fields only — never `assigned_to`, value or stage — so
    /// it grants nothing: the console reads an unknown assignee as "no
    /// assigned-scope authority".
    static func leadSnapshot(
        from details: CalendarSiteVisitLeadDetails,
        companyId: String
    ) -> Opportunity {
        let lead = Opportunity(
            id: details.opportunityId,
            companyId: companyId,
            contactName: details.contactName ?? ""
        )
        lead.title = details.title
        lead.address = details.address
        lead.aiSummary = details.agentSummary
        lead.descriptionText = details.leadDescription
        return lead
    }
}

struct RootSiteVisitCaptureHost: ViewModifier {
    @Binding var request: RootSiteVisitCaptureRequest?
    @Binding var convertLead: Opportunity?

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $request) { request in
                SiteVisitCaptureView(
                    opportunity: request.lead,
                    onCreateProject: { converted in
                        self.request = nil
                        // One modal at a time: the cover finishes dismissing
                        // before the convert sheet presents (same hand-off as
                        // the leads tab and the + menu).
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            convertLead = converted
                        }
                    },
                    resumingSiteVisitId: request.visitId
                )
                .environmentObject(dataController)
            }
            .sheet(item: $convertLead) { lead in
                ConvertToProjectSheet(opportunity: lead)
                    .environmentObject(dataController)
                    .environmentObject(appState)
            }
    }
}
