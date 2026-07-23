//
//  SharePhotoEndpointRequestTests.swift
//  OPSTests
//
//  The extension's instant path and the app's durable fallback must address the
//  same endpoint with the same stable job identity. That is what makes a race
//  between the two paths idempotent instead of creating two project photos.
//

import XCTest
@testable import OPS

final class SharePhotoEndpointRequestTests: XCTestCase {

    func testInstantAndFallbackRequestsUseTheSameStableIdentity() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://app.opsapp.co"))
        let projectId = "B7EB718E-357D-45F9-A19D-68B2350F6544"
        let jobId = "2C20ED29-F328-49CB-A5DB-A45D83FB5938"
        let takenAt = Date(timeIntervalSince1970: 1_785_700_574)

        let instant = try SharePhotoEndpoint.makeRequest(
            baseURL: baseURL,
            projectId: projectId,
            jobId: jobId,
            takenAt: takenAt,
            bearerToken: "extension-token"
        )
        let fallback = try SharePhotoEndpoint.makeRequest(
            baseURL: baseURL,
            projectId: projectId,
            jobId: jobId,
            takenAt: takenAt,
            bearerToken: "fresh-app-token"
        )

        XCTAssertEqual(instant.httpMethod, "POST")
        XCTAssertEqual(instant.url, fallback.url)
        XCTAssertEqual(instant.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        XCTAssertEqual(instant.value(forHTTPHeaderField: "Authorization"), "Bearer extension-token")
        XCTAssertEqual(fallback.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-app-token")

        let components = try XCTUnwrap(URLComponents(url: instant.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/uploads/share-photo")
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }),
            [
                "projectId": projectId,
                "jobId": jobId,
                "takenAt": "2026-08-02T19:56:14Z",
            ]
        )
    }

    func testRejectsAnInvalidJobIdentityBeforeUploading() {
        let baseURL = URL(string: "https://app.opsapp.co")!

        XCTAssertThrowsError(
            try SharePhotoEndpoint.makeRequest(
                baseURL: baseURL,
                projectId: "B7EB718E-357D-45F9-A19D-68B2350F6544",
                jobId: "../different-object",
                takenAt: Date(),
                bearerToken: "token"
            )
        )
    }

    func testParkedRecoveryReportUsesTheStableJobIdentity() throws {
        let request = try SharePhotoEndpoint.makeRecoveryReportRequest(
            baseURL: URL(string: "https://app.opsapp.co")!,
            projectId: "B7EB718E-357D-45F9-A19D-68B2350F6544",
            jobId: "2C20ED29-F328-49CB-A5DB-A45D83FB5938",
            bearerToken: "fresh-app-token"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.path,
            "/api/uploads/share-photo/recovery"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer fresh-app-token"
        )
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: (
                    URLComponents(
                        url: try XCTUnwrap(request.url),
                        resolvingAgainstBaseURL: false
                    )?.queryItems ?? []
                ).map { ($0.name, $0.value ?? "") }
            ),
            [
                "projectId": "B7EB718E-357D-45F9-A19D-68B2350F6544",
                "jobId": "2C20ED29-F328-49CB-A5DB-A45D83FB5938",
            ]
        )
    }

    func testCorruptLegacyIdentityCanStillRequestAnUnlinkedRecoveryAlert() {
        XCTAssertNoThrow(
            try SharePhotoEndpoint.makeRecoveryReportRequest(
                baseURL: URL(string: "https://app.opsapp.co")!,
                projectId: "legacy-project-id",
                jobId: "legacy-job-id",
                bearerToken: "fresh-app-token"
            )
        )
    }
}
