//
//  LoginStepView.swift
//  OPS
//
//  Onboarding rebuild P3 — S4 (Login): the RETURNING-USER auth screen and the
//  final P3 screen of the rebuilt flow. This is the screen where an existing
//  user signs back in — it touches LIVE auth, so it is built surgically and the
//  screen itself owns NO auth logic.
//
//  Design spec §4.2 Login. Layout (top → bottom):
//    • Header — Back → welcome (login.backEdge is .welcome), Cake Mono title "LOG IN".
//    • Email form — Email + Password (with show/hide), inline field-level errors,
//      a "Forgot password?" affordance (presents `ForgotPasswordView`, email
//      prefilled).
//    • "OR" hairline divider.
//    • Social auth — Apple + Google (the shared `OnboardingSocialAuthButtons`).
//    • Primary CTA — "Log in" (the one accented control), loading + disabled-until
//      -valid (email + password present).
//
//  COMMIT CONTRACT — exactly the S3 pattern. The screen funnels every data op
//  through an injected `LoginBoundary` whose async methods return a `LoginOutcome`;
//  the gateway wires a live boundary (over `DataController` + `OnboardingManager`),
//  tests inject a stub. The host-navigating outcomes route through the pure
//  `LoginOutcomeRouter` so navigation branching is unit-testable WITHOUT rendering
//  or touching Firebase/network.
//
//  THREE OUTCOMES (mirrors the §4.2 Login spec):
//    1. Returning COMPLETE user → admit to the app (gateway's complete/admit
//       path). The boundary arms the returning-login preload gate when the login
//       starts so the WorkspacePreloadGate covers the initial sync (parity with
//       the legacy LandingView/LoginView `onLoginInitiated`/`onLoginAbandoned`).
//    2. Returning INCOMPLETE user → advance the flow to
//       `OnboardingResume.derive(serverState)` (resume at the derived step).
//    3. SOCIAL sign-in to a BRAND-NEW identity → sync-user runs, then route into
//       the flow at `.rolePick` with auth already satisfied. (Email login to a
//       non-existent account is NOT account creation — inline error, no nav; only
//       SOCIAL providers auto-create.)
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, zero shadows. Accent (`opsAccent`)
//      appears ONLY on the primary CTA (via the shared component).
//    • Built entirely on the Task 3.1 components — `OPSOnboardingField`,
//      `OnboardingStepHeader`, `OnboardingPrimaryCTA`, and the shared
//      `OnboardingSocialAuthButtons`. Nothing re-rolled here.
//    • One easing curve; honored only when Reduce Motion is off. Medium-impact
//      haptic on the commit; success notification reserved for admit.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

// MARK: - Login boundary (the testable seam)

/// What a login attempt resolved to. The screen branches on these; the gateway
/// produces them from the live managers. Distinguishing complete / incomplete /
/// social-new-identity / no-account / failed is the whole point of this enum — it
/// is the contract the gateway's live boundary must honor.
enum LoginOutcome: Equatable {
    /// The credentials resolved to an EXISTING, fully-onboarded account and the
    /// user was (or should be) admitted. The screen hands off to the gateway's
    /// admit-to-app path.
    case complete

    /// The credentials resolved to an existing account that has NOT finished
    /// onboarding. The screen advances to the supplied derived resume step (the
    /// same `OnboardingResume.derive` rule Create-account uses).
    case incomplete(resumeStep: OnboardingFlowStep)

    /// SOCIAL ONLY: auth succeeded against a brand-new identity (no prior account
    /// / onboarding). sync-user has run and the session is authenticated; the
    /// screen routes into the flow at `.rolePick` (auth already satisfied).
    case newIdentity

    /// EMAIL ONLY: no account exists for that email. Email login is NOT account
    /// creation, so the screen surfaces an inline "no account" error and offers no
    /// navigation (the user signs up via the flow, or checks the address).
    case noAccount

    /// The attempt failed (network / server / wrong password). The screen surfaces
    /// `message` inline. A `nil` message = user cancelled a social sheet (no error
    /// shown).
    case failed(message: String?)
}

/// The async boundary Login funnels every data op through. Implemented live by
/// the gateway (over `DataController` + `OnboardingManager`); stubbed in tests.
@MainActor
protocol LoginBoundary {
    /// Email/password sign-in. Returns the resolved outcome.
    func logInEmail(email: String, password: String) async -> LoginOutcome

    /// Apple sign-in. A brand-new identity resolves to `.newIdentity`.
    func logInApple() async -> LoginOutcome

    /// Google sign-in. A brand-new identity resolves to `.newIdentity`.
    func logInGoogle() async -> LoginOutcome
}

// MARK: - Login screen

struct LoginStepView: View {

    /// The async login boundary. Injected so the screen never touches Firebase.
    let boundary: LoginBoundary

