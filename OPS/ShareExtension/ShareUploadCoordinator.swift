//
//  ShareUploadCoordinator.swift
//  OPS
//
//  App-side drainer for the "Add to OPS" share extension. The extension only
//  saves captured photos into the shared App Group queue; the app retries the
//  same idempotent server request the extension may have started, then removes
//  the job once the server confirms storage, filing, and notification.
//
//  Reliability contract: **a shared photo always reaches its project.** Bytes are
//  persisted on the device the instant they're shared, so nothing is lost. The
//  drain runs on every app foreground, on a Darwin nudge from the extension, and
//  when connectivity is restored — uploading when online and leaving the queue
//  untouched when offline. Both paths address the deterministic job ID, so an
//  extension/app race can only repeat the same operation. Deployed legacy jobs
//  that already carry an uploaded URL retain their old finalize-only path.
//

import Foundation
import os

final class ShareUploadCoordinator: NSObject {
    enum AttemptAction: Equatable {
        case upload
        case reportRecovery
        case reported
    }

    static let shared = ShareUploadCoordinator()

    private let log = Logger(subsystem: "co.opsapp.ops.share", category: "drain")

    /// Set by the app at startup so the drain can skip while offline (jobs stay
    /// queued and drain when connectivity returns). Weak — owned by DataController.
    weak var connectivity: ConnectivityManager?

    /// Reads the outbound queue so the drain can ask the SAME create barrier
    /// that orders every queued write (`SyncCrossEntityDependency`). Set by the
    /// app at startup beside `connectivity`.
    ///
    /// A closure rather than a context because this type is deliberately free of
    /// SwiftData — it runs the App Group rail, not the model layer — and because
    /// nil then means exactly "no queue knowledge", under which the drain behaves
    /// precisely as it did before the barrier existed.
    var queuedOperationsProvider: (() -> [SyncOperation])?

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
        let jobs = ShareUploadManifestStore.recoverableJobs()
        guard !jobs.isEmpty else { return }

        // Rebuild the mutable fast-path from the immutable recovery ledger. This
        // is a no-op when every row is already present and makes later attempt
        // updates durable after a prior manifest write was lost.
        let indexResult = ShareUploadManifestStore.append(jobs)
        if indexResult != .committed {
            log.error(
                "drain: mutable manifest index remains unavailable; recovery ledger stays authoritative"
            )
        }

        // Offline → leave everything queued; the connectivity-restored hook
        // re-drains. (When connectivity is unknown, attempt anyway.)
        if let connectivity, !connectivity.isConnected {
            log.info("drain: offline — \(jobs.count, privacy: .public) job(s) deferred")
            return
        }

        guard let currentUserId = UserDefaults.standard.string(
            forKey: "currentUserId"
        ), !currentUserId.isEmpty else {
            log.info("drain: retaining \(jobs.count, privacy: .public) job(s) — no signed-in user")
            return
        }

