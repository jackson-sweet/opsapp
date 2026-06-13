//
//  InviteCheckStepView.swift
//  OPS
//
//  Onboarding rebuild P5 — S4c (Invite check): the AUTO-TRANSITION screen on the
//  CREW path. The user has just created (or signed into) their account as crew;
//  here the app silently checks the server for pending team invitations matching
//  their email, then routes them onward. No input — the screen drives itself.
//
//  Design spec §4.2 S4c. On appear it runs the injected `InviteCheckBoundary`
//  (the live one calls `CompanyRepository.checkPendingInvites(email:)`) and
//  branches on the outcome:
//    • 1+ invites → `.invitePicker` (the picker shows 1 or N company cards — a
//      single-card picker still lets the user confirm their crew before joining).
//    • 0 invites  → `.codeEntry(provenance: .zeroInvites)` (no invite found; the
//      worker types the code their boss gave them).
//    • FETCH/DECODE FAILURE (R13) → a VISIBLE, retry-able error state. NEVER
//      silently treated as zero invites. The screen surfaces CHECK AGAIN (re-run)
//      and ENTER CODE INSTEAD (→ codeEntry(.zeroInvites)), and fires an
//      `onboarding_invite_check_failed` diagnostic. inviteCheck has no back-edge
//      (it is a transition), so SIGN OUT is the escape on the failure state.
//
//  ROUTING CONTRACT — the screen owns NO flow logic and reaches NO singletons. The
//  check is funnelled through an injected `InviteCheckBoundary` returning an
//  `InviteCheckOutcome`; the navigation decision is the pure `InviteCheckRouter`.
//  The gateway wires the live boundary + the coordinator advances; tests inject a
//  stub boundary and drive the router directly — all WITHOUT touching the network.
//  The fetched invites are persisted via `onInvitesFetched` so the picker doesn't
//  re-fetch.
//
//  NEVER-TRAP — the screen has NO back-edge (it is a transition), so a wedged or
//  slow connection must not strand the user behind a spinner with no escape. The
//  boundary's URLSession can hang ~60s; long before that a SOFT TIMEOUT
//  (`softTimeout`) escalates a still-running check to the existing `.failed` state,
//  which already offers CHECK AGAIN + ENTER CODE INSTEAD + SIGN OUT — i.e. "took
//  too long" is treated as a soft, actionable failure (mirrors CompletionGateView's
//  watchdog/escape pattern). A run-generation guard ignores a late boundary success
//  that returns AFTER the timeout escalated, so a stale success can never yank the
//  user back out of the escape state they chose to act from.
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, ZERO shadows. Accent (`opsAccent`)
//      appears ONLY on the one primary CTA (CHECK AGAIN, via the shared component).
//    • Loading is the §10 inline spinner + a `//`-prefixed JetBrains Mono status
//      label. The failure state is the §10 error pattern (`// ERROR — ` rose label
//      + Mohave body + retry).
//    • Built on the shared `OnboardingStepHeader` / `OnboardingPrimaryCTA` /
//      `OnboardingSecondaryCTA`. Nothing re-rolled.
//    • One easing curve; honored only when Reduce Motion is off.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

// MARK: - Invite-check boundary (the testable seam)

/// What an invite check resolved to. The screen branches on these; the gateway
/// produces them from the live `CompanyRepository`. `.found` carries the fetched
/// invites so the picker (or the zero-invite route) is decided WITHOUT a re-fetch.
enum InviteCheckOutcome: Equatable {
    /// The check completed. `invites` is the (possibly empty) list of pending
    /// invitations for the user's email. Empty → route to code entry; non-empty →
    /// route to the picker.
    case found([PendingInviteDTO])

    /// The check FAILED (network / RPC / server). R13: surface a VISIBLE,
    /// retry-able error — NEVER silently treated as zero invites.
    case failed
}

extension InviteCheckOutcome {
    // PendingInviteDTO is not Equatable (and need not be); equate structurally on
    // the discriminant + the invitation ids, which uniquely identify each invite.
    static func == (lhs: InviteCheckOutcome, rhs: InviteCheckOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.failed, .failed):
            return true
        case let (.found(a), .found(b)):
            return a.map(\.invitationId) == b.map(\.invitationId)
        default:
            return false
        }
    }
}

