//
//  OnboardingGateway.swift
//  OPS
//
//  Onboarding rebuild P2 — the SwiftUI shell that hosts the rebuilt onboarding
//  flow. It owns a single `OnboardingFlowCoordinator`, maps the live user into
//  the server-state the coordinator derives resume placement from, renders the
//  screen for the current step, and performs the host-level side effects
//  (completion → enter the app, sign-out → real auth signout).
//
//  This is now the LIVE onboarding shell: the cutover landed
//  (`FeatureFlags.useRebuiltOnboarding` defaults true and ContentView routes
//  here), so every step renders its real, design-system-final screen — there
//  are no remaining placeholder stubs. The feature flag is retained only as a
//  revert switch back to the legacy flow.
//

import SwiftUI

struct OnboardingGateway: View {

    @EnvironmentObject private var dataController: DataController

    /// One coordinator for the lifetime of the gateway. Constructed with a fresh
    /// store (live `.standard` UserDefaults), a live auth-state closure, and a
    /// server-state provider that maps the current user into the facts
    /// `OnboardingResume` derives placement from. Dependencies are injected so
    /// the coordinator stays free of singleton reach and unit-testable.
    @StateObject private var coordinator: OnboardingFlowCoordinator

    /// Returning-login preload-gate hooks (bug 95bf7c82). ContentView's rebuilt
    /// branch passes the SAME closures the legacy LandingView/LoginView branch
    /// passes (`pendingReturningLogin = true` / `disarmWorkspacePreload()`); the
    /// gateway forwards them into the `LoginLiveBoundary` so the WorkspacePreloadGate
    /// covers a returning login's initial sync in this branch too. Optional +
    /// nil-default so any other call site (and the flag-off path) is unaffected.
    private let onLoginInitiated: (() -> Void)?
    private let onLoginAbandoned: (() -> Void)?

    init(
        onLoginInitiated: (() -> Void)? = nil,
        onLoginAbandoned: (() -> Void)? = nil
    ) {
        self.onLoginInitiated = onLoginInitiated
        self.onLoginAbandoned = onLoginAbandoned

        // `dataController` is not yet available here (environment objects are
        // injected after init), so the closures capture it lazily. They run only
        // after the view is in the hierarchy — `start()` is called from
        // `.onAppear`, never from init — so the environment object is present by
        // the time either closure is first invoked.
        //
        // The capture is resolved at call time via a holder the body wires up in
        // `.onAppear` (see `bind`), avoiding capturing `self` (a struct) or an
        // un-injected environment object inside the init.
        let holder = DataControllerHolder()
        _coordinator = StateObject(wrappedValue: OnboardingFlowCoordinator(
            store: OnboardingFlowStateStore(),
            isAuthenticated: { holder.controller?.isAuthenticated ?? false },
            serverStateProvider: {
                guard let user = holder.controller?.currentUser else { return nil }
                return Self.serverState(for: user)
            }
        ))
        _holder = StateObject(wrappedValue: holder)
    }

    /// Bridges the environment-injected `dataController` into the closures the
    /// coordinator captured at init. Set once in `.onAppear`, before `start()`.
    @StateObject private var holder: DataControllerHolder

    /// The hardened `OnboardingManager` — the live auth/data boundary the
    /// rebuilt screens drive (createAccount, handleSocialAuth, joinCompany,
    /// createCompanyViaRPC). Constructed lazily on first appear from the
    /// environment-injected `dataController` (not available at `init`), and held
    /// for the gateway's lifetime so flow state (selected flow, collected names)
    /// survives across step renders. S3 talks to it ONLY through the
    /// `CreateAccountLiveBoundary` adapter, keeping the screen testable.
    @State private var onboardingManager: OnboardingManager?

    /// The pending invitations S4c fetched, handed to the invite picker WITHOUT a
    /// re-fetch (the picker advance happens within this gateway's lifetime). Held in
    /// gateway state — NOT persisted into the form-data blob (the full DTOs are too
    /// large; the picked invite's compact company fields are what gets persisted on
    /// selection). A same-session resume directly onto `.invitePicker` (rare) finds
    /// this empty and the picker shows its empty state, harmlessly; the normal flow
    /// always arrives via S4c which fills it.
    @State private var fetchedInvites: [PendingInviteDTO] = []

