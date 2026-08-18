//
//  CalendarGridDataActorTests.swift
//  OPSTests
//
//  Locks the Schedule's two rebuild passes — the week canvas's per-day cache and
//  the month grid's badge cache — to what they produced when they ran inline on the
//  main thread (bug 1bade6dd). The DataActor may move the walk off the render
//  thread; it may not change a single row the calendar shows.
//
//  Content is asserted concretely before parity is asserted: a parity check alone
//  would pass if both paths were identically wrong.
//

import XCTest
import SwiftData
@testable import OPS

final class CalendarGridDataActorTests: XCTestCase {

    /// Containers outlive the contexts they vend. A `ModelContext` does not keep its
    /// container alive, and inserting into a context whose container has been
    /// released traps inside SwiftData before the first assertion runs.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - Week canvas

    /// Monday 2026-06-22. Everything below is expressed as an offset from it.
    private var monday: Date { Calendar.current.startOfDay(for: date(2026, 6, 22)) }

    func testWeekCacheScopesFiltersAndBucketsByOverlap() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let live = makeProject(id: "live", title: "Smith deck", status: .inProgress, in: context)
        makeTask(id: "t-mon", project: live, start: day(monday, 0), end: day(monday, 0), in: context)
        // Tue → Thu. Overlap admission means it must land on all three days.
        makeTask(id: "t-span", project: live, start: day(monday, 1), end: day(monday, 3), in: context)
        // Outside the 21-day window (which runs monday-7 … monday+13).
        makeTask(id: "t-far-past", project: live, start: day(monday, -30), end: day(monday, -30), in: context)

        // Filed away and not-yet-won work is not a commitment — never on the canvas.
        let archived = makeProject(id: "archived", title: "Filed away", status: .archived, in: context)
        makeTask(id: "t-archived", project: archived, start: day(monday, 0), end: day(monday, 0), in: context)
        let quoted = makeProject(id: "quoted", title: "Not won yet", status: .estimated, in: context)
        makeTask(id: "t-quoted", project: quoted, start: day(monday, 0), end: day(monday, 0), in: context)

        // Another company's job. The scope gate is the only thing keeping it out.
        let foreign = makeProject(id: "foreign", title: "Someone else", status: .inProgress, in: context)
        foreign.companyId = "company-2"
        let foreignTask = makeTask(id: "t-foreign", project: foreign, start: day(monday, 0), end: day(monday, 0), in: context)
        foreignTask.companyId = "company-2"

        try context.save()

        let scope = makeScope(mode: .all, canViewAllCalendar: true, hasFullTaskAccess: true)
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let snapshot = await actor.calendarWeekCache(scope: scope, weekStart: monday)

        XCTAssertEqual(snapshot.weekStart, monday)
        XCTAssertEqual(snapshot.taskIdsByDay[key(day(monday, 0))], ["t-mon"])
        XCTAssertEqual(snapshot.taskIdsByDay[key(day(monday, 1))], ["t-span"])
        XCTAssertEqual(snapshot.taskIdsByDay[key(day(monday, 2))], ["t-span"])
        XCTAssertEqual(snapshot.taskIdsByDay[key(day(monday, 3))], ["t-span"])
        XCTAssertEqual(snapshot.countsByDay[key(day(monday, 0))], 1)
        XCTAssertEqual(snapshot.countsByDay[key(day(monday, 4))], 0)

        let everyId = Set(snapshot.taskIdsByDay.values.flatMap { $0 })
        XCTAssertEqual(everyId, ["t-mon", "t-span"])
        XCTAssertFalse(everyId.contains("t-archived"))
        XCTAssertFalse(everyId.contains("t-quoted"))
        XCTAssertFalse(everyId.contains("t-foreign"))
        XCTAssertFalse(everyId.contains("t-far-past"))
        // The window itself: one week either side of the anchor, and nothing more.
        XCTAssertNil(snapshot.taskIdsByDay[key(day(monday, -8))])
        XCTAssertNotNil(snapshot.taskIdsByDay[key(day(monday, -7))])
        XCTAssertNotNil(snapshot.taskIdsByDay[key(day(monday, 13))])
        XCTAssertNil(snapshot.taskIdsByDay[key(day(monday, 14))])

