// OPSTests/DeckBuilder/DeckCanvasViewportLayoutTests.swift

import CoreGraphics
import XCTest
@testable import OPS

final class DeckCanvasViewportLayoutTests: XCTestCase {
    func testBottomChromeNeverShortensTheFullBleedRenderSurface() {
        let layout = DeckCanvasViewportLayout(
            renderSize: CGSize(width: 390, height: 844),
            bottomChromeInset: 132
        )

        XCTAssertEqual(layout.renderFrame, CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertEqual(layout.unobstructedFrame, CGRect(x: 0, y: 0, width: 390, height: 712))
    }

    func testChangingBottomChromeOnlyChangesTheUnobstructedWorkArea() {
        let standard = DeckCanvasViewportLayout(
            renderSize: CGSize(width: 390, height: 844),
            bottomChromeInset: 98
        )
        let contextual = DeckCanvasViewportLayout(
            renderSize: CGSize(width: 390, height: 844),
            bottomChromeInset: 154
        )

        XCTAssertEqual(standard.renderFrame, contextual.renderFrame)
        XCTAssertEqual(standard.unobstructedSize.height, 746)
        XCTAssertEqual(contextual.unobstructedSize.height, 690)
    }

    func testOffsetAdjustmentKeepsTheSameWorldPointCenteredAboveChrome() {
        let oldLayout = DeckCanvasViewportLayout(
            renderSize: CGSize(width: 390, height: 844),
            bottomChromeInset: 0
        )
        let newLayout = DeckCanvasViewportLayout(
            renderSize: CGSize(width: 390, height: 844),
            bottomChromeInset: 132
        )

        let adjusted = newLayout.offsetPreservingUnobstructedCenter(
            CGSize(width: -40, height: 20),
            from: oldLayout
        )

        XCTAssertEqual(adjusted.width, -40, accuracy: 0.000_001)
        XCTAssertEqual(adjusted.height, -46, accuracy: 0.000_001)
    }

    func testOversizedAndNonFiniteInputsClampToSafeFiniteFrames() {
        let oversized = DeckCanvasViewportLayout(
            renderSize: CGSize(width: 390, height: 844),
            bottomChromeInset: 2_000
        )
        let invalid = DeckCanvasViewportLayout(
            renderSize: CGSize(width: .infinity, height: .nan),
            bottomChromeInset: .nan
        )

        XCTAssertEqual(oversized.renderSize, CGSize(width: 390, height: 844))
        XCTAssertEqual(oversized.unobstructedSize, CGSize(width: 390, height: 0))
        XCTAssertEqual(invalid.renderSize, .zero)
        XCTAssertEqual(invalid.unobstructedSize, .zero)
    }
}
