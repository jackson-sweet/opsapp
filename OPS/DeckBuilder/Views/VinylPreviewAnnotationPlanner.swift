//
//  VinylPreviewAnnotationPlanner.swift
//  OPS
//
//  Geometry planner for vinyl preview wrap bands, labels, and leaders.
//

import CoreGraphics
import SwiftUI

enum VinylPreviewAnnotationTone: Equatable {
    case deck
    case neutral
}

struct VinylPreviewAnnotationPlan: Equatable {
    let bands: [VinylPreviewBand]
    let houseLabels: [VinylPreviewHouseLabel]
    let leaders: [VinylPreviewLeader]
}

struct VinylPreviewBand: Equatable {
    let edgeType: EdgeType
    let tone: VinylPreviewAnnotationTone
    let polygon: [CGPoint]
    let hatchLines: [VinylPreviewHatchLine]
}

struct VinylPreviewHatchLine: Equatable {
    let start: CGPoint
    let end: CGPoint
}

struct VinylPreviewHouseLabel: Equatable {
    let text: String
    let tone: VinylPreviewAnnotationTone
    let point: CGPoint
    let distanceFromEdge: CGFloat
}

struct VinylPreviewLeader: Equatable {
    let edgeType: EdgeType
    let tone: VinylPreviewAnnotationTone
    let label: String
    let lineStart: CGPoint
    let lineEnd: CGPoint
    let labelPoint: CGPoint
    let labelRect: CGRect
    let centerLineLength: CGFloat

    var lineLength: CGFloat {
        hypot(lineEnd.x - lineStart.x, lineEnd.y - lineStart.y)
    }
}

enum VinylPreviewAnnotationPlanner {

    static func plan(
        surface: VinylSurfaceCutPlan,
        settings: VinylOrderSettings,
        viewportScale: CGFloat
    ) -> VinylPreviewAnnotationPlan {
        let sourceUnitsPerScreenPoint = 1 / max(viewportScale, 0.001)
        let layouts = edgeLayouts(for: surface)
        let wrapCanvas = CGFloat(settings.edgeWrapInches * surfaceScale(surface))

        let bands: [VinylPreviewBand]
        if settings.edgeWrapInches > 0 {
            bands = layouts.map { layout in
                band(
                    for: layout,
                    wrapCanvas: wrapCanvas,
                    sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint
                )
            }
        } else {
            bands = []
        }

        let houseLabels = layouts
            .filter { $0.edge.edgeType == .houseEdge }
            .map { layout in
                houseLabel(
                    for: layout,
                    sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint
                )
            }

        let leaders: [VinylPreviewLeader]
        if settings.edgeWrapInches > 0 {
            leaders = [
                representativeLayout(in: layouts, type: .deckEdge).map {
                    leader(
                        "DECK LAP \(formatOverlapInches(settings.edgeWrapInches))",
                        for: $0,
                        tone: .deck,
                        wrapCanvas: wrapCanvas,
                        sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint
                    )
                },
                representativeLayout(in: layouts, type: .houseEdge).map {
                    leader(
                        "HOUSE LAP \(formatOverlapInches(settings.edgeWrapInches))",
                        for: $0,
                        tone: .neutral,
                        wrapCanvas: wrapCanvas,
                        sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint
                    )
                }
            ].compactMap { $0 }
        } else {
            leaders = []
        }

        return VinylPreviewAnnotationPlan(
            bands: bands,
            houseLabels: houseLabels,
            leaders: leaders
        )
    }

    private static func band(
        for layout: VinylPreviewAnnotationEdgeLayout,
        wrapCanvas: CGFloat,
        sourceUnitsPerScreenPoint: CGFloat
    ) -> VinylPreviewBand {
        let outerStart = offset(layout.edge.start, normal: layout.outwardNormal, distance: wrapCanvas)
        let outerEnd = offset(layout.edge.end, normal: layout.outwardNormal, distance: wrapCanvas)
        let tone: VinylPreviewAnnotationTone = layout.edge.edgeType == .houseEdge ? .neutral : .deck
        let hatches = layout.edge.edgeType == .houseEdge
            ? hatchLines(for: layout, wrapCanvas: wrapCanvas, sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint)
            : []

        return VinylPreviewBand(
            edgeType: layout.edge.edgeType,
            tone: tone,
            polygon: [layout.edge.start, layout.edge.end, outerEnd, outerStart],
            hatchLines: hatches
        )
    }

