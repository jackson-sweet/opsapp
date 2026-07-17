//
//  VinylOrderMarkerMigrationTests.swift
//  OPSTests
//
//  Guards the V16 → V17 schema boundary. `ProjectVinylOrderMarker` gained
//  `vinylColor` / `vinylPO` (projections of `projects.vinyl_color` /
//  `vinyl_po`) after V16 had shipped, so V7–V16 must keep the frozen
//  pre-widening marker shape and historical stores must migrate forward
//  without losing marker rows.
//

import SwiftData
import XCTest
@testable import OPS

final class VinylOrderMarkerMigrationTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vinyl-marker-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("ops.store")
    }

    override func tearDownWithError() throws {
        if let directory = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testReleasedSchemasDoNotReferenceWidenedLiveMarker() {
        let releasedSchemas: [any VersionedSchema.Type] = [
            OPSSchemaV7.self,
            OPSSchemaV10.self,
            OPSSchemaV16.self
        ]
        for schema in releasedSchemas {
            XCTAssertFalse(
                contains(ProjectVinylOrderMarker.self, in: schema),
                "\(schema) must keep the marker shape shipped before vinylColor/vinylPO were added"
            )
        }
        XCTAssertTrue(
            contains(ProjectVinylOrderMarker.self, in: OPSSchemaV17.self),
            "V17 carries the live widened marker"
        )
    }

    func testV16StoreMigratesToV17PreservingVinylOrderMarker() throws {
        let projectId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        let orderedAt = Date(timeIntervalSince1970: 1_784_800_000)

        try autoreleasepool {
            let v16Schema = Schema(versionedSchema: OPSSchemaV16.self)
            let v16Configuration = ModelConfiguration(schema: v16Schema, url: storeURL)
            let v16Container = try ModelContainer(
                for: v16Schema,
                configurations: v16Configuration
            )
            let context = ModelContext(v16Container)

            let marker = OPSSchemaLegacyVinylOrderV16.ProjectVinylOrderMarker(
                projectId: projectId,
                status: .ordered,
                orderedAt: orderedAt,
                orderedBy: "user-1",
                sourceProjectUpdatedAt: orderedAt
            )
            marker.lastSyncedAt = orderedAt
            context.insert(marker)
            try context.save()
        }

        let v17Schema = Schema(versionedSchema: OPSSchemaV17.self)
        let v17Configuration = ModelConfiguration(schema: v17Schema, url: storeURL)
        let migrated = try ModelContainer(
            for: v17Schema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: v17Configuration
        )
        let context = ModelContext(migrated)

        let markers = try context.fetch(FetchDescriptor<ProjectVinylOrderMarker>())
        XCTAssertEqual(markers.count, 1, "Every marker row must survive the V16→V17 migration")
        let marker = try XCTUnwrap(markers.first)
        XCTAssertEqual(marker.projectId, projectId)
        XCTAssertEqual(marker.status, .ordered)
        XCTAssertEqual(marker.orderedAt, orderedAt)
        XCTAssertEqual(marker.orderedBy, "user-1")
        XCTAssertNil(marker.vinylColor, "New color defaults nil for historical rows")
        XCTAssertNil(marker.vinylPO, "New PO defaults nil for historical rows")

        marker.vinylColor = "68mil Cobblestone"
        marker.vinylPO = "PO 6836 Mark Ln"
        XCTAssertNoThrow(try context.save(), "V17 fields must persist after migration")
    }

    private func contains(
        _ model: any PersistentModel.Type,
        in schema: any VersionedSchema.Type
    ) -> Bool {
        schema.models.contains { ObjectIdentifier($0) == ObjectIdentifier(model) }
    }
}
