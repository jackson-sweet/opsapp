//
//  DimensionedAnnotationWorkflow.swift
//  OPS
//
//  Small pure workflow helpers for post-capture annotation continuity.
//

import Foundation
import SwiftData

public enum DimensionedAnnotationCloseDecision: Equatable {
    case dismiss
    case confirmDiscard
}

public enum DimensionedAnnotationSaveState: Equatable {
    case idle
    case saving(copy: String)
    case failed(copy: String)
    case queued(copy: String)

    public var copy: String? {
        switch self {
        case .idle:
            return nil
        case .saving(let copy), .failed(let copy), .queued(let copy):
            return copy
        }
    }

    public var allowsRetry: Bool {
        switch self {
        case .failed, .queued:
            return true
        case .idle, .saving:
            return false
        }
    }

    public var isVisible: Bool {
        copy != nil
    }
}

public enum DimensionedAnnotationSaveResult: Equatable {
    case synced
    case queuedForRetry
}

public struct DimensionedAnnotationSaveContinuity: Equatable {
    public let saveState: DimensionedAnnotationSaveState
    public let keepsOperatorInContext: Bool
    public let leavesAnnotationDirty: Bool
}

enum DimensionedAnnotationWorkflow {
    static func dirtyAfterMeasurementCommit(previouslyDirty: Bool) -> Bool {
        true
    }

    static func dirtyAfterAutoMeasure(
        addedMeasurementCount: Int,
        previouslyDirty: Bool
    ) -> Bool {
        previouslyDirty || addedMeasurementCount > 0
    }

    static func dirtyAfterCalibrationResult(previouslyDirty: Bool) -> Bool {
        true
    }

    static func closeDecision(
        hasUnsavedChanges: Bool,
        saveState: DimensionedAnnotationSaveState
    ) -> DimensionedAnnotationCloseDecision {
        if hasUnsavedChanges {
            return .confirmDiscard
        }
        if case .saving = saveState {
            return .confirmDiscard
        }
        return .dismiss
    }

    static func saveFailureState() -> DimensionedAnnotationSaveContinuity {
        DimensionedAnnotationSaveContinuity(
            saveState: .failed(copy: failedCopy),
            keepsOperatorInContext: true,
            leavesAnnotationDirty: true
        )
    }

    static func queuedSaveState() -> DimensionedAnnotationSaveContinuity {
        DimensionedAnnotationSaveContinuity(
            saveState: .queued(copy: queuedCopy),
            keepsOperatorInContext: true,
            leavesAnnotationDirty: false
        )
    }

    static let savingCopy = "// SAVING MEASUREMENTS"
    static let failedCopy = "// SAVE FAILED · RETRY"
    static let queuedCopy = "// SYNC QUEUED · RETRY"
}

enum DimensionedCaptureSaveStoreError: LocalizedError {
    case missingQueuedAnnotation
    case saveAlreadyInFlight

    var errorDescription: String? {
        switch self {
        case .missingQueuedAnnotation:
            return "Queued measurement payload missing"
        case .saveAlreadyInFlight:
            return "Measurement save already in progress"
        }
    }
}

@MainActor
enum DimensionedCaptureSaveStore {
    static func localQueuedAnnotationID(for captured: CapturedAssets) -> String {
        "local-\(captured.captureID.uuidString)"
    }

    static func persistQueuedAnnotation(
        captured: CapturedAssets,
        modelContext: ModelContext
    ) throws -> PhotoAnnotation {
        guard let queued = DimensionedPhotoSyncManager.lastQueuedAnnotation else {
            throw DimensionedCaptureSaveStoreError.missingQueuedAnnotation
        }

        if let existing = try fetchAnnotation(
            id: localQueuedAnnotationID(for: captured),
            modelContext: modelContext
        ) {
            copyQueuedFields(from: queued, to: existing)
            try modelContext.save()
            DimensionedPhotoSyncManager.lastQueuedAnnotation = nil
            return existing
        }

        modelContext.insert(queued)
        try modelContext.save()
        DimensionedPhotoSyncManager.lastQueuedAnnotation = nil
        return queued
    }

    static func persistSyncedAnnotation(
        _ annotation: PhotoAnnotation,
        captured: CapturedAssets,
        modelContext: ModelContext
    ) throws {
        if let queued = try fetchAnnotation(
            id: localQueuedAnnotationID(for: captured),
            modelContext: modelContext
        ) {
            modelContext.delete(queued)
        }

        if let existing = try fetchAnnotation(id: annotation.id, modelContext: modelContext) {
            copySyncedFields(from: annotation, to: existing)
        } else {
            modelContext.insert(annotation)
        }
        try modelContext.save()
    }

    private static func fetchAnnotation(
        id: String,
        modelContext: ModelContext
    ) throws -> PhotoAnnotation? {
        var descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func copyQueuedFields(
        from source: PhotoAnnotation,
        to target: PhotoAnnotation
    ) {
        target.projectId = source.projectId
        target.companyId = source.companyId
        target.photoURL = source.photoURL
        target.annotationURL = source.annotationURL
        target.note = source.note
        target.authorId = source.authorId
        target.createdAt = source.createdAt
        target.updatedAt = source.updatedAt
        target.deletedAt = source.deletedAt
        target.renderedPhotoURL = source.renderedPhotoURL
        target.lastSyncedAt = source.lastSyncedAt
        target.needsSync = source.needsSync
        target.localDrawingData = source.localDrawingData
        target.dimensionsData = source.dimensionsData
        target.localDepthMapPath = source.localDepthMapPath
        target.localSidecarPath = source.localSidecarPath
        target.localCaptureFinishedAt = source.localCaptureFinishedAt
    }

    private static func copySyncedFields(
        from source: PhotoAnnotation,
        to target: PhotoAnnotation
    ) {
        copyQueuedFields(from: source, to: target)
        target.needsSync = false
        target.lastSyncedAt = source.lastSyncedAt ?? Date()
    }
}
