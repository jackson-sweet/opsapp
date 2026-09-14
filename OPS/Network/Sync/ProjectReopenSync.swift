import Foundation
import SwiftData

/// Reopening is an explicit, immutable command. A later archive or task edit
/// cannot overtake it while its server receipt is still outstanding.
enum ProjectReopenSync {
    static let operationType = "reopenForTask"

    static func isReopen(_ operation: SyncOperation) -> Bool {
        operation.entityType == SyncEntityType.project.rawValue
            && operation.operationType == operationType
    }

    static func preservesOrdering(_ operation: SyncOperation) -> Bool {
        isReopen(operation) || operation.dependsOnId != nil
    }

    static func isHeld(_ operation: SyncOperation, in operations: [SyncOperation]) -> Bool {
        if operation.entityType == SyncEntityType.projectTask.rawValue,
           let payload = try? JSONSerialization.jsonObject(with: operation.payload) as? [String: Any],
           let projectId = payload["project_id"] as? String,
           operations.contains(where: {
               isReopen($0) && $0.entityId.lowercased() == projectId.lowercased()
                   && TaskLifecycleSync.unresolvedStatuses.contains($0.status)
           }) { return true }
        return operations.contains { predecessor in
            guard predecessor.id != operation.id,
                  predecessor.entityType == operation.entityType,
                  predecessor.entityId.lowercased() == operation.entityId.lowercased(),
                  TaskLifecycleSync.unresolvedStatuses.contains(predecessor.status),
                  TaskLifecycleSync.precedes(predecessor, operation) else { return false }
            if operation.entityType == SyncEntityType.project.rawValue {
                return isReopen(predecessor) || isReopen(operation)
            }
            return operation.entityType == SyncEntityType.projectTask.rawValue
                && (predecessor.dependsOnId != nil || operation.dependsOnId != nil)
        }
    }
}

/// Exact server revision metadata, scoped to company + project. Date's ISO
/// formatting drops Postgres microseconds, so it cannot be used for this CAS.
/// This cache contains identifiers/status/revisions only; the durable command
/// copies its revision into SwiftData before any local status changes.
final class ProjectRevisionCache: @unchecked Sendable {
    static let shared = ProjectRevisionCache()
    struct Snapshot: Codable, Equatable {
        let status: String
        let updatedAt: String
    }
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func record(_ dto: SupabaseProjectDTO) {
        guard UUID(uuidString: dto.id) != nil, UUID(uuidString: dto.companyId) != nil,
              let revision = dto.updatedAt, SupabaseDate.parse(revision) != nil else { return }
        lock.lock()
        defer { lock.unlock() }
        let key = key(companyId: dto.companyId, projectId: dto.id)
        // A stale read may only cause a conservative CAS rejection. It never
        // permits a timestamp reconstructed from local model state.
        if let data = try? JSONEncoder().encode(Snapshot(status: dto.status, updatedAt: revision)) {
            defaults.set(data, forKey: key)
        }
    }

    func snapshot(companyId: String, projectId: String) -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: key(companyId: companyId, projectId: projectId)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func key(companyId: String, projectId: String) -> String {
        "project-revision.v1.\(companyId.lowercased()).\(projectId.lowercased())"
    }
}
