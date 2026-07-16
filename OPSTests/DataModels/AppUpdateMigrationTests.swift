//
//  AppUpdateMigrationTests.swift
//  OPSTests
//
//  Guards the released SwiftData schema graph used during in-place app updates.
//

import CoreData
import SwiftData
import XCTest
@testable import OPS

final class AppUpdateMigrationTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-update-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("ops.store")
    }

    override func tearDownWithError() throws {
        if let directory = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testReleasedV15DoesNotReferenceWidenedLiveModels() {
        XCTAssertFalse(
            contains(Opportunity.self, in: OPSSchemaV15.self),
            "V15 must keep the Opportunity shape shipped before images and coordinates were added"
        )
        XCTAssertFalse(
            contains(DeckDesign.self, in: OPSSchemaV15.self),
            "V15 must keep the DeckDesign shape shipped before opportunityId was added"
        )
    }

    func testAppUpdateChangesHaveMigrationBoundaryAfterV15() {
        XCTAssertGreaterThan(
            OPSMigrationPlan.schemas.count,
            15,
            "Persisted fields added after V15 require a new versioned schema"
        )
        XCTAssertGreaterThan(
            OPSMigrationPlan.stages.count,
            14,
            "The post-V15 schema requires an adjacent migration stage"
        )
    }

    func testDeclaredSchemaChecksumsStayImmutable() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/swiftdata-released-schema-fingerprints.json")
        let expected = try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: fixtureURL)
        )

        var actual: [String: String] = [:]
        for releasedSchema in OPSMigrationPlan.schemas {
            let version = String(describing: releasedSchema.versionIdentifier)
            actual[version] = try fingerprint(of: releasedSchema, version: version)
        }

        XCTAssertEqual(
            actual,
            expected,
            "Declared SwiftData schemas are immutable. Freeze a changed model under its released shape, then add a new schema and adjacent migration stage."
        )
        XCTAssertEqual(
            Set(actual.values).count,
            actual.count,
            "Every declared schema needs a distinct Core Data compatibility checksum"
        )
    }

    func testV15StoreMigratesToV16PreservingOpportunityAndDeckDesign() throws {
        try assertOpportunityAndDeckDesignMigration(from: OPSSchemaV15.self, sourceLabel: "v15")
    }

    func testV10StoreMigratesToV16PreservingOpportunityAndDeckDesign() throws {
        try assertOpportunityAndDeckDesignMigration(from: OPSSchemaV10.self, sourceLabel: "v10")
    }

    func testProductionStoreConfigurationPinsThePrimaryAppGroup() {
        XCTAssertEqual(
            OPSModelStore.appGroupIdentifier(isStoredInMemoryOnly: false),
            AppGroupConfig.identifier
        )
    }

    func testHostedTestStoreStaysInMemoryWithoutAppGroupStorage() {
        let schema = Schema(versionedSchema: OPSSchemaV16.self)
        let configuration = OPSModelStore.configuration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        XCTAssertTrue(configuration.isStoredInMemoryOnly)
        XCTAssertNil(configuration.groupAppContainerIdentifier)
    }

    func testCopiedDeviceV15StoreMigratesToV16WithoutLosingRows() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["OPS_V15_STORE_FIXTURE_DIR"] else {
            throw XCTSkip("Set OPS_V15_STORE_FIXTURE_DIR to run the real-device-store migration proof")
        }

        let fixtureDirectory = URL(fileURLWithPath: fixturePath, isDirectory: true)
        let sourceStore = fixtureDirectory.appendingPathComponent("default.store")
        guard FileManager.default.fileExists(atPath: sourceStore.path) else {
            XCTFail("Missing default.store in OPS_V15_STORE_FIXTURE_DIR")
            return
        }

        for suffix in ["", "-wal", "-shm"] {
            let source = fixtureDirectory.appendingPathComponent("default.store\(suffix)")
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(
                at: source,
                to: URL(fileURLWithPath: storeURL.path + suffix)
            )
        }

        var legacyOpportunityCount = 0
        var legacyDeckCount = 0
        try autoreleasepool {
            let v15Schema = Schema(versionedSchema: OPSSchemaV15.self)
            let v15Configuration = ModelConfiguration(schema: v15Schema, url: storeURL)
            let v15Container = try ModelContainer(
                for: v15Schema,
                configurations: v15Configuration
            )
            let context = ModelContext(v15Container)
            legacyOpportunityCount = try context.fetchCount(
                FetchDescriptor<OPSSchemaLegacyOpportunityV15.Opportunity>()
            )
            legacyDeckCount = try context.fetchCount(
                FetchDescriptor<OPSSchemaLegacyDeckDesignV15.DeckDesign>()
            )
        }

        let currentSchema = Schema(versionedSchema: OPSSchemaV16.self)
        let currentConfiguration = ModelConfiguration(schema: currentSchema, url: storeURL)
        let migrated = try ModelContainer(
            for: currentSchema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: currentConfiguration
        )
        let context = ModelContext(migrated)

        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<Opportunity>()),
            legacyOpportunityCount,
            "Every opportunity row in the copied device store must survive"
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<DeckDesign>()),
            legacyDeckCount,
            "Every deck-design row in the copied device store must survive"
        )
    }

    private func contains(
        _ model: any PersistentModel.Type,
        in schema: any VersionedSchema.Type
    ) -> Bool {
        schema.models.contains { ObjectIdentifier($0) == ObjectIdentifier(model) }
    }

    private func fingerprint(
        of versionedSchema: any VersionedSchema.Type,
        version: String
    ) throws -> String {
        let url = storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("schema-\(version).store")
        let schema = Schema(versionedSchema: versionedSchema)
        let configuration = ModelConfiguration(
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )

        try autoreleasepool {
            _ = try ModelContainer(for: schema, configurations: configuration)
        }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: url
        )
        return try XCTUnwrap(
            metadata[NSPersistentStoreModelVersionChecksumKey] as? String,
            "Missing Core Data model checksum for released schema \(version)"
        )
    }

    private func assertOpportunityAndDeckDesignMigration(
        from sourceVersion: any VersionedSchema.Type,
        sourceLabel: String
    ) throws {
        let opportunityID = "lead-\(sourceLabel)"
        let deckID = "deck-\(sourceLabel)"

        try autoreleasepool {
            let sourceSchema = Schema(versionedSchema: sourceVersion)
            let sourceConfiguration = ModelConfiguration(schema: sourceSchema, url: storeURL)
            let sourceContainer = try ModelContainer(
                for: sourceSchema,
                configurations: sourceConfiguration
            )
            let context = ModelContext(sourceContainer)

            let opportunity = OPSSchemaLegacyOpportunityV15.Opportunity(
                id: opportunityID,
                companyId: "company-1",
                contactName: "Taylor Morgan",
                stage: .qualifying
            )
            opportunity.title = "North deck replacement"
            opportunity.address = "1100 Maple Ave"
            opportunity.estimatedValue = 24_500
            opportunity.tags = ["deck", "priority"]
            context.insert(opportunity)

            let deck = OPSSchemaLegacyDeckDesignV15.DeckDesign(
                id: deckID,
                companyId: "company-1",
                projectId: "project-1",
                title: "North deck concept",
                drawingDataJSON: "{\"version\":1}",
                createdBy: "user-1"
            )
            deck.thumbnailURL = "https://cdn.ops.test/deck.png"
            deck.needsSync = true
            context.insert(deck)

            try context.save()
        }

        let currentSchema = Schema(versionedSchema: OPSSchemaV16.self)
        let currentConfiguration = ModelConfiguration(schema: currentSchema, url: storeURL)
        let migratedContainer = try ModelContainer(
            for: currentSchema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: currentConfiguration
        )
        let context = ModelContext(migratedContainer)

        let opportunities = try context.fetch(FetchDescriptor<Opportunity>())
        XCTAssertEqual(opportunities.count, 1)
        let opportunity = try XCTUnwrap(opportunities.first)
        XCTAssertEqual(opportunity.id, opportunityID)
        XCTAssertEqual(opportunity.contactName, "Taylor Morgan")
        XCTAssertEqual(opportunity.title, "North deck replacement")
        XCTAssertEqual(opportunity.address, "1100 Maple Ave")
        XCTAssertEqual(opportunity.estimatedValue, 24_500)
        XCTAssertEqual(opportunity.tags, ["deck", "priority"])
        XCTAssertEqual(opportunity.images, [], "New collection defaults empty for historical rows")
        XCTAssertNil(opportunity.latitude, "New latitude defaults nil for historical rows")
        XCTAssertNil(opportunity.longitude, "New longitude defaults nil for historical rows")

        let decks = try context.fetch(FetchDescriptor<DeckDesign>())
        XCTAssertEqual(decks.count, 1)
        let deck = try XCTUnwrap(decks.first)
        XCTAssertEqual(deck.id, deckID)
        XCTAssertEqual(deck.projectId, "project-1")
        XCTAssertEqual(deck.title, "North deck concept")
        XCTAssertEqual(deck.drawingDataJSON, "{\"version\":1}")
        XCTAssertEqual(deck.thumbnailURL, "https://cdn.ops.test/deck.png")
        XCTAssertTrue(deck.needsSync)
        XCTAssertNil(deck.opportunityId, "New lead link defaults nil for historical rows")

        opportunity.images = ["https://cdn.ops.test/lead.jpg"]
        opportunity.latitude = 49.2827
        opportunity.longitude = -123.1207
        deck.opportunityId = opportunityID
        XCTAssertNoThrow(try context.save(), "V16 fields must persist after migration")
    }
}
