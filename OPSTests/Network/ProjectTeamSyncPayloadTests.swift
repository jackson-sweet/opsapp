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

    /// Regression: the Deck Builder "MARK ORDERED" write sends only the
    /// `vinyl_order_*` columns. They live on `projects` (projected locally into
    /// ProjectVinylOrderMarker), so if the outbound allowlist drops them the
    /// server never persists the status and the optimistic marker reverts on the
    /// next sync. Both outbound paths must keep them.
    func testProjectSyncPayloadKeepsVinylOrderFields() throws {
        let payload: [String: Any] = [
            "vinyl_order_status": "ordered",
            "vinyl_ordered_at": "2026-06-15T00:00:00Z",
            "vinyl_ordered_by": "user-1"
        ]

        let legacy = OutboundProcessor.sanitizedProjectPayloadForSync(payload)
        XCTAssertEqual(legacy["vinyl_order_status"] as? String, "ordered")
        XCTAssertEqual(legacy["vinyl_ordered_at"] as? String, "2026-06-15T00:00:00Z")
        XCTAssertEqual(legacy["vinyl_ordered_by"] as? String, "user-1")

        let active = DataActor.sanitizedProjectPayloadForSync(payload)
        XCTAssertEqual(active["vinyl_order_status"] as? String, "ordered")
        XCTAssertEqual(active["vinyl_ordered_at"] as? String, "2026-06-15T00:00:00Z")
        XCTAssertEqual(active["vinyl_ordered_by"] as? String, "user-1")
    }

    /// Regression (bug bbc2d228): `title_is_auto` was present in
    /// OutboundProcessor's allowlist but missing from DataActor's copy, so a
    /// rename pushed through the default path lost the `title_is_auto: false`
    /// flip and the server's `projects_autoname` trigger re-derived the old
    /// address title over the user's rename. Both paths must keep it (and
    /// `priority_rank`, which drifted the same way).
    func testProjectSyncPayloadKeepsTitleAutoFlagOnBothPaths() throws {
        let payload: [String: Any] = [
            "title": "Harbour house reroof",
            "title_is_auto": false,
            "priority_rank": 4
        ]

        let legacy = OutboundProcessor.sanitizedProjectPayloadForSync(payload)
        XCTAssertEqual(legacy["title_is_auto"] as? Bool, false)
        XCTAssertEqual(legacy["priority_rank"] as? Int, 4)

        let active = DataActor.sanitizedProjectPayloadForSync(payload)
        XCTAssertEqual(active["title_is_auto"] as? Bool, false)
        XCTAssertEqual(active["priority_rank"] as? Int, 4)
    }

    /// Drift tripwire: both outbound project sanitizers must accept the SAME
    /// column set. Feeds a probe payload covering the full union of known
    /// server columns plus local-only keys; if one allowlist gains or loses a
    /// column the other doesn't, the surviving key sets diverge and this fails
    /// — the exact failure mode that let `title_is_auto` drift unnoticed.
    func testProjectSanitizerAllowlistsDoNotDrift() throws {
        let probeColumns: [String] = [
            "id", "bubble_id", "company_id", "client_id", "opportunity_id",
            "title", "title_is_auto", "status", "address", "latitude", "longitude",
            "start_date", "end_date", "duration", "notes", "description",
            "all_day", "project_images", "completed_at",
            "vinyl_order_status", "vinyl_ordered_at", "vinyl_ordered_by",
            "deleted_at", "created_at", "updated_at", "priority_rank",
            // Local-only keys — both paths must strip these.
            "needs_sync", "team_member_ids", "task_index", "last_synced_at"
        ]
        let payload = Dictionary(uniqueKeysWithValues: probeColumns.map { ($0, "probe" as Any) })

        let legacyKeys = Set(OutboundProcessor.sanitizedProjectPayloadForSync(payload).keys)
        let activeKeys = Set(DataActor.sanitizedProjectPayloadForSync(payload).keys)

        XCTAssertEqual(
            legacyKeys, activeKeys,
            "OutboundProcessor and DataActor project allowlists drifted: " +
            "only-legacy=\(legacyKeys.subtracting(activeKeys).sorted()) " +
            "only-active=\(activeKeys.subtracting(legacyKeys).sorted())"
        )
        XCTAssertFalse(legacyKeys.contains("needs_sync"))
        XCTAssertFalse(legacyKeys.contains("team_member_ids"))
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
