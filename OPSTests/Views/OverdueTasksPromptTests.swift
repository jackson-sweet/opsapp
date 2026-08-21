import SwiftUI
import XCTest
@testable import OPS

final class OverdueTasksPromptTests: XCTestCase {
    func testFailureStateStaysActionable() {
        XCTAssertEqual(OverdueReviewPresentation.actionLabel(hasError: false), "MARK DONE")
        XCTAssertEqual(OverdueReviewPresentation.actionLabel(hasError: true), "TRY AGAIN")
        XCTAssertEqual(OverdueReviewPresentation.failureLabel, "// COULD NOT MARK DONE")
    }

    func testAccessibilityTypeStacksTheRowAction() {
        XCTAssertFalse(OverdueReviewPresentation.stacksAction(for: .large))
        XCTAssertTrue(OverdueReviewPresentation.stacksAction(for: .accessibility1))
        XCTAssertTrue(OverdueReviewPresentation.stacksAction(for: .accessibility5))
    }

    func testPendingLastCompletionCannotDismissTheReview() {
        XCTAssertFalse(
            OverdueReviewPresentation.isReviewComplete(
                visibleTaskCount: 0,
                pendingCompletionCount: 1
            )
        )
        XCTAssertTrue(
            OverdueReviewPresentation.isReviewComplete(
                visibleTaskCount: 0,
                pendingCompletionCount: 0
            )
        )
    }
}