/// The async boundary S4c funnels the invite check through. Implemented live by
/// the gateway (over `CompanyRepository.checkPendingInvites(email:)`); stubbed in
/// tests. Never throws — failures map to `.failed` so the screen always has an
/// outcome to branch on.
@MainActor
protocol InviteCheckBoundary {
    func checkInvites() async -> InviteCheckOutcome
}

// MARK: - S4c screen

struct InviteCheckStepView: View {

    /// The async invite-check boundary. Injected so the screen never touches the
    /// RPC directly.
    let boundary: InviteCheckBoundary

    /// Persist the fetched invites so the picker doesn't re-fetch. The gateway
    /// wires this to `coordinator.update`. Invoked with the found invites BEFORE
    /// the picker advance.
    let onInvitesFetched: ([PendingInviteDTO]) -> Void

    /// 1+ invites → advance to `.invitePicker`. The gateway wires the advance.
    let onHasInvites: () -> Void

    /// 0 invites → advance to `.codeEntry(provenance: .zeroInvites)`. The gateway
    /// wires the advance.
    let onNoInvites: () -> Void

    /// The R13 ENTER CODE INSTEAD escape from the failure state →
    /// `.codeEntry(provenance: .zeroInvites)`. Same destination as `onNoInvites`,
    /// kept distinct so the gateway can wire it independently and the intent reads
    /// clearly at the call site.
    let onEnterCodeInstead: () -> Void

    /// SIGN OUT escape — the only bail-out on this no-back-edge transition. The
    /// gateway wires the real auth signout.
    let onSignOut: () -> Void

    // MARK: Init

    init(
        boundary: InviteCheckBoundary,
        onInvitesFetched: @escaping ([PendingInviteDTO]) -> Void,
        onHasInvites: @escaping () -> Void,
        onNoInvites: @escaping () -> Void,
        onEnterCodeInstead: @escaping () -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.boundary = boundary
        self.onInvitesFetched = onInvitesFetched
        self.onHasInvites = onHasInvites
        self.onNoInvites = onNoInvites
        self.onEnterCodeInstead = onEnterCodeInstead
        self.onSignOut = onSignOut
    }

    #if DEBUG
    /// Snapshot/preview seam — seeds the visual `@State` so a renderer can capture
    /// the loading vs failure states (otherwise only reachable after an async
    /// interaction). When `previewInert` is set the screen does NOT auto-run the
    /// check on appear, so the captured frame is stable and no boundary fires.
    init(
        boundary: InviteCheckBoundary,
        previewPhase: Phase,
        previewInert: Bool = true
    ) {
        self.boundary = boundary
        self.onInvitesFetched = { _ in }
        self.onHasInvites = {}
        self.onNoInvites = {}
        self.onEnterCodeInstead = {}
        self.onSignOut = {}
        _phase = State(initialValue: previewPhase)
        _hasAppeared = State(initialValue: true)
        self.previewInert = previewInert
    }
    #endif

    /// When true (DEBUG snapshot only), the screen never auto-runs the check.
    private var previewInert = false

    // MARK: Tuning

    /// Soft timeout for a still-running check. The boundary's own request can hang
    /// up to URLSession's ~60s default; long before that this escalates a check
    /// that hasn't resolved to the actionable `.failed` state (CHECK AGAIN + ENTER
    /// CODE INSTEAD + SIGN OUT), so a slow/wedged connection never traps the user
    /// behind a spinner. On any reachable network the boundary returns well under
    /// this, so on the normal path this never fires. Mirrors CompletionGateView's
    /// escape-hatch ceiling, sized for a fetch (not the full preload).
    private static let softTimeout: TimeInterval = 8.0

    // MARK: Phase

    /// The screen's lifecycle: checking (spinner) → routed away (handled by the
    /// host advance) OR failed (the visible R13 / slow-connection error state).
    enum Phase: Equatable {
        case checking
        case failed
    }

