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
//  Placement: `MainTabView` floats this in a band offset by the tab header's
//  measured height (`AppHeaderHeightKey`), so it can never land on the header's
//  trailing action cluster. It used to start at the top safe area — the same
//  rectangle the search button occupies — which put the button's translucent
//  disc on top of the pill and swallowed taps. See `SyncPillHeaderLayoutTests`.
//

import SwiftUI
import SwiftData

/// The needs-a-look pill — "<n> NEED A LOOK", tan normally, rose when anything
/// is parked. Extracted from `SyncStatusIndicator` so the visual can be rendered
/// and geometrically verified without a DataController or a live SwiftData
/// context (see `SyncPillHeaderLayoutTests`).
///
/// The pill floats above whatever tab is scrolling underneath it, so two things
/// are deliberate here:
///
/// * **Opaque base under the tone wash.** The tint alone (`tone × 0.15`) let the
///   content behind bleed through and made the label unreadable over a busy
///   list. The capsule now sits on `background` first, exactly as `syncingPill`
///   already did, and the shadow reads against a solid edge instead of tinting
///   the fill unevenly.
/// * **The one sanctioned shadow.** `Layout.floatingElevation` — MOBILE.md §8's
///   documented exception for elements that float over scrolling content.
struct SyncAttentionPill: View {
    let count: Int
    let isParked: Bool

    /// Stable hook for the layout regression test — not user-facing copy.
    static let accessibilityID = "sync.attention.pill"

    private var tone: Color { isParked ? OPSStyle.Colors.rose : OPSStyle.Colors.tan }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: isParked ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(tone)

            Text(SyncStatusCopy.PendingWork.pillBadge(count: count))
                .font(OPSStyle.Typography.smallCaption.weight(.bold))
                .foregroundColor(tone)
                .tracking(0.8)
                // The reported symptom was a clipped "LOOK". Never wrap, never
                // truncate — the pill grows instead, at any count and any
                // Dynamic Type size.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .background(
            Capsule()
                .fill(OPSStyle.Colors.background)
                .overlay(Capsule().fill(tone.opacity(0.15)))
        )
        .overlay(Capsule().strokeBorder(tone.opacity(0.55), lineWidth: OPSStyle.Layout.Border.standard))
        .shadow(
            color: OPSStyle.Layout.floatingElevation.color,
            radius: OPSStyle.Layout.floatingElevation.radius,
            x: OPSStyle.Layout.floatingElevation.x,
            y: OPSStyle.Layout.floatingElevation.y
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}

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
        SyncAttentionPill(count: attentionCount, isParked: anyParked)
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
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
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
