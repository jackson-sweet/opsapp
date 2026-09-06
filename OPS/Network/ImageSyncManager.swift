//
//  ImageSyncManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI
import SwiftData
import Foundation
import Network
import Supabase

/// Seam for the crew "photos added" rail broadcast. Conformed to by
/// `NotificationRepository` (the `notify_project_photos_added` RPC); tests
/// substitute a spy.
protocol ProjectPhotosAddedNotifying {
    /// The server derives the recipients from the project row's crew list,
    /// renders the copy, and returns ONLY the user ids that received NEW rail
    /// rows — aim the companion push at exactly that list.
    @discardableResult
    func notifyProjectPhotosAdded(projectId: String, photoCount: Int) async throws -> [String]
}

extension NotificationRepository: ProjectPhotosAddedNotifying {}

/// One canonical portal row, as PostgREST takes it. Hoisted to file scope so
/// the insert can travel through a seam instead of being welded to
/// `SupabaseService.shared` — a wrong verdict on this write is what filed a
/// false bug at a customer (bug 16d487c4), so it has to be provable.
struct ProjectPhotoMirrorRow: Codable, Equatable {
    let project_id: String
    let company_id: String
    let url: String
    let source: String
    let uploaded_by: String
    let is_client_visible: Bool
    let taken_at: String
}

/// Seam for the canonical `project_photos` insert. Production talks to
/// PostgREST; tests substitute a recorder.
protocol ProjectPhotoMirrorInserting {
    /// Throws on any rejection. The classification — and the decision to file
    /// anything — belongs to the caller's single chokepoint, never here.
    func insertProjectPhotoRows(_ rows: [ProjectPhotoMirrorRow]) async throws
}

/// Seam for the two truth-probes run behind a permanent mirror rejection.
///
/// This exists because the client used to INFER absence from a failed write and
/// was wrong about a live job (bug 16d487c4). Absence is now something the
/// server states, and a stub can prove every branch of that statement without a
/// network.
protocol ProjectServerStateProbing {
    /// Whether the projects row is SELECT-able by this account. The read policy
    /// exposes only live rows, so `true` means live AND visible.
    func isProjectVisible(projectId: String) async throws -> Bool

    /// The company-scoped verdict for a row this account cannot see, from the
    /// `public.project_server_state` RPC. `nil` when the answer is
    /// unrecognizable — the caller then concludes nothing.
    func projectServerState(
        projectId: String
    ) async throws -> SyncOperationReconcilers.ProjectServerState?
}

/// Seam for the two batched reads the stranded-mirror backfill sweep makes.
///
/// Both are plain reads, but they decide whether a photo already delivered or
/// is still owed — so a wrong answer either double-delivers or re-strands. They
/// get a seam for the same reason the probes do.
protocol StrandedPortalMirrorReading {
    /// The server's legacy CSV per project. RLS returns only rows this account
    /// can view, so an invisible project is simply absent from the result —
    /// which is correct: a photo cannot be inserted against a project this
    /// account cannot see.
    func serverProjectImages(projectIds: [String]) async throws -> [String: [String]]

    /// The canonical portal rows per project, as a url set.
    func serverPhotoURLs(projectIds: [String]) async throws -> [String: Set<String>]
}

/// Seam for the auto-bug filings the portal-mirror chokepoint makes.
///
/// Filing is a real server write against the live triage queue, so it needs a
/// seam for the same reason the probes do: the tests that prove WHEN a bug is
/// filed must not file one. It also makes "filed exactly once, with this code"
/// directly assertable, which is the property that regressed in bug 16d487c4.
protocol PortalMirrorIncidentReporting {
    func reportPortalMirrorIncident(
        errorCode: String,
        summary: String,
        metadata: [String: Any]
    ) async
}

/// Production filing: one screen, one suspected file, server-side dedupe.
struct LivePortalMirrorIncidentReporter: PortalMirrorIncidentReporting {
    func reportPortalMirrorIncident(
        errorCode: String,
        summary: String,
        metadata: [String: Any]
    ) async {
        await AutoBugReporter.shared.report(
            screen: "ImageSyncManager.deliverPortalMirror",
            suspectedFile: "ImageSyncManager.swift",
            errorCode: errorCode,
            summary: summary,
            metadata: metadata
        )
    }
}

/// The production ports. Ids travel lowercased: `UUID().uuidString` is
/// uppercase and Postgres uuid text is lowercase, so an un-normalized id
/// silently matches nothing.
struct LiveProjectPortalMirrorPort:
    ProjectPhotoMirrorInserting,
    ProjectServerStateProbing,
    StrandedPortalMirrorReading {

    /// PostgREST `.in` filters are URL-encoded into the query string; chunking
    /// keeps a large local gallery from building a request no server will take.
    static let readChunkSize = 50

    func serverProjectImages(projectIds: [String]) async throws -> [String: [String]] {
        struct Row: Decodable {
            let id: String
            let project_images: [String]?
        }
        var result: [String: [String]] = [:]
        for chunk in Self.chunked(projectIds) {
            let rows: [Row] = try await SupabaseService.shared.client
                .from("projects")
                .select("id, project_images")
                .in("id", values: chunk)
                .execute()
                .value
            for row in rows {
                result[row.id.lowercased()] = row.project_images ?? []
            }
        }
        return result
    }

    func serverPhotoURLs(projectIds: [String]) async throws -> [String: Set<String>] {
        struct Row: Decodable {
            let project_id: String
            let url: String
        }
        var result: [String: Set<String>] = [:]
        for chunk in Self.chunked(projectIds) {
            let rows: [Row] = try await SupabaseService.shared.client
                .from("project_photos")
                .select("project_id, url")
                .in("project_id", values: chunk)
                .execute()
                .value
            for row in rows {
                result[row.project_id.lowercased(), default: []].insert(row.url)
            }
        }
        return result
    }

    private static func chunked(_ ids: [String]) -> [[String]] {
        stride(from: 0, to: ids.count, by: readChunkSize).map {
            Array(ids[$0..<min($0 + readChunkSize, ids.count)])
        }
    }

    func insertProjectPhotoRows(_ rows: [ProjectPhotoMirrorRow]) async throws {
        try await SupabaseService.shared.client
            .from("project_photos")
            .insert(rows)
            .execute()
    }

    func isProjectVisible(projectId: String) async throws -> Bool {
        struct ServerProjectRow: Decodable {
            let id: String
        }
        let rows: [ServerProjectRow] = try await SupabaseService.shared.client
            .from("projects")
            .select("id")
            .eq("id", value: projectId.lowercased())
            .execute()
            .value
        return !rows.isEmpty
    }

    func projectServerState(
        projectId: String
    ) async throws -> SyncOperationReconcilers.ProjectServerState? {
        let response = try await SupabaseService.shared.client
            .rpc("project_server_state", params: ["p_project_id": projectId.lowercased()])
            .execute()
        return SyncOperationReconcilers.projectServerState(from: response.data)
    }
}

/// One undelivered portal row: an S3 photo whose canonical `project_photos`
/// insert has not landed yet.
///
/// This is the persistence whose absence let bug 16d487c4 strand three photos.
/// The S3 bytes were real and the gallery CSV knew about them, but a failed or
/// skipped portal insert left NO record that delivery was still owed — so
/// nothing ever retried it, and the tile copy promising "It'll retry
/// automatically" was not true for the online path. Restart-surviving
/// (UserDefaults), deduped by url, drained by the same passes as every other
/// pending upload.
struct PendingPortalMirror: Codable, Equatable {
    /// The https S3 URL. The natural key, and half of the server-side
    /// idempotency arbiter (project_id, url).
    let url: String
    let projectId: String
    let companyId: String
    let uploadedBy: String
    /// `photo_source` raw value, e.g. "in_progress".
    let source: String
    /// Preserved across retries so a redelivered row keeps its original
    /// capture time instead of drifting to whenever the retry happened.
    let takenAt: Date
}

/// One undelivered photo tombstone: the (project, url) pair a `project_photos`
/// soft-delete statement targets. A single statement covers every row on the
/// pair, so the drain works pairs, not rows.
struct PendingPhotoSoftDelete: Equatable {
    let projectId: String
    let url: String

    /// Dedupe key. `url` cannot contain the separator in any form this app
    /// produces (S3/HTTPS URLs percent-encode it), so collision is not a risk.
    var key: String { "\(projectId)|\(url)" }
}

/// Manager for handling image synchronization between local storage, S3, and Supabase
@MainActor
class ImageSyncManager: ObservableObject {
    // Dependencies
    private let modelContext: ModelContext?
    private let connectivity: ConnectivityManager
    private let presignedURLService = PresignedURLUploadService.shared

    /// Creator of the crew photos-added rail rows. Production talks to the
    /// narrow server RPC; tests substitute a spy.
    var photosAddedSyncer: ProjectPhotosAddedNotifying = NotificationRepository.shared

    /// The canonical portal insert and the two truth-probes behind a permanent
    /// rejection. Both default to PostgREST; tests substitute recorders.
    var portalMirrorInserter: ProjectPhotoMirrorInserting = LiveProjectPortalMirrorPort()
    var projectServerStateProbe: ProjectServerStateProbing = LiveProjectPortalMirrorPort()

    /// Filer for the two portal-mirror incidents. Production writes real
    /// bug_reports rows; tests substitute a recorder.
    var portalMirrorReporter: PortalMirrorIncidentReporting = LivePortalMirrorIncidentReporter()

    /// Batched reads for the launch backfill sweep.
    var strandedMirrorReader: StrandedPortalMirrorReading = LiveProjectPortalMirrorPort()

    /// The backfill sweep is network-bound and its answer does not change
    /// within a launch, so it runs once — on the first drain pass that gets a
    /// complete answer. A failure leaves the flag down so the next pass retries.
    private var didReconcileStrandedPortalMirrors = false

    // In-memory queue of pending image uploads
    private var pendingUploads: [PendingImageUpload] = []

    /// Photos whose S3 bytes landed but whose canonical portal row has not.
    /// Durable for the same reason `pendingUploads` is: an app restart must not
    /// be what decides whether a photo reaches the client portal.
    private var pendingPortalMirrors: [PendingPortalMirror] = []

    // Current sync state
    @Published private var isSyncing = false

    // Progress tracking
    @Published var syncProgress: Double = 0
    @Published var syncingProjectId: String? = nil

    /// Bug e5310f3d — published map of in-flight uploads keyed by project
    /// id. The carousel observes this so each newly added photo appears
    /// immediately as a placeholder card with a spinner that resolves
    /// once S3 returns the public URL.
    @Published var inFlightUploads: [String: [InFlightUpload]] = [:]

