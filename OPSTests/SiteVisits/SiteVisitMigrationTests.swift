//
//  SiteVisitMigrationTests.swift
//  OPSTests
//
//  Proves the V10→V12 staged migration is safe for the `SiteVisit.opportunityId`
//  required→optional relaxation. A real shipped store sits at V10 with a NOT NULL
//  `opportunityId`; this test stands up that exact on-disk shape (the frozen
//  `OPSSchemaLegacySiteVisit.SiteVisit`), then reopens the same file with the
//  full migration plan and the current (V12) schema and asserts the row survives
//  with its `opportunityId` intact — and that the migrated store can now persist
//  an unlinked visit with a nil `opportunityId`.
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

    func test_v10StoreMigratesToV12_preservingOpportunityIdAndAllowingUnlinkedVisit() throws {
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

        // 2. Reopen the SAME file with the full migration plan + current schema.
        //    This drives V10 → V11 (opportunityId becomes optional) → V12.
        let v12Schema = Schema(versionedSchema: OPSSchemaV12.self)
        let v12Config = ModelConfiguration(schema: v12Schema, url: storeURL)
        let migrated = try ModelContainer(
            for: v12Schema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: v12Config
        )
        let context = ModelContext(migrated)

        // 3. The pre-existing linked visit survives with its opportunityId intact.
        let visits = try context.fetch(FetchDescriptor<SiteVisit>())
        XCTAssertEqual(visits.count, 1, "The V10 visit row must survive migration.")
        let migratedVisit = try XCTUnwrap(visits.first)
        XCTAssertEqual(migratedVisit.id, "visit-v10")
        XCTAssertEqual(migratedVisit.opportunityId, "lead-123", "opportunityId must be preserved across the required→optional relaxation.")
        XCTAssertEqual(migratedVisit.address, "1100 Maple Ave")
        XCTAssertEqual(migratedVisit.companyId, "company-1")

        // 4. The migrated (V12) store can now persist an UNLINKED visit — the
        //    whole point of the optionality change.
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
}
