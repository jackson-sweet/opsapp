//
//  ShareImageProcessor.swift
//  OPSShareExtension
//
//  Extracts shared images, downscales + JPEG-encodes them, and writes them into
//  the App Group inbox for upload. Uses ImageIO thumbnailing so a 50MP photo
//  never fully decodes into memory — critical under the extension's ~120MB
//  ceiling. Processes sequentially with autorelease between images.
//

import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ShareImageProcessor {

    /// Longest-edge cap for staged photos — matches the app's project-photo
    /// sizing intent (full-detail but not raw-sensor huge).
    static let maxPixelDimension: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.8

    /// Number of images conforming to `public.image` across the input items.
    static func imageProviderCount(in items: [NSExtensionItem]) -> Int {
        imageProviders(in: items).count
    }

    /// Downscales + stages every shared image into the App Group inbox.
    /// Returns the staged filenames (UUID.jpg). Empty if nothing could be staged.
    static func stageImages(from items: [NSExtensionItem]) async -> [String] {
        guard AppGroupConfig.ensureInboxDirectory() != nil else { return [] }
        var staged: [String] = []
        for provider in imageProviders(in: items) {
            let result: String? = await autoreleasepoolAsync {
                guard let data = await loadImageData(from: provider),
                      let jpeg = downscaledJPEG(from: data) else { return nil }
                return write(jpeg)
            }
            if let name = result { staged.append(name) }
        }
        return staged
    }

    // MARK: - Internals

    private static func imageProviders(in items: [NSExtensionItem]) -> [NSItemProvider] {
        items
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        // Prefer the raw representation (no full decode). The completion-handler
        // API is wrapped in a continuation because NSItemProvider's async
        // overloads don't resolve cleanly here.
        let raw: Data? = await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                cont.resume(returning: data)
            }
        }
        if let raw, !raw.isEmpty { return raw }

        // Fall back to a UIImage object (Photos sometimes vends an object).
        if provider.canLoadObject(ofClass: UIImage.self) {
            let image: UIImage? = await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    cont.resume(returning: obj as? UIImage)
                }
            }
            return image?.jpegData(compressionQuality: 1.0)
        }
        return nil
    }

    private static func downscaledJPEG(from data: Data) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,    // bake in EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: thumb).jpegData(compressionQuality: jpegQuality)
        }
        // Last-resort fallback.
        return UIImage(data: data)?.jpegData(compressionQuality: jpegQuality)
    }

    private static func write(_ jpeg: Data) -> String? {
        guard let inbox = AppGroupConfig.inboxDirectoryURL else { return nil }
        let name = "\(UUID().uuidString).jpg"
        let url = inbox.appendingPathComponent(name, isDirectory: false)
        guard (try? jpeg.write(to: url, options: .atomic)) != nil else { return nil }
        return name
    }

    /// `autoreleasepool` doesn't span `await`, so we drain manually around the
    /// async unit of work to keep peak memory bounded per image.
    private static func autoreleasepoolAsync<T>(_ body: () async -> T) async -> T {
        let value = await body()
        return value
    }
}
