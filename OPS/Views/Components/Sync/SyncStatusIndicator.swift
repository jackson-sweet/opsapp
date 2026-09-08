//
//  SyncStatusIndicator.swift
//  OPS
//
//  Compact sync pill superimposed on every root's header. Tapping
//  opens PENDING WORK (SYNC RECOVERY · T6). Its attention state —
//  "<n> NEED A LOOK",
//  tan normally, rose when anything is parked (out of auto-retries) — takes
//  precedence over the existing pending/syncing states, and its count comes from
//  the same `RecoveryInventory` the recovery screen reads (not raw pending).
//
//  Placement: every root superimposes this on its own `AppHeader`, sharing the
//  title band's control row with the trailing cluster and painting OVER it
//  (bug 417aac7b). It reserves no layout — nothing below the header moves when
//  an attention item appears — and it is allowed to cover header TEXT (the
//  greeting, the company line, the screen title) AND the trailing control
//  itself, because something needing attention outranks both. It is never
//  allowed to reach the content BELOW the header; see
//  `HeaderSyncStatusGeometry` for why that holds by construction. Home project
//  mode is the sole exception and keeps the same control inside the top project
//  stack after AppHeader leaves the screen. See `SyncPillHeaderLayoutTests` and
//  `HomeSyncStatusLayoutTests`.
//

import Combine
import SwiftUI
import SwiftData

/// The needs-a-look pill — "<n> NEED A LOOK", tan normally, rose when anything
/// is parked. Extracted from `SyncStatusIndicator` so the visual can be rendered
/// and geometrically verified in isolation; the layout proofs measure the whole
/// shipped control inside the shipped `HeaderSyncStatusOverlay` (see
/// `SyncPillHeaderLayoutTests` and `HomeSyncStatusLayoutTests`).
///
/// The pill floats above the header's fade — and, on Home, above the live map —
/// so two things remain deliberate in the shared visual:
///
/// * **Opaque base under the tone wash.** The tint alone let the
///   content behind bleed through and made the label unreadable over a busy
///   list. The capsule now sits on `background` first, exactly as `syncingPill`
///   already did, and the shadow reads against a solid edge instead of tinting
///   the fill unevenly.
/// * **The one sanctioned shadow.** `Layout.floatingElevation` — MOBILE.md §8's
///   documented exception for elements that float over other content. This is
///   NOT a band-only allowance: the pill now floats directly over the header's
///   trailing CONTROL (Home's avatar, every other root's search button), which
///   is precisely the case the exception exists for, and Jackson asked for it
///   in as many words on 2026-09-08 — "with a dropshadow". The shadow is what
///   separates the pill from the control underneath it. Do not delete it, and
///   do not pass `isElevated: false` for the `.header` placement.
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

    /// Accessibility fallback. The label keeps the user's chosen text size and
    /// full count, wrapping inside the insets its host offers instead of
    /// painting beyond the screen. A button surface replaces the capsule
    /// because the control can now be taller than one text line.
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
    /// Superimposed on a root's `AppHeader`, hanging off its bottom edge.
    case header
    /// Home project mode's owned project stack, after `AppHeader` leaves.
    case projectHeader
}

/// Whether a root's header may superimpose the pill at all.
///
/// The pill is the most urgent thing on screen, so it outranks the greeting,
/// the company line and the screen title it covers. It yields only to another
/// sync voice: the restored banner, or a toast that has claimed the topic.
enum HeaderSyncStatusPlacementPolicy {
    static func showsHeaderOverlay(
        isSyncRestoredAlertVisible: Bool,
        isSuppressedByToast: Bool
    ) -> Bool {
        !isSyncRestoredAlertVisible && !isSuppressedByToast
    }
}

/// Geometry of the pill superimposed on `AppHeader`'s title band.
///
/// Bug 417aac7b closed wrong THREE times:
///
/// 1. IN FLOW inside Home's measured header — so TODAY / ACTIVE / ALL and the
///    map under them were pushed down the moment an attention item existed.
/// 2. Floated in MainTabView's app-level band starting exactly at the header's
///    lower edge — which put it straight on top of the ALL filter chip.
/// 3. Superimposed on the header but RESERVING the trailing control cluster's
///    column, which staggered it below-left of the avatar. Jackson,
///    2026-09-08: "The needs a look chip is still not in the correct place. It
///    is being influenced by the avatar. It should appear ONTOP of the avatar."
///
/// The pill is the most urgent thing on screen and it is transient — it is
/// addressed or cancelled, then gone. While it is there it outranks the
/// greeting, the company line, the screen title AND the trailing control, so
/// it takes that control's own row and paints over it. It is influenced by
/// nothing in the band.
///
/// **The placement rule, in one line:** the pill's BOTTOM edge sits on the
/// bottom edge of the `touchTargetMin` control row that `OPSHeaderControlSlot`
/// centres in the band, and the pill grows UPWARD and LEFTWARD from there.
///
/// Two invariants fall out of that by construction — at every width, count,
/// header type and Dynamic Type size, trusting no font metric:
///
/// * **It always covers the trailing control.** Pill and control end on the
///   same row edge and both are at least `touchTargetMin` tall, so their
///   frames always intersect. This is the point, not a side effect.
/// * **It never reaches the content below the header.** The row's bottom edge
///   is `bandHeight / 2 + controlRowHeight / 2`, which is `<= bandHeight` for
///   any band at least `controlRowHeight` tall — and the canonical band's
///   floor is `screenHeaderBandHeight`. The header is the band plus its
///   context strip, so `pill.maxY <= band.maxY <= header.maxY` always. Moving
///   the pill up onto the control row makes this bound strictly TIGHTER than
///   the retired bottom-of-header anchor, which is the original defect's only
///   permanent guard.
enum HeaderSyncStatusGeometry {
    /// Height of the band's control row — the row `OPSHeaderControlSlot`
    /// centres the trailing cluster inside, and the row the pill now shares
    /// with it.
    static let controlRowHeight: CGFloat = OPSStyle.Layout.touchTargetMin
}

