//
//  PhotoAnnotationVisibilityTests.swift
//  OPSTests
//
//  Regression coverage for classic PencilKit photo markup visibility.
//

import CoreGraphics
import XCTest
@testable import OPS

final class PhotoAnnotationVisibilityTests: XCTestCase {

    func testRenderGeometryUsesDisplayedCanvasSizeRatherThanNaturalImagePixels() {
        let fittedCanvas = CGSize(width: 390, height: 520)
        let naturalImage = CGSize(width: 3024, height: 4032)

        let renderSize = PhotoAnnotationRenderGeometry.renderSize(
            displayedCanvasSize: fittedCanvas,
            sourceImageSize: naturalImage
        )

        XCTAssertEqual(renderSize.width, fittedCanvas.width, accuracy: 0.001)
        XCTAssertEqual(renderSize.height, fittedCanvas.height, accuracy: 0.001)
    }

    func testRenderGeometryFallsBackToSourceImageOnlyWhenDisplayedCanvasIsUnavailable() {
        let renderSize = PhotoAnnotationRenderGeometry.renderSize(
            displayedCanvasSize: .zero,
            sourceImageSize: CGSize(width: 3024, height: 4032)
        )

        XCTAssertEqual(renderSize.width, 3024, accuracy: 0.001)
        XCTAssertEqual(renderSize.height, 4032, accuracy: 0.001)
    }

    func testCompositePlanDownloadsRemoteBaseImageWhenItIsNotCachedYet() throws {
        let plan = try XCTUnwrap(PhotoAnnotationCompositePlan(
            photoURL: "//cdn.example.test/project/photo.jpg",
            annotationURL: "https://cdn.example.test/project/annotation.png"
        ))

        XCTAssertEqual(plan.cacheKey, "https://cdn.example.test/project/photo.jpg")
        XCTAssertEqual(plan.baseLocalIDs, [
            "//cdn.example.test/project/photo.jpg",
            "https://cdn.example.test/project/photo.jpg"
        ])
        XCTAssertEqual(plan.baseRemoteURL?.absoluteString, "https://cdn.example.test/project/photo.jpg")
        XCTAssertEqual(plan.overlayRemoteURL.absoluteString, "https://cdn.example.test/project/annotation.png")
        XCTAssertEqual(plan.overlayLocalID(annotationId: "ann-1"), "overlay_ann-1")
    }

    func testCompositePlanIsNilWhenRemoteOverlayIsMissing() {
        XCTAssertNil(PhotoAnnotationCompositePlan(
            photoURL: "https://cdn.example.test/project/photo.jpg",
            annotationURL: nil
        ))
    }
}
