//
//  DeckRendererStairAnnotationTests.swift
//  OPSTests
//
//  Regression coverage for partial-stair measurement parity in exported plans.
//

import CoreGraphics
import UIKit
import XCTest
@testable import OPS

final class DeckRendererStairAnnotationTests: XCTestCase {

    func testExportDrawsPartialStairBoundaryAndDimensionChips() throws {
        let image = try XCTUnwrap(
            DeckRenderer.renderToPNG(
                drawingData: partialStairDrawing(),
                size: CGSize(width: 600, height: 400)
            )
        )
        let attachment = XCTAttachment(image: image)
        attachment.name = "partial-stair-export-annotations"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Hand-derived from the fixture's 222 x 96 canvas fitted into the
        // renderer's 60pt inset: the right-aligned stair starts at x ~= 436,
        // its WIDTH chip is centred near (488, 80), and the 14' 6" adjacent
        // span chip is centred near (248, 60).
        XCTAssertGreaterThan(
            darkPixelCount(in: image, pointRect: CGRect(x: 429, y: 89, width: 14, height: 14)),
            45,
            "The exported host edge must include a visible stair-boundary marker."
        )
        XCTAssertGreaterThan(
            darkPixelCount(in: image, pointRect: CGRect(x: 448, y: 68, width: 80, height: 24)),
            120,
            "The exported stair must include its WIDTH chip."
        )
        XCTAssertGreaterThan(
            darkPixelCount(in: image, pointRect: CGRect(x: 208, y: 48, width: 80, height: 24)),
            120,
            "The exported host edge must include its authoritative adjacent-span chip."
        )
        XCTAssertGreaterThan(
            dimensionPixelCount(in: image, pointRect: CGRect(x: 260, y: 106, width: 80, height: 24)),
            20,
            "The exported host edge must retain its total dimension on the side opposite the stair."
        )
    }

    private func partialStairDrawing() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 222, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 222, y: 96)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 96)),
        ]
        var stairEdge = DeckEdge(
            id: "e1",
            startVertexId: "v1",
            endVertexId: "v2",
            dimension: 222
        )
        stairEdge.stairConfig = StairConfig(
            width: 48,
            runPerTread: 10,
            treadCount: 4,
            alignment: .right
        )
        data.edges = [
            stairEdge,
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3", dimension: 96),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4", dimension: 222),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1", dimension: 96),
        ]
        return data
    }

    private func darkPixelCount(in image: UIImage, pointRect: CGRect) -> Int {
        pixelCount(in: image, pointRect: pointRect) { red, green, blue, alpha in
            red < 100 && green < 100 && blue < 100 && alpha > 0
        }
    }

    private func dimensionPixelCount(in image: UIImage, pointRect: CGRect) -> Int {
        pixelCount(in: image, pointRect: pointRect) { red, green, blue, alpha in
            red < 150 && green < 175 && blue < 210 && blue > red && alpha > 0
        }
    }

    private func pixelCount(
        in image: UIImage,
        pointRect: CGRect,
        matching predicate: (UInt8, UInt8, UInt8, UInt8) -> Bool
    ) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixelRect = CGRect(
            x: pointRect.minX * image.scale,
            y: pointRect.minY * image.scale,
            width: pointRect.width * image.scale,
            height: pointRect.height * image.scale
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        var count = 0
        for y in Int(pixelRect.minY)..<Int(pixelRect.maxY) {
            for x in Int(pixelRect.minX)..<Int(pixelRect.maxX) {
                let index = y * bytesPerRow + x * 4
                if predicate(
                    pixels[index],
                    pixels[index + 1],
                    pixels[index + 2],
                    pixels[index + 3]
                ) {
                    count += 1
                }
            }
        }
        return count
    }
}
