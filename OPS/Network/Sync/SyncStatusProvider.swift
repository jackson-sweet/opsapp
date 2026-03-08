//
//  SyncStatusProvider.swift
//  OPS
//
//  Observable provider that reads SyncOperation records and
//  exposes sync-status data for the UI layer.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class SyncStatusProvider {

    // MARK: - Public state

    var pendingCount: Int = 0
    var failedCount: Int = 0
    var isSyncing: Bool = false
    var isFullySynced: Bool = true
    var statusItems: [SyncStatusItem] = []
    var showSyncedConfirmation: Bool = false

    // MARK: - Private

    private var refreshTimer: Timer?
    private var modelContext: ModelContext?

    /// Tracks previous fully-synced state so we can detect the transition.
    private var wasFullySynced: Bool = true

    // MARK: - Configuration

    /// Store the model context, perform an initial refresh, and start a
    /// repeating 2-second timer to keep the UI up to date.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    // MARK: - Refresh

    /// Query SyncOperations and update all published properties.
    func refresh() {
        guard let context = modelContext else { return }

        do {
            // --- Pending operations (pending OR inProgress) ---
            let pendingPredicate = #Predicate<SyncOperation> { op in
                op.status == "pending" || op.status == "inProgress"
            }
            var pendingDescriptor = FetchDescriptor<SyncOperation>(predicate: pendingPredicate)
            pendingDescriptor.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
            let pendingOps = try context.fetch(pendingDescriptor)

            // --- Failed operations ---
            let failedPredicate = #Predicate<SyncOperation> { op in
                op.status == "failed"
            }
            var failedDescriptor = FetchDescriptor<SyncOperation>(predicate: failedPredicate)
            failedDescriptor.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
            let failedOps = try context.fetch(failedDescriptor)

            // Update counts
            pendingCount = pendingOps.count
            failedCount = failedOps.count
            isSyncing = pendingOps.contains { $0.status == "inProgress" }

            // Build statusItems (pending + failed, capped at 50)
            var items: [SyncStatusItem] = []

            for op in pendingOps {
                guard items.count < 50 else { break }
                items.append(statusItem(from: op))
            }
            for op in failedOps {
                guard items.count < 50 else { break }
                items.append(statusItem(from: op))
            }

            statusItems = items

            // Determine fully-synced state
            let nowFullySynced = pendingOps.isEmpty && failedOps.isEmpty
            isFullySynced = nowFullySynced

            // Detect transition: was NOT synced → now IS synced
            if nowFullySynced && !wasFullySynced {
                showSyncedConfirmation = true
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    self?.showSyncedConfirmation = false
                }
            }
            wasFullySynced = nowFullySynced

        } catch {
            // Silently handle fetch errors; the UI will keep its last state.
        }
    }

    // MARK: - Retry

    /// Reset a single failed operation so the sync engine picks it up again.
    func retryFailed(operationId: UUID) {
        guard let context = modelContext else { return }

        do {
            let targetId = operationId
            let predicate = #Predicate<SyncOperation> { op in
                op.id == targetId && op.status == "failed"
            }
            var descriptor = FetchDescriptor<SyncOperation>(predicate: predicate)
            descriptor.fetchLimit = 1

            if let operation = try context.fetch(descriptor).first {
                operation.status = "pending"
                operation.retryCount = 0
                operation.lastError = nil
                try context.save()
                refresh()
            }
        } catch {
            // Save failed — nothing to surface to UI for now.
        }
    }

    /// Reset all failed operations for retry.
    func retryAllFailed() {
        guard let context = modelContext else { return }

        do {
            let predicate = #Predicate<SyncOperation> { op in
                op.status == "failed"
            }
            let descriptor = FetchDescriptor<SyncOperation>(predicate: predicate)
            let failedOps = try context.fetch(descriptor)

            for op in failedOps {
                op.status = "pending"
                op.retryCount = 0
                op.lastError = nil
            }

            try context.save()
            refresh()
        } catch {
            // Save failed — nothing to surface to UI for now.
        }
    }

    // MARK: - Helpers

    /// Build a `SyncStatusItem` from a `SyncOperation`.
    private func statusItem(from op: SyncOperation) -> SyncStatusItem {
        let itemStatus: SyncItemStatus
        switch op.status {
        case "pending":
            itemStatus = .pending
        case "inProgress":
            itemStatus = .syncing
        case "failed":
            itemStatus = .failed
        case "completed":
            itemStatus = .completed
        default:
            itemStatus = .pending
        }

        return SyncStatusItem(
            id: op.id,
            entityType: op.entityType,
            entityId: op.entityId,
            operationType: op.operationType,
            description: describeOperation(op),
            status: itemStatus,
            progress: nil,
            error: op.lastError,
            timestamp: op.createdAt
        )
    }

    /// Generate a human-readable description of the sync operation.
    private func describeOperation(_ op: SyncOperation) -> String {
        let verb: String
        switch op.operationType.lowercased() {
        case "create", "insert":
            verb = "Creating"
        case "update":
            verb = "Updating"
        case "delete":
            verb = "Deleting"
        default:
            verb = "Syncing"
        }

        let entity = humanReadableEntity(op.entityType)
        return "\(verb) \(entity)"
    }

    /// Convert a camelCase or snake_case entity type string into a
    /// user-friendly label (e.g. "projectTask" → "task",
    /// "inventoryItem" → "inventory item").
    private func humanReadableEntity(_ entityType: String) -> String {
        switch entityType.lowercased() {
        case "project":                return "project"
        case "projecttask":            return "task"
        case "user":                   return "user"
        case "client":                 return "client"
        case "subclient":              return "sub-client"
        case "company":                return "company"
        case "tasktype":               return "task type"
        case "taskstatusoption":       return "status option"
        case "expense":                return "expense"
        case "expensecategory":        return "expense category"
        case "estimate":               return "estimate"
        case "invoice":                return "invoice"
        case "lineitem":               return "line item"
        case "payment":                return "payment"
        case "projectnote":            return "note"
        case "photoannotation":        return "photo annotation"
        case "calendaruserevent":      return "calendar event"
        case "inventoryitem":          return "inventory item"
        case "inventoryunit":          return "inventory unit"
        case "inventorytag":           return "inventory tag"
        case "inventorysnapshot":      return "inventory snapshot"
        case "inventorysnapshotitem":  return "snapshot item"
        case "timeentry":              return "time entry"
        case "signaturecapture":       return "signature"
        case "formsubmission":         return "form submission"
        case "localphoto":             return "photo"
        default:                       return entityType
        }
    }
}
