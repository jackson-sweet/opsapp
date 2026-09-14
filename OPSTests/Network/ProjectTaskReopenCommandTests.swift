import Foundation
import Supabase
import XCTest
@testable import OPS

final class ProjectTaskReopenCommandTests: XCTestCase {
    private let company = "10000000-0000-4000-8000-000000000001"
    private let project = "30000000-0000-4000-8000-000000000001"
    private let command = "40000000-0000-4000-8000-000000000001"
    private let revision = "2026-09-14T12:00:00.123456+00:00"

    func test_rpcPreservesExactRevisionAndNeverSendsQueueMetadataAsTableFields() throws {
        let request = try makeRequest()
        XCTAssertEqual(request.rpcParameters, [
            "p_command_id": .string(command),
            "p_project_id": .string(project),
            "p_expected_updated_at": .string("2026-09-14T12:00:00.123456+00:00"),
            "p_target_status": .string("accepted")
        ])
    }

    func test_payloadMustMatchRepositoryCompany() {
        var fields = payload()
        fields["company_id"] = .string("10000000-0000-4000-8000-000000000002")
        XCTAssertThrowsError(try ProjectTaskReopenCommand(
            projectId: project, companyId: company, fields: fields
        )) { XCTAssertEqual($0 as? ProjectTaskReopenError, .companyMismatch) }
    }

    func test_malformedMissingAndUnrelatedCommandFieldsFailClosed() {
        let invalid: [[String: AnyJSON]] = [
            payload().filter { $0.key != "_reopen_command_id" },
            payload().merging(["_expected_updated_at": .string("not-a-revision")]) { _, rhs in rhs },
            payload().merging(["status": .string("completed")]) { _, rhs in rhs },
            payload().merging(["_reopen_command_id": .string("legacy-id")]) { _, rhs in rhs },
            payload().merging(["deleted_at": .null]) { _, rhs in rhs }
        ]
        for fields in invalid {
            XCTAssertThrowsError(try ProjectTaskReopenCommand(
                projectId: project, companyId: company, fields: fields
            ))
        }
    }

    func test_validReceiptProvesExactOriginalCommand() throws {
        let receipt = try makeRequest().validateReceipt(receiptData())
        XCTAssertEqual(receipt.commandId, command)
        XCTAssertEqual(receipt.projectId, project)
        XCTAssertEqual(receipt.companyId, company)
        XCTAssertEqual(receipt.status, "accepted")
        XCTAssertEqual(receipt.updatedAt, "2026-09-14T14:00:00.654321+00:00")
        XCTAssertTrue(receipt.changed)
        XCTAssertFalse(receipt.replayed)
    }

    func test_responseLossReplayIsAcceptedAsHistoricalReceipt() throws {
        let request = try makeRequest()
        let first = try request.validateReceipt(receiptData())
        let replay = try request.validateReceipt(receiptData(overrides: ["replayed": true]))
        XCTAssertEqual(replay.updatedAt, first.updatedAt)
        XCTAssertEqual(replay.status, first.status)
        XCTAssertTrue(replay.replayed)
    }

    func test_foreignMismatchedAndUncommittedReceiptsCannotReleaseDependentTask() throws {
        let request = try makeRequest()
        let cases: [[String: Any]] = [
            ["command_id": "40000000-0000-4000-8000-000000000002"],
            ["project_id": "30000000-0000-4000-8000-000000000002"],
            ["company_id": "10000000-0000-4000-8000-000000000002"],
            ["status": "in_progress"], ["changed": false], ["updated_at": "not-a-date"]
        ]
        for overrides in cases {
            XCTAssertThrowsError(try request.validateReceipt(receiptData(overrides: overrides))) {
                XCTAssertEqual($0 as? ProjectTaskReopenError, .invalidReceipt)
            }
        }
    }

    func test_emptyMalformedAndPartialResponsesCannotRetireCommand() throws {
        let request = try makeRequest()
        for response in ["", "[]", "{}", "{\"changed\":true}", "null", "<html>retry</html>"] {
            XCTAssertThrowsError(try request.validateReceipt(Data(response.utf8))) {
                XCTAssertEqual($0 as? ProjectTaskReopenError, .invalidReceipt)
            }
        }
    }

    private func makeRequest() throws -> ProjectTaskReopenCommand {
        try ProjectTaskReopenCommand(projectId: project, companyId: company, fields: payload())
    }

    private func payload() -> [String: AnyJSON] {
        ["status": .string("accepted"), "_reopen_command_id": .string(command),
         "_expected_updated_at": .string(revision), "company_id": .string(company)]
    }

    private func receiptData(overrides: [String: Any] = [:]) throws -> Data {
        var value: [String: Any] = [
            "command_id": command, "project_id": project, "company_id": company,
            "status": "accepted", "updated_at": "2026-09-14T14:00:00.654321+00:00",
            "changed": true, "replayed": false
        ]
        value.merge(overrides) { _, rhs in rhs }
        return try JSONSerialization.data(withJSONObject: value)
    }
}
