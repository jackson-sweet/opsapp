//
//  TaskReviewQueryParityTests.swift
//  OPSTests
//
//  The FAB badge derived five cached counts from four review entry points, and
//  every one of those entry points re-fetched the whole task or project table on
//  the main thread — on each sync completion and each schedule mutation, from
//  whichever tab the operator happened to be on. The counts now come from ONE
//  `getAllTasks()` and ONE `getProjects()`, handed to `tasks:` / `projects:`
//  overloads of the same queries.
//
//  Two different guarantees live here, and they are not interchangeable.
//
//  The shape-vs-shape assertions — original entry point against `tasks:` /
//  `projects:` overload, same rows in the same ORDER, under every permission
//  shape the scoping branches on — prove the DELEGATE WIRING: that the two
//  entry points cannot drift apart from here on. They say nothing about the
//  pre-refactor code, since both shapes now run the same body.
//
//  What guards against behavior having changed underneath the refactor is the
//  absolute row assertions: each permission configuration names the exact rows
//  it is required to produce, derived from the queue rules rather than from
//  either implementation. Those are the oracle. They also keep the parity
//  assertions from passing over two empty arrays.
//
//  `getAllTasks()` moved from an in-memory `deletedAt == nil` filter to a
//  `#Predicate` on the fetch — a real change of mechanism, so it is pinned
//  against the old filter run verbatim over the same store, plus a case proving
//  a tombstoned row that would otherwise qualify never reaches a badge count.
//
//  `PermissionStore.shared` is a process-wide singleton the queries read
//  directly, so each test saves and restores it — the test host carries whatever
//  a previous suite left behind.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class TaskReviewQueryParityTests: XCTestCase {

    // MARK: - Permission configurations

    /// Owner/admin: full scope on every gate the review queues read.
    private let fullAccess = [
        "tasks.view": "all",
        "tasks.edit": "all",
        "tasks.assign": "all",
        "tasks.change_status": "all",
        "calendar.edit": "all",
        "projects.edit": "all",
    ]

    /// Crew: no `tasks.view`, so `scopedTasks` falls to the assignment filter,
    /// and every mutation gate is scope-limited to rows the operator is on.
    private let assignedScope = [
        "tasks.edit": "assigned",
        "tasks.change_status": "assigned",
        "calendar.edit": "assigned",
        "projects.edit": "assigned",
    ]

    /// A view-only grant: sees the whole company, may mutate nothing.
    private let viewOnly = [
        "tasks.view": "all",
    ]

    private var savedPermissions: [String: String] = [:]
    private var savedBlockedByFlags: Set<String> = []
    private var savedDisabledFlags: Set<String> = []

    override func setUp() {
        super.setUp()
        savedPermissions = PermissionStore.shared.permissions
        savedBlockedByFlags = PermissionStore.shared.blockedByFlags
        savedDisabledFlags = PermissionStore.shared.disabledFlags
        PermissionStore.shared.blockedByFlags = []
        PermissionStore.shared.disabledFlags = []
    }

    override func tearDown() {
        PermissionStore.shared.permissions = savedPermissions
        PermissionStore.shared.blockedByFlags = savedBlockedByFlags
        PermissionStore.shared.disabledFlags = savedDisabledFlags
        super.tearDown()
    }

    // MARK: - Task queue parity

    func test_taskQueueOverloadsMatchTheirEntryPointsUnderFullAccess() throws {
        let fixture = try makeFixture()
        PermissionStore.shared.permissions = fullAccess

        assertTaskQueueParity(fixture)

        // What full access is required to produce — so the parity above can
        // never pass on four empty arrays.
        let tasks = fixture.dataController.getAllTasks()
        XCTAssertEqual(
            Set(TaskReviewQuery.scopedTasks(tasks: tasks, dataController: fixture.dataController).map(\.id)),
            Set(fixture.liveTaskIDs),
            "tasks.view=all sees every non-deleted task in the store, both companies"
        )
        XCTAssertEqual(
            Set(TaskReviewQuery.overdueReviewTasks(tasks: tasks, dataController: fixture.dataController).map(\.id)),
            [
                "t-overdue-3d",
                "t-overdue-5d",
                "t-overdue-tie-a",
                "t-overdue-tie-b",
                "t-on-completed-project",
                "t-beta-overdue",
            ],
            "Every active, dated task whose scheduled completion is before end of today"
        )
        XCTAssertEqual(
            Set(TaskReviewQuery.unscheduledReviewTasks(tasks: tasks, dataController: fixture.dataController).map(\.id)),
            [
                "t-overdue-5d",           // dated, but no crew
                "t-unscheduled-assigned", // crewed, but no date
                "t-unscheduled-nocrew",
                "t-beta-unscheduled",
            ],
            "Active tasks on an ACTIVE project missing a date or a crew"
        )
    }

    func test_taskQueueOverloadsMatchTheirEntryPointsUnderAssignedScope() throws {
        let fixture = try makeFixture()
        PermissionStore.shared.permissions = assignedScope

        assertTaskQueueParity(fixture)

        let tasks = fixture.dataController.getAllTasks()
        let scoped = TaskReviewQuery.scopedTasks(tasks: tasks, dataController: fixture.dataController)
        XCTAssertFalse(scoped.isEmpty, "The operator is on tasks; the assigned branch must return them")
        XCTAssertTrue(
            scoped.allSatisfy { $0.getTeamMemberIds().contains(fixture.operatorID) },
            "Without tasks.view=all the scope is exactly the operator's own assignments"
        )

        let unscheduled = TaskReviewQuery.unscheduledReviewTasks(tasks: tasks, dataController: fixture.dataController)
        XCTAssertEqual(
            Set(unscheduled.map(\.id)),
            ["t-unscheduled-assigned"],
            """
            tasks.edit=assigned reaches only rows the operator is on, and without \
            tasks.assign the crewless rows carry no available mutation.
            """
        )
    }

    func test_taskQueueOverloadsMatchTheirEntryPointsUnderAViewOnlyGrant() throws {
        let fixture = try makeFixture()
        PermissionStore.shared.permissions = viewOnly

        assertTaskQueueParity(fixture)

        let tasks = fixture.dataController.getAllTasks()
        XCTAssertFalse(
            TaskReviewQuery.overdueReviewTasks(tasks: tasks, dataController: fixture.dataController).isEmpty,
            "A view-only grant still sees the overdue queue"
        )
        XCTAssertTrue(
            TaskReviewQuery.editableTasks(tasks: tasks, dataController: fixture.dataController).isEmpty,
            "No tasks.edit grant means no mutation-scoped rows"
        )
        XCTAssertTrue(
            TaskReviewQuery.unscheduledReviewTasks(tasks: tasks, dataController: fixture.dataController).isEmpty,
            "A view-only grant must never produce an actionable review card"
        )
    }

    // MARK: - Project snapshot parity

    func test_projectSnapshotOverloadMatchesItsEntryPointUnderFullAccess() throws {
        let fixture = try makeFixture()
        PermissionStore.shared.permissions = fullAccess

        assertProjectSnapshotParity(fixture)

        let snapshot = ProjectReviewQuery.snapshot(
            projects: fixture.dataController.getProjects(),
            dataController: fixture.dataController
        )
        // Membership, not order: an unsorted fetch has no defined row order, and
        // the completed list carries the fetch's. Order is asserted where it is
        // actually promised — between the two entry points, above, and in the
        // overdue list, which sorts.
        XCTAssertEqual(
            Set(snapshot.completedProjects.map(\.id)),
            ["p-completed-old", "p-completed-recent"],
            "Completed, non-deleted, closable — and only the operator's own company"
        )
        XCTAssertEqual(
            snapshot.overdueProjects.map(\.id),
            ["p-completed-old"],
            "Completed longer ago than the 14-day threshold"
        )
        XCTAssertEqual(snapshot.count, 2, "Overdue first, then the remaining completed, deduped")
    }

    func test_projectSnapshotOverloadMatchesItsEntryPointUnderAssignedScope() throws {
        let fixture = try makeFixture()
        PermissionStore.shared.permissions = assignedScope

        assertProjectSnapshotParity(fixture)

        let snapshot = ProjectReviewQuery.snapshot(
            projects: fixture.dataController.getProjects(),
            dataController: fixture.dataController
        )
        XCTAssertEqual(
            snapshot.completedProjects.map(\.id),
            ["p-completed-old"],
            """
            projects.edit=assigned reaches a project the operator is on through \
            its own crew or a task's — p-completed-recent has neither.
            """
        )
        XCTAssertEqual(snapshot.count, 1)
    }

    func test_projectSnapshotOverloadMatchesItsEntryPointWithNoEditGrant() throws {
        let fixture = try makeFixture()
        PermissionStore.shared.permissions = viewOnly

        assertProjectSnapshotParity(fixture)

        let snapshot = ProjectReviewQuery.snapshot(
            projects: fixture.dataController.getProjects(),
            dataController: fixture.dataController
        )
        XCTAssertTrue(
            snapshot.projects.isEmpty,
            "Nothing is closable without projects.edit, so the badge shows nothing"
        )
    }

    // MARK: - The soft-delete predicate

    func test_getAllTasksDropsExactlyTheRowsTheInMemoryFilterDropped() throws {
        let fixture = try makeFixture()

        let everyRow = try fixture.context.fetch(FetchDescriptor<ProjectTask>())
        // The pre-predicate implementation, verbatim.
        let filteredInMemory = everyRow.filter { $0.deletedAt == nil }

        XCTAssertTrue(
            everyRow.contains { $0.deletedAt != nil },
            "Precondition: the store has to hold tombstones for this to mean anything"
        )
        XCTAssertEqual(
            fixture.dataController.getAllTasks().map(\.id),
            filteredInMemory.map(\.id),
            "The fetch predicate must return the same rows in the same order as the filter it replaced"
        )
        XCTAssertEqual(
            Set(everyRow.map(\.id)).subtracting(filteredInMemory.map(\.id)),
            Set(fixture.softDeletedTaskIDs)
        )
    }

    func test_aTombstonedTaskThatWouldOtherwiseBeOverdueNeverReachesACount() throws {
        let fixture = try makeFixture()
        PermissionStore.shared.permissions = fullAccess

        let tombstoned = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<ProjectTask>())
                .first { $0.id == "t-deleted" }
        )
        let scheduledCompletion = try XCTUnwrap(tombstoned.endDate)
        XCTAssertEqual(tombstoned.status, .active)
        XCTAssertLessThan(
            scheduledCompletion,
            Date(),
            "Precondition: only its tombstone keeps this row out of the overdue queue"
        )

        let overdue = TaskReviewQuery.overdueReviewTasks(dataController: fixture.dataController)
        XCTAssertFalse(overdue.contains { $0.id == "t-deleted" })
    }

    // MARK: - Parity assertions

    /// Every task queue, both shapes, same rows and same order. The `tasks:`
    /// shape is fed the single fetch the FAB now performs; the original shape
    /// fetches for itself, exactly as it did before the split.
    private func assertTaskQueueParity(
        _ fixture: Fixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let dataController = fixture.dataController
        let tasks = dataController.getAllTasks()

        assertSameRows(
            TaskReviewQuery.scopedTasks(dataController: dataController),
            TaskReviewQuery.scopedTasks(tasks: tasks, dataController: dataController),
            "scopedTasks",
            file: file,
            line: line
        )
        assertSameRows(
            TaskReviewQuery.editableTasks(dataController: dataController),
            TaskReviewQuery.editableTasks(tasks: tasks, dataController: dataController),
            "editableTasks",
            file: file,
            line: line
        )
        assertSameRows(
            TaskReviewQuery.overdueReviewTasks(dataController: dataController),
            TaskReviewQuery.overdueReviewTasks(tasks: tasks, dataController: dataController),
            "overdueReviewTasks",
            file: file,
            line: line
        )
        assertSameRows(
            TaskReviewQuery.unscheduledReviewTasks(dataController: dataController),
            TaskReviewQuery.unscheduledReviewTasks(tasks: tasks, dataController: dataController),
            "unscheduledReviewTasks",
            file: file,
            line: line
        )
    }

    private func assertProjectSnapshotParity(
        _ fixture: Fixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let dataController = fixture.dataController
        let fetched = ProjectReviewQuery.snapshot(dataController: dataController)
        let passedThrough = ProjectReviewQuery.snapshot(
            projects: dataController.getProjects(),
            dataController: dataController
        )

        XCTAssertEqual(
            fetched.projects.map(\.id),
            passedThrough.projects.map(\.id),
            "snapshot.projects diverged",
            file: file,
            line: line
        )
        XCTAssertEqual(
            fetched.overdueProjects.map(\.id),
            passedThrough.overdueProjects.map(\.id),
            "snapshot.overdueProjects diverged",
            file: file,
            line: line
        )
        XCTAssertEqual(
            fetched.completedProjects.map(\.id),
            passedThrough.completedProjects.map(\.id),
            "snapshot.completedProjects diverged",
            file: file,
            line: line
        )
        XCTAssertEqual(
            fetched.count,
            passedThrough.count,
            "snapshot.count is what the badge renders",
            file: file,
            line: line
        )
    }

    private func assertSameRows(
        _ fetched: [ProjectTask],
        _ passedThrough: [ProjectTask],
        _ queue: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            fetched.map(\.id),
            passedThrough.map(\.id),
            "\(queue): the tasks: overload must return the same rows in the same order",
            file: file,
            line: line
        )
    }

    // MARK: - Fixture

    private struct Fixture {
        let context: ModelContext
        let dataController: DataController
        let operatorID: String
        /// Every task id in the store that carries no tombstone.
        let liveTaskIDs: [String]
        let softDeletedTaskIDs: [String]
    }

    /// Two companies, seven projects across the status range, and thirteen tasks
    /// covering every branch the queues read: deleted, completed, active, dated,
    /// undated, crewed, crewless, on an active project and on an inactive one —
    /// plus a pair sharing an endDate, so a tie in the overdue sort is exercised
    /// rather than assumed away.
    private func makeFixture() throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let operatorID = "user-1"
        let alpha = "co-alpha"
        let beta = "co-beta"

        let company = Company(id: alpha, name: "Norcut")
        context.insert(company)

        let user = User(
            id: operatorID,
            firstName: "Marcus",
            lastName: "Hale",
            role: .crew,
            companyId: alpha
        )
        context.insert(user)

        let projects: [(String, String, Status, String)] = [
            ("p-active-inprogress", "South deck rebuild", .inProgress, alpha),
            ("p-active-accepted", "Cedar rail swap", .accepted, alpha),
            ("p-rfq", "Quote pending", .rfq, alpha),
            ("p-completed-old", "Fence line", .completed, alpha),
            ("p-completed-recent", "Gate repair", .completed, alpha),
            ("p-completed-deleted", "Cancelled patio", .completed, alpha),
            ("p-closed", "Paid and filed", .closed, alpha),
            ("p-beta-active", "Other company's job", .inProgress, beta),
        ]
        var projectsByID: [String: Project] = [:]
        for (id, title, status, companyID) in projects {
            let project = Project(id: id, title: title, status: status)
            project.companyId = companyID
            context.insert(project)
            projectsByID[id] = project
        }

        let day: TimeInterval = 86_400
        // Comfortably past the 14-day company threshold.
        projectsByID["p-completed-old"]?.completedAt = Date(timeIntervalSinceNow: -40 * day)
        projectsByID["p-completed-recent"]?.completedAt = Date()
        projectsByID["p-completed-deleted"]?.completedAt = Date(timeIntervalSinceNow: -40 * day)
        projectsByID["p-completed-deleted"]?.deletedAt = Date(timeIntervalSinceNow: -day)

        /// id, project, status, days-before-now the task is scheduled (nil =
        /// unscheduled), crew, tombstoned.
        let tasks: [(String, String, TaskStatus, Double?, [String], Bool)] = [
            ("t-overdue-3d", "p-active-inprogress", .active, 3, [operatorID], false),
            ("t-overdue-5d", "p-active-inprogress", .active, 5, [], false),
            ("t-overdue-tie-a", "p-active-accepted", .active, 7, [operatorID], false),
            ("t-overdue-tie-b", "p-active-accepted", .active, 7, [operatorID], false),
            ("t-future", "p-active-inprogress", .active, -5, [operatorID], false),
            ("t-unscheduled-assigned", "p-active-inprogress", .active, nil, [operatorID], false),
            ("t-unscheduled-nocrew", "p-active-accepted", .active, nil, [], false),
            ("t-completed", "p-active-inprogress", .completed, 2, [operatorID], false),
            ("t-deleted", "p-active-inprogress", .active, 10, [operatorID], true),
            ("t-rfq-unscheduled", "p-rfq", .active, nil, [operatorID], false),
            ("t-on-completed-project", "p-completed-old", .active, 20, [operatorID], false),
            ("t-beta-overdue", "p-beta-active", .active, 4, ["user-2"], false),
            ("t-beta-unscheduled", "p-beta-active", .active, nil, ["user-2"], false),
        ]
        for (id, projectID, status, daysAgo, crew, isDeleted) in tasks {
            let project = projectsByID[projectID]
            let task = ProjectTask(
                id: id,
                projectId: projectID,
                taskTypeId: "task-type-1",
                companyId: project?.companyId ?? alpha,
                status: status
            )
            if let daysAgo {
                // Both ends set: a dated task must not fall into the unscheduled
                // queue through a nil startDate.
                let scheduled = Date(timeIntervalSinceNow: -daysAgo * day)
                task.startDate = scheduled
                task.endDate = scheduled
            }
            task.setTeamMemberIds(crew)
            if isDeleted {
                task.deletedAt = Date(timeIntervalSinceNow: -day)
            }
            task.project = project
            context.insert(task)
        }
        try context.save()

        let dataController = DataController()
        dataController.setModelContext(context)

        // `DataController.init` fires a one-shot `checkExistingAuth()`; with no
        // stored credentials it calls `clearAuthentication()`, which nils
        // `currentUser`. Seed the operator, wait for that clear to land, then
        // seed again — otherwise it arrives mid-test and every query guarded on
        // `currentUser` silently returns []. Waiting on the observed event, not
        // a fixed sleep; the bound only guards an environment that never clears.
        dataController.currentUser = user
        let authSettled = Date(timeIntervalSinceNow: 5)
        while dataController.currentUser != nil, Date() < authSettled {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        dataController.currentUser = user

        return Fixture(
            context: context,
            dataController: dataController,
            operatorID: operatorID,
            liveTaskIDs: tasks.filter { !$0.5 }.map(\.0),
            softDeletedTaskIDs: tasks.filter { $0.5 }.map(\.0)
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
            ProjectPhoto.self,
            SyncOperation.self,
            // ProjectReviewQuery reads the company's review threshold, so the
            // entity has to exist in the store the controller fetches from.
            Company.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
