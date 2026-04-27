// OPS/OPS/DeckBuilder/Views/DeckCanvasView.swift

import SwiftUI
import UIKit

struct DeckCanvasView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel

    // MARK: - Transform State (driven by UIKit gestures)

    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero
    @State private var drawingStarted = false
    @State private var hasInitializedOffset = false

    // Drives the auto-pan when the user drags toward the viewport edge.
    // Lives on the view so its timer is torn down with the view.
    @StateObject private var edgePan = EdgePanController()

    // 4800 × 4800 pt workspace ≈ 400' × 400'
    private let canvasSize: CGFloat = 4800

    /// Width of the auto-pan zone along each viewport edge (canvas-untransformed pt).
    /// Thumb-sized so a finger naturally driven to the edge engages the pan, and so
    /// the gradient of pan velocity has enough room to feel proportional.
    private static let edgePanZone: CGFloat = 70

    /// Pan speed in pt/sec at the very edge of the viewport. Tunes the "feels right"
    /// of the auto-scroll. 700 pt/s clears a typical iPhone viewport in ~0.6s, which
    /// matches the tempo of dragging across the canvas at a normal sketch pace.
    private static let edgePanMaxSpeed: CGFloat = 700

    /// Zoom range over which annotation scaling is active. Outside this range we
    /// clamp to the nearest end so labels never become microscopic (at extreme
    /// zoom-in) or overwhelm the viewport (at extreme zoom-out).
    private static let annotationMinZoom: CGFloat = 0.3
    private static let annotationMaxZoom: CGFloat = 4.0

    /// Compute a canvas-space size for an annotation so it stays legible across the
    /// full zoom range. The returned value is in canvas points (pre-zoom). When the
    /// canvas is transformed by `canvasScale`, the on-screen size lives in the range
    /// [`minPt`, `maxPt`] as long as zoom is inside [annotationMinZoom,
    /// annotationMaxZoom]. Outside that range we hold the endpoint size so extreme
    /// zoom doesn't produce illegible text.
    private func scaledSize(_ basePt: CGFloat, min minPt: CGFloat = 8, max maxPt: CGFloat = 24) -> CGFloat {
        // Clamp zoom into the "labels track zoom" band before compensating. Pinning
        // to the endpoint outside the band gives a fixed on-screen size instead of
        // continuing to explode or shrink.
        let clampedZoom = Swift.min(Self.annotationMaxZoom, Swift.max(Self.annotationMinZoom, canvasScale))
        let compensated = basePt / clampedZoom
        return Swift.min(maxPt, Swift.max(minPt, compensated))
    }

    /// Grid spacing for dot rendering. Always a whole multiple of the snap increment so
    /// every dot sits on a valid snap position — never lies to the user about where snap
    /// points are. At extreme scales we render every Nth snap line (or finer subdivision)
    /// to keep visible density in the 12-60pt range, without changing the underlying snap.
    /// Pre-scale drawings use the same fallback as DeckBuilderViewModel so visible
    /// grid dots align with actual snap positions from the very first stroke.
    private var gridSpacing: CGFloat {
        let snapInches = viewModel.drawingData.config.lengthSnapIncrement
        let scale: Double
        if let s = viewModel.drawingData.scaleFactor, s > 0 {
            scale = s
        } else {
            scale = DeckBuilderViewModel.prescaleFallbackScale
        }
        let snapPt = CGFloat(snapInches * scale)
        let visiblePt = snapPt * canvasScale
        if visiblePt >= 12 { return snapPt }
        // Too dense on screen → skip every Nth snap line (powers of 2 look cleanest)
        var multiplier: CGFloat = 2
        while snapPt * multiplier * canvasScale < 12, multiplier < 64 {
            multiplier *= 2
        }
        return snapPt * multiplier
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                // Canvas content — sized to the viewport so Canvas always renders
                // at native pixel density. Pan + zoom are applied via context
                // transforms inside the Canvas closure (see canvasContent), so
                // strokes/text/dots stay crisp at any zoom level. Bug e289b094 —
                // previously the canvas was sized at canvasSize × canvasSize and
                // the outer .scaleEffect / .offset bitmap-scaled the rendered
                // output, causing visible blur at high zoom.
                canvasContent
                    .frame(width: geometry.size.width, height: geometry.size.height)

                // Selection overlays (screen space)
                selectionOverlay

                // Top info bar
                if viewModel.isClosed, let area = viewModel.totalArea {
                    dimensionInfoBar(area: area)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            // UIKit gesture layer — handles pinch + two-finger pan
            .overlay {
                CanvasGestureView(
                    scale: $canvasScale,
                    offset: $canvasOffset,
                    isDrawing: viewModel.drawingMode != .idle
                )
            }
            // SwiftUI gestures — single-finger drawing, tap, long-press
            .simultaneousGesture(viewModel.activeTool == .draw ? drawGesture(size: geometry.size) : nil)
            .simultaneousGesture(
                (viewModel.activeTool == .select || viewModel.activeTool == .lasso || viewModel.activeTool == .tapSelect)
                    ? selectionDragGesture(size: geometry.size) : nil
            )
            .simultaneousGesture(tapGesture(size: geometry.size))
            .simultaneousGesture(longPressGesture(size: geometry.size))
            .onAppear {
                if !hasInitializedOffset {
                    hasInitializedOffset = true
                    centerViewportOnGeometry(viewportSize: geometry.size)
                }
                wireEdgePan(viewportSize: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                // GeometryReader can re-fire on rotation / split-view; keep the
                // controller's notion of viewport in lockstep so edge zones don't
                // drift after a layout change.
                wireEdgePan(viewportSize: newSize)
            }
        }
    }

    /// Bind the edge-pan controller to the live view state. Called on appear and
    /// on viewport size changes so the closures always read current `canvasOffset`,
    /// `canvasScale`, viewport size, and drawingMode.
    private func wireEdgePan(viewportSize: CGSize) {
        edgePan.getCanvasOffset = { canvasOffset }
        edgePan.setCanvasOffset = { canvasOffset = $0 }
        edgePan.viewportSize = { viewportSize }
        edgePan.edgeZone = Self.edgePanZone
        edgePan.maxSpeed = Self.edgePanMaxSpeed
        edgePan.isDragActive = {
            switch viewModel.drawingMode {
            case .drawing, .draggingVertex, .selecting, .lassoing: return true
            case .idle: return false
            }
        }
        edgePan.onPan = {
            // Convert the latest finger position (in viewport coords) into canvas
            // space using the now-updated offset, then re-emit the drawing update
            // for whichever mode is active. Without this, the line/marquee would
            // appear frozen as the canvas slides past the finger.
            guard let location = edgePan.lastLocation else { return }
            let canvasPt = canvasPoint(from: location, in: viewportSize)
            switch viewModel.drawingMode {
            case .drawing:
                viewModel.updateLine(to: canvasPt)
            case .draggingVertex:
                viewModel.updateVertexDrag(to: canvasPt)
            case .selecting:
                viewModel.updateMarquee(to: canvasPt)
            case .lassoing:
                viewModel.updateLasso(to: canvasPt)
            case .idle:
                break
            }
        }
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        Canvas { context, size in
            // Apply pan + zoom inside the Canvas so it redraws at the viewport's
            // native pixel density at any scale. The outer scaleEffect/offset
            // were removed — see makeBody comment for the bug context (e289b094).
            // All draw* helpers below operate in world (canvas) coordinates;
            // this transform maps world → screen.
            var context = context
            context.translateBy(x: canvasOffset.width, y: canvasOffset.height)
            context.scaleBy(x: canvasScale, y: canvasScale)

            // drawGrid intentionally receives the world-space canvas extents so
            // its visible-rect culling math (lines ~260-263) operates on world
            // coordinates the same way it always did.
            drawGrid(context: context, size: CGSize(width: canvasSize, height: canvasSize))

            if viewModel.isMultiLevel {
                for (index, level) in viewModel.drawingData.levels.enumerated() {
                    if index != viewModel.activeLevelIndex {
                        drawInactiveLevel(context: context, level: level)
                    }
                }
                for connection in viewModel.drawingData.levelConnections {
                    drawLevelConnection(context: context, connection: connection)
                }
                if let activeLevel = viewModel.activeLevel {
                    drawLevelFootprint(context: context, level: activeLevel)
                    for edge in activeLevel.edges {
                        drawEdge(context: context, edge: edge, vertexLookup: activeLevel.vertex(byId:))
                    }
                    if case .drawing(_, let startPos, let currentEnd) = viewModel.drawingMode {
                        drawActiveLine(context: context, startPosition: startPos, currentEnd: currentEnd)
                        drawAlignmentGuides(context: context)
                    }
                    for vertex in activeLevel.vertices {
                        drawVertex(context: context, vertex: vertex)
                    }
                    for edge in activeLevel.edges {
                        drawDimensionLabel(context: context, edge: edge, vertexLookup: activeLevel.vertex(byId:), canvasSize: size)
                    }
                }
            } else {
                if viewModel.isClosed { drawFootprint(context: context) }
                if let poolDiameter = viewModel.drawingData.poolDiameter,
                   let scale = viewModel.drawingData.scaleFactor, scale > 0 {
                    drawPoolOverlay(context: context, diameterInches: poolDiameter, scaleFactor: scale)
                }
                for edge in viewModel.drawingData.edges {
                    drawEdge(context: context, edge: edge, vertexLookup: viewModel.drawingData.vertex(byId:))
                }
                if case .drawing(_, let startPos, let currentEnd) = viewModel.drawingMode {
                    drawActiveLine(context: context, startPosition: startPos, currentEnd: currentEnd)
                    drawAlignmentGuides(context: context)
                }
                for vertex in viewModel.drawingData.vertices {
                    drawVertex(context: context, vertex: vertex)
                }
                for edge in viewModel.drawingData.edges {
                    drawDimensionLabel(context: context, edge: edge, vertexLookup: viewModel.drawingData.vertex(byId:), canvasSize: size)
                }
            }

            // Marquee selection rectangle (canvas space)
            if case .selecting(let rect) = viewModel.drawingMode, rect.width > 0 || rect.height > 0 {
                drawMarqueeRect(context: context, rect: rect)
            }

            // Lasso selection path (canvas space)
            if case .lassoing(let points) = viewModel.drawingMode, points.count >= 2 {
                drawLassoPath(context: context, points: points)
            }
        }
    }

    // MARK: - Marquee Selection Rectangle

    private func drawMarqueeRect(context: GraphicsContext, rect: CGRect) {
        let path = Path(rect)
        context.fill(path, with: .color(OPSStyle.Colors.primaryAccent.opacity(0.05)))
        let stroke = scaledSize(1, min: 0.75, max: 2)
        context.stroke(path, with: .color(OPSStyle.Colors.primaryAccent),
                        style: StrokeStyle(lineWidth: stroke,
                                           dash: [scaledSize(6, min: 4, max: 10), scaledSize(4, min: 3, max: 7)]))
    }

    // MARK: - Lasso Selection Path

    private func drawLassoPath(context: GraphicsContext, points: [CGPoint]) {
        var path = Path()
        path.move(to: points[0])
        for i in 1..<points.count { path.addLine(to: points[i]) }
        let stroke = scaledSize(1.5, min: 1, max: 3)
        context.stroke(path, with: .color(OPSStyle.Colors.primaryAccent.opacity(0.7)),
                        style: StrokeStyle(lineWidth: stroke,
                                           dash: [scaledSize(6, min: 4, max: 10), scaledSize(3, min: 2, max: 6)]))
    }

    // MARK: - Grid (visible region only)

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        guard viewModel.drawingData.config.gridVisible else { return }
        let visMinX = max(0, -canvasOffset.width / canvasScale)
        let visMinY = max(0, -canvasOffset.height / canvasScale)
        let vpW = UIScreen.main.bounds.width / canvasScale
        let vpH = UIScreen.main.bounds.height / canvasScale
        let visMaxX = min(size.width, visMinX + vpW + gridSpacing)
        let visMaxY = min(size.height, visMinY + vpH + gridSpacing)

        let startCol = max(0, Int(floor(visMinX / gridSpacing)))
        let endCol = min(Int(size.width / gridSpacing), Int(ceil(visMaxX / gridSpacing)))
        let startRow = max(0, Int(floor(visMinY / gridSpacing)))
        let endRow = min(Int(size.height / gridSpacing), Int(ceil(visMaxY / gridSpacing)))

        guard startCol <= endCol, startRow <= endRow else { return }

        // Dots at grid intersections — not lines
        let dotRadius = scaledSize(1.0, min: 0.5, max: 2.0)
        let dotColor = Color.white.opacity(0.12)
        var dotPath = Path()
        for col in startCol...endCol {
            let x = CGFloat(col) * gridSpacing
            for row in startRow...endRow {
                let y = CGFloat(row) * gridSpacing
                dotPath.addEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius,
                                              width: dotRadius * 2, height: dotRadius * 2))
            }
        }
        context.fill(dotPath, with: .color(dotColor))
    }

    // MARK: - Footprint

    private func drawFootprint(context: GraphicsContext) {
        let positions = viewModel.drawingData.orderedPositions
        guard positions.count >= 3 else { return }
        var path = Path()
        path.move(to: positions[0])
        for i in 1..<positions.count { path.addLine(to: positions[i]) }
        path.closeSubpath()

        let isSelected = viewModel.selection.selectedFootprint
        let hasAssignment = !viewModel.drawingData.footprint.assignedItems.isEmpty
        let selfIntersecting = PolygonMath.isSelfIntersecting(vertices: positions)

        if selfIntersecting {
            drawSelfIntersectingWarningFill(context: context, path: path, positions: positions)
            return
        }

        // Non-zero fill matches the visible boundary for all simple polygons (convex + concave).
        // Avoids the even-odd "alternating regions" that confuse users on complex shapes.
        let fillStyle = FillStyle(eoFill: false)
        if hasAssignment {
            let fillColor: Color = {
                if let hex = viewModel.drawingData.footprint.assignedItems.first?.taskTypeColor, !hex.isEmpty,
                   let c = Color(hex: hex) { return c }
                return OPSStyle.Colors.primaryAccent
            }()
            context.fill(path, with: .color(fillColor.opacity(isSelected ? 0.15 : 0.08)), style: fillStyle)
        } else {
            context.fill(path, with: .color(Color.white.opacity(isSelected ? 0.08 : 0.03)), style: fillStyle)
        }

        // Surface material label at centroid — only when geometry is clean
        if let firstItem = viewModel.drawingData.footprint.assignedItems.first {
            drawSurfaceLabel(context: context, positions: positions, label: firstItem.name)
        }
    }

    /// Draw a clear visual warning when the polygon crosses itself — field workers need
    /// to SEE the problem, not read a small toast. Uses warningStatus + 45° hash so it
    /// reads as "broken" even in sunlight / on greyscale.
    private func drawSelfIntersectingWarningFill(context: GraphicsContext, path: Path, positions: [CGPoint]) {
        context.fill(path, with: .color(OPSStyle.Colors.warningStatus.opacity(0.12)), style: FillStyle(eoFill: false))

        // 45° diagonal hash clipped to the path
        var clipped = context
        clipped.clip(to: path)
        let bbox = path.boundingRect
        let spacing: CGFloat = 10
        let extent = max(bbox.width, bbox.height) * 2
        var hash = Path()
        var offset = -extent
        while offset < extent {
            let a = CGPoint(x: bbox.minX + offset, y: bbox.minY)
            let b = CGPoint(x: bbox.minX + offset + extent, y: bbox.minY + extent)
            hash.move(to: a)
            hash.addLine(to: b)
            offset += spacing
        }
        clipped.stroke(hash, with: .color(OPSStyle.Colors.warningStatus.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1))

        // Centroid warning label so the cause is obvious
        let cx = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let cy = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        let label = "EDGES CROSS — FIX SHAPE"
        let charW = scaledSize(7.5, min: 5, max: 12)
        let pillW = CGFloat(label.count) * charW + scaledSize(16, min: 10, max: 24)
        let pillH = scaledSize(22, min: 14, max: 30)
        let cr = scaledSize(4, min: 2, max: 6)
        let pillRect = CGRect(x: cx - pillW / 2, y: cy - pillH / 2, width: pillW, height: pillH)
        context.fill(Path(roundedRect: pillRect, cornerRadius: cr),
                     with: .color(OPSStyle.Colors.cardBackground.opacity(0.95)))
        context.stroke(Path(roundedRect: pillRect, cornerRadius: cr),
                       with: .color(OPSStyle.Colors.warningStatus), lineWidth: 1)
        let fontSize = scaledSize(10, min: 7, max: 16)
        context.draw(Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundColor(OPSStyle.Colors.warningStatus),
                     at: CGPoint(x: cx, y: cy))
    }

    private func drawSurfaceLabel(context: GraphicsContext, positions: [CGPoint], label: String) {
        let cx = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let cy = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        let charW = scaledSize(7, min: 5, max: 11)
        let pillW = CGFloat(label.count) * charW + scaledSize(16, min: 10, max: 22)
        let pillH = scaledSize(20, min: 14, max: 28)
        let cr = scaledSize(4, min: 2, max: 6)
        let pillRect = CGRect(x: cx - pillW / 2, y: cy - pillH / 2, width: pillW, height: pillH)
        context.fill(Path(roundedRect: pillRect, cornerRadius: cr),
                     with: .color(OPSStyle.Colors.cardBackground.opacity(0.9)))
        let fontSize = scaledSize(11, min: 8, max: 17)
        context.draw(Text(label).font(.system(size: fontSize, weight: .medium, design: .monospaced))
            .foregroundColor(OPSStyle.Colors.primaryAccent), at: CGPoint(x: cx, y: cy))
    }

    // MARK: - Pool Overlay

    private func drawPoolOverlay(context: GraphicsContext, diameterInches: Double, scaleFactor: Double) {
        let positions = viewModel.drawingData.orderedPositions
        guard positions.count >= 3 else { return }
        let cx = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let cy = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        let r = CGFloat(diameterInches * scaleFactor) / 2
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        let stroke = scaledSize(1.5, min: 1, max: 3)
        context.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.25)),
                        style: StrokeStyle(lineWidth: stroke,
                                           dash: [scaledSize(8, min: 5, max: 14), scaledSize(4, min: 3, max: 7)]))
        let fontSize = scaledSize(11, min: 8, max: 16)
        context.draw(Text("Pool").font(.system(size: fontSize, weight: .medium, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.35)), at: CGPoint(x: cx, y: cy))
    }

    // MARK: - Multi-Level Inactive

    private func drawInactiveLevel(context: GraphicsContext, level: DeckLevel) {
        let positions = level.orderedPositions
        guard positions.count >= 3 else { return }
        if level.isClosed {
            var p = Path(); p.move(to: positions[0])
            for i in 1..<positions.count { p.addLine(to: positions[i]) }
            p.closeSubpath()
            context.fill(p, with: .color(level.displayColor.swiftUIColor.opacity(0.08)), style: FillStyle(eoFill: false))
        }
        let inactiveStroke = scaledSize(1.5, min: 1, max: 3)
        for edge in level.edges {
            guard let s = level.vertex(byId: edge.startVertexId),
                  let e = level.vertex(byId: edge.endVertexId) else { continue }
            var ep = Path(); ep.move(to: s.position); ep.addLine(to: e.position)
            context.stroke(ep, with: .color(level.displayColor.swiftUIColor.opacity(0.2)), lineWidth: inactiveStroke)
        }
        let cx = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let cy = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        let levelLabelFont = scaledSize(11, min: 8, max: 17)
        context.draw(Text(level.name).font(.system(size: levelLabelFont, weight: .medium, design: .monospaced))
            .foregroundColor(level.displayColor.swiftUIColor.opacity(0.4)), at: CGPoint(x: cx, y: cy))
    }

    // MARK: - Multi-Level Active Footprint

    private func drawLevelFootprint(context: GraphicsContext, level: DeckLevel) {
        guard level.isClosed else { return }
        let positions = level.orderedPositions
        guard positions.count >= 3 else { return }
        var path = Path(); path.move(to: positions[0])
        for i in 1..<positions.count { path.addLine(to: positions[i]) }
        path.closeSubpath()

        if PolygonMath.isSelfIntersecting(vertices: positions) {
            drawSelfIntersectingWarningFill(context: context, path: path, positions: positions)
            return
        }

        let isSelected = viewModel.selection.selectedFootprint
        let levelFillColor: Color = {
            if let hex = level.footprint.assignedItems.first?.taskTypeColor, !hex.isEmpty,
               let c = Color(hex: hex) { return c }
            return level.displayColor.swiftUIColor
        }()
        context.fill(path, with: .color(levelFillColor.opacity(isSelected ? 0.12 : 0.06)), style: FillStyle(eoFill: false))
    }

    // MARK: - Level Connection

    private func drawLevelConnection(context: GraphicsContext, connection: LevelConnection) {
        guard let upperLevel = viewModel.drawingData.level(byId: connection.upperLevelId),
              let edge = upperLevel.edge(byId: connection.upperEdgeId),
              let start = upperLevel.vertex(byId: edge.startVertexId),
              let end = upperLevel.vertex(byId: edge.endVertexId) else { return }
        let dx = end.position.x - start.position.x
        let dy = end.position.y - start.position.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return }
        let perpX = -dy / len, perpY = dx / len
        let depth: CGFloat = 30
        let p1 = start.position, p2 = end.position
        let p3 = CGPoint(x: p2.x + perpX * depth, y: p2.y + perpY * depth)
        let p4 = CGPoint(x: p1.x + perpX * depth, y: p1.y + perpY * depth)
        var sp = Path(); sp.move(to: p1); sp.addLine(to: p2); sp.addLine(to: p3); sp.addLine(to: p4); sp.closeSubpath()
        context.fill(sp, with: .color(OPSStyle.Colors.warningStatus.opacity(0.08)))
        let outline = scaledSize(1.5, min: 1, max: 3)
        context.stroke(sp, with: .color(OPSStyle.Colors.warningStatus.opacity(0.4)), lineWidth: outline)
        let tc = connection.stairConfig.treadCount ?? 5
        guard tc > 1 else { return }
        let treadStroke = scaledSize(1, min: 0.75, max: 2)
        for i in 1..<min(tc, 20) {
            let t = CGFloat(i) / CGFloat(tc)
            let ls = CGPoint(x: p1.x + dx * t, y: p1.y + dy * t)
            let le = CGPoint(x: ls.x + perpX * depth, y: ls.y + perpY * depth)
            var hp = Path(); hp.move(to: ls); hp.addLine(to: le)
            context.stroke(hp, with: .color(OPSStyle.Colors.warningStatus.opacity(0.25)), lineWidth: treadStroke)
        }
        let lx = (p1.x + p3.x) / 2, ly = (p1.y + p3.y) / 2
        let labelFont = scaledSize(9, min: 7, max: 14)
        context.draw(Text("\(tc) treads").font(.system(size: labelFont, weight: .medium, design: .monospaced))
            .foregroundColor(OPSStyle.Colors.warningStatus.opacity(0.6)), at: CGPoint(x: lx, y: ly))
    }

    // MARK: - Edges

    private func drawEdge(context: GraphicsContext, edge: DeckEdge, vertexLookup: (String) -> DeckVertex?) {
        guard let start = vertexLookup(edge.startVertexId),
              let end = vertexLookup(edge.endVertexId) else { return }
        var path = Path(); path.move(to: start.position); path.addLine(to: end.position)
        let isSelected = viewModel.selection.selectedEdgeIds.contains(edge.id)

        // Railing indicator (subtle thicker line behind) — scales with zoom
        if edge.railingConfig != nil {
            let railingWidth = scaledSize(isSelected ? 6 : 4, min: 2.5, max: 10)
            context.stroke(path, with: .color(Color.white.opacity(0.15)), lineWidth: railingWidth)
        }

        // Main edge line — colored by task type, fallback to accent/white
        let lineColor: Color
        if edge.edgeType == .houseEdge {
            lineColor = OPSStyle.Colors.secondaryText.opacity(0.6)
        } else if let hex = edge.assignedItems.first?.taskTypeColor, !hex.isEmpty, let c = Color(hex: hex) {
            lineColor = c.opacity(isSelected ? 1.0 : 0.8)
        } else if let hex = edge.railingConfig?.assignedItems.first?.taskTypeColor, !hex.isEmpty, let c = Color(hex: hex) {
            lineColor = c.opacity(isSelected ? 1.0 : 0.8)
        } else if !edge.assignedItems.isEmpty || edge.railingConfig != nil {
            lineColor = OPSStyle.Colors.primaryAccent.opacity(isSelected ? 1.0 : 0.8)
        } else {
            lineColor = Color.white.opacity(isSelected ? 1.0 : 0.8)
        }
        let edgeStroke = scaledSize(isSelected ? 2.5 : 1.5, min: 1.0, max: 4.0)
        context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: edgeStroke))

        // Selection visibility — parallel offset lines + glow, all zoom-aware
        if isSelected {
            let glowWidth = scaledSize(6, min: 3, max: 10)
            context.stroke(path, with: .color(OPSStyle.Colors.primaryAccent.opacity(0.35)), lineWidth: glowWidth)

            let dx = end.position.x - start.position.x
            let dy = end.position.y - start.position.y
            let len = sqrt(dx * dx + dy * dy)
            if len > 0 {
                let offsetDist: CGFloat = scaledSize(3, min: 2, max: 6)
                let perpX = (-dy / len) * offsetDist
                let perpY = (dx / len) * offsetDist
                var offsetPath1 = Path()
                offsetPath1.move(to: CGPoint(x: start.position.x + perpX, y: start.position.y + perpY))
                offsetPath1.addLine(to: CGPoint(x: end.position.x + perpX, y: end.position.y + perpY))
                var offsetPath2 = Path()
                offsetPath2.move(to: CGPoint(x: start.position.x - perpX, y: start.position.y - perpY))
                offsetPath2.addLine(to: CGPoint(x: end.position.x - perpX, y: end.position.y - perpY))
                let offsetColor = OPSStyle.Colors.primaryAccent.opacity(0.5)
                let offsetWidth = scaledSize(1, min: 0.75, max: 2)
                context.stroke(offsetPath1, with: .color(offsetColor), lineWidth: offsetWidth)
                context.stroke(offsetPath2, with: .color(offsetColor), lineWidth: offsetWidth)
            }
        }

        // House edge — diagonal 45° hatch on the house side (architectural wall convention)
        if edge.edgeType == .houseEdge {
            drawHouseHatch(context: context, start: start.position, end: end.position)
        }

        // Stair indicator
        if edge.stairConfig != nil {
            drawStairIndicator(context: context, start: start.position, end: end.position, edge: edge)
        }
    }

    /// Architectural wall hatch: short 45° lines on the interior side of a house edge + "HOUSE" label
    private func drawHouseHatch(context: GraphicsContext, start: CGPoint, end: CGPoint) {
        let dx = end.x - start.x, dy = end.y - start.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 4 else { return }
        let nx = dx / len, ny = dy / len
        let perpX = -ny, perpY = nx
        // Hatch spacing and length track zoom so the pattern density is consistent.
        let spacing: CGFloat = scaledSize(8, min: 6, max: 16)
        let hatchLen: CGFloat = scaledSize(6, min: 4, max: 12)
        let count = Int(len / spacing)
        guard count >= 1 else { return }
        var hatchPath = Path()
        for i in 1...count {
            let t = CGFloat(i) * spacing
            let bx = start.x + nx * t
            let by = start.y + ny * t
            hatchPath.move(to: CGPoint(x: bx, y: by))
            hatchPath.addLine(to: CGPoint(x: bx + (perpX - nx) * hatchLen * 0.7,
                                          y: by + (perpY - ny) * hatchLen * 0.7))
        }
        let hatchStroke = scaledSize(1, min: 0.75, max: 2)
        context.stroke(hatchPath, with: .color(OPSStyle.Colors.secondaryText.opacity(0.35)), lineWidth: hatchStroke)

        if len > 40 {
            let labelOffset: CGFloat = scaledSize(12, min: 9, max: 20)
            let midX = (start.x + end.x) / 2 + perpX * labelOffset
            let midY = (start.y + end.y) / 2 + perpY * labelOffset
            let fontSize = scaledSize(9, min: 7, max: 15)
            context.draw(
                Text("HOUSE")
                    .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.7)),
                at: CGPoint(x: midX, y: midY)
            )
        }
    }

    /// Draw stairs extending PERPENDICULAR from the edge, to scale.
    /// The stair rectangle extends outward from the deck edge with tread lines inside.
    private func drawStairIndicator(context: GraphicsContext, start: CGPoint, end: CGPoint, edge: DeckEdge) {
        guard let config = edge.stairConfig, let tc = config.treadCount, tc > 0 else { return }
        let dx = end.x - start.x, dy = end.y - start.y
        let edgeLen = sqrt(dx * dx + dy * dy)
        guard edgeLen > 0 else { return }

        // Edge direction (unit vectors)
        let edgeNx = dx / edgeLen, edgeNy = dy / edgeLen
        // Perpendicular unit vector (90° CCW from edge — outward from deck).
        // The previous form divided by edgeLen twice (the components are already
        // unit-vector terms), which scaled the perpendicular by 1/edgeLen and
        // made stair depth shrink as edges got longer.
        let perpUnitX = -edgeNy, perpUnitY = edgeNx

        // Stair width in canvas points
        let scale = viewModel.drawingData.scaleFactor ?? 1.0
        let stairWidthCanvas = min(CGFloat(config.width) * CGFloat(scale), edgeLen)

        // Stair run depth in canvas points (totalRun = treadCount * runPerTread)
        let totalRunInches = Double(tc) * config.runPerTread
        let stairDepthCanvas = CGFloat(totalRunInches) * CGFloat(scale)

        // Position along the edge based on alignment + offset
        let offsetCanvas = CGFloat(config.offset) * CGFloat(scale)
        let gapTotal = edgeLen - stairWidthCanvas
        let stairStartT: CGFloat  // fraction along edge where stair begins
        switch config.alignment {
        case .left:
            stairStartT = offsetCanvas / edgeLen
        case .center:
            stairStartT = (gapTotal / 2 + offsetCanvas) / edgeLen
        case .right:
            stairStartT = (gapTotal - offsetCanvas) / edgeLen
        }

        // Four corners of the stair rectangle
        let baseStart = CGPoint(
            x: start.x + edgeNx * edgeLen * stairStartT,
            y: start.y + edgeNy * edgeLen * stairStartT
        )
        let baseEnd = CGPoint(
            x: baseStart.x + edgeNx * stairWidthCanvas,
            y: baseStart.y + edgeNy * stairWidthCanvas
        )
        let farStart = CGPoint(
            x: baseStart.x + perpUnitX * stairDepthCanvas,
            y: baseStart.y + perpUnitY * stairDepthCanvas
        )
        let farEnd = CGPoint(
            x: baseEnd.x + perpUnitX * stairDepthCanvas,
            y: baseEnd.y + perpUnitY * stairDepthCanvas
        )

        // Stair outline rectangle
        var rectPath = Path()
        rectPath.move(to: baseStart)
        rectPath.addLine(to: baseEnd)
        rectPath.addLine(to: farEnd)
        rectPath.addLine(to: farStart)
        rectPath.closeSubpath()

        // Hatched fill + outline — outline scales with zoom
        context.fill(rectPath, with: .color(OPSStyle.Colors.warningStatus.opacity(0.06)))
        let outlineStroke = scaledSize(1.5, min: 1, max: 3)
        context.stroke(rectPath, with: .color(OPSStyle.Colors.warningStatus.opacity(0.4)),
                        style: StrokeStyle(lineWidth: outlineStroke))

        // Tread lines (perpendicular to stair run direction, evenly spaced)
        let treadStroke = scaledSize(1, min: 0.75, max: 2)
        for i in 1..<min(tc, 30) {
            let t = CGFloat(i) / CGFloat(tc)
            let treadBase = CGPoint(
                x: baseStart.x + perpUnitX * stairDepthCanvas * t,
                y: baseStart.y + perpUnitY * stairDepthCanvas * t
            )
            let treadEnd = CGPoint(
                x: baseEnd.x + perpUnitX * stairDepthCanvas * t,
                y: baseEnd.y + perpUnitY * stairDepthCanvas * t
            )
            var treadPath = Path()
            treadPath.move(to: treadBase)
            treadPath.addLine(to: treadEnd)
            context.stroke(treadPath, with: .color(OPSStyle.Colors.warningStatus.opacity(0.25)), lineWidth: treadStroke)
        }

        // Label: tread count + run
        let labelX = (baseStart.x + farEnd.x) / 2
        let labelY = (baseStart.y + farEnd.y) / 2
        let runLabel = DimensionEngine.formatImperial(totalRunInches)
        let labelFont = scaledSize(9, min: 7, max: 15)
        context.draw(
            Text("\(tc) treads · \(runLabel)")
                .font(.system(size: labelFont, weight: .semibold, design: .monospaced))
                .foregroundColor(OPSStyle.Colors.warningStatus.opacity(0.7)),
            at: CGPoint(x: labelX, y: labelY)
        )
    }

    // MARK: - Active Drawing Line

    /// Render the in-progress line from `startPosition` to `currentEnd`.
    /// `startPosition` comes straight from the DrawingMode case and is the
    /// authoritative anchor — when the drag began in empty space the start
    /// vertex doesn't exist yet, so a vertex lookup would fail.
    private func drawActiveLine(context: GraphicsContext, startPosition: CGPoint, currentEnd: CGPoint) {
        var path = Path(); path.move(to: startPosition); path.addLine(to: currentEnd)
        let activeStroke = scaledSize(1.5, min: 1, max: 3)
        let activeDash = [scaledSize(8, min: 5, max: 14), scaledSize(4, min: 3, max: 8)]
        context.stroke(path, with: .color(Color.white.opacity(0.6)),
                        style: StrokeStyle(lineWidth: activeStroke, dash: activeDash))

        let distance = SnapEngine.distance(startPosition, currentEnd)
        guard distance > 1 else { return }

        // Dimension — show real-world length if calibrated, otherwise read against the
        // same prescale fallback the snap engine uses so the live drag readout matches
        // the snapped commit. Bug 4c30cd77 — previously the display used 20 pt/foot
        // while the snap used 2 pt/inch (24 pt/foot), and the format was whole-feet
        // only ("~%.0f'"), so a drag that snapped to 3'6" displayed as "~4'" mid-drag
        // and jumped on release. Use DimensionEngine.format with the prescale fallback
        // so the readout shows the snapped value at full precision (6" by default).
        let dimText: String
        if let scale = viewModel.drawingData.scaleFactor, scale > 0.001 {
            let inches = distance / scale
            dimText = DimensionEngine.format(inches, system: viewModel.drawingData.config.measurementSystem)
        } else {
            let inches = distance / DeckBuilderViewModel.prescaleFallbackScale
            dimText = "~" + DimensionEngine.format(inches, system: viewModel.drawingData.config.measurementSystem)
        }

        // Angle — relative if extending from an existing vertex, else absolute.
        // We only attempt the relative-angle lookup when the start is anchored
        // on a real vertex (fromVertexId != nil in DrawingMode).
        let angleText: String
        if case .drawing(let fromId, _, _) = viewModel.drawingMode,
           let fromVertexId = fromId {
            let edges = viewModel.isMultiLevel ? (viewModel.activeLevel?.edges ?? []) : viewModel.drawingData.edges
            let connected = edges.filter { $0.startVertexId == fromVertexId || $0.endVertexId == fromVertexId }
            if let prev = connected.last {
                let otherId = prev.startVertexId == fromVertexId ? prev.endVertexId : prev.startVertexId
                if let other = resolveVertex(byId: otherId) {
                    let prevA = SnapEngine.lineAngle(from: startPosition, to: other.position)
                    let newA = SnapEngine.lineAngle(from: startPosition, to: currentEnd)
                    var rel = newA - prevA; if rel < 0 { rel += 360 }; if rel > 180 { rel = 360 - rel }
                    angleText = String(format: "%.0f\u{00B0}", rel)
                } else {
                    angleText = String(format: "%.0f\u{00B0}", SnapEngine.lineAngle(from: startPosition, to: currentEnd))
                }
            } else {
                angleText = String(format: "%.0f\u{00B0}", SnapEngine.lineAngle(from: startPosition, to: currentEnd))
            }
        } else {
            angleText = String(format: "%.0f\u{00B0}", SnapEngine.lineAngle(from: startPosition, to: currentEnd))
        }

        let label = "\(dimText)  \(angleText)"
        let midX = (startPosition.x + currentEnd.x) / 2
        let midY = (startPosition.y + currentEnd.y) / 2

        // Dark pill background
        let aCharW = scaledSize(7.5, min: 5, max: 12)
        let aPillW = CGFloat(label.count) * aCharW + scaledSize(20, min: 12, max: 28)
        let aPillH = scaledSize(22, min: 14, max: 30)
        let aOffset = scaledSize(30, min: 20, max: 44)
        let aCR = scaledSize(4, min: 2, max: 6)
        let pillRect = CGRect(x: midX - aPillW / 2, y: midY - aOffset - aPillH / 2, width: aPillW, height: aPillH)
        context.fill(Path(roundedRect: pillRect, cornerRadius: aCR),
                     with: .color(OPSStyle.Colors.cardBackground.opacity(0.95)))
        context.stroke(Path(roundedRect: pillRect, cornerRadius: aCR),
                       with: .color(Color.white.opacity(0.1)), lineWidth: 0.5)
        let aFontSize = scaledSize(11, min: 8, max: 18)
        context.draw(Text(label).font(.system(size: aFontSize, weight: .semibold, design: .monospaced))
            .foregroundColor(Color.white), at: CGPoint(x: midX, y: midY - aOffset))
    }

    // MARK: - Alignment Guides

    /// Render dotted alignment guide lines when the drawing endpoint aligns with existing geometry
    private func drawAlignmentGuides(context: GraphicsContext) {
        let guides = viewModel.alignmentGuides
        guard !guides.isEmpty else { return }

        let guideStroke = scaledSize(0.75, min: 0.5, max: 1.5)
        let shortDashA = scaledSize(4, min: 3, max: 7)
        let longDashA = scaledSize(8, min: 5, max: 14)
        let dashB = scaledSize(4, min: 3, max: 7)

        for guide in guides {
            var path = Path()
            path.move(to: guide.from)
            path.addLine(to: guide.to)

            let color: Color
            let dashPattern: [CGFloat]

            switch guide.type {
            case .horizontal, .vertical:
                color = Color.cyan.opacity(0.6)
                dashPattern = [shortDashA, dashB]
            case .parallel:
                color = OPSStyle.Colors.primaryAccent.opacity(0.5)
                dashPattern = [longDashA, dashB]
            case .perpendicular:
                color = OPSStyle.Colors.successStatus.opacity(0.5)
                dashPattern = [longDashA, dashB]
            }

            context.stroke(path, with: .color(color),
                            style: StrokeStyle(lineWidth: guideStroke, dash: dashPattern))

            if guide.type == .horizontal || guide.type == .vertical {
                let refOffset = scaledSize(20, min: 14, max: 30)
                let refPoint = guide.type == .horizontal
                    ? CGPoint(x: guide.from.x + refOffset, y: guide.from.y)
                    : CGPoint(x: guide.from.x, y: guide.from.y + refOffset)
                let dotR = scaledSize(3, min: 2, max: 5)
                let dotRect = CGRect(x: refPoint.x - dotR, y: refPoint.y - dotR,
                                      width: dotR * 2, height: dotR * 2)
                context.fill(Path(ellipseIn: dotRect), with: .color(color))
            }

            if let label = guide.referenceLabel {
                let midX = (guide.from.x + guide.to.x) / 2
                let midY = (guide.from.y + guide.to.y) / 2
                let labelFont = scaledSize(10, min: 7, max: 16)
                let labelOffset = scaledSize(10, min: 7, max: 16)
                context.draw(
                    Text(label)
                        .font(.system(size: labelFont, weight: .bold, design: .monospaced))
                        .foregroundColor(color),
                    at: CGPoint(x: midX, y: midY - labelOffset)
                )
            }
        }
    }

    // MARK: - Vertices

    private func drawVertex(context: GraphicsContext, vertex: DeckVertex) {
        let isSelected = viewModel.selection.selectedVertexIds.contains(vertex.id)
        // Vertex markers are annotations — keep them consistently sized on screen.
        let r: CGFloat = scaledSize(isSelected ? 7 : 5, min: 3.5, max: 12)

        if isSelected {
            let outerR = r + scaledSize(4, min: 3, max: 7)
            let outerRing = CGRect(x: vertex.position.x - outerR, y: vertex.position.y - outerR,
                                    width: outerR * 2, height: outerR * 2)
            context.stroke(Path(ellipseIn: outerRing), with: .color(Color.white),
                           lineWidth: scaledSize(2, min: 1.25, max: 3.5))

            let innerR = r + scaledSize(1, min: 0.75, max: 2)
            let innerRing = CGRect(x: vertex.position.x - innerR, y: vertex.position.y - innerR,
                                    width: innerR * 2, height: innerR * 2)
            context.stroke(Path(ellipseIn: innerRing), with: .color(OPSStyle.Colors.primaryAccent.opacity(0.6)),
                           lineWidth: scaledSize(1.5, min: 1, max: 2.5))
        }

        let dot = CGRect(x: vertex.position.x - r, y: vertex.position.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: dot), with: .color(isSelected ? OPSStyle.Colors.primaryAccent : Color.white))

        if let elevation = vertex.elevation {
            let label = DimensionEngine.formatImperial(elevation * 12)
            let elevFontSize = scaledSize(10, min: 7, max: 16)
            let elevOffset = scaledSize(12, min: 8, max: 18)
            context.draw(Text(label).font(.system(size: elevFontSize, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText), at: CGPoint(x: vertex.position.x, y: vertex.position.y + r + elevOffset))
        }
    }

    // MARK: - Dimension Labels (offset from line with dark pill)

    private func drawDimensionLabel(context: GraphicsContext, edge: DeckEdge, vertexLookup: (String) -> DeckVertex?, canvasSize: CGSize) {
        guard let dim = edge.dimension,
              let start = vertexLookup(edge.startVertexId),
              let end = vertexLookup(edge.endVertexId) else { return }

        let midX = (start.position.x + end.position.x) / 2
        let midY = (start.position.y + end.position.y) / 2
        // Stale flag wins over the raw value: prefix the label so the user
        // sees at a glance that the typed dimension and the drawn length are
        // out of sync (e.g. they dragged a vertex that was on a manually-typed
        // edge — the field crew expects a warning, not silent mismatch).
        let baseLabel = DimensionEngine.format(dim, system: viewModel.drawingData.config.measurementSystem)
        let label = edge.dimensionStale ? "\u{26A0} \(baseLabel)" : baseLabel
        let hasAccuracy = edge.accuracyPercent != nil
        let isStale = edge.dimensionStale

        // Offset label perpendicular to the edge so it doesn't sit on the line
        let dx = end.position.x - start.position.x
        let dy = end.position.y - start.position.y
        let len = sqrt(dx * dx + dy * dy)
        let offsetDist = scaledSize(18, min: 12, max: 30)
        let perpX = len > 0 ? (-dy / len) * offsetDist : 0
        let perpY = len > 0 ? (dx / len) * offsetDist : -offsetDist
        let rawLabelX = midX + perpX
        let labelY = midY + perpY

        // Dark pill background
        let charW = scaledSize(7.5, min: 5, max: 12)
        let pillW = CGFloat(label.count) * charW + scaledSize(16, min: 10, max: 24)
        let pillH = scaledSize(20, min: 14, max: 28)
        let cr = scaledSize(4, min: 2, max: 6)

        // Clamp horizontally so labels at edge-of-canvas vertices don't bleed
        // into the rounded screen corners — canvas runs full-bleed (top +
        // horizontal safe area ignored), so without this any vertex placed
        // near the screen edge produces a label that sits half off-screen.
        let edgeBuffer: CGFloat = 16
        let halfPill = pillW / 2
        let minX = halfPill + edgeBuffer
        let maxX = max(minX, canvasSize.width - halfPill - edgeBuffer)
        let labelX = min(max(rawLabelX, minX), maxX)

        let pillRect = CGRect(x: labelX - pillW / 2, y: labelY - pillH / 2, width: pillW, height: pillH)
        let pillColor: Color = (isStale || hasAccuracy)
            ? OPSStyle.Colors.warningStatus.opacity(0.15)
            : OPSStyle.Colors.cardBackground.opacity(0.95)
        context.fill(Path(roundedRect: pillRect, cornerRadius: cr), with: .color(pillColor))
        context.stroke(Path(roundedRect: pillRect, cornerRadius: cr),
                       with: .color(Color.white.opacity(0.08)), lineWidth: 0.5)

        let fontSize = scaledSize(11, min: 8, max: 18)
        let labelColor: Color = (isStale || hasAccuracy) ? OPSStyle.Colors.warningStatus : Color.white
        context.draw(Text(label).font(.system(size: fontSize, weight: .medium, design: .monospaced))
            .foregroundColor(labelColor), at: CGPoint(x: labelX, y: labelY))

        // Secondary label below dimension: stale notice > accuracy > material/type.
        var secondaryLabel: String?
        var secondaryColor: Color = OPSStyle.Colors.secondaryText

        if isStale {
            secondaryLabel = "DRAWN LENGTH CHANGED"
            secondaryColor = OPSStyle.Colors.warningStatus
        } else if let accuracy = edge.accuracyPercent {
            secondaryLabel = AccuracyModel.formatAccuracy(dimensionInches: dim, accuracyPercent: accuracy,
                                                           system: viewModel.drawingData.config.measurementSystem)
            secondaryColor = OPSStyle.Colors.warningStatus
        } else if let railing = edge.railingConfig {
            secondaryLabel = railing.railingType.displayName.uppercased()
        } else if edge.edgeType == .houseEdge {
            secondaryLabel = "HOUSE"
        } else if let item = edge.assignedItems.first {
            secondaryLabel = item.name.uppercased()
        } else if edge.dimensionSource == .ar {
            secondaryLabel = "AR"
            secondaryColor = OPSStyle.Colors.successStatus.opacity(0.6)
        }

        if let secText = secondaryLabel {
            let secOffset = scaledSize(12, min: 8, max: 18)
            context.draw(Text(secText)
                .font(.system(size: scaledSize(9, min: 6, max: 14), weight: .medium, design: .monospaced))
                .foregroundColor(secondaryColor), at: CGPoint(x: labelX, y: labelY + secOffset))
        }
    }

    // MARK: - Selection Overlay (screen space — summary + height overlay)

    @ViewBuilder
    private var selectionOverlay: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear // fill ZStack

            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                // Deck height overlay
                deckHeightOverlay
                // Selection summary overlay
                selectionSummaryContent
            }
            .padding(.leading, 12)
            .padding(.bottom, 12)
        }
    }

    /// Deck height persistent overlay
    @ViewBuilder
    private var deckHeightOverlay: some View {
        if let heightText = deckHeightDisplayText {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(heightText)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(Color.white.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(OPSStyle.Colors.cardBackground.opacity(0.85))
            .cornerRadius(6)
        }
    }

    /// Compute deck height display: uniform or averaged per-vertex
    private var deckHeightDisplayText: String? {
        if viewModel.isMultiLevel, let level = viewModel.activeLevel, let elev = level.elevation {
            return "Height: \(formatElevation(elev))"
        }

        if let overall = viewModel.drawingData.overallElevation, overall > 0 {
            return "Height: \(formatElevation(overall))"
        }

        let vertices = viewModel.isMultiLevel
            ? (viewModel.activeLevel?.vertices ?? [])
            : viewModel.drawingData.vertices
        let elevations = vertices.compactMap { $0.elevation }
        guard !elevations.isEmpty else { return nil }
        let avg = elevations.reduce(0, +) / Double(elevations.count)
        if elevations.allSatisfy({ abs($0 - avg) < 0.01 }) {
            return "Height: \(formatElevation(avg))"
        }
        return "Avg Height: \(formatElevation(avg))"
    }

    private func formatElevation(_ feet: Double) -> String {
        let wholeFeet = Int(feet)
        let inches = Int((feet - Double(wholeFeet)) * 12)
        if inches == 0 { return "\(wholeFeet)'" }
        return "\(wholeFeet)' \(inches)\""
    }

    /// Bottom-left selection count (e.g., "2 vertices, 1 edge")
    @ViewBuilder
    private var selectionSummaryContent: some View {
        let vCount = viewModel.selection.selectedVertexIds.count
        let eCount = viewModel.selection.selectedEdgeIds.count
        let fCount = viewModel.selection.selectedFootprint ? 1 : 0
        if vCount + eCount + fCount > 0 {
            let parts = [
                vCount > 0 ? "\(vCount) vert\(vCount == 1 ? "ex" : "ices")" : nil,
                eCount > 0 ? "\(eCount) edge\(eCount == 1 ? "" : "s")" : nil,
                fCount > 0 ? "1 surface" : nil
            ].compactMap { $0 }
            Text(parts.joined(separator: ", "))
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(Color.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(OPSStyle.Colors.cardBackground.opacity(0.85))
                .cornerRadius(6)
        }
    }

    // MARK: - Info Bar

    @ViewBuilder
    private func dimensionInfoBar(area: Double) -> some View {
        VStack {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Label(DimensionEngine.formatArea(area, system: viewModel.drawingData.config.measurementSystem),
                      systemImage: "square.dashed")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(Color.white)
                if let perimeter = viewModel.totalPerimeter {
                    Label(DimensionEngine.format(perimeter, system: viewModel.drawingData.config.measurementSystem),
                          systemImage: "ruler")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackground.opacity(0.9))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func resolveVertex(byId id: String) -> DeckVertex? {
        if viewModel.isMultiLevel {
            for level in viewModel.drawingData.levels {
                if let v = level.vertex(byId: id) { return v }
            }
            return nil
        }
        return viewModel.drawingData.vertex(byId: id)
    }

    // MARK: - Viewport Centering

    /// Center the viewport on existing geometry, or on the canvas center if no geometry.
    private func centerViewportOnGeometry(viewportSize: CGSize) {
        let allVerts = viewModel.drawingData.allVertices
        guard !allVerts.isEmpty else {
            // No geometry — center on canvas midpoint
            canvasOffset = CGSize(
                width: (viewportSize.width - canvasSize) / 2,
                height: (viewportSize.height - canvasSize) / 2
            )
            return
        }

        // Bounding box of all vertices
        let xs = allVerts.map { $0.position.x }
        let ys = allVerts.map { $0.position.y }
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let geoCenterX = (minX + maxX) / 2
        let geoCenterY = (minY + maxY) / 2

        // Fit geometry with padding — scale so shape fills ~60% of viewport
        let geoW = max(maxX - minX, 1)
        let geoH = max(maxY - minY, 1)
        let fitScaleX = (viewportSize.width * 0.6) / geoW
        let fitScaleY = (viewportSize.height * 0.6) / geoH
        let fitScale = max(0.15, min(8.0, min(fitScaleX, fitScaleY)))
        canvasScale = fitScale

        // Offset so geometry center maps to viewport center
        canvasOffset = CGSize(
            width: viewportSize.width / 2 - geoCenterX * fitScale,
            height: viewportSize.height / 2 - geoCenterY * fitScale
        )
    }

    // MARK: - Coordinate Conversion

    private func canvasPoint(from location: CGPoint, in size: CGSize) -> CGPoint {
        // Clamp to the canvas workspace so vertices created from the gesture
        // can't drift to (7200, 6800) when the user pinches way out and taps
        // beyond the canvas edge. Off-workspace vertices render invisible but
        // still count toward perimeter / area.
        let raw = CGPoint(
            x: (location.x - canvasOffset.width) / canvasScale,
            y: (location.y - canvasOffset.height) / canvasScale
        )
        return CGPoint(
            x: min(max(0, raw.x), canvasSize),
            y: min(max(0, raw.y), canvasSize)
        )
    }

    // MARK: - Drawing Gesture (single-finger: long-press 0.2s → drag)

    private func drawGesture(size: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 5))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    guard let drag = drag else { return }
                    let point = canvasPoint(from: drag.location, in: size)
                    let startPoint = canvasPoint(from: drag.startLocation, in: size)
                    switch viewModel.activeTool {
                    case .draw:
                        if !drawingStarted {
                            drawingStarted = true
                            // Vertex drag takes priority: if drag starts on/near a selected vertex, move it
                            let hitR = max(22.0, 25.0 / canvasScale)
                            if let vertexId = PolygonMath.findVertexAtPoint(startPoint,
                                    vertices: viewModel.isMultiLevel ? (viewModel.activeLevel?.vertices ?? []) : viewModel.drawingData.vertices,
                                    hitThreshold: hitR),
                               viewModel.selection.selectedVertexIds.contains(vertexId) {
                                viewModel.beginVertexDrag(vertexId)
                            } else {
                                viewModel.beginLine(from: startPoint)
                            }
                            edgePan.startTracking(location: drag.location)
                        }
                        if case .draggingVertex = viewModel.drawingMode {
                            viewModel.updateVertexDrag(to: point)
                        } else {
                            viewModel.updateLine(to: point)
                        }
                    case .select:
                        if !drawingStarted {
                            drawingStarted = true
                            viewModel.beginMarquee(at: startPoint)
                            edgePan.startTracking(location: drag.location)
                        }
                        viewModel.updateMarquee(to: point)
                    case .lasso:
                        if !drawingStarted {
                            drawingStarted = true
                            viewModel.beginLasso(at: startPoint)
                            edgePan.startTracking(location: drag.location)
                        }
                        viewModel.updateLasso(to: point)
                    case .tapSelect, .none: break
                    }
                    // Keep the auto-pan controller in sync with the latest finger
                    // position on every frame regardless of which sub-mode we're in.
                    edgePan.updateLocation(drag.location)
                default: break
                }
            }
            .onEnded { value in
                switch value {
                case .second(true, let drag):
                    guard let drag = drag, drawingStarted else { break }
                    let point = canvasPoint(from: drag.location, in: size)
                    switch viewModel.activeTool {
                    case .draw:
                        if case .draggingVertex = viewModel.drawingMode {
                            viewModel.endVertexDrag()
                        } else {
                            viewModel.endLine(at: point)
                        }
                    case .select: viewModel.endMarquee()
                    case .lasso: viewModel.endLasso()
                    case .tapSelect, .none: break
                    }
                default: break
                }
                edgePan.stopTracking()
                drawingStarted = false
            }
    }

    // MARK: - Selection Drag Gesture (immediate one-finger drag, no long press)

    private func selectionDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                let point = canvasPoint(from: value.location, in: size)
                let startPoint = canvasPoint(from: value.startLocation, in: size)
                // In multi-select mode, marquee drag is the default (rectangular add).
                // Lasso tool keeps its freeform behavior.
                let useLasso = viewModel.activeTool == .lasso
                if !drawingStarted {
                    drawingStarted = true
                    if useLasso {
                        viewModel.beginLasso(at: startPoint)
                    } else {
                        viewModel.beginMarquee(at: startPoint)
                    }
                    edgePan.startTracking(location: value.location)
                }
                if useLasso {
                    viewModel.updateLasso(to: point)
                } else {
                    viewModel.updateMarquee(to: point)
                }
                edgePan.updateLocation(value.location)
            }
            .onEnded { _ in
                if viewModel.activeTool == .lasso {
                    viewModel.endLasso()
                } else {
                    viewModel.endMarquee()
                }
                edgePan.stopTracking()
                drawingStarted = false
            }
    }

    // MARK: - Tap Gesture

    private func tapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let point = canvasPoint(from: value.location, in: size)
                let hitThreshold = max(22.0, 25.0 / canvasScale)
                viewModel.handleTap(at: point, hitThreshold: hitThreshold)
            }
    }

    // MARK: - Long Press Gesture

    private func longPressGesture(size: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onEnded { value in
                switch value {
                case .second(true, let drag):
                    let loc = drag?.location ?? .zero
                    let point = canvasPoint(from: loc, in: size)
                    let hitThreshold = max(22.0, 25.0 / canvasScale)
                    viewModel.handleLongPress(at: point, hitThreshold: hitThreshold)
                default: break
                }
            }
    }
}

