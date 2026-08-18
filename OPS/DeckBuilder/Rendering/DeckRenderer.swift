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
                        let stairPlan = renderEdgeStairs(
                                gc: gc,
                                p1: p1,
                                p2: p2,
                                edge: edge,
                                polygonInTransformed: drawingData.stairFacePolygon(forEdgeId: edge.id).map(transform),
                                scaleFactor: drawingData.effectiveScaleFactor * Double(fitScale),
                                measurementSystem: drawingData.config.measurementSystem,
                                markerColor: UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
                        )

                        if let dim = edge.dimension {
                            drawExportEdgeDimension(
                                gc: gc,
                                dimensionInches: dim,
                                measurementSystem: drawingData.config.measurementSystem,
                                color: UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1),
                                p1: p1,
                                p2: p2,
                                stairPlan: stairPlan
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
                    renderConnectionStairs(
                        gc: gc,
                        connection: connection,
                        drawingData: drawingData,
                        transform: transform,
                        scaleFactor: drawingData.effectiveScaleFactor * Double(fitScale)
                    )
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
                    let stairPlan = renderEdgeStairs(
                            gc: gc,
                            p1: p1,
                            p2: p2,
                            edge: edge,
                            polygonInTransformed: drawingData.stairFacePolygon(forEdgeId: edge.id).map(transform),
                            scaleFactor: drawingData.effectiveScaleFactor * Double(fitScale),
                            measurementSystem: drawingData.config.measurementSystem,
                            markerColor: edgeColor
                    )

                    if let dim = edge.dimension {
                        drawExportEdgeDimension(
                            gc: gc,
                            dimensionInches: dim,
                            measurementSystem: drawingData.config.measurementSystem,
                            color: singleLevelColor,
                            p1: p1,
                            p2: p2,
                            stairPlan: stairPlan
                        )
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
    /// space as p1/p2. `scaleFactor` is canvas-points-per-inch in that same
    /// transformed share-image space.
    @discardableResult
    private static func renderEdgeStairs(
        gc: CGContext,
        p1: CGPoint,
        p2: CGPoint,
        edge: DeckEdge,
        polygonInTransformed: [CGPoint],
        scaleFactor: Double,
        measurementSystem: MeasurementSystem,
        markerColor: UIColor
    ) -> DeckStairRenderPlan? {
        guard let config = edge.stairConfig,
              let treadCount = config.treadCount,
              treadCount > 0,
              let plan = DeckStairRenderPlanner.plan(
                edgeStart: p1,
                edgeEnd: p2,
                polygonVertices: polygonInTransformed,
                config: config,
                treadCount: treadCount,
                scaleFactor: scaleFactor,
                measurementSystem: measurementSystem,
                edgeDimensionInches: edge.dimension
              ) else { return nil }

        let amber = UIColor(OPSStyle.Colors.tan)

        // Outline rect
        gc.setFillColor(amber.withAlphaComponent(0.12).cgColor)
        gc.beginPath()
        gc.move(to: plan.baseStart)
        gc.addLine(to: plan.baseEnd)
        gc.addLine(to: plan.farEnd)
        gc.addLine(to: plan.farStart)
        gc.closePath()
        gc.fillPath()
        gc.setStrokeColor(amber.withAlphaComponent(0.6).cgColor)
        gc.setLineWidth(1.5)
        gc.beginPath()
        gc.move(to: plan.baseStart)
        gc.addLine(to: plan.baseEnd)
        gc.addLine(to: plan.farEnd)
        gc.addLine(to: plan.farStart)
        gc.closePath()
        gc.strokePath()

        // Tread lines
        gc.setStrokeColor(amber.withAlphaComponent(0.4).cgColor)
        gc.setLineWidth(1.0)
        for tread in plan.treadLines {
            gc.beginPath()
            gc.move(to: tread.start)
            gc.addLine(to: tread.end)
            gc.strokePath()
        }

        let isPartial = !plan.boundaryMarkers.isEmpty
        if isPartial {
            for marker in plan.boundaryMarkers {
                drawExportStairBoundaryMarker(gc: gc, at: marker, color: markerColor)
            }
            for label in plan.dimensionLabels where label.kind == .width {
                drawExportStairDimensionChip(
                    gc: gc,
                    label: label,
                    at: plan.edgeLabelPosition(for: label, zoomScale: 1)
                )
            }
            for label in plan.adjacentEdgeLabels {
                drawExportStairDimensionChip(
                    gc: gc,
                    label: label,
                    at: plan.edgeLabelPosition(for: label, zoomScale: 1)
                )
            }
        }

        gc.setLineWidth(2.0)
        return plan
    }

    private static func drawExportEdgeDimension(
        gc: CGContext,
        dimensionInches: Double,
        measurementSystem: MeasurementSystem,
        color: UIColor,
        p1: CGPoint,
        p2: CGPoint,
        stairPlan: DeckStairRenderPlan?
    ) {
        let label = DimensionEngine.format(dimensionInches, system: measurementSystem) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: OPSStyle.Typography.uiDataValueMedium(),
            .foregroundColor: color,
        ]
        let labelSize = label.size(withAttributes: attributes)
        let midpoint = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        let origin: CGPoint

        if let stairPlan,
           !stairPlan.boundaryMarkers.isEmpty,
           let stairNormal = stairPlan.stairNormal {
            let offset = CGFloat(OPSStyle.Layout.spacing3_5)
            let center = CGPoint(
                x: midpoint.x - stairNormal.dx * offset,
                y: midpoint.y - stairNormal.dy * offset
            )
            origin = CGPoint(
                x: center.x - labelSize.width / 2,
                y: center.y - labelSize.height / 2
            )
        } else {
            origin = CGPoint(
                x: midpoint.x - labelSize.width / 2,
                y: midpoint.y - labelSize.height - CGFloat(OPSStyle.Layout.spacing1)
            )
        }

        label.draw(at: origin, withAttributes: attributes)
    }

    private static func drawExportStairBoundaryMarker(
        gc: CGContext,
        at point: CGPoint,
        color: UIColor
    ) {
        let radius = CGFloat(OPSStyle.Layout.spacing1) + OPSStyle.Layout.Border.standard
        gc.saveGState()
        let marker = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        gc.setFillColor(UIColor(OPSStyle.Colors.Light.background).cgColor)
        gc.fillEllipse(in: marker)
        gc.setStrokeColor(color.cgColor)
        gc.setLineWidth(OPSStyle.Layout.Border.standard)
        gc.strokeEllipse(in: marker)
        gc.restoreGState()
    }

    private static func drawExportStairDimensionChip(
        gc: CGContext,
        label: DeckStairDimensionLabel,
        at position: CGPoint
    ) {
        let text = label.text as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: OPSStyle.Typography.uiDataValueMedium(),
            .foregroundColor: UIColor(OPSStyle.Colors.text),
        ]
        let textSize = text.size(withAttributes: attributes)
        let horizontalPadding = CGFloat(OPSStyle.Layout.spacing1)
        let verticalPadding = CGFloat(OPSStyle.Layout.spacing1) / 2
        let background = CGRect(
            x: position.x - textSize.width / 2 - horizontalPadding,
            y: position.y - textSize.height / 2 - verticalPadding,
            width: textSize.width + horizontalPadding * 2,
            height: textSize.height + verticalPadding * 2
        )
        let path = UIBezierPath(
            roundedRect: background,
            cornerRadius: CGFloat(OPSStyle.Layout.chipRadius)
        ).cgPath

        gc.saveGState()
        gc.addPath(path)
        gc.setFillColor(UIColor(OPSStyle.Colors.glassDenseApprox).cgColor)
        gc.fillPath()
        gc.addPath(path)
        gc.setStrokeColor(UIColor(OPSStyle.Colors.line).cgColor)
        gc.setLineWidth(OPSStyle.Layout.Border.standard)
        gc.strokePath()
        text.draw(
            at: CGPoint(
                x: position.x - textSize.width / 2,
                y: position.y - textSize.height / 2
            ),
            withAttributes: attributes
        )
        gc.restoreGState()
    }

    // MARK: - Connection Stair Rendering

    /// Connection stairs in the export image resolve through the same shared
    /// plan as the editor canvas and the 3D scene (bug 4a773e11). This used to
    /// hand-roll a raw-winding perpendicular, a fixed 20pt depth, a hardcoded
    /// 5-tread fallback and lines running along the direction of travel — four
    /// separate ways to disagree with what the user was looking at.
    private static func renderConnectionStairs(
        gc: CGContext,
        connection: LevelConnection,
        drawingData: DeckDrawingData,
        transform: (CGPoint) -> CGPoint,
        scaleFactor: Double
    ) {
        guard let plan = drawingData.connectionStairPlan(
            for: connection,
            transform: transform,
            scaleFactor: scaleFactor
        ) else { return }

        let stairColor = UIColor(OPSStyle.Colors.tan)

        gc.setFillColor(stairColor.withAlphaComponent(0.15).cgColor)
        gc.beginPath()
        gc.move(to: plan.baseStart)
        gc.addLine(to: plan.baseEnd)
        gc.addLine(to: plan.farEnd)
        gc.addLine(to: plan.farStart)
        gc.closePath()
        gc.fillPath()

        gc.setStrokeColor(stairColor.withAlphaComponent(0.6).cgColor)
        gc.setLineWidth(OPSStyle.Layout.Border.thick)
        gc.beginPath()
        gc.move(to: plan.baseStart)
        gc.addLine(to: plan.baseEnd)
        gc.addLine(to: plan.farEnd)
        gc.addLine(to: plan.farStart)
        gc.closePath()
        gc.strokePath()

        gc.setStrokeColor(stairColor.withAlphaComponent(0.4).cgColor)
        gc.setLineWidth(OPSStyle.Layout.Border.standard)
        for tread in plan.treadLines {
            gc.beginPath()
            gc.move(to: tread.start)
            gc.addLine(to: tread.end)
            gc.strokePath()
        }

        let railInfo = drawingData.stairRailInfo(for: connection)
        let labelText: String
        if let railInfo {
            labelText = "\(railInfo.treadCount) treads · \(DimensionEngine.format(railInfo.railRunInches, system: drawingData.config.measurementSystem)) rail"
        } else {
            labelText = "\(plan.treadCount) treads"
        }
        let label = labelText as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: OPSStyle.Typography.uiDataValueMedium(),
            .foregroundColor: stairColor
        ]
        let labelSize = label.size(withAttributes: attrs)
        let anchor = plan.summaryLabelPosition(zoomScale: 1)
        label.draw(
            at: CGPoint(x: anchor.x - labelSize.width / 2, y: anchor.y - labelSize.height / 2),
            withAttributes: attrs
        )
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
