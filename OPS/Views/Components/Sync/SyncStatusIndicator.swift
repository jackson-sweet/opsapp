//
//  SyncStatusIndicator.swift
//  OPS
//
//  Compact sync pill in the tab-view overlay. Tapping opens PENDING WORK
//  (SYNC RECOVERY · T6). The pill's NEW attention state — "<n> NEED A LOOK",
//  tan normally, rose when anything is parked (out of auto-retries) — takes
//  precedence over the existing pending/syncing states, and its count comes from
//  the same `RecoveryInventory` the recovery screen reads (not raw pending).
//

import SwiftUI
import SwiftData

/// Compact indicator showing pending / attention sync status. Tap → PENDING WORK.
struct SyncStatusIndicator: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @State private var attentionCount = 0
    @State private var anyParked = false
    @State private var showPendingWork = false

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private var queue: ClientLeadAutocreateQueue { ClientLeadAutocreateQueue.shared }

    private var showsPending: Bool { dataController.hasPendingSyncs && !dataController.isConnected }
    private var isVisible: Bool { attentionCount > 0 || showsPending || dataController.isSyncing }

    var body: some View {
        Group {
            if isVisible {
                Button {
                    showPendingWork = true
                } label: {
                    pill
                }
                .buttonStyle(.plain)
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            }
        }
        .onAppear(perform: refreshAttention)
        .onReceive(refreshTimer) { _ in refreshAttention() }
        .onReceive(NotificationCenter.default.publisher(for: .opsLeadsDidChange)) { _ in refreshAttention() }
        .fullScreenCover(isPresented: $showPendingWork) {
            PendingWorkScreen(leading: .close)
                .environmentObject(dataController)
        }
    }

    // MARK: - Pill variants

    @ViewBuilder
    private var pill: some View {
        if attentionCount > 0 {
            attentionPill
        } else if showsPending {
            pendingPill
        } else {
            syncingPill
        }
    }

    /// NEW — needs-a-look state. Tan, or rose when a permanent rejection is parked.
    private var attentionPill: some View {
        let tone = anyParked ? OPSStyle.Colors.rose : OPSStyle.Colors.tan
        return HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: anyParked ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(tone)

            Text(SyncStatusCopy.PendingWork.pillBadge(count: attentionCount))
                .font(OPSStyle.Typography.smallCaption.weight(.bold))
                .foregroundColor(tone)
                .tracking(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(tone.opacity(0.15)))
        .overlay(Capsule().strokeBorder(tone.opacity(0.55), lineWidth: OPSStyle.Layout.Border.standard))
    }

    private var pendingPill: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                .foregroundColor(OPSStyle.Colors.warningStatus)

            Text("\(dataController.pendingSyncCount) pending")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.warningStatus)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .background(Capsule().fill(OPSStyle.Colors.warningStatus.opacity(0.15)))
        .overlay(Capsule().stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard))
    }

    private var syncingPill: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            TacticalLoadingBarAnimated(
                barCount: 6,
                barWidth: 2,
                barHeight: 6,
                spacing: 3,
                emptyColor: OPSStyle.Colors.primaryAccent.opacity(0.3),
                fillColor: OPSStyle.Colors.primaryAccent
            )

            Text("SYNCING")
                .font(OPSStyle.Typography.smallCaption.weight(.bold))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .tracking(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(OPSStyle.Colors.background.opacity(0.95)))
        .overlay(Capsule().strokeBorder(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: OPSStyle.Layout.Border.standard))
    }

    // MARK: - Attention count (from the same inventory the screen reads)

    private func refreshAttention() {
        let inventory = RecoveryInventory.load(from: modelContext, queue: queue)
        attentionCount = inventory.attentionCount
        anyParked = inventory.attention.contains { $0.tone == .parked }
    }
}

#Preview {
    ZStack {
        OPSStyle.Colors.background
        SyncStatusIndicator()
            .environmentObject(DataController())
    }
}