// MARK: - Edge Pan Controller

/// Drives auto-pan when a drawing/selection drag enters the viewport edge zone.
/// Owns its own display-rate timer and only ticks while a drag is active. The
/// view wires four closures (offset getter/setter, viewport size, drag-active
/// predicate) plus a per-tick `onPan` callback that re-emits the drawing update
/// for whichever mode is active so the in-progress shape tracks the new canvas
/// coordinates while the canvas slides past the finger.
@MainActor
final class EdgePanController: ObservableObject {
    private var timer: Timer?
    private(set) var lastLocation: CGPoint?

    var getCanvasOffset: (() -> CGSize)?
    var setCanvasOffset: ((CGSize) -> Void)?
    var viewportSize: (() -> CGSize)?
    var isDragActive: (() -> Bool)?
    var onPan: (() -> Void)?

    var edgeZone: CGFloat = 60
    var maxSpeed: CGFloat = 600

    /// Tick at the device's display refresh — Timer at 60Hz is close enough for
    /// pan smoothness without bringing in CADisplayLink plumbing.
    private static let tickInterval: TimeInterval = 1.0 / 60.0

    func startTracking(location: CGPoint) {
        lastLocation = location
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func updateLocation(_ location: CGPoint) {
        lastLocation = location
    }

    func stopTracking() {
        timer?.invalidate()
        timer = nil
        lastLocation = nil
    }

    deinit {
        timer?.invalidate()
    }

    private func tick() {
        // Self-cancel if the drag ended without onEnded firing (gesture cancelled
        // by the system, sheet presentation, etc.) so we don't keep panning.
        guard isDragActive?() == true else {
            stopTracking()
            return
        }
        guard let location = lastLocation,
              let viewport = viewportSize?(),
              viewport.width > 0, viewport.height > 0 else { return }

        // Press is the depth of the finger into the edge zone, in [-1, 1] per axis.
        // 0 means outside the zone, ±1 means right at the viewport boundary.
        var pressX: CGFloat = 0
        var pressY: CGFloat = 0
        if location.x < edgeZone {
            pressX = -(1 - location.x / edgeZone)
        } else if location.x > viewport.width - edgeZone {
            pressX = 1 - (viewport.width - location.x) / edgeZone
        }
        if location.y < edgeZone {
            pressY = -(1 - location.y / edgeZone)
        } else if location.y > viewport.height - edgeZone {
            pressY = 1 - (viewport.height - location.y) / edgeZone
        }
        guard pressX != 0 || pressY != 0 else { return }

        // Ease the pan velocity so the very corner doesn't slingshot. Squaring
        // turns the linear depth into a gentler ramp (0 → 0, 0.5 → 0.25, 1 → 1).
        let easedX = pressX * abs(pressX)
        let easedY = pressY * abs(pressY)

        // Finger pressing toward +X (right edge) should reveal more of the canvas
        // to the right, which means the canvas's offset.width must DECREASE
        // (canvas content shifts left to expose its right side under the finger).
        // Same logic applies to the Y axis.
        let dx = -easedX * maxSpeed * CGFloat(Self.tickInterval)
        let dy = -easedY * maxSpeed * CGFloat(Self.tickInterval)

        guard let getOffset = getCanvasOffset, let setOffset = setCanvasOffset else { return }
        var offset = getOffset()
        offset.width += dx
        offset.height += dy
        setOffset(offset)

        // Re-emit the drawing update so the in-progress line/marquee/vertex
        // follows the finger in the new canvas coordinate space.
        onPan?()
    }
}

// MARK: - UIKit Gesture Handler (Unified Pinch + Pan)

/// Transparent view that forwards all raw touches to the responder chain (SwiftUI)
/// while still letting its own gesture recognizers evaluate multi-touch gestures.
class GesturePassthroughView: UIView {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        next?.touchesBegan(touches, with: event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        next?.touchesMoved(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        next?.touchesEnded(touches, with: event)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        next?.touchesCancelled(touches, with: event)
    }
}

/// Single UIPinchGestureRecognizer handles both zoom AND pan — exactly like Photos.
/// The pinch recognizer fires for any two-finger movement. We track the midpoint
/// delta each frame for panning, and the scale delta for zooming. No separate pan
/// gesture, so there's zero conflict.
struct CanvasGestureView: UIViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    var isDrawing: Bool

