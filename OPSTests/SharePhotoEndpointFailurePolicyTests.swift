//
//  SharePhotoEndpointFailurePolicyTests.swift
//  OPSTests
//
//  Temporary transport/auth/server failures never consume a queued photo's
//  retry budget. Deterministic request/project failures eventually park it while
//  retaining the bytes for recovery.
//

import XCTest
@testable import OPS

final class SharePhotoEndpointFailurePolicyTests: XCTestCase {

    func testTransientHTTPFailuresNeverConsumeTheRetryBudget() {
        for status in [401, 408, 429, 500, 503] {
            XCTAssertTrue(
                SharePhotoEndpointUploader.isTransient(
                    SharePhotoEndpointUploader.UploadError.rejected(
                        statusCode: status,
                        message: nil
                    )
                ),
                "HTTP \(status) should remain retryable"
            )
        }
    }

    func testDeterministicHTTPFailuresCountTowardParking() {
        for status in [400, 403, 404, 409, 413] {
            XCTAssertFalse(
                SharePhotoEndpointUploader.isTransient(
                    SharePhotoEndpointUploader.UploadError.rejected(
                        statusCode: status,
                        message: nil
                    )
                ),
                "HTTP \(status) should count toward parking"
            )
        }
    }

    func testInvalidRequestConstructionCountsTowardParking() {
        let errors: [SharePhotoEndpoint.RequestError] = [
            .invalidBaseURL,
            .invalidProjectId,
            .invalidJobId,
            .missingBearerToken,
        ]

        for error in errors {
            XCTAssertFalse(
                SharePhotoEndpointUploader.isTransient(error),
                "\(error) is deterministic and must not retry forever"
            )
        }
    }

    func testParkedJobReportsUntilTheRecoveryNotificationIsAcknowledged() {
        XCTAssertEqual(
            ShareUploadCoordinator.actionForAttemptCount(
                ShareUploadManifestStore.maxAttempts - 1
            ),
            .upload
        )
        XCTAssertEqual(
            ShareUploadCoordinator.actionForAttemptCount(
                ShareUploadManifestStore.maxAttempts
            ),
            .reportRecovery
        )
        XCTAssertEqual(
            ShareUploadCoordinator.actionForAttemptCount(
                ShareUploadManifestStore.maxAttempts + 1
            ),
            .reported
        )
    }
}
