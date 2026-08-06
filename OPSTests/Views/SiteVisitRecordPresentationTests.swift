//
//  SiteVisitRecordPresentationTests.swift
//  OPSTests
//
//  Width and modal-state contracts for the Project Details site-visit record.
//

import XCTest
@testable import OPS

final class SiteVisitRecordPresentationTests: XCTestCase {

    func testDocumentWidthIsBoundedByTheActualSheetAtCompactWidths() {
        for width: CGFloat in [320, 390, 393] {
            let noPhotos = SiteVisitRecordPresentationMetrics(
                availableWidth: width,
                photoCount: 0
            )
            let sevenPhotos = SiteVisitRecordPresentationMetrics(
                availableWidth: width,
                photoCount: 7
            )

            XCTAssertEqual(noPhotos.documentWidth, width)
            XCTAssertEqual(sevenPhotos.documentWidth, width)
            XCTAssertEqual(
                sevenPhotos.documentWidth,
                noPhotos.documentWidth,
                "Adding photos must extend the horizontal evidence rail, never the document's ideal width."
            )
        }
    }

    func testEvidencePhotoTargetsMeetTheMobileMinimum() {
        let metrics = SiteVisitRecordPresentationMetrics(availableWidth: 320, photoCount: 7)
        XCTAssertGreaterThanOrEqual(metrics.photoTargetSize, OPSStyle.Layout.touchTargetMin)
    }

    func testViewerSelectionKeepsEveryPhotoAndTheTappedIndex() throws {
        let urls = (1...7).map { "file:///tmp/site-visit-photo-\($0).jpg" }
        let selection = try XCTUnwrap(
            SiteVisitRecordViewerState.selecting(photos: urls, index: 5)
        )

        XCTAssertEqual(selection.photos, urls)
        XCTAssertEqual(selection.index, 5)
    }

    func testViewerSelectionRejectsAnOutOfRangeIndex() {
        XCTAssertNil(SiteVisitRecordViewerState.selecting(photos: ["one.jpg"], index: 1))
        XCTAssertNil(SiteVisitRecordViewerState.selecting(photos: [], index: 0))
    }
}
