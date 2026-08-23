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
    var sectionTitle: String? = nil
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
            VStack(spacing: 0) {
                if let sectionTitle {
                    SyncStatusSectionHeader(title: sectionTitle)
                }

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
    }

    /// Clears the failed/stuck state on the given operations and kicks a sync.
    private func requeue(_ operations: [SyncOperation]) {
        syncEngine.retryOperations(operations)
        Task { await syncEngine.triggerSync() }
    }
}

/// Local title used only when the compact panel sits inside a larger content
/// rail. The panel keeps its own operation count and status sentence below.
struct SyncStatusSectionHeader: View {
    let title: String

    var body: some View {
        PanelSectionHeader(label: title)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3_5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }
}
