//
//  ShareUploadManifest.swift
//  Shared between the OPS app and the OPSShareExtension.
//
//  The manifest is the single source of truth for every photo the share
//  extension has captured but not yet fully landed in a project. The extension
//  writes the image bytes into the App Group inbox and appends a job; the app
//  (via its background-upload session delegate and its launch/foreground drain)
//  advances each job to completion and removes it. All mutations go through
//  `ShareUploadManifestStore` under `NSFileCoordinator`, so the two processes
//  never corrupt the file.
//

import Foundation

/// Lifecycle of a single captured image on its way into a project.
enum ShareUploadState: String, Codable {
    /// Bytes are on disk in the inbox; still needs presign + S3 upload. The app
    /// owns this work (the extension could not presign — offline or token expired,
    /// or the background PUT failed and was reset here for retry).
    case pendingPresign
    /// The extension presigned and started a background S3 PUT; bytes are in
    /// flight. The app's background-session delegate resolves the outcome.
    case uploadingS3
    /// Bytes are confirmed on S3; the project_photos row + project_images CSV +
    /// notification still need to be written by the app.
    case s3Complete
}

/// One captured image awaiting upload/finalization.
struct ShareUploadJob: Codable, Identifiable {
    /// Stable UUID string. Also the inbox filename stem and the background
    /// URLSession task's `taskDescription`, so completions map back to the job.
    let id: String
    /// Filename (not full path) of the JPEG inside `AppGroupConfig.inboxDirectoryURL`.
    let fileName: String
    let projectId: String
    let projectTitle: String
    let companyId: String
    /// `users.id` of the uploader — stamped as `uploaded_by`.
    let uploadedBy: String
    let createdAt: Date
    var state: ShareUploadState
    /// Public (CDN/S3) URL once known from presign.
    var s3PublicUrl: String?
    /// Presigned PUT URL (may expire; the app re-presigns if a retry is needed).
    var s3UploadUrl: String?
    /// Number of times upload has been attempted (caps retry churn).
    var attempts: Int

    init(
        id: String,
        fileName: String,
        projectId: String,
        projectTitle: String,
        companyId: String,
        uploadedBy: String,
        createdAt: Date,
        state: ShareUploadState,
        s3PublicUrl: String? = nil,
        s3UploadUrl: String? = nil,
        attempts: Int = 0
    ) {
        self.id = id
        self.fileName = fileName
        self.projectId = projectId
        self.projectTitle = projectTitle
        self.companyId = companyId
        self.uploadedBy = uploadedBy
        self.createdAt = createdAt
        self.state = state
        self.s3PublicUrl = s3PublicUrl
        self.s3UploadUrl = s3UploadUrl
        self.attempts = attempts
    }

    /// Absolute URL of this job's image bytes in the shared inbox.
    var fileURL: URL? {
        AppGroupConfig.inboxDirectoryURL?.appendingPathComponent(fileName, isDirectory: false)
    }
}

/// Cross-process, file-coordinated store for the upload manifest.
enum ShareUploadManifestStore {

    /// Hard cap on retry attempts before a job is abandoned (and its bytes
    /// removed) to avoid an unkillable poison job.
    static let maxAttempts = 6

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
    /// Returns the post-mutation job list.
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
