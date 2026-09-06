import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitStageDeliveryTests: XCTestCase {
    private let company = "11111111-1111-1111-1111-111111111111"
    private let actor = "22222222-2222-2222-2222-222222222222"
    private let visit = "33333333-3333-3333-3333-333333333333"
    private let lead = "44444444-4444-4444-4444-444444444444"

    func test_legacyPayloadDecodesWithNoStageCommand() throws {
        let data = Data("{\"company_id\":\"fixture\",\"site_visit_id\":\"visit\",\"entity_id\":\"visit\"}".utf8)
        let payload = try JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: data)
        XCTAssertNil(payload.stageCommand)
    }

    func test_replayKeepsCommandAndNeverMergesHistoricalStage() async throws {
        for outcome in ["already_applied", "already_satisfied"] {
            let command = makeCommand()
            let operation = try makeOperation(command)
            let schema = Schema([SyncOperation.self, Opportunity.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let context = container.mainContext
            let opportunity = Opportunity(id: lead, companyId: company, contactName: "Synthetic", stage: .negotiation)
            context.insert(opportunity); context.insert(operation); try context.save()
            var deliveries: [SiteVisitStageCommand] = []
            let executor = SiteVisitOutboundSync(repositoryFactory: { _ in
                XCTFail("Stage command must use its own typed transport")
                return SiteVisitRepository(companyId: "fixture", transport: RejectNetwork())
            }, sessionUserId: { self.actor }, deliverStage: { cmd in
                deliveries.append(cmd)
                return try self.result(command: cmd, outcome: outcome, transitionId: outcome == "already_satisfied" ? nil : "66666666-6666-6666-6666-666666666666")
            })
            let first = try await executor.executeIfHandled(operation: operation, context: context, activeCompanyId: company)
            let replay = try await executor.executeIfHandled(operation: operation, context: context, activeCompanyId: company)
            XCTAssertTrue(first)
            XCTAssertTrue(replay)
            XCTAssertEqual(deliveries, [command, command])
            XCTAssertEqual(opportunity.stage, .negotiation)
        }
    }

    func test_otherAccountCannotMakeEvenFirstDelivery() async throws {
        let command = makeCommand()
        let operation = try makeOperation(command)
        let schema = Schema([SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var sent = false
        let executor = SiteVisitOutboundSync(repositoryFactory: { _ in
            SiteVisitRepository(companyId: "fixture", transport: RejectNetwork())
        }, sessionUserId: { "different-operator" }, deliverStage: { cmd in
            sent = true
            return try self.result(command: cmd, outcome: "applied")
        })
        do {
            _ = try await executor.executeIfHandled(operation: operation, context: container.mainContext, activeCompanyId: company)
            XCTFail("Replacement identity must be rejected")
        } catch { XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .permanent) }
        XCTAssertFalse(sent)
    }

    func test_snapshotIsBoundToExactActorAndCompany() {
        let command = makeCommand()
        XCTAssertTrue(command.canDeliver)
        let switched = SiteVisitStageCommand(commandId: command.commandId, companyId: company, actorId: "other",
            siteVisitId: visit, opportunityId: lead, targetStage: "quoting", snapshot: command.snapshot)
        XCTAssertFalse(switched.canDeliver)
    }

    func test_missingSnapshotNeverSendsAndCannotAcquireRevisionDuringRetry() async throws {
        let old = makeCommand()
        let command = SiteVisitStageCommand(commandId: old.commandId, companyId: company, actorId: actor,
            siteVisitId: visit, opportunityId: lead, targetStage: "quoting", snapshot: nil)
        let operation = try makeOperation(command)
        let schema = Schema([SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var sends = 0
        let executor = SiteVisitOutboundSync(repositoryFactory: { _ in
            SiteVisitRepository(companyId: "fixture", transport: RejectNetwork())
        }, sessionUserId: { self.actor }, deliverStage: { cmd in
            sends += 1; return try self.result(command: cmd, outcome: "applied")
        })
        do {
            _ = try await executor.executeIfHandled(operation: operation, context: container.mainContext, activeCompanyId: company)
            XCTFail("No expected revision must retain recovery custody")
        } catch { XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .permanent) }
        XCTAssertEqual(sends, 0)
    }

    func test_conflictParksWhileNotReadyAndLockContentionRetryUnchangedCommand() throws {
        let command = makeCommand()
        do { try result(command: command, outcome: "conflict").validate(for: command); XCTFail() }
        catch { XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .permanent) }
        do { try result(command: command, outcome: "not_ready").validate(for: command); XCTFail() }
        catch { XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .transient) }
        for code in ["55P03", "40P01", "40001"] { XCTAssertTrue(SiteVisitStageTransport.isRetryableSQLCode(code)) }
        XCTAssertFalse(SiteVisitStageTransport.isRetryableSQLCode("42501"))
    }

    func test_alreadySatisfiedRequiresTruthfulNoTransitionReceipt() throws {
        let command = makeCommand()
        try result(command: command, outcome: "already_satisfied", transitionId: nil).validate(for: command)
        XCTAssertThrowsError(try result(command: command, outcome: "already_satisfied").validate(for: command))
    }

    func test_completionAutoAdvanceConflictDoesNotRebaseExpectedRevision() throws {
        let original = makeCommand()
        let snapshot = SiteVisitStageSnapshot(contractVersion: 1, capability: "site_visit_stage_command_v1",
            actorId: actor, companyId: company, opportunityId: lead, stage: "new_lead",
            stageRevision: "before-completion", stageEnteredAt: "2026-09-06T01:02:03.123456Z", canMove: true)
        let command = SiteVisitStageCommand(commandId: original.commandId, companyId: company, actorId: actor,
            siteVisitId: visit, opportunityId: lead, targetStage: "qualifying", snapshot: snapshot)
        do { try result(command: command, outcome: "conflict").validate(for: command); XCTFail() }
        catch { XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .permanent) }
        XCTAssertEqual(command.snapshot?.stage, "new_lead")
        XCTAssertEqual(command.snapshot?.stageRevision, "before-completion")
    }

    func test_stageCommandSurvivesCRUDCoalescingAsItsOwnLane() throws {
        let command = makeCommand()
        let stage = try makeOperation(command)
        let parent = SyncOperation(entityType: SyncEntityType.siteVisit.rawValue, entityId: visit,
            operationType: "update", payload: Data(), changedFields: ["notes"])
        let result = SiteVisitOutboundSync.coalesceOperations([parent, stage])
        XCTAssertEqual(Set(result.map(\.id)), [parent.id, stage.id])
    }

    private func makeCommand() -> SiteVisitStageCommand {
        let snapshot = SiteVisitStageSnapshot(contractVersion: 1, capability: "site_visit_stage_command_v1", actorId: actor,
            companyId: company, opportunityId: lead, stage: "qualifying", stageRevision: "exact-opaque-revision",
            stageEnteredAt: "2026-09-06T01:02:03.123456Z", canMove: true)
        return SiteVisitStageCommand(commandId: "55555555-5555-5555-5555-555555555555", companyId: company, actorId: actor,
            siteVisitId: visit, opportunityId: lead, targetStage: "quoting", snapshot: snapshot)
    }
    private func makeOperation(_ command: SiteVisitStageCommand) throws -> SyncOperation {
        SyncOperation(entityType: SyncEntityType.siteVisit.rawValue, entityId: visit,
            operationType: SiteVisitSyncOperation.stageOperationType,
            payload: try JSONEncoder().encode(SiteVisitSyncOperation.Payload(companyId: company, siteVisitId: visit,
                entityId: visit, stageCommand: command)), changedFields: ["stage"])
    }
    private func result(command: SiteVisitStageCommand, outcome: String,
                        transitionId: String? = "66666666-6666-6666-6666-666666666666") throws -> SiteVisitStageCommandResult {
        let object: [String: Any] = ["contract_version": 1, "command_id": command.commandId, "outcome": outcome,
            "receipt": ["opportunity_id": lead, "stage": command.targetStage, "stage_revision": "later-opaque-revision",
                "stage_entered_at": "2026-09-06T01:02:03.123456Z", "transition_id": transitionId as Any? ?? NSNull(),
                "recorded_at": "2026-09-06T01:02:03.123456Z"]]
        return try JSONDecoder().decode(SiteVisitStageCommandResult.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

private final class RejectNetwork: SiteVisitRemoteTransport {
    func send(_ request: SiteVisitRemoteRequest) async throws -> Data {
        XCTFail("This test must not send a repository request")
        throw URLError(.unsupportedURL)
    }
}
