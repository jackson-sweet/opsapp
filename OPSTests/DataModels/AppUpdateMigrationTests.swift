//
//  AppUpdateMigrationTests.swift
//  OPSTests
//
//  Guards the released SwiftData schema graph used during in-place app updates.
//

import CoreData
import CryptoKit
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

    func testReleasedV18DoesNotReferenceWidenedLiveOpportunity() {
        XCTAssertFalse(
            contains(Opportunity.self, in: OPSSchemaV18.self),
            "V18 must keep the Opportunity shape released before operatorActionRequiredAt was added"
        )
        XCTAssertTrue(
            contains(OPSSchemaLegacyOpportunityV18.Opportunity.self, in: OPSSchemaV18.self),
            "V18 must register its frozen released Opportunity shape"
        )
        XCTAssertTrue(
            contains(Opportunity.self, in: OPSSchemaV19.self),
            "V19 must register the widened live Opportunity"
        )
    }

    func testReleasedV19DoesNotReferenceWidenedLiveSiteVisitModels() {
        XCTAssertFalse(
            contains(SiteVisit.self, in: OPSSchemaV19.self),
            "V19 must keep the SiteVisit shape released before cloud sync fields were added"
        )
        XCTAssertTrue(
            contains(OPSSchemaLegacySiteVisitV19.SiteVisit.self, in: OPSSchemaV19.self),
            "V19 must register its frozen released SiteVisit shape"
        )
        XCTAssertFalse(
            contains(SiteVisitIdentityDraft.self, in: OPSSchemaV19.self),
            "V19 must keep the identity-draft shape released before cloud sync fields were added"
        )
        XCTAssertTrue(
            contains(OPSSchemaLegacySiteVisitIdentityDraftV19.SiteVisitIdentityDraft.self, in: OPSSchemaV19.self),
            "V19 must register its frozen released identity-draft shape"
        )
        XCTAssertTrue(contains(OPSSchemaLegacySiteVisitV22.SiteVisit.self, in: OPSSchemaV20.self))
        XCTAssertTrue(contains(SiteVisitIdentityDraft.self, in: OPSSchemaV20.self))
        XCTAssertTrue(
            contains(OPSSchemaLegacySiteVisitV22.SiteVisit.self, in: OPSSchemaV22.self),
            "The activity-feed widenings above V20 must carry the frozen cloud SiteVisit forward"
        )
        XCTAssertTrue(
            contains(SiteVisitIdentityDraft.self, in: OPSSchemaV22.self),
            "The activity-feed widenings above V20 must carry the cloud identity draft forward"
        )
    }

    func testReleasedV22DoesNotReferenceWidenedLiveSiteVisit() {
        XCTAssertFalse(
            contains(SiteVisit.self, in: OPSSchemaV20.self),
            "V20 must keep the SiteVisit shape released before the booking fields were added"
        )
        XCTAssertFalse(
            contains(SiteVisit.self, in: OPSSchemaV21.self),
            "V21 must keep the SiteVisit shape released before the booking fields were added"
        )
        XCTAssertFalse(
            contains(SiteVisit.self, in: OPSSchemaV22.self),
            "V22 must keep the SiteVisit shape released before the booking fields were added"
        )
        XCTAssertFalse(
            contains(SiteVisit.self, in: OPSSchemaV23.self),
            "V23 must retain the released booking-only SiteVisit shape"
        )
        XCTAssertTrue(
            contains(OPSSchemaLegacySiteVisitV23.SiteVisit.self, in: OPSSchemaV23.self),
            "V23 must register its frozen released SiteVisit shape"
        )
        XCTAssertTrue(
            contains(SiteVisit.self, in: OPSSchemaV24.self),
            "V24 must register the widened live SiteVisit"
        )
    }

    func testV25AddsPrimaryContactProjectionWithoutChangingReleasedProject() {
        XCTAssertTrue(contains(Project.self, in: OPSSchemaV24.self))
        XCTAssertTrue(
            contains(ProjectPrimaryContactSelection.self, in: OPSSchemaV25.self),
            "V25 must add the independent primary-contact projection"
        )
        XCTAssertFalse(
            contains(ProjectPrimaryContactSelection.self, in: OPSSchemaV24.self),
            "V24 must remain at its released fingerprint"
        )
    }

    func testV24StoreMigratesToV25PreservingProjectAndPrimaryContact() throws {
        try autoreleasepool {
            let sourceSchema = Schema(versionedSchema: OPSSchemaV24.self)
            let sourceConfiguration = ModelConfiguration(schema: sourceSchema, url: storeURL)
            let sourceContainer = try ModelContainer(
                for: sourceSchema,
                configurations: sourceConfiguration
            )
            let context = ModelContext(sourceContainer)

            let project = Project(
                id: "project-v24",
                title: "North deck replacement",
                status: .inProgress
            )
            project.companyId = "company-1"
            project.clientId = "client-1"
            project.address = "1100 Maple Ave"
            project.priorityRank = 1.25
            project.projectDescription = "Preserve the existing field record"
            project.teamMemberIdsString = "user-1,user-2"
            project.needsSync = true
            context.insert(project)
            try context.save()
        }

        let targetSchema = Schema(versionedSchema: OPSSchemaV25.self)
        let targetConfiguration = ModelConfiguration(schema: targetSchema, url: storeURL)
        let migratedContainer = try ModelContainer(
            for: targetSchema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: targetConfiguration
        )
        let context = ModelContext(migratedContainer)

        let projects = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.count, 1)
        let migrated = try XCTUnwrap(projects.first)
        XCTAssertEqual(migrated.id, "project-v24")
        XCTAssertEqual(migrated.title, "North deck replacement")
        XCTAssertEqual(migrated.companyId, "company-1")
        XCTAssertEqual(migrated.clientId, "client-1")
        XCTAssertEqual(migrated.address, "1100 Maple Ave")
        XCTAssertEqual(migrated.priorityRank, 1.25)
        XCTAssertEqual(migrated.projectDescription, "Preserve the existing field record")
        XCTAssertEqual(migrated.teamMemberIdsString, "user-1,user-2")
        XCTAssertTrue(migrated.needsSync)
        XCTAssertNil(migrated.primarySubClientId)

        try ProjectPrimaryContactProjection.upsert(
            project: migrated,
            primarySubClientId: "sub-client-1",
            in: context
        )
        try context.save()

        migrated.primarySubClientId = nil
        try ProjectPrimaryContactProjection.hydrate(project: migrated, in: context)
        let reread = migrated
        XCTAssertEqual(reread.primarySubClientId, "sub-client-1")
        let projections = try context.fetch(
            FetchDescriptor<ProjectPrimaryContactSelection>()
        )
        XCTAssertEqual(projections.count, 1)
        XCTAssertEqual(projections.first?.projectId, migrated.id)
        XCTAssertEqual(projections.first?.primarySubClientId, "sub-client-1")
    }

    func testV22StoreMigratesToV24PreservingSiteVisitAndDefaultingServerFields() throws {
        try autoreleasepool {
            let sourceSchema = Schema(versionedSchema: OPSSchemaV22.self)
            let sourceConfiguration = ModelConfiguration(schema: sourceSchema, url: storeURL)
            let sourceContainer = try ModelContainer(
                for: sourceSchema,
                configurations: sourceConfiguration
            )
            let context = ModelContext(sourceContainer)

            let visit = OPSSchemaLegacySiteVisitV22.SiteVisit(
                id: "visit-v22",
                opportunityId: "lead-v22",
                companyId: "company-1",
                status: .inProgress,
                createdAt: Date(timeIntervalSince1970: 2_400_000)
            )
            visit.scheduledAt = Date(timeIntervalSince1970: 2_500_000)
            visit.durationMinutes = 90
            visit.assigneeIds = ["user-jackson"]
            visit.notes = "Deck measurements captured"
            visit.photos = ["https://cdn.ops.test/v22-visit.jpg"]
            visit.needsSync = true
            visit.loggedActivityId = "act-v22"
            context.insert(visit)
            try context.save()
        }

        let targetSchema = Schema(versionedSchema: OPSSchemaV24.self)
        let targetConfiguration = ModelConfiguration(schema: targetSchema, url: storeURL)
        let migratedContainer = try ModelContainer(
            for: targetSchema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: targetConfiguration
        )
        let context = ModelContext(migratedContainer)

        let visits = try context.fetch(FetchDescriptor<SiteVisit>())
        XCTAssertEqual(visits.count, 1, "The V22 site visit must survive migration.")
        let migrated = try XCTUnwrap(visits.first)
        XCTAssertEqual(migrated.id, "visit-v22")
        XCTAssertEqual(migrated.opportunityId, "lead-v22")
        XCTAssertEqual(migrated.status, .inProgress)
        XCTAssertEqual(migrated.durationMinutes, 90)
        XCTAssertEqual(migrated.assigneeIds, ["user-jackson"])
        XCTAssertEqual(migrated.notes, "Deck measurements captured")
        XCTAssertEqual(migrated.photos, ["https://cdn.ops.test/v22-visit.jpg"])
        XCTAssertTrue(migrated.needsSync)
        XCTAssertEqual(migrated.loggedActivityId, "act-v22")
        XCTAssertNil(migrated.bookedAt, "Pre-booking rows must default to nil bookedAt")
        XCTAssertNil(
            migrated.reminderLeadMinutes,
            "Pre-booking rows must default to nil reminderLeadMinutes"
        )
        XCTAssertNil(migrated.appointmentHandoffId)
        XCTAssertNil(migrated.appointmentKind)
        XCTAssertNil(migrated.appointmentTitle)
        XCTAssertNil(migrated.appointmentLocation)
        XCTAssertFalse(migrated.isBookedAppointment)

        migrated.bookedAt = Date(timeIntervalSince1970: 2_600_000)
        migrated.reminderLeadMinutes = 30
        migrated.appointmentHandoffId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        migrated.appointmentKind = "call"
        migrated.appointmentTitle = "Call — North deck"
        migrated.appointmentLocation = "Microsoft Teams"
        try context.save()

        let rebound = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SiteVisit>()).first,
            "The widened row must persist its booking fields"
        )
        XCTAssertEqual(rebound.bookedAt, Date(timeIntervalSince1970: 2_600_000))
        XCTAssertEqual(rebound.reminderLeadMinutes, 30)
        XCTAssertEqual(rebound.appointmentKind, "call")
        XCTAssertEqual(rebound.appointmentTitle, "Call — North deck")
        XCTAssertEqual(rebound.appointmentLocation, "Microsoft Teams")
        XCTAssertTrue(rebound.isBookedAppointment)
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

    func testV15StoreMigratesToCurrentPreservingOpportunityAndDeckDesign() throws {
        try assertOpportunityAndDeckDesignMigration(from: OPSSchemaV15.self, sourceLabel: "v15")
    }

    func testV10StoreMigratesToCurrentPreservingOpportunityAndDeckDesign() throws {
        try assertOpportunityAndDeckDesignMigration(from: OPSSchemaV10.self, sourceLabel: "v10")
    }

    func testV18StoreMigratesToV19PreservingOpportunityAndAddingActionRequiredTimestamp() throws {
        let handledAt = Date(timeIntervalSince1970: 2_100_000)
        let summaryUpdatedAt = Date(timeIntervalSince1970: 2_200_000)

        try autoreleasepool {
            let sourceSchema = Schema(versionedSchema: OPSSchemaV18.self)
            let sourceConfiguration = ModelConfiguration(schema: sourceSchema, url: storeURL)
            let sourceContainer = try ModelContainer(
                for: sourceSchema,
                configurations: sourceConfiguration
            )
            let context = ModelContext(sourceContainer)

            let opportunity = OPSSchemaLegacyOpportunityV18.Opportunity(
                id: "lead-v18",
                companyId: "company-1",
                contactName: "Helen Calloway",
                stage: .quoted,
                stageEnteredAt: Date(timeIntervalSince1970: 2_000_000),
                createdAt: Date(timeIntervalSince1970: 1_900_000),
                updatedAt: Date(timeIntervalSince1970: 2_300_000)
            )
            opportunity.title = "South deck replacement"
            opportunity.assignedTo = "user-helen"
            opportunity.assignmentVersion = 7
            opportunity.images = ["https://cdn.ops.test/v18-lead.jpg"]
            opportunity.latitude = 48.4284
            opportunity.longitude = -123.3656
            opportunity.lastInboundAt = Date(timeIntervalSince1970: 2_050_000)
            opportunity.lastMessageDirection = "in"
            opportunity.handledAt = handledAt
            opportunity.aiSummary = "Quote sent. Waiting on measurements."
            opportunity.aiSummaryUpdatedAt = summaryUpdatedAt
            context.insert(opportunity)
            try context.save()
        }

        let targetSchema = Schema(versionedSchema: OPSSchemaV19.self)
        let targetConfiguration = ModelConfiguration(schema: targetSchema, url: storeURL)
        let migratedContainer = try ModelContainer(
            for: targetSchema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: targetConfiguration
        )
        let context = ModelContext(migratedContainer)

        let migrated = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Opportunity>()).first
        )
        XCTAssertEqual(migrated.id, "lead-v18")
        XCTAssertEqual(migrated.title, "South deck replacement")
        XCTAssertEqual(migrated.assignedTo, "user-helen")
        XCTAssertEqual(migrated.assignmentVersion, 7)
        XCTAssertEqual(migrated.images, ["https://cdn.ops.test/v18-lead.jpg"])
        XCTAssertEqual(migrated.latitude, 48.4284)
        XCTAssertEqual(migrated.longitude, -123.3656)
        XCTAssertEqual(migrated.lastMessageDirection, "in")
        XCTAssertEqual(migrated.handledAt, handledAt)
        XCTAssertEqual(migrated.aiSummary, "Quote sent. Waiting on measurements.")
        XCTAssertEqual(migrated.aiSummaryUpdatedAt, summaryUpdatedAt)
        XCTAssertNil(
            migrated.operatorActionRequiredAt,
            "The additive V19 timestamp must default to nil for V18 rows"
        )

        let actionRequiredAt = Date(timeIntervalSince1970: 2_400_000)
        migrated.operatorActionRequiredAt = actionRequiredAt
        try context.save()

        let rereadContext = ModelContext(migratedContainer)
        let reread = try XCTUnwrap(
            try rereadContext.fetch(FetchDescriptor<Opportunity>()).first
        )
        XCTAssertEqual(
            reread.operatorActionRequiredAt,
            actionRequiredAt,
            "The V19 timestamp must persist after the migration"
        )
    }

    func testProductionStoreConfigurationPinsThePrimaryAppGroup() {
        XCTAssertEqual(
            OPSModelStore.appGroupIdentifier(isStoredInMemoryOnly: false),
            AppGroupConfig.identifier
        )
    }

    func testHostedTestStoreStaysInMemoryWithoutAppGroupStorage() {
        let schema = Schema(versionedSchema: OPSSchemaV22.self)
        let configuration = OPSModelStore.configuration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        XCTAssertTrue(configuration.isStoredInMemoryOnly)
        XCTAssertNil(configuration.groupAppContainerIdentifier)
    }

    func testCopiedDeviceV15StoreMigratesToCurrentWithoutLosingRows() throws {
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

        let currentSchema = Schema(versionedSchema: OPSSchemaCurrent.self)
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

    /// Opt-in only. The fixture is never opened by Core Data/SwiftData; only
    /// its private disposable copy is opened. No application services attach.
    func testCopiedDeviceV25StoreMigratesToCurrentPreservingCustody() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["OPS_V25_STORE_FIXTURE_DIR"],
              !fixturePath.isEmpty else {
            throw XCTSkip("Set OPS_V25_STORE_FIXTURE_DIR to run the copied V25 migration proof")
        }
        let directory = storeURL.deletingLastPathComponent()
            .appendingPathComponent("private-v25", isDirectory: true)
        var phase = "private fixture copy"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            defer {
                do { try FileManager.default.removeItem(at: directory) }
                catch { XCTFail("Private V25 test-copy cleanup failed; details suppressed") }
            }
            let copyURL = directory.appendingPathComponent("default.store")
            let fixture = URL(fileURLWithPath: fixturePath, isDirectory: true)
            for name in ["default.store", "default.store-wal", "default.store-shm",
                         "default.store_SUPPORT", ".default.store_SUPPORT"] {
                let source = fixture.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    if name == "default.store" { throw PrivateStoreProofError.missingStore }
                    continue
                }
                try rejectPrivateFixtureSymlinks(at: source)
                try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
            }

            phase = "released V25 metadata preflight"
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: copyURL)
            guard metadata[NSStoreModelVersionIdentifiersKey] as? [String] == ["25.0.0"],
                  metadata[NSPersistentStoreModelVersionChecksumKey] as? String
                    == "oDrDy3ePGUW2ZiuwOISzdvuUZ8yf5LtXt42AFLxtTrs=" else {
                throw PrivateStoreProofError.wrongReleasedSchema
            }

            // A fresh key per invocation prevents reusable content/ID hashes.
            // Neither the key nor any digest/record is logged or persisted.
            let key = SymmetricKey(size: .bits256)
            phase = "frozen V25 aggregate preflight"
            let baseline = try autoreleasepool {
                let container = try privateProofContainer(OPSSchemaV25.self, at: copyURL, migrate: false)
                return try privateStoreSnapshot(container, legacyDeck: true, key: key)
            }
            for migrationPass in [true, false] {
                phase = migrationPass ? "V25 to current migration" : "independent current-store reopen"
                let after = try autoreleasepool {
                    let container = try privateProofContainer(OPSSchemaCurrent.self, at: copyURL,
                                                              migrate: migrationPass)
                    return try privateStoreSnapshot(container, legacyDeck: false, key: key)
                }
                // Boolean assertions deliberately avoid XCTest's value dumps.
                XCTAssertTrue(Set(baseline.keys) == Set(after.keys), "Copied-store model coverage changed")
                for model in baseline.keys.sorted() {
                    XCTAssertTrue(baseline[model]?.count == after[model]?.count,
                                  "Copied-store row count changed: \(model)")
                    XCTAssertTrue(baseline[model]?.digest == after[model]?.digest,
                                  "Copied-store identity/content/custody changed: \(model)")
                }
                let reopenedMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                    type: .sqlite, at: copyURL)
                XCTAssertTrue(reopenedMetadata[NSStoreModelVersionIdentifiersKey] as? [String] == ["26.0.0"],
                              "Copied-store migration did not persist the V26 schema")
            }
        } catch {
            // SwiftData/filesystem error descriptions can contain record values
            // and private paths. Keep even failing XCTest output structural.
            XCTFail("Copied V25 proof failed during \(phase); underlying details suppressed")
        }
    }

    private enum PrivateStoreProofError: Error { case missingStore, wrongReleasedSchema, symbolicLink }

    private struct PrivateStoreDigest {
        let count: Int
        let digest: Data
    }

    private func rejectPrivateFixtureSymlinks(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true else { throw PrivateStoreProofError.symbolicLink }
        if values.isDirectory == true {
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                try rejectPrivateFixtureSymlinks(at: child)
            }
        }
    }

    private func privateProofContainer(_ version: any VersionedSchema.Type, at url: URL,
                                       migrate: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: version)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        if migrate {
            return try ModelContainer(for: schema, migrationPlan: OPSMigrationPlan.self, configurations: configuration)
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// All persisted scalar fields for the visit packet, decks, outbox, media,
    /// leads, clients, contacts, notes and primary-contact projection. Project
    /// relationships are represented by stable IDs, never SQLite row numbers.
    private func privateStoreSnapshot(_ container: ModelContainer, legacyDeck: Bool,
                                      key: SymmetricKey) throws -> [String: PrivateStoreDigest] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var result: [String: PrivateStoreDigest] = [:]
        func capture<T: PersistentModel>(_ type: T.Type, _ name: String,
                                         fields: (T) -> [Any?]) throws {
            let rows = try context.fetch(FetchDescriptor<T>())
            var rowDigests: [Data] = []
            for row in rows {
                let values: [Any] = fields(row).map { value in
                    guard let value else { return NSNull() }
                    switch value {
                    case let date as Date: return ["dateBits": String(date.timeIntervalSinceReferenceDate.bitPattern)]
                    case let data as Data: return ["bytes": data.base64EncodedString()]
                    case let uuid as UUID: return ["uuid": uuid.uuidString]
                    case let number as Double: return ["doubleBits": String(number.bitPattern)]
                    default: return value
                    }
                }
                let bytes = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
                rowDigests.append(Data(HMAC<SHA256>.authenticationCode(for: bytes, using: key)))
            }
            var combined = Data()
            for digest in rowDigests.sorted(by: { $0.lexicographicallyPrecedes($1) }) { combined.append(digest) }
            result[name] = PrivateStoreDigest(count: rows.count,
                digest: Data(HMAC<SHA256>.authenticationCode(for: combined, using: key)))
        }
        try capture(SiteVisit.self, "visits") { r in [
            r.id, r.opportunityId, r.companyId, r.projectId, r.projectRef, r.clientId, r.clientRef,
            r.status.rawValue, r.scheduledAt, r.durationMinutes, r.assigneeIds, r.completedAt,
            r.notes, r.internalNotes, r.measurements, r.photos, r.address, r.assignedTo, r.calendarEventId,
            r.createdBy, r.createdAt, r.updatedAt, r.deletedAt, r.needsSync, r.lastSyncedAt,
            r.loggedActivityId, r.bookedAt, r.reminderLeadMinutes, r.appointmentHandoffId,
            r.appointmentKind, r.appointmentTitle, r.appointmentLocation
        ] }
        try capture(SiteVisitCaptureArtifact.self, "artifacts") { r in [
            r.id, r.siteVisitId, r.companyId, r.opportunityId, r.kind.rawValue, r.source.rawValue,
            r.title, r.body, r.localAssetURL, r.renderedAssetURL, r.thumbnailURL, r.dimensionsJSON,
            r.deckDesignId, r.includedInProjectReview, r.capturedAt, r.createdBy, r.createdAt,
            r.updatedAt, r.deletedAt, r.needsSync, r.lastSyncedAt
        ] }
        try capture(SiteVisitChecklistAnswer.self, "answers") { r in [
            r.id, r.siteVisitId, r.companyId, r.opportunityId, r.siteVisitTypeId, r.fieldId, r.label,
            r.kind.rawValue, r.required, r.helpText, r.sortOrder, r.answerValueData, r.createdBy,
            r.createdAt, r.updatedAt, r.deletedAt, r.needsSync, r.lastSyncedAt
        ] }
        try capture(SiteVisitIdentityDraft.self, "identity drafts") { r in [
            r.id, r.siteVisitId, r.companyId, r.opportunityId, r.clientId, r.subClientId, r.searchText,
            r.clientName, r.contactName, r.preferredEmail, r.additionalEmailsJSON, r.phoneNumber,
            r.address, r.notes, r.createdBy, r.createdAt, r.updatedAt, r.lastCommittedAt,
            r.deletedAt, r.needsSync, r.lastSyncedAt
        ] }
        try capture(SiteVisitType.self, "visit types") { r in [
            r.id, r.companyId, r.slug, r.name, r.descriptionText, r.isSystemTemplate, r.isDefault,
            r.sortOrder, r.fieldsData, r.createdAt, r.updatedAt, r.deletedAt, r.needsSync, r.lastSyncedAt
        ] }
        if legacyDeck {
            try capture(OPSSchemaLegacyDeckDesignV25.DeckDesign.self, "decks") { r in [
                r.id, r.companyId, r.projectId, r.opportunityId, r.title, r.drawingDataJSON,
                r.thumbnailURL, r.localThumbnailPath, r.version, r.createdBy, r.needsSync,
                r.lastSyncedAt, r.syncPriority, r.deletedAt, r.createdAt, r.updatedAt
            ] }
        } else {
            try capture(DeckDesign.self, "decks") { r in [
                r.id, r.companyId, r.projectId, r.opportunityId, r.title, r.drawingDataJSON,
                r.thumbnailURL, r.localThumbnailPath, r.version, r.createdBy, r.needsSync,
                r.lastSyncedAt, r.syncPriority, r.deletedAt, r.createdAt, r.updatedAt
            ] }
            let decks = try context.fetch(FetchDescriptor<DeckDesign>())
            XCTAssertTrue(decks.allSatisfy { $0.syncedDrawingJSON == nil },
                          "Migrated legacy decks must retain an unknown merge base, including dirty drawings")
            XCTAssertTrue(decks.filter(\.needsSync).allSatisfy(\.hasUnsyncedDrawing),
                          "Migrated dirty drawing custody must remain unsent")
        }
        try capture(SyncOperation.self, "outbox") { r in [
            r.id, r.entityType, r.entityId, r.operationType, r.payload, r.changedFields, r.createdAt,
            r.retryCount, r.lastAttemptedAt, r.status, r.lastError, r.previousValues, r.priority,
            r.requiresWiFi, r.dependsOnId, r.completedAt, r.serverConfirmedAt
        ] }
        try capture(LocalPhoto.self, "local photos") { r in [
            r.id, r.companyId, r.entityType, r.entityId, r.localPath, r.thumbnailPath, r.uploadedURL,
            r.fileSize, r.mimeType, r.width, r.height, r.capturedAt, r.latitude, r.longitude,
            r.uploadProgress, r.uploadRetryCount, r.status, r.createdAt, r.deletedAt, r.lastSyncedAt, r.needsSync
        ] }
        try capture(PhotoAnnotation.self, "photo annotations") { r in [
            r.id, r.projectId, r.companyId, r.photoURL, r.annotationURL, r.note, r.authorId,
            r.createdAt, r.updatedAt, r.deletedAt, r.renderedPhotoURL, r.lastSyncedAt, r.needsSync,
            r.syncFailureCount, r.syncParkedAt, r.localDrawingData, r.layersData, r.changeLogData,
            r.beforeSnapshotURL, r.afterSnapshotURL, r.hiddenAuthorIdsData, r.dimensionsData,
            r.localDepthMapPath, r.localSidecarPath, r.localCaptureFinishedAt
        ] }
        try capture(ProjectNote.self, "project notes") { r in [
            r.id, r.projectId, r.companyId, r.authorId, r.content, r.attachmentsJSON, r.mentionedUserIdsString,
            r.photoURL, r.eventKind, r.contentMetadataJSON, r.createdAt, r.updatedAt, r.deletedAt,
            r.lastSyncedAt, r.needsSync
        ] }
        try capture(Opportunity.self, "leads") { r in [
            r.id, r.companyId, r.title, r.contactName, r.contactEmail, r.contactPhone, r.descriptionText,
            r.address, r.stage.rawValue, r.stageEnteredAt, r.stageManuallySet, r.assignedTo,
            r.assignmentVersion, r.priority, r.source, r.quoteDeliveryMethod?.rawValue, r.estimatedValue,
            r.actualValue, r.winProbabilityOverride, r.expectedCloseDate, r.actualCloseDate,
            r.nextFollowUpAt, r.lastActivityAt, r.projectId, r.clientId, r.lostReason, r.lostNotes,
            r.deletedAt, r.archivedAt, r.tags, r.sourceEmailId, r.images, r.latitude, r.longitude,
            r.correspondenceCount, r.outboundCount, r.inboundCount, r.lastInboundAt, r.lastOutboundAt,
            r.lastMessageDirection, r.handledAt, r.operatorActionRequiredAt, r.aiSummary,
            r.aiSummaryUpdatedAt, r.createdAt, r.updatedAt
        ] }
        try capture(Client.self, "clients") { r in [
            r.id, r.name, r.email, r.phoneNumber, r.address, r.latitude, r.longitude, r.profileImageURL,
            r.notes, r.companyId, r.lastSyncedAt, r.needsSync, r.createdAt, r.deletedAt,
            r.projects.map(\.id).sorted(), r.subClients.map(\.id).sorted()
        ] }
        try capture(SubClient.self, "contacts") { r in [
            r.id, r.name, r.title, r.email, r.phoneNumber, r.address, r.client?.id,
            r.createdAt, r.updatedAt, r.lastSyncedAt, r.needsSync, r.deletedAt
        ] }
        try capture(Project.self, "projects") { r in [
            r.id, r.title, r.address, r.latitude, r.longitude, r.startDate, r.endDate, r.completedAt,
            r.duration, r.status.rawValue, r.notes, r.companyId, r.priorityRank, r.clientId, r.allDay,
            r.opportunityId, r.titleIsAuto, r.client?.id, r.teamMemberIdsString, r.projectDescription,
            r.projectImagesString, r.unsyncedImagesString, r.clientVisibleImagesString,
            r.teamMembers.map(\.id).sorted(), r.tasks.map(\.id).sorted(), r.lastSyncedAt, r.needsSync,
            r.syncPriority, r.deletedAt, r.createdAt, r.createdBy, r.updatedAt
        ] }
        try capture(ProjectPrimaryContactSelection.self, "primary contact projections") { r in [
            r.id, r.primarySubClientId, r.sourceProjectUpdatedAt, r.lastSyncedAt
        ] }
        return result
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

        let currentSchema = Schema(versionedSchema: OPSSchemaCurrent.self)
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
        XCTAssertNil(
            opportunity.operatorActionRequiredAt,
            "New ownership-correction timestamp defaults nil for historical rows"
        )

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
