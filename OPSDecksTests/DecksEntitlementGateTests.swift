import XCTest
@testable import OPSDecks

final class DecksEntitlementGateTests: XCTestCase {
    func testFreeUserCanSaveFirstDeck() {
        let gate = DecksEntitlementGate(entitlement: .free(savedDeckLimit: 1))

        XCTAssertEqual(gate.decision(savedDeckCount: 0), .allowSave)
    }

    func testFreeUserCannotSaveSecondDeck() {
        let gate = DecksEntitlementGate(entitlement: .free(savedDeckLimit: 1))

        XCTAssertEqual(gate.decision(savedDeckCount: 1), .requiresPro)
    }

    func testProUserCanSaveUnlimitedDecks() {
        let gate = DecksEntitlementGate(entitlement: .pro)

        XCTAssertEqual(gate.decision(savedDeckCount: 99), .allowSave)
    }

    func testFreeUserWithZeroLimitRequiresPro() {
        let gate = DecksEntitlementGate(entitlement: .free(savedDeckLimit: 0))

        XCTAssertEqual(gate.decision(savedDeckCount: 0), .requiresPro)
    }
}
