//
//  ActivityMigrationTests.swift
//  OPSTests
//
//  Proves the V13→V14 staged migration is safe for the `Activity` widening —
//  `opportunityId` required→optional plus the new nullable `clientId`/`projectId`
//  (unified-activity parents). A real shipped store sits at V13 with a NOT NULL
//  `opportunityId` and no client/project columns; this test stands up that exact
//  on-disk shape (the frozen `OPSSchemaLegacyActivity.Activity`), then reopens
//  the same file with the full migration plan and the V14 schema and
//  asserts the row survives with its `opportunityId` intact — and that the
//  migrated store can now persist a client- or job-parented activity with a nil
//  `opportunityId`.
//
//  This is the direct analogue of `SiteVisitMigrationTests` and is the evidence
//  that version-scoping `Activity` (frozen legacy model + widened V14 model)
//  opens an existing store without NSCocoaErrorDomain 134110 or a
//  "Duplicate version checksums across stages" crash.
//

import XCTest
import SwiftData
@testable import OPS

final class ActivityMigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("activity-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("ops.store")
    }

    override func tearDownWithError() throws {
        if let dir = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func test_v13StoreMigratesToV14_preservingOpportunityIdAndAllowingClientAndJobParents() throws {
        // 1. Stand up a V13 store with the frozen (required-opportunityId,
        //    no client/project) Activity shape, exactly as a shipped build wrote
        //    it, and seed one opportunity-linked activity.
        try autoreleasepool {
            let v13Schema = Schema(versionedSchema: OPSSchemaV13.self)
            let v13Config = ModelConfiguration(schema: v13Schema, url: storeURL)
            let v13Container = try ModelContainer(for: v13Schema, configurations: v13Config)
            let context = ModelContext(v13Container)

            let legacyActivity = OPSSchemaLegacyActivity.Activity(
                id: "act-v13",
                opportunityId: "lead-123",
                companyId: "company-1",
                type: .note
            )
            legacyActivity.bodyText = "Quote sent"
            legacyActivity.createdBy = "user-1"
            context.insert(legacyActivity)
            try context.save()
        }

        // 2. Reopen the SAME file with the full migration plan + V14 schema.
        //    This drives V13 → V14 (opportunityId becomes optional; clientId /
        //    projectId columns are added).
        let v14Schema = Schema(versionedSchema: OPSSchemaV14.self)
        let v14Config = ModelConfiguration(schema: v14Schema, url: storeURL)
        let migrated = try ModelContainer(
            for: v14Schema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: v14Config
        )
        let context = ModelContext(migrated)

        // 3. The pre-existing opportunity-linked activity survives with its
        //    opportunityId intact, and the new columns default to nil.
        let activities = try context.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(activities.count, 1, "The V13 activity row must survive migration.")
        let migratedActivity = try XCTUnwrap(activities.first)
        XCTAssertEqual(migratedActivity.id, "act-v13")
        XCTAssertEqual(migratedActivity.opportunityId, "lead-123",
                       "opportunityId must be preserved across the required→optional relaxation.")
        XCTAssertNil(migratedActivity.clientId, "New clientId column defaults to nil for historical rows.")
        XCTAssertNil(migratedActivity.projectId, "New projectId column defaults to nil for historical rows.")
        XCTAssertEqual(migratedActivity.bodyText, "Quote sent")
        XCTAssertEqual(migratedActivity.createdBy, "user-1")
        XCTAssertEqual(migratedActivity.companyId, "company-1")

        // 4. The migrated (V14) store can now persist a CLIENT-parented activity
        //    (nil opportunityId, set clientId) — the point of the widening.
        let clientActivity = Activity(
            id: "act-client",
            opportunityId: nil,
            companyId: "company-1",
            type: .note
        )
        clientActivity.clientId = "client-99"
        clientActivity.bodyText = "Left voicemail with client"
        context.insert(clientActivity)
        XCTAssertNoThrow(try context.save(),
                         "A client-parented activity (nil opportunityId, set clientId) must persist on the migrated store.")

        // 5. And a JOB-parented activity (projectId set).
        let jobActivity = Activity(
            id: "act-job",
            opportunityId: nil,
            companyId: "company-1",
            type: .note
        )
        jobActivity.projectId = "job-77"
        context.insert(jobActivity)
        XCTAssertNoThrow(try context.save(),
                         "A job-parented activity (nil opportunityId, set projectId) must persist on the migrated store.")

        let all = try context.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.filter { $0.opportunityId == nil }.count, 2,
                       "Two client/job-parented activities should have a nil opportunityId.")
        XCTAssertEqual(all.first(where: { $0.id == "act-client" })?.clientId, "client-99")
        XCTAssertEqual(all.first(where: { $0.id == "act-job" })?.projectId, "job-77")
    }
}