    /// Funnel instrumentation (P6, spec §8). Held for the gateway's lifetime so the
    /// once-per-entry `step_viewed` guard, the viewed-step count, and the flow
    /// start instant persist across re-renders. The coordinator stays
    /// analytics-free (it is dependency-injected and unit-tested) — the gateway is
    /// the firing surface: it OBSERVES `coordinator.currentStep` and translates the
    /// tracker's pure event output into `AnalyticsService.shared.track`. All of the
    /// funnel decisions (step id, path, dedupe) live in `OnboardingFunnelTracker`,
    /// which is unit-tested directly. See `OnboardingFunnelAnalytics.swift`.
    @State private var funnel = OnboardingFunnelTracker()

    var body: some View {
        currentStepView
            .onAppear {
                // Wire the live controller into the coordinator's closures BEFORE
                // resolving the entry point, then start (idempotent).
                holder.controller = dataController
                if onboardingManager == nil {
                    onboardingManager = OnboardingManager(dataController: dataController)
                }
                coordinator.start()
                // First funnel touch — fire `step_viewed` for the resolved entry
                // step. The tracker's once-per-entry guard makes the immediately
                // following `onChange` (which fires for the same initial step) a
                // no-op, so this never double-fires.
                recordStepViewed()
            }
            // Funnel: fire `step_viewed` on every genuine step transition. The
            // tracker dedupes by the step's stable `analyticsId`, so a re-render
            // for an unchanged step, or a parameter-only change on `.codeEntry` /
            // `.confirmCompany`, does not re-fire.
            .onChange(of: coordinator.currentStep) { _, _ in
                recordStepViewed()
            }
    }

    // MARK: - Funnel instrumentation (gateway-observed)

    /// The current funnel path, derived from the role the user picked on S2.
    private var funnelPath: OnboardingFunnelPath {
        OnboardingFunnelPath.from(role: coordinator.formData.selectedRole)
    }

    /// Record an entry to the coordinator's current step and fire
    /// `onboarding_step_viewed` if the tracker says it's a genuine new entry. The
    /// dedupe lives in the tracker; this is the thin firing surface.
    private func recordStepViewed() {
        if let event = funnel.recordStepEntry(step: coordinator.currentStep, path: funnelPath) {
            fire(event)
        }
    }

    /// Fire one funnel event through `AnalyticsService`. The view body runs on the
    /// main actor and `AnalyticsService.track` is `@MainActor`, so this is a direct
    /// call — no hop needed (unlike the screen-local diagnostics fired from
    /// possibly-nonisolated contexts).
    private func fire(_ event: OnboardingFunnelEvent) {
        AnalyticsService.shared.track(
            eventType: event.type,
            eventName: event.name,
            properties: event.properties.mapValues { $0.analyticsValue },
            durationMs: event.durationMs
        )
    }

    /// Renders the real screen for the current step. P3 lights up the first two
    /// screens — `.welcome` (S1) and `.rolePick` (S2) — with their design-system
    /// -final views; every other step still renders the `OnboardingPlaceholderStep`
    /// scaffolding until its real screen lands in P3–P5. The flag-gated seam and
    /// the placeholder's CONTINUE/BACK/SIGN OUT contract are untouched for those
    /// steps.
    @ViewBuilder
    private var currentStepView: some View {
        switch coordinator.currentStep {
        case .welcome:
            WelcomeStepView(
                onGetStarted: { coordinator.advance(to: .rolePick) },
                onSignIn: { coordinator.advance(to: .login) }
            )

        case .rolePick:
            RolePickStepView(
                onSelectOwner: {
                    coordinator.update { $0.selectedRole = .owner }
                    coordinator.advance(to: .createAccount)
                },
                onSelectCrew: {
                    coordinator.update { $0.selectedRole = .crew }
                    coordinator.advance(to: .createAccount)
                },
                canGoBack: coordinator.canGoBack,
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )

        case .createAccount:
            createAccountView

        case .login:
            loginView

        case .companyName:
            companyNameView

        case .crewCode:
            crewCodeView

        case .inviteCheck:
            inviteCheckView

        case .invitePicker:
            invitePickerView

        case .codeEntry(let provenance):
            codeEntryView(provenance: provenance)

        case .confirmCompany(let source):
            confirmCompanyView(source: source)

        case .profile:
            profileView

        case .emergencyContact:
            emergencyContactView

        case .completionGate:
            completionGateView

        default:
            OnboardingPlaceholderStep(
                step: coordinator.currentStep,
                canGoBack: coordinator.canGoBack,
                onContinue: { handleContinue() },
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )
        }
    }

    // MARK: - S3 (Create account)

