//
//  DeckStairRenderPlanner.swift
//  OPS
//
//  Shared stair geometry planner for read-only deck renderers.
//

import CoreGraphics
import SwiftUI

struct DeckStairRenderPlan {
    let baseStart: CGPoint
    let baseEnd: CGPoint
    let farStart: CGPoint
    let farEnd: CGPoint
    let outline: [CGPoint]
    let treadLines: [DeckStairTreadLine]
    let dimensionLabels: [DeckStairDimensionLabel]
    let boundaryMarkers: [CGPoint]
    let adjacentEdgeLabels: [DeckStairDimensionLabel]

    var framePoints: [CGPoint] {
        outline
            + boundaryMarkers
            + dimensionLabels.map(\.position)
            + adjacentEdgeLabels.map(\.position)
    }

    /// Places stair-width and adjacent-edge chips in stable screen-space lanes.
    /// The canvas itself is zoomed, so the lane distance must be converted back
    /// into world coordinates to keep labels readable and collision-free.
    func edgeLabelPosition(
        for label: DeckStairDimensionLabel,
        zoomScale: CGFloat
    ) -> CGPoint {
        guard label.kind == .width || label.kind == .adjacentEdge,
              let edgeUnit,
              let stairNormal else { return label.position }

        let fromBase = CGVector(
            dx: label.position.x - baseStart.x,
            dy: label.position.y - baseStart.y
        )
        let projectedDistance = fromBase.dx * edgeUnit.dx + fromBase.dy * edgeUnit.dy
        let anchor = baseStart.offset(by: edgeUnit, distance: projectedDistance)
        let safeZoom = max(abs(zoomScale), CGFloat.ulpOfOne.squareRoot())
        let screenDistance = CGFloat(OPSStyle.Layout.spacing3)
            + CGFloat(OPSStyle.Layout.spacing4) * CGFloat(label.lane)
        return anchor.offset(by: stairNormal, distance: screenDistance / safeZoom)
    }

    /// Places the builder's tread/rail summary beyond both the stair run and
    /// every segment-label lane, regardless of the current zoom level.
    func summaryLabelPosition(zoomScale: CGFloat) -> CGPoint {
        guard let stairNormal else {
            return CGPoint(
                x: (baseStart.x + farEnd.x) / 2,
                y: (baseStart.y + farEnd.y) / 2
            )
        }

        let safeZoom = max(abs(zoomScale), CGFloat.ulpOfOne.squareRoot())
        let runLength = hypot(farStart.x - baseStart.x, farStart.y - baseStart.y)
        let maxLane = max(
            dimensionLabels.filter { $0.kind == .width }.map(\.lane).max() ?? 0,
            adjacentEdgeLabels.map(\.lane).max() ?? 0
        )
        let beyondStair = runLength + CGFloat(OPSStyle.Layout.spacing2) / safeZoom
        let beyondLanes = (
            CGFloat(OPSStyle.Layout.spacing3)
                + CGFloat(OPSStyle.Layout.spacing4) * CGFloat(maxLane + 1)
        ) / safeZoom
        let distance = max(beyondStair, beyondLanes)
        let baseMidpoint = CGPoint(
            x: (baseStart.x + baseEnd.x) / 2,
            y: (baseStart.y + baseEnd.y) / 2
        )
        return baseMidpoint.offset(by: stairNormal, distance: distance)
    }

    var stairNormal: CGVector? {
        normalizedVector(from: baseStart, to: farStart)
    }

    private var edgeUnit: CGVector? {
        normalizedVector(from: baseStart, to: baseEnd)
    }

    private func normalizedVector(from start: CGPoint, to end: CGPoint) -> CGVector? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > CGFloat.ulpOfOne.squareRoot() else { return nil }
        return CGVector(dx: dx / length, dy: dy / length)
    }
}

struct DeckStairTreadLine: Equatable {
    let start: CGPoint
    let end: CGPoint
}

struct DeckStairDimensionLabel: Equatable {
    enum Kind: Equatable {
        case width
        case run
        case rail
        case adjacentEdge
    }

    let kind: Kind
    let text: String
    let position: CGPoint
    let lane: Int

    init(kind: Kind, text: String, position: CGPoint, lane: Int = 0) {
        self.kind = kind
        self.text = text
        self.position = position
        self.lane = lane
    }
}

/// Tread count + sloped rail run for one stair — the shared source for every
/// 2D stair label. The rail run is the stair triangle's hypotenuse (total
/// rise over total horizontal run): the length a stair railing actually
/// follows, which is what a railing order is measured by.
struct DeckStairRailInfo: Equatable {
    let treadCount: Int
    let railRunInches: Double
}

