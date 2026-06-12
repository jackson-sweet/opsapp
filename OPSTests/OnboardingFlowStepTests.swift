//
//  OnboardingFlowStepTests.swift
//  OPSTests
//
//  Onboarding rebuild Task 2.1 — the pure step machine.
//  Covers the §5.2 back-edge map row by row (both auth contexts), the
//  code-entry provenance chain, the pinned Codable wire format (round-trip,
//  fixed fixtures, decode-failure on corrupt/unknown payloads), and the
//  §5.3 resume-derivation rules including precedence.
//

import XCTest
@testable import OPS

final class OnboardingFlowStepTests: XCTestCase {

    // MARK: - Back map (§5.2) — every row, both contexts

    func testWelcomeHasNoBackEdge() {
        XCTAssertNil(OnboardingFlowStep.welcome.backEdge(context: .preAuth))
        XCTAssertNil(OnboardingFlowStep.welcome.backEdge(context: .postAuth))
    }

    func testLoginBacksToWelcomeInBothContexts() {
        XCTAssertEqual(OnboardingFlowStep.login.backEdge(context: .preAuth), .welcome)
        XCTAssertEqual(OnboardingFlowStep.login.backEdge(context: .postAuth), .welcome)
    }

    func testRolePickBacksToWelcomePreAuth() {
        XCTAssertEqual(OnboardingFlowStep.rolePick.backEdge(context: .preAuth), .welcome)
    }

    func testRolePickHasNoBackEdgePostAuth() {
        // Resumed post-auth there is nothing behind role pick — SIGN OUT is the escape.
        XCTAssertNil(OnboardingFlowStep.rolePick.backEdge(context: .postAuth))
    }

    func testCreateAccountBacksToRolePickInBothContexts() {
        XCTAssertEqual(OnboardingFlowStep.createAccount.backEdge(context: .preAuth), .rolePick)
        XCTAssertEqual(OnboardingFlowStep.createAccount.backEdge(context: .postAuth), .rolePick)
    }

    func testCompanyNameBacksToRolePickInBothContexts() {
        // Role is uncommitted until a company exists — this back-edge is the
        // wrong-role escape, post-auth included.
        XCTAssertEqual(OnboardingFlowStep.companyName.backEdge(context: .preAuth), .rolePick)
        XCTAssertEqual(OnboardingFlowStep.companyName.backEdge(context: .postAuth), .rolePick)
    }

    func testCrewCodeHasNoBackEdge() {
        // Company committed — no way back.
        XCTAssertNil(OnboardingFlowStep.crewCode.backEdge(context: .preAuth))
        XCTAssertNil(OnboardingFlowStep.crewCode.backEdge(context: .postAuth))
    }

    func testInviteCheckHasNoBackEdge() {
        // Auto transition; its failure state has its own retry affordances.
        XCTAssertNil(OnboardingFlowStep.inviteCheck.backEdge(context: .preAuth))
        XCTAssertNil(OnboardingFlowStep.inviteCheck.backEdge(context: .postAuth))
    }

    func testInvitePickerBacksToRolePickInBothContexts() {
        XCTAssertEqual(OnboardingFlowStep.invitePicker.backEdge(context: .preAuth), .rolePick)
        XCTAssertEqual(OnboardingFlowStep.invitePicker.backEdge(context: .postAuth), .rolePick)
    }

    func testCodeEntryZeroInvitesBacksToRolePickInBothContexts() {
        let step = OnboardingFlowStep.codeEntry(provenance: .zeroInvites)
        XCTAssertEqual(step.backEdge(context: .preAuth), .rolePick)
        XCTAssertEqual(step.backEdge(context: .postAuth), .rolePick)
    }

    func testCodeEntryFromPickerBacksToInvitePickerInBothContexts() {
        let step = OnboardingFlowStep.codeEntry(provenance: .fromPicker)
        XCTAssertEqual(step.backEdge(context: .preAuth), .invitePicker)
        XCTAssertEqual(step.backEdge(context: .postAuth), .invitePicker)
    }

