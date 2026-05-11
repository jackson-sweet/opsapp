//
//  ProductThumbnailUploader.swift
//  OPS
//
//  Reusable helper that takes a UIImage + product id, resizes + JPEG-encodes
//  it, uploads it to the `product-thumbnails` Storage bucket, and hands back
//  the public URL. Mirrors the pattern in EmployeeProfileView.uploadAvatar
//  but parameterised on company + product so the path layout matches the
//  bucket policy convention from the Phase 1 migration.
//
//  Object naming convention (kept in lockstep with the Storage migration):
//      {companyId}/{productId}/{UUID().uuidString}.jpg
//
//  The leading company segment leaves room for a future per-company write
//  policy without re-keying any existing objects.
//

import Foundation
import UIKit

/// Errors specific to the product-thumbnail upload pipeline. Surfaced to
/// the caller so the UI can give the user a real reason ("ENCODE FAILED",
/// "UPLOAD FAILED — TAP TO RETRY") instead of swallowing into a generic
/// thrown Error.
enum ProductThumbnailUploadError: LocalizedError {
    case encodeFailed
    case missingPublicURL

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "Could not encode the image."
        case .missingPublicURL:
            return "Upload finished but no public URL was returned."
        }
    }
}

/// Stateless service. Lives behind a `.shared` singleton for parity with
/// the other Storage-touching services in this codebase (presigned URL,
/// S3, etc.) so call sites don't have to instantiate it themselves.
final class ProductThumbnailUploader {
    static let shared = ProductThumbnailUploader()

    /// Bucket name. Lifted to a constant so any future rename touches one
    /// line; matches the bucket created in
    /// `2026-05-08-product-thumbnails-storage-policy.sql`.
    private let bucket = "product-thumbnails"

    /// Max long-edge in pixels. We resize before encoding so a 12MP camera
    /// roll original doesn't become a multi-megabyte object on the wire —
    /// thumbnails get rendered at 40-300pt, so 1024px is plenty.
    private let maxLongEdge: CGFloat = 1024

    /// JPEG compression quality. 0.85 is the same value the avatar pipeline
    /// in EmployeeProfileView uses; visually lossless for product shots
    /// while keeping object size reasonable for sync to slow networks.
    private let jpegQuality: CGFloat = 0.85

    private init() {}

    // MARK: - Public API

    /// Upload `image` for the given product. Returns the public URL string.
    ///
    /// Both `companyId` and `productId` are used to build the object path —
    /// passing them explicitly (rather than reading from a global) means
    /// the helper is testable and there's no implicit assumption that the
    /// upload happens on the user's "current" company.
    func upload(_ image: UIImage, productId: String, companyId: String) async throws -> URL {
        let resized = resized(image, maxLongEdge: maxLongEdge)
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else {
            throw ProductThumbnailUploadError.encodeFailed
        }

        // {companyId}/{productId}/{UUID().uuidString}.jpg
        // The UUID-per-upload means a "replace" call doesn't have to delete
        // the previous object — the row just points at a new key. Storage
        // GC of orphaned objects is out of scope; if it becomes an issue
        // we can sweep against `products.thumbnail_url` server-side.
        let objectName = "\(UUID().uuidString).jpg"
        let path = "\(companyId)/\(productId)/\(objectName)"

        let storage = SupabaseService.shared.client.storage.from(bucket)

        // upsert: true so a retry against the same path is safe — though
        // the UUID rotation above means we'd only collide on a retry of
        // the exact same logical upload, which we want to be idempotent.
        try await storage.upload(
            path: path,
            file: data,
            options: .init(contentType: "image/jpeg", upsert: true)
        )

        let publicURL = try storage.getPublicURL(path: path)
        return publicURL
    }

    // MARK: - Resize helper

    /// Aspect-fit resize so neither edge exceeds `maxLongEdge`. Returns the
    /// original image untouched when it's already small enough so we don't
    /// recompress in place. `UIGraphicsImageRenderer` honors the device
    /// scale, so the output is in pixel-space (not point-space) — exactly
    /// what we want before JPEG-encoding for upload.
    private func resized(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxLongEdge else { return image }

        let scale = maxLongEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0  // we already resolved into pixel-space
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
