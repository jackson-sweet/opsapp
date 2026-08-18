// OPS/OPS/DeckBuilder/Models/DeckCanvasWorkspace.swift

import CoreGraphics
import Foundation

/// Session-scoped world bounds for Deck Designer's 2D editor.
///
/// Geometry coordinates remain authoritative and are never translated to fit a
/// viewport. Instead, the workspace grows around committed and previewed points
/// in predictable increments. Bounds only expand during a session so undo,
/// deletion, or a move back toward the centre cannot make the canvas jump.
struct DeckCanvasWorkspace: Equatable {
    /// Legacy 400' × 400' working area (1 canvas point is approximately 1 inch
    /// at the default scale). Retaining it as the minimum keeps existing designs
    /// and initial viewport behaviour stable.
    static let initialBounds = CGRect(x: 0, y: 0, width: 4_800, height: 4_800)

    /// Keep geometry this far inside a boundary so an active finger has room to
    /// continue drawing before it encounters the next expansion.
    static let expansionMargin: CGFloat = 240

    /// Grow in 40-foot increments instead of tracking a finger point-for-point.
    /// Deterministic chunks keep grid extents stable during continuous edge-pan.
    static let expansionQuantum: CGFloat = 480

    private(set) var bounds: CGRect

    init(bounds: CGRect = Self.initialBounds) {
        let standardized = bounds.standardized
        if standardized.origin.x.isFinite,
           standardized.origin.y.isFinite,
           standardized.width.isFinite,
           standardized.height.isFinite,
           standardized.width > 0,
           standardized.height > 0 {
            self.bounds = standardized
        } else {
            self.bounds = Self.initialBounds
        }
    }

    /// Expands the approached axes to include every finite point plus a safety
    /// margin. Returns whether the bounds changed.
    @discardableResult
    mutating func expand(toInclude points: [CGPoint]) -> Bool {
        let finitePoints = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard let first = finitePoints.first else { return false }

        var contentMinX = first.x
        var contentMinY = first.y
        var contentMaxX = first.x
        var contentMaxY = first.y
        for point in finitePoints.dropFirst() {
            contentMinX = min(contentMinX, point.x)
            contentMinY = min(contentMinY, point.y)
            contentMaxX = max(contentMaxX, point.x)
            contentMaxY = max(contentMaxY, point.y)
        }

        var nextMinX = bounds.minX
        var nextMinY = bounds.minY
        var nextMaxX = bounds.maxX
        var nextMaxY = bounds.maxY

        let requiredMinX = contentMinX - Self.expansionMargin
        let requiredMinY = contentMinY - Self.expansionMargin
        let requiredMaxX = contentMaxX + Self.expansionMargin
        let requiredMaxY = contentMaxY + Self.expansionMargin

        if requiredMinX < nextMinX {
            nextMinX = floor(requiredMinX / Self.expansionQuantum) * Self.expansionQuantum
        }
        if requiredMinY < nextMinY {
            nextMinY = floor(requiredMinY / Self.expansionQuantum) * Self.expansionQuantum
        }
        if requiredMaxX > nextMaxX {
            nextMaxX = ceil(requiredMaxX / Self.expansionQuantum) * Self.expansionQuantum
        }
        if requiredMaxY > nextMaxY {
            nextMaxY = ceil(requiredMaxY / Self.expansionQuantum) * Self.expansionQuantum
        }

        let next = CGRect(
            x: nextMinX,
            y: nextMinY,
            width: nextMaxX - nextMinX,
            height: nextMaxY - nextMinY
        )
        guard next != bounds else { return false }
        bounds = next
        return true
    }

    func screenPoint(fromWorld point: CGPoint, scale: CGFloat, offset: CGSize) -> CGPoint {
        let scale = Self.usableScale(scale)
        return CGPoint(
            x: point.x * scale + offset.width,
            y: point.y * scale + offset.height
        )
    }

    func worldPoint(fromScreen point: CGPoint, scale: CGFloat, offset: CGSize) -> CGPoint {
        let scale = Self.usableScale(scale)
        return CGPoint(
            x: (point.x - offset.width) / scale,
            y: (point.y - offset.height) / scale
        )
    }

    func visibleWorldRect(viewportSize: CGSize, scale: CGFloat, offset: CGSize) -> CGRect {
        let scale = Self.usableScale(scale)
        return CGRect(
            x: -offset.width / scale,
            y: -offset.height / scale,
            width: max(0, viewportSize.width) / scale,
            height: max(0, viewportSize.height) / scale
        )
    }

