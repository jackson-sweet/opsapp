//
//  MonthDaySheetWindowTests.swift
//  OPSTests
//
//  Bug 83a01905 — "Nothing showing in day sheet on month view."
//
//  The month grid draws bars from the month-wide preview cache, but the day
//  sheet reads the 21-day week cache anchored on the SELECTED date. Tapping a
//  day in a far month therefore read an un-recentered cache and reported
//  "0 events" under a grid full of bars. The fix routes every month-grid day
//  tap through selectDate(_:userInitiated:), which recenters the window.
//  These tests lock the window mechanics; the tap wiring itself is one-line
//  call sites in MonthGridView (the EventBar tap, the EventBar day-details
//  action, and the MonthDayCell tap).
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class MonthDaySheetWindowTests: XCTestCase {

    /// A day far outside the 21-day window around today — the month-view case.
    private var fiveWeeksOut: Date {
        Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 35, to: Date())!
        )
    }

    /// A `ModelContext` does not keep its `ModelContainer` alive — retain it for
    /// the case lifetime or the next insert traps inside SwiftData.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - Tests

    /// The exact broken read: without recentering, a far day answers [].
    /// With selectedDate moved onto the far day, the awaitable reload must
    /// land that day's tasks in the sheet's read path.
    func testRecenteredReloadServesAFarMonthDay() async throws {
        let fixture = try makeCalendarFixture()
        defer { fixture.restorePermissions() }

        // Baseline (today-anchored window): the far day reads empty — this is
        // the pre-fix symptom, asserted so the test proves the mechanism and
        // not an accident of seeding.
        await fixture.viewModel.reloadCalendarDataOffMain()
        XCTAssertTrue(fixture.viewModel.scheduledTasks(for: fiveWeeksOut).isEmpty)

        // What the month-grid tap now does: select, then reload around it.
        fixture.viewModel.selectedDate = fiveWeeksOut
        await fixture.viewModel.reloadCalendarDataOffMain()

        XCTAssertEqual(
            fixture.viewModel.scheduledTasks(for: fiveWeeksOut).map(\.id),
            ["task-far"],
            "Recentering the window on the tapped day must surface its tasks in the day sheet's read path."
        )
    }

    /// The fire-and-forget path the actual tap takes. selectDate schedules an
    /// off-main load; poll the cache with a deadline (never a fixed sleep).
    func testSelectDateRecentersTheWindowForTheSheet() throws {
        let fixture = try makeCalendarFixture()
        defer { fixture.restorePermissions() }

        fixture.viewModel.selectDate(fiveWeeksOut, userInitiated: true)

        let deadline = Date(timeIntervalSinceNow: 5)
        while fixture.viewModel.scheduledTasks(for: fiveWeeksOut).isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertEqual(
            fixture.viewModel.scheduledTasks(for: fiveWeeksOut).map(\.id),
            ["task-far"]
        )
    }

    /// The sheet's content gate: while the recentered snapshot is in flight an
    /// empty count means LOADING, never the empty state — the empty flash IS
    /// the reported bug ("0 events" under a grid of bars).
    func testSheetContentStateNeverShowsEmptyWhileLoading() {
        XCTAssertEqual(DayDetailsSheetContentState.resolve(isLoading: true, eventCount: 0), .loading)
        XCTAssertEqual(DayDetailsSheetContentState.resolve(isLoading: false, eventCount: 0), .empty)
        XCTAssertEqual(DayDetailsSheetContentState.resolve(isLoading: true, eventCount: 3), .populated)
        XCTAssertEqual(DayDetailsSheetContentState.resolve(isLoading: false, eventCount: 1), .populated)
    }

    // MARK: - Fixtures

    /// A real store with one live job carrying a single task scheduled five
    /// weeks out, plus a DataController and CalendarViewModel wired the way the
    /// app wires them.
    private struct CalendarFixture {
        let context: ModelContext
        let dataController: DataController
        let viewModel: CalendarViewModel
        let restorePermissions: () -> Void
    }

    private func makeCalendarFixture() throws -> CalendarFixture {
        let container = try makeInMemoryContainer()
        retainedContainers.append(container)
        let context = ModelContext(container)

        let previousPermissions = PermissionStore.shared.permissions
        let previousBlocked = PermissionStore.shared.blockedByFlags
        PermissionStore.shared.permissions = ["tasks.view": "all", "calendar.view": "all"]
        PermissionStore.shared.blockedByFlags = []

        let dataController = DataController()
        dataController.setModelContext(context)

        let user = User(
            id: "user-1", firstName: "Marcus", lastName: "Hale",
            role: .crew, companyId: "co"
        )
        context.insert(user)

        // `DataController.init` fires a one-shot `checkExistingAuth()`; with no
        // stored credentials it calls `clearAuthentication()`, which nils
        // `currentUser`. Seed the operator, wait for that clear to actually
        // land, then seed again — otherwise the async clear lands mid-test and
        // every fetch guarded on `currentUser` silently returns []. Waiting on
        // the observed event, not a fixed sleep; the bound only guards the case
        // where the environment never clears at all.
        dataController.currentUser = user
        let authSettled = Date(timeIntervalSinceNow: 5)
        while dataController.currentUser != nil, Date() < authSettled {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        dataController.currentUser = user

        let farProject = Project(id: "p-far", title: "North stair rebuild", status: .inProgress)
        farProject.companyId = "co"
        context.insert(farProject)

        let scheduled = ProjectTask(
            id: "task-far", projectId: farProject.id, taskTypeId: "tt", companyId: "co"
        )
        let farDay = fiveWeeksOut
        scheduled.startDate = farDay
        scheduled.endDate = farDay
        scheduled.teamMemberIdsString = "user-1"
        scheduled.project = farProject
        context.insert(scheduled)
        try context.save()

        let viewModel = CalendarViewModel()
        viewModel.dataController = dataController
        viewModel.selectedDate = Calendar.current.startOfDay(for: Date())

        return CalendarFixture(
            context: context,
            dataController: dataController,
            viewModel: viewModel,
            restorePermissions: {
                PermissionStore.shared.permissions = previousPermissions
                PermissionStore.shared.blockedByFlags = previousBlocked
            }
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            SyncOperation.self,
            CalendarUserEvent.self,
            SiteVisit.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