    /// The real S3 screen, wired to the live signup boundary. The manager is
    /// constructed on first appear; until it exists (a transient first-frame
    /// race that the `.onAppear` resolves immediately) the placeholder renders so
    /// the view is never empty.
    @ViewBuilder
    private var createAccountView: some View {
        if let manager = onboardingManager {
            CreateAccountStepView(
                selectedRole: coordinator.formData.selectedRole,
                boundary: CreateAccountLiveBoundary(
                    manager: manager,
                    dataController: dataController,
                    selectedRole: coordinator.formData.selectedRole,
                    resumeStepForCurrentUser: {
                        guard let user = dataController.currentUser else { return nil }
                        return OnboardingResume.derive(Self.serverState(for: user))
                    }
                ),
                onUpdateFormData: { mutate in coordinator.update(mutate) },
                onCreated: {
                    // New account — advance to the role-appropriate next step.
                    coordinator.advance(to: Self.createAccountNextStep(role: coordinator.formData.selectedRole))
                },
                onExistingComplete: {
                    // Existing + complete account → admit to the app.
                    handleComplete()
                },
                onExistingIncomplete: { resumeStep in
                    // Existing + incomplete → resume at the derived step.
                    coordinator.advance(to: resumeStep)
                },
                onSignIn: {
                    // Email already registered → Login (email already persisted
                    // into formData by the screen for prefill).
                    coordinator.advance(to: .login)
                },
                onBack: { coordinator.goBack() }
            )
        } else {
            OnboardingPlaceholderStep(
                step: .createAccount,
                canGoBack: coordinator.canGoBack,
                onContinue: {},
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )
        }
    }

    // MARK: - S4 (Login)

    /// The real S4 (Login) screen, wired to the live login boundary. Like S3 the
    /// manager is constructed on first appear; until it exists (a transient
    /// first-frame race the `.onAppear` resolves immediately) the placeholder
    /// renders so the view is never empty.
    ///
    /// Outcome wiring (mirrors S3's structure, login's semantics):
    ///   • onComplete         → host admit path (`handleComplete`).
    ///   • onIncomplete       → resume at the derived step.
    ///   • onNewIdentity      → brand-new social identity → `.rolePick`.
    ///   • onBack             → `coordinator.goBack()` (back-edge is `.welcome`).
    ///   • prefilledEmail     → the email persisted on the SIGN IN handoff from S3.
    @ViewBuilder
    private var loginView: some View {
        if let manager = onboardingManager {
            LoginStepView(
                boundary: LoginLiveBoundary(
                    dataController: dataController,
                    manager: manager,
                    resumeStepForCurrentUser: {
                        guard let user = dataController.currentUser else { return nil }
                        return OnboardingResume.derive(Self.serverState(for: user))
                    },
                    // Preload-gate parity: forward the host hooks (no-ops when the
                    // call site didn't supply them, e.g. previews).
                    onLoginInitiated: { onLoginInitiated?() },
                    onLoginAbandoned: { onLoginAbandoned?() }
                ),
                onUpdateFormData: { mutate in coordinator.update(mutate) },
                onComplete: {
                    // Returning + complete account → admit to the app.
                    handleComplete()
                },
                onIncomplete: { resumeStep in
                    // Existing + incomplete → resume at the derived step.
                    coordinator.advance(to: resumeStep)
                },
                onNewIdentity: {
                    // Brand-new SOCIAL identity (auth satisfied) → into the flow at role pick.
                    coordinator.advance(to: .rolePick)
                },
                onBack: { coordinator.goBack() },
                prefilledEmail: coordinator.formData.email
            )
        } else {
            OnboardingPlaceholderStep(
                step: .login,
                canGoBack: coordinator.canGoBack,
                onContinue: {},
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )
        }
    }

    // MARK: - S4o (Company name — the company-creation commit point)

    /// The real S4o screen, wired to the live company-creation boundary over the
    /// `OnboardingManager`. Like S3 the manager is constructed on first appear;
    /// until it exists (a transient first-frame race the `.onAppear` resolves
    /// immediately) the placeholder renders so the view is never empty.
    ///
    /// On success the boundary returns the DB-truth crew code; the screen persists
    /// it into `formData.generatedCrewCode` and advances to `.crewCode` (which then
    /// renders that code).
    @ViewBuilder
    private var companyNameView: some View {
        if let manager = onboardingManager {
            CompanyNameStepView(
                boundary: CompanyCreationLiveBoundary(manager: manager),
                onUpdateFormData: { mutate in coordinator.update(mutate) },
                onCreated: { code in
                    // Persist the DB-truth crew code, then advance to the payoff.
                    coordinator.update { $0.generatedCrewCode = code }
                    coordinator.advance(to: .crewCode)
                },
                onBack: { coordinator.goBack() }
            )
        } else {
            OnboardingPlaceholderStep(
                step: .companyName,
                canGoBack: coordinator.canGoBack,
                onContinue: {},
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )
        }
    }