    private static func houseLabel(
        for layout: VinylPreviewAnnotationEdgeLayout,
        sourceUnitsPerScreenPoint: CGFloat
    ) -> VinylPreviewHouseLabel {
        let distance = CGFloat(OPSStyle.Layout.spacing2) * sourceUnitsPerScreenPoint
        let point = offset(
            midpoint(layout.edge.start, layout.edge.end),
            normal: layout.outwardNormal,
            distance: -distance
        )
        return VinylPreviewHouseLabel(
            text: "HOUSE EDGE",
            tone: .neutral,
            point: point,
            distanceFromEdge: distance
        )
    }

    private static func leader(
        _ label: String,
        for layout: VinylPreviewAnnotationEdgeLayout,
        tone: VinylPreviewAnnotationTone,
        wrapCanvas: CGFloat,
        sourceUnitsPerScreenPoint: CGFloat
    ) -> VinylPreviewLeader {
        let edgeMidpoint = midpoint(layout.edge.start, layout.edge.end)
        let labelGap = CGFloat(OPSStyle.Layout.spacing3) * sourceUnitsPerScreenPoint
        let labelSize = labelSourceSize(for: label, sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint)
        let labelPoint = offset(
            edgeMidpoint,
            normal: layout.outwardNormal,
            distance: wrapCanvas + labelGap
        )
        let labelRect = CGRect(
            x: labelPoint.x - labelSize.width / 2,
            y: labelPoint.y - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        let anchor = offset(edgeMidpoint, normal: layout.outwardNormal, distance: wrapCanvas)
        let halfLabelAlongLeader =
            abs(layout.outwardNormal.dx) * labelSize.width / 2 +
            abs(layout.outwardNormal.dy) * labelSize.height / 2
        let stopGap = CGFloat(OPSStyle.Layout.spacing1) * sourceUnitsPerScreenPoint
        let centerLength = distance(anchor, labelPoint)
        let visibleLength = max(0, centerLength - halfLabelAlongLeader - stopGap)
        let lineEnd = offset(anchor, normal: layout.outwardNormal, distance: visibleLength)

        return VinylPreviewLeader(
            edgeType: layout.edge.edgeType,
            tone: tone,
            label: label,
            lineStart: anchor,
            lineEnd: lineEnd,
            labelPoint: labelPoint,
            labelRect: labelRect,
            centerLineLength: centerLength
        )
    }

    private static func hatchLines(
        for layout: VinylPreviewAnnotationEdgeLayout,
        wrapCanvas: CGFloat,
        sourceUnitsPerScreenPoint: CGFloat
    ) -> [VinylPreviewHatchLine] {
        guard wrapCanvas > 0 else { return [] }
        let spacing = CGFloat(OPSStyle.Layout.spacing2_5) * sourceUnitsPerScreenPoint
        let tokenInset = CGFloat(OPSStyle.Layout.spacing1) * sourceUnitsPerScreenPoint
        let inset = min(tokenInset, wrapCanvas * 0.25)
        let hatchDepth = max(0, wrapCanvas - inset * 2)
        guard spacing > 0, hatchDepth > 0 else { return [] }

        let tangent = CGVector(
            dx: (layout.edge.end.x - layout.edge.start.x) / layout.length,
            dy: (layout.edge.end.y - layout.edge.start.y) / layout.length
        )
        var lines: [VinylPreviewHatchLine] = []
        var cursor = spacing / 2
        while cursor < layout.length {
            let edgePoint = CGPoint(
                x: layout.edge.start.x + tangent.dx * cursor,
                y: layout.edge.start.y + tangent.dy * cursor
            )
            let start = offset(edgePoint, normal: layout.outwardNormal, distance: inset)
            let end = CGPoint(
                x: start.x + layout.outwardNormal.dx * hatchDepth + tangent.dx * inset,
                y: start.y + layout.outwardNormal.dy * hatchDepth + tangent.dy * inset
            )
            lines.append(VinylPreviewHatchLine(start: start, end: end))
            cursor += spacing
        }
        return lines
    }

    private static func edgeLayouts(for surface: VinylSurfaceCutPlan) -> [VinylPreviewAnnotationEdgeLayout] {
        previewEdges(for: surface).compactMap { edge in
            let dx = edge.end.x - edge.start.x
            let dy = edge.end.y - edge.start.y
            let length = hypot(dx, dy)
            guard length > 0 else { return nil }
            return VinylPreviewAnnotationEdgeLayout(
                surface: surface,
                edge: edge,
                outwardNormal: outwardNormal(for: edge, surface: surface),
                length: length
            )
        }
    }

    private static func previewEdges(for surface: VinylSurfaceCutPlan) -> [VinylOrderSurfaceEdge] {
        if !surface.edges.isEmpty { return surface.edges }
        guard surface.positions.count >= 2 else { return [] }
        return surface.positions.indices.map { index in
            let nextIndex = (index + 1) % surface.positions.count
            return VinylOrderSurfaceEdge(
                id: "\(surface.id)-edge-\(index)",
                start: surface.positions[index],
                end: surface.positions[nextIndex],
                edgeType: .deckEdge,
                label: nil
            )
        }
    }

    private static func outwardNormal(
        for edge: VinylOrderSurfaceEdge,
        surface: VinylSurfaceCutPlan
    ) -> CGVector {
        let dx = edge.end.x - edge.start.x
        let dy = edge.end.y - edge.start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return .zero }

        let normalA = CGVector(dx: dy / length, dy: -dx / length)
        let normalB = CGVector(dx: -normalA.dx, dy: -normalA.dy)
        let mid = midpoint(edge.start, edge.end)
        let probeDistance = CGFloat(OPSStyle.Layout.spacing2)
        let probeA = offset(mid, normal: normalA, distance: probeDistance)

        return PolygonMath.pointInPolygon(probeA, vertices: surface.positions) ? normalB : normalA
    }

