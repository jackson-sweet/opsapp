//
//  AnnotationClearPlannerTests.swift
//  OPSTests
//
//  Locks the decision for an empty (cleared) drawing save: an existing pure
//  PencilKit annotation is soft-deleted (so cleared markup disappears here and
//  on teammates' devices), a dimensioned capture is preserved, and a brand-new
//  empty save is a no-op rather than a junk empty row.
//

import XCTest
@testable import OPS

final class AnnotationClearPlannerTests: XCTestCase {

    func testExistingPencilKitAnnotationIsSoftDeleted() {
        XCTAssertEqual(
            AnnotationClearPlanner.plan(existingAnnotationId: "anno-1", hasDimensions: false),
            .softDelete
        )
    }

    func testDimensionedCaptureIsPreserved() {
        XCTAssertEqual(
            AnnotationClearPlanner.plan(existingAnnotationId: "anno-1", hasDimensions: true),
            .preserveDimensioned
        )
    }

    func testNoExistingAnnotationIsIgnored() {
        XCTAssertEqual(
            AnnotationClearPlanner.plan(existingAnnotationId: nil, hasDimensions: false),
            .ignore
        )
        // A nil id wins even if dimensions were (spuriously) reported.
        XCTAssertEqual(
            AnnotationClearPlanner.plan(existingAnnotationId: nil, hasDimensions: true),
            .ignore
        )
    }

    // MARK: - Author-scoped clear (collaborative markup, HARD CORRECTION 3)

    private func layer(_ id: String, cleared: Bool = false) -> MarkupLayer {
        MarkupLayer(
            layerId: id, authorId: id, authorName: id,
            overlayUrl: cleared ? nil : "\(id).png", strokeRef: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            clearedAt: cleared ? Date(timeIntervalSince1970: 1_700_000_000) : nil
        )
    }

    /// THE spec case: open a PEER's row, tap DONE with no marks of your own.
    /// Must be a no-op — never delete the peer's layer/row.
    func testPeerRowClearedByNonAuthorIsIgnored() {
        XCTAssertEqual(
            AnnotationClearPlanner.plan(
                existingAnnotationId: "anno-1",
                hasDimensions: false,
                layers: [layer("peer")],          // only the peer has a layer
                currentUserId: "me"               // I never drew
            ),
            .ignore
        )
    }

    func testClearingOwnLayerWhilePeerActive_keepsRow() {
        XCTAssertEqual(
            AnnotationClearPlanner.plan(
                existingAnnotationId: "anno-1",
                hasDimensions: false,
                layers: [layer("me"), layer("peer")],
                currentUserId: "me"
            ),
            .clearOwnLayer
        )
    }

    func testClearingOwnLayerWhenSoleAuthor_softDeletes() {
        XCTAssertEqual(
            AnnotationClearPlanner.plan(
                existingAnnotationId: "anno-1",
                hasDimensions: false,
                layers: [layer("me")],
                currentUserId: "me"
            ),
            .softDelete
        )
    }

    func testDimensionedRowWithOwnLayer_clearsLayerNotRow() {
        XCTAssertEqual(
            AnnotationClearPlanner.plan(
                existingAnnotationId: "anno-1",
                hasDimensions: true,
                layers: [layer("me")],
                currentUserId: "me"
            ),
            .clearOwnLayer
        )
    }

    func testDimensionedRowWithoutOwnLayer_preserved() {
        XCTAssertEqual(
            AnnotationClearPlanner.plan(
                existingAnnotationId: "anno-1",
                hasDimensions: true,
                layers: [layer("peer")],
                currentUserId: "me"
            ),
            .preserveDimensioned
        )
    }

    func testAlreadyClearedPeerLayerCountsAsInactive() {
        // Only my layer is active; the peer already cleared theirs -> sole author.
        XCTAssertEqual(
            AnnotationClearPlanner.plan(
                existingAnnotationId: "anno-1",
                hasDimensions: false,
                layers: [layer("me"), layer("peer", cleared: true)],
                currentUserId: "me"
            ),
            .softDelete
        )
    }
}
