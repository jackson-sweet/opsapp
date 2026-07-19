//
//  SiteVisitStageDefault.swift
//  OPS
//
//  Pure policy for the lead stage a completed site visit should default to.
//
//  Bug (site-visit report) — completing a visit auto-converted the lead to
//  WON. It must not. Saving a visit means the operator has engaged the lead
//  (an RFQ / qualifying-level touch), so a brand-new lead advances to
//  QUALIFYING; a lead already further along is left where it is (never
//  regressed); a terminal lead (won/lost/discarded) is never resurrected or
//  altered. The operator can still override the preselection in the review
//  sheet's stage picker — this only decides the DEFAULT.
//

import Foundation

enum SiteVisitStageDefault {

    /// The stage a visit's lead should be preset to on save. Never returns a
    /// terminal stage that the lead wasn't already in — saving a visit is not
    /// a conversion.
    static func defaultStage(current: PipelineStage) -> PipelineStage {
        switch current {
        case .newLead:
            // A visit is the first real engagement — qualify the lead.
            return .qualifying
        case .qualifying, .quoting, .quoted, .followUp, .negotiation:
            // Already in flight — don't regress the operator's progress.
            return current
        case .won, .lost, .discarded:
            // Terminal — a visit save must never touch a closed lead.
            return current
        }
    }

    /// Non-terminal stages the review sheet offers as pickable chips, in
    /// pipeline order. Terminal stages (won/lost/discarded) are deliberately
    /// excluded — closing a lead is an explicit action elsewhere, not a
    /// side effect of saving a visit.
    static var selectableStages: [PipelineStage] {
        [.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]
    }
}
