//
//  PhotoGalleryAttributionTests.swift
//  OPSTests
//
//  Regression: Settings > Photos used PhotoAnnotation.authorId as the uploader.
//  Annotation authors own markup and notes; project_photos.uploaded_by owns the
//  photo. These tests lock that identity boundary and its legacy fallback.
//

import SwiftData
import XCTest
@testable import OPS

final class PhotoGalleryAttributionTests: XCTestCase {

    private let uploaderA = "283d49df-90a1-4abb-b94c-3e9f17f02c0d"
    private let annotatorB = "7d4fbe1c-a25c-421e-9987-875776b8c831"

    private func registerModels() throws {
        let schema = Schema([ProjectPhoto.self, PhotoAnnotation.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        _ = try ModelContainer(for: schema, configurations: [config])
    }

    private func photo(
        id: String = UUID().uuidString,
        projectId: String = "project-a",
        companyId: String = "company-a",
        url: String = "https://photos.test/shared.jpg",
        uploadedBy: String? = nil,
        takenAt: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_000),
        source: String = "in_progress"
    ) -> ProjectPhoto {
        ProjectPhoto(
            id: id,
            projectId: projectId,
            companyId: companyId,
            url: url,
            source: source,
            uploadedBy: uploadedBy ?? uploaderA,
            takenAt: takenAt,
            createdAt: createdAt
        )
    }

    private func annotation(
        projectId: String = "project-a",
        companyId: String = "company-a",
        url: String = "https://photos.test/shared.jpg",
        authorId: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 2_000),
        note: String = "Site measurement confirmed"
    ) -> PhotoAnnotation {
        let model = PhotoAnnotation(
            projectId: projectId,
            companyId: companyId,
            photoURL: url,
            authorId: authorId ?? annotatorB,
            createdAt: createdAt
        )
        model.note = note
        return model
    }

    @MainActor
    func testCanonicalUploaderAndCaptureDateWinWhileAnnotationNoteRemains() throws {
        try registerModels()
        let captureDate = Date(timeIntervalSince1970: 1_500)
        let row = photo(takenAt: captureDate)
        let markup = annotation()
        let resolver = PhotoGalleryMetadataResolver(projectPhotos: [row], annotations: [markup])

        let metadata = resolver.metadata(
            projectId: "project-a",
            companyId: "company-a",
            url: row.url,
            legacyFallbackDate: Date(timeIntervalSince1970: 500)
        )

        XCTAssertEqual(metadata.uploaderId, uploaderA)
        XCTAssertEqual(metadata.date, captureDate)
        XCTAssertEqual(metadata.note, "Site measurement confirmed")
        XCTAssertNotEqual(metadata.uploaderId, annotatorB, "the person adding markup is never the uploader")
        XCTAssertTrue(PhotoGalleryMetadataResolver.matchesUploader(metadata.uploaderId, selectedIds: [uploaderA]))
        XCTAssertFalse(PhotoGalleryMetadataResolver.matchesUploader(metadata.uploaderId, selectedIds: [annotatorB]))
    }

    @MainActor
    func testLookupIsScopedByProjectAndCompanyWhenURLsCollide() throws {
        try registerModels()
        let wrongProject = photo(
            id: "wrong-project",
            projectId: "project-b",
            uploadedBy: annotatorB,
            takenAt: Date(timeIntervalSince1970: 9_000)
        )
        let wrongCompany = photo(
            id: "wrong-company",
            companyId: "company-b",
            uploadedBy: annotatorB,
            takenAt: Date(timeIntervalSince1970: 8_000)
        )
        let expected = photo(
            id: "expected",
            takenAt: Date(timeIntervalSince1970: 1_500)
        )
        let resolver = PhotoGalleryMetadataResolver(
            projectPhotos: [wrongProject, wrongCompany, expected],
            annotations: []
        )

        let metadata = resolver.metadata(
            projectId: "project-a",
            companyId: "company-a",
            url: expected.url,
            legacyFallbackDate: .distantPast
        )

        XCTAssertEqual(metadata.uploaderId, uploaderA)
        XCTAssertEqual(metadata.date, Date(timeIntervalSince1970: 1_500))
    }

    @MainActor
    func testProtocolRelativeGalleryURLResolvesCanonicalPhotoAndAnnotation() throws {
        try registerModels()
        let canonicalURL = "https://photos.test/aliased.jpg"
        let row = photo(url: canonicalURL)
        let markup = annotation(url: "//photos.test/aliased.jpg")
        let resolver = PhotoGalleryMetadataResolver(projectPhotos: [row], annotations: [markup])

        let metadata = resolver.metadata(
            projectId: row.projectId,
            companyId: row.companyId,
            url: "//photos.test/aliased.jpg",
            legacyFallbackDate: nil
        )

        XCTAssertEqual(metadata.uploaderId, uploaderA)
        XCTAssertEqual(metadata.note, markup.note)
        XCTAssertEqual(metadata.date, row.createdAt)
    }

    @MainActor
    func testLegacyPhotoKeepsNoteButNeverCreditsAnnotatorAsUploader() throws {
        try registerModels()
        let legacyDate = Date(timeIntervalSince1970: 700)
        let markup = annotation(createdAt: Date(timeIntervalSince1970: 2_000))
        let resolver = PhotoGalleryMetadataResolver(projectPhotos: [], annotations: [markup])

        let metadata = resolver.metadata(
            projectId: "project-a",
            companyId: "company-a",
            url: markup.photoURL,
            legacyFallbackDate: legacyDate
        )

        XCTAssertNil(metadata.uploaderId)
        XCTAssertEqual(metadata.date, markup.createdAt)
        XCTAssertEqual(metadata.note, markup.note)
        XCTAssertFalse(PhotoGalleryMetadataResolver.matchesUploader(metadata.uploaderId, selectedIds: [annotatorB]))
    }

    @MainActor
    func testLegacyPhotoWithoutAnyDateSignalRemainsUndated() throws {
        try registerModels()
        let resolver = PhotoGalleryMetadataResolver(projectPhotos: [], annotations: [])

        let metadata = resolver.metadata(
            projectId: "project-a",
            companyId: "company-a",
            url: "https://photos.test/migrated.jpg",
            legacyFallbackDate: nil
        )

        XCTAssertNil(metadata.date)
    }

    @MainActor
    func testMalformedUploaderIsNeverExposedAndCannotReplaceValidLocalIdentity() throws {
        try registerModels()
        let malformed = photo(uploadedBy: "not-a-user-id")
        let resolver = PhotoGalleryMetadataResolver(projectPhotos: [malformed], annotations: [])

        let metadata = resolver.metadata(
            projectId: malformed.projectId,
            companyId: malformed.companyId,
            url: malformed.url,
            legacyFallbackDate: .distantPast
        )

        XCTAssertNil(metadata.uploaderId)

        let existing = photo(uploadedBy: uploaderA)
        existing.applyInboundUploader("not-a-user-id", isProtected: false)
        XCTAssertEqual(existing.uploadedBy, uploaderA)
    }

    @MainActor
    func testInboundUploaderHealsBlankLocalRowButRespectsPendingLocalField() throws {
        try registerModels()
        let existing = photo(uploadedBy: "")

        existing.applyInboundUploader("  \(uploaderA.uppercased())  ", isProtected: false)
        XCTAssertEqual(existing.uploadedBy, uploaderA)

        existing.applyInboundUploader(annotatorB, isProtected: true)
        XCTAssertEqual(existing.uploadedBy, uploaderA)
    }
}
