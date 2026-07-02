//
//  ImageDownsamplerTests.swift
//  OPSTests
//
//  Verifies the tile-size downsampler used by PhotoThumbnail: encoded-data
//  downsampling (ImageIO, no full-bitmap decode) and already-decoded
//  downscaling (disk originals / composites).
//

import XCTest
@testable import OPS

final class ImageDownsamplerTests: XCTestCase {

    private func makeJPEGData(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        ).image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }

    func testDownsampleDataCapsLongestSide() {
        let data = makeJPEGData(width: 1200, height: 900)
        let result = ImageDownsampler.downsample(data: data, maxPixelSize: 216)
        XCTAssertNotNil(result)
        let cg = result!.cgImage!
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 216)
        XCTAssertEqual(Double(cg.width) / Double(cg.height), 1200.0 / 900.0, accuracy: 0.05)
    }

    func testDownsampleGarbageDataReturnsNil() {
        XCTAssertNil(ImageDownsampler.downsample(data: Data([0x00, 0x01, 0x02]), maxPixelSize: 216))
    }

    func testDownsampleImageAlreadySmallReturnsOriginal() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80), format: format).image { _ in }
        let result = ImageDownsampler.downsample(image: small, maxPixelSize: 216)
        XCTAssertEqual(result.size, small.size)
    }

    func testDownsampleImageCapsLongestSide() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000), format: format).image { _ in }
        let result = ImageDownsampler.downsample(image: big, maxPixelSize: 216)
        XCTAssertLessThanOrEqual(max(result.size.width, result.size.height) * result.scale, 216)
    }
}
