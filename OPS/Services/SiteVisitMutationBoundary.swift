import Foundation
import SwiftData

/// Marks the pre-mutation boundary even when a shared context already has WIP.
/// Exact value snapshots keep unrelated inserted/changed models out of the queue.
@MainActor
struct SiteVisitMutationBoundary {
    private let pending: [ObjectIdentifier: [AnyHashable]]

    init(context: ModelContext) {
        pending = Dictionary(
            (context.insertedModelsArray + context.changedModelsArray).compactMap { model in
                Self.values(model).map { (ObjectIdentifier(model), $0) }
            }, uniquingKeysWith: { first, _ in first })
    }

    func changedEntities(in context: ModelContext) -> [any PersistentModel] {
        var seen = Set<ObjectIdentifier>()
        return (context.insertedModelsArray + context.changedModelsArray).filter { model in
            let id = ObjectIdentifier(model)
            guard seen.insert(id).inserted, let values = Self.values(model) else { return false }
            return pending[id] != values
        }
    }

    private static func values(_ entity: any PersistentModel) -> [AnyHashable]? {
        switch entity {
        case let model as SiteVisit:
            return [AnyHashable(model.id),
                AnyHashable(model.opportunityId),
                AnyHashable(model.companyId),
                AnyHashable(model.projectId),
                AnyHashable(model.projectRef),
                AnyHashable(model.clientId),
                AnyHashable(model.clientRef),
                AnyHashable(model.status),
                AnyHashable(model.scheduledAt),
                AnyHashable(model.durationMinutes),
                AnyHashable(model.assigneeIds),
                AnyHashable(model.completedAt),
                AnyHashable(model.notes),
                AnyHashable(model.internalNotes),
                AnyHashable(model.measurements),
                AnyHashable(model.photos),
                AnyHashable(model.address),
                AnyHashable(model.assignedTo),
                AnyHashable(model.calendarEventId),
                AnyHashable(model.createdBy),
                AnyHashable(model.createdAt),
                AnyHashable(model.updatedAt),
                AnyHashable(model.deletedAt),
                AnyHashable(model.needsSync),
                AnyHashable(model.lastSyncedAt),
                AnyHashable(model.loggedActivityId),
                AnyHashable(model.bookedAt),
                AnyHashable(model.reminderLeadMinutes),
                AnyHashable(model.appointmentHandoffId),
                AnyHashable(model.appointmentKind),
                AnyHashable(model.appointmentTitle),
                AnyHashable(model.appointmentLocation)]
        case let model as SiteVisitCaptureArtifact:
            return [AnyHashable(model.id),
                AnyHashable(model.siteVisitId),
                AnyHashable(model.companyId),
                AnyHashable(model.opportunityId),
                AnyHashable(model.kind),
                AnyHashable(model.source),
                AnyHashable(model.title),
                AnyHashable(model.body),
                AnyHashable(model.localAssetURL),
                AnyHashable(model.renderedAssetURL),
                AnyHashable(model.thumbnailURL),
                AnyHashable(model.dimensionsJSON),
                AnyHashable(model.deckDesignId),
                AnyHashable(model.includedInProjectReview),
                AnyHashable(model.capturedAt),
                AnyHashable(model.createdBy),
                AnyHashable(model.createdAt),
                AnyHashable(model.updatedAt),
                AnyHashable(model.deletedAt),
                AnyHashable(model.needsSync),
                AnyHashable(model.lastSyncedAt)]
        case let model as SiteVisitChecklistAnswer:
            return [AnyHashable(model.id),
                AnyHashable(model.siteVisitId),
                AnyHashable(model.companyId),
                AnyHashable(model.opportunityId),
                AnyHashable(model.siteVisitTypeId),
                AnyHashable(model.fieldId),
                AnyHashable(model.label),
                AnyHashable(model.kind),
                AnyHashable(model.required),
                AnyHashable(model.helpText),
                AnyHashable(model.sortOrder),
                AnyHashable(model.answerValueData),
                AnyHashable(model.createdBy),
                AnyHashable(model.createdAt),
                AnyHashable(model.updatedAt),
                AnyHashable(model.deletedAt),
                AnyHashable(model.needsSync),
                AnyHashable(model.lastSyncedAt)]
        case let model as SiteVisitIdentityDraft:
            return [AnyHashable(model.id),
                AnyHashable(model.siteVisitId),
                AnyHashable(model.companyId),
                AnyHashable(model.opportunityId),
                AnyHashable(model.clientId),
                AnyHashable(model.subClientId),
                AnyHashable(model.searchText),
                AnyHashable(model.clientName),
                AnyHashable(model.contactName),
                AnyHashable(model.preferredEmail),
                AnyHashable(model.additionalEmailsJSON),
                AnyHashable(model.phoneNumber),
                AnyHashable(model.address),
                AnyHashable(model.notes),
                AnyHashable(model.createdBy),
                AnyHashable(model.createdAt),
                AnyHashable(model.updatedAt),
                AnyHashable(model.lastCommittedAt),
                AnyHashable(model.deletedAt),
                AnyHashable(model.needsSync),
                AnyHashable(model.lastSyncedAt)]
        default: return nil
        }
    }

    struct Row {
        let type: String
        let id: String
        init(_ model: any PersistentModel) {
            switch model {
            case let row as SiteVisit: type = "visit"; id = row.id
            case let row as SiteVisitCaptureArtifact: type = "artifact"; id = row.id
            case let row as SiteVisitChecklistAnswer: type = "answer"; id = row.id
            case let row as SiteVisitIdentityDraft: type = "draft"; id = row.id
            default: type = ""; id = ""
            }
        }
        func rematerialize(in context: ModelContext) {
            let target = id
            switch type {
            case "visit": _ = try? context.fetch(FetchDescriptor<SiteVisit>(predicate: #Predicate { $0.id == target }))
            case "artifact": _ = try? context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>(predicate: #Predicate { $0.id == target }))
            case "answer": _ = try? context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>(predicate: #Predicate { $0.id == target }))
            case "draft": _ = try? context.fetch(FetchDescriptor<SiteVisitIdentityDraft>(predicate: #Predicate { $0.id == target }))
            default: break
            }
        }
    }
}
