//
//  ProjectPhotoBatchUploader.swift
//  OPS
//
//  Resilient, concurrent batch upload for project photos.
//
//  Replaces the old sequential / abort-on-first-error loop in
//  `PresignedURLUploadService.uploadProjectImages`, which uploaded one photo at
//  a time and, on the first failure, threw out of the whole batch — discarding
//  every photo already PUT to S3 in that call. On a 10-photo batch over a field
//  connection that meant a single mid-batch timeout silently dropped the rest
//  ("only some make it"), and the early successes became orphaned S3 objects
//  with no project row pointing at them.
//
//  This uploader:
//    - uploads with bounded concurrency (so 10 photos don't crawl serially),
//    - isolates per-photo failures (one timeout never aborts the others),
//    - retries each photo through a transient blip (NetworkRetry),
//    - returns one outcome PER input, in input order, so the caller can record
//      the successes immediately and queue only the genuine failures.
//
//  Testability mirrors `DimensionedPhotoSyncManager`: the single-image network
//  call sits behind `ProjectImageDataUploading`, so the orchestration is unit
//  tested with an in-process mock (no S3, no Supabase, no network).
//

import Foundation
import UIKit

/// Single-image upload primitive. The live impl wraps
/// `PresignedURLUploadService.uploadImageData`; tests inject a mock.
protocol ProjectImageDataUploading: Sendable {
    func uploadImageData(_ data: Data, filename: String, folder: String) async throws -> String
}

/// An image already resized, JPEG-encoded, and assigned a unique filename —
/// ready to PUT. Encoding/filename derivation happens before the concurrent
/// region so there are no per-photo races on the dedupe set.
struct PreparedProjectImage {
    let image: UIImage
    let filename: String
    let data: Data

    init(image: UIImage, filename: String, data: Data) {
        self.image = image
        self.filename = filename
        self.data = data
    }
}

/// Outcome for a single image, aligned 1:1 (and in order) with the input batch.
/// Failures carry the classified `UploadErrorKind` so the caller can decide
/// between queue-and-retry (transient) and surface-a-failed-tile (permanent),
/// plus a field-friendly message for display.
enum ProjectImageUploadOutcome {
    case success(image: UIImage, filename: String, url: String)
    case failure(image: UIImage, filename: String, kind: UploadErrorKind, message: String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var filename: String {
        switch self {
        case .success(_, let filename, _): return filename
        case .failure(_, let filename, _, _): return filename
        }
    }

    var url: String? {
        if case .success(_, _, let url) = self { return url }
        return nil
    }

    var image: UIImage {
        switch self {
        case .success(let image, _, _): return image
        case .failure(let image, _, _, _): return image
        }
    }

    var kind: UploadErrorKind? {
        if case .failure(_, _, let kind, _) = self { return kind }
        return nil
    }

    var isPermanentFailure: Bool {
        if case .failure(_, _, let kind, _) = self, case .permanent = kind { return true }
        return false
    }
}

struct ProjectPhotoBatchUploader {

    /// One slot in the batch. `encodingFailed` carries an image whose JPEG
    /// encoding failed during prep — it passes straight through as a failure
    /// outcome (never silently dropped, which is what shrank the old result
    /// array and misaligned the queue-drain index map).
    enum Input {
        case ready(PreparedProjectImage)
        case encodingFailed(image: UIImage, filename: String)
    }

    let uploader: ProjectImageDataUploading
    let folder: String
    let maxConcurrent: Int
    let maxAttempts: Int
    let baseDelaySeconds: Double

    init(
        uploader: ProjectImageDataUploading,
        folder: String,
        maxConcurrent: Int = 3,
        maxAttempts: Int = 3,
        baseDelaySeconds: Double = 0.5
    ) {
        self.uploader = uploader
        self.folder = folder
        self.maxConcurrent = max(1, maxConcurrent)
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelaySeconds = baseDelaySeconds
    }

