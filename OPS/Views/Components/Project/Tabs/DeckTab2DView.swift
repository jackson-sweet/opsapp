//
//  DeckTab2DView.swift
//  OPS
//
//  Read-only 2D blueprint view for deck designs in project details.
//  Renders footprint, edges, vertices, and dimension labels without editing tools.
//

import SwiftUI

struct DeckTab2DView: View {
    let drawingData: DeckDrawingData

    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero
    @State private var lastCenteredSize: CGSize = .zero

    // Bug 033b5328 — measurement tool. User toggles ruler mode, taps two
    // points on the drawing, and a measurement readout appears between them.
    @State private var measurementMode: Bool = false
    @State private var measurementStart: CGPoint?
    @State private var measurementEnd: CGPoint?

    private let canvasSize: CGFloat = 4800

    private var gridSpacing: CGFloat {
        let snapInches = drawingData.config.lengthSnapIncrement
        guard let scale = drawingData.scaleFactor, scale > 0 else { return 20.0 }
        let spacing = CGFloat(snapInches * scale)
        return max(8, min(80, spacing))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                canvasContent
                    .frame(width: canvasSize, height: canvasSize)
                    .scaleEffect(canvasScale, anchor: .topLeading)
                    .offset(canvasOffset)

                // Bug 033b5328 — measurement tools UI overlay.
                measurementToolOverlay(viewportSize: geometry.size)
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay {
                CanvasGestureView(
                    scale: $canvasScale,
                    offset: $canvasOffset,
                    isDrawing: false
                )
            }
            // Tap gesture for measurement. Only active when ruler mode is
            // toggled on so it doesn't interfere with pan/zoom.
            .simultaneousGesture(
                measurementMode
                    ? SpatialTapGesture().onEnded { value in
                        recordMeasurementTap(at: value.location, in: geometry.size)
                    }
                    : nil
            )
            .onAppear {
                if geometry.size.width > 0 && geometry.size.height > 0 {
                    centerViewport(viewportSize: geometry.size)
                    lastCenteredSize = geometry.size
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                // Bug 9327599a — previously we only ran centerViewport on the
                // very first non-zero geometry. When DeckTabView is inside
                // ProjectDetailsView''s ScrollView, onAppear fires with a
                // collapsed (~0pt) size, so the first centerViewport saw a
                // tiny viewport, scaled the drawing to that tiny size, and
                // then refused to re-run when the aspect-ratio frame
                // resolved. Now we re-center whenever the geometry changes
                // meaningfully. The deck tab is read-only — users do not
                // expect their pan/zoom to survive a layout shift, and
                // re-centering on every meaningful resize is the right
                // default for a read-only viewer.
                guard newSize.width > 0, newSize.height > 0 else { return }
                let widthChange = abs(newSize.width - lastCenteredSize.width)
                let heightChange = abs(newSize.height - lastCenteredSize.height)
                guard widthChange > 1 || heightChange > 1 else { return }
                centerViewport(viewportSize: newSize)
                lastCenteredSize = newSize
            }
        }
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
            drawMeasurement(context: context)

            if drawingData.isMultiLevel {
                // DECK-NEW-8 — render every level so multi-level designs are
                // fully visible in the project tab. Previously only level 0
                // was drawn fully (others got the dim "inactive" footprint),
                // which made the viewer claim levels existed but never show
                // their edges, vertices, or dimensions.
                for connection in drawingData.levelConnections {
                    drawLevelConnection(context: context, connection: connection)
                }
                for level in drawingData.levels {
                    // DECK-NEW-1 — fill every detected face in this level so
                    // multi-surface levels render correctly. Material/label
                    // pulled from per-surface persisted store so each face
                    // shows its own assignment (DECK-NEW-1 follow-up).
                    let levelSurfaces = level.detectedSurfaces
                    if !levelSurfaces.isEmpty {
                        let primary = primarySurfaceId(among: levelSurfaces)
                        for face in levelSurfaces {
                            let resolved = resolvedReadOnlySurface(
                                detected: face,
                                persisted: level.surfaces,
                                legacy: level.footprint,
                                isLegacyPrimary: face.id == primary
                            )
                            drawLevelSurfaceFill(
                                context: context,
                                level: level,
                                positions: face.positions,
                                assignedItems: resolved.assignedItems,
                                label: resolved.label
                            )
                        }
                    } else if level.isClosed {
                        drawLevelFootprint(context: context, level: level)
                    }
                    for edge in level.edges {
                        drawEdge(context: context, edge: edge, vertexLookup: level.vertex(byId:))
                    }
                    for vertex in level.vertices {
                        drawVertex(context: context, vertex: vertex)
                    }
                    for edge in level.edges {
                        drawDimensionLabel(context: context, edge: edge, vertexLookup: level.vertex(byId:))
                    }
                }
            } else {
                // DECK-NEW-1 — fill every detected closed face. Falls back
                // to the legacy single-polygon fill when nothing is detected
                // (degenerate or scale-less data).
                let surfaces = drawingData.detectedSurfaces
                if !surfaces.isEmpty {
                    let persisted = drawingData.surfaces
                    for face in surfaces {
                        let resolved = resolvedReadOnlySurface(detected: face, persisted: persisted, legacy: drawingData.footprint, isLegacyPrimary: face.id == primarySurfaceId(among: surfaces))
                        drawSurfaceFill(context: context, positions: face.positions, assignedItems: resolved.assignedItems, label: resolved.label)
                    }
                } else if drawingData.isClosed {
                    drawFootprint(context: context)
                }
                if let poolDiameter = drawingData.poolDiameter,
                   let scale = drawingData.scaleFactor, scale > 0 {
                    drawPoolOverlay(context: context, diameterInches: poolDiameter, scaleFactor: scale)
                }
                for edge in drawingData.edges {
                    drawEdge(context: context, edge: edge, vertexLookup: drawingData.vertex(byId:))
                }
                for vertex in drawingData.vertices {
                    drawVertex(context: context, vertex: vertex)
                }
                for edge in drawingData.edges {
                    drawDimensionLabel(context: context, edge: edge, vertexLookup: drawingData.vertex(byId:))
                }
            }
        }
    }

    // MARK: - Viewport Centering

    private func centerViewport(viewportSize: CGSize) {
        // DECK-NEW-8 — frame the camera around ALL levels' bounds so every
        // level is visible. Previously only level 0 informed the fit, which
        // could push higher levels offscreen entirely.
        let positions: [CGPoint]
        if drawingData.isMultiLevel {
            positions = drawingData.levels.flatMap { $0.vertices.map(\.position) }
        } else {
            positions = drawingData.vertices.map(\.position)
        }

        guard !positions.isEmpty else {
            canvasOffset = CGSize(
                width: -canvasSize / 2 + viewportSize.width / 2,
                height: -canvasSize / 2 + viewportSize.height / 2
            )
            return
        }

        let xs = positions.map(\.x)
        let ys = positions.map(\.y)
        let centerX = (xs.min()! + xs.max()!) / 2
        let centerY = (ys.min()! + ys.max()!) / 2

        // Bug 1959e011 — small decks rendered at near-1x because fitScale was
        // capped at 2.0 AND a fixed 200pt margin was added to span (which
        // dominated small drawings, dragging fitScale below 1). Use proportional
        // margin (15% padding via 0.85 multiplier) and a much higher cap so a
        // 200pt-wide deck can actually fill an iPhone viewport.
        let rawSpanX = xs.max()! - xs.min()!
        let rawSpanY = ys.max()! - ys.min()!
        // Guard against degenerate spans (single vertex / colinear points) — fall
        // back to a sensible reference span so we don't divide by ~zero.
        let spanX = max(rawSpanX, 1)
        let spanY = max(rawSpanY, 1)
        let rawFit = min(viewportSize.width / spanX, viewportSize.height / spanY)
        // 0.85 leaves ~7.5% margin on each side; 8.0 cap keeps very tiny
        // drawings from rendering at ridiculous zoom (just enough to read).
        let fitScale = min(rawFit * 0.85, 8.0)

        canvasScale = fitScale
        canvasOffset = CGSize(
            width: viewportSize.width / 2 - centerX * fitScale,
            height: viewportSize.height / 2 - centerY * fitScale
        )
    }

    // MARK: - Drawing Functions

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let visMinX = max(0, -canvasOffset.width / canvasScale)
        let visMinY = max(0, -canvasOffset.height / canvasScale)
        let vpW = UIScreen.main.bounds.width / canvasScale
        let vpH = UIScreen.main.bounds.height / canvasScale
        let visMaxX = min(size.width, visMinX + vpW)
        let visMaxY = min(size.height, visMinY + vpH)

        let startX = floor(visMinX / gridSpacing) * gridSpacing
        let startY = floor(visMinY / gridSpacing) * gridSpacing

        let dotSize: CGFloat = 1.5
        let dotColor = Color.white.opacity(0.08)

        var x = startX
        while x <= visMaxX {
            var y = startY
            while y <= visMaxY {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                    with: .color(dotColor)
                )
                y += gridSpacing
            }
            x += gridSpacing
        }
    }

    private func drawFootprint(context: GraphicsContext) {
        let positions = drawingData.orderedPositions
        drawSurfaceFill(context: context, positions: positions, assignedItems: drawingData.footprint.assignedItems, label: drawingData.footprint.label)
    }

    /// Subtle fill + stroke for one detected surface in the read-only viewer.
    /// Tinted by the surface's first assigned item color when present —
    /// matches the in-builder look so per-surface materials read correctly
    /// in the project tab. DECK-NEW-1 follow-up.
    private func drawSurfaceFill(context: GraphicsContext, positions: [CGPoint], assignedItems: [AssignedItem] = [], label: String? = nil) {
        guard positions.count >= 3 else { return }
        var path = Path()
        path.move(to: positions[0])
        for i in 1..<positions.count { path.addLine(to: positions[i]) }
        path.closeSubpath()

        if !assignedItems.isEmpty,
           let hex = assignedItems.first?.taskTypeColor,
           !hex.isEmpty,
           let tint = Color(hex: hex) {
            context.fill(path, with: .color(tint.opacity(0.10)))
            context.stroke(path, with: .color(tint.opacity(0.30)), lineWidth: 1)
        } else {
            context.fill(path, with: .color(Color.white.opacity(0.04)))
            context.stroke(path, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
        }

        let resolvedLabel: String? = {
            if let l = label?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty { return l }
            return assignedItems.first?.name
        }()
        if let l = resolvedLabel {
            drawSurfaceLabel(context: context, positions: positions, label: l)
        }
    }

    /// Resolved per-surface payload for the read-only viewer. Mirrors
    /// `DeckCanvasView.resolveSurface` — exact vertex-set first, then best
    /// Jaccard, falling back to the legacy footprint payload only on the
    /// primary face for unmigrated drawings. DECK-NEW-1 follow-up.
    private struct ResolvedReadOnlySurface {
        let assignedItems: [AssignedItem]
        let label: String?
    }

    private func resolvedReadOnlySurface(
        detected: DetectedSurface,
        persisted: [DeckSurface],
        legacy: DeckFootprint,
        isLegacyPrimary: Bool
    ) -> ResolvedReadOnlySurface {
        let dSet = Set(detected.vertexIds)
        if let exact = persisted.first(where: { $0.vertexIds == dSet }) {
            return ResolvedReadOnlySurface(assignedItems: exact.assignedItems, label: exact.label)
        }
        var best: (s: DeckSurface, j: Double)? = nil
        for p in persisted {
            let inter = dSet.intersection(p.vertexIds).count
            let union = dSet.union(p.vertexIds).count
            guard union > 0 else { continue }
            let j = Double(inter) / Double(union)
            if j > (best?.j ?? -1) { best = (p, j) }
        }
        if let m = best, m.j >= SurfaceReconciler.rebindThreshold {
            return ResolvedReadOnlySurface(assignedItems: m.s.assignedItems, label: m.s.label)
        }
        if isLegacyPrimary {
            return ResolvedReadOnlySurface(assignedItems: legacy.assignedItems, label: legacy.label)
        }
        return ResolvedReadOnlySurface(assignedItems: [], label: nil)
    }

    /// Largest detected surface — used to attribute legacy footprint
    /// payloads to a single face for unmigrated drawings.
    private func primarySurfaceId(among surfaces: [DetectedSurface]) -> String? {
        surfaces.max(by: { abs(PolygonMath.signedArea(vertices: $0.positions)) < abs(PolygonMath.signedArea(vertices: $1.positions)) })?.id
    }

    /// Surface label — small monochrome pill at the surface centroid.
    private func drawSurfaceLabel(context: GraphicsContext, positions: [CGPoint], label: String) {
        let cx = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let cy = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        let pillH: CGFloat = 18
        let charW: CGFloat = 6
        let pillW = CGFloat(label.count) * charW + 12
        let cr: CGFloat = 4
        let pillRect = CGRect(x: cx - pillW / 2, y: cy - pillH / 2, width: pillW, height: pillH)
        context.fill(Path(roundedRect: pillRect, cornerRadius: cr),
                     with: .color(OPSStyle.Colors.cardBackground.opacity(0.85)))
        context.draw(Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.9)),
                     at: CGPoint(x: cx, y: cy))
    }

    private func drawEdge(context: GraphicsContext, edge: DeckEdge, vertexLookup: (String) -> DeckVertex?) {
        guard let start = vertexLookup(edge.startVertexId),
              let end = vertexLookup(edge.endVertexId) else { return }

        let lineColor: Color
        let lineWidth: CGFloat

        switch edge.edgeType {
        case .houseEdge:
            // Bug 3d72ce0b — house edges read as a raised wall. Use the
            // selected cladding material's tone, falling back to a neutral
            // wall white when unset.
            if let mat = edge.houseEdgeMaterial, let c = Color(hex: mat.fillHex) {
                lineColor = c
            } else {
                lineColor = Color.white.opacity(0.7)
            }
            lineWidth = 4.0   // chunkier stroke implies a wall, not just an edge
        case .deckEdge:
            lineColor = OPSStyle.Colors.primaryAccent
            lineWidth = 2.0
        }

        var path = Path()
        path.move(to: start.position)
        path.addLine(to: end.position)
        context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)

        // House edge hatching
        if edge.edgeType == .houseEdge {
            let dx = end.position.x - start.position.x
            let dy = end.position.y - start.position.y
            let length = hypot(dx, dy)
            guard length > 0 else { return }
            let nx = -dy / length
            let ny = dx / length
            let hatchLen: CGFloat = 8
            let hatchSpacing: CGFloat = 10
            var d: CGFloat = hatchSpacing / 2
            while d < length {
                let t = d / length
                let px = start.position.x + dx * t
                let py = start.position.y + dy * t
                var hp = Path()
                hp.move(to: CGPoint(x: px, y: py))
                hp.addLine(to: CGPoint(x: px + nx * hatchLen, y: py + ny * hatchLen))
                context.stroke(hp, with: .color(Color.white.opacity(0.3)), lineWidth: 1)
                d += hatchSpacing
            }
        }

        // Bug a046a041 / 3d72ce0b — render full stair geometry in the 2D
        // project viewer (previously a tiny dot at midpoint, easy to miss).
        // Mirror the builder canvas: outline rectangle + tread lines on the
        // outward perpendicular.
        if let config = edge.stairConfig, let tc = config.treadCount, tc > 0 {
            drawStairsOnEdge(
                context: context,
                edge: edge,
                config: config,
                treadCount: tc,
                start: start.position,
                end: end.position
            )
        }
    }

    /// Render a stair rectangle + tread lines for a 2D viewer edge. Uses
    /// PolygonMath.outwardPerpendicular when the surrounding polygon is
    /// available so stairs land on the empty side of the deck.
    private func drawStairsOnEdge(
        context: GraphicsContext,
        edge: DeckEdge,
        config: StairConfig,
        treadCount: Int,
        start: CGPoint,
        end: CGPoint
    ) {
        // Polygon for outward-perpendicular lookup (use the level matching
        // the edge's vertex ids, falling back to the single-level polygon).
        let polygon: [CGPoint]
        if drawingData.isMultiLevel {
            // Find which level holds this edge
            var found: [CGPoint] = []
            for level in drawingData.levels where level.edge(byId: edge.id) != nil {
                found = level.orderedPositions
                break
            }
            polygon = found
        } else {
            polygon = drawingData.orderedPositions
        }

        guard let plan = DeckStairRenderPlanner.plan(
            edgeStart: start,
            edgeEnd: end,
            polygonVertices: polygon,
            config: config,
            treadCount: treadCount,
            scaleFactor: drawingData.effectiveScaleFactor,
            measurementSystem: drawingData.config.measurementSystem
        ) else { return }

        var rectPath = Path()
        rectPath.move(to: plan.baseStart)
        rectPath.addLine(to: plan.baseEnd)
        rectPath.addLine(to: plan.farEnd)
        rectPath.addLine(to: plan.farStart)
        rectPath.closeSubpath()

        context.fill(rectPath, with: .color(OPSStyle.Colors.tanSoft))
        context.stroke(rectPath, with: .color(OPSStyle.Colors.tanLine), lineWidth: OPSStyle.Layout.Border.standard)

        // Tread lines
        for line in plan.treadLines {
            var tp = Path()
            tp.move(to: line.start)
            tp.addLine(to: line.end)
            context.stroke(tp, with: .color(OPSStyle.Colors.tanLine.opacity(0.75)), lineWidth: OPSStyle.Layout.Border.standard)
        }

        for label in plan.dimensionLabels {
            drawStairDimensionLabel(context: context, label: label)
        }
    }

    private func drawStairDimensionLabel(
        context: GraphicsContext,
        label: DeckStairDimensionLabel
    ) {
        let resolved = context.resolve(Text(label.text)
            .font(OPSStyle.Typography.microLabel)
            .foregroundColor(OPSStyle.Colors.text))

        let textSize = resolved.measure(in: CGSize(width: 220, height: 50))
        let padH = CGFloat(OPSStyle.Layout.spacing1)
        let padV = CGFloat(OPSStyle.Layout.spacing1) / 2
        let bgRect = CGRect(
            x: label.position.x - textSize.width / 2 - padH,
            y: label.position.y - textSize.height / 2 - padV,
            width: textSize.width + padH * 2,
            height: textSize.height + padV * 2
        )
        context.fill(
            Path(roundedRect: bgRect, cornerRadius: CGFloat(OPSStyle.Layout.chipRadius)),
            with: .color(OPSStyle.Colors.glassDenseApprox)
        )
        context.stroke(
            Path(roundedRect: bgRect, cornerRadius: CGFloat(OPSStyle.Layout.chipRadius)),
            with: .color(OPSStyle.Colors.line),
            lineWidth: OPSStyle.Layout.Border.standard
        )
        context.draw(resolved, at: label.position, anchor: .center)
    }

    private func drawVertex(context: GraphicsContext, vertex: DeckVertex) {
        let r: CGFloat = 5
        let circle = Path(ellipseIn: CGRect(
            x: vertex.position.x - r,
            y: vertex.position.y - r,
            width: r * 2,
            height: r * 2
        ))
        context.fill(circle, with: .color(Color.white))
        context.stroke(circle, with: .color(OPSStyle.Colors.primaryAccent), lineWidth: 1.5)
    }

    private func drawDimensionLabel(context: GraphicsContext, edge: DeckEdge, vertexLookup: (String) -> DeckVertex?) {
        guard let dim = edge.dimension, dim > 0,
              let start = vertexLookup(edge.startVertexId),
              let end = vertexLookup(edge.endVertexId) else { return }

        let midX = (start.position.x + end.position.x) / 2
        let midY = (start.position.y + end.position.y) / 2

        let feet = Int(dim) / 12
        let inches = Int(dim) % 12
        let text = feet > 0 ? "\(feet)' \(inches)\"" : "\(inches)\""

        let resolved = context.resolve(Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white))

        let textSize = resolved.measure(in: CGSize(width: 200, height: 50))
        let padH: CGFloat = 6
        let padV: CGFloat = 3
        let bgRect = CGRect(
            x: midX - textSize.width / 2 - padH,
            y: midY - textSize.height / 2 - padV,
            width: textSize.width + padH * 2,
            height: textSize.height + padV * 2
        )
        context.fill(
            Path(roundedRect: bgRect, cornerRadius: 3),
            with: .color(Color.black.opacity(0.7))
        )
        context.draw(resolved, at: CGPoint(x: midX, y: midY), anchor: .center)
    }

    private func drawLevelFootprint(context: GraphicsContext, level: DeckLevel) {
        drawLevelSurfaceFill(context: context, level: level, positions: level.orderedPositions, assignedItems: level.footprint.assignedItems, label: level.footprint.label)
    }

    /// Fill + stroke for one detected surface within a multi-level design's
    /// level. Tinted by per-surface material color when present, falling
    /// back to the level's display color for the unassigned look.
    /// DECK-NEW-1 follow-up.
    private func drawLevelSurfaceFill(context: GraphicsContext, level: DeckLevel, positions: [CGPoint], assignedItems: [AssignedItem] = [], label: String? = nil) {
        guard positions.count >= 3 else { return }
        var path = Path()
        path.move(to: positions[0])
        for i in 1..<positions.count { path.addLine(to: positions[i]) }
        path.closeSubpath()

        if !assignedItems.isEmpty,
           let hex = assignedItems.first?.taskTypeColor,
           !hex.isEmpty,
           let tint = Color(hex: hex) {
            context.fill(path, with: .color(tint.opacity(0.10)))
            context.stroke(path, with: .color(tint.opacity(0.30)), lineWidth: 1)
        } else {
            context.fill(path, with: .color(level.displayColor.swiftUIColor.opacity(0.06)))
            context.stroke(path, with: .color(level.displayColor.swiftUIColor.opacity(0.15)), lineWidth: 1)
        }

        let resolvedLabel: String? = {
            if let l = label?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty { return l }
            return assignedItems.first?.name
        }()
        if let l = resolvedLabel {
            drawSurfaceLabel(context: context, positions: positions, label: l)
        }
    }

    private func drawInactiveLevel(context: GraphicsContext, level: DeckLevel) {
        let positions = level.orderedPositions
        guard positions.count >= 3 else { return }

        var path = Path()
        path.move(to: positions[0])
        for i in 1..<positions.count { path.addLine(to: positions[i]) }
        path.closeSubpath()

        context.fill(path, with: .color(level.displayColor.swiftUIColor.opacity(0.03)))
        context.stroke(path, with: .color(level.displayColor.swiftUIColor.opacity(0.08)), lineWidth: 1)
    }

    private func drawLevelConnection(context: GraphicsContext, connection: LevelConnection) {
        guard let upperLevel = drawingData.levels.first(where: { $0.id == connection.upperLevelId }),
              let upperEdge = upperLevel.edges.first(where: { $0.id == connection.upperEdgeId }),
              let uStart = upperLevel.vertex(byId: upperEdge.startVertexId),
              let uEnd = upperLevel.vertex(byId: upperEdge.endVertexId) else { return }

        let midX = (uStart.position.x + uEnd.position.x) / 2
        let midY = (uStart.position.y + uEnd.position.y) / 2

        let stairIcon = Path(ellipseIn: CGRect(x: midX - 8, y: midY - 8, width: 16, height: 16))
        context.fill(stairIcon, with: .color(OPSStyle.Colors.warningStatus.opacity(0.2)))
        context.stroke(stairIcon, with: .color(OPSStyle.Colors.warningStatus.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func drawPoolOverlay(context: GraphicsContext, diameterInches: Double, scaleFactor: Double) {
        let radiusPt = CGFloat(diameterInches / 2 * scaleFactor)
        let center = CGPoint(x: canvasSize / 2, y: canvasSize / 2)
        let circle = Path(ellipseIn: CGRect(
            x: center.x - radiusPt, y: center.y - radiusPt,
            width: radiusPt * 2, height: radiusPt * 2
        ))
        context.fill(circle, with: .color(Color.blue.opacity(0.08)))
        context.stroke(circle, with: .color(Color.blue.opacity(0.2)),
                       style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
    }

    // MARK: - Bug 033b5328 — Measurement Tool

    /// Convert a viewport-space tap location to canvas-space coordinates.
    /// Inverse of the `.scaleEffect(canvasScale, anchor: .topLeading).offset(canvasOffset)`
    /// transform applied to `canvasContent`. Tap location comes in viewport
    /// (GeometryReader-local) coords; the rendered canvas is `canvasOffset`
    /// shifted then `canvasScale` scaled at top-leading anchor.
    private func canvasPoint(from viewportPoint: CGPoint, viewportSize: CGSize) -> CGPoint {
        let cx = (viewportPoint.x - canvasOffset.width) / canvasScale
        let cy = (viewportPoint.y - canvasOffset.height) / canvasScale
        return CGPoint(x: cx, y: cy)
    }

    /// Measurement-mode tap state machine: first tap sets start, second tap
    /// closes the measurement, third tap resets and starts a new one.
    /// DECK-NEW-9 — taps now snap to nearest vertex / edge projection
    /// before being recorded, and the second tap also snaps the LINE
    /// angle to perpendicular / parallel of nearby edges.
    private func recordMeasurementTap(at location: CGPoint, in viewportSize: CGSize) {
        let rawCanvasLoc = canvasPoint(from: location, viewportSize: viewportSize)
        let snappedLoc = snapToGeometry(rawCanvasLoc)

        if measurementStart == nil {
            measurementStart = snappedLoc
            measurementEnd = nil
        } else if measurementEnd == nil {
            // Second tap: snap angle relative to existing edges so the
            // measurement reads true perpendicular / parallel when the
            // user is close to that intent.
            measurementEnd = snapAngleToEdges(from: measurementStart!, candidate: snappedLoc)
        } else {
            measurementStart = snappedLoc
            measurementEnd = nil
        }
    }

    /// Snap a canvas-space point to the nearest vertex (within hit threshold),
    /// or to the closest projection on the nearest edge (slightly larger
    /// threshold). Falls back to the raw point when nothing is in range.
    /// Threshold is scaled by the inverse of canvasScale so it stays
    /// roughly 14pt / 24pt of *finger* slop regardless of zoom.
    private func snapToGeometry(_ point: CGPoint) -> CGPoint {
        let vertexThreshold: Double = max(8, 14 / Double(canvasScale))
        let edgeThreshold: Double = max(12, 24 / Double(canvasScale))

        let vertices = drawingData.isMultiLevel
            ? drawingData.levels.flatMap { $0.vertices }
            : drawingData.vertices
        let edges = drawingData.isMultiLevel
            ? drawingData.levels.flatMap { $0.edges }
            : drawingData.edges

        // 1. Vertex snap takes priority — a clear visual target.
        var bestVertexDist = Double.infinity
        var bestVertexPoint: CGPoint?
        for v in vertices {
            let d = SnapEngine.distance(point, v.position)
            if d < vertexThreshold && d < bestVertexDist {
                bestVertexDist = d
                bestVertexPoint = v.position
            }
        }
        if let p = bestVertexPoint { return p }

        // 2. Edge snap — perpendicular projection onto the nearest segment.
        var bestEdgeDist = Double.infinity
        var bestEdgePoint: CGPoint?
        for edge in edges {
            guard let start = vertices.first(where: { $0.id == edge.startVertexId }),
                  let end = vertices.first(where: { $0.id == edge.endVertexId }) else { continue }
            let (closest, d) = PolygonMath.closestPointOnSegment(point: point, segStart: start.position, segEnd: end.position)
            if d < edgeThreshold && d < bestEdgeDist {
                bestEdgeDist = d
                bestEdgePoint = closest
            }
        }
        if let p = bestEdgePoint { return p }

        return point
    }

    /// Adjust the second-tap location so the measurement line lands exactly
    /// perpendicular or parallel to the closest edge if the user's pick is
    /// already within ±5°. The line LENGTH stays the same; only the angle
    /// is rotated. Returns the original candidate when no edge is nearby.
    private func snapAngleToEdges(from start: CGPoint, candidate: CGPoint) -> CGPoint {
        let vertices = drawingData.isMultiLevel
            ? drawingData.levels.flatMap { $0.vertices }
            : drawingData.vertices
        let edges = drawingData.isMultiLevel
            ? drawingData.levels.flatMap { $0.edges }
            : drawingData.edges
        guard !edges.isEmpty else { return candidate }

        // Find the edge whose midpoint is closest to the measurement line —
        // a rough "which edge is the user near" heuristic that avoids
        // anchoring snap to a faraway edge.
        let midM = CGPoint(x: (start.x + candidate.x) / 2, y: (start.y + candidate.y) / 2)
        var bestEdgeAngle: Double?
        var bestDist = Double.infinity
        for edge in edges {
            guard let s = vertices.first(where: { $0.id == edge.startVertexId }),
                  let e = vertices.first(where: { $0.id == edge.endVertexId }) else { continue }
            let edgeMid = CGPoint(x: (s.position.x + e.position.x) / 2, y: (s.position.y + e.position.y) / 2)
            let d = SnapEngine.distance(midM, edgeMid)
            if d < bestDist {
                bestDist = d
                bestEdgeAngle = SnapEngine.lineAngle(from: s.position, to: e.position)
            }
        }
        guard let edgeAngle = bestEdgeAngle else { return candidate }

        let lineAngle = SnapEngine.lineAngle(from: start, to: candidate)
        let length = SnapEngine.distance(start, candidate)

        // Candidate snap targets: parallel (edgeAngle, edgeAngle ± 180°) and
        // perpendicular (edgeAngle ± 90°). Pick the one within ±5°.
        let targets: [Double] = [
            edgeAngle, edgeAngle + 180, edgeAngle - 180,
            edgeAngle + 90, edgeAngle - 90,
            edgeAngle + 270, edgeAngle - 270
        ]
        let tolerance: Double = 5.0
        var snapAngle: Double?
        for t in targets {
            // Normalise both into [0, 360) before comparing.
            let normLine = ((lineAngle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            let normT = ((t.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            var diff = abs(normLine - normT)
            if diff > 180 { diff = 360 - diff }
            if diff <= tolerance {
                snapAngle = t
                break
            }
        }

        guard let target = snapAngle else { return candidate }

        // Rotate end point around start to land on the snapped angle while
        // preserving the user's chosen length.
        let rad = target * .pi / 180
        return CGPoint(
            x: start.x + CGFloat(length * cos(rad)),
            y: start.y + CGFloat(length * sin(rad))
        )
    }

    /// Render the in-progress measurement (anchor dots, dashed line, midpoint
    /// distance pill) inside the Canvas pass.
    private func drawMeasurement(context: GraphicsContext) {
        guard measurementMode else { return }
        let dotR: CGFloat = 6
        let dotStroke: CGFloat = 2
        let lineColor = OPSStyle.Colors.warningStatus

        if let start = measurementStart {
            let circle = Path(ellipseIn: CGRect(
                x: start.x - dotR, y: start.y - dotR,
                width: dotR * 2, height: dotR * 2
            ))
            context.fill(circle, with: .color(lineColor.opacity(0.2)))
            context.stroke(circle, with: .color(lineColor), lineWidth: dotStroke)
        }

        guard let start = measurementStart, let end = measurementEnd else { return }

        var linePath = Path()
        linePath.move(to: start)
        linePath.addLine(to: end)
        context.stroke(linePath, with: .color(lineColor),
                       style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

        let endCircle = Path(ellipseIn: CGRect(
            x: end.x - dotR, y: end.y - dotR,
            width: dotR * 2, height: dotR * 2
        ))
        context.fill(endCircle, with: .color(lineColor.opacity(0.2)))
        context.stroke(endCircle, with: .color(lineColor), lineWidth: dotStroke)

        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let canvasDistance = hypot(end.x - start.x, end.y - start.y)

        let labelText: String
        if let scale = drawingData.scaleFactor, scale > 0 {
            let inches = canvasDistance / scale
            let totalInches = Int(inches.rounded())
            let feet = totalInches / 12
            let remInches = totalInches % 12
            labelText = feet > 0 ? "\(feet)' \(remInches)\"" : "\(remInches)\""
        } else {
            // No scale calibrated — show canvas units so user still gets
            // a relative read; the warning HUD in measurementToolOverlay
            // tells them why it isn't a real measurement.
            labelText = "\(Int(canvasDistance.rounded())) pt"
        }

        let resolved = context.resolve(Text(labelText)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(.black))
        let textSize = resolved.measure(in: CGSize(width: 200, height: 50))
        let padH: CGFloat = 8
        let padV: CGFloat = 4
        let bgRect = CGRect(
            x: midX - textSize.width / 2 - padH,
            y: midY - textSize.height / 2 - padV,
            width: textSize.width + padH * 2,
            height: textSize.height + padV * 2
        )
        context.fill(Path(roundedRect: bgRect, cornerRadius: 4), with: .color(lineColor))
        context.draw(resolved, at: CGPoint(x: midX, y: midY), anchor: .center)
    }

    /// Floating ruler-mode toggle and instruction HUD pinned to the top-right
    /// of the viewer. Disabled state shows a subtle dark pill; enabled state
    /// switches to the warning accent so it reads as "active mode" at a glance.
    @ViewBuilder
    private func measurementToolOverlay(viewportSize: CGSize) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button {
                measurementMode.toggle()
                if !measurementMode {
                    measurementStart = nil
                    measurementEnd = nil
                }
            } label: {
                Image(OPSStyle.Icons.measure)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(measurementMode ? .black : .white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(
                            measurementMode
                                ? OPSStyle.Colors.warningStatus
                                : Color.black.opacity(0.6)
                        )
                    )
                    .overlay(
                        Circle().stroke(
                            measurementMode ? Color.clear : Color.white.opacity(0.2),
                            lineWidth: 1
                        )
                    )
            }

            if let hint = measurementHintText {
                Text(hint)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.chipRadius)
            }
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    /// Hint shown beside the ruler toggle when measurement mode is on.
    /// Pulled out of the ViewBuilder body so the if/else cascade isn't
    /// misread as a conditional view branch.
    private var measurementHintText: String? {
        guard measurementMode else { return nil }
        if measurementStart == nil { return "TAP — SNAPS TO POINTS" }
        if measurementEnd == nil { return "TAP — SNAPS ⊥ ∥" }
        if drawingData.scaleFactor == nil { return "NO SCALE CALIBRATED" }
        return "TAP TO RESET"
    }
}
