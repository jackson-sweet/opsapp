import DeckKit
import XCTest
@testable import OPSDecks

@MainActor
final class OPSDecksRuntimeFactoryTests: XCTestCase {
    func testStandaloneRuntimeUsesFullDesignerSurface() {
        let runtime = OPSDecksRuntimeFactory.make(companyId: "deck-company")

        XCTAssertEqual(runtime.context.companyId, "deck-company")
        XCTAssertNil(runtime.context.projectId)
        XCTAssertEqual(runtime.context.appSurface, .opsDecks)
        XCTAssertEqual(DeckCapabilities.forSurface(runtime.context.appSurface), .full)
        XCTAssertNotEqual(DeckCapabilities.full, DeckCapabilities.light)
        XCTAssertTrue(DeckCapabilities.full.contains(.plausibleFrame))
        XCTAssertTrue(DeckCapabilities.full.contains(.groundCover))
    }
}
