// OPS/OPS/DeckBuilder/Rendering/DeckRenderer.swift

import UIKit
import SwiftUI

struct DeckRenderer {

    /// Render the deck drawing to a PNG UIImage
    /// - Parameters:
    ///   - drawingData: The drawing data to render
    ///   - size: Output image size in points
    /// - Returns: Rendered UIImage
    static func renderToPNG(
        drawingData: DeckDrawingData,
        size: CGSize = CGSize(width: 1024, height: 1024)
    ) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let gc = ctx.cgContext

            // White background
            gc.setFillColor(UIColor.white.cgColor)
            gc.fill(CGRect(origin: .zero, size: size))

            // Calculate bounds to fit drawing in image
            let positions = drawingData.orderedPositions
            guard !positions.isEmpty else { return }

            let bounds = boundingRect(for: positions)
            let padding: CGFloat = 60
            let availableSize = CGSize(
                width: size.width - padding * 2,
                height: size.height - padding * 2
            )

            guard bounds.width > 0, bounds.height > 0 else { return }

            let scaleX = availableSize.width / bounds.width
            let scaleY = availableSize.height / bounds.height
            let fitScale = min(scaleX, scaleY)

            let offsetX = padding + (availableSize.width - bounds.width * fitScale) / 2 - bounds.origin.x * fitScale
            let offsetY = padding + (availableSize.height - bounds.height * fitScale) / 2 - bounds.origin.y * fitScale

            func transform(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * fitScale + offsetX, y: point.y * fitScale + offsetY)
            }

            // Draw footprint fill
            if drawingData.isClosed && positions.count >= 3 {
                gc.setFillColor(UIColor(red: 89/255, green: 119/255, blue: 148/255, alpha: 0.1).cgColor)
                gc.beginPath()
                gc.move(to: transform(positions[0]))
                for i in 1..<positions.count {
                    gc.addLine(to: transform(positions[i]))
                }
                gc.closePath()
                gc.fillPath()
            }

            // Draw edges
            gc.setStrokeColor(UIColor(red: 40/255, green: 40/255, blue: 40/255, alpha: 1).cgColor)
            gc.setLineWidth(2.0)
            for edge in drawingData.edges {
                guard let start = drawingData.vertex(byId: edge.startVertexId),
                      let end = drawingData.vertex(byId: edge.endVertexId) else { continue }
                let p1 = transform(start.position)
                let p2 = transform(end.position)
                gc.beginPath()
                gc.move(to: p1)
                gc.addLine(to: p2)
                gc.strokePath()

                // Draw dimension label at midpoint
                if let dim = edge.dimension {
                    let midX = (p1.x + p2.x) / 2
                    let midY = (p1.y + p2.y) / 2
                    let label = DimensionEngine.format(dim, system: drawingData.config.measurementSystem)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: UIColor(red: 89/255, green: 119/255, blue: 148/255, alpha: 1)
                    ]
                    let nsLabel = label as NSString
                    let labelSize = nsLabel.size(withAttributes: attrs)
                    nsLabel.draw(at: CGPoint(x: midX - labelSize.width / 2, y: midY - labelSize.height - 4), withAttributes: attrs)
                }

                // Draw railing indicator
                if edge.railingConfig != nil {
                    gc.setStrokeColor(UIColor(red: 89/255, green: 119/255, blue: 148/255, alpha: 0.6).cgColor)
                    gc.setLineWidth(4.0)
                    gc.beginPath()
                    gc.move(to: p1)
                    gc.addLine(to: p2)
                    gc.strokePath()
                    gc.setLineWidth(2.0)
                    gc.setStrokeColor(UIColor(red: 40/255, green: 40/255, blue: 40/255, alpha: 1).cgColor)
                }
            }

            // Draw vertices
            gc.setFillColor(UIColor(red: 89/255, green: 119/255, blue: 148/255, alpha: 1).cgColor)
            for vertex in drawingData.vertices {
                let p = transform(vertex.position)
                gc.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            }
        }
        return image
    }

    /// Save rendered image to S3 and return the URL
    static func saveToS3(
        image: UIImage,
        deckDesign: DeckDesign
    ) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw DeckRendererError.compressionFailed
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "deck_\(deckDesign.id)_\(timestamp).jpg"
        let folder = "deck_designs/\(deckDesign.companyId)"

        let publicUrl = try await PresignedURLUploadService.shared.uploadImageData(
            imageData,
            filename: filename,
            folder: folder
        )

        return publicUrl
    }

    // MARK: - Helpers

    private static func boundingRect(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    enum DeckRendererError: Error {
        case compressionFailed
        case uploadFailed
    }
}
