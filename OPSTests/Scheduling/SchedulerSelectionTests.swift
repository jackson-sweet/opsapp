//
//  SchedulerSelectionTests.swift
//  OPSTests
//
//  The schedule sheet's date-selection machine, plus a render smoke test for
//  the day cell it drives. The machine is the whole contract between tapping a
//  day and being allowed to save, so it is pinned here rather than inferred
//  from the view.
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class SchedulerSelectionTests: XCTestCase {

    private let calendar = Calendar.current

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    // MARK: - Transitions

    func testFirstTapStartsAndSecondTapCompletesARange() {
        var selection = SchedulerSelection.none
        XCTAssertFalse(selection.isCommittable)

        selection = selection.tapping(day(2026, 8, 10), calendar: calendar)
        XCTAssertEqual(selection, .start(day(2026, 8, 10)))
        XCTAssertFalse(selection.isCommittable)

        selection = selection.tapping(day(2026, 8, 13), calendar: calendar)
        XCTAssertEqual(selection, .range(day(2026, 8, 10), day(2026, 8, 13)))
        XCTAssertTrue(selection.isCommittable)
        XCTAssertEqual(selection.dayCount(calendar: calendar), 4)
    }

    func testABackwardsSecondTapSortsItselfIntoAValidRange() {
        let selection = SchedulerSelection
            .start(day(2026, 8, 13))
            .tapping(day(2026, 8, 10), calendar: calendar)

        XCTAssertEqual(selection, .range(day(2026, 8, 10), day(2026, 8, 13)))
        XCTAssertTrue(selection.isCommittable)
    }

    func testTappingTheSameDayTwiceIsAOneDayJob() {
        let selection = SchedulerSelection
            .none
            .tapping(day(2026, 8, 10), calendar: calendar)
            .tapping(day(2026, 8, 10), calendar: calendar)

        XCTAssertEqual(selection, .range(day(2026, 8, 10), day(2026, 8, 10)))
        XCTAssertEqual(selection.dayCount(calendar: calendar), 1)
        XCTAssertTrue(selection.isCommittable)
    }

    func testTappingWithACompleteRangeRestartsFromThatDay() {
        let selection = SchedulerSelection
            .range(day(2026, 8, 10), day(2026, 8, 13))
            .tapping(day(2026, 8, 20), calendar: calendar)

        XCTAssertEqual(selection, .start(day(2026, 8, 20)))
        XCTAssertFalse(selection.isCommittable)
    }

    func testPrefillFromPersistedDatesMakesSaveImmediatelyValid() {
        let prefilled = SchedulerSelection.prefilled(
            start: day(2026, 8, 10),
            end: day(2026, 8, 12),
            calendar: calendar
        )
        XCTAssertEqual(prefilled, .range(day(2026, 8, 10), day(2026, 8, 12)))
        XCTAssertTrue(prefilled.isCommittable)

        XCTAssertEqual(
            SchedulerSelection.prefilled(start: day(2026, 8, 10), end: nil, calendar: calendar),
            .start(day(2026, 8, 10))
        )
        XCTAssertEqual(
            SchedulerSelection.prefilled(start: nil, end: nil, calendar: calendar),
            .none
        )
        // A record whose dates were stored backwards still opens as a range.
        XCTAssertEqual(
            SchedulerSelection.prefilled(start: day(2026, 8, 12), end: day(2026, 8, 10), calendar: calendar),
            .range(day(2026, 8, 10), day(2026, 8, 12))
        )
    }

    func testClearingReturnsToTheEmptySelectionWithoutTouchingPersistedDates() {
        // CLEAR is a local reset — the machine simply returns to `.none`, and
        // nothing in the machine can unschedule anything.
        var selection = SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 12))
        selection = .none
        XCTAssertNil(selection.startDate)
        XCTAssertNil(selection.endDate)
        XCTAssertFalse(selection.isCommittable)
    }

    // MARK: - Day-inspector action

    func testTheDaySheetOffersEndOnlyWhileAStartIsWaiting() {
        XCTAssertEqual(SchedulerSelection.none.dayAction, .useAsStart)
        XCTAssertEqual(SchedulerSelection.start(day(2026, 8, 10)).dayAction, .useAsEnd)
        XCTAssertEqual(
            SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 12)).dayAction,
            .useAsStart
        )
    }

    func testUseAsStartFromACompleteRangeRestartsAtThatDay() {
        let selection = SchedulerSelection
            .range(day(2026, 8, 10), day(2026, 8, 12))
            .tapping(day(2026, 8, 25), calendar: calendar)

        XCTAssertEqual(selection, .start(day(2026, 8, 25)))
    }

    // MARK: - Day roles (what each cell draws)

    func testDayRolesDescribeCapsInteriorAndOutside() {
        let selection = SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 13))

        XCTAssertEqual(selection.role(for: day(2026, 8, 9), calendar: calendar), .none)
        XCTAssertEqual(selection.role(for: day(2026, 8, 10), calendar: calendar), .start)
        XCTAssertEqual(selection.role(for: day(2026, 8, 11), calendar: calendar), .interior)
        XCTAssertEqual(selection.role(for: day(2026, 8, 13), calendar: calendar), .end)
        XCTAssertEqual(selection.role(for: day(2026, 8, 14), calendar: calendar), .none)
    }

    func testAHalfMadeSelectionDrawsAClosedCapNotAnOpenBar() {
        let selection = SchedulerSelection.start(day(2026, 8, 10))
        XCTAssertEqual(selection.role(for: day(2026, 8, 10), calendar: calendar), .single)
        XCTAssertEqual(selection.role(for: day(2026, 8, 11), calendar: calendar), .none)
    }

    func testASingleDayRangeDrawsOneCap() {
        let selection = SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 10))
        XCTAssertEqual(selection.role(for: day(2026, 8, 10), calendar: calendar), .single)
    }

    // MARK: - Render smoke

    /// Renders the day cell in every signal state through a real
    /// UIHostingController in a UIWindow. ImageRenderer cannot resolve OPS
    /// asset colours, so this is the only harness that proves the cell paints.
    func testDayCellRendersEverySignalState() {
        let states: [(String, SchedulerDayContext.DaySignals, SchedulerSelection.DayRole)] = [
            ("clear", .init(), .none),
            ("this_project", .init(thisProject: true), .none),
            ("crew_busy", .init(crewBusy: true), .none),
            ("crew_off", .init(crewTimeOff: true), .none),
            ("stacked", .init(thisProject: true, crewBusy: true, crewTimeOff: true, otherCount: 2), .none),
            ("pre_floor", .init(crewBusy: true, isPreFloor: true), .none),
            ("start_cap", .init(), .start),
            ("interior", .init(), .interior),
            ("end_cap", .init(), .end),
            ("single", .init(), .single)
        ]

        let size = CGSize(width: 52, height: OPSStyle.Layout.schedulerDayCellHeight)
        for (name, signals, role) in states {
            let host = UIHostingController(
                rootView: SchedulerDayCell(
                    date: Date(),
                    signals: signals,
                    role: role,
                    isToday: name == "clear",
                    onTap: {},
                    onLongPress: {}
                )
                .frame(width: size.width, height: size.height)
                .background(Color.black)
            )
            host.overrideUserInterfaceStyle = .dark
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.backgroundColor = .black

            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            XCTAssertNotNil(image.pngData(), "day cell state \(name) failed to render")
        }
    }
}
#endif
