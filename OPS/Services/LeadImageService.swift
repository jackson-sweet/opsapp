//
//  LeadImageService.swift
//  OPS
//
//  Photos on a LEAD. Uploads ride the standard presign flow into the public
//  project-media namespace at `projects/{companyId}/leads/{opportunityId}/…`
//  and land as full S3 URLs in `opportunities.images`. The PATCH is a
//  fetch→merge→update against the SERVER row (never the possibly-stale local
//  array), so two devices adding photos near-simultaneously lose nothing.
//
//  Offline / failed uploads follow the ImageSyncManager doctrine in
//  miniature: bytes persist via ImageFileManager under a `local://` id, a
//  pending record survives relaunch in UserDefaults, and the queue drains on
//  connectivity change, on a retry timer, and whenever a lead's photo section
//  appears. The drain is idempotent and failure-safe — attempting it while
//  offline just fails fast (the upload session never waits for connectivity)
//  and items stay queued.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

enum LeadImageStoragePath {
    static func folder(companyId: String, opportunityId: String) -> String {
        "projects/\(companyId)/leads/\(opportunityId)"
    }
}

/// One queued lead photo. Persisted in UserDefaults (bytes live on disk via
/// ImageFileManager) so the queue survives relaunch.
struct PendingLeadImageUpload: Codable, Equatable, Identifiable {
    let localURL: String          // "local://lead_<opp>_<epoch>_<i>.jpg"
    let opportunityId: String
    let companyId: String
    let timestamp: Date
    /// Matches the picker reservation so SwiftUI replaces the placeholder
    /// without moving the tile. Nil for queues written by older app versions.
    let displayID: String?
    /// Preserves selection order for photos staged in the same batch.
    let batchIndex: Int?
    let journalID: String?
    let originalLocalURL: String?
    let userID: String?
    var uploadedURL: String?

    var id: String { displayID ?? localURL }

    init(
        localURL: String,
        opportunityId: String,
        companyId: String,
        timestamp: Date,
        displayID: String? = nil,
        batchIndex: Int? = nil,
        journalID: String? = nil,
        originalLocalURL: String? = nil,
        userID: String? = nil,
        uploadedURL: String? = nil
    ) {
        self.localURL = localURL
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.timestamp = timestamp
        self.displayID = displayID
        self.batchIndex = batchIndex
        self.journalID = journalID
        self.originalLocalURL = originalLocalURL
        self.userID = userID
        self.uploadedURL = uploadedURL
    }
}

enum LeadImagePendingQueue {
    /// Replaces only the snapshot a drain owned. Entries appended while the
    /// drain was suspended on network work remain in the queue.
    static func reconciling(
        current: [PendingLeadImageUpload],
        drainedSnapshot: [PendingLeadImageUpload],
        stillPendingFromSnapshot: [PendingLeadImageUpload]
    ) -> [PendingLeadImageUpload] {
        let snapshotURLs = Set(drainedSnapshot.map(\.localURL))
        let appendedDuringDrain = current.filter { !snapshotURLs.contains($0.localURL) }
        return stillPendingFromSnapshot + appendedDuringDrain
    }
}

@MainActor
final class LeadImageService: ObservableObject {
    static let shared = LeadImageService()

    /// Queued (not-yet-uploaded) photos. Published so the lead photo strip
    /// re-renders QUEUED tiles as the drain lands them.
    @Published private(set) var pendingUploads: [PendingLeadImageUpload] = []

    /// Set by the lead detail surface so a successful drain can heal the
    /// local SwiftData Opportunity row. Optional on purpose: with no context
    /// the server PATCH still lands and the next lead reload catches up.
    weak private(set) var modelContext: ModelContext?

    private let defaultsKey = "pendingLeadImageUploads"
    private let defaults: UserDefaults
    private let backgroundWorkEnabled: Bool
    private var isDraining = false
    private var drainRequested = false
    private var retryTimer: Timer?
    private let uploader = PresignedURLUploadService.shared

