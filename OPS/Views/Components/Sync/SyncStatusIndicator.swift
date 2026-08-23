//
//  SyncStatusIndicator.swift
//  OPS
//
//  Compact sync pill shared by Home's header and the tab-view overlay. Tapping
//  opens PENDING WORK (SYNC RECOVERY · T6). Its attention state —
//  "<n> NEED A LOOK",
//  tan normally, rose when anything is parked (out of auto-retries) — takes
//  precedence over the existing pending/syncing states, and its count comes from
//  the same `RecoveryInventory` the recovery screen reads (not raw pending).
//
//  Placement: Home owns this as an in-flow row inside its measured AppHeader,
//  so TODAY / ACTIVE / ALL cannot begin underneath it. Other tabs retain the
//  app-level band below their measured header. See `SyncPillHeaderLayoutTests`.
//

import Combine
import SwiftUI
import SwiftData

/// The needs-a-look pill — "<n> NEED A LOOK", tan normally, rose when anything
/// is parked. Extracted from `SyncStatusIndicator` so the visual can be rendered
/// and geometrically verified without a DataController or a live SwiftData
/// context (see `SyncPillHeaderLayoutTests`).
///
/// The pill still floats above scrolling content on non-Home roots, so two
/// things remain deliberate in the shared visual:
///
/// * **Opaque base under the tone wash.** The tint alone let the
///   content behind bleed through and made the label unreadable over a busy
///   list. The capsule now sits on `background` first, exactly as `syncingPill`
///   already did, and the shadow reads against a solid edge instead of tinting
///   the fill unevenly.
/// * **The one sanctioned shadow.** `Layout.floatingElevation` — MOBILE.md §8's
///   documented exception for elements that float over scrolling content.
enum SyncAttentionPillLayoutStyle: Equatable {
    case compact
    case expanded

    static func resolve(
        adaptsForAccessibility: Bool,
        dynamicTypeSize: DynamicTypeSize
    ) -> Self {
        adaptsForAccessibility && dynamicTypeSize.isAccessibilitySize
            ? .expanded
            : .compact
    }
}

struct SyncAttentionPill: View {
    let count: Int
    let isParked: Bool
    var isElevated = true
    var adaptsForAccessibility = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Stable hook for the layout regression test — not user-facing copy.
    static let accessibilityID = "sync.attention.pill"

