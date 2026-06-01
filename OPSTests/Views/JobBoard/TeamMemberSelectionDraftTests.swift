//
//  TeamMemberSelectionDraftTests.swift
//  OPSTests
//
//  Regression coverage for explicit crew-picker confirmation.
//

import XCTest
@testable import OPS

final class TeamMemberSelectionDraftTests: XCTestCase {

    func testCancelKeepsCommittedTeamMemberSelectionUntouched() {
        var draft = TeamMemberSelectionDraft(committedIds: ["crew-a"])

        draft.toggle("crew-b")

        XCTAssertEqual(draft.draftIds, ["crew-a", "crew-b"])
        XCTAssertEqual(draft.cancelledIds(), ["crew-a"])
    }

    func testConfirmReturnsOnlyExplicitlyCommittedDraftSelection() {
        var draft = TeamMemberSelectionDraft(committedIds: ["crew-a"])

        draft.toggle("crew-a")
        draft.toggle("crew-b")

        XCTAssertEqual(draft.confirmedIds(), ["crew-b"])
    }
}
