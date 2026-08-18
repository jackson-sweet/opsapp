// OPS/OPS/DeckBuilder/Engine/DeckStairGeometry.swift
//
// THE single source of truth for where a stair sits on its host edge and which
// way it travels. Bug 4a773e11.
//
// Before this file, six renderers each decided stair direction for themselves:
// the editor canvas, the read-only 2D viewer, the export/share/overlay images,
// and the 3D scene. Edge-attached stairs happened to agree (they all reached
// for `PolygonMath.outwardPerpendicular`), but level-connection stairs did not:
// 2D resolved "away from the upper deck's face" while 3D used the raw
// edge-winding perpendicular, and the two are opposite on roughly half of all
// edges. On a real drawing (3998 Holland Ave) that showed as a connecting stair
// drawn backwards in 2D and correctly in 3D from the very same stored model.
//
// The rules below are resolved ONCE, here, from geometry the drawing already
// holds. Every renderer consumes the result. A divergence that can happen once
// will happen again, so no renderer is permitted to re-derive a direction.
//
// COORDINATE SPACES. Every function takes plain 2D points and is agnostic to
// which space they live in, provided the space relates to canvas coordinates by
// a positive-scale similarity (uniform scale + translation, no mirroring).
// Canvas points and the 3D scene's ground plane both qualify: the scene maps
// canvas (x, y) to world (x, z) with a single positive factor and no axis flip,
// so perpendicular handedness, polygon winding, and side-of-line tests all
// survive the trip. That is what lets 2D and 3D share one resolver instead of
// two mirror-image implementations.

import CoreGraphics
import Foundation

// MARK: - Facing

/// Why a stair points the way it does. Carried on the resolved orientation so
/// renderers, tests, and future diagnostics can tell a decision the drawing
/// made from a fallback nobody could avoid.
enum DeckStairFacing: String, Equatable {
    /// The drawing names a destination: a level-connection stair whose lower
    /// level sits on a known side of the host edge.
    case towardLowerLevel
    /// A closed face owns the edge, so the stair runs off the deck surface it
    /// serves — the natural case for an edge-attached stair.
    case awayFromDeckSurface
    /// No face owns the edge and no destination resolves (an open outline, an
    /// interior divider, an AR sketch). The edge's own winding decides, and the
    /// user's flip toggle is the only remaining signal.
    case edgeWindingFallback
}

// MARK: - Orientation

/// The two axes that define a stair in plan.
///
/// `travel` is the direction of descent — perpendicular to the host edge, the
/// way a person walks off the deck. `treadAxis` runs ALONG the host edge, which
/// is the axis every tread line lies on: a tread is a step you stand across, so
/// in plan view treads are always parallel to the edge the stair leaves from,
/// never parallel to the direction of travel.
struct DeckStairOrientation: Equatable {
    let travel: CGVector
    let treadAxis: CGVector
    let facing: DeckStairFacing
    /// Whether the user's `flipDirection` toggle was consulted. False on every
    /// path where the drawing itself names the side — see the note on
    /// `DeckStairGeometryResolver.connectionOrientation`.
    let userFlipApplied: Bool
}

// MARK: - Tread line

struct DeckStairTreadLine: Equatable {
    let start: CGPoint
    let end: CGPoint
}

// MARK: - Placement

/// A fully placed stair in the caller's coordinate space.
///
/// `baseStart`/`baseEnd` sit on the host edge; `farStart`/`farEnd` are their
/// counterparts at the foot of the run. Gaps are the untouched spans of the
/// host edge on either side of a partial-width stair.
struct DeckStairPlacement: Equatable {
    let baseStart: CGPoint
    let baseEnd: CGPoint
    let farStart: CGPoint
    let farEnd: CGPoint
    let treadLines: [DeckStairTreadLine]
    let treadCount: Int
    let orientation: DeckStairOrientation
    let widthInches: Double
    let leadingGapInches: Double
    let trailingGapInches: Double
    let totalRunInches: Double
    /// Distance along the host edge, in the caller's units, from `edgeStart` to
    /// `baseStart`.
    let leadingGapDistance: CGFloat
    /// Stair width in the caller's units (clamped to the host edge).
    let widthDistance: CGFloat
    /// Run depth in the caller's units.
    let runDistance: CGFloat

