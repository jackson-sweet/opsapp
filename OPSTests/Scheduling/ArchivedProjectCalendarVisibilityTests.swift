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