    @State private var phase: Phase = .checking
    @State private var hasAppeared = false
    @State private var hasRun = false
    /// Monotonic run id. Each `runCheck()` bumps it; the timeout task and the
    /// boundary continuation both capture the id they were started under and act
    /// ONLY if it still matches — so a stale boundary result that returns AFTER the
    /// soft timeout escalated (or after a retry started a newer run) is ignored and
    /// can never yank the user back out of the escape state they chose.
    @State private var runGeneration = 0
    /// The armed soft-timeout task for the current run. Cancelled on a real outcome,
    /// on a retry, and on disappear so nothing fires after the screen is gone.
    @State private var timeoutTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            content
        }
        .onAppear {
            OnboardingHaptics.prepare()
            if !hasAppeared {
                if reduceMotion {
                    hasAppeared = true
                } else {
                    withAnimation(OPSStyle.Animation.page) { hasAppeared = true }
                }
            }
            if !previewInert { runCheck() }
        }
        .onDisappear {
            // The screen is leaving (routed onward or torn down) — stop the timer so
            // it can't fire against a dead view.
            cancelTimeout()
        }
    }

    #if DEBUG
    /// A render of the screen for the snapshot harness only. Identical body; the
    /// `previewInert` init keeps it from auto-running the check.
    var snapshotBody: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            content
        }
    }
    #endif

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .checking:
            checkingState
        case .failed:
            failedState
        }
    }

    // MARK: - Checking state (§10 loading — inline spinner + status label)

    private var checkingState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.text2))
                .controlSize(.regular)

            Text("// CHECKING FOR INVITES")
                .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                .tracking(1.6)
                .foregroundColor(OPSStyle.Colors.text3)
                .accessibilityLabel("Checking for invites")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(OPSStyle.Layout.spacing3_5)
        .opacity(hasAppeared ? 1 : 0)
    }

    // MARK: - Failed state (R13 — VISIBLE, retry-able, never a silent zero)

    private var failedState: some View {
        VStack(alignment: .leading, spacing: 0) {
            // SIGN OUT is the only bail-out on this no-back-edge transition.
            OnboardingStepHeader(
                title: "Can't reach the crew",
                onSignOut: onSignOut
            )

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text("// ERROR — INVITE CHECK FAILED")
                        .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                        .tracking(1.4)
                        .foregroundColor(OPSStyle.Colors.rose)
                        .accessibilityLabel("Error. Invite check failed.")

                    Text("Couldn't check for invites. Check your connection and try again, or enter the code your boss gave you.")
                        .font(OPSStyle.Typography.body) // Mohave 16pt
                        .foregroundColor(OPSStyle.Colors.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: OPSStyle.Layout.spacing2_5) {
                    OnboardingPrimaryCTA(title: "Check again", trailingArrow: false) {
                        runCheck()
                    }

                    OnboardingSecondaryCTA(title: "Enter code instead") {
                        onEnterCodeInstead()
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing4)

            Spacer(minLength: 0)
        }
        .opacity(hasAppeared ? 1 : 0)
    }

    // MARK: - Actions

    /// Run (or re-run) the invite check. Resets to the checking phase, bumps the run
    /// generation, arms the soft timeout, then awaits the boundary and routes via the
    /// pure router. A failure lands on the visible error phase and fires the
    /// diagnostic — NEVER a silent zero (R13). A still-running check that crosses the
    /// soft timeout is escalated to the same `.failed` state so the user is never
    /// trapped behind the spinner.
    private func runCheck() {
        // Start a NEW run: invalidate any in-flight boundary/timeout from a prior
        // run (a retry, or the first appear) so only this run's result lands.
        runGeneration += 1
        let generation = runGeneration

        phase = .checking
        hasRun = true

        armTimeout(for: generation)

        Task { @MainActor in
            let outcome = await boundary.checkInvites()
            // Late-success guard: a result that returns after the soft timeout
            // escalated (or after a newer run began) carries a stale generation and
            // is dropped — it must NOT override the escape state the user is now in.
            guard generation == runGeneration else { return }
            cancelTimeout()
            handle(outcome)
        }
    }

    /// Arm the soft-timeout backstop for `generation`. If the run hasn't resolved by
    /// `softTimeout`, escalate to `.failed` so the user gets CHECK AGAIN + ENTER CODE
    /// INSTEAD + SIGN OUT. The pure `InviteCheckTimeoutPolicy` owns the should-escape
    /// decision so it is unit-testable without a timer; the in-flight boundary, if it
    /// later returns, is ignored by the generation guard.
    private func armTimeout(for generation: Int) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.softTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard InviteCheckTimeoutPolicy.shouldEscape(
                timedOutGeneration: generation,
                currentGeneration: runGeneration,
                phase: phase
            ) else { return }
            escalateToFailed()
        }
    }

    /// Cancel the armed soft timeout (a real outcome arrived, a retry started, or the
    /// screen disappeared).
    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// Route an invite-check outcome. The two navigating cases (`hasInvites` /
    /// `noInvites`) are delegated to the pure `InviteCheckRouter` so the routing is
    /// unit-testable; the failure case flips local phase + fires the diagnostic.
    private func handle(_ outcome: InviteCheckOutcome) {
        InviteCheckRouter.route(
            outcome,
            onHasInvites: { invites in
                onInvitesFetched(invites)
                onHasInvites()
            },
            onNoInvites: {
                onNoInvites()
            },
            onFailed: {
                InviteCheckDiagnostics.recordFailure()
                escalateToFailed()
            }
        )
    }

    /// Flip to the visible `.failed` state (the shared sink for an explicit boundary
    /// failure AND a soft timeout), honoring Reduce Motion.
    private func escalateToFailed() {
        if reduceMotion {
            phase = .failed
        } else {
            withAnimation(OPSStyle.Animation.panel) { phase = .failed }
        }
    }
}

