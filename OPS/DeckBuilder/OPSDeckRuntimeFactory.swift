import DeckKit
import Foundation
import SwiftData

@MainActor
final class OPSDeckStore: DeckStore {
    private let deckDesign: DeckDesign
    private let modelContext: ModelContext?

    init(deckDesign: DeckDesign, modelContext: ModelContext?) {
        self.deckDesign = deckDesign
        self.modelContext = modelContext
    }

    func save(drawingData: DeckDrawingData) throws {
        deckDesign.drawingData = drawingData
        if deckDesign.modelContext == nil {
            modelContext?.insert(deckDesign)
        }
        try modelContext?.save()
    }

    func delete() throws {
        deckDesign.deletedAt = Date()
        deckDesign.markForSync()
        try modelContext?.save()
    }
}

@MainActor
final class OPSDeckSyncQueue: DeckSyncQueue {
    private let deckDesign: DeckDesign
    private weak var syncEngine: SyncEngine?
    private var hasEnqueuedCreate: Bool

    init(deckDesign: DeckDesign, syncEngine: SyncEngine?) {
        self.deckDesign = deckDesign
        self.syncEngine = syncEngine
        self.hasEnqueuedCreate = deckDesign.lastSyncedAt != nil
    }

    func enqueueSave(drawingData: DeckDrawingData) {
        guard let syncEngine else { return }

        let nowIso = ISO8601DateFormatter().string(from: Date())
        let createdIso = ISO8601DateFormatter().string(from: deckDesign.createdAt)
        let drawingObject = Self.drawingObject(from: drawingData)

        if !hasEnqueuedCreate {
            var payload: [String: Any] = [
                "id": deckDesign.id,
                "company_id": deckDesign.companyId,
                "title": deckDesign.title,
                "drawing_data": drawingObject,
                "version": deckDesign.version,
                "created_at": createdIso,
                "updated_at": nowIso
            ]
            if let projectId = deckDesign.projectId, !projectId.isEmpty {
                payload["project_id"] = projectId
            }
            if let thumbnail = deckDesign.thumbnailURL, !thumbnail.isEmpty {
                payload["thumbnail_url"] = thumbnail
            }
            if let createdBy = deckDesign.createdBy, !createdBy.isEmpty {
                payload["created_by"] = createdBy
            }
            syncEngine.recordOperation(
                entityType: .deckDesign,
                entityId: deckDesign.id,
                operationType: "create",
                changedFields: payload,
                priority: 1
            )
            hasEnqueuedCreate = true
            return
        }

        var payload: [String: Any] = [
            "title": deckDesign.title,
            "drawing_data": drawingObject,
            "version": deckDesign.version,
            "updated_at": nowIso
        ]
        if let thumbnail = deckDesign.thumbnailURL, !thumbnail.isEmpty {
            payload["thumbnail_url"] = thumbnail
        }
        syncEngine.recordOperation(
            entityType: .deckDesign,
            entityId: deckDesign.id,
            operationType: "update",
            changedFields: payload,
            priority: 1
        )
    }

    private static func drawingObject(from drawingData: DeckDrawingData) -> Any {
        let drawingJSONString = drawingData.toJSON()
        return (try? JSONSerialization.jsonObject(
            with: Data(drawingJSONString.utf8),
            options: []
        )) ?? [String: Any]()
    }
}

enum OPSDeckRuntimeFactory {
    @MainActor
    static func make(
        deckDesign: DeckDesign,
        modelContext: ModelContext?,
        syncEngine: SyncEngine?,
        projectName: String?
    ) -> DeckRuntime {
        DeckRuntime(
            context: DeckRuntimeContext(
                companyId: deckDesign.companyId,
                projectId: deckDesign.projectId,
                projectName: projectName,
                appSurface: .ops
            ),
            store: OPSDeckStore(
                deckDesign: deckDesign,
                modelContext: modelContext
            ),
            syncQueue: OPSDeckSyncQueue(
                deckDesign: deckDesign,
                syncEngine: syncEngine
            )
        )
    }
}
