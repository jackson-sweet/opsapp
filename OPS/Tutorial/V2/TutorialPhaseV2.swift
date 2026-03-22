import Foundation

/// Nine phases of the OPS "Lead to Revenue" V2 tutorial.
/// Extended from v1's 6 phases to include project closeout, financials, and closing.
/// Every piece of information transforms into the next — one continuous metamorphosis.
enum TutorialPhaseV2: Int, CaseIterable, Identifiable {
    case leadArrives       = 0   // Lead card slides down, typewriter
    case sendEstimate      = 1   // Card morphs to estimate, line items, send
    case estimateApproved  = 2   // Approval → tasks peel off → crew assigned
    case crewExecutes      = 3   // Status cycling → project assembly
    case calendarWeek      = 4   // Calendar reveals multiple projects
    case weeklyReview      = 5   // Swipe review cards (stack on right)
    case projectCloseout   = 6   // Stacked → projects → invoices → sent → paid
    case financials        = 7   // Per-project revenue/expense/profit
    case closing           = 8   // 13 steps → 11 struck → tagline → CTA

    var id: Int { rawValue }

    var next: TutorialPhaseV2? {
        TutorialPhaseV2(rawValue: rawValue + 1)
    }

    static var totalSteps: Int { allCases.count }

    /// Analytics-safe name
    var name: String {
        switch self {
        case .leadArrives:      return "leadArrives"
        case .sendEstimate:     return "sendEstimate"
        case .estimateApproved: return "estimateApproved"
        case .crewExecutes:     return "crewExecutes"
        case .calendarWeek:     return "calendarWeek"
        case .weeklyReview:     return "weeklyReview"
        case .projectCloseout:  return "projectCloseout"
        case .financials:       return "financials"
        case .closing:          return "closing"
        }
    }
}
