import Foundation

extension Feedback.SiteVisit {
    static let draftSaved = Toast(label: "// DRAFT SAVED", tone: .success)
    static let savedStagePending = Toast(label: "// VISIT SAVED · STAGE SYNC PENDING", tone: .success)
    static let savedStageReviewRequired = Toast(label: "// VISIT SAVED · REVIEW LEAD STAGE", tone: .warning)
}
