import SwiftData
import Supabase
import XCTest
@testable import OPS

@MainActor
final class SyncBugReportingIntegrationTests: XCTestCase {
    func testActorAndFallbackReportSameRLSFingerprintAndKeepParkedCustody() async throws {
        let error = PostgrestError(detail: "private payload", hint: nil, code: "42501", message: "private row rejected")
        var reports: [SyncBugReporter.Report] = []
        for actorPath in [false, true] {
            let capture = SyncBugReportCapture()
            let container = try makeContainer()
            let operation = try makeOperation(in: container.mainContext)
            let payload = operation.payload
            try await execute(actorPath: actorPath, container: container, operation: operation, capture: capture, error: error)
            let row = try freshOperation(container)
            XCTAssertEqual(row.status, "parked")
            XCTAssertEqual(row.retryCount, 0)
            XCTAssertEqual(row.payload, payload)
            XCTAssertNil(row.completedAt)
            XCTAssertEqual(capture.reports.count, 1)
            reports.append(try XCTUnwrap(capture.reports.first))
        }
        XCTAssertEqual(reports.first, reports.last, "Changing sync engines must not create another logical bug")
        XCTAssertEqual(reports.first?.screen, "Sync.client.update")
        XCTAssertEqual(reports.first?.errorCode, "PG_42501")
    }

    func testAcceptedDuplicateCreateNeverFilesBugOnEitherPath() async throws {
        let error = PostgrestError(detail: nil, hint: nil, code: "23505", message: "duplicate key value violates unique constraint \"clients_pkey\"")
        for actorPath in [false, true] {
            let capture = SyncBugReportCapture()
            let container = try makeContainer()
            let operation = try makeOperation(in: container.mainContext, operationType: "create")
            try await execute(actorPath: actorPath, container: container, operation: operation, capture: capture, error: error, succeeds: true)
            XCTAssertEqual(try freshOperation(container).status, "completed")
            XCTAssertTrue(capture.reports.isEmpty)
        }
    }

    func testTransientFailureKeepsRetryBehaviorWithoutReportOnEitherPath() async throws {
        for actorPath in [false, true] {
            let capture = SyncBugReportCapture()
            let container = try makeContainer()
            let operation = try makeOperation(in: container.mainContext)
            try await execute(actorPath: actorPath, container: container, operation: operation, capture: capture, error: URLError(.notConnectedToInternet))
            let row = try freshOperation(container)
            XCTAssertEqual(row.status, "pending")
            XCTAssertEqual(row.retryCount, 1)
            XCTAssertTrue(capture.reports.isEmpty)
        }
    }

    func testFirebaseAccountSwitchDropsLateRejectionOnEitherPath() async throws {
        let error = PostgrestError(detail: nil, hint: nil, code: "42501", message: "private row rejected")
        for actorPath in [false, true] {
            let capture = SyncBugReportCapture()
            let container = try makeContainer()
            let operation = try makeOperation(in: container.mainContext)
            try await execute(actorPath: actorPath, container: container, operation: operation, capture: capture, error: error, replaceAccount: true)
            XCTAssertTrue(capture.reports.isEmpty, "An old account's rejection must never be sent under its replacement")
        }
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: SyncOperation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func makeOperation(in context: ModelContext, operationType: String = "update") throws -> SyncOperation {
        let operation = SyncOperation(entityType: "client", entityId: UUID().uuidString.lowercased(), operationType: operationType, payload: Data("{\"name\":\"private customer\"}".utf8), changedFields: ["name"])
        context.insert(operation)
        try context.save()
        return operation
    }

    private struct OperationSnapshot {
        let status: String
        let retryCount: Int
        let payload: Data
        let completedAt: Date?
    }

    private func freshOperation(_ container: ModelContainer) throws -> OperationSnapshot {
        let context = ModelContext(container)
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first)
        return OperationSnapshot(status: row.status, retryCount: row.retryCount,
            payload: row.payload, completedAt: row.completedAt)
    }

    private func execute(actorPath: Bool, container: ModelContainer, operation: SyncOperation, capture: SyncBugReportCapture, error: Error, succeeds: Bool = false, replaceAccount: Bool = false) async throws {
        let push: (String, String, String, [String: Any]) async throws -> Void = { _, _, _, _ in
            if replaceAccount {
                let original = capture.identity
                capture.identity = .init(companyID: original.companyID, userID: original.userID, firebaseUserID: "replacement-Firebase")
            }
            throw error
        }
        if actorPath {
            let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
            await actor.setSyncBugReporterForTesting(capture.reporter)
            await actor.setOutboundPushForTesting(push)
            _ = await actor.processPendingOperations()
        } else {
            let processor = OutboundProcessor(repositoryPush: push, bugReporter: capture.reporter)
            do {
                try await processor.executeOperation(operation, context: container.mainContext)
                XCTAssertTrue(succeeds, "An automatic report must not swallow the sync failure")
            } catch let actual {
                XCTAssertFalse(succeeds, "An accepted duplicate create remains a success")
                if let expected = error as? PostgrestError {
                    XCTAssertEqual((actual as? PostgrestError)?.code, expected.code)
                } else {
                    XCTAssertEqual((actual as NSError).code, (error as NSError).code)
                }
            }
            try container.mainContext.save()
        }
    }
}
