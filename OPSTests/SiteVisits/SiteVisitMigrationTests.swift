//
//  SiteVisitMigrationTests.swift
//  OPSTests
//
//  Proves the staged migration is safe for the `SiteVisit.opportunityId`
//  required→optional relaxation. A real shipped store sits at V10 with a NOT NULL
//  `opportunityId`; this test stands up that exact on-disk shape (the frozen
//  `OPSSchemaLegacySiteVisit.SiteVisit`), then reopens the same file with the
//  full migration plan and the current (V19) schema and asserts the row survives
//  with its `opportunityId` intact — and that the migrated store can now persist
//  an unlinked visit with a nil `opportunityId`. (The migrated store must be
//  opened at the CURRENT schema so the live `SiteVisit` type — which V15+
//  registers, and V11–V14 do NOT after the loggedActivityId version-scoping — is
//  the queryable entity.)
//

import XCTest
import SwiftData
@testable import OPS

final class SiteVisitMigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sitevisit-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("ops.store")
    }

    override func tearDownWithError() throws {
        if let dir = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func test_v10StoreMigratesToCurrent_preservingOpportunityIdAndAllowingUnlinkedVisit() throws {
        // 1. Stand up a V10 store with the frozen (required-opportunityId) shape,
        //    exactly as a shipped build wrote it, and seed one linked visit.
        try autoreleasepool {
            let v10Schema = Schema(versionedSchema: OPSSchemaV10.self)
            let v10Config = ModelConfiguration(schema: v10Schema, url: storeURL)
            let v10Container = try ModelContainer(for: v10Schema, configurations: v10Config)
            let context = ModelContext(v10Container)

            let legacyVisit = OPSSchemaLegacySiteVisit.SiteVisit(
                id: "visit-v10",
                opportunityId: "lead-123",
                companyId: "company-1",
                status: .scheduled
            )
            legacyVisit.address = "1100 Maple Ave"
            legacyVisit.assignedTo = "user-1"
            context.insert(legacyVisit)
            try context.save()
        }

        // 2. Reopen the SAME file with the full migration plan + CURRENT (V19)
        //    schema. This drives V10 → V11 (opportunityId becomes optional) → V12
        //    → V13 → V14 → V15 (adds loggedActivityId) → … → V19. Opening at V19 means the
        //    live `SiteVisit` type is the registered entity (V11–V14 register the
        //    frozen `OPSSchemaLegacySiteVisitV11.SiteVisit` after version-scoping).
        let currentSchema = Schema(versionedSchema: OPSSchemaV19.self)
        let currentConfig = ModelConfiguration(schema: currentSchema, url: storeURL)
        let migrated = try ModelContainer(
            for: currentSchema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: currentConfig
        )
        let context = ModelContext(migrated)

        // 3. The pre-existing linked visit survives with its opportunityId intact;
        //    the V15 loggedActivityId column defaults to nil for the historical row.
        let visits = try context.fetch(FetchDescriptor<SiteVisit>())
        XCTAssertEqual(visits.count, 1, "The V10 visit row must survive migration.")
        let migratedVisit = try XCTUnwrap(visits.first)
        XCTAssertEqual(migratedVisit.id, "visit-v10")
        XCTAssertEqual(migratedVisit.opportunityId, "lead-123", "opportunityId must be preserved across the required→optional relaxation.")
        XCTAssertEqual(migratedVisit.address, "1100 Maple Ave")
        XCTAssertEqual(migratedVisit.companyId, "company-1")
        XCTAssertNil(migratedVisit.loggedActivityId, "the V15 column defaults to nil for historical rows.")

        // 4. The migrated store can now persist an UNLINKED visit — the whole
        //    point of the optionality change.
        let unlinked = SiteVisit(
            id: "visit-unlinked",
            opportunityId: nil,
            companyId: "company-1",
            status: .scheduled
        )
        context.insert(unlinked)
        XCTAssertNoThrow(try context.save(), "An unlinked visit (nil opportunityId) must persist on the migrated store.")

        let all = try context.fetch(FetchDescriptor<SiteVisit>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.filter { $0.opportunityId == nil }.count, 1, "Exactly one unlinked visit should exist.")
    }

    func test_v14StoreMigratesToV15_preservingRowsAndAllowingLoggedActivityId() throws {
        // 1. Stand up a V14 store with the frozen V11–V14 SiteVisit shape (optional
        //    opportunityId, NO loggedActivityId), exactly as a pre-V15 build wrote
        //    it, and seed one completed linked visit.
        try autoreleasepool {
            let v14Schema = Schema(versionedSchema: OPSSchemaV14.self)
            let v14Config = ModelConfiguration(schema: v14Schema, url: storeURL)
            let v14Container = try ModelContainer(for: v14Schema, configurations: v14Config)
            let context = ModelContext(v14Container)

            let legacyVisit = OPSSchemaLegacySiteVisitV11.SiteVisit(
                id: "visit-v14",
                opportunityId: "lead-777",
                companyId: "company-1",
                status: .completed
            )
            legacyVisit.address = "88 Birch Rd"
            legacyVisit.notes = "Measured the back deck"
            context.insert(legacyVisit)
            try context.save()
        }

        // 2. Reopen the SAME file with the full migration plan + target V15
        //    schema. This isolates V14 → V15 (adds the nullable loggedActivityId).
        let v15Schema = Schema(versionedSchema: OPSSchemaV15.self)
        let v15Config = ModelConfiguration(schema: v15Schema, url: storeURL)
        let migrated = try ModelContainer(
            for: v15Schema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: v15Config
        )
        let context = ModelContext(migrated)

        // 3. The pre-existing visit survives with its fields intact; the new
        //    column defaults to nil for the historical row.
        let visits = try context.fetch(FetchDescriptor<SiteVisit>())
        XCTAssertEqual(visits.count, 1, "The V14 visit row must survive migration.")
        let migratedVisit = try XCTUnwrap(visits.first)
        XCTAssertEqual(migratedVisit.id, "visit-v14")
        XCTAssertEqual(migratedVisit.opportunityId, "lead-777", "opportunityId must be preserved.")
        XCTAssertEqual(migratedVisit.notes, "Measured the back deck")
        XCTAssertNil(migratedVisit.loggedActivityId, "the new column defaults to nil for historical rows.")

        // 4. The migrated (V15) store can now persist a loggedActivityId — the
        //    whole point of the widening (site-visit → timeline post idempotency).
        migratedVisit.loggedActivityId = "activity-abc"
        XCTAssertNoThrow(try context.save(), "A visit carrying a loggedActivityId must persist on the migrated store.")

        let reread = try XCTUnwrap(try context.fetch(FetchDescriptor<SiteVisit>()).first)
        XCTAssertEqual(reread.loggedActivityId, "activity-abc")
    }
}