    private static func representativeLayout(
        in layouts: [VinylPreviewAnnotationEdgeLayout],
        type: EdgeType
    ) -> VinylPreviewAnnotationEdgeLayout? {
        layouts
            .filter { $0.edge.edgeType == type }
            .max { $0.length < $1.length }
    }

    private static func surfaceScale(_ surface: VinylSurfaceCutPlan) -> Double {
        guard let faceBounds = rawSurfaceBounds(for: surface.positions), surface.boundingWidthInches > 0 else {
            return 1
        }
        return Double(faceBounds.width) / surface.boundingWidthInches
    }

    private static func rawSurfaceBounds(for points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private static func labelSourceSize(
        for label: String,
        sourceUnitsPerScreenPoint: CGFloat
    ) -> CGSize {
        CGSize(
            width: (CGFloat(label.count) * 5.5 + CGFloat(OPSStyle.Layout.spacing2)) * sourceUnitsPerScreenPoint,
            height: CGFloat(OPSStyle.Layout.spacing3) * sourceUnitsPerScreenPoint
        )
    }

    private static func midpoint(_ start: CGPoint, _ end: CGPoint) -> CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    private static func offset(_ point: CGPoint, normal: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + normal.dx * distance, y: point.y + normal.dy * distance)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func formatOverlapInches(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))\""
        }
        return String(format: "%.1f\"", rounded)
    }
}

private struct VinylPreviewAnnotationEdgeLayout {
    let surface: VinylSurfaceCutPlan
    let edge: VinylOrderSurfaceEdge
    let outwardNormal: CGVector
    let length: CGFloat
}
