// OPSTests/DeckBuilder/DeckDimensionLabelViewportTests.swift

import CoreGraphics
import XCTest
@testable import OPS

final class DeckDimensionLabelViewportTests: XCTestCase {
    func testCompleteLabelLayoutLeavesViewportWithItsEdge() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 700)
        let pillSize = CGSize(width: 72, height: 20)

        let leftPlacement = DeckDimensionLabelPlacement.resolve(
            edgeStart: CGPoint(x: -240, y: 120),
            edgeEnd: CGPoint(x: -120, y: 120),
            perpendicularOffset: CGVector(dx: 0, dy: 18),
            pillSize: pillSize
        )
        let rightPlacement = DeckDimensionLabelPlacement.resolve(
            edgeStart: CGPoint(x: 510, y: 240),
            edgeEnd: CGPoint(x: 630, y: 240),
            perpendicularOffset: CGVector(dx: 0, dy: 18),
            pillSize: pillSize
        )

        XCTAssertEqual(leftPlacement.primaryAnchor, CGPoint(x: -180, y: 138))
        XCTAssertEqual(leftPlacement.pillRect, CGRect(x: -216, y: 128, width: 72, height: 20))
        XCTAssertEqual(leftPlacement.secondaryAnchor(verticalOffset: 12), CGPoint(x: -180, y: 150))
        XCTAssertFalse(viewport.intersects(leftPlacement.pillRect))

        XCTAssertEqual(rightPlacement.primaryAnchor, CGPoint(x: 570, y: 258))
        XCTAssertEqual(rightPlacement.pillRect, CGRect(x: 534, y: 248, width: 72, height: 20))
        XCTAssertEqual(rightPlacement.secondaryAnchor(verticalOffset: 12), CGPoint(x: 570, y: 270))
        XCTAssertFalse(viewport.intersects(rightPlacement.pillRect))
    }
}