    /// Bug b171536b — periodic retry timer for the pending-upload queue.
    /// `connectivityChanged` only fires on a binary connected/disconnected
    /// edge, but a weak-connection upload that silently times out at the
    /// HTTP layer never causes that edge — so the queued image would sit
    /// untouched until the next app launch. This timer kicks in whenever
    /// the queue is non-empty and retries every 30 seconds, regardless of
    /// the connectivity state vector. Stops itself once the queue drains.
    private var retryTimer: Timer?
    private static let retryInterval: TimeInterval = 30

    /// Initialize the ImageSyncManager with required dependencies
    init(modelContext: ModelContext?, connectivity: ConnectivityManager) {
        self.modelContext = modelContext
        self.connectivity = connectivity

        // Clean up UserDefaults bloat first
        cleanupUserDefaultsImageData()

        // Load any pending uploads from UserDefaults
        loadPendingUploads()
        loadPendingPortalMirrors()

        // Set up connectivity change notifications
        setupConnectivityObserver()

        // If we're already connected and have pending uploads, try to sync them
        if connectivity.isConnected && !(pendingUploads.isEmpty && pendingPortalMirrors.isEmpty) {
            Task {
                // Small delay to ensure everything is initialized
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await syncPendingImages()
            }
        }

        // Bug b171536b — if a previous session left items in the queue,
        // keep the periodic retry running so they get a fair shake even
        // without a connectivity edge.
        startRetryTimerIfNeeded()
    }

