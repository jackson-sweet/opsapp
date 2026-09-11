import CoreData
import SwiftData
import XCTest
@testable import OPS

/// Every fixture is synthetic. No container here initializes sync or networking.
final class DeckMergeBaseMigrationTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("ops.store") }
    private let drawing = #"{"version":1,"offline":"unsent drawing"}"#
    private let mergeBase = #"{"version":1,"offline":"server drawing"}"#
    private let payload = Data(#"{"drawing_data":{"offline":"unsent drawing"}}"#.utf8)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testReleasedV16ThroughV25KeepFrozenDeckModel() {
        for version in OPSMigrationPlan.schemas where (16...25).contains(version.versionIdentifier.major) {
            XCTAssertFalse(version.models.contains { ObjectIdentifier($0) == ObjectIdentifier(DeckDesign.self) })
            XCTAssertTrue(version.models.contains {
                ObjectIdentifier($0) == ObjectIdentifier(OPSSchemaLegacyDeckDesignV25.DeckDesign.self)
            })
        }
        XCTAssertEqual(OPSSchemaCurrent.versionIdentifier, Schema.Version(28, 0, 0))
        XCTAssertEqual(OPSMigrationPlan.schemas.count, OPSMigrationPlan.stages.count + 1)
    }

    func testReleasedV25PreservesUnsentVisitPacketAndDrawingAcrossUpgradeAndReopen() throws {
        let originalPhoto = Data("synthetic original capture bytes".utf8)
        let photoURL = directory.appendingPathComponent("unuploaded-photo.jpg")
        try originalPhoto.write(to: photoURL)
        try autoreleasepool {
            let container = try makeContainer(OPSSchemaV25.self)
            let context = ModelContext(container)
            let deck = makeLegacyDeck()
            context.insert(deck)
            context.insert(makeOperation())
            let visit = SiteVisit(id: "visit-1", companyId: "company-1", status: .inProgress)
            visit.notes = "Keep this offline site note"
            context.insert(visit)
            context.insert(SiteVisitCaptureArtifact(
                id: "photo-1", siteVisitId: visit.id, companyId: visit.companyId,
                kind: .photo, source: .camera, localAssetURL: photoURL.path, createdBy: "user-1"
            ))
            context.insert(SiteVisitIdentityDraft(
                id: "identity-1", siteVisitId: visit.id, companyId: visit.companyId,
                searchText: "Partial contact", notes: "Call after measurements", createdBy: "user-1"
            ))
            let answer = OPSSchemaLegacyPhoneV27.SiteVisitChecklistAnswer(
                id: "answer-1", siteVisitId: visit.id, companyId: visit.companyId,
                opportunityId: nil, siteVisitTypeId: nil, fieldId: "width", label: "Width",
                kind: .shortText, required: true, sortOrder: 1, answerValue: .text("Unsent answer")
            )
            context.insert(answer)
            try context.save()
        }
        XCTAssertEqual(try checksum(), "oDrDy3ePGUW2ZiuwOISzdvuUZ8yf5LtXt42AFLxtTrs=",
                       "Fixture must match the original released V25, including the diagnosed phone shape")

        // A second close/open proves idempotency, not merely a cached context read.
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try makeContainer(OPSSchemaCurrent.self, migrate: true)
                let context = ModelContext(container)
                let deck = try assertUnsentDeck(in: context)
                XCTAssertNil(deck.syncedDrawingJSON, "An unknown merge base must not become an acknowledgement")
                let visit = try XCTUnwrap(try context.fetch(FetchDescriptor<SiteVisit>()).first)
                XCTAssertEqual(visit.id, "visit-1")
                XCTAssertEqual(visit.notes, "Keep this offline site note")
                XCTAssertTrue(visit.needsSync)
                XCTAssertEqual(visit.status, .inProgress)
                let photos = try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
                XCTAssertEqual(photos.count, 1)
                XCTAssertEqual(photos.first?.siteVisitId, visit.id)
                XCTAssertEqual(photos.first?.localAssetURL, photoURL.path)
                XCTAssertEqual(photos.first?.needsSync, true)
                let identities = try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
                XCTAssertEqual(identities.count, 1)
                XCTAssertEqual(identities.first?.searchText, "Partial contact")
                XCTAssertEqual(identities.first?.notes, "Call after measurements")
                XCTAssertEqual(identities.first?.needsSync, true)
                let answers = try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
                XCTAssertEqual(answers.count, 1)
                XCTAssertEqual(answers.first?.answerValue, .text("Unsent answer"))
                XCTAssertEqual(answers.first?.needsSync, true)
            }
        }
        XCTAssertEqual(try Data(contentsOf: photoURL), originalPhoto)
    }

    func testMigratedDirtyDrawingStaysUnsentWhenFirstSaveHasUnchangedContent() throws {
        try autoreleasepool {
            let container = try makeContainer(OPSSchemaV25.self)
            let context = ModelContext(container)
            context.insert(makeLegacyDeck())
            context.insert(makeOperation())
            try context.save()
        }
        try autoreleasepool {
            let container = try makeContainer(OPSSchemaCurrent.self, migrate: true)
            let context = ModelContext(container)
            let deck = try assertUnsentDeck(in: context)
            deck.storeDrawingData(DeckDrawingData(), json: drawing)
            XCTAssertNil(deck.syncedDrawingJSON, "Pre-upgrade dirty content was never a server acknowledgement")
            XCTAssertTrue(deck.hasUnsyncedDrawing, "Opening and saving unchanged geometry must not abandon unsent work")
            try context.save()
        }
        let container = try makeContainer(OPSSchemaCurrent.self, migrate: true)
        let context = ModelContext(container)
        let deck = try assertUnsentDeck(in: context)
        XCTAssertNil(deck.syncedDrawingJSON)
    }

    func testReleasedV16PreservesUnsentDrawingAndOutboxThroughEveryAdjacentStage() throws {
        try autoreleasepool {
            let container = try makeContainer(OPSSchemaV16.self)
            let context = ModelContext(container)
            context.insert(makeLegacyDeck())
            context.insert(makeOperation())
            try context.save()
        }
        let container = try makeContainer(OPSSchemaCurrent.self, migrate: true)
        let context = ModelContext(container)
        let deck = try assertUnsentDeck(in: context)
        XCTAssertNil(deck.syncedDrawingJSON)
    }

    func testWidenedDebugV25OpensAtV26PreservingMergeBaseAndStoppedOutbox() throws {
        try autoreleasepool {
            let container = try makeContainer(WidenedDebugV25.self)
            let context = ModelContext(container)
            let deck = WidenedDebugV25.DeckDesign(
                id: "deck-1", companyId: "company-1", drawingDataJSON: drawing
            )
            deck.projectId = "project-1"
            deck.opportunityId = "lead-1"
            deck.syncedDrawingJSON = mergeBase
            // The merge-base difference is authoritative even if a stale flag was cleared.
            deck.needsSync = false
            context.insert(deck)
            context.insert(makeOperation())
            try context.save()
        }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL)
        XCTAssertEqual(metadata[NSStoreModelVersionIdentifiersKey] as? [String], ["25.0.0"])
        XCTAssertEqual(try checksum(), "W/BL26OkKY5G0Ed7qNE0Bc9SjxDXSTK+LsRyd/fTKy8=",
                       "Pin the observed September 6 debug graph independently from the released fixture")
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try makeContainer(OPSSchemaCurrent.self, migrate: true)
                let context = ModelContext(container)
                let decks = try context.fetch(FetchDescriptor<DeckDesign>())
                XCTAssertEqual(decks.count, 1)
                let deck = try XCTUnwrap(decks.first)
                XCTAssertEqual(deck.id, "deck-1")
                XCTAssertEqual(deck.drawingDataJSON, drawing)
                XCTAssertEqual(deck.syncedDrawingJSON, mergeBase)
                XCTAssertFalse(deck.needsSync)
                XCTAssertTrue(deck.hasUnsyncedDrawing)
                try assertStoppedOperation(in: context)
            }
        }
    }

    private func makeLegacyDeck() -> OPSSchemaLegacyDeckDesignV25.DeckDesign {
        let deck = OPSSchemaLegacyDeckDesignV25.DeckDesign(
            id: "deck-1", companyId: "company-1", projectId: "project-1",
            opportunityId: "lead-1", drawingDataJSON: drawing, createdBy: "user-1"
        )
        deck.needsSync = true
        deck.version = 8
        deck.localThumbnailPath = "local/unsent-thumbnail.png"
        return deck
    }

    private func makeOperation() -> OPSSchemaLegacyPhoneV27.SyncOperation {
        let operation = OPSSchemaLegacyPhoneV27.SyncOperation(
            entityType: SyncEntityType.deckDesign.rawValue, entityId: "deck-1", operationType: "update",
            payload: payload, changedFields: ["drawing_data"], dependsOnId: "visit-parent-operation"
        )
        operation.status = "parked"
        operation.retryCount = 7
        operation.lastError = "Synthetic permanent failure"
        return operation
    }

    @discardableResult
    private func assertUnsentDeck(in context: ModelContext) throws -> DeckDesign {
        let decks = try context.fetch(FetchDescriptor<DeckDesign>())
        XCTAssertEqual(decks.count, 1)
        let deck = try XCTUnwrap(decks.first)
        XCTAssertEqual(deck.id, "deck-1")
        XCTAssertEqual(deck.companyId, "company-1")
        XCTAssertEqual(deck.projectId, "project-1")
        XCTAssertEqual(deck.opportunityId, "lead-1")
        XCTAssertEqual(deck.createdBy, "user-1")
        XCTAssertEqual(deck.drawingDataJSON, drawing)
        XCTAssertEqual(deck.version, 8)
        XCTAssertEqual(deck.localThumbnailPath, "local/unsent-thumbnail.png")
        XCTAssertTrue(deck.needsSync)
        XCTAssertTrue(deck.hasUnsyncedDrawing)
        try assertStoppedOperation(in: context)
        return deck
    }

    private func assertStoppedOperation(in context: ModelContext) throws {
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.count, 1)
        let operation = try XCTUnwrap(operations.first)
        XCTAssertEqual(operation.entityId, "deck-1")
        XCTAssertEqual(operation.payload, payload)
        XCTAssertEqual(operation.status, "parked")
        XCTAssertEqual(operation.retryCount, 7)
        XCTAssertEqual(operation.lastError, "Synthetic permanent failure")
        XCTAssertEqual(operation.dependsOnId, "visit-parent-operation")
    }

    private func checksum() throws -> String {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL)
        return try XCTUnwrap(metadata[NSPersistentStoreModelVersionChecksumKey] as? String)
    }

    private func makeContainer(_ version: any VersionedSchema.Type, migrate: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: version)
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: migrate ? OPSMigrationPlan.self : nil, configurations: config)
    }
}

