import Foundation

/// Six phases of the OPS "Lead to Revenue" tutorial.
/// Each phase maps to a real stage in the job lifecycle.
enum TutorialPhase: Int, CaseIterable, Identifiable {
    case leadArrives     = 0
    case sendEstimate    = 1
    case estimateApproved = 2
    case crewExecutes    = 3
    case weeklyReview    = 4
    case invoiceAndPay   = 5

    var id: Int { rawValue }

    var next: TutorialPhase? {
        TutorialPhase(rawValue: rawValue + 1)
    }

    static var totalSteps: Int { allCases.count }

    /// Analytics-safe name
    var name: String {
        switch self {
        case .leadArrives:      return "leadArrives"
        case .sendEstimate:     return "sendEstimate"
        case .estimateApproved: return "estimateApproved"
        case .crewExecutes:     return "crewExecutes"
        case .weeklyReview:     return "weeklyReview"
        case .invoiceAndPay:    return "invoiceAndPay"
        }
    }
}
