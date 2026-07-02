//
//  DeckTab2DView.swift
//  OPS
//
//  Read-only 2D blueprint view for deck designs. Renders footprint, edges,
//  vertices, and dimension labels. Tool CHROME (rail, readouts, hints) lives in
//  the fullscreen viewer — this view only DRAWS, driven by a shared
//  `DeckViewerToolState`. Inline usage passes `showsTools: false` and a default
//  tool state, so it stays a pristine read-only preview (dimensions on, no
//  isolation, no selection) regardless of what the fullscreen tools do.
//

import SwiftUI

struct DeckTab2DView: View {
    let drawingData: DeckDrawingData
    /// Shared tool state — measurement/selection modes, dimensions toggle, level
    /// isolation, and the fit trigger. Owned by the fullscreen viewer; inline
    /// usage passes a default instance and never mutates it.
    @ObservedObject var toolState: DeckViewerToolState
    /// When false (inline), the tap gesture + measurement rendering are inert and
    /// the canvas ignores tool state entirely — a pure read-only preview. The
    /// fullscreen viewer sets this true and drives the tools from its rail.
    var showsTools: Bool = false
    /// Reports `true` while the user is actively pinching/panning the blueprint
    /// so the parent can fade the floating badges (parity with the 3D viewer).
    var onInteractingChange: (Bool) -> Void = { _ in }

    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero
    @State private var lastCenteredSize: CGSize = .zero

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
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay {
                CanvasGestureView(
                    scale: $canvasScale,
                    offset: $canvasOffset,
                    isDrawing: false,
                    onInteractingChange: onInteractingChange
                )
            }
            // Tap gesture for measurement / surface inspection. Only active in the
            // fullscreen viewer (showsTools) with a tool mode toggled on, so it
            // never interferes with inline pan/zoom.
            .simultaneousGesture(
                (showsTools && (toolState.isMeasuring || toolState.isSelecting))
                    ? SpatialTapGesture().onEnded { value in
                        if toolState.isMeasuring {
                            recordMeasurementTap(at: value.location, in: geometry.size)
                        } else {
                            recordSelectionTap(at: value.location, in: geometry.size)
                        }
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
            // Fit tool — reframe the whole deck. Animated so the reset reads as a
            // deliberate camera move, not a jump.
            .onChange(of: toolState.fitTrigger) { _, _ in
                guard lastCenteredSize.width > 0, lastCenteredSize.height > 0 else { return }
                withAnimation(OPSStyle.Animation.standard) {
                    centerViewport(viewportSize: lastCenteredSize)
                }
            }
        }
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)

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
                    // Isolate tool (fullscreen only) — when a level is isolated,
                    // dim the others back to their inactive footprint so the
                    // focused level reads clearly on a busy multi-level plan.
                    if showsTools, let isolated = toolState.isolatedLevelId, isolated != level.id {
                        drawInactiveLevel(context: context, level: level)
                        continue
                    }
                    // DECK-NEW-1 — fill every detected face in this level so
                    // multi-surface levels render correctly. Material/label
                    // pulled from per-surface persisted store so each face
                    // shows its own assignment (DECK-NEW-1 follow-up).
                    let levelSurfaces = level.detectedSurfaces
                    if !levelSurfaces.isEmpty {
                        let primary = DeckSurfaceInspector.primarySurfaceId(among: levelSurfaces)
                        for face in levelSurfaces {
                            let resolved = DeckSurfaceInspector.resolvedPayload(
                                detected: face,
                                persisted: level.surfaces,
                                legacyFootprint: level.footprint,
                                isLegacyPrimary: face.id == primary
                            )
                            drawLevelSurfaceFill(
                                context: context,
                                level: level,
                                positions: face.positions,
                                assignedItems: resolved.assignedItems,
                                label: resolved.label,
                                selected: showsTools && toolState.selectedSurfaceIds.contains(face.id)
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
                    // Dimensions toggle (fullscreen only). Inline always shows them.
                    if !showsTools || toolState.showDimensions {
                        for edge in level.edges {
                            drawDimensionLabel(context: context, edge: edge, vertexLookup: level.vertex(byId:))
                        }
                    }
                }
            } else {
                // DECK-NEW-1 — fill every detected closed face. Falls back
                // to the legacy single-polygon fill when nothing is detected
                // (degenerate or scale-less data).
                let surfaces = drawingData.detectedSurfaces
                if !surfaces.isEmpty {
                    let persisted = drawingData.surfaces
                    let primary = DeckSurfaceInspector.primarySurfaceId(among: surfaces)
                    for face in surfaces {
                        let resolved = DeckSurfaceInspector.resolvedPayload(
                            detected: face,
                            persisted: persisted,
                            legacyFootprint: drawingData.footprint,
                            isLegacyPrimary: face.id == primary
                        )
                        drawSurfaceFill(context: context, positions: face.positions, assignedItems: resolved.assignedItems, label: resolved.label, selected: showsTools && toolState.selectedSurfaceIds.contains(face.id))
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
                // Dimensions toggle (fullscreen only). Inline always shows them.
                if !showsTools || toolState.showDimensions {
                    for edge in drawingData.edges {
                        drawDimensionLabel(context: context, edge: edge, vertexLookup: drawingData.vertex(byId:))
                    }
                }
            }

            // The active tool draws LAST so the measurement always reads over
            // the plan — edges, fills, and dimension labels never occlude it.
            drawMeasurement(context: context)
            drawSplit(context: context)
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
        let dotColor = OPSStyle.Colors.surfaceActive

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
    private func drawSurfaceFill(context: GraphicsContext, positions: [CGPoint], assignedItems: [AssignedItem] = [], label: String? = nil, selected: Bool = false) {
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
            context.fill(path, with: .color(OPSStyle.Colors.surfaceInput))
            context.stroke(path, with: .color(OPSStyle.Colors.surfaceActive), lineWidth: 1)
        }

        drawSelectionHighlight(context: context, path: path, selected: selected)

        let resolvedLabel: String? = {
            if let l = label?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty { return l }
            return assignedItems.first?.name
        }()
        if let l = resolvedLabel {
            drawSurfaceLabel(context: context, positions: positions, label: l)
        }
    }

    /// Accent fill + stroke layered over a selected surface so the pick reads
    /// at a glance in sun/gloves. No-op when the surface isn't selected.
    private func drawSelectionHighlight(context: GraphicsContext, path: Path, selected: Bool) {
        guard selected else { return }
        context.fill(path, with: .color(OPSStyle.Colors.primaryAccent.opacity(0.18)))
        context.stroke(path, with: .color(OPSStyle.Colors.primaryAccent), lineWidth: 2.5)
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
                     with: .color(OPSStyle.Colors.glassDenseApprox))
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
        // Selection halo under the edge so its type color still reads (fullscreen only).
        if showsTools && toolState.selectedEdgeIds.contains(edge.id) {
            context.stroke(path, with: .color(OPSStyle.Colors.primaryAccent), lineWidth: lineWidth + 5)
        }
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
    private func drawLevelSurfaceFill(context: GraphicsContext, level: DeckLevel, positions: [CGPoint], assignedItems: [AssignedItem] = [], label: String? = nil, selected: Bool = false) {
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

        drawSelectionHighlight(context: context, path: path, selected: selected)

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

    // MARK: - Select & Measure (taps write to the shared tool state)

    /// Toggle the edge under the tap into the selection; if no edge is in
    /// range, toggle the smallest enclosing surface. Edge hit-test wins so
    /// tapping a perimeter line picks the edge while tapping the interior
    /// picks the surface.
    private func recordSelectionTap(at location: CGPoint, in viewportSize: CGSize) {
        // Scissors armed: taps place the cut line instead of changing the
        // selection. Points get the same geometry + angle snapping as the
        // measure tool (perpendicular cuts across rectilinear decks are the
        // common case); the SECOND point snaps relative to the first.
        if toolState.isSplitting {
            let raw = canvasPoint(from: location, viewportSize: viewportSize)
            let snapped = snapToGeometry(raw)
            let point = toolState.splitPoints.count == 1
                ? snapAngleToEdges(from: toolState.splitPoints[0], candidate: snapped)
                : snapped
            let countBefore = toolState.splitPoints.count
            toolState.recordSplitTap(point)
            let countAfter = toolState.splitPoints.count
            // Haptic doctrine: light per placed point, success only when the
            // cut actually computes — a line that misses the face and an
            // ignored coincident tap both stay silent.
            if countAfter == 2 {
                if let surface = selectedSplitSurface(),
                   PolygonSplitter.split(polygon: surface,
                                         lineA: toolState.splitPoints[0],
                                         lineB: toolState.splitPoints[1]).didSplit {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } else if countAfter != countBefore {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            return
        }
        let p = canvasPoint(from: location, viewportSize: viewportSize)
        let edges = DeckSelectionReadout.edges(in: drawingData)
        let vertices = DeckSelectionReadout.vertices(in: drawingData)
        // Threshold tracks zoom so it stays ~finger-sized at any canvas scale.
        let edgeThreshold = max(14, 28 / Double(canvasScale))
        if let edgeId = PolygonMath.findEdgeAtPoint(p, edges: edges, vertices: vertices, hitThreshold: edgeThreshold) {
            if toolState.selectedEdgeIds.contains(edgeId) { toolState.selectedEdgeIds.remove(edgeId) } else { toolState.selectedEdgeIds.insert(edgeId) }
            toolState.selectionDidChange()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        let enclosing = DeckSelectionReadout.surfaceContexts(in: drawingData)
            .map(\.face)
            .filter { PolygonMath.pointInPolygon(p, vertices: $0.positions) }
            .min { PolygonMath.area(vertices: $0.positions) < PolygonMath.area(vertices: $1.positions) }
        if let face = enclosing {
            if toolState.selectedSurfaceIds.contains(face.id) { toolState.selectedSurfaceIds.remove(face.id) } else { toolState.selectedSurfaceIds.insert(face.id) }
            toolState.selectionDidChange()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Measurement Tool (Bug 033b5328)

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

    /// Measurement-mode tap: routed through the tool state's polyline machine
    /// (append / finish on last-dot tap / close on first-dot tap / reset after
    /// a frozen run). Close and finish are detected on the RAW canvas point —
    /// before snapping — so a nearby deck-vertex snap can't yank a deliberate
    /// close-tap out of the finger-sized target. Appended vertices snap to
    /// geometry (DECK-NEW-9), then the segment angle snaps parallel /
    /// perpendicular to nearby edges relative to the PREVIOUS vertex.
    private func recordMeasurementTap(at location: CGPoint, in viewportSize: CGSize) {
        let raw = canvasPoint(from: location, viewportSize: viewportSize)
        // Finger-sized close/finish target regardless of zoom.
        let closeThreshold = max(12, 22 / Double(canvasScale))
        let result = toolState.recordMeasureTap(
            raw: raw,
            closeThreshold: closeThreshold,
            snapPoint: { snapToGeometry($0) },
            snapSegmentEnd: { last, candidate in snapAngleToEdges(from: last, candidate: candidate) }
        )
        switch result {
        case .started, .appended:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .finished:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .closed:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .ignored:
            break
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
    /// already within ±5°. The line LENGTH and DIRECTION stay the same; only the
    /// angle is nudged onto the axis. Returns the original candidate when no edge
    /// is nearby. Thin adapter over the pure, unit-tested `SnapEngine` routine.
    private func snapAngleToEdges(from start: CGPoint, candidate: CGPoint) -> CGPoint {
        let vertices = drawingData.isMultiLevel
            ? drawingData.levels.flatMap { $0.vertices }
            : drawingData.vertices
        let edges = drawingData.isMultiLevel
            ? drawingData.levels.flatMap { $0.edges }
            : drawingData.edges
        let segments: [(start: CGPoint, end: CGPoint)] = edges.compactMap { edge in
            guard let s = vertices.first(where: { $0.id == edge.startVertexId }),
                  let e = vertices.first(where: { $0.id == edge.endVertexId }) else { return nil }
            return (start: s.position, end: e.position)
        }
        return SnapEngine.snapMeasurementEnd(from: start, candidate: candidate, referenceEdges: segments)
    }

    /// Render the measure polyline — anchor dots, dashed segments, per-segment
    /// length pills, the first-dot close halo, the faint close-preview edge,
    /// and (once closed) the loop fill + centroid area pill — inside the
    /// Canvas pass. Drawn last so the tool reads over the plan. Fullscreen only.
    ///
    /// Distances are always real-world readings: effectiveScaleFactor is the
    /// calibrated scale when set, else the prescale every edge is already
    /// dimensioned at (always > 0). All values format through DimensionEngine
    /// so metric decks read metric — matching dimension labels and readouts.
    private func drawMeasurement(context: GraphicsContext) {
        guard showsTools, toolState.isMeasuring else { return }
        let points = toolState.measurementPoints
        guard !points.isEmpty else { return }

        let lineColor = OPSStyle.Colors.warningStatus
        let closed = toolState.measurementPhase == .closed && points.count >= 3
        let scale = drawingData.effectiveScaleFactor
        let system = drawingData.config.measurementSystem

        // Closed loop — fill first so segments, dots, and pills stay legible over it.
        if closed {
            var fill = Path()
            fill.move(to: points[0])
            for p in points.dropFirst() { fill.addLine(to: p) }
            fill.closeSubpath()
            context.fill(fill, with: .color(lineColor.opacity(0.12)))
        }

        // Drawn segments, each with its mid-point length pill.
        for i in 1..<points.count {
            drawMeasureSegment(context: context, from: points[i - 1], to: points[i],
                               color: lineColor, scale: scale, system: system)
        }
        if closed {
            // The implicit closing edge is a real measured run — draw + label it.
            drawMeasureSegment(context: context, from: points[points.count - 1], to: points[0],
                               color: lineColor, scale: scale, system: system)
        } else if toolState.canCloseMeasurement {
            // Faint preview of the loop a first-dot tap would close.
            var preview = Path()
            preview.move(to: points[points.count - 1])
            preview.addLine(to: points[0])
            context.stroke(preview, with: .color(lineColor.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
        }

        // Vertex dots over the lines. The FIRST dot gets a halo while the loop
        // is closable — the visual target the "TAP FIRST TO CLOSE" hint names.
        let dotR: CGFloat = 6
        for (index, p) in points.enumerated() {
            if index == 0 && toolState.canCloseMeasurement {
                let haloR = dotR + 5
                let halo = Path(ellipseIn: CGRect(
                    x: p.x - haloR, y: p.y - haloR,
                    width: haloR * 2, height: haloR * 2
                ))
                context.stroke(halo, with: .color(lineColor.opacity(0.5)), lineWidth: 1.5)
            }
            let circle = Path(ellipseIn: CGRect(
                x: p.x - dotR, y: p.y - dotR,
                width: dotR * 2, height: dotR * 2
            ))
            context.fill(circle, with: .color(lineColor.opacity(0.2)))
            context.stroke(circle, with: .color(lineColor), lineWidth: 2)
        }

        // Enclosed area at the true centroid once closed. Suppressed for
        // self-intersecting loops — a bowtie's shoelace area is a net value,
        // not a footprint, and a confidently-wrong number erodes trust.
        if closed,
           !PolygonMath.isSelfIntersecting(vertices: points),
           let centroid = PolygonMath.polygonCentroid(vertices: points) {
            let areaSqIn = PolygonMath.realWorldArea(vertices: points, scaleFactor: scale)
            drawMeasurePill(
                context: context,
                text: DimensionEngine.formatArea(areaSqIn, system: system).uppercased(),
                at: centroid,
                color: lineColor,
                fontSize: 13
            )
        }
    }

    /// One dashed measure segment + its mid-point length pill. The pill is
    /// skipped when the segment is too short on screen to carry it — the
    /// card's running total still accounts for every segment.
    private func drawMeasureSegment(
        context: GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        scale: Double,
        system: MeasurementSystem
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

        let canvasLength = SnapEngine.distance(start, end)
        guard canvasLength * Double(canvasScale) >= 56 else { return }
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        drawMeasurePill(
            context: context,
            text: DimensionEngine.format(canvasLength / scale, system: system),
            at: mid,
            color: color,
            fontSize: 12
        )
    }

    /// Solid measure-color pill with black text — the measure tool's label style.
    private func drawMeasurePill(
        context: GraphicsContext,
        text: String,
        at point: CGPoint,
        color: Color,
        fontSize: CGFloat
    ) {
        let resolved = context.resolve(Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
            .foregroundColor(.black))
        let textSize = resolved.measure(in: CGSize(width: 220, height: 50))
        let padH: CGFloat = 8
        let padV: CGFloat = 4
        let bgRect = CGRect(
            x: point.x - textSize.width / 2 - padH,
            y: point.y - textSize.height / 2 - padV,
            width: textSize.width + padH * 2,
            height: textSize.height + padV * 2
        )
        context.fill(Path(roundedRect: bgRect, cornerRadius: OPSStyle.Layout.chipRadius), with: .color(color))
        context.draw(resolved, at: point, anchor: .center)
    }

    /// Render the split inspection: tinted side fills, the cut chord(s), and
    /// the two definition dots. Side tints match the card rows — A accent,
    /// B amber. Drawn last, over the plan and the selection highlight.
    private func drawSplit(context: GraphicsContext) {
        guard showsTools, toolState.isSplitting else { return }
        let points = toolState.splitPoints
        guard !points.isEmpty else { return }
        let accentA = OPSStyle.Colors.primaryAccent
        let accentB = OPSStyle.Colors.warningStatus

        // Definition dots (always visible so the first tap reads immediately).
        let dotR: CGFloat = 6
        for p in points {
            let circle = Path(ellipseIn: CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2))
            context.fill(circle, with: .color(Color.white.opacity(0.25)))
            context.stroke(circle, with: .color(Color.white), lineWidth: 2)
        }
        guard points.count == 2, let surface = selectedSplitSurface() else { return }

        let readout = DeckSplitReadout.build(
            surface: surface,
            cutA: points[0], cutB: points[1],
            scaleFactor: drawingData.effectiveScaleFactor,
            system: drawingData.config.measurementSystem
        )
        guard readout.didSplit else { return }

        var fillA = Path()
        if let first = readout.sideAPolygon.first {
            fillA.move(to: first)
            for p in readout.sideAPolygon.dropFirst() { fillA.addLine(to: p) }
            fillA.closeSubpath()
            context.fill(fillA, with: .color(accentA.opacity(0.18)))
        }
        var fillB = Path()
        if let first = readout.sideBPolygon.first {
            fillB.move(to: first)
            for p in readout.sideBPolygon.dropFirst() { fillB.addLine(to: p) }
            fillB.closeSubpath()
            context.fill(fillB, with: .color(accentB.opacity(0.15)))
        }
        for segment in readout.chordSegments {
            var chord = Path()
            chord.move(to: segment.start)
            chord.addLine(to: segment.end)
            context.stroke(chord, with: .color(Color.white), lineWidth: 2.5)
        }
    }

    /// Positions of the single selected surface (the scissors gate guarantees
    /// exactly one) — nil when the selection changed out from under the tool.
    private func selectedSplitSurface() -> [CGPoint]? {
        guard let id = toolState.selectedSurfaceIds.first,
              toolState.selectedSurfaceIds.count == 1 else { return nil }
        return DeckSelectionReadout.surfaceContexts(in: drawingData)
            .first(where: { $0.face.id == id })?
            .face.positions
    }
}
