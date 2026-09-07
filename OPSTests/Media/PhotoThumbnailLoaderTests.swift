import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import OPS

final class PhotoThumbnailLoaderTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testCompositeWinsAndDecodeHonorsPixelBoundWithoutNetwork() async throws {
        let composite = root.appendingPathComponent("composite.png")
        try await fixture(width: 120, height: 60).write(to: composite)
        let probe = ThumbnailFetchProbe(data: Data())
        let loader = PhotoThumbnailLoader(
            fetch: { try await probe.fetch($0) },
            localURL: { $0 == "composite" ? composite : nil },
            compositeID: { _ in "composite" }, store: { _, _ in }
        )
        let image = try await loader.image(for: PhotoThumbnailRequest(sourceURL: "https://example.test/raw.jpg", maxPixelSize: 30))
        XCTAssertEqual(image?.cgImage?.width, 30)
        XCTAssertEqual(image?.cgImage?.height, 15)
        let count = await probe.count
        XCTAssertEqual(count, 0)
    }

    func testUnavailableRenderedSourceFallsBackToRemoteOriginal() async throws {
        let raw = await fixture(width: 80, height: 40)
        let probe = ThumbnailFetchProbe(data: raw)
        let loader = PhotoThumbnailLoader(
            fetch: { url in
                if url.lastPathComponent == "markup.jpg" { throw URLError(.notConnectedToInternet) }
                return try await probe.fetch(url)
            }, localURL: { _ in nil }, compositeID: { "composite-" + $0 }, store: { _, _ in }
        )
        let image = try await loader.image(for: PhotoThumbnailRequest(sourceURL: "https://example.test/markup.jpg", fallbackURL: "https://example.test/raw.jpg", maxPixelSize: 20))
        XCTAssertEqual(image?.cgImage?.width, 20)
        let count = await probe.count
        XCTAssertEqual(count, 1)
    }

    func testCacheArrivalOnSameRequestLoadsNewMarkup() async throws {
        let composite = root.appendingPathComponent("composite.png")
        let raw = await fixture(width: 80, height: 40)
        let loader = PhotoThumbnailLoader(fetch: { _ in raw }, localURL: { $0 == "composite" ? composite : nil }, compositeID: { _ in "composite" }, store: { _, _ in })
        let request = PhotoThumbnailRequest(sourceURL: "https://example.test/raw.jpg", maxPixelSize: 20)
        let first = try await loader.image(for: request)
        XCTAssertEqual(first?.cgImage?.height, 10)
        try await fixture(width: 40, height: 80).write(to: composite)
        let refreshed = try await loader.image(for: request)
        XCTAssertEqual(refreshed?.cgImage?.width, 10)
        XCTAssertEqual(refreshed?.cgImage?.height, 20)
    }

    func testOrientationMetadataIsAppliedDuringDownsampling() async throws {
        let data = await fixture(width: 80, height: 40)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let image = PhotoDownsampler.image(data: output as Data, maxPixelSize: 20)
        XCTAssertEqual(image?.cgImage?.width, 10)
        XCTAssertEqual(image?.cgImage?.height, 20)
        XCTAssertEqual(image?.imageOrientation, .up)
    }

    func testConcurrentRequestsShareFetchAndCancellationLeavesOtherWaiterAlive() async throws {
        let probe = ThumbnailFetchProbe(data: await fixture(width: 80, height: 40), suspended: true)
        let loader = PhotoThumbnailLoader(fetch: { try await probe.fetch($0) }, localURL: { _ in nil }, store: { _, _ in })
        let request = PhotoThumbnailRequest(sourceURL: "https://example.test/shared.jpg", maxPixelSize: 20)
        let first = Task { try await loader.image(for: request) }
        let second = Task { try await loader.image(for: request) }
        // Bounded cooperative scheduling, no wall-time sleep or real network.
        for _ in 0..<1000 {
            if await loader.waiterCount(for: request) == 2 { break }
            await Task.yield()
        }
        let waiters = await loader.waiterCount(for: request)
        XCTAssertEqual(waiters, 2)
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled tile must finish with cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        await probe.release()
        let remaining = try await second.value
        XCTAssertNotNil(remaining)
        let count = await probe.count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    private func fixture(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: format).pngData { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
    }
}

private actor ThumbnailFetchProbe {
    private let data: Data
    private var suspended: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var count = 0
    init(data: Data, suspended: Bool = false) { self.data = data; self.suspended = suspended }
    func fetch(_ url: URL) async throws -> Data {
        count += 1
        if suspended { await withCheckedContinuation { continuation = $0 } }
        return data
    }
    func release() { suspended = false; continuation?.resume(); continuation = nil }
}
