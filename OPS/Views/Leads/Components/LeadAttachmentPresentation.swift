//
//  LeadAttachmentPresentation.swift
//  OPS
//
//  Pure media and count policy for Lead Details email attachments. Raster
//  images join the Lead Photos viewer; every attachment remains available in
//  the compact attachment sheet.
//

import Foundation

enum LeadAttachmentVisualKind: Equatable {
    case image
    case pdf
    case file
}

enum LeadAttachmentPresentation {
    private static let rasterImageExtensions: Set<String> = [
        "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
    ]

    static func kind(mimeType: String?, filename: String?) -> LeadAttachmentVisualKind {
        let rawMime = mimeType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let mime = rawMime.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
        let fileExtension = filename?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .last
            .map(String.init)?
            .lowercased() ?? ""

        if mime == "application/pdf" || fileExtension == "pdf" {
            return .pdf
        }
        if mime == "image/svg+xml" || fileExtension == "svg" {
            return .file
        }
        if mime.hasPrefix("image/") || rasterImageExtensions.contains(fileExtension) {
            return .image
        }
        return .file
    }

    static func summary(count: Int) -> String {
        count == 1 ? "1 attachment" : "\(count) attachments"
    }

    static func isLeadPhoto(
        ingestStatus: String,
        mimeType: String?,
        filename: String?
    ) -> Bool {
        ingestStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "stored"
            && kind(mimeType: mimeType, filename: filename) == .image
    }

    /// Produces a display-friendly leaf name that cannot escape the dedicated
    /// temporary attachment directory when passed to `appendingPathComponent`.
    static func safeFilename(filename: String?, mimeType: String?) -> String {
        let normalized = (filename ?? "")
            .replacingOccurrences(of: "\\", with: "/")
        let leaf = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? ""
        let withoutControls = leaf.components(separatedBy: .controlCharacters).joined()
        var safeName = withoutControls.trimmingCharacters(in: .whitespacesAndNewlines)

        if safeName.isEmpty || safeName == "." || safeName == ".." {
            safeName = "attachment"
        }

        if (safeName as NSString).pathExtension.isEmpty,
           let suggestedExtension = suggestedExtension(for: mimeType) {
            safeName += ".\(suggestedExtension)"
        }

        return safeName
    }

    private static func suggestedExtension(for mimeType: String?) -> String? {
        let normalized = mimeType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)

        switch normalized {
        case "application/pdf": return "pdf"
        case "image/bmp": return "bmp"
        case "image/gif": return "gif"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/tiff": return "tiff"
        case "image/webp": return "webp"
        default: return nil
        }
    }
}
