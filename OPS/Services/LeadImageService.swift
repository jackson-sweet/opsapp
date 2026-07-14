//
//  LeadImageService.swift
//  OPS
//
//  Photos on a LEAD. Uploads ride the standard presign flow into
//  `opportunities/{companyId}/{opportunityId}/…` and land as full public S3
//  URLs in `opportunities.images` — the exact shape the web email-extract
//  pipeline writes, so both producers stay interchangeable. The PATCH is a
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

/// One queued lead photo. Persisted in UserDefaults (bytes live on disk via
/// ImageFileManager) so the queue survives relaunch.
struct PendingLeadImageUpload: Codable, Equatable, Identifiable {
    let localURL: String          // "local://lead_<opp>_<epoch>_<i>.jpg"
    let opportunityId: String
    let companyId: String
    let timestamp: Date

    var id: String { localURL }
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
    private var isDraining = false
    private var retryTimer: Timer?
    private let uploader = PresignedURLUploadService.shared

    private init() {
        loadPendingUploads()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectivityChanged),
            name: ConnectivityManager.connectivityChangedNotification,
            object: nil
        )
        if !pendingUploads.isEmpty {
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

    /// Upload a batch for one lead. Sequential per photo (leads carry a
    /// handful, not a jobsite dump) with per-photo failure isolation: what
    /// lands is recorded immediately, what doesn't is queued durably.
    @discardableResult
    func addImages(_ images: [UIImage], to opportunity: Opportunity) async -> AddResult {
        let companyId = opportunity.companyId
        let opportunityId = opportunity.id
        var result = AddResult()

        for (index, image) in images.enumerated() {
            guard let data = preparedJPEGData(for: image) else {
                result.failedCount += 1
                continue
            }

            let epoch = Date().timeIntervalSince1970
            let filename = "lead_\(epoch)_\(index).jpg"
            do {
                let url = try await uploader.uploadImageData(
                    data,
                    filename: filename,
                    folder: "opportunities/\(companyId)/\(opportunityId)"
                )
                result.uploadedURLs.append(url)
            } catch {
                // Persist bytes + queue the retry. localID doubles as the
                // stable tile identity in the strip. The `project_images`
                // namespace is ImageFileManager's ONLY recognized local://
                // prefix (getFileURL nils anything else — proven by the
                // snapshot harness); the lead_ filename keeps the store
                // debuggable and timestamp-parseable.
                let localID = "local://project_images/lead_\(opportunityId)_\(epoch)_\(index).jpg"
                if ImageFileManager.shared.saveImage(data: data, localID: localID) {
                    pendingUploads.append(PendingLeadImageUpload(
                        localURL: localID,
                        opportunityId: opportunityId,
                        companyId: companyId,
                        timestamp: Date()
                    ))
                    result.queuedCount += 1
                } else {
                    result.failedCount += 1
                }
            }
        }

        if !result.uploadedURLs.isEmpty {
            await recordUploaded(result.uploadedURLs, opportunityId: opportunityId, companyId: companyId, localModel: opportunity)
        }
        if result.queuedCount > 0 {
            savePendingUploads()
            startRetryTimerIfNeeded()
        }
        return result
    }

    /// PATCH the uploaded URLs onto the server row and mirror the echo onto
    /// the local model. Server-merge failure re-queues NOTHING — the bytes are
    /// already on S3 — instead the URLs queue as a lightweight "record" retry
    /// through the same pending store using a synthetic local id that resolves
    /// straight to the remote URL on drain.
    private func recordUploaded(
        _ urls: [String],
        opportunityId: String,
        companyId: String,
        localModel: Opportunity?
    ) async {
        do {
            let repo = OpportunityRepository(companyId: companyId)
            let dto = try await repo.appendImages(urls, to: opportunityId)
            applyEcho(dto, to: localModel, opportunityId: opportunityId)
        } catch {
            // S3 succeeded, the row PATCH didn't (e.g. connection dropped
            // between the two). Queue the URL itself for a drain-side merge.
            for url in urls {
                pendingUploads.append(PendingLeadImageUpload(
                    localURL: url,
                    opportunityId: opportunityId,
                    companyId: companyId,
                    timestamp: Date()
                ))
            }
            savePendingUploads()
            startRetryTimerIfNeeded()
        }
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
        guard !isDraining, !pendingUploads.isEmpty else { return }
        isDraining = true
        defer { isDraining = false }

        var stillPending: [PendingLeadImageUpload] = []
        var mergedByOpportunity: [String: (companyId: String, urls: [String])] = [:]

        for pending in pendingUploads {
            if pending.localURL.hasPrefix("local://") {
                guard let data = ImageFileManager.shared.getImageData(localID: pending.localURL) else {
                    // Bytes are gone (storage cleanup) — nothing recoverable.
                    continue
                }
                do {
                    let url = try await uploader.uploadImageData(
                        data,
                        filename: (pending.localURL as NSString).lastPathComponent,
                        folder: "opportunities/\(pending.companyId)/\(pending.opportunityId)"
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

        pendingUploads = stillPending
        savePendingUploads()
        if pendingUploads.isEmpty {
            stopRetryTimer()
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
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([PendingLeadImageUpload].self, from: data) else {
            return
        }
        pendingUploads = decoded
    }

    private func savePendingUploads() {
        guard let data = try? JSONEncoder().encode(pendingUploads) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
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
