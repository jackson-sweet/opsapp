//
//  AnnotationFeedPolicyTests.swift
//  OPSTests
//
//  Locks the Activity-feed inclusion + labelling rules: a drawing markup with
//  no note now earns a "marked up a photo" card; a note-only annotation stays
//  "commented on a photo"; an empty/dimensioned-only row stays out of the feed.
//

import XCTest
@testable import OPS

final class AnnotationFeedPolicyTests: XCTestCase {

    // MARK: belongsInFeed

    func testMarkupOnlyBelongsInFeed() {
        XCTAssertTrue(AnnotationFeedPolicy.belongsInFeed(
            annotationURL: "https://x/annotations/a.png", note: ""))
    }

    func testNoteOnlyBelongsInFeed() {
        XCTAssertTrue(AnnotationFeedPolicy.belongsInFeed(annotationURL: nil, note: "check this corner"))
        XCTAssertTrue(AnnotationFeedPolicy.belongsInFeed(annotationURL: "", note: "check this corner"))
    }

    func testMarkupAndNoteBelongsInFeed() {
        XCTAssertTrue(AnnotationFeedPolicy.belongsInFeed(
            annotationURL: "https://x/annotations/a.png", note: "fix this"))
    }

    func testEmptyRowExcluded() {
        // No overlay + no note (e.g. a pure dimensioned capture) → not in feed.
        XCTAssertFalse(AnnotationFeedPolicy.belongsInFeed(annotationURL: nil, note: ""))
        XCTAssertFalse(AnnotationFeedPolicy.belongsInFeed(annotationURL: "", note: "   "))
    }

    // MARK: actionLabel

    func testActionLabelMarkup() {
        XCTAssertEqual(AnnotationFeedPolicy.actionLabel(annotationURL: "https://x/a.png"), "marked up a photo")
    }

    func testActionLabelComment() {
        XCTAssertEqual(AnnotationFeedPolicy.actionLabel(annotationURL: nil), "commented on a photo")
        XCTAssertEqual(AnnotationFeedPolicy.actionLabel(annotationURL: ""), "commented on a photo")
    }
}
