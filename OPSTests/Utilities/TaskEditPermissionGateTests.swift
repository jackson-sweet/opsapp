//
//  TaskEditPermissionGateTests.swift
//  OPSTests
//
//  Bug 10b66fce — the expanded task sheet honoured exactly one gate (dates, on
//  `calendar.edit`) and ignored every other one. TEAM reassignment was fully
//  open, the status buttons were fully open, and `ProjectTask.canEdit` checked
//  `tasks.edit` without ever consulting its scope — so an `assigned`-scope
//  grant behaved like `all` on any task in the company.
//
//  These pin the three task gates the sheet must honour, each mirroring the
//  shape of the schedule gate that already worked:
//    tasks.edit          → all / assigned   (edit type + description)
//    tasks.assign        → all only         (reassign the crew)
//    tasks.change_status → all / assigned   (complete, reopen, cancel)
//
//  Scope semantics match `PermissionStore.canEditSchedule`: an `assigned`
//  grant reaches only rows the operator is on, ids compare case-insensitively
//  (Postgres stores uuids lowercased), and a feature-flag block beats the
//  role grant.
//

import XCTest
@testable import OPS

final class TaskEditPermissionGateTests: XCTestCase {

    private func store(
        _ permissions: [String: String],
        operatorId: String? = "user-1",
        blockedByFlags: Set<String> = []
    ) -> PermissionStore {
        let store = PermissionStore()
        store.permissions = permissions
        store.blockedByFlags = blockedByFlags
        store.disabledFlags = []
        store.setPreviewOperatorId(operatorId)
        return store
    }

    // MARK: - tasks.edit (type + description)

    func testTaskFieldEditsAreDeniedWithoutAGrant() {
        XCTAssertFalse(store([:]).canEditTaskFields(assigneeIds: ["user-1"]))
    }

    func testTaskFieldEditsWithAllScopeReachAnyTask() {
        let permissions = store(["tasks.edit": "all"])
        XCTAssertTrue(permissions.canEditTaskFields(assigneeIds: []))
        XCTAssertTrue(permissions.canEditTaskFields(assigneeIds: ["someone-else"]))
    }

    func testTaskFieldEditsWithAssignedScopeReachOnlyOwnTasks() {
        let permissions = store(["tasks.edit": "assigned"])
        XCTAssertTrue(permissions.canEditTaskFields(assigneeIds: ["user-1", "user-2"]))
        XCTAssertFalse(
            permissions.canEditTaskFields(assigneeIds: ["user-2"]),
            "An assigned-scope grant must not reach a task the operator is not on."
        )
        XCTAssertFalse(permissions.canEditTaskFields(assigneeIds: []))
    }

    /// Ids arrive lowercased from Postgres but `UUID().uuidString` is uppercase.
    func testTaskFieldEditScopeMatchesAssigneeIdsCaseInsensitively() {
        let permissions = store(["tasks.edit": "assigned"], operatorId: "ABC-123")
        XCTAssertTrue(permissions.canEditTaskFields(assigneeIds: ["abc-123"]))
    }

    func testTaskFieldEditsAreDeniedWhenTheFeatureFlagBlocksThem() {
        let permissions = store(["tasks.edit": "all"], blockedByFlags: ["tasks.edit"])
        XCTAssertFalse(permissions.canEditTaskFields(assigneeIds: ["user-1"]))
    }

    // MARK: - tasks.assign (crew reassignment)

    func testCrewReassignmentIsDeniedWithoutAGrant() {
        XCTAssertFalse(store([:]).canAssignTaskCrew)
    }

    func testCrewReassignmentRequiresFullAccess() {
        XCTAssertTrue(store(["tasks.assign": "all"]).canAssignTaskCrew)
        XCTAssertFalse(
            store(["tasks.assign": "assigned"]).canAssignTaskCrew,
            "tasks.assign is defined all-only — a narrower value must not grant it."
        )
    }

    func testCrewReassignmentIsDeniedWhenTheFeatureFlagBlocksIt() {
        XCTAssertFalse(
            store(["tasks.assign": "all"], blockedByFlags: ["tasks.assign"]).canAssignTaskCrew
        )
    }

    // MARK: - tasks.change_status (complete / reopen / cancel)

    func testStatusChangesAreDeniedWithoutAGrant() {
        XCTAssertFalse(store([:]).canChangeTaskStatus(assigneeIds: ["user-1"]))
    }

    func testStatusChangesWithAllScopeReachAnyTask() {
        XCTAssertTrue(store(["tasks.change_status": "all"]).canChangeTaskStatus(assigneeIds: ["other"]))
    }

    func testStatusChangesWithAssignedScopeReachOnlyOwnTasks() {
        let permissions = store(["tasks.change_status": "assigned"])
        XCTAssertTrue(permissions.canChangeTaskStatus(assigneeIds: ["user-1"]))
        XCTAssertFalse(permissions.canChangeTaskStatus(assigneeIds: ["user-2"]))
    }

    func testStatusChangesAreDeniedWhenTheFeatureFlagBlocksThem() {
        XCTAssertFalse(
            store(["tasks.change_status": "all"], blockedByFlags: ["tasks.change_status"])
                .canChangeTaskStatus(assigneeIds: ["user-1"])
        )
    }

    // MARK: - The gates are independent

    /// A Crew operator with assigned-scope status rights but no edit rights is
    /// the exact case the sheet used to get wrong: it let them retype the job.
    func testStatusRightsDoNotImplyFieldEditRights() {
        let permissions = store(["tasks.change_status": "assigned"])
        XCTAssertTrue(permissions.canChangeTaskStatus(assigneeIds: ["user-1"]))
        XCTAssertFalse(permissions.canEditTaskFields(assigneeIds: ["user-1"]))
        XCTAssertFalse(permissions.canAssignTaskCrew)
    }

    /// …and the inverse: full edit rights say nothing about reassigning crew.
    func testFieldEditRightsDoNotImplyCrewReassignment() {
        let permissions = store(["tasks.edit": "all"])
        XCTAssertTrue(permissions.canEditTaskFields(assigneeIds: ["user-1"]))
        XCTAssertFalse(permissions.canAssignTaskCrew)
    }

    // MARK: - ProjectTask surfaces the gates against the shared store

    func testProjectTaskExposesTheGatesFromTheSharedStore() {
        let shared = PermissionStore.shared
        let previousPermissions = shared.permissions
        let previousBlocked = shared.blockedByFlags
        defer {
            shared.permissions = previousPermissions
            shared.blockedByFlags = previousBlocked
        }

        shared.permissions = ["tasks.edit": "assigned", "tasks.change_status": "all"]
        shared.blockedByFlags = []
        shared.setPreviewOperatorId("user-1")

        let mine = ProjectTask(id: "t1", projectId: "p1", taskTypeId: "tt", companyId: "co")
        mine.teamMemberIdsString = "user-1"

        let theirs = ProjectTask(id: "t2", projectId: "p1", taskTypeId: "tt", companyId: "co")
        theirs.teamMemberIdsString = "user-2"

        XCTAssertTrue(mine.canEditFields)
        XCTAssertFalse(theirs.canEditFields, "assigned scope stops at tasks the operator is on")
        XCTAssertTrue(mine.canChangeStatus)
        XCTAssertTrue(theirs.canChangeStatus, "all scope reaches every task")
        XCTAssertFalse(mine.canAssignCrew, "no tasks.assign grant")
    }
}
