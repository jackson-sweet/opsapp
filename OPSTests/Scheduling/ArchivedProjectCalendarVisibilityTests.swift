//
//  ArchivedProjectCalendarVisibilityTests.swift
//  OPSTests
//
//  Bug 9997c11c — archiving a job did nothing to the calendar. Its tasks kept
//  drawing on the week canvas, kept occupying month-grid rows, and kept
//  manufacturing phantom conflicts inside the scheduler sheet's day inspector.
//  Nothing in the calendar layer had ever consulted project status.
//
//  These pin the rule and its three consumer surfaces:
//    • the shared predicate itself (archived hidden, everything else visible),
//    • the week canvas + month grid, which share CalendarViewModel.applyTaskFilters,
//    • the scheduler sheet's availability engine, which must stop counting
//      archived work as a conflict.
//
//  The rule is deliberately narrow: ONLY `.archived`. `.closed` jobs still
//  belong on a calendar (they are finished, not filed away), and `isActive`
//  would have erased every rfq/estimated job that is legitimately scheduled.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class ArchivedProjectCalendarVisibilityTests: XCTestCase {

    private let calendar = Calendar.current

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    // MARK: - The shared predicate

    func testTaskOnArchivedProjectIsHidden() {
        XCTAssertFalse(
            CalendarTaskVisibility.includes(projectId: "p-archived", archivedProjectIds: ["p-archived"]),
            "An archived job's task must not reach any calendar surface."
        )
    }

    func testTaskWhoseProjectIsNotArchivedIsVisible() {
        XCTAssertTrue(
            CalendarTaskVisibility.includes(projectId: "p-live", archivedProjectIds: ["p-archived"])
        )
    }

    /// The inverse of `TaskReviewQuery`'s `?? false`: there, an unresolvable
    /// project means "not schedulable work, hide it". Here it must mean the
    /// opposite. A project row that has not synced down yet — or a task whose
    /// `project` relationship linking has not run — is real scheduled work with
    /// a crew expecting to show up. Hiding it because the client happens to be
    /// missing a row would lose a day of work; showing it costs nothing.
    func testTaskWithNoKnownProjectStaysVisible() {
        XCTAssertTrue(
            CalendarTaskVisibility.includes(projectId: "p-never-synced", archivedProjectIds: ["p-archived"]),
            "An unsynced or unlinked project must never hide real scheduled work."
        )
        XCTAssertTrue(
            CalendarTaskVisibility.includes(projectId: "", archivedProjectIds: ["p-archived"])
        )
    }

    func testEveryNonArchivedStatusStaysVisible() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let live: [Status] = [.rfq, .estimated, .accepted, .inProgress, .completed, .closed]
        for status in live {
            context.insert(Project(id: status.rawValue, title: status.displayName, status: status))
        }
        context.insert(Project(id: "archived", title: "Filed away", status: .archived))

        let archivedIds = CalendarTaskVisibility.archivedProjectIds(in: context)

        XCTAssertEqual(archivedIds, ["archived"], "Only `.archived` may ever land in the exclusion set.")
        for status in live {
            XCTAssertTrue(
                CalendarTaskVisibility.includes(projectId: status.rawValue, archivedProjectIds: archivedIds),
                "\(status.displayName) is live work and must stay on the calendar."
            )
        }
    }

    func testArchivedProjectIdsIsEmptyWithoutAContext() {
        XCTAssertEqual(CalendarTaskVisibility.archivedProjectIds(in: nil), [])
    }

    func testVisibleDropsOnlyArchivedTasksAndKeepsOrder() {
        let archived = task(id: "t-archived", projectId: "p-archived")
        let live = task(id: "t-live", projectId: "p-live")
        let orphan = task(id: "t-orphan", projectId: "p-never-synced")

        let kept = CalendarTaskVisibility.visible(
            [archived, live, orphan],
            archivedProjectIds: ["p-archived"]
        )

        XCTAssertEqual(kept.map(\.id), ["t-live", "t-orphan"])
    }

    // MARK: - Week canvas + month grid (shared: CalendarViewModel.applyTaskFilters)

    /// `rebuildWeekCache` (week canvas), the per-day cache path, and
    /// `MonthGridCache.loadEvents` (month grid) all funnel through
    /// `applyTaskFilters`. One chokepoint, all three call sites.
    func testCalendarFiltersDropTasksOnArchivedProjects() {
        let viewModel = CalendarViewModel()

        let archived = task(id: "t-archived", projectId: "p-archived")
        let live = task(id: "t-live", projectId: "p-live")

        let filtered = viewModel.applyTaskFilters(
            to: [archived, live],
            archivedProjectIds: ["p-archived"]
        )

        XCTAssertEqual(filtered.map(\.id), ["t-live"])
    }

    /// The archived cut must compose with — not replace — the existing task
    /// type / client / crew filters.
    func testArchivedCutComposesWithTheExistingTaskTypeFilter() {
        let viewModel = CalendarViewModel()
        viewModel.selectedTaskTypeIds = ["install"]

        let archivedInstall = task(id: "t-archived", projectId: "p-archived", taskTypeId: "install")
        let liveInstall = task(id: "t-live-install", projectId: "p-live", taskTypeId: "install")
        let liveTeardown = task(id: "t-live-teardown", projectId: "p-live", taskTypeId: "teardown")

        let filtered = viewModel.applyTaskFilters(
            to: [archivedInstall, liveInstall, liveTeardown],
            archivedProjectIds: ["p-archived"]
        )

        XCTAssertEqual(filtered.map(\.id), ["t-live-install"])
    }

    /// The status filter chip list must not offer a status the calendar can
    /// never show — a filter that always returns nothing is a dead control.
    func testCalendarStatusFilterDoesNotOfferArchived() {
        XCTAssertFalse(
            CalendarTaskVisibility.filterableStatuses.contains(.archived),
            "Archived is not a schedule state; offering it would be a dead filter."
        )
        XCTAssertEqual(
            CalendarTaskVisibility.filterableStatuses,
            [.rfq, .estimated, .accepted, .inProgress, .completed, .closed]
        )
    }

    // MARK: - End-to-end through the real calendar surfaces

    /// The week canvas, driven all the way through `loadProjectsForDate` ->
    /// `rebuildWeekCache` -> `scheduledTasks(for:)` against a real SwiftData
    /// store. Proves the fix at the surface the operator actually looks at,
    /// not just at the predicate.
    func testWeekCanvasDropsTasksOnArchivedProjectsEndToEnd() throws {
        let fixture = try makeCalendarFixture()
        defer { fixture.restorePermissions() }

        fixture.viewModel.loadProjectsForDate(fixture.today)
        let visible = fixture.viewModel.scheduledTasks(for: fixture.today)

        XCTAssertEqual(
            visible.map(\.id).sorted(),
            ["task-live"],
            "The archived job's task must not reach the week canvas."
        )
    }

    /// The month grid, driven through `MonthGridCache.loadEvents` ->
    /// `getAllScheduledTasks` -> `applyTaskFilters` against the same store.
    func testMonthGridDropsTasksOnArchivedProjectsEndToEnd() throws {
        let fixture = try makeCalendarFixture()
        defer { fixture.restorePermissions() }

        let cache = MonthGridCache()
        cache.loadEvents(from: fixture.dataController, viewModel: fixture.viewModel)

        // loadEvents hops to a MainActor Task; wait on the published result
        // rather than a fixed sleep, and fail loudly if it never lands.
        let deadline = Date(timeIntervalSinceNow: 5)
        while cache.isLoading, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertFalse(cache.isLoading, "loadEvents never completed")
        XCTAssertNotNil(
            fixture.dataController.currentUser,
            "Harness check: the operator must survive the async load, or every guarded fetch returns []."
        )

        let eventIds = Set(cache.eventsByDate.values.flatMap { $0 }.map(\.eventId))
        XCTAssertTrue(eventIds.contains("task-live"), "The live job still draws on the month grid.")
        XCTAssertFalse(
            eventIds.contains("task-archived"),
            "The archived job's task must not hold a month-grid row."
        )
    }

    /// Archiving a project must repaint the calendars rather than leaving the
    /// job on screen until the next sync. `updateProjectStatus` publishes
    /// `scheduledTasksDidChange`, which every calendar surface observes, and
    /// the reload clears `cachedWeekStart` so the week actually re-fetches.
    func testArchivingRepaintsTheWeekCanvas() throws {
        let fixture = try makeCalendarFixture()
        defer { fixture.restorePermissions() }

        fixture.viewModel.loadProjectsForDate(fixture.today)
        XCTAssertEqual(fixture.viewModel.scheduledTasks(for: fixture.today).map(\.id), ["task-live"])

        fixture.liveProject.status = .archived
        try fixture.context.save()

        // What ScheduleView does on the scheduledTasksDidChange signal.
        fixture.viewModel.reloadCalendarData()

        XCTAssertTrue(
            fixture.viewModel.scheduledTasks(for: fixture.today).isEmpty,
            "Archiving must clear the cached week, not leave the job drawn."
        )
    }

    // MARK: - Scheduler sheet (conflict math)

    /// The day inspector counted archived jobs as clashes, so picking a day
    /// that only ever collided with a filed-away job read as "conflict" and the
    /// operator was steered off a day that was in fact free.
    func testArchivedJobDoesNotManufactureAConflictInTheSchedulerSheet() {
        let crew: Set<String> = ["crew-1"]

        let archivedTask = task(id: "t-archived", projectId: "p-archived")
        archivedTask.startDate = day(2026, 8, 10)
        archivedTask.endDate = day(2026, 8, 10)
        archivedTask.teamMemberIdsString = "crew-1"

        let visible = CalendarTaskVisibility.visible(
            [archivedTask],
            archivedProjectIds: ["p-archived"]
        )

        let context = SchedulerDayContext(
            item: SchedulerDayContext.Item(
                selfTaskId: "t-new",
                projectId: "p-new",
                crewIds: crew,
                dependencies: [],
                isScheduled: false
            ),
            events: visible.map { task in
                SchedulerDayContext.Event(
                    id: task.id,
                    kind: .job,
                    title: "Archived job",
                    projectId: task.projectId,
                    start: task.startDate!,
                    end: task.endDate!,
                    crewIds: Set(task.getTeamMemberIds()),
                    crewFirstNames: [:]
                )
            },
            prerequisites: [],
            skipsWeekends: false,
            calendar: calendar
        )

        XCTAssertTrue(context.events.isEmpty, "An archived job is not a commitment.")
        XCTAssertTrue(
            context.signals(for: day(2026, 8, 10)).isEmpty,
            "A day whose only collision is an archived job is a free day."
        )
    }

    /// Guard the other direction — the engine still flags a real clash, so the
    /// test above is proving the archived cut and not a broken conflict engine.
    func testLiveJobStillProducesAConflictInTheSchedulerSheet() {
        let crew: Set<String> = ["crew-1"]

        let liveTask = task(id: "t-live", projectId: "p-live")
        liveTask.startDate = day(2026, 8, 10)
        liveTask.endDate = day(2026, 8, 10)
        liveTask.teamMemberIdsString = "crew-1"

        let visible = CalendarTaskVisibility.visible(
            [liveTask],
            archivedProjectIds: ["p-archived"]
        )

        let context = SchedulerDayContext(
            item: SchedulerDayContext.Item(
                selfTaskId: "t-new",
                projectId: "p-new",
                crewIds: crew,
                dependencies: [],
                isScheduled: false
            ),
            events: visible.map { task in
                SchedulerDayContext.Event(
                    id: task.id,
                    kind: .job,
                    title: "Live job",
                    projectId: task.projectId,
                    start: task.startDate!,
                    end: task.endDate!,
                    crewIds: Set(task.getTeamMemberIds()),
                    crewFirstNames: [:]
                )
            },
            prerequisites: [],
            skipsWeekends: false,
            calendar: calendar
        )

        XCTAssertEqual(context.events.count, 1)
        XCTAssertTrue(
            context.signals(for: day(2026, 8, 10)).crewBusy,
            "The same crew on the same day is a real clash — the engine still says so."
        )
    }

    // MARK: - Fixtures

    private func task(id: String, projectId: String, taskTypeId: String = "tt") -> ProjectTask {
        ProjectTask(id: id, projectId: projectId, taskTypeId: taskTypeId, companyId: "co")
    }

    /// A real store with one live job and one archived job, each carrying a
    /// task scheduled for today, plus a DataController and CalendarViewModel
    /// wired the way the app wires them.
    private struct CalendarFixture {
        let context: ModelContext
        let dataController: DataController
        let viewModel: CalendarViewModel
        let liveProject: Project
        let today: Date
        let restorePermissions: () -> Void
    }

    private func makeCalendarFixture() throws -> CalendarFixture {
        let container = try makeInMemoryContainer()
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

        let today = Calendar.current.startOfDay(for: Date())

        let liveProject = Project(id: "p-live", title: "South deck rebuild", status: .inProgress)
        liveProject.companyId = "co"
        let archivedProject = Project(id: "p-archived", title: "Filed away", status: .archived)
        archivedProject.companyId = "co"
        context.insert(liveProject)
        context.insert(archivedProject)

        for (id, project) in [("task-live", liveProject), ("task-archived", archivedProject)] {
            let scheduled = task(id: id, projectId: project.id)
            scheduled.startDate = today
            scheduled.endDate = today
            scheduled.teamMemberIdsString = "user-1"
            scheduled.project = project
            context.insert(scheduled)
        }
        try context.save()

        let viewModel = CalendarViewModel()
        viewModel.dataController = dataController
        viewModel.selectedDate = today

        return CalendarFixture(
            context: context,
            dataController: dataController,
            viewModel: viewModel,
            liveProject: liveProject,
            today: today,
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
            CalendarUserEvent.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
