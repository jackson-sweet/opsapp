//
//  LeadAttachmentContentLoader.swift
//  OPS
//
//  One authenticated content path for Lead Details attachments. Stored files
//  stream through the guarded ops-web endpoint; externally hosted files use
//  the safe HTTPS URL returned by the sanctioned lead-files RPC.
//

import SwiftUI
import UIKit
import PDFKit

enum LeadAttachmentContentLoader {
    /// Large enough to preserve useful pinch-zoom detail without decoding an
    /// unbounded original into memory.
    static let viewerMaxPixelSize: CGFloat = 4_096
    /// Canonical ingestion rejects files above 25 MiB. Re-enforce that limit
    /// before any client cache or decoder receives response bytes.
    fileprivate static let maximumDownloadBytes = 25 * 1_024 * 1_024
    private static let downloadGate = LeadAttachmentDownloadGate(maxConcurrent: 2)

    static func data(for attachment: LeadAttachment) async throws -> Data {
        try await LeadAttachmentDataStore.shared.data(for: attachment)
    }

    /// Synchronous by design: logout calls this before authentication teardown,
    /// cancelling old-session requests and invalidating late completions.
    static func resetForLogout() {
        LeadAttachmentDataStore.shared.resetForLogout()
    }

    fileprivate static func fetchUncached(for attachment: LeadAttachment) async throws -> Data {
        try await downloadGate.run {
            let request = try await request(for: attachment)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let declaredLength = http.expectedContentLength
            guard (declaredLength < 0 || declaredLength <= Int64(maximumDownloadBytes)),
                  data.count <= maximumDownloadBytes else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            return data
        }
    }

    static func image(
        for attachment: LeadAttachment,
        maxPixelSize: CGFloat
    ) async -> UIImage? {
        let generation = LeadAttachmentDataStore.shared.currentGeneration()
        let cacheKey = "lead-attachment:\(attachment.id):\(Int(maxPixelSize.rounded()))"
        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            return cached
        }

        guard let data = try? await data(for: attachment) else {
            return nil
        }

        let image: UIImage?
        switch LeadAttachmentPresentation.kind(
            mimeType: attachment.mimeType,
            filename: attachment.filename
        ) {
        case .image:
            image = ImageDownsampler.downsample(
                data: data,
                maxPixelSize: maxPixelSize
            )
        case .pdf:
            image = PDFDocument(data: data)?
                .page(at: 0)?
                .thumbnail(
                    of: CGSize(width: maxPixelSize, height: maxPixelSize),
                    for: .mediaBox
                )
        case .file:
            image = nil
        }

        guard let image else { return nil }
        guard LeadAttachmentDataStore.shared.cacheDecodedImageIfCurrent(
            image,
            forKey: cacheKey,
            generation: generation
        ) else { return nil }
        return image
    }

    private static func request(for attachment: LeadAttachment) async throws -> URLRequest {
        switch attachment.ingestStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "external":
            guard let rawURL = attachment.sourceUrl,
                  let url = URL(string: rawURL),
                  url.scheme?.lowercased() == "https" else {
                throw URLError(.badURL)
            }
            return URLRequest(url: url)

        case "stored":
            break

        default:
            throw URLError(.unsupportedURL)
        }

        let token = try await FirebaseAuthService.shared.getIDToken()
        var components = URLComponents(
            url: AppConfiguration.apiBaseURL
                .appendingPathComponent("/api/integrations/email/attachment"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "id", value: attachment.id)]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

/// Caps distinct attachment requests so an attachment-heavy lead cannot hold
/// every full file body in memory at the same time. Cancelled waiters inherit a
/// transferred permit, observe cancellation, and immediately release it.
private actor LeadAttachmentDownloadGate {
    private let maxConcurrent: Int
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(maxConcurrent, 1)
    }

    func run<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            activeCount = max(activeCount - 1, 0)
            return
        }
        waiters.removeFirst().resume()
    }
}

/// Coalesces simultaneous strip/sheet/viewer requests and keeps the encoded
/// bytes under a bounded cache so different decode sizes do not re-download
/// the same private attachment.
private final class LeadAttachmentDataStore: @unchecked Sendable {
    static let shared = LeadAttachmentDataStore()

    private struct InFlight: Sendable {
        let token: UUID
        let generation: UInt64
        let task: Task<Data, Error>
    }