    /// Setup observer for connectivity changes to trigger syncs when coming online
    private func setupConnectivityObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectivityChanged),
            name: ConnectivityManager.connectivityChangedNotification,
            object: nil
        )
    }

    @objc private func connectivityChanged() {
        if connectivity.isConnected {
            Task {
                await syncPendingImages()
            }
        }
    }

    // MARK: - The create barrier, asked from outside the queue

    /// The outbound queue as a plain array.
    ///
    /// Fetched predicate-free and filtered in Swift on purpose: a `#Predicate`
    /// fetch of `SyncOperation` traps (uncatchable EXC_BREAKPOINT) against a
    /// table that has never held a row, and this runs on every photo save.
    /// See the note on `ProjectCacheMerge.operations`.
    private func queuedOperations() -> [SyncOperation] {
        guard let modelContext else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<SyncOperation>())) ?? []
    }

    /// True when this project has no confirmed row on the server yet — its own
    /// `create` is still queued, retrying, or parked.
    ///
    /// Every server write this file makes is scoped to a project: the
    /// `project_photos` insert is gated by an RLS policy that begins
    /// `EXISTS (SELECT 1 FROM projects …)`, and the `projects.project_images`
    /// PATCH addresses the project row itself. Against a project the server has
    /// never seen, the first is a guaranteed 42501 and the second is a 0-row
    /// PATCH that PostgREST answers 200 — a silent write-off (bug ca26fd7a,
    /// 2026-08-19: two note photos reached S3, the portal insert was rejected,
    /// and the gallery mirror "succeeded" against nothing).
    ///
    /// So a photo aimed at such a project is not sent. It is saved on the phone
    /// and queued exactly as an offline photo is, and the retry timer delivers
    /// it once the create lands. Ordering is the queue's job.
    /// Internal, not private, so `SharePhotoCreateBarrierTests` can prove this
    /// manager asks the barrier about the right project over real SwiftData rows
    /// — the connectivity guard beside it has no test seam (`isConnected` is a
    /// stored `private(set)` property), so a `saveImages` test would pass
    /// vacuously through the offline branch and prove nothing.
    func projectAwaitsItsOwnCreate(_ projectId: String) -> Bool {
        SyncCrossEntityDependency.hasUnresolvedCreate(
            entityType: .project,
            entityId: projectId,
            in: queuedOperations()
        )
    }
    
    /// Save images using S3 and update Supabase.
    ///
    /// Resilient per-photo path (Bug photo-upload-resilience). The old version
    /// uploaded the whole batch in one call that threw on the FIRST failure —
    /// so a single mid-batch timeout discarded every photo (including ones
    /// already on S3) and fell back to re-queueing all of them. Now each photo
    /// uploads independently (`ProjectPhotoBatchUploader`): the ones that land
    /// are recorded immediately, transient failures are saved locally + queued,
    /// and permanent failures surface a red failed tile — per photo, never
    /// all-or-nothing.
    ///
    /// Bug e5310f3d — in-flight placeholder tiles (one per image) are resolved
    /// individually by each photo's fate rather than cleared en masse.
    func saveImages(_ images: [UIImage], for project: Project, notifyCrew: Bool = true) async -> [String] {
        let companyId = project.companyId
        guard !companyId.isEmpty else {
            return []
        }

        let placeholders = beginInFlightUploads(images, for: project)
        var savedURLs: [String] = []

        // Two reasons a photo waits on the phone rather than going out now, and
        // they take the SAME path because they have the same answer: there is
        // no signal, or the job it belongs to has not reached the server yet
        // (its create is queued, retrying, or parked). Sending in the second
        // case is not a failed send — the portal insert's RLS policy opens with
        // EXISTS (SELECT 1 FROM projects …), so it is a guaranteed rejection
        // against a project the server has never seen (bug ca26fd7a).
        //
        // Held is not failed: the photo is on disk, renders in the carousel via
        // its local:// URL, sits in `pendingUploads`, and the retry timer
        // delivers it the moment the project lands. Nothing is shown to the
        // operator, because there is nothing for them to do.
        let awaitsProjectCreate = projectAwaitsItsOwnCreate(project.id)
        guard connectivity.isConnected, !awaitsProjectCreate else {
            for (index, image) in images.enumerated() {
                if let localURL = await saveImageLocally(image, for: project, index: index) {
                    savedURLs.append(localURL)
                }
            }
            if awaitsProjectCreate {
                DebugLogger.shared.log(
                    "saveImages holding \(images.count) photo(s) for \(project.id) — project create not on server yet",
                    level: .info,
                    category: "ImageSyncManager"
                )
            }
            endInFlightUploads(placeholders.map { $0.id }, for: project.id)
            return savedURLs
        }

        // Online — resilient concurrent upload. One outcome per input image, in
        // input order, so placeholders/images/outcomes all align by index.
        let outcomes = await presignedURLService.uploadProjectImages(images, for: project, companyId: companyId)
        let successURLs = outcomes.compactMap { $0.url }
        let uploaderId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        var mirrorOutcome: PortalMirrorOutcome = .delivered

        // 1) Record the photos that DID upload — immediately. Their S3 bytes are
        //    real; a sibling photo's failure must never drop them.
        if !successURLs.isEmpty {
            savedURLs.append(contentsOf: successURLs)

            var currentImages = project.getProjectImages()
            currentImages.append(contentsOf: successURLs)
            project.setProjectImageURLs(currentImages)

            // Canonical-first (bug 16d487c4). There is deliberately NO client
            // PATCH of the legacy projects.project_images CSV here any more.
            //
            // That PATCH was gated on `projects.edit`, which a crew member does
            // not have, so it matched 0 rows — and the client read that as "the
            // project is gone", skipped the canonical insert (gated only on
            // project VIEW, which crew DO have), filed a false absence bug, and
            // left the photo recorded nowhere but this phone. The CSV is now a
            // server-side projection of project_photos (migration
            // cluster_j_02), so delivering a photo never requires edit rights,
            // and the projection travels back to every device on the project
            // row's normal updated_at/realtime path. The local append above is
            // still made, so the carousel shows the photo this run loop.
            mirrorOutcome = await deliverPortalMirror(
                urls: successURLs,
                project: project,
                uploadedBy: uploaderId,
                source: "in_progress"
            )

            project.lastSyncedAt = Date()
            if let modelContext = modelContext {
                try? modelContext.save()
            }

            // Notify assigned crew. notifyCrew:false on the note-attachment path
            // so a photo-bearing note doesn't fire a second notification.
            if notifyCrew && mirrorOutcome.isDelivered {
                notifyCrewOfAddedPhotos(
                    project: project,
                    uploaderId: uploaderId,
                    photoCount: successURLs.count,
                    firstURL: successURLs.first
                )
            }
        }

        // 2) Resolve each tile by its own photo's fate (index-aligned).
        var permanentFailureMessages: [String] = []
        for (index, outcome) in outcomes.enumerated() {
            guard index < placeholders.count else { break }
            let tileId = placeholders[index].id
            switch outcome {
            case .success:
                if let failureMessage = mirrorOutcome.failedTileMessage {
                    // S3 + gallery took the photo but the portal cannot have it
                    // and no retry will change that — say which, and say where
                    // the photo is.
                    markInFlightUploadsFailed(
                        ids: [tileId],
                        for: project.id,
                        lastError: failureMessage
                    )
                } else {
                    // Delivered, already mirrored, or queued for retry. A queued
                    // mirror clears its tile on purpose: the photo renders from
                    // its own S3 URL and delivery is now durable, so there is
                    // nothing for the operator to do — the same doctrine the
                    // offline hold path follows.
                    endInFlightUploads([tileId], for: project.id)
                }
            case .failure(let image, _, let kind, let message):
                if case .permanent = kind {
                    permanentFailureMessages.append(message)
                    markInFlightUploadsFailed(ids: [tileId], for: project.id, lastError: message)
                } else {
                    // Transient — save locally + queue; the carousel renders the
                    // local placeholder, so clear the spinner tile.
                    DebugLogger.shared.log(
                        "saveImages transient photo failure (\(kind)) for \(project.id)",
                        level: .warning,
                        category: "ImageSyncManager"
                    )
                    if let localURL = await saveImageLocally(image, for: project, index: index) {
                        savedURLs.append(localURL)
                    }
                    endInFlightUploads([tileId], for: project.id)
                }
            }
        }

        // Auto-bug permanent rejections once (server-side dedupe collapses repeats).
        if !permanentFailureMessages.isEmpty {
            await AutoBugReporter.shared.report(
                screen: "ImageSyncManager.saveImages",
                suspectedFile: "ImageSyncManager.swift",
                errorCode: "PHOTO_UPLOAD_PERMANENT",
                summary: "saveImages: \(permanentFailureMessages.count) of \(images.count) photo(s) permanently rejected for project \(project.id). First: \(permanentFailureMessages[0])",
                metadata: [
                    "project_id": project.id,
                    "permanent_failures": permanentFailureMessages.count,
                    "image_count": images.count
                ]
            )
        }

        return savedURLs
    }

    /// Fire the "photos added" notification to assigned crew.
    ///
    /// The rail rows are created by the narrow server RPC
    /// (`notify_project_photos_added`): it derives the recipients from the
    /// project row's `team_member_ids` minus the actor, renders the copy, and
    /// returns ONLY the user ids that received NEW rows. The client no longer
    /// computes recipients or writes rows itself — the 2026-07-15
    /// notification-creation hardening revoked app-role INSERT on
    /// `notifications`, so the old per-recipient insert loop died 42501 on every
    /// upload and the rail went silently dead.
    ///
    /// The push is aimed at exactly the ids the rail accepted, and is skipped
    /// entirely when the server created nothing. Previously the push fired at
    /// the locally-computed list even when the rail write failed, so crews got a
    /// buzz with nothing behind it — that split is the thing being fixed.
    ///
    /// The uploader name and project title stay local reads: they only dress the
    /// push copy (the rail copy is server-rendered). Best-effort throughout —
    /// failures log only and never affect the upload result.
    ///
    /// - Returns: the notification task, for tests to await. Production call
    ///   sites discard it (the upload return must not block on the rail).
    @discardableResult
    func notifyCrewOfAddedPhotos(project: Project, uploaderId: String, photoCount: Int, firstURL: String?) -> Task<Void, Never>? {
        guard photoCount > 0 else { return nil }
        let projectId = project.id

        // No display name or title is resolved here any more: the companion
        // push carries the rail row's own server-rendered copy.
        let syncer = photosAddedSyncer

        return Task {
            let created: [String]
            do {
                created = try await syncer.notifyProjectPhotosAdded(
                    projectId: projectId,
                    photoCount: photoCount
                )
            } catch {
                print("[IMAGE_SYNC] Failed to create photos-added rail rows for \(projectId): \(error)")
                return
            }

            // The server's list is the dedupe truth. No new rail rows — no crew
            // to reach, or a repeat inside the server's window — means no push.
            guard !created.isEmpty else { return }

            do {
                try await OneSignalService.shared.notifyPhotosAdded(userIds: created)
            } catch {
                print("[IMAGE_SYNC] Failed to send photos-added companion push: \(error)")
            }
        }
    }

    // MARK: - Portal mirror (bug 16d487c4)

    /// What became of a batch's client-portal delivery. Every value is a
    /// statement about where the photo now IS — never a guess about why a write
    /// failed, which is the class of error this type exists to end.
    enum PortalMirrorOutcome: Equatable {
        /// The canonical rows are on the server.
        case delivered
        /// The server already held them — the repair, another device, or an
        /// earlier attempt got there first. Indistinguishable from delivered as
        /// far as the operator is concerned.
        case alreadyMirrored
        /// Not delivered yet, and durably queued. Nothing to tell anyone.
        case retryQueued
        /// The job is live in OPS but is no longer shared with this account.
        /// A permission state, not a defect: no bug is filed.
        case heldNotShared
        /// The job was deleted in OPS. Normal lifecycle: the photos stay on the
        /// phone inside the now-trashed job.
        case heldProjectDeleted
        /// The server confirms no such row, and no create is queued for it.
        case heldProjectAbsent

        /// Delivered in the only sense the crew notification cares about: the
        /// portal can render the photos right now.
        var isDelivered: Bool {
            self == .delivered || self == .alreadyMirrored
        }

        /// The failed-tile line for this outcome, or nil when the tile should
        /// simply clear. Held states earn a tile because no retry will fix
        /// them; a queued mirror does not, because it needs nothing from anyone.
        var failedTileMessage: String? {
            switch self {
            case .delivered, .alreadyMirrored, .retryQueued:
                return nil
            case .heldNotShared:
                return SyncStatusCopy.Photo.notShared
            case .heldProjectDeleted, .heldProjectAbsent:
                return SyncStatusCopy.Photo.projectMissing
            }
        }
    }

    /// The single place a photo becomes visible in the client portal, and the
    /// single place a delivery failure is classified or filed.
    ///
    /// Canonical-first by design. `project_photos` is the cross-device + portal
    /// store, and its INSERT policy asks only for company membership, the
    /// uploader's own identity, and project VIEW — everything a crew member
    /// holds. The legacy CSV is a server-side projection of these rows now
    /// (migration cluster_j_02), so no client needs `projects.edit` to deliver
    /// a photo.
    ///
    /// Nothing here is inferred. A permanent rejection is handed to the truth
    /// probes, and an absence is only ever claimed after the server has stated
    /// it — the two things whose absence made bug 16d487c4 file a false report
    /// against a job that was live the whole time.
    @discardableResult
    func deliverPortalMirror(
        urls: [String],
        project: Project,
        uploadedBy: String,
        source: String,
        takenAt: Date = Date()
    ) async -> PortalMirrorOutcome {
        guard !urls.isEmpty else { return .delivered }
        let projectId = project.id
        let companyId = project.companyId

        // One timestamp for the whole batch keeps the rows grouped
        // chronologically without needing to invent per-photo EXIF, and a
        // redelivery reuses the ORIGINAL one so a retry never rewrites when the
        // photo was taken.
        let timestamp = ISO8601DateFormatter().string(from: takenAt)
        let rows = urls.map { url in
            ProjectPhotoMirrorRow(
                project_id: projectId,
                company_id: companyId,
                url: url,
                source: source,
                uploaded_by: uploadedBy,
                is_client_visible: false,
                taken_at: timestamp
            )
        }

        // Every exit below routes through here, so the queue can never disagree
        // with the verdict: a debt is recorded exactly while delivery is still
        // owed and something might still change the answer.
        func settle(_ outcome: PortalMirrorOutcome) -> PortalMirrorOutcome {
            switch outcome {
            case .delivered, .alreadyMirrored:
                removePortalMirrors(urls: urls)
            case .retryQueued, .heldNotShared:
                // Held-not-shared stays queued on purpose: an assignment can be
                // handed back, and the photo should land the moment it is.
                enqueuePortalMirrors(
                    urls: urls,
                    projectId: projectId,
                    companyId: companyId,
                    uploadedBy: uploadedBy,
                    source: source,
                    takenAt: takenAt
                )
            case .heldProjectDeleted:
                // Nothing left to deliver to. Drop the project's queued bytes
                // too rather than re-uploading them into a trashed job forever.
                dropQueuedWork(forProject: projectId)
            case .heldProjectAbsent:
                // The auto-bug has fired and the server has been asked. Never
                // hammer a confirmed-absent project on a 30s loop; the launch
                // backfill sweep re-offers if the project is ever recreated.
                removePortalMirrors(urls: urls)
            }
            return outcome
        }

        do {
            try await portalMirrorInserter.insertProjectPhotoRows(rows)
            return settle(.delivered)
        } catch {
            // Both spellings are searched: the raw error carries the Postgres
            // text, the localized description is what string-only surfaces see.
            let description = "\(error) \(error.localizedDescription)"

            // The active-(project_id, url) arbiter already holds these rows.
            // Same doctrine as the outbound reconcilers: the constraint NAME is
            // the contract, so an unrelated 23505 falls through to be classified.
            if SyncOperationReconcilers.isActiveProjectPhotoURLDuplicate(description) {
                DebugLogger.shared.log(
                    "portal mirror for \(projectId) already held server-side (\(urls.count) url(s))",
                    level: .info,
                    category: "ImageSyncManager"
                )
                return settle(.alreadyMirrored)
            }

            guard SyncErrorClassifier.disposition(for: error) == .permanent else {
                DebugLogger.shared.log(
                    "portal mirror transient failure for \(projectId) — queued: \(error)",
                    level: .warning,
                    category: "ImageSyncManager"
                )
                return settle(.retryQueued)
            }

            return settle(await classifyPermanentMirrorRejection(
                error: error,
                urls: urls,
                project: project,
                source: source
            ))
        }
    }

    /// Turns a permanent portal-mirror rejection into a verdict the server
    /// actually stated. A probe that does not answer yields `.retryQueued` —
    /// never a conclusion, because concluding from a failed write is the bug.
    private func classifyPermanentMirrorRejection(
        error: Error,
        urls: [String],
        project: Project,
        source: String
    ) async -> PortalMirrorOutcome {
        let projectId = project.id
        let companyId = project.companyId

        let isVisible: Bool
        do {
            isVisible = try await projectServerStateProbe.isProjectVisible(projectId: projectId)
        } catch {
            DebugLogger.shared.log(
                "portal mirror visibility probe failed for \(projectId) — queued: \(error)",
                level: .warning,
                category: "ImageSyncManager"
            )
            return .retryQueued
        }

        if isVisible {
            // Unexpected, and therefore loud. The insert policy needs company +
            // uploader identity + project view, and view is proven right here —
            // so something else refused it and a human must see the raw cause.
            DebugLogger.shared.log(
                "portal mirror refused for VISIBLE project \(projectId): \(error)",
                level: .error,
                category: "ImageSyncManager"
            )
            await portalMirrorReporter.reportPortalMirrorIncident(
                errorCode: "PHOTO_PORTAL_INSERT_REFUSED",
                summary: "project_photos INSERT was refused for project \(projectId) although the row is visible to this account; \(urls.count) uploaded photo(s) queued for retry.",
                metadata: [
                    "project_id": projectId,
                    "company_id": companyId,
                    "url_count": urls.count,
                    "source": source,
                    "error": "\(error)"
                ]
            )
            return .retryQueued
        }

        let state: SyncOperationReconcilers.ProjectServerState?
        do {
            state = try await projectServerStateProbe.projectServerState(projectId: projectId)
        } catch {
            DebugLogger.shared.log(
                "project_server_state probe failed for \(projectId) — queued: \(error)",
                level: .warning,
                category: "ImageSyncManager"
            )
            return .retryQueued
        }

        switch state {
        case .active:
            // The job is live for the company; this account's view scope no
            // longer reaches it. Assignment changes are routine — no bug — and
            // visibility can come back, so the mirror stays queued.
            DebugLogger.shared.log(
                "portal mirror held for \(projectId) — job is live but no longer shared with this account",
                level: .info,
                category: "ImageSyncManager"
            )
            return .heldNotShared

        case .deleted:
            // Normal lifecycle. Trash the job locally so this phone stops
            // showing a job OPS no longer has; the photos ride along inside it.
            if let modelContext {
                try? SyncOperationReconcilers.applyProjectTombstone(
                    projectId: projectId,
                    deletedAt: Date(),
                    in: modelContext
                )
                try? modelContext.save()
            }
            DebugLogger.shared.log(
                "portal mirror held for \(projectId) — the job was deleted in OPS; tombstoned locally",
                level: .info,
                category: "ImageSyncManager"
            )
            return .heldProjectDeleted

        case .absent:
            // The create barrier is the last thing standing between "the server
            // says absent" and a filed claim: a project whose own create is
            // still queued is not missing, it simply has not been sent yet.
            if projectAwaitsItsOwnCreate(projectId) {
                DebugLogger.shared.log(
                    "portal mirror queued for \(projectId) — its own create has not landed yet",
                    level: .info,
                    category: "ImageSyncManager"
                )
                return .retryQueued
            }
            DebugLogger.shared.log(
                "portal mirror held for \(projectId) — server confirms the project row is absent",
                level: .error,
                category: "ImageSyncManager"
            )
            await portalMirrorReporter.reportPortalMirrorIncident(
                errorCode: "PROJECT_ROW_MISSING",
                summary: "projects row \(projectId) is confirmed absent server-side (no create queued); \(urls.count) uploaded photo(s) kept on device.",
                metadata: [
                    "project_id": projectId,
                    "company_id": companyId,
                    "url_count": urls.count,
                    "source": source
                ]
            )
            return .heldProjectAbsent

        case .unknown:
            // The server could not identify the caller, so it has no opinion
            // about this row. Saying so out loud rather than inheriting the
            // `nil` fallback: "I could not identify you" must never again be
            // read as "the project is gone" (bug bf2a75fb).
            DebugLogger.shared.log(
                "portal mirror queued for \(projectId) — the server could not resolve this account to a company",
                level: .warning,
                category: "ImageSyncManager"
            )
            return .retryQueued

        case nil:
            // The RPC answered something this build does not recognize. Not
            // evidence of anything — queue it.
            DebugLogger.shared.log(
                "project_server_state returned an unrecognized verdict for \(projectId) — queued",
                level: .warning,
                category: "ImageSyncManager"
            )
            return .retryQueued
        }
    }

    /// Bug 7b43be32 — flip a single photo's portal visibility on the
    /// server. The local model write is the caller's responsibility (they
    /// already have a project handle and want the UI to update on tap).
    /// Best-effort write: an error logs but does not surface to the user
    /// because the local UI has already moved.
    func setPhotoClientVisibility(url: String, isVisible: Bool, projectId: String) async throws {
        struct ProjectPhotoVisibilityUpdate: Codable {
            let is_client_visible: Bool
        }

        try await SupabaseService.shared.client
            .from("project_photos")
            .update(ProjectPhotoVisibilityUpdate(is_client_visible: isVisible))
            .eq("project_id", value: projectId)
            .eq("url", value: url)
            .execute()
    }

    /// Bug 7b43be32 — pull the live client-visibility set for a project
    /// from Supabase and hydrate `Project.clientVisibleImagesString` so
    /// the per-photo toggle reflects what the customer actually sees in
    /// the portal. Runs on project detail open. Best-effort: a network
    /// failure leaves the existing local values in place rather than
    /// emptying them.
    func refreshClientVisibility(for project: Project) async {
        struct VisibilityRow: Decodable {
            let url: String
            let is_client_visible: Bool
        }

        do {
            let rows: [VisibilityRow] = try await SupabaseService.shared.client
                .from("project_photos")
                .select("url, is_client_visible")
                .eq("project_id", value: project.id)
                .is("deleted_at", value: nil)
                .execute()
                .value

            let visibleURLs = rows.filter { $0.is_client_visible }.map { $0.url }
            project.setClientVisibleImages(visibleURLs)
            try? modelContext?.save()
        } catch {
            print("[IMAGE_SYNC] Failed to refresh client visibility for \(project.id): \(error)")
        }
    }
    
    /// Save a single image locally for offline use
    private func saveImageLocally(_ image: UIImage, for project: Project, index: Int) async -> String? {
        // Resize image if it's too large
        let resizedImage = resizeImageIfNeeded(image)

        // Use adaptive compression based on image size
        let compressionQuality = getAdaptiveCompressionQuality(for: resizedImage)

        guard let imageData = resizedImage.jpegData(compressionQuality: compressionQuality) else {
            return nil
        }

        // Log image size
        let sizeInMB = Double(imageData.count) / (1024 * 1024)

        let timestamp = Date().timeIntervalSince1970
        let filename = "local_project_\(project.id)_\(timestamp)_\(index).jpg"
        let localURL = "local://project_images/\(filename)"

        // Store the image in file system
        let success = ImageFileManager.shared.saveImage(data: imageData, localID: localURL)
        if success {

            // Create pending upload
            let pendingUpload = PendingImageUpload(
                localURL: localURL,
                projectId: project.id,
                companyId: project.companyId,
                timestamp: Date()

            )

            // Add to pending uploads
            pendingUploads.append(pendingUpload)
            savePendingUploads()

            // Mark the image as unsynced in the project
            project.addUnsyncedImage(localURL)

            // Bug b171536b — also append the local URL to the project's
            // visible image list so the carousel renders the photo
            // immediately, even when the upload's still queued. Local
            // URLs render via ImageFileManager, and `syncImagesForProject`
            // swaps each local URL out for the S3 URL once the upload
            // succeeds, so the substitution is invisible to the user.
            // Without this, a weak-connection failure left the photo
            // saved on disk but missing from the UI — making the user
            // think the upload had silently dropped it.
            var currentImages = project.getProjectImages()
            if !currentImages.contains(localURL) {
                currentImages.append(localURL)
                project.setProjectImageURLs(currentImages)
            }

            // Bug b171536b — kick the periodic retry timer so the queue
            // gets reattempted even if connectivity never toggles.
            startRetryTimerIfNeeded()

            return localURL
        }

        return nil
    }

    // MARK: - Periodic Retry Timer (Bug b171536b)

    /// True while any durable delivery is still owed — bytes to upload, or a
    /// portal row to insert. Both queues keep the timer alive: a photo whose
    /// bytes landed but whose portal row did not is exactly the case that
    /// stranded in bug 16d487c4, and it deserves the same 30s retry.
    ///
    /// Internal, not private, so tests can assert the timer's own liveness
    /// predicate — `retryTimer` is private state with no other observable
    /// surface, and "the retry stopped running" is precisely the failure that
    /// strands a photo.
    var hasQueuedDeliveryWork: Bool {
        !pendingUploads.isEmpty || !pendingPortalMirrors.isEmpty
    }

    private func startRetryTimerIfNeeded() {
        guard retryTimer == nil, hasQueuedDeliveryWork else { return }
        retryTimer = Timer.scheduledTimer(
            withTimeInterval: Self.retryInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !self.hasQueuedDeliveryWork {
                    self.stopRetryTimer()
                    return
                }
                if self.connectivity.isConnected {
                    await self.syncPendingImages()
                }
                if !self.hasQueuedDeliveryWork {
                    self.stopRetryTimer()
                }
            }
        }
    }

    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    // MARK: - Site-Visit Handoff Photos (Carol Dancer stranding fix)

    /// Enqueue an ALREADY-SAVED `local://` image into the durable upload queue.
    ///
    /// The queue was previously fed only by `saveImageLocally`, which both
    /// writes the bytes and appends the entry — so photos whose bytes were
    /// saved elsewhere (site-visit capture writes straight to ImageFileManager)
    /// had no path into it, and their optimistic `ProjectPhoto` rows stayed
    /// phone-local forever. This is the missing entry point: it queues a file
    /// that already exists on disk. Restart-surviving (UserDefaults), deduped
    /// by URL, drained by the same retry timer / connectivity passes as every
    /// other pending upload.
    func enqueueExistingLocalImage(localURL: String, projectId: String, companyId: String) {
        guard localURL.hasPrefix("local://") else { return }
        guard ImageFileManager.shared.imageExists(localID: localURL) else { return }
        guard !pendingUploads.contains(where: { $0.localURL == localURL }) else { return }

        pendingUploads.append(PendingImageUpload(
            localURL: localURL,
            projectId: projectId,
            companyId: companyId,
            timestamp: Date()
        ))
        savePendingUploads()
        startRetryTimerIfNeeded()
    }

    /// Reconciliation sweep for stranded handoff photos. Any `ProjectPhoto`
    /// row still carrying a `local://` url with `needsSync == true` is a photo
    /// whose bytes exist ONLY on this phone — no server backfill can recover
    /// it, so this sweep is the sole healing path for projects converted
    /// before the durable-enqueue fix (and the safety net behind it). Runs at
    /// the top of every `syncPendingImages` pass (startup + reconnect + retry).
    ///
    /// Rows whose url matches a pending `PhotoAnnotation` are skipped: the
    /// dimensioned-capture pipeline uploads those itself (HEIC + rendered
    /// deliverable), inserts the `project_photos` row, and heals the local row
    /// on success — queueing them here too would upload the same photo twice
    /// and double-tile every teammate's gallery.
    func reconcileStrandedProjectPhotos() {
        guard let modelContext = modelContext else { return }

        let stranded: [ProjectPhoto]
        do {
            stranded = try modelContext.fetch(FetchDescriptor<ProjectPhoto>(
                predicate: #Predicate { $0.needsSync == true && $0.deletedAt == nil }
            ))
        } catch {
            DebugLogger.shared.log(
                "Stranded-photo sweep fetch failed: \(error)",
                level: .warning,
                category: "ImageSyncManager"
            )
            return
        }
        guard !stranded.isEmpty else { return }

        let pendingAnnotationURLs: Set<String> = {
            let descriptor = FetchDescriptor<PhotoAnnotation>(
                predicate: #Predicate { $0.needsSync == true && $0.deletedAt == nil }
            )
            let annotations = (try? modelContext.fetch(descriptor)) ?? []
            return Set(annotations.map(\.photoURL))
        }()

        var enqueued = 0
        for row in stranded {
            guard row.url.hasPrefix("local://") else { continue }
            guard !pendingAnnotationURLs.contains(row.url) else { continue }
            guard ImageFileManager.shared.imageExists(localID: row.url) else { continue }
            guard !pendingUploads.contains(where: { $0.localURL == row.url }) else { continue }

            pendingUploads.append(PendingImageUpload(
                localURL: row.url,
                projectId: row.projectId,
                companyId: row.companyId,
                timestamp: Date()
            ))
            enqueued += 1
        }

        guard enqueued > 0 else { return }
        DebugLogger.shared.log(
            "Stranded-photo sweep enqueued \(enqueued) local photo(s) for upload",
            level: .info,
            category: "ImageSyncManager"
        )
        savePendingUploads()
        startRetryTimerIfNeeded()
    }

    // MARK: - Stranded portal-mirror backfill (bug 16d487c4)

    /// Re-delivers photos stranded by the pre-fix online path, without anyone
    /// having to touch the affected phone.
    ///
    /// The strand has a precise shape: an https URL sitting in this device's
    /// local gallery CSV with NO canonical `project_photos` row and NO entry in
    /// the SERVER's CSV. That combination can only mean one thing — this device
    /// uploaded the bytes and its portal delivery was skipped. Legacy photos
    /// always appear in the server CSV, so they never match; already-delivered
    /// photos have a server row, so they never match either; projects this
    /// account cannot see drop out of the read for free, which is correct
    /// because a photo cannot be inserted against a project it cannot view.
    ///
    /// Runs once per launch on the first drain pass that gets a complete
    /// answer. Delivery and idempotency ride the retry queue and the
    /// active-(project_id, url) arbiter, so a row the PM repair already
    /// inserted comes back `.alreadyMirrored` rather than duplicating.
    func reconcileStrandedPortalMirrors() async {
        guard !didReconcileStrandedPortalMirrors else { return }
        guard let modelContext else { return }

        // Attribution is truthful only because this strand class is created by
        // THIS device's own writes. With no operator id there is nothing
        // honest to attribute, and the insert would be refused anyway.
        let uploaderId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        guard !uploaderId.isEmpty else { return }

        let projects: [Project]
        do {
            projects = try modelContext.fetch(FetchDescriptor<Project>(
                predicate: #Predicate { $0.deletedAt == nil }
            ))
        } catch {
            DebugLogger.shared.log(
                "Stranded portal-mirror sweep fetch failed: \(error)",
                level: .warning,
                category: "ImageSyncManager"
            )
            return
        }

        var localURLsByProject: [String: [String]] = [:]
        for project in projects where !project.companyId.isEmpty {
            let remote = project.getProjectImages().filter { $0.hasPrefix("http") }
            guard !remote.isEmpty else { continue }
            localURLsByProject[project.id] = remote
        }
        guard !localURLsByProject.isEmpty else {
            didReconcileStrandedPortalMirrors = true
            return
        }

        let projectIds = Array(localURLsByProject.keys).map { $0.lowercased() }
        let serverCSV: [String: [String]]
        let serverRows: [String: Set<String>]
        do {
            serverCSV = try await strandedMirrorReader.serverProjectImages(projectIds: projectIds)
            // Only projects this account can actually see are worth asking
            // about — and only those can receive an insert.
            let visible = Array(serverCSV.keys)
            serverRows = visible.isEmpty
                ? [:]
                : try await strandedMirrorReader.serverPhotoURLs(projectIds: visible)
        } catch {
            // Flag stays down: an incomplete answer must not be mistaken for
            // "nothing was stranded".
            DebugLogger.shared.log(
                "Stranded portal-mirror sweep read failed — will retry next pass: \(error)",
                level: .warning,
                category: "ImageSyncManager"
            )
            return
        }

        let companyIdByProject = Dictionary(
            projects.map { ($0.id.lowercased(), $0.companyId) },
            uniquingKeysWith: { first, _ in first }
        )

        var enqueued = 0
        for (projectId, localURLs) in localURLsByProject {
            let key = projectId.lowercased()
            // Absent from the read = invisible to this account. Skip it.
            guard let csv = serverCSV[key] else { continue }
            guard let companyId = companyIdByProject[key], !companyId.isEmpty else { continue }
            let delivered = Set(csv).union(serverRows[key] ?? [])
            let stranded = localURLs.filter { !delivered.contains($0) }
            guard !stranded.isEmpty else { continue }

            enqueuePortalMirrors(
                urls: stranded,
                projectId: projectId,
                companyId: companyId,
                uploadedBy: uploaderId,
                source: "in_progress",
                takenAt: Date()
            )
            enqueued += stranded.count
        }

        didReconcileStrandedPortalMirrors = true
        guard enqueued > 0 else { return }
        DebugLogger.shared.log(
            "Stranded portal-mirror sweep queued \(enqueued) photo(s) for portal delivery",
            level: .info,
            category: "ImageSyncManager"
        )
    }

    /// The `project_photos` insert for a drained handoff photo. Carries the
    /// LOCAL row's identity + metadata so provenance survives the drain.
    ///
    /// Site visits are now cloud-backed. A canonical UUID provenance link is
    /// included when present; malformed legacy phone-only ids are omitted so a
    /// historical row cannot 22P02/FK-reject an otherwise recoverable photo.
    struct HandoffProjectPhotoInsert: Encodable {
        let id: String
        let projectId: String
        let companyId: String
        let url: String
        let thumbnailUrl: String?
        let renderedUrl: String?
        let source: String
        let siteVisitId: String?
        let uploadedBy: String?
        let caption: String?
        let takenAt: String
        let isClientVisible: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case projectId = "project_id"
            case companyId = "company_id"
            case url
            case thumbnailUrl = "thumbnail_url"
            case renderedUrl = "rendered_url"
            case source
            case siteVisitId = "site_visit_id"
            case uploadedBy = "uploaded_by"
            case caption
            case takenAt = "taken_at"
            case isClientVisible = "is_client_visible"
        }
    }

    /// Build the server insert for a handoff row whose upload just landed.
    /// The id travels lowercased (Postgres uuids are lowercase) so the insert
    /// echo merges back into the SAME local row instead of duplicating it.
    /// An empty uploader is omitted — `uploaded_by` is a uuid column and an
    /// empty string would 22P02 the whole insert.
    static func handoffPhotoInsert(for row: ProjectPhoto, remoteURL: String) -> HandoffProjectPhotoInsert {
        let uploader = row.uploadedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalVisitId = row.siteVisitId.flatMap {
            UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines))?
                .uuidString
                .lowercased()
        }
        let renderedURL: String?
        if row.renderedURL == row.url {
            renderedURL = remoteURL
        } else if let value = row.renderedURL,
                  SiteVisitMediaSyncManager.isRemoteURL(value) {
            renderedURL = value
        } else {
            renderedURL = nil
        }
        let thumbnailURL = row.thumbnailURL.flatMap {
            SiteVisitMediaSyncManager.isRemoteURL($0) ? $0 : nil
        }
        return HandoffProjectPhotoInsert(
            id: row.id.lowercased(),
            projectId: row.projectId,
            companyId: row.companyId,
            url: remoteURL,
            thumbnailUrl: thumbnailURL,
            renderedUrl: renderedURL,
            source: row.source,
            siteVisitId: canonicalVisitId,
            uploadedBy: ProjectPhotoUploaderIdentity.canonicalUserID(uploader),
            caption: row.caption,
            takenAt: ISO8601DateFormatter().string(from: row.takenAt ?? row.createdAt),
            isClientVisible: false
        )
    }

    /// Heal a handoff row IN PLACE after its upload + server insert landed.
    /// The gallery dedupes by URL, so the row's url must swap local:// → S3
    /// in place — inserting a second row instead would double-tile. A rendered
    /// URL that pointed at the same local file follows the swap.
    static func healHandoffPhotoRow(_ row: ProjectPhoto, remoteURL: String) {
        if row.renderedURL == row.url {
            row.renderedURL = remoteURL
        }
        row.url = remoteURL
        row.id = row.id.lowercased()
        row.needsSync = false
        row.lastSyncedAt = Date()
    }

    /// Local ProjectPhoto rows (site-visit handoff) keyed by their local:// url.
    private func handoffPhotoRows(projectId: String, localURLs: [String]) -> [String: ProjectPhoto] {
        guard let modelContext = modelContext, !localURLs.isEmpty else { return [:] }
        let urls = localURLs
        let descriptor = FetchDescriptor<ProjectPhoto>(
            predicate: #Predicate { $0.projectId == projectId && urls.contains($0.url) && $0.deletedAt == nil }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(rows.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Insert the `project_photos` row for a drained handoff photo. Returns
    /// whether the row is now on the server — the caller only heals the local
    /// row (and drops the queue entry) on success, so a failed insert retries
    /// on the next drain pass instead of silently losing portal visibility.
    private func insertHandoffPhotoRow(_ row: ProjectPhoto, remoteURL: String) async -> Bool {
        let insert = Self.handoffPhotoInsert(for: row, remoteURL: remoteURL)
        do {
            try await SupabaseService.shared.client
                .from("project_photos")
                .insert(insert)
                .execute()
            return true
        } catch {
            // A duplicate-key reject means a prior drain's insert DID land and
            // only the response was lost — the server row exists, so heal.
            if "\(error)".contains("23505") { return true }
            let kind = await AutoBugReporter.shared.reportIfPermanent(
                error,
                screen: "ImageSyncManager.insertHandoffPhotoRow",
                suspectedFile: "ImageSyncManager.swift",
                summary: "Handoff project_photos INSERT failed for project \(row.projectId): \(error.localizedDescription)",
                metadata: [
                    "project_id": row.projectId,
                    "company_id": row.companyId,
                    "photo_id": row.id
                ]
            )
            DebugLogger.shared.log(
                "handoff project_photos insert failed (\(kind)) for \(row.projectId): \(error)",
                level: .error,
                category: "ImageSyncManager"
            )
            return false
        }
    }

    /// Delete an image from S3 and locally
    func deleteImage(_ urlString: String, from project: Project) async -> Bool {
        // Check if it's a local URL
        if urlString.starts(with: "local://") {
            _ = ImageFileManager.shared.deleteImage(localID: urlString)
            pendingUploads.removeAll { $0.localURL == urlString }
            savePendingUploads()
            return true
        }

        // If it's an S3 URL, remove from local cache
        if urlString.contains("s3") && urlString.contains("amazonaws.com") {
            _ = ImageFileManager.shared.deleteImage(localID: urlString)
            return true
        }

        // Handle legacy URLs
        if urlString.contains("opsapp.co/") && urlString.contains("/img/") {
            ImageFileManager.shared.deleteImage(localID: urlString)
            return true
        }

        return false
    }

    /// Durably delete a single project photo from EVERY gallery source.
    ///
    /// The gallery (`Project+Gallery.mergedGalleryImageURLs`) is the union of
    /// the legacy `projects.project_images` CSV and synced `project_photos`
    /// rows, deduped by URL — so a photo only disappears for good when it is
    /// removed from BOTH. The previous delete path rewrote only the CSV, so a
    /// photo that also had a `project_photos` row simply reappeared from the
    /// synced store (and stayed visible in the web client portal). This is the
    /// complete, correct delete:
    ///   1. Optimistic local removal — drop from the CSV so the carousel's
    ///      `@Query` drops the tile immediately, then push the `project_images`
    ///      change through `DataController.updateProjectFields` (which records a
    ///      SyncOperation). That recorded op is what actually persists the
    ///      removal to Supabase AND arms the inbound-merge pending-field guard —
    ///      `project.needsSync` alone never drains for Project, so a flag-only
    ///      removal would never reach the server and the photo would reappear
    ///      from the server CSV on the next inbound merge (bug 209281ba). Also
    ///      soft-delete the local `ProjectPhoto` row.
    ///   2. Remote `project_photos` soft-delete so it stays gone for teammates
    ///      and the client portal.
    ///   3. Best-effort S3 object delete (server authorizes by company; no
    ///      client AWS credentials).
    ///   4. Local cache + file cleanup.
    ///
    /// Gated by the caller on `projects.edit`; this method assumes authorization.
    @discardableResult
    func deleteProjectPhoto(_ url: String, from project: Project, dataController: DataController) async -> Bool {
        // 1a. Legacy CSV — optimistic local removal for the @Query-backed UI.
        var images = project.getProjectImages()
        let removedFromCSV = images.contains(url)
        if removedFromCSV {
            images.removeAll { $0 == url }
            project.setProjectImageURLs(images)
        }

        // 1b. Soft-delete the local synced row(s) so the @Query-backed carousel
        //     drops the tile this run loop.
        if let modelContext = modelContext {
            let pid = project.id
            let descriptor = FetchDescriptor<ProjectPhoto>(
                predicate: #Predicate { $0.projectId == pid && $0.url == url && $0.deletedAt == nil }
            )
            if let rows = try? modelContext.fetch(descriptor) {
                let now = Date()
                for row in rows {
                    row.deletedAt = now
                    row.updatedAt = now
                    row.needsSync = true
                }
            }
            try? modelContext.save()
        }

        // 1c. Push the canonical project_images write. updateProjectFields
        //     records a SyncOperation, which BOTH persists the CSV removal to
        //     Supabase AND registers the pending-field guard so the next inbound
        //     merge can't resurrect the photo from the server CSV (bug 209281ba).
        //     A bare project.needsSync never drains for Project — only recorded
        //     ops do — so this awaited push is mandatory, not optional.
        if removedFromCSV {
            do {
                try await dataController.updateProjectFields(
                    projectId: project.id,
                    fields: ["project_images": .array(images.map { .string($0) })]
                )
            } catch {
                DebugLogger.shared.log(
                    "project_images push failed for photo delete \(url): \(error)",
                    level: .warning,
                    category: "ImageSyncManager"
                )
            }
        }

        // 2. Remote project_photos soft-delete (best-effort).
        await softDeleteProjectPhotoRow(url: url, projectId: project.id)

        // 3. Best-effort S3 object delete (orphan cleanup).
        do {
            try await presignedURLService.deleteImage(url: url)
        } catch {
            DebugLogger.shared.log(
                "S3 object delete failed for \(url): \(error)",
                level: .warning,
                category: "ImageSyncManager"
            )
        }

        // 4. Local cache + file cleanup.
        _ = ImageFileManager.shared.deleteImage(localID: url)
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url
        ImageCache.shared.remove(forKey: cacheKey)

        return true
    }

    /// Soft-delete the `project_photos` row(s) for a URL by stamping
    /// `deleted_at`. Returns whether the server accepted the write. On failure
    /// the local rows keep `needsSync = true`, and `drainPendingPhotoSoftDeletes`
    /// re-pushes them on every sync pass until the server accepts — a photo the
    /// operator deleted must never resurrect because the delete raced a dead
    /// spot. Permanent rejections auto-file so a policy regression is loud
    /// (May-12 class: silent RLS swallow).
    @discardableResult
    private func softDeleteProjectPhotoRow(url: String, projectId: String) async -> Bool {
        struct ProjectPhotoSoftDelete: Codable { let deleted_at: String }
        do {
            try await SupabaseService.shared.client
                .from("project_photos")
                .update(ProjectPhotoSoftDelete(deleted_at: ISO8601DateFormatter().string(from: Date())))
                .eq("project_id", value: projectId)
                .eq("url", value: url)
                .is("deleted_at", value: nil)
                .execute()
            markPhotoSoftDeleteSynced(url: url, projectId: projectId)
            return true
        } catch {
            let kind = await AutoBugReporter.shared.reportIfPermanent(
                error,
                screen: "ImageSyncManager.softDeleteProjectPhotoRow",
                suspectedFile: "ImageSyncManager.swift",
                summary: "project_photos soft-delete failed for \(projectId): \(error.localizedDescription)",
                metadata: [
                    "project_id": projectId,
                    "url": url
                ]
            )
            DebugLogger.shared.log(
                "project_photos soft-delete failed (\(kind)) for \(url): \(error)",
                level: .error,
                category: "ImageSyncManager"
            )
            return false
        }
    }

    /// Clears the retry flag on the local rows a confirmed remote soft-delete
    /// covered.
    private func markPhotoSoftDeleteSynced(url: String, projectId: String) {
        guard let modelContext else { return }
        Self.clearPendingSoftDelete(url: url, projectId: projectId, in: modelContext)
    }

    /// The flag-clearing half of a confirmed soft-delete, as a plain store
    /// operation so it is provable without a network seam.
    ///
    /// Scoped to rows already tombstoned locally: a live row on the same URL is
    /// a different photo's business and keeps whatever pending state it has.
    static func clearPendingSoftDelete(url: String, projectId: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<ProjectPhoto>(
            predicate: #Predicate<ProjectPhoto> {
                $0.projectId == projectId && $0.url == url
            }
        )
        guard let rows = try? context.fetch(descriptor) else { return }
        var changed = false
        for row in rows where row.deletedAt != nil && row.needsSync {
            row.needsSync = false
            changed = true
        }
        if changed {
            try? context.save()
        }
    }

    /// Every (project, url) pair whose local tombstone the server has not
    /// confirmed — the drain's work list.
    ///
    /// Fetches on the single `deletedAt` clause and filters `needsSync` in
    /// Swift: the compound `#Predicate` is a type-check budget risk, and the
    /// tombstoned set is tiny. One UPDATE statement covers every row on a
    /// (project, url) pair, so pairs are deduped before the network sees them.
    static func pendingSoftDeleteTargets(in context: ModelContext) -> [PendingPhotoSoftDelete] {
        let descriptor = FetchDescriptor<ProjectPhoto>(
            predicate: #Predicate<ProjectPhoto> { $0.deletedAt != nil }
        )
        guard let tombstoned = try? context.fetch(descriptor) else { return [] }
        var seen = Set<String>()
        var targets: [PendingPhotoSoftDelete] = []
        for row in tombstoned where row.needsSync {
            let target = PendingPhotoSoftDelete(projectId: row.projectId, url: row.url)
            guard seen.insert(target.key).inserted else { continue }
            targets.append(target)
        }
        return targets
    }

    /// Re-pushes locally soft-deleted photo rows whose remote soft-delete has
    /// not been confirmed (`deletedAt != nil && needsSync`). Runs on every
    /// drain pass (startup, reconnect, retry timer) — cheap when empty.
    ///
    /// Without this, an offline or otherwise failed delete lost the remote
    /// soft-delete forever and the photo resurrected on the next inbound sync:
    /// `deleteProjectPhoto` already stamped `deletedAt`/`needsSync` on the local
    /// row, but nothing ever drained that flag (bug 1154fe67).
    private func drainPendingPhotoSoftDeletes() async {
        guard let modelContext, connectivity.isConnected else { return }
        let targets = Self.pendingSoftDeleteTargets(in: modelContext)
        guard !targets.isEmpty else { return }
        for target in targets {
            _ = await softDeleteProjectPhotoRow(url: target.url, projectId: target.projectId)
        }
    }

    /// Sync all pending images to S3 and Supabase
    func syncPendingImages() async {

        guard !isSyncing, connectivity.isConnected else {
            if isSyncing {
            }
            if !connectivity.isConnected {
            }
            return
        }

        // Stranded-photo recovery runs on every drain pass (startup, reconnect,
        // retry timer) BEFORE the empty-queue check — a launch with an empty
        // queue but stranded local:// rows must still pick them up.
        reconcileStrandedProjectPhotos()

        // The other strand class, and the one bug 16d487c4 created: bytes that
        // reached S3 and the local gallery while their portal delivery was
        // skipped. Once per launch, network-bound, and self-healing — this is
        // what re-delivers the affected photos without anyone touching the
        // phone they are stranded on.
        await reconcileStrandedPortalMirrors()

        // Unconfirmed soft-deletes drain on the same schedule and for the same
        // reason: a delete that raced a dead spot must not leave the photo alive
        // on the server. Runs BEFORE the empty-queue check — a launch with no
        // pending uploads but an undelivered tombstone must still push it.
        await drainPendingPhotoSoftDeletes()

        // Owed portal rows drain on the same schedule and BEFORE the
        // empty-queue check: a photo whose bytes are already in S3 has no
        // pending upload, so a launch with nothing to upload must still deliver
        // it. This is what finally makes the tile's "It'll retry automatically"
        // true for the online path (bug 16d487c4).
        await drainPendingPortalMirrors()

        if pendingUploads.isEmpty {
            if !hasQueuedDeliveryWork { stopRetryTimer() }
            return
        }
        
        isSyncing = true
        
        // Group by project for batch uploading
        var uploadsByProject: [String: [PendingImageUpload]] = [:]
        for upload in pendingUploads {
            if uploadsByProject[upload.projectId] == nil {
                uploadsByProject[upload.projectId] = []
            }
            uploadsByProject[upload.projectId]?.append(upload)
        }
        
        
        // Process each project's uploads
        for (projectId, uploads) in uploadsByProject {
            await syncImagesForProject(projectId: projectId, uploads: uploads)
        }
        
        isSyncing = false
    }
    
    /// Sync images for a specific project
    private func syncImagesForProject(projectId: String, uploads: [PendingImageUpload]) async {
        guard let project = getProject(by: projectId) else {
            return
        }

        let companyId = project.companyId
        guard !companyId.isEmpty else {
            return
        }

        // The same barrier `saveImages` applies, applied again on every drain.
        // The queue is durable and the retry timer fires every 30s, so without
        // this a photo held at capture would be pushed into the guaranteed
        // rejection on the very next tick. Returning early leaves the uploads in
        // `pendingUploads`, which keeps the retry timer alive — so the photo is
        // re-offered for free until the project's create lands, then delivered.
        guard !projectAwaitsItsOwnCreate(projectId) else {
            DebugLogger.shared.log(
                "syncImagesForProject holding \(uploads.count) photo(s) for \(projectId) — project create not on server yet",
                level: .info,
                category: "ImageSyncManager"
            )
            return
        }

        // The other end of the same question: a job that is GONE. Uploading
        // bytes into a trashed job every 30s helps nobody, so settle instead —
        // free when this phone already holds the tombstone, and one probe when
        // it does not (this runs only for projects that actually have queued
        // work, so the cost is bounded by real stranded photos).
        if await projectIsSettledAsDeleted(project) {
            DebugLogger.shared.log(
                "syncImagesForProject settling \(uploads.count) photo(s) for \(projectId) — the job was deleted in OPS",
                level: .info,
                category: "ImageSyncManager"
            )
            dropQueuedWork(forProject: projectId)
            if !hasQueuedDeliveryWork { stopRetryTimer() }
            return
        }

        // Pair each pending upload with its decoded image, KEEPING the localURL
        // link. The old version compactMapped to a bare [UIImage] then remapped
        // results back BY POSITION (s3Results[index]) — which misaligned and
        // permanently stranded local:// URLs the moment any image was skipped.
        // Undecodable uploads can never succeed, so drop them from the queue.
        var pairs: [(upload: PendingImageUpload, image: UIImage)] = []
        var undecodable: [PendingImageUpload] = []
        for upload in uploads {
            if let imageData = ImageFileManager.shared.getImageData(localID: upload.localURL),
               let image = UIImage(data: imageData) {
                pairs.append((upload, image))
            } else if let image = upload.originalImage {
                pairs.append((upload, image))
            } else {
                undecodable.append(upload)
            }
        }

        if !undecodable.isEmpty {
            let dead = Set(undecodable.map { $0.localURL })
            pendingUploads.removeAll { dead.contains($0.localURL) }
            savePendingUploads()
        }

        guard !pairs.isEmpty else {
            if pendingUploads.isEmpty { stopRetryTimer() }
            return
        }

        // Resilient per-photo upload — one failure never aborts the batch.
        let images = pairs.map { $0.image }
        let outcomes = await presignedURLService.uploadProjectImages(images, for: project, companyId: companyId)

        // Reconcile by IDENTITY: each upload's local:// URL is swapped for ITS
        // OWN remote URL, found by identity (never by array position).
        let results: [(localURL: String, outcome: ProjectImageUploadOutcome)] =
            zip(pairs, outcomes).map { ($0.0.upload.localURL, $0.1) }

        // Site-visit handoff photos carry a local ProjectPhoto row keyed by the
        // same local:// URL. They drain through their own path below (per-photo
        // server insert with the row's identity + metadata, then the row heals
        // in place) — the legacy CSV path must not also insert a generic
        // `in_progress` row for them, or the gallery double-tiles.
        let handoffRowsByURL = handoffPhotoRows(projectId: projectId, localURLs: results.map(\.localURL))
        let legacyResults = results.filter { handoffRowsByURL[$0.localURL] == nil }
        let handoffResults = results.filter { handoffRowsByURL[$0.localURL] != nil }

        let reconciled = GalleryReconciler.reconcileDrain(
            currentImageURLs: project.getProjectImages(),
            results: legacyResults
        )

        if !reconciled.syncedLocalURLs.isEmpty {
            project.setProjectImageURLs(reconciled.updatedImageURLs)
            for localURL in reconciled.syncedLocalURLs {
                project.markImageAsSynced(localURL)
            }

            // No client CSV PATCH here either (bug 16d487c4). This one had no
            // write guard at all: for a crew member it matched 0 rows, PostgREST
            // answered 200, and `project.needsSync = false` wrote the change off
            // silently. The server projects the CSV from project_photos now, so
            // the canonical delivery below is the only write this path needs.

            // Canonical portal rows for the newly landed URLs, through the same
            // classification chokepoint the online path uses.
            let uploaderId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
            await deliverPortalMirror(
                urls: reconciled.newRemoteURLs,
                project: project,
                uploadedBy: uploaderId,
                source: "in_progress"
            )

            project.lastSyncedAt = Date()

            // Drop the drained (synced) uploads from the queue.
            let synced = Set(reconciled.syncedLocalURLs)
            pendingUploads.removeAll { synced.contains($0.localURL) }
            savePendingUploads()

            if let modelContext = modelContext {
                try? modelContext.save()
            }
        }

        // Drain the handoff-owned uploads: per-photo server insert carrying
        // the row's own id/source/caption/site_visit_id, then the local row
        // heals local:// → S3 in place. A failed insert keeps the entry queued
        // so the next pass retries; the S3 bytes are re-uploaded then, which is
        // the price of never losing the portal row.
        var inserted: [(localURL: String, row: ProjectPhoto, remoteURL: String)] = []
        for (localURL, outcome) in handoffResults {
            guard let remoteURL = outcome.url,
                  let row = handoffRowsByURL[localURL],
                  await insertHandoffPhotoRow(row, remoteURL: remoteURL) else { continue }
            inserted.append((localURL, row, remoteURL))
        }
        // Camera retirement requires an authoritative row, including lost-response
        // duplicate inserts. Read once for the project, then match exact identities.
        let hasCameraReceipts = inserted.contains { $0.localURL.hasPrefix("local://project_images/capture_") }
        let canonical = hasCameraReceipts
            ? (try? await ProjectPhotoRepository(companyId: companyId).fetchForProject(projectId)) ?? [] : []
        var deliveries: [StagedPhotoDestinations.ProjectDelivery] = []
        for entry in inserted {
            let remoteURL: String
            if entry.localURL.hasPrefix("local://project_images/capture_") {
                guard let canonicalURL = StagedPhotoDestinations.canonicalCaptureURL(for: entry.row, receipts: canonical) else { continue }
                remoteURL = canonicalURL
            } else { remoteURL = entry.remoteURL }
            deliveries.append(.init(id: entry.row.id, projectID: entry.row.projectId, companyID: entry.row.companyId,
                uploadedBy: entry.row.uploadedBy, localURL: entry.localURL, remoteURL: remoteURL))
        }
        if !deliveries.isEmpty, let modelContext {
            do {
                try StagedPhotoDestinations.persistProjectDeliveries(deliveries, context: modelContext)
                for delivery in deliveries {
                    if let row = handoffRowsByURL[delivery.localURL] { Self.healHandoffPhotoRow(row, remoteURL: delivery.remoteURL) }
                    var seen = Set<String>()
                    project.setProjectImageURLs(project.getProjectImages().map { $0 == delivery.localURL ? delivery.remoteURL : $0 }.filter { seen.insert($0).inserted })
                }
                // Only now are the canonical URL and row healing durable locally.
                // Reopen also reconciles any retirement whose receipt write fails.
                let localURLs = Set(deliveries.map(\.localURL))
                try? await DurableCaptureStore.shared.recordDelivered(localURLs: localURLs)
                pendingUploads.removeAll { localURLs.contains($0.localURL) }
                savePendingUploads()
            } catch {
                // Original rows, upload queue and camera bytes remain recoverable.
                DebugLogger.shared.log("Photo delivery could not be saved locally: \(error)", level: .warning, category: "ImageSyncManager")
            }
        }

        // Permanent failures will keep failing — drop them from the queue and
        // auto-bug, so the 30s retry loop doesn't hammer a rejection forever.
        // Transient failures stay queued for the next pass (Bug b171536b).
        let permanentLocalURLs = zip(pairs, outcomes)
            .filter { $0.1.isPermanentFailure }
            .map { $0.0.upload.localURL }
        if !permanentLocalURLs.isEmpty {
            let dead = Set(permanentLocalURLs)
            pendingUploads.removeAll { dead.contains($0.localURL) }
            savePendingUploads()
            await AutoBugReporter.shared.report(
                screen: "ImageSyncManager.syncImagesForProject",
                suspectedFile: "ImageSyncManager.swift",
                errorCode: "PHOTO_DRAIN_PERMANENT",
                summary: "Offline-drain: \(permanentLocalURLs.count) of \(pairs.count) queued photo(s) permanently rejected for project \(projectId).",
                metadata: [
                    "project_id": projectId,
                    "permanent_failures": permanentLocalURLs.count,
                    "queued_count": uploads.count
                ]
            )
        }

        // Keep the periodic retry timer alive only while delivery is still owed
        // — bytes to upload OR a portal row to insert; otherwise stop waking the
        // runloop every 30s.
        if hasQueuedDeliveryWork {
            startRetryTimerIfNeeded()
        } else {
            stopRetryTimer()
        }
    }
    
    /// Whether this job is deleted and the drain should stop working for it.
    ///
    /// A local tombstone answers for free. Otherwise the server is asked, and
    /// only `deleted` counts: `active`, `absent`, an unrecognized answer, and a
    /// probe that throws all return false, because none of them is evidence of
    /// a deletion and the queue must never be dropped on a guess. A server
    /// tombstone is applied locally on the way past, so the next pass is free.
    ///
    /// No connectivity guard: offline, the probe simply throws and this returns
    /// false — the same answer, with one fewer branch that no test can reach.
    /// Internal so the settle decision is provable through the probe seam.
    func projectIsSettledAsDeleted(_ project: Project) async -> Bool {
        if project.deletedAt != nil { return true }

        let state: SyncOperationReconcilers.ProjectServerState?
        do {
            state = try await projectServerStateProbe.projectServerState(projectId: project.id)
        } catch {
            DebugLogger.shared.log(
                "pre-drain project state probe failed for \(project.id): \(error)",
                level: .warning,
                category: "ImageSyncManager"
            )
            return false
        }
        guard state == .deleted else { return false }

        if let modelContext {
            try? SyncOperationReconcilers.applyProjectTombstone(
                projectId: project.id,
                deletedAt: Date(),
                in: modelContext
            )
            try? modelContext.save()
        }
        return true
    }

    /// Helper to get project by ID
    private func getProject(by id: String) -> Project? {
        guard let modelContext = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.id == id }
            )
            let projects = try modelContext.fetch(descriptor)
            return projects.first
        } catch {
            return nil
        }
    }
    
    /// Helper to load pending uploads from UserDefaults
    private func loadPendingUploads() {
        if let data = UserDefaults.standard.data(forKey: "pendingImageUploads"),
           let uploads = try? JSONDecoder().decode([PendingImageUpload].self, from: data) {
            pendingUploads = uploads
        }
    }
    
    /// Helper to save pending uploads to UserDefaults
    private func savePendingUploads() {
        if let data = try? JSONEncoder().encode(pendingUploads) {
            UserDefaults.standard.set(data, forKey: "pendingImageUploads")
        }
    }

    // MARK: - Portal-mirror queue persistence (bug 16d487c4)

    static let pendingPortalMirrorsKey = "pendingPortalMirrors"

    private func loadPendingPortalMirrors() {
        if let data = UserDefaults.standard.data(forKey: Self.pendingPortalMirrorsKey),
           let mirrors = try? JSONDecoder().decode([PendingPortalMirror].self, from: data) {
            pendingPortalMirrors = mirrors
        }
    }

    private func savePendingPortalMirrors() {
        if let data = try? JSONEncoder().encode(pendingPortalMirrors) {
            UserDefaults.standard.set(data, forKey: Self.pendingPortalMirrorsKey)
        }
    }

    /// Current portal-mirror queue. Internal so the drain and its tests can see
    /// what delivery is still owed.
    func getPendingPortalMirrors() -> [PendingPortalMirror] {
        pendingPortalMirrors
    }

    /// Records that delivery is still owed for these urls. Deduped by url — the
    /// same photo enqueued twice is still one debt.
    private func enqueuePortalMirrors(
        urls: [String],
        projectId: String,
        companyId: String,
        uploadedBy: String,
        source: String,
        takenAt: Date
    ) {
        var added = 0
        for url in urls where !pendingPortalMirrors.contains(where: { $0.url == url }) {
            pendingPortalMirrors.append(PendingPortalMirror(
                url: url,
                projectId: projectId,
                companyId: companyId,
                uploadedBy: uploadedBy,
                source: source,
                takenAt: takenAt
            ))
            added += 1
        }
        guard added > 0 else { return }
        savePendingPortalMirrors()
        startRetryTimerIfNeeded()
    }

    /// Settles delivery for these urls — delivered, already held server-side, or
    /// held for a reason no retry can change.
    private func removePortalMirrors(urls: [String]) {
        let settled = Set(urls)
        guard pendingPortalMirrors.contains(where: { settled.contains($0.url) }) else { return }
        pendingPortalMirrors.removeAll { settled.contains($0.url) }
        savePendingPortalMirrors()
    }

    /// Drops every queued mirror and upload for a project. Used when the server
    /// says the job is deleted: there is nothing left to deliver it to, and
    /// re-uploading its bytes every 30s would be pure waste.
    private func dropQueuedWork(forProject projectId: String) {
        let hadMirrors = pendingPortalMirrors.contains { $0.projectId == projectId }
        let hadUploads = pendingUploads.contains { $0.projectId == projectId }
        if hadMirrors {
            pendingPortalMirrors.removeAll { $0.projectId == projectId }
            savePendingPortalMirrors()
        }
        if hadUploads {
            pendingUploads.removeAll { $0.projectId == projectId }
            savePendingUploads()
        }
    }

    /// Re-offers every owed portal row, in the batches they were enqueued as.
    ///
    /// Batches are reconstructed by grouping on everything a single
    /// `deliverPortalMirror` call fixes for the whole batch — project, uploader,
    /// source, capture time — so a redelivered row is byte-identical to the one
    /// first attempted. `deliverPortalMirror` owns the queue transitions, so
    /// this method only has to decide WHAT to re-offer, never what to remove.
    ///
    /// No connectivity guard of its own — `syncPendingImages` gates the whole
    /// pass on connectivity before calling in, the same arrangement
    /// `reconcileStrandedProjectPhotos` uses. Internal so the redelivery is
    /// provable without a live network stack.
    func drainPendingPortalMirrors() async {
        guard !pendingPortalMirrors.isEmpty else { return }

        struct BatchKey: Hashable {
            let projectId: String
            let uploadedBy: String
            let source: String
            let takenAt: Date
        }

        var batches: [BatchKey: [PendingPortalMirror]] = [:]
        for mirror in pendingPortalMirrors {
            let key = BatchKey(
                projectId: mirror.projectId,
                uploadedBy: mirror.uploadedBy,
                source: mirror.source,
                takenAt: mirror.takenAt
            )
            batches[key, default: []].append(mirror)
        }

        for (key, mirrors) in batches {
            guard let project = getProject(by: key.projectId) else {
                // No local row to deliver against. Keep the debt: the project
                // may still arrive from an authoritative pull, and dropping it
                // here would be the silent write-off this queue exists to end.
                continue
            }
            _ = await deliverPortalMirror(
                urls: mirrors.map(\.url),
                project: project,
                uploadedBy: key.uploadedBy,
                source: key.source,
                takenAt: key.takenAt
            )
        }
    }
    
    /// Clean up UserDefaults from image data bloat
    private func cleanupUserDefaultsImageData() {
        
        let defaults = UserDefaults.standard
        var removedCount = 0
        var totalSizeSaved = 0
        
        // Get all keys
        let dictionaryRepresentation = defaults.dictionaryRepresentation()
        
        for (key, value) in dictionaryRepresentation {
            // Remove image URL keys (these contain base64 image data)
            if key.contains("https://") && (key.contains(".jpeg") || key.contains(".jpg") || key.contains(".png")) {
                if let data = value as? Data {
                    totalSizeSaved += data.count
                } else if let string = value as? String {
                    totalSizeSaved += string.count
                }
                defaults.removeObject(forKey: key)
                removedCount += 1
            }
        }
        
    }
    
    // MARK: - Public Methods for Progress Tracking
    
    /// Clear all pending image syncs
    func clearAllPendingUploads() {

        // Clear from memory
        let count = pendingUploads.count
        pendingUploads.removeAll()
        // Owed portal rows go with them: they are the same debt one step
        // further along, and leaving them would keep the 30s retry timer alive
        // for work the operator just asked to clear.
        pendingPortalMirrors.removeAll()

        // Clear from UserDefaults
        UserDefaults.standard.removeObject(forKey: "pendingImageUploads")
        UserDefaults.standard.removeObject(forKey: Self.pendingPortalMirrorsKey)
        stopRetryTimer()

        // Reset sync state
        isSyncing = false
        syncProgress = 0
        syncingProjectId = nil
        
    }
    
    /// Get current pending uploads
    func getPendingUploads() -> [PendingImageUpload] {
        return pendingUploads
    }
    
    /// Check if there are pending uploads
    var hasPendingUploads: Bool {
        return !pendingUploads.isEmpty
    }
    
    /// Get count of pending uploads
    var pendingUploadCount: Int {
        return pendingUploads.count
    }
    
    // MARK: - In-Flight Upload Tracking (Bug e5310f3d)

    /// Register a batch of UIImages as in-flight uploads for a project.
    /// Returns the placeholders (id + UIImage) so the caller can clear
    /// them when the upload settles. Always called on the main actor.
    private func beginInFlightUploads(_ images: [UIImage], for project: Project) -> [InFlightUpload] {
        let projectId = project.id
        let placeholders = images.map { InFlightUpload(id: UUID().uuidString, image: $0) }
        var current = inFlightUploads[projectId] ?? []
        current.append(contentsOf: placeholders)
        inFlightUploads[projectId] = current
        return placeholders
    }

    /// Remove placeholders for a finished upload batch. The carousel will
    /// re-render with only the resolved S3 URLs left in the project's
    /// project_images list.
    private func endInFlightUploads(_ ids: [String], for projectId: String) {
        guard var current = inFlightUploads[projectId] else { return }
        let idSet = Set(ids)
        current.removeAll { idSet.contains($0.id) }
        if current.isEmpty {
            inFlightUploads.removeValue(forKey: projectId)
        } else {
            inFlightUploads[projectId] = current
        }
    }

    /// Auto-bug-reporting (May-12 follow-up): flip the failed flag for a
    /// set of in-flight tiles so the carousel can render them with a red
    /// badge + tap-to-retry instead of silently disappearing. Called from
    /// catch sites that hit a permanent rejection (RLS, 4xx, validation).
    func markInFlightUploadsFailed(
        ids: [String],
        for projectId: String,
        lastError: String?
    ) {
        guard var current = inFlightUploads[projectId] else { return }
        let idSet = Set(ids)
        for index in current.indices where idSet.contains(current[index].id) {
            current[index].failed = true
            current[index].lastError = lastError
        }
        inFlightUploads[projectId] = current
    }

    /// Drop a single failed tile from the carousel — used when the user
    /// taps "dismiss" on a permanent-failure tile after acknowledging it.
    /// (Tap-to-retry uses retryFailedInFlightUpload instead.)
    func dismissFailedInFlightUpload(id: String, for projectId: String) {
        endInFlightUploads([id], for: projectId)
    }

    /// Public accessor — used by the carousel to render upload spinners.
    func currentInFlightUploads(for projectId: String) -> [InFlightUpload] {
        return inFlightUploads[projectId] ?? []
    }

    /// Re-attempt a failed in-flight upload by running a fresh upload
    /// through `saveImages`. The old failed tile is removed BEFORE
    /// `saveImages` runs so the carousel transitions cleanly:
    /// `[failed tile]` → (briefly nothing) → `[new spinning tile]` →
    /// `[resolved photo OR new failed tile]`. Removing the old tile after
    /// `saveImages` returns would leave the user looking at TWO tiles
    /// for the duration of the upload (the old failed one and the new
    /// spinning one) — confusing.
    func retryFailedInFlightUpload(id: String, for projectId: String) async {
        guard let current = inFlightUploads[projectId],
              let upload = current.first(where: { $0.id == id }),
              upload.failed else { return }

        let image = upload.image

        // Drop the failed tile first so the carousel doesn't briefly
        // render two tiles for the same retry.
        endInFlightUploads([id], for: projectId)

        guard let project = getProject(by: projectId) else { return }
        _ = await saveImages([image], for: project)
    }

    // MARK: - Image Processing Helpers
    
    /// Resize image if it exceeds maximum dimensions
    private func resizeImageIfNeeded(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 2048 // Maximum width or height
        
        guard image.size.width > maxDimension || image.size.height > maxDimension else {
            return image
        }
        
        let aspectRatio = image.size.width / image.size.height
        let newSize: CGSize
        
        if image.size.width > image.size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
    
    /// Get adaptive compression quality based on image size
    private func getAdaptiveCompressionQuality(for image: UIImage) -> CGFloat {
        let pixelCount = image.size.width * image.size.height
        
        // Higher resolution images get more compression
        if pixelCount > 4_000_000 { // > 4MP
            return 0.5
        } else if pixelCount > 2_000_000 { // > 2MP
            return 0.6
        } else if pixelCount > 1_000_000 { // > 1MP
            return 0.7
        } else {
            return 0.8
        }
    }
}

