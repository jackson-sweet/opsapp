import XCTest
@testable import OPSDecks

final class AccountDeletionPlannerTests: XCTestCase {
    func testDeletesSoleAdminDecksCompany() {
        let plan = AccountDeletionPlanner().plan(
            company: AccountDeletionCompanyRow(
                id: "co-1",
                adminIds: ["u-1"],
                subscriptionPlan: "decks",
                memberCount: 1
            ),
            userId: "u-1",
            deckIds: ["deck-1", "deck-2"]
        )

        XCTAssertEqual(plan.softDeleteDeckIds, ["deck-1", "deck-2"])
        XCTAssertTrue(plan.deleteCompany)
        XCTAssertTrue(plan.deleteUser)
        XCTAssertNil(plan.blockedReason)
    }

    func testBlocksDeletionOfUpgradedOpsCompany() {
        let plan = AccountDeletionPlanner().plan(
            company: AccountDeletionCompanyRow(
                id: "co-1",
                adminIds: ["u-1"],
                subscriptionPlan: "pro",
                memberCount: 1
            ),
            userId: "u-1",
            deckIds: ["deck-1"]
        )

        XCTAssertEqual(plan.softDeleteDeckIds, [])
        XCTAssertFalse(plan.deleteCompany)
        XCTAssertFalse(plan.deleteUser)
        XCTAssertEqual(plan.blockedReason, .upgradedOPSCompany)
    }

    func testBlocksDeletionWhenOtherMembersExist() {
        let plan = AccountDeletionPlanner().plan(
            company: AccountDeletionCompanyRow(
                id: "co-1",
                adminIds: ["u-1"],
                subscriptionPlan: "decks",
                memberCount: 2
            ),
            userId: "u-1",
            deckIds: ["deck-1"]
        )

        XCTAssertEqual(plan.softDeleteDeckIds, [])
        XCTAssertFalse(plan.deleteCompany)
        XCTAssertFalse(plan.deleteUser)
        XCTAssertEqual(plan.blockedReason, .otherMembersPresent)
    }

    func testBlocksDeletionWhenUserIsNotSoleAdmin() {
        let plan = AccountDeletionPlanner().plan(
            company: AccountDeletionCompanyRow(
                id: "co-1",
                adminIds: ["u-2"],
                subscriptionPlan: "decks",
                memberCount: 1
            ),
            userId: "u-1",
            deckIds: ["deck-1"]
        )

        XCTAssertEqual(plan.softDeleteDeckIds, [])
        XCTAssertFalse(plan.deleteCompany)
        XCTAssertFalse(plan.deleteUser)
        XCTAssertEqual(plan.blockedReason, .userIsNotSoleAdmin)
    }
}