extension DetectedSurface {
    /// Whether this face walks straight from one vertex to the other — i.e.
    /// the pair is one of the face's own sides. Cyclic, direction-agnostic.
    func hasSide(_ a: String, _ b: String) -> Bool {
        let count = vertexIds.count
        guard count >= 3 else { return false }
        for index in 0..<count {
            let start = vertexIds[index]
            let end = vertexIds[(index + 1) % count]
            if (start == a && end == b) || (start == b && end == a) { return true }
        }
        return false
    }
}

extension DeckDrawingData {
    /// The closed face a stair on `edgeId` must face AWAY from, in canvas
    /// coordinates — the deck surface itself, which is exactly how a stair's
    /// direction is decided in the field.
    ///
    /// Resolving this per-edge is what makes stair direction correct on real
    /// drawings. Callers used to pass the level's `orderedPositions`, which
    /// silently degenerates to an unordered vertex dump whenever ANY vertex
    /// lacks exactly two connections — two separate shapes, an interior
    /// detail line, a T-junction, an unfinished outline. Feeding that
    /// scribble to the inside/outside test produced an essentially random
    /// side, so stairs faced the wrong way on most non-trivial decks.
    ///
    /// Returns an empty array when no single face owns the edge (an open
    /// outline, or an interior edge shared by two surfaces, where "outward"
    /// is undefined); the geometry helpers then fall back to their historic
    /// perpendicular instead of trusting a bad polygon.
    func stairFacePolygon(forEdgeId edgeId: String) -> [CGPoint] {
        if isMultiLevel {
            for level in levels {
                guard let edge = level.edge(byId: edgeId) else { continue }
                if let face = Self.facePositions(owning: edge, among: level.detectedSurfaces) {
                    return face
                }
                return level.isClosed ? level.orderedPositions : []
            }
            return []
        }
        guard let edge = edge(byId: edgeId) else { return [] }
        if let face = Self.facePositions(owning: edge, among: detectedSurfaces) {
            return face
        }
        return isClosed ? orderedPositions : []
    }

    /// Vertex ids of that same face, for renderers that hold their own
    /// coordinate mapping (3D metres, transformed export canvases) and must
    /// rebuild the polygon in their own space.
    func stairFaceVertexIds(forEdgeId edgeId: String) -> [String]? {
        if isMultiLevel {
            for level in levels {
                guard let edge = level.edge(byId: edgeId) else { continue }
                return Self.faceIds(owning: edge, among: level.detectedSurfaces)
            }
            return nil
        }
        guard let edge = edge(byId: edgeId) else { return nil }
        return Self.faceIds(owning: edge, among: detectedSurfaces)
    }

    private static func owningFace(_ edge: DeckEdge, among faces: [DetectedSurface]) -> DetectedSurface? {
        let owning = faces.filter { $0.hasSide(edge.startVertexId, edge.endVertexId) }
        // Exactly one face → a true perimeter edge with a well-defined
        // outside. Two → an interior divider between surfaces (no outward
        // side). Zero → the edge isn't part of any closed loop yet.
        return owning.count == 1 ? owning[0] : nil
    }

    private static func facePositions(owning edge: DeckEdge, among faces: [DetectedSurface]) -> [CGPoint]? {
        owningFace(edge, among: faces)?.positions
    }

    private static func faceIds(owning edge: DeckEdge, among faces: [DetectedSurface]) -> [String]? {
        owningFace(edge, among: faces)?.vertexIds
    }

    /// Total rise (inches) a fixed-rise stair on `edge` spans: the stored
    /// rise when the user set one, else the owning context's resolved render
    /// height — the same fallback the 3D scene uses, so labels and geometry
    /// never disagree.
    func stairTotalRiseInches(for edge: DeckEdge) -> Double? {
        guard let config = edge.stairConfig else { return nil }
        if let stored = config.totalRiseInches, stored > 0 { return stored }
        if isMultiLevel {
            for (index, level) in levels.enumerated() where level.edge(byId: edge.id) != nil {
                return renderElevationFeet(for: level, levelIndex: index) * 12.0
            }
            return nil
        }
        return renderElevationFeetSingleLevel * 12.0
    }

    /// Rail info for a fixed-rise stair on `edge`, or nil when the edge
    /// carries no stair.
    func stairRailInfo(for edge: DeckEdge) -> DeckStairRailInfo? {
        guard let config = edge.stairConfig,
              let riseInches = stairTotalRiseInches(for: edge), riseInches > 0 else { return nil }
        let treadCount = config.treadCount
            ?? StairConfig.calculateTreadCount(totalRise: riseInches, risePerStep: config.risePerStep)
        guard treadCount > 0 else { return nil }
        return DeckStairRailInfo(
            treadCount: treadCount,
            railRunInches: StairConfig.stringerLength(
                totalRise: riseInches,
                treadCount: treadCount,
                runPerTread: config.runPerTread
            )
        )
    }

