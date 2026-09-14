import SwiftData
import XCTest
@testable import OPS

@MainActor
final class ProjectReopenSyncTests: XCTestCase {
    func testParkedReopenHoldsLaterProjectArchiveAndTaskEdit() {
        let reopen = operation(type: "project", action: "reopenForTask", fields: ["status": "Accepted"])
        let archive = operation(type: "project", action: "update", fields: ["status": "Archived"])
        archive.createdAt = reopen.createdAt.addingTimeInterval(1)
        reopen.status = "parked"
        XCTAssertTrue(SyncCrossEntityDependency.isHeld(archive, in: [reopen, archive]))
        let schedule = operation(type: "projectTask", action: "update", fields: ["start_date": "2026-09-20"])
        schedule.dependsOnId = reopen.id.uuidString
        let edit = operation(type: "projectTask", action: "update", fields: ["task_notes": "Retained"])
        edit.createdAt = schedule.createdAt.addingTimeInterval(1)
        XCTAssertTrue(SyncCrossEntityDependency.isHeld(edit, in: [reopen, schedule, edit]))
        reopen.status = "completed"
        schedule.status = "completed"
        XCTAssertFalse(SyncCrossEntityDependency.isHeld(archive, in: [reopen, archive]))
        XCTAssertFalse(SyncCrossEntityDependency.isHeld(edit, in: [schedule, edit]))
    }

    func testPairedTaskCreateWaitsForBothReopenAndPredecessorCreation() {
        let reopen = operation(type: "project", action: "reopenForTask", fields: ["status": "accepted"])
        reopen.status = "parked"
        let predecessor = operation(type: "projectTask", action: "create", fields: ["project_id": "fixture"])
        predecessor.entityId = "predecessor"
        let paired = operation(type: "projectTask", action: "create", fields: ["project_id": "fixture", "paired_from_task_id": "predecessor"])
        XCTAssertTrue(SyncCrossEntityDependency.isHeld(paired, in: [reopen, predecessor, paired]))
        reopen.status = "completed"
        XCTAssertTrue(SyncCrossEntityDependency.isHeld(paired, in: [reopen, predecessor, paired]))
        predecessor.status = "completed"
        XCTAssertFalse(SyncCrossEntityDependency.isHeld(paired, in: [reopen, predecessor, paired]))
    }

    func testDependentScheduleCannotOvertakeOlderTaskEditInBackoff() {
        let older = operation(type: "projectTask", action: "update", fields: ["start_date": "2026-09-18"])
        older.status = "failed"
        let newer = operation(type: "projectTask", action: "update", fields: ["start_date": "2026-09-20"])
        newer.createdAt = older.createdAt.addingTimeInterval(1)
        newer.dependsOnId = UUID().uuidString
        XCTAssertTrue(SyncCrossEntityDependency.isHeld(newer, in: [older, newer]))
        older.status = "completed"
        XCTAssertFalse(SyncCrossEntityDependency.isHeld(newer, in: [older, newer]))
    }

    func testReopenWaitsForAnOlderProjectMutation() {
        let prior = operation(type: "project", action: "update", fields: ["title": "Updated"])
        let reopen = operation(type: "project", action: "reopenForTask", fields: ["status": "Accepted"])
        reopen.createdAt = prior.createdAt.addingTimeInterval(1)
        prior.status = "failed"
        XCTAssertTrue(ProjectReopenSync.isHeld(reopen, in: [prior, reopen]))
        prior.entityId = "another-project"
        XCTAssertFalse(ProjectReopenSync.isHeld(reopen, in: [prior, reopen]))
    }

    func testCoalescingCannotAcknowledgeReopenOrDiscardDependentCreate() {
        let reopen = operation(type: "project", action: "reopenForTask", fields: ["status": "Accepted"])
        let archive = operation(type: "project", action: "update", fields: ["status": "Archived"])
        let create = operation(type: "projectTask", action: "create", fields: ["start_date": "2026-09-20"])
        create.dependsOnId = reopen.id.uuidString
        let edit = operation(type: "projectTask", action: "update", fields: ["task_notes": "Retained"])
        let inputs = [reopen, archive, create, edit]
        let result = OutboundProcessor().coalesceOperations(inputs)
        XCTAssertEqual(Set(result.map(\.id)), Set(inputs.map(\.id)))
        XCTAssertTrue(inputs.allSatisfy { $0.status == "pending" && $0.completedAt == nil })
    }

    func testRevisionCacheKeepsMicrosecondsAndCompanyBoundaryAcrossReload() throws {
        let suite = "ProjectReopenSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let company = UUID().uuidString
        let project = UUID().uuidString
        let object = ["id": project, "company_id": company, "title": "Fixture", "status": "Archived", "updated_at": "2026-09-12T10:11:12.123456Z"]
        let dto = try JSONDecoder().decode(SupabaseProjectDTO.self, from: JSONSerialization.data(withJSONObject: object))
        ProjectRevisionCache(defaults: defaults).record(dto)
        let reloaded = ProjectRevisionCache(defaults: defaults)
        XCTAssertEqual(reloaded.snapshot(companyId: company.lowercased(), projectId: project.lowercased())?.updatedAt, object["updated_at"])
        XCTAssertNil(reloaded.snapshot(companyId: UUID().uuidString, projectId: project))
    }

    private func operation(type: String, action: String, fields: [String: String]) -> SyncOperation {
        SyncOperation(entityType: type, entityId: "fixture", operationType: action,
            payload: try! JSONSerialization.data(withJSONObject: fields), changedFields: Array(fields.keys))
    }
}
