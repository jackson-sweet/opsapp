//
//  PhotoThumbnailTileTests.swift
//  OPSTests
//
//  The photo tile has one size, and the decode cap is derived from it.
//
//  `tileMaxPixelSize` used to be the literal 216 with a comment explaining it
//  was "72 pt at 3×" — two numbers that had to be kept in agreement by hand,
//  while every call site wrote its own bare `72` frame. A tile that is resized
//  without its cap moving either decodes a blurry image (cap too small) or
//  burns memory decoding pixels it will never show (cap too large).
//
//  So the point size is now the single source, the cap is derived, and this
//  pins the relationship.
//

import XCTest
@testable import OPS

final class PhotoThumbnailTileTests: XCTestCase {

    func test_decodeCapIsTheTileSizeAtThreeX() {
        XCTAssertEqual(
            PhotoThumbnail.tileMaxPixelSize,
            PhotoThumbnail.tileSize * 3,
            "The decode cap must follow the tile size — a tile resized without its cap decodes blurry or wastes memory."
        )
    }

    func test_tileIsAtLeastTheMinimumTouchTarget() {
        // Tiles are tappable (they open the photo viewer), so the tile size is
        // also a touch target and answers to the field minimum.
        XCTAssertGreaterThanOrEqual(
            PhotoThumbnail.tileSize,
            OPSStyle.Layout.touchTargetMin,
            "A tappable photo tile must clear the 44pt field minimum."
        )
    }
}