    // MARK: - S5o (Crew code — the payoff)

    /// The real S5o screen. Reads the DB-truth code + company name straight off the
    /// coordinator's form data (persisted by S4o on success). Forward-only — ENTER
    /// OPS advances to the completion gate (still a placeholder until 4.3, which is
    /// fine — it renders the placeholder for now).
    private var crewCodeView: some View {
        CrewCodeStepView(
            crewCode: coordinator.formData.generatedCrewCode ?? "",
            companyName: coordinator.formData.companyName ?? "",
            onEnter: { coordinator.advance(to: .completionGate) }
        )
    }

    // MARK: - S4c (Invite check — the crew-path auto transition)

    /// The real S4c screen, wired to the live invite-check boundary built from the
    /// gateway's email (form data, falling back to the live user). The screen
    /// auto-runs the check on appear and routes: 1+ invites → invite picker (holding
    /// the fetched invites in gateway state so the picker doesn't re-fetch), 0 →
    /// code entry (`provenance: .zeroInvites`), failure → the visible retry state.
    ///
    /// No manager dependency (the boundary calls the repository directly), so unlike
    /// the boundary-over-manager screens there is no first-frame placeholder race.
    private var inviteCheckView: some View {
        InviteCheckStepView(
            boundary: InviteCheckLiveBoundary(
                email: coordinator.formData.email ?? dataController.currentUser?.email
            ),
            onInvitesFetched: { invites in
                fetchedInvites = invites
            },
            onHasInvites: { coordinator.advance(to: .invitePicker) },
            onNoInvites: { coordinator.advance(to: .codeEntry(provenance: .zeroInvites)) },
            onEnterCodeInstead: { coordinator.advance(to: .codeEntry(provenance: .zeroInvites)) },
            onSignOut: { handleSignOut() }
        )
    }

    // MARK: - Invite picker (crew-path — pick your crew from pending invites)

    /// The real invite-picker screen. Reads the invites S4c fetched into gateway
    /// state. Selecting a card persists the chosen invite's company (id / name /
    /// code / logo) + the invitation id into form data and advances to
    /// `.confirmCompany(source: .picker)`. "Enter a different code" advances to
    /// `.codeEntry(provenance: .fromPicker)`. Back → role pick.
    ///
    /// SELF-HEAL (kill+resume) — `fetchedInvites` lives in gateway `@State`, NOT in
    /// the persisted v4 blob (the full DTOs are too large to persist). A kill+resume
    /// that restores a saved step of `.invitePicker` therefore arrives with an EMPTY
    /// invite list → the picker would render "Pick your crew" with zero cards. Rather
    /// than show that dead end, re-route to `.inviteCheck` on appear so the auto-check
    /// re-fetches and re-routes correctly (invites → picker WITH cards; none →
    /// codeEntry; failure → the visible retry). The normal flow always arrives via
    /// S4c which fills `fetchedInvites` first, so this only fires on a resume — no
    /// loop: `.inviteCheck` only sends a NON-empty list back here (an empty re-fetch
    /// goes to codeEntry), so a second empty render can't occur.
    private var invitePickerView: some View {
        InvitePickerStepView(
            invites: fetchedInvites,
            onSelectInvite: { invite in
                coordinator.update {
                    $0.joinCompanyId = invite.companyId
                    $0.joinCompanyName = invite.companyName
                    $0.joinCompanyCode = invite.companyCode
                    $0.joinCompanyLogoUrl = invite.companyLogoUrl
                    $0.joinInvitationId = invite.invitationId
                }
                coordinator.advance(to: .confirmCompany(source: .picker))
            },
            onEnterDifferentCode: { coordinator.advance(to: .codeEntry(provenance: .fromPicker)) },
            onBack: { coordinator.goBack() }
        )
        .onAppear {
            if InvitePickerResumeHealer.shouldReRunInviteCheck(
                step: coordinator.currentStep,
                fetchedInvites: fetchedInvites
            ) {
                coordinator.advance(to: .inviteCheck)
            }
        }
    }

    // MARK: - S4c-code (Crew code entry)

