//
//  ProjectGalleryFilterTests.swift
//  OPSTests
//
//  Regression: deck-builder 3D render snapshots (project_photos.source =
//  "deck_design") were leaking into the project photo carousel as blank tiles
//  because the gallery merge included every project_photos row regardless of
//  source. The gallery must show only real photos.
//

import SwiftData
import XCTest
@testable import OPS

final class ProjectGalleryFilterTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ProjectPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func photo(_ url: String, source: String, deletedAt: Date? = nil) -> ProjectPhoto {
        let p = ProjectPhoto(projectId: "proj", companyId: "co", url: url, source: source, uploadedBy: "user")
        p.deletedAt = deletedAt
        return p
    }

    @MainActor
    func test_galleryURLs_excludesDeckRenders_keepsRealPhotos() throws {
        // Register the schema so @Model property access works; galleryURLs()
        // operates on the in-memory array directly, so no insert is needed
        // (and inserting into a non-retained container's context crashes).
        let container = try makeContainer()
        _ = container
        let rows = [
            photo("https://s3/projects/co/proj/a.jpg", source: "in_progress"),
            photo("https://s3/deck_designs/co/r1.jpg", source: "deck_design"),
            photo("https://s3/projects/co/proj/b.jpg", source: "measurement"),
            photo("https://s3/deck_designs/co/r2.jpg", source: "deck_design"),
            photo("https://s3/projects/co/proj/c.jpg", source: "in_progress")
        ]

        let urls = rows.galleryURLs()

        XCTAssertEqual(urls, [
            "https://s3/projects/co/proj/a.jpg",
            "https://s3/projects/co/proj/b.jpg",   // measurement photos ARE real gallery photos
            "https://s3/projects/co/proj/c.jpg"
        ])
        XCTAssertFalse(urls.contains { $0.contains("deck_designs") }, "deck renders must never reach the gallery")
    }

    @MainActor
    func test_isGalleryEligible_perSource() throws {
        _ = try makeContainer()
        XCTAssertTrue(photo("u", source: "in_progress").isGalleryEligible)
        XCTAssertTrue(photo("u", source: "measurement").isGalleryEligible)
        XCTAssertFalse(photo("u", source: "deck_design").isGalleryEligible)
        XCTAssertFalse(photo("u", source: "in_progress", deletedAt: Date()).isGalleryEligible,
                       "soft-deleted photos are never gallery-eligible")
    }
}
