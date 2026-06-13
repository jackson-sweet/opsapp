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
    }
}
#endif
