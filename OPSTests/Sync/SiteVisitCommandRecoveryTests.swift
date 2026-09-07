import XCTest
@testable import OPS

@MainActor
final class SiteVisitCommandRecoveryTests: XCTestCase {
    private let actor = "11111111-1111-1111-1111-111111111111"
    private let company = "22222222-2222-2222-2222-222222222222"
    private let visit = "33333333-3333-3333-3333-333333333333"
    private let lead = "44444444-4444-4444-4444-444444444444"

    func testAutomaticRetryRetainsOriginalSnapshotAndExactAuthority() throws {
        let operation = try makeOperation()
        let originalPayload = operation.payload
        for status in ["failed", "inProgress"] {
            operation.status = status
            XCTAssertTrue(SiteVisitCommandRecoveryPolicy.mayAutomaticallyResume(operation, userId: actor, companyId: company))
            XCTAssertFalse(SiteVisitCommandRecoveryPolicy.mayAutomaticallyResume(operation, userId: "another-actor", companyId: company))
            XCTAssertFalse(SiteVisitCommandRecoveryPolicy.mayAutomaticallyResume(operation, userId: actor, companyId: "another-company"))
            XCTAssertFalse(SiteVisitCommandRecoveryPolicy.mayAutomaticallyResume(operation, userId: nil, companyId: company))
            XCTAssertEqual(operation.payload, originalPayload, "Recovery cannot obtain a newer expected revision")
        }
        operation.entityId = "different-visit"
        XCTAssertFalse(SiteVisitCommandRecoveryPolicy.mayAutomaticallyResume(operation, userId: actor, companyId: company))
    }

    func testMissingOriginalSnapshotAndStoppedCustodyNeverAutomaticallyResume() throws {
        let missing = try makeOperation(includeSnapshot: false)
        missing.status = "failed"
        XCTAssertFalse(SiteVisitCommandRecoveryPolicy.mayAutomaticallyResume(missing, userId: actor, companyId: company))
        let operation = try makeOperation()
        for status in ["parked", "quarantined", "declined", "completed"] {
            operation.status = status
            let originalPayload = operation.payload
            XCTAssertFalse(SiteVisitCommandRecoveryPolicy.mayAutomaticallyResume(operation, userId: actor, companyId: company))
            XCTAssertEqual(operation.status, status)
            XCTAssertEqual(operation.payload, originalPayload)
        }
    }

    func testLegacyEnvelopeCannotTurnIntoAStageCommand() throws {
        let operation = SyncOperation(entityType: "siteVisit", entityId: visit,
            operationType: SiteVisitSyncOperation.stageOperationType,
            payload: try JSONEncoder().encode(SiteVisitSyncOperation.Payload(companyId: company, siteVisitId: visit, entityId: visit)),
            changedFields: ["stage"])
        operation.status = "failed"
        XCTAssertFalse(SiteVisitCommandRecoveryPolicy.mayAutomaticallyResume(operation, userId: actor, companyId: company))
    }

    private func makeOperation(includeSnapshot: Bool = true) throws -> SyncOperation {
        let snapshot = SiteVisitStageSnapshot(contractVersion: 1, capability: "site_visit_stage_command_v1",
            actorId: actor, companyId: company, opportunityId: lead, stage: "qualifying",
            stageRevision: "original-opaque-revision", stageEnteredAt: "2026-09-06T01:02:03.123456Z", canMove: true)
        let command = SiteVisitStageCommand(commandId: "55555555-5555-5555-5555-555555555555", companyId: company,
            actorId: actor, siteVisitId: visit, opportunityId: lead, targetStage: "quoting", snapshot: includeSnapshot ? snapshot : nil)
        return SyncOperation(entityType: "siteVisit", entityId: visit, operationType: SiteVisitSyncOperation.stageOperationType,
            payload: try JSONEncoder().encode(SiteVisitSyncOperation.Payload(companyId: company, siteVisitId: visit,
                entityId: visit, stageCommand: command)), changedFields: ["stage"])
    }
}
