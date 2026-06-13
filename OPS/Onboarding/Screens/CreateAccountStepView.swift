//
//  CreateAccountStepView.swift
//  OPS
//
//  Onboarding rebuild P3 — S3 (Create account): the AUTH COMMIT POINT.
//
//  Design spec §4.2 S3. This is the screen where a brand-new user's account is
//  actually created (Firebase + sync-user). It serves the role chosen on S2
//  (owner / crew) — the role is still UNCOMMITTED here, so Back returns to role
//  pick (the wrong-role escape).
//
//  Layout (top → bottom):
//    • Header — Back → role pick (the role is uncommitted), Cake Mono title.
//    • Social auth — Apple + Google (the shared `OnboardingSocialAuthButtons`).
//    • "OR" hairline divider.
//    • Email form — First name + Last name (inline pair), Email, Password with a
//      show/hide toggle and a BEFORE-submit "8+ characters" rule hint.
//    • Primary CTA — "Create account" (the one accented control), loading +
//      disabled-until-valid.
//
//  COMMIT CONTRACT — the screen owns NO auth logic and reaches NO singletons.
//  Every data op is funnelled through an injected `CreateAccountSignupBoundary`
//  whose three async methods return a `CreateAccountOutcome`. The gateway wires
//  the live boundary (backed by `OnboardingManager` + `DataController`); tests
//  inject a stub so name-gating, the existing-account handoff, and the
//  role-branched advance are all verifiable WITHOUT touching Firebase/network.
//
//  NAME-REQUIRED RULE (spec): no path may exit S3 with an empty first/last name.
//    • Email path — first + last are required fields; the CTA is disabled until
//      first, last, a valid email, and an 8+ char password are all present.
//    • Social path — names auto-fill from the provider. If the resolved name is
//      EMPTY (subsequent Apple sign-in, or a no-name Google account), the screen
//      reveals the first/last fields and REQUIRES them before continuing.
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, zero shadows. Accent (`opsAccent`)
//      appears ONLY on the primary CTA (via the shared component).
//    • Built entirely on the Task 3.1 components — `OPSOnboardingField`,
//      `OnboardingStepHeader`, `OnboardingPrimaryCTA`/`Secondary`, and the
//      shared `OnboardingSocialAuthButtons`. Nothing re-rolled here.
//    • One easing curve; honored only when Reduce Motion is off. Medium-impact
//      haptic on the commit; success notification on account created.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

// MARK: - Signup boundary (the testable seam)

/// What a signup attempt resolved to. The screen branches on these; the gateway
/// produces them from the live managers. Distinguishing new / existing-complete
/// / existing-incomplete / needs-name / failed is the whole point of this enum —
/// it is the contract the gateway's live boundary must honor.
enum CreateAccountOutcome: Equatable {
    /// Brand-new account created. The screen advances to the role-appropriate
    /// next step (owner → companyName, crew → inviteCheck).
    case created

    /// The credentials resolved to an EXISTING, fully-onboarded account and the
    /// user was admitted (or should be). The screen hands off to the gateway's
    /// admit-to-app path.
    case existingComplete

    /// The credentials resolved to an existing account that has NOT finished
    /// onboarding. The screen advances to the supplied derived resume step (the
    /// same rule Login uses), carrying any prefilled form data.
    case existingIncomplete(resumeStep: OnboardingFlowStep)

    /// EMAIL ONLY: the email is already registered but this was a fresh signup
    /// attempt (e.g. password mismatch, or a different provider). The screen
    /// shows an inline error + a one-tap SIGN IN handoff to `.login`, carrying
    /// the typed email so Login can prefill.
    case emailAlreadyRegistered

    /// SOCIAL ONLY: auth succeeded but the provider returned NO usable name. The
    /// screen reveals + requires the first/last fields, then re-commits the
    /// already-authenticated session with the typed name via `completeSocialName`.
    case socialNeedsName(email: String)