    /// Constrains camera overscroll while preserving room to draw beyond an
    /// existing edge. A touch-target-wide strip always remains recoverable. If
    /// the scaled workspace fits on an axis, it is centred instead of floating.
    func constrainedOffset(
        _ proposed: CGSize,
        scale: CGFloat,
        viewportSize: CGSize,
        minimumVisibleLength: CGFloat,
        centerWhenWorkspaceFits: Bool = true
    ) -> CGSize {
        let scale = Self.usableScale(scale)
        return CGSize(
            width: Self.constrainedAxisOffset(
                proposed.width,
                worldMin: bounds.minX,
                worldMax: bounds.maxX,
                scale: scale,
                viewportLength: viewportSize.width,
                minimumVisibleLength: minimumVisibleLength,
                centerWhenWorkspaceFits: centerWhenWorkspaceFits
            ),
            height: Self.constrainedAxisOffset(
                proposed.height,
                worldMin: bounds.minY,
                worldMax: bounds.maxY,
                scale: scale,
                viewportLength: viewportSize.height,
                minimumVisibleLength: minimumVisibleLength,
                centerWhenWorkspaceFits: centerWhenWorkspaceFits
            )
        )
    }

    private static func usableScale(_ scale: CGFloat) -> CGFloat {
        scale.isFinite && scale > 0 ? scale : 1
    }

    private static func constrainedAxisOffset(
        _ proposed: CGFloat,
        worldMin: CGFloat,
        worldMax: CGFloat,
        scale: CGFloat,
        viewportLength: CGFloat,
        minimumVisibleLength: CGFloat,
        centerWhenWorkspaceFits: Bool
    ) -> CGFloat {
        let viewportLength = max(0, viewportLength.isFinite ? viewportLength : 0)
        let reveal = min(
            max(0, minimumVisibleLength.isFinite ? minimumVisibleLength : 0),
            viewportLength / 2
        )
        let scaledMin = worldMin * scale
        let scaledMax = worldMax * scale
        let scaledLength = scaledMax - scaledMin
        let centered = viewportLength / 2 - (scaledMin + scaledMax) / 2

        if centerWhenWorkspaceFits, scaledLength <= viewportLength {
            return centered
        }

        let minimumOffset = reveal - scaledMax
        let maximumOffset = viewportLength - reveal - scaledMin
        let finiteProposal = proposed.isFinite ? proposed : centered
        return min(max(finiteProposal, minimumOffset), maximumOffset)
    }
}

/// Resolves rendered geometry that extends beyond persisted vertex positions.
/// Workspace bounds use these points without adding them to the deck payload.
enum DeckCanvasWorkspaceExtentResolver {
    /// Every point a stair actually occupies, resolved through the same plans
    /// the canvas draws — edge-attached AND level-connection. The envelope used
    /// to miss connection stairs entirely and to skip any edge stair whose
    /// tread count was auto-derived, so the workspace could clip geometry the
    /// user could plainly see.
    static func stairPoints(in drawingData: DeckDrawingData) -> [CGPoint] {
        var points: [CGPoint] = []

        if drawingData.isMultiLevel {
            for level in drawingData.levels {
                points += stairPoints(
                    edges: level.edges,
                    vertices: level.vertices,
                    drawingData: drawingData
                )
            }
            for connection in drawingData.levelConnections {
                guard let plan = drawingData.connectionStairPlan(for: connection) else { continue }
                points += plan.outline
            }
            return points
        }

        return stairPoints(
            edges: drawingData.edges,
            vertices: drawingData.vertices,
            drawingData: drawingData
        )
    }

    private static func stairPoints(
        edges: [DeckEdge],
        vertices: [DeckVertex],
        drawingData: DeckDrawingData
    ) -> [CGPoint] {
        let vertexByID = Dictionary(
            vertices.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return edges.flatMap { edge -> [CGPoint] in
            guard let start = vertexByID[edge.startVertexId]?.position,
                  let end = vertexByID[edge.endVertexId]?.position,
                  let plan = drawingData.edgeStairPlan(
                      for: edge,
                      edgeStart: start,
                      edgeEnd: end
                  ) else {
                return []
            }
            return plan.outline
        }
    }
}

/// Keeps camera reconciliation aligned with direct-manipulation lifetime.
/// Editing workflow state can remain active after a finger lifts, so perimeter
/// reorientation is tracked separately from the broader entry mode.
enum DeckCanvasPerimeterReorientationPhase {
    case changed
    case ended
}

enum DeckCanvasPerimeterReorientationCameraAction: Equatable {
    case stopCurrentMotion
    case centerOn(CGPoint)
    case reconcileWorkspace
}

enum DeckCanvasWorkspaceInteractionPolicy {
    static func isDirectManipulationActive(
        drawingMode: DrawingMode,
        isReorientingPerimeterDraft: Bool
    ) -> Bool {
        drawingMode != .idle || isReorientingPerimeterDraft
    }

    static func shouldCenterPerimeterAnchor(
        isReorientingPerimeterDraft: Bool
    ) -> Bool {
        !isReorientingPerimeterDraft
    }