// MARK: - Soft-timeout policy (pure — the should-escape decision)

/// The decision for whether a soft-timeout firing should escalate the screen to the
/// actionable `.failed` state. Extracted from the view so the never-trap rule is
/// unit-testable without a timer or a render. Escape ONLY when the timeout belongs to
/// the CURRENT run (no newer `runCheck` superseded it) AND the screen is still
/// `.checking` (the boundary hasn't already routed away or failed). This is the seam
/// that guarantees a stale timeout can't disturb a run that already resolved.
enum InviteCheckTimeoutPolicy {
    static func shouldEscape(
        timedOutGeneration: Int,
        currentGeneration: Int,
        phase: InviteCheckStepView.Phase
    ) -> Bool {
        timedOutGeneration == currentGeneration && phase == .checking
    }
}

// MARK: - Pure outcome routing (no SwiftUI, fully unit-testable)

/// Routes an `InviteCheckOutcome` to exactly one of three effects. Extracted from
/// the view so the R13 "failure is NOT a zero" contract is testable without
/// rendering. `.found` with a non-empty list → `onHasInvites(invites)`; `.found`
/// with an empty list → `onNoInvites`; `.failed` → `onFailed` (the VISIBLE error).
enum InviteCheckRouter {
    static func route(
        _ outcome: InviteCheckOutcome,
        onHasInvites: ([PendingInviteDTO]) -> Void,
        onNoInvites: () -> Void,
        onFailed: () -> Void
    ) {
        switch outcome {
        case .found(let invites):
            if invites.isEmpty {
                onNoInvites()
            } else {
                onHasInvites(invites)
            }
        case .failed:
            onFailed()
        }
    }
}

// MARK: - Diagnostics

/// Fires the `onboarding_invite_check_failed` event so an R13 failure is
/// observable in analytics (not just a silent local error state). Isolated so the
/// view stays free of the analytics singleton and the call is testable as a unit.
enum InviteCheckDiagnostics {
    static func recordFailure() {
        // Hop to the main actor — `AnalyticsService.track` is @MainActor and this
        // is called from the screen's failure handling, which may be nonisolated.
        // The event is fire-and-forget, so the next-runloop hop is immaterial.
        Task { @MainActor in
            AnalyticsService.shared.track(
                eventType: .error,
                eventName: "onboarding_invite_check_failed"
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
/// A preview/stub boundary — no network. Returns a fixed outcome.
private struct PreviewInviteCheckBoundary: InviteCheckBoundary {
    var outcome: InviteCheckOutcome = .found([])
    func checkInvites() async -> InviteCheckOutcome { outcome }
}

#Preview("InviteCheckStepView — checking") {
    InviteCheckStepView(
        boundary: PreviewInviteCheckBoundary(),
        previewPhase: .checking
    )
    .preferredColorScheme(.dark)
}

#Preview("InviteCheckStepView — failed") {
    InviteCheckStepView(
        boundary: PreviewInviteCheckBoundary(),
        previewPhase: .failed
    )
    .preferredColorScheme(.dark)
}
#endif
