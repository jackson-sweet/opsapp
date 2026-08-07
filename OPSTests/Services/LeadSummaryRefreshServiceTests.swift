import XCTest
@testable import OPS

final class LeadSummaryRefreshServiceTests: XCTestCase {
    func testRequestUsesAuthenticatedOpportunityEndpoint() async throws {
        let opportunityId = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        let captured = RequestCapture()
        let service = LeadSummaryRefreshService(
            baseURL: URL(string: "https://app.ops.test")!,
            tokenProvider: { "firebase-token" },
            requestSender: { request in
                await captured.store(request)
                return (
                    Data(),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 202,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        await service.requestRefresh(opportunityId: opportunityId)

        let request = await captured.value
        XCTAssertEqual(
            request?.url?.absoluteString,
            "https://app.ops.test/api/opportunities/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/summary-refresh"
        )
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(
            request?.value(forHTTPHeaderField: "Authorization"),
            "Bearer firebase-token"
        )
    }

    func testInvalidOpportunityDoesNotAcquireTokenOrSendRequest() async {
        let tokenCalls = Counter()
        let requestCalls = Counter()
        let service = LeadSummaryRefreshService(
            baseURL: URL(string: "https://app.ops.test")!,
            tokenProvider: {
                await tokenCalls.increment()
                return "firebase-token"
            },
            requestSender: { request in
                await requestCalls.increment()
                return (Data(), URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
            }
        )

        await service.requestRefresh(opportunityId: "not-a-uuid")

        let acquiredTokenCount = await tokenCalls.value
        let sentRequestCount = await requestCalls.value
        XCTAssertEqual(acquiredTokenCount, 0)
        XCTAssertEqual(sentRequestCount, 0)
    }
}

private actor RequestCapture {
    private(set) var value: URLRequest?

    func store(_ request: URLRequest) {
        value = request
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
