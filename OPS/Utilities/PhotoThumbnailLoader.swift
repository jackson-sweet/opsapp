import Foundation
import ImageIO
import UIKit

extension Notification.Name {
    static let photoThumbnailSourceChanged = Notification.Name("photoThumbnailSourceChanged")
}

struct PhotoThumbnailRequest: Hashable, Sendable {
    let sourceURL: String
    let fallbackURL: String?
    let maxPixelSize: Int
    let prefersComposite: Bool

    init(sourceURL: String, fallbackURL: String? = nil, maxPixelSize: Int, prefersComposite: Bool = true) {
        self.sourceURL = sourceURL.hasPrefix("//") ? "https:" + sourceURL : sourceURL
        self.fallbackURL = fallbackURL.map { $0.hasPrefix("//") ? "https:" + $0 : $0 }
        self.maxPixelSize = min(2048, max(1, maxPixelSize))
        self.prefersComposite = prefersComposite
    }
}

/// Limits concurrent decoding/network work without blocking an executor thread.
actor PhotoWorkLimiter {
    static let shared = PhotoWorkLimiter(limit: 3)
    private let limit: Int
    private var running = 0
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []
    init(limit: Int) { self.limit = max(1, limit) }

    func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if running < limit { running += 1; return }
            try await withCheckedThrowingContinuation { waiting.append((id, $0)) }
            if Task.isCancelled { release(); throw CancellationError() }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func release() {
        if waiting.isEmpty { running -= 1 }
        else { waiting.removeFirst().1.resume() }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }
}

enum PhotoDownsampler {
    static func image(data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return image(source: source, maxPixelSize: maxPixelSize)
    }
    static func image(url: URL, maxPixelSize: Int) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return image(source: source, maxPixelSize: maxPixelSize)
    }
    private static func image(source: CGImageSource, maxPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Each request shares one bounded job; cancelling a tile promptly releases its
/// waiter, and cancels the underlying download only when no other tile needs it.
actor PhotoThumbnailLoader {
    static let shared = PhotoThumbnailLoader()
    typealias Fetch = @Sendable (URL) async throws -> Data
    typealias LocalURL = @Sendable (String) -> URL?
    private struct Job {
        let generation: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<UIImage?, Error>]
    }
    private var jobs: [PhotoThumbnailRequest: Job] = [:]
    private let fetch: Fetch
    private let localURL: LocalURL
    private let compositeID: @Sendable (String) -> String
    private let store: @Sendable (Data, String) -> Void
    private let limiter: PhotoWorkLimiter

    init(
        fetch: @escaping Fetch = PhotoThumbnailLoader.fetchRemote,
        localURL: @escaping LocalURL = { ImageFileManager.shared.getFileURL(for: $0) },
        compositeID: @escaping @Sendable (String) -> String = { ImageFileManager.shared.compositedReadLocalID(forURL: $0) },
        store: @escaping @Sendable (Data, String) -> Void = { _ = ImageFileManager.shared.saveImage(data: $0, localID: $1) },
        limiter: PhotoWorkLimiter = .shared
    ) {
        self.fetch = fetch; self.localURL = localURL; self.compositeID = compositeID
        self.store = store; self.limiter = limiter
    }

    func image(for request: PhotoThumbnailRequest) async throws -> UIImage? {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if jobs[request] != nil {
                    jobs[request]?.waiters[id] = continuation
                } else {
                    let generation = UUID()
                    let task = Task { [fetch, localURL, compositeID, store, limiter] in
                        let result: Result<UIImage?, Error>
                        do {
                            try await limiter.acquire()
                            do {
                                let image = try await Self.load(request, fetch: fetch, localURL: localURL, compositeID: compositeID, store: store)
                                await limiter.release()
                                result = .success(image)
                            } catch {
                                await limiter.release()
                                result = .failure(error)
                            }
                        } catch { result = .failure(error) }
                        self.finish(request, generation: generation, result: result)
                    }
                    jobs[request] = Job(generation: generation, task: task, waiters: [id: continuation])
                }
            }
        } onCancel: { Task { await self.cancel(request, id: id) } }
    }

    /// Lightweight diagnostic count; exposes no image bytes or source identities.
    func waiterCount(for request: PhotoThumbnailRequest) -> Int { jobs[request]?.waiters.count ?? 0 }

    private func finish(_ request: PhotoThumbnailRequest, generation: UUID, result: Result<UIImage?, Error>) {
        guard jobs[request]?.generation == generation, let job = jobs.removeValue(forKey: request) else { return }
        for continuation in job.waiters.values { continuation.resume(with: result) }
    }
    private func cancel(_ request: PhotoThumbnailRequest, id: UUID) {
        guard var job = jobs[request], let waiter = job.waiters.removeValue(forKey: id) else { return }
        waiter.resume(throwing: CancellationError())
        if job.waiters.isEmpty { jobs.removeValue(forKey: request); job.task.cancel() }
        else { jobs[request] = job }
    }

    private nonisolated static func load(
        _ request: PhotoThumbnailRequest, fetch: Fetch, localURL: LocalURL,
        compositeID: @Sendable (String) -> String, store: @Sendable (Data, String) -> Void
    ) async throws -> UIImage? {
        var seen = Set<String>()
        for source in [request.sourceURL, request.fallbackURL].compactMap({ $0 }) where seen.insert(source).inserted {
            try Task.checkCancellation()
            let keys = request.prefersComposite ? [compositeID(source), source] : [source]
            for key in keys {
                if let url = localURL(key), let image = PhotoDownsampler.image(url: url, maxPixelSize: request.maxPixelSize) { return image }
            }
            guard let url = URL(string: source), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            do {
                let data = try await fetch(url)
                try Task.checkCancellation()
                guard let image = PhotoDownsampler.image(data: data, maxPixelSize: request.maxPixelSize) else { continue }
                store(data, source)
                // A markup composite may have arrived while the original downloaded.
                if request.prefersComposite, let url = localURL(compositeID(source)),
                   let composite = PhotoDownsampler.image(url: url, maxPixelSize: request.maxPixelSize) { return composite }
                return image
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        return nil
    }

    nonisolated static func fetchRemote(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (file, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 80 * 1024 * 1024 else { throw URLError(.badServerResponse) }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }
}