    var outline: [CGPoint] {
        [baseStart, baseEnd, farEnd, farStart]
    }

    /// Midpoint of the stair's footing on the host edge — the anchor 3D uses to
    /// seat treads, stringers, and railings.
    var baseMidpoint: CGPoint {
        CGPoint(x: (baseStart.x + baseEnd.x) / 2, y: (baseStart.y + baseEnd.y) / 2)
    }
}

// MARK: - Resolver

enum DeckStairGeometryResolver {

    /// Relative slack on the side-of-line test. A destination this close to the
    /// host edge's own line names no side, so the geometry is treated as
    /// ambiguous rather than trusted.
    private static let sideResolutionEpsilon: CGFloat = 1e-3

    // MARK: Orientation — edge-attached stairs

    /// Direction an edge-attached stair travels: off the deck surface that owns
    /// the edge. The user's `flipDirection` genuinely applies here — the stair
    /// lands on grade, and only the operator knows whether a fence, a wall, or
    /// a neighbouring structure makes the far side the wrong side.
    static func orientation(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        deckFacePolygon: [CGPoint],
        flipDirection: Bool
    ) -> DeckStairOrientation? {
        guard let treadAxis = unitVector(from: edgeStart, to: edgeEnd) else { return nil }
        let (base, facing) = baseDirection(
            edgeStart: edgeStart,
            edgeEnd: edgeEnd,
            facePolygon: deckFacePolygon,
            treadAxis: treadAxis
        )
        return DeckStairOrientation(
            travel: flipDirection ? inverted(base) : base,
            treadAxis: treadAxis,
            facing: facing,
            userFlipApplied: flipDirection
        )
    }

    // MARK: Orientation — level-connection stairs

    /// Direction a level-connection stair travels: from the upper level's edge
    /// down onto the lower level's surface.
    ///
    /// A connection stair's destination is not a preference — the drawing
    /// already records which two levels it joins, so the side it must descend
    /// toward is a fact, not a setting. That is why `flipDirection` is NOT
    /// consulted whenever the geometry names a side: a connection stair
    /// travelling away from the deck it descends to would land on nothing. The
    /// toggle is honoured only on the last-resort path, where neither a closed
    /// face nor a destination footprint can decide and the operator's explicit
    /// choice is the only signal left.
    ///
    /// - Parameters:
    ///   - upperFacePolygon: the closed face on the UPPER level that owns the
    ///     host edge, in the caller's space. Empty when no single face does.
    ///   - lowerDestination: where the stair must land — the midpoint of the
    ///     lower level's matching edge when the connection names one, else the
    ///     centre of the lower level's footprint. Nil when neither resolves.
    static func connectionOrientation(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        upperFacePolygon: [CGPoint],
        lowerDestination: CGPoint?,
        flipDirection: Bool
    ) -> DeckStairOrientation? {
        guard let treadAxis = unitVector(from: edgeStart, to: edgeEnd) else { return nil }
        let (base, baseFacing) = baseDirection(
            edgeStart: edgeStart,
            edgeEnd: edgeEnd,
            facePolygon: upperFacePolygon,
            treadAxis: treadAxis
        )

        // Which side of the host edge does the lower level actually sit on?
        // When it answers, it wins: the stair has to reach the deck below, even
        // on drawings where the two levels overlap and "outward from the upper
        // face" would send it the other way.
        if let destinationSign = side(
            of: lowerDestination,
            relativeTo: base,
            edgeStart: edgeStart,
            edgeEnd: edgeEnd
        ) {
            return DeckStairOrientation(
                travel: destinationSign >= 0 ? base : inverted(base),
                treadAxis: treadAxis,
                facing: .towardLowerLevel,
                userFlipApplied: false
            )
        }

        // A closed face still beats a coin flip: run off the upper deck's
        // surface, and keep ignoring the toggle — the destination is known even
        // when its exact side is not.
        if baseFacing == .awayFromDeckSurface {
            return DeckStairOrientation(
                travel: base,
                treadAxis: treadAxis,
                facing: .awayFromDeckSurface,
                userFlipApplied: false
            )
        }

        return DeckStairOrientation(
            travel: flipDirection ? inverted(base) : base,
            treadAxis: treadAxis,
            facing: .edgeWindingFallback,
            userFlipApplied: flipDirection
        )
    }

