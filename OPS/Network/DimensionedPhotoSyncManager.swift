//
//  DimensionedPhotoSyncManager.swift
//  OPS
//
//  Phase F — orchestrates the three-asset upload pipeline for a LiDAR
//  dimensioned capture (spec §7) and inserts the matching SwiftData +
//  Supabase rows so the photo appears in the gallery and in the office
//  web portal.
//
//  Asset pipeline (all uploads via the existing `PresignedURLUploadService`):
//
//    1. HEIC photo with embedded Disparity aux channel
//         → S3, content-type `image/heic`
//         → URL stored on a new `project_photos` row with
//           `source = 'measurement'`, `is_client_visible = false`
//    2. Sidecar metadata JSON (ARKit anchors + intrinsics + device pose)
//         → S3, content-type `application/json`
//         → URL stored in `DimensionsData.sidecarMetadataUrl`
//    3. Standalone FP32 depth grid
//         → S3, content-type `application/octet-stream`
//         → URL stored in `DimensionsData.depthAssetUrl`
//
//  After the three assets land, a `project_photo_annotations` row is
//  inserted with the `dimensions` jsonb column populated via the typed
//  `PhotoAnnotation.dimensions` accessor (Phase A added this).
//
//  Failure handling per spec §7 + brief: each asset retries up to 3 times
//  with exponential backoff (0.5s, 1.5s, 4.5s). If any asset still fails,
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
//  Public API per brief:
//      func sync(captured: CapturedAssets,
//                dimensions: DimensionsData,
//                projectId: String,
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
        // `JSONValue` round-trip uses `DimensionsData.jsonEncoder` (snake_case)
        // so the persisted keys match the spec §4.1 schema verbatim.
        let dimensionsJSON = try Self.encodeDimensionsAsJSONValue(dimensions)
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
        let dimensions: JSONValue
    }

    private struct AnnotationInsertResponse: Decodable {
        let id: String
        let created_at: String
    }

    static func encodeDimensionsAsJSONValue(_ dimensions: DimensionsData) throws -> JSONValue {
        let data = try DimensionsData.jsonEncoder.encode(dimensions)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

// MARK: - JSON value wrapper for nested jsonb insert

/// Minimal recursive JSON tree used to forward an already-serialised
/// `DimensionsData` blob through the outer Postgrest Encodable container
/// without losing the snake_case key encoding `DimensionsData.jsonEncoder`
/// applied.
public indirect enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.typeMismatch(
            JSONValue.self,
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

    public var errorDescription: String? {
        switch self {
        case .queuedForRetry(let r):       return "Dimensioned capture queued for retry: \(r)"
        case .annotationInsertFailed(let r): return "Annotation row insert failed: \(r)"
        case .missingLocalAsset(let url):  return "Local asset missing: \(url.lastPathComponent)"
        }
    }
}

// MARK: - Manager

@MainActor
public final class DimensionedPhotoSyncManager {

    public static let shared = DimensionedPhotoSyncManager()

    /// Maximum upload attempts per asset (initial + 2 retries = 3 total).
    public static let maxAttempts = 3

    /// Exponential backoff base — attempt N waits `baseDelaySeconds * 3^(N-1)`.
    /// With base=0.5 the schedule is 0.5s, 1.5s, 4.5s. Field-first: short enough
    /// the user doesn't bail, long enough to recover from a flaky cell signal.
    public static let baseDelaySeconds: Double = 0.5

    private let uploader: DimensionedAssetUploader
    private let persister: DimensionedAnnotationPersister

    public init(
        uploader: DimensionedAssetUploader = LivePresignedAssetUploader(),
        persister: DimensionedAnnotationPersister = LiveDimensionedAnnotationPersister()
    ) {
        self.uploader = uploader
        self.persister = persister
    }

    // MARK: - Public API (per brief)

    /// Upload the three assets, insert the project_photos row + annotation row,
    /// return a hydrated `PhotoAnnotation` model. Caller is responsible for
    /// `modelContext.insert(_:)` and `modelContext.save()` after success — this
    /// keeps the manager free of SwiftData store coupling and lets the caller
    /// roll back if surrounding state changes need to abort.
    public func sync(
        captured: CapturedAssets,
        dimensions: DimensionsData,
        projectId: String,
        companyId: String,
        userId: String
    ) async throws -> PhotoAnnotation {

        // 1. Read all three assets off disk up front. If any file is missing
        // we fail fast — this is a capture-pipeline bug, not a sync condition.
        let heicData = try readAsset(captured.heicURL)
        let sidecarData = try readAsset(captured.sidecarURL)
        let depthData = try readAsset(captured.depthURL)

        let folder = "measurements/\(companyId)/\(projectId)"
        let captureID = captured.captureID.uuidString

        // 2. Attempt all three uploads with per-asset retry. Any failure after
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
            uploadedDepth = try await uploadWithRetry(
                data: depthData,
                filename: "\(captureID).depth.fp32",
                folder: folder,
                contentType: "application/octet-stream",
                label: "depth"
            )
        } catch {
            failureReason = "\(error)"
        }

        guard
            let heicURLString = uploadedHeic,
            let sidecarURLString = uploadedSidecar,
            let depthURLString = uploadedDepth
        else {
            // 2a. Failure path — persist local cache + queue for retry.
            let stub = makeQueuedAnnotation(
                captured: captured,
                dimensions: dimensions,
                projectId: projectId,
                companyId: companyId,
                authorId: userId
            )
            throw DimensionedSyncError.queuedForRetry(
                reason: failureReason ?? "unknown upload failure"
            ).attach(annotation: stub)
        }

        // 3. Decorate dimensions with the persisted asset URLs (the worldPoints /
        // measurements list was authored by the annotation view; we only wire in
        // the URLs that didn't exist until upload finished).
        var enriched = dimensions
        enriched.sidecarMetadataUrl = sidecarURLString
        enriched.depthAssetUrl = depthURLString

        // 4. Best-effort `project_photos` row so the web portal sees the photo.
        // Mirrors the `ImageSyncManager.insertProjectPhotoRows` pattern — a
        // failure here logs but doesn't block the annotation insert.
        do {
            try await persister.insertProjectPhotoRow(
                url: heicURLString,
                projectId: projectId,
                companyId: companyId,
                uploadedBy: userId,
                takenAt: captured.captureFinishedAt
            )
        } catch {
            print("[DIMENSIONED_SYNC] project_photos insert failed (continuing): \(error)")
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
            throw DimensionedSyncError.annotationInsertFailed(
                reason: "\(error)"
            ).attach(annotation: stub)
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
        model.localDepthMapPath = captured.depthURL.path
        model.localSidecarPath = captured.sidecarURL.path
        model.localCaptureFinishedAt = captured.captureFinishedAt
        model.lastSyncedAt = Date()
        model.needsSync = false
        return model
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
                let depthPath = annotation.localDepthMapPath,
                let sidecarPath = annotation.localSidecarPath,
                let finishedAt = annotation.localCaptureFinishedAt
            else { continue }

            let depthURL = URL(fileURLWithPath: depthPath)
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
                  let sidecarData = try? Data(contentsOf: sidecarURL),
                  let depthData = try? Data(contentsOf: depthURL)
            else {
                print("[DIMENSIONED_SYNC] Skipping \(annotation.id) — local asset missing")
                continue
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
                let depthURLString = try await uploadWithRetry(
                    data: depthData,
                    filename: "\(captureID).depth.fp32",
                    folder: folder,
                    contentType: "application/octet-stream",
                    label: "depth"
                )

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
                print("[DIMENSIONED_SYNC] Retry failed for \(annotation.id): \(error)")
            }
        }
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
        model.localDepthMapPath = captured.depthURL.path
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

// MARK: - Error annotation attachment

private struct AnnotationErrorContext {
    let annotation: PhotoAnnotation
}

private extension DimensionedSyncError {
    /// Attaches the locally-persisted `PhotoAnnotation` stub to the error so the
    /// caller (Phase G) can insert it into the SwiftData store and surface
    /// `measurement_pending_sync` without losing the in-flight context.
    /// Stored via associated thread-local so the public error type stays a
    /// plain enum (Equatable, Codable-friendly).
    func attach(annotation: PhotoAnnotation) -> Self {
        DimensionedPhotoSyncManager.lastQueuedAnnotation = annotation
        return self
    }
}

extension DimensionedPhotoSyncManager {
    /// Holds the most recent queued-for-retry `PhotoAnnotation` so the caller
    /// can pluck it after catching a `DimensionedSyncError.queuedForRetry`.
    /// Single slot — overwritten on each failure. Cleared by the caller after
    /// the local insert.
    @MainActor
    public static var lastQueuedAnnotation: PhotoAnnotation?
}
