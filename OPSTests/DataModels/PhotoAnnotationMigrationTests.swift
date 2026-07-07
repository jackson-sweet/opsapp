//
//  PhotoAnnotationMigrationTests.swift
//  OPSTests
//
//  Proves the V14->V15 staged migration is safe for the `PhotoAnnotation`
//  retry-hygiene widening — the two columns `syncFailureCount` (Int, defaulted)
//  and `syncParkedAt` (Date?) that were added to the live model in-place after
//  V10 shipped. Those columns were widened inside `unchangedModels`, which would
//  have shifted V10's persistent fingerprint and destructively wiped real shipped
//  stores; version-scoping (frozen `OPSSchemaLegacyPhotoAnnotation.PhotoAnnotation`
//  for V1-V14, live for V15+) restores the shipped fingerprint. This test stands
//  up the exact frozen on-disk shape a shipped device carries, reopens the same
//  file with the full migration plan + the current (V15) schema, and asserts the
//  row survives with its fields intact and the new columns default for the
//  historical row — i.e. no NSCocoaErrorDomain 134110 and no store wipe.
//

import XCTest
import SwiftData
@testable import OPS

final class PhotoAnnotationMigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("photoannotation-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("ops.store")
    }

    override func tearDownWithError() throws {
        if let dir = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func test_v14StoreMigratesToV15_preservingRowsAndDefaultingRetryColumns() throws {
        // 1. Stand up a V14 store with the frozen (pre-retry-hygiene) PhotoAnnotation
        //    shape, exactly as a shipped build wrote it, and seed one annotation.
        try autoreleasepool {
            let v14Schema = Schema(versionedSchema: OPSSchemaV14.self)
            let v14Config = ModelConfiguration(schema: v14Schema, url: storeURL)
            let v14Container = try ModelContainer(for: v14Schema, configurations: v14Config)
            let context = ModelContext(v14Container)

            let legacy = OPSSchemaLegacyPhotoAnnotation.PhotoAnnotation(
                id: "anno-v14",
                projectId: "proj-1",
                companyId: "company-1",
                photoURL: "https://s3/photo.heic",
                authorId: "user-1"
            )
            legacy.note = "Cracked flashing on the north edge"
            legacy.annotationURL = "https://s3/overlay.png"
            legacy.localDrawingData = Data([0x01, 0x02, 0x03])
            context.insert(legacy)
            try context.save()
        }

        // 2. Reopen the SAME file with the full migration plan + current (V15)
        //    schema. This drives V14 -> V15 (adds syncFailureCount + syncParkedAt).
        let v15Schema = Schema(versionedSchema: OPSSchemaV15.self)
        let v15Config = ModelConfiguration(schema: v15Schema, url: storeURL)
        let migrated = try ModelContainer(
            for: v15Schema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: v15Config
        )
        let context = ModelContext(migrated)

        // 3. The pre-existing annotation survives with its fields intact; the new
        //    columns default for the historical row (Int -> 0, Date? -> nil).
        let annotations = try context.fetch(FetchDescriptor<PhotoAnnotation>())
        XCTAssertEqual(annotations.count, 1, "The V14 annotation row must survive migration.")
        let migratedAnnotation = try XCTUnwrap(annotations.first)
        XCTAssertEqual(migratedAnnotation.id, "anno-v14")
        XCTAssertEqual(migratedAnnotation.projectId, "proj-1")
        XCTAssertEqual(migratedAnnotation.companyId, "company-1")
        XCTAssertEqual(migratedAnnotation.note, "Cracked flashing on the north edge")
        XCTAssertEqual(migratedAnnotation.annotationURL, "https://s3/overlay.png")
        XCTAssertEqual(migratedAnnotation.localDrawingData, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(migratedAnnotation.syncFailureCount, 0, "New defaulted column is 0 for historical rows.")
        XCTAssertNil(migratedAnnotation.syncParkedAt, "New optional column is nil for historical rows.")

        // 4. The migrated (V15) store can now persist the retry-hygiene fields.
        migratedAnnotation.syncFailureCount = 3
        migratedAnnotation.syncParkedAt = Date(timeIntervalSince1970: 2_000)
        XCTAssertNoThrow(try context.save(), "The widened annotation must persist on the migrated store.")

        let reread = try XCTUnwrap(try context.fetch(FetchDescriptor<PhotoAnnotation>()).first)
        XCTAssertEqual(reread.syncFailureCount, 3)
        XCTAssertEqual(reread.syncParkedAt, Date(timeIntervalSince1970: 2_000))
    }
}
