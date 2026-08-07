import XCTest
import Supabase
@testable import OPS

final class SiteVisitRepositoryTests: XCTestCase {
    private let visitId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let companyId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let userId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

    func testFetchAllScopesEveryTableToCompanyAndDeltaCursor() async throws {
        let transport = RecordingSiteVisitTransport()
        transport.response = Data("[]".utf8)
        let repository = SiteVisitRepository(companyId: companyId, transport: transport)
        let since = Date(timeIntervalSince1970: 42)

        let bundle = try await repository.fetchAll(since: since)

        XCTAssertTrue(bundle.visits.isEmpty)
        XCTAssertEqual(transport.requests.count, 4)
        XCTAssertEqual(Set(transport.requests.compactMap(\.table)), Set(SiteVisitRemoteTable.allCases))
        for request in transport.requests {
            guard case let .fetch(_, scopedCompanyId, requestSince, siteVisitId) = request else {
                return XCTFail("Expected only fetch requests, got \(request)")
            }
            XCTAssertEqual(scopedCompanyId, companyId)
            XCTAssertEqual(requestSince, since)
            XCTAssertNil(siteVisitId)
        }
    }

    func testFetchBundleScopesParentAndChildrenToCompanyAndVisit() async throws {
        let transport = RecordingSiteVisitTransport()
        transport.responseProvider = { request in
            guard case let .fetch(table, _, _, _) = request else { return Data() }
            if table == .visits {
                return Self.parentArrayJSON(
                    visitId: self.visitId,
                    companyId: self.companyId,
                    userId: self.userId
                )
            }
            return Data("[]".utf8)
        }
        let repository = SiteVisitRepository(companyId: companyId, transport: transport)

        let bundle = try await repository.fetchBundle(siteVisitId: visitId.uppercased())

        XCTAssertEqual(bundle.visit.id, visitId)
        XCTAssertEqual(transport.requests.count, 4)
        for request in transport.requests {
            guard case let .fetch(_, scopedCompanyId, since, scopedVisitId) = request else {
                return XCTFail("Expected only fetch requests")
            }
            XCTAssertEqual(scopedCompanyId, companyId)
            XCTAssertNil(since)
            XCTAssertEqual(scopedVisitId, visitId)
        }
    }

    func testSoftDeleteIsCompanyScopedAndNeverUsesHardDelete() async throws {
        let transport = RecordingSiteVisitTransport()
        let repository = SiteVisitRepository(companyId: companyId, transport: transport)
        let deletedAt = Date(timeIntervalSince1970: 100)

        try await repository.softDelete(.artifacts, id: visitId.uppercased(), at: deletedAt)

        XCTAssertEqual(
            transport.requests,
            [.softDelete(table: .artifacts, id: visitId, companyId: companyId, deletedAt: deletedAt)]
        )
    }

    func testCompletionUsesGuardedRPCRequestInsteadOfTableUpdate() async throws {
        let transport = RecordingSiteVisitTransport()
        transport.response = Self.completionJSON(
            visitId: visitId,
            companyId: companyId,
            userId: userId
        )
        let repository = SiteVisitRepository(companyId: companyId, transport: transport)

        let result = try await repository.completeSiteVisit(
            visitId,
            completion: SiteVisitCompletionPayload(notes: "Scope complete", photos: [])
        )

        XCTAssertEqual(result.visit.status, .completed)
        XCTAssertEqual(transport.requests.count, 1)
        guard case let .complete(id, scopedCompanyId, payload) = transport.requests[0] else {
            return XCTFail("Completion must use the guarded RPC request")
        }
        XCTAssertEqual(id, visitId)
        XCTAssertEqual(scopedCompanyId, companyId)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(object["notes"] as? String, "Scope complete")
    }

