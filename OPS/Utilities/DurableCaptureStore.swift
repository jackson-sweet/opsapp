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

enum CaptureStagingError: Error {
    case invalidImage, invalidIdentity, incompatibleManifest, missingOriginal, writeFailed
}

/// A versioned file journal, separate from SwiftData schema history. Every intent
/// is journaled BEFORE its original is atomically written. Recovery repairs a
/// missing JPEG from that untouched original. Nothing is pruned by age/cache policy.
actor DurableCaptureStore {
    static let shared = DurableCaptureStore()
    private struct Manifest: Codable {
        var version = 1
        var batch: StagedCaptureBatch
        var acknowledged: Set<String> = []
        var discarded: Set<String> = []
    }
    typealias Writer = @Sendable (Data, URL) throws -> Void
    private let root: URL
    private let images: URL
    private let writer: Writer
    private let ledger: PhotoCacheLedger?

    init(root: URL? = nil, images: URL? = nil, writer: @escaping Writer = { try $0.write(to: $1, options: .atomic) }) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? docs.appendingPathComponent("CaptureBatches", isDirectory: true)
        self.images = images ?? docs.appendingPathComponent("ProjectImages", isDirectory: true)
        self.writer = writer
        self.ledger = images == nil ? .shared : nil
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
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var recovered: [StagedCaptureBatch] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "json" {
            // Unknown/corrupt journals are retained, never removed or reassigned.
            guard var manifest = try? read(file.deletingPathExtension().lastPathComponent), manifest.batch.owner == owner else { continue }
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
    func failedItems(owner: StagedCaptureOwner) throws -> [StagedCaptureBatch] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return files.compactMap { file in
            guard file.pathExtension == "json", let manifest = try? read(file.deletingPathExtension().lastPathComponent),
                  manifest.batch.owner == owner else { return nil }
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
