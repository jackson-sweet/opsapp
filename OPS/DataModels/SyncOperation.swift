//
//  SyncOperation.swift
//  OPS
//
//  Queued sync operations for offline-first outbound sync.
//

import Foundation
import SwiftData

@Model
final class SyncOperation {
    var id: UUID
    var entityType: String
    var entityId: String
    var operationType: String
    var payload: Data
    var changedFields: String
    var createdAt: Date
    var retryCount: Int = 0
    var status: String = "pending"
    var lastError: String?

    init(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: Data,
        changedFields: [String]
    ) {
        self.id = UUID()
        self.entityType = entityType
        self.entityId = entityId
        self.operationType = operationType
        self.payload = payload
        self.changedFields = changedFields.joined(separator: ",")
        self.createdAt = Date()
    }

    func getChangedFields() -> [String] {
        changedFields.isEmpty ? [] : changedFields.components(separatedBy: ",")
    }

    var isPending: Bool { status == "pending" }
    var isInProgress: Bool { status == "inProgress" }
    var isFailed: Bool { status == "failed" }
    var isCompleted: Bool { status == "completed" }
    var canRetry: Bool { retryCount < 5 }
}
