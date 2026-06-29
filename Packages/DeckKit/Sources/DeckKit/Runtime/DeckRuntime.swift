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

@MainActor
public protocol DeckSyncQueue: AnyObject {
    func enqueueSave(drawingData: DeckDrawingData)
}

public protocol DeckImageUploader: AnyObject {}
public protocol DeckOCRService: AnyObject {}

public final class NoopDeckSyncQueue: DeckSyncQueue {
    nonisolated public init() {}

    @MainActor
    public func enqueueSave(drawingData: DeckDrawingData) {}
}

public final class NoopDeckImageUploader: DeckImageUploader {
    public init() {}
}

public final class NoopDeckOCRService: DeckOCRService {
    public init() {}
}

public struct DeckRuntime {
    public let context: DeckRuntimeContext
    public let store: DeckStore?
    public let syncQueue: DeckSyncQueue
    public let imageUploader: DeckImageUploader
    public let ocrService: DeckOCRService
    public let codeProfile: DeckCodeProfile?
    public let codeProfileRequest: DeckCodeProfileRequest?
    public let codeProfileResolution: DeckCodeProfileResolution?

    public var activeCodeProfile: DeckCodeProfile? {
        guard context.appSurface == .opsDecks else { return nil }
        return codeProfileResolution?.profile ?? codeProfile
    }

    @MainActor
    public init(
        context: DeckRuntimeContext,
        store: DeckStore?,
        syncQueue: DeckSyncQueue = NoopDeckSyncQueue(),
        imageUploader: DeckImageUploader = NoopDeckImageUploader(),
        ocrService: DeckOCRService = NoopDeckOCRService(),
        codeProfile: DeckCodeProfile? = nil,
        codeProfileRequest: DeckCodeProfileRequest? = nil,
        codeProfileResolution: DeckCodeProfileResolution? = nil
    ) {
        self.context = context
        self.store = store
        self.syncQueue = syncQueue
        self.imageUploader = imageUploader
        self.ocrService = ocrService
        self.codeProfile = codeProfile
        self.codeProfileRequest = codeProfileRequest
        self.codeProfileResolution = codeProfileResolution
    }
}