    /// The real S4c-code screen, wired to the live code-entry boundary over the
    /// `OnboardingManager`. The provenance the screen was entered with is carried
    /// into the confirm advance so the confirm-company back-edge returns to the
    /// right origin. On `.found` the screen persists the company into form data and
    /// advances to `.confirmCompany(source: .codeEntry(provenance))`. Like the other
    /// boundary-over-manager screens the manager is constructed on first appear;
    /// until it exists (a transient first-frame race the `.onAppear` resolves) the
    /// placeholder renders so the view is never empty.
    @ViewBuilder
    private func codeEntryView(provenance: CodeEntryProvenance) -> some View {
        if let manager = onboardingManager {
            CodeEntryStepView(
                provenance: provenance,
                boundary: CodeEntryLiveBoundary(manager: manager),
                onUpdateFormData: { mutate in coordinator.update(mutate) },
                onFound: { _ in
                    // The screen already persisted the resolved company into form
                    // data; advance to confirm, carrying the provenance so the
                    // confirm back-edge returns to the right origin.
                    coordinator.advance(to: .confirmCompany(source: .codeEntry(provenance)))
                },
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )
        } else {
            OnboardingPlaceholderStep(
                step: .codeEntry(provenance: provenance),
                canGoBack: coordinator.canGoBack,
                onContinue: {},
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )
        }
    }

    // MARK: - S5c (Confirm company — the crew JOIN commit point)

    /// The real S5c screen, wired to the live confirm-company boundary over the
    /// `OnboardingManager`. Reads the company identity the picker / code-entry screen
    /// persisted into form data (`joinCompany*` + `joinInvitationId`) — the screen
    /// renders that immediately and the boundary best-effort enriches it with the team
    /// preview (`fetchCompanyJoinDetails`). On the live JOIN
    /// (`joinCompanyFromOnboarding`) success the gateway advances to `.profile`;
    /// failure surfaces inline on the screen with no nav. Back follows the back map for
    /// the source (`.picker` → invite picker; `.codeEntry(prov)` → code entry), so the
    /// back label is resolved from the source. Like the other boundary-over-manager
    /// screens the manager is constructed on first appear; until it exists (a transient
    /// first-frame race the `.onAppear` resolves immediately) the placeholder renders so
    /// the view is never empty.
    @ViewBuilder
    private func confirmCompanyView(source: ConfirmSource) -> some View {
        if let manager = onboardingManager {
            ConfirmCompanyStepView(
                boundary: ConfirmCompanyLiveBoundary(
                    manager: manager,
                    companyId: coordinator.formData.joinCompanyId ?? "",
                    invitationId: coordinator.formData.joinInvitationId,
                    companyCode: coordinator.formData.joinCompanyCode
                ),
                companyName: coordinator.formData.joinCompanyName ?? "",
                companyLogoUrl: coordinator.formData.joinCompanyLogoUrl,
                backLabel: Self.confirmCompanyBackLabel(source: source),
                onJoined: {
                    // Crew JOIN committed — advance to profile (the crew-path
                    // post-join screen). The screen already fired the success haptic.
                    coordinator.advance(to: .profile)
                },
                onBack: { coordinator.goBack() }
            )
        } else {
            OnboardingPlaceholderStep(
                step: .confirmCompany(source: source),
                canGoBack: coordinator.canGoBack,
                onContinue: {},
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )
        }
    }

    /// The previous-screen short name for S5c's Back control — depends on the source
    /// (matches the back map: `.picker` → invite picker; `.codeEntry(prov)` → code
    /// entry). The screen stays ignorant of the source; the gateway resolves the label.
    static func confirmCompanyBackLabel(source: ConfirmSource) -> String {
        switch source {
        case .picker:    return "Invites"
        case .codeEntry: return "Code"
        }
    }

    // MARK: - S6c (Profile — crew post-join)

    /// The real S6c screen, wired to the live profile boundary over the
    /// `OnboardingManager`. The name/phone fields prefill from the form data the
    /// account/confirm screens persisted (editable). The avatar uploads through the
    /// boundary's THROWING path so a failure surfaces a retry-able error (R7 — never
    /// silent). On CONTINUE the name/phone save commits and the gateway advances to
    /// `.emergencyContact`. There is no Back (the join is committed —
    /// `profile.backEdge=nil`); SIGN OUT is the escape. Like the other boundary-over-
    /// manager screens the manager is constructed on first appear; until it exists (a
    /// transient first-frame race the `.onAppear` resolves immediately) the placeholder
    /// renders so the view is never empty.
    @ViewBuilder
    private var profileView: some View {
        if let manager = onboardingManager {
            ProfileStepView(
                boundary: ProfileLiveBoundary(manager: manager),
                prefillFirstName: coordinator.formData.firstName,
                prefillLastName: coordinator.formData.lastName,
                prefillPhone: coordinator.formData.phone,
                onUpdateFormData: { mutate in coordinator.update(mutate) },
                onContinue: {
                    // Profile saved — advance to the (optional) emergency-contact step.
                    coordinator.advance(to: .emergencyContact)
                },
                onSignOut: { handleSignOut() }
            )
        } else {
            OnboardingPlaceholderStep(
                step: .profile,
                canGoBack: coordinator.canGoBack,
                onContinue: {},
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )
        }
    }