    /// Rail info for a level-connection stair. Rise derives from the two
    /// levels' resolved heights (the connection's live geometry), so the
    /// label tracks height edits exactly like the rendered stair does.
    func stairRailInfo(for connection: LevelConnection) -> DeckStairRailInfo? {
        guard let riseInches = elevationDifference(
            upperLevelId: connection.upperLevelId,
            lowerLevelId: connection.lowerLevelId
        ), riseInches > 0 else { return nil }
        let config = connection.stairConfig
        let treadCount = config.treadCount
            ?? StairConfig.calculateTreadCount(totalRise: riseInches, risePerStep: config.risePerStep)
        guard treadCount > 0 else { return nil }
        return DeckStairRailInfo(
            treadCount: treadCount,
            railRunInches: StairConfig.stringerLength(
                totalRise: riseInches,
                treadCount: treadCount,
                runPerTread: config.runPerTread
            )
        )
    }
}

enum DeckStairRenderPlanner {

    static func plan(
        edgeStart start: CGPoint,
        edgeEnd end: CGPoint,
        polygonVertices: [CGPoint],
        config: StairConfig,
        treadCount: Int,
        scaleFactor: Double,
        measurementSystem: MeasurementSystem,
        edgeDimensionInches: Double? = nil,
        totalRiseInches: Double? = nil
    ) -> DeckStairRenderPlan? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let edgeLength = hypot(dx, dy)
        guard edgeLength > 0, treadCount > 0, scaleFactor > 0 else { return nil }

        let edgeUnit = CGVector(dx: dx / edgeLength, dy: dy / edgeLength)
        let outward: CGVector
        if polygonVertices.count >= 3 {
            let resolved = PolygonMath.outwardPerpendicular(
                edgeStart: start,
                edgeEnd: end,
                polygonVertices: polygonVertices
            )
            outward = CGVector(dx: CGFloat(resolved.x), dy: CGFloat(resolved.y))
        } else {
            outward = CGVector(dx: -dy / edgeLength, dy: dx / edgeLength)
        }
        let stairNormal = config.flipDirection
            ? CGVector(dx: -outward.dx, dy: -outward.dy)
            : outward

        let scale = CGFloat(scaleFactor)
        let stairWidthCanvas = min(max(0, CGFloat(config.width) * scale), edgeLength)
        let totalRunInches = Double(treadCount) * config.runPerTread
        let stairDepthCanvas = CGFloat(totalRunInches) * scale
        guard stairWidthCanvas > 0, stairDepthCanvas > 0 else { return nil }

        let availableGap = max(0, edgeLength - stairWidthCanvas)
        let offsetCanvas = CGFloat(config.offset) * scale
        let rawStartDistance: CGFloat
        switch config.alignment {
        case .left:
            rawStartDistance = offsetCanvas
        case .center:
            rawStartDistance = (availableGap / 2) + offsetCanvas
        case .right:
            rawStartDistance = availableGap - offsetCanvas
        }
        let startDistance = min(max(0, rawStartDistance), availableGap)

        let baseStart = CGPoint(
            x: start.x + edgeUnit.dx * startDistance,
            y: start.y + edgeUnit.dy * startDistance
        )
        let baseEnd = CGPoint(
            x: baseStart.x + edgeUnit.dx * stairWidthCanvas,
            y: baseStart.y + edgeUnit.dy * stairWidthCanvas
        )
        let farStart = CGPoint(
            x: baseStart.x + stairNormal.dx * stairDepthCanvas,
            y: baseStart.y + stairNormal.dy * stairDepthCanvas
        )
        let farEnd = CGPoint(
            x: baseEnd.x + stairNormal.dx * stairDepthCanvas,
            y: baseEnd.y + stairNormal.dy * stairDepthCanvas
        )

        let treadLines: [DeckStairTreadLine] = (1..<min(treadCount, 30)).map { index in
            let t = CGFloat(index) / CGFloat(treadCount)
            let lineStart = CGPoint(
                x: baseStart.x + stairNormal.dx * stairDepthCanvas * t,
                y: baseStart.y + stairNormal.dy * stairDepthCanvas * t
            )
            let lineEnd = CGPoint(
                x: baseEnd.x + stairNormal.dx * stairDepthCanvas * t,
                y: baseEnd.y + stairNormal.dy * stairDepthCanvas * t
            )
            return DeckStairTreadLine(start: lineStart, end: lineEnd)
        }

