import Foundation
import ImageIO
import UIKit

struct StagedCaptureOwner: Codable, Hashable, Sendable {
    let companyID: String
    let userID: String
    let contextID: String
    init(companyID: String, userID: String, contextID: String) {
        self.companyID = companyID.lowercased()
        self.userID = userID.lowercased()
        self.contextID = contextID.lowercased()
    }
}

struct StagedCaptureItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let localURL: String
    let originalLocalURL: String
    let capturedAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
}

struct StagedCaptureBatch: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let owner: StagedCaptureOwner
    var items: [StagedCaptureItem]
}

struct CaptureAccountIdentity: Equatable, Sendable {
    let companyID: String
    let userID: String
    init(companyID: String, userID: String) { self.companyID = companyID.lowercased(); self.userID = userID.lowercased() }
    static func current(defaults: UserDefaults = .standard) -> CaptureAccountIdentity? {
        guard let company = defaults.string(forKey: "currentUserCompanyId"), !company.isEmpty,
              let user = defaults.string(forKey: "currentUserId"), !user.isEmpty else { return nil }
        return .init(companyID: company, userID: user)
    }
    func owns(_ owner: StagedCaptureOwner) -> Bool { companyID == owner.companyID && userID == owner.userID }
}

struct RetainedCaptureRecovery: Sendable {
    let batch: StagedCaptureBatch
    let failedItems: [StagedCaptureItem]
}

enum CaptureStagingError: LocalizedError {
    case invalidImage, invalidIdentity, incompatibleManifest, missingOriginal, writeFailed, closedDraft
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Some photos need another save attempt. Retry or remove them before finishing."
        case .invalidIdentity: return "Photo destination changed. Reopen it and try again."
        case .incompatibleManifest: return "Saved photos need a newer version of OPS. Their files remain on this device."
        case .missingOriginal: return "A saved photo could not be read. Retry before continuing."
        case .writeFailed: return "Photos could not be saved. Keep this screen open and retry."
        case .closedDraft: return "This photo draft has already been completed."
        }
    }
}

