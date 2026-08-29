//
//  ProjectPhotoUploaderAttributionMapTests.swift
//  OPSTests
//
//  iOS bug sweep 2026-08-28 (Cluster D) — the ownership half of the photo
//  delete gate, built one way for every surface.
//
//  `ProjectPhotoDeleteAuthorization` decides who may delete; the matrix it
//  applies is proven in `ProjectPhotoDeleteAuthorizationTests`. What is proven
//  HERE is the step before it: turning this device's `project_photos` rows into
//  the per-URL attribution the gate reads. Two surfaces offer a photo delete —
//  `ActivityTabView`'s edit-mode badges and `ProjectPhotosGrid`'s long press —
//  and each used to build that map itself, which is exactly how two surfaces
//  drift into disagreeing about the same photo. They now share
//  `ProjectPhotoUploaderAttribution.byURL`.
//
//  The collapse rule is the load-bearing part: ONE statement soft-deletes every
//  row on a URL, so the trigger must accept them all. Rows that disagree about
//  who uploaded the photo are undeletable, and the map must say so rather than
//  picking a winner and offering a delete the server will refuse.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class ProjectPhotoUploaderAttributionMapTests: XCTestCase {

    // Lowercase — Postgres uuid columns are lowercase.
    private let projectId = "7e4d418e-6a0c-4ec6-865b-bef70bc57fe6"
    private let companyId = "0a887c18-0000-4832-97f0-f302dcae2e9d"
    private let operatorID = "283d49df-90a1-4abb-b94c-3e9f17f02c0d"
    private let teammateID = "9f2c1b84-77a1-4e5c-8d3a-6b0e2f7a4c11"

    private let urlA = "https://ops-media.s3.amazonaws.com/photos/a.jpg"
    private let urlB = "https://ops-media.s3.amazonaws.com/photos/b.jpg"

    /// The ordinary case: one row per URL, attribution resolved and normalized.
    func testResolvesUploaderPerURL() throws {
        let context = try makeContext()
        let mine = insertPhoto(url: urlA, uploadedBy: operatorID, into: context)
        let theirs = insertPhoto(url: urlB, uploadedBy: teammateID, into: context)

        let map = ProjectPhotoUploaderAttribution.byURL([mine, theirs])

        XCTAssertEqual(map[urlA], .known(operatorID))
        XCTAssertEqual(map[urlB], .known(teammateID))
    }

    /// `uploaded_by` is TEXT and legacy iOS rows wrote UPPERCASE UUIDs. The
    /// trigger compares `lower()`, so the map must normalize the same way or an
    /// operator loses the delete on their own photo.
    func testNormalizesUploaderCasing() throws {
        let context = try makeContext()
        let row = insertPhoto(url: urlA, uploadedBy: operatorID.uppercased(), into: context)

        XCTAssertEqual(ProjectPhotoUploaderAttribution.byURL([row])[urlA], .known(operatorID))
    }

    /// The server writes the literal `'system'` on ingested photos. It can never
    /// equal an operator id, so it must read as unmatchable — NOT as missing,
    /// which would hand it the unattributed fallback and offer a delete the
    /// trigger rejects for everyone below scope `all`.
    func testSystemSentinelIsUnmatchable() throws {
        let context = try makeContext()
        let row = insertPhoto(url: urlA, uploadedBy: "system", into: context)

        XCTAssertEqual(ProjectPhotoUploaderAttribution.byURL([row])[urlA], .unmatchable)
    }

    /// Duplicate rows that agree are still that uploader — collapsing to
    /// unmatchable here would strip a crew member's delete on their own photo.
    func testAgreeingDuplicateRowsKeepTheirUploader() throws {
        let context = try makeContext()
        let first = insertPhoto(url: urlA, uploadedBy: operatorID, into: context)
        let second = insertPhoto(url: urlA, uploadedBy: operatorID.uppercased(), into: context)

        XCTAssertEqual(
            ProjectPhotoUploaderAttribution.byURL([first, second])[urlA],
            .known(operatorID),
            "Same uploader in different casing is the same uploader"
        )
    }

    /// The load-bearing rule: one statement covers every row on the URL, so a
    /// URL whose rows disagree is undeletable by anyone below scope `all`.
    func testDisagreeingRowsOnOneURLCollapseToUnmatchable() throws {
        let context = try makeContext()
        let mine = insertPhoto(url: urlA, uploadedBy: operatorID, into: context)
        let theirs = insertPhoto(url: urlA, uploadedBy: teammateID, into: context)

        XCTAssertEqual(ProjectPhotoUploaderAttribution.byURL([mine, theirs])[urlA], .unmatchable)
    }

    /// A real row plus a system-written row on the same URL is the same
    /// disagreement, and must not resolve to the real uploader.
    func testKnownAndSystemRowsOnOneURLCollapseToUnmatchable() throws {
        let context = try makeContext()
        let mine = insertPhoto(url: urlA, uploadedBy: operatorID, into: context)
        let ingested = insertPhoto(url: urlA, uploadedBy: "system", into: context)

        XCTAssertEqual(ProjectPhotoUploaderAttribution.byURL([mine, ingested])[urlA], .unmatchable)
    }

    /// A URL with no row is absent, not `.unattributed` — the fallback is the
    /// caller's, so a surface that wants to fail closed can tell the two apart.
    func testURLsWithoutRowsAreAbsent() throws {
        let context = try makeContext()
        let row = insertPhoto(url: urlA, uploadedBy: operatorID, into: context)

        let map = ProjectPhotoUploaderAttribution.byURL([row])

        XCTAssertNil(map[urlB])
        XCTAssertEqual(map.count, 1)
    }

    /// No rows at all — an empty gallery, or a device that has not pulled yet.
    func testEmptyInputProducesEmptyMap() {
        XCTAssertTrue(ProjectPhotoUploaderAttribution.byURL([]).isEmpty)
    }

    // MARK: - Fixtures

    @discardableResult
    private func insertPhoto(
        url: String,
        uploadedBy: String,
        into context: ModelContext
    ) -> ProjectPhoto {
        let photo = ProjectPhoto(
            id: UUID().uuidString.lowercased(),
            projectId: projectId,
            companyId: companyId,
            url: url,
            source: "site_visit",
            uploadedBy: uploadedBy
        )
        context.insert(photo)
        try? context.save()
        return photo
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ProjectPhoto.self, PhotoAnnotation.self, SyncOperation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Containers outlive the contexts they vend, for the whole test case — a
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try makeContainer()
        retainedContainers.append(container)
        return container.mainContext
    }
}