    func testPayloadFromAnotherCompanyIsRejectedBeforeTransport() async throws {
        let transport = RecordingSiteVisitTransport()
        let repository = SiteVisitRepository(companyId: companyId, transport: transport)
        let visit = SiteVisit(
            id: visitId,
            companyId: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
            status: .inProgress,
            scheduledAt: Date(),
            createdBy: userId
        )
        let payload = try CreateSiteVisitDTO(model: visit)

        do {
            _ = try await repository.upsertVisit(payload)
            XCTFail("Expected a tenant mismatch")
        } catch let error as SiteVisitRepositoryError {
            guard case .companyMismatch = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testStructuredServerErrorsRetainAuthPermanentAndTransportDisposition() {
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitRepositoryError.server(
                    code: "42501",
                    message: "RLS denied",
                    detail: nil,
                    hint: nil
                )
            ),
            .auth
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitRepositoryError.server(
                    code: "23503",
                    message: "FK missing",
                    detail: nil,
                    hint: nil
                )
            ),
            .permanent
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitRepositoryError.server(
                    code: "PGRST202",
                    message: "RPC missing",
                    detail: nil,
                    hint: nil
                )
            ),
            .permanent
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitRepositoryError.server(
                    code: nil,
                    message: "connection lost",
                    detail: nil,
                    hint: nil
                )
            ),
            .transient
        )
    }

    func testPostgrestFailurePreservesCodeMessageDetailAndHintForQueuePolicy() async throws {
        let transport = RecordingSiteVisitTransport()
        transport.responseProvider = { _ in
            throw PostgrestError(
                detail: "Key (site_visit_id, field_id) already exists.",
                hint: "Reconcile the canonical server answer before retrying.",
                code: "23505",
                message: "duplicate key value violates unique constraint \"site_visit_checklist_answers_active_field_uidx\""
            )
        }
        let repository = SiteVisitRepository(companyId: companyId, transport: transport)

        do {
            _ = try await repository.fetchAll()
            XCTFail("Expected the structured PostgREST failure")
        } catch let error as SiteVisitRepositoryError {
            guard case let .server(code, message, detail, hint) = error else {
                return XCTFail("Expected structured server context, got \(error)")
            }
            XCTAssertEqual(code, "23505")
            XCTAssertEqual(
                message,
                "duplicate key value violates unique constraint \"site_visit_checklist_answers_active_field_uidx\""
            )
            XCTAssertEqual(detail, "Key (site_visit_id, field_id) already exists.")
            XCTAssertEqual(hint, "Reconcile the canonical server answer before retrying.")
            XCTAssertTrue(error.localizedDescription.contains("23505"))
            XCTAssertTrue(error.localizedDescription.contains("duplicate key value"))
            XCTAssertTrue(error.localizedDescription.contains("Key (site_visit_id, field_id) already exists."))
            XCTAssertTrue(error.localizedDescription.contains("Reconcile the canonical server answer"))
            XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .permanent)
            XCTAssertFalse(
                errorIndicatesPrimaryKeyViolation(error),
                "The logical active-field unique index is not an idempotent primary-key retry"
            )
        } catch {
            XCTFail("Expected SiteVisitRepositoryError, got \(error)")
        }
    }

    func testWrappedPostgrestPrimaryKeyViolationRemainsAnIdempotentCreateRetry() {
        let error = SiteVisitRepositoryError.wrapping(
            PostgrestError(
                detail: "Key (id) already exists.",
                hint: nil,
                code: "23505",
                message: "duplicate key value violates unique constraint \"site_visit_checklist_answers_pkey\""
            )
        )

        XCTAssertTrue(errorIndicatesPrimaryKeyViolation(error))
        XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .permanent)
    }

    private static func parentArrayJSON(visitId: String, companyId: String, userId: String) -> Data {
        Data("""
        [{
          "id":"\(visitId)",
          "company_id":"\(companyId)",
          "scheduled_at":"2026-07-31T18:12:45Z",
          "status":"in_progress",
          "created_by":"\(userId)"
        }]
        """.utf8)
    }

    private static func completionJSON(visitId: String, companyId: String, userId: String) -> Data {
        Data("""
        {
          "visit": {
            "id":"\(visitId)",
            "company_id":"\(companyId)",
            "scheduled_at":"2026-07-31T18:12:45Z",
            "status":"completed",
            "completed_at":"2026-07-31T19:12:45Z",
            "created_by":"\(userId)"
          },
          "activity_id": null
        }
        """.utf8)
    }
}

private final class RecordingSiteVisitTransport: SiteVisitRemoteTransport {
    var requests: [SiteVisitRemoteRequest] = []
    var response = Data()
    var responseProvider: ((SiteVisitRemoteRequest) throws -> Data)?

    func send(_ request: SiteVisitRemoteRequest) async throws -> Data {
        requests.append(request)
        return try responseProvider?(request) ?? response
    }
}

private extension SiteVisitRemoteRequest {
    var table: SiteVisitRemoteTable? {
        switch self {
        case .fetch(let table, _, _, _),
             .upsert(let table, _, _),
             .update(let table, _, _, _),
             .softDelete(let table, _, _, _):
            return table
        case .complete:
            return nil
        }
    }
}
