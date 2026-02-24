//
//  SyncQueue.swift
//  OPS
//
//  Centralized outbound sync queue.
//  Manages SyncOperation entities in SwiftData.
//  Drains FIFO with exponential backoff.
//

import Foundation
import SwiftData
import Combine

@MainActor
class SyncQueue: ObservableObject {
    private var modelContext: ModelContext?
    private var connectivityMonitor: ConnectivityMonitor
    private var drainTask: Task<Void, Never>?
    private var isProcessing = false

    /// Set to true once repositories are connected and processOperation can function.
    /// Until this is true, drainQueue() will no-op to prevent burning retries.
    var isConfigured = false

    @Published var pendingCount: Int = 0
    @Published var failedCount: Int = 0

    init(connectivityMonitor: ConnectivityMonitor) {
        self.connectivityMonitor = connectivityMonitor
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshCounts()
    }

    // MARK: - Enqueue

    /// Queue a new sync operation. Coalesces updates to the same entity.
    func enqueue(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: Data,
        changedFields: [String]
    ) {
        guard let context = modelContext else { return }

        // Coalesce: if pending update exists for same entity, merge fields
        if operationType == "update" {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate<SyncOperation> {
                    $0.entityId == entityId &&
                    $0.entityType == entityType &&
                    $0.status == "pending" &&
                    $0.operationType == "update"
                }
            )
            if let existing = try? context.fetch(descriptor).first {
                let existingFields = Set(existing.getChangedFields())
                let newFields = Set(changedFields)
                let merged = existingFields.union(newFields)
                existing.changedFields = Array(merged).joined(separator: ",")
                existing.payload = payload
                print("[SYNC_QUEUE] Coalesced update for \(entityType)/\(entityId)")
                refreshCounts()
                return
            }
        }

        let operation = SyncOperation(
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payload: payload,
            changedFields: changedFields
        )
        context.insert(operation)
        try? context.save()

        print("[SYNC_QUEUE] Enqueued \(operationType) for \(entityType)/\(entityId)")
        refreshCounts()

        // Try to drain immediately if connected
        if connectivityMonitor.isConnected {
            drainQueue()
        }
    }

    // MARK: - Drain Queue

    func drainQueue() {
        guard isConfigured else {
            print("[SYNC_QUEUE] Not yet configured, skipping drain")
            return
        }
        guard !isProcessing else { return }
        guard connectivityMonitor.isConnected else {
            print("[SYNC_QUEUE] Offline, skipping drain")
            return
        }

        drainTask = Task {
            isProcessing = true
            defer { isProcessing = false }

            while let operation = fetchNextPending() {
                operation.status = "inProgress"
                try? modelContext?.save()

                let success = await processOperation(operation)

                if success {
                    operation.status = "completed"
                } else {
                    operation.retryCount += 1
                    if operation.canRetry {
                        operation.status = "pending"
                        let delay = pow(2.0, Double(operation.retryCount))
                        print("[SYNC_QUEUE] Retry #\(operation.retryCount) in \(delay)s")
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    } else {
                        operation.status = "failed"
                        print("[SYNC_QUEUE] Failed permanently: \(operation.entityType)/\(operation.entityId)")
                    }
                }

                try? modelContext?.save()
                refreshCounts()
            }

            cleanupCompleted()
        }
    }

    // MARK: - Process Single Operation

    private func processOperation(_ operation: SyncOperation) async -> Bool {
        // TODO: Route to appropriate repository based on entityType
        // This will be wired up when SupabaseSyncManager is rewritten
        // Pattern:
        //   1. Decode operation.payload to the entity's DTO
        //   2. Based on operationType: create/update/delete via repository
        //   3. On conflict: use ConflictResolver
        //   4. Return true on success, false on failure

        print("[SYNC_QUEUE] Processing \(operation.operationType) for \(operation.entityType)/\(operation.entityId)")

        // Placeholder — will be connected to repositories in the sync coordinator rewrite
        operation.lastError = "Not yet connected to repositories"
        return false
    }

    // MARK: - Helpers

    private func fetchNextPending() -> SyncOperation? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "pending" },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func refreshCounts() {
        guard let context = modelContext else { return }
        let pendingDescriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "pending" || $0.status == "inProgress" }
        )
        let failedDescriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "failed" }
        )
        pendingCount = (try? context.fetchCount(pendingDescriptor)) ?? 0
        failedCount = (try? context.fetchCount(failedDescriptor)) ?? 0
    }

    private func cleanupCompleted() {
        guard let context = modelContext else { return }
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.status == "completed" && $0.createdAt < oneHourAgo
            }
        )
        if let completed = try? context.fetch(descriptor) {
            for op in completed {
                context.delete(op)
            }
            try? context.save()
        }
    }
}