    // MARK: Placement

    /// Places a stair of `widthInches` on its host edge and projects it
    /// `treadCount × runPerTreadInches` along the orientation's travel axis.
    ///
    /// `pointsPerUnit` converts inches into the caller's space — canvas points
    /// per inch for 2D, metres per inch for the 3D scene.
    static func placement(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        orientation: DeckStairOrientation,
        widthInches: Double,
        alignment: StairAlignment,
        offsetInches: Double,
        treadCount: Int,
        runPerTreadInches: Double,
        pointsPerUnit: Double,
        edgeDimensionInches: Double? = nil
    ) -> DeckStairPlacement? {
        let edgeLength = hypot(edgeEnd.x - edgeStart.x, edgeEnd.y - edgeStart.y)
        guard edgeLength > 0,
              treadCount > 0,
              pointsPerUnit > 0,
              runPerTreadInches > 0 else { return nil }

        let scale = CGFloat(pointsPerUnit)
        let widthDistance = min(max(0, CGFloat(widthInches) * scale), edgeLength)
        let totalRunInches = Double(treadCount) * runPerTreadInches
        let runDistance = CGFloat(totalRunInches) * scale
        guard widthDistance > 0, runDistance > 0 else { return nil }

        let availableGap = max(0, edgeLength - widthDistance)
        let offsetDistance = CGFloat(offsetInches) * scale
        let rawStartDistance: CGFloat
        switch alignment {
        case .left:
            rawStartDistance = offsetDistance
        case .center:
            rawStartDistance = (availableGap / 2) + offsetDistance
        case .right:
            rawStartDistance = availableGap - offsetDistance
        }
        let startDistance = min(max(0, rawStartDistance), availableGap)

        let axis = orientation.treadAxis
        let travel = orientation.travel
        let baseStart = edgeStart.offset(by: axis, distance: startDistance)
        let baseEnd = baseStart.offset(by: axis, distance: widthDistance)
        let farStart = baseStart.offset(by: travel, distance: runDistance)
        let farEnd = baseEnd.offset(by: travel, distance: runDistance)

        // Tread lines run ALONG the host edge (parallel to `treadAxis`), one per
        // step, marching outward along `travel`. Drawing them along the travel
        // axis instead would render the stringers and read as a stair running
        // sideways — which is exactly what the connection-stair renderers used
        // to do.
        let renderedTreads = min(treadCount, 30)
        let treadLines: [DeckStairTreadLine] = (1..<max(1, renderedTreads)).map { index in
            let t = CGFloat(index) / CGFloat(treadCount)
            return DeckStairTreadLine(
                start: baseStart.offset(by: travel, distance: runDistance * t),
                end: baseEnd.offset(by: travel, distance: runDistance * t)
            )
        }

        // Real-world spans for the labels. The host edge's stored dimension is
        // authoritative when it has one; otherwise fall back to its drawn
        // length through the same scale.
        let resolvedEdgeInches = max(0, edgeDimensionInches ?? Double(edgeLength / scale))
        let clampedWidthInches = min(max(0, widthInches), resolvedEdgeInches)
        let availableGapInches = max(0, resolvedEdgeInches - clampedWidthInches)
        let rawLeadingGapInches: Double
        switch alignment {
        case .left:
            rawLeadingGapInches = offsetInches
        case .center:
            rawLeadingGapInches = (availableGapInches / 2) + offsetInches
        case .right:
            rawLeadingGapInches = availableGapInches - offsetInches
        }
        let leadingGapInches = min(max(0, rawLeadingGapInches), availableGapInches)

        return DeckStairPlacement(
            baseStart: baseStart,
            baseEnd: baseEnd,
            farStart: farStart,
            farEnd: farEnd,
            treadLines: treadLines,
            treadCount: treadCount,
            orientation: orientation,
            widthInches: clampedWidthInches,
            leadingGapInches: leadingGapInches,
            trailingGapInches: max(0, availableGapInches - leadingGapInches),
            totalRunInches: totalRunInches,
            leadingGapDistance: startDistance,
            widthDistance: widthDistance,
            runDistance: runDistance
        )
    }

