import Foundation
import UIKit

/// Lead-file custody is journaled per item before publishing to the existing
/// UserDefaults queue. Reopening can recover an interrupted batch in order.
actor LeadImageStager {
    static let shared = LeadImageStager()
    private struct Record: Codable {
        var version = 1
        var finished = false
        let pending: PendingLeadImageUpload
    }
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeadPhotoStaging", isDirectory: true)
    }

    func stage(_ image: UIImage, pending: PendingLeadImageUpload) throws -> PendingLeadImageUpload {
        // A journal without bytes is retained for diagnosis; it is never reported
        // as queued. Original PNG retains source orientation when flattened.
        try save(pending)
        guard let originalID = pending.originalLocalURL,
              let original = Self.normalizedOriginalPNG(image),
              ImageFileManager.shared.saveImage(data: original, localID: originalID) else { throw CaptureStagingError.writeFailed }
        guard let jpeg = Self.preparedJPEG(image),
              ImageFileManager.shared.saveImage(data: jpeg, localID: pending.localURL) else { throw CaptureStagingError.writeFailed }
        return pending
    }

    /// Adopts already-durable camera bytes without another decode/encode cycle.
    func adopt(_ pending: PendingLeadImageUpload) throws -> PendingLeadImageUpload {
        if let id = pending.journalID, FileManager.default.fileExists(atPath: try journalURL(id).path) {
            let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: journalURL(id)))
            guard record.version == 1 else { throw CaptureStagingError.incompatibleManifest }
            guard record.pending.companyId.lowercased() == pending.companyId.lowercased(),
                  record.pending.opportunityId.lowercased() == pending.opportunityId.lowercased(),
                  record.pending.userID == pending.userID, record.pending.localURL == pending.localURL,
                  record.pending.originalLocalURL == pending.originalLocalURL else { throw CaptureStagingError.invalidIdentity }
            return record.pending
        }
        guard ImageFileManager.shared.imageExists(localID: pending.localURL) else { throw CaptureStagingError.missingOriginal }
        try save(pending)
        return pending
    }

    func recover(companyID: String, userID: String) throws -> [PendingLeadImageUpload] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var pending: [PendingLeadImageUpload] = []
        for file in files where file.pathExtension == "json" {
            let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file))
            guard record.version == 1 else { throw CaptureStagingError.incompatibleManifest }
            guard !record.finished else { continue }
            let item = record.pending
            guard item.companyId.lowercased() == companyID.lowercased(), item.userID == userID.lowercased() else { continue }
            if item.uploadedURL == nil && !ImageFileManager.shared.imageExists(localID: item.localURL) {
                guard let originalID = item.originalLocalURL,
                      let original = ImageFileManager.shared.loadImage(localID: originalID),
                      let jpeg = Self.preparedJPEG(original),
                      ImageFileManager.shared.saveImage(data: jpeg, localID: item.localURL) else { continue }
            }
            pending.append(item)
        }
        return pending.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return ($0.batchIndex ?? 0) < ($1.batchIndex ?? 0)
        }
    }

    func recordRemote(_ item: PendingLeadImageUpload, url: String) throws -> PendingLeadImageUpload {
        var item = item
        // Never resurrect a journal concurrently removed by a deliberate delete.
        guard try isActive(item) else { throw CancellationError() }
        item.uploadedURL = url
        if item.journalID != nil { try save(item) }
        return item
    }

    func finish(_ item: PendingLeadImageUpload) throws {
        if let id = item.journalID {
            let url = try journalURL(id)
            try JSONEncoder().encode(Record(finished: true, pending: item)).write(to: url, options: .atomic)
        }
        _ = ImageFileManager.shared.deleteImage(localID: item.localURL)
        if let original = item.originalLocalURL { _ = ImageFileManager.shared.deleteImage(localID: original) }
    }

    func current(_ item: PendingLeadImageUpload) throws -> PendingLeadImageUpload {
        guard let id = item.journalID else { return item }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: journalURL(id)))
        guard record.version == 1, !record.finished else { throw CancellationError() }
        return record.pending
    }

    func isActive(_ item: PendingLeadImageUpload) throws -> Bool {
        guard let id = item.journalID else { return true }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: journalURL(id)))
        return record.version == 1 && !record.finished
    }

    func hasOriginal(_ item: PendingLeadImageUpload) -> Bool {
        item.originalLocalURL.map { ImageFileManager.shared.imageExists(localID: $0) } ?? false
    }

    func uploadData(_ item: PendingLeadImageUpload) throws -> Data? {
        guard try isActive(item) else { throw CancellationError() }
        if let data = ImageFileManager.shared.getImageData(localID: item.localURL) { return data }
        guard let originalID = item.originalLocalURL,
              let original = ImageFileManager.shared.loadImage(localID: originalID),
              let jpeg = Self.preparedJPEG(original),
              ImageFileManager.shared.saveImage(data: jpeg, localID: item.localURL) else { return nil }
        return jpeg
    }

    private nonisolated static func normalizedOriginalPNG(_ image: UIImage) -> Data? {
        // UIImage-only legacy callers no longer expose encoded source metadata.
        // Preserve their full visible resolution losslessly, including orientation.
        let size = CGSize(width: max(1, image.size.width * image.scale), height: max(1, image.size.height * image.scale))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    nonisolated static func preparedJPEG(_ image: UIImage) -> Data? {
        let pixelWidth = image.size.width * image.scale, pixelHeight = image.size.height * image.scale
        let scale = min(1, 2048 / max(pixelWidth, pixelHeight))
        let size = CGSize(width: max(1, pixelWidth * scale), height: max(1, pixelHeight * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        let pixels = size.width * size.height
        let quality: CGFloat = pixels > 4_000_000 ? 0.5 : pixels > 2_000_000 ? 0.6 : pixels > 1_000_000 ? 0.7 : 0.8
        return resized.jpegData(compressionQuality: quality)
    }

    private func journalURL(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw CaptureStagingError.invalidIdentity }
        return root.appendingPathComponent(id.lowercased()).appendingPathExtension("json")
    }
    private func save(_ item: PendingLeadImageUpload) throws {
        guard let id = item.journalID else { throw CaptureStagingError.invalidIdentity }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(Record(pending: item)).write(to: journalURL(id), options: .atomic)
    }
}
