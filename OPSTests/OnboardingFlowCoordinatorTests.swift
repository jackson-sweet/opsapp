//
//  OnboardingFlowCoordinatorTests.swift
//  OPSTests
//
//  Onboarding rebuild Task 2.3a — the runtime driver of the rebuilt flow.
//  Test-first. Covers start() placement (unauth → welcome, authed-incomplete →
//  server-derived resume, same-session saved-step restore), advance/persist,
//  back navigation with a LIVE auth context (the same step backs differently
//  pre- vs post-auth), form-data mutation, sign-out/reset, complete(), and
//  provenance preservation through advance → goBack. All persistence runs on an
//  isolated UserDefaults suite — never `.standard`. The coordinator is
//  @MainActor, so this test case is too.
//

import XCTest
@testable import OPS

@MainActor
final class OnboardingFlowCoordinatorTests: XCTestCase {

    // MARK: - Isolated UserDefaults suite (never pollute .standard)

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingFlowCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Builders

    /// A fresh store bound to the isolated suite. A second store on the SAME
    /// suite reads what the coordinator's store wrote — used to assert
    /// persistence independently of the coordinator's in-memory state.
    private func makeStore() -> OnboardingFlowStateStore {
        OnboardingFlowStateStore(defaults: defaults)
    }

    private func makeCoordinator(
        isAuthenticated: @escaping () -> Bool,
        serverState: @escaping () -> OnboardingServerState? = { nil }
    ) -> OnboardingFlowCoordinator {
        OnboardingFlowCoordinator(
            store: makeStore(),
            isAuthenticated: isAuthenticated,
            serverStateProvider: serverState
        )
    }

    /// Reads the persisted step from a fresh store on the same suite.
    private func persistedStep() -> OnboardingFlowStep? {
        makeStore().load()?.step
    }

    /// Reads the persisted form data from a fresh store on the same suite.
    private func persistedData() -> OnboardingFormData? {
        makeStore().load()?.data
    }

    // MARK: - start(): unauthenticated, no saved state → welcome

    func testStartUnauthenticatedNoSavedStateGoesToWelcome() {
        let coordinator = makeCoordinator(isAuthenticated: { false })
        coordinator.start()

        XCTAssertEqual(coordinator.currentStep, .welcome)
        // Resolved state is persisted so a kill resumes.
        XCTAssertEqual(persistedStep(), .welcome)
    }

    // MARK: - start(): authenticated-incomplete, no saved state → server resume

    func testStartAuthenticatedIncompleteDerivesResumeStep() {
        // hasCompany + crew + incomplete profile → OnboardingResume.derive → .profile
        let server = OnboardingServerState(
            hasCompany: true,
            role: "crew",
            userType: "employee",
            profileComplete: false,
            webComplete: false
        )
        let coordinator = makeCoordinator(isAuthenticated: { true }, serverState: { server })
        coordinator.start()

        XCTAssertEqual(coordinator.currentStep, .profile, "resume derivation must be wired")
        XCTAssertEqual(persistedStep(), .profile)
    }

    func testStartAuthenticatedNoServerStateFallsBackToWelcome() {
        // Authenticated but the server state is unavailable (e.g. offline before
        // the first fetch) and there is no usable saved step → welcome fallback.
        let coordinator = makeCoordinator(isAuthenticated: { true }, serverState: { nil })
        coordinator.start()

        XCTAssertEqual(coordinator.currentStep, .welcome)
        XCTAssertEqual(persistedStep(), .welcome)
    }

    // MARK: - start(): same-session saved step beats derivation

    func testStartRestoresSavedStepAndFormData() {
        // Seed a saved blob with a concrete step + form data via an independent
        // store on the same suite, then start a coordinator over it.
        let seeded = OnboardingFormData(firstName: "Dana", companyName: "Acme Plumbing")
        makeStore().save(OnboardingFlowState(step: .companyName, data: seeded))

        // Authenticated WITH a server state that would derive elsewhere — proves
        // the saved step wins over derivation (same-session resume optimization).
        let server = OnboardingServerState(
            hasCompany: true, role: "owner", userType: "company",
            profileComplete: false, webComplete: false
        )
        let coordinator = makeCoordinator(isAuthenticated: { true }, serverState: { server })
        coordinator.start()

        XCTAssertEqual(coordinator.currentStep, .companyName, "saved step must beat server derivation")
        XCTAssertEqual(coordinator.formData.firstName, "Dana")
        XCTAssertEqual(coordinator.formData.companyName, "Acme Plumbing")
    }

