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
//  Placement: every root floats this in the app-level band below its measured
//  header — Home included (bug 417aac7b: the pill overlays Home's content
//  instead of displacing it; it no longer owns an in-flow header row). Home
//  project mode is the sole exception and keeps the same control inside the top
//  project stack after AppHeader leaves the screen. See
//  `SyncPillHeaderLayoutTests` and `HomeSyncStatusLayoutTests`.
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
    private var ink: Color {
        isParked ? OPSStyle.Colors.roseTextM : OPSStyle.Colors.tanTextM
    }
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
            .foregroundColor(ink)
    }

    private func statusLabel(
        lineLimit: Int?,
        fixedHorizontal: Bool
    ) -> some View {
        Text(SyncStatusCopy.PendingWork.pillBadge(count: count))
            .font(OPSStyle.Typography.smallCaption.weight(.bold))
            .foregroundColor(ink)
            .tracking(0.8)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: fixedHorizontal, vertical: !fixedHorizontal)
    }
}

enum SyncStatusIndicatorPlacement: Equatable {
    case appOverlay
    case projectHeader
}

enum HomeSyncStatusPlacementPolicy {
    static func showsProjectModeFallback(
        isInProjectMode: Bool,
        isSyncStatusPresentationVisible: Bool
    ) -> Bool {
        isInProjectMode && !isSyncStatusPresentationVisible
    }
}

enum SyncStatusIndicatorVisibility {
    static func isVisible(
        attentionCount: Int,
        hasPendingSyncs: Bool,
        isConnected: Bool,
        isSyncing: Bool,
        isSyncStatusPresentationVisible: Bool
    ) -> Bool {
        guard !isSyncStatusPresentationVisible else { return false }
        return attentionCount > 0 || (hasPendingSyncs && !isConnected) || isSyncing
    }
}

/// SwiftUI can reverse an in-flight transition when project mode changes
/// quickly. Phase ownership keeps both the incoming and settled host live while
/// making only a fully departed snapshot inert.
enum HomeSyncStatusHostOwnership {
    static func isInteractive(phase: TransitionPhase) -> Bool {
        phase != .didDisappear
    }
}

struct HomeSyncStatusHostTransition: Transition {
    let reduceMotion: Bool

    @ViewBuilder
    func body(content: Content, phase: TransitionPhase) -> some View {
        if reduceMotion {
            OpacityTransition()
                .apply(content: content, phase: phase)
                .allowsHitTesting(HomeSyncStatusHostOwnership.isInteractive(phase: phase))
                .accessibilityHidden(!HomeSyncStatusHostOwnership.isInteractive(phase: phase))
        } else {
            MoveTransition(edge: .top)
                .combined(with: OpacityTransition())
                .apply(content: content, phase: phase)
                .allowsHitTesting(HomeSyncStatusHostOwnership.isInteractive(phase: phase))
                .accessibilityHidden(!HomeSyncStatusHostOwnership.isInteractive(phase: phase))
        }
    }
}

/// Stable recovery state owned by MainTabView. Visual placement can switch
/// between Home and the app overlay without repeating the inventory fetches or
/// discarding a debounced refresh in flight.
@MainActor
final class SyncStatusIndicatorModel: ObservableObject {
    @Published private(set) var summary = RecoveryAttentionSummary()
    var attentionCount: Int { summary.attentionCount }
    var anyParked: Bool { summary.anyParked }
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var displayedIdentity: String?
    private var requestedContainer: ModelContainer?

    func refresh(from modelContext: ModelContext) {
        requestedContainer = modelContext.container
        refreshGeneration += 1
        let user = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        let company = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
        let identity = "\(user.lowercased()):\(company.lowercased())"
        if displayedIdentity != identity {
            displayedIdentity = identity
            if summary != RecoveryAttentionSummary() { summary = RecoveryAttentionSummary() }
        }
        // A slow read coalesces requests instead of building concurrent inventories.
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                let generation = self.refreshGeneration
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased() ?? ""
                let userId = UserDefaults.standard.string(forKey: "currentUserId")?.lowercased() ?? ""
                guard !companyId.isEmpty, !userId.isEmpty,
                      let container = self.requestedContainer else { break }
                let queue = ClientLeadAutocreateQueue.shared
                let autocreates = (queue.parkedRequests + queue.activeRequests).map(AutocreateSnapshot.init(from:))
                do {
                    let quarantines = try await SiteVisitRecoveryVault.shared.quarantinedVisitIds(userId: userId, companyId: companyId)
                    let snapshot = try await Task.detached(priority: .utility) {
                        try RecoveryAttentionReader.read(
                            container: container, companyId: companyId,
                            autocreates: autocreates, quarantinedVisitIds: quarantines
                        )
                    }.value
                    guard !Task.isCancelled else { break }
                    let currentCompany = UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased() ?? ""
                    let currentUser = UserDefaults.standard.string(forKey: "currentUserId")?.lowercased() ?? ""
                    if generation == self.refreshGeneration,
                       currentCompany == companyId, currentUser == userId,
                       self.summary != snapshot {
                        self.summary = snapshot
                    }
                } catch {
                    // An unreadable snapshot is not evidence of zero attention.
                    print("[SyncStatus] Compact recovery read failed: \(error)")
                }
                if generation == self.refreshGeneration { break }
            } while !Task.isCancelled
            self.refreshTask = nil
        }
    }
}

/// Keeps project recovery status and EXIT PROJECT in one owned header row.
/// Accessibility sizes stack the two controls so neither truncates, overlaps,
/// or steals the other's 44pt hit target.
struct ProjectModeSyncStatusActions<Status: View, ExitAction: View>: View {
    private let status: Status
    private let exitAction: ExitAction

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        @ViewBuilder status: () -> Status,
        @ViewBuilder exitAction: () -> ExitAction
    ) {
        self.status = status()
        self.exitAction = exitAction()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing2) {
                    status
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    exitAction
                }
            } else {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    status
                    Spacer(minLength: 0)
                    exitAction
                }
            }
        }
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
        SyncStatusIndicatorVisibility.isVisible(
            attentionCount: statusModel.attentionCount,
            hasPendingSyncs: dataController.hasPendingSyncs,
            isConnected: dataController.isConnected,
            isSyncing: dataController.isSyncing,
            isSyncStatusPresentationVisible: false
        )
    }

    var body: some View {
        Group {
            if isVisible {
                indicatorButton
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
        .accessibilityHint("Opens pending work")
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
    ///
    /// Every placement adapts for accessibility now that the floating band is
    /// the pill's only normal-mode home (bug 417aac7b): at accessibility sizes
    /// it renders the full-width `expandedPill`, wrapping its label inside the
    /// band's insets instead of painting past the screen edge. The floating
    /// shadow stays band-only — MOBILE.md §8's single documented exception.
    private var attentionPill: some View {
        SyncAttentionPill(
            count: statusModel.attentionCount,
            isParked: statusModel.anyParked,
            isElevated: placement == .appOverlay,
            adaptsForAccessibility: true
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
