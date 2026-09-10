import CoreData
import SwiftData
import XCTest
@testable import OPS

@MainActor
final class StorageBootstrapTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-bootstrap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testUnknownStoreFailsVisiblyAndRetainsOfflineRecordsAfterRetry() async throws {
        let url = directory.appendingPathComponent("unknown.store")
        let sourceSchema = Schema(versionedSchema: UnknownInstalledSchema.self)
        let sourceConfig = ModelConfiguration(schema: sourceSchema, url: url, cloudKitDatabase: .none)
        try autoreleasepool {
            let container = try ModelContainer(for: sourceSchema, configurations: sourceConfig)
            let context = ModelContext(container)
            context.insert(UnknownInstalledSchema.OfflineRecord(content: "Synthetic unsent capture"))
            try context.save()
        }
        let sourceMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let bootstrap = OPSStorageBootstrap(configuration: configuration(url: url))
        for _ in 0..<2 {
            await bootstrap.open()
            guard case .failed = bootstrap.state else {
                return XCTFail("An unknown installed schema must not produce an empty usable app")
            }
        }
        let afterMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        XCTAssertEqual(sourceMetadata[NSStoreUUIDKey] as? String, afterMetadata[NSStoreUUIDKey] as? String)
        XCTAssertEqual(sourceMetadata[NSPersistentStoreModelVersionChecksumKey] as? String,
                       afterMetadata[NSPersistentStoreModelVersionChecksumKey] as? String)
        let preserved = try ModelContainer(for: sourceSchema, configurations: sourceConfig)
        let rows = try ModelContext(preserved).fetch(FetchDescriptor<UnknownInstalledSchema.OfflineRecord>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.content, "Synthetic unsent capture")
    }

    func testRetryUsesSameLocationAfterTemporaryFileAccessFailure() async throws {
        let blockedParent = directory.appendingPathComponent("blocked-parent")
        try Data("synthetic path obstruction".utf8).write(to: blockedParent)
        let url = blockedParent.appendingPathComponent("ops.store")
        let bootstrap = OPSStorageBootstrap(configuration: configuration(url: url))
        await bootstrap.open()
        guard case .failed = bootstrap.state else { return XCTFail("Opening under a file must fail") }
        XCTAssertEqual(try Data(contentsOf: blockedParent), Data("synthetic path obstruction".utf8))

        // Only the test removes its synthetic obstruction; bootstrap never removes files.
        try FileManager.default.removeItem(at: blockedParent)
        try FileManager.default.createDirectory(at: blockedParent, withIntermediateDirectories: true)
        await bootstrap.open()
        guard case .ready(let container) = bootstrap.state else { return XCTFail("Retry must open the configured store") }
        XCTAssertEqual(container.configurations.first?.url, url)
        XCTAssertFalse(try XCTUnwrap(container.configurations.first).isStoredInMemoryOnly)
    }

    func testConcurrentAndRepeatedOpenReuseOneContainer() async throws {
        let url = directory.appendingPathComponent("current.store")
        let bootstrap = OPSStorageBootstrap(configuration: configuration(url: url))
        async let first: Void = bootstrap.open()
        async let second: Void = bootstrap.open()
        _ = await (first, second)
        guard case .ready(let container) = bootstrap.state else { return XCTFail("Fresh store must open") }
        let context = ModelContext(container)
        let deck = DeckDesign(id: "unsent-deck", companyId: "company-1", drawingDataJSON: "synthetic unsent drawing")
        deck.needsSync = true
        context.insert(deck)
        try context.save()
        await bootstrap.open()
        guard case .ready(let reopened) = bootstrap.state else { return XCTFail("Open state must remain ready") }
        XCTAssertTrue(container === reopened, "Repeated lifecycle work must not reopen a ready store")
        let decks = try ModelContext(reopened).fetch(FetchDescriptor<DeckDesign>())
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks.first?.drawingDataJSON, "synthetic unsent drawing")
        XCTAssertEqual(decks.first?.needsSync, true)
    }

    func testCanceledViewWaiterDoesNotAbandonStoreOpening() async throws {
        let url = directory.appendingPathComponent("interrupted-open.store")
        let bootstrap = OPSStorageBootstrap(configuration: configuration(url: url))
        let waiter = Task { await bootstrap.open() }
        waiter.cancel()
        await waiter.value
        await bootstrap.open()
        guard case .ready(let container) = bootstrap.state else {
            return XCTFail("A view interruption must not cancel the store's owned open attempt")
        }
        XCTAssertEqual(container.configurations.first?.url, url)
    }

    private func configuration(url: URL) -> ModelConfiguration {
        ModelConfiguration(schema: Schema(versionedSchema: OPSSchemaCurrent.self), url: url, cloudKitDatabase: .none)
    }
}

private enum UnknownInstalledSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(97, 0, 0) }
    static var models: [any PersistentModel.Type] { [OfflineRecord.self] }

    @Model
    final class OfflineRecord {
        var content: String
        init(content: String) { self.content = content }
    }
}
