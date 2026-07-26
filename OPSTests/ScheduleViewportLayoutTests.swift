#if DEBUG
import XCTest
@testable import OPS

final class ScheduleViewportLayoutTests: XCTestCase {

    func testWeekViewportIsFullBleedWithoutWizard() {
        XCTAssertEqual(
            ScheduleViewportLayout.outerBottomInset(
                isMonthExpanded: false,
                wizardActive: false
            ),
            0
        )
    }

    func testWeekViewportIsFullBleedWithWizard() {
        XCTAssertEqual(
            ScheduleViewportLayout.outerBottomInset(
                isMonthExpanded: false,
                wizardActive: true
            ),
            0
        )
    }

    func testExpandedMonthOnlyReservesWizardClearanceWhenActive() {
        XCTAssertEqual(
            ScheduleViewportLayout.outerBottomInset(
                isMonthExpanded: true,
                wizardActive: false
            ),
            0
        )
        XCTAssertEqual(
            ScheduleViewportLayout.outerBottomInset(
                isMonthExpanded: true,
                wizardActive: true
            ),
            OPSStyle.Layout.wizardInstructionBarClearance
        )
    }
}
#endif
