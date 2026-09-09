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
    let transitions: [VinylPreviewTransition]
    let dimensionLabels: [VinylPreviewDimensionLabel]
}

/// Where a surface's dimension labels sit, in screen points measured out from
/// the wrap band. `offsetPoints` is the ring the label CENTRES sit on;
/// `reachPoints` is the outermost pixel any of them paints — the reserve the
/// drawing's fit has to honour.
struct VinylPreviewDimensionRing: Equatable {
    let offsetPoints: CGFloat
    let reachPoints: CGFloat
}

/// One deck edge's own length, drawn outside the outline at the edge midpoint.
/// The order layout showed every cut width but never the deck's dimensions
/// (bug 1a8e48af).
struct VinylPreviewDimensionLabel: Equatable {
    let edgeId: String
    let text: String
    let point: CGPoint
    /// Source-unit distance from the edge midpoint out to `point`, along the
    /// outward normal. Always positive — the label sits outside the outline.
    let distanceFromEdge: CGFloat
}

struct VinylPreviewTransition: Equatable {
    let sourceTransitionId: String
    let houseEdgeId: String
    let start: CGPoint
    let end: CGPoint
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

struct VinylPreviewLeaderPlacement: Equatable {
    let leaderStart: CGPoint
    let leaderEnd: CGPoint
    let labelCenter: CGPoint
}

enum VinylPreviewAnnotationPlanner {
    static let houseEdgeTone: VinylPreviewAnnotationTone = .neutral
    static let houseEdgeLabelFontSize: CGFloat = 7
    static let overlapLabelFontSize: CGFloat = 8
    static let houseEdgeLabelInsetPoints: CGFloat = 12
    static let leaderPadding: CGFloat = 4

    /// Screen-point gap between the wrap band and the NEAR edge of a dimension
    /// label. The ring's own radius is derived from this — see `dimensionRing`.
    static let dimensionLabelStandoffPoints = CGFloat(OPSStyle.Layout.spacing3)

    /// Screen-point clearance kept between a lap leader's label and a dimension
    /// label, so a wrapped edge never stacks two callouts on one another.
    static let dimensionLabelClearancePoints = CGFloat(OPSStyle.Layout.spacing2)

    /// Edges under two feet are structure — a notch return, a stair nosing —
    /// not a dimension worth reading. Labelling them only crowds the corner.
    static let dimensionLabelMinimumInches: Double = 24

    /// Per-character advance of the mono micro tier, in screen points. Canvas
    /// text is drawn, not laid out, so callout extents are sized from this
    /// rather than measured — the same figure `labelSourceSize` has always used.
    static let monoAdvancePoints: CGFloat = 5.5

    static func houseEdgeLabelSourcePoint(
        edgeMidpoint: CGPoint,
        outwardNormal: CGVector,
        previewScale: CGFloat
    ) -> CGPoint {
        let sourceInset = houseEdgeLabelInsetPoints / max(previewScale, 0.001)
        return CGPoint(
            x: edgeMidpoint.x - (outwardNormal.dx * sourceInset),
            y: edgeMidpoint.y - (outwardNormal.dy * sourceInset)
        )
    }