    func testStartIgnoresSavedStateWithNilStepAndDerives() {
        // A saved blob whose step is nil (e.g. post-migration) carries form data
        // but NO position — derivation owns placement, form data is restored.
        let seeded = OnboardingFormData(firstName: "Kai")
        makeStore().save(OnboardingFlowState(step: nil, data: seeded))

        let server = OnboardingServerState(
            hasCompany: false, role: nil, userType: nil,
            profileComplete: false, webComplete: false
        )
        let coordinator = makeCoordinator(isAuthenticated: { true }, serverState: { server })
        coordinator.start()

        // hasCompany == false → .rolePick from derivation.
        XCTAssertEqual(coordinator.currentStep, .rolePick)
        // Form data from the saved blob is still restored.
        XCTAssertEqual(coordinator.formData.firstName, "Kai")
    }

    // MARK: - advance(to:)

    func testAdvanceSetsStepAndPersists() {
        let coordinator = makeCoordinator(isAuthenticated: { false })
        coordinator.start()

        coordinator.advance(to: .rolePick)

        XCTAssertEqual(coordinator.currentStep, .rolePick)
        XCTAssertEqual(persistedStep(), .rolePick, "advance must persist so a kill resumes")
    }

    // MARK: - goBack / canGoBack (live context)

    func testGoBackPostAuthFromCompanyNameReturnsToRolePick() {
        // companyName.backEdge is .rolePick in BOTH contexts; here we exercise
        // the post-auth path (isAuthenticated == true).
        let coordinator = makeCoordinator(isAuthenticated: { true })
        coordinator.start()
        coordinator.advance(to: .companyName)

        XCTAssertTrue(coordinator.canGoBack)
        coordinator.goBack()

        XCTAssertEqual(coordinator.currentStep, .rolePick)
        XCTAssertEqual(persistedStep(), .rolePick)
    }

    func testGoBackNoOpWhenNoBackEdge() {
        // crewCode has no back-edge in any context → canGoBack false, goBack no-op.
        let coordinator = makeCoordinator(isAuthenticated: { true })
        coordinator.start()
        coordinator.advance(to: .crewCode)

        XCTAssertFalse(coordinator.canGoBack)
        coordinator.goBack()
        XCTAssertEqual(coordinator.currentStep, .crewCode, "no back-edge → goBack must not move")
    }

    // MARK: - Live context switch on the SAME step

    func testCurrentContextIsLiveAcrossAuthState() {
        // rolePick.backEdge == .welcome pre-auth, nil post-auth. The coordinator
        // must read the auth closure live, not snapshot it at init.
        let preAuth = makeCoordinator(isAuthenticated: { false })
        preAuth.start()
        preAuth.advance(to: .rolePick)
        XCTAssertTrue(preAuth.canGoBack)
        preAuth.goBack()
        XCTAssertEqual(preAuth.currentStep, .welcome, "pre-auth rolePick backs to welcome")

        let postAuth = makeCoordinator(isAuthenticated: { true })
        postAuth.start()
        postAuth.advance(to: .rolePick)
        XCTAssertFalse(postAuth.canGoBack, "post-auth rolePick has no back-edge")
        postAuth.goBack()
        XCTAssertEqual(postAuth.currentStep, .rolePick, "post-auth goBack is a no-op")
    }

    // MARK: - update()

