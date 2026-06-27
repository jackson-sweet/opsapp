import Combine
import DeckKit
import Foundation

struct OPSDecksDeckDocument: Identifiable {
    let id: String
    let companyId: String
    let projectId: String?
    var title: String
    var drawingData: DeckDrawingData
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        companyId: String,
        projectId: String? = nil,
        title: String = OPSDecksCopy.defaultDeckTitle,
        drawingData: DeckDrawingData = DeckDrawingData(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.projectId = projectId
        self.title = title
        self.drawingData = drawingData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var drawingDataJSON: String {
        DeckSchemaMigration.stampFramingVersion(drawingData).toJSON()
    }

    mutating func updateDrawingData(_ drawingData: DeckDrawingData) {
        self.drawingData = DeckSchemaMigration.stampFramingVersion(drawingData)
        self.updatedAt = Date()
    }
}

struct OPSDecksActiveDesign {
    var document: OPSDecksDeckDocument
    let runtime: DeckRuntime
}

@MainActor
final class OPSDecksDesignSession: ObservableObject {
    let companyId: String
    private let entitlement: DecksEntitlement
    private let libraryStore: OPSDecksDeckLibraryStore

    @Published private(set) var activeDesign: OPSDecksActiveDesign?
    @Published private(set) var savedDecks: [OPSDecksDeckDocument]
    @Published private(set) var libraryError: Error?

    convenience init(
        companyId: String,
        savedDeckCount: Int,
        entitlement: DecksEntitlement
    ) {
        self.init(
            companyId: companyId,
            entitlement: entitlement,
            libraryStore: OPSDecksInMemoryDeckLibraryStore(
                seedCount: savedDeckCount,
                companyId: companyId
            )
        )
    }

    init(
        companyId: String,
        entitlement: DecksEntitlement,
        libraryStore: OPSDecksDeckLibraryStore
    ) {
        self.companyId = companyId
        self.entitlement = entitlement
        self.libraryStore = libraryStore
        do {
            self.savedDecks = Self.documents(
                try libraryStore.listDecks(),
                for: companyId
            )
            self.libraryError = nil
        } catch {
            self.savedDecks = []
            self.libraryError = error
        }
    }

    var createState: OPSDecksCreateState {
        let gate = DecksEntitlementGate(entitlement: entitlement)
        switch gate.decision(savedDeckCount: savedDecks.count) {
        case .allowSave:
            return .canCreate
        case .requiresPro:
            return .lockedAtFreeLimit
        }
    }

    @discardableResult
    func startNewDeck() -> Bool {
        guard createState == .canCreate else { return false }

        let document = OPSDecksDeckDocument(
            companyId: companyId,
            title: OPSDecksCopy.defaultDeckTitle
        )
        do {
            try libraryStore.save(document)
            refreshSavedDecks()
        } catch {
            libraryError = error
            return false
        }
        activeDesign = OPSDecksActiveDesign(
            document: document,
            runtime: OPSDecksRuntimeFactory.make(
                document: document,
                libraryStore: libraryStore
            )
        )
        return true
    }

    @discardableResult
    func openDeck(id: String) -> Bool {
        do {
            let document = try libraryStore.loadDeck(id: id)
            guard document.companyId == companyId else {
                throw OPSDecksDeckLibraryStoreError.documentBelongsToDifferentCompany(id)
            }
            activeDesign = OPSDecksActiveDesign(
                document: document,
                runtime: OPSDecksRuntimeFactory.make(
                    document: document,
                    libraryStore: libraryStore
                )
            )
            libraryError = nil
            return true
        } catch {
            libraryError = error
            return false
        }
    }

    func closeActiveDesign() {
        activeDesign = nil
    }

    @discardableResult
    func deleteDeck(id: String) -> Bool {
        do {
            let document = try libraryStore.loadDeck(id: id)
            guard document.companyId == companyId else {
                throw OPSDecksDeckLibraryStoreError.documentBelongsToDifferentCompany(id)
            }
            try libraryStore.deleteDeck(id: id)
            if activeDesign?.document.id == id {
                activeDesign = nil
            }
            refreshSavedDecks()
            libraryError = nil
            return true
        } catch {
            libraryError = error
            return false
        }
    }

    func updateActiveDrawingData(_ drawingData: DeckDrawingData) {
        guard var activeDesign else { return }
        activeDesign.document.updateDrawingData(drawingData)
        do {
            try libraryStore.save(activeDesign.document)
            refreshSavedDecks()
            libraryError = nil
        } catch {
            libraryError = error
        }
        self.activeDesign = activeDesign
    }

    private func refreshSavedDecks() {
        do {
            savedDecks = Self.documents(
                try libraryStore.listDecks(),
                for: companyId
            )
            libraryError = nil
        } catch {
            savedDecks = []
            libraryError = error
        }
    }

    private static func documents(
        _ documents: [OPSDecksDeckDocument],
        for companyId: String
    ) -> [OPSDecksDeckDocument] {
        documents.filter { $0.companyId == companyId }
    }
}