/// The debug build widened V25 in place. Do NOT add this to OPSMigrationPlan:
/// its checksum already matches V26, and duplicate checksums make a plan invalid.
private enum WidenedDebugV25: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(25, 0, 0) }
    static var models: [any PersistentModel.Type] {
        OPSSchemaV25.models.filter {
            ObjectIdentifier($0) != ObjectIdentifier(OPSSchemaLegacyDeckDesignV25.DeckDesign.self)
        } + [DeckDesign.self]
    }

    @Model
    final class DeckDesign {
        @Attribute(.unique) var id: String
        var companyId: String
        var projectId: String?
        var opportunityId: String?
        var title: String
        var drawingDataJSON: String
        var thumbnailURL: String?
        var localThumbnailPath: String?
        var version: Int = 1
        var createdBy: String?
        var needsSync: Bool = false
        var lastSyncedAt: Date?
        var syncPriority: Int = 1
        var deletedAt: Date?
        var syncedDrawingJSON: String?
        var createdAt: Date
        var updatedAt: Date?

        init(id: String, companyId: String, drawingDataJSON: String) {
            self.id = id
            self.companyId = companyId
            self.title = "Synthetic debug drawing"
            self.drawingDataJSON = drawingDataJSON
            self.createdAt = Date()
        }
    }
}
