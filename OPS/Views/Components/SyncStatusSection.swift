//
//  SyncStatusSection.swift
//  OPS
//
//  Engine-wired wrapper for the notifications sync panel. Fetches the live
//  operation lists from SyncEngine and hands them to SyncStatusPanel, which
//  owns all rendering. Splitting the data source (here) from the presentation
//  (SyncStatusPanel) keeps the visuals snapshot-testable. See bug dbada8f5.
//

import SwiftUI

struct SyncStatusSection: View {
    @EnvironmentObject private var dataController: DataController
    @State private var isExpanded: Bool = false

    /// Access sync state from the engine (SyncEngine is @Observable).
    private var syncEngine: SyncEngine {
        dataController.syncEngine
    }

    var body: some View {
        // Read tracked engine state so the view re-renders when sync changes,
        // then fetch the live operation lists for display.
        let isSyncing = syncEngine.isSyncing
        let pending = syncEngine.getPendingOperations()
        let failed = syncEngine.getFailedOperations()
        // Reading pendingOperationCount keeps the @Observable subscription live
        // so the panel re-renders as operations move between pending/failed/done.
        let trackedCount = syncEngine.pendingOperationCount

        if !pending.isEmpty || !failed.isEmpty || isSyncing || trackedCount > 0 {
            SyncStatusPanel(
                pending: pending,
                failed: failed,
                isSyncing: isSyncing,
                isExpanded: $isExpanded,
                onRetry: { requeue([$0]) },
                onRetryAll: { requeue($0) },
                onDismiss: { syncEngine.cancelOperation($0) }
            )
        }
    }

    /// Clears the failed/stuck state on the given operations and kicks a sync.
    private func requeue(_ operations: [SyncOperation]) {
        for op in operations {
            op.status = "pending"
            op.retryCount = 0
            op.lastError = nil
        }
        try? dataController.modelContext?.save()
        Task { await syncEngine.triggerSync() }
    }
}
