//
//  LeadClientAssignmentTests.swift
//  OPSTests
//
//  Bug 908888f6 — "Add client in lead details does not work."
//
//  It did work. `opportunities.client_id` was written and the server accepted
//  it; the CLIENT row simply went on saying otherwise. Two facts made the
//  dossier lie about a write that had landed:
//
//    1. The row decided "this lead has a client" from the FETCHED client row,
//       and the roster is fetched once, when the screen opens. A lead that had
//       no client at open time therefore had no client for the rest of the
//       session, no matter what was saved to it.
//    2. The view model froze the client link at construction, so even a reload
//       would have re-fetched nothing.
//
//  These tests pin both halves plus the seam between them: the row states the
//  LINK, and the roster follows the link.
//

import XCTest
@testable import OPS

@MainActor
final class LeadClientAssignmentTests: XCTestCase {

    // MARK: - Fixtures

    private static let leadId    = "11111111-1111-1111-1111-111111111111"
    private static let companyId = "22222222-2222-2222-2222-222222222222"
    private static let clientId  = "33333333-3333-3333-3333-333333333333"

    /// Records every roster fetch and answers with a fixed client.
    private final class RosterSpy {
        private(set) var clientRequests: [String] = []
        private(set) var subClientRequests: [String] = []
        var clientName = "Traditional Homes"
        var clientError: Error?

        func loader() -> LeadClientRosterLoader {
            LeadClientRosterLoader(
                client: { [weak self] id in
                    guard let self else { throw StubError() }
                    self.clientRequests.append(id)
                    if let error = self.clientError { throw error }
                    return Client(id: id, name: self.clientName)
                },
                subClients: { [weak self] id in
                    guard let self else { throw StubError() }
                    self.subClientRequests.append(id)
                    return [SubClient(id: "sub-\(id)", name: "Helen Calloway")]
                }
            )
        }
    }

    private struct StubError: Error {}

    private func makeViewModel(
        clientId: String?,
        spy: RosterSpy
    ) -> LeadDetailViewModel {
        LeadDetailViewModel(
            opportunityId: Self.leadId,
            companyId: Self.companyId,
            clientId: clientId,
            rosterLoader: spy.loader()
        )
    }

    // MARK: - 1. The roster follows the lead's CURRENT link

    /// The headline regression. A lead opened with no client gains one under
    /// the open dossier — the roster must go and fetch it. Before the fix this
    /// early-returned on a link captured at init and the CLIENT row never
    /// learned that the assignment had landed.
    func testRosterLoadsWhenTheLeadGainsItsFirstClient() async {
        let spy = RosterSpy()
        let vm = makeViewModel(clientId: nil, spy: spy)

        await vm.clientLinkChanged(to: Self.clientId)

        XCTAssertEqual(spy.clientRequests, [Self.clientId])
        XCTAssertEqual(spy.subClientRequests, [Self.clientId])
        XCTAssertEqual(vm.client?.id, Self.clientId)
        XCTAssertEqual(vm.client?.name, "Traditional Homes")
        XCTAssertEqual(vm.subClients.count, 1)
    }

    /// Re-assignment is the same rule: a DIFFERENT client re-fetches.
    func testRosterFollowsAReassignment() async {
        let spy = RosterSpy()
        let vm = makeViewModel(clientId: Self.clientId, spy: spy)

        spy.clientName = "Calloway Homes"
        await vm.clientLinkChanged(to: "44444444-4444-4444-4444-444444444444")

        XCTAssertEqual(spy.clientRequests, ["44444444-4444-4444-4444-444444444444"])
        XCTAssertEqual(vm.client?.name, "Calloway Homes")
    }

    /// Wiring this to a view's `onChange` has to be free, or the dossier would
    /// re-fetch the roster on every unrelated repaint.
    func testAnUnchangedLinkCostsNothing() async {
        let spy = RosterSpy()
        let vm = makeViewModel(clientId: Self.clientId, spy: spy)

        await vm.clientLinkChanged(to: Self.clientId)
        await vm.clientLinkChanged(to: Self.clientId)

        XCTAssertTrue(spy.clientRequests.isEmpty)
        XCTAssertTrue(spy.subClientRequests.isEmpty)
    }

