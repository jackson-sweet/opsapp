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

    var editorIdentity: String {
        guard let resolution = runtime.codeProfileResolution else {
            return "\(document.id)::code:none"
        }
        guard let profile = runtime.activeCodeProfile else {
            return "\(document.id)::code:\(resolution.status.rawValue)"
        }
        return "\(document.id)::code:\(resolution.status.rawValue):\(profile.id)"
    }
}

@MainActor
final class OPSDecksDesignSession: ObservableObject {
    let companyId: String
    private let entitlement: DecksEntitlement
    private let libraryStore: OPSDecksDeckLibraryStore
    private let codeProfileResolver: DeckManualCodeProfileResolver

    @Published private(set) var activeDesign: OPSDecksActiveDesign?
    @Published private(set) var savedDecks: [OPSDecksDeckDocument]
    @Published private(set) var libraryError: Error?
    @Published private(set) var availableCodeProfiles: [DeckCodeProfile]
    @Published private(set) var codeProfileRequest: DeckCodeProfileRequest
    @Published private(set) var codeProfileResolution: DeckCodeProfileResolution

    private var syncingLibraryStore: OPSDecksRemoteSyncingDeckLibraryStore? {
        libraryStore as? OPSDecksRemoteSyncingDeckLibraryStore
    }

    convenience init(
        companyId: String,
        savedDeckCount: Int,
        entitlement: DecksEntitlement,
        codeProfiles: [DeckCodeProfile] = [],
        codeProfileRequest: DeckCodeProfileRequest = DeckCodeProfileRequest()
    ) {
        self.init(
            companyId: companyId,
            entitlement: entitlement,
            libraryStore: OPSDecksInMemoryDeckLibraryStore(
                seedCount: savedDeckCount,
                companyId: companyId
            ),
            codeProfiles: codeProfiles,
            codeProfileRequest: codeProfileRequest
        )
    }

    init(
        companyId: String,
        entitlement: DecksEntitlement,
        libraryStore: OPSDecksDeckLibraryStore,
        codeProfiles: [DeckCodeProfile] = [],
        codeProfileRequest: DeckCodeProfileRequest = DeckCodeProfileRequest()
    ) {
        self.companyId = companyId
        self.entitlement = entitlement
        self.libraryStore = libraryStore
        let codeProfileResolver = DeckManualCodeProfileResolver(profiles: codeProfiles)
        self.codeProfileResolver = codeProfileResolver
        self.availableCodeProfiles = codeProfiles
        self.codeProfileRequest = codeProfileRequest
        self.codeProfileResolution = codeProfileResolver.resolve(codeProfileRequest)
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
        activate(document)
        return true
    }

    @discardableResult
    func startNewDeckAndSync() async -> Bool {
        guard createState == .canCreate else { return false }

        let document = OPSDecksDeckDocument(
            companyId: companyId,
            title: OPSDecksCopy.defaultDeckTitle
        )
        do {
            if let syncingLibraryStore {
                try await syncingLibraryStore.saveAndSync(document)
            } else {
                try libraryStore.save(document)
            }
            refreshSavedDecks()
            activate(document)
            return true
        } catch {
            if localDeckExists(id: document.id) {
                refreshSavedDecks(clearErrorOnSuccess: false)
                libraryError = error
                activate(document)
                return true
            }
            libraryError = error
            return false
        }
    }

