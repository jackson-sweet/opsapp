//
//  ShareUploadCoordinator.swift
//  OPS
//
//  App-side drainer for the "Add to OPS" share extension. The extension only
//  saves captured photos into the shared App Group queue; the app uploads each
//  through its proven pipeline (PresignedURLUploadService + SharePhotoFinalizer)
//  and removes the job once it lands.
//
//  Reliability contract: **a shared photo always reaches its project.** Bytes are
//  persisted on the device the instant they're shared, so nothing is lost. The
//  drain runs on every app foreground, on a Darwin nudge from the extension, and
//  when connectivity is restored — uploading when online and leaving the queue
//  untouched when offline. Idempotent: a photo's S3 URL is persisted before
//  finalize, so a finalize retry never re-uploads (no duplicate), and the
//  finalizer dedups both project_images and project_photos.
//

import Foundation
import os

final class ShareUploadCoordinator: NSObject {
    static let shared = ShareUploadCoordinator()

    private let log = Logger(subsystem: "co.opsapp.ops.share", category: "drain")

    /// Set by the app at startup so the drain can skip while offline (jobs stay
    /// queued and drain when connectivity returns). Weak — owned by DataController.
    weak var connectivity: ConnectivityManager?

    private var darwinObserverRegistered = false
    private var isDraining = false
    private var rerunRequested = false

    private override init() { super.init() }

    /// Registers the Darwin observer so a running app drains the moment the
    /// extension enqueues a photo. Idempotent; call on launch + foreground.
    @MainActor
    func activate() {
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
    /// arrives mid-drain requests one more pass. Safe to call from any trigger.
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
        let jobs = ShareUploadManifestStore.allJobs()
        guard !jobs.isEmpty else { return }

        // Offline → leave everything queued; the connectivity-restored hook
        // re-drains. (When connectivity is unknown, attempt anyway.)
        if let connectivity, !connectivity.isConnected {
            log.info("drain: offline — \(jobs.count, privacy: .public) job(s) deferred")
            return
        }

        // Defense-in-depth: drop jobs for projects the user can no longer edit —
        // but only when the permission set is actually loaded.
        if PermissionStore.shared.initialized && !PermissionStore.shared.can("projects.edit") {
            log.info("drain: dropping \(jobs.count, privacy: .public) job(s) — projects.edit not granted")
            for job in jobs { ShareUploadManifestStore.remove(id: job.id) }
            return
        }

        log.info("drain: \(jobs.count, privacy: .public) job(s) to upload")
        let byProject = Dictionary(grouping: jobs, by: { $0.projectId })
        for (_, projectJobs) in byProject {
            await drainProject(projectJobs)
        }
    }

