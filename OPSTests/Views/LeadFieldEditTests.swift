//
//  LeadFieldEditTests.swift
//  OPSTests
//
//  Coverage for hold-to-edit on the lead dossier (bug b1d30fe8).
//
//  Four promises are under test here, in this order of importance:
//
//    1. PERMISSION. An operator without edit rights gets no editing affordance
//       at all — not a disabled one, not one that refuses on tap. Nothing.
//    2. ONE EFFECT PER PRESS. A press opens the editor OR runs the field's own
//       tap meaning. Never both, never neither by accident.
//    3. HONEST FAILURE. A write that does not land leaves the editor OPEN
//       (which is what keeps the operator's typing on screen), states the
//       failure, and can retry the identical change without a retype.
//    4. SERVER TRUTH. A write that DOES land repaints the lead from the row the
//       server returned — never from the local guess.
//

import XCTest
@testable import OPS

@MainActor
final class LeadFieldEditTests: XCTestCase {

    // MARK: - Fixtures

    private func makeLead(
        address: String? = "1240 Maple Ave",
        latitude: Double? = 49.28,
        longitude: Double? = -123.12,
        phone: String? = "604-555-0142",
        email: String? = "helen@example.com",
        estimatedValue: Double? = 14_200,
        clientId: String? = nil
    ) -> Opportunity {
        let lead = Opportunity(
            id: "11111111-1111-1111-1111-111111111111",
            companyId: "22222222-2222-2222-2222-222222222222",
            contactName: "Helen Calloway",
            stage: .quoted
        )
        lead.address = address
        lead.latitude = latitude
        lead.longitude = longitude
        lead.contactPhone = phone
        lead.contactEmail = email
        lead.estimatedValue = estimatedValue
        lead.clientId = clientId
        return lead
    }

    /// A server row, as the repository would hand it back.
    private func serverRow(
        from lead: Opportunity,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        phone: String? = nil,
        email: String? = nil,
        estimatedValue: Double? = nil,
        clientId: String? = nil
    ) -> Opportunity {
        let fresh = Opportunity(
            id: lead.id,
            companyId: lead.companyId,
            contactName: lead.contactName,
            stage: lead.stage
        )
        fresh.address = address
        fresh.latitude = latitude
        fresh.longitude = longitude
        fresh.contactPhone = phone
        fresh.contactEmail = email
        fresh.estimatedValue = estimatedValue
        fresh.clientId = clientId
        return fresh
    }

    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    /// Records every change the controller pushes at the wire, and answers with
    /// whatever the test wants — a server row, or a failure.
    private final class WriteSpy {
        private(set) var changes: [LeadFieldChange] = []
        var result: Result<Opportunity, Error>

        init(result: Result<Opportunity, Error>) {
            self.result = result
        }

        var callCount: Int { changes.count }

        func write(_ change: LeadFieldChange) throws -> Opportunity {
            changes.append(change)
            return try result.get()
        }
    }

    private func makeController(
        lead: Opportunity,
        spy: WriteSpy
    ) -> LeadFieldEditController {
        LeadFieldEditController(opportunity: lead) { change in
            try spy.write(change)
        }
    }

    // MARK: - 1. Permission gate

    /// The headline promise: a viewer holding a dossier field gets NOTHING.
    /// Not a disabled editor, not a refusal — no editing effect at all.
    ///
    /// The gate is `InfoRowEdit.offersLongPressEdit`, the SAME rule the
    /// project-details document already uses for its CLIENT / ADDRESS / NOTES
    /// rows, so the two documents cannot drift apart.
    func testViewerIsNeverOfferedAnEditor() {
        for hasValue in [true, false] {
            XCTAssertFalse(
                InfoRowEdit.offersLongPressEdit(canEdit: false, hasValue: hasValue),
                "A viewer must never be gated in (hasValue: \(hasValue))"
            )
        }

        for hasTapAction in [true, false] {
            XCTAssertEqual(
                LeadFieldPress.resolve(
                    .hold,
                    offersEdit: false,
                    hasTapAction: hasTapAction
                ),
                .ignore,
                "A hold that is not gated in must resolve to nothing"
            )
        }
    }

