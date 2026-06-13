//
//  CompletionGateView.swift
//  OPS
//
//  Onboarding rebuild P4 — Task 4.3: the COMPLETION GATE. The single terminal
//  screen BOTH paths end on — owner (crewCode → completionGate) and crew
//  (emergencyContact → completionGate, the crew screens land in P5). Design spec
//  §4.2 (Completion gate).
//
//  This is the FINISH of onboarding. On appear it ACKs completion to the server
//  (via the injected boundary, which wraps `OnboardingManager.markOnboardingComplete
//  OrQueue()`), then admits the user into the authenticated app. It is built to
//  WorkspacePreloadGate's standard — its explicit quality benchmark:
//
//    • Logo mark + a thin accent sweep bar (STATIC under Reduce Motion) + status
//      copy in the unified "setting up" loading voice — the SAME strings
//      WorkspacePreloadGate renders, so the two entry paths read as one product.
//    • Honors Reduce Motion (sweep → static hairline, staged fades → instant).
//    • The single OPS easing curve — no spring, no bounce.
//    • Reserved layout so the queued status / escape hatch can't shift the screen.
//    • A watchdog + escape hatch so the gate can NEVER trap the user.
//
//  ACK-or-queue contract (never traps the user):
//    • ACK lands (≤ ceiling) → `.acknowledged` → fire the SUCCESS haptic (the final
//      FINISH of onboarding — the single most important success haptic in the flow),
//      then admit to the app.
//    • ACK fails / times out → `.queued` → show a brief "finishes in the background"
//      status, then STILL admit (the SyncEngine sweep retries the ACK later, and
//      `shouldShowOnboarding` already treats pending as complete).
//    • The call hangs forever → a hard watchdog admits anyway, and an "ENTER OPS"
//      escape surfaces after a ceiling so the user can self-admit. Either way the
//      user gets in.
//
//  Terminal / forward-only: `completionGate.backEdge == nil` (no Back) and NO SIGN
//  OUT — there is nothing to escape from; the account + workspace exist.
//
//  This is a DUMB screen: it owns no completion logic and reaches no singletons.
//  The completion call is an injected closure (`CompletionBoundary`, wired to the
//  live `OnboardingManager` by the gateway) and admit is an injected closure
//  (wired to the gateway's `handleComplete`), so both the ACK-or-queue handling
//  and the watchdog/escape are unit-testable by driving stubs directly.
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, ZERO shadows. Accent (`opsAccent`)
//      appears ONLY on the sweep segment + the escape-hatch primary CTA.
//    • One easing curve; honored only when Reduce Motion is off.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

// MARK: - Completion boundary (the injected ACK-or-queue seam)

/// The single async action the completion gate performs: ACK onboarding
/// completion to the server, or queue it for the sync sweep on failure. The live
/// adapter (`CompletionLiveBoundary`) wraps `OnboardingManager.markOnboarding
/// CompleteOrQueue()`; tests inject a stub so the gate's handling is exercised
/// with no network. `@MainActor` because the live manager is main-actor isolated.
@MainActor
protocol CompletionBoundary {
    /// Complete onboarding. Returns `.acknowledged` when the server ACK lands (or
    /// was already complete), `.queued` when it failed/timed out and the ACK was
    /// persisted for the SyncEngine sweep. In BOTH cases onboarding is completed
    /// locally so the gate may admit the user.
    func complete() async -> OnboardingManager.CompletionOutcome
}

/// The LIVE boundary, backed by the hardened `OnboardingManager`. The gateway
/// builds this from its own manager. It does NOT reinvent completion — it forwards
/// to `markOnboardingCompleteOrQueue()`, the method that owns the server ACK, the
/// `onboarding_completion_pending` persistence, and the local completion.
///
/// `callCompletion: false` — the gate does NOT want the manager's `onComplete`
/// callback to fire (that legacy callback is the OLD admit path). The gate admits
/// through its OWN injected `onAdmit` closure (the gateway's `handleComplete`), so
/// suppressing the manager callback keeps admit single-sourced and prevents a
/// double-admit.
@MainActor
struct CompletionLiveBoundary: CompletionBoundary {
    let manager: OnboardingManager