    /// The attempt failed (network / server / cancelled-not-applicable). The
    /// screen surfaces `message` inline. A `nil` message = user cancelled (no
    /// error shown).
    case failed(message: String?)
}

/// The async boundary S3 funnels every data op through. Implemented live by the
/// gateway (over `OnboardingManager` + `DataController`); stubbed in tests.
@MainActor
protocol CreateAccountSignupBoundary {
    /// Email/password signup. `firstName`/`lastName` are the validated, required
    /// names — the boundary persists them.
    func signUpEmail(firstName: String, lastName: String, email: String, password: String) async -> CreateAccountOutcome

    /// Apple signup. Names come from the provider (may be empty → `.socialNeedsName`).
    func signUpApple() async -> CreateAccountOutcome

    /// Google signup. Names come from the provider (may be empty → `.socialNeedsName`).
    func signUpGoogle() async -> CreateAccountOutcome

    /// Finish a `.socialNeedsName` session: the user is already authenticated;
    /// this persists the typed name and resolves to `.created` (or a failure).
    func completeSocialName(firstName: String, lastName: String, email: String) async -> CreateAccountOutcome
}

// MARK: - S3 screen

struct CreateAccountStepView: View {

    /// The role committed on S2. Drives the success advance (owner → companyName,
    /// crew → inviteCheck). The gateway passes `coordinator.formData.selectedRole`.
    let selectedRole: OnboardingFlowRole?

    /// The async signup boundary. Injected so the screen never touches Firebase.
    let boundary: CreateAccountSignupBoundary

    /// Persist a collected field into the coordinator's form data. The gateway
    /// wires this to `coordinator.update`.
    let onUpdateFormData: (@escaping (inout OnboardingFormData) -> Void) -> Void

    /// New account created → advance to the role-appropriate next step.
    let onCreated: () -> Void

    /// Existing + COMPLETE account → admit to the app (gateway's handleComplete).
    let onExistingComplete: () -> Void

    /// Existing + INCOMPLETE account → resume at the derived step.
    let onExistingIncomplete: (OnboardingFlowStep) -> Void

    /// SIGN IN handoff (email already registered) → `.login`, email prefilled.
    let onSignIn: () -> Void

    /// Back → role pick (role uncommitted). The gateway wires `coordinator.goBack()`.
    let onBack: () -> Void

    // MARK: Init

    init(
        selectedRole: OnboardingFlowRole?,
        boundary: CreateAccountSignupBoundary,
        onUpdateFormData: @escaping (@escaping (inout OnboardingFormData) -> Void) -> Void,
        onCreated: @escaping () -> Void,
        onExistingComplete: @escaping () -> Void,
        onExistingIncomplete: @escaping (OnboardingFlowStep) -> Void,
        onSignIn: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.selectedRole = selectedRole
        self.boundary = boundary
        self.onUpdateFormData = onUpdateFormData
        self.onCreated = onCreated
        self.onExistingComplete = onExistingComplete
        self.onExistingIncomplete = onExistingIncomplete
        self.onSignIn = onSignIn
        self.onBack = onBack
    }

    #if DEBUG
    /// Snapshot/preview seam — seeds the visual `@State` so a renderer can capture
    /// the error / social-name states (which are otherwise only reachable after an
    /// async interaction). DEBUG-only; never used by the live gateway.
    init(
        selectedRole: OnboardingFlowRole?,
        boundary: CreateAccountSignupBoundary,
        previewFirstName: String = "",
        previewLastName: String = "",
        previewEmail: String = "",
        previewPassword: String = "",
        previewDidAttemptSubmit: Bool = false,
        previewEmailAlreadyRegistered: Bool = false,
        previewFailureMessage: String? = nil,
        previewSocialNameEmail: String? = nil
    ) {
        self.selectedRole = selectedRole
        self.boundary = boundary
        self.onUpdateFormData = { _ in }
        self.onCreated = {}
        self.onExistingComplete = {}
        self.onExistingIncomplete = { _ in }
        self.onSignIn = {}
        self.onBack = {}
        _firstName = State(initialValue: previewFirstName)
        _lastName = State(initialValue: previewLastName)
        _email = State(initialValue: previewEmail)
        _password = State(initialValue: previewPassword)
        _didAttemptSubmit = State(initialValue: previewDidAttemptSubmit)
        _emailAlreadyRegistered = State(initialValue: previewEmailAlreadyRegistered)
        _failureMessage = State(initialValue: previewFailureMessage)
        _socialNameEmail = State(initialValue: previewSocialNameEmail)
        _hasAppeared = State(initialValue: true) // settle the entrance for snapshots
    }
    #endif

