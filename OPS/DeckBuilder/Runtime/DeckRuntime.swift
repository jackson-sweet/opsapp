import Foundation
import DeckKit

enum DeckAppSurface: Equatable {
    case ops
    case opsDecks
}

struct DeckRuntimeContext: Equatable {
    let companyId: String
    let projectId: String?
    let projectName: String?
    let appSurface: DeckAppSurface
}

@MainActor
protocol DeckStore: AnyObject {
    func save(deckDesign: DeckDesign, drawingData: DeckDrawingData) throws
    func delete(deckDesign: DeckDesign) throws
}

protocol DeckImageUploader: AnyObject {}
protocol DeckOCRService: AnyObject {}

final class NoopDeckImageUploader: DeckImageUploader {}
final class NoopDeckOCRService: DeckOCRService {}

struct DeckRuntime {
    let context: DeckRuntimeContext
    let store: DeckStore?
    let imageUploader: DeckImageUploader
    let ocrService: DeckOCRService

    init(
        context: DeckRuntimeContext,
        store: DeckStore?,
        imageUploader: DeckImageUploader = NoopDeckImageUploader(),
        ocrService: DeckOCRService = NoopDeckOCRService()
    ) {
        self.context = context
        self.store = store
        self.imageUploader = imageUploader
        self.ocrService = ocrService
    }
}