    /// A viewer keeps every read affordance they have today. The gesture change
    /// takes nothing away from them.
    func testViewerKeepsTapMeaning() {
        XCTAssertEqual(
            LeadFieldPress.resolve(.tap, offersEdit: false, hasTapAction: true),
            .activate
        )
    }

    /// The permission rule has to hold for VoiceOver too. A viewer must not be
    /// offered an "Edit …" action in the rotor that then silently does nothing,
    /// and an inert fact must not announce itself as a button.
    func testInertFactIsNotAButtonForAViewer() {
        XCTAssertFalse(
            LeadFieldPress.isInteractive(offersEdit: false, hasTapAction: false),
            "A viewer reading an estimated value hears a value, not a button"
        )
        XCTAssertTrue(LeadFieldPress.isInteractive(offersEdit: false, hasTapAction: true))
        XCTAssertTrue(LeadFieldPress.isInteractive(offersEdit: true, hasTapAction: false))
    }

    // MARK: - 2. One effect per press

    func testHoldOpensEditorWhenGatedIn() {
        XCTAssertTrue(InfoRowEdit.offersLongPressEdit(canEdit: true, hasValue: true))
        XCTAssertEqual(
            LeadFieldPress.resolve(.hold, offersEdit: true, hasTapAction: true),
            .edit
        )
    }

    /// A hold must never ALSO fire the tap. The resolver can only ever produce
    /// one effect per press, so the two can never both come out of one gesture.
    func testPopulatedFieldTapKeepsItsOwnMeaning() {
        XCTAssertEqual(
            LeadFieldPress.resolve(.tap, offersEdit: true, hasTapAction: true),
            .activate,
            "A tap on a populated field routes/opens — it must not pop a keyboard under a reading finger"
        )
    }

    /// A populated KPI cell has no tap meaning. It stays inert under a stray
    /// finger — only a deliberate hold opens it.
    func testPopulatedFieldWithoutTapMeaningStaysInert() {
        XCTAssertEqual(
            LeadFieldPress.resolve(.tap, offersEdit: true, hasTapAction: false),
            .ignore
        )
    }

    /// A BLANK field is deliberately not hold-editable. A long press on nothing
    /// is undiscoverable, so a blank carries an explicit ADD / ASSIGN chip
    /// instead — the project document's rule, applied here unchanged.
    func testBlankFieldIsNotHoldEditable() {
        XCTAssertFalse(
            InfoRowEdit.offersLongPressEdit(canEdit: true, hasValue: false),
            "A blank shows a named way in, never a hidden gesture"
        )
    }

    /// A field already in its editor offers nothing further — a hold inside an
    /// open editor must not re-open it underneath the operator.
    func testFieldAlreadyEditingOffersNothingFurther() {
        XCTAssertFalse(
            InfoRowEdit.offersLongPressEdit(canEdit: true, hasValue: true, isEditing: true)
        )
    }

    // MARK: - 3. Each field's editor opens

    func testHoldOpensEachInlineEditor() {
        let lead = makeLead()
        let spy = WriteSpy(result: .success(serverRow(from: lead)))
        let controller = makeController(lead: lead, spy: spy)

        for field in [LeadEditableField.address, .contact, .value] {
            controller.begin(field)
            XCTAssertTrue(
                controller.isEditing(field),
                "\(field.rawValue) must open its own editor"
            )
            XCTAssertNil(controller.failure(for: field))
            controller.cancel()
            XCTAssertFalse(controller.isEditing(field))
        }
    }

    /// Opening one editor closes any other. Nobody corrects two facts at once.
    func testOnlyOneEditorIsOpenAtATime() {
        let lead = makeLead()
        let spy = WriteSpy(result: .success(serverRow(from: lead)))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.address)
        controller.begin(.value)

