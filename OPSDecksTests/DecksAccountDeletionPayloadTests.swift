import XCTest
@testable import OPSDecks

final class DecksAccountDeletionPayloadTests: XCTestCase {
    func testDeletionPayloadContainsFirebaseAndCompanyOnly() throws {
        let request = DecksAccountDeletionRequest(
            firebaseUID: "firebase-123",
            companyId: "company-123"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"firebase_uid\":\"firebase-123\""))
        XCTAssertTrue(json.contains("\"company_id\":\"company-123\""))
        XCTAssertFalse(json.contains("subscription_status"))
        XCTAssertFalse(json.contains("trial_end_date"))
    }

    func testDeletionReceiptDecodesReceiptAndTimestamp() throws {
        let json = """
        {
          "receipt_id": "deletion-123",
          "deleted_at": "2026-06-26T16:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let receipt = try decoder.decode(
            DecksAccountDeletionReceipt.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )
        let expectedDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-06-26T16:00:00Z")
        )

        XCTAssertEqual(receipt.receiptId, "deletion-123")
        XCTAssertEqual(receipt.deletedAt, expectedDate)
    }

    func testDeletionServiceDelegatesRequestAndDecodesReceipt() async throws {
        let request = DecksAccountDeletionRequest(
            firebaseUID: "firebase-123",
            companyId: "company-123"
        )
        let transport = RecordingDecksAccountDeletionTransport(
            data: Data("""
            {
              "receipt_id": "deletion-123",
              "deleted_at": "2026-06-26T16:00:00Z"
            }
            """.utf8)
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let service = DecksAccountDeletionService(
            transport: transport,
            decoder: decoder
        )

        let receipt = try await service.deleteAccount(request)

        XCTAssertEqual(transport.requests, [request])
        XCTAssertEqual(receipt.receiptId, "deletion-123")
        XCTAssertEqual(
            receipt.deletedAt,
            try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-26T16:00:00Z"))
        )
    }

    func testDeletionServiceUsesISO8601ReceiptDecoderByDefault() async throws {
        let transport = RecordingDecksAccountDeletionTransport(
            data: Data("""
            {
              "receipt_id": "deletion-123",
              "deleted_at": "2026-06-26T16:00:00Z"
            }
            """.utf8)
        )
        let service = DecksAccountDeletionService(transport: transport)

        let receipt = try await service.deleteAccount(
            DecksAccountDeletionRequest(
                firebaseUID: "firebase-123",
                companyId: "company-123"
            )
        )

        XCTAssertEqual(receipt.receiptId, "deletion-123")
        XCTAssertEqual(
            receipt.deletedAt,
            try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-26T16:00:00Z"))
        )
    }

    func testURLSessionTransportPostsDeletionRequestWithBearerToken() async throws {
        let endpointURL = try XCTUnwrap(
            URL(string: "https://app.opsapp.co/api/decks/delete-account")
        )
        let dataLoader = RecordingDeletionDataLoader(
            data: Data("{\"ok\":true}".utf8),
            statusCode: 202
        )
        let transport = DecksAccountDeletionURLSessionTransport(
            endpointURL: endpointURL,
            accessTokenProvider: { "firebase-token-123" },
            dataLoader: dataLoader
        )
        let request = DecksAccountDeletionRequest(
            firebaseUID: "firebase-123",
            companyId: "company-123"
        )

        let data = try await transport.deleteAccount(request)

        let urlRequest = try XCTUnwrap(dataLoader.requests.first)
        let body = try XCTUnwrap(urlRequest.httpBody)
        let json = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertEqual(data, Data("{\"ok\":true}".utf8))
        XCTAssertEqual(urlRequest.url, endpointURL)
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer firebase-token-123")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(json.contains("\"firebase_uid\":\"firebase-123\""))
        XCTAssertTrue(json.contains("\"company_id\":\"company-123\""))
        XCTAssertFalse(json.contains("subscription_status"))
    }

    func testURLSessionTransportThrowsOnNonSuccessStatus() async throws {
        let endpointURL = try XCTUnwrap(
            URL(string: "https://app.opsapp.co/api/decks/delete-account")
        )
        let dataLoader = RecordingDeletionDataLoader(
            data: Data("{\"error\":\"forbidden\"}".utf8),
            statusCode: 403
        )
        let transport = DecksAccountDeletionURLSessionTransport(
            endpointURL: endpointURL,
            accessTokenProvider: { "firebase-token-123" },
            dataLoader: dataLoader
        )

        do {
            _ = try await transport.deleteAccount(
                DecksAccountDeletionRequest(
                    firebaseUID: "firebase-123",
                    companyId: "company-123"
                )
            )
            XCTFail("Expected deletion transport to throw.")
        } catch let error as DecksAccountDeletionTransportError {
            XCTAssertEqual(error, .httpStatus(403))
        }
    }
}

private final class RecordingDecksAccountDeletionTransport: DecksAccountDeletionTransport {
    private let data: Data
    private(set) var requests: [DecksAccountDeletionRequest] = []

    init(data: Data) {
        self.data = data
    }

    func deleteAccount(_ request: DecksAccountDeletionRequest) async throws -> Data {
        requests.append(request)
        return data
    }
}

private final class RecordingDeletionDataLoader: URLSessionDataLoading {
    private let data: Data
    private let statusCode: Int
    private(set) var requests: [URLRequest] = []

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )
        )
        return (data, response)
    }
}