    private var tone: Color { isParked ? OPSStyle.Colors.rose : OPSStyle.Colors.tan }
    private var layoutStyle: SyncAttentionPillLayoutStyle {
        .resolve(
            adaptsForAccessibility: adaptsForAccessibility,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    var body: some View {
        Group {
            if layoutStyle == .expanded {
                expandedPill
            } else {
                compactPill
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.accessibilityID)
    }

    private var compactPill: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            statusIcon
            statusLabel(lineLimit: 1, fixedHorizontal: true)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .background(
            Capsule()
                .fill(OPSStyle.Colors.background)
                .overlay(
                    Capsule().fill(
                        tone.opacity(OPSStyle.Colors.StatusTagM.fill)
                    )
                )
        )
        .overlay(
            Capsule().strokeBorder(
                tone.opacity(OPSStyle.Colors.StatusTagM.border),
                lineWidth: OPSStyle.Layout.Border.standard
            )
        )
        .shadow(
            color: isElevated ? OPSStyle.Layout.floatingElevation.color : .clear,
            radius: isElevated ? OPSStyle.Layout.floatingElevation.radius : 0,
            x: OPSStyle.Layout.floatingElevation.x,
            y: OPSStyle.Layout.floatingElevation.y
        )
    }

    /// Accessibility fallback for Home's measured header. The label keeps the
    /// user's chosen text size and full count, wrapping inside the 20pt header
    /// inset instead of painting beyond the screen. A button surface replaces
    /// the capsule because the control can now be taller than one text line.
    private var expandedPill: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
            statusIcon
            statusLabel(lineLimit: nil, fixedHorizontal: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .frame(
            maxWidth: .infinity,
            minHeight: OPSStyle.Layout.touchTargetMin,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .fill(OPSStyle.Colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .fill(tone.opacity(OPSStyle.Colors.StatusTagM.fill))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .strokeBorder(
                    tone.opacity(OPSStyle.Colors.StatusTagM.border),
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
    }

    private var statusIcon: some View {
        Image(systemName: isParked ? "exclamationmark.circle.fill" : "exclamationmark.circle")
            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
            .foregroundColor(tone)
    }

    private func statusLabel(
        lineLimit: Int?,
        fixedHorizontal: Bool
    ) -> some View {
        Text(SyncStatusCopy.PendingWork.pillBadge(count: count))
            .font(OPSStyle.Typography.smallCaption.weight(.bold))
            .foregroundColor(tone)
            .tracking(0.8)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: fixedHorizontal, vertical: !fixedHorizontal)
    }
}

enum SyncStatusIndicatorPlacement: Equatable {
    case appOverlay
    case homeHeader
}

/// Stable recovery state owned by MainTabView. Visual placement can switch
/// between Home and the app overlay without repeating the inventory fetches or
/// discarding a debounced refresh in flight.
@MainActor
final class SyncStatusIndicatorModel: ObservableObject {
    @Published private(set) var attentionCount = 0
    @Published private(set) var anyParked = false

    func refresh(from modelContext: ModelContext) {
        let inventory = RecoveryInventory.load(
            from: modelContext,
            queue: ClientLeadAutocreateQueue.shared
        )
        attentionCount = inventory.attentionCount
        anyParked = inventory.attention.contains { $0.tone == .parked }
    }
}

/// Trailing row reserved inside Home's measured header. It is constructed only
/// while the indicator is visible, so the zero state adds no empty band.
struct AppHeaderSyncStatusRow<Content: View>: View {
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                content
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    content
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }
}

/// Compact indicator showing pending / attention sync status. Tap → PENDING WORK.
struct SyncStatusIndicator: View {
    var placement: SyncStatusIndicatorPlacement = .appOverlay

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var statusModel: SyncStatusIndicatorModel

    @State private var showPendingWork = false

    private var showsPending: Bool { dataController.hasPendingSyncs && !dataController.isConnected }
    private var isVisible: Bool {
        statusModel.attentionCount > 0 || showsPending || dataController.isSyncing
    }

    var body: some View {
        Group {
            if isVisible {
                if placement == .homeHeader {
                    AppHeaderSyncStatusRow {
                        indicatorButton
                    }
                } else {
                    indicatorButton
                }
            }
        }
        .fullScreenCover(isPresented: $showPendingWork) {
            PendingWorkScreen(leading: .close)
                .environmentObject(dataController)
        }
    }

    // MARK: - Pill variants

    private var indicatorButton: some View {
        Button {
            showPendingWork = true
        } label: {
            pill
        }
        .buttonStyle(.plain)
        .frame(
            minWidth: OPSStyle.Layout.touchTargetMin,
            minHeight: OPSStyle.Layout.touchTargetMin
        )
    }

    @ViewBuilder
    private var pill: some View {
        if statusModel.attentionCount > 0 {
            attentionPill
        } else if showsPending {
            pendingPill
        } else {
            syncingPill
        }
    }

    /// NEW — needs-a-look state. Tan, or rose when a permanent rejection is parked.
    private var attentionPill: some View {
        SyncAttentionPill(
            count: statusModel.attentionCount,
            isParked: statusModel.anyParked,
            isElevated: placement == .appOverlay,
            adaptsForAccessibility: placement == .homeHeader
        )
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

}

#Preview {
    ZStack {
        OPSStyle.Colors.background
        SyncStatusIndicator()
            .environmentObject(DataController())
            .environmentObject(SyncStatusIndicatorModel())
    }
}
