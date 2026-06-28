import XCTest
@testable import OPSDecks

final class DecksProvisioningPayloadTests: XCTestCase {
    func testProvisioningPayloadUsesDeckOnlySourceAndDoesNotContainOPSSubscriptionState() throws {
        let request = DecksCompanyProvisioningRequest(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: "Deck Operator"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"source_app\":\"ops_decks\""))
        XCTAssertFalse(json.contains("subscription_status"))
        XCTAssertFalse(json.contains("trial_end_date"))
    }

    func testProvisioningResponseDecodesDeckOnlyCompanyIdentity() throws {
        let json = """
        {
          "company_id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "role": "admin",
          "subscription_plan": "decks"
        }
        """

        let response = try JSONDecoder().decode(
            DecksCompanyProvisioningResponse.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(response.companyId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(response.userId, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(response.role, "admin")
        XCTAssertEqual(response.subscriptionPlan, "decks")
    }

    func testProvisioningServiceDelegatesRequestAndDecodesResponse() async throws {
        let request = DecksCompanyProvisioningRequest(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: "Deck Operator"
        )
        let transport = RecordingDecksCompanyProvisioningTransport(
            data: Data("""
            {
              "company_id": "company-123",
              "user_id": "user-123",
              "role": "admin",
              "subscription_plan": "decks"
            }
            """.utf8)
        )
        let service = DecksCompanyProvisioningService(transport: transport)

        let response = try await service.provisionCompany(request)

        XCTAssertEqual(transport.requests, [request])
        XCTAssertEqual(
            response,
            DecksCompanyProvisioningResponse(
                companyId: "company-123",
                userId: "user-123",
                role: "admin",
                subscriptionPlan: "decks"
            )
        )
    }

    func testURLSessionTransportPostsDeckProvisioningRequestWithBearerToken() async throws {
        let endpointURL = try XCTUnwrap(
            URL(string: "https://app.opsapp.co/api/decks/provision-company")
        )
        let dataLoader = RecordingProvisioningDataLoader(
            data: Data("{\"ok\":true}".utf8),
            statusCode: 201
        )
        let transport = DecksCompanyProvisioningURLSessionTransport(
            endpointURL: endpointURL,
            accessTokenProvider: { "firebase-token-123" },
            dataLoader: dataLoader
        )
        let request = DecksCompanyProvisioningRequest(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: nil
        )

        let data = try await transport.provisionCompany(request)

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
        XCTAssertTrue(json.contains("\"source_app\":\"ops_decks\""))
        XCTAssertFalse(json.contains("subscription_status"))
    }

    func testURLSessionTransportThrowsOnNonSuccessStatus() async throws {
        let endpointURL = try XCTUnwrap(
            URL(string: "https://app.opsapp.co/api/decks/provision-company")
        )
        let dataLoader = RecordingProvisioningDataLoader(
            data: Data("{\"error\":\"forbidden\"}".utf8),
            statusCode: 403
        )
        let transport = DecksCompanyProvisioningURLSessionTransport(
            endpointURL: endpointURL,
            accessTokenProvider: { "firebase-token-123" },
            dataLoader: dataLoader
        )

        do {
            _ = try await transport.provisionCompany(
                DecksCompanyProvisioningRequest(
                    firebaseUID: "firebase-123",
                    email: "deck@example.com",
                    displayName: nil
                )
            )
            XCTFail("Expected provisioning transport to throw.")
        } catch let error as DecksCompanyProvisioningTransportError {
            XCTAssertEqual(error, .httpStatus(403))
        }
    }
}

private final class RecordingDecksCompanyProvisioningTransport: DecksCompanyProvisioningTransport {
    private let data: Data
    private(set) var requests: [DecksCompanyProvisioningRequest] = []

    init(data: Data) {
        self.data = data
    }

    func provisionCompany(_ request: DecksCompanyProvisioningRequest) async throws -> Data {
        requests.append(request)
        return data
    }
}

private final class RecordingProvisioningDataLoader: URLSessionDataLoading {
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
