// OPS/OPS/DeckBuilder/Rendering/DeckOverlayRenderer.swift

import UIKit

struct DeckOverlayRenderer {

    /// Ratio of overlay width to container width — shared between editor display and compositor
    static let overlayWidthRatio: CGFloat = 0.6

    // MARK: - Railing Type Colors

    private static func railingColor(for type: RailingType) -> UIColor {
        switch type {
        case .parapetWall: return UIColor(hex: HouseEdgeMaterial.parapet.fillHex)
        case .glass:      return UIColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1)
        case .picket:     return UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1)
        case .cable:      return UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        case .horizontal: return UIColor(red: 0.6, green: 0.5, blue: 0.3, alpha: 1)
        case .wood:       return UIColor(red: 0.5, green: 0.35, blue: 0.2, alpha: 1)
        }
    }

    // MARK: - Dimension Label Attributes

    private static func dimensionLabelAttributes(fontSize: CGFloat = 14) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowOffset = CGSize(width: 1, height: 1)
        shadow.shadowBlurRadius = 2
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)

        return [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white,
            .shadow: shadow
        ]
    }

    // MARK: - Render Overlay

    /// Renders the deck drawing as a transparent UIImage for overlay compositing.
    /// - Parameters:
    ///   - drawingData: The deck drawing data
    ///   - fillOpacity: Fill opacity for the footprint (0.1 to 0.8)
    ///   - size: Output image size in points
    /// - Returns: Transparent UIImage with the deck overlay
    static func renderOverlay(
        drawingData: DeckDrawingData,
        fillOpacity: Double,
        size: CGSize = CGSize(width: 1000, height: 1000)
    ) -> UIImage? {
        let allPositions = drawingData.isMultiLevel
            ? drawingData.levels.flatMap { $0.orderedPositions }
            : drawingData.orderedPositions
        guard !allPositions.isEmpty else { return nil }

        let bounds = boundingRect(for: allPositions)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let padding: CGFloat = 80
        let availableSize = CGSize(
            width: size.width - padding * 2,
            height: size.height - padding * 2
        )

        let scaleX = availableSize.width / bounds.width
        let scaleY = availableSize.height / bounds.height
        let fitScale = min(scaleX, scaleY)

        let offsetX = padding + (availableSize.width - bounds.width * fitScale) / 2 - bounds.origin.x * fitScale
        let offsetY = padding + (availableSize.height - bounds.height * fitScale) / 2 - bounds.origin.y * fitScale

        func transform(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * fitScale + offsetX, y: point.y * fitScale + offsetY)
        }

        // Helper to render one level's overlay
        func renderLevelOverlay(gc: CGContext, vertices: [DeckVertex], edges: [DeckEdge], positions: [CGPoint], isClosed: Bool, fillColor: UIColor) {
            // Footprint fill
            if isClosed && positions.count >= 3 {
                gc.setFillColor(fillColor.cgColor)
                gc.beginPath()
                gc.move(to: transform(positions[0]))
                for i in 1..<positions.count { gc.addLine(to: transform(positions[i])) }
                gc.closePath()
                gc.fillPath()
            }

            // Edges
            for edge in edges {
                guard let start = vertices.first(where: { $0.id == edge.startVertexId }),
                      let end = vertices.first(where: { $0.id == edge.endVertexId }) else { continue }
                let p1 = transform(start.position)
                let p2 = transform(end.position)

                if edge.edgeType == .houseEdge {
                    gc.setStrokeColor(UIColor.white.cgColor)
                    gc.setLineWidth(2.0)
                    gc.setLineDash(phase: 0, lengths: [8, 4])
                    gc.beginPath(); gc.move(to: p1); gc.addLine(to: p2); gc.strokePath()
                    gc.setLineDash(phase: 0, lengths: [])
                    continue
                }

                if let railingConfig = edge.railingConfig {
                    let railColor: UIColor = {
                        if let hex = railingConfig.assignedItems.first?.taskTypeColor,
                           !hex.isEmpty { return UIColor(hex: hex) }
                        return railingColor(for: railingConfig.railingType)
                    }()
                    gc.setStrokeColor(railColor.cgColor)
                    gc.setLineWidth(4.0)
                    gc.beginPath(); gc.move(to: p1); gc.addLine(to: p2); gc.strokePath()
                }

                if edge.stairConfig != nil {
                    drawStairIndicator(
                        gc: gc,
                        edge: edge,
                        start: start.position,
                        end: end.position,
                        drawingData: drawingData,
                        transform: transform,
                        scaleFactor: drawingData.effectiveScaleFactor * Double(fitScale)
                    )
                }

                gc.setStrokeColor(UIColor.white.cgColor)
                gc.setLineWidth(2.0)
                gc.beginPath(); gc.move(to: p1); gc.addLine(to: p2); gc.strokePath()

                if let dim = edge.dimension {
                    let midX = (p1.x + p2.x) / 2
                    let midY = (p1.y + p2.y) / 2
                    let label = DimensionEngine.format(dim, system: drawingData.config.measurementSystem)
                    let attrs = dimensionLabelAttributes()
                    let nsLabel = label as NSString
                    let labelSize = nsLabel.size(withAttributes: attrs)
                    nsLabel.draw(at: CGPoint(x: midX - labelSize.width / 2, y: midY - labelSize.height - 6), withAttributes: attrs)
                }
            }
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let gc = ctx.cgContext

            if drawingData.isMultiLevel {
                for level in drawingData.levels {
                    let fill: UIColor = {
                        if let hex = level.footprint.assignedItems.first?.taskTypeColor,
                           !hex.isEmpty { return UIColor(hex: hex).withAlphaComponent(CGFloat(fillOpacity)) }
                        let c = level.displayColor.fillColor
                        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: CGFloat(fillOpacity))
                    }()
                    renderLevelOverlay(gc: gc, vertices: level.vertices, edges: level.edges,
                                       positions: level.orderedPositions, isClosed: level.isClosed, fillColor: fill)

                    // Level name label
                    let positions = level.orderedPositions
                    if positions.count >= 3 {
                        let centroid = polygonCentroid(for: positions)
                        let tc = transform(centroid)
                        let attrs = dimensionLabelAttributes(fontSize: 16)
                        let nsName = level.name as NSString
                        let nameSize = nsName.size(withAttributes: attrs)
                        nsName.draw(at: CGPoint(x: tc.x - nameSize.width / 2, y: tc.y - nameSize.height / 2), withAttributes: attrs)
                    }
                }

                // Render level connections
                for connection in drawingData.levelConnections {
                    Self.renderConnectionStairs(
                        gc: gc,
                        connection: connection,
                        drawingData: drawingData,
                        transform: transform,
                        scaleFactor: drawingData.effectiveScaleFactor * Double(fitScale)
                    )
                }
            } else {
                let positions = drawingData.orderedPositions
                let fill: UIColor = {
                    if let hex = drawingData.footprint.assignedItems.first?.taskTypeColor,
                       !hex.isEmpty { return UIColor(hex: hex).withAlphaComponent(CGFloat(fillOpacity)) }
                    return UIColor(red: 89/255, green: 119/255, blue: 148/255, alpha: CGFloat(fillOpacity))
                }()
                renderLevelOverlay(gc: gc, vertices: drawingData.vertices, edges: drawingData.edges,
                                   positions: positions, isClosed: drawingData.isClosed, fillColor: fill)

                // Area label centered in footprint
                if drawingData.isClosed, let scale = drawingData.scaleFactor, scale > 0 {
                    let areaSqInches = PolygonMath.realWorldArea(vertices: positions, scaleFactor: scale)
                    let areaLabel = DimensionEngine.formatArea(areaSqInches, system: drawingData.config.measurementSystem)
                    let centroid = polygonCentroid(for: positions)
                    let tc = transform(centroid)
                    let attrs = dimensionLabelAttributes(fontSize: 18)
                    let nsLabel = areaLabel as NSString
                    let labelSize = nsLabel.size(withAttributes: attrs)
                    nsLabel.draw(at: CGPoint(x: tc.x - labelSize.width / 2, y: tc.y - labelSize.height / 2), withAttributes: attrs)
                }
            }
        }

        return image
    }

    // MARK: - Composite Overlay on Photo

    /// Composites the deck overlay on top of a site photo with position/scale/rotation transforms.
    /// - Parameters:
    ///   - photo: The base site photo
    ///   - overlay: The pre-rendered transparent deck overlay
    ///   - offset: Overlay offset in screen points
    ///   - scale: Overlay scale factor
    ///   - rotation: Overlay rotation angle
    ///   - displaySize: The size the photo was displayed at on screen (for coordinate scaling)
    /// - Returns: Composited image at the photo's original resolution
    static func compositeOverlayOnPhoto(
        photo: UIImage,
        overlay: UIImage,
        offset: CGSize,
        scale: CGFloat,
        rotation: Angle,
        displaySize: CGSize
    ) -> UIImage {
        let photoSize = photo.size
        let renderer = UIGraphicsImageRenderer(size: photoSize)

        return renderer.image { ctx in
            let gc = ctx.cgContext

            // Draw photo as base layer
            photo.draw(in: CGRect(origin: .zero, size: photoSize))

            // Scale from screen coordinates to photo-resolution coordinates
            let coordScale: CGFloat
            if displaySize.width > 0 {
                coordScale = photoSize.width / displaySize.width
            } else {
                coordScale = 1.0
            }

            // Calculate overlay display size in photo coordinates
            // The overlay was displayed at a size proportional to the display area
            let overlayDisplayWidth = displaySize.width * overlayWidthRatio
            let overlayDisplayHeight = overlayDisplayWidth * (overlay.size.height / overlay.size.width)
            let overlayPhotoWidth = overlayDisplayWidth * coordScale
            let overlayPhotoHeight = overlayDisplayHeight * coordScale

            // Center position in photo coordinates
            let centerX = photoSize.width / 2 + offset.width * coordScale
            let centerY = photoSize.height / 2 + offset.height * coordScale

            // Apply transform: translate to center, rotate, scale
            gc.saveGState()
            gc.translateBy(x: centerX, y: centerY)
            gc.rotate(by: CGFloat(rotation.radians))
            gc.scaleBy(x: scale, y: scale)

            // Draw overlay centered at origin (which is now the translated center)
            let drawRect = CGRect(
                x: -overlayPhotoWidth / 2,
                y: -overlayPhotoHeight / 2,
                width: overlayPhotoWidth,
                height: overlayPhotoHeight
            )
            overlay.draw(in: drawRect)

            gc.restoreGState()
        }
    }

    // MARK: - Connection Stair Rendering

    /// Connection stairs resolve through the shared plan (bug 4a773e11) so this
    /// image shows the same stair, on the same side, at the same run depth as
    /// the editor canvas and the 3D scene.
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

        gc.setFillColor(stairColor.withAlphaComponent(0.2).cgColor)
        gc.beginPath()
        gc.move(to: plan.baseStart)
        gc.addLine(to: plan.baseEnd)
        gc.addLine(to: plan.farEnd)
        gc.addLine(to: plan.farStart)
        gc.closePath()
        gc.fillPath()

        gc.setStrokeColor(stairColor.withAlphaComponent(0.7).cgColor)
        gc.setLineWidth(OPSStyle.Layout.Border.thick)
        gc.beginPath()
        gc.move(to: plan.baseStart)
        gc.addLine(to: plan.baseEnd)
        gc.addLine(to: plan.farEnd)
        gc.addLine(to: plan.farStart)
        gc.closePath()
        gc.strokePath()

        gc.setStrokeColor(stairColor.withAlphaComponent(0.5).cgColor)
        gc.setLineWidth(OPSStyle.Layout.Border.standard)
        for tread in plan.treadLines {
            gc.beginPath()
            gc.move(to: tread.start)
            gc.addLine(to: tread.end)
            gc.strokePath()
        }

        let railInfo = drawingData.stairRailInfo(for: connection)
        let labelText = railInfo.map {
            "\($0.treadCount) treads · \(DimensionEngine.format($0.railRunInches, system: drawingData.config.measurementSystem)) rail"
        } ?? "\(plan.treadCount) treads"
        let label = labelText as NSString
        let attrs = dimensionLabelAttributes(fontSize: 12)
        let labelSize = label.size(withAttributes: attrs)
        let anchor = plan.summaryLabelPosition(zoomScale: 1)
        label.draw(
            at: CGPoint(x: anchor.x - labelSize.width / 2, y: anchor.y - labelSize.height / 2),
            withAttributes: attrs
        )
    }

    // MARK: - Stair Indicator

    /// Edge-attached stairs on the photo overlay draw from the shared plan too
    /// (bug 4a773e11). The old symbol straddled the edge with four evenly
    /// spaced rungs, so it showed that a stair existed but never which side it
    /// descended to — and its rung count had nothing to do with the stair.
    private static func drawStairIndicator(
        gc: CGContext,
        edge: DeckEdge,
        start: CGPoint,
        end: CGPoint,
        drawingData: DeckDrawingData,
        transform: (CGPoint) -> CGPoint,
        scaleFactor: Double
    ) {
        guard let plan = drawingData.edgeStairPlan(
            for: edge,
            edgeStart: start,
            edgeEnd: end,
            transform: transform,
            scaleFactor: scaleFactor
        ) else { return }

        gc.setStrokeColor(UIColor.white.withAlphaComponent(0.7).cgColor)
        gc.setLineWidth(OPSStyle.Layout.Border.thick)
        gc.beginPath()
        gc.move(to: plan.baseStart)
        gc.addLine(to: plan.baseEnd)
        gc.addLine(to: plan.farEnd)
        gc.addLine(to: plan.farStart)
        gc.closePath()
        gc.strokePath()

        gc.setStrokeColor(UIColor.white.withAlphaComponent(0.5).cgColor)
        gc.setLineWidth(OPSStyle.Layout.Border.standard)
        for tread in plan.treadLines {
            gc.beginPath()
            gc.move(to: tread.start)
            gc.addLine(to: tread.end)
            gc.strokePath()
        }
    }

    // MARK: - Geometry Helpers

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

    private static func polygonCentroid(for points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }
}

// MARK: - Angle (used by compositor without SwiftUI dependency)

import SwiftUI
