//
//  DepthMapLoaderTests.swift
//  OPSTests
//
//  Focused tests for the standalone FP32 LiDAR depth asset.
//

import XCTest
@testable import OPS

final class DepthMapLoaderTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DepthMapLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_load_acceptsExactLiDARRawFP32Grid() throws {
        let url = tempDir.appendingPathComponent("exact.depth.fp32")
        try writeDepthFixture(
            to: url,
            width: DepthMapLoader.lidarDepthWidth,
            height: DepthMapLoader.lidarDepthHeight
        )

        let depth = try XCTUnwrap(DepthMapLoader.load(from: url))

        XCTAssertEqual(depth.width, 768)
        XCTAssertEqual(depth.height, 576)
        XCTAssertEqual(depth.values.count, 768 * 576)
    }

    func test_loadRejectsRawFP32GridWithWrongHeight() throws {
        let url = tempDir.appendingPathComponent("wrong-height.depth.fp32")
        try writeDepthFixture(to: url, width: 768, height: 575)

        XCTAssertNil(DepthMapLoader.load(from: url))
    }

    private func writeDepthFixture(to url: URL, width: Int, height: Int) throws {
        let values = Array(repeating: Float(2), count: width * height)
        let data = values.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        try data.write(to: url)
    }
}