    // MARK: Field state

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""

    /// True once the user has tried to submit — gates whether per-field errors
    /// render. Before the first attempt the form is clean (only the rule hint
    /// shows), per the spec (hint BEFORE failure, errors only after a try).
    @State private var didAttemptSubmit = false

    /// Set when the email is already registered → inline error + SIGN IN handoff.
    @State private var emailAlreadyRegistered = false

    /// A surfaced top-level failure (network/server) — rendered inline, never
    /// silent. Cleared on the next attempt.
    @State private var failureMessage: String?

    /// Social path returned no name → reveal + require first/last, then finish
    /// the already-authenticated session. Carries the resolved email.
    @State private var socialNameEmail: String?
    private var isCompletingSocialName: Bool { socialNameEmail != nil }

    /// Which async op is in flight, so the right control shows its spinner.
    @State private var inFlight: InFlight?
    private enum InFlight: Equatable { case email, apple, google }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case first, last, email, password }

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
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(OPSStyle.Animation.page) { hasAppeared = true }
            }
        }
    }

    /// The full vertical stack of the screen. Extracted so the DEBUG snapshot
    /// harness can render it WITHOUT the enclosing `ScrollView` — `ImageRenderer`
    /// reports a zero intrinsic size for a `ScrollView` and would capture a blank
    /// frame. The live screen always wraps this in the scroll view.
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            header

            instruction
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            // The social/divider block is hidden once we drop into the
            // social-name-completion sub-state: at that point the user is
            // already authenticated and only owes us a name.
            if !isCompletingSocialName {
                socialBlock
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                orDivider
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }

            formFields
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            ctaBlock
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

    // MARK: - Header (Back → role pick)

    private var header: some View {
        OnboardingStepHeader(
            title: "Create your account",
            backLabel: "Role",
            onBack: onBack
        )
    }

    // MARK: - Bracketed micro-instruction

    private var instruction: some View {
        Text("[ LOCK IT IN — 30 SECONDS ]")
            .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
            .foregroundColor(OPSStyle.Colors.text3)
            .tracking(1.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true) // decorative; the title carries the label
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

    // MARK: - Email form

    @ViewBuilder
    private var formFields: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            // First + Last name. Required on the email path always, and on the
            // social path once a provider returned no name. The inline pair keeps
            // the once-only identity entry compact.
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                OPSOnboardingField(
                    label: "First name",
                    text: $firstName,
                    placeholder: "First name",
                    kind: .name,
                    error: didAttemptSubmit ? firstNameError : nil,
                    submitLabel: .next,
                    onSubmit: { focusedField = .last }
                )
                .focused($focusedField, equals: .first)

                OPSOnboardingField(
                    label: "Last name",
                    text: $lastName,
                    placeholder: "Last name",
                    kind: .name,
                    error: didAttemptSubmit ? lastNameError : nil,
                    submitLabel: .next,
                    onSubmit: { focusedField = .email }
                )
                .focused($focusedField, equals: .last)
            }

            // Email + password are hidden during social-name completion — the
            // user already authenticated via the provider, so only the name is
            // outstanding.
            if !isCompletingSocialName {
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
                    // Editing the email clears the already-registered handoff.
                    if emailAlreadyRegistered { emailAlreadyRegistered = false }
                }

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1 + 2) {
                    OPSOnboardingField(
                        label: "Password",
                        text: $password,
                        placeholder: "Min 8 characters",
                        kind: .password,
                        error: didAttemptSubmit ? passwordError : nil,
                        submitLabel: .go,
                        onSubmit: { attemptEmailSignup() }
                    )
                    .focused($focusedField, equals: .password)

                    // Rule hint shown BEFORE submit (spec): only while there is no
                    // password error yet, so it never stacks under the error line.
                    if !(didAttemptSubmit && passwordError != nil) {
                        Text("// 8+ CHARACTERS")
                            .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                            .tracking(1.4)
                            .foregroundColor(OPSStyle.Colors.textMute)
                            .accessibilityLabel("Password must be at least 8 characters")
                    }
                }
            }

            // Email-already-registered handoff — inline error + one-tap SIGN IN.
            if emailAlreadyRegistered {
                existingAccountHandoff
            }

            // Top-level failure (network/server) — inline, never silent.
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

    // MARK: - Existing-account handoff (email already registered)

    private var existingAccountHandoff: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("// ERROR — THAT EMAIL ALREADY HAS AN ACCOUNT")
                .font(OPSStyle.Typography.metadata)
                .tracking(1.4)
                .foregroundColor(OPSStyle.Colors.rose)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("That email already has an account")

            // Ghost SIGN IN — carries the typed email into Login (set just before
            // the handoff fires). Never accented.
            OnboardingSecondaryCTA(title: "Sign in") {
                handoffToSignIn()
            }
        }
    }

    // MARK: - CTA

    private var ctaBlock: some View {
        OnboardingPrimaryCTA(
            title: ctaTitle,
            isEnabled: isFormValid,
            isLoading: inFlight == .email
        ) {
            if isCompletingSocialName {
                attemptSocialNameCompletion()
            } else {
                attemptEmailSignup()
            }
        }
    }

    /// During social-name completion the action is "continue" (finish the
    /// already-authenticated session); otherwise it is the account commit.
    private var ctaTitle: String {
        isCompletingSocialName ? "Continue" : "Create account"
    }

    // MARK: - Validation (delegated to the pure, unit-testable value type)

    /// A snapshot of the current field values + sub-state, fed to the pure
    /// validator. Recomputed per access; cheap.
    private var validation: CreateAccountFormValidation {
        CreateAccountFormValidation(
            firstName: firstName,
            lastName: lastName,
            email: email,
            password: password,
            isCompletingSocialName: isCompletingSocialName
        )
    }

    private var trimmedFirst: String { validation.trimmedFirst }
    private var trimmedLast: String { validation.trimmedLast }
    private var trimmedEmail: String { validation.trimmedEmail }

    var firstNameError: String? { validation.firstNameError }
    var lastNameError: String? { validation.lastNameError }

    /// Email error renders after a submit attempt OR once the already-registered
    /// state is set (so the bare field also reads rose alongside the handoff).
    var emailError: String? {
        if emailAlreadyRegistered { return "that email already has an account" }
        guard didAttemptSubmit else { return nil }
        return validation.emailError
    }

    var passwordError: String? { validation.passwordError }

    /// Names are always required. Email + password are required only when NOT
    /// completing a social name (the social session is already authenticated).
    var isFormValid: Bool { validation.isFormValid }

    // MARK: - Actions

    /// Email/password commit. Validates locally (gating the CTA already enforces
    /// this, but `didAttemptSubmit` lights the per-field errors), then funnels
    /// through the boundary and branches on the outcome.
    func attemptEmailSignup() {
        didAttemptSubmit = true
        failureMessage = nil
        guard isFormValid else { return }
        guard inFlight == nil else { return }

        focusedField = nil
        inFlight = .email
        OnboardingHaptics.commit()
        persistTypedIdentity()

        Task { @MainActor in
            let outcome = await boundary.signUpEmail(
                firstName: trimmedFirst,
                lastName: trimmedLast,
                email: trimmedEmail,
                password: password
            )
            inFlight = nil
            handle(outcome)
        }
    }

    /// Apple / Google commit. The provider drives name resolution; on a no-name
    /// result we drop into the social-name sub-state.
    private func commitSocial(_ provider: InFlight) {
        guard inFlight == nil else { return }
        failureMessage = nil
        emailAlreadyRegistered = false
        focusedField = nil
        inFlight = provider
        OnboardingHaptics.commit()

        Task { @MainActor in
            let outcome: CreateAccountOutcome
            switch provider {
            case .apple:  outcome = await boundary.signUpApple()
            case .google: outcome = await boundary.signUpGoogle()
            case .email:  return // unreachable — social entry points only
            }
            inFlight = nil
            handle(outcome)
        }
    }

    /// Finish a `.socialNeedsName` session — the user is already authenticated,
    /// so this only persists the typed name.
    func attemptSocialNameCompletion() {
        didAttemptSubmit = true
        failureMessage = nil
        guard let email = socialNameEmail, isFormValid else { return }
        guard inFlight == nil else { return }

        focusedField = nil
        inFlight = .email
        OnboardingHaptics.commit()
        persistTypedIdentity()

        Task { @MainActor in
            let outcome = await boundary.completeSocialName(
                firstName: trimmedFirst,
                lastName: trimmedLast,
                email: email
            )
            inFlight = nil
            handle(outcome)
        }
    }

    /// Route an outcome to the right host effect. The host-navigating cases are
    /// delegated to the pure `CreateAccountOutcomeRouter` so the navigation
    /// branching is unit-testable without rendering; the cases that only mutate
    /// local screen state (`@State`) are applied here.
    func handle(_ outcome: CreateAccountOutcome) {
        // Host-navigating effects (created / existing-complete / existing-incomplete)
        // route through the pure router so a test can assert them directly.
        let navigated = CreateAccountOutcomeRouter.route(
            outcome,
            onCreated: {
                OnboardingHaptics.success()
                onCreated()
            },
            onExistingComplete: onExistingComplete,
            onExistingIncomplete: onExistingIncomplete
        )
        guard !navigated else { return }

        // Local-state-only outcomes.
        switch outcome {
        case .emailAlreadyRegistered:
            // Persist the typed email so the SIGN IN handoff prefills Login, then
            // surface the inline error + handoff.
            persistTypedEmail()
            emailAlreadyRegistered = true

        case .socialNeedsName(let email):
            // Drop into name-completion: reveal + require first/last. The email/
            // password fields hide; the CTA becomes "Continue". Any partial name
            // the provider DID return is already in the fields (the boundary
            // doesn't reach here unless BOTH are missing).
            socialNameEmail = email
            didAttemptSubmit = false

        case .failed(let message):
            // nil message = user cancelled → no error surfaced.
            failureMessage = message

        case .created, .existingComplete, .existingIncomplete:
            break // already handled by the router
        }
    }

    /// SIGN IN handoff — make sure Login can prefill the typed email, then route.
    private func handoffToSignIn() {
        persistTypedEmail()
        onSignIn()
    }

    // MARK: - Form-data persistence

    /// Persist first/last/email into the coordinator before the async commit, so
    /// a kill mid-request resumes with the typed identity.
    private func persistTypedIdentity() {
        onUpdateFormData { data in
            data.firstName = trimmedFirst.isEmpty ? data.firstName : trimmedFirst
            data.lastName = trimmedLast.isEmpty ? data.lastName : trimmedLast
            if !trimmedEmail.isEmpty { data.email = trimmedEmail }
        }
    }

    /// Persist just the email — used for the SIGN IN handoff prefill.
    private func persistTypedEmail() {
        guard !trimmedEmail.isEmpty else { return }
        onUpdateFormData { $0.email = trimmedEmail }
    }
}

