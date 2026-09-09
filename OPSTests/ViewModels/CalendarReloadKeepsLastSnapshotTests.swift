import SwiftData
import XCTest
@testable import OPS

/// Bug a4225f3f — "When I make a schedule change, the UI flashes, all events
/// disappear momentarily, then the change takes effect." The data-change
/// reload emptied the day caches up front, so the day read as empty for the
/// length of the off-main replacement. The last snapshot now stays on screen
/// through a reload; a scope or filter change still clears, because a stale
/// row under a fresh filter would be a lie.
@MainActor
final class CalendarReloadKeepsLastSnapshotTests: XCTestCase {

    func testDataChangeReloadKeepsTheDayOnScreenAndAScopeChangeClearsIt() {
        let viewModel = CalendarViewModel()
        let monday = Calendar.current.startOfDay(for: Date())
        let key = CalendarDayKey.key(for: monday)
        let task = ProjectTask(id: "t-mon", projectId: "p-1", taskTypeId: "tt-1", companyId: "c-1")
        viewModel.applyWeekCache(
            CalendarWeekCacheSnapshot(weekStart: monday, taskIdsByDay: [key: ["t-mon"]], countsByDay: [key: 1]),
            resolving: [task]
        )
        XCTAssertEqual(viewModel.scheduledTasks(for: monday).map(\.id), ["t-mon"])

        // The product entry point for "a task changed" — must not blank the day.
        viewModel.reloadCalendarData()
        XCTAssertEqual(
            viewModel.scheduledTasks(for: monday).map(\.id), ["t-mon"],
            "a data-change reload keeps the last snapshot on screen until the replacement lands"
        )

        viewModel.invalidateForReload()
        XCTAssertEqual(viewModel.scheduledTasks(for: monday).map(\.id), ["t-mon"])

        // A scope / filter change alters what a row means — that still clears.
        viewModel.clearProjectCountCache()
        XCTAssertTrue(viewModel.scheduledTasks(for: monday).isEmpty)
    }
}
