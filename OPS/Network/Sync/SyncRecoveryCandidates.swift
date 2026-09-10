import Foundation
import SwiftData

struct SyncRecoveryCandidates: Sendable {
    var taskIds = Set<String>()
    var deckIds = Set<String>()
    var visitIds = Set<String>()
    var hasParkedTaskUpdates = false
    var hasDeletedVisitParents = false
    var hasParkedMedia = false
    var hasParkedNotes = false
    var hasQuarantines = false
}

enum SyncRecoveryReader {
    /// Historical discovery owns a read-only context on a utility executor.
    /// Return IDs, never registered models. The UI context revalidates each
    /// candidate before writing, so edits made during discovery stay authoritative.
    static func discover(container: ModelContainer, companyId: String) throws -> SyncRecoveryCandidates {
        let signposter = CapturePerformanceTrace.signposter
        let span = signposter.beginInterval("SyncRecoveryDiscovery", id: signposter.makeSignpostID())
        defer { signposter.endInterval("SyncRecoveryDiscovery", span) }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var result = SyncRecoveryCandidates()
        let operations = try RecoveryStoreQueries.activeOperations(in: context, includeStopped: true)
        let owners = Set(operations.map { "\($0.entityType):\($0.entityId.lowercased())" })
        for operation in operations {
            if operation.entityType == "projectTask", operation.status == "parked" { result.hasParkedTaskUpdates = true }
            if operation.entityType == "projectNote", operation.status == "parked" { result.hasParkedNotes = true }
            if operation.status == "quarantined" { result.hasQuarantines = true }
            if operation.operationType == SiteVisitSyncOperation.mediaOperationType,
               operation.status == "parked" { result.hasParkedMedia = true }
            // The mutation path owns the exact deleted-parent error test.
            if operation.operationType == SiteVisitSyncOperation.completionOperationType,
               operation.status == "parked" || operation.status == "failed" { result.hasDeletedVisitParents = true }
        }
        let tasks = try context.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.needsSync && $0.deletedAt == nil }))
        for task in tasks where task.companyId.lowercased() == companyId && !owners.contains("projectTask:\(task.id.lowercased())") {
            result.taskIds.insert(task.id)
        }
        let designs = try context.fetch(FetchDescriptor<DeckDesign>(predicate: #Predicate { $0.deletedAt == nil }))
        for design in designs where design.companyId.lowercased() == companyId
            && (design.needsSync || design.hasUnsyncedDrawing)
            && !owners.contains("deckDesign:\(design.id.lowercased())") {
            result.deckIds.insert(design.id)
        }
        let visits = try context.fetch(FetchDescriptor<SiteVisit>())
        for visit in visits where visit.companyId.lowercased() == companyId && (visit.needsSync || visit.lastSyncedAt == nil) { result.visitIds.insert(visit.id) }
        // Missing parents can be foreign/malformed: retain those exact candidates
        // so the established quarantine path, rather than a guess, owns them.
        for row in try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>(predicate: #Predicate { $0.needsSync || $0.lastSyncedAt == nil })) {
            result.visitIds.insert(row.siteVisitId)
        }
        for row in try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>(predicate: #Predicate { $0.needsSync || $0.lastSyncedAt == nil })) {
            result.visitIds.insert(row.siteVisitId)
        }
        for row in try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>(predicate: #Predicate { $0.needsSync || $0.lastSyncedAt == nil })) {
            result.visitIds.insert(row.siteVisitId)
        }
        // Carry original spellings through scoped predicates. Legacy mixed-case
        // UUIDs must resolve to the existing parent rather than a duplicate.
        let canonicalVisits = Set(result.visitIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        for visit in visits where canonicalVisits.contains(visit.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            result.visitIds.insert(visit.id)
        }
        return result
    }
}
