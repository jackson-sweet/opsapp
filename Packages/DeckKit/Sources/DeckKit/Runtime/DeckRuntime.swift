import Foundation

public enum DeckAppSurface: Equatable {
    case ops
    case opsDecks
}

public struct DeckRuntimeContext: Equatable {
    public let companyId: String
    public let projectId: String?
    public let projectName: String?
    public let appSurface: DeckAppSurface

    public init(
        companyId: String,
        projectId: String?,
        projectName: String?,
        appSurface: DeckAppSurface
    ) {
        self.companyId = companyId
        self.projectId = projectId
        self.projectName = projectName
        self.appSurface = appSurface
    }
}

@MainActor
public protocol DeckStore: AnyObject {
    func save(drawingData: DeckDrawingData) throws
    func delete() throws
}

public protocol DeckImageUploader: AnyObject {}
public protocol DeckOCRService: AnyObject {}

public final class NoopDeckImageUploader: DeckImageUploader {
    public init() {}
}

public final class NoopDeckOCRService: DeckOCRService {
    public init() {}
}

public struct DeckRuntime {
    public let context: DeckRuntimeContext
    public let store: DeckStore?
    public let imageUploader: DeckImageUploader
    public let ocrService: DeckOCRService

    public init(
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