    // MARK: Tread count

    /// Tread count for a stair, resolved the way every surface must resolve it:
    /// the user's explicit override when set, else derived from the rise the
    /// stair actually spans. 2D renderers used to require the stored override
    /// and drew nothing without it, while 3D always derived one — so stairs on
    /// auto-counted rises rendered in 3D and vanished in plan.
    static func treadCount(config: StairConfig, totalRiseInches: Double?) -> Int? {
        if let override = config.treadCount, override > 0 { return override }
        guard let rise = totalRiseInches, rise > 0 else { return nil }
        let derived = StairConfig.calculateTreadCount(
            totalRise: rise,
            risePerStep: config.risePerStep
        )
        return derived > 0 ? derived : nil
    }

    // MARK: - Internals

    private static func baseDirection(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        facePolygon: [CGPoint],
        treadAxis: CGVector
    ) -> (CGVector, DeckStairFacing) {
        guard facePolygon.count >= 3 else {
            return (leftPerpendicular(of: treadAxis), .edgeWindingFallback)
        }
        let outward = PolygonMath.outwardPerpendicular(
            edgeStart: edgeStart,
            edgeEnd: edgeEnd,
            polygonVertices: facePolygon
        )
        let vector = CGVector(dx: CGFloat(outward.x), dy: CGFloat(outward.y))
        guard vector.dx.isFinite, vector.dy.isFinite,
              hypot(vector.dx, vector.dy) > CGFloat.ulpOfOne.squareRoot() else {
            return (leftPerpendicular(of: treadAxis), .edgeWindingFallback)
        }
        return (vector, .awayFromDeckSurface)
    }

    /// Sign of `destination`'s offset from the host edge's line, measured along
    /// `reference`. Nil when the destination is missing or sits so close to the
    /// line that it names no side.
    private static func side(
        of destination: CGPoint?,
        relativeTo reference: CGVector,
        edgeStart: CGPoint,
        edgeEnd: CGPoint
    ) -> CGFloat? {
        guard let destination,
              destination.x.isFinite,
              destination.y.isFinite else { return nil }
        let edgeLength = hypot(edgeEnd.x - edgeStart.x, edgeEnd.y - edgeStart.y)
        guard edgeLength > 0 else { return nil }
        let midpoint = CGPoint(
            x: (edgeStart.x + edgeEnd.x) / 2,
            y: (edgeStart.y + edgeEnd.y) / 2
        )
        let toDestination = CGVector(
            dx: destination.x - midpoint.x,
            dy: destination.y - midpoint.y
        )
        let projection = toDestination.dx * reference.dx + toDestination.dy * reference.dy
        guard abs(projection) > edgeLength * sideResolutionEpsilon else { return nil }
        return projection
    }

