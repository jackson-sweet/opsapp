//
//  GalleryOrderingTests.swift
//  OPSTests
//
//  Bug e7ef2c88 / e1f073ed — the project gallery must render newest-first
//  everywhere (carousel, grid, viewer). Ordering resolves a per-URL date from
//  the synced project_photos row when one exists, else from the timestamp
//  embedded in the upload filename, else sinks to the legacy tail.
//

import XCTest
@testable import OPS

final class GalleryOrderingTests: XCTestCase {

    // MARK: - Filename timestamp parsing

    func testParsesWebMillisFilename() throws {
        let url = "https://bucket.s3.amazonaws.com/projects/co/proj/1782770183522-cji4cnrx.jpg"
        let date = try XCTUnwrap(GalleryOrdering.timestamp(fromURL: url))
        XCTAssertEqual(date.timeIntervalSince1970, 1782770183.522, accuracy: 0.01)
    }

    func testParsesIOSProjectUploadFilename() throws {
        // PresignedURLUploadService: "<street>_IMG_<epochSeconds>_<index>.jpg"
        // (timeIntervalSince1970 is a Double — may carry a fractional part).
        let url = "https://bucket.s3.amazonaws.com/projects/co/proj/123%20Main%20St_IMG_1782770183.123456_0.jpg"
        let date = try XCTUnwrap(GalleryOrdering.timestamp(fromURL: url))
        XCTAssertEqual(date.timeIntervalSince1970, 1782770183.123456, accuracy: 0.01)
    }

    func testParsesNoteUploadFilename() throws {
        let url = "https://bucket.s3.amazonaws.com/notes/co/proj/note_1782770183.5_1.jpg"
        let date = try XCTUnwrap(GalleryOrdering.timestamp(fromURL: url))
        XCTAssertEqual(date.timeIntervalSince1970, 1782770183.5, accuracy: 0.01)
    }

    func testParsesOfflineLocalFilename() throws {
        let url = "local://project_images/local_project_abc-123_1782770183.9_0.jpg"
        let date = try XCTUnwrap(GalleryOrdering.timestamp(fromURL: url))
        XCTAssertEqual(date.timeIntervalSince1970, 1782770183.9, accuracy: 0.01)
    }

    func testUnparseableFilenameReturnsNil() {
        XCTAssertNil(GalleryOrdering.timestamp(fromURL: "https://x.com/migrated/supabase-storage/photo.png"))
        XCTAssertNil(GalleryOrdering.timestamp(fromURL: "https://x.com/foo.jpg"))
        XCTAssertNil(GalleryOrdering.timestamp(fromURL: ""))
    }

    // MARK: - Newest-first merge

    private func epoch(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    func testRowDatedPhotosOrderNewestFirstRegardlessOfCSVPosition() {
        // CSV stored order: old, newest, middle — the bug's "inserted mid-list".
        let csv = ["https://x/a.jpg", "https://x/c.jpg", "https://x/b.jpg"]
        let rows: [(url: String, date: Date)] = [
            ("https://x/a.jpg", epoch(1_000)),
            ("https://x/b.jpg", epoch(2_000)),
            ("https://x/c.jpg", epoch(3_000)),
        ]
        let ordered = GalleryOrdering.orderedNewestFirst(csvURLs: csv, syncedPhotoDates: rows)
        XCTAssertEqual(ordered, ["https://x/c.jpg", "https://x/b.jpg", "https://x/a.jpg"])
    }

    func testFilenameDateUsedWhenNoRowExists() {
        // b has no synced row but a newer filename timestamp than a's row date.
        let csv = ["https://x/1000000000000-aaaa.jpg", "https://x/2000000000000-bbbb.jpg"]
        let rows: [(url: String, date: Date)] = [
            ("https://x/1000000000000-aaaa.jpg", epoch(1_000_000_000)),
        ]
        let ordered = GalleryOrdering.orderedNewestFirst(csvURLs: csv, syncedPhotoDates: rows)
        XCTAssertEqual(ordered.first, "https://x/2000000000000-bbbb.jpg")
    }

    func testUndatedLegacyURLsKeepCSVOrderAtTheTail() {
        let csv = ["https://x/legacy-one.png", "https://x/legacy-two.png", "https://x/3000000000000-c.jpg"]
        let ordered = GalleryOrdering.orderedNewestFirst(csvURLs: csv, syncedPhotoDates: [])
        XCTAssertEqual(ordered, [
            "https://x/3000000000000-c.jpg",
            "https://x/legacy-one.png",
            "https://x/legacy-two.png",
        ])
    }

    func testSyncedOnlyURLsAppearAndEmptyStringsDrop() {
        let csv = ["", "https://x/legacy.png"]
        let rows: [(url: String, date: Date)] = [
            ("https://x/synced-only.jpg", epoch(5_000)),
            ("", epoch(6_000)),
        ]
        let ordered = GalleryOrdering.orderedNewestFirst(csvURLs: csv, syncedPhotoDates: rows)
        XCTAssertEqual(ordered, ["https://x/synced-only.jpg", "https://x/legacy.png"])
    }

    func testDeduplicatesByURL() {
        let csv = ["https://x/dup.jpg", "https://x/dup.jpg"]
        let rows: [(url: String, date: Date)] = [("https://x/dup.jpg", epoch(1_000))]
        let ordered = GalleryOrdering.orderedNewestFirst(csvURLs: csv, syncedPhotoDates: rows)
        XCTAssertEqual(ordered, ["https://x/dup.jpg"])
    }

    func testProtocolRelativeAliasesDeduplicateAndCanonicalTombstonesSuppressCSV() {
        let csv = [
            "//x/photo.jpg",
            "https://x/photo.jpg",
            "//x/deleted.jpg",
        ]
        let rows: [(url: String, date: Date)] = [
            ("https://x/photo.jpg", epoch(1_000)),
        ]

        let ordered = GalleryOrdering.orderedNewestFirst(
            csvURLs: csv,
            syncedPhotoDates: rows,
            excludedURLIdentities: ["https://x/deleted.jpg"]
        )

        XCTAssertEqual(ordered, ["//x/photo.jpg"])
    }

    func testTiedDatesKeepStableOrder() {
        let csv: [String] = []
        let rows: [(url: String, date: Date)] = [
            ("https://x/first.jpg", epoch(1_000)),
            ("https://x/second.jpg", epoch(1_000)),
        ]
        let ordered = GalleryOrdering.orderedNewestFirst(csvURLs: csv, syncedPhotoDates: rows)
        XCTAssertEqual(ordered, ["https://x/first.jpg", "https://x/second.jpg"])
    }
}
