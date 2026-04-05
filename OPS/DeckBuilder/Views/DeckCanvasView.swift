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

    // 4800 × 4800 pt workspace ≈ 400' × 400'
    private let canvasSize: CGFloat = 4800
    private let gridSpacing: CGFloat = 20.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                // Canvas content — large fixed workspace, transformed by scale + offset
                canvasContent
                    .frame(width: canvasSize, height: canvasSize)
                    .scaleEffect(canvasScale, anchor: .topLeading)
                    .offset(canvasOffset)

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
                    offset: $canvasOffset
                )
            }
            // SwiftUI gestures — single-finger drawing, tap, long-press
            .simultaneousGesture(drawGesture(size: geometry.size))
            .simultaneousGesture(tapGesture(size: geometry.size))
            .simultaneousGesture(longPressGesture(size: geometry.size))
            .onAppear {
                guard !hasInitializedOffset else { return }
                hasInitializedOffset = true
                centerViewportOnGeometry(viewportSize: geometry.size)
            }
        }
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)

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
                    if case .drawing(let fromId, let currentEnd) = viewModel.drawingMode {
                        drawActiveLine(context: context, fromVertexId: fromId, currentEnd: currentEnd)
                    }
                    for vertex in activeLevel.vertices {
                        drawVertex(context: context, vertex: vertex)
                    }
                    for edge in activeLevel.edges {
                        drawDimensionLabel(context: context, edge: edge, vertexLookup: activeLevel.vertex(byId:))
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
                if case .drawing(let fromId, let currentEnd) = viewModel.drawingMode {
                    drawActiveLine(context: context, fromVertexId: fromId, currentEnd: currentEnd)
                }
                for vertex in viewModel.drawingData.vertices {
                    drawVertex(context: context, vertex: vertex)
                }
                for edge in viewModel.drawingData.edges {
                    drawDimensionLabel(context: context, edge: edge, vertexLookup: viewModel.drawingData.vertex(byId:))
                }
            }
        }
    }

    // MARK: - Grid (visible region only)

    private func drawGrid(context: GraphicsContext, size: CGSize) {
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

        var path = Path()
        for col in startCol...endCol {
            let x = CGFloat(col) * gridSpacing
            path.move(to: CGPoint(x: x, y: visMinY))
            path.addLine(to: CGPoint(x: x, y: visMaxY))
        }
        for row in startRow...endRow {
            let y = CGFloat(row) * gridSpacing
            path.move(to: CGPoint(x: visMinX, y: y))
            path.addLine(to: CGPoint(x: visMaxX, y: y))
        }
        context.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
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
        context.fill(path, with: .color(Color.white.opacity(isSelected ? 0.08 : 0.03)))
    }

    // MARK: - Pool Overlay

    private func drawPoolOverlay(context: GraphicsContext, diameterInches: Double, scaleFactor: Double) {
        let positions = viewModel.drawingData.orderedPositions
        guard positions.count >= 3 else { return }
        let cx = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let cy = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        let r = CGFloat(diameterInches * scaleFactor) / 2
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        context.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.25)),
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
        context.draw(Text("Pool").font(OPSStyle.Typography.smallCaption)
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
            context.fill(p, with: .color(level.displayColor.swiftUIColor.opacity(0.08)))
        }
        for edge in level.edges {
            guard let s = level.vertex(byId: edge.startVertexId),
                  let e = level.vertex(byId: edge.endVertexId) else { continue }
            var ep = Path(); ep.move(to: s.position); ep.addLine(to: e.position)
            context.stroke(ep, with: .color(level.displayColor.swiftUIColor.opacity(0.2)), lineWidth: 1.5)
        }
        let cx = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let cy = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        context.draw(Text(level.name).font(OPSStyle.Typography.smallCaption)
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
        let isSelected = viewModel.selection.selectedFootprint
        context.fill(path, with: .color(level.displayColor.swiftUIColor.opacity(isSelected ? 0.12 : 0.06)))
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
        context.stroke(sp, with: .color(OPSStyle.Colors.warningStatus.opacity(0.4)), lineWidth: 1.5)
        let tc = connection.stairConfig.treadCount ?? 5
        for i in 1..<min(tc, 20) {
            let t = CGFloat(i) / CGFloat(tc)
            let ls = CGPoint(x: p1.x + dx * t, y: p1.y + dy * t)
            let le = CGPoint(x: ls.x + perpX * depth, y: ls.y + perpY * depth)
            var hp = Path(); hp.move(to: ls); hp.addLine(to: le)
            context.stroke(hp, with: .color(OPSStyle.Colors.warningStatus.opacity(0.25)), lineWidth: 1.0)
        }
        let lx = (p1.x + p3.x) / 2, ly = (p1.y + p3.y) / 2
        context.draw(Text("\(tc) treads").font(OPSStyle.Typography.miniLabel)
            .foregroundColor(OPSStyle.Colors.warningStatus.opacity(0.6)), at: CGPoint(x: lx, y: ly))
    }

    // MARK: - Edges

    private func drawEdge(context: GraphicsContext, edge: DeckEdge, vertexLookup: (String) -> DeckVertex?) {
        guard let start = vertexLookup(edge.startVertexId),
              let end = vertexLookup(edge.endVertexId) else { return }
        var path = Path(); path.move(to: start.position); path.addLine(to: end.position)
        let isSelected = viewModel.selection.selectedEdgeIds.contains(edge.id)

        // Railing indicator (subtle thicker line behind)
        if edge.railingConfig != nil {
            context.stroke(path, with: .color(Color.white.opacity(0.15)), lineWidth: isSelected ? 6 : 4)
        }

        // Main edge line — white, clean
        let lineColor: Color
        if edge.edgeType == .houseEdge {
            lineColor = OPSStyle.Colors.secondaryText.opacity(0.6)
        } else {
            lineColor = Color.white.opacity(isSelected ? 1.0 : 0.8)
        }
        context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5))

        // Selection glow — the ONE place accent color earns its presence
        if isSelected {
            context.stroke(path, with: .color(OPSStyle.Colors.primaryAccent.opacity(0.35)), lineWidth: 6)
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

    /// Architectural wall hatch: short 45° lines on the interior side of a house edge
    private func drawHouseHatch(context: GraphicsContext, start: CGPoint, end: CGPoint) {
        let dx = end.x - start.x, dy = end.y - start.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 4 else { return }
        let nx = dx / len, ny = dy / len  // unit direction along edge
        let perpX = -ny, perpY = nx       // perpendicular (into house)
        let spacing: CGFloat = 8
        let hatchLen: CGFloat = 6
        let count = Int(len / spacing)
        var hatchPath = Path()
        for i in 1...count {
            let t = CGFloat(i) * spacing
            let bx = start.x + nx * t
            let by = start.y + ny * t
            hatchPath.move(to: CGPoint(x: bx, y: by))
            hatchPath.addLine(to: CGPoint(x: bx + (perpX - nx) * hatchLen * 0.7,
                                          y: by + (perpY - ny) * hatchLen * 0.7))
        }
        context.stroke(hatchPath, with: .color(OPSStyle.Colors.secondaryText.opacity(0.35)), lineWidth: 1)
    }

    private func drawStairIndicator(context: GraphicsContext, start: CGPoint, end: CGPoint, edge: DeckEdge) {
        guard let config = edge.stairConfig, let tc = config.treadCount, tc > 0 else { return }
        let dx = end.x - start.x, dy = end.y - start.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return }
        let perpX = -dy / len * 8, perpY = dx / len * 8
        let fraction = min(config.width, len) / len
        for i in 0..<min(tc, 20) {
            let t = CGFloat(i) / CGFloat(tc) * fraction
            let cx = start.x + dx * t, cy = start.y + dy * t
            var tp = Path()
            tp.move(to: CGPoint(x: cx - perpX, y: cy - perpY))
            tp.addLine(to: CGPoint(x: cx + perpX, y: cy + perpY))
            context.stroke(tp, with: .color(Color.white.opacity(0.2)), lineWidth: 1)
        }
    }

    // MARK: - Active Drawing Line

    private func drawActiveLine(context: GraphicsContext, fromVertexId: String, currentEnd: CGPoint) {
        guard let startVertex = resolveVertex(byId: fromVertexId) else { return }
        var path = Path(); path.move(to: startVertex.position); path.addLine(to: currentEnd)
        context.stroke(path, with: .color(Color.white.opacity(0.6)),
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))

        let distance = SnapEngine.distance(startVertex.position, currentEnd)
        guard distance > 1 else { return }

        // Dimension — always show length
        let scale = viewModel.drawingData.scaleFactor ?? 1.0
        let inches = distance / max(scale, 0.001)
        let dimText = DimensionEngine.format(inches, system: viewModel.drawingData.config.measurementSystem)

        // Angle — relative if extending from existing edge, else absolute
        let edges = viewModel.isMultiLevel ? (viewModel.activeLevel?.edges ?? []) : viewModel.drawingData.edges
        let connected = edges.filter { $0.startVertexId == fromVertexId || $0.endVertexId == fromVertexId }
        let angleText: String
        if let prev = connected.last {
            let otherId = prev.startVertexId == fromVertexId ? prev.endVertexId : prev.startVertexId
            if let other = resolveVertex(byId: otherId) {
                let prevA = SnapEngine.lineAngle(from: startVertex.position, to: other.position)
                let newA = SnapEngine.lineAngle(from: startVertex.position, to: currentEnd)
                var rel = newA - prevA; if rel < 0 { rel += 360 }; if rel > 180 { rel = 360 - rel }
                angleText = String(format: "%.0f\u{00B0}", rel)
            } else {
                angleText = String(format: "%.0f\u{00B0}", SnapEngine.lineAngle(from: startVertex.position, to: currentEnd))
            }
        } else {
            angleText = String(format: "%.0f\u{00B0}", SnapEngine.lineAngle(from: startVertex.position, to: currentEnd))
        }

        let label = "\(dimText)  \(angleText)"
        let midX = (startVertex.position.x + currentEnd.x) / 2
        let midY = (startVertex.position.y + currentEnd.y) / 2

        // Dark pill background
        let pillW: CGFloat = CGFloat(label.count) * 7.5 + 20
        let pillH: CGFloat = 22
        let pillRect = CGRect(x: midX - pillW / 2, y: midY - 30 - pillH / 2, width: pillW, height: pillH)
        context.fill(Path(roundedRect: pillRect, cornerRadius: 4),
                     with: .color(OPSStyle.Colors.cardBackground.opacity(0.95)))
        context.stroke(Path(roundedRect: pillRect, cornerRadius: 4),
                       with: .color(Color.white.opacity(0.1)), lineWidth: 0.5)
        context.draw(Text(label).font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(Color.white), at: CGPoint(x: midX, y: midY - 30))
    }

    // MARK: - Vertices

    private func drawVertex(context: GraphicsContext, vertex: DeckVertex) {
        let isSelected = viewModel.selection.selectedVertexIds.contains(vertex.id)
        let r: CGFloat = isSelected ? 7 : 5

        if isSelected {
            let ring = CGRect(x: vertex.position.x - r - 3, y: vertex.position.y - r - 3,
                              width: (r + 3) * 2, height: (r + 3) * 2)
            context.stroke(Path(ellipseIn: ring), with: .color(OPSStyle.Colors.primaryAccent.opacity(0.6)), lineWidth: 1.5)
        }

        let dot = CGRect(x: vertex.position.x - r, y: vertex.position.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: dot), with: .color(isSelected ? OPSStyle.Colors.primaryAccent : Color.white))

        if let elevation = vertex.elevation {
            let label = DimensionEngine.formatImperial(elevation * 12)
            context.draw(Text(label).font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText), at: CGPoint(x: vertex.position.x, y: vertex.position.y + r + 12))
        }
    }

    // MARK: - Dimension Labels (offset from line with dark pill)

    private func drawDimensionLabel(context: GraphicsContext, edge: DeckEdge, vertexLookup: (String) -> DeckVertex?) {
        guard let dim = edge.dimension,
              let start = vertexLookup(edge.startVertexId),
              let end = vertexLookup(edge.endVertexId) else { return }

        let midX = (start.position.x + end.position.x) / 2
        let midY = (start.position.y + end.position.y) / 2
        let label = DimensionEngine.format(dim, system: viewModel.drawingData.config.measurementSystem)
        let hasAccuracy = edge.accuracyPercent != nil

        // Offset label perpendicular to the edge so it doesn't sit on the line
        let dx = end.position.x - start.position.x
        let dy = end.position.y - start.position.y
        let len = sqrt(dx * dx + dy * dy)
        let offsetDist: CGFloat = 18
        let perpX = len > 0 ? (-dy / len) * offsetDist : 0
        let perpY = len > 0 ? (dx / len) * offsetDist : -offsetDist
        let labelX = midX + perpX
        let labelY = midY + perpY

        // Dark pill background
        let pillW = CGFloat(label.count) * 7.5 + 16
        let pillH: CGFloat = 20
        let pillRect = CGRect(x: labelX - pillW / 2, y: labelY - pillH / 2, width: pillW, height: pillH)
        let pillColor: Color = hasAccuracy
            ? OPSStyle.Colors.warningStatus.opacity(0.15)
            : OPSStyle.Colors.cardBackground.opacity(0.95)
        context.fill(Path(roundedRect: pillRect, cornerRadius: 4), with: .color(pillColor))
        context.stroke(Path(roundedRect: pillRect, cornerRadius: 4),
                       with: .color(Color.white.opacity(0.08)), lineWidth: 0.5)

        let labelColor: Color = hasAccuracy ? OPSStyle.Colors.warningStatus : Color.white
        context.draw(Text(label).font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(labelColor), at: CGPoint(x: labelX, y: labelY))

        if let accuracy = edge.accuracyPercent {
            let accLabel = AccuracyModel.formatAccuracy(dimensionInches: dim, accuracyPercent: accuracy,
                                                         system: viewModel.drawingData.config.measurementSystem)
            context.draw(Text(accLabel).font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.warningStatus), at: CGPoint(x: labelX, y: labelY + 12))
        } else if edge.dimensionSource == .ar {
            context.draw(Text("AR").font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.successStatus.opacity(0.6)),
                         at: CGPoint(x: labelX + pillW / 2 + 12, y: labelY))
        }
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    private var selectionOverlay: some View {
        if case .selecting(let rect) = viewModel.drawingMode {
            Rectangle()
                .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .background(Color.white.opacity(0.03))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        if case .lassoing(let points) = viewModel.drawingMode, points.count >= 2 {
            Path { p in p.move(to: points[0]); for i in 1..<points.count { p.addLine(to: points[i]) } }
                .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
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
        CGPoint(
            x: (location.x - canvasOffset.width) / canvasScale,
            y: (location.y - canvasOffset.height) / canvasScale
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
                        }
                        if case .draggingVertex = viewModel.drawingMode {
                            viewModel.updateVertexDrag(to: point)
                        } else {
                            viewModel.updateLine(to: point)
                        }
                    case .select:
                        if !drawingStarted { drawingStarted = true; viewModel.beginMarquee(at: startPoint) }
                        viewModel.updateMarquee(to: point)
                    case .lasso:
                        if !drawingStarted { drawingStarted = true; viewModel.beginLasso(at: startPoint) }
                        viewModel.updateLasso(to: point)
                    case .none: break
                    }
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
                    case .none: break
                    }
                default: break
                }
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

// MARK: - UIKit Gesture Handler (Unified Pinch + Pan)

/// Transparent view that forwards all raw touches to the responder chain (SwiftUI)
/// while still letting its own gesture recognizers evaluate multi-touch gestures.
private class GesturePassthroughView: UIView {
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
private struct CanvasGestureView: UIViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    func makeUIView(context: Context) -> GesturePassthroughView {
        let view = GesturePassthroughView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delaysTouchesBegan = false
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: GesturePassthroughView, context: Context) {
        context.coordinator.scaleBinding = $scale
        context.coordinator.offsetBinding = $offset
    }

    func makeCoordinator() -> Coordinator { Coordinator(scale: $scale, offset: $offset) }

    class Coordinator: NSObject {
        var scaleBinding: Binding<CGFloat>
        var offsetBinding: Binding<CGSize>
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
