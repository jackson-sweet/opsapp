import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

final class DraftingCanvasTests: XCTestCase {
    func testModelToPageUsesArchitecturalScale() {
        let canvas = DraftingCanvas(
            scale: DrawingScale(inchesPerFoot: 0.25),
            pageRect: CGRect(x: 36, y: 72, width: 720, height: 540)
        )

        XCTAssertEqual(canvas.modelToPage(CGPoint(x: 0, y: 0)), CGPoint(x: 36, y: 72))
        XCTAssertEqual(canvas.modelToPage(CGPoint(x: 12, y: 24)), CGPoint(x: 54, y: 108))
    }

    func testDraftingPrimitivesRenderNonBlankPixels() throws {
        let size = CGSize(width: 256, height: 256)
        let bitmap = BitmapHarness(size: size)
        let canvas = DraftingCanvas(
            scale: DrawingScale(inchesPerFoot: 0.25),
            pageRect: CGRect(x: 24, y: 24, width: 208, height: 208)
        )

        canvas.drawDimension(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 48, y: 0),
            in: bitmap.context,
            label: "4'-0\""
        )
        canvas.drawLeaderCallout(
            at: CGPoint(x: 24, y: 24),
            text: "A1",
            in: bitmap.context
        )
        canvas.drawScaleBar(in: bitmap.context)
        canvas.drawNorthArrow(in: bitmap.context)
        canvas.hatch(
            [
                CGPoint(x: 12, y: 36),
                CGPoint(x: 72, y: 36),
                CGPoint(x: 72, y: 72),
                CGPoint(x: 12, y: 72)
            ],
            pattern: .diagonal45,
            in: bitmap.context
        )

        XCTAssertGreaterThan(bitmap.nonTransparentPixelCount(), 120)
    }
}

private final class BitmapHarness {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    private let data: NSMutableData
    let context: CGContext

    init(size: CGSize) {
        self.width = Int(size.width)
        self.height = Int(size.height)
        self.bytesPerRow = width * 4
        self.data = NSMutableData(length: bytesPerRow * height)!
        self.context = CGContext(
            data: data.mutableBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    func nonTransparentPixelCount() -> Int {
        let bytes = data.bytes.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        return stride(from: 3, to: bytesPerRow * height, by: 4).reduce(0) { count, index in
            bytes[index] == 0 ? count : count + 1
        }
    }
}