        // Parity with the retired inline build, over the same store.
        let expected = mainThreadWeekCache(scope: scope, weekStart: monday, container: container)
        XCTAssertEqual(snapshot.taskIdsByDay, expected.taskIdsByDay)
        XCTAssertEqual(snapshot.countsByDay, expected.countsByDay)
    }

    /// A crew member without `tasks.view(all)` sees only their own work — assignment
    /// counts from the task's crew OR the project's, exactly as it did inline.
    func testWeekCacheMineScopeAdmitsOnlyAssignedWork() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let live = makeProject(id: "live", title: "Smith deck", status: .inProgress, in: context)
        let assigned = makeTask(id: "t-assigned", project: live, start: day(monday, 0), end: day(monday, 0), in: context)
        assigned.setTeamMemberIds(["user-1"])
        makeTask(id: "t-someone-else", project: live, start: day(monday, 0), end: day(monday, 0), in: context)

        let crewed = makeProject(id: "crewed", title: "Jones rail", status: .accepted, in: context)
        crewed.setTeamMemberIds(["user-1"])
        makeTask(id: "t-project-crew", project: crewed, start: day(monday, 0), end: day(monday, 0), in: context)

        try context.save()

        let scope = makeScope(mode: .mine, canViewAllCalendar: false, hasFullTaskAccess: false)
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let snapshot = await actor.calendarWeekCache(scope: scope, weekStart: monday)

        XCTAssertEqual(
            Set(snapshot.taskIdsByDay[key(day(monday, 0))] ?? []),
            ["t-assigned", "t-project-crew"]
        )

        let expected = mainThreadWeekCache(scope: scope, weekStart: monday, container: container)
        XCTAssertEqual(snapshot.taskIdsByDay, expected.taskIdsByDay)
    }

    /// A crew filter narrows further, and still cannot resurrect hidden work.
    func testWeekCacheHonorsTheCrewFilter() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let live = makeProject(id: "live", title: "Smith deck", status: .inProgress, in: context)
        let mine = makeTask(id: "t-mine", project: live, start: day(monday, 0), end: day(monday, 0), in: context)
        mine.setTeamMemberIds(["user-1"])
        let theirs = makeTask(id: "t-theirs", project: live, start: day(monday, 0), end: day(monday, 0), in: context)
        theirs.setTeamMemberIds(["user-2"])

        try context.save()

        var scope = makeScope(mode: .all, canViewAllCalendar: true, hasFullTaskAccess: true)
        scope = CalendarTaskScope(
            mode: scope.mode,
            userId: scope.userId,
            companyId: scope.companyId,
            canViewAllCalendar: scope.canViewAllCalendar,
            hasFullTaskAccess: scope.hasFullTaskAccess,
            selectedTeamMemberIds: ["user-2"],
            selectedTaskTypeIds: [],
            selectedClientIds: [],
            selectedStatuses: []
        )

        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let snapshot = await actor.calendarWeekCache(scope: scope, weekStart: monday)

        XCTAssertEqual(snapshot.taskIdsByDay[key(day(monday, 0))], ["t-theirs"])
    }

    // MARK: - Month grid

    func testMonthPreviewsExpandEveryCoveredDay() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let live = makeProject(id: "live", title: "Smith deck", status: .inProgress, in: context)
        makeTask(id: "t-span", project: live, start: day(monday, 0), end: day(monday, 2), in: context)

        let archived = makeProject(id: "archived", title: "Filed away", status: .archived, in: context)
        makeTask(id: "t-archived", project: archived, start: day(monday, 0), end: day(monday, 0), in: context)

        try context.save()

        let scope = makeScope(mode: .all, canViewAllCalendar: true, hasFullTaskAccess: true)
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let previews = await actor.calendarMonthPreviews(
            scope: scope,
            since: day(monday, -365),
            tutorialOnly: false
        )

        let first = previews[key(day(monday, 0))] ?? []
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.eventId, "t-span")
        // Bug 087bfaf8 — the project title is the badge's primary label.
        XCTAssertEqual(first.first?.title, "Smith deck")
        XCTAssertEqual(first.first?.totalDays, 3)
        XCTAssertEqual(first.first?.dayOffset, 0)
        XCTAssertTrue(first.first?.isFirst == true)
        XCTAssertFalse(first.first?.isLast == true)
        XCTAssertTrue(first.first?.isMultiDay == true)

        XCTAssertEqual(previews[key(day(monday, 1))]?.first?.dayOffset, 1)
        XCTAssertTrue(previews[key(day(monday, 2))]?.first?.isLast == true)
        XCTAssertNil(previews[key(day(monday, 3))])

        // Filed-away work never gets a badge.
        let everyEventId = Set(previews.values.flatMap { $0 }.map(\.eventId))
        XCTAssertEqual(everyEventId, ["t-span"])
    }

    /// Tutorial mode shows demo rows only — the cut has to survive the move off-main.
    func testMonthPreviewsHonorTutorialMode() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let live = makeProject(id: "live", title: "Smith deck", status: .inProgress, in: context)
        makeTask(id: "DEMO_task", project: live, start: day(monday, 0), end: day(monday, 0), in: context)
        makeTask(id: "real-task", project: live, start: day(monday, 0), end: day(monday, 0), in: context)

        try context.save()

        let scope = makeScope(mode: .all, canViewAllCalendar: true, hasFullTaskAccess: true)
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let previews = await actor.calendarMonthPreviews(
            scope: scope,
            since: day(monday, -365),
            tutorialOnly: true
        )

        XCTAssertEqual(Set(previews.values.flatMap { $0 }.map(\.eventId)), ["DEMO_task"])
    }

    // MARK: - Retired main-thread build (parity reference)

    /// What `CalendarViewModel.rebuildWeekCache` did inline, on a main-style context.
    private func mainThreadWeekCache(
        scope: CalendarTaskScope,
        weekStart: Date,
        container: ModelContainer
    ) -> CalendarWeekCacheSnapshot {
        let context = ModelContext(container)
        let allTasks = (try? context.fetch(
            FetchDescriptor<ProjectTask>(
                predicate: #Predicate<ProjectTask> { $0.deletedAt == nil && $0.startDate != nil }
            )
        )) ?? []
        let hiddenProjectIds = CalendarTaskVisibility.hiddenProjectIds(in: context)
        let visible = allTasks.filter {
            CalendarTaskScoping.admitsForWeekCanvas($0, scope: scope)
                && CalendarTaskScoping.passesFilters($0, scope: scope, hiddenProjectIds: hiddenProjectIds)
        }
        return CalendarWeekCacheBuilder.snapshot(tasks: visible, weekStart: weekStart)
    }

    // MARK: - Fixtures

    private func makeScope(
        mode: CalendarTaskScope.Mode,
        canViewAllCalendar: Bool,
        hasFullTaskAccess: Bool
    ) -> CalendarTaskScope {
        CalendarTaskScope(
            mode: mode,
            userId: "user-1",
            companyId: "company-1",
            canViewAllCalendar: canViewAllCalendar,
            hasFullTaskAccess: hasFullTaskAccess,
            selectedTeamMemberIds: [],
            selectedTaskTypeIds: [],
            selectedClientIds: [],
            selectedStatuses: []
        )
    }

    private func key(_ date: Date) -> String { CalendarDayKey.key(for: date) }

    private func day(_ from: Date, _ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: from) ?? from
    }

    private func date(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = 9
        return Calendar.current.date(from: components) ?? Date()
    }

    @discardableResult
    private func makeProject(
        id: String,
        title: String,
        status: Status,
        in context: ModelContext
    ) -> Project {
        let project = Project(id: id, title: title, status: status)
        project.companyId = "company-1"
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeTask(
        id: String,
        project: Project,
        start: Date,
        end: Date,
        in context: ModelContext
    ) -> ProjectTask {
        let task = ProjectTask(
            id: id,
            projectId: project.id,
            taskTypeId: "task-type",
            companyId: project.companyId
        )
        task.startDate = start
        task.endDate = end
        task.project = project
        context.insert(task)
        return task
    }

    private func makeContainer() throws -> ModelContainer {
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
            Company.self,
            Invoice.self,
            Estimate.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return container
    }
}
