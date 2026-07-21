//
//  TaskReviewImageRenditionTests.swift
//  OPSTests
//
//  Regression coverage for isolated Task Review image-cache variants.
//

import XCTest
@testable import OPS

final class TaskReviewImageRenditionTests: XCTestCase {

    func testReviewRenditionDoesNotOverwriteFullResolutionCacheEntry() {
        let sourceKey = TaskReviewImageRendition.sourceCacheKey(
            for: "https://example.com/project-photo.jpg"
        )
        let reviewKey = TaskReviewImageRendition.cacheKey(forSourceKey: sourceKey)

        XCTAssertNotEqual(reviewKey, sourceKey)
        XCTAssertEqual(reviewKey, sourceKey + "#review-card-2048")
    }

    func testProtocolRelativePhotoUsesSameNormalizedSourceKey() {
        let absolute = TaskReviewImageRendition.sourceCacheKey(
            for: "https://example.com/project-photo.jpg"
        )
        let protocolRelative = TaskReviewImageRendition.sourceCacheKey(
            for: "//example.com/project-photo.jpg"
        )

        XCTAssertEqual(protocolRelative, absolute)
        XCTAssertEqual(
            TaskReviewImageRendition.cacheKey(forSourceKey: protocolRelative),
            TaskReviewImageRendition.cacheKey(forSourceKey: absolute)
        )
    }

    func testProjectAndTaskCardsShareTheSameReviewRenditionKey() {
        let source = "https://example.com/project-photo.jpg"

        XCTAssertEqual(
            ReviewCardImageRendition.cacheKey(forSourceKey: source),
            TaskReviewImageRendition.cacheKey(forSourceKey: source)
        )
        XCTAssertTrue(
            ReviewCardImageRendition.cacheKey(forSourceKey: source)
                .hasSuffix("#review-card-2048")
        )
    }
}