    func testUpdateMutatesFormDataAndPersists() {
        let coordinator = makeCoordinator(isAuthenticated: { false })
        coordinator.start()

        coordinator.update { $0.firstName = "Jane" }
        coordinator.update { $0.companyName = "Mason Electrical" }

        XCTAssertEqual(coordinator.formData.firstName, "Jane")
        XCTAssertEqual(coordinator.formData.companyName, "Mason Electrical")
        // A reload from a fresh store on the same suite shows the change.
        XCTAssertEqual(persistedData()?.firstName, "Jane")
        XCTAssertEqual(persistedData()?.companyName, "Mason Electrical")
    }

    // MARK: - signOut / reset

    func testSignOutClearsStoreAndResets() {
        let coordinator = makeCoordinator(isAuthenticated: { true })
        coordinator.start()
        coordinator.advance(to: .companyName)
        coordinator.update { $0.firstName = "Dana" }
        XCTAssertNotNil(persistedStep())

        coordinator.signOut()

        XCTAssertEqual(coordinator.currentStep, .welcome)
        XCTAssertEqual(coordinator.formData, OnboardingFormData())
        XCTAssertNil(makeStore().load(), "signOut must clear the persisted blob")
    }

    func testResetClearsStoreAndResets() {
        let coordinator = makeCoordinator(isAuthenticated: { true })
        coordinator.start()
        coordinator.advance(to: .profile)
        coordinator.update { $0.lastName = "Reyes" }

        coordinator.reset()

        XCTAssertEqual(coordinator.currentStep, .welcome)
        XCTAssertEqual(coordinator.formData, OnboardingFormData())
        XCTAssertNil(makeStore().load())
    }

    // MARK: - complete()

    func testCompleteClearsStore() {
        let coordinator = makeCoordinator(isAuthenticated: { true })
        coordinator.start()
        coordinator.advance(to: .completionGate)
        XCTAssertNotNil(makeStore().load())

        coordinator.complete()

        XCTAssertNil(makeStore().load(), "complete must clear local state")
    }

    func testCompleteResetsInMemoryState() {
        // Advance to the end of the flow with form data populated, then call
        // complete(). Both in-memory state and the store must return to neutral.
        let coordinator = makeCoordinator(isAuthenticated: { true })
        coordinator.start()
        coordinator.advance(to: .completionGate)
        coordinator.update { $0.firstName = "Lee"; $0.companyName = "Apex Roofing" }

        coordinator.complete()

        XCTAssertEqual(coordinator.currentStep, .welcome,
                       "complete() must reset currentStep to .welcome")
        XCTAssertEqual(coordinator.formData, OnboardingFormData(),
                       "complete() must reset formData to empty")
        XCTAssertNil(makeStore().load(),
                     "complete() must clear the persisted blob")
    }

    // MARK: - start() idempotency

    func testStartIsIdempotent() {
        // start() once, then advance and fill form data to simulate the user
        // being mid-flow. A second start() must be a no-op — it must NOT
        // restore from the store or re-derive the step, clobbering in-flight
        // state.
        let coordinator = makeCoordinator(isAuthenticated: { true })
        coordinator.start()
        coordinator.advance(to: .companyName)
        coordinator.update { $0.firstName = "Sam" }

        let stepAfterFirst = coordinator.currentStep
        let dataAfterFirst = coordinator.formData

        // Second start() — must be ignored entirely.
        coordinator.start()

        XCTAssertEqual(coordinator.currentStep, stepAfterFirst,
                       "second start() must not change currentStep")
        XCTAssertEqual(coordinator.formData, dataAfterFirst,
                       "second start() must not change formData")
        XCTAssertEqual(coordinator.formData.firstName, "Sam",
                       "in-flight form data must survive the second start()")
    }

    // MARK: - Provenance preserved through advance → goBack

    func testProvenancePreservedThroughAdvanceAndGoBack() {
        let coordinator = makeCoordinator(isAuthenticated: { true })
        coordinator.start()
        coordinator.advance(to: .confirmCompany(source: .codeEntry(.fromPicker)))

        XCTAssertTrue(coordinator.canGoBack)
        coordinator.goBack()

        // confirmCompany(.codeEntry(p)).backEdge → .codeEntry(provenance: p)
        XCTAssertEqual(coordinator.currentStep, .codeEntry(provenance: .fromPicker))
    }
}
