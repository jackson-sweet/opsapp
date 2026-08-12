//
//  JobBoardSectionBindingParityTests.swift
//  OPSTests
//
//  The job board's two lists each derived their sections several times per
//  render: the TASK list read `activeTasks`, `completedTasks`, `cancelledTasks`,
//  and `allTasks` separately — every one of them re-running the whole
//  filter+sort pipeline — and the PROJECT list read its three partitions seven
//  times. Both now compute once and bind the result at the top of `body`.
//
//  Binding once is only safe if one computation yields exactly what the several
//  reads did, so the task pipeline is pinned against an oracle that replicates
//  the original `filteredTasks` verbatim, and the project partitions are pinned
//  against the sorted list they must reconstitute.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class JobBoardSectionBindingParityTests: XCTestCase {

    private let companyID = "co-alpha"
    private let operatorID = "user-1"

    // MARK: - Oracle: the pre-refactor `JobBoardTasksView.filteredTasks`

    private func oracleFilteredTasks(
        allTasks: [ProjectTask],
        projectsById: [String: Project],
        taskTypesById: [String: TaskType],
        assignedToMe: Bool,
        currentUserId: String?,
        selectedStatuses: Set<TaskStatus>,
        selectedTaskTypeIds: Set<String>,
        selectedTeamMemberIds: Set<String>,
        searchText: String,
        sortOption: TaskSortOption
    ) -> [ProjectTask] {
        var filtered = allTasks

        filtered = filtered.filter { task in projectsById[task.projectId] != nil }

        if assignedToMe, let userId = currentUserId {
            filtered = filtered.filter { $0.getTeamMemberIds().contains(userId) }
        }

        if !selectedStatuses.isEmpty {
            filtered = filtered.filter { selectedStatuses.contains($0.status) }
        }

        if !selectedTaskTypeIds.isEmpty {
            filtered = filtered.filter { selectedTaskTypeIds.contains($0.taskTypeId) }
        }

        if !selectedTeamMemberIds.isEmpty {
            filtered = filtered.filter { task in
                !Set(task.getTeamMemberIds()).intersection(selectedTeamMemberIds).isEmpty
            }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { task in
                let taskTypeName = taskTypesById[task.taskTypeId]?.display ?? ""
                let projectName = projectsById[task.projectId]?.title ?? ""
                return taskTypeName.localizedCaseInsensitiveContains(searchText) ||
                       projectName.localizedCaseInsensitiveContains(searchText) ||
                       (task.taskNotes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        switch sortOption {
        case .latestEdited:
            return filtered.sorted(by: { t1, t2 in
                let s1 = t1.lastSyncedAt ?? t1.scheduledDate ?? Date.distantPast
                let s2 = t2.lastSyncedAt ?? t2.scheduledDate ?? Date.distantPast
                return s1 > s2
            })
        case .earliestEdited:
            return filtered.sorted(by: { t1, t2 in
                let s1 = t1.lastSyncedAt ?? t1.scheduledDate ?? Date.distantFuture
                let s2 = t2.lastSyncedAt ?? t2.scheduledDate ?? Date.distantFuture
                return s1 < s2
            })
        case .scheduledDateDescending:
            return filtered.sorted(by: { ($0.scheduledDate ?? Date.distantPast) > ($1.scheduledDate ?? Date.distantPast) })
        case .scheduledDateAscending:
            return filtered.sorted(by: { ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast) })
        case .statusAscending:
            return filtered.sorted(by: { $0.status.sortOrder < $1.status.sortOrder })
        case .statusDescending:
            return filtered.sorted(by: { $0.status.sortOrder > $1.status.sortOrder })
        }
    }

    // MARK: - Task sections

    func test_taskSectionsMatchTheOldPerPartitionDerivations() throws {
        let fixture = try makeFixture()

        /// Every filter shape the list can be in, so one binding is proven to
        /// replace the repeated reads under each of them.
        let cases: [(String, Bool, Set<TaskStatus>, Set<String>, Set<String>, String, TaskSortOption)] = [
            ("unfiltered / latest", false, [], [], [], "", .latestEdited),
            ("assigned to me", true, [], [], [], "", .latestEdited),
            ("status filter", false, [.active], [], [], "", .statusAscending),
            ("type filter", false, [], ["tt-framing"], [], "", .scheduledDateAscending),
            ("crew filter", false, [], [], ["user-2"], "", .earliestEdited),
            ("search", false, [], [], [], "deck", .scheduledDateDescending),
            ("search on notes", false, [], [], [], "punch list", .statusDescending),
            ("stacked filters", true, [.active], ["tt-framing"], [operatorID], "deck", .latestEdited),
        ]

        for (name, assignedToMe, statuses, typeIDs, crewIDs, search, sort) in cases {
            let expected = oracleFilteredTasks(
                allTasks: fixture.visibleTasks,
                projectsById: fixture.projectsByID,
                taskTypesById: fixture.taskTypesByID,
                assignedToMe: assignedToMe,
                currentUserId: operatorID,
                selectedStatuses: statuses,
                selectedTaskTypeIds: typeIDs,
                selectedTeamMemberIds: crewIDs,
                searchText: search,
                sortOption: sort
            )

            let sections = JobBoardTaskFiltering.sections(
                visibleTasks: fixture.visibleTasks,
                projectsById: fixture.projectsByID,
                taskTypesById: fixture.taskTypesByID,
                assignedToUserId: assignedToMe ? operatorID : nil,
                selectedStatuses: statuses,
                selectedTaskTypeIds: typeIDs,
                selectedTeamMemberIds: crewIDs,
                searchText: search,
                sortOption: sort
            )

            XCTAssertEqual(
                sections.active.map(\.id),
                expected.filter { $0.status != .cancelled && $0.status != .completed }.map(\.id),
                "ACTIVE rows and their order must be unchanged — \(name)"
            )
            XCTAssertEqual(
                sections.completed.map(\.id),
                expected.filter { $0.status == .completed }.map(\.id),
                "COMPLETED rows and their order must be unchanged — \(name)"
            )
            XCTAssertEqual(
                sections.cancelled.map(\.id),
                expected.filter { $0.status == .cancelled }.map(\.id),
                "CANCELLED rows and their order must be unchanged — \(name)"
            )
            XCTAssertEqual(
                sections.visible.map(\.id),
                fixture.visibleTasks.map(\.id),
                "The empty state keys off the unfiltered set — \(name)"
            )
        }
    }

    func test_taskSectionsAreNotVacuous() throws {
        let fixture = try makeFixture()

        let sections = JobBoardTaskFiltering.sections(
            visibleTasks: fixture.visibleTasks,
            projectsById: fixture.projectsByID,
            taskTypesById: fixture.taskTypesByID,
            assignedToUserId: nil,
            selectedStatuses: [],
            selectedTaskTypeIds: [],
            selectedTeamMemberIds: [],
            searchText: "",
            sortOption: .latestEdited
        )

        // Absolute expectations, derived from the fixture rather than from
        // either implementation — so the parity assertions can never pass over
        // three empty arrays.
        XCTAssertEqual(sections.active.map(\.id).sorted(), ["t-a1", "t-a2", "t-b1"])
        XCTAssertEqual(sections.completed.map(\.id), ["t-done"])
        XCTAssertEqual(sections.cancelled.map(\.id), ["t-cancelled"])
        XCTAssertFalse(
            sections.visible.contains { $0.id == "t-rfq" },
            "Tasks on a pre-acceptance project never enter the visible set"
        )
        // `t-orphan` hangs off an active project's task list but names a
        // projectId no live project answers to — visible to the empty state,
        // excluded from every section, exactly as the old pipeline had it.
        XCTAssertTrue(sections.visible.contains { $0.id == "t-orphan" })
        XCTAssertFalse(
            (sections.active + sections.completed + sections.cancelled).contains { $0.id == "t-orphan" },
            "A task whose project is not in the map never reaches a section"
        )
    }

    func test_noCompanyProducesNoRowsInAnySection() throws {
        let fixture = try makeFixture()

        // The old code guarded `guard let companyId … else { return [] }` before
        // building its task-type map; nil must still mean an empty list rather
        // than an unfiltered one.
        let sections = JobBoardTaskFiltering.sections(
            visibleTasks: fixture.visibleTasks,
            projectsById: fixture.projectsByID,
            taskTypesById: nil,
            assignedToUserId: nil,
            selectedStatuses: [],
            selectedTaskTypeIds: [],
            selectedTeamMemberIds: [],
            searchText: "",
            sortOption: .latestEdited
        )

        XCTAssertTrue(sections.active.isEmpty)
        XCTAssertTrue(sections.completed.isEmpty)
        XCTAssertTrue(sections.cancelled.isEmpty)
        XCTAssertFalse(
            sections.visible.isEmpty,
            "The empty state still reflects that tasks exist — it just can't scope them"
        )
    }

    func test_duplicateTaskRowsAreStillDedupedIntoTheVisibleSet() throws {
        let fixture = try makeFixture()

        // The real sync-anomaly shape the guard exists for: one task row
        // reachable through TWO projects' task arrays. Without the dedup,
        // visibleTasks(from:) yields the row once per parent.
        let duplicated = try XCTUnwrap(
            fixture.projectsByID["p-a"]?.tasks.first { $0.id == "t-a1" }
        )
        fixture.projectsByID["p-b"]?.tasks.append(duplicated)

        let visible = JobBoardTaskFiltering.visibleTasks(from: fixture.projects)
        XCTAssertEqual(
            visible.filter { $0.id == "t-a1" }.count,
            1,
            "A task reachable through two parents must surface exactly once"
        )
    }

    // MARK: - Project sections

    func test_projectPartitionsReconstituteTheSortedListForEverySort() throws {
        let fixture = try makeFixture()

        for sort in ProjectSortOption.allCases {
            let sorted = JobBoardProjectFiltering.sortedProjects(fixture.projects, sortOption: sort)
            let sections = JobBoardProjectFiltering.projectSections(from: fixture.projects, sortOption: sort)

            XCTAssertEqual(
                sections.active.map(\.id),
                sorted.filter { $0.status != .closed && $0.status != .archived }.map(\.id),
                "ACTIVE partition — \(sort.rawValue)"
            )
            XCTAssertEqual(
                sections.closed.map(\.id),
                sorted.filter { $0.status == .closed }.map(\.id),
                "CLOSED partition — \(sort.rawValue)"
            )
            XCTAssertEqual(
                sections.archived.map(\.id),
                sorted.filter { $0.status == .archived }.map(\.id),
                "ARCHIVED partition — \(sort.rawValue)"
            )
            XCTAssertEqual(
                Set(sections.active.map(\.id))
                    .union(sections.closed.map(\.id))
                    .union(sections.archived.map(\.id)),
                Set(fixture.projects.map(\.id)),
                "Every project lands in exactly one section — \(sort.rawValue)"
            )
        }
    }

    func test_projectSectionsAreDeterministicAcrossRepeatedReads() throws {
        let fixture = try makeFixture()

        // Seven reads per render became one binding; that is only equivalent if
        // repeated derivations agree — including where the comparator ties.
        for sort in ProjectSortOption.allCases {
            let first = JobBoardProjectFiltering.projectSections(from: fixture.projects, sortOption: sort)
            for _ in 0..<3 {
                let again = JobBoardProjectFiltering.projectSections(from: fixture.projects, sortOption: sort)
                XCTAssertEqual(first.active.map(\.id), again.active.map(\.id), sort.rawValue)
                XCTAssertEqual(first.closed.map(\.id), again.closed.map(\.id), sort.rawValue)
                XCTAssertEqual(first.archived.map(\.id), again.archived.map(\.id), sort.rawValue)
            }
        }

        let sections = JobBoardProjectFiltering.projectSections(from: fixture.projects, sortOption: .latestEdited)
        XCTAssertFalse(sections.active.isEmpty)
        XCTAssertFalse(sections.closed.isEmpty)
        XCTAssertFalse(sections.archived.isEmpty)
    }

    // MARK: - Fixture

    private struct Fixture {
        let projects: [Project]
        let projectsByID: [String: Project]
        let taskTypesByID: [String: TaskType]
        let visibleTasks: [ProjectTask]
    }

    private func makeFixture() throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let user = User(id: operatorID, firstName: "Marcus", lastName: "Hale", role: .crew, companyId: companyID)
        let other = User(id: "user-2", firstName: "Dana", lastName: "Reyes", role: .crew, companyId: companyID)
        context.insert(user)
        context.insert(other)

        let framing = TaskType(id: "tt-framing", display: "Framing", color: "#59779F", companyId: companyID)
        let cleanup = TaskType(id: "tt-cleanup", display: "Cleanup", color: "#9DB582", companyId: companyID)
        context.insert(framing)
        context.insert(cleanup)

        /// id, title, status
        let projectSpecs: [(String, String, Status)] = [
            ("p-a", "South deck rebuild", .inProgress),
            ("p-b", "Cedar rail swap", .accepted),
            ("p-rfq", "Quote pending", .rfq),
            ("p-closed", "Paid and filed", .closed),
            ("p-archived", "Old job", .archived),
        ]
        var projects: [Project] = []
        var projectsByID: [String: Project] = [:]
        let day: TimeInterval = 86_400
        for (index, spec) in projectSpecs.enumerated() {
            let project = Project(id: spec.0, title: spec.1, status: spec.2)
            project.companyId = companyID
            project.startDate = Date(timeIntervalSinceNow: -Double(index) * day)
            project.endDate = Date(timeIntervalSinceNow: Double(index) * day)
            project.updatedAt = Date(timeIntervalSinceNow: -Double(index) * 2 * day)
            project.createdAt = Date(timeIntervalSinceNow: -Double(index) * 3 * day)
            project.teamMembers = index.isMultiple(of: 2) ? [user] : [other]
            project.setTeamMemberIds(index.isMultiple(of: 2) ? [operatorID] : ["user-2"])
            context.insert(project)
            projects.append(project)
            projectsByID[spec.0] = project
        }

        /// id, project id, type id, status, crew, notes, days scheduled ago
        let taskSpecs: [(String, String, String, TaskStatus, [String], String?, Double)] = [
            ("t-a1", "p-a", "tt-framing", .active, [operatorID], nil, 1),
            ("t-a2", "p-a", "tt-cleanup", .active, ["user-2"], "punch list walk", 2),
            ("t-b1", "p-b", "tt-framing", .active, [operatorID], nil, 3),
            ("t-done", "p-a", "tt-framing", .completed, [operatorID], nil, 4),
            ("t-cancelled", "p-b", "tt-cleanup", .cancelled, ["user-2"], nil, 5),
            ("t-rfq", "p-rfq", "tt-framing", .active, [operatorID], nil, 6),
            ("t-orphan", "p-a", "tt-framing", .active, [operatorID], nil, 7),
        ]
        for (id, projectID, typeID, status, crew, notes, daysAgo) in taskSpecs {
            let task = ProjectTask(
                id: id,
                projectId: id == "t-orphan" ? "p-not-in-map" : projectID,
                taskTypeId: typeID,
                companyId: companyID,
                status: status
            )
            task.startDate = Date(timeIntervalSinceNow: -daysAgo * day)
            task.endDate = Date(timeIntervalSinceNow: -daysAgo * day + 3_600)
            task.lastSyncedAt = Date(timeIntervalSinceNow: -daysAgo * day / 2)
            task.taskNotes = notes
            task.setTeamMemberIds(crew)
            if let project = projectsByID[projectID] {
                task.project = project
                project.tasks.append(task)
            }
            task.taskType = typeID == "tt-framing" ? framing : cleanup
            context.insert(task)
        }

        try context.save()

        // The list feeds `visibleTasks(from:)` the same way the view does.
        let visible = JobBoardTaskFiltering.visibleTasks(from: projects)

        return Fixture(
            projects: projects,
            projectsByID: projectsByID,
            taskTypesByID: ["tt-framing": framing, "tt-cleanup": cleanup],
            visibleTasks: visible
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
