//
//  DimensionedPhotoSyncManager.swift
//  OPS
//
//  Phase F — orchestrates the HEIC + sidecar + optional-depth upload pipeline
//  for a dimensioned capture (spec §7) and inserts the matching SwiftData +
//  Supabase rows so the photo appears in the gallery and in the office
//  web portal.
//
//  Asset pipeline (all uploads via the existing `PresignedURLUploadService`):
//
//    1. HEIC photo with embedded Disparity aux channel when depth exists
//         → S3, content-type `image/heic`
//         → URL stored on a new `project_photos` row with
//           `source = 'measurement'`, `is_client_visible = false`
//    2. Sidecar metadata JSON (ARKit anchors + intrinsics + device pose)
//         → S3, content-type `application/json`
//         → URL stored in `DimensionsData.sidecarMetadataUrl`
//    3. Standalone FP32 depth grid (LiDAR only)
//         → S3, content-type `application/octet-stream`
//         → URL stored in `DimensionsData.depthAssetUrl`
//
//  After the required assets land, a `project_photo_annotations` row is
//  inserted with the `dimensions` jsonb column populated via the typed
//  `PhotoAnnotation.dimensions` accessor (Phase A added this).
//
//  Failure handling per spec §7 + brief: each asset retries up to 3 times
//  with exponential backoff (0.5s, 1.5s, 4.5s). If any required asset still fails,
//  the manager persists the local cache paths in
//  `PhotoAnnotation.localDepthMapPath` / `.localSidecarPath` /
//  `.localCaptureFinishedAt`, marks `needsSync = true`, and throws
//  `DimensionedSyncError.queuedForRetry`. The caller surfaces a
//  `measurement_pending_sync` notification (spec §6) — the file lives on
//  disk and the next `syncPendingDimensions(modelContext:)` pass retries.
//
//  Mirrors the queue + retry pattern from `PhotoAnnotationSyncManager`
//  (PencilKit annotations) per brief constraint "Reuse existing
//  `PhotoAnnotationSyncManager` patterns for queue + retry logic — mirror,
//  don't reinvent."
//
//  Public API per brief (updated 2026-05-12 for Phase G coordination —
//  added `projectName` for notification body formatting per spec §6):
//      func sync(captured: CapturedAssets,
//                dimensions: DimensionsData,
//                projectId: String,
//                projectName: String,
//                companyId: String,
//                userId: String) async throws -> PhotoAnnotation
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md
//      §3.7 (output / deliverable)
//      §7   (storage, three-asset pipeline, 90-day FP32 lifecycle)
//      §6   (notification mapping)
//

import Foundation
import SwiftData
import Supabase

// MARK: - Protocols for testability

/// Single-asset upload primitive. The live impl wraps
/// `PresignedURLUploadService.uploadAsset`; tests inject a mock that simulates
/// success / N-th-attempt failure.
public protocol DimensionedAssetUploader {
    func uploadAsset(
        _ data: Data,
        filename: String,
        folder: String,
        contentType: String
    ) async throws -> String
}

/// Live uploader — wraps the shared `PresignedURLUploadService`.
public struct LivePresignedAssetUploader: DimensionedAssetUploader {
    public init() {}
    @MainActor
    public func uploadAsset(
        _ data: Data,
        filename: String,
        folder: String,
        contentType: String
    ) async throws -> String {
        try await PresignedURLUploadService.shared.uploadAsset(
            data,
            filename: filename,
            folder: folder,
            contentType: contentType
        )
    }
}

/// Persists the two server-side rows that close the loop on a dimensioned
/// capture: a `project_photos` row (so the web portal sees the photo) and a
/// `project_photo_annotations` row (so the dimensions jsonb is queryable).
public protocol DimensionedAnnotationPersister {
    func insertProjectPhotoRow(
        url: String,
        projectId: String,
        companyId: String,
        uploadedBy: String,
        takenAt: Date
    ) async throws

    func insertAnnotationRow(
        photoUrl: String,
        projectId: String,
        companyId: String,
        authorId: String,
        dimensions: DimensionsData
    ) async throws -> InsertedAnnotation
}

