import Foundation
import SwiftData

/// Task deletion/restoration are ordered commands. They must never be swallowed
/// by generic last-write/delete-wins coalescing, even after offline backoff.
enum TaskLifecycleSync {
    static let unresolvedStatuses: Set<String> = ["pending", "inProgress", "failed", "parked", "quarantined"]
    static let scheduleFields: Set<String> = ["start_date", "end_date", "duration", "start_time", "end_time", "all_day", "schedule_locked"]

    static func isLifecycle(_ operation: SyncOperation) -> Bool {
        guard operation.entityType == SyncEntityType.projectTask.rawValue else { return false }
        return operation.operationType == "delete" || operation.getChangedFields().contains("deleted_at")
            || payload(operation).keys.contains("deleted_at")
    }

    static func isRestore(_ operation: SyncOperation) -> Bool {
        operation.entityType == SyncEntityType.projectTask.rawValue
            && operation.operationType == "update" && payload(operation)["deleted_at"] is NSNull
    }

    static func carriesSchedule(_ operation: SyncOperation) -> Bool {
        !scheduleFields.isDisjoint(with: operation.getChangedFields())
            || !scheduleFields.isDisjoint(with: payload(operation).keys)
    }

    static func precedes(_ lhs: SyncOperation, _ rhs: SyncOperation) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func isHeld(_ operation: SyncOperation, in operations: [SyncOperation]) -> Bool {
        guard operation.entityType == SyncEntityType.projectTask.rawValue else { return false }
        return operations.contains {
            $0.id != operation.id && $0.entityId.lowercased() == operation.entityId.lowercased()
                && unresolvedStatuses.contains($0.status) && isLifecycle($0) && precedes($0, operation)
        }
    }

    static func hasUnresolvedCreationOrRestore(taskId: String, in operations: [SyncOperation]) -> Bool {
        operations.contains {
            $0.entityType == SyncEntityType.projectTask.rawValue
                && $0.entityId.lowercased() == taskId.lowercased()
                && unresolvedStatuses.contains($0.status)
                && ($0.operationType == "create" || isRestore($0))
        }
    }

    /// A confirmed write releases the dirty flag only when no other edit owns it.
    static func clearNeedsSyncAfterConfirmation(_ operation: SyncOperation, companyId: String?, in context: ModelContext) throws {
        guard operation.entityType == SyncEntityType.projectTask.rawValue,
              let companyId, !companyId.isEmpty else { return }
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        guard !operations.contains(where: {
            $0.entityType == operation.entityType && $0.entityId.lowercased() == operation.entityId.lowercased()
                && unresolvedStatuses.contains($0.status)
        }) else { return }
        let ids = [operation.entityId.lowercased(), operation.entityId.uppercased()]
        for task in try context.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate { ids.contains($0.id) })) {
            guard task.companyId.lowercased() == companyId.lowercased() else { continue }
            task.needsSync = false
        }
    }

    private static func payload(_ operation: SyncOperation) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: operation.payload) as? [String: Any]) ?? [:]
    }
}
