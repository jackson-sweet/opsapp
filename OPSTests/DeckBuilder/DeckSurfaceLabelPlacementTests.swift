// OPSTests/DeckBuilder/DeckSurfaceLabelPlacementTests.swift
//
// Surface labels have to fill the space a surface actually offers — the
// largest axis-aligned rectangle that fits inside the polygon — instead of
// sitting at 11pt canvas units that a fit-zoom transform shrinks to 3-6pt on
// screen (bug f7dd3673). These cover the geometry, the screen-space floor and
// cap, and the truncation fallback.

import CoreGraphics
import XCTest
@testable import OPS

final class DeckSurfaceLabelPlacementTests: XCTestCase {
    private let square: [CGPoint] = [
        .init(x: 0, y: 0), .init(x: 400, y: 0), .init(x: 400, y: 300), .init(x: 0, y: 300)
    ]
    /// L-shape: 400 wide, 300 tall, with the top-right 200x150 notch removed.
    private let lShape: [CGPoint] = [
        .init(x: 0, y: 0), .init(x: 200, y: 0), .init(x: 200, y: 150),
        .init(x: 400, y: 150), .init(x: 400, y: 300), .init(x: 0, y: 300)
    ]

    /// Fake text metrics: linear in font size, so the fit math is exercised
    /// without a font stack. Width = 0.6 * size per character, height = 1.2 * size.
    private let measure: (String, CGFloat) -> CGSize = { text, size in
        CGSize(width: CGFloat(text.count) * 0.6 * size, height: 1.2 * size)
    }

    func testRectangleSurfaceYieldsNearlyTheWholeSurface() throws {
        let rect = try XCTUnwrap(DeckSurfaceLabelPlacement.largestInscribedRect(in: square))
        XCTAssertGreaterThan(rect.width * rect.height, 0.9 * 400 * 300)
        XCTAssertTrue(DeckSurfaceLabelPlacement.isInside(rect, polygon: square))
    }

    func testLShapeRectangleLiesInsideOneLegAndNeverInTheNotch() throws {
        let rect = try XCTUnwrap(DeckSurfaceLabelPlacement.largestInscribedRect(in: lShape))
        XCTAssertTrue(DeckSurfaceLabelPlacement.isInside(rect, polygon: lShape))
        // The notch is x > 200 && y < 150; no corner may be there.
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        for corner in corners {
            XCTAssertFalse(corner.x > 200 && corner.y < 150, "corner \(corner) is in the notch")
        }
        XCTAssertGreaterThan(rect.width * rect.height, 0.5 * 200 * 300) // at least half of the tall leg
    }

    func testDegeneratePolygonReturnsNil() {
        XCTAssertNil(DeckSurfaceLabelPlacement.largestInscribedRect(in: [.zero, .init(x: 10, y: 10)]))
    }

    func testFitFillsTheRectangleAndRespectsScreenFloorAndCap() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let fit = DeckSurfaceLabelPlacement.fit(
            text: "Upper deck",
            in: rect,
            canvasScale: 0.5,
            padding: 8,
            measure: measure
        )
        XCTAssertLessThanOrEqual(fit.size.width, rect.width - 16)
        XCTAssertLessThanOrEqual(fit.size.height, rect.height - 16)
        XCTAssertLessThanOrEqual(fit.fontSize * 0.5, DeckSurfaceLabelPlacement.screenCapPoints)
        XCTAssertGreaterThanOrEqual(fit.fontSize * 0.5, DeckSurfaceLabelPlacement.screenFloorPoints)
        XCTAssertEqual(fit.text, "Upper deck")
    }

    func testTooNarrowRectangleTruncatesAtTheScreenFloorInsteadOfOverflowing() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 40)
        let fit = DeckSurfaceLabelPlacement.fit(
            text: "Upper deck level two",
            in: rect,
            canvasScale: 1,
            padding: 4,
            measure: measure
        )
        XCTAssertEqual(fit.fontSize, DeckSurfaceLabelPlacement.screenFloorPoints)
        XCTAssertTrue(fit.text.hasSuffix("\u{2026}"))
        XCTAssertLessThanOrEqual(fit.size.width, rect.width - 8)
    }

    /// Terminal case of the truncation walk: when not even one character plus
    /// the ellipsis fits, the label degrades to the ellipsis alone rather than
    /// drawing a word across the neighbouring geometry.
    func testUnfittableRectangleDegradesToTheEllipsisAlone() {
        let rect = CGRect(x: 0, y: 0, width: 14, height: 40)
        let fit = DeckSurfaceLabelPlacement.fit(
            text: "Upper deck level two",
            in: rect,
            canvasScale: 1,
            padding: 4,
            measure: measure
        )
        XCTAssertEqual(fit.text, "\u{2026}")
    }

    // MARK: - Edge captions

    /// Caption metrics at a given screen size: "6' TALL" is 7 characters wide.
    private let captionMeasure: (CGFloat) -> CGSize = { size in
        CGSize(width: 7 * 0.6 * size, height: 1.2 * size)
    }

    func testEdgeCaptionGrowsWithTheEdgeItAnnotatesUpToTheCaptionCap() {
        let size = DeckSurfaceLabelPlacement.edgeCaptionFontSize(
            edgeScreenLength: 600,
            measure: captionMeasure
        )
        XCTAssertEqual(size, DeckSurfaceLabelPlacement.edgeCaptionCapPoints)
    }

    func testEdgeCaptionNeverDropsBelowTheScreenFloor() {
        let longCaption: (CGFloat) -> CGSize = { size in
            CGSize(width: 40 * 0.6 * size, height: 1.2 * size)
        }
        let size = DeckSurfaceLabelPlacement.edgeCaptionFontSize(
            edgeScreenLength: 40,
            measure: longCaption
        )
        XCTAssertEqual(size, DeckSurfaceLabelPlacement.screenFloorPoints)
    }

    func testEdgeCaptionFitsSixtyPercentOfTheEdgeBetweenFloorAndCap() {
        let edgeScreenLength: CGFloat = 105
        let size = DeckSurfaceLabelPlacement.edgeCaptionFontSize(
            edgeScreenLength: edgeScreenLength,
            measure: captionMeasure
        )
        XCTAssertGreaterThan(size, DeckSurfaceLabelPlacement.screenFloorPoints)
        XCTAssertLessThan(size, DeckSurfaceLabelPlacement.edgeCaptionCapPoints)
        XCTAssertLessThanOrEqual(captionMeasure(size).width, edgeScreenLength * 0.6 + 0.001)
    }

    func testZeroLengthEdgeStillCaptionsAtTheScreenFloor() {
        let size = DeckSurfaceLabelPlacement.edgeCaptionFontSize(
            edgeScreenLength: 0,
            measure: captionMeasure
        )
        XCTAssertEqual(size, DeckSurfaceLabelPlacement.screenFloorPoints)
    }

    func testCenterIsInsideConcavePolygon() throws {
        let placement = try XCTUnwrap(DeckSurfaceLabelPlacement.largestInscribedRect(in: lShape))
        XCTAssertTrue(
            PolygonMath.pointInPolygon(CGPoint(x: placement.midX, y: placement.midY), vertices: lShape)
        )
    }
}
