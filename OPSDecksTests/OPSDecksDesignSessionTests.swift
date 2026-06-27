import CoreGraphics
import DeckKit
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
}
