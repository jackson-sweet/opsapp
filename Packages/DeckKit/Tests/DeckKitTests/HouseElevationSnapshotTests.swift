import CoreGraphics
import XCTest
@testable import DeckKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class HouseElevationSnapshotTests: XCTestCase {
    func test_layoutScalesInchSpaceIntoCanvasWithMargins() throws {
        let layout = HouseElevationRenderer.layout(
            Self.sampleElevation(),
            size: Self.snapshotSize
        )

        XCTAssertEqual(layout.canvasSize, Self.snapshotSize)
        XCTAssertGreaterThan(layout.scale, 0)
        XCTAssertGreaterThan(layout.contentRect.width, 0)
        XCTAssertGreaterThan(layout.contentRect.height, 0)
        XCTAssertGreaterThan(layout.wallRect.width, 0)
        XCTAssertGreaterThan(layout.wallRect.height, 0)
        XCTAssertGreaterThan(layout.wallRect.minX, 0)
        XCTAssertGreaterThan(layout.wallRect.minY, 0)
        XCTAssertLessThan(layout.wallRect.maxX, Self.snapshotSize.width)
        XCTAssertLessThan(layout.gradeLineY, Self.snapshotSize.height)
        XCTAssertGreaterThan(layout.gradeLineY, layout.deckSurfaceY)
        XCTAssertGreaterThan(layout.deckSurfaceY, layout.wallRect.minY)

        let door = try XCTUnwrap(layout.openings.first { $0.id == "door-1" })
        XCTAssertEqual(door.rect.maxY, layout.deckSurfaceY, accuracy: 0.5)
        XCTAssertGreaterThan(door.rect.height, 0)
        XCTAssertGreaterThan(door.rect.minX, layout.wallRect.minX)
        XCTAssertLessThan(door.rect.maxX, layout.wallRect.maxX)

        let window = try XCTUnwrap(layout.openings.first { $0.id == "window-1" })
        XCTAssertLessThan(window.rect.maxY, layout.deckSurfaceY)
        XCTAssertGreaterThan(window.rect.minY, layout.wallRect.minY)
        XCTAssertGreaterThan(window.rect.height, 0)
    }

    func test_calloutTagsDrawnForEachOpening() throws {
        let layout = HouseElevationRenderer.layout(
            Self.sampleElevation(),
            size: Self.snapshotSize
        )

        XCTAssertEqual(layout.callouts.count, 2)
        XCTAssertEqual(Set(layout.callouts.map(\.tag)), Set(["D1", "W1"]))

        for callout in layout.callouts {
            XCTAssertGreaterThan(callout.badgeRect.width, 0)
            XCTAssertGreaterThan(callout.badgeRect.height, 0)
            XCTAssertTrue(layout.contentRect.contains(callout.anchor))
            XCTAssertTrue(layout.contentRect.contains(callout.leaderEnd))
        }
    }

    func test_renderProducesNonemptyImageOfRequestedSize() throws {
        let image = HouseElevationRenderer.render(
            Self.sampleElevation(),
            size: Self.snapshotSize
        )

        XCTAssertEqual(image.size.width, Self.snapshotSize.width)
        XCTAssertEqual(image.size.height, Self.snapshotSize.height)

        let data = try Self.imageData(from: image)
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertGreaterThan(try Self.distinctSampledColorCount(in: image), 1)

        let attachment = Self.attachment(from: data)
        attachment.name = "house-elevation-render"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "House Elevation Render") { activity in
            activity.add(attachment)
        }
    }

    private static let snapshotSize = CGSize(width: 800, height: 600)

    private static func sampleElevation() -> HouseElevationProjector.Elevation {
        HouseElevationProjector.Elevation(
            edgeId: "edge-house",
            wallLengthInches: 240,
            gradeYInches: 0,
            deckSurfaceYInches: 108,
            wallTopYInches: 216,
            openings: [
                HouseElevationProjector.ProjectedOpening(
                    id: "door-1",
                    kind: .sliderDoor,
                    rect: CGRect(x: 24, y: 108, width: 72, height: 80),
                    calloutTag: "D1"
                ),
                HouseElevationProjector.ProjectedOpening(
                    id: "window-1",
                    kind: .window,
                    rect: CGRect(x: 132, y: 144, width: 48, height: 36),
                    calloutTag: "W1"
                ),
            ],
            storyLines: [108, 216]
        )
    }

    private static func imageData(from image: DeckKitPlatformImage) throws -> Data {
        #if canImport(UIKit)
        return try XCTUnwrap(image.pngData())
        #elseif canImport(AppKit)
        return try XCTUnwrap(image.tiffRepresentation)
        #endif
    }

    private static func attachment(from data: Data) -> XCTAttachment {
        #if canImport(UIKit)
        return XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        #elseif canImport(AppKit)
        return XCTAttachment(data: data, uniformTypeIdentifier: "public.tiff")
        #endif
    }

    private static func cgImage(from image: DeckKitPlatformImage) throws -> CGImage {
        #if canImport(UIKit)
        return try XCTUnwrap(image.cgImage)
        #elseif canImport(AppKit)
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return try XCTUnwrap(
            image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        )
        #endif
    }

    private static func distinctSampledColorCount(
        in image: DeckKitPlatformImage
    ) throws -> Int {
        let cgImage = try cgImage(from: image)
        let sampleWidth = 80
        let sampleHeight = 60
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](
            repeating: 0,
            count: sampleWidth * sampleHeight * bytesPerPixel
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )

        context.interpolationQuality = .none
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
        )

        var colors = Set<UInt32>()
        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            guard pixels[offset + 3] > 0 else { continue }
            let red = UInt32(pixels[offset])
            let green = UInt32(pixels[offset + 1])
            let blue = UInt32(pixels[offset + 2])
            let alpha = UInt32(pixels[offset + 3])
            colors.insert(red << 24 | green << 16 | blue << 8 | alpha)
        }
        return colors.count
    }
}
