import UIKit
import XCTest
@testable import OPS

final class ClientSheetDuplicateRoutingTests: XCTestCase {
    func testUseExistingTransitionsCreateSessionToEditAndHydratesExistingClient() {
        var session = ClientSheet.Session(
            mode: .create,
            prefilledName: "Abandoned draft"
        )
        session.email = "draft@ops.test"
        session.phone = "2505550100"
        session.address = "1 Draft Road"
        session.notes = "Draft notes"
        session.tempNotes = "Unsaved draft notes"
        session.clientImage = UIImage()

        let existingClient = Client(
            id: "existing-client",
            name: "Existing Client",
            email: "existing@ops.test",
            phoneNumber: "6045550100",
            address: "123 Existing Road",
            companyId: "company",
            notes: "Persisted notes"
        )
        existingClient.profileImageURL = "https://example.com/existing-client.jpg"

        let action = ClientSheet.resolveDuplicateSelection(
            existingClient,
            from: session
        )

        guard case .editInPlace(let resolvedSession) = action else {
            return XCTFail("Using a suspected duplicate must route to in-place editing")
        }
        session = resolvedSession

        guard case .edit(let routedClient) = session.mode else {
            return XCTFail("Using a suspected duplicate must keep the sheet open in edit mode")
        }

        XCTAssertEqual(routedClient.id, existingClient.id)
        XCTAssertEqual(session.name, existingClient.name)
        XCTAssertEqual(session.email, existingClient.email)
        XCTAssertEqual(session.phone, existingClient.phoneNumber)
        XCTAssertEqual(session.address, existingClient.address)
        XCTAssertEqual(session.notes, existingClient.notes)
        XCTAssertEqual(session.clientImageURL, existingClient.profileImageURL)
        XCTAssertNil(session.clientImage)
        XCTAssertEqual(session.tempNotes, "")
    }
}