/// Bug e5310f3d — represents a single image actively being uploaded
/// to S3 and Supabase. The carousel renders one placeholder per item
/// in this list while the upload finishes; the placeholder dissolves
/// into the real photo once `inFlightUploads` no longer contains it.
///
/// Auto-bug-reporting (May-12 follow-up): when an upload hits a permanent
/// server rejection (RLS denied, validation, 4xx), `failed = true` and
/// `lastError` carries the human-readable cause. The carousel renders
/// the tile with a red corner badge and tap-to-retry instead of removing
/// it, so the user sees that the photo did NOT make it to the project.
public struct InFlightUpload: Identifiable {
    public let id: String
    public let image: UIImage
    public var failed: Bool
    public var lastError: String?

    public init(id: String, image: UIImage, failed: Bool = false, lastError: String? = nil) {
        self.id = id
        self.image = image
        self.failed = failed
        self.lastError = lastError
    }
}

/// Model for a pending image upload
public struct PendingImageUpload: Codable {
    let localURL: String
    let projectId: String
    let companyId: String
    let timestamp: Date
    
    // Store reference to original image for offline sync
    var originalImage: UIImage? {
        if let imageData = ImageFileManager.shared.getImageData(localID: localURL) {
            return UIImage(data: imageData)
        }
        return nil
    }
    
    // Custom encoding to avoid storing UIImage
    enum CodingKeys: String, CodingKey {
        case localURL, projectId, companyId, timestamp
    }
}
