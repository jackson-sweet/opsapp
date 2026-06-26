// OPS/OPS/DeckBuilder/Rendering/DeckRenderer.swift

import UIKit
import DeckKit
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

                        // Bug 3d72ce0b — house edges render thicker with the
                        // selected cladding tone so they read as a wall.
                        if edge.edgeType == .houseEdge {
                            let wallColor: UIColor = {
                                if let mat = edge.houseEdgeMaterial { return UIColor(hex: mat.fillHex) }
                                return UIColor(white: 0.7, alpha: 1)
                            }()
                            gc.setStrokeColor(wallColor.cgColor)
                            gc.setLineWidth(4.0)
                            gc.beginPath(); gc.move(to: p1); gc.addLine(to: p2); gc.strokePath()
                            // Restore for the next edge
                            gc.setStrokeColor(UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.8).cgColor)
                            gc.setLineWidth(2.0)
                        } else {
                            gc.beginPath(); gc.move(to: p1); gc.addLine(to: p2); gc.strokePath()
                        }

                        // Render edge-attached stairs (bug 3d72ce0b)
                        if let config = edge.stairConfig, let tc = config.treadCount, tc > 0 {
                            renderEdgeStairs(
                                gc: gc,
                                p1: p1, p2: p2,
                                config: config,
                                treadCount: tc,
                                polygonInTransformed: level.orderedPositions.map(transform),
                                scaleFactor: drawingData.scaleFactor.map { $0 * Double(fitScale) }
                            )
                        }

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

                    // Edge color: house edge cladding (bug 3d72ce0b) → task type color → railing color → default.
                    let edgeColor: UIColor = {
                        if edge.edgeType == .houseEdge {
                            if let mat = edge.houseEdgeMaterial { return UIColor(hex: mat.fillHex) }
                            return UIColor(white: 0.7, alpha: 1)
                        }
                        if let hex = edge.assignedItems.first?.taskTypeColor, !hex.isEmpty { return UIColor(hex: hex) }
                        if let hex = edge.railingConfig?.assignedItems.first?.taskTypeColor, !hex.isEmpty { return UIColor(hex: hex) }
                        return UIColor(red: 40/255, green: 40/255, blue: 40/255, alpha: 1)
                    }()

                    // House edges render thicker so they read as a raised wall.
                    let prevWidth: CGFloat = 2.0
                    if edge.edgeType == .houseEdge {
                        gc.setLineWidth(4.0)
                    }
                    gc.setStrokeColor(edgeColor.cgColor)
                    gc.beginPath(); gc.move(to: p1); gc.addLine(to: p2); gc.strokePath()
                    if edge.edgeType == .houseEdge {
                        gc.setLineWidth(prevWidth)
                    }

                    // Bug 3d72ce0b — render stairs on edges (not just level
                    // connections). Mirror the builder logic so shares match.
                    if let config = edge.stairConfig, let tc = config.treadCount, tc > 0 {
                        renderEdgeStairs(
                            gc: gc,
                            p1: p1,
                            p2: p2,
                            config: config,
                            treadCount: tc,
                            polygonInTransformed: drawingData.orderedPositions.map(transform),
                            scaleFactor: drawingData.scaleFactor.map { $0 * Double(fitScale) }
                        )
                    }

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

    // MARK: - Edge Stair Rendering (bug 3d72ce0b)

    /// Render stairs that live on a single edge (not a level connection) into
    /// the share-image context. Mirrors `DeckCanvasView.drawStairIndicator` so
    /// the exported PNG matches what the user sees in the builder.
    /// `polygonInTransformed` is the surrounding polygon in TRANSFORMED canvas
    /// coordinates so the outward-perpendicular probe makes sense in the same
    /// space as p1/p2. `scaleFactor` here is canvas-points-per-inch in the
    /// transformed (share-image) space — pass nil if the drawing has no scale,
    /// in which case stairs will be sized using a sane default.
    private static func renderEdgeStairs(
        gc: CGContext,
        p1: CGPoint,
        p2: CGPoint,
        config: StairConfig,
        treadCount: Int,
        polygonInTransformed: [CGPoint],
        scaleFactor: Double?
    ) {
        let dx = p2.x - p1.x, dy = p2.y - p1.y
        let edgeLen = sqrt(dx * dx + dy * dy)
        guard edgeLen > 0 else { return }
        let edgeNx = dx / edgeLen, edgeNy = dy / edgeLen

        let outward = PolygonMath.outwardPerpendicular(
            edgeStart: p1,
            edgeEnd: p2,
            polygonVertices: polygonInTransformed
        )
        let perpX = config.flipDirection ? -outward.x : outward.x
        let perpY = config.flipDirection ? -outward.y : outward.y

        // Convert real-world dimensions to render-canvas points. Without a
        // scale we fall back to "stair width spans 60% of edge, depth = width".
        let stairWidthPts: CGFloat
        let stairDepthPts: CGFloat
        if let scale = scaleFactor, scale > 0 {
            stairWidthPts = min(CGFloat(config.width * scale), edgeLen)
            let totalRunInches = Double(treadCount) * config.runPerTread
            stairDepthPts = CGFloat(totalRunInches * scale)
        } else {
            stairWidthPts = edgeLen * 0.6
            stairDepthPts = stairWidthPts * 0.5
        }

        let offsetCanvas: CGFloat = scaleFactor.map { CGFloat(config.offset * $0) } ?? 0
        let gapTotal = edgeLen - stairWidthPts
        let stairStartT: CGFloat
        switch config.alignment {
        case .left:   stairStartT = offsetCanvas / edgeLen
        case .center: stairStartT = (gapTotal / 2 + offsetCanvas) / edgeLen
        case .right:  stairStartT = (gapTotal - offsetCanvas) / edgeLen
        }

        let perpCGX = CGFloat(perpX), perpCGY = CGFloat(perpY)
        let baseStart = CGPoint(
            x: p1.x + edgeNx * edgeLen * stairStartT,
            y: p1.y + edgeNy * edgeLen * stairStartT
        )
        let baseEnd = CGPoint(
            x: baseStart.x + edgeNx * stairWidthPts,
            y: baseStart.y + edgeNy * stairWidthPts
        )
        let farStart = CGPoint(
            x: baseStart.x + perpCGX * stairDepthPts,
            y: baseStart.y + perpCGY * stairDepthPts
        )
        let farEnd = CGPoint(
            x: baseEnd.x + perpCGX * stairDepthPts,
            y: baseEnd.y + perpCGY * stairDepthPts
        )

        let amber = UIColor(red: 196/255, green: 168/255, blue: 104/255, alpha: 1)

        // Outline rect
        gc.setFillColor(amber.withAlphaComponent(0.12).cgColor)
        gc.beginPath()
        gc.move(to: baseStart)
        gc.addLine(to: baseEnd)
        gc.addLine(to: farEnd)
        gc.addLine(to: farStart)
        gc.closePath()
        gc.fillPath()
        gc.setStrokeColor(amber.withAlphaComponent(0.6).cgColor)
        gc.setLineWidth(1.5)
        gc.beginPath()
        gc.move(to: baseStart)
        gc.addLine(to: baseEnd)
        gc.addLine(to: farEnd)
        gc.addLine(to: farStart)
        gc.closePath()
        gc.strokePath()

        // Tread lines
        gc.setStrokeColor(amber.withAlphaComponent(0.4).cgColor)
        gc.setLineWidth(1.0)
        for i in 1..<min(treadCount, 30) {
            let t = CGFloat(i) / CGFloat(treadCount)
            let tb = CGPoint(
                x: baseStart.x + perpCGX * stairDepthPts * t,
                y: baseStart.y + perpCGY * stairDepthPts * t
            )
            let te = CGPoint(
                x: baseEnd.x + perpCGX * stairDepthPts * t,
                y: baseEnd.y + perpCGY * stairDepthPts * t
            )
            gc.beginPath(); gc.move(to: tb); gc.addLine(to: te); gc.strokePath()
        }

        gc.setLineWidth(2.0)
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
