//
//  ProjectTeamSyncPayloadTests.swift
//  OPSTests
//
//  Regression coverage for server-derived project team membership sync.
//

import XCTest
@testable import OPS

@MainActor
final class ProjectTeamSyncPayloadTests: XCTestCase {

    func testProjectSyncPayloadDropsDerivedTeamMemberIds() throws {
        let sanitized = OutboundProcessor.sanitizedProjectPayloadForSync([
            "title": "Deck rebuild",
            "team_member_ids": ["crew-a", "crew-b"],
            "project_images": ["image-a"]
        ])

        XCTAssertEqual(sanitized["title"] as? String, "Deck rebuild")
        XCTAssertEqual(sanitized["project_images"] as? [String], ["image-a"])
        XCTAssertNil(sanitized["team_member_ids"])
    }

    func testProjectTaskSyncPayloadKeepsTaskTeamMemberIds() throws {
        let sanitized = OutboundProcessor.sanitizedProjectTaskPayloadForSync([
            "project_id": "project-a",
            "team_member_ids": ["crew-a", "crew-b"],
            "display_order": 3
        ])

        XCTAssertEqual(sanitized["project_id"] as? String, "project-a")
        XCTAssertEqual(sanitized["team_member_ids"] as? [String], ["crew-a", "crew-b"])
        XCTAssertEqual(sanitized["display_order"] as? Int, 3)
    }

    func testProjectTeamSyncGateOnlyReportsMissingRelationshipIds() {
        let missing = DataController.projectTeamMemberIdsNeedingRelationshipSync(
            storedIds: ["crew-a", "crew-b", "crew-a"],
            relationshipIds: ["crew-b"]
        )

        XCTAssertEqual(missing, ["crew-a"])
    }

    func testProjectTeamSyncGateSkipsFullyHydratedProject() {
        let missing = DataController.projectTeamMemberIdsNeedingRelationshipSync(
            storedIds: ["crew-a", "crew-b"],
            relationshipIds: ["crew-b", "crew-a"]
        )

        XCTAssertTrue(missing.isEmpty)
    }

    // MARK: - Per-task optimistic mirror of project-team RPC delta

    /// Removing a member that lived on only one task must empty that task, not
    /// flatten every task to the surviving project team. (task A:[alice],
    /// B:[bob]; remove alice → A:[], B:[bob] — never A:[bob], B:[bob].)
    func testTaskCrewAfterRemovalDoesNotCrossAssignSurvivingMember() {
        let taskA = DataController.projectTaskTeamMemberIdsAfterServerAssignment(
            currentTaskMemberIds: ["alice"],
            removedMemberIds: ["alice"],
            addedMemberIds: []
        )
        let taskB = DataController.projectTaskTeamMemberIdsAfterServerAssignment(
            currentTaskMemberIds: ["bob"],
            removedMemberIds: ["alice"],
            addedMemberIds: []
        )

        XCTAssertEqual(taskA, [])
        XCTAssertEqual(taskB, ["bob"])
    }

    /// Adding a member adds them to every task, but unchanged members keep their
    /// per-task differentiation. (task A:[alice], B:[alice,bob]; add carol →
    /// A:[alice,carol], B:[alice,bob,carol] — bob is never spread onto task A.)
    func testTaskCrewAfterAdditionPreservesPerTaskDifferentiation() {
        let taskA = DataController.projectTaskTeamMemberIdsAfterServerAssignment(
            currentTaskMemberIds: ["alice"],
            removedMemberIds: [],
            addedMemberIds: ["carol"]
        )
        let taskB = DataController.projectTaskTeamMemberIdsAfterServerAssignment(
            currentTaskMemberIds: ["alice", "bob"],
            removedMemberIds: [],
            addedMemberIds: ["carol"]
        )

        XCTAssertEqual(taskA, ["alice", "carol"])
        XCTAssertEqual(taskB, ["alice", "bob", "carol"])
    }

    /// A simultaneous add + remove applies both deltas per task without
    /// resurrecting the removed member or duplicating the added one.
    func testTaskCrewAppliesAddAndRemoveDeltaTogether() {
        let result = DataController.projectTaskTeamMemberIdsAfterServerAssignment(
            currentTaskMemberIds: ["alice", "bob"],
            removedMemberIds: ["alice"],
            addedMemberIds: ["carol", "bob"]
        )

        XCTAssertEqual(result, ["bob", "carol"])
    }

    /// Output is lowercased and sorted to match Postgres's stored uuid casing
    /// and `array_agg(distinct member_id order by member_id)` ordering.
    func testTaskCrewNormalizesCasingAndSortsResult() {
        let result = DataController.projectTaskTeamMemberIdsAfterServerAssignment(
            currentTaskMemberIds: ["Bob", "ALICE"],
            removedMemberIds: [],
            addedMemberIds: ["Carol"]
        )

        XCTAssertEqual(result, ["alice", "bob", "carol"])
    }
}