    init(
        defaults: UserDefaults = .standard,
        backgroundWorkEnabled: Bool = true
    ) {
        self.defaults = defaults
        self.backgroundWorkEnabled = backgroundWorkEnabled
        loadPendingUploads()
        if backgroundWorkEnabled {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(connectivityChanged),
                name: ConnectivityManager.connectivityChangedNotification,
                object: nil
            )
        }
        if backgroundWorkEnabled {
            Task { await restoreStagedImages() }
        }
        if backgroundWorkEnabled && !pendingUploads.isEmpty {
            startRetryTimerIfNeeded()
            Task {
                // Small delay so app startup settles before the first drain.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await drain()
            }
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Add

    struct AddResult {
        var uploadedURLs: [String] = []
        var queuedCount = 0
        var failedCount = 0
    }

    /// Persist and publish the whole batch before starting network work.
    /// The caller can therefore replace picker reservations with real local
    /// thumbnails while upload/reconciliation continues in the background.
    @discardableResult
    func addImages(
        _ images: [UIImage],
        to opportunity: Opportunity,
        reservationIDs: [String] = []
    ) async -> AddResult {
        // Snapshot model identity before suspending; only immutable metadata and
        // UIImage sources enter the serial background stager.
        let opportunityID = opportunity.id
        let companyID = opportunity.companyId
        let userID = defaults.string(forKey: "currentUserId")?.lowercased()
        let timestamp = Date()
        var result = AddResult()
        for (index, image) in images.enumerated() {
            let id = UUID().uuidString.lowercased()
            let displayID = reservationIDs.indices.contains(index) ? reservationIDs[index] : id
            let pending = PendingLeadImageUpload(
                localURL: "local://project_images/lead_\(id).jpg",
                opportunityId: opportunityID, companyId: companyID, timestamp: timestamp,
                displayID: displayID, batchIndex: index, journalID: id,
                originalLocalURL: "local://project_images/lead_\(id).original", userID: userID
            )
            do {
                let staged = try await LeadImageStager.shared.stage(image, pending: pending)
                if !pendingUploads.contains(where: { $0.localURL == staged.localURL }) { pendingUploads.append(staged) }
                savePendingUploads()
                result.queuedCount += 1
            } catch {
                if await LeadImageStager.shared.hasOriginal(pending) {
                    pendingUploads.append(pending)
                    savePendingUploads()
                    result.queuedCount += 1
                } else { result.failedCount += 1 }
            }
        }
        if result.queuedCount > 0, backgroundWorkEnabled {
            startRetryTimerIfNeeded()
            Task { await drain() }
        }
        return result
    }

    /// Compatibility-only synchronous entry point. Production import uses
    /// addImages, which awaits the background, per-item durable stager.
    @available(*, deprecated, message: "Use addImages for background durable staging")
    @discardableResult
    func stageImages(
        _ images: [UIImage],
        opportunityId: String,
        companyId: String,
        reservationIDs: [String] = []
    ) -> AddResult {
        var result = AddResult()
        let batchTimestamp = Date()

        for (index, image) in images.enumerated() {
            guard let data = preparedJPEGData(for: image) else {
                result.failedCount += 1
                continue
            }

            let displayID = reservationIDs.indices.contains(index)
                ? reservationIDs[index]
                : UUID().uuidString
            let localID = "local://project_images/lead_\(opportunityId)_\(displayID).jpg"
            if ImageFileManager.shared.saveImage(data: data, localID: localID) {
                pendingUploads.append(PendingLeadImageUpload(
                    localURL: localID,
                    opportunityId: opportunityId,
                    companyId: companyId,
                    timestamp: batchTimestamp,
                    displayID: displayID,
                    batchIndex: index
                ))
                result.queuedCount += 1
            } else {
                result.failedCount += 1
            }
        }

        if result.queuedCount > 0 {
            savePendingUploads()
            if backgroundWorkEnabled {
                startRetryTimerIfNeeded()
            }
        }
        return result
    }

    // MARK: - Delete

    /// Remove a photo. Remote URLs: PATCH the array (fetch→filter→update) and
    /// best-effort delete the S3 object. Queued local ids: drop the pending
    /// record + bytes.
    func deleteImage(_ url: String, from opportunity: Opportunity) async -> Bool {
        if url.hasPrefix("local://") {
            let selected = pendingUploads.filter { $0.localURL == url }
            do {
                for pending in selected { try await LeadImageStager.shared.finish(pending) }
                pendingUploads.removeAll { $0.localURL == url }
                savePendingUploads()
                return true
            } catch { return false }
        }

        do {
            let repo = OpportunityRepository(companyId: opportunity.companyId)
            let dto = try await repo.removeImage(url, from: opportunity.id)
            applyEcho(dto, to: opportunity, opportunityId: opportunity.id)
            // Orphan cleanup only — the row array is the source of truth.
            Task.detached { try? await PresignedURLUploadService.shared.deleteImage(url: url) }
            return true
        } catch {
            print("[LEAD_IMAGES] delete failed for \(url): \(error)")
            return false
        }
    }

    // MARK: - Queue

    func queuedUploads(for opportunityId: String) -> [PendingLeadImageUpload] {
        pendingUploads.filter { $0.opportunityId == opportunityId }
    }

    func queuedImage(for pending: PendingLeadImageUpload) -> UIImage? {
        guard pending.localURL.hasPrefix("local://"),
              let data = ImageFileManager.shared.getImageData(localID: pending.localURL)
                ?? pending.originalLocalURL.flatMap({ ImageFileManager.shared.getImageData(localID: $0) }) else {
            return nil
        }
        return UIImage(data: data)
    }

    /// Drain the pending queue. Two entry kinds:
    ///   - `local://…`  — bytes on disk; upload, then merge the URL.
    ///   - `https://…`  — already on S3 (row PATCH failed earlier); merge only.
    func drain() async {
        guard !pendingUploads.isEmpty else { return }
        guard !isDraining else {
            drainRequested = true
            return
        }
        isDraining = true
        let snapshot = pendingUploads

        for pending in snapshot {
            guard !Task.isCancelled, pendingUploads.contains(where: { $0.localURL == pending.localURL }) else { continue }
            do {
                guard try await LeadImageStager.shared.isActive(pending) else {
                    pendingUploads.removeAll { $0.localURL == pending.localURL }
                    savePendingUploads()
                    continue
                }
                guard canDeliver(pending) else { continue }
                var current = try await LeadImageStager.shared.current(pending)
                let remoteURL: String
                if let uploaded = current.uploadedURL {
                    remoteURL = uploaded
                } else if pending.localURL.hasPrefix("local://") {
                    guard let data = try await LeadImageStager.shared.uploadData(pending) else { continue }
                    remoteURL = try await uploader.uploadImageData(
                        data, filename: (pending.localURL as NSString).lastPathComponent,
                        folder: LeadImageStoragePath.folder(companyId: pending.companyId, opportunityId: pending.opportunityId)
                    )
                    guard pendingUploads.contains(where: { $0.localURL == pending.localURL }) else { continue }
                    current = try await LeadImageStager.shared.recordRemote(pending, url: remoteURL)
                    if let index = pendingUploads.firstIndex(where: { $0.localURL == pending.localURL }) {
                        pendingUploads[index] = current
                        savePendingUploads()
                    }
                } else { remoteURL = pending.localURL }
                guard !Task.isCancelled, canDeliver(current), pendingUploads.contains(where: { $0.localURL == pending.localURL }) else { continue }
                let repo = OpportunityRepository(companyId: current.companyId)
                let dto = try await repo.appendImages([remoteURL], to: current.opportunityId)
                applyEcho(dto, to: nil, opportunityId: current.opportunityId)
                // Retain original + upload JPEG until both S3 and the lead row
                // confirm custody. A failed merge retries the recorded remote URL.
                try await LeadImageStager.shared.finish(current)
                pendingUploads.removeAll { $0.localURL == pending.localURL }
                savePendingUploads()
            } catch { continue }
        }
        isDraining = false
        let appendedDuringDrain = pendingUploads.contains { current in !snapshot.contains { $0.localURL == current.localURL } }
        let shouldDrainAgain = drainRequested || appendedDuringDrain
        drainRequested = false
        if pendingUploads.isEmpty { stopRetryTimer() }
        else if shouldDrainAgain, backgroundWorkEnabled { Task { await drain() } }
    }

    private func canDeliver(_ item: PendingLeadImageUpload) -> Bool {
        guard defaults.string(forKey: "currentUserCompanyId")?.lowercased() == item.companyId.lowercased() else { return false }
        if let expectedUser = item.userID { return defaults.string(forKey: "currentUserId")?.lowercased() == expectedUser }
        return true // Legacy records did not persist user identity.
    }

    private func restoreStagedImages() async {
        guard let company = defaults.string(forKey: "currentUserCompanyId"),
              let user = defaults.string(forKey: "currentUserId") else { return }
        do {
            let recovered = try await LeadImageStager.shared.recover(companyID: company, userID: user)
            guard defaults.string(forKey: "currentUserCompanyId") == company,
                  defaults.string(forKey: "currentUserId") == user else { return }
            for item in recovered {
                if let index = pendingUploads.firstIndex(where: { $0.localURL == item.localURL }) { pendingUploads[index] = item }
                else { pendingUploads.append(item) }
            }
            savePendingUploads()
            if !pendingUploads.isEmpty { startRetryTimerIfNeeded(); await drain() }
        } catch { print("[LEAD_IMAGES] Staged photo recovery remains pending: \(error)") }
    }

    // MARK: - Local model healing

    private func applyEcho(_ dto: OpportunityDTO, to model: Opportunity?, opportunityId: String) {
        if let model {
            model.images = dto.images ?? []
            return
        }
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Opportunity>(
            predicate: #Predicate<Opportunity> { $0.id == opportunityId }
        )
        if let local = (try? context.fetch(descriptor))?.first {
            local.images = dto.images ?? []
            try? context.save()
        }
    }

    // MARK: - Connectivity + retry

    @objc private func connectivityChanged() {
        Task { await drain() }
    }

    private func startRetryTimerIfNeeded() {
        guard retryTimer == nil, !pendingUploads.isEmpty else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.drain()
            }
        }
    }

    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    // MARK: - Persistence

    private func loadPendingUploads() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([PendingLeadImageUpload].self, from: data) else {
            return
        }
        pendingUploads = decoded
    }

    private func savePendingUploads() {
        guard let data = try? JSONEncoder().encode(pendingUploads) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    // MARK: - Snapshot seeding (DEBUG)

    #if DEBUG
    /// Harness-only: swap the in-memory queue so snapshot tests can render
    /// deterministic QUEUED tiles. Does NOT touch the persisted store.
    func _setQueueForSnapshots(_ uploads: [PendingLeadImageUpload]) {
        pendingUploads = uploads
    }
    #endif

    // MARK: - Image prep

    /// Max 2048 on the long edge + adaptive JPEG quality — same envelope the
    /// presign uploader applies to project photos (those helpers are private
    /// to PresignedURLUploadService; the sizes are the shared contract).
    private func preparedJPEGData(for image: UIImage) -> Data? {
        let resized = resizeIfNeeded(image, maxDimension: 2048)
        return resized.jpegData(compressionQuality: adaptiveQuality(for: resized))
    }

    private func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        guard image.size.width > maxDimension || image.size.height > maxDimension else {
            return image
        }
        let aspect = image.size.width / image.size.height
        let newSize = image.size.width > image.size.height
            ? CGSize(width: maxDimension, height: maxDimension / aspect)
            : CGSize(width: maxDimension * aspect, height: maxDimension)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return resized
    }

    private func adaptiveQuality(for image: UIImage) -> CGFloat {
        let pixels = image.size.width * image.size.height
        if pixels > 4_000_000 { return 0.5 }
        if pixels > 2_000_000 { return 0.6 }
        if pixels > 1_000_000 { return 0.7 }
        return 0.8
    }
}
