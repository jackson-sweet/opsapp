//
//  ShareUploadManifest.swift
//  Shared between the OPS app and the OPSShareExtension.
//
//  The manifest is a simple, durable queue of photos the share extension has
//  captured but the app has not yet uploaded. The extension writes the image
//  bytes into the App Group inbox and appends a job; the app drains the queue on
//  next open / when back online, uploading each through its proven pipeline and
//  removing the job once it lands. All mutations go through
//  `ShareUploadManifestStore` under `NSFileCoordinator`, so the two processes
//  never corrupt the file.
//

import Foundation

/// One captured photo awaiting upload by the app.
struct ShareUploadJob: Codable, Identifiable {
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

    /// Absolute URL of this job's image bytes in the shared inbox.
    var fileURL: URL? {
        AppGroupConfig.inboxDirectoryURL?.appendingPathComponent(fileName, isDirectory: false)
    }
}

/// Cross-process, file-coordinated store for the upload manifest.
enum ShareUploadManifestStore {

    /// Online failures before a job is abandoned (and its bytes removed) to avoid
    /// an unkillable poison job. Generous — losing a photo is worse than a few
    /// extra retries — and offline never counts against it.
    static let maxAttempts = 10

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

    /// Returns every job currently in the manifest.
    static func allJobs() -> [ShareUploadJob] {
        guard let url = AppGroupConfig.manifestURL else { return [] }
        var coordError: NSError?
        var jobs: [ShareUploadJob] = []
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            guard let data = try? Data(contentsOf: readURL) else { return }
            jobs = (try? decoder.decode([ShareUploadJob].self, from: data)) ?? []
        }
        return jobs
    }

    /// Atomically reads, transforms, and writes the whole manifest under a single
    /// coordinated write — the core primitive every other mutation builds on.
    @discardableResult
    static func mutate(_ transform: (inout [ShareUploadJob]) -> Void) -> [ShareUploadJob] {
        guard let url = AppGroupConfig.manifestURL else { return [] }
        AppGroupConfig.ensureInboxDirectory()
        var coordError: NSError?
        var resulting: [ShareUploadJob] = []
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordError) { writeURL in
            var jobs: [ShareUploadJob] = []
            if let data = try? Data(contentsOf: writeURL) {
                jobs = (try? decoder.decode([ShareUploadJob].self, from: data)) ?? []
            }
            transform(&jobs)
            if let out = try? encoder.encode(jobs) {
                try? out.write(to: writeURL, options: .atomic)
            }
            resulting = jobs
        }
        return resulting
    }

    /// Appends a new job.
    static func append(_ job: ShareUploadJob) {
        mutate { $0.append(job) }
    }

    /// Applies `change` to the job with `id`, if present.
    static func update(id: String, _ change: (inout ShareUploadJob) -> Void) {
        mutate { jobs in
            guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
            change(&jobs[idx])
        }
    }

    /// Removes the job with `id` and deletes its inbox file.
    static func remove(id: String) {
        var fileToDelete: URL?
        mutate { jobs in
            if let idx = jobs.firstIndex(where: { $0.id == id }) {
                fileToDelete = jobs[idx].fileURL
                jobs.remove(at: idx)
            }
        }
        if let fileToDelete { try? FileManager.default.removeItem(at: fileToDelete) }
    }
}