    func testConfirmCompanyFromPickerBacksToInvitePickerInBothContexts() {
        let step = OnboardingFlowStep.confirmCompany(source: .picker)
        XCTAssertEqual(step.backEdge(context: .preAuth), .invitePicker)
        XCTAssertEqual(step.backEdge(context: .postAuth), .invitePicker)
    }

    func testConfirmCompanyFromCodeEntryBacksToCodeEntryPreservingProvenance() {
        let viaZero = OnboardingFlowStep.confirmCompany(source: .codeEntry(.zeroInvites))
        XCTAssertEqual(viaZero.backEdge(context: .preAuth), .codeEntry(provenance: .zeroInvites))
        XCTAssertEqual(viaZero.backEdge(context: .postAuth), .codeEntry(provenance: .zeroInvites))

        let viaPicker = OnboardingFlowStep.confirmCompany(source: .codeEntry(.fromPicker))
        XCTAssertEqual(viaPicker.backEdge(context: .preAuth), .codeEntry(provenance: .fromPicker))
        XCTAssertEqual(viaPicker.backEdge(context: .postAuth), .codeEntry(provenance: .fromPicker))
    }

    func testProfileHasNoBackEdge() {
        // Join committed — SIGN OUT is the escape.
        XCTAssertNil(OnboardingFlowStep.profile.backEdge(context: .preAuth))
        XCTAssertNil(OnboardingFlowStep.profile.backEdge(context: .postAuth))
    }

    func testEmergencyContactBacksToProfileInBothContexts() {
        XCTAssertEqual(OnboardingFlowStep.emergencyContact.backEdge(context: .preAuth), .profile)
        XCTAssertEqual(OnboardingFlowStep.emergencyContact.backEdge(context: .postAuth), .profile)
    }

    func testCompletionGateHasNoBackEdge() {
        XCTAssertNil(OnboardingFlowStep.completionGate.backEdge(context: .preAuth))
        XCTAssertNil(OnboardingFlowStep.completionGate.backEdge(context: .postAuth))
    }

    // MARK: - Provenance chain

    func testFromPickerProvenanceChainWalksBackToInvitePicker() {
        // confirm(.codeEntry(.fromPicker)) → codeEntry(.fromPicker) → invitePicker
        let confirm = OnboardingFlowStep.confirmCompany(source: .codeEntry(.fromPicker))
        let first = confirm.backEdge(context: .preAuth)
        XCTAssertEqual(first, .codeEntry(provenance: .fromPicker))
        XCTAssertEqual(first?.backEdge(context: .preAuth), .invitePicker)
    }

    func testZeroInvitesProvenanceChainWalksBackToRolePick() {
        // confirm(.codeEntry(.zeroInvites)) → codeEntry(.zeroInvites) → rolePick
        let confirm = OnboardingFlowStep.confirmCompany(source: .codeEntry(.zeroInvites))
        let first = confirm.backEdge(context: .postAuth)
        XCTAssertEqual(first, .codeEntry(provenance: .zeroInvites))
        XCTAssertEqual(first?.backEdge(context: .postAuth), .rolePick)
    }

    // MARK: - Codable: round-trip for every case incl. associated values

    /// Every distinct persistable value of the step machine.
    private static let allSteps: [OnboardingFlowStep] = [
        .welcome,
        .login,
        .rolePick,
        .createAccount,
        .companyName,
        .crewCode,
        .inviteCheck,
        .invitePicker,
        .codeEntry(provenance: .zeroInvites),
        .codeEntry(provenance: .fromPicker),
        .confirmCompany(source: .picker),
        .confirmCompany(source: .codeEntry(.zeroInvites)),
        .confirmCompany(source: .codeEntry(.fromPicker)),
        .profile,
        .emergencyContact,
        .completionGate,
    ]

