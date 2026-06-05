//
//  ImageFileManagerCompositeTests.swift
//  OPSTests
//
//  Coverage for the durable annotated-composite cache tier and the
//  overlay-PNG local cache. Both rely on ImageFileManager recognising key
//  forms (`composited_…`, `overlay_…`) that the pre-existing getFileURL
//  prefix cascade silently rejected (returning nil → save/load no-op).
//
//  These exercise real Documents file I/O against the test host's sandbox,
//  mirroring CaptureAssetWriterTests / CapturedAssetsTests. Every key is
//  uniquely suffixed and torn down so runs stay isolated.
//

import UIKit
import XCTest
@testable import OPS

final class ImageFileManagerCompositeTests: XCTestCase {

    private var createdURLs: [String] = []
    private var createdOverlayIDs: [String] = []

    override func tearDown() {
        for url in createdURLs {
            _ = ImageFileManager.shared.deleteCompositedImage(forURL: url)
            _ = ImageFileManager.shared.deleteImage(localID: url.hasPrefix("//") ? "https:" + url : url)
        }
        for overlayID in createdOverlayIDs {
            _ = ImageFileManager.shared.deleteImage(localID: overlayID)
        }
        createdURLs.removeAll()
        createdOverlayIDs.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func uniqueURL() -> String {
        let url = "https://test.ops.example.com/photo-\(UUID().uuidString).jpg"
        createdURLs.append(url)
        return url
    }

    private func imageData(_ side: CGFloat, color: UIColor = .red) -> Data {
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    // MARK: - Composited tier round-trip

    func testCompositedImageRoundTrips() throws {
        let url = uniqueURL()
        XCTAssertFalse(ImageFileManager.shared.compositedImageExists(forURL: url),
                       "No composite should exist before a save")
        XCTAssertNil(ImageFileManager.shared.loadCompositedImage(forURL: url))

        let data = imageData(16)
        XCTAssertTrue(ImageFileManager.shared.saveCompositedImage(data, forURL: url),
                      "saveCompositedImage must persist for a composited_ key")

        XCTAssertTrue(ImageFileManager.shared.compositedImageExists(forURL: url))
        XCTAssertNotNil(ImageFileManager.shared.loadCompositedImage(forURL: url),
                        "A persisted composite must decode back to a UIImage")
        XCTAssertEqual(ImageFileManager.shared.compositedImageFileSize(forURL: url), Int64(data.count))
        XCTAssertNotNil(ImageFileManager.shared.compositedImageModificationDate(forURL: url))

        XCTAssertTrue(ImageFileManager.shared.deleteCompositedImage(forURL: url))
        XCTAssertFalse(ImageFileManager.shared.compositedImageExists(forURL: url),
                       "Composite must be gone after delete")
    }

    /// The composite is a SEPARATE on-disk asset from the raw original. Writing
    /// a composite must not clobber the raw cache entry and vice-versa — the
    /// reader resolves composite-first, raw-second, so they must coexist.
    func testCompositedKeyDoesNotCollideWithRawCacheKey() throws {
        let url = uniqueURL()
        let cacheKey = url // already https:

        XCTAssertTrue(ImageFileManager.shared.saveImage(data: imageData(16, color: .blue), localID: cacheKey))
        XCTAssertTrue(ImageFileManager.shared.saveCompositedImage(imageData(16, color: .green), forURL: url))

        // Both resolve independently.
        XCTAssertNotNil(ImageFileManager.shared.loadImage(localID: cacheKey), "Raw must survive a composite write")
        XCTAssertNotNil(ImageFileManager.shared.loadCompositedImage(forURL: url), "Composite must survive a raw write")

        // Deleting the composite leaves the raw intact.
        _ = ImageFileManager.shared.deleteCompositedImage(forURL: url)
        XCTAssertNotNil(ImageFileManager.shared.loadImage(localID: cacheKey))
        XCTAssertFalse(ImageFileManager.shared.compositedImageExists(forURL: url))
    }

    /// Normalisation parity: a protocol-relative `//host/...` URL and its
    /// `https://host/...` form must address the same composite file, matching
    /// the cache-key contract every reader computes.
    func testCompositedKeyNormalisesProtocolRelativeURL() throws {
        let suffix = UUID().uuidString
        let httpsURL = "https://test.ops.example.com/p-\(suffix).jpg"
        let relativeURL = "//test.ops.example.com/p-\(suffix).jpg"
        createdURLs.append(httpsURL)

        XCTAssertTrue(ImageFileManager.shared.saveCompositedImage(imageData(16), forURL: relativeURL))
        XCTAssertTrue(ImageFileManager.shared.compositedImageExists(forURL: httpsURL),
                      "// and https: forms must hash to the same composite file")
    }

    // MARK: - Overlay PNG cache (regression — getFileURL used to reject overlay_)

    func testOverlayKeyPersistsAndLoads() throws {
        let overlayID = "overlay_\(UUID().uuidString)"
        createdOverlayIDs.append(overlayID)

        XCTAssertNotNil(ImageFileManager.shared.getFileURL(for: overlayID),
                        "getFileURL must resolve an overlay_ key (was returning nil → silent no-op)")
        XCTAssertTrue(ImageFileManager.shared.saveImage(data: imageData(8), localID: overlayID),
                      "Overlay PNG must persist for instant offline compositing")
        XCTAssertNotNil(ImageFileManager.shared.loadImage(localID: overlayID))
        XCTAssertTrue(ImageFileManager.shared.imageExists(localID: overlayID))
    }

    // MARK: - Budget / eviction integration

    /// Composited files must be eviction candidates so they can be reclaimed
    /// under storage pressure — otherwise they accumulate and silently blow
    /// the user's quota. NOTE: with budget 0 the evictor reclaims every
    /// non-pinned candidate in the photo cache dir; acceptable in the
    /// ephemeral test host.
    func testCompositedFilesAreEvictionCandidates() throws {
        let url = uniqueURL()
        XCTAssertTrue(ImageFileManager.shared.saveCompositedImage(imageData(32), forURL: url))
        XCTAssertTrue(ImageFileManager.shared.compositedImageExists(forURL: url))

        // Force eviction: budget 0 means everything non-pinned must go.
        _ = ImageFileManager.shared.evictRemoteImagesIfNeeded(bytesNeeded: 50_000_000, budget: 0)

        XCTAssertFalse(ImageFileManager.shared.compositedImageExists(forURL: url),
                       "A composited file must be reclaimable by the budget evictor")
    }

    /// A composite whose source URL is pinned must survive eviction, mirroring
    /// the raw-original pin guarantee.
    func testPinnedCompositedFileSurvivesEviction() throws {
        let url = uniqueURL()
        XCTAssertTrue(ImageFileManager.shared.saveCompositedImage(imageData(32), forURL: url))

        let previousPins = UserDefaults.standard.data(forKey: "photoPinnedURLs")
        defer {
            if let previousPins {
                UserDefaults.standard.set(previousPins, forKey: "photoPinnedURLs")
            } else {
                UserDefaults.standard.removeObject(forKey: "photoPinnedURLs")
            }
        }
        UserDefaults.standard.set(try JSONEncoder().encode(Set([url])), forKey: "photoPinnedURLs")

        _ = ImageFileManager.shared.evictRemoteImagesIfNeeded(bytesNeeded: 50_000_000, budget: 0)

        XCTAssertTrue(ImageFileManager.shared.compositedImageExists(forURL: url),
                      "A pinned photo's composite must be skipped by the evictor")
    }
}
