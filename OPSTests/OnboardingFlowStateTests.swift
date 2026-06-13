//
//  OnboardingFlowStateTests.swift
//  OPSTests
//
//  Onboarding rebuild Task 2.2 — the unified v4 flow state + v3→v4 migration.
//  Pure persistence logic, test-first. Covers the v4 round-trip (with/without
//  step, every form-data shape incl. associated-value steps), absent/corrupt
//  load behaviour, clear(), and the idempotent v3→v4 migration's four paths
//  (mapped, v4-present no-op, corrupt v3, no v3 at all). All persistence runs
//  on an isolated UserDefaults suite — never `.standard`.
//

import XCTest
@testable import OPS

final class OnboardingFlowStateTests: XCTestCase {

    // MARK: - Isolated UserDefaults suite (never pollute .standard)

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingFlowStateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Keys under test

    private let v4Key = "onboarding_state_v4"
    private let v3Key = "onboarding_state_v3"
    private let abTestKey = "ab_test_flow_step"

    // MARK: - Sample form data

    private func fullFormData() -> OnboardingFormData {
        OnboardingFormData(
            selectedRole: .owner,
            firstName: "Jane",
            lastName: "Mason",
            email: "jane@mason.co",
            companyName: "Mason Electrical",
            industries: ["Electrical", "HVAC"],
            enteredCrewCode: nil,
            generatedCrewCode: "MASON-7Q",
            phone: "+15551234567",
            emergencyContactName: "Pat Mason",
            emergencyContactPhone: "+15557654321",
            emergencyContactRelationship: "Spouse",
            hasSelectedAvatar: true
        )
    }

    private func crewFormData() -> OnboardingFormData {
        OnboardingFormData(
            selectedRole: .crew,
            firstName: "Sam",
            lastName: "",
            email: "sam@crew.io",
            companyName: nil,
            industries: nil,
            enteredCrewCode: "MASON-7Q",
            generatedCrewCode: nil,
            phone: nil,
            emergencyContactName: nil,
            emergencyContactPhone: nil,
            emergencyContactRelationship: nil,
            hasSelectedAvatar: false
        )
    }

    // MARK: - v4 round-trip

