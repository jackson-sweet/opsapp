import CoreGraphics
import DeckKit
import Foundation
import XCTest
@testable import OPSDecks

@MainActor
final class OPSDecksDesignSessionTests: XCTestCase {
    func testStartNewDeckCreatesStandaloneDesignWithFullRuntime() throws {
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            savedDeckCount: 0,
            entitlement: .free(savedDeckLimit: 1)
        )

        XCTAssertTrue(session.startNewDeck())

        let activeDesign = try XCTUnwrap(session.activeDesign)
        XCTAssertEqual(activeDesign.document.companyId, "deck-company")
        XCTAssertNil(activeDesign.document.projectId)
        XCTAssertEqual(activeDesign.document.title, OPSDecksCopy.defaultDeckTitle)
        XCTAssertNotNil(DeckDrawingData.fromJSON(activeDesign.document.drawingDataJSON))
        XCTAssertEqual(activeDesign.runtime.context.companyId, "deck-company")
        XCTAssertNil(activeDesign.runtime.context.projectId)
        XCTAssertEqual(activeDesign.runtime.context.projectName, OPSDecksCopy.defaultDeckTitle)
        XCTAssertEqual(activeDesign.runtime.context.appSurface, .opsDecks)
        XCTAssertEqual(DeckCapabilities.forSurface(activeDesign.runtime.context.appSurface), .full)
    }

    func testStartNewDeckDoesNotCreateDesignWhenFreeLimitIsReached() {
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            savedDeckCount: 1,
            entitlement: .free(savedDeckLimit: 1)
        )

        XCTAssertFalse(session.startNewDeck())
        XCTAssertNil(session.activeDesign)
    }

    func testEditorWritebackUpdatesActiveStandaloneDocument() throws {
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            savedDeckCount: 0,
            entitlement: .free(savedDeckLimit: 1)
        )
        XCTAssertTrue(session.startNewDeck())

        var drawingData = DeckDrawingData()
        drawingData.vertices.append(DeckVertex(position: CGPoint(x: 120, y: 120)))

        session.updateActiveDrawingData(drawingData)

        let activeDesign = try XCTUnwrap(session.activeDesign)
        XCTAssertEqual(activeDesign.document.drawingData.vertices.count, 1)
        XCTAssertEqual(activeDesign.document.drawingDataJSON, drawingData.toJSON())
    }

    func testStartNewDeckPersistsDocumentAndUsesLibraryCountForFreeGate() throws {
        let store = OPSDecksInMemoryDeckLibraryStore()
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            entitlement: .free(savedDeckLimit: 1),
            libraryStore: store
        )

        XCTAssertEqual(session.savedDecks.count, 0)
        XCTAssertTrue(session.startNewDeck())

        let activeDesign = try XCTUnwrap(session.activeDesign)
        XCTAssertEqual(store.documents.map(\.id), [activeDesign.document.id])
        XCTAssertEqual(session.savedDecks.map(\.id), [activeDesign.document.id])
        XCTAssertEqual(session.createState, .lockedAtFreeLimit)

        session.closeActiveDesign()

        XCTAssertFalse(session.startNewDeck())
        XCTAssertNil(session.activeDesign)
    }

    func testEditorWritebackPersistsAndOpenDeckRestoresStandaloneRuntime() throws {
        let store = OPSDecksInMemoryDeckLibraryStore()
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            entitlement: .pro,
            libraryStore: store
        )
        XCTAssertTrue(session.startNewDeck())
        let deckId = try XCTUnwrap(session.activeDesign?.document.id)

        var drawingData = DeckDrawingData()
        drawingData.vertices.append(DeckVertex(position: CGPoint(x: 96, y: 144)))

        session.updateActiveDrawingData(drawingData)
        session.closeActiveDesign()

        XCTAssertTrue(session.openDeck(id: deckId))

        let reopened = try XCTUnwrap(session.activeDesign)
        XCTAssertEqual(reopened.document.id, deckId)
        XCTAssertEqual(reopened.document.drawingData.vertices.count, 1)
        XCTAssertEqual(reopened.runtime.context.appSurface, .opsDecks)
        XCTAssertEqual(DeckCapabilities.forSurface(reopened.runtime.context.appSurface), .full)
    }

    func testDeleteDeckRemovesSavedDocumentAndClearsActiveDesign() throws {
        let store = OPSDecksInMemoryDeckLibraryStore()
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            entitlement: .free(savedDeckLimit: 1),
            libraryStore: store
        )
        XCTAssertTrue(session.startNewDeck())
        let deckId = try XCTUnwrap(session.activeDesign?.document.id)

        XCTAssertTrue(session.deleteDeck(id: deckId))

        XCTAssertNil(session.activeDesign)
        XCTAssertTrue(session.savedDecks.isEmpty)
        XCTAssertEqual(session.createState, .canCreate)
        XCTAssertTrue(store.documents.isEmpty)
    }

    func testFileDeckLibraryStoreSurvivesReinitialization() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var drawingData = DeckDrawingData()
        drawingData.vertices.append(DeckVertex(position: CGPoint(x: 72, y: 96)))

        let document = OPSDecksDeckDocument(
            id: "persisted-deck",
            companyId: "deck-company",
            title: "FIELD DECK",
            drawingData: drawingData
        )

        let writer = try OPSDecksFileDeckLibraryStore(directory: directory)
        try writer.save(document)

        let reader = try OPSDecksFileDeckLibraryStore(directory: directory)
        let loaded = try XCTUnwrap(reader.listDecks().first)

        XCTAssertEqual(loaded.id, "persisted-deck")
        XCTAssertEqual(loaded.companyId, "deck-company")
        XCTAssertEqual(loaded.projectId, nil)
        XCTAssertEqual(loaded.title, "FIELD DECK")
        XCTAssertEqual(loaded.drawingData.vertices.count, 1)
    }

    func testLibraryOnlySurfacesDecksForCurrentCompany() throws {
        let ownedDeck = OPSDecksDeckDocument(
            id: "owned-deck",
            companyId: "deck-company",
            title: "OWNED"
        )
        let otherCompanyDeck = OPSDecksDeckDocument(
            id: "other-company-deck",
            companyId: "other-company",
            title: "OTHER"
        )
        let store = OPSDecksInMemoryDeckLibraryStore(
            documents: [ownedDeck, otherCompanyDeck]
        )
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            entitlement: .free(savedDeckLimit: 1),
            libraryStore: store
        )

        XCTAssertEqual(session.savedDecks.map(\.id), ["owned-deck"])
        XCTAssertEqual(session.createState, .lockedAtFreeLimit)
        XCTAssertFalse(session.openDeck(id: "other-company-deck"))
        XCTAssertNil(session.activeDesign)
        XCTAssertFalse(session.deleteDeck(id: "other-company-deck"))
        XCTAssertEqual(Set(store.documents.map(\.id)), ["owned-deck", "other-company-deck"])
    }

    func testRemoteBackedLibraryRefreshSaveAndSoftDeleteUseDeckDesignRows() async throws {
        let cache = OPSDecksInMemoryDeckLibraryStore()
        let remote = RecordingRemoteDeckLibraryClient(
            rows: [
                OPSDecksDeckDesignRow(
                    id: "remote-deck",
                    companyId: "deck-company",
                    projectId: nil,
                    title: "REMOTE FIELD DECK",
                    drawingData: DeckDrawingData(),
                    version: 1,
                    createdBy: "deck-user",
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 20),
                    deletedAt: nil
                )
            ]
        )
        let store = OPSDecksSyncingDeckLibraryStore(
            companyId: "deck-company",
            cache: cache,
            remoteClient: remote
        )

        try await store.refreshFromRemote()

        XCTAssertEqual(remote.listedCompanyIds, ["deck-company"])
        XCTAssertEqual(try store.listDecks().map(\.id), ["remote-deck"])
        XCTAssertEqual(try cache.listDecks().map(\.id), ["remote-deck"])

        var drawingData = DeckDrawingData()
        drawingData.vertices.append(DeckVertex(position: CGPoint(x: 72, y: 96)))
        let savedDocument = OPSDecksDeckDocument(
            id: "saved-deck",
            companyId: "deck-company",
            title: "SAVED FIELD DECK",
            drawingData: drawingData,
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40)
        )

        try await store.saveAndSync(savedDocument)

        XCTAssertEqual(try store.loadDeck(id: "saved-deck").drawingData.vertices.count, 1)
        XCTAssertEqual(remote.upsertedRows.map(\.id), ["saved-deck"])
        XCTAssertEqual(remote.upsertedRows.first?.companyId, "deck-company")
        XCTAssertNil(remote.upsertedRows.first?.projectId)
        XCTAssertEqual(remote.upsertedRows.first?.title, "SAVED FIELD DECK")
        XCTAssertEqual(remote.upsertedRows.first?.drawingData.vertices.count, 1)

        try await store.deleteAndSync(id: "saved-deck")

        XCTAssertThrowsError(try store.loadDeck(id: "saved-deck"))
        XCTAssertEqual(remote.softDeletedRows.map(\.id), ["saved-deck"])
        XCTAssertEqual(remote.softDeletedRows.first?.companyId, "deck-company")
    }

    func testSessionRefreshesRemoteBackedLibraryAndRecomputesFreeGate() async throws {
        let remote = RecordingRemoteDeckLibraryClient(
            rows: [
                OPSDecksDeckDesignRow(
                    id: "remote-deck",
                    companyId: "deck-company",
                    projectId: nil,
                    title: "REMOTE FIELD DECK",
                    drawingData: DeckDrawingData(),
                    version: 1,
                    createdBy: "deck-user",
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 20),
                    deletedAt: nil
                )
            ]
        )
        let store = OPSDecksSyncingDeckLibraryStore(
            companyId: "deck-company",
            cache: OPSDecksInMemoryDeckLibraryStore(),
            remoteClient: remote
        )
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            entitlement: .free(savedDeckLimit: 1),
            libraryStore: store
        )

        XCTAssertTrue(session.savedDecks.isEmpty)

        await session.refreshLibraryFromRemote()

        XCTAssertNil(session.libraryError)
        XCTAssertEqual(remote.listedCompanyIds, ["deck-company"])
        XCTAssertEqual(session.savedDecks.map(\.id), ["remote-deck"])
        XCTAssertEqual(session.createState, .lockedAtFreeLimit)
    }

    func testAsyncSessionCreateUpdateAndDeleteUseRemoteSyncWhenAvailable() async throws {
        let remote = RecordingRemoteDeckLibraryClient(rows: [])
        let store = OPSDecksSyncingDeckLibraryStore(
            companyId: "deck-company",
            cache: OPSDecksInMemoryDeckLibraryStore(),
            remoteClient: remote
        )
        let session = OPSDecksDesignSession(
            companyId: "deck-company",
            entitlement: .pro,
            libraryStore: store
        )

        let didStart = await session.startNewDeckAndSync()

        XCTAssertTrue(didStart)
        let deckId = try XCTUnwrap(session.activeDesign?.document.id)

        XCTAssertEqual(remote.upsertedRows.map(\.id), [deckId])
        XCTAssertEqual(session.savedDecks.map(\.id), [deckId])

        var drawingData = DeckDrawingData()
        drawingData.vertices.append(DeckVertex(position: CGPoint(x: 72, y: 96)))

        await session.updateActiveDrawingDataAndSync(drawingData)

        XCTAssertEqual(remote.upsertedRows.map(\.id), [deckId, deckId])
        XCTAssertEqual(remote.upsertedRows.last?.drawingData.vertices.count, 1)
        XCTAssertEqual(session.activeDesign?.document.drawingData.vertices.count, 1)

        let didDelete = await session.deleteDeckAndSync(id: deckId)

        XCTAssertTrue(didDelete)
        XCTAssertNil(session.activeDesign)
        XCTAssertTrue(session.savedDecks.isEmpty)
        XCTAssertEqual(remote.softDeletedRows.map(\.id), [deckId])
    }

    func testDeckDesignRowCodableUsesDeckDesignStorageContract() throws {
        let payload = """
        {
            "id": "row-deck",
            "company_id": "deck-company",
            "project_id": "project-7",
            "title": "PERMIT DECK",
            "drawing_data": {"schemaVersion": 0},
            "version": 0,
            "created_by": "designer-1",
            "created_at": "2026-06-27T20:00:00Z",
            "updated_at": "2026-06-27T20:01:02.123Z",
            "deleted_at": null
        }
        """
        let row = try JSONDecoder().decode(
            OPSDecksDeckDesignRow.self,
            from: Data(payload.utf8)
        )

        let createdAt = try XCTUnwrap(isoDateFormatter.date(from: "2026-06-27T20:00:00Z"))
        let updatedAt = try XCTUnwrap(fractionalISODateFormatter.date(
            from: "2026-06-27T20:01:02.123Z"
        ))
        let rowUpdatedAt = try XCTUnwrap(row.updatedAt)

        XCTAssertEqual(row.id, "row-deck")
        XCTAssertEqual(row.companyId, "deck-company")
        XCTAssertEqual(row.projectId, "project-7")
        XCTAssertEqual(row.title, "PERMIT DECK")
        XCTAssertEqual(row.version, 1)
        XCTAssertEqual(row.createdBy, "designer-1")
        XCTAssertEqual(row.createdAt, createdAt)
        XCTAssertEqual(
            rowUpdatedAt.timeIntervalSince1970,
            updatedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertNil(row.deletedAt)

        let encoded = try JSONEncoder().encode(row)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["company_id"] as? String, "deck-company")
        XCTAssertEqual(object["project_id"] as? String, "project-7")
        XCTAssertEqual(object["created_by"] as? String, "designer-1")
        XCTAssertEqual(object["created_at"] as? String, "2026-06-27T20:00:00Z")
        XCTAssertNotNil(object["drawing_data"] as? [String: Any])
        XCTAssertNil(object["companyId"])
        XCTAssertNil(object["drawingData"])
    }
}

private let isoDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private let fractionalISODateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private final class RecordingRemoteDeckLibraryClient: OPSDecksRemoteDeckLibraryClient {
    private var rows: [OPSDecksDeckDesignRow]
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
        if let index = rows.firstIndex(where: { $0.id == row.id }) {
            rows[index] = row
        } else {
            rows.append(row)
        }
    }

    func softDeleteDeck(id: String, companyId: String, deletedAt: Date) async throws {
        softDeletedRows.append((id: id, companyId: companyId, deletedAt: deletedAt))
        if let index = rows.firstIndex(where: { $0.id == id && $0.companyId == companyId }) {
            rows[index].deletedAt = deletedAt
        }
    }
}