    /// Persist a collected field into the coordinator's form data. The gateway
    /// wires this to `coordinator.update`.
    let onUpdateFormData: (@escaping (inout OnboardingFormData) -> Void) -> Void

    /// Returning + COMPLETE account → admit to the app (gateway's handleComplete).
    let onComplete: () -> Void

    /// Returning + INCOMPLETE account → resume at the derived step.
    let onIncomplete: (OnboardingFlowStep) -> Void

    /// Brand-new SOCIAL identity → route into the flow at `.rolePick`.
    let onNewIdentity: () -> Void

    /// Back → welcome. The gateway wires `coordinator.goBack()`.
    let onBack: () -> Void

    /// Email prefill from the SIGN IN handoff (Create-account persisted the typed
    /// email into `coordinator.formData.email`). Applied once on appear.
    let prefilledEmail: String?

    // MARK: Init

    init(
        boundary: LoginBoundary,
        onUpdateFormData: @escaping (@escaping (inout OnboardingFormData) -> Void) -> Void,
        onComplete: @escaping () -> Void,
        onIncomplete: @escaping (OnboardingFlowStep) -> Void,
        onNewIdentity: @escaping () -> Void,
        onBack: @escaping () -> Void,
        prefilledEmail: String? = nil
    ) {
        self.boundary = boundary
        self.onUpdateFormData = onUpdateFormData
        self.onComplete = onComplete
        self.onIncomplete = onIncomplete
        self.onNewIdentity = onNewIdentity
        self.onBack = onBack
        self.prefilledEmail = prefilledEmail
    }

    #if DEBUG
    /// Snapshot/preview seam — seeds the visual `@State` so a renderer can capture
    /// the error states (which are otherwise only reachable after an async
    /// interaction). DEBUG-only; never used by the live gateway.
    init(
        boundary: LoginBoundary,
        previewEmail: String = "",
        previewPassword: String = "",
        previewDidAttemptSubmit: Bool = false,
        previewNoAccount: Bool = false,
        previewFailureMessage: String? = nil
    ) {
        self.boundary = boundary
        self.onUpdateFormData = { _ in }
        self.onComplete = {}
        self.onIncomplete = { _ in }
        self.onNewIdentity = {}
        self.onBack = {}
        self.prefilledEmail = nil
        _email = State(initialValue: previewEmail)
        _password = State(initialValue: previewPassword)
        _didAttemptSubmit = State(initialValue: previewDidAttemptSubmit)
        _noAccount = State(initialValue: previewNoAccount)
        _failureMessage = State(initialValue: previewFailureMessage)
        _hasAppeared = State(initialValue: true) // settle the entrance for snapshots
    }
    #endif

    // MARK: Field state

    @State private var email = ""
    @State private var password = ""

    /// True once the user has tried to submit — gates whether per-field errors
    /// render (the form is clean before the first attempt, per the spec).
    @State private var didAttemptSubmit = false

    /// Set when an email login resolved to a non-existent account → inline error.
    @State private var noAccount = false

    /// A surfaced top-level failure (wrong password / network / server) — rendered
    /// inline, never silent. Cleared on the next attempt.
    @State private var failureMessage: String?

    /// Which async op is in flight, so the right control shows its spinner.
    @State private var inFlight: InFlight?
    private enum InFlight: Equatable { case email, apple, google }

