import Foundation

/// Automatic retry retains the original command's authority. A missing
/// expected stage/revision is a review item, never something recovery fills in.
enum SiteVisitCommandRecoveryPolicy {
    static func mayAutomaticallyResume(_ operation: SyncOperation, userId: String?, companyId: String?) -> Bool {
        guard operation.operationType == SiteVisitSyncOperation.stageOperationType else { return true }
        guard operation.entityType == SyncEntityType.siteVisit.rawValue,
              operation.status == "failed" || operation.status == "inProgress",
              let envelope = try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: operation.payload),
              let command = envelope.stageCommand, command.canDeliver,
              command.actorId.lowercased() == userId?.lowercased(),
              command.companyId.lowercased() == companyId?.lowercased(),
              command.companyId.lowercased() == envelope.companyId.lowercased(),
              command.siteVisitId.lowercased() == envelope.siteVisitId.lowercased(),
              envelope.siteVisitId.lowercased() == envelope.entityId.lowercased(),
              envelope.entityId.lowercased() == operation.entityId.lowercased() else { return false }
        return true
    }
}