    /// Upload every input, returning one outcome per input in input order.
    /// Never throws — a per-photo failure becomes a `.failure` outcome.
    @MainActor
    func upload(_ inputs: [Input]) async -> [ProjectImageUploadOutcome] {
        // Index-aligned result buffer. Encoding failures resolve immediately;
        // ready inputs become upload jobs. Keeping the original index per job
        // means the result order never depends on completion order.
        var outcomes = [ProjectImageUploadOutcome?](repeating: nil, count: inputs.count)

        struct Job {
            let index: Int
            let prepared: PreparedProjectImage
        }
        var jobs: [Job] = []

        for (index, input) in inputs.enumerated() {
            switch input {
            case .ready(let prepared):
                jobs.append(Job(index: index, prepared: prepared))
            case .encodingFailed(let image, let filename):
                outcomes[index] = .failure(
                    image: image,
                    filename: filename,
                    kind: .permanent(errorCode: "ENCODING_FAILED", reason: "image could not be encoded to JPEG"),
                    message: "Couldn't prepare this photo. Try retaking it."
                )
            }
        }

        // Bounded-concurrency upload. Child tasks capture only Sendable values
        // (index, filename, data) plus `self` (a Sendable value type); the
        // non-Sendable UIImage stays here on the main actor and is paired back
        // to its result by index below.
        let resultsByIndex: [Int: JobResult] = await withTaskGroup(of: JobResult.self) { group in
            var nextJob = 0
            let initialBurst = min(maxConcurrent, jobs.count)
            while nextJob < initialBurst {
                let job = jobs[nextJob]
                nextJob += 1
                let index = job.index
                let filename = job.prepared.filename
                let data = job.prepared.data
                group.addTask { await self.uploadOne(index: index, filename: filename, data: data) }
            }

            var collected: [Int: JobResult] = [:]
            while let result = await group.next() {
                collected[result.index] = result
                if nextJob < jobs.count {
                    let job = jobs[nextJob]
                    nextJob += 1
                    let index = job.index
                    let filename = job.prepared.filename
                    let data = job.prepared.data
                    group.addTask { await self.uploadOne(index: index, filename: filename, data: data) }
                }
            }
            return collected
        }

        for job in jobs {
            guard let result = resultsByIndex[job.index] else { continue }
            switch result.payload {
            case .ok(let url):
                outcomes[job.index] = .success(
                    image: job.prepared.image,
                    filename: job.prepared.filename,
                    url: url
                )
            case .fail(let kind, let message):
                outcomes[job.index] = .failure(
                    image: job.prepared.image,
                    filename: job.prepared.filename,
                    kind: kind,
                    message: message
                )
            }
        }

        return outcomes.compactMap { $0 }
    }

    /// Upload one prepared image, retrying transient failures. Nonisolated so it
    /// runs off the main actor inside the task group; takes only Sendable args.
    private func uploadOne(index: Int, filename: String, data: Data) async -> JobResult {
        do {
            let url = try await NetworkRetry.run(maxAttempts: maxAttempts, baseDelaySeconds: baseDelaySeconds) {
                try await uploader.uploadImageData(data, filename: filename, folder: folder)
            }
            return JobResult(index: index, payload: .ok(url: url))
        } catch {
            let kind = UploadErrorClassifier.classify(error)
            let message = FieldErrorHandler.userFriendlyMessage(for: error)
            return JobResult(index: index, payload: .fail(kind: kind, message: message))
        }
    }
}

/// Sendable result carried back from each upload task. Deliberately UIImage-free
/// so it crosses the task boundary cleanly; the caller re-pairs it with the
/// original image by `index`.
private struct JobResult: Sendable {
    enum Payload: Sendable {
        case ok(url: String)
        case fail(kind: UploadErrorKind, message: String)
    }
    let index: Int
    let payload: Payload
}

/// Encoding failure for an image that could not be turned into JPEG bytes.
enum ProjectImageEncodingError: Error {
    case encodingFailed
}

/// Live single-image uploader — wraps the shared `PresignedURLUploadService`.
struct LiveProjectImageDataUploader: ProjectImageDataUploading {
    init() {}

    @MainActor
    func uploadImageData(_ data: Data, filename: String, folder: String) async throws -> String {
        try await PresignedURLUploadService.shared.uploadImageData(data, filename: filename, folder: folder)
    }
}
