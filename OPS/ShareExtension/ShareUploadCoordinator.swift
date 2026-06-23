//
//  ShareUploadCoordinator.swift
//  OPS
//
//  App-side owner of the share-extension upload pipeline. Two responsibilities:
//
//  1. Re-attach to the SAME background URLSession the extension started, so iOS
//     delivers S3-upload completions to the app (the extension is long gone by
//     then). On completion we mark the manifest, then drain.
//  2. Drain the App Group share inbox: for each project, upload any still-pending
//     photos (token expired / offline at capture time) and finalize every photo
//     that's on S3 (project_images + project_photos + notification). Runs on app
//     launch, on every foreground, on a Darwin nudge from the extension, and when
//     background-session events finish.
//
//  The manifest is the source of truth; all transitions go through the
//  file-coordinated ShareUploadManifestStore, so the background delegate and the
//  foreground drain never corrupt it.
//

import Foundation

final class ShareUploadCoordinator: NSObject {
    static let shared = ShareUploadCoordinator()

    /// Stale-upload threshold: a job stuck in `.uploadingS3` with no completion
    /// after this long is reset to pending so the app re-presigns + re-uploads
    /// (covers a presigned URL that expired before iOS ran the transfer).
    private static let staleUploadInterval: TimeInterval = 2 * 60 * 60

    private var backgroundCompletionHandler: (() -> Void)?
    private var darwinObserverRegistered = false
    private var isDraining = false

    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: AppGroupConfig.backgroundSessionIdentifier)
        config.sharedContainerIdentifier = AppGroupConfig.identifier
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() { super.init() }

    // MARK: - Lifecycle

    /// Re-creates the background session (so pending completions route to us) and
    /// registers the Darwin observer. Idempotent. Call on launch + foreground.
    @MainActor
    func activate() {
        _ = backgroundSession
        registerDarwinObserverIfNeeded()
    }

    /// Stores the system completion handler for a background-session relaunch.
    @MainActor
    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == AppGroupConfig.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        backgroundCompletionHandler = completionHandler
        _ = backgroundSession
    }

    private func registerDarwinObserverIfNeeded() {
        guard !darwinObserverRegistered else { return }
        darwinObserverRegistered = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = AppGroupConfig.inboxUpdatedDarwinName as CFString
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, _, _, _, _ in
                Task { @MainActor in await ShareUploadCoordinator.shared.drainInbox() }
            },
            name,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Drain

    /// Uploads pending photos and finalizes on-S3 photos for every project with
    /// queued work. Serialized by `isDraining`; safe to call from any trigger.
    @MainActor
    func drainInbox() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        // Recover stale in-flight uploads.
        let now = Date()
        for job in ShareUploadManifestStore.allJobs() where job.state == .uploadingS3 {
            if now.timeIntervalSince(job.createdAt) > Self.staleUploadInterval {
                ShareUploadManifestStore.update(id: job.id) { job in
                    job.state = .pendingPresign
                    job.s3UploadUrl = nil
                }
            }
        }

        let actionable = ShareUploadManifestStore.allJobs()
            .filter { $0.state == .pendingPresign || $0.state == .s3Complete }
        guard !actionable.isEmpty else { return }

        // Defense-in-depth: drop jobs for projects the user can no longer edit —
        // but only when the permission set is actually loaded. In a background
        // launch PermissionStore isn't populated; trust the capture-time gate
        // (the bridge only ever offered editable projects).
        let permissionsLoaded = PermissionStore.shared.initialized
        let canEdit = !permissionsLoaded || PermissionStore.shared.can("projects.edit")
        if permissionsLoaded && !canEdit {
            for job in actionable { ShareUploadManifestStore.remove(id: job.id) }
            return
        }

        let byProject = Dictionary(grouping: actionable, by: { $0.projectId })
        for (_, jobs) in byProject {
            await drainProject(jobs)
        }
    }

    @MainActor
    private func drainProject(_ jobs: [ShareUploadJob]) async {
        guard let reference = jobs.first else { return }

        var publicURLs: [String] = []
        var doneJobIds: [String] = []

        for job in jobs {
            if job.state == .s3Complete, let url = job.s3PublicUrl {
                publicURLs.append(url)
                doneJobIds.append(job.id)
                continue
            }

            // pendingPresign — upload the bytes via the app's tested pipeline.
            if job.attempts >= ShareUploadManifestStore.maxAttempts {
                ShareUploadManifestStore.remove(id: job.id)   // abandon poison job
                continue
            }
            ShareUploadManifestStore.update(id: job.id) { $0.attempts += 1 }

            guard let fileURL = job.fileURL, let data = try? Data(contentsOf: fileURL) else {
                ShareUploadManifestStore.remove(id: job.id)   // bytes are gone
                continue
            }
            let folder = "projects/\(job.companyId)/\(job.projectId)"
            if let url = try? await PresignedURLUploadService.shared.uploadImageData(
                data, filename: job.fileName, folder: folder
            ) {
                publicURLs.append(url)
                doneJobIds.append(job.id)
            }
            // On failure: leave pending (attempts already bumped) for the next drain.
        }

        guard !publicURLs.isEmpty else { return }

        let landed = await SharePhotoFinalizer.finalize(
            publicURLs: publicURLs,
            projectId: reference.projectId,
            companyId: reference.companyId,
            projectTitle: reference.projectTitle,
            uploadedBy: reference.uploadedBy
        )
        if landed {
            for id in doneJobIds { ShareUploadManifestStore.remove(id: id) }
        }
    }

    @MainActor
    private func callBackgroundCompletionHandler() {
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        handler?()
    }
}

// MARK: - URLSessionDelegate (background S3 upload completions)

extension ShareUploadCoordinator: URLSessionDataDelegate {

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let jobId = task.taskDescription else { return }
        let statusOK = (task.response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        let success = error == nil && statusOK

        if success {
            ShareUploadManifestStore.update(id: jobId) { job in
                if job.state == .uploadingS3 { job.state = .s3Complete }
            }
        } else {
            // Reset for the app to re-presign + re-upload on the next drain
            // (handles an expired presigned URL or a transient transfer failure).
            ShareUploadManifestStore.update(id: jobId) { job in
                job.attempts += 1
                job.state = .pendingPresign
                job.s3UploadUrl = nil
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // All queued background events delivered — finalize, THEN tell iOS we're
        // done so it doesn't suspend us mid-write.
        Task { @MainActor in
            await self.drainInbox()
            self.callBackgroundCompletionHandler()
        }
    }
}