    static func overlapLeaderPlacement(
        anchor: CGPoint,
        labelCenter: CGPoint,
        labelSize: CGSize,
        padding: CGFloat = leaderPadding
    ) -> VinylPreviewLeaderPlacement {
        let dx = anchor.x - labelCenter.x
        let dy = anchor.y - labelCenter.y
        let length = sqrt((dx * dx) + (dy * dy))
        guard length > 0 else {
            return VinylPreviewLeaderPlacement(
                leaderStart: anchor,
                leaderEnd: anchor,
                labelCenter: labelCenter
            )
        }

        let unit = CGVector(dx: dx / length, dy: dy / length)
        let protectedDistance = (abs(unit.dx) * labelSize.width / 2)
            + (abs(unit.dy) * labelSize.height / 2)
            + padding
        let unclampedEnd = CGPoint(
            x: labelCenter.x + (unit.dx * protectedDistance),
            y: labelCenter.y + (unit.dy * protectedDistance)
        )

        if distanceSquared(anchor, unclampedEnd) > distanceSquared(anchor, labelCenter) {
            return VinylPreviewLeaderPlacement(
                leaderStart: anchor,
                leaderEnd: anchor,
                labelCenter: labelCenter
            )
        }

        return VinylPreviewLeaderPlacement(
            leaderStart: anchor,
            leaderEnd: unclampedEnd,
            labelCenter: labelCenter
        )
    }

    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx) + (dy * dy)
    }

    static func regionPolygon(
        for cut: VinylCutPiece,
        in surface: VinylSurfaceCutPlan
    ) -> [CGPoint] {
        guard let regionId = cut.directionRegionId,
              let region = surface.directionRegions.first(where: { $0.id == regionId }) else {
            return surface.positions
        }
        return region.polygon
    }

    static func plan(
        surface: VinylSurfaceCutPlan,
        settings: VinylOrderSettings,
        viewportScale: CGFloat,
        measurementSystem: MeasurementSystem = .imperial
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
                        lapLabel(for: .deckEdge, settings: settings),
                        for: $0,
                        tone: .deck,
                        wrapCanvas: wrapCanvas,
                        sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint
                    )
                },
                representativeLayout(in: layouts, type: .houseEdge).map {
                    leader(
                        lapLabel(for: .houseEdge, settings: settings),
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
            leaders: leaders,
            transitions: surface.directionTransitions.flatMap { transition in
                transition.segments.map { segment in
                    VinylPreviewTransition(
                        sourceTransitionId: transition.id,
                        houseEdgeId: transition.houseEdgeId,
                        start: segment.start,
                        end: segment.end
                    )
                }
            },
            dimensionLabels: dimensionLabels(
                for: layouts,
                placements: dimensionPlacements(
                    for: surface,
                    settings: settings,
                    measurementSystem: measurementSystem,
                    sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint
                ),
                wrapCanvas: wrapCanvas,
                sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint,
                measurementSystem: measurementSystem
            )
        )
    }

    // MARK: - Deck dimensions

    /// Where one edge's dimension label sits, in screen points.
    ///
    /// `standoff` is measured out along the edge's outward normal; `slide` runs
    /// ALONG the edge, and is non-zero only where the edge also carries a lap
    /// leader.
    struct VinylPreviewDimensionPlacement: Equatable {
        let standoffPoints: CGFloat
        let slidePoints: CGFloat
        /// Outermost screen point the label paints, measured from the edge.
        let reachPoints: CGFloat
    }

    /// Where one surface's dimension labels sit, in screen points measured from
    /// the OUTER edge of the wrap band.
    ///
    /// Each label stands off its OWN edge — a `spacing3` gap and nothing more.
    /// The two edges that also carry a lap leader step their label ALONG the
    /// edge to clear it rather than out past it: a `DECK LAP 6"` callout is
    /// ~68pt of text projecting sideways from a vertical edge, and pushing the
    /// dimension beyond it used to drive a single worst-case ring that every
    /// other edge then paid for. On the founder's phone that ring cost ~30% of
    /// the drawing's width and left the labels adrift ~78pt off the deck. An
    /// edge with no room to slide falls back to the radial push.
    ///
    /// Scale-free by construction: every term is a screen-point size, so the
    /// caller multiplies by its own source-units-per-point, and
    /// `VinylCutPreview` reserves `reachPoints` when it fits the drawing.
    static func dimensionPlacements(
        for surface: VinylSurfaceCutPlan,
        settings: VinylOrderSettings,
        measurementSystem: MeasurementSystem,
        sourceUnitsPerScreenPoint: CGFloat
    ) -> [String: VinylPreviewDimensionPlacement] {
        let layouts = edgeLayouts(for: surface)
        let lapEdgeIds = lapLeaderEdgeIds(in: layouts, settings: settings)
        var placements: [String: VinylPreviewDimensionPlacement] = [:]

        for layout in layouts {
            guard let inches = edgeLengthInches(for: layout),
                  inches >= dimensionLabelMinimumInches else { continue }

            // The label's own reach along the outward normal: a vertical edge
            // pushes its text out sideways (half the width), a horizontal edge
            // upward (half the line height).
            let text = DimensionEngine.format(inches, system: measurementSystem)
            let labelSize = labelSourceSize(for: text, sourceUnitsPerScreenPoint: 1)
            let halfExtent = self.halfExtent(of: labelSize, along: layout.outwardNormal)

            // Floor: the label's near edge stands one `spacing3` off the band.
            let standoff = dimensionLabelStandoffPoints + halfExtent

            guard let lapLabel = lapEdgeIds[layout.edge.id] else {
                placements[layout.edge.id] = VinylPreviewDimensionPlacement(
                    standoffPoints: standoff,
                    slidePoints: 0,
                    reachPoints: standoff + halfExtent
                )
                continue
            }

            // This edge carries a lap leader on the same midpoint. Step the
            // dimension sideways along the edge if the edge is long enough to
            // hold both without either running off its own end.
            let leaderSize = labelSourceSize(for: lapLabel, sourceUnitsPerScreenPoint: 1)
            let edgeDirection = self.edgeDirection(of: layout)
            let slide = halfExtent(of: leaderSize, along: edgeDirection)
                + dimensionLabelClearancePoints
                + halfExtent(of: labelSize, along: edgeDirection)
            let edgeLengthPoints = layout.length / max(sourceUnitsPerScreenPoint, 0.0001)

            if (slide + halfExtent(of: labelSize, along: edgeDirection)) * 2 <= edgeLengthPoints {
                placements[layout.edge.id] = VinylPreviewDimensionPlacement(
                    standoffPoints: standoff,
                    slidePoints: slide,
                    reachPoints: standoff + halfExtent
                )
            } else {
                // No room to slide — clear the leader radially instead.
                let leaderOuterEdge = CGFloat(OPSStyle.Layout.spacing3)
                    + self.halfExtent(of: leaderSize, along: layout.outwardNormal)
                let pushed = max(
                    standoff,
                    leaderOuterEdge + dimensionLabelClearancePoints + halfExtent
                )
                placements[layout.edge.id] = VinylPreviewDimensionPlacement(
                    standoffPoints: pushed,
                    slidePoints: 0,
                    reachPoints: pushed + halfExtent
                )
            }
        }

        return placements
    }

    /// The widest reach any of a surface's dimension labels needs, in screen
    /// points, and the widest stand-off among them.
    static func dimensionRing(
        for surface: VinylSurfaceCutPlan,
        settings: VinylOrderSettings,
        measurementSystem: MeasurementSystem,
        sourceUnitsPerScreenPoint: CGFloat = 1
    ) -> VinylPreviewDimensionRing {
        let placements = dimensionPlacements(
            for: surface,
            settings: settings,
            measurementSystem: measurementSystem,
            sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint
        )
        return VinylPreviewDimensionRing(
            offsetPoints: placements.values.map(\.standoffPoints).max() ?? 0,
            reachPoints: placements.values.map(\.reachPoints).max() ?? 0
        )
    }

    /// Unit vector along the edge, start → end.
    private static func edgeDirection(
        of layout: VinylPreviewAnnotationEdgeLayout
    ) -> CGVector {
        let dx = layout.edge.end.x - layout.edge.start.x
        let dy = layout.edge.end.y - layout.edge.start.y
        let length = max(hypot(dx, dy), 0.0001)
        return CGVector(dx: dx / length, dy: dy / length)
    }

    /// The widest reach any surface's dimension ring needs, in screen points.
    /// `VinylCutPreview` reserves exactly this much, so the deck's dimensions
    /// are never the thing that falls off the canvas.
    static func dimensionRingReachPoints(
        for surfaces: [VinylSurfaceCutPlan],
        settings: VinylOrderSettings,
        measurementSystem: MeasurementSystem,
        sourceUnitsPerScreenPoint: CGFloat = 1
    ) -> CGFloat {
        surfaces
            .map {
                dimensionRing(
                    for: $0,
                    settings: settings,
                    measurementSystem: measurementSystem,
                    sourceUnitsPerScreenPoint: sourceUnitsPerScreenPoint
                ).reachPoints
            }
            .max() ?? 0
    }

    /// The lap-leader label each edge carries, keyed by edge id. Empty when the
    /// order has no edge wrap — there are no bands and no leaders to clear.
    private static func lapLeaderEdgeIds(
        in layouts: [VinylPreviewAnnotationEdgeLayout],
        settings: VinylOrderSettings
    ) -> [String: String] {
        guard settings.edgeWrapInches > 0 else { return [:] }
        var ids: [String: String] = [:]
        for type in [EdgeType.deckEdge, .houseEdge] {
            if let layout = representativeLayout(in: layouts, type: type) {
                ids[layout.edge.id] = lapLabel(for: type, settings: settings)
            }
        }
        return ids
    }

    private static func lapLabel(
        for type: EdgeType,
        settings: VinylOrderSettings
    ) -> String {
        let lap = formatOverlapInches(settings.edgeWrapInches)
        return type == .houseEdge ? "HOUSE LAP \(lap)" : "DECK LAP \(lap)"
    }

    /// How far a label of `size` reaches along `normal` from its own centre.
    private static func halfExtent(of size: CGSize, along normal: CGVector) -> CGFloat {
        (abs(normal.dx) * size.width / 2) + (abs(normal.dy) * size.height / 2)
    }

    private static func dimensionLabels(
        for layouts: [VinylPreviewAnnotationEdgeLayout],
        placements: [String: VinylPreviewDimensionPlacement],
        wrapCanvas: CGFloat,
        sourceUnitsPerScreenPoint: CGFloat,
        measurementSystem: MeasurementSystem
    ) -> [VinylPreviewDimensionLabel] {
        layouts.compactMap { layout in
            guard let inches = edgeLengthInches(for: layout),
                  let placement = placements[layout.edge.id] else { return nil }

            // Out along the normal past the wrap band, then along the edge to
            // clear a lap leader where there is one.
            let distance = wrapCanvas
                + (placement.standoffPoints * sourceUnitsPerScreenPoint)
            let base = offset(
                midpoint(layout.edge.start, layout.edge.end),
                normal: layout.outwardNormal,
                distance: distance
            )
            let slide = placement.slidePoints * sourceUnitsPerScreenPoint
            let direction = edgeDirection(of: layout)

            return VinylPreviewDimensionLabel(
                edgeId: layout.edge.id,
                text: DimensionEngine.format(inches, system: measurementSystem),
                point: CGPoint(
                    x: base.x + (direction.dx * slide),
                    y: base.y + (direction.dy * slide)
                ),
                distanceFromEdge: distance
            )
        }
    }

    /// The deck's measured dimension when it has one, else canvas length ÷ the
    /// surface's scale — the same fallback `DeckMaterialsEngine` applies.
    private static func edgeLengthInches(
        for layout: VinylPreviewAnnotationEdgeLayout
    ) -> Double? {
        if let measured = layout.edge.dimensionInches, measured > 0 {
            return measured
        }
        let scale = surfaceScale(layout.surface)
        guard scale > 0 else { return nil }
        return Double(layout.length) / scale
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
            width: (CGFloat(label.count) * monoAdvancePoints + CGFloat(OPSStyle.Layout.spacing2))
                * sourceUnitsPerScreenPoint,
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
