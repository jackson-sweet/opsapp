import Foundation
import Combine
import UIKit

struct CameraCapturePreview: Identifiable {
    let id: String
    let batchID: String
    var item: StagedCaptureItem?
    var thumbnail: UIImage?
    var retryData: Data?
    var failed: Bool
}

@MainActor
final class CameraCaptureSession: ObservableObject {
    @Published private(set) var photos: [CameraCapturePreview] = []
    @Published private(set) var isWorking = true
    @Published var errorMessage: String?
    private let owner: StagedCaptureOwner
    private let store: DurableCaptureStore
    private var batch: StagedCaptureBatch?
    private var initialized = false
    var canCapture: Bool { initialized && !isWorking && !hasFailures }
    var hasFailures: Bool { photos.contains { $0.failed } }

    init(owner: StagedCaptureOwner, store: DurableCaptureStore = .shared) {
        self.owner = owner; self.store = store
    }

    func prepare() async {
        guard !initialized else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let recovered = try await store.recover(owner: owner)
            photos.removeAll()
            for batch in recovered {
                for item in batch.items {
                    let thumbnail = await store.thumbnail(for: item)
                    photos.append(CameraCapturePreview(id: item.id, batchID: batch.id, item: item, thumbnail: thumbnail, failed: false))
                }
            }
            for batch in try await store.failedItems(owner: owner) {
                for item in batch.items {
                    let data = await store.originalData(for: item)
                    photos.append(CameraCapturePreview(id: item.id, batchID: batch.id, retryData: data, failed: true))
                }
            }
            batch = try await store.create(owner: owner)
            initialized = true
            if hasFailures { errorMessage = "Some photos need another save attempt. Retry or remove them in review." }
        } catch { errorMessage = "Photo storage could not open. Retry before taking photos." }
    }

    func capture(_ data: Data) async -> Bool {
        guard let batch, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        let id = UUID().uuidString.lowercased()
        photos.append(CameraCapturePreview(id: id, batchID: batch.id, retryData: data, failed: false))
        return await stage(id: id, data: data, batchID: batch.id)
    }

    func retry() async {
        guard !isWorking else { return }
        if !initialized { await prepare(); return }
        isWorking = true
        defer { isWorking = false }
        for photo in photos where photo.failed {
            if let data = photo.retryData { _ = await stage(id: photo.id, data: data, batchID: photo.batchID) }
        }
    }

    private func stage(id: String, data: Data, batchID: String) async -> Bool {
        do {
            let item = try await store.stage(data: data, batchID: batchID, itemID: id)
            let thumbnail = await store.thumbnail(for: item)
            guard let index = photos.firstIndex(where: { $0.id == id }) else { return false }
            photos[index].item = item
            photos[index].thumbnail = thumbnail
            photos[index].retryData = nil
            photos[index].failed = false
            return true
        } catch {
            if let index = photos.firstIndex(where: { $0.id == id }) { photos[index].failed = true }
            errorMessage = "Photo could not be saved. Keep this camera open and retry."
            return false
        }
    }

    func remove(_ ids: Set<String>) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let selected = photos.filter { ids.contains($0.id) }
            for (batchID, group) in Dictionary(grouping: selected, by: \.batchID) {
                try await store.discard(batchID: batchID, itemIDs: Set(group.map(\.id)))
                photos.removeAll { $0.batchID == batchID && ids.contains($0.id) }
            }
            return true
        } catch {
            errorMessage = "Photos could not be removed. Retry."
            return false
        }
    }

    /// Partial host success removes only acknowledged items. A failed save or
    /// ack keeps stable IDs visible and retryable; the host must dedupe by ID.
    func commit(onStaged: ((StagedCaptureBatch) async -> Bool)?, onLegacy: (([UIImage]) -> Void)?) async -> Bool {
        guard !isWorking, !photos.isEmpty, !hasFailures else { return false }
        isWorking = true
        defer { isWorking = false }
        let groups = Dictionary(grouping: photos, by: \.batchID).sorted { $0.key < $1.key }
        for (batchID, group) in groups {
            let staged = StagedCaptureBatch(id: batchID, owner: owner, items: group.compactMap(\.item))
            do {
                if let onStaged {
                    guard await onStaged(staged) else {
                        errorMessage = "Photos are saved on this device. Retry adding them to the visit."
                        return false
                    }
                    try await store.acknowledge(batchID: batchID, itemIDs: Set(staged.items.map(\.id)))
                } else if let onLegacy {
                    let images = try await store.legacyImages(for: staged)
                    onLegacy(images)
                    // Legacy void callbacks cannot prove a durable host save.
                    // Keep journal custody until those callers adopt typed receipts.
                }
                photos.removeAll { $0.batchID == batchID }
            } catch {
                errorMessage = "Photos are saved on this device. Retry finishing this batch."
                return false
            }
        }
        return true
    }
}
