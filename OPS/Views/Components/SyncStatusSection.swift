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
    struct RenderState {
        let pending: [SyncOperation]
        let failed: [SyncOperation]
        let isSyncing: Bool
        let trackedCount: Int
    }

    var sectionTitle: String? = nil
    var renderStateOverride: RenderState? = nil
    @EnvironmentObject private var dataController: DataController
    @State private var isExpanded: Bool = false

    static func shouldRender(
        pendingCount: Int,
        failedCount: Int,
        isSyncing: Bool,
        trackedCount: Int
    ) -> Bool {
        pendingCount > 0 || failedCount > 0 || isSyncing || trackedCount > 0
    }

    /// Access sync state from the engine (SyncEngine is @Observable).
    private var syncEngine: SyncEngine {
        dataController.syncEngine
    }

    private var liveRenderState: RenderState {
        RenderState(
            pending: syncEngine.getPendingOperations(),
            failed: syncEngine.getFailedOperations(),
            isSyncing: syncEngine.isSyncing,
            trackedCount: syncEngine.pendingOperationCount
        )
    }

    var body: some View {
        // Read tracked engine state so the view re-renders when sync changes,
        // then fetch the live operation lists for display.
        // The override is a narrow visual-test seam; production always takes
        // this live path. Reading trackedCount keeps @Observable subscribed as
        // operations move between pending, failed, and done.
        let state = renderStateOverride ?? liveRenderState

        if Self.shouldRender(
            pendingCount: state.pending.count,
            failedCount: state.failed.count,
            isSyncing: state.isSyncing,
            trackedCount: state.trackedCount
        ) {
            VStack(spacing: 0) {
                if let sectionTitle {
                    SyncStatusSectionHeader(title: sectionTitle)
                }

                SyncStatusPanel(
                    pending: state.pending,
                    failed: state.failed,
                    isSyncing: state.isSyncing,
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
