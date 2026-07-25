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

    var id: String { displayID ?? localURL }

    init(
        localURL: String,
        opportunityId: String,
        companyId: String,
        timestamp: Date,
        displayID: String? = nil,
        batchIndex: Int? = nil
    ) {
        self.localURL = localURL
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.timestamp = timestamp
        self.displayID = displayID
        self.batchIndex = batchIndex
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
        let result = stageImages(
            images,
            opportunityId: opportunity.id,
            companyId: opportunity.companyId,
            reservationIDs: reservationIDs
        )
        if result.queuedCount > 0, backgroundWorkEnabled {
            Task { await drain() }
        }
        return result
    }

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
            pendingUploads.removeAll { $0.localURL == url }
            savePendingUploads()
            _ = ImageFileManager.shared.deleteImage(localID: url)
            return true
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
              let data = ImageFileManager.shared.getImageData(localID: pending.localURL) else {
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

        var stillPending: [PendingLeadImageUpload] = []
        var mergedByOpportunity: [String: (companyId: String, urls: [String])] = [:]

        for pending in snapshot {
            if pending.localURL.hasPrefix("local://") {
                guard let data = ImageFileManager.shared.getImageData(localID: pending.localURL) else {
                    // Bytes are gone (storage cleanup) — nothing recoverable.
                    continue
                }
                do {
                    let url = try await uploader.uploadImageData(
                        data,
                        filename: (pending.localURL as NSString).lastPathComponent,
                        folder: LeadImageStoragePath.folder(
                            companyId: pending.companyId,
                            opportunityId: pending.opportunityId
                        )
                    )
                    _ = ImageFileManager.shared.deleteImage(localID: pending.localURL)
                    mergedByOpportunity[pending.opportunityId, default: (pending.companyId, [])].urls.append(url)
                } catch {
                    stillPending.append(pending)
                }
            } else {
                mergedByOpportunity[pending.opportunityId, default: (pending.companyId, [])].urls.append(pending.localURL)
            }
        }

        for (opportunityId, entry) in mergedByOpportunity {
            do {
                let repo = OpportunityRepository(companyId: entry.companyId)
                let dto = try await repo.appendImages(entry.urls, to: opportunityId)
                applyEcho(dto, to: nil, opportunityId: opportunityId)
            } catch {
                // Row merge still failing — keep the URLs queued (as merge-only
                // records; any local bytes were already uploaded + cleared).
                for url in entry.urls {
                    stillPending.append(PendingLeadImageUpload(
                        localURL: url,
                        opportunityId: opportunityId,
                        companyId: entry.companyId,
                        timestamp: Date()
                    ))
                }
            }
        }

        let appendedDuringDrain = pendingUploads.contains { current in
            !snapshot.contains { $0.localURL == current.localURL }
        }
        pendingUploads = LeadImagePendingQueue.reconciling(
            current: pendingUploads,
            drainedSnapshot: snapshot,
            stillPendingFromSnapshot: stillPending
        )
        savePendingUploads()
        isDraining = false
        let shouldDrainAgain = drainRequested || appendedDuringDrain
        drainRequested = false
        if pendingUploads.isEmpty {
            stopRetryTimer()
        } else if shouldDrainAgain, backgroundWorkEnabled {
            Task { await drain() }
        }
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