        let groups = Self.drainGroups(jobs, currentUserId: currentUserId)
        guard !groups.isEmpty else {
            log.info("drain: retaining \(jobs.count, privacy: .public) job(s) owned by another account")
            return
        }
        log.info("drain: \(groups.flatMap { $0 }.count, privacy: .public) current-account job(s) to upload")
        for projectJobs in groups {
            await drainProject(projectJobs)
        }
    }

    /// Filters before grouping so retained jobs from another signed-in account
    /// can never block or contaminate the current account's work for the same
    /// project. Company is part of the key for users who switch company context.
    static func drainGroups(
        _ jobs: [ShareUploadJob],
        currentUserId: String
    ) -> [[ShareUploadJob]] {
        struct Key: Hashable {
            let uploadedBy: String
            let companyId: String
            let projectId: String
        }

        let current = jobs.filter { $0.uploadedBy == currentUserId }
        return Array(
            Dictionary(grouping: current) {
                Key(
                    uploadedBy: $0.uploadedBy,
                    companyId: $0.companyId,
                    projectId: $0.projectId
                )
            }.values
        )
    }

    @MainActor
    private func drainProject(_ jobs: [ShareUploadJob]) async {
        guard let reference = jobs.first else { return }

        // Account-switch guard: never finalize a previous user's queued photo under
        // a newly signed-in session. If the signed-in user no longer matches the
        // job's uploader, these photos belong to another/logged-out account.
        // Retain them so the original account can safely resume.
        guard isCurrentUser(reference.uploadedBy) else {
            log.info("drain: skipping project \(reference.projectId, privacy: .public) — uploader is not the signed-in user")
            return
        }

        // The destination job can exist only on this phone. The extension's
        // picker is fed from local SwiftData (`ShareSessionBridgeWriter`), which
        // publishes any non-deleted, non-terminal project — including one whose
        // own `create` is still queued, retrying, or parked. Against such a
        // project `/api/uploads/share-photo` answers 404, and `isTransient`
        // — correctly, and context-free — calls a 404 permanent. Ten of those
        // park the share and spend the operator a recovery notice for a job that
        // would have landed on its own minutes later.
        //
        // So hold, exactly as the outbound queue holds a write whose row has no
        // confirmed create: no attempt, no attempt count, no park. The bytes stay
        // in the App Group and the next drain — foreground, Darwin nudge, or
        // connectivity restored — retries for free. Ordering is the queue's job;
        // the failure policy stays context-free.
        if let queuedOperationsProvider,
           Self.holdsForUnresolvedProjectCreate(
               projectId: reference.projectId,
               operations: queuedOperationsProvider()
           ) {
            log.info(
                "drain: holding \(jobs.count, privacy: .public) photo(s) for project \(reference.projectId, privacy: .public) — its create has not reached the server yet"
            )
            return
        }

        // Deployed jobs from the previous pipeline may already carry a random S3
        // URL. Those must re-finalize that exact URL; uploading them through the
        // deterministic endpoint would create a second photo.
        var legacyResolved: [(jobId: String, url: String)] = []

        for job in jobs {
            if let url = job.uploadedURL {
                legacyResolved.append((job.id, url))
                continue
            }

            switch Self.actionForAttemptCount(job.attempts) {
            case .reported:
                continue
            case .reportRecovery:
                await reportParkedJob(job)
                continue
            case .upload:
                break
            }

            guard let fileURL = job.fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path) else {
                log.error("drain: bytes already missing for job \(job.id, privacy: .public); clearing unrecoverable manifest row")
                _ = ShareUploadManifestStore.remove(id: job.id)
                continue
            }

            guard isCurrentUser(job.uploadedBy) else {
                log.info("drain: retaining job \(job.id, privacy: .public) — account changed")
                return
            }

            do {
                let url = try await SharePhotoEndpointUploader.upload(job)
                if ShareUploadManifestStore.remove(id: job.id) {
                    log.info(
                        "drain: endpoint confirmed and cleared \(job.id, privacy: .public) at \(url.absoluteString, privacy: .private)"
                    )
                } else {
                    // Server work is complete. A failed local clear is safe: the
                    // same deterministic request will be retried next pass.
                    log.error("drain: endpoint confirmed \(job.id, privacy: .public), but local queue clear failed — safe retry retained")
                }
            } catch {
                if (error as? SharePhotoEndpointUploader.UploadError) == .accountChanged {
                    log.info("drain: retaining \(job.id, privacy: .public) — account changed during token refresh")
                    return
                }
                if SharePhotoEndpointUploader.isTransient(error) {
                    log.info("drain: transient failure uploading \(job.id, privacy: .public) — will retry: \(error.localizedDescription, privacy: .public)")
                } else {
                    let attempts = job.attempts + 1
                    let persisted = ShareUploadManifestStore.update(id: job.id) {
                        $0.attempts = attempts
                    }
                    if !persisted {
                        log.error("drain: could not persist attempt count for \(job.id, privacy: .public) — bytes retained")
                    }
                    if attempts >= ShareUploadManifestStore.maxAttempts {
                        log.error("drain: parking job \(job.id, privacy: .public) after \(attempts, privacy: .public) permanent failures — bytes kept and operator recovery requested")
                        var parkedJob = job
                        parkedJob.attempts = attempts
                        await reportParkedJob(parkedJob)
                    } else {
                        log.error("drain: upload failed for \(job.id, privacy: .public) (attempt \(attempts, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        guard !legacyResolved.isEmpty else { return }

        // Re-check the account didn't switch during the uploads above.
        guard isCurrentUser(reference.uploadedBy) else {
            log.info("drain: aborting finalize for \(reference.projectId, privacy: .public) — account switched mid-drain")
            return
        }

        let landed = await SharePhotoFinalizer.finalize(
            publicURLs: legacyResolved.map { $0.url },
            projectId: reference.projectId,
            companyId: reference.companyId,
            projectTitle: reference.projectTitle,
            uploadedBy: reference.uploadedBy
        )
        log.info("drain: legacy finalize \(landed ? "ok" : "FAILED", privacy: .public) for project \(reference.projectId, privacy: .public) — \(legacyResolved.count, privacy: .public) photo(s)")
        if landed {
            for result in legacyResolved {
                _ = ShareUploadManifestStore.remove(id: result.jobId)
            }
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

    /// The share rail's ordering policy, in one place: photos wait when the job
    /// they were shared into has no confirmed row on the server yet.
    ///
    /// It delegates rather than deciding, and that IS the decision — the share
    /// rail gets no bespoke notion of "is this project real". It asks the same
    /// `SyncCrossEntityDependency` barrier that orders every queued write, over
    /// the same operations. Named and static so the delegation is visible at the
    /// seam and locked down by test: a future bespoke rule here fails
    /// `SharePhotoCreateBarrierTests`.
    static func holdsForUnresolvedProjectCreate(
        projectId: String,
        operations: [SyncOperation]
    ) -> Bool {
        SyncCrossEntityDependency.hasUnresolvedCreate(
            entityType: .project,
            entityId: projectId,
            in: operations
        )
    }

    static func actionForAttemptCount(_ attempts: Int) -> AttemptAction {
        if attempts < ShareUploadManifestStore.maxAttempts {
            return .upload
        }
        if attempts == ShareUploadManifestStore.maxAttempts {
            return .reportRecovery
        }
        return .reported
    }

    @MainActor
    private func reportParkedJob(_ job: ShareUploadJob) async {
        guard await SharePhotoRecoveryReporter.report(job) else {
            log.error(
                "drain: recovery notification not yet acknowledged for \(job.id, privacy: .public); will retry"
            )
            return
        }
        let persisted = ShareUploadManifestStore.update(id: job.id) {
            $0.attempts = ShareUploadManifestStore.maxAttempts + 1
        }
        if persisted {
            log.error(
                "drain: \(job.id, privacy: .public) parked with an operator recovery notification"
            )
        } else {
            // Server dedupe makes a repeated report harmless. Leave the job at
            // the threshold so a later drain can persist the acknowledgement.
            log.error(
                "drain: recovery notification acknowledged for \(job.id, privacy: .public), but local acknowledgement could not be saved"
            )
        }
    }

}
