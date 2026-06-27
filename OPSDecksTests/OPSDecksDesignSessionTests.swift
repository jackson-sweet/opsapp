import DeckKit
import XCTest
@testable import OPSDecks

@MainActor
final class OPSDecksDesignSessionTests: XCTestCase {
    func testStartNewDeckCreatesStandaloneDesignWithFullRuntime() throws {
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            savedDeckCount: 0,
            entitlement: .free(savedDeckLimit: 1)
        )

        XCTAssertTrue(session.startNewDeck())

        let activeDesign = try XCTUnwrap(session.activeDesign)
        XCTAssertEqual(activeDesign.document.companyId, "deck-company")
        XCTAssertNil(activeDesign.document.projectId)
        XCTAssertEqual(activeDesign.document.title, OPSDecksCopy.defaultDeckTitle)
        XCTAssertNotNil(DeckDrawingData.fromJSON(activeDesign.document.drawingDataJSON))
        XCTAssertEqual(activeDesign.runtime.context.companyId, "deck-company")
        XCTAssertNil(activeDesign.runtime.context.projectId)
        XCTAssertEqual(activeDesign.runtime.context.projectName, OPSDecksCopy.defaultDeckTitle)
        XCTAssertEqual(activeDesign.runtime.context.appSurface, .opsDecks)
        XCTAssertEqual(DeckCapabilities.forSurface(activeDesign.runtime.context.appSurface), .full)
    }

    func testStartNewDeckDoesNotCreateDesignWhenFreeLimitIsReached() {
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            savedDeckCount: 1,
            entitlement: .free(savedDeckLimit: 1)
        )

        XCTAssertFalse(session.startNewDeck())
        XCTAssertNil(session.activeDesign)
    }
}
