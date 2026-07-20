//
//  MarkupOverlayCompositor.swift
//  OPS
//
//  Shared overlay compositing for collaborative markup — extracted from the
//  download+flatten primitive in PhotoAnnotationSyncManager.preCompositeAnnotations
//  so the EDITOR's peer-base layer and the GALLERY composite use one code path.
//
//  Two consumers:
//   • Editor — flatten the VISIBLE PEER layers into a transparent base image that
//     sits under the current user's PencilKit canvas (the #1 fix: peers' marks are
//     visible, not overwritten).
//   • Gallery — flatten the photo + ALL active layers so a thumbnail shows every
//     author's marks (not just the legacy single overlay).
//

import UIKit

enum MarkupOverlayCompositor {

    /// Cap the editor peer-base composite so a single editor session never holds a
    /// full-resolution transparent frame per peer on a 3-year-old device. Overlays
    /// scale by aspect-fit, so capping does not affect stroke alignment.
    static let editorCompositeMaxEdge: CGFloat = 2048

    // MARK: - Flatten

    /// Flatten `overlays` (already in z-order) onto an optional `base` at `size`.
    /// `base == nil` → transparent result (editor peer-base). `base != nil` →
    /// opaque composite (gallery display). Returns `base` unchanged if `size` is
    /// degenerate.
    static func composite(base: UIImage?, overlays: [UIImage], size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return base }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = (base != nil)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            base?.draw(in: rect)
            for overlay in overlays { overlay.draw(in: rect) }
        }
    }

    // MARK: - Resolve overlays

    /// Resolve one layer's overlay PNG: local cache first, else download by URL and
    /// cache. Nil for a cleared layer (no overlay) or on failure.
    static func loadOverlay(for layer: MarkupLayer) async -> UIImage? {
        guard layer.isActive, let urlString = layer.overlayUrl, !urlString.isEmpty else { return nil }
        let cacheID = overlayCacheID(forURL: urlString)
        if let cached = ImageFileManager.shared.loadImage(localID: cacheID) {
            return cached
        }
        let normalized = urlString.hasPrefix("//") ? "https:" + urlString : urlString
        guard let url = URL(string: normalized),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        _ = ImageFileManager.shared.saveImage(data: data, localID: cacheID)
        return image
    }

    /// Resolve + flatten the given (already-filtered, e.g. visible peer) layers into
    /// one transparent base image of `size`, capped to `editorCompositeMaxEdge`.
    /// Nil when no overlay resolves (so the caller can hide the peer-base view).
    static func compositePeerOverlays(_ layers: [MarkupLayer], sourceSize: CGSize) async -> UIImage? {
        let ordered = layers.sorted { $0.zIndex < $1.zIndex }
        var images: [UIImage] = []
        for layer in ordered {
            if let image = await loadOverlay(for: layer) { images.append(image) }
        }
        guard !images.isEmpty else { return nil }
        return composite(base: nil, overlays: images, size: cappedSize(sourceSize, maxEdge: editorCompositeMaxEdge))
    }

    // MARK: - Cache id

    /// Stable, bounded, filename-safe cache id from the full overlay URL (FNV-1a).
    /// Stable across launches (Swift's `hashValue` is not), bounded length (URLs
    /// can exceed the 255-char filename limit).
    static func overlayCacheID(forURL url: String) -> String {
        let normalized = url.hasPrefix("//") ? "https:" + url : url
        var hash: UInt64 = 14695981039346656037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return "mklayer_" + String(hash, radix: 16)
    }

    // MARK: - Helpers

    static func cappedSize(_ size: CGSize, maxEdge: CGFloat) -> CGSize {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxEdge, longEdge > 0 else { return size }
        let scale = maxEdge / longEdge
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
