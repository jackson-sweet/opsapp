//
//  ProjectVisitBookingGate.swift
//  OPS
//
//  Bug 7d94c9f3 — pure decision for the project action bar's BOOK VISIT /
//  REBOOK entry. Booking is opportunity-anchored (book_site_visit takes
//  p_opportunity_id), so the entry exists only when the project has a linked
//  lead the operator may run visits on.
//
//  Permission: the same convert-grant grammar every lead surface uses for
//  visit verbs (LeadDetailView.canConvert, LeadsTabView, the FAB branch).
//  scope(.convert) ⊆ scope(.edit), and the server requires pipeline.edit —
//  so a rendered verb can never come back 42501. Stage is NOT consulted:
//  the linked lead of a converted project is WON by definition, and the
//  booking RPC is stage-blind (verified 2026-08-31); a pre-start walkthrough
//  on a won job is exactly the use case.
//
//  Project status IS consulted: completed/closed/archived projects take no
//  new visits from this surface — the bar's other planning verbs
//  (COMPLETE PROJECT) go quiet on the same boundary.
//

import Foundation

enum ProjectVisitBookingGate {
    static func canOffer(
        projectStatus: Status,
        lead: Opportunity?,
        policy: LeadAccessPolicy
    ) -> Bool {
        guard let lead else { return false }
        guard projectStatus != .completed,
              projectStatus != .closed,
              projectStatus != .archived else { return false }
        return policy.can(.convert, assignedTo: lead.assignedTo)
    }
}
