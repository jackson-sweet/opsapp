//
//  DeletedProjectTaskOperationSettlement.swift
//  OPS
//
//  Retires only the provably obsolete task-update shape: the server-row-missing
//  permanent rejection plus an exact same-company local soft-delete tombstone.
//  An active or absent local task remains protected for operator review.
//

import Foundation
import SwiftData

@MainActor
enum DeletedProjectTaskOperationSettlement {
    struct Result: Equatable {
        let settledOperationIds: [UUID]

        static let empty = Result(settledOperationIds: [])
    }

    @discardableResult
    static func sweep(
        in modelContext: ModelContext,
        activeCompanyId: String,
        now: Date = Date()
    ) throws -> Result {
        let company = canonical(activeCompanyId)
        guard !company.isEmpty else { return .empty }

        let tombstoneIds = Set(
            try modelContext.fetch(FetchDescriptor<ProjectTask>())
                .filter {
                    canonical($0.companyId) == company && $0.deletedAt != nil
                }
                .map { canonical($0.id) }
        )
        guard !tombstoneIds.isEmpty else { return .empty }

        let operations = try modelContext.fetch(FetchDescriptor<SyncOperation>())
            .filter {
                $0.entityType == SyncEntityType.projectTask.rawValue
                    && $0.operationType == "update"
                    && $0.status == "parked"
                    && ($0.lastError?.lowercased().contains(
                        SyncError.serverRowMissingMarker
                    ) == true)
                    && tombstoneIds.contains(canonical($0.entityId))
            }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        guard !operations.isEmpty else { return .empty }

        try modelContext.transaction {
            for operation in operations {
                operation.status = "completed"
                operation.completedAt = now
                operation.serverConfirmedAt = nil
                operation.lastAttemptedAt = nil
                operation.lastError = nil
            }
        }
        return Result(settledOperationIds: operations.map(\.id))
    }

    private static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