// MARK: - Pure outcome routing (no SwiftUI, fully unit-testable)

/// Routes the HOST-NAVIGATING outcomes (created / existing-complete /
/// existing-incomplete) to the supplied effects, and reports whether it handled
/// the outcome. The local-state-only outcomes (`emailAlreadyRegistered`,
/// `socialNeedsName`, `failed`) are NOT navigation and return `false` so the
/// caller applies them to `@State`. Extracted so the navigation branching is
/// testable without rendering the screen.
enum CreateAccountOutcomeRouter {
    /// - Returns: `true` when the outcome was a host-navigation effect (and the
    ///   matching closure was invoked); `false` for local-state-only outcomes.
    @discardableResult
    static func route(
        _ outcome: CreateAccountOutcome,
        onCreated: () -> Void,
        onExistingComplete: () -> Void,
        onExistingIncomplete: (OnboardingFlowStep) -> Void
    ) -> Bool {
        switch outcome {
        case .created:
            onCreated()
            return true
        case .existingComplete:
            onExistingComplete()
            return true
        case .existingIncomplete(let resumeStep):
            onExistingIncomplete(resumeStep)
            return true
        case .emailAlreadyRegistered, .socialNeedsName, .failed:
            return false
        }
    }
}

// MARK: - Pure form validation (no SwiftUI, fully unit-testable)