    func complete() async -> OnboardingManager.CompletionOutcome {
        await manager.markOnboardingCompleteOrQueue(callCompletion: false)
    }
}

// MARK: - Completion gate

struct CompletionGateView: View {

    /// The ACK-or-queue boundary. The gateway injects `CompletionLiveBoundary`;
    /// tests inject a stub. Called once on appear.
    let boundary: CompletionBoundary

    /// Admit to the app. The gateway wires this to `handleComplete`
    /// (`coordinator.complete()` + `dataController.isAuthenticated = true`). The
    /// gate guarantees this fires EXACTLY ONCE, no matter the outcome — ack,
    /// queued, watchdog, or escape — so the user is never trapped.
    let onAdmit: () -> Void

    // MARK: Tuning

    /// Ceiling for a clean ACK before we surface the escape hatch. The boundary's
    /// own ACK has a tighter server timeout (~8s) and resolves to `.acknowledged`
    /// or `.queued` well before this on any reachable network — so on the normal
    /// path the gate admits on the boundary's return and this never fires. The
    /// escape only surfaces if the boundary's async call itself stalls (e.g. a
    /// wedged URLSession), which the hard watchdog also covers.
    private static let escapeHatchDelay: TimeInterval = 10.0

    /// Hard ceiling. If the boundary call has not returned by here (a genuinely
    /// hung request), the gate admits anyway — completion is queued and retried by
    /// the SyncEngine, so admitting is always safe and the user is never stuck.
    /// Comfortably under ContentView's 30s preload watchdog.
    private static let watchdogDelay: TimeInterval = 15.0

    /// How long the queued ("finishes in the background") status shows before the
    /// gate admits, so the reassurance is readable but the user isn't held.
    private static let queuedDwell: TimeInterval = 1.2

    init(
        boundary: CompletionBoundary,
        onAdmit: @escaping () -> Void
    ) {
        self.boundary = boundary
        self.onAdmit = onAdmit
    }

    #if DEBUG
    /// Snapshot/preview seam — pins the visual state (default loading / queued)
    /// and settles the entrance so the snapshot harness can capture each frame
    /// without driving the async boundary. DEBUG-only.
    init(
        boundary: CompletionBoundary,
        previewPhase: Phase,
        previewSettled: Bool = true,
        onAdmit: @escaping () -> Void = {}
    ) {
        self.boundary = boundary
        self.onAdmit = onAdmit
        _phase = State(initialValue: previewPhase)
        _logoOpacity = State(initialValue: previewSettled ? 1 : 0)
        _loadingOpacity = State(initialValue: previewSettled ? 1 : 0)
        _messageOpacity = State(initialValue: previewSettled ? 1 : 0)
        _previewInert = State(initialValue: true)
    }
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The status the gate is presenting. Drives only the status COPY — the logo +
    /// sweep are constant across phases so the screen never re-lays-out.
    enum Phase: Equatable {
        /// ACK in flight — the unified "setting up" loading voice.
        case syncing
        /// ACK queued (failed/timed out) — admit is imminent, shown briefly.
        case queued
    }

    @State private var phase: Phase = .syncing

    // Staged fade-in (mirrors WorkspacePreloadGate's entrance choreography).
    @State private var logoOpacity: Double = 0
    @State private var loadingOpacity: Double = 0
    @State private var messageOpacity: Double = 0

    // Escape hatch + lifecycle guards.
    @State private var showEscapeHatch = false
    @State private var hasAdmitted = false
    @State private var escapeHatchTask: Task<Void, Never>?
    @State private var watchdogTask: Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?

    #if DEBUG
    /// When true (snapshot seam only) the view performs NO side effects on appear
    /// — no boundary call, no timers — so a render captures a stable frame.
    @State private var previewInert = false
    #endif

