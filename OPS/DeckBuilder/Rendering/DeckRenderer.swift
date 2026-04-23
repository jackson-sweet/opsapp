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

            // Calculate bounds from all vertices (multi-level or single)
            let allPositions = drawingData.isMultiLevel
                ? drawingData.levels.flatMap { $0.orderedPositions }
                : drawingData.orderedPositions
            guard !allPositions.isEmpty else { return }

            let bounds = boundingRect(for: allPositions)
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

            if drawingData.isMultiLevel {
                // Multi-level: render each level
                for level in drawingData.levels {
                    let positions = level.orderedPositions
                    let c: (r: CGFloat, g: CGFloat, b: CGFloat) = {
                        if let hex = level.footprint.assignedItems.first?.taskTypeColor, !hex.isEmpty {
                            let uiColor = UIColor(hex: hex)
                            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                            uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)
                            return (r, g, b)
                        }
                        let lc = level.displayColor.fillColor
                        return (lc.r, lc.g, lc.b)
                    }()

                    // Footprint fill
                    if level.isClosed && positions.count >= 3 {
                        gc.setFillColor(UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.1).cgColor)
                        gc.beginPath()
                        gc.move(to: transform(positions[0]))
                        for i in 1..<positions.count { gc.addLine(to: transform(positions[i])) }
                        gc.closePath()
                        // Non-zero winding matches the visible boundary on concave polygons.
                    // Even-odd leaves holes in "crossing" regions of construction-mole shapes.
                    gc.fillPath(using: .winding)
                    }

                    // Edges
                    gc.setStrokeColor(UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.8).cgColor)
                    gc.setLineWidth(2.0)
                    for edge in level.edges {
                        guard let start = level.vertex(byId: edge.startVertexId),
                              let end = level.vertex(byId: edge.endVertexId) else { continue }
                        let p1 = transform(start.position)
                        let p2 = transform(end.position)
                        gc.beginPath(); gc.move(to: p1); gc.addLine(to: p2); gc.strokePath()

                        if let dim = edge.dimension {
                            let midX = (p1.x + p2.x) / 2
                            let midY = (p1.y + p2.y) / 2
                            let label = DimensionEngine.format(dim, system: drawingData.config.measurementSystem)
                            let attrs: [NSAttributedString.Key: Any] = [
                                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                                .foregroundColor: UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
                            ]
                            (label as NSString).draw(
                                at: CGPoint(x: midX - (label as NSString).size(withAttributes: attrs).width / 2,
                                            y: midY - (label as NSString).size(withAttributes: attrs).height - 4),
                                withAttributes: attrs
                            )
                        }
                    }

                    // Vertices
                    gc.setFillColor(UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1).cgColor)
                    for vertex in level.vertices {
                        let p = transform(vertex.position)
                        gc.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                    }

                    // Level name label at centroid
                    if positions.count >= 3 {
                        let cx = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
                        let cy = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
                        let tp = transform(CGPoint(x: cx, y: cy))
                        let nameAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                            .foregroundColor: UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.8)
                        ]
                        let nsName = level.name as NSString
                        let nameSize = nsName.size(withAttributes: nameAttrs)
                        nsName.draw(at: CGPoint(x: tp.x - nameSize.width / 2, y: tp.y - nameSize.height / 2), withAttributes: nameAttrs)
                    }
                }

                // Render level connections (stairs between levels)
                for connection in drawingData.levelConnections {
                    renderConnectionStairs(gc: gc, connection: connection, drawingData: drawingData, transform: transform)
                }
            } else {
                // Single-level rendering (existing behavior)
                let positions = drawingData.orderedPositions
                let singleLevelColor: UIColor = {
                    if let hex = drawingData.footprint.assignedItems.first?.taskTypeColor,
                       !hex.isEmpty { return UIColor(hex: hex) }
                    return UIColor(red: 89/255, green: 119/255, blue: 148/255, alpha: 1)
                }()
                if drawingData.isClosed && positions.count >= 3 {
                    gc.setFillColor(singleLevelColor.withAlphaComponent(0.1).cgColor)
                    gc.beginPath()
                    gc.move(to: transform(positions[0]))
                    for i in 1..<positions.count { gc.addLine(to: transform(positions[i])) }
                    gc.closePath()
                    // Non-zero winding matches the visible boundary on concave polygons.
                    // Even-odd leaves holes in "crossing" regions of construction-mole shapes.
                    gc.fillPath(using: .winding)
                }

                gc.setLineWidth(2.0)
                for edge in drawingData.edges {
                    guard let start = drawingData.vertex(byId: edge.startVertexId),
                          let end = drawingData.vertex(byId: edge.endVertexId) else { continue }
                    let p1 = transform(start.position)
                    let p2 = transform(end.position)

                    // Edge color: task type color from assigned items, or railing items, or default
                    let edgeColor: UIColor = {
                        if let hex = edge.assignedItems.first?.taskTypeColor, !hex.isEmpty { return UIColor(hex: hex) }
                        if let hex = edge.railingConfig?.assignedItems.first?.taskTypeColor, !hex.isEmpty { return UIColor(hex: hex) }
                        return UIColor(red: 40/255, green: 40/255, blue: 40/255, alpha: 1)
                    }()

                    gc.setStrokeColor(edgeColor.cgColor)
                    gc.beginPath(); gc.move(to: p1); gc.addLine(to: p2); gc.strokePath()

                    if let dim = edge.dimension {
                        let midX = (p1.x + p2.x) / 2
                        let midY = (p1.y + p2.y) / 2
                        let label = DimensionEngine.format(dim, system: drawingData.config.measurementSystem)
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                            .foregroundColor: singleLevelColor
                        ]
                        let nsLabel = label as NSString
                        let labelSize = nsLabel.size(withAttributes: attrs)
                        nsLabel.draw(at: CGPoint(x: midX - labelSize.width / 2, y: midY - labelSize.height - 4), withAttributes: attrs)
                    }

                    if edge.railingConfig != nil {
                        let railColor: UIColor = {
                            if let hex = edge.railingConfig?.assignedItems.first?.taskTypeColor, !hex.isEmpty { return UIColor(hex: hex) }
                            return singleLevelColor
                        }()
                        gc.setStrokeColor(railColor.withAlphaComponent(0.6).cgColor)
                        gc.setLineWidth(4.0)
                        gc.beginPath(); gc.move(to: p1); gc.addLine(to: p2); gc.strokePath()
                        gc.setLineWidth(2.0)
                    }
                }

                gc.setFillColor(singleLevelColor.cgColor)
                for vertex in drawingData.vertices {
                    let p = transform(vertex.position)
                    gc.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                }
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

    // MARK: - Connection Stair Rendering

    private static func renderConnectionStairs(
        gc: CGContext,
        connection: LevelConnection,
        drawingData: DeckDrawingData,
        transform: (CGPoint) -> CGPoint
    ) {
        guard let upperLevel = drawingData.level(byId: connection.upperLevelId),
              let edge = upperLevel.edge(byId: connection.upperEdgeId),
              let start = upperLevel.vertex(byId: edge.startVertexId),
              let end = upperLevel.vertex(byId: edge.endVertexId) else { return }

        let p1 = transform(start.position)
        let p2 = transform(end.position)
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let edgeLength = sqrt(dx * dx + dy * dy)
        guard edgeLength > 0 else { return }

        let perpX = -dy / edgeLength
        let perpY = dx / edgeLength
        let stairDepth: CGFloat = 20.0

        let p3 = CGPoint(x: p2.x + perpX * stairDepth, y: p2.y + perpY * stairDepth)
        let p4 = CGPoint(x: p1.x + perpX * stairDepth, y: p1.y + perpY * stairDepth)

        let amberColor = UIColor(red: 196/255, green: 168/255, blue: 104/255, alpha: 1)

        // Hatched fill
        gc.setFillColor(amberColor.withAlphaComponent(0.15).cgColor)
        gc.beginPath()
        gc.move(to: p1); gc.addLine(to: p2); gc.addLine(to: p3); gc.addLine(to: p4)
        gc.closePath()
        gc.fillPath()

        // Outline
        gc.setStrokeColor(amberColor.withAlphaComponent(0.6).cgColor)
        gc.setLineWidth(1.5)
        gc.beginPath()
        gc.move(to: p1); gc.addLine(to: p2); gc.addLine(to: p3); gc.addLine(to: p4)
        gc.closePath()
        gc.strokePath()

        // Hatch lines
        let treadCount = connection.stairConfig.treadCount ?? 5
        gc.setStrokeColor(amberColor.withAlphaComponent(0.4).cgColor)
        gc.setLineWidth(1.0)
        for i in 1..<min(treadCount, 20) {
            let t = CGFloat(i) / CGFloat(treadCount)
            let ls = CGPoint(x: p1.x + dx * t, y: p1.y + dy * t)
            let le = CGPoint(x: ls.x + perpX * stairDepth, y: ls.y + perpY * stairDepth)
            gc.beginPath(); gc.move(to: ls); gc.addLine(to: le); gc.strokePath()
        }

        // Tread count label
        let labelX = (p1.x + p3.x) / 2
        let labelY = (p1.y + p3.y) / 2
        let label = "\(treadCount) treads" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: amberColor
        ]
        let labelSize = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: labelX - labelSize.width / 2, y: labelY - labelSize.height / 2), withAttributes: attrs)
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
