//
//  DimensionBadgeOverlayTests.swift
//  OPSTests
//
//  Phase F — verifies the dimensioned-photo badge overlay produces the
//  expected on-screen presence (or absence) and that the URL-set helper
//  buckets `PhotoAnnotation` rows correctly.
//
//  Pure SwiftUI snapshot testing without a third-party framework is awkward
//  on iOS — the project doesn't ship a snapshot harness, so these tests
//  exercise the renderable rect of the badge via `ImageRenderer` and assert
//  the bytes meet structural invariants (non-empty when shown, empty when
//  hidden). That keeps verification deterministic without a golden-image
//  pipeline that would need to be re-baselined on each font release.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.7
//

import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class DimensionBadgeOverlayTests: XCTestCase {

    // MARK: - dimensionedURLs helper

    func test_dimensionedURLs_returnsURLs_withDimensionsBlob() {
        let withDims = PhotoAnnotation(
            id: "a", projectId: "p", companyId: "c",
            photoURL: "https://example.test/photo-a.heic", authorId: "u"
        )
        withDims.dimensions = DimensionsData(
            captureMode: .lidar,
            calibration: .init(method: .lidar, estimatedAccuracyMeters: 0.025),
            intrinsics: .init(fx: 1, fy: 1, cx: 0, cy: 0, imageWidth: 1, imageHeight: 1)
        )

        let withoutDims = PhotoAnnotation(
            id: "b", projectId: "p", companyId: "c",
            photoURL: "https://example.test/photo-b.jpg", authorId: "u"
        )
        // No dimensions set — legacy PencilKit-only row.

        let deleted = PhotoAnnotation(
            id: "c", projectId: "p", companyId: "c",
            photoURL: "https://example.test/photo-c.heic", authorId: "u"
        )
        deleted.dimensions = DimensionsData(
            captureMode: .lidar,
            calibration: .init(method: .lidar, estimatedAccuracyMeters: 0.025),
            intrinsics: .init(fx: 1, fy: 1, cx: 0, cy: 0, imageWidth: 1, imageHeight: 1)
        )
        deleted.deletedAt = Date()

        let set = DimensionBadgeOverlay.dimensionedURLs(
            in: [withDims, withoutDims, deleted]
        )

        XCTAssertEqual(set, ["https://example.test/photo-a.heic"])
    }

    // MARK: - Rendered output presence

    func test_badge_renders_someContent_whenDimensioned() {
        let view = DimensionBadgeOverlay(isDimensioned: true)
            .frame(width: 80, height: 80)
        let image = renderToImage(view, size: CGSize(width: 80, height: 80))
        let data = image.pngData()
        XCTAssertNotNil(data)
        // A rendered SwiftUI view at 80×80 with a 12pt SF Symbol should produce
        // a PNG with non-trivial bytes — far more than a fully-transparent
        // 80×80 canvas (which is ~80 bytes after PNG encode).
        XCTAssertGreaterThan(data?.count ?? 0, 200,
                             "Expected the badge to draw visible pixels")
    }

    func test_badge_rendersEmpty_whenNotDimensioned() {
        let view = DimensionBadgeOverlay(isDimensioned: false)
            .frame(width: 80, height: 80)
        let image = renderToImage(view, size: CGSize(width: 80, height: 80))
        let data = image.pngData()
        XCTAssertNotNil(data)
        // A fully-transparent 80×80 PNG encodes very small.
        XCTAssertLessThan(data?.count ?? .max, 400,
                          "Expected near-empty PNG when badge is hidden; got \(data?.count ?? 0) bytes")
    }

    func test_badge_iconSizeOverride_isHonoured() {
        let small = DimensionBadgeOverlay(isDimensioned: true, iconPointSize: 8)
            .frame(width: 80, height: 80)
        let large = DimensionBadgeOverlay(isDimensioned: true, iconPointSize: 24)
            .frame(width: 80, height: 80)

        let smallBytes = renderToImage(small, size: CGSize(width: 80, height: 80))
            .pngData()?.count ?? 0
        let largeBytes = renderToImage(large, size: CGSize(width: 80, height: 80))
            .pngData()?.count ?? 0

        // Larger icon paints more pixels → bigger PNG. Not a tight assertion,
        // but enough to catch a regression that ignored the override.
        XCTAssertGreaterThan(largeBytes, smallBytes,
                             "24 pt badge should produce more rendered bytes than 8 pt")
    }

    // MARK: - Helpers

    private func renderToImage<V: View>(_ view: V, size: CGSize) -> UIImage {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = 1.0
        return renderer.uiImage ?? UIImage()
    }
}
