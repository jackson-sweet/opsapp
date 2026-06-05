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
}