    /// Forgot-password sheet.
    @State private var showForgotPassword = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case email, password }

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                scrollContent
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            OnboardingHaptics.prepare()
            applyPrefillIfNeeded()
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(OPSStyle.Animation.page) { hasAppeared = true }
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            // Prefill the reset sheet with whatever the user has typed so far.
            ForgotPasswordView(prefilledEmail: trimmedEmail)
        }
    }

    /// The full vertical stack of the screen. Extracted so the DEBUG snapshot
    /// harness can render it WITHOUT the enclosing `ScrollView` — `ImageRenderer`
    /// reports a zero intrinsic size for a `ScrollView` and would capture a blank
    /// frame. The live screen always wraps this in the scroll view.
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            header

            formFields
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            ctaBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            orDivider
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            socialBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
        .padding(.bottom, OPSStyle.Layout.spacing5)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: (hasAppeared || reduceMotion) ? 0 : OPSStyle.Layout.spacing3)
    }

    #if DEBUG
    /// A render of the screen with no `ScrollView`, for the snapshot harness only.
    /// Top-aligned on the canvas so the captured frame matches the live layout.
    var snapshotBody: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()
            scrollContent
        }
    }
    #endif

    // MARK: - Header (Back → welcome)

    private var header: some View {
        OnboardingStepHeader(
            title: "Log in",
            backLabel: "Welcome",
            onBack: onBack
        )
    }

    // MARK: - Email form

    @ViewBuilder
    private var formFields: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            OPSOnboardingField(
                label: "Email",
                text: $email,
                placeholder: "you@company.com",
                kind: .email,
                error: emailError,
                submitLabel: .next,
                onSubmit: { focusedField = .password }
            )
            .focused($focusedField, equals: .email)
            .onChange(of: email) { _, _ in
                // Editing the email clears the no-account state.
                if noAccount { noAccount = false }
            }

            OPSOnboardingField(
                label: "Password",
                text: $password,
                placeholder: "Your password",
                kind: .password,
                error: didAttemptSubmit ? passwordError : nil,
                submitLabel: .go,
                onSubmit: { attemptEmailLogin() }
            )
            .focused($focusedField, equals: .password)

            // Forgot password — ghost affordance, trailing-aligned. Never accent.
            forgotPassword

            // No-account handoff — email login to a non-existent address.
            if noAccount {
                Text("// ERROR — NO ACCOUNT FOR THAT EMAIL — CHECK IT OR SIGN UP")
                    .font(OPSStyle.Typography.metadata)
                    .tracking(1.4)
                    .foregroundColor(OPSStyle.Colors.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("No account for that email. Check it or sign up.")
            }

            // Top-level failure (wrong password / network / server) — inline, never silent.
            if let failureMessage {
                Text("// ERROR — \(failureMessage.uppercased())")
                    .font(OPSStyle.Typography.metadata)
                    .tracking(1.4)
                    .foregroundColor(OPSStyle.Colors.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Error. \(failureMessage)")
            }
        }
    }

    private var forgotPassword: some View {
        Button {
            OnboardingHaptics.selection()
            showForgotPassword = true
        } label: {
            Text("Forgot password?")
                .font(OPSStyle.Typography.body) // Mohave
                .foregroundColor(OPSStyle.Colors.text2) // ghost link, never accent (§9)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Forgot password")
    }

    // MARK: - OR divider (hairline + centered label)

    private var orDivider: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            hairline
            Text("OR")
                .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(1.4)
            hairline
        }
        .accessibilityHidden(true)
    }

    private var hairline: some View {
        Rectangle()
            .fill(OPSStyle.Colors.line) // standard hairline (white@0.10)
            .frame(height: OPSStyle.Layout.Border.standard)
    }

    // MARK: - Social auth (shared component)

    private var socialBlock: some View {
        OnboardingSocialAuthButtons(
            onApple: { commitSocial(.apple) },
            onGoogle: { commitSocial(.google) },
            isLoading: inFlight == .apple || inFlight == .google,
            loadingProvider: inFlight == .apple ? .apple : (inFlight == .google ? .google : nil)
        )
    }

    // MARK: - CTA

    private var ctaBlock: some View {
        OnboardingPrimaryCTA(
            title: "Log in",
            isEnabled: isFormValid,
            isLoading: inFlight == .email
        ) {
            attemptEmailLogin()
        }
    }

    // MARK: - Validation (delegated to the pure, unit-testable value type)

    private var validation: LoginFormValidation {
        LoginFormValidation(email: email, password: password)
    }

    private var trimmedEmail: String { validation.trimmedEmail }

    /// Email error renders after a submit attempt OR once the no-account state is
    /// set (so the bare field also reads rose alongside the handoff line).
    var emailError: String? {
        if noAccount { return "no account for that email" }
        guard didAttemptSubmit else { return nil }
        return validation.emailError
    }

    var passwordError: String? { validation.passwordError }

    /// Email + password both present (and the email is shaped) gates the CTA.
    var isFormValid: Bool { validation.isFormValid }

    // MARK: - Actions

    /// Email/password commit. Validates locally (gating the CTA already enforces
    /// this, but `didAttemptSubmit` lights the per-field errors), then funnels
    /// through the boundary and branches on the outcome.
    func attemptEmailLogin() {
        didAttemptSubmit = true
        failureMessage = nil
        noAccount = false
        guard isFormValid else { return }
        guard inFlight == nil else { return }

        focusedField = nil
        inFlight = .email
        OnboardingHaptics.commit()
        persistTypedEmail()

        Task { @MainActor in
            let outcome = await boundary.logInEmail(email: trimmedEmail, password: password)
            inFlight = nil
            handle(outcome)
        }
    }

    /// Apple / Google commit. A brand-new identity drops into `.newIdentity`.
    private func commitSocial(_ provider: InFlight) {
        guard inFlight == nil else { return }
        failureMessage = nil
        noAccount = false
        focusedField = nil
        inFlight = provider
        OnboardingHaptics.commit()

        Task { @MainActor in
            let outcome: LoginOutcome
            switch provider {
            case .apple:  outcome = await boundary.logInApple()
            case .google: outcome = await boundary.logInGoogle()
            case .email:  return // unreachable — social entry points only
            }
            inFlight = nil
            handle(outcome)
        }
    }

    /// Route an outcome to the right host effect. The host-navigating cases are
    /// delegated to the pure `LoginOutcomeRouter` so the navigation branching is
    /// unit-testable without rendering; the cases that only mutate local screen
    /// state (`@State`) are applied here.
    func handle(_ outcome: LoginOutcome) {
        // Host-navigating effects (complete / incomplete / new-identity) route
        // through the pure router so a test can assert them directly.
        let navigated = LoginOutcomeRouter.route(
            outcome,
            onComplete: {
                OnboardingHaptics.success()
                onComplete()
            },
            onIncomplete: onIncomplete,
            onNewIdentity: {
                OnboardingHaptics.success()
                onNewIdentity()
            }
        )
        guard !navigated else { return }

        // Local-state-only outcomes.
        switch outcome {
        case .noAccount:
            // Persist the typed email (a later sign-up flow may reuse it), then
            // surface the inline error.
            persistTypedEmail()
            noAccount = true

        case .failed(let message):
            // nil message = user cancelled a social sheet → no error surfaced.
            failureMessage = message

        case .complete, .incomplete, .newIdentity:
            break // already handled by the router
        }
    }

    // MARK: - Form-data persistence + prefill

    /// Persist just the email so a kill mid-request resumes with the typed value
    /// and a downstream sign-up can reuse it.
    private func persistTypedEmail() {
        guard !trimmedEmail.isEmpty else { return }
        onUpdateFormData { $0.email = trimmedEmail }
    }

    /// Apply the SIGN IN handoff prefill once, only when the field is still empty
    /// (never clobber what the user has started typing).
    private func applyPrefillIfNeeded() {
        guard email.isEmpty, let prefilledEmail, !prefilledEmail.isEmpty else { return }
        email = prefilledEmail
    }
}

