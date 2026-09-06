import UIKit

/// Serial CPU worker for offscreen drawing and JPEG encoding. It never owns a
/// SwiftData model or a view hierarchy; only immutable drawing/image values.
actor DeckThumbnailWorker {
    static let shared = DeckThumbnailWorker()

    func render(
        drawingJSON: String,
        using renderer: @Sendable (DeckDrawingData) -> UIImage?
    ) -> UIImage? {
        autoreleasepool {
            // DeckDrawingData has reference-backed derived caches. Decoding
            // here gives the worker its own caches; a value copy would race
            // the editor's cache mutation even though geometry is a struct.
            guard let drawing = DeckDrawingData.fromJSON(drawingJSON) else { return nil }
            return renderer(drawing)
        }
    }

    func jpegData(for image: UIImage) -> Data? {
        autoreleasepool { image.jpegData(compressionQuality: 0.85) }
    }

    /// Copy the identifiers while on the model's owner, then use this API.
    /// Neither compression nor networking receives a live DeckDesign instance.
    static func upload(image: UIImage, designId: String, companyId: String) async throws -> String {
        guard let data = await shared.jpegData(for: image) else {
            throw DeckRenderer.DeckRendererError.compressionFailed
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        return try await PresignedURLUploadService.shared.uploadImageData(
            data, filename: "deck_\(designId)_\(timestamp).jpg", folder: "deck_designs/\(companyId)"
        )
    }
}