    func testCodableRoundTripForEveryCase() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for step in Self.allSteps {
            let data = try encoder.encode(step)
            let decoded = try decoder.decode(OnboardingFlowStep.self, from: data)
            XCTAssertEqual(decoded, step, "Round-trip mismatch for \(step)")
        }
    }

    // MARK: - Codable: pinned wire format (decode side)

    /// Fixed persisted payloads — these are the on-disk contract. If any of
    /// these stop decoding, persisted onboarding state from a prior install
    /// would be corrupted.
    private static let pinnedFixtures: [(json: String, expected: OnboardingFlowStep)] = [
        (#"{"step":"welcome"}"#, .welcome),
        (#"{"step":"login"}"#, .login),
        (#"{"step":"rolePick"}"#, .rolePick),
        (#"{"step":"createAccount"}"#, .createAccount),
        (#"{"step":"companyName"}"#, .companyName),
        (#"{"step":"crewCode"}"#, .crewCode),
        (#"{"step":"inviteCheck"}"#, .inviteCheck),
        (#"{"step":"invitePicker"}"#, .invitePicker),
        (#"{"step":"codeEntry","provenance":"zeroInvites"}"#, .codeEntry(provenance: .zeroInvites)),
        (#"{"step":"codeEntry","provenance":"fromPicker"}"#, .codeEntry(provenance: .fromPicker)),
        (#"{"step":"confirmCompany","source":{"kind":"picker"}}"#, .confirmCompany(source: .picker)),
        (#"{"step":"confirmCompany","source":{"kind":"codeEntry","provenance":"zeroInvites"}}"#,
         .confirmCompany(source: .codeEntry(.zeroInvites))),
        (#"{"step":"confirmCompany","source":{"kind":"codeEntry","provenance":"fromPicker"}}"#,
         .confirmCompany(source: .codeEntry(.fromPicker))),
        (#"{"step":"profile"}"#, .profile),
        (#"{"step":"emergencyContact"}"#, .emergencyContact),
        (#"{"step":"completionGate"}"#, .completionGate),
    ]

    func testDecodesPinnedFixtureForEveryCase() throws {
        let decoder = JSONDecoder()
        for (json, expected) in Self.pinnedFixtures {
            let decoded = try decoder.decode(OnboardingFlowStep.self, from: Data(json.utf8))
            XCTAssertEqual(decoded, expected, "Pinned payload \(json) decoded to the wrong step")
        }
    }

    // MARK: - Codable: pinned wire format (encode side)

    func testEncodesStableStepIdentifiers() throws {
        let expectedIdentifiers: [(OnboardingFlowStep, String)] = [
            (.welcome, "welcome"),
            (.login, "login"),
            (.rolePick, "rolePick"),
            (.createAccount, "createAccount"),
            (.companyName, "companyName"),
            (.crewCode, "crewCode"),
            (.inviteCheck, "inviteCheck"),
            (.invitePicker, "invitePicker"),
            (.codeEntry(provenance: .zeroInvites), "codeEntry"),
            (.codeEntry(provenance: .fromPicker), "codeEntry"),
            (.confirmCompany(source: .picker), "confirmCompany"),
            (.confirmCompany(source: .codeEntry(.zeroInvites)), "confirmCompany"),
            (.confirmCompany(source: .codeEntry(.fromPicker)), "confirmCompany"),
            (.profile, "profile"),
            (.emergencyContact, "emergencyContact"),
            (.completionGate, "completionGate"),
        ]
        for (step, identifier) in expectedIdentifiers {
            let object = try encodedObject(for: step)
            XCTAssertEqual(object["step"] as? String, identifier, "Wrong wire identifier for \(step)")
        }
    }

    func testEncodesCodeEntryProvenanceAsStableString() throws {
        let zero = try encodedObject(for: .codeEntry(provenance: .zeroInvites))
        XCTAssertEqual(zero["provenance"] as? String, "zeroInvites")

        let picker = try encodedObject(for: .codeEntry(provenance: .fromPicker))
        XCTAssertEqual(picker["provenance"] as? String, "fromPicker")
    }

    func testEncodesConfirmSourceAsStableObject() throws {
        let viaPicker = try encodedObject(for: .confirmCompany(source: .picker))
        let pickerSource = viaPicker["source"] as? [String: Any]
        XCTAssertEqual(pickerSource?["kind"] as? String, "picker")
        XCTAssertNil(pickerSource?["provenance"], "picker source must not carry a provenance")

        let viaCode = try encodedObject(for: .confirmCompany(source: .codeEntry(.fromPicker)))
        let codeSource = viaCode["source"] as? [String: Any]
        XCTAssertEqual(codeSource?["kind"] as? String, "codeEntry")
        XCTAssertEqual(codeSource?["provenance"] as? String, "fromPicker")
    }

    // MARK: - StepIdentifier completeness tripwire
    //
    // If a new case is added to StepIdentifier without a corresponding pinned
    // fixture, this test fails — ensuring the wire-format contract stays complete.

    func testPinnedFixturesCoverAllStepIdentifiers() throws {
        // Collect the set of "step" discriminator strings present in pinnedFixtures.
        let coveredSteps: Set<String> = try Set(
            Self.pinnedFixtures.compactMap { (json, _) -> String? in
                guard let obj = try JSONSerialization.jsonObject(
                    with: Data(json.utf8)
                ) as? [String: Any] else { return nil }
                return obj["step"] as? String
            }
        )
        let allIdentifiers = Set(OnboardingFlowStep.StepIdentifier.allCases.map(\.rawValue))
        XCTAssertEqual(
            coveredSteps,
            allIdentifiers,
            "pinnedFixtures is missing coverage for: \(allIdentifiers.subtracting(coveredSteps))"
        )
    }

    // MARK: - Codable: corrupt/unknown payloads must throw, never misdecode

    func testDecodeFailsOnUnknownStepIdentifier() {
        assertDecodeFails(#"{"step":"emailEntry"}"#)
    }

    func testDecodeFailsOnMissingStepKey() {
        assertDecodeFails(#"{}"#)
    }

    func testDecodeFailsOnStructurallyCorruptPayloads() {
        assertDecodeFails(#""welcome""#)        // bare string, not our keyed format
        assertDecodeFails(#"{"welcome":{}}"#)   // synthesized-enum style payload
        assertDecodeFails(#"{"step":7}"#)       // wrong discriminator type
        assertDecodeFails(#"[]"#)               // wrong top-level container
    }

    func testDecodeFailsOnCodeEntryMissingProvenance() {
        assertDecodeFails(#"{"step":"codeEntry"}"#)
    }

    func testDecodeFailsOnCodeEntryUnknownProvenance() {
        assertDecodeFails(#"{"step":"codeEntry","provenance":"teleport"}"#)
    }

    func testDecodeFailsOnConfirmCompanyMissingSource() {
        assertDecodeFails(#"{"step":"confirmCompany"}"#)
    }

    func testDecodeFailsOnConfirmCompanyUnknownSourceKind() {
        assertDecodeFails(#"{"step":"confirmCompany","source":{"kind":"mystery"}}"#)
    }

    func testDecodeFailsOnConfirmCompanyCodeEntrySourceMissingProvenance() {
        assertDecodeFails(#"{"step":"confirmCompany","source":{"kind":"codeEntry"}}"#)
    }

    // MARK: - Resume derivation (§5.3) — rules in priority order

    func testResumeNoCompanyDerivesRolePick() {
        XCTAssertEqual(OnboardingResume.derive(serverState(hasCompany: false)), .rolePick)
    }

    func testResumeNoCompanyBeatsEverything() {
        // webComplete + owner + complete profile — none of it matters with no
        // company; the role is uncommitted regardless of stored values.
        let state = serverState(
            hasCompany: false,
            role: "owner",
            userType: "company",
            profileComplete: true,
            webComplete: true
        )
        XCTAssertEqual(OnboardingResume.derive(state), .rolePick)
    }

    func testResumeWebCompleteDerivesCompletionGate() {
        let state = serverState(
            hasCompany: true,
            role: "crew",
            userType: "employee",
            profileComplete: true,
            webComplete: true
        )
        XCTAssertEqual(OnboardingResume.derive(state), .completionGate)
    }

    func testResumeWebCompleteBeatsOwner() {
        let state = serverState(
            hasCompany: true,
            role: "owner",
            userType: "company",
            webComplete: true
        )
        XCTAssertEqual(OnboardingResume.derive(state), .completionGate)
    }

    func testResumeWebCompleteBeatsIncompleteProfile() {
        let state = serverState(
            hasCompany: true,
            role: "crew",
            userType: "employee",
            profileComplete: false,
            webComplete: true
        )
        XCTAssertEqual(OnboardingResume.derive(state), .completionGate)
    }

    func testResumeOwnerWithCompanyDerivesCrewCode() {
        let state = serverState(hasCompany: true, role: "owner", userType: "company")
        XCTAssertEqual(OnboardingResume.derive(state), .crewCode)
    }

    func testResumeTitleCaseOwnerDerivesCrewCode() {
        // Legacy rows in users.role may carry title-case "Owner" — must resolve identically.
        let state = serverState(hasCompany: true, role: "Owner", webComplete: false)
        XCTAssertEqual(OnboardingResume.derive(state), .crewCode)
    }

    func testResumeOwnerIgnoresProfileCompleteness() {
        // The owner path re-shows the code regardless of profile state.
        XCTAssertEqual(
            OnboardingResume.derive(serverState(hasCompany: true, role: "owner", profileComplete: false)),
            .crewCode
        )
        XCTAssertEqual(
            OnboardingResume.derive(serverState(hasCompany: true, role: "owner", profileComplete: true)),
            .crewCode
        )
    }

    func testResumeEmployeeWithIncompleteProfileDerivesProfile() {
        let state = serverState(
            hasCompany: true,
            role: "crew",
            userType: "employee",
            profileComplete: false
        )
        XCTAssertEqual(OnboardingResume.derive(state), .profile)
    }

    func testResumeEmployeeWithCompleteProfileDerivesCompletionGate() {
        // emergencyContact is optional and never re-offered on resume.
        let state = serverState(
            hasCompany: true,
            role: "crew",
            userType: "employee",
            profileComplete: true
        )
        XCTAssertEqual(OnboardingResume.derive(state), .completionGate)
    }

    func testResumeNilRoleWithCompanyFollowsEmployeePath() {
        // Priority ordering: anything with a company that is not webComplete
        // and not an owner takes the employee path.
        XCTAssertEqual(
            OnboardingResume.derive(serverState(hasCompany: true, role: nil, profileComplete: false)),
            .profile
        )
        XCTAssertEqual(
            OnboardingResume.derive(serverState(hasCompany: true, role: nil, profileComplete: true)),
            .completionGate
        )
    }

    // MARK: - Helpers

    private func encodedObject(
        for step: OnboardingFlowStep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let data = try JSONEncoder().encode(step)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Encoded payload for \(step) is not a JSON object", file: file, line: line)
            return [:]
        }
        return object
    }

    private func assertDecodeFails(
        _ json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try JSONDecoder().decode(OnboardingFlowStep.self, from: Data(json.utf8)),
            "Expected decode to throw for payload: \(json)",
            file: file,
            line: line
        )
    }

    private func serverState(
        hasCompany: Bool,
        role: String? = nil,
        userType: String? = nil,
        profileComplete: Bool = false,
        webComplete: Bool = false
    ) -> OnboardingServerState {
        OnboardingServerState(
            hasCompany: hasCompany,
            role: role,
            userType: userType,
            profileComplete: profileComplete,
            webComplete: webComplete
        )
    }
}
