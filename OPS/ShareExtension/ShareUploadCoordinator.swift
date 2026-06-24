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
//     photos and finalize every photo that's on S3 (project_images + project_photos
//     + notification). Runs on launch, every foreground, a Darwin nudge from the
//     extension, and when background-session events arrive.
//
//  Reliability contract: **opening OPS always lands a captured photo.** The
//  in-extension background upload is a best-effort fast path; if its completion is
//  lost, never delivered, or the transfer stalled, the foreground drain reconciles
//  the job against the session's actually-live tasks and re-drives it through the
//  app's proven upload pipeline rather than waiting out a long stale window.
//
//  The manifest is the source of truth; all transitions go through the
//  file-coordinated ShareUploadManifestStore.
//

import Foundation
import os

final class ShareUploadCoordinator: NSObject {
    static let shared = ShareUploadCoordinator()

    private let log = Logger(subsystem: "co.opsapp.ops.share", category: "drain")

    /// Grace after capture before a still-`.uploadingS3` job whose background task
    /// is no longer live gets re-driven through the reliable foreground upload.
    /// Long enough for a just-finished task's completion to deliver first (avoids a
    /// duplicate upload), short enough that reopening OPS lands the photo promptly.
    private static let uploadGrace: TimeInterval = 60

    private var backgroundCompletionHandler: (() -> Void)?
    private var darwinObserverRegistered = false
    private var isDraining = false
    private var rerunRequested = false

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

    // MARK: - Drain (serialized + coalescing)

    /// Drains the inbox to quiescence. Serialized by `isDraining`; a call that
    /// arrives mid-drain requests one more pass (so an upload completion delivered
    /// while a drain is running still gets finalized). Safe to call from any trigger.
    @MainActor
    func drainInbox() async {
        if isDraining {
            rerunRequested = true
            return
        }
        isDraining = true
        repeat {
            rerunRequested = false
            await drainPass()
        } while rerunRequested
        isDraining = false
    }

    @MainActor
    private func drainPass() async {
        await reconcileInFlightUploads()

        let actionable = ShareUploadManifestStore.allJobs()
            .filter { $0.state == .pendingPresign || $0.state == .s3Complete }
        guard !actionable.isEmpty else { return }

        // Defense-in-depth: drop jobs for projects the user can no longer edit —
        // but only when the permission set is actually loaded. In a background
        // launch PermissionStore isn't populated; trust the capture-time gate.
        if PermissionStore.shared.initialized && !PermissionStore.shared.can("projects.edit") {
            log.info("drain: dropping \(actionable.count, privacy: .public) job(s) — projects.edit not granted")
            for job in actionable { ShareUploadManifestStore.remove(id: job.id) }
            return
        }

        log.info("drain: \(actionable.count, privacy: .public) actionable job(s)")
        let byProject = Dictionary(grouping: actionable, by: { $0.projectId })
        for (_, jobs) in byProject {
            await drainProject(jobs)
        }
    }

    /// Re-drive `.uploadingS3` jobs whose background task is no longer live: a lost
    /// or never-delivered completion, a silently-failed transfer, or a handoff from
    /// the dismissed extension that never landed. These are reset to pending so the
    /// drain re-uploads them via the app's reliable path — opening OPS lands the
    /// photo instead of waiting out a multi-hour window.
    @MainActor
    private func reconcileInFlightUploads() async {
        let inFlight = ShareUploadManifestStore.allJobs().filter { $0.state == .uploadingS3 }
        guard !inFlight.isEmpty else { return }

        let liveIds = Set(await liveBackgroundTaskIDs())
        let now = Date()
        for job in inFlight {
            let stillRunning = liveIds.contains(job.id)
            let agedOut = now.timeIntervalSince(job.createdAt) > Self.uploadGrace
            if !stillRunning && agedOut {
                log.info("drain: re-driving stalled upload \(job.id, privacy: .public)")
                ShareUploadManifestStore.update(id: job.id) { j in
                    j.state = .pendingPresign
                    j.s3UploadUrl = nil
                }
            }
        }
    }

    /// `taskDescription`s of tasks the background session still considers live
    /// (running or suspended). A task that finished — successfully or not — is
    /// absent, which is exactly the signal `reconcileInFlightUploads` needs.
    @MainActor
    private func liveBackgroundTaskIDs() async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            backgroundSession.getAllTasks { tasks in
                cont.resume(returning: tasks.compactMap { $0.taskDescription })
            }
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
                log.error("drain: abandoning job \(job.id, privacy: .public) after \(job.attempts, privacy: .public) attempts")
                ShareUploadManifestStore.remove(id: job.id)   // abandon poison job
                continue
            }
            ShareUploadManifestStore.update(id: job.id) { $0.attempts += 1 }

            guard let fileURL = job.fileURL, let data = try? Data(contentsOf: fileURL) else {
                log.error("drain: bytes missing for job \(job.id, privacy: .public); dropping")
                ShareUploadManifestStore.remove(id: job.id)   // bytes are gone
                continue
            }
            let folder = "projects/\(job.companyId)/\(job.projectId)"
            do {
                let url = try await PresignedURLUploadService.shared.uploadImageData(
                    data, filename: job.fileName, folder: folder
                )
                publicURLs.append(url)
                doneJobIds.append(job.id)
                log.info("drain: uploaded job \(job.id, privacy: .public)")
            } catch {
                log.error("drain: upload failed for job \(job.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                // Leave pending (attempts already bumped) for the next drain.
            }
        }

        guard !publicURLs.isEmpty else { return }

        let landed = await SharePhotoFinalizer.finalize(
            publicURLs: publicURLs,
            projectId: reference.projectId,
            companyId: reference.companyId,
            projectTitle: reference.projectTitle,
            uploadedBy: reference.uploadedBy
        )
        log.info("drain: finalize \(landed ? "ok" : "FAILED", privacy: .public) for project \(reference.projectId, privacy: .public) — \(publicURLs.count, privacy: .public) photo(s)")
        if landed {
            for id in doneJobIds { ShareUploadManifestStore.remove(id: id) }
        }
    }

    @MainActor
    private func releaseBackgroundCompletionHandler() {
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
        // Finalize/re-upload promptly — covers the foreground-reopen case where
        // urlSessionDidFinishEvents is never called.
        Task { @MainActor in await self.drainInbox() }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // All queued background events delivered — finalize, THEN tell iOS we're
        // done so it doesn't suspend us mid-write.
        Task { @MainActor in
            await self.drainInbox()
            self.releaseBackgroundCompletionHandler()
        }
    }
}
