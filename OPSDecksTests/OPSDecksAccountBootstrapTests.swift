import DeckKit
import Foundation
import XCTest
@testable import OPSDecks

final class OPSDecksAccountBootstrapTests: XCTestCase {
    func testAccountContextUsesDeckOnlyStorageContract() throws {
        let context = OPSDecksAccountContext(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: "Deck Operator",
            companyId: "company-123",
            userId: "user-123",
            role: "admin",
            subscriptionPlan: "decks"
        )

        let data = try JSONEncoder().encode(context)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(OPSDecksAccountContext.self, from: data)

        XCTAssertEqual(decoded, context)
        XCTAssertTrue(json.contains("\"firebase_uid\":\"firebase-123\""))
        XCTAssertTrue(json.contains("\"company_id\":\"company-123\""))
        XCTAssertTrue(json.contains("\"subscription_plan\":\"decks\""))
        XCTAssertFalse(json.contains("subscription_status"))
        XCTAssertFalse(json.contains("trial_end_date"))
    }

    func testAccountContextCanBeBuiltFromProvisioningResponse() {
        let response = DecksCompanyProvisioningResponse(
            companyId: "company-123",
            userId: "user-123",
            role: "admin",
            subscriptionPlan: "decks"
        )

        let context = OPSDecksAccountContext(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: nil,
            provisioningResponse: response
        )

        XCTAssertEqual(context.firebaseUID, "firebase-123")
        XCTAssertEqual(context.email, "deck@example.com")
        XCTAssertNil(context.displayName)
        XCTAssertEqual(context.companyId, "company-123")
        XCTAssertEqual(context.userId, "user-123")
        XCTAssertEqual(context.role, "admin")
        XCTAssertEqual(context.subscriptionPlan, "decks")
    }

    func testFileAccountContextStorePersistsAndClearsContext() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try OPSDecksFileAccountContextStore(directory: directory)
        let context = OPSDecksAccountContext(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: "Deck Operator",
            companyId: "company-123",
            userId: "user-123",
            role: "admin",
            subscriptionPlan: "decks"
        )

        XCTAssertNil(try store.loadAccountContext())

        try store.saveAccountContext(context)

        XCTAssertEqual(try store.loadAccountContext(), context)

        try store.clearAccountContext()

        XCTAssertNil(try store.loadAccountContext())
    }

    func testLibraryBootstrapUsesLocalDraftStoreWithoutAccount() throws {
        let bootstrap = OPSDecksLibraryBootstrap.make(
            accountContext: nil,
            savedDeckCount: 1
        )

        XCTAssertEqual(bootstrap.companyId, OPSDecksLibraryBootstrap.localCompanyId)
        XCTAssertEqual(try bootstrap.libraryStore.listDecks().map(\.companyId), [
            OPSDecksLibraryBootstrap.localCompanyId
        ])
        XCTAssertNil(bootstrap.libraryStore as? OPSDecksRemoteSyncingDeckLibraryStore)
    }

    func testLibraryBootstrapUsesRemoteSyncStoreForAccountContext() async throws {
        let accountContext = OPSDecksAccountContext(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: "Deck Operator",
            companyId: "company-123",
            userId: "user-123",
            role: "admin",
            subscriptionPlan: "decks"
        )
        let remote = RecordingAccountBootstrapRemoteDeckLibraryClient(
            rows: [
                OPSDecksDeckDesignRow(
                    id: "remote-deck",
                    companyId: "company-123",
                    projectId: nil,
                    title: "REMOTE DECK",
                    drawingData: DeckDrawingData(),
                    version: 1,
                    createdBy: "user-123",
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: nil,
                    deletedAt: nil
                )
            ]
        )
        let bootstrap = OPSDecksLibraryBootstrap.make(
            accountContext: accountContext,
            remoteClient: remote,
            cacheStore: OPSDecksInMemoryDeckLibraryStore()
        )
        let syncingStore = try XCTUnwrap(
            bootstrap.libraryStore as? OPSDecksRemoteSyncingDeckLibraryStore
        )

        XCTAssertEqual(bootstrap.companyId, "company-123")

        try await syncingStore.refreshFromRemote()

        XCTAssertEqual(remote.listedCompanyIds, ["company-123"])
        XCTAssertEqual(try bootstrap.libraryStore.listDecks().map(\.id), ["remote-deck"])
    }
}

private final class RecordingAccountBootstrapRemoteDeckLibraryClient: OPSDecksRemoteDeckLibraryClient {
    private let rows: [OPSDecksDeckDesignRow]
    private(set) var listedCompanyIds: [String] = []
    private(set) var upsertedRows: [OPSDecksDeckDesignRow] = []
    private(set) var softDeletedRows: [(id: String, companyId: String, deletedAt: Date)] = []

    init(rows: [OPSDecksDeckDesignRow]) {
        self.rows = rows
    }

    func listDecks(companyId: String) async throws -> [OPSDecksDeckDesignRow] {
        listedCompanyIds.append(companyId)
        return rows.filter { $0.companyId == companyId && $0.deletedAt == nil }
    }

    func upsertDeck(_ row: OPSDecksDeckDesignRow) async throws {
        upsertedRows.append(row)
    }

    func softDeleteDeck(id: String, companyId: String, deletedAt: Date) async throws {
        softDeletedRows.append((id: id, companyId: companyId, deletedAt: deletedAt))
    }
}
