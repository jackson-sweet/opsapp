//
//  ProjectShareSheet.swift
//  OPS
//
//  Builds the system share sheet for a Project deep link.
//
//  - Primary item is the canonical web URL: https://app.opsapp.co/projects/{id}
//  - LPLinkMetadata supplies a rich preview with the project title and the
//    project's first image as the thumbnail, so iMessage / Mail / Slack / etc.
//    show a recognizable card instead of a bare URL.
//

import Foundation
import LinkPresentation
import UIKit

/// Production OPS-Web base URL. Project deep links use:
///   https://app.opsapp.co/projects/{id}
private let opsWebBaseURL = "https://app.opsapp.co"

enum ProjectShareLinkBuilder {
    /// Character set used to encode the project ID into the URL path.
    /// We start from `.urlPathAllowed` and SUBTRACT `/` so that any future
    /// ID containing a slash is percent-encoded rather than silently
    /// splitting into extra path segments (which would cause the receiving
    /// `handleUniversalLink` to read only the first slash-fragment as the
    /// entity ID and drop the rest).
    private static let idAllowedCharacters: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()

    /// Builds the canonical shareable web URL for a project.
    ///
    /// Bubble IDs today are alphanumeric so this is belt-and-suspenders,
    /// but it means any future ID-format change can't silently corrupt
    /// the link.
    static func url(for project: Project) -> URL? {
        let encodedId = project.id.addingPercentEncoding(
            withAllowedCharacters: idAllowedCharacters
        ) ?? project.id
        return URL(string: "\(opsWebBaseURL)/projects/\(encodedId)")
    }
}

/// UIActivityItemSource that returns the project's deep-link URL alongside
/// rich link metadata (title + thumbnail image) so share targets render a
/// preview card with the project image.
///
/// Conforms to `Identifiable` so it can drive `.sheet(item:)` presentation —
/// avoids the stale-state race where `.sheet(isPresented:)` snapshots an
/// empty items array on the first tap and renders a blank share sheet.
final class ProjectShareItemSource: NSObject, UIActivityItemSource, Identifiable {

    let id = UUID()
    let url: URL
    let title: String
    let subtitle: String?
    let image: UIImage?

    init(url: URL, title: String, subtitle: String?, image: UIImage?) {
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.image = image
    }

    // MARK: - UIActivityItemSource

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        thumbnailImageForActivityType activityType: UIActivity.ActivityType?,
        suggestedSize size: CGSize
    ) -> UIImage? {
        image
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title

        if let image = image {
            let provider = NSItemProvider(object: image)
            metadata.imageProvider = provider
            metadata.iconProvider = provider
        }

        return metadata
    }
}

// MARK: - Image Loading

/// Loads the first project image (cache → local file → remote URL) for use as
/// the share thumbnail. Returns nil if the project has no images or loading
/// fails — share still works without a thumbnail.
enum ProjectShareImageLoader {
    static func loadFirstImage(for project: Project) async -> UIImage? {
        let photos = project.getProjectImages()
        guard let first = photos.first else { return nil }
        return await loadSingleImage(first)
    }

    /// Mirrors the loading order used in `SwipeCardView.loadSingleImage`:
    /// 1. ImageCache (in-memory)
    /// 2. ImageFileManager (offline / unsynced local files)
    /// 3. URLSession (remote)
    private static func loadSingleImage(_ photoKey: String) async -> UIImage? {
        let cacheKey = photoKey.hasPrefix("//") ? "https:" + photoKey : photoKey

        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            return cached
        }

        if let loaded = ImageFileManager.shared.loadImage(localID: photoKey) {
            ImageCache.shared.set(loaded, forKey: cacheKey)
            return loaded
        }

        guard let url = URL(string: cacheKey) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                ImageCache.shared.set(img, forKey: cacheKey)
                return img
            }
        } catch {
            // Swallow — share will proceed without a thumbnail.
        }

        return nil
    }
}