    @MainActor
    private func drainProject(_ jobs: [ShareUploadJob]) async {
        guard let reference = jobs.first else { return }

        // Account-switch guard: never finalize a previous user's queued photo under
        // a newly signed-in session. If the signed-in user no longer matches the
        // job's uploader, these photos belong to a logged-out account (whose queue
        // was cleared on logout) — abandon this drain.
        guard isCurrentUser(reference.uploadedBy) else {
            log.info("drain: skipping project \(reference.projectId, privacy: .public) — uploader is not the signed-in user")
            return
        }

        // (jobId, url) for every photo whose bytes are on S3 and ready to finalize.
        var resolved: [(jobId: String, url: String)] = []

        for job in jobs {
            // Already uploaded on a prior pass (finalize must have failed) —
            // re-finalize the SAME URL, never re-upload.
            if let url = job.uploadedURL {
                resolved.append((job.id, url))
                continue
            }

            // Parked: repeatedly failed to upload for a permanent-looking reason.
            // We KEEP the bytes (never lose a photo) but stop retrying.
            if job.attempts >= ShareUploadManifestStore.maxAttempts {
                continue
            }

            guard let fileURL = job.fileURL, let data = try? Data(contentsOf: fileURL) else {
                log.error("drain: bytes missing for job \(job.id, privacy: .public); dropping")
                ShareUploadManifestStore.remove(id: job.id)
                continue
            }

            let folder = "projects/\(job.companyId)/\(job.projectId)"
            do {
                let url = try await PresignedURLUploadService.shared.uploadImageData(
                    data, filename: job.fileName, folder: folder
                )
                // Durably record the URL on the job, and ONLY finalize if it stuck.
                // If the manifest write is lost, a later pass would re-upload and
                // mint a SECOND, different S3 URL (the presign endpoint generates a
                // unique key each time) — a duplicate photo no dedup can catch. So
                // we never finalize a URL we couldn't persist; the bytes stay queued
                // and we retry (an unfinalized URL is just an orphaned S3 object).
                if persistUploadedURL(url, jobId: job.id) {
                    resolved.append((job.id, url))
                    log.info("drain: uploaded job \(job.id, privacy: .public)")
                } else {
                    log.error("drain: could not persist URL for \(job.id, privacy: .public) — deferring finalize, will retry")
                }
            } catch {
                if Self.isTransientError(error) {
                    // Offline / backend / auth-refresh blip — retry forever, never
                    // count against the budget. A photo must never be lost to a
                    // temporary outage.
                    log.info("drain: transient failure uploading \(job.id, privacy: .public) — will retry: \(error.localizedDescription, privacy: .public)")
                } else {
                    let attempts = job.attempts + 1
                    ShareUploadManifestStore.update(id: job.id) { $0.attempts = attempts }
                    if attempts >= ShareUploadManifestStore.maxAttempts {
                        // Permanent-looking failure repeated too many times. PARK
                        // the job — keep the bytes on disk (never delete a photo)
                        // but stop retrying. Future drains skip it.
                        log.error("drain: parking job \(job.id, privacy: .public) after \(attempts, privacy: .public) permanent failures — bytes kept, not deleted")
                    } else {
                        log.error("drain: upload failed for \(job.id, privacy: .public) (attempt \(attempts, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        guard !resolved.isEmpty else { return }

        // Re-check the account didn't switch during the uploads above.
        guard isCurrentUser(reference.uploadedBy) else {
            log.info("drain: aborting finalize for \(reference.projectId, privacy: .public) — account switched mid-drain")
            return
        }

        let landed = await SharePhotoFinalizer.finalize(
            publicURLs: resolved.map { $0.url },
            projectId: reference.projectId,
            companyId: reference.companyId,
            projectTitle: reference.projectTitle,
            uploadedBy: reference.uploadedBy
        )
        log.info("drain: finalize \(landed ? "ok" : "FAILED", privacy: .public) for project \(reference.projectId, privacy: .public) — \(resolved.count, privacy: .public) photo(s)")
        if landed {
            for r in resolved { ShareUploadManifestStore.remove(id: r.jobId) }
        }
        // If finalize FAILED, jobs stay queued WITH their uploadedURL set, so the
        // next drain re-finalizes the same URLs (idempotent) without re-uploading.
    }

    /// True when the signed-in user is still the job's uploader. Guards against
    /// finalizing a logged-out user's queued photo under a freshly signed-in
    /// session (cross-account write / mis-attribution).
    @MainActor
    private func isCurrentUser(_ userId: String) -> Bool {
        guard !userId.isEmpty else { return false }
        return UserDefaults.standard.string(forKey: "currentUserId") == userId
    }

    /// Durably records the uploaded S3 URL on the job, verifying the cross-process
    /// manifest write actually stuck. Returns false if it could not be persisted —
    /// in which case the caller must NOT finalize the URL (a later re-upload would
    /// mint a different URL, i.e. a duplicate photo).
    private func persistUploadedURL(_ url: String, jobId: String) -> Bool {
        for _ in 0..<3 {
            ShareUploadManifestStore.update(id: jobId) { $0.uploadedURL = url }
            if ShareUploadManifestStore.allJobs().first(where: { $0.id == jobId })?.uploadedURL == url {
                return true
            }
        }
        return false
    }

    /// True for transient failures that should NOT count against a job's attempt
    /// budget — we retry indefinitely instead. Covers offline/network errors, ops-web
    /// / S3 server errors (5xx, 408, 429), and auth blips (401/403 — the app's token
    /// refreshes) plus ambiguous token/transport failures. Only genuinely permanent,
    /// deterministic failures (e.g. 400/404/413) count toward parking, so a backend or
    /// auth outage can never burn the budget and lose a photo.
    private static func isTransientError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff:
                return true
            default:
                return false
            }
        }
        if let uploadError = error as? UploadError {
            switch uploadError {
            case .invalidResponse, .invalidURL:
                // Token-refresh hiccup / non-HTTP response / malformed presigned URL —
                // ambiguous and usually recoverable; retry rather than burn the budget.
                return true
            case .presignError(let code), .s3Error(let code):
                return code >= 500 || code == 408 || code == 429 || code == 401 || code == 403
            }
        }
        return false
    }
}