    private enum Lookup {
        case cached(Data)
        case inFlight(InFlight)
    }

    private let cache = NSCache<NSString, NSData>()
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var inFlight: [String: InFlight] = [:]

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 50 * 1_024 * 1_024
    }

    func data(for attachment: LeadAttachment) async throws -> Data {
        let lookup = lookupOrCreate(for: attachment)
        switch lookup {
        case .cached(let data):
            return data

        case .inFlight(let request):
            do {
                let data = try await request.task.value
                guard finishSuccess(
                    data,
                    key: attachment.id,
                    request: request
                ) else {
                    throw CancellationError()
                }
                return data
            } catch {
                finishFailure(key: attachment.id, request: request)
                throw error
            }
        }
    }

    func resetForLogout() {
        let requests: [Task<Data, Error>]
        lock.lock()
        generation &+= 1
        cache.removeAllObjects()
        ImageCache.shared.clear()
        requests = inFlight.values.map(\.task)
        inFlight.removeAll()
        lock.unlock()

        requests.forEach { $0.cancel() }
    }

    func currentGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    func cacheDecodedImageIfCurrent(
        _ image: UIImage,
        forKey key: String,
        generation expectedGeneration: UInt64
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expectedGeneration else { return false }
        ImageCache.shared.set(image, forKey: key)
        return true
    }

    private func lookupOrCreate(for attachment: LeadAttachment) -> Lookup {
        let key = attachment.id
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache.object(forKey: key as NSString) {
            return .cached(cached as Data)
        }
        if let request = inFlight[key] {
            return .inFlight(request)
        }

        let request = InFlight(
            token: UUID(),
            generation: generation,
            task: Task {
                try await LeadAttachmentContentLoader.fetchUncached(for: attachment)
            }
        )
        inFlight[key] = request
        return .inFlight(request)
    }

    private func finishSuccess(
        _ data: Data,
        key: String,
        request: InFlight
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard generation == request.generation else {
            if inFlight[key]?.token == request.token {
                inFlight[key] = nil
            }
            return false
        }

        if inFlight[key]?.token == request.token {
            inFlight[key] = nil
        }
        if data.count <= LeadAttachmentContentLoader.maximumDownloadBytes {
            cache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        }
        return true
    }

    private func finishFailure(key: String, request: InFlight) {
        lock.lock()
        defer { lock.unlock() }
        if inFlight[key]?.token == request.token {
            inFlight[key] = nil
        }
    }
}

/// Reusable stored-file preview for the photo strip and attachment sheet.
/// Raster images downsample directly; PDFs render their first page. The caller
/// owns the frame, clipping, and border so this remains layout-neutral.
struct LeadAttachmentPreview: View {
    let attachment: LeadAttachment
    let maxPixelSize: CGFloat
    var contentMode: ContentMode = .fill
    var showsFailureMessage = false

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var didFail = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.surfaceInput

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(OPSStyle.Colors.text3)
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: placeholderIcon)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .regular))
                    if didFail && showsFailureMessage {
                        Text("// COULD NOT LOAD")
                            .font(OPSStyle.Typography.miniLabel)
                            .kerning(OPSStyle.Typography.trackingStandard)
                    }
                }
                .foregroundColor(OPSStyle.Colors.textMute)
            }
        }
        .clipped()
        .task(id: "\(attachment.id):\(Int(maxPixelSize.rounded()))") {
            let status = attachment.ingestStatus
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let visualKind = LeadAttachmentPresentation.kind(
                mimeType: attachment.mimeType,
                filename: attachment.filename
            )
            // Never auto-fetch sender-controlled external URLs. Stored raster
            // images and PDFs can safely render authenticated thumbnails.
            guard status == "stored", visualKind != .file else { return }

            isLoading = true
            didFail = false
            let loaded = await LeadAttachmentContentLoader.image(
                for: attachment,
                maxPixelSize: maxPixelSize
            )
            image = loaded
            didFail = loaded == nil
            isLoading = false
        }
    }

    private var placeholderIcon: String {
        switch LeadAttachmentPresentation.kind(
            mimeType: attachment.mimeType,
            filename: attachment.filename
        ) {
        case .image:
            return OPSStyle.Icons.photos
        case .pdf, .file:
            return OPSStyle.Icons.documents
        }
    }
}
