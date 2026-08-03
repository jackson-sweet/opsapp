//
//  SiteVisitMigrationTests.swift
//  OPSTests
//
//  Proves the staged migration is safe for the `SiteVisit.opportunityId`
//  required→optional relaxation. A real shipped store sits at V10 with a NOT NULL
//  `opportunityId`; this test stands up that exact on-disk shape (the frozen
//  `OPSSchemaLegacySiteVisit.SiteVisit`), then reopens the same file with the
//  full migration plan and the current (V22) schema and asserts the row survives
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

        // 2. Reopen the SAME file with the full migration plan + CURRENT (V22)
        //    schema. This drives V10 → V11 (opportunityId becomes optional) → V12
        //    → V13 → V14 → V15 (adds loggedActivityId) → … → V20 (cloud fields) →
        //    V21 → V22. Opening at V22 means the live `SiteVisit` type is the
        //    registered entity (V11–V14 register the frozen
        //    `OPSSchemaLegacySiteVisitV11.SiteVisit` after version-scoping).
        let currentSchema = Schema(versionedSchema: OPSSchemaV22.self)
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
        let visits = try context.fetch(FetchDescriptor<OPSSchemaLegacySiteVisitV19.SiteVisit>())
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

        let reread = try XCTUnwrap(
            try context.fetch(FetchDescriptor<OPSSchemaLegacySiteVisitV19.SiteVisit>()).first
        )
        XCTAssertEqual(reread.loggedActivityId, "activity-abc")
    }

    func test_v19StoreMigratesToV20_preservingEntireVisitPacketAndDefaultingCloudFields() throws {
        try assertV19PacketSurvivesMigration(openingAt: OPSSchemaV20.self)
    }

    /// The same released V19 packet opened directly at the CURRENT schema, so
    /// the two activity-feed widenings stacked above the cloud boundary are
    /// proven not to disturb a site-visit store on the way through.
    func test_v19StoreMigratesStraightToCurrent_preservingEntireVisitPacket() throws {
        try assertV19PacketSurvivesMigration(openingAt: OPSSchemaV22.self)
    }

    private func assertV19PacketSurvivesMigration(
        openingAt targetVersion: any VersionedSchema.Type
    ) throws {
        let target = "opened at \(targetVersion.versionIdentifier)"
        let visitID = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        let artifactID = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        let answerID = "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"
        let draftID = "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD"
        let companyID = "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE"

        try autoreleasepool {
            let sourceSchema = Schema(versionedSchema: OPSSchemaV19.self)
            let sourceConfiguration = ModelConfiguration(schema: sourceSchema, url: storeURL)
            let sourceContainer = try ModelContainer(
                for: sourceSchema,
                configurations: sourceConfiguration
            )
            let context = ModelContext(sourceContainer)

            let visit = OPSSchemaLegacySiteVisitV19.SiteVisit(
                id: visitID,
                opportunityId: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF",
                companyId: companyID,
                status: .completed,
                createdAt: Date(timeIntervalSince1970: 1_000)
            )
            visit.scheduledAt = Date(timeIntervalSince1970: 2_000)
            visit.completedAt = Date(timeIntervalSince1970: 3_000)
            visit.notes = "Existing visit notes"
            visit.loggedActivityId = "11111111-1111-4111-8111-111111111111"
            context.insert(visit)

            let artifact = SiteVisitCaptureArtifact(
                id: artifactID,
                siteVisitId: visitID,
                companyId: companyID,
                opportunityId: visit.opportunityId,
                kind: .photo,
                source: .camera,
                title: "North elevation",
                localAssetURL: "file:///visit/north.jpg",
                capturedAt: Date(timeIntervalSince1970: 2_100),
                createdBy: "user-1"
            )
            // The live initializer canonicalizes new IDs. Reapply the exact
            // released V19 values so this fixture still represents a real
            // historical store with uppercase identifiers.
            artifact.id = artifactID
            artifact.siteVisitId = visitID
            artifact.companyId = companyID
            artifact.opportunityId = visit.opportunityId
            context.insert(artifact)

            let answer = SiteVisitChecklistAnswer(
                id: answerID,
                siteVisitId: visitID,
                companyId: companyID,
                opportunityId: visit.opportunityId,
                siteVisitTypeId: "estimate",
                fieldId: "access",
                label: "Access",
                kind: .shortText,
                required: true,
                sortOrder: 10,
                answerValue: SiteVisitChecklistValue(text: "North gate"),
                createdBy: "user-1",
                createdAt: Date(timeIntervalSince1970: 2_200)
            )
            answer.id = answerID
            answer.siteVisitId = visitID
            answer.companyId = companyID
            answer.opportunityId = visit.opportunityId
            context.insert(answer)

            let draft = OPSSchemaLegacySiteVisitIdentityDraftV19.SiteVisitIdentityDraft(
                id: draftID,
                siteVisitId: visitID,
                companyId: companyID,
                opportunityId: visit.opportunityId,
                searchText: "temporary lookup",
                clientName: "North Shore Homes",
                contactName: "Helen Calloway",
                preferredEmail: "helen@example.com",
                address: "88 Birch Rd",
                createdAt: Date(timeIntervalSince1970: 1_900)
            )
            context.insert(draft)
            try context.save()
        }

        let targetSchema = Schema(versionedSchema: targetVersion)
        let targetConfiguration = ModelConfiguration(schema: targetSchema, url: storeURL)
        let migratedContainer = try ModelContainer(
            for: targetSchema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: targetConfiguration
        )
        let context = ModelContext(migratedContainer)

        let visit = try XCTUnwrap(try context.fetch(FetchDescriptor<SiteVisit>()).first, target)
        XCTAssertEqual(visit.id, visitID, "Migration must preserve historical uppercase ids; recovery canonicalizes them later — \(target)")
        XCTAssertEqual(visit.notes, "Existing visit notes", target)
        XCTAssertEqual(visit.loggedActivityId, "11111111-1111-4111-8111-111111111111", target)
        XCTAssertNil(visit.projectId, target)
        XCTAssertNil(visit.projectRef, target)
        XCTAssertNil(visit.clientId, target)
        XCTAssertNil(visit.clientRef, target)
        XCTAssertEqual(visit.durationMinutes, 60, target)
        XCTAssertEqual(visit.assigneeIds, [], target)
        XCTAssertEqual(visit.photos, [], target)
        XCTAssertFalse(visit.needsSync, target)
        XCTAssertNil(visit.lastSyncedAt, target)
        XCTAssertNil(visit.deletedAt, target)

        let artifact = try XCTUnwrap(try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).first, target)
        XCTAssertEqual(artifact.id, artifactID, target)
        XCTAssertEqual(artifact.title, "North elevation", target)
        XCTAssertEqual(artifact.localAssetURL, "file:///visit/north.jpg", target)

        let answer = try XCTUnwrap(try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first, target)
        XCTAssertEqual(answer.id, answerID, target)
        XCTAssertEqual(answer.answerValue.text, "North gate", target)

        let draft = try XCTUnwrap(try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).first, target)
        XCTAssertEqual(draft.id, draftID, target)
        XCTAssertEqual(draft.searchText, "temporary lookup", target)
        XCTAssertEqual(draft.clientName, "North Shore Homes", target)
        XCTAssertFalse(draft.needsSync, target)
        XCTAssertNil(draft.lastSyncedAt, target)
        XCTAssertNil(draft.deletedAt, target)
    }
}
