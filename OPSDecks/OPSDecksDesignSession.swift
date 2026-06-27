import Combine
import DeckKit
import Foundation

struct OPSDecksDeckDocument: Identifiable {
    let id: String
    let companyId: String
    let projectId: String?
    var title: String
    var drawingData: DeckDrawingData

    init(
        id: String = UUID().uuidString,
        companyId: String,
        projectId: String? = nil,
        title: String = OPSDecksCopy.defaultDeckTitle,
        drawingData: DeckDrawingData = DeckDrawingData()
    ) {
        self.id = id
        self.companyId = companyId
        self.projectId = projectId
        self.title = title
        self.drawingData = drawingData
    }

    var drawingDataJSON: String {
        DeckSchemaMigration.stampFramingVersion(drawingData).toJSON()
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
    private let savedDeckCount: Int

    @Published private(set) var activeDesign: OPSDecksActiveDesign?

    init(
        companyId: String,
        savedDeckCount: Int,
        entitlement: DecksEntitlement
    ) {
        self.companyId = companyId
        self.savedDeckCount = savedDeckCount
        self.entitlement = entitlement
    }

    var createState: OPSDecksCreateState {
        let gate = DecksEntitlementGate(entitlement: entitlement)
        switch gate.decision(savedDeckCount: savedDeckCount) {
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
        activeDesign = OPSDecksActiveDesign(
            document: document,
            runtime: OPSDecksRuntimeFactory.make(
                companyId: document.companyId,
                projectName: document.title
            )
        )
        return true
    }

    func closeActiveDesign() {
        activeDesign = nil
    }
}
