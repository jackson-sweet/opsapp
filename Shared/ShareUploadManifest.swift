//
//  ShareUploadManifest.swift
//  Shared between the OPS app and the OPSShareExtension.
//
//  The manifest is a simple, durable queue of photos the share extension has
//  captured but the app has not yet uploaded. The extension writes the image
//  bytes into the App Group inbox and appends a job; the app drains the queue on
//  next open / when back online, retrying the same deterministic server request
//  the extension may have started and removing the job once it lands. All
//  mutations go through
//  `ShareUploadManifestStore` under `NSFileCoordinator`, so the two processes
//  never corrupt the file.
//

import Foundation
import os

/// One captured photo awaiting upload by the app.
struct ShareUploadJob: Codable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case projectId
        case projectTitle
        case companyId
        case uploadedBy
        case createdAt
        case attempts
        case uploadedURL
        case legacyState = "state"
        case legacyS3PublicURL = "s3PublicUrl"
    }

    /// Stable UUID string; also the inbox filename stem.
    let id: String
    /// Filename (not full path) of the JPEG inside `AppGroupConfig.inboxDirectoryURL`.
    let fileName: String
    let projectId: String
    let projectTitle: String
    let companyId: String
    /// `users.id` of the uploader — stamped as `uploaded_by`.
    let uploadedBy: String
    let createdAt: Date
    /// Online upload attempts that failed for a non-connectivity reason. Offline
    /// retries do not count. Caps pathological retry loops.
    var attempts: Int
    /// Public S3 URL once the bytes are uploaded. Persisted BEFORE finalize so a
    /// finalize failure is retried against the SAME URL — never a re-upload, which
    /// would create a duplicate photo.
    var uploadedURL: String?

    init(
        id: String,
        fileName: String,
        projectId: String,
        projectTitle: String,
        companyId: String,
        uploadedBy: String,
        createdAt: Date,
        attempts: Int = 0,
        uploadedURL: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.projectId = projectId
        self.projectTitle = projectTitle
        self.companyId = companyId
        self.uploadedBy = uploadedBy
        self.createdAt = createdAt
        self.attempts = attempts
        self.uploadedURL = uploadedURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        projectId = try container.decode(String.self, forKey: .projectId)
        projectTitle = try container.decode(String.self, forKey: .projectTitle)
        companyId = try container.decode(String.self, forKey: .companyId)
        uploadedBy = try container.decode(String.self, forKey: .uploadedBy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        attempts = try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        if let currentURL = try container.decodeIfPresent(
            String.self,
            forKey: .uploadedURL
        ) {
            uploadedURL = currentURL
        } else {
            // The shipped presign pipeline populated s3PublicUrl before the PUT
            // started, and its failure path could leave that URL behind while
            // resetting state to pendingPresign. Only s3Complete proves bytes
            // reached the object. In-flight/pending jobs must retry local bytes.
            let legacyState = try container.decodeIfPresent(
                String.self,
                forKey: .legacyState
            )
            uploadedURL = legacyState == "s3Complete"
                ? try container.decodeIfPresent(
                    String.self,
                    forKey: .legacyS3PublicURL
                )
                : nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(projectTitle, forKey: .projectTitle)
        try container.encode(companyId, forKey: .companyId)
        try container.encode(uploadedBy, forKey: .uploadedBy)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(attempts, forKey: .attempts)
        try container.encodeIfPresent(uploadedURL, forKey: .uploadedURL)
    }

    /// Absolute URL of this job's image bytes in the shared inbox.
    var fileURL: URL? {
        AppGroupConfig.inboxDirectoryURL?.appendingPathComponent(fileName, isDirectory: false)
    }
}

/// Cross-process, file-coordinated store for the upload manifest.
enum ShareUploadManifestStore {

    enum AppendResult: Equatable {
        /// The coordinated atomic write returned successfully.
        case committed
        /// Validation/read/encode failed before any write was attempted.
        case rejected
        /// A write was attempted but threw, so callers must retain source bytes:
        /// the atomic replacement may or may not have become visible.
        case uncertain
    }

    private enum MutationResult {
        case committed
        case rejected
        case uncertain
    }

    /// Deterministic failures before a job is parked and a visible recovery
    /// notification is requested for the uploader. Parking stops an unkillable
    /// poison loop but deliberately retains both the queue row and photo bytes.
    /// Temporary connectivity/auth/server failures never count toward this limit.
    static let maxAttempts = 10
    private static let log = Logger(
        subsystem: "co.opsapp.ops.share",
        category: "manifest"
    )

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Returns every valid job currently in the manifest. A corrupt/unreadable
    /// manifest is left byte-for-byte untouched and reported as no actionable
    /// work; critically, mutation uses a throwing read and will not overwrite it.
    static func allJobs(
        manifestURL: URL? = AppGroupConfig.manifestURL
    ) -> [ShareUploadJob] {
        guard let url = manifestURL else {
            log.error("manifest read failed: App Group container unavailable")
            return []
        }
        var coordError: NSError?
        var jobs: [ShareUploadJob] = []
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            guard FileManager.default.fileExists(atPath: readURL.path) else {
                return
            }
            do {
                jobs = try decodeJobs(at: readURL)
            } catch {
                readError = error
            }
        }
        if let error = coordError ?? readError as NSError? {
            log.error(
                "manifest read preserved existing bytes after error: \(error.localizedDescription, privacy: .public)"
            )
        }
        return jobs
    }

    /// Returns the mutable manifest plus any still-present JPEGs reconstructed
    /// from immutable recovery-batch records. The recovery ledger is what lets
    /// the app finish a share even if the manifest never committed. Conflicting
    /// routing for one ID is parked rather than guessed.
    static func recoverableJobs(
        manifestURL: URL? = AppGroupConfig.manifestURL,
        inboxDirectoryURL: URL? = AppGroupConfig.inboxDirectoryURL
    ) -> [ShareUploadJob] {
        ShareUploadRecoveryStore.cleanupCompletedBatches(
            inboxDirectoryURL: inboxDirectoryURL
        )
        var byId: [String: ShareUploadJob] = [:]
        var conflicted = Set<String>()

        for manifestJob in allJobs(manifestURL: manifestURL) {
            if let existing = byId[manifestJob.id] {
                if sameStableJob(existing, manifestJob) {
                    var merged = existing.uploadedURL != nil
                        ? existing
                        : manifestJob
                    merged.attempts = max(
                        existing.attempts,
                        manifestJob.attempts
                    )
                    merged.uploadedURL =
                        existing.uploadedURL ?? manifestJob.uploadedURL
                    byId[manifestJob.id] = merged
                } else {
                    conflicted.insert(manifestJob.id)
                }
            } else {
                byId[manifestJob.id] = manifestJob
            }
        }

        for recoveryJob in ShareUploadRecoveryStore.jobs(
            inboxDirectoryURL: inboxDirectoryURL
        ) {
            if let manifestJob = byId[recoveryJob.id] {
                if !sameStableJob(manifestJob, recoveryJob) {
                    conflicted.insert(recoveryJob.id)
                }
            } else {
                byId[recoveryJob.id] = recoveryJob
            }
        }

        for id in conflicted {
            byId.removeValue(forKey: id)
            log.error(
                "queued share \(id, privacy: .public) parked because manifest and recovery routing disagree"
            )
        }
        return byId.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }

    /// Atomically reads, transforms, and writes the whole manifest under a single
    /// coordinated write — the core primitive every other mutation builds on.
    /// Decode/validation/encode failures are definite rejections because no write
    /// starts. Once an atomic write is attempted, a thrown error is uncertain and
    /// callers must retain source bytes. A successful atomic write is committed;
    /// there is deliberately no second read that could turn success into a false
    /// failure and prompt deletion of the newly queued bytes.
    @discardableResult
    private static func mutate(
        manifestURL: URL?,
        writer: (Data, URL) throws -> Void,
        _ transform: (inout [ShareUploadJob]) -> Bool
    ) -> MutationResult {
        guard let url = manifestURL else {
            log.error("manifest write failed: App Group container unavailable")
            return .rejected
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            log.error(
                "manifest directory creation failed: \(error.localizedDescription, privacy: .public)"
            )
            return .rejected
        }

        var coordError: NSError?
        var mutationError: Error?
        var writeAttempted = false
        var writeSucceeded = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordError) { writeURL in
            do {
                var jobs = FileManager.default.fileExists(atPath: writeURL.path)
                    ? try decodeJobs(at: writeURL)
                    : []
                guard transform(&jobs) else { return }
                let encoded = try encoder.encode(jobs)
                writeAttempted = true
                try writer(encoded, writeURL)
                writeSucceeded = true
            } catch {
                mutationError = error
            }
        }
        if let error = coordError ?? mutationError as NSError? {
            log.error(
                "manifest mutation failed without clearing queued bytes: \(error.localizedDescription, privacy: .public)"
            )
        }

        // The writer returning is the commit acknowledgement. A later
        // coordination bookkeeping error cannot safely downgrade that success.
        if writeSucceeded { return .committed }
        if writeAttempted { return .uncertain }
        return .rejected
    }

    /// Atomically appends every job in one share. Existing identical job IDs are
    /// treated as successful retries; a conflicting ID fails the whole append.
    /// Every ID is validated exactly once inside the same coordinated mutation.
    /// Callers must retain staged bytes when the result is `.uncertain`.
    @discardableResult
    static func append(
        _ newJobs: [ShareUploadJob],
        manifestURL: URL? = AppGroupConfig.manifestURL,
        writer: (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        }
    ) -> AppendResult {
        guard !newJobs.isEmpty,
              Set(newJobs.map(\.id)).count == newJobs.count else {
            return .rejected
        }

        var sawUncertainWrite = false
        for _ in 0..<3 {
            var alreadyCommitted = false
            var conflict = false
            let result = mutate(
                manifestURL: manifestURL,
                writer: writer
            ) { jobs in
                conflict = newJobs.contains { candidate in
                    guard let existing = jobs.first(where: { $0.id == candidate.id }) else {
                        return false
                    }
                    return !sameStableJob(existing, candidate)
                }
                guard !conflict else { return false }

                alreadyCommitted = newJobs.allSatisfy { candidate in
                    jobs.contains { sameStableJob($0, candidate) }
                }
                if alreadyCommitted {
                    // The prior write may have committed even though its caller
                    // lost acknowledgement. This coordinated read is enough to
                    // confirm it; do not rewrite or report failure.
                    return false
                }

                for job in newJobs {
                    if !jobs.contains(where: { $0.id == job.id }) {
                        jobs.append(job)
                    }
                }
                let byID = Dictionary(grouping: jobs, by: \.id)
                return newJobs.allSatisfy { candidate in
                    guard let matches = byID[candidate.id],
                          matches.count == 1,
                          let stored = matches.first else {
                        return false
                    }
                    return sameStableJob(stored, candidate)
                }
            }

            if alreadyCommitted { return .committed }
            if conflict { return sawUncertainWrite ? .uncertain : .rejected }
            switch result {
            case .committed:
                return .committed
            case .rejected:
                return sawUncertainWrite ? .uncertain : .rejected
            case .uncertain:
                sawUncertainWrite = true
            }
        }
        return .uncertain
    }

    /// Convenience for single-job callers.
    @discardableResult
    static func append(_ job: ShareUploadJob) -> AppendResult {
        append([job])
    }

    /// Applies `change` to the job with `id`, if present.
    @discardableResult
    static func update(
        id: String,
        _ change: (inout ShareUploadJob) -> Void
    ) -> Bool {
        var found = false
        let result = mutate(
            manifestURL: AppGroupConfig.manifestURL,
            writer: { try $0.write(to: $1, options: .atomic) }
        ) { jobs in
            guard let idx = jobs.firstIndex(where: { $0.id == id }) else {
                return false
            }
            found = true
            change(&jobs[idx])
            return true
        }
        if case .committed = result { return found }
        return false
    }

    /// Removes the job with `id` and deletes its inbox file.
    @discardableResult
    static func remove(id: String) -> Bool {
        var fileToDelete: URL?
        var found = false
        let recoveryJob = ShareUploadRecoveryStore.jobs().first {
            $0.id == id
        }
        let result = mutate(
            manifestURL: AppGroupConfig.manifestURL,
            writer: { try $0.write(to: $1, options: .atomic) }
        ) { jobs in
            if let idx = jobs.firstIndex(where: { $0.id == id }) {
                found = true
                fileToDelete = jobs[idx].fileURL
                jobs.remove(at: idx)
            }
            return found
        }
        if found {
            guard case .committed = result else { return false }
        } else if recoveryJob == nil {
            return false
        }
        fileToDelete = fileToDelete ?? recoveryJob?.fileURL
        if let fileToDelete,
           FileManager.default.fileExists(atPath: fileToDelete.path) {
            do {
                try FileManager.default.removeItem(at: fileToDelete)
            } catch {
                log.error(
                    "queued photo cleanup failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }
        ShareUploadRecoveryStore.cleanupCompletedBatches()
        return true
    }

    private static func decodeJobs(at url: URL) throws -> [ShareUploadJob] {
        let data = try Data(contentsOf: url)
        return try decoder.decode([ShareUploadJob].self, from: data)
    }

    /// Date JSON is second-granularity. Compare the capture instant at that same
    /// precision so a normal encode/readback remains stable, while a manifest
    /// row can never silently replace a recovery row bound to another instant.
    private static func sameStableJob(
        _ lhs: ShareUploadJob,
        _ rhs: ShareUploadJob
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.fileName == rhs.fileName
            && lhs.projectId == rhs.projectId
            && lhs.projectTitle == rhs.projectTitle
            && lhs.companyId == rhs.companyId
            && lhs.uploadedBy == rhs.uploadedBy
            && lhs.createdAt.timeIntervalSince1970.rounded(.down)
                == rhs.createdAt.timeIntervalSince1970.rounded(.down)
    }
}