    @discardableResult
    func openDeck(id: String) -> Bool {
        do {
            let document = try libraryStore.loadDeck(id: id)
            guard document.companyId == companyId else {
                throw OPSDecksDeckLibraryStoreError.documentBelongsToDifferentCompany(id)
            }
            activate(document)
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

    func setCodeProfileRequest(_ request: DeckCodeProfileRequest) {
        codeProfileRequest = request
        codeProfileResolution = codeProfileResolver.resolve(request)
        refreshActiveRuntime()
    }

    func setCodeProfileJurisdictionId(_ jurisdictionId: String?) {
        let trimmedJurisdictionId = jurisdictionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        setCodeProfileRequest(
            DeckCodeProfileRequest(
                siteAddress: codeProfileRequest.siteAddress,
                jurisdictionId: trimmedJurisdictionId?.isEmpty == false ? trimmedJurisdictionId : nil
            )
        )
    }

    @discardableResult
    func deleteDeck(id: String) -> Bool {
        do {
            let document = try libraryStore.loadDeck(id: id)
            guard document.companyId == companyId else {
                throw OPSDecksDeckLibraryStoreError.documentBelongsToDifferentCompany(id)
            }
            try libraryStore.deleteDeck(id: id)
            clearActiveDesignIfNeeded(id: id)
            refreshSavedDecks()
            libraryError = nil
            return true
        } catch {
            libraryError = error
            return false
        }
    }

    @discardableResult
    func deleteDeckAndSync(id: String) async -> Bool {
        do {
            let document = try libraryStore.loadDeck(id: id)
            guard document.companyId == companyId else {
                throw OPSDecksDeckLibraryStoreError.documentBelongsToDifferentCompany(id)
            }
            if let syncingLibraryStore {
                try await syncingLibraryStore.deleteAndSync(id: id)
            } else {
                try libraryStore.deleteDeck(id: id)
            }
            clearActiveDesignIfNeeded(id: id)
            refreshSavedDecks()
            libraryError = nil
            return true
        } catch {
            if !localDeckExists(id: id) {
                clearActiveDesignIfNeeded(id: id)
                refreshSavedDecks(clearErrorOnSuccess: false)
            }
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

    func updateActiveDrawingDataAndSync(_ drawingData: DeckDrawingData) async {
        guard var activeDesign else { return }
        activeDesign.document.updateDrawingData(drawingData)
        do {
            if let syncingLibraryStore {
                try await syncingLibraryStore.saveAndSync(activeDesign.document)
            } else {
                try libraryStore.save(activeDesign.document)
            }
            refreshSavedDecks()
            libraryError = nil
        } catch {
            refreshSavedDecks(clearErrorOnSuccess: false)
            libraryError = error
        }
        self.activeDesign = activeDesign
    }

    func refreshLibraryFromRemote() async {
        guard let syncingLibraryStore else {
            refreshSavedDecks()
            return
        }

        do {
            try await syncingLibraryStore.refreshFromRemote()
            refreshSavedDecks()
        } catch {
            refreshSavedDecks(clearErrorOnSuccess: false)
            libraryError = error
        }
    }

    private func refreshSavedDecks(clearErrorOnSuccess: Bool = true) {
        do {
            savedDecks = Self.documents(
                try libraryStore.listDecks(),
                for: companyId
            )
            if clearErrorOnSuccess {
                libraryError = nil
            }
        } catch {
            savedDecks = []
            libraryError = error
        }
    }

    private func activate(_ document: OPSDecksDeckDocument) {
        activeDesign = OPSDecksActiveDesign(
            document: document,
            runtime: runtime(for: document)
        )
    }

    private func refreshActiveRuntime() {
        guard let activeDesign else { return }
        self.activeDesign = OPSDecksActiveDesign(
            document: activeDesign.document,
            runtime: runtime(for: activeDesign.document)
        )
    }

    private func runtime(for document: OPSDecksDeckDocument) -> DeckRuntime {
        OPSDecksRuntimeFactory.make(
            document: document,
            libraryStore: libraryStore,
            codeProfileRequest: codeProfileRequest,
            codeProfileResolution: codeProfileResolution
        )
    }

    private func clearActiveDesignIfNeeded(id: String) {
        if activeDesign?.document.id == id {
            activeDesign = nil
        }
    }

    private func localDeckExists(id: String) -> Bool {
        (try? libraryStore.loadDeck(id: id)) != nil
    }

    private static func documents(
        _ documents: [OPSDecksDeckDocument],
        for companyId: String
    ) -> [OPSDecksDeckDocument] {
        documents.filter { $0.companyId == companyId }
    }
}
