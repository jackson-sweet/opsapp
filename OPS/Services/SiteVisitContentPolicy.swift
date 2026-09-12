import Foundation

/// Preservation and completion are different decisions. Any operator input
/// prevents automatic cleanup, including partial identity and checklist work.
@MainActor
enum SiteVisitContentPolicy {
    static func hasContent(visit: SiteVisit?, artifacts: [SiteVisitCaptureArtifact],
                           answers: [SiteVisitChecklistAnswer], drafts: [SiteVisitIdentityDraft]) -> Bool {
        if artifacts.contains(where: \.isActive) || answers.contains(where: { $0.isActive && $0.answerValue.hasContent }) { return true }
        if let visit, hasText([visit.notes, visit.internalNotes, visit.measurements, visit.address]) || !visit.photos.isEmpty { return true }
        return drafts.contains { draft in
            draft.deletedAt == nil && (hasText([draft.searchText, draft.clientName, draft.contactName,
                draft.preferredEmail, draft.phoneNumber, draft.address, draft.notes])
                || draft.additionalEmails.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                || draft.clientId != nil || draft.opportunityId != nil || draft.subClientId != nil)
        }
    }

    private static func hasText(_ values: [String?]) -> Bool {
        values.contains { !($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
