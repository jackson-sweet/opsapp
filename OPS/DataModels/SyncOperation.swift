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
    var lastAttemptedAt: Date?
    /// Lifecycle status. One of:
    /// - `pending`    — queued, eligible for the next outbound push.
    /// - `inProgress` — currently being pushed (set immediately before the network call).
    /// - `completed`  — server confirmed; eligible for cleanup after 24h.
    /// - `failed`     — transient failures exhausted the retry budget (20). Recoverable:
    ///                  the launch / reconnect re-enqueue sweep resets it to `pending`.
    /// - `parked`     — a permanent server rejection (4xx / data / integrity / syntax).
    ///                  NEVER auto-retried. Only an explicit user Retry (→ `pending`,
    ///                  retryCount 0) or Discard moves it. See `SyncErrorClassifier`.
    /// - `quarantined`— site-visit identity/tenant evidence is unsafe. Never sent
    ///                  or exposed through generic Retry; its encrypted recovery
    ///                  entry is the only operator disposition surface.
    var status: String = "pending"
    var lastError: String?

    // Rollback support
    var previousValues: Data?

    // Priority & scheduling
    var priority: Int = 1  // 0 = immediate, 1 = normal, 2 = low
    var requiresWiFi: Bool = false

    // Dependency tracking
    var dependsOnId: String?

    // Completion timestamps
    var completedAt: Date?
    var serverConfirmedAt: Date?

    init(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: Data,
        changedFields: [String],
        previousValues: Data? = nil,
        priority: Int = 1,
        dependsOnId: String? = nil
    ) {
        self.id = UUID()
        self.entityType = entityType
        self.entityId = entityId
        self.operationType = operationType
        self.payload = payload
        self.changedFields = changedFields.joined(separator: ",")
        self.createdAt = Date()
        self.previousValues = previousValues
        self.priority = priority
        self.dependsOnId = dependsOnId
    }

    func getChangedFields() -> [String] {
        changedFields.isEmpty ? [] : changedFields.components(separatedBy: ",")
    }

    var isPending: Bool { status == "pending" }
    var isInProgress: Bool { status == "inProgress" }
    var isFailed: Bool { status == "failed" }
    var isParked: Bool { status == "parked" }
    var isCompleted: Bool { status == "completed" }
    var canRetry: Bool { retryCount < 20 }

    /// Exponential backoff delay capped at 60 seconds.
    /// Use this with `lastAttemptedAt` to determine the earliest eligible retry time:
    /// `lastAttemptedAt.addingTimeInterval(backoffDelay)`
    var backoffDelay: TimeInterval { min(pow(2.0, Double(retryCount)), 60.0) }
}