    /// Fixed footprint reserved for the escape hatch (button + gap + caption) so
    /// the content above never shifts when the button appears. Matches
    /// WorkspacePreloadGate's reservation approach.
    private var escapeHatchReservedHeight: CGFloat {
        OPSStyle.Layout.bottomCTAHeight + OPSStyle.Layout.spacing5
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // OPS mark — same asset + sizing as WorkspacePreloadGate.
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .opacity(logoOpacity)

                Spacer().frame(height: OPSStyle.Layout.spacing5 + OPSStyle.Layout.spacing3) // 48

                // Ambient in-progress indicator — thin accent sweep, static under RM.
                CompletionSweepBar(reduceMotion: reduceMotion)
                    .opacity(loadingOpacity)

                Spacer().frame(height: OPSStyle.Layout.spacing4) // 24

                // Status copy — the unified "setting up" loading voice. The queued
                // phase swaps the copy in place (the block keeps its footprint).
                statusCopy
                    .opacity(messageOpacity)

                Spacer()

                // Escape hatch — only after the ceiling, only if still un-admitted.
                escapeHatch
                    .frame(height: escapeHatchReservedHeight)
                    .padding(.bottom, OPSStyle.Layout.spacing4)
            }
        }
        .onAppear(perform: startSequence)
        .onDisappear(perform: cancelAll)
    }

    // MARK: - Status copy (unified loading voice → queued reassurance)

    @ViewBuilder
    private var statusCopy: some View {
        VStack(spacing: OPSStyle.Layout.spacing2 + 2) { // 10
            switch phase {
            case .syncing:
                // VERBATIM from WorkspacePreloadGate so both paths read identically.
                Text("SETTING UP YOUR WORKSPACE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(2)
                    .multilineTextAlignment(.center)

                Text("Loading your jobs, photos, and crew")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)

            case .queued:
                // ACK queued — admit is imminent. Reassure, don't alarm: the user
                // did nothing wrong; the rest just isn't blocking them.
                Text("YOU'RE IN")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(2)
                    .multilineTextAlignment(.center)

                Text("Setup finishes in the background")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: phase)
    }

    // MARK: - Escape hatch (never trap the user)

    @ViewBuilder
    private var escapeHatch: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            if showEscapeHatch {
                OnboardingPrimaryCTA(title: "Enter OPS") {
                    admit(reason: .escape)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                Text("Setup finishes in the background")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Sequence

    private func startSequence() {
        OnboardingHaptics.prepare()

        #if DEBUG
        if previewInert { return } // snapshot seam — no side effects
        #endif

        runEntranceFades()
        armEscapeHatch()
        armWatchdog()
        runCompletion()
    }

    /// Staged fade-in on the single OPS curve (instant under Reduce Motion).
    private func runEntranceFades() {
        if reduceMotion {
            logoOpacity = 1; loadingOpacity = 1; messageOpacity = 1
        } else {
            withAnimation(OPSStyle.Animation.standard) { logoOpacity = 1 }
            withAnimation(OPSStyle.Animation.standard.delay(0.4)) { loadingOpacity = 1 }
            withAnimation(OPSStyle.Animation.standard.delay(0.6)) { messageOpacity = 1 }
        }
    }

    /// The ACK-or-queue call. On `.acknowledged` fire the success haptic (the final
    /// FINISH of onboarding) and admit. On `.queued` show the background status
    /// briefly, then admit. Either outcome admits — the user is never trapped.
    private func runCompletion() {
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            let outcome = await boundary.complete()
            guard !Task.isCancelled, !hasAdmitted else { return }

            switch outcome {
            case .acknowledged:
                // The single most important success moment in onboarding.
                OnboardingHaptics.success()
                admit(reason: .acknowledged)

            case .queued:
                // Show the reassurance, then admit. The SyncEngine retries the ACK.
                if reduceMotion {
                    phase = .queued
                } else {
                    withAnimation(OPSStyle.Animation.hover) { phase = .queued }
                }
                try? await Task.sleep(nanoseconds: UInt64(Self.queuedDwell * 1_000_000_000))
                guard !Task.isCancelled, !hasAdmitted else { return }
                admit(reason: .queued)
            }
        }
    }

    /// Surface the "ENTER OPS" escape after the ceiling, only if still un-admitted.
    private func armEscapeHatch() {
        escapeHatchTask?.cancel()
        escapeHatchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.escapeHatchDelay * 1_000_000_000))
            guard !Task.isCancelled, !hasAdmitted else { return }
            if reduceMotion {
                showEscapeHatch = true
            } else {
                withAnimation(OPSStyle.Animation.standard) { showEscapeHatch = true }
            }
        }
    }

    /// Hard backstop. If the boundary call never returns, admit anyway — completion
    /// is queued + retried, so admitting is always safe.
    private func armWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.watchdogDelay * 1_000_000_000))
            guard !Task.isCancelled, !hasAdmitted else { return }
            admit(reason: .watchdog)
        }
    }

    // MARK: - Admit (exactly once)

    /// Why the gate admitted — for diagnostics; admit is identical regardless.
    private enum AdmitReason: String {
        case acknowledged, queued, watchdog, escape
    }

    /// Admit to the app EXACTLY ONCE. Idempotent — the first caller wins; the ack/
    /// queued path, the watchdog, and the escape button all funnel here, and any
    /// later arrival is dropped. Cancels every outstanding timer/task so nothing
    /// fires after admit.
    private func admit(reason: AdmitReason) {
        guard !hasAdmitted else { return }
        hasAdmitted = true
        cancelAll()
        print("[COMPLETION_GATE] Admitting — reason: \(reason.rawValue)")
        onAdmit()
    }

    private func cancelAll() {
        escapeHatchTask?.cancel();  escapeHatchTask = nil
        watchdogTask?.cancel();     watchdogTask = nil
        completionTask?.cancel();   completionTask = nil
    }

    #if DEBUG
    /// A render of the screen for the snapshot harness — identical body, the seam
    /// just suppresses side effects via `previewInert`.
    var snapshotBody: some View { body }
    #endif
}

