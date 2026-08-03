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
        //
        //    NOTE: V14's `Activity` is the FROZEN V14–V20 shape
        //    (`OPSSchemaLegacyActivityV19.Activity`), not the live model — the
        //    widened graph starts at V21, where the per-message email identity
        //    was added. A V14 container can only see the type V14 declares.
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
        let activities = try context.fetch(
            FetchDescriptor<OPSSchemaLegacyActivityV19.Activity>()
        )
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
        let clientActivity = OPSSchemaLegacyActivityV19.Activity(
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
        let jobActivity = OPSSchemaLegacyActivityV19.Activity(
            id: "act-job",
            opportunityId: nil,
            companyId: "company-1",
            type: .note
        )
        jobActivity.projectId = "job-77"
        context.insert(jobActivity)
        XCTAssertNoThrow(try context.save(),
                         "A job-parented activity (nil opportunityId, set projectId) must persist on the migrated store.")

        let all = try context.fetch(
            FetchDescriptor<OPSSchemaLegacyActivityV19.Activity>()
        )
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.filter { $0.opportunityId == nil }.count, 2,
                       "Two client/job-parented activities should have a nil opportunityId.")
        XCTAssertEqual(all.first(where: { $0.id == "act-client" })?.clientId, "client-99")
        XCTAssertEqual(all.first(where: { $0.id == "act-job" })?.projectId, "job-77")
    }

    /// V20 → V21 adds the per-message email identity. A store written by a V20
    /// build — the last released shape, cloud site visits and all — must open,
    /// keep every row, and default the five new identity columns.
    func test_v20StoreMigratesToV21_preservingTheRowAndDefaultingEmailIdentity() throws {
        try autoreleasepool {
            let v20Schema = Schema(versionedSchema: OPSSchemaV20.self)
            let v20Config = ModelConfiguration(schema: v20Schema, url: storeURL)
            let v20Container = try ModelContainer(for: v20Schema, configurations: v20Config)
            let context = ModelContext(v20Container)

            let released = OPSSchemaLegacyActivityV19.Activity(
                id: "act-v20",
                opportunityId: "lead-123",
                companyId: "company-1",
                type: .email
            )
            released.subject = "Re: Roof tear-off quote"
            released.direction = "inbound"
            released.bodyText = "Sending measurements tomorrow."
            released.createdBy = "user-1"
            context.insert(released)
            try context.save()
        }

        let v21Schema = Schema(versionedSchema: OPSSchemaV21.self)
        let v21Config = ModelConfiguration(schema: v21Schema, url: storeURL)
        let migrated = try ModelContainer(
            for: v21Schema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: v21Config
        )
        let context = ModelContext(migrated)

        let activities = try context.fetch(
            FetchDescriptor<OPSSchemaLegacyActivityV21.Activity>()
        )
        XCTAssertEqual(activities.count, 1, "The V20 activity row must survive migration.")
        let migratedActivity = try XCTUnwrap(activities.first)
        XCTAssertEqual(migratedActivity.id, "act-v20")
        XCTAssertEqual(migratedActivity.opportunityId, "lead-123")
        XCTAssertEqual(migratedActivity.subject, "Re: Roof tear-off quote")
        XCTAssertEqual(migratedActivity.direction, "inbound")
        XCTAssertEqual(migratedActivity.bodyText, "Sending measurements tomorrow.")
        XCTAssertEqual(migratedActivity.createdBy, "user-1")
        XCTAssertNil(migratedActivity.emailMessageId, "New identity columns default to nil.")
        XCTAssertNil(migratedActivity.emailThreadId, "New identity columns default to nil.")
        XCTAssertNil(migratedActivity.fromEmail, "New identity columns default to nil.")
        XCTAssertEqual(migratedActivity.toEmails, [], "New identity arrays default empty.")
        XCTAssertEqual(migratedActivity.ccEmails, [], "New identity arrays default empty.")

        migratedActivity.emailMessageId = "msg-1"
        migratedActivity.toEmails = ["dale@ops.test"]
        XCTAssertNoThrow(
            try context.save(),
            "The V21 email identity must persist on the migrated store."
        )
    }

    /// V21 → V22 adds the site-visit link. A store carrying email identity must
    /// open, keep every row and every identity field, default the new column to
    /// nil, and then persist a real link — the whole point of the widening.
    func test_v21StoreMigratesToV22_preservingEmailIdentityAndAddingTheSiteVisitLink() throws {
        try autoreleasepool {
            let v21Schema = Schema(versionedSchema: OPSSchemaV21.self)
            let v21Config = ModelConfiguration(schema: v21Schema, url: storeURL)
            let v21Container = try ModelContainer(for: v21Schema, configurations: v21Config)
            let context = ModelContext(v21Container)

            let legacy = OPSSchemaLegacyActivityV21.Activity(
                id: "act-v21",
                opportunityId: "lead-123",
                companyId: "company-1",
                type: .email
            )
            legacy.subject = "Re: Roof tear-off quote"
            legacy.direction = "inbound"
            legacy.emailMessageId = "msg-1"
            legacy.emailThreadId = "thread-1"
            legacy.fromEmail = "helen.calloway@example.com"
            legacy.toEmails = ["dale@ops.test"]
            legacy.ccEmails = ["office@ops.test"]
            context.insert(legacy)
            try context.save()
        }

        let v22Schema = Schema(versionedSchema: OPSSchemaV22.self)
        let v22Config = ModelConfiguration(schema: v22Schema, url: storeURL)
        let migrated = try ModelContainer(
            for: v22Schema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: v22Config
        )
        let context = ModelContext(migrated)

        let activities = try context.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(activities.count, 1, "The V21 activity row must survive migration.")
        let migratedActivity = try XCTUnwrap(activities.first)
        XCTAssertEqual(migratedActivity.id, "act-v21")
        XCTAssertEqual(migratedActivity.opportunityId, "lead-123")
        XCTAssertEqual(migratedActivity.subject, "Re: Roof tear-off quote")
        XCTAssertEqual(migratedActivity.direction, "inbound")
        XCTAssertEqual(migratedActivity.emailMessageId, "msg-1")
        XCTAssertEqual(migratedActivity.emailThreadId, "thread-1")
        XCTAssertEqual(migratedActivity.fromEmail, "helen.calloway@example.com")
        XCTAssertEqual(migratedActivity.toEmails, ["dale@ops.test"])
        XCTAssertEqual(migratedActivity.ccEmails, ["office@ops.test"])
        XCTAssertNil(
            migratedActivity.siteVisitId,
            "The additive V22 link must default to nil for V21 rows."
        )

        migratedActivity.siteVisitId = "visit-77"
        try context.save()

        let rereadContext = ModelContext(migrated)
        let reread = try XCTUnwrap(
            try rereadContext.fetch(FetchDescriptor<Activity>()).first
        )
        XCTAssertEqual(
            reread.siteVisitId,
            "visit-77",
            "The V22 site-visit link must persist after the migration."
        )
    }

    /// The whole chain in one hop, from the last shape a released build could
    /// have written before either widening landed: a V20 store opened directly
    /// at the current schema must traverse both new stages and keep its row.
    func test_v20StoreMigratesStraightToCurrent_withoutLosingTheActivity() throws {
        try autoreleasepool {
            let v20Schema = Schema(versionedSchema: OPSSchemaV20.self)
            let v20Config = ModelConfiguration(schema: v20Schema, url: storeURL)
            let v20Container = try ModelContainer(for: v20Schema, configurations: v20Config)
            let context = ModelContext(v20Container)

            let released = OPSSchemaLegacyActivityV19.Activity(
                id: "act-v20-direct",
                opportunityId: "lead-456",
                companyId: "company-1",
                type: .note
            )
            released.bodyText = "Walked the roof with the owner."
            context.insert(released)
            try context.save()
        }

        let currentSchema = Schema(versionedSchema: OPSSchemaV22.self)
        let currentConfig = ModelConfiguration(schema: currentSchema, url: storeURL)
        let migrated = try ModelContainer(
            for: currentSchema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: currentConfig
        )
        let context = ModelContext(migrated)

        let activities = try context.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(activities.count, 1, "The V20 activity row must survive both stages.")
        let migratedActivity = try XCTUnwrap(activities.first)
        XCTAssertEqual(migratedActivity.id, "act-v20-direct")
        XCTAssertEqual(migratedActivity.opportunityId, "lead-456")
        XCTAssertEqual(migratedActivity.bodyText, "Walked the roof with the owner.")
        XCTAssertNil(migratedActivity.emailMessageId)
        XCTAssertEqual(migratedActivity.toEmails, [])
        XCTAssertNil(migratedActivity.siteVisitId)
    }

    func test_releasedSchemasDoNotReferenceTheWidenedLiveActivity() {
        XCTAssertFalse(
            OPSSchemaV20.models.contains { $0 == Activity.self },
            "V20 must keep the Activity shape released before email identity was added"
        )
        XCTAssertTrue(
            OPSSchemaV20.models.contains { $0 == OPSSchemaLegacyActivityV19.Activity.self },
            "V20 must register the frozen V14–V20 Activity shape"
        )
        XCTAssertFalse(
            OPSSchemaV21.models.contains { $0 == Activity.self },
            "V21 must keep the Activity shape that predates siteVisitId"
        )
        XCTAssertTrue(
            OPSSchemaV21.models.contains { $0 == OPSSchemaLegacyActivityV21.Activity.self },
            "V21 must register its frozen email-identity Activity shape"
        )
        XCTAssertTrue(
            OPSSchemaV22.models.contains { $0 == Activity.self },
            "V22 must register the widened live Activity"
        )
    }
}