    // MARK: - S7c (Emergency contact — crew, optional + skippable)

    /// The real S7c screen, wired to the live emergency-contact boundary over the
    /// `OnboardingManager`. Truly optional: SKIP advances to `.completionGate` WITHOUT
    /// saving; FINISH saves the emergency fields (carrying the profile identity S6c
    /// committed) and then advances to `.completionGate`. Back returns to `.profile`
    /// (`emergencyContact.backEdge=profile`). Like the other boundary-over-manager
    /// screens the manager is constructed on first appear; until it exists (a transient
    /// first-frame race the `.onAppear` resolves immediately) the placeholder renders so
    /// the view is never empty.
    @ViewBuilder
    private var emergencyContactView: some View {
        if let manager = onboardingManager {
            EmergencyContactStepView(
                boundary: EmergencyContactLiveBoundary(manager: manager),
                onUpdateFormData: { mutate in coordinator.update(mutate) },
                onFinish: {
                    // Emergency contact saved — both crew paths terminate at the gate.
                    coordinator.advance(to: .completionGate)
                },
                onSkip: {
                    // Truly optional — advance to the gate WITHOUT saving.
                    coordinator.advance(to: .completionGate)
                },
                onBack: { coordinator.goBack() }
            )
        } else {
            OnboardingPlaceholderStep(
                step: .emergencyContact,
                canGoBack: coordinator.canGoBack,
                onContinue: {},
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )
        }
    }

    // MARK: - Completion gate (the terminal screen — both paths end here)

    /// The real completion gate (Task 4.3). BOTH paths terminate here — owner
    /// (crewCode → completionGate) and crew (emergencyContact → completionGate, the
    /// crew screens land in P5). On appear it ACKs completion through the live
    /// `CompletionLiveBoundary` (which wraps `OnboardingManager.markOnboarding
    /// CompleteOrQueue`) and admits via the host's `handleComplete`. Like the other
    /// boundary-backed screens the manager is constructed on first appear; until it
    /// exists (a transient first-frame race the `.onAppear` resolves immediately)
    /// the placeholder renders so the view is never empty.
    @ViewBuilder
    private var completionGateView: some View {
        if let manager = onboardingManager {
            CompletionGateView(
                boundary: CompletionLiveBoundary(manager: manager),
                onAdmit: { handleComplete() }
            )
        } else {
            OnboardingPlaceholderStep(
                step: .completionGate,
                canGoBack: coordinator.canGoBack,
                onContinue: { handleComplete() },
                onBack: { coordinator.goBack() },
                onSignOut: { handleSignOut() }
            )
        }
    }

    /// The step a NEW account advances to off S3 (spec §4.2 S3):
    ///   owner → companyName, crew (and unknown) → inviteCheck.
    static func createAccountNextStep(role: OnboardingFlowRole?) -> OnboardingFlowStep {
        role == .owner ? .companyName : .inviteCheck
    }

    // MARK: - Host-level side effects

    /// Advance off the current step. P2 scaffolding: this walks the linear
    /// forward path so the flow is traversable in a debug build. The completion
    /// step is terminal — CONTINUE there finishes onboarding (host action below)
    /// rather than advancing to another step. The real per-step forward logic
    /// (branching on role, invite results, etc.) lands with the real screens in
    /// P3–P5.
    private func handleContinue() {
        if coordinator.currentStep == .completionGate {
            handleComplete()
            return
        }
        if let next = Self.placeholderNextStep(after: coordinator.currentStep) {
            coordinator.advance(to: next)
        }
    }