// MARK: - Sweep Bar

/// A thin horizontal bar with a glowing accent segment that sweeps left-to-right.
/// Matches WorkspacePreloadGate's `WorkspaceSweepBar` exactly (monochrome track,
/// accent segment, ultra-thin line, single OPS easing) so the two loading screens
/// are visually identical. Under Reduce Motion the sweep is replaced by a static
/// centered accent segment — no looping animation.
private struct CompletionSweepBar: View {
    let reduceMotion: Bool

    @State private var sweepPhase: CGFloat = 0

    private let trackWidth: CGFloat = 120
    private let trackHeight: CGFloat = 2

    var body: some View {
        ZStack(alignment: .leading) {
            // Base track — barely-there hairline.
            RoundedRectangle(cornerRadius: 1)
                .fill(OPSStyle.Colors.fillNeutralDim)
                .frame(width: trackWidth, height: trackHeight)

            // Accent segment.
            RoundedRectangle(cornerRadius: 1)
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: trackWidth * 0.3, height: trackHeight)
                .offset(x: reduceMotion
                        ? trackWidth * 0.35           // static, centered
                        : sweepPhase * trackWidth * 0.7)
        }
        .frame(width: trackWidth, height: trackHeight)
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .timingCurve(
                    OPSStyle.Animation.easeSmoothP1x, OPSStyle.Animation.easeSmoothP1y,
                    OPSStyle.Animation.easeSmoothP2x, OPSStyle.Animation.easeSmoothP2y,
                    duration: 1.4
                )
                .repeatForever(autoreverses: true)
            ) {
                sweepPhase = 1.0
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CompletionGateView — syncing") {
    CompletionGateView(
        boundary: PreviewCompletionBoundary(outcome: .acknowledged),
        previewPhase: .syncing
    )
    .preferredColorScheme(.dark)
}

#Preview("CompletionGateView — queued") {
    CompletionGateView(
        boundary: PreviewCompletionBoundary(outcome: .queued),
        previewPhase: .queued
    )
    .preferredColorScheme(.dark)
}

/// A no-op boundary for previews/snapshots. Never touches the network.
@MainActor
struct PreviewCompletionBoundary: CompletionBoundary {
    let outcome: OnboardingManager.CompletionOutcome
    func complete() async -> OnboardingManager.CompletionOutcome { outcome }
}
#endif