    /// Blank is not a link. `client_id` arrives as an optional string that is
    /// sometimes an empty one; treating that as a client would fetch nothing
    /// and then claim a client exists.
    func testBlankLinkIsNoLink() async {
        let spy = RosterSpy()
        let vm = makeViewModel(clientId: nil, spy: spy)

        await vm.clientLinkChanged(to: "   ")

        XCTAssertTrue(spy.clientRequests.isEmpty)
        XCTAssertNil(vm.client)
    }

    /// Unlinking clears the roster rather than leaving the last client it
    /// happened to hold sitting on a lead that no longer has one.
    func testUnlinkingClearsTheRoster() async {
        let spy = RosterSpy()
        let vm = makeViewModel(clientId: nil, spy: spy)
        await vm.clientLinkChanged(to: Self.clientId)
        XCTAssertNotNil(vm.client)

        await vm.clientLinkChanged(to: nil)

        XCTAssertNil(vm.client)
        XCTAssertTrue(vm.subClients.isEmpty)
    }

    /// A roster fetch that fails must not take the sub-client fetch with it,
    /// and must not wipe the screen — the dossier's every load fails soft.
    func testAFailedClientFetchStillLoadsTheSubClients() async {
        let spy = RosterSpy()
        spy.clientError = StubError()
        let vm = makeViewModel(clientId: nil, spy: spy)

        await vm.clientLinkChanged(to: Self.clientId)

        XCTAssertNil(vm.client)
        XCTAssertEqual(vm.subClients.count, 1)
    }

    // MARK: - 2. The CLIENT row states the LINK, not the fetch

    /// The exact shape of the bug: the write landed, `client_id` is set, and
    /// the client's own row has not come back yet. The row must NOT fall back
    /// to inviting an assignment that already happened — and it names the link
    /// the way the PROJECT row names an unnamed one, because an em dash there
    /// would read as "no client", which is the same lie by a shorter route.
    func testLinkedTheMomentTheLeadHasAClientId() {
        let state = LeadDetailsDocument.clientRowState(
            clientId: Self.clientId,
            rosterName: nil,
            pickedName: nil,
            isSaving: false
        )
        XCTAssertEqual(state, .linked(name: "LINKED CLIENT"))
        XCTAssertFalse(state.isLinking)
    }

    /// In that same gap the row shows the name the operator just picked, so a
    /// filled row never blinks back to an em dash on its way to the truth.
    func testTheJustPickedNameCarriesTheRowUntilTheRosterArrives() {
        XCTAssertEqual(
            LeadDetailsDocument.clientRowState(
                clientId: Self.clientId,
                rosterName: nil,
                pickedName: "Traditional Homes",
                isSaving: false
            ),
            .linked(name: "Traditional Homes")
        )
    }

    /// Once the roster answers, the client on file wins — the row is never a
    /// lasting echo of what was typed at it.
    func testTheRosterNameWinsOverThePickedName() {
        XCTAssertEqual(
            LeadDetailsDocument.clientRowState(
                clientId: Self.clientId,
                rosterName: "Traditional Homes",
                pickedName: "Tradtional Homes",
                isSaving: false
            ),
            .linked(name: "Traditional Homes")
        )
    }

    /// The write in flight is its own state — that is what earns the spinner.
    func testTheWriteInFlightIsLinking() {
        let state = LeadDetailsDocument.clientRowState(
            clientId: nil,
            rosterName: nil,
            pickedName: "Traditional Homes",
            isSaving: true
        )
        XCTAssertEqual(state, .linking(name: "Traditional Homes"))
        XCTAssertTrue(state.isLinking)
    }

    /// ASSIGN CLIENT survives for the case it was written for: a lead with no
    /// client, nothing on the wire, nothing picked.
    func testAbsentOnlyWhenThereIsNoClientAtAll() {
        for blank in [nil, "", "   "] as [String?] {
            XCTAssertEqual(
                LeadDetailsDocument.clientRowState(
                    clientId: blank,
                    rosterName: nil,
                    pickedName: nil,
                    isSaving: false
                ),
                .absent,
                "A lead with no client link must still invite one"
            )
        }
    }

    /// Snapshot and preview hosts hand the document a client without a link.
    /// They keep rendering the client, not the invitation.
    func testAFetchedClientAloneStillRendersAsLinked() {
        XCTAssertEqual(
            LeadDetailsDocument.clientRowState(
                clientId: nil,
                rosterName: "Traditional Homes",
                pickedName: nil,
                isSaving: false
            ),
            .linked(name: "Traditional Homes")
        )
    }
}
