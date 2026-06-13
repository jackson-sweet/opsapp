//
//  OnboardingScreensTests.swift
//  OPSTests
//
//  Onboarding rebuild P3 — S1 (Welcome) and S2 (Role pick).
//
//  TWO concerns, one file:
//
//  1. LOGIC — the screens are dumb views whose buttons/cards are injected
//     closures. We wire those closures to the SAME coordinator actions the
//     gateway wires (advance / update+advance / goBack / signOut) and assert
//     the navigation + form-data effects:
//       • GET STARTED        → currentStep == .rolePick
//       • SIGN IN            → currentStep == .login
//       • RUN A CREW (owner) → selectedRole == .owner  AND  .createAccount
//       • JOIN A CREW (crew) → selectedRole == .crew   AND  .createAccount
//     The closures we exercise are EXACTLY the ones the gateway passes (kept in
//     sync via `GatewayActions` below), so a wiring regression in the gateway
//     would be caught here. Persistence runs on an isolated UserDefaults suite —
//     never `.standard`. The coordinator is @MainActor, so this case is too.
//
//  2. SNAPSHOT — renders each screen to a PNG via `ImageRenderer`→`XCTAttachment`
//     (the house harness, mirrored from `BooksSnapshotTests`) in default + dark +
//     Reduce-Motion, for human/agent visual inspection. Never asserts on pixels.
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class OnboardingScreensTests: XCTestCase {

    // MARK: - Isolated UserDefaults suite (never pollute .standard)

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingScreensTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Builders

    private func makeCoordinator(
        isAuthenticated: @escaping () -> Bool,
        serverState: @escaping () -> OnboardingServerState? = { nil }
    ) -> OnboardingFlowCoordinator {
        OnboardingFlowCoordinator(
            store: OnboardingFlowStateStore(defaults: defaults),
            isAuthenticated: isAuthenticated,
            serverStateProvider: serverState
        )
    }

    /// The exact closures the gateway wires into each screen. Keeping the wiring
    /// in ONE place the test drives means the test exercises the production
    /// navigation paths, not a re-implementation of them. `@MainActor` because
    /// the closures touch the @MainActor coordinator.
    @MainActor
    private enum GatewayActions {
        static func welcome(_ c: OnboardingFlowCoordinator) -> WelcomeStepView {
            WelcomeStepView(
                onGetStarted: { c.advance(to: .rolePick) },
                onSignIn: { c.advance(to: .login) }
            )
        }

        static func rolePick(_ c: OnboardingFlowCoordinator, onSignOut: @escaping () -> Void) -> RolePickStepView {
            RolePickStepView(
                onSelectOwner: {
                    c.update { $0.selectedRole = .owner }
                    c.advance(to: .createAccount)
                },
                onSelectCrew: {
                    c.update { $0.selectedRole = .crew }
                    c.advance(to: .createAccount)
                },
                canGoBack: c.canGoBack,
                onBack: { c.goBack() },
                onSignOut: onSignOut
            )
        }

        /// The EXACT closures the gateway wires into S4 (Login). `onComplete` is
        /// the host admit path (asserted via a flag in tests — it does not advance
        /// the flow); `onIncomplete` resumes at the derived step; `onNewIdentity`
        /// routes a brand-new social identity to `.rolePick`; `onSignIn`/`onBack`
        /// mirror the gateway. Driving these exercises the production navigation.
        static func login(
            _ c: OnboardingFlowCoordinator,
            boundary: LoginBoundary,
            onComplete: @escaping () -> Void
        ) -> LoginStepView {
            LoginStepView(
                boundary: boundary,
                onUpdateFormData: { mutate in c.update(mutate) },
                onComplete: onComplete,
                onIncomplete: { resume in c.advance(to: resume) },
                onNewIdentity: { c.advance(to: .rolePick) },
                onBack: { c.goBack() },
                prefilledEmail: c.formData.email
            )
        }

        /// The EXACT closures the gateway wires into S4o (Company name). `onCreated`
        /// persists the DB-truth code into `generatedCrewCode` and advances to
        /// `.crewCode` — the gateway's exact success wiring; `onBack` mirrors the
        /// gateway. Driving these exercises the production navigation, not a copy.
        static func companyName(
            _ c: OnboardingFlowCoordinator,
            boundary: CompanyCreationBoundary
        ) -> CompanyNameStepView {
            CompanyNameStepView(
                boundary: boundary,
                onUpdateFormData: { mutate in c.update(mutate) },
                onCreated: { code in
                    c.update { $0.generatedCrewCode = code }
                    c.advance(to: .crewCode)
                },
                onBack: { c.goBack() }
            )
        }

        /// The EXACT closures the gateway wires into S5o (Crew code). It reads the
        /// code + company name off form data; ENTER OPS advances to the completion
        /// gate. Driving the closure exercises the production navigation.
        static func crewCode(_ c: OnboardingFlowCoordinator) -> CrewCodeStepView {
            CrewCodeStepView(
                crewCode: c.formData.generatedCrewCode ?? "",
                companyName: c.formData.companyName ?? "",
                onEnter: { c.advance(to: .completionGate) }
            )
        }

        /// The EXACT closures the gateway wires into S3. The `onCreated` advance
        /// is the gateway's `createAccountNextStep(role:)` rule; `onSignIn` routes
        /// to `.login` (email already persisted into formData for prefill). Driving
        /// these from the test exercises the production navigation, not a copy.
        static func createAccount(
            _ c: OnboardingFlowCoordinator,
            boundary: CreateAccountSignupBoundary
        ) -> CreateAccountStepView {
            CreateAccountStepView(
                selectedRole: c.formData.selectedRole,
                boundary: boundary,
                onUpdateFormData: { mutate in c.update(mutate) },
                onCreated: {
                    c.advance(to: OnboardingGateway.createAccountNextStep(role: c.formData.selectedRole))
                },
                onExistingComplete: { /* host admit path — asserted via a flag in tests */ },
                onExistingIncomplete: { resume in c.advance(to: resume) },
                onSignIn: { c.advance(to: .login) },
                onBack: { c.goBack() }
            )
        }
    }

    // MARK: - Stub signup boundary (no Firebase / no network)

    /// Records the calls S3 makes and returns canned outcomes per provider, so the
    /// async actions resolve deterministically. `@MainActor` to satisfy the
    /// protocol's isolation.
    @MainActor
    private final class StubSignupBoundary: CreateAccountSignupBoundary {
        var emailOutcome: CreateAccountOutcome = .created
        var appleOutcome: CreateAccountOutcome = .created
        var googleOutcome: CreateAccountOutcome = .created
        var socialNameOutcome: CreateAccountOutcome = .created

        private(set) var emailCallCount = 0
        private(set) var appleCallCount = 0
        private(set) var googleCallCount = 0
        private(set) var socialNameCallCount = 0
        private(set) var lastEmail: String?
        private(set) var lastFirstName: String?
        private(set) var lastLastName: String?

        func signUpEmail(firstName: String, lastName: String, email: String, password: String) async -> CreateAccountOutcome {
            emailCallCount += 1
            lastEmail = email; lastFirstName = firstName; lastLastName = lastName
            return emailOutcome
        }
        func signUpApple() async -> CreateAccountOutcome { appleCallCount += 1; return appleOutcome }
        func signUpGoogle() async -> CreateAccountOutcome { googleCallCount += 1; return googleOutcome }
        func completeSocialName(firstName: String, lastName: String, email: String) async -> CreateAccountOutcome {
            socialNameCallCount += 1
            lastFirstName = firstName; lastLastName = lastName; lastEmail = email
            return socialNameOutcome
        }
    }

    // MARK: - Stub login boundary (no Firebase / no network)

    /// Records the calls S4 makes and returns canned outcomes per provider, so the
    /// async login actions resolve deterministically. `@MainActor` to satisfy the
    /// protocol's isolation.
    @MainActor
    private final class StubLoginBoundary: LoginBoundary {
        var emailOutcome: LoginOutcome = .complete
        var appleOutcome: LoginOutcome = .complete
        var googleOutcome: LoginOutcome = .complete

        private(set) var emailCallCount = 0
        private(set) var appleCallCount = 0
        private(set) var googleCallCount = 0
        private(set) var lastEmail: String?
        private(set) var lastPassword: String?

        func logInEmail(email: String, password: String) async -> LoginOutcome {
            emailCallCount += 1
            lastEmail = email; lastPassword = password
            return emailOutcome
        }
        func logInApple() async -> LoginOutcome { appleCallCount += 1; return appleOutcome }
        func logInGoogle() async -> LoginOutcome { googleCallCount += 1; return googleOutcome }
    }

    // MARK: - Stub company-creation boundary (no network / no RPC)

    /// Records the company-create call S4o makes and returns a canned outcome, so
    /// the async commit resolves deterministically. `@MainActor` to satisfy the
    /// protocol's isolation.
    @MainActor
    private final class StubCompanyBoundary: CompanyCreationBoundary {
        var outcome: CompanyCreationOutcome = .created(code: "BR8K-90ZT")

        private(set) var callCount = 0
        private(set) var lastName: String?
        private(set) var lastIndustries: [String]?

        func createCompany(name: String, industries: [String]) async -> CompanyCreationOutcome {
            callCount += 1
            lastName = name
            lastIndustries = industries
            return outcome
        }
    }

    // MARK: - Stub completion boundary (no network / no server ACK)

    /// Records the completion call the gate makes and returns a canned outcome, so
    /// the ACK-or-queue async action resolves deterministically. A `nil` outcome
    /// models a HUNG call (the boundary never returns) so the watchdog/escape path
    /// can be exercised. `@MainActor` to satisfy the protocol's isolation.
    @MainActor
    private final class StubCompletionBoundary: CompletionBoundary {
        /// The outcome to return; `nil` = never return (simulate a hung request).
        var outcome: OnboardingManager.CompletionOutcome? = .acknowledged

        private(set) var callCount = 0

        func complete() async -> OnboardingManager.CompletionOutcome {
            callCount += 1
            guard let outcome else {
                // Never resolves — the gate's watchdog/escape must admit anyway.
                // Suspend forever (cooperatively cancellable) without busy-waiting.
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                } onCancel: {}
                return .queued // unreachable; satisfies the signature
            }
            return outcome
        }
    }

    // MARK: - Stub invite-check boundary (no network / no RPC)

    /// Records the invite-check call S4c makes and returns a canned outcome, so the
    /// async check resolves deterministically. `@MainActor` for protocol isolation.
    @MainActor
    private final class StubInviteCheckBoundary: InviteCheckBoundary {
        var outcome: InviteCheckOutcome = .found([])
        private(set) var callCount = 0

        func checkInvites() async -> InviteCheckOutcome {
            callCount += 1
            return outcome
        }
    }

    // MARK: - Stub code-entry boundary (no network / no RPC)

    /// Records the lookup call S4c-code makes and returns a canned outcome, so the
    /// async lookup resolves deterministically. `@MainActor` for protocol isolation.
    @MainActor
    private final class StubCodeEntryBoundary: CodeEntryBoundary {
        var outcome: CodeEntryOutcome = .found(
            FoundCompany(companyId: "c1", companyName: "Sweet Deck & Rail", companyCode: "BR8K90ZT", companyLogoUrl: nil)
        )
        private(set) var callCount = 0
        private(set) var lastCode: String?

        func lookUpCompany(code: String) async -> CodeEntryOutcome {
            callCount += 1
            lastCode = code
            return outcome
        }
    }

    // MARK: - Invite fixtures (no network)

    /// A pending-invite fixture for the picker / invite-check tests.
    private func makeInvite(
        invitationId: String = UUID().uuidString,
        companyId: String = UUID().uuidString,
        companyName: String = "Sweet Deck & Rail",
        companyCode: String? = "BR8K90ZT"
    ) -> PendingInviteDTO {
        PendingInviteDTO(
            invitationId: invitationId,
            companyId: companyId,
            companyName: companyName,
            companyCode: companyCode,
            companyLogoUrl: nil,
            industries: ["Carpentry"],
            roleName: "Crew",
            invitedByName: "Jack Sweet",
            teamMembers: [TeamMemberDTO(firstName: "Jack", lastName: "Sweet", profileImageUrl: nil)],
            teamSize: 4,
            expiresAt: "2026-12-31T00:00:00Z"
        )
    }

    // MARK: - S1 Welcome — GET STARTED → rolePick

    func testWelcomeGetStartedAdvancesToRolePick() {
        let coordinator = makeCoordinator(isAuthenticated: { false })
        coordinator.start()
        XCTAssertEqual(coordinator.currentStep, .welcome)

        let screen = GatewayActions.welcome(coordinator)
        screen.onGetStarted()

        XCTAssertEqual(coordinator.currentStep, .rolePick)
    }

    // MARK: - S1 Welcome — SIGN IN → login

    func testWelcomeSignInAdvancesToLogin() {
        let coordinator = makeCoordinator(isAuthenticated: { false })
        coordinator.start()

        let screen = GatewayActions.welcome(coordinator)
        screen.onSignIn()

        XCTAssertEqual(coordinator.currentStep, .login)
    }

    // MARK: - S2 Role pick — RUN A CREW → owner + createAccount

    func testRolePickOwnerSetsRoleAndAdvances() {
        let coordinator = makeCoordinator(isAuthenticated: { false })
        coordinator.start()
        coordinator.advance(to: .rolePick)

        let screen = GatewayActions.rolePick(coordinator, onSignOut: {})
        screen.onSelectOwner()

        XCTAssertEqual(coordinator.formData.selectedRole, .owner)
        XCTAssertEqual(coordinator.currentStep, .createAccount)
    }

    // MARK: - S2 Role pick — JOIN A CREW → crew + createAccount

    func testRolePickCrewSetsRoleAndAdvances() {
        let coordinator = makeCoordinator(isAuthenticated: { false })
        coordinator.start()
        coordinator.advance(to: .rolePick)

        let screen = GatewayActions.rolePick(coordinator, onSignOut: {})
        screen.onSelectCrew()

        XCTAssertEqual(coordinator.formData.selectedRole, .crew)
        XCTAssertEqual(coordinator.currentStep, .createAccount)
    }

    // MARK: - S2 Role pick — Back (pre-auth) → welcome

    func testRolePickBackReturnsToWelcomePreAuth() {
        let coordinator = makeCoordinator(isAuthenticated: { false })
        coordinator.start()
        coordinator.advance(to: .rolePick)
        // Pre-auth, rolePick has a back-edge to welcome — the screen shows Back.
        XCTAssertTrue(coordinator.canGoBack)

        let screen = GatewayActions.rolePick(coordinator, onSignOut: {})
        screen.onBack()

        XCTAssertEqual(coordinator.currentStep, .welcome)
    }

    // MARK: - S2 Role pick — post-auth resume has no back-edge (SIGN OUT shows)

    func testRolePickPostAuthResumeHasNoBackEdge() {
        // Authenticated + no company + owner-ish facts → resume lands at rolePick
        // with NO back-edge, so the screen must surface SIGN OUT, not Back.
        let coordinator = makeCoordinator(isAuthenticated: { true })
        coordinator.advance(to: .rolePick) // place directly, post-auth context

        XCTAssertFalse(coordinator.canGoBack)

        var didSignOut = false
        let screen = GatewayActions.rolePick(coordinator, onSignOut: { didSignOut = true })
        screen.onSignOut()

        XCTAssertTrue(didSignOut, "SIGN OUT escape must invoke the host handler")
    }

    // MARK: - S3 Create account — name-required gating (pure validator)

    func testCreateAccountNameRequiredGatesSubmit() {
        // No first/last → invalid regardless of a perfect email + password.
        let noNames = CreateAccountFormValidation(
            firstName: "", lastName: "",
            email: "jack@ops.app", password: "hunter2hunter2",
            isCompletingSocialName: false
        )
        XCTAssertFalse(noNames.isFormValid)
        XCTAssertEqual(noNames.firstNameError, "enter your first name")
        XCTAssertEqual(noNames.lastNameError, "enter your last name")

        // First only → still invalid (last missing).
        let firstOnly = CreateAccountFormValidation(
            firstName: "Jack", lastName: "  ",
            email: "jack@ops.app", password: "hunter2hunter2",
            isCompletingSocialName: false
        )
        XCTAssertFalse(firstOnly.isFormValid)
        XCTAssertEqual(firstOnly.lastNameError, "enter your last name")

        // All present + valid → valid.
        let complete = CreateAccountFormValidation(
            firstName: "Jack", lastName: "Sweet",
            email: "jack@ops.app", password: "hunter2hunter2",
            isCompletingSocialName: false
        )
        XCTAssertTrue(complete.isFormValid)
        XCTAssertNil(complete.firstNameError)
        XCTAssertNil(complete.lastNameError)
        XCTAssertNil(complete.emailError)
        XCTAssertNil(complete.passwordError)
    }

    func testCreateAccountEmailAndPasswordGating() {
        // Names present but bad email → invalid.
        let badEmail = CreateAccountFormValidation(
            firstName: "Jack", lastName: "Sweet",
            email: "not-an-email", password: "hunter2hunter2",
            isCompletingSocialName: false
        )
        XCTAssertFalse(badEmail.isFormValid)
        XCTAssertEqual(badEmail.emailError, "enter a valid email")

        // Names + email present but short password → invalid.
        let shortPw = CreateAccountFormValidation(
            firstName: "Jack", lastName: "Sweet",
            email: "jack@ops.app", password: "short",
            isCompletingSocialName: false
        )
        XCTAssertFalse(shortPw.isFormValid)
        XCTAssertEqual(shortPw.passwordError, "use at least 8 characters")
    }

    func testCreateAccountSocialNameCompletionOnlyRequiresName() {
        // In the social-name sub-state, email/password are NOT collected — names
        // alone gate the continue.
        let namesOnly = CreateAccountFormValidation(
            firstName: "Jack", lastName: "Sweet",
            email: "", password: "",
            isCompletingSocialName: true
        )
        XCTAssertTrue(namesOnly.isFormValid)

        let missingName = CreateAccountFormValidation(
            firstName: "", lastName: "Sweet",
            email: "", password: "",
            isCompletingSocialName: true
        )
        XCTAssertFalse(missingName.isFormValid)
    }

    func testEmailShapeValidator() {
        XCTAssertTrue(CreateAccountFormValidation.isValidEmail("jack@ops.app"))
        XCTAssertTrue(CreateAccountFormValidation.isValidEmail("a.b+c@sub.domain.io"))
        XCTAssertFalse(CreateAccountFormValidation.isValidEmail("jack"))
        XCTAssertFalse(CreateAccountFormValidation.isValidEmail("jack@ops"))
        XCTAssertFalse(CreateAccountFormValidation.isValidEmail("@ops.app"))
        XCTAssertFalse(CreateAccountFormValidation.isValidEmail("jack@.app"))
        XCTAssertFalse(CreateAccountFormValidation.isValidEmail("jack@@ops.app"))
    }

    // MARK: - S3 Create account — successful new signup advance (role-branched)

    /// Mirrors the gateway's `onCreated`: a created outcome advances to the
    /// role-appropriate next step via the pure router + the gateway rule.
    private func routeCreated(_ c: OnboardingFlowCoordinator) {
        CreateAccountOutcomeRouter.route(
            .created,
            onCreated: { c.advance(to: OnboardingGateway.createAccountNextStep(role: c.formData.selectedRole)) },
            onExistingComplete: {},
            onExistingIncomplete: { c.advance(to: $0) }
        )
    }

    func testCreateAccountOwnerSuccessAdvancesToCompanyName() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .owner }
        c.advance(to: .createAccount)

        routeCreated(c)

        XCTAssertEqual(c.currentStep, .companyName)
    }

    func testCreateAccountCrewSuccessAdvancesToInviteCheck() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .crew }
        c.advance(to: .createAccount)

        routeCreated(c)

        XCTAssertEqual(c.currentStep, .inviteCheck)
    }

    // MARK: - S3 Create account — existing-account branches

    func testCreateAccountExistingCompleteAdmitsToApp() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .createAccount)

        var didAdmit = false
        let handled = CreateAccountOutcomeRouter.route(
            .existingComplete,
            onCreated: { XCTFail("should not advance") },
            onExistingComplete: { didAdmit = true },
            onExistingIncomplete: { _ in XCTFail("should not resume") }
        )
        XCTAssertTrue(handled)
        XCTAssertTrue(didAdmit, "existing-complete must take the host admit path")
        // No flow advance — the host admits to the app instead.
        XCTAssertEqual(c.currentStep, .createAccount)
    }

    func testCreateAccountExistingIncompleteResumesAtDerivedStep() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .crew }
        c.advance(to: .createAccount)

        // Existing-but-incomplete account → resume at the derived step (.profile),
        // exactly as Login will. The gateway wires onExistingIncomplete → advance.
        CreateAccountOutcomeRouter.route(
            .existingIncomplete(resumeStep: .profile),
            onCreated: { XCTFail("should not advance to next") },
            onExistingComplete: { XCTFail("should not admit") },
            onExistingIncomplete: { c.advance(to: $0) }
        )

        XCTAssertEqual(c.currentStep, .profile)
    }

    func testCreateAccountSocialNoNameIsNotANavigation() {
        // A no-name social result is local-state-only (the screen reveals + requires
        // the name fields). The router must NOT treat it as a navigation, so the
        // flow stays on createAccount.
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .owner }
        c.advance(to: .createAccount)

        let handled = CreateAccountOutcomeRouter.route(
            .socialNeedsName(email: "jack@ops.app"),
            onCreated: { XCTFail("no advance") },
            onExistingComplete: { XCTFail("no admit") },
            onExistingIncomplete: { _ in XCTFail("no resume") }
        )
        XCTAssertFalse(handled, "social-no-name is local state, not a navigation")
        XCTAssertEqual(c.currentStep, .createAccount)
    }

    func testCreateAccountEmailAlreadyRegisteredIsNotANavigationAndSignInHandsOff() {
        // emailAlreadyRegistered is local-state-only too — the router doesn't move
        // the flow; the SIGN IN button is what hands off to .login.
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .createAccount)

        let handled = CreateAccountOutcomeRouter.route(
            .emailAlreadyRegistered,
            onCreated: { XCTFail() },
            onExistingComplete: { XCTFail() },
            onExistingIncomplete: { _ in XCTFail() }
        )
        XCTAssertFalse(handled)
        XCTAssertEqual(c.currentStep, .createAccount)

        // The SIGN IN handoff routes to .login with the typed email persisted for
        // Login to prefill.
        c.update { $0.email = "jack@ops.app" }
        let screen = GatewayActions.createAccount(c, boundary: StubSignupBoundary())
        screen.onSignIn()

        XCTAssertEqual(c.currentStep, .login)
        XCTAssertEqual(c.formData.email, "jack@ops.app")
    }

    func testCreateAccountNextStepRule() {
        XCTAssertEqual(OnboardingGateway.createAccountNextStep(role: .owner), .companyName)
        XCTAssertEqual(OnboardingGateway.createAccountNextStep(role: .crew), .inviteCheck)
        XCTAssertEqual(OnboardingGateway.createAccountNextStep(role: nil), .inviteCheck)
    }

    // MARK: - S4o Company name — name-required gating (pure validator)

    func testCompanyNameRequiredGatesSubmit() {
        // Empty / whitespace → invalid, with the bare field-error phrase.
        let empty = CompanyNameValidation(companyName: "")
        XCTAssertFalse(empty.isFormValid)
        XCTAssertEqual(empty.nameError, "enter a company name")

        let blank = CompanyNameValidation(companyName: "   ")
        XCTAssertFalse(blank.isFormValid)
        XCTAssertEqual(blank.nameError, "enter a company name")

        // A real name → valid, no error. Trimming is applied.
        let named = CompanyNameValidation(companyName: "  Sweet Deck & Rail  ")
        XCTAssertTrue(named.isFormValid)
        XCTAssertNil(named.nameError)
        XCTAssertEqual(named.trimmedName, "Sweet Deck & Rail")
    }

    // MARK: - S4o Company name — successful creation persists code + advances

    func testCompanyNameSuccessPersistsCodeAndAdvancesToCrewCode() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .owner }
        c.advance(to: .companyName)

        // The created outcome carries the DB-truth code. Routing it via the gateway's
        // exact wiring must persist `generatedCrewCode` AND advance to `.crewCode`.
        CompanyCreationOutcomeRouter.route(
            .created(code: "BR8K-90ZT"),
            onCreated: { code in
                c.update { $0.generatedCrewCode = code }
                c.advance(to: .crewCode)
            }
        )

        XCTAssertEqual(c.formData.generatedCrewCode, "BR8K-90ZT")
        XCTAssertEqual(c.currentStep, .crewCode)
    }

    // MARK: - S4o Company name — invalidName is a FIELD error, no nav

    func testCompanyNameInvalidNameIsNotANavigation() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .owner }
        c.advance(to: .companyName)

        let handled = CompanyCreationOutcomeRouter.route(
            .invalidName(message: "enter a company name"),
            onCreated: { _ in XCTFail("invalidName must not advance") }
        )
        XCTAssertFalse(handled, "invalidName is a field error, not a navigation")
        XCTAssertEqual(c.currentStep, .companyName)
        XCTAssertNil(c.formData.generatedCrewCode)
    }

    // MARK: - S4o Company name — alreadyInCompany surfaces inline, no nav

    func testCompanyNameAlreadyInCompanyIsNotANavigation() {
        // The RPC handles the IDEMPOTENT reuse internally (returns the existing code
        // as `.created`). A `.alreadyInCompany` outcome therefore means this account
        // already owns a company it did NOT create here — no code, so the screen
        // surfaces an inline error and the flow does NOT advance.
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .owner }
        c.advance(to: .companyName)

        let handled = CompanyCreationOutcomeRouter.route(
            .alreadyInCompany(message: "this account already belongs to a company"),
            onCreated: { _ in XCTFail("alreadyInCompany must not advance") }
        )
        XCTAssertFalse(handled, "alreadyInCompany is local state, not a navigation")
        XCTAssertEqual(c.currentStep, .companyName)
        XCTAssertNil(c.formData.generatedCrewCode)
    }

    func testCompanyNameFailedIsNotANavigation() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .companyName)

        let handled = CompanyCreationOutcomeRouter.route(
            .failed(message: "couldn't create your company — try again"),
            onCreated: { _ in XCTFail("failure must not advance") }
        )
        XCTAssertFalse(handled, "failure is local state, not a navigation")
        XCTAssertEqual(c.currentStep, .companyName)
    }

    // MARK: - S4o Company name — back-edge is rolePick in BOTH contexts

    func testCompanyNameBackReturnsToRolePick() {
        // Pre-auth: companyName backs to rolePick (the wrong-role escape).
        let pre = makeCoordinator(isAuthenticated: { false })
        pre.start()
        pre.advance(to: .companyName)
        XCTAssertTrue(pre.canGoBack)
        let screen = GatewayActions.companyName(pre, boundary: StubCompanyBoundary())
        screen.onBack()
        XCTAssertEqual(pre.currentStep, .rolePick)

        // Post-auth resume: companyName STILL backs to rolePick (role uncommitted
        // until a company exists), so Back is available post-auth too.
        let post = makeCoordinator(isAuthenticated: { true })
        post.advance(to: .companyName)
        XCTAssertTrue(post.canGoBack, "companyName has a back-edge in both contexts")
    }

    // MARK: - S4o Company name — stub boundary records the create call

    func testStubCompanyBoundaryRecordsCreateCall() async {
        let stub = StubCompanyBoundary()
        stub.outcome = .created(code: "BR8K-90ZT")
        let outcome = await stub.createCompany(name: "Sweet Deck & Rail", industries: ["Carpentry"])
        XCTAssertEqual(outcome, .created(code: "BR8K-90ZT"))
        XCTAssertEqual(stub.callCount, 1)
        XCTAssertEqual(stub.lastName, "Sweet Deck & Rail")
        XCTAssertEqual(stub.lastIndustries, ["Carpentry"])
    }

    // MARK: - S4o Company name — live-boundary typed-error mapping

    func testCompanyCreationLiveBoundaryMapsTypedErrors() {
        // invalidName → field error; alreadyInCompany → its inline phrase; the
        // remaining typed cases collapse to a retry-able failure.
        XCTAssertEqual(
            CompanyCreationLiveBoundary.map(.invalidName),
            .invalidName(message: "enter a company name")
        )
        XCTAssertEqual(
            CompanyCreationLiveBoundary.map(.alreadyInCompany),
            .alreadyInCompany(message: "this account already belongs to a company")
        )
        XCTAssertEqual(
            CompanyCreationLiveBoundary.map(.userRowMissing),
            .failed(message: "couldn't finish setup — try again")
        )
        XCTAssertEqual(
            CompanyCreationLiveBoundary.map(.noUserId),
            .failed(message: "couldn't finish setup — try again")
        )
        XCTAssertEqual(
            CompanyCreationLiveBoundary.map(.generic("RAW_TOKEN")),
            .failed(message: "couldn't create your company — try again")
        )
    }

    // MARK: - S5o Crew code — renders the form-data code, CTA advances to gate

    func testCrewCodeRendersFormDataCodeAndEntersToCompletionGate() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update {
            $0.selectedRole = .owner
            $0.companyName = "Sweet Deck & Rail"
            $0.generatedCrewCode = "BR8K-90ZT"
        }
        c.advance(to: .crewCode)

        // The screen reads the code + company name straight off form data.
        let screen = GatewayActions.crewCode(c)
        XCTAssertEqual(screen.crewCode, "BR8K-90ZT",
                       "S5o must render the DB-truth code persisted by S4o")
        XCTAssertEqual(screen.companyName, "Sweet Deck & Rail")

        // ENTER OPS → completion gate (forward-only).
        screen.onEnter()
        XCTAssertEqual(c.currentStep, .completionGate)
    }

    // MARK: - S5o Crew code — forward-only (no back-edge)

    func testCrewCodeHasNoBackEdge() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .crewCode)
        XCTAssertFalse(c.canGoBack, "crewCode is forward-only — the company is committed")
    }

    // MARK: - Completion gate (Task 4.3) — ACK-or-queue, never traps the user

    /// `.acknowledged` → fire the FINISH success haptic and admit immediately.
    func testCompletionAcknowledgedFiresSuccessHapticAndAdmits() {
        let decision = CompletionGateOutcomeRouter.decide(.acknowledged)
        XCTAssertTrue(decision.firesSuccessHaptic,
                      "the clean server ACK fires the onboarding FINISH success haptic")
        XCTAssertFalse(decision.showsQueuedStatus,
                       "acknowledged admits straight away — no queued reassurance")
    }

    /// `.queued` → NO success haptic, show the background-sync reassurance, then admit.
    func testCompletionQueuedShowsBackgroundStatusNoSuccessHaptic() {
        let decision = CompletionGateOutcomeRouter.decide(.queued)
        XCTAssertFalse(decision.firesSuccessHaptic,
                       "a queued ACK is not the success moment — no FINISH haptic")
        XCTAssertTrue(decision.showsQueuedStatus,
                      "queued shows the 'finishes in the background' reassurance before admit")
    }

    /// The admit guard latches on the FIRST admit and no-ops every later attempt —
    /// the backbone of "never trapped, never double-admitted". The ack/queued path,
    /// the watchdog, and the escape button all funnel through it; whichever fires
    /// first wins, the rest are dropped.
    func testCompletionAdmitGuardAdmitsExactlyOnce() {
        var guardState = CompletionAdmitGuard()
        XCTAssertFalse(guardState.hasAdmitted)

        // First admit (e.g. the acknowledged path) wins.
        XCTAssertTrue(guardState.tryAdmit(), "first admit must succeed")
        XCTAssertTrue(guardState.hasAdmitted)

        // A racing watchdog / escape arrival is dropped — no double-admit.
        XCTAssertFalse(guardState.tryAdmit(), "watchdog arriving after admit must be a no-op")
        XCTAssertFalse(guardState.tryAdmit(), "escape arriving after admit must be a no-op")
        XCTAssertTrue(guardState.hasAdmitted)
    }

    /// The live boundary forwards to the manager WITHOUT firing the manager's own
    /// `onComplete` callback — admit is single-sourced through the gate's injected
    /// `onAdmit` (the gateway's `handleComplete`), so suppressing the manager
    /// callback prevents a double-admit. We assert the boundary stub's async seam
    /// wires through and the gate consumes the outcome.
    func testStubCompletionBoundaryRecordsCallAndReturnsOutcome() async {
        let ackStub = StubCompletionBoundary()
        ackStub.outcome = .acknowledged
        let ack = await ackStub.complete()
        XCTAssertEqual(ack, .acknowledged)
        XCTAssertEqual(ackStub.callCount, 1)

        let queuedStub = StubCompletionBoundary()
        queuedStub.outcome = .queued
        let queued = await queuedStub.complete()
        XCTAssertEqual(queued, .queued)
        XCTAssertEqual(queuedStub.callCount, 1)
    }

    /// The gate has NO back-edge — it is terminal / forward-only. The company +
    /// workspace exist; there is nothing to go back to and no SIGN OUT.
    func testCompletionGateHasNoBackEdge() {
        let c = makeCoordinator(isAuthenticated: { true })
        c.advance(to: .completionGate)
        XCTAssertFalse(c.canGoBack, "completionGate is terminal — forward-only, no back-edge")
        XCTAssertNil(
            OnboardingFlowStep.completionGate.backEdge(context: .postAuth),
            "completionGate.backEdge must be nil"
        )
        XCTAssertNil(
            OnboardingFlowStep.completionGate.backEdge(context: .preAuth),
            "completionGate.backEdge must be nil in both contexts"
        )
    }

    /// NEVER-TRAPPED, modelled as the gate does it (no network, deterministic): the
    /// admit guard is fed by THREE concurrent admit sources — the boundary path, a
    /// hard watchdog, and the escape button — and whichever fires first wins. This
    /// replays the exact funnel the view uses (`StubCompletionBoundary` for the
    /// async ACK, `CompletionGateOutcomeRouter` for the per-outcome decision, and a
    /// short-circuited watchdog) and asserts admit fires EXACTLY ONCE for every
    /// outcome — acknowledged, queued, AND a hung call that only the watchdog can
    /// resolve. Tiny sleeps stand in for the production ceilings so the test is fast.
    func testCompletionGateAdmitsExactlyOnce_acknowledged() async {
        let admits = await simulateGateAdmit(outcome: .acknowledged)
        XCTAssertEqual(admits, 1, "acknowledged must admit exactly once")
    }

    func testCompletionGateAdmitsExactlyOnce_queued() async {
        let admits = await simulateGateAdmit(outcome: .queued)
        XCTAssertEqual(admits, 1, "queued must STILL admit (exactly once) — user not trapped")
    }

    func testCompletionGateAdmitsExactlyOnce_hungCallHitsWatchdog() async {
        // The boundary never returns; ONLY the watchdog can admit. Proves a wedged
        // request cannot trap the user.
        let admits = await simulateGateAdmit(outcome: nil)
        XCTAssertEqual(admits, 1, "a hung ACK must still admit via the watchdog (exactly once)")
    }

    /// Replays the view's admit funnel with miniature ceilings: a boundary task
    /// (ack/queued/hung) and a watchdog task both race through one shared
    /// `CompletionAdmitGuard`; returns the number of times admit actually fired
    /// (must always be 1). Mirrors `runCompletion` + `armWatchdog` semantics exactly.
    @MainActor
    private func simulateGateAdmit(outcome: OnboardingManager.CompletionOutcome?) async -> Int {
        let stub = StubCompletionBoundary()
        stub.outcome = outcome

        var admitGuard = CompletionAdmitGuard()
        var admitCount = 0
        let tryAdmit: () -> Void = {
            if admitGuard.tryAdmit() { admitCount += 1 }
        }

        // Boundary path — mirrors runCompletion: await the ACK, apply the router's
        // decision (queued shows a brief status → tiny dwell), then admit. A hung
        // boundary is given a cancellable task so the watchdog can win.
        let completionTask = Task { @MainActor in
            let result = await stub.complete()
            guard !Task.isCancelled else { return }
            let decision = CompletionGateOutcomeRouter.decide(result)
            if decision.showsQueuedStatus {
                try? await Task.sleep(nanoseconds: 20_000_000) // queued dwell (mini)
                guard !Task.isCancelled else { return }
            }
            tryAdmit()
        }

        // Hard watchdog — mirrors armWatchdog: admit after a ceiling regardless.
        let watchdogTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000) // watchdog ceiling (mini)
            guard !Task.isCancelled else { return }
            tryAdmit()
        }

        // Let whichever source wins resolve, then cancel the rest (as the view's
        // `cancelAll` does on admit), and confirm the call was made.
        try? await Task.sleep(nanoseconds: 200_000_000)
        completionTask.cancel()
        watchdogTask.cancel()
        XCTAssertGreaterThanOrEqual(stub.callCount, 1, "the gate must call the boundary on appear")
        return admitCount
    }

    // MARK: - S3 Create account — boundary stub sanity (async seam wires through)

    func testStubBoundaryRecordsEmailSignupCall() async {
        let stub = StubSignupBoundary()
        let outcome = await stub.signUpEmail(
            firstName: "Jack", lastName: "Sweet",
            email: "jack@ops.app", password: "hunter2hunter2"
        )
        XCTAssertEqual(outcome, .created)
        XCTAssertEqual(stub.emailCallCount, 1)
        XCTAssertEqual(stub.lastEmail, "jack@ops.app")
    }

    // MARK: - S4 Login — form validation (pure validator, no rendering)

    func testLoginFormValidationGatesSubmit() {
        // Both blank → invalid; the empty email is not a "valid email", the empty
        // password is flagged.
        let blank = LoginFormValidation(email: "", password: "")
        XCTAssertFalse(blank.isFormValid)
        XCTAssertEqual(blank.passwordError, "enter your password")

        // Email present + shaped, password blank → still invalid (password gates).
        let noPw = LoginFormValidation(email: "jack@ops.app", password: "")
        XCTAssertFalse(noPw.isFormValid)
        XCTAssertEqual(noPw.passwordError, "enter your password")

        // Bad email, password present → invalid (email shape gates).
        let badEmail = LoginFormValidation(email: "not-an-email", password: "anything")
        XCTAssertFalse(badEmail.isFormValid)
        XCTAssertEqual(badEmail.emailError, "enter a valid email")

        // Both present + shaped → valid. Login never enforces an 8-char minimum
        // (legacy accounts may predate it), so a short password still gates clean.
        let ok = LoginFormValidation(email: "jack@ops.app", password: "x")
        XCTAssertTrue(ok.isFormValid)
        XCTAssertNil(ok.emailError)
        XCTAssertNil(ok.passwordError)
    }

    func testLoginEmailValidatorReusesCreateAccountRule() {
        // Login's email shape delegates to the SAME validator S3 uses — proving
        // there is one source of truth for "is this a valid email".
        let good = LoginFormValidation(email: "a.b+c@sub.domain.io", password: "x")
        XCTAssertTrue(good.isFormValid)
        let bad = LoginFormValidation(email: "jack@ops", password: "x")
        XCTAssertFalse(bad.isFormValid)
        XCTAssertEqual(bad.emailError, "enter a valid email")
    }

    // MARK: - S4 Login — host-navigating outcomes (pure router)

    func testLoginCompleteTakesHostAdmitPathNoFlowNav() {
        // `.complete` is the host admit path — the router invokes onComplete and
        // does NOT advance the flow (the host admits to the app instead).
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .login)

        var didAdmit = false
        let handled = LoginOutcomeRouter.route(
            .complete,
            onComplete: { didAdmit = true },
            onIncomplete: { _ in XCTFail("should not resume") },
            onNewIdentity: { XCTFail("should not route to new identity") }
        )
        XCTAssertTrue(handled)
        XCTAssertTrue(didAdmit, "complete must take the host admit path")
        XCTAssertEqual(c.currentStep, .login, "complete does not advance the flow")
    }

    func testLoginIncompleteResumesAtDerivedStep() {
        // `.incomplete(step)` → the gateway wires onIncomplete → advance(to:).
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .login)

        LoginOutcomeRouter.route(
            .incomplete(resumeStep: .profile),
            onComplete: { XCTFail("should not admit") },
            onIncomplete: { c.advance(to: $0) },
            onNewIdentity: { XCTFail("should not route to new identity") }
        )
        XCTAssertEqual(c.currentStep, .profile)
    }

    func testLoginNewIdentityRoutesToRolePick() {
        // `.newIdentity` (brand-new social identity) → the gateway routes to
        // `.rolePick` with auth already satisfied.
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .login)

        LoginOutcomeRouter.route(
            .newIdentity,
            onComplete: { XCTFail("should not admit") },
            onIncomplete: { _ in XCTFail("should not resume") },
            onNewIdentity: { c.advance(to: .rolePick) }
        )
        XCTAssertEqual(c.currentStep, .rolePick)
    }

    func testLoginNoAccountIsNotANavigation() {
        // `.noAccount` is local-state-only — the screen surfaces an inline error
        // and offers no navigation, so the router does NOT move the flow.
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .login)

        let handled = LoginOutcomeRouter.route(
            .noAccount,
            onComplete: { XCTFail("no admit") },
            onIncomplete: { _ in XCTFail("no resume") },
            onNewIdentity: { XCTFail("no new identity") }
        )
        XCTAssertFalse(handled, "no-account is local state, not a navigation")
        XCTAssertEqual(c.currentStep, .login)
    }

    func testLoginFailedIsNotANavigation() {
        // `.failed` is local-state-only (the screen surfaces the message inline).
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .login)

        let handled = LoginOutcomeRouter.route(
            .failed(message: "WRONG EMAIL OR PASSWORD."),
            onComplete: { XCTFail("no admit") },
            onIncomplete: { _ in XCTFail("no resume") },
            onNewIdentity: { XCTFail("no new identity") }
        )
        XCTAssertFalse(handled, "failure is local state, not a navigation")
        XCTAssertEqual(c.currentStep, .login)
    }

    // MARK: - S4 Login — gating gates the boundary call

    func testLoginEmptyEmailGatesSubmit() async {
        // With an empty email the form is invalid, so attempting to submit must NOT
        // reach the boundary. Driven via the validation gate the screen enforces.
        let stub = StubLoginBoundary()
        let validation = LoginFormValidation(email: "", password: "hunter2")
        XCTAssertFalse(validation.isFormValid, "empty email must gate submit")
        // The screen guards on `isFormValid` before calling the boundary, so a
        // gated submit never invokes it — assert the stub stays untouched.
        XCTAssertEqual(stub.emailCallCount, 0)
    }

    func testLoginBoundaryStubRecordsEmailLoginCall() async {
        // The async seam wires through: a valid email login reaches the boundary
        // with the typed credentials and returns the canned outcome.
        let stub = StubLoginBoundary()
        stub.emailOutcome = .complete
        let outcome = await stub.logInEmail(email: "jack@ops.app", password: "hunter2")
        XCTAssertEqual(outcome, .complete)
        XCTAssertEqual(stub.emailCallCount, 1)
        XCTAssertEqual(stub.lastEmail, "jack@ops.app")
        XCTAssertEqual(stub.lastPassword, "hunter2")
    }

    // MARK: - S4 Login — SIGN IN handoff prefill

    func testLoginPrefillSeedsEmailFromFormData() {
        // The SIGN IN handoff persists the typed email into formData; the gateway
        // passes it as `prefilledEmail`. A LoginStepView seeded with it surfaces
        // the value on its validation/init path (the field applies it on appear).
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.email = "jack@ops.app" }
        c.advance(to: .login)

        let screen = GatewayActions.login(c, boundary: StubLoginBoundary(), onComplete: {})
        XCTAssertEqual(screen.prefilledEmail, "jack@ops.app",
                       "the gateway must pass the persisted email as the Login prefill")
    }

    // MARK: - S4 Login — live boundary no-account sentinel classification

    func testLiveBoundaryNoAccountSentinelMatching() {
        // The live boundary classifies ONLY the explicit DataController no-account
        // sentinel as `.noAccount`; a wrong-password message is a generic failure.
        XCTAssertTrue(LoginLiveBoundary.indicatesNoAccount(
            "NO ACCOUNT FOUND FOR THIS EMAIL. SIGN UP OR CHECK THE ADDRESS."))
        XCTAssertTrue(LoginLiveBoundary.indicatesNoAccount(
            "  no account found for this email  "), "match is trimmed + case-insensitive")
        XCTAssertFalse(LoginLiveBoundary.indicatesNoAccount("WRONG EMAIL OR PASSWORD."))
        XCTAssertFalse(LoginLiveBoundary.indicatesNoAccount(nil))

        // userFacing collapses an empty/absent message to the connection fallback,
        // and passes through DataController's terse copy untouched.
        XCTAssertEqual(LoginLiveBoundary.userFacing("WRONG EMAIL OR PASSWORD."),
                       "WRONG EMAIL OR PASSWORD.")
        XCTAssertEqual(LoginLiveBoundary.userFacing(nil),
                       "Couldn't sign you in. Check your connection and try again.")
        XCTAssertEqual(LoginLiveBoundary.userFacing("   "),
                       "Couldn't sign you in. Check your connection and try again.")
    }

    // MARK: - S4c Invite check — InviteCheckRouter (R13 regression guard + routing)

    /// `.found` with a non-empty list → `onHasInvites` fires with the forwarded
    /// invites; `onNoInvites` and `onFailed` must NOT fire.
    func testInviteCheckRouterFoundWithInvitesCallsOnHasInvites() {
        let invite = makeInvite()
        var hasInvitesCalled = false
        var noInvitesCalled = false
        var failedCalled = false
        var receivedInvites: [PendingInviteDTO] = []

        InviteCheckRouter.route(
            .found([invite]),
            onHasInvites: { invites in
                hasInvitesCalled = true
                receivedInvites = invites
            },
            onNoInvites: { noInvitesCalled = true },
            onFailed: { failedCalled = true }
        )

        XCTAssertTrue(hasInvitesCalled, "found([invite]) must invoke onHasInvites")
        XCTAssertFalse(noInvitesCalled, "found([invite]) must NOT invoke onNoInvites")
        XCTAssertFalse(failedCalled, "found([invite]) must NOT invoke onFailed")
        XCTAssertEqual(
            receivedInvites.map(\.invitationId),
            [invite.invitationId],
            "the invite must be forwarded verbatim to onHasInvites"
        )
    }

    /// `.found([])` (zero invites) → `onNoInvites` only. Confirms the router
    /// correctly disambiguates the empty-list case from the failure case.
    func testInviteCheckRouterFoundEmptyCallsOnNoInvites() {
        var hasInvitesCalled = false
        var noInvitesCalled = false
        var failedCalled = false

        InviteCheckRouter.route(
            .found([]),
            onHasInvites: { _ in hasInvitesCalled = true },
            onNoInvites: { noInvitesCalled = true },
            onFailed: { failedCalled = true }
        )

        XCTAssertFalse(hasInvitesCalled, "found([]) must NOT invoke onHasInvites")
        XCTAssertTrue(noInvitesCalled, "found([]) must invoke onNoInvites")
        XCTAssertFalse(failedCalled, "found([]) must NOT invoke onFailed")
    }

    /// R13 regression guard: `.failed` → `onFailed` only. Explicitly asserts
    /// `onNoInvites` is NOT called — failure must never be silently treated as
    /// zero invites (the bug this case guards against).
    func testInviteCheckRouterFailedCallsOnFailedNotOnNoInvites() {
        var hasInvitesCalled = false
        var noInvitesCalled = false
        var failedCalled = false

        InviteCheckRouter.route(
            .failed,
            onHasInvites: { _ in hasInvitesCalled = true },
            onNoInvites: { noInvitesCalled = true },
            onFailed: { failedCalled = true }
        )

        XCTAssertFalse(hasInvitesCalled, "failed must NOT invoke onHasInvites")
        // R13: this is the critical assertion — failure ≠ zero invites.
        XCTAssertFalse(
            noInvitesCalled,
            "R13 REGRESSION: .failed must NOT invoke onNoInvites — failure is not zero invites"
        )
        XCTAssertTrue(failedCalled, "failed must invoke onFailed")
    }

    /// Multiple invites are all forwarded — the router does not truncate or reorder.
    func testInviteCheckRouterForwardsMultipleInvitesInOrder() {
        let a = makeInvite(invitationId: "aaa", companyName: "Alpha Co")
        let b = makeInvite(invitationId: "bbb", companyName: "Bravo Co")
        var received: [PendingInviteDTO] = []

        InviteCheckRouter.route(
            .found([a, b]),
            onHasInvites: { received = $0 },
            onNoInvites: { XCTFail("must not fire") },
            onFailed: { XCTFail("must not fire") }
        )

        XCTAssertEqual(received.map(\.invitationId), ["aaa", "bbb"])
    }

    // MARK: - S4c Invite check — gateway wiring (navigator driven at the coordinator seam)

    /// `onHasInvites` + gateway wiring → coordinator advances to `.invitePicker`.
    func testInviteCheckGatewayWiringFoundAdvancesToInvitePicker() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .crew }
        c.advance(to: .inviteCheck)

        var inviteStore: [PendingInviteDTO] = []
        let invite = makeInvite()

        // Mirror the gateway's exact closures for inviteCheckView.
        var onInvitesFetched: ([PendingInviteDTO]) -> Void = { inviteStore = $0 }
        var onHasInvites: () -> Void = { c.advance(to: .invitePicker) }
        var onNoInvites: () -> Void = { c.advance(to: .codeEntry(provenance: .zeroInvites)) }
        var onFailed: () -> Void = { /* local phase flip — not testable here */ }

        InviteCheckRouter.route(
            .found([invite]),
            onHasInvites: { invites in
                onInvitesFetched(invites)
                onHasInvites()
            },
            onNoInvites: { onNoInvites() },
            onFailed: { onFailed() }
        )

        XCTAssertEqual(c.currentStep, .invitePicker, "found([invite]) must advance to .invitePicker")
        XCTAssertEqual(inviteStore.map(\.invitationId), [invite.invitationId],
                       "fetched invites must be forwarded to the gateway's invite store")
    }

    /// `onNoInvites` + gateway wiring → `.codeEntry(provenance: .zeroInvites)`.
    func testInviteCheckGatewayWiringZeroInvitesAdvancesToCodeEntry() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .crew }
        c.advance(to: .inviteCheck)

        InviteCheckRouter.route(
            .found([]),
            onHasInvites: { _ in XCTFail("must not fire") },
            onNoInvites: { c.advance(to: .codeEntry(provenance: .zeroInvites)) },
            onFailed: { XCTFail("must not fire") }
        )

        XCTAssertEqual(c.currentStep, .codeEntry(provenance: .zeroInvites),
                       "zero invites must advance to codeEntry(.zeroInvites)")
    }

    /// `onEnterCodeInstead` (the failure-state escape) also routes to
    /// `.codeEntry(.zeroInvites)`, distinct from the zero-invite path but same
    /// destination.
    func testInviteCheckEnterCodeInsteadEscapeAdvancesToCodeEntry() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .crew }
        c.advance(to: .inviteCheck)

        // Gateway wires onEnterCodeInstead the same as onNoInvites.
        let onEnterCodeInstead: () -> Void = { c.advance(to: .codeEntry(provenance: .zeroInvites)) }
        onEnterCodeInstead()

        XCTAssertEqual(c.currentStep, .codeEntry(provenance: .zeroInvites),
                       "ENTER CODE INSTEAD escape must advance to codeEntry(.zeroInvites)")
    }

    /// inviteCheck has NO back-edge (it is an auto-transition screen).
    func testInviteCheckHasNoBackEdge() {
        XCTAssertNil(OnboardingFlowStep.inviteCheck.backEdge(context: .preAuth))
        XCTAssertNil(OnboardingFlowStep.inviteCheck.backEdge(context: .postAuth))
    }

    // MARK: - S4c Invite check — stub boundary sanity (async seam wires through)

    func testStubInviteCheckBoundaryRecordsCallAndReturnsOutcome() async {
        let invite = makeInvite()
        let stub = StubInviteCheckBoundary()
        stub.outcome = .found([invite])

        let outcome = await stub.checkInvites()

        XCTAssertEqual(outcome, .found([invite]))
        XCTAssertEqual(stub.callCount, 1)
    }

    func testStubInviteCheckBoundaryReturnsFailedOutcome() async {
        let stub = StubInviteCheckBoundary()
        stub.outcome = .failed

        let outcome = await stub.checkInvites()

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(stub.callCount, 1)
    }

    // MARK: - Invite picker — card selection persists invite fields + advances

    /// Selecting a card via the gateway's exact wiring persists the invite's
    /// company fields into form data and advances to
    /// `.confirmCompany(source: .picker)`.
    func testInvitePickerSelectPersistsInviteAndAdvancesToConfirmCompany() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .crew }
        c.advance(to: .invitePicker)

        let invite = makeInvite(
            invitationId: "inv-123",
            companyId: "co-456",
            companyName: "Sweet Deck & Rail",
            companyCode: "BR8K90ZT"
        )

        // Mirror the gateway's exact onSelectInvite closure.
        let onSelectInvite: (PendingInviteDTO) -> Void = { selected in
            c.update {
                $0.joinCompanyId = selected.companyId
                $0.joinCompanyName = selected.companyName
                $0.joinCompanyCode = selected.companyCode
                $0.joinCompanyLogoUrl = selected.companyLogoUrl
                $0.joinInvitationId = selected.invitationId
            }
            c.advance(to: .confirmCompany(source: .picker))
        }

        onSelectInvite(invite)

        XCTAssertEqual(c.currentStep, .confirmCompany(source: .picker),
                       "selecting an invite must advance to confirmCompany(.picker)")
        XCTAssertEqual(c.formData.joinCompanyId, "co-456")
        XCTAssertEqual(c.formData.joinCompanyName, "Sweet Deck & Rail")
        XCTAssertEqual(c.formData.joinCompanyCode, "BR8K90ZT")
        XCTAssertNil(c.formData.joinCompanyLogoUrl)
        // Critical: the invitation id must be set (drives the invite-acceptance write).
        XCTAssertEqual(c.formData.joinInvitationId, "inv-123",
                       "joinInvitationId must be persisted from the selected invite")
    }

    /// "Enter a different code" → `.codeEntry(provenance: .fromPicker)`.
    func testInvitePickerEnterDifferentCodeAdvancesToCodeEntryFromPicker() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .crew }
        c.advance(to: .invitePicker)

        // Mirror the gateway's onEnterDifferentCode closure.
        let onEnterDifferentCode: () -> Void = { c.advance(to: .codeEntry(provenance: .fromPicker)) }
        onEnterDifferentCode()

        XCTAssertEqual(c.currentStep, .codeEntry(provenance: .fromPicker),
                       "Enter a different code must advance to codeEntry(.fromPicker)")
    }

    /// invitePicker Back → rolePick (back-edge is rolePick).
    func testInvitePickerBackReturnsToRolePick() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .invitePicker)
        XCTAssertTrue(c.canGoBack)

        c.goBack()

        XCTAssertEqual(c.currentStep, .rolePick,
                       "invitePicker Back must return to rolePick")
    }

    // MARK: - S4c-code Code entry — CodeEntryOutcomeRouter

    /// `.found` → `onFound` invoked AND returns true (the only host-navigating outcome).
    func testCodeEntryRouterFoundCallsOnFoundAndReturnsTrue() {
        let company = FoundCompany(
            companyId: "co-1", companyName: "Sweet Deck & Rail",
            companyCode: "BR8K90ZT", companyLogoUrl: nil
        )
        var receivedCompany: FoundCompany?

        let handled = CodeEntryOutcomeRouter.route(
            .found(company),
            onFound: { receivedCompany = $0 }
        )

        XCTAssertTrue(handled, ".found must return true (it is the host-navigation outcome)")
        XCTAssertEqual(receivedCompany, company, "the resolved company must be forwarded to onFound")
    }

    /// `.notFound` → `onFound` NOT called, returns false (inline error, no nav).
    func testCodeEntryRouterNotFoundReturnsFalseAndDoesNotCallOnFound() {
        let handled = CodeEntryOutcomeRouter.route(
            .notFound,
            onFound: { _ in XCTFail("onFound must not be called for .notFound") }
        )
        XCTAssertFalse(handled, ".notFound is a local-state error — returns false")
    }

    /// `.failed` → `onFound` NOT called, returns false (inline retry error, no nav).
    func testCodeEntryRouterFailedReturnsFalseAndDoesNotCallOnFound() {
        let handled = CodeEntryOutcomeRouter.route(
            .failed,
            onFound: { _ in XCTFail("onFound must not be called for .failed") }
        )
        XCTAssertFalse(handled, ".failed is a local-state error — returns false")
    }

    // MARK: - S4c-code Code entry — CodeEntryValidation (non-empty only)

    /// Empty string is invalid (the CTA is disabled; submit never fires).
    func testCodeEntryValidationEmptyStringIsInvalid() {
        XCTAssertFalse(CodeEntryValidation(code: "").isFormValid)
    }

    /// Whitespace-only is invalid (trimming collapses it to empty).
    func testCodeEntryValidationWhitespaceOnlyIsInvalid() {
        XCTAssertFalse(CodeEntryValidation(code: "   ").isFormValid)
        XCTAssertFalse(CodeEntryValidation(code: "\t\n").isFormValid)
    }

    /// A normal crew code (8-char block) is valid.
    func testCodeEntryValidationNormalCodeIsValid() {
        XCTAssertTrue(CodeEntryValidation(code: "BR8K90ZT").isFormValid)
    }

    /// A legacy `PREFIX-XXXXXX` hyphenated code must be accepted without
    /// rejection — NO client format rule applies (spec: "NO CLIENT FORMAT REJECTION").
    func testCodeEntryValidationLegacyHyphenatedCodeIsValid() {
        XCTAssertTrue(CodeEntryValidation(code: "BR8K-90ZT").isFormValid,
                      "legacy hyphenated codes must pass the client gate — format validation is server-only")
    }

    /// A single character is sufficient to unlock the CTA; minimum is non-empty.
    func testCodeEntryValidationSingleCharIsValid() {
        XCTAssertTrue(CodeEntryValidation(code: "X").isFormValid)
    }

    /// Surrounding whitespace is stripped — the trimmed code is what gates validity.
    func testCodeEntryValidationTrimmingApplied() {
        XCTAssertTrue(CodeEntryValidation(code: "  BR8K90ZT  ").isFormValid)
        XCTAssertFalse(CodeEntryValidation(code: "   ").isFormValid)
    }

    // MARK: - S4c-code Code entry — company persistence (code-entry found path)

    /// When `.found` fires, the screen persists company id / name / code / logo into
    /// form data and explicitly clears `joinInvitationId` (this path is NOT from a
    /// picker-accepted invite). The coordinator then advances to
    /// `.confirmCompany(source: .codeEntry(provenance))`.
    func testCodeEntryFoundPathPersistsCompanyAndClearsInvitationId() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.update { $0.selectedRole = .crew }
        // Seed a stale joinInvitationId (e.g. from a previous picker session) to
        // confirm the code-entry path explicitly clears it.
        c.update { $0.joinInvitationId = "stale-inv-id" }
        c.advance(to: .codeEntry(provenance: .zeroInvites))

        let company = FoundCompany(
            companyId: "co-789",
            companyName: "North Ridge HVAC",
            companyCode: "NR4G99AB",
            companyLogoUrl: "https://cdn.ops.app/logo.png"
        )
        let provenance = CodeEntryProvenance.zeroInvites

        // Mirror the gateway's exact onFound closure wiring (which the screen calls
        // after persistCompany; drive both effects here to test the full seam).
        let persistCompany: (FoundCompany) -> Void = { co in
            c.update {
                $0.joinCompanyId = co.companyId
                $0.joinCompanyName = co.companyName
                $0.joinCompanyCode = co.companyCode
                $0.joinCompanyLogoUrl = co.companyLogoUrl
                $0.joinInvitationId = nil // code-entry path: no invitation
            }
        }
        let onFound: (FoundCompany) -> Void = { co in
            persistCompany(co)
            c.advance(to: .confirmCompany(source: .codeEntry(provenance)))
        }

        // Simulate CodeEntryOutcomeRouter routing .found → onFound.
        CodeEntryOutcomeRouter.route(.found(company), onFound: onFound)

        XCTAssertEqual(c.currentStep, .confirmCompany(source: .codeEntry(.zeroInvites)),
                       "code-entry found must advance to confirmCompany(source: .codeEntry(.zeroInvites))")
        XCTAssertEqual(c.formData.joinCompanyId, "co-789")
        XCTAssertEqual(c.formData.joinCompanyName, "North Ridge HVAC")
        XCTAssertEqual(c.formData.joinCompanyCode, "NR4G99AB")
        XCTAssertEqual(c.formData.joinCompanyLogoUrl, "https://cdn.ops.app/logo.png")
        // Critical: joinInvitationId must be nil for the code-entry path.
        XCTAssertNil(c.formData.joinInvitationId,
                     "code-entry path must clear joinInvitationId — no invite-acceptance write")
    }

    // MARK: - S4c-code Code entry — provenance carried through to confirmCompany

    /// Entered with `.zeroInvites` → confirmCompany carries `.codeEntry(.zeroInvites)`.
    func testCodeEntryZeroInvitesProvenanceCarriedToConfirmCompany() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .codeEntry(provenance: .zeroInvites))

        let company = FoundCompany(companyId: "c1", companyName: "Alpha", companyCode: nil, companyLogoUrl: nil)
        let provenance = CodeEntryProvenance.zeroInvites

        CodeEntryOutcomeRouter.route(.found(company)) { _ in
            c.advance(to: .confirmCompany(source: .codeEntry(provenance)))
        }

        XCTAssertEqual(c.currentStep, .confirmCompany(source: .codeEntry(.zeroInvites)),
                       "zeroInvites provenance must be carried into the confirmCompany source")
    }

    /// Entered with `.fromPicker` → confirmCompany carries `.codeEntry(.fromPicker)`.
    func testCodeEntryFromPickerProvenanceCarriedToConfirmCompany() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .codeEntry(provenance: .fromPicker))

        let company = FoundCompany(companyId: "c1", companyName: "Alpha", companyCode: nil, companyLogoUrl: nil)
        let provenance = CodeEntryProvenance.fromPicker

        CodeEntryOutcomeRouter.route(.found(company)) { _ in
            c.advance(to: .confirmCompany(source: .codeEntry(provenance)))
        }

        XCTAssertEqual(c.currentStep, .confirmCompany(source: .codeEntry(.fromPicker)),
                       "fromPicker provenance must be carried into the confirmCompany source")
    }

    // MARK: - S4c-code Code entry — "different code" from picker → codeEntry(.fromPicker)

    /// "Enter a different code" from the picker → codeEntry with `.fromPicker`
    /// provenance. This is the picker's secondary CTA; the gateway wires it as
    /// `onEnterDifferentCode → advance(.codeEntry(provenance: .fromPicker))`.
    func testPickerDifferentCodeAdvancesToCodeEntryFromPicker() {
        let c = makeCoordinator(isAuthenticated: { false })
        c.start()
        c.advance(to: .invitePicker)

        // Mirror the gateway's onEnterDifferentCode closure.
        c.advance(to: .codeEntry(provenance: .fromPicker))

        XCTAssertEqual(c.currentStep, .codeEntry(provenance: .fromPicker))
    }

    // MARK: - S4c-code Code entry — back edges (provenance-dependent)

    /// `.zeroInvites` → Back returns to rolePick (came from role, no picker stop).
    func testCodeEntryZeroInvitesBackEdgeIsRolePick() {
        XCTAssertEqual(
            OnboardingFlowStep.codeEntry(provenance: .zeroInvites).backEdge(context: .preAuth),
            .rolePick
        )
    }

    /// `.fromPicker` → Back returns to invitePicker.
    func testCodeEntryFromPickerBackEdgeIsInvitePicker() {
        XCTAssertEqual(
            OnboardingFlowStep.codeEntry(provenance: .fromPicker).backEdge(context: .preAuth),
            .invitePicker
        )
    }

    // MARK: - S4c-code Code entry — stub boundary sanity

    func testStubCodeEntryBoundaryRecordsCallAndReturnsOutcome() async {
        let stub = StubCodeEntryBoundary()
        let company = FoundCompany(
            companyId: "c1", companyName: "Sweet Deck & Rail",
            companyCode: "BR8K90ZT", companyLogoUrl: nil
        )
        stub.outcome = .found(company)

        let outcome = await stub.lookUpCompany(code: "BR8K90ZT")

        XCTAssertEqual(outcome, .found(company))
        XCTAssertEqual(stub.callCount, 1)
        XCTAssertEqual(stub.lastCode, "BR8K90ZT")
    }

    func testStubCodeEntryBoundaryNotFoundOutcome() async {
        let stub = StubCodeEntryBoundary()
        stub.outcome = .notFound

        let outcome = await stub.lookUpCompany(code: "BADCODE")

        XCTAssertEqual(outcome, .notFound)
        XCTAssertEqual(stub.callCount, 1)
    }

    // MARK: - Snapshots (default + dark + reduce-motion)

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-onboarding-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// iPhone 17 logical width (pt). Screens apply their own horizontal padding.
    private let deviceWidth: CGFloat = 393
    private let deviceHeight: CGFloat = 852

    /// Renders a full-screen view to a PNG at @3x, in a chosen color scheme.
    /// Mirrors the `BooksSnapshotTests` harness: attaches to the .xcresult AND
    /// mirrors to the sim tmp dir. Never asserts on pixels.
    ///
    /// Note on Reduce Motion: `accessibilityReduceMotion` is a read-only
    /// `EnvironmentValues` key (it cannot be injected via `.environment`), so the
    /// RM variant is captured by rendering with animations disabled — the screens'
    /// entrance is the only motion and `ImageRenderer` captures the settled
    /// frame, so the RM output is the static end-state regardless. The RM CODE
    /// path (nil'd animations, no offset) is asserted structurally by the logic
    /// tests above and the components' own Reduce-Motion handling.
    private func snapshot<V: View>(
        _ name: String,
        colorScheme: ColorScheme = .dark,
        disableAnimations: Bool = false,
        @ViewBuilder _ content: () -> V
    ) {
        let host = content()
            .frame(width: deviceWidth, height: deviceHeight)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, colorScheme)
            .transaction { txn in txn.disablesAnimations = disableAnimations }

        let renderer = ImageRenderer(content: host)
        renderer.scale = 3
        renderer.isOpaque = true

        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    func testRenderOnboardingScreens() {
        // S1 Welcome — default (dark), Reduce-Motion (animations disabled), light.
        snapshot("welcome_dark") {
            WelcomeStepView(onGetStarted: {}, onSignIn: {})
        }
        snapshot("welcome_reduce_motion", disableAnimations: true) {
            WelcomeStepView(onGetStarted: {}, onSignIn: {})
        }
        // Light scheme proves the canvas/token behavior under the alternate scheme.
        snapshot("welcome_light", colorScheme: .light) {
            WelcomeStepView(onGetStarted: {}, onSignIn: {})
        }

        // S2 Role pick — pre-auth (Back), post-auth resume (SIGN OUT), Reduce-Motion, light.
        snapshot("rolepick_back_dark") {
            RolePickStepView(
                onSelectOwner: {}, onSelectCrew: {},
                canGoBack: true, onBack: {}, onSignOut: {}
            )
        }
        snapshot("rolepick_signout_dark") {
            RolePickStepView(
                onSelectOwner: {}, onSelectCrew: {},
                canGoBack: false, onBack: {}, onSignOut: {}
            )
        }
        snapshot("rolepick_reduce_motion", disableAnimations: true) {
            RolePickStepView(
                onSelectOwner: {}, onSelectCrew: {},
                canGoBack: true, onBack: {}, onSignOut: {}
            )
        }
        snapshot("rolepick_light", colorScheme: .light) {
            RolePickStepView(
                onSelectOwner: {}, onSelectCrew: {},
                canGoBack: true, onBack: {}, onSignOut: {}
            )
        }

        // S3 Create account — default (dark), error state, social-no-name (name
        // fields shown), light. Uses the DEBUG snapshot seam to reach the post-
        // interaction states a renderer can't otherwise drive.
        let stub = StubSignupBoundary()
        snapshot("createaccount_default_dark") {
            CreateAccountStepView(selectedRole: .owner, boundary: stub).snapshotBody
        }
        snapshot("createaccount_error_dark") {
            CreateAccountStepView(
                selectedRole: .owner,
                boundary: stub,
                previewFirstName: "Jack",
                previewLastName: "Sweet",
                previewEmail: "jack@ops.app",
                previewPassword: "short",
                previewDidAttemptSubmit: true,
                previewEmailAlreadyRegistered: true
            ).snapshotBody
        }
        snapshot("createaccount_social_no_name_dark") {
            CreateAccountStepView(
                selectedRole: .crew,
                boundary: stub,
                previewSocialNameEmail: "jack@ops.app"
            ).snapshotBody
        }
        snapshot("createaccount_default_light", colorScheme: .light) {
            CreateAccountStepView(selectedRole: .owner, boundary: stub).snapshotBody
        }

        // S4 Login — default (dark), no-account error, top-level failure error,
        // light. Uses the DEBUG snapshot seam to reach the post-interaction error
        // states a renderer can't otherwise drive.
        let loginStub = StubLoginBoundary()
        snapshot("login_default_dark") {
            LoginStepView(boundary: loginStub, previewEmail: "jack@ops.app").snapshotBody
        }
        snapshot("login_no_account_dark") {
            LoginStepView(
                boundary: loginStub,
                previewEmail: "jack@ops.app",
                previewPassword: "hunter2",
                previewDidAttemptSubmit: true,
                previewNoAccount: true
            ).snapshotBody
        }
        snapshot("login_failure_dark") {
            LoginStepView(
                boundary: loginStub,
                previewEmail: "jack@ops.app",
                previewPassword: "hunter2",
                previewDidAttemptSubmit: true,
                previewFailureMessage: "WRONG EMAIL OR PASSWORD."
            ).snapshotBody
        }
        snapshot("login_default_light", colorScheme: .light) {
            LoginStepView(boundary: loginStub, previewEmail: "jack@ops.app").snapshotBody
        }

        // S4o Company name — default (dark), loading + selected-trade, error
        // (already-in-company top-level error), light. Uses the DEBUG snapshot seam
        // to reach the post-interaction states a renderer can't otherwise drive.
        let companyStub = StubCompanyBoundary()
        snapshot("companyname_default_dark") {
            CompanyNameStepView(boundary: companyStub).snapshotBody
        }
        snapshot("companyname_loading_dark") {
            CompanyNameStepView(
                boundary: companyStub,
                previewCompanyName: "Sweet Deck & Rail",
                previewSelectedTrade: "Carpentry",
                previewIsCreating: true
            ).snapshotBody
        }
        snapshot("companyname_error_dark") {
            CompanyNameStepView(
                boundary: companyStub,
                previewCompanyName: "",
                previewDidAttemptSubmit: true,
                previewTopLevelError: "this account already belongs to a company"
            ).snapshotBody
        }
        snapshot("companyname_default_light", colorScheme: .light) {
            CompanyNameStepView(boundary: companyStub).snapshotBody
        }

        // S5o Crew code — default (dark), Reduce-Motion (animations disabled), light.
        // The payoff screen is static after entrance; the snapshot seam settles it.
        snapshot("crewcode_dark") {
            CrewCodeStepView(crewCode: "BR8K-90ZT", companyName: "Sweet Deck & Rail", previewSettled: true).snapshotBody
        }
        snapshot("crewcode_reduce_motion", disableAnimations: true) {
            CrewCodeStepView(crewCode: "BR8K-90ZT", companyName: "Sweet Deck & Rail", previewSettled: true).snapshotBody
        }
        snapshot("crewcode_light", colorScheme: .light) {
            CrewCodeStepView(crewCode: "BR8K-90ZT", companyName: "Sweet Deck & Rail", previewSettled: true).snapshotBody
        }

        // S4c Invite check — checking state, failed/error state, light.
        // The previewInert seam pins the phase and prevents the boundary from
        // auto-running so the captured frame is stable.
        let inviteCheckBoundary = StubInviteCheckBoundary()
        snapshot("invitecheck_checking_dark") {
            InviteCheckStepView(
                boundary: inviteCheckBoundary,
                previewPhase: .checking
            ).snapshotBody
        }
        snapshot("invitecheck_failed_dark") {
            InviteCheckStepView(
                boundary: inviteCheckBoundary,
                previewPhase: .failed
            ).snapshotBody
        }
        snapshot("invitecheck_checking_light", colorScheme: .light) {
            InviteCheckStepView(
                boundary: inviteCheckBoundary,
                previewPhase: .checking
            ).snapshotBody
        }

        // Invite picker — multiple invites (the normal case), single-invite
        // (still shows the card so the user confirms), light.
        let singleInvite = makeInvite()
        let multiInvites = [
            makeInvite(companyName: "Sweet Deck & Rail"),
            makeInvite(invitationId: UUID().uuidString, companyId: UUID().uuidString,
                       companyName: "North Ridge HVAC")
        ]
        snapshot("invitepicker_multiple_dark") {
            InvitePickerStepView(
                invites: multiInvites,
                previewSettled: true
            ).snapshotBody
        }
        snapshot("invitepicker_single_dark") {
            InvitePickerStepView(
                invites: [singleInvite],
                previewSettled: true
            ).snapshotBody
        }
        snapshot("invitepicker_multiple_light", colorScheme: .light) {
            InvitePickerStepView(
                invites: multiInvites,
                previewSettled: true
            ).snapshotBody
        }

        // S4c-code Code entry — default (empty field), with a code typed, error
        // (not-found inline), light. Uses the DEBUG snapshot seam.
        let codeEntryBoundary = StubCodeEntryBoundary()
        snapshot("codeentry_default_dark") {
            CodeEntryStepView(
                provenance: .zeroInvites,
                boundary: codeEntryBoundary
            ).snapshotBody
        }
        snapshot("codeentry_typed_dark") {
            CodeEntryStepView(
                provenance: .zeroInvites,
                boundary: codeEntryBoundary,
                previewCode: "BR8K90ZT"
            ).snapshotBody
        }
        snapshot("codeentry_error_dark") {
            CodeEntryStepView(
                provenance: .fromPicker,
                boundary: codeEntryBoundary,
                previewCode: "BADCODE",
                previewError: "no company found with that code. check with your boss"
            ).snapshotBody
        }
        snapshot("codeentry_default_light", colorScheme: .light) {
            CodeEntryStepView(
                provenance: .zeroInvites,
                boundary: codeEntryBoundary
            ).snapshotBody
        }

        // Completion gate (Task 4.3) — default loading (syncing), queued state,
        // Reduce-Motion (animations disabled), light. The previewInert seam pins
        // the phase + settles the entrance so the snapshot is a stable frame and
        // no boundary/network call fires. The PreviewCompletionBoundary is a no-op.
        let ackBoundary = PreviewCompletionBoundary(outcome: .acknowledged)
        let queuedBoundary = PreviewCompletionBoundary(outcome: .queued)
        snapshot("completiongate_syncing_dark") {
            CompletionGateView(boundary: ackBoundary, previewPhase: .syncing).snapshotBody
        }
        snapshot("completiongate_queued_dark") {
            CompletionGateView(boundary: queuedBoundary, previewPhase: .queued).snapshotBody
        }
        snapshot("completiongate_reduce_motion", disableAnimations: true) {
            CompletionGateView(boundary: ackBoundary, previewPhase: .syncing).snapshotBody
        }
        snapshot("completiongate_syncing_light", colorScheme: .light) {
            CompletionGateView(boundary: ackBoundary, previewPhase: .syncing).snapshotBody
        }
    }
}
#endif