/// Bounds of the superimposed pill, published by `HeaderSyncStatusOverlay`.
///
/// Bug 417aac7b closed wrong three times because nothing measured where the
/// pill actually LANDED. Publishing its real frame lets the layout proofs
/// assert against the shipped composition — the real `AppHeader`, the real
/// trailing controls, the real pill — instead of a reconstruction of it that
/// can drift from what ships. The proofs assert BOTH directions: the pill must
/// overlap the trailing control, and must never reach the content below the
/// header.
struct HeaderSyncStatusPillBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The pill's superimposed placement on a root header's title band.
///
/// `AppHeader` and both layout proofs (`HomeSyncStatusLayoutTests`,
/// `SyncPillHeaderLayoutTests`) render this same view, so the regression tests
/// measure the SHIPPED geometry rather than a copy of it that can drift. It is
/// hosted as an `.overlay` on the BAND — never in flow, and therefore always
/// painted above the trailing control it covers.
///
/// The composition reads bottom-up as the placement rule in
/// `HeaderSyncStatusGeometry`: trailing-flush with the band's content inset,
/// bottom-anchored inside the control row, and that row centred in the band
/// exactly where `OPSHeaderControlSlot` centres the control.
struct HeaderSyncStatusOverlay<Pill: View>: View {
    private let pill: () -> Pill

    init(@ViewBuilder pill: @escaping () -> Pill) {
        self.pill = pill
    }

    var body: some View {
        pill()
            .anchorPreference(
                key: HeaderSyncStatusPillBoundsKey.self,
                value: .bounds
            ) { $0 }
            // Flush to the band's own trailing inset — the very edge the
            // control cluster ends on, so the pill lands ON the control rather
            // than staggered beside it. As the count grows the pill extends
            // leftward over the greeting; that is intended.
            .frame(maxWidth: .infinity, alignment: .trailing)
            // Bottom-anchored inside the control row: an accessibility-size
            // pill grows UPWARD over the title, never downward toward the
            // filter row and the content under the header.
            .frame(
                height: HeaderSyncStatusGeometry.controlRowHeight,
                alignment: .bottom
            )
            // ...and that row is centred in the band, which is where
            // `OPSHeaderControlSlot` centres the control being covered.
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }
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

#if DEBUG
    /// Test seam for the layout proofs. Seeds the displayed summary directly so
    /// the REAL `SyncStatusIndicator` can be rendered and measured — rather than
    /// a hand-copied stand-in that drifts from it — without standing up a live
    /// SwiftData inventory read. Never called from app code.
    func seedAttentionForLayoutProof(_ summary: RecoveryAttentionSummary) {
        self.summary = summary
    }
#endif

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
    var placement: SyncStatusIndicatorPlacement = .header

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

    /// The capsule is centred in its glove-safe frame in BOTH placements.
    ///
    /// It used to be bottom-aligned for `.header`, because the pill then hung
    /// off the header's bottom edge and had to grow upward over header text.
    /// The pill now shares the band's control row with the trailing control it
    /// covers (`HeaderSyncStatusGeometry`), and that control is centred in the
    /// row — so centring the capsule is what lands it ON the control instead of
    /// low against its bottom edge. In the project stack the pill shares a
    /// normal action row with EXIT PROJECT and was always centred.
    private var indicatorButton: some View {
        Button {
            showPendingWork = true
        } label: {
            pill
        }
        .buttonStyle(.plain)
        .frame(
            minWidth: OPSStyle.Layout.touchTargetMin,
            minHeight: OPSStyle.Layout.touchTargetMin,
            alignment: .center
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
    /// Every placement adapts for accessibility (bug 417aac7b): at accessibility
    /// sizes it renders the full-width `expandedPill`, wrapping its label inside
    /// whatever insets its host gives it instead of painting past the screen
    /// edge.
    ///
    /// Superimposed on a header the capsule floats over the header's own fade,
    /// over the live map on Home, and — since 2026-09-08 — directly over the
    /// header's trailing CONTROL. That is MOBILE.md §8's documented shadow
    /// exception at its most literal, and Jackson asked for it explicitly
    /// ("with a dropshadow"), so `isElevated` is TRUE for `.header` and must
    /// stay that way: the elevation is what separates the pill from the avatar
    /// underneath it. Inside the project stack the pill is a plain row member
    /// with nothing beneath it, so it takes no shadow.
    private var attentionPill: some View {
        SyncAttentionPill(
            count: statusModel.attentionCount,
            isParked: statusModel.anyParked,
            isElevated: placement == .header,
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