    private static func unitVector(from start: CGPoint, to end: CGPoint) -> CGVector? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length.isFinite, length > CGFloat.ulpOfOne.squareRoot() else { return nil }
        return CGVector(dx: dx / length, dy: dy / length)
    }

    private static func leftPerpendicular(of vector: CGVector) -> CGVector {
        CGVector(dx: -vector.dy, dy: vector.dx)
    }

    private static func inverted(_ vector: CGVector) -> CGVector {
        CGVector(dx: -vector.dx, dy: -vector.dy)
    }
}

// MARK: - Model bindings

extension CGPoint {
    /// Shared by every stair renderer so "walk this far along that unit vector"
    /// means the same thing in canvas points and in metres.
    func offset(by vector: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(x: x + vector.dx * distance, y: y + vector.dy * distance)
    }
}

/// Everything a renderer needs to place one level-connection stair, resolved
/// from the stored model in canvas coordinates. Renderers that hold their own
/// coordinate mapping (3D metres, transformed export canvases) take the vertex
/// ids instead and rebuild the same inputs in their own space.
struct DeckConnectionStairContext {
    let edgeStart: CGPoint
    let edgeEnd: CGPoint
    let upperFacePolygon: [CGPoint]
    let lowerDestination: CGPoint?
    let riseInches: Double?
    let treadCount: Int
}

extension DeckDrawingData {

    /// Vertex ids whose average position marks where a connection stair has to
    /// land: the lower level's matching edge when the connection names one,
    /// otherwise the lower level's whole footprint. Ids rather than points so
    /// the 3D scene can resolve the same destination in metres.
    func connectionDestinationVertexIds(for connection: LevelConnection) -> [String] {
        guard let lowerLevel = level(byId: connection.lowerLevelId) else { return [] }
        if let lowerEdgeId = connection.lowerEdgeId,
           let lowerEdge = lowerLevel.edge(byId: lowerEdgeId) {
            return [lowerEdge.startVertexId, lowerEdge.endVertexId]
        }
        return lowerLevel.vertices.map(\.id)
    }

    /// Canvas-space destination for a connection stair. Plain mean of the
    /// resolved positions: the footprint arrives as an unordered vertex list,
    /// so an area-weighted centroid would be reading a polygon that isn't
    /// there.
    func connectionLowerDestination(for connection: LevelConnection) -> CGPoint? {
        guard let lowerLevel = level(byId: connection.lowerLevelId) else { return nil }
        let ids = Set(connectionDestinationVertexIds(for: connection))
        let positions = lowerLevel.vertices
            .filter { ids.contains($0.id) }
            .map(\.position)
        return Self.meanPoint(positions)
    }

    static func meanPoint(_ points: [CGPoint]) -> CGPoint? {
        let finite = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard !finite.isEmpty else { return nil }
        let count = CGFloat(finite.count)
        return CGPoint(
            x: finite.reduce(0) { $0 + $1.x } / count,
            y: finite.reduce(0) { $0 + $1.y } / count
        )
    }

    /// Resolved placement inputs for a connection stair, in canvas coordinates.
    func connectionStairContext(for connection: LevelConnection) -> DeckConnectionStairContext? {
        guard let upperLevel = level(byId: connection.upperLevelId),
              let upperEdge = upperLevel.edge(byId: connection.upperEdgeId),
              let start = upperLevel.vertex(byId: upperEdge.startVertexId),
              let end = upperLevel.vertex(byId: upperEdge.endVertexId) else { return nil }

        let riseInches = elevationDifference(
            upperLevelId: connection.upperLevelId,
            lowerLevelId: connection.lowerLevelId
        )
        guard let treadCount = DeckStairGeometryResolver.treadCount(
            config: connection.stairConfig,
            totalRiseInches: riseInches
        ) else { return nil }

        return DeckConnectionStairContext(
            edgeStart: start.position,
            edgeEnd: end.position,
            upperFacePolygon: stairFacePolygon(forEdgeId: upperEdge.id),
            lowerDestination: connectionLowerDestination(for: connection),
            riseInches: (riseInches ?? 0) > 0 ? riseInches : nil,
            treadCount: treadCount
        )
    }
}