    /// Onboarding finished — admit the user into the authenticated app. Drop the
    /// coordinator's local optimisation blob and flip `isAuthenticated` so the app
    /// routes to PINGatedView.
    ///
    /// The server `onboarding_completed.ios` ACK + the completion-pending sweep now
    /// run inside `CompletionGateView` (Task 4.3) via `CompletionLiveBoundary`
    /// before this host admit fires — so by the time `handleComplete` runs,
    /// completion is already ACKed (or queued for the SyncEngine retry). This host
    /// step is therefore the pure admit: it only flips local auth state. It is the
    /// admit closure the gate injects (`onAdmit`), and is also the admit path for
    /// the existing-account branches on S3/S4. Guarded so it only admits when a
    /// user actually exists; a stub-walked flow with no signed-in user simply
    /// resets without falsely entering the app.
    private func handleComplete() {
        // Funnel: fire `onboarding_completed` BEFORE `coordinator.complete()`
        // wipes the form data — the path is derived from `selectedRole`, and the
        // tracker's step-count / duration are read off its own state (unaffected by
        // the reset), but the path read must precede the reset.
        fire(funnel.completedEvent(path: funnelPath))

        coordinator.complete()
        if dataController.currentUser != nil {
            dataController.isAuthenticated = true
        }
    }

    /// SIGN OUT escape. Triggers the real auth signout (which flips
    /// `isAuthenticated`, clears the user, posts `LogoutInitiated`, and wipes
    /// auth tokens) AND resets the coordinator's local flow state.
    private func handleSignOut() {
        // Funnel: fire `onboarding_abandoned` BEFORE `coordinator.signOut()` resets
        // the step + form data — the event carries the step the user was on and the
        // path they were on when they bailed, both of which the reset would clear.
        fire(funnel.abandonedEvent(lastStep: coordinator.currentStep, path: funnelPath))

        coordinator.signOut()
        dataController.logout()
    }

    // MARK: - Server-state mapping