// MARK: - Pure outcome routing (no SwiftUI, fully unit-testable)

/// Routes the HOST-NAVIGATING outcomes (complete / incomplete / new-identity) to
/// the supplied effects, and reports whether it handled the outcome. The
/// local-state-only outcomes (`noAccount`, `failed`) are NOT navigation and
/// return `false` so the caller applies them to `@State`. Extracted so the
/// navigation branching is testable without rendering the screen.
enum LoginOutcomeRouter {
    /// - Returns: `true` when the outcome was a host-navigation effect (and the
    ///   matching closure was invoked); `false` for local-state-only outcomes.
    @discardableResult
    static func route(
        _ outcome: LoginOutcome,
        onComplete: () -> Void,
        onIncomplete: (OnboardingFlowStep) -> Void,
        onNewIdentity: () -> Void
    ) -> Bool {
        switch outcome {
        case .complete:
            onComplete()
            return true
        case .incomplete(let resumeStep):
            onIncomplete(resumeStep)
            return true
        case .newIdentity:
            onNewIdentity()
            return true
        case .noAccount, .failed:
            return false
        }
    }
}

// MARK: - Pure form validation (no SwiftUI, fully unit-testable)

/// The complete validation surface for Login, derived purely from the field
/// values. Extracted from the view so the submit gate is testable WITHOUT
/// rendering. Error strings are the bare phrases (the field renders the
/// `// ERROR — ` prefix). Copy locked via ops-copywriter.
struct LoginFormValidation: Equatable {
    let email: String
    let password: String

    var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var emailError: String? {
        CreateAccountFormValidation.isValidEmail(trimmedEmail) ? nil : "enter a valid email"
    }

    /// The password is only ever blank-checked here — the server is the authority
    /// on correctness (a wrong password surfaces as a top-level `.failed` error,
    /// not a field-level rule). Login never enforces an 8-char minimum: legacy
    /// accounts may predate it.
    var passwordError: String? {
        password.isEmpty ? "enter your password" : nil
    }

    /// Both fields present and the email is shaped → the CTA is live.
    var isFormValid: Bool {
        CreateAccountFormValidation.isValidEmail(trimmedEmail) && !password.isEmpty
    }
}

// MARK: - Previews

#if DEBUG
/// A preview/stub boundary — no network. Returns a fixed outcome so the screen
/// renders in each state.
private struct PreviewLoginBoundary: LoginBoundary {
    var outcome: LoginOutcome = .complete
    func logInEmail(email: String, password: String) async -> LoginOutcome { outcome }
    func logInApple() async -> LoginOutcome { outcome }
    func logInGoogle() async -> LoginOutcome { outcome }
}

#Preview("LoginStepView") {
    LoginStepView(
        boundary: PreviewLoginBoundary(),
        onUpdateFormData: { _ in },
        onComplete: {},
        onIncomplete: { _ in },
        onNewIdentity: {},
        onBack: {}
    )
    .preferredColorScheme(.dark)
}
#endif
