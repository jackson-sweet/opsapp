import Foundation
import SwiftData

/// Shared read helpers avoid completed-history materialization and the known
/// predicate trap on a never-populated SyncOperation table. Count is SQL-only.
enum RecoveryStoreQueries {
    static func activeOperations(in context: ModelContext, includeStopped: Bool = false) throws -> [SyncOperation] {
        guard try context.fetchCount(FetchDescriptor<SyncOperation>()) > 0 else { return [] }
        return try context.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate {
            $0.status == "pending" || $0.status == "inProgress" || $0.status == "failed" || $0.status == "parked"
                || (includeStopped && ($0.status == "declined" || $0.status == "quarantined"))
        }))
    }

    static func caseVariants(_ ids: Set<String>) -> [String] {
        Array(Set(ids.flatMap {
            let canonical = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return [$0, canonical, canonical.lowercased(), canonical.uppercased()]
        }))
    }
}
