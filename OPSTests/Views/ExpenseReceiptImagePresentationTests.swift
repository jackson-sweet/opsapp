//
//  ExpenseReceiptImagePresentationTests.swift
//  OPSTests
//
//  Regression coverage for bug 8831f6db-a616-41d6-949f-fa6f65c41907:
//  every edge of a tall receipt must survive thumbnail preparation and remain
//  visible in the compact Books review presentation.
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class ExpenseReceiptImagePresentationTests: XCTestCase {

    func testReviewUsesAuthoritativeFullImageWhenHistoricalThumbnailWasCropped() {
        XCTAssertEqual(
            ExpenseReceiptDisplaySource.reviewURL(
                full: "https://example.com/full-receipt.jpg",
                thumbnail: "https://example.com/cropped-thumbnail.jpg"
            ),
            "https://example.com/full-receipt.jpg"
        )
    }

    func testReviewFallsBackToThumbnailWhenFullImageIsUnavailable() {
        XCTAssertEqual(
            ExpenseReceiptDisplaySource.reviewURL(
                full: nil,
                thumbnail: "https://example.com/receipt-thumbnail.jpg"
            ),
            "https://example.com/receipt-thumbnail.jpg"
        )
    }

    func testThumbnailPreparationPreservesTallReceiptAspectAndEdges() throws {
        let source = makeReceipt(width: 600, height: 2_400)

        let thumbnail = ExpenseReceiptImagePreparation.thumbnail(from: source)

        XCTAssertEqual(thumbnail.size.width, 128, accuracy: 1)
        XCTAssertEqual(thumbnail.size.height, 512, accuracy: 1)
        let colors = try colorCounts(in: thumbnail)
        XCTAssertGreaterThan(colors.red, 100, "The receipt's top edge must survive thumbnail preparation.")
        XCTAssertGreaterThan(colors.blue, 100, "The receipt's bottom edge must survive thumbnail preparation.")
    }

    func testCompactReceiptPresentationKeepsTopAndBottomVisible() throws {
        let source = makeReceipt(width: 60, height: 240)
        let rendered = try FixedSizeSnapshot.render(
            ExpenseReceiptThumbnailImage(image: Image(uiImage: source))
                .frame(width: 60, height: 80)
                .background(Color.black)
                .clipped(),
            size: CGSize(width: 60, height: 80)
        )

        let colors = try colorCounts(in: rendered)
        XCTAssertGreaterThan(colors.red, 20, "The compact receipt must show its top edge.")
        XCTAssertGreaterThan(colors.blue, 20, "The compact receipt must show its bottom edge.")
    }

    private func makeReceipt(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 10))

            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: height - (height / 10), width: width, height: height / 10))
        }
    }

    private func colorCounts(in image: UIImage) throws -> (red: Int, blue: Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ))
        context.setBlendMode(.copy)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var red = 0
        var blue = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[index])
            let g = Int(pixels[index + 1])
            let b = Int(pixels[index + 2])
            if r > 180, g < 80, b < 80 { red += 1 }
            if b > 180, r < 80, g < 80 { blue += 1 }
        }
        return (red, blue)
    }
}
#endif
