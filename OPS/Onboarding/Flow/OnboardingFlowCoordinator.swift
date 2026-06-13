//
//  OnboardingFlowCoordinator.swift
//  OPS
//
//  Onboarding rebuild Task 2.3a (§4.1, §5.2, §5.3) — the runtime driver of the
//  rebuilt onboarding flow. An ObservableObject that owns the current step and
//  the collected form data, persisting both on every change so a kill at any
//  point resumes. No UI, no ContentView coupling: every dependency the
//  coordinator needs is injected, so it has no reach into live singletons and
//  is fully unit-testable.
//
//  This code is DEAD until a later phase flips a feature flag — it cannot
//  affect the live app.
//
//  Placement authority (§5.3): the server-observable state is the authority for
//  WHERE a returning user lands; the persisted local step is purely an
//  optimisation that lets a same-session/same-device resume skip a re-walk and
//  re-derivation. `start()` therefore prefers a usable saved step, then falls
//  back to server-derived resume, then to `.welcome`.
//

import Foundation

@MainActor
final class OnboardingFlowCoordinator: ObservableObject {

    // MARK: - Published state

    /// Where the flow currently sits. The view layer renders off this.
    @Published private(set) var currentStep: OnboardingFlowStep

    /// Everything the flow has collected so far. Screens mutate it via
    /// `update(_:)`; it is persisted alongside the step on every change.
    @Published private(set) var formData: OnboardingFormData

    // MARK: - Injected dependencies

    /// Persistence boundary (isolated UserDefaults suite in tests).
    private let store: OnboardingFlowStateStore

    /// Live auth state. Read on every back-navigation decision so the same step
    /// backs differently pre- vs post-auth — never snapshotted at init.
    private let isAuthenticated: () -> Bool

    /// Server-observable onboarding facts, used to derive the resume step for an
    /// authenticated-but-incomplete user who has no usable saved step. Returns
    /// `nil` when the facts are not yet available (e.g. offline before the first
    /// fetch), in which case the flow falls back to `.welcome`.
    private let serverStateProvider: () -> OnboardingServerState?

    // MARK: - Init

    init(
        store: OnboardingFlowStateStore,
        isAuthenticated: @escaping () -> Bool,
        serverStateProvider: @escaping () -> OnboardingServerState?
    ) {
        self.store = store
        self.isAuthenticated = isAuthenticated
        self.serverStateProvider = serverStateProvider
        // Provisional placement; `start()` resolves the real entry point. A
        // sensible default keeps `currentStep` non-optional and safe to render
        // even if a caller observes before calling `start()`.
        self.currentStep = .welcome
        self.formData = OnboardingFormData()
    }

    // MARK: - Lifecycle

    /// Resolve the flow's entry point. Call once when the gateway appears.
    ///
    /// Order (§5.3):
    /// 1. Run the one-shot v3→v4 migration (no-op if already migrated).
    /// 2. Load any saved state. If it carries a non-nil step, restore the step
    ///    AND the form data verbatim — the same-session/same-device resume
    ///    optimisation, which beats server derivation.
    /// 3. Otherwise restore whatever form data the saved blob holds (a nil-step
    ///    blob still carries collected fields), then place the step:
    ///    - not authenticated → `.welcome`.
    ///    - authenticated → server-derived resume if facts are available, else
    ///      `.welcome`.
    /// 4. Persist the resolved state so a kill resumes.
    func start() {
        store.migrateV3IfNeeded()

        let saved = store.load()

        // Restore collected form data first — it is valid regardless of whether
        // the blob carries a step.
        if let saved { formData = saved.data }

        if let savedStep = saved?.step {
            // Same-session resume: trust the persisted position.
            currentStep = savedStep
        } else if !isAuthenticated() {
            currentStep = .welcome
        } else if let serverState = serverStateProvider() {
            currentStep = OnboardingResume.derive(serverState)
        } else {
            currentStep = .welcome
        }

        persist()
    }

    // MARK: - Navigation

    /// Move to an explicit step and persist.
    func advance(to step: OnboardingFlowStep) {
        currentStep = step
        persist()
    }

    /// Whether the current step has a back-edge in the live auth context.
    var canGoBack: Bool {
        currentStep.backEdge(context: currentContext) != nil
    }

    /// Follow the current step's back-edge if one exists; otherwise a no-op. The
    /// header only renders Back when an edge exists, so the no-op branch is a
    /// safety net, never a user-reachable dead press.
    func goBack() {
        guard let previous = currentStep.backEdge(context: currentContext) else { return }
        currentStep = previous
        persist()
    }

    // MARK: - Form data

    /// Mutate the collected form data in place and persist. A single flexible
    /// setter so screens don't need a per-field method on the coordinator.
    func update(_ mutate: (inout OnboardingFormData) -> Void) {
        mutate(&formData)
        persist()
    }

    // MARK: - Exit / completion

    /// Reset to a clean pre-auth slate and drop the persisted blob. Used when
    /// the SIGN OUT escape is taken — the gateway triggers the real auth
    /// sign-out separately.
    func signOut() {
        reset()
    }

    /// Clear persisted state and return to `.welcome` with empty form data.
    func reset() {
        store.clear()
        formData = OnboardingFormData()
        currentStep = .welcome
    }

    /// Onboarding finished — drop the local optimisation blob. The actual
    /// completion ACK lives elsewhere (P4); this stays deliberately minimal.
    func complete() {
        store.clear()
    }

    // MARK: - Internals

    /// The back-map context for the CURRENT auth state, read live on every
    /// query so a mid-flow auth transition is reflected immediately.
    private var currentContext: OnboardingFlowStep.BackContext {
        isAuthenticated() ? .postAuth : .preAuth
    }

    /// Persist the current in-memory state so a kill at any point resumes.
    private func persist() {
        store.save(OnboardingFlowState(step: currentStep, data: formData))
    }
}
