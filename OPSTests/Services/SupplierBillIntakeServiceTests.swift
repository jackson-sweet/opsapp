import XCTest
@testable import OPS

final class SupplierBillIntakeServiceTests: XCTestCase {
    func testListDecodesCanproLifecycleWithoutInventingMissingDates() async throws {
        let service = SupplierBillIntakeService(
            baseURL: URL(string: "https://app.ops.test")!,
            tokenProvider: { "firebase-token" },
            requestSender: { request in
                let body = #"{"items":[{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","company_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","document_kind":"material","review_stage":"review","supplier_name":"DEKSMART","invoice_number":"43066","invoice_date":"2025-12-09","due_date":null,"currency":"CAD","total":"2378.46","payment_owner_id":null,"planned_payment_date":null,"hold_reason":null,"next_action":null,"revision":1,"created_at":"2026-09-04T07:00:00.000Z","updated_at":"2026-09-04T07:00:00.000Z","promoted_bill_id":null}]}"#
                return (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        let bills = try await service.list()

        XCTAssertEqual(bills.count, 1)
        XCTAssertEqual(bills[0].supplierName, "DEKSMART")
        XCTAssertEqual(bills[0].total, "2378.46")
        XCTAssertNil(bills[0].dueDate)
        XCTAssertEqual(bills[0].reviewStage, .review)
    }

    func testCaptureUsesStableIdentityForMultipartPrepareAndExactCommit() async throws {
        let log = SupplierBillRequestLog()
        let service = SupplierBillIntakeService(
            baseURL: URL(string: "https://app.ops.test")!,
            tokenProvider: { "firebase-token" },
            requestSender: { request in
                await log.append(request)
                let isCommit = request.url?.lastPathComponent == "commit"
                let body = isCommit
                    ? #"{"intake":{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","company_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","document_kind":"material","review_stage":"review","supplier_name":"DEKSMART","invoice_number":"43066","invoice_date":"2025-12-09","due_date":null,"currency":"CAD","total":"2378.46","payment_owner_id":null,"planned_payment_date":null,"hold_reason":null,"next_action":null,"revision":1,"created_at":"2026-09-04T07:00:00.000Z","updated_at":"2026-09-04T07:00:00.000Z","promoted_bill_id":null},"lines":[],"checks":[],"document":null,"events":[]}"#
                    : #"{"intentId":"intent-1","confirmationText":"CAPTURE 43066","expiresAt":"2026-09-04T07:10:00.000Z","status":"prepared","preview":{"requestId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}}"#
                return (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try Data("%PDF-1.7\ninvoice".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let job = QueuedSupplierBillCapture(
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            companyId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            documentKind: .material,
            originalFilename: "DeksMart-43066.pdf",
            storedFilename: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.pdf",
            sizeBytes: 16,
            queuedAt: Date(timeIntervalSince1970: 1_788_500_000)
        )

        let detail = try await service.capture(job: job, documentURL: file)

        XCTAssertEqual(detail.intake.id, job.id)
        let requests = await log.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer firebase-token")
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let multipart = String(decoding: try XCTUnwrap(requests[0].httpBody), as: UTF8.self)
        XCTAssertTrue(multipart.contains(job.id))
        XCTAssertTrue(multipart.contains("capture:\(job.id)"))
        XCTAssertTrue(multipart.contains("DeksMart-43066.pdf"))
        XCTAssertTrue(multipart.contains("application/pdf"))
        XCTAssertEqual(
            requests[1].url?.absoluteString,
            "https://app.ops.test/api/internal/accounting/supplier-bills/intakes/\(job.id)/commit"
        )
        let commit = String(decoding: try XCTUnwrap(requests[1].httpBody), as: UTF8.self)
        XCTAssertTrue(commit.contains("intent-1"))
        XCTAssertTrue(commit.contains("CAPTURE 43066"))
    }

    func testTemporaryServerFailureRemainsRetryable() async {
        let service = SupplierBillIntakeService(
            baseURL: URL(string: "https://app.ops.test")!,
            tokenProvider: { "firebase-token" },
            requestSender: { request in
                (
                    Data(#"{"error":"Supplier bill extraction is temporarily unavailable."}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        do {
            _ = try await service.list()
            XCTFail("Expected a retryable service failure")
        } catch {
            XCTAssertEqual(
                error as? SupplierBillIntakeServiceError,
                .unavailable("Supplier bill extraction is temporarily unavailable.")
            )
        }
    }
}

private actor SupplierBillRequestLog {
    private(set) var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }
}