@MainActor
protocol DimensionedPendingSyncing: AnyObject {
    func pendingDimensionedAnnotationCount(modelContext: ModelContext) -> Int
    func syncPendingDimensions(modelContext: ModelContext) async
}

/// Slim DTO returned by the persister so the manager can hydrate a
/// `PhotoAnnotation` SwiftData model with the server-assigned id + timestamps.
public struct InsertedAnnotation: Equatable {
    public let id: String
    public let createdAt: Date

    public init(id: String, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

/// Live persister — talks to Supabase directly. The two inserts follow the
/// same pattern `ImageSyncManager.insertProjectPhotoRows` uses for standard
/// project photos: best-effort `project_photos` insert (a failure logs but
/// doesn't block the annotation), authoritative `project_photo_annotations`
/// insert (failure throws).
public struct LiveDimensionedAnnotationPersister: DimensionedAnnotationPersister {
    public init() {}

    @MainActor
    public func insertProjectPhotoRow(
        url: String,
        projectId: String,
        companyId: String,
        uploadedBy: String,
        takenAt: Date
    ) async throws {
        struct ProjectPhotoInsert: Codable {
            let project_id: String
            let company_id: String
            let url: String
            let source: String
            let uploaded_by: String
            let is_client_visible: Bool
            let taken_at: String
        }

        let row = ProjectPhotoInsert(
            project_id: projectId,
            company_id: companyId,
            url: url,
            source: "measurement",
            uploaded_by: uploadedBy,
            is_client_visible: false,
            taken_at: ISO8601DateFormatter().string(from: takenAt)
        )

        try await SupabaseService.shared.client
            .from("project_photos")
            .insert(row)
            .execute()
    }

    @MainActor
    public func insertAnnotationRow(
        photoUrl: String,
        projectId: String,
        companyId: String,
        authorId: String,
        dimensions: DimensionsData
    ) async throws -> InsertedAnnotation {
        // Build the insert payload manually so the nested `dimensions` value is
        // emitted as JSONB (a Postgres object), not as base64-encoded Data. The
        // `DimensionsJSONValue` round-trip uses `DimensionsData.jsonEncoder` (snake_case)
        // so the persisted keys match the spec §4.1 schema verbatim.
        let dimensionsJSON = try Self.encodeDimensionsAsDimensionsJSONValue(dimensions)
        let payload = AnnotationInsert(
            project_id: projectId,
            company_id: companyId,
            photo_url: photoUrl,
            annotation_url: nil,
            note: "",
            author_id: authorId,
            dimensions: dimensionsJSON
        )

        let response: AnnotationInsertResponse = try await SupabaseService.shared.client
            .from("project_photo_annotations")
            .insert(payload)
            .select("id, created_at")
            .single()
            .execute()
            .value

        let createdAt = SupabaseDate.parse(response.created_at) ?? Date()
        return InsertedAnnotation(id: response.id, createdAt: createdAt)
    }

    private struct AnnotationInsert: Encodable {
        let project_id: String
        let company_id: String
        let photo_url: String
        let annotation_url: String?
        let note: String
        let author_id: String
        let dimensions: DimensionsJSONValue
    }

    private struct AnnotationInsertResponse: Decodable {
        let id: String
        let created_at: String
    }

    static func encodeDimensionsAsDimensionsJSONValue(_ dimensions: DimensionsData) throws -> DimensionsJSONValue {
        let data = try DimensionsData.jsonEncoder.encode(dimensions)
        return try JSONDecoder().decode(DimensionsJSONValue.self, from: data)
    }
}

// MARK: - JSON value wrapper for nested jsonb insert

/// Minimal recursive JSON tree used to forward an already-serialised
/// `DimensionsData` blob through the outer Postgrest Encodable container
/// without losing the snake_case key encoding `DimensionsData.jsonEncoder`
/// applied.
public indirect enum DimensionsJSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([DimensionsJSONValue])
    case object([String: DimensionsJSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([DimensionsJSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: DimensionsJSONValue].self) { self = .object(o); return }
        throw DecodingError.typeMismatch(
            DimensionsJSONValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unrecognised JSON value")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let b):   try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a):  try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - Errors

public enum DimensionedSyncError: Error, LocalizedError, Equatable {
    /// All three asset uploads attempted; at least one still failed after
    /// retries. The local cache paths have been persisted to a
    /// `PhotoAnnotation` row marked `needsSync = true` — call
    /// `syncPendingDimensions` after connectivity returns.
    case queuedForRetry(reason: String)

    /// The annotation row insert itself failed (DB error after assets succeeded).
    /// Local cache is preserved for retry.
    case annotationInsertFailed(reason: String)

    /// The HEIC / depth / sidecar file isn't readable from disk. Indicates a
    /// capture-pipeline bug — not a sync failure.
    case missingLocalAsset(URL)

    /// A LiDAR dimensions payload reached sync without the required standalone
    /// FP32 depth asset. Visual captures may omit depth; LiDAR captures may not.
    case missingRequiredDepthAsset

    public var errorDescription: String? {
        switch self {
        case .queuedForRetry(let r):       return "Dimensioned capture queued for retry: \(r)"
        case .annotationInsertFailed(let r): return "Annotation row insert failed: \(r)"
        case .missingLocalAsset(let url):  return "Local asset missing: \(url.lastPathComponent)"
        case .missingRequiredDepthAsset:   return "LiDAR capture missing required depth asset"
        }
    }
}

// MARK: - Manager

@MainActor
public final class DimensionedPhotoSyncManager: DimensionedPendingSyncing {

    public static let shared = DimensionedPhotoSyncManager()

    /// Maximum upload attempts per asset (initial + 2 retries = 3 total).
    public static let maxAttempts = 3

    /// Exponential backoff base — attempt N waits `baseDelaySeconds * 3^(N-1)`.
    /// With base=0.5 the schedule is 0.5s, 1.5s, 4.5s. Field-first: short enough
    /// the user doesn't bail, long enough to recover from a flaky cell signal.
    public static let baseDelaySeconds: Double = 0.5

    private let uploader: DimensionedAssetUploader
    private let persister: DimensionedAnnotationPersister
    private let notifier: DimensionedNotificationDispatcher

    /// Internal because the new `notifier` parameter type
    /// `DimensionedNotificationDispatcher` references
    /// `MeasurementNotificationCopy.CapturedBodySummary` which is internal
    /// to the module. Same-module callers use `.shared` (still public).
    init(
        uploader: DimensionedAssetUploader = LivePresignedAssetUploader(),
        persister: DimensionedAnnotationPersister = LiveDimensionedAnnotationPersister(),
        notifier: DimensionedNotificationDispatcher = LiveDimensionedNotificationDispatcher()
    ) {
        self.uploader = uploader
        self.persister = persister
        self.notifier = notifier
    }

    // MARK: - Public API (per brief)

    /// Upload the three assets, insert the project_photos row + annotation row,
    /// return a hydrated `PhotoAnnotation` model. Caller is responsible for
    /// `modelContext.insert(_:)` and `modelContext.save()` after success — this
    /// keeps the manager free of SwiftData store coupling and lets the caller
    /// roll back if surrounding state changes need to abort.
    ///
    /// Internal because the return type `PhotoAnnotation` is a SwiftData @Model
    /// class with internal access. Same-module callers use `.shared.sync(...)`.
    func sync(
        captured: CapturedAssets,
        dimensions: DimensionsData,
        projectId: String,
        projectName: String,
        companyId: String,
        userId: String
    ) async throws -> PhotoAnnotation {

        guard dimensions.captureMode != .lidar || captured.depthURL != nil else {
            throw DimensionedSyncError.missingRequiredDepthAsset
        }

        // 1. Read assets off disk up front. LiDAR captures include a standalone
        // depth file; visual captures intentionally do not.
        let heicData = try readAsset(captured.heicURL)
        let sidecarData = try readAsset(captured.sidecarURL)
        let depthData = try captured.depthURL.map { try readAsset($0) }

        let folder = "measurements/\(companyId)/\(projectId)"
        let captureID = captured.captureID.uuidString

        // 2. Attempt all present uploads with per-asset retry. Any failure after
        // retries falls through to the queue-for-retry path.
        var uploadedHeic: String?
        var uploadedSidecar: String?
        var uploadedDepth: String?
        var failureReason: String?

        do {
            uploadedHeic = try await uploadWithRetry(
                data: heicData,
                filename: "\(captureID).heic",
                folder: folder,
                contentType: "image/heic",
                label: "heic"
            )
            uploadedSidecar = try await uploadWithRetry(
                data: sidecarData,
                filename: "\(captureID).metadata.json",
                folder: folder,
                contentType: "application/json",
                label: "sidecar"
            )
            if let depthData {
                uploadedDepth = try await uploadWithRetry(
                    data: depthData,
                    filename: "\(captureID).depth.fp32",
                    folder: folder,
                    contentType: "application/octet-stream",
                    label: "depth"
                )
            }
        } catch {
            failureReason = "\(error)"
        }

        guard
            let heicURLString = uploadedHeic,
            let sidecarURLString = uploadedSidecar,
            depthData == nil || uploadedDepth != nil
        else {
            // 2a. Failure path — persist local cache + queue for retry.
            let stub = makeQueuedAnnotation(
                captured: captured,
                dimensions: dimensions,
                projectId: projectId,
                companyId: companyId,
                authorId: userId
            )
            await MainActor.run {
                Self.lastQueuedAnnotation = stub
            }
            await notifier.dispatchPendingSync(
                userId: userId,
                companyId: companyId,
                projectId: projectId,
                queueDepth: 1
            )
            throw DimensionedSyncError.queuedForRetry(
                reason: failureReason ?? "unknown upload failure"
            )
        }

        // 3. Decorate dimensions with the persisted asset URLs (the worldPoints /
        // measurements list was authored by the annotation view; we only wire in
        // the URLs that didn't exist until upload finished).
        var enriched = dimensions
        enriched.sidecarMetadataUrl = sidecarURLString
        enriched.depthAssetUrl = uploadedDepth

        // 4. Best-effort `project_photos` row so the web portal sees the photo.
        // Mirrors the `ImageSyncManager.insertProjectPhotoRows` pattern — a
        // failure here logs but doesn't block the annotation insert.
        //
        // Auto-bug-reporting (May-12 follow-up): same RLS-tightening shape
        // that triggered the original outage applies here too. Classify
        // and auto-bug if permanent so we don't repeat the silent loss.
        do {
            try await persister.insertProjectPhotoRow(
                url: heicURLString,
                projectId: projectId,
                companyId: companyId,
                uploadedBy: userId,
                takenAt: captured.captureFinishedAt
            )
        } catch {
            await AutoBugReporter.shared.reportIfPermanent(
                error,
                screen: "DimensionedPhotoSyncManager.insertProjectPhotoRow",
                suspectedFile: "DimensionedPhotoSyncManager.swift",
                summary: "LiDAR project_photos INSERT failed for \(projectId): \(error.localizedDescription)",
                metadata: [
                    "project_id": projectId,
                    "company_id": companyId,
                    "capture_id": captured.captureID.uuidString
                ]
            )
            DebugLogger.shared.log(
                "LiDAR project_photos insert failed (continuing): \(error)",
                level: .warning,
                category: "DimensionedPhotoSyncManager"
            )
        }

        // 5. Authoritative `project_photo_annotations` insert with dimensions jsonb.
        let inserted: InsertedAnnotation
        do {
            inserted = try await persister.insertAnnotationRow(
                photoUrl: heicURLString,
                projectId: projectId,
                companyId: companyId,
                authorId: userId,
                dimensions: enriched
            )
        } catch {
            // Auto-bug if permanent — a 42501 on annotation insert means
            // a parallel RLS tightening on project_photo_annotations and
            // would silently kill measurement sync if we just queued it.
            await AutoBugReporter.shared.reportIfPermanent(
                error,
                screen: "DimensionedPhotoSyncManager.insertAnnotationRow",
                suspectedFile: "DimensionedPhotoSyncManager.swift",
                summary: "LiDAR annotation INSERT failed for \(projectId): \(error.localizedDescription)",
                metadata: [
                    "project_id": projectId,
                    "company_id": companyId,
                    "capture_id": captured.captureID.uuidString,
                    "photo_url": heicURLString
                ]
            )

            let stub = makeQueuedAnnotation(
                captured: captured,
                dimensions: enriched,
                projectId: projectId,
                companyId: companyId,
                authorId: userId
            )
            // Override the photoURL since the upload DID succeed — re-sync only
            // needs to retry the annotation row, not the asset uploads.
            stub.photoURL = heicURLString
            await MainActor.run {
                Self.lastQueuedAnnotation = stub
            }
            await notifier.dispatchPendingSync(
                userId: userId,
                companyId: companyId,
                projectId: projectId,
                queueDepth: 1
            )
            throw DimensionedSyncError.annotationInsertFailed(
                reason: "\(error)"
            )
        }

        // 6. Build the hydrated `PhotoAnnotation` model. Use the server-assigned
        // id so subsequent local fetches by id match Supabase.
        let model = PhotoAnnotation(
            id: inserted.id,
            projectId: projectId,
            companyId: companyId,
            photoURL: heicURLString,
            authorId: userId,
            createdAt: inserted.createdAt
        )
        model.dimensions = enriched
        model.localDepthMapPath = captured.depthURL?.path
        model.localSidecarPath = captured.sidecarURL.path
        model.localCaptureFinishedAt = captured.captureFinishedAt
        model.lastSyncedAt = Date()
        model.needsSync = false

        // 7. Spec §6: fire `measurement_captured` when a body summary can be
        // derived from the dimensions. Manual-only captures with no opening +
        // fewer than two linear measurements skip the notification silently —
        // the UI dismissal back to the project view is sufficient feedback.
        if let summary = Self.capturedBodySummary(from: enriched) {
            await notifier.dispatchCaptured(
                userId: userId,
                companyId: companyId,
                projectId: projectId,
                projectName: projectName,
                summary: summary,
                photoAnnotationId: inserted.id
            )
        }
        return model
    }

    // MARK: - Internal — captured-body summary derivation (spec §6)

    /// Derive a `CapturedBodySummary` from a `DimensionsData` blob for the
    /// `measurement_captured` notification body. Returns `nil` when the capture
    /// is too sparse to produce a meaningful summary (no openings + < 2 linear
    /// measurements) — the caller skips firing in that case.
    static func capturedBodySummary(
        from dimensions: DimensionsData
    ) -> MeasurementNotificationCopy.CapturedBodySummary? {
        if let opening = dimensions.openings.first {
            switch opening.type {
            case .window, .door:
                return openingSummary(for: opening, in: dimensions)
            case .wallSection:
                return wallSectionSummary(for: opening, in: dimensions)
            }
        }
        // No opening detected — fall back to wall-section heuristic when we
        // have at least two linear measurements to interpret as width × height.
        if dimensions.measurements.filter({ $0.type == .linear }).count >= 2 {
            return wallSectionSummary(for: nil, in: dimensions)
        }
        return nil
    }

    private static func openingSummary(
        for opening: DimensionsData.Opening,
        in dimensions: DimensionsData
    ) -> MeasurementNotificationCopy.CapturedBodySummary? {
        let related = dimensions.measurements.filter { opening.measurementIds.contains($0.id) }
        guard !related.isEmpty else { return nil }

        let width = related.first { $0.label.range(of: "width", options: .caseInsensitive) != nil }
        let height = related.first { $0.label.range(of: "height", options: .caseInsensitive) != nil }
        let sill = related.first { $0.label.range(of: "sill", options: .caseInsensitive) != nil }

        guard let width, let height else { return nil }

        let widthInches = inchesRounded(metres: width.valueMeters)
        let heightInches = inchesRounded(metres: height.valueMeters)
        let sillInches = sill.map { inchesRounded(metres: $0.valueMeters) } ?? 0
        let type: MeasurementNotificationCopy.CapturedBodySummary.OpeningType =
            opening.type == .door ? .door : .window

        return .opening(
            widthInches: widthInches,
            heightInches: heightInches,
            type: type,
            sillInches: sillInches
        )
    }

    private static func wallSectionSummary(
        for opening: DimensionsData.Opening?,
        in dimensions: DimensionsData
    ) -> MeasurementNotificationCopy.CapturedBodySummary? {
        let pool: [DimensionsData.Measurement] = {
            if let opening {
                return dimensions.measurements.filter { opening.measurementIds.contains($0.id) }
            }
            return dimensions.measurements.filter { $0.type == .linear }
        }()
        guard pool.count >= 2 else { return nil }
        let sorted = pool.sorted { $0.valueMeters > $1.valueMeters }
        let widthInches = inchesRounded(metres: sorted[0].valueMeters)
        let heightInches = inchesRounded(metres: sorted[1].valueMeters)
        return .wallSection(
            widthFeet: widthInches / 12,
            widthInches: widthInches % 12,
            heightFeet: heightInches / 12
        )
    }

    /// Meters → integer inches, rounded to the nearest inch.
    private static func inchesRounded(metres: Double) -> Int {
        Int((metres / 0.0254).rounded())
    }

    // MARK: - Retry pass for queued captures

    /// Re-attempt uploads for any `PhotoAnnotation` rows that finished a LiDAR
    /// capture locally but failed to upload at the time. Mirrors the
    /// `PhotoAnnotationSyncManager.syncPendingAnnotations` pattern — best
    /// effort, logs failures rather than throwing so a partial sweep can
    /// still succeed on the rows it can handle.
    public func syncPendingDimensions(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate {
                $0.needsSync == true
                    && $0.dimensionsData != nil
                    && $0.deletedAt == nil
            }
        )

        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else {
            return
        }

        print("[DIMENSIONED_SYNC] Found \(pending.count) pending dimensioned captures to retry")

        for annotation in pending {
            guard
                let dims = annotation.dimensions,
                let sidecarPath = annotation.localSidecarPath,
                let finishedAt = annotation.localCaptureFinishedAt
            else { continue }

            guard dims.captureMode != .lidar || annotation.localDepthMapPath != nil else {
                print("[DIMENSIONED_SYNC] Skipping \(annotation.id) — LiDAR depth asset missing")
                continue
            }

            let depthURL = annotation.localDepthMapPath.map(URL.init(fileURLWithPath:))
            let sidecarURL = URL(fileURLWithPath: sidecarPath)
            // The HEIC URL convention from `CapturedAssets._AssetURLs` is the
            // sidecar URL's parent + `<captureID>.heic`. The captureID isn't
            // stored on the annotation, so derive it from the sidecar filename
            // which we control (`<uuid>.metadata.json`).
            let captureID = sidecarURL.deletingPathExtension().deletingPathExtension()
                .lastPathComponent
            let heicURL = sidecarURL.deletingLastPathComponent()
                .appendingPathComponent("\(captureID).heic")

            guard let heicData = try? Data(contentsOf: heicURL),
                  let sidecarData = try? Data(contentsOf: sidecarURL)
            else {
                print("[DIMENSIONED_SYNC] Skipping \(annotation.id) — local asset missing")
                continue
            }
            let depthData: Data?
            if let depthURL {
                guard let data = try? Data(contentsOf: depthURL) else {
                    print("[DIMENSIONED_SYNC] Skipping \(annotation.id) — local depth asset missing")
                    continue
                }
                depthData = data
            } else {
                depthData = nil
            }

            do {
                let folder = "measurements/\(annotation.companyId)/\(annotation.projectId)"
                let heicURLString = try await uploadWithRetry(
                    data: heicData,
                    filename: "\(captureID).heic",
                    folder: folder,
                    contentType: "image/heic",
                    label: "heic"
                )
                let sidecarURLString = try await uploadWithRetry(
                    data: sidecarData,
                    filename: "\(captureID).metadata.json",
                    folder: folder,
                    contentType: "application/json",
                    label: "sidecar"
                )
                let depthURLString: String?
                if let depthData {
                    depthURLString = try await uploadWithRetry(
                        data: depthData,
                        filename: "\(captureID).depth.fp32",
                        folder: folder,
                        contentType: "application/octet-stream",
                        label: "depth"
                    )
                } else {
                    depthURLString = nil
                }

                var enriched = dims
                enriched.sidecarMetadataUrl = sidecarURLString
                enriched.depthAssetUrl = depthURLString

                try? await persister.insertProjectPhotoRow(
                    url: heicURLString,
                    projectId: annotation.projectId,
                    companyId: annotation.companyId,
                    uploadedBy: annotation.authorId,
                    takenAt: finishedAt
                )

                let inserted = try await persister.insertAnnotationRow(
                    photoUrl: heicURLString,
                    projectId: annotation.projectId,
                    companyId: annotation.companyId,
                    authorId: annotation.authorId,
                    dimensions: enriched
                )

                annotation.id = inserted.id
                annotation.photoURL = heicURLString
                annotation.dimensions = enriched
                annotation.needsSync = false
                annotation.lastSyncedAt = Date()
                try? modelContext.save()
            } catch {
                // Auto-bug-reporting (May-12 follow-up): the queued-retry
                // loop will hammer the same poisoned row every retry pass.
                // If the underlying cause is permanent, we need to know
                // immediately so the dev team can intervene before the
                // user's measurement queue silently bloats.
                await AutoBugReporter.shared.reportIfPermanent(
                    error,
                    screen: "DimensionedPhotoSyncManager.retryQueued",
                    suspectedFile: "DimensionedPhotoSyncManager.swift",
                    summary: "Queued LiDAR annotation retry failed for \(annotation.id): \(error.localizedDescription)",
                    metadata: [
                        "annotation_id": annotation.id,
                        "project_id": annotation.projectId,
                        "company_id": annotation.companyId
                    ]
                )
                DebugLogger.shared.log(
                    "DimensionedPhotoSyncManager retry failed for \(annotation.id): \(error)",
                    level: .warning,
                    category: "DimensionedPhotoSyncManager"
                )
            }
        }
    }

    func pendingDimensionedAnnotationCount(modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate {
                $0.needsSync == true
                    && $0.dimensionsData != nil
                    && $0.deletedAt == nil
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Internal — per-asset retry with exponential backoff

    func uploadWithRetry(
        data: Data,
        filename: String,
        folder: String,
        contentType: String,
        label: String
    ) async throws -> String {
        var lastError: Error?
        for attempt in 1...Self.maxAttempts {
            do {
                return try await uploader.uploadAsset(
                    data,
                    filename: filename,
                    folder: folder,
                    contentType: contentType
                )
            } catch {
                lastError = error
                if attempt < Self.maxAttempts {
                    let delay = Self.baseDelaySeconds * pow(3.0, Double(attempt - 1))
                    let ns = UInt64(delay * 1_000_000_000)
                    print("[DIMENSIONED_SYNC] \(label) upload attempt \(attempt) failed; retrying in \(delay)s")
                    try? await Task.sleep(nanoseconds: ns)
                }
            }
        }
        throw lastError ?? DimensionedSyncError.queuedForRetry(reason: "\(label) failed")
    }

    // MARK: - Internal — local-cache stub for queued state

    private func makeQueuedAnnotation(
        captured: CapturedAssets,
        dimensions: DimensionsData,
        projectId: String,
        companyId: String,
        authorId: String
    ) -> PhotoAnnotation {
        // Use a local-only id so duplicate queued rows from repeat captures
        // don't collide. The server id replaces this on successful retry.
        let model = PhotoAnnotation(
            id: "local-\(captured.captureID.uuidString)",
            projectId: projectId,
            companyId: companyId,
            photoURL: captured.heicURL.path,
            authorId: authorId,
            createdAt: captured.captureFinishedAt
        )
        model.dimensions = dimensions
        model.localDepthMapPath = captured.depthURL?.path
        model.localSidecarPath = captured.sidecarURL.path
        model.localCaptureFinishedAt = captured.captureFinishedAt
        model.needsSync = true
        return model
    }

    // MARK: - Internal — disk reads

    private func readAsset(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw DimensionedSyncError.missingLocalAsset(url)
        }
    }
}

extension DimensionedPhotoSyncManager {
    /// Holds the most recent queued-for-retry `PhotoAnnotation` so the caller
    /// can pluck it after catching a `DimensionedSyncError.queuedForRetry`.
    /// Single slot — overwritten on each failure. Cleared by the caller after
    /// the local insert.
    ///
    /// Internal because `PhotoAnnotation` is a SwiftData @Model with internal
    /// access. The `.shared` singleton API stays public; same-module callers
    /// (view layer) read this slot to surface the queued stub.
    @MainActor
    static var lastQueuedAnnotation: PhotoAnnotation?
}

// MARK: - Notification dispatch (spec §6)

/// Side-channel for the three measurement notifications. Behind a protocol so
/// tests can verify the DTO contracts without coupling to a live Supabase
/// client. The live implementation calls `NotificationRepository.shared` and
/// swallows-and-logs any error — a missing notification is never worth failing
/// a successful capture over.
protocol DimensionedNotificationDispatcher: Sendable {
    func dispatchCaptured(
        userId: String,
        companyId: String,
        projectId: String,
        projectName: String,
        summary: MeasurementNotificationCopy.CapturedBodySummary,
        photoAnnotationId: String
    ) async

    func dispatchPendingSync(
        userId: String,
        companyId: String,
        projectId: String?,
        queueDepth: Int
    ) async

    func dispatchSyncFailed(
        userId: String,
        companyId: String,
        projectId: String,
        projectName: String,
        photoAnnotationId: String
    ) async
}

/// No-op dispatcher for unit tests that don't care about notification firing.
/// `RecordingNotifier` in the test target handles the observed-call cases.
struct NoopDimensionedNotificationDispatcher: DimensionedNotificationDispatcher {
    init() {}

    func dispatchCaptured(
        userId: String,
        companyId: String,
        projectId: String,
        projectName: String,
        summary: MeasurementNotificationCopy.CapturedBodySummary,
        photoAnnotationId: String
    ) async {}

    func dispatchPendingSync(
        userId: String,
        companyId: String,
        projectId: String?,
        queueDepth: Int
    ) async {}

    func dispatchSyncFailed(
        userId: String,
        companyId: String,
        projectId: String,
        projectName: String,
        photoAnnotationId: String
    ) async {}
}

/// Production dispatcher — talks to Supabase via `NotificationRepository`.
struct LiveDimensionedNotificationDispatcher: DimensionedNotificationDispatcher {
    init() {}

    func dispatchCaptured(
        userId: String,
        companyId: String,
        projectId: String,
        projectName: String,
        summary: MeasurementNotificationCopy.CapturedBodySummary,
        photoAnnotationId: String
    ) async {
        let dto = NotificationRepository.CreateNotificationDTO.measurementCaptured(
            userId: userId,
            companyId: companyId,
            projectId: projectId,
            projectName: projectName,
            summary: summary,
            photoAnnotationId: photoAnnotationId
        )
        do {
            try await NotificationRepository.shared.createNotification(dto)
        } catch {
            print("[DIMENSIONED_SYNC] measurement_captured notification failed (continuing): \(error)")
        }
    }

    func dispatchPendingSync(
        userId: String,
        companyId: String,
        projectId: String?,
        queueDepth: Int
    ) async {
        let dto = NotificationRepository.CreateNotificationDTO.measurementPendingSync(
            userId: userId,
            companyId: companyId,
            projectId: projectId,
            queueDepth: queueDepth
        )
        do {
            try await NotificationRepository.shared.createNotification(dto)
        } catch {
            print("[DIMENSIONED_SYNC] measurement_pending_sync notification failed (continuing): \(error)")
        }
    }

    func dispatchSyncFailed(
        userId: String,
        companyId: String,
        projectId: String,
        projectName: String,
        photoAnnotationId: String
    ) async {
        let dto = NotificationRepository.CreateNotificationDTO.measurementSyncFailed(
            userId: userId,
            companyId: companyId,
            projectId: projectId,
            projectName: projectName,
            photoAnnotationId: photoAnnotationId
        )
        do {
            try await NotificationRepository.shared.createNotification(dto)
        } catch {
            print("[DIMENSIONED_SYNC] measurement_sync_failed notification failed (continuing): \(error)")
        }
    }
}