/// The complete validation surface for S3, derived purely from field values and
/// whether the screen is in the social-name-completion sub-state. Extracted from
/// the view so the name-required rule and the submit gate are testable WITHOUT
/// rendering. Error strings are the bare phrases (the field renders the
/// `// ERROR — ` prefix). Copy locked via ops-copywriter.
struct CreateAccountFormValidation: Equatable {
    let firstName: String
    let lastName: String
    let email: String
    let password: String
    /// When true, the social provider already authenticated the user — only the
    /// name is required; email/password are not collected on this screen.
    let isCompletingSocialName: Bool

    var trimmedFirst: String { firstName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedLast: String { lastName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var firstNameError: String? { trimmedFirst.isEmpty ? "enter your first name" : nil }
    var lastNameError: String? { trimmedLast.isEmpty ? "enter your last name" : nil }
    var emailError: String? { Self.isValidEmail(trimmedEmail) ? nil : "enter a valid email" }
    var passwordError: String? { password.count >= 8 ? nil : "use at least 8 characters" }

    /// Names are ALWAYS required (the spec's no-empty-name rule). Email + password
    /// are required only when NOT completing a social name.
    var isFormValid: Bool {
        guard !trimmedFirst.isEmpty, !trimmedLast.isEmpty else { return false }
        if isCompletingSocialName { return true }
        return Self.isValidEmail(trimmedEmail) && password.count >= 8
    }

    /// Minimal, dependency-free email shape check (a single `@` with a non-empty
    /// local part + a dotted domain that doesn't start/end with a dot). The
    /// server is the real authority; this just gates the local CTA.
    static func isValidEmail(_ candidate: String) -> Bool {
        let parts = candidate.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}

// MARK: - Previews

#if DEBUG
/// A preview/stub boundary — no network. Returns a fixed outcome so the screen
/// renders in each state.
private struct PreviewSignupBoundary: CreateAccountSignupBoundary {
    var outcome: CreateAccountOutcome = .created
    func signUpEmail(firstName: String, lastName: String, email: String, password: String) async -> CreateAccountOutcome { outcome }
    func signUpApple() async -> CreateAccountOutcome { outcome }
    func signUpGoogle() async -> CreateAccountOutcome { outcome }
    func completeSocialName(firstName: String, lastName: String, email: String) async -> CreateAccountOutcome { outcome }
}

#Preview("CreateAccountStepView — owner") {
    CreateAccountStepView(
        selectedRole: .owner,
        boundary: PreviewSignupBoundary(),
        onUpdateFormData: { _ in },
        onCreated: {},
        onExistingComplete: {},
        onExistingIncomplete: { _ in },
        onSignIn: {},
        onBack: {}
    )
    .preferredColorScheme(.dark)
}
#endif