    func makeUIView(context: Context) -> GesturePassthroughView {
        let view = GesturePassthroughView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delaysTouchesBegan = false
        view.addGestureRecognizer(pinch)
        context.coordinator.pinchGesture = pinch
        return view
    }

    func updateUIView(_ uiView: GesturePassthroughView, context: Context) {
        context.coordinator.scaleBinding = $scale
        context.coordinator.offsetBinding = $offset
        context.coordinator.pinchGesture?.isEnabled = !isDrawing
    }

    func makeCoordinator() -> Coordinator { Coordinator(scale: $scale, offset: $offset) }

    class Coordinator: NSObject {
        var scaleBinding: Binding<CGFloat>
        var offsetBinding: Binding<CGSize>
        weak var pinchGesture: UIPinchGestureRecognizer?
        private var baseScale: CGFloat = 1.0
        private var lastMidpoint: CGPoint = .zero

        init(scale: Binding<CGFloat>, offset: Binding<CGSize>) {
            self.scaleBinding = scale
            self.offsetBinding = offset
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view else { return }
            let mid = gesture.location(in: view)

            switch gesture.state {
            case .began:
                baseScale = scaleBinding.wrappedValue
                lastMidpoint = mid

            case .changed:
                // When one finger lifts, numberOfTouches drops to 1 and the
                // midpoint jumps to the remaining finger — causes a huge pan spike.
                guard gesture.numberOfTouches >= 2 else { return }

                let currentScale = scaleBinding.wrappedValue
                guard currentScale > 0 else { return }

                // 1. Pan: midpoint delta since last frame
                let dx = mid.x - lastMidpoint.x
                let dy = mid.y - lastMidpoint.y
                lastMidpoint = mid

                var newOffset = offsetBinding.wrappedValue
                newOffset.width += dx
                newOffset.height += dy

                // 2. Zoom: scale change anchored at current midpoint
                let newScale = max(0.15, min(8.0, baseScale * gesture.scale))
                if abs(newScale - currentScale) > 0.001 {
                    let ratio = newScale / currentScale
                    newOffset.width = mid.x - ratio * (mid.x - newOffset.width)
                    newOffset.height = mid.y - ratio * (mid.y - newOffset.height)
                }

                offsetBinding.wrappedValue = newOffset
                scaleBinding.wrappedValue = newScale

            case .ended, .cancelled:
                baseScale = scaleBinding.wrappedValue
            default: break
            }
        }
    }
}