/// A versioned file journal, separate from SwiftData schema history. Every intent
/// is journaled BEFORE its original is atomically written. Recovery repairs a
/// missing JPEG from that untouched original. Nothing is pruned by age/cache policy.
actor DurableCaptureStore {
    static let shared = DurableCaptureStore()
    private struct Manifest: Codable {
        // Any change to custody semantics or required fields MUST bump version.
        // Unknown higher versions remain untouched; v1 extensions are optional.
        var version = 1
        var batch: StagedCaptureBatch
        var acknowledged: Set<String> = []
        var discarded: Set<String> = []
        var delivered: Set<String>? = nil
    }
    typealias Writer = @Sendable (Data, URL) throws -> Void
    private let root: URL
    private let images: URL
    private let writer: Writer
    private let ledger: PhotoCacheLedger?
    private let currentAccount: (@Sendable () -> CaptureAccountIdentity?)?

    init(root: URL? = nil, images: URL? = nil, currentAccount: (@Sendable () -> CaptureAccountIdentity?)? = nil,
        writer: @escaping Writer = { try $0.write(to: $1, options: .atomic) }) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? docs.appendingPathComponent("CaptureBatches", isDirectory: true)
        self.images = images ?? docs.appendingPathComponent("ProjectImages", isDirectory: true)
        self.writer = writer
        self.ledger = images == nil ? .shared : nil
        if let currentAccount { self.currentAccount = currentAccount }
        else if root == nil { self.currentAccount = { CaptureAccountIdentity.current() } }
        else { self.currentAccount = nil }
    }

    func create(owner: StagedCaptureOwner) throws -> StagedCaptureBatch {
        guard !owner.companyID.isEmpty, !owner.userID.isEmpty, !owner.contextID.isEmpty else { throw CaptureStagingError.invalidIdentity }
        let batch = StagedCaptureBatch(id: UUID().uuidString.lowercased(), owner: owner, items: [])
        try save(Manifest(batch: batch))
        return batch
    }

    /// Stable itemID allows a disk-failed shot to retry without duplicate artifacts.
    func stage(data: Data, batchID: String, itemID: String = UUID().uuidString.lowercased(), capturedAt: Date = Date()) throws -> StagedCaptureItem {
        guard UUID(uuidString: itemID) != nil else { throw CaptureStagingError.invalidIdentity }
        var manifest = try read(batchID)
        guard !manifest.acknowledged.contains(itemID), !manifest.discarded.contains(itemID) else { throw CaptureStagingError.invalidIdentity }
        var item = manifest.batch.items.first { $0.id == itemID } ?? StagedCaptureItem(
            id: itemID.lowercased(), localURL: "local://project_images/capture_\(itemID.lowercased()).jpg",
            originalLocalURL: "local://project_images/capture_\(itemID.lowercased()).original",
            capturedAt: capturedAt, pixelWidth: 0, pixelHeight: 0
        )
        if !manifest.batch.items.contains(where: { $0.id == item.id }) {
            manifest.batch.items.append(item)
            try save(manifest)
        }
        // Do not overwrite a banked original on a retry.
        let original = fileURL(item.originalLocalURL)
        if !FileManager.default.fileExists(atPath: original.path) { try writeImage(data, to: original) }
        item = try prepare(item)
        manifest.batch.items = manifest.batch.items.map { $0.id == item.id ? item : $0 }
        try save(manifest)
        return item
    }

    func stage(image: UIImage, batchID: String, itemID: String = UUID().uuidString.lowercased()) throws -> StagedCaptureItem {
        guard let data = image.pngData() else { throw CaptureStagingError.invalidImage }
        return try stage(data: data, batchID: batchID, itemID: itemID)
    }

    /// One account-scoped manifest scan for draft discovery. Failure to inspect
    /// a journal propagates: unreadable custody must never look like no capture.
    func pendingContextIDs(companyID: String, userID: String) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var contexts = Set<String>()
        for file in files where file.pathExtension == "json" {
            let manifest = try read(file.deletingPathExtension().lastPathComponent)
            guard manifest.batch.owner.companyID == companyID.lowercased(),
                  manifest.batch.owner.userID == userID.lowercased() else { continue }
            if manifest.batch.items.contains(where: {
                !manifest.acknowledged.contains($0.id) && !manifest.discarded.contains($0.id)
                    && FileManager.default.fileExists(atPath: fileURL($0.originalLocalURL).path)
            }) { contexts.insert(manifest.batch.owner.contextID) }
        }
        return contexts
    }

    func recover(owner: StagedCaptureOwner) throws -> [StagedCaptureBatch] {
        try recordDelivered(localURLs: [], account: .init(companyID: owner.companyID, userID: owner.userID))
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var recovered: [StagedCaptureBatch] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "json" {
            // A damaged journal has unknown ownership. Surface the read failure
            // instead of treating this exact-owner reopen as an empty camera.
            var manifest = try read(file.deletingPathExtension().lastPathComponent)
            guard manifest.batch.owner == owner else { continue }
            var pending: [StagedCaptureItem] = []
            for item in manifest.batch.items where !manifest.acknowledged.contains(item.id) && !manifest.discarded.contains(item.id) {
                guard FileManager.default.fileExists(atPath: fileURL(item.originalLocalURL).path) else { continue }
                guard let prepared = try? prepare(item) else { continue }
                pending.append(prepared)
                if let index = manifest.batch.items.firstIndex(where: { $0.id == item.id }) { manifest.batch.items[index] = prepared }
            }
            if !pending.isEmpty {
                try save(manifest)
                recovered.append(StagedCaptureBatch(id: manifest.batch.id, owner: owner, items: pending))
            }
        }
        return recovered
    }

    /// Failed siblings remain owned and visible in camera review; successfully
    /// prepared siblings can still be recovered/committed independently.
    func retainedBatch(batchID: String, owner: StagedCaptureOwner, prepareImages: Bool = true) throws -> StagedCaptureBatch {
        if prepareImages { return try retainedRecovery(batchID: batchID, owner: owner).batch }
        let manifest = try read(batchID)
        guard manifest.batch.owner == owner else { throw CaptureStagingError.invalidIdentity }
        let retained = manifest.batch.items.filter { !manifest.discarded.contains($0.id) && !(manifest.delivered ?? []).contains($0.id) }
        return StagedCaptureBatch(id: batchID, owner: owner, items: retained)
    }

    /// A bad original cannot hide its prepared siblings from the form. Failed
    /// metadata remains explicit and owned, including previously acknowledged shots.
    func retainedRecovery(batchID: String, owner: StagedCaptureOwner) throws -> RetainedCaptureRecovery {
        var manifest = try read(batchID)
        guard manifest.batch.owner == owner else { throw CaptureStagingError.invalidIdentity }
        var prepared: [StagedCaptureItem] = [], failed: [StagedCaptureItem] = []
        for item in manifest.batch.items where !manifest.discarded.contains(item.id) && !(manifest.delivered ?? []).contains(item.id) {
            if let value = try? prepare(item) {
                prepared.append(value)
                if let index = manifest.batch.items.firstIndex(where: { $0.id == item.id }) { manifest.batch.items[index] = value }
            } else { failed.append(item) }
        }
        try save(manifest)
        return RetainedCaptureRecovery(batch: .init(id: batchID, owner: owner, items: prepared), failedItems: failed)
    }

    /// Metadata only: destination reopen can settle delivered items even when
    /// an earlier disk failure interrupted retirement after local model healing.
    func retainedBatches(owner: StagedCaptureOwner) throws -> [StagedCaptureBatch] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.compactMap { file in
                let manifest = try read(file.deletingPathExtension().lastPathComponent)
                guard manifest.batch.owner == owner else { return nil }
                let items = manifest.batch.items.filter { !manifest.discarded.contains($0.id) && !(manifest.delivered ?? []).contains($0.id) }
                return items.isEmpty ? nil : StagedCaptureBatch(id: manifest.batch.id, owner: owner, items: items)
            }
    }

    /// Draft receipts own acknowledged photos before a project exists. Only an
    /// explicit draft discard may release these, and the exact owner is required.
    func discardDraft(batchID: String, owner: StagedCaptureOwner, itemIDs: Set<String>) throws {
        guard owner.contextID.hasPrefix("project-draft:") else { throw CaptureStagingError.invalidIdentity }
        var manifest = try read(batchID)
        guard manifest.batch.owner == owner, itemIDs.isSubset(of: Set(manifest.batch.items.map(\.id))), (manifest.delivered ?? []).isDisjoint(with: itemIDs) else { throw CaptureStagingError.invalidIdentity }
        manifest.acknowledged.subtract(itemIDs)
        try save(manifest)
        try discard(batchID: batchID, itemIDs: itemIDs)
    }

    func failedItems(owner: StagedCaptureOwner) throws -> [StagedCaptureBatch] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "json" }.compactMap { file in
            let manifest = try read(file.deletingPathExtension().lastPathComponent)
            guard manifest.batch.owner == owner else { return nil }
            let failed = manifest.batch.items.filter {
                !manifest.acknowledged.contains($0.id) && !manifest.discarded.contains($0.id)
                    && (!FileManager.default.fileExists(atPath: fileURL($0.localURL).path) || $0.pixelWidth == 0)
            }
            return failed.isEmpty ? nil : StagedCaptureBatch(id: manifest.batch.id, owner: owner, items: failed)
        }
    }

    func originalData(for item: StagedCaptureItem) -> Data? {
        try? Data(contentsOf: fileURL(item.originalLocalURL), options: .mappedIfSafe)
    }

    /// Called only with exact canonical-delivery receipts after local healing.
    /// Retire duplicate source/JPEG bytes; compact metadata keeps old ack/replay
    /// IDs valid without retaining an unbounded protected photo cache.
    func recordDelivered(localURLs: Set<String>, account: CaptureAccountIdentity? = nil) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let receiptURL = root.appendingPathComponent("retirements.pending")
        var pending = FileManager.default.fileExists(atPath: receiptURL.path)
            ? try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: receiptURL)) : []
        pending.formUnion(localURLs.filter { $0.hasPrefix("local://project_images/capture_") })
        guard !pending.isEmpty else { return }
        let expected = account ?? currentAccount?()
        func requireOriginalAccount() throws {
            if let currentAccount {
                guard let expected, currentAccount() == expected else { throw CancellationError() }
            }
        }
        try requireOriginalAccount()
        try JSONEncoder().encode(pending).write(to: receiptURL, options: .atomic)
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            // An unrelated damaged manifest cannot destroy a delivery receipt.
            guard var manifest = try? read(file.deletingPathExtension().lastPathComponent) else { continue }
            if let expected, !expected.owns(manifest.batch.owner) { continue }
            let delivered = manifest.batch.items.filter { pending.contains($0.localURL) }
            guard !delivered.isEmpty else { continue }
            manifest.delivered = (manifest.delivered ?? []).union(delivered.map(\.id))
            manifest.acknowledged.formUnion(delivered.map(\.id))
            try requireOriginalAccount()
            try save(manifest)
            for item in delivered {
                var removed = true
                for id in [item.originalLocalURL, item.localURL] {
                    try requireOriginalAccount()
                    let url = fileURL(id)
                    if let ledger { removed = ledger.remove(url) && removed }
                    else if FileManager.default.fileExists(atPath: url.path) {
                        do { try FileManager.default.removeItem(at: url) } catch { removed = false }
                    }
                }
                if removed { pending.remove(item.localURL) }
            }
        }
        try requireOriginalAccount()
        try JSONEncoder().encode(pending).write(to: receiptURL, options: .atomic)
    }

    func acknowledge(batchID: String, itemIDs: Set<String>) throws {
        var manifest = try read(batchID)
        guard itemIDs.isSubset(of: Set(manifest.batch.items.map(\.id))), manifest.discarded.isDisjoint(with: itemIDs) else { throw CaptureStagingError.invalidIdentity }
        manifest.acknowledged.formUnion(itemIDs)
        try save(manifest)
        // Photo bytes are now owned by the model/outbox, including originals.
    }

    /// Only an explicit remove/discard action can release an uncommitted shot.
    /// Persist the tombstone first; a crash cannot resurrect a discarded item.
    func discard(batchID: String, itemIDs: Set<String>) throws {
        var manifest = try read(batchID)
        guard itemIDs.allSatisfy({ UUID(uuidString: $0) != nil }), manifest.acknowledged.isDisjoint(with: itemIDs) else { throw CaptureStagingError.invalidIdentity }
        manifest.discarded.formUnion(itemIDs)
        try save(manifest)
        for item in manifest.batch.items where itemIDs.contains(item.id) {
            for id in [item.localURL, item.originalLocalURL] {
                let url = fileURL(id)
                if let ledger { _ = ledger.remove(url) }
                else { try? FileManager.default.removeItem(at: url) }
            }
        }
    }

    func thumbnail(for item: StagedCaptureItem, maxPixelSize: Int = 240) -> UIImage? {
        PhotoDownsampler.image(url: fileURL(item.localURL), maxPixelSize: maxPixelSize)
    }

    func legacyImages(for batch: StagedCaptureBatch) throws -> [UIImage] {
        try batch.items.map {
            guard let image = UIImage(contentsOfFile: fileURL($0.localURL).path) else { throw CaptureStagingError.missingOriginal }
            return image
        }
    }

    private func prepare(_ item: StagedCaptureItem) throws -> StagedCaptureItem {
        let original = fileURL(item.originalLocalURL)
        guard let source = CGImageSourceCreateWithURL(original as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw CaptureStagingError.invalidImage }
        var item = item
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        item.pixelWidth = (5...8).contains(orientation) ? height : width
        item.pixelHeight = (5...8).contains(orientation) ? width : height
        let prepared = fileURL(item.localURL)
        if !FileManager.default.fileExists(atPath: prepared.path) {
            guard let image = PhotoDownsampler.image(url: original, maxPixelSize: max(width, height)),
                  let jpeg = image.jpegData(compressionQuality: 0.92) else { throw CaptureStagingError.invalidImage }
            try writeImage(jpeg, to: prepared)
        }
        return item
    }

    private func writeImage(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        if let ledger {
            guard ledger.write(data: data, to: url, budget: nil) else { throw CaptureStagingError.writeFailed }
        } else { try writer(data, url) }
    }
    private func fileURL(_ localURL: String) -> URL { images.appendingPathComponent((localURL as NSString).lastPathComponent) }
    private func manifestURL(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw CaptureStagingError.invalidIdentity }
        return root.appendingPathComponent(id.lowercased()).appendingPathExtension("json")
    }
    private func read(_ id: String) throws -> Manifest {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL(id)))
        guard manifest.version == 1, manifest.batch.id == id.lowercased() else { throw CaptureStagingError.incompatibleManifest }
        return manifest
    }
    private func save(_ manifest: Manifest) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writer(JSONEncoder().encode(manifest), manifestURL(manifest.batch.id))
    }
}