    /// Maps the live user row into the server-observable facts
    /// `OnboardingResume.derive` keys off. Returns `nil` when there is no current
    /// user (facts unknown) so the coordinator falls back to `.welcome`.
    ///
    /// Field sources (verified against `User` / `DataController`):
    ///   - `hasCompany`        ← `companyId` non-nil & non-blank
    ///   - `role`              ← `role.rawValue` (UserRole; derive is case-insensitive)
    ///   - `userType`          ← `userType?.rawValue` (UserType?)
    ///   - `profileComplete`   ← firstName & lastName & phone all non-blank
    ///   - `webComplete`       ← NOT EXPOSED on the local model — see TODO below.
    private static func serverState(for user: User) -> OnboardingServerState {
        let hasCompany = !(user.companyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let firstOK = !user.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let lastOK = !user.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let phoneOK = !(user.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let profileComplete = firstOK && lastOK && phoneOK

        // TODO(P4): `onboarding_completed.web` is NOT exposed on the local `User`
        // model or the user DTO — the iOS client only tracks the app/iOS ACK
        // (`hasCompletedAppOnboarding`), never the web flag. Surfacing the web
        // flag requires a server/DTO/model change that is out of P2 scope and
        // must not be invented here. Until it lands, `webComplete` is reported
        // `false`. Consequence (per OnboardingResume.derive): a returning user
        // who finished onboarding on WEB but not on iOS is NOT silently
        // auto-completed to the completion gate — they are routed by company +
        // role + profile instead (owner → crewCode, employee → profile/gate).
        // This is the SAFE default: it never skips required local steps. The
        // exact web-driven silent auto-complete is finished in P4 once the flag
        // is available on the model.
        let webComplete = false

        return OnboardingServerState(
            hasCompany: hasCompany,
            role: user.role.rawValue,
            userType: user.userType?.rawValue,
            profileComplete: profileComplete,
            webComplete: webComplete
        )
    }

    // MARK: - P2 placeholder forward path

    /// The next step in the LINEAR scaffolding walk. This is NOT the real flow
    /// graph — it exists only so the P2 stub can advance through every step in a
    /// debug build. Branching steps (rolePick → owner/crew, inviteCheck →
    /// picker/code, etc.) are linearised here; the real branching logic ships
    /// with the real screens in P3–P5.
    private static func placeholderNextStep(after step: OnboardingFlowStep) -> OnboardingFlowStep? {
        switch step {
        case .welcome:           return .rolePick
        case .login:             return .rolePick
        case .rolePick:          return .createAccount
        case .createAccount:     return .companyName
        case .companyName:       return .crewCode
        case .crewCode:          return .completionGate
        case .inviteCheck:       return .invitePicker
        case .invitePicker:      return .codeEntry(provenance: .fromPicker)
        case .codeEntry(let p):  return .confirmCompany(source: .codeEntry(p))
        case .confirmCompany:    return .profile
        case .profile:           return .emergencyContact
        case .emergencyContact:  return .completionGate
        case .completionGate:    return nil // terminal — CONTINUE completes
        }
    }
}

// MARK: - Invite-picker resume self-heal (pure decision)

/// Decides whether the invite picker, on appear, should bounce back to
/// `.inviteCheck` to re-fetch. Extracted from the gateway so the kill+resume
/// self-heal (and its loop guard) is unit-testable without a render.
///
/// Re-run ONLY when BOTH hold:
///   • the coordinator is genuinely on `.invitePicker` (guards against a stale
///     `.onAppear` firing after the coordinator already advanced elsewhere), AND
///   • `fetchedInvites` is empty (the picker has nothing to show — the kill+resume
///     signature, since the normal S4c arrival always fills the list first).
///
/// Loop safety: re-running `.inviteCheck` either re-fetches a NON-empty list (→
/// picker WITH cards, `fetchedInvites` now populated, this returns false) or routes
/// to `.codeEntry` / the failure state — `.inviteCheck` never sends an EMPTY list
/// back to the picker, so the empty-picker render cannot recur.
enum InvitePickerResumeHealer {
    static func shouldReRunInviteCheck(
        step: OnboardingFlowStep,
        fetchedInvites: [PendingInviteDTO]
    ) -> Bool {
        step == .invitePicker && fetchedInvites.isEmpty
    }
}

// MARK: - DataController holder

/// A tiny reference box so `OnboardingGateway.init` can hand the coordinator's
/// closures a forward reference to the environment-injected `dataController`
/// without capturing an un-injected value. The body sets `controller` in
/// `.onAppear` before any closure fires. `ObservableObject` only so it can live
/// in a `@StateObject` and survive view re-creation alongside the coordinator;
/// it publishes nothing.
private final class DataControllerHolder: ObservableObject {
    weak var controller: DataController?
}

// MARK: - P2 placeholder step

/// TEMPORARY P2 scaffolding — NOT a design-system-final screen. A single labeled
/// view that renders the current step's identifier and the navigation
/// affordances available at that step (CONTINUE always; BACK when the coordinator
/// reports a back-edge; SIGN OUT when there is no back-edge, i.e. the step's only
/// escape is signing out). It exists solely to make the flow walkable in a debug
/// build while the real screens are built in P3–P5. Styling uses OPSStyle tokens
/// to avoid hardcoded values, but the layout/copy are placeholders and the §12
/// design gate does NOT apply to this view.
private struct OnboardingPlaceholderStep: View {
    let step: OnboardingFlowStep
    let canGoBack: Bool
    let onContinue: () -> Void
    let onBack: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: OPSStyle.Layout.spacing4) {
                Spacer()

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("// ONBOARDING — P2 SCAFFOLDING")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(stepIdentifier)
                        .font(OPSStyle.Typography.display)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Button(action: onContinue) {
                        Text(step == .completionGate ? "FINISH" : "CONTINUE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(OPSStyle.Colors.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetLarge)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }

                    if canGoBack {
                        Button(action: onBack) {
                            Text("BACK")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: OPSStyle.Layout.touchTargetStandard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                        .stroke(OPSStyle.Colors.secondaryText, lineWidth: 1)
                                )
                        }
                    } else {
                        // No back-edge at this step → SIGN OUT is the escape.
                        Button(action: onSignOut) {
                            Text("SIGN OUT")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: OPSStyle.Layout.touchTargetStandard)
                        }
                    }
                }
            }
            .padding(OPSStyle.Layout.contentPadding)
        }
    }

    /// Human-readable step identifier for the scaffolding label, including
    /// provenance/source for the parameterised steps so the walk is legible.
    private var stepIdentifier: String {
        switch step {
        case .welcome:                  return "WELCOME"
        case .login:                    return "LOGIN"
        case .rolePick:                 return "ROLE PICK"
        case .createAccount:            return "CREATE ACCOUNT"
        case .companyName:              return "COMPANY NAME"
        case .crewCode:                 return "CREW CODE"
        case .inviteCheck:              return "INVITE CHECK"
        case .invitePicker:             return "INVITE PICKER"
        case .codeEntry(let p):         return "CODE ENTRY (\(p.rawValue))"
        case .confirmCompany(let s):    return "CONFIRM COMPANY (\(confirmSourceLabel(s)))"
        case .profile:                  return "PROFILE"
        case .emergencyContact:         return "EMERGENCY CONTACT"
        case .completionGate:           return "COMPLETION GATE"
        }
    }

    private func confirmSourceLabel(_ source: ConfirmSource) -> String {
        switch source {
        case .picker:                   return "picker"
        case .codeEntry(let p):         return "codeEntry/\(p.rawValue)"
        }
    }
}
