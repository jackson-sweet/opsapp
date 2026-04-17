//
//  SpotlightThumbnailRenderer.swift
//  OPS
//
//  Produces 256x256 JPEG data for Spotlight thumbnails from cached project
//  images or client avatars, with SF Symbol fallbacks for entities without images.
//

import UIKit

enum SpotlightThumbnailRenderer {

    static let targetSize = CGSize(width: 256, height: 256)
    static let jpegQuality: CGFloat = 0.7

    /// Thumbnail for a project — iterates through cached images until one renders,
    /// falling back to a briefcase SF Symbol if none are usable.
    static func projectThumbnail(imageURLs: [String]) -> Data? {
        for url in imageURLs {
            if let image = ImageFileManager.shared.loadImage(localID: url),
               image.size.width > 0, image.size.height > 0,
               let data = render(image) {
                return data
            }
        }
        return symbolFallback("briefcase.fill", tint: .systemGray)
    }

    /// Thumbnail for a client — uses disk-cached avatar, or a person SF Symbol.
    static func clientThumbnail(avatarURL: String?) -> Data? {
        if let url = avatarURL,
           let image = ClientAvatarCache.shared.loadImage(for: url),
           image.size.width > 0, image.size.height > 0,
           let data = render(image) {
            return data
        }
        return symbolFallback("person.crop.circle.fill", tint: .systemGray)
    }

    /// Thumbnail for a task — uses parent project's thumbnail if available, else a checklist symbol.
    static func taskThumbnail(parentProjectImageURLs: [String]) -> Data? {
        if !parentProjectImageURLs.isEmpty {
            if let data = projectThumbnail(imageURLs: parentProjectImageURLs) {
                return data
            }
        }
        return symbolFallback("checklist", tint: .systemGray)
    }

    /// Thumbnail for an invoice — document SF Symbol.
    static func invoiceThumbnail() -> Data? {
        symbolFallback("doc.text.fill", tint: .systemGreen)
    }

    /// Thumbnail for an estimate — document SF Symbol.
    static func estimateThumbnail() -> Data? {
        symbolFallback("doc.plaintext.fill", tint: .systemOrange)
    }

    // MARK: - Private

    private static func render(_ image: UIImage) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaled = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: targetSize)
            image.draw(in: aspectFillRect(image: image, in: rect))
        }
        return scaled.jpegData(compressionQuality: jpegQuality)
    }

    private static func symbolFallback(_ name: String, tint: UIColor) -> Data? {
        let config = UIImage.SymbolConfiguration(pointSize: 160, weight: .medium)
        guard let symbol = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(tint, renderingMode: .alwaysOriginal) else { return nil }

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            let symbolRect = CGRect(
                x: (targetSize.width - symbol.size.width) / 2,
                y: (targetSize.height - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: symbolRect)
        }
        return rendered.jpegData(compressionQuality: jpegQuality)
    }

    private static func aspectFillRect(image: UIImage, in bounds: CGRect) -> CGRect {
        let imageAspect = image.size.width / image.size.height
        let boundsAspect = bounds.width / bounds.height

        if imageAspect > boundsAspect {
            // Image is wider — scale to height, crop width
            let scaledWidth = bounds.height * imageAspect
            return CGRect(
                x: (bounds.width - scaledWidth) / 2,
                y: 0,
                width: scaledWidth,
                height: bounds.height
            )
        } else {
            let scaledHeight = bounds.width / imageAspect
            return CGRect(
                x: 0,
                y: (bounds.height - scaledHeight) / 2,
                width: bounds.width,
                height: scaledHeight
            )
        }
    }
}
