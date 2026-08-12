//
//  JobBoardCardModelTests.swift
//  OPSTests
//
//  The job-board card used to re-derive itself from whole-table fetches on
//  every render: `getAllProjects().first { $0.id == task.projectId }` twice per
//  task card, `getAllTaskTypes(for:).first { $0.id == task.taskTypeId }` three
//  times, plus three or four separate walks of `project.tasks` per project card.
//  `JobBoardCardModels` replaces all of it with SwiftData relationship reads and
//  single passes.
//
//  Each assertion below runs the ORIGINAL derivation as an oracle over the same
//  store and requires the new one to agree — including the awkward cases the
//  fetch answered by accident: a tombstoned parent project (the fetch was
//  predicated `deletedAt == nil`, so it resolved to nil, and the relationship
//  read must too), and a task whose type row is missing.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class JobBoardCardModelTests: XCTestCase {

    private let companyID = "co-alpha"
    private let operatorID = "user-1"

    // MARK: - Oracles (the pre-refactor derivations, verbatim)

    /// `UniversalJobBoardCard.subtitle`, task branch, before the change.
    private func oracleSubtitle(task: ProjectTask, allProjects: [Project]) -> String {
        if let project = allProjects.first(where: { $0.id == task.projectId }) {
            let clientName = project.effectiveClientName
            return "\(project.title) - \(clientName)"
        }
        return "No project"
    }

    /// `UniversalJobBoardCard.title`, task branch, before the change.
    private func oracleTitle(task: ProjectTask, allTaskTypes: [TaskType]) -> String {
        if let taskType = allTaskTypes.first(where: { $0.id == task.taskTypeId }) {
            return taskType.display.uppercased()
        }
        return "TASK"
    }

    /// `UniversalJobBoardCard.taskProgressBars`, before the change: four passes.
    private func oracleProgress(project: Project) -> [JobBoardTaskProgressState] {
        let tasks = project.tasks.filter { $0.deletedAt == nil }
        let completed = tasks.filter { $0.status == .completed }
        let cancelled = tasks.filter { $0.status == .cancelled }
        let active = tasks.filter { $0.status != .completed && $0.status != .cancelled }
        return (completed + active + cancelled).map { task in
            switch task.status {
            case .completed: return .completed
            case .cancelled: return .cancelled
            case .active:    return .active
            }
        }
    }

    /// `UniversalJobBoardCard.shouldShowUnscheduledBadge(for:)`, before: three passes.
    private func oracleShowsUnscheduled(project: Project) -> Bool {
        if project.tasks.isEmpty { return true }
        let relevant = project.tasks.filter { $0.status != .completed && $0.status != .cancelled }
        if relevant.isEmpty { return false }
        return !relevant.filter { $0.startDate == nil }.isEmpty
    }

    /// `UniversalJobBoardCard.compactTaskProgress(project:)`, before: two filters.
    private func oracleCompact(project: Project) -> (completed: Int, total: Int) {
        let tasks = project.tasks.filter { $0.deletedAt == nil && $0.status != .cancelled }
        return (tasks.filter { $0.status == .completed }.count, tasks.count)
    }

    // MARK: - Task card

    func test_taskModelMatchesTheOldWholeTableLookups() throws {
        let fixture = try makeFixture()

        for task in fixture.tasks {
            let model = JobBoardTaskCardModel.make(
                task: task,
                currentUserId: operatorID,
                hasFullTaskView: true
            )
            XCTAssertEqual(
                model.title,
                oracleTitle(task: task, allTaskTypes: fixture.liveTaskTypes),
                "Relationship read must name the same task type as the id lookup (\(task.id))"
            )
            XCTAssertEqual(
                model.subtitle,
                oracleSubtitle(task: task, allProjects: fixture.liveProjects),
                "Relationship read must resolve the same parent project as the id lookup (\(task.id))"
            )
        }
    }

    func test_taskOnATombstonedProjectFallsBackExactlyAsAMissingProjectDid() throws {
        let fixture = try makeFixture()
        let orphan = try XCTUnwrap(fixture.tasks.first { $0.id == "t-on-deleted-project" })
        let missing = try XCTUnwrap(fixture.tasks.first { $0.id == "t-no-project" })

        // The old fetch was predicated deletedAt == nil, so a tombstoned parent
        // was invisible to it — same graceful fallback as no parent at all.
        XCTAssertNotNil(orphan.project, "Fixture must keep the relationship wired to the tombstone")
        let orphanModel = JobBoardTaskCardModel.make(task: orphan, currentUserId: operatorID, hasFullTaskView: true)
        let missingModel = JobBoardTaskCardModel.make(task: missing, currentUserId: operatorID, hasFullTaskView: true)

        XCTAssertEqual(orphanModel.subtitle, "No project")
        XCTAssertEqual(missingModel.subtitle, "No project")
        XCTAssertNil(orphanModel.addressText, "No parent resolves — the row shows no address cell")
        XCTAssertNil(missingModel.addressText)
        XCTAssertEqual(
            orphanModel.subtitle,
            oracleSubtitle(task: orphan, allProjects: fixture.liveProjects),
            "Tombstoned parent must read the same as it did through the predicated fetch"
        )
    }

    func test_taskWithNoResolvableTypeKeepsTheTaskFallback() throws {
        let fixture = try makeFixture()
        let typeless = try XCTUnwrap(fixture.tasks.first { $0.id == "t-typeless" })

        let model = JobBoardTaskCardModel.make(task: typeless, currentUserId: operatorID, hasFullTaskView: true)
        XCTAssertEqual(model.title, "TASK")
        XCTAssertNil(model.typeColorHex, "No type row — the stripe falls back to the neutral token")
        XCTAssertEqual(model.title, oracleTitle(task: typeless, allTaskTypes: fixture.liveTaskTypes))
    }

    func test_taskAssignmentBadgeHonoursScopeAndCrew() throws {
        let fixture = try makeFixture()
        let mine = try XCTUnwrap(fixture.tasks.first { $0.id == "t-mine" })
        let theirs = try XCTUnwrap(fixture.tasks.first { $0.id == "t-theirs" })

        XCTAssertTrue(
            JobBoardTaskCardModel.make(task: mine, currentUserId: operatorID, hasFullTaskView: true).isAssignedToMe
        )
        XCTAssertFalse(
            JobBoardTaskCardModel.make(task: theirs, currentUserId: operatorID, hasFullTaskView: true).isAssignedToMe
        )
        XCTAssertFalse(
            JobBoardTaskCardModel.make(task: mine, currentUserId: operatorID, hasFullTaskView: false).isAssignedToMe,
            "Scoped operators see only their own rows, so the badge would be noise on every card"
        )
        XCTAssertFalse(
            JobBoardTaskCardModel.make(task: mine, currentUserId: nil, hasFullTaskView: true).isAssignedToMe
        )
        XCTAssertEqual(
            JobBoardTaskCardModel.make(task: mine, currentUserId: operatorID, hasFullTaskView: true).teamCount,
            mine.getTeamMemberIds().count,
            "One CSV split now serves both the badge and the crew count"
        )
    }

    func test_taskDateAndReadyStateMatchTheRow() throws {
        let fixture = try makeFixture()
        for task in fixture.tasks {
            let model = JobBoardTaskCardModel.make(task: task, currentUserId: operatorID, hasFullTaskView: true)
            XCTAssertEqual(model.isUnscheduled, task.startDate == nil, task.id)
            XCTAssertEqual(model.isReadyToStart, task.isReadyToStart, task.id)
            if let start = task.startDate {
                XCTAssertEqual(model.dateText, DateHelper.simpleDateString(from: start), task.id)
            } else {
                XCTAssertEqual(model.dateText, "-", "Empty state is an em dash placeholder, never N/A")
            }
        }
    }

    // MARK: - Project card

    func test_projectProgressBarsMatchTheOldFourPassBuild() throws {
        let fixture = try makeFixture()

        for project in fixture.projects {
            let model = JobBoardProjectCardModel.make(
                project: project,
                currentUserId: operatorID,
                hasFullProjectView: true
            )
            XCTAssertEqual(
                model.progress,
                oracleProgress(project: project),
                "Single pass must produce the same ordered segments as the four filters (\(project.id))"
            )
        }
    }

    func test_unscheduledBadgeMatchesTheOldThreePassPredicate() throws {
        let fixture = try makeFixture()

        for project in fixture.projects {
            let model = JobBoardProjectCardModel.make(
                project: project,
                currentUserId: operatorID,
                hasFullProjectView: true
            )
            XCTAssertEqual(
                model.showsUnscheduledBadge,
                oracleShowsUnscheduled(project: project),
                "UNSCHEDULED rule must be unchanged for \(project.id)"
            )
        }

        // The oracle would pass over three empty sets without these.
        let noTasks = try XCTUnwrap(fixture.projects.first { $0.id == "p-no-tasks" })
        let allDone = try XCTUnwrap(fixture.projects.first { $0.id == "p-all-done" })
        let someUnscheduled = try XCTUnwrap(fixture.projects.first { $0.id == "p-mixed" })
        let allScheduled = try XCTUnwrap(fixture.projects.first { $0.id == "p-scheduled" })

        XCTAssertTrue(JobBoardProjectCardModel.make(project: noTasks, currentUserId: nil, hasFullProjectView: true).showsUnscheduledBadge)
        XCTAssertFalse(JobBoardProjectCardModel.make(project: allDone, currentUserId: nil, hasFullProjectView: true).showsUnscheduledBadge)
        XCTAssertTrue(JobBoardProjectCardModel.make(project: someUnscheduled, currentUserId: nil, hasFullProjectView: true).showsUnscheduledBadge)
        XCTAssertFalse(JobBoardProjectCardModel.make(project: allScheduled, currentUserId: nil, hasFullProjectView: true).showsUnscheduledBadge)
    }

    func test_compactProgressMatchesTheOldTwoFilterBuild() throws {
        let fixture = try makeFixture()

        for project in fixture.projects {
            let progress = JobBoardCompactProgress.make(project: project)
            let oracle = oracleCompact(project: project)
            XCTAssertEqual(progress.completed, oracle.completed, project.id)
            XCTAssertEqual(progress.total, oracle.total, project.id)
        }

        let mixed = try XCTUnwrap(fixture.projects.first { $0.id == "p-mixed" })
        XCTAssertGreaterThan(JobBoardCompactProgress.make(project: mixed).total, 0, "Fixture must exercise a non-empty bar")
    }

    func test_projectMetadataMatchesTheRow() throws {
        let fixture = try makeFixture()
        let addressed = try XCTUnwrap(fixture.projects.first { $0.id == "p-mixed" })
        let unaddressed = try XCTUnwrap(fixture.projects.first { $0.id == "p-no-tasks" })

        let addressedModel = JobBoardProjectCardModel.make(project: addressed, currentUserId: operatorID, hasFullProjectView: true)
        XCTAssertEqual(addressedModel.addressText, "1420 Agnes St", "Street only — the city never fits the row")
        XCTAssertEqual(addressedModel.teamCount, addressed.teamMembers.count)
        XCTAssertTrue(addressedModel.isAssignedToMe)

        let unaddressedModel = JobBoardProjectCardModel.make(project: unaddressed, currentUserId: operatorID, hasFullProjectView: true)
        XCTAssertEqual(unaddressedModel.addressText, "NO ADDRESS")
        XCTAssertFalse(unaddressedModel.isAssignedToMe)
    }

    // MARK: - Fixture

    private struct Fixture {
        let projects: [Project]
        let liveProjects: [Project]
        let tasks: [ProjectTask]
        let liveTaskTypes: [TaskType]
    }

    private func makeFixture() throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let user = User(id: operatorID, firstName: "Marcus", lastName: "Hale", role: .crew, companyId: companyID)
        context.insert(user)

        let other = User(id: "user-2", firstName: "Dana", lastName: "Reyes", role: .crew, companyId: companyID)
        context.insert(other)

        let client = Client(id: "client-1", name: "Norcut Holdings", companyId: companyID)
        context.insert(client)

        let framing = TaskType(id: "tt-framing", display: "Framing", color: "#59779F", companyId: companyID, icon: "hammer")
        let cleanup = TaskType(id: "tt-cleanup", display: "Cleanup", color: "#9DB582", companyId: companyID)
        context.insert(framing)
        context.insert(cleanup)

        /// id, title, status, address, tombstoned
        let projectSpecs: [(String, String, Status, String?, Bool)] = [
            ("p-mixed", "South deck rebuild", .inProgress, "1420 Agnes St, New Westminster, BC", false),
            ("p-all-done", "Cedar rail swap", .inProgress, "88 Columbia St", false),
            ("p-scheduled", "Gate repair", .accepted, "12 Sixth Ave", false),
            ("p-no-tasks", "Quote pending", .rfq, nil, false),
            ("p-deleted", "Binned patio", .inProgress, "9 Carnarvon St", true),
        ]
        var projectsByID: [String: Project] = [:]
        var projects: [Project] = []
        for (id, title, status, address, isDeleted) in projectSpecs {
            let project = Project(id: id, title: title, status: status)
            project.companyId = companyID
            project.address = address
            project.client = client
            project.startDate = status == .rfq ? nil : Date(timeIntervalSince1970: 1_760_000_000)
            if isDeleted { project.deletedAt = Date() }
            if id == "p-mixed" {
                project.teamMembers = [user, other]
                project.setTeamMemberIds([operatorID, "user-2"])
            }
            context.insert(project)
            projectsByID[id] = project
            projects.append(project)
        }

        let day: TimeInterval = 86_400
        /// id, project id (nil = no parent at all), type id (nil = unresolvable),
        /// status, scheduled, crew
        let taskSpecs: [(String, String?, String?, TaskStatus, Bool, [String])] = [
            ("t-mine", "p-mixed", "tt-framing", .active, true, [operatorID]),
            ("t-theirs", "p-mixed", "tt-cleanup", .active, false, ["user-2"]),
            ("t-mixed-done", "p-mixed", "tt-framing", .completed, true, [operatorID]),
            ("t-mixed-cancelled", "p-mixed", "tt-cleanup", .cancelled, true, []),
            ("t-mixed-tombstoned", "p-mixed", "tt-framing", .active, true, []),
            ("t-done-1", "p-all-done", "tt-framing", .completed, true, [operatorID]),
            ("t-done-2", "p-all-done", "tt-cleanup", .cancelled, false, []),
            ("t-sched", "p-scheduled", "tt-framing", .active, true, [operatorID]),
            ("t-typeless", "p-scheduled", nil, .active, true, [operatorID]),
            ("t-on-deleted-project", "p-deleted", "tt-framing", .active, true, [operatorID]),
            ("t-no-project", nil, "tt-cleanup", .active, false, [operatorID]),
        ]
        var tasks: [ProjectTask] = []
        for (id, projectID, typeID, status, scheduled, crew) in taskSpecs {
            let task = ProjectTask(
                id: id,
                projectId: projectID ?? "p-does-not-exist",
                taskTypeId: typeID ?? "tt-does-not-exist",
                companyId: companyID,
                status: status
            )
            task.startDate = scheduled ? Date(timeIntervalSinceNow: -2 * day) : nil
            task.setTeamMemberIds(crew)
            task.teamMembers = crew.compactMap { $0 == operatorID ? user : ($0 == "user-2" ? other : nil) }
            // Relationships as `linkAllRelationships` wires them: by id, with no
            // regard for the parent's tombstone.
            if let projectID, let project = projectsByID[projectID] {
                task.project = project
                project.tasks.append(task)
            }
            if let typeID {
                task.taskType = typeID == "tt-framing" ? framing : cleanup
            }
            if id == "t-mixed-tombstoned" { task.deletedAt = Date() }
            context.insert(task)
            tasks.append(task)
        }

        try context.save()

        return Fixture(
            projects: projects,
            liveProjects: projects.filter { $0.deletedAt == nil },
            tasks: tasks,
            liveTaskTypes: [framing, cleanup]
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
            ProjectVinylOrderMarker.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