    /// A direction drag owns the camera until the finger lifts. This explicit
    /// completion action is required even when the final direction matches the
    /// last drag update and therefore emits no final perimeter-state change.
    static func perimeterReorientationCameraAction(
        phase: DeckCanvasPerimeterReorientationPhase,
        activeAnchor: PerimeterEntryAnchor?
    ) -> DeckCanvasPerimeterReorientationCameraAction {
        switch phase {
        case .changed:
            return .stopCurrentMotion
        case .ended:
            if let activeAnchor {
                return .centerOn(activeAnchor.position)
            }
            return .reconcileWorkspace
        }
    }
}

/// Pure edge-pan velocity policy shared by the controller and its regression
/// tests. Keeping the math independent from the timer makes direction and
/// proportional speed deterministic.
enum DeckCanvasPanPolicy {
    static func delta(
        for location: CGPoint,
        viewportSize: CGSize,
        edgeZone: CGFloat,
        maxSpeed: CGFloat,
        interval: TimeInterval
    ) -> CGSize {
        guard location.x.isFinite,
              location.y.isFinite,
              viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.width > 0,
              viewportSize.height > 0,
              edgeZone.isFinite,
              edgeZone > 0,
              maxSpeed.isFinite,
              maxSpeed >= 0,
              interval.isFinite,
              interval > 0 else {
            return .zero
        }

        let pressX = edgePress(
            location: location.x,
            viewportLength: viewportSize.width,
            edgeZone: edgeZone
        )
        let pressY = edgePress(
            location: location.y,
            viewportLength: viewportSize.height,
            edgeZone: edgeZone
        )

        let easedX = pressX * abs(pressX)
        let easedY = pressY * abs(pressY)
        let tickDistance = maxSpeed * CGFloat(interval)
        return CGSize(
            width: -easedX * tickDistance,
            height: -easedY * tickDistance
        )
    }

    private static func edgePress(
        location: CGFloat,
        viewportLength: CGFloat,
        edgeZone: CGFloat
    ) -> CGFloat {
        if location < edgeZone {
            return max(-1, -(1 - location / edgeZone))
        }
        if location > viewportLength - edgeZone {
            return min(1, 1 - (viewportLength - location) / edgeZone)
        }
        return 0
    }
}

/// Keeps the point the operator is CREATING inside the viewport while they
/// draw or dictate a perimeter. Bug 5f285f64.
///
/// The camera used to follow the anchor — the vertex the current segment runs
/// FROM — and nothing followed the segment's far end. Dictating a long run
/// therefore walked the new point straight off the screen: the operator called
/// out a length and watched nothing happen, because the only thing the viewport
/// tracked was where they had already been.
///
/// The rule is "follow the work, minimally". The new point must always be
/// visible; the anchor comes along whenever both fit; and the camera nudges by
/// the smallest amount that achieves it rather than recentring. A recentre on
/// every dictated digit would throw the drawing across the screen and destroy
/// the operator's sense of where they are.
///
/// Everything here is screen-space and pure, so it is asserted directly rather
/// than through a rendered canvas.
enum DeckCanvasFollowPolicy {

    /// Offset delta to ADD to the canvas offset so `focus` — and `context` when
    /// there is room — sit inside `safeArea`. `.zero` when nothing must move.
    static func pan(
        focus: CGPoint,
        context: CGPoint?,
        safeArea: CGRect
    ) -> CGSize {
        guard focus.x.isFinite, focus.y.isFinite,
              safeArea.width > 0, safeArea.height > 0 else { return .zero }

        let contextPoint = context.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }

        // Prefer bringing the whole segment into view; fall back to the new
        // point alone when the segment is longer than the viewport.
        if let contextPoint {
            let span = boundingBox(focus, contextPoint)
            if span.width <= safeArea.width, span.height <= safeArea.height {
                return translation(bringing: span, into: safeArea)
            }
        }
        return translation(bringing: boundingBox(focus, focus), into: safeArea)
    }

    private static func boundingBox(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    /// Smallest translation that puts `box` inside `bounds`. Assumes `box`
    /// fits; when it does not, the leading edge wins so the caller keeps a
    /// deterministic anchor.
    private static func translation(bringing box: CGRect, into bounds: CGRect) -> CGSize {
        CGSize(
            width: axisTranslation(min: box.minX, max: box.maxX, boundsMin: bounds.minX, boundsMax: bounds.maxX),
            height: axisTranslation(min: box.minY, max: box.maxY, boundsMin: bounds.minY, boundsMax: bounds.maxY)
        )
    }

    private static func axisTranslation(
        min boxMin: CGFloat,
        max boxMax: CGFloat,
        boundsMin: CGFloat,
        boundsMax: CGFloat
    ) -> CGFloat {
        if boxMin < boundsMin { return boundsMin - boxMin }
        if boxMax > boundsMax { return boundsMax - boxMax }
        return 0
    }
}