        let resolvedEdgeInches = max(
            0,
            edgeDimensionInches ?? Double(edgeLength / scale)
        )
        let widthInches = min(max(0, config.width), resolvedEdgeInches)
        let availableGapInches = max(0, resolvedEdgeInches - widthInches)
        let rawLeadingGapInches: Double
        switch config.alignment {
        case .left:
            rawLeadingGapInches = config.offset
        case .center:
            rawLeadingGapInches = (availableGapInches / 2) + config.offset
        case .right:
            rawLeadingGapInches = availableGapInches - config.offset
        }
        let leadingGapInches = min(max(0, rawLeadingGapInches), availableGapInches)
        let trailingGapInches = max(0, availableGapInches - leadingGapInches)
        let labelInset = min(
            CGFloat(OPSStyle.Layout.spacing3),
            max(CGFloat(OPSStyle.Layout.spacing2), stairDepthCanvas * 0.25)
        )
        let lateralLabelInset = min(
            CGFloat(OPSStyle.Layout.spacing3),
            max(CGFloat(OPSStyle.Layout.spacing2), stairWidthCanvas * 0.28)
        )

        let widthLabelPoint = midpoint(baseStart, baseEnd)
            .offset(by: stairNormal, distance: labelInset)
        let runLabelPoint = midpoint(baseStart, farStart)
            .offset(by: CGVector(dx: -edgeUnit.dx, dy: -edgeUnit.dy), distance: lateralLabelInset)

        // A stair can occupy only part of its host edge. Those internal stair
        // corners are real measurement boundaries even though they are not
        // persisted topology vertices: splitting the stored edge would break
        // the stair attachment and every item already assigned to that edge.
        // Emit presentation-only markers and the remaining edge spans instead.
        let boundaryTolerance = edgeLength * CGFloat.ulpOfOne.squareRoot()
        let leadingGap = startDistance
        let trailingGap = max(0, edgeLength - startDistance - stairWidthCanvas)
        var boundaryMarkers: [CGPoint] = []
        var adjacentEdgeLabels: [DeckStairDimensionLabel] = []
        let edgeLabelNormal = stairNormal
        let edgeLabelLaneSpacing = CGFloat(OPSStyle.Layout.spacing4)
        let hasLeadingGap = leadingGap > boundaryTolerance
        let hasTrailingGap = trailingGap > boundaryTolerance

        if hasLeadingGap {
            boundaryMarkers.append(baseStart)
            adjacentEdgeLabels.append(
                DeckStairDimensionLabel(
                    kind: .adjacentEdge,
                    text: DimensionEngine.format(leadingGapInches, system: measurementSystem),
                    position: midpoint(start, baseStart)
                        .offset(by: edgeLabelNormal, distance: labelInset + edgeLabelLaneSpacing),
                    lane: 1
                )
            )
        }

        if hasTrailingGap {
            let lane = hasLeadingGap ? 2 : 1
            boundaryMarkers.append(baseEnd)
            adjacentEdgeLabels.append(
                DeckStairDimensionLabel(
                    kind: .adjacentEdge,
                    text: DimensionEngine.format(trailingGapInches, system: measurementSystem),
                    position: midpoint(baseEnd, end)
                        .offset(
                            by: edgeLabelNormal,
                            distance: labelInset + edgeLabelLaneSpacing * CGFloat(lane)
                        ),
                    lane: lane
                )
            )
        }

        var labels = [
            DeckStairDimensionLabel(
                kind: .width,
                text: "WIDTH \(DimensionEngine.format(widthInches, system: measurementSystem))",
                position: widthLabelPoint
            ),
            DeckStairDimensionLabel(
                kind: .run,
                text: "RUN \(DimensionEngine.format(totalRunInches, system: measurementSystem))",
                position: runLabelPoint
            )
        ]

        // Rail run — the stair triangle's hypotenuse (rise over horizontal
        // run), the length a stair railing follows. Emitted only when the
        // caller knows the rise; mirrored on the flank opposite the RUN chip.
        if let totalRiseInches, totalRiseInches > 0 {
            let railRunInches = StairConfig.stringerLength(
                totalRise: totalRiseInches,
                treadCount: treadCount,
                runPerTread: config.runPerTread
            )
            let railLabelPoint = midpoint(baseEnd, farEnd)
                .offset(by: edgeUnit, distance: lateralLabelInset)
            labels.append(
                DeckStairDimensionLabel(
                    kind: .rail,
                    text: "RAIL \(DimensionEngine.format(railRunInches, system: measurementSystem))",
                    position: railLabelPoint
                )
            )
        }

        return DeckStairRenderPlan(
            baseStart: baseStart,
            baseEnd: baseEnd,
            farStart: farStart,
            farEnd: farEnd,
            outline: [baseStart, baseEnd, farEnd, farStart],
            treadLines: treadLines,
            dimensionLabels: labels,
            boundaryMarkers: boundaryMarkers,
            adjacentEdgeLabels: adjacentEdgeLabels
        )
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

private extension CGPoint {
    func offset(by vector: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(
            x: x + vector.dx * distance,
            y: y + vector.dy * distance
        )
    }
}
