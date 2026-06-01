//
//  CatalogSetupCommitServiceTests.swift
//  OPSTests
//
//  TDD coverage for CatalogSetupCommitService:
//  - post-ok reconcile errors are treated as .resynced (not re-thrown)
//  - ok server response → .committed
//  - rejected server response → .rejected(message:)
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class CatalogSetupCommitServiceTests: XCTestCase {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: OPSSchemaV8.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    func test_reconcile_missingMapping_afterOkResponse_returnsResynced_notFailure() throws {
        var didRequestResync = false
        let service = CatalogSetupCommitService(
            companyId: "c1",
            modelContext: try makeInMemoryContext(),
            requestCatalogResync: { didRequestResync = true }
        )
        // minimalTestPayload has family.id == nil and clientId "family:<draftId>"
        let payload = CatalogSetupSavePayload.minimalTestPayload(draftId: "draft-1", familyName: "Vinyl")
        // ok response with an EMPTY idMap -> reconcileSuccessfulSave throws .missingServerId on the family
        let response = CatalogSetupSaveResponse(ok: true, idMap: [:])

        let result = service.reconcile(payload: payload, response: response)

        guard case .resynced = result else {
            return XCTFail("Expected .resynced after a post-ok mapping failure, got \(result)")
        }
        XCTAssertTrue(didRequestResync, "A catalog resync must be requested when local reconcile fails after an ok server commit")
    }

    func test_commit_okResponse_returnsCommitted() async throws {
        let response = CatalogSetupSaveResponse(ok: true, idMap: ["family:draft-1": "server-fam-1"])
        let service = CatalogSetupCommitService(
            companyId: "c1",
            modelContext: try makeInMemoryContext(),
            performSave: { _, _ in response }
        )
        let payload = CatalogSetupSavePayload.minimalTestPayload(draftId: "draft-1", familyName: "Vinyl")
        let attempt = try CatalogSetupSaveAttempt.resolve(payload: payload, existingAttempt: nil)
        let outcome = try await service.commit(payload: payload, saveAttempt: attempt)
        guard case .committed = outcome else { return XCTFail("Expected .committed, got \(outcome)") }
    }

    func test_commit_rejectedResponse_returnsRejectedWithMessage() async throws {
        let response = CatalogSetupSaveResponse(ok: false, blockers: [CatalogSetupSaveIssue(code: "x", path: "family", message: "Nope")])
        let service = CatalogSetupCommitService(
            companyId: "c1",
            modelContext: try makeInMemoryContext(),
            performSave: { _, _ in response }
        )
        let payload = CatalogSetupSavePayload.minimalTestPayload(draftId: "draft-1", familyName: "Vinyl")
        let attempt = try CatalogSetupSaveAttempt.resolve(payload: payload, existingAttempt: nil)
        let outcome = try await service.commit(payload: payload, saveAttempt: attempt)
        guard case .rejected(let message) = outcome else { return XCTFail("Expected .rejected, got \(outcome)") }
        XCTAssertEqual(message, "Nope")
    }
}