        XCTAssertTrue(controller.isEditing(.value))
        XCTAssertFalse(controller.isEditing(.address))
    }

    /// Every hold-editable field publishes a named VoiceOver action, because a
    /// long press is unreachable with VoiceOver running.
    func testEveryEditableFieldPublishesAnAccessibilityAction() {
        for field in LeadEditableField.allCases {
            XCTAssertFalse(
                field.accessibilityActionName.isEmpty,
                "\(field.rawValue) must be reachable without the gesture"
            )
        }
    }

    // MARK: - 4. A successful write persists

    func testSuccessfulAddressSaveAppliesTheServerRow() async {
        let lead = makeLead(address: "1240 Maple Ave")
        let fresh = serverRow(
            from: lead,
            address: "3185 Fairview Rd",
            latitude: 49.5,
            longitude: -123.5
        )
        let spy = WriteSpy(result: .success(fresh))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.address)
        await controller.saveAddress("3185 Fairview Rd", latitude: 49.5, longitude: -123.5)

        XCTAssertEqual(
            spy.changes,
            [.address("3185 Fairview Rd", latitude: 49.5, longitude: -123.5)]
        )
        // The lead now reads what the SERVER returned, not what was typed.
        XCTAssertEqual(lead.address, "3185 Fairview Rd")
        XCTAssertEqual(lead.latitude, 49.5)
        XCTAssertEqual(lead.longitude, -123.5)
        XCTAssertNil(controller.editing, "A landed write closes the editor")
        XCTAssertNil(controller.failure)
        XCTAssertTrue(controller.didCompleteAnEdit)
    }

    /// The lead repaints from the server even when the server disagrees with
    /// the operator. A write that landed differently must be VISIBLE, not
    /// papered over with a hopeful echo of the local input.
    func testSaveRepaintsFromServerEvenWhenItDisagrees() async {
        let lead = makeLead(estimatedValue: 14_200)
        let fresh = serverRow(from: lead, estimatedValue: 9_000)
        let spy = WriteSpy(result: .success(fresh))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.value)
        await controller.saveValue("21000")

        XCTAssertEqual(spy.changes, [.value(21_000)])
        XCTAssertEqual(
            lead.estimatedValue, 9_000,
            "The server's row wins — the operator sees the truth, not their guess"
        )
    }

    func testSuccessfulContactSaveSendsBothHalves() async {
        let lead = makeLead(phone: "604-555-0142", email: "helen@example.com")
        let fresh = serverRow(from: lead, phone: "604-555-9999", email: nil)
        let spy = WriteSpy(result: .success(fresh))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.contact)
        await controller.saveContact(phone: " 604-555-9999 ", email: "   ")

        XCTAssertEqual(
            spy.changes,
            [.contact(phone: "604-555-9999", email: nil)],
            "Trimmed-empty clears the field; whitespace is never persisted as a value"
        )
        XCTAssertEqual(lead.contactPhone, "604-555-9999")
        XCTAssertNil(lead.contactEmail)
    }

    /// Clearing the street clears the pin. A coordinate with no address is a
    /// map hero pointing at nothing.
    func testClearingAddressAlsoClearsCoordinates() async {
        let lead = makeLead()
        let spy = WriteSpy(result: .success(serverRow(from: lead)))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.address)
        await controller.saveAddress("   ", latitude: 49.28, longitude: -123.12)

        XCTAssertEqual(spy.changes, [.address(nil, latitude: nil, longitude: nil)])
    }

    /// Emptying the value sends an explicit nil, not a zero. Zero is a real
    /// number and would pollute pipeline totals.
    func testClearingValueSendsNilNotZero() async {
        let lead = makeLead()
        let spy = WriteSpy(result: .success(serverRow(from: lead)))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.value)
        await controller.saveValue("")

        XCTAssertEqual(spy.changes, [.value(nil)])
    }

    func testClientCommitSendsTheChosenClient() async {
        let lead = makeLead(clientId: nil)
        let fresh = serverRow(from: lead, clientId: "33333333-3333-3333-3333-333333333333")
        let spy = WriteSpy(result: .success(fresh))
        let controller = makeController(lead: lead, spy: spy)

        await controller.commitClient(
            id: "33333333-3333-3333-3333-333333333333",
            name: "Calloway Homes"
        )

        XCTAssertEqual(spy.changes, [.client(id: "33333333-3333-3333-3333-333333333333")])
        XCTAssertEqual(lead.clientId, "33333333-3333-3333-3333-333333333333")
        XCTAssertNil(controller.editing)
    }

    // MARK: - 5. A failed write surfaces and preserves input

    /// The core of the honest-failure contract. The editor STAYS OPEN — which
    /// is precisely what leaves the operator's typing on screen, because the
    /// draft lives in the mounted editor's own state — and the failure is
    /// stated rather than swallowed.
    func testFailedSaveKeepsTheEditorOpenAndSaysSo() async {
        let lead = makeLead(address: "1240 Maple Ave")
        let spy = WriteSpy(result: .failure(StubError(description: "The network connection was lost")))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.address)
        await controller.saveAddress("3185 Fairview Rd", latitude: nil, longitude: nil)

        XCTAssertTrue(
            controller.isEditing(.address),
            "A failed write must NOT close the editor — closing it is what throws the operator's input away"
        )
        XCTAssertEqual(controller.failure(for: .address), .offline)
        XCTAssertFalse(controller.isSaving)
        XCTAssertFalse(controller.didCompleteAnEdit)
        XCTAssertEqual(
            lead.address, "1240 Maple Ave",
            "A write that did not land must not be reflected on the lead"
        )
    }

    /// RETRY resends the identical change. The operator retypes nothing.
    func testRetryResendsTheSameChangeAndCanSucceed() async {
        let lead = makeLead(address: "1240 Maple Ave")
        let spy = WriteSpy(result: .failure(StubError(description: "The network connection was lost")))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.address)
        await controller.saveAddress("3185 Fairview Rd", latitude: 49.5, longitude: -123.5)
        XCTAssertEqual(controller.failure(for: .address), .offline)

        spy.result = .success(serverRow(
            from: lead,
            address: "3185 Fairview Rd",
            latitude: 49.5,
            longitude: -123.5
        ))
        await controller.retry()

        XCTAssertEqual(spy.callCount, 2)
        XCTAssertEqual(
            spy.changes[0], spy.changes[1],
            "RETRY must resend the operator's input byte for byte"
        )
        XCTAssertEqual(lead.address, "3185 Fairview Rd")
        XCTAssertNil(controller.editing)
        XCTAssertNil(controller.failure)
    }

    /// A failed client link keeps the operator's CHOICE, so retry does not send
    /// them back to the picker.
    func testFailedClientLinkHoldsTheChoiceForRetry() async {
        let lead = makeLead(clientId: nil)
        let spy = WriteSpy(result: .failure(StubError(description: "Request timed out")))
        let controller = makeController(lead: lead, spy: spy)

        await controller.commitClient(id: "abc", name: "Calloway Homes")

        XCTAssertTrue(controller.isEditing(.client))
        XCTAssertEqual(controller.failure(for: .client), .offline)
        XCTAssertEqual(controller.pendingClientName, "Calloway Homes")
        XCTAssertNil(lead.clientId)

        spy.result = .success(serverRow(from: lead, clientId: "abc"))
        await controller.retry()

        XCTAssertEqual(spy.changes, [.client(id: "abc"), .client(id: "abc")])
        XCTAssertEqual(lead.clientId, "abc")
    }

    /// One field's failure never bleeds onto another field's row.
    func testFailureIsScopedToTheFieldThatFailed() async {
        let lead = makeLead()
        let spy = WriteSpy(result: .failure(StubError(description: "boom")))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.value)
        await controller.saveValue("21000")

        XCTAssertEqual(controller.failure(for: .value), .failed)
        XCTAssertNil(controller.failure(for: .address))
        XCTAssertNil(controller.failure(for: .contact))
        XCTAssertNil(controller.failure(for: .client))
    }

    /// Cancelling after a failure is the operator's deliberate discard. Only
    /// then does the input go away.
    func testCancelAfterFailureClearsEverything() async {
        let lead = makeLead()
        let spy = WriteSpy(result: .failure(StubError(description: "boom")))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.value)
        await controller.saveValue("21000")
        controller.cancel()

        XCTAssertNil(controller.editing)
        XCTAssertNil(controller.failure)
        await controller.retry()
        XCTAssertEqual(spy.callCount, 1, "A cancelled edit has nothing left to retry")
    }

    // MARK: - 6. Malformed money never reaches the wire

    func testMalformedValueIsBlockedBeforeTheRequest() async {
        let lead = makeLead()
        let spy = WriteSpy(result: .success(serverRow(from: lead)))
        let controller = makeController(lead: lead, spy: spy)

        controller.begin(.value)
        await controller.saveValue("twelve hundred")

        XCTAssertEqual(spy.callCount, 0, "A refused parse must never leave the device")
        XCTAssertEqual(controller.failure(for: .value), .failed)
        XCTAssertTrue(controller.isEditing(.value))
    }

    func testMoneyParsingMatchesTheLeadForm() {
        XCTAssertEqual(LeadFieldValue.money("14,200"), 14_200)
        XCTAssertEqual(LeadFieldValue.money("14200.50"), 14_200.50)
        XCTAssertNil(LeadFieldValue.money(""))
        XCTAssertNil(LeadFieldValue.money("abc"))
        // The numeric(12,2) ceiling guard LeadForm already enforces.
        XCTAssertNil(LeadFieldValue.money("99999999999999"))

        XCTAssertFalse(LeadFieldValue.moneyIsMalformed(""), "Blank is a deliberate clear, not a mistake")
        XCTAssertFalse(LeadFieldValue.moneyIsMalformed("   "))
        XCTAssertTrue(LeadFieldValue.moneyIsMalformed("abc"))
    }

    // MARK: - 7. Failure vocabulary

    func testFailureClassificationAndCopy() {
        XCTAssertEqual(
            LeadFieldSaveFailure.classify(StubError(description: "The network connection was lost")),
            .offline
        )
        XCTAssertEqual(
            LeadFieldSaveFailure.classify(StubError(description: "new row violates row-level security policy")),
            .notAllowed
        )
        XCTAssertEqual(
            LeadFieldSaveFailure.classify(StubError(description: "PGRST100 unexpected token")),
            .failed
        )

        // Retrying a refusal would just fail again — offering it would be a lie.
        XCTAssertFalse(LeadFieldSaveFailure.notAllowed.canRetry)
        XCTAssertTrue(LeadFieldSaveFailure.offline.canRetry)
        XCTAssertTrue(LeadFieldSaveFailure.failed.canRetry)

        // Every failure states what happened AND that nothing was lost.
        for failure in [LeadFieldSaveFailure.offline, .notAllowed, .failed] {
            XCTAssertTrue(failure.label.hasPrefix("// ERROR — "), "MOBILE.md §10 error shape")
            XCTAssertFalse(failure.message.isEmpty)
            XCTAssertFalse(failure.message.contains("!"), "OPS copy never shouts")
        }
        XCTAssertTrue(LeadFieldSaveFailure.offline.message.contains("Nothing was lost"))
        XCTAssertTrue(LeadFieldSaveFailure.failed.message.contains("Nothing was lost"))
    }

    // MARK: - 8. The discovery hint retires itself

    func testHintIsOnlyOfferedToOperatorsWhoCanEdit() {
        XCTAssertTrue(LeadHoldHint.shouldShow(state: 0, canEdit: true))
        XCTAssertFalse(
            LeadHoldHint.shouldShow(state: 0, canEdit: false),
            "Teaching a viewer a gesture they cannot use is noise"
        )
    }

    func testHintRetiresOnItsOwnAfterAFewOpens() {
        var state = 0
        for _ in 0..<LeadHoldHint.showLimit {
            XCTAssertTrue(LeadHoldHint.shouldShow(state: state, canEdit: true))
            state = LeadHoldHint.advanced(state)
        }
        XCTAssertFalse(
            LeadHoldHint.shouldShow(state: state, canEdit: true),
            "An operator who never tries the gesture stops being told about it"
        )
        XCTAssertEqual(state, LeadHoldHint.showLimit, "The counter never runs away")
    }

    func testFirstCompletedEditRetiresTheHintForGood() async {
        XCTAssertTrue(LeadHoldHint.shouldShow(state: 1, canEdit: true))
        XCTAssertFalse(LeadHoldHint.shouldShow(state: LeadHoldHint.retired(), canEdit: true))

        // And a landed write is what flips it.
        let lead = makeLead()
        let spy = WriteSpy(result: .success(serverRow(from: lead)))
        let controller = makeController(lead: lead, spy: spy)
        XCTAssertFalse(controller.didCompleteAnEdit)

        controller.begin(.value)
        await controller.saveValue("21000")

        XCTAssertTrue(controller.didCompleteAnEdit)
    }
}
