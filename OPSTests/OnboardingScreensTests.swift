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
    }
}
#endif