    func testRoundTripStateWithStepAndFullData() throws {
        let store = OnboardingFlowStateStore(defaults: defaults)
        let state = OnboardingFlowState(step: .profile, data: fullFormData())
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testRoundTripStateWithNilStep() throws {
        let store = OnboardingFlowStateStore(defaults: defaults)
        let state = OnboardingFlowState(step: nil, data: crewFormData())
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testRoundTripStateWithEmptyData() throws {
        let store = OnboardingFlowStateStore(defaults: defaults)
        let state = OnboardingFlowState(step: .welcome, data: OnboardingFormData())
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testRoundTripAssociatedValueStep() throws {
        let store = OnboardingFlowStateStore(defaults: defaults)
        let state = OnboardingFlowState(
            step: .confirmCompany(source: .codeEntry(.fromPicker)),
            data: crewFormData()
        )
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testRoundTripEveryStepShape() throws {
        let store = OnboardingFlowStateStore(defaults: defaults)
        let steps: [OnboardingFlowStep?] = [
            nil,
            .welcome, .login, .rolePick, .createAccount, .companyName,
            .crewCode, .inviteCheck, .invitePicker,
            .codeEntry(provenance: .zeroInvites),
            .codeEntry(provenance: .fromPicker),
            .confirmCompany(source: .picker),
            .confirmCompany(source: .codeEntry(.zeroInvites)),
            .confirmCompany(source: .codeEntry(.fromPicker)),
            .profile, .emergencyContact, .completionGate,
        ]
        for step in steps {
            let state = OnboardingFlowState(step: step, data: fullFormData())
            store.save(state)
            XCTAssertEqual(store.load(), state, "Round-trip mismatch for step \(String(describing: step))")
        }
    }

    func testSaveOverwritesPreviousState() throws {
        let store = OnboardingFlowStateStore(defaults: defaults)
        store.save(OnboardingFlowState(step: .welcome, data: OnboardingFormData()))
        let updated = OnboardingFlowState(step: .profile, data: fullFormData())
        store.save(updated)
        XCTAssertEqual(store.load(), updated)
    }

    // MARK: - load() on absent / corrupt

    func testLoadAbsentKeyReturnsNil() {
        let store = OnboardingFlowStateStore(defaults: defaults)
        XCTAssertNil(store.load())
    }

    func testLoadCorruptBytesReturnsNilAndClearsKey() {
        // Decision: corrupt v4 bytes are discarded (key removed) so a poison
        // blob can never wedge the user. Asserting the clear here.
        defaults.set(Data("not json at all".utf8), forKey: v4Key)
        let store = OnboardingFlowStateStore(defaults: defaults)
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.data(forKey: v4Key), "corrupt v4 blob should be cleared on failed load")
    }

    func testLoadValidJSONWithUnknownStepPayloadReturnsNil() {
        // A v4 blob whose `step` carries an unknown identifier must be treated
        // as no-saved-state (the step machine throws), not crash.
        let json = #"{"v":1,"step":{"step":"teleport"},"data":{}}"#
        defaults.set(Data(json.utf8), forKey: v4Key)
        let store = OnboardingFlowStateStore(defaults: defaults)
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.data(forKey: v4Key))
    }

    // MARK: - clear()

    func testClearRemovesKey() {
        let store = OnboardingFlowStateStore(defaults: defaults)
        store.save(OnboardingFlowState(step: .profile, data: fullFormData()))
        XCTAssertNotNil(defaults.data(forKey: v4Key))
        store.clear()
        XCTAssertNil(defaults.data(forKey: v4Key))
        XCTAssertNil(store.load())
    }

    // MARK: - Migration: v3 present → mapped into v4, legacy keys cleaned

    /// Seed a real legacy v3 blob exactly as `OnboardingState` encodes it.
    private func seedV3(_ state: OnboardingState) throws {
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: v3Key)
    }

    private func legacyV3State() -> OnboardingState {
        var state = OnboardingState.initial
        state.flow = .companyCreator
        state.userData.email = "owner@acme.co"
        state.userData.firstName = "Dana"
        state.userData.lastName = "Reyes"
        state.userData.phone = "+15550001111"
        state.companyData.name = "Acme Plumbing"
        state.companyData.industry = "Plumbing"
        state.companyData.companyCode = "ACME-42"
        return state
    }

    func testMigrationMapsV3FieldsIntoV4() throws {
        try seedV3(legacyV3State())
        defaults.set("companySetup", forKey: abTestKey)

        let store = OnboardingFlowStateStore(defaults: defaults)
        store.migrateV3IfNeeded()

        let migrated = store.load()
        XCTAssertNotNil(migrated, "migration should have created a v4 blob")
        // Step is intentionally nil — server-derived resume is the authority.
        XCTAssertNil(migrated?.step)

        let data = migrated!.data
        XCTAssertEqual(data.selectedRole, .owner)        // flow .companyCreator → .owner
        XCTAssertEqual(data.firstName, "Dana")
        XCTAssertEqual(data.lastName, "Reyes")
        XCTAssertEqual(data.email, "owner@acme.co")
        XCTAssertEqual(data.phone, "+15550001111")
        XCTAssertEqual(data.companyName, "Acme Plumbing")
        XCTAssertEqual(data.industries, ["Plumbing"])
        XCTAssertEqual(data.generatedCrewCode, "ACME-42") // owner path: company code is the generated crew code

        // Legacy keys removed.
        XCTAssertNil(defaults.data(forKey: v3Key))
        XCTAssertNil(defaults.object(forKey: abTestKey))
    }

    func testMigrationMapsEmployeeFlowToCrewRole() throws {
        var state = OnboardingState.initial
        state.flow = .employee
        state.userData.firstName = "Lee"
        state.userData.email = "lee@crew.io"
        try seedV3(state)

        let store = OnboardingFlowStateStore(defaults: defaults)
        store.migrateV3IfNeeded()

        let migrated = store.load()
        XCTAssertEqual(migrated?.data.selectedRole, .crew)
        XCTAssertEqual(migrated?.data.firstName, "Lee")
        // No company code on the employee path → generatedCrewCode stays nil.
        XCTAssertNil(migrated?.data.generatedCrewCode)
    }

    func testMigrationWithNilFlowLeavesRoleNil() throws {
        var state = OnboardingState.initial
        state.flow = nil
        state.userData.firstName = "Kai"
        try seedV3(state)

        let store = OnboardingFlowStateStore(defaults: defaults)
        store.migrateV3IfNeeded()

        let migrated = store.load()
        XCTAssertNotNil(migrated)
        XCTAssertNil(migrated?.data.selectedRole)
        XCTAssertEqual(migrated?.data.firstName, "Kai")
    }

    func testMigrationDropsEmptyV3StringsToNil() throws {
        // OnboardingState defaults are "" — migration must not persist empties
        // as present values; they map to nil so v4 stays minimal.
        let state = OnboardingState.initial // flow nil, all strings ""
        try seedV3(state)

        let store = OnboardingFlowStateStore(defaults: defaults)
        store.migrateV3IfNeeded()

        let data = store.load()?.data
        XCTAssertNotNil(data)
        XCTAssertNil(data?.firstName)
        XCTAssertNil(data?.lastName)
        XCTAssertNil(data?.email)
        XCTAssertNil(data?.phone)
        XCTAssertNil(data?.companyName)
        XCTAssertNil(data?.industries)
        XCTAssertNil(data?.generatedCrewCode)
    }

    // MARK: - Migration: v4 already present → no-op (but legacy keys cleaned)

    func testMigrationNoOpWhenV4AlreadyPresent() throws {
        let existing = OnboardingFlowState(step: .profile, data: fullFormData())
        let store = OnboardingFlowStateStore(defaults: defaults)
        store.save(existing)

        // Legacy state also lingers — migration must not clobber v4 but must
        // still clean the legacy keys.
        try seedV3(legacyV3State())
        defaults.set("companySetup", forKey: abTestKey)

        store.migrateV3IfNeeded()

        XCTAssertEqual(store.load(), existing, "existing v4 blob must not be clobbered")
        XCTAssertNil(defaults.data(forKey: v3Key))
        XCTAssertNil(defaults.object(forKey: abTestKey))
    }

    // MARK: - Migration: corrupt v3 → no v4, legacy keys removed, no crash

    func testMigrationCorruptV3CreatesNoV4AndCleansKeys() {
        defaults.set(Data("garbage".utf8), forKey: v3Key)
        defaults.set("companySetup", forKey: abTestKey)

        let store = OnboardingFlowStateStore(defaults: defaults)
        store.migrateV3IfNeeded()

        XCTAssertNil(store.load(), "corrupt v3 must not produce a v4 blob")
        XCTAssertNil(defaults.data(forKey: v3Key))
        XCTAssertNil(defaults.object(forKey: abTestKey))
    }

    // MARK: - Migration: no v3 at all → no v4, legacy keys still removed

    func testMigrationNoV3CreatesNoV4ButCleansLegacyKeys() {
        defaults.set("companySetup", forKey: abTestKey)

        let store = OnboardingFlowStateStore(defaults: defaults)
        store.migrateV3IfNeeded()

        XCTAssertNil(store.load())
        XCTAssertNil(defaults.data(forKey: v3Key))
        XCTAssertNil(defaults.object(forKey: abTestKey))
    }

    func testMigrationIsIdempotent() throws {
        try seedV3(legacyV3State())
        let store = OnboardingFlowStateStore(defaults: defaults)

        store.migrateV3IfNeeded()
        let first = store.load()
        // Second run: v4 exists, v3 already gone → must be a pure no-op.
        store.migrateV3IfNeeded()
        let second = store.load()

        XCTAssertEqual(first, second)
        XCTAssertNotNil(first)
    }

    // MARK: - OnboardingFormData Codable stability

    func testFormDataRoundTripPreservesAllFields() throws {
        let original = fullFormData()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OnboardingFormData.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testFormDataDecodesFromPartialBlob() throws {
        // A future-written blob missing fields (all optional) must still decode.
        let json = #"{"firstName":"Jo"}"#
        let decoded = try JSONDecoder().decode(OnboardingFormData.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.firstName, "Jo")
        XCTAssertNil(decoded.lastName)
        XCTAssertNil(decoded.selectedRole)
    }
}
