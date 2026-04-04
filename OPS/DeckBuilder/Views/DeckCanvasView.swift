// OPS/OPS/DeckBuilder/Views/DeckCanvasView.swift

import SwiftUI

struct DeckCanvasView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel

    // MARK: - Gesture State

    @State private var canvasScale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero
    @State private var lastDragValue: CGSize = .zero
    @State private var drawingStarted = false
    @State private var longPressLocation: CGPoint?
    @State private var hasInitializedOffset = false

    // Canvas workspace: 4800 × 4800 pts ≈ 400' × 400' at ~1pt/inch
    private let canvasSize: CGFloat = 4800

    // Grid
    private let gridSpacing: CGFloat = 20.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                // Transformed canvas content — fixed large workspace
                canvasContent(size: CGSize(width: canvasSize, height: canvasSize))
                    .frame(width: canvasSize, height: canvasSize)
                    .scaleEffect(canvasScale, anchor: .topLeading)
                    .offset(canvasOffset)

                // Selection overlay (marquee rect)
                selectionOverlay

                // Dimension info bar at top
                if viewModel.isClosed, let area = viewModel.totalArea {
                    dimensionInfoBar(area: area)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay {
                // Two-finger pan via UIKit (SwiftUI DragGesture can't filter by touch count)
                TwoFingerPanView(
                    offset: $canvasOffset,
                    lastOffset: $lastDragValue,
                    drawingStarted: drawingStarted
                )
            }
            .simultaneousGesture(drawGesture(size: geometry.size))
            .simultaneousGesture(tapGesture(size: geometry.size))
            .simultaneousGesture(longPressGesture(size: geometry.size))
            .simultaneousGesture(pinchGesture)
            .onAppear {
                guard !hasInitializedOffset else { return }
                hasInitializedOffset = true
                // Start with the center of the canvas visible
                let offsetX = (geometry.size.width - canvasSize) / 2
                let offsetY = (geometry.size.height - canvasSize) / 2
                canvasOffset = CGSize(width: offsetX, height: offsetY)
                lastDragValue = canvasOffset
            }
        }
    }

    // MARK: - Canvas Content

    @ViewBuilder
    private func canvasContent(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            // Draw grid
            drawGrid(context: context, size: canvasSize)

            if viewModel.isMultiLevel {
                // Multi-level rendering: inactive → connections → active
                for (index, level) in viewModel.drawingData.levels.enumerated() {
                    if index != viewModel.activeLevelIndex {
                        drawInactiveLevel(context: context, level: level)
                    }
                }
                for connection in viewModel.drawingData.levelConnections {
                    drawLevelConnection(context: context, connection: connection)
                }
                if let activeLevel = viewModel.activeLevel {
                    drawLevelFootprint(context: context, level: activeLevel, isActive: true)
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
                // Single-level rendering (existing behavior)
                if viewModel.isClosed {
                    drawFootprint(context: context)
                }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Multi-Level: Inactive Level

    private func drawInactiveLevel(context: GraphicsContext, level: DeckLevel) {
        let positions = level.orderedPositions
        guard positions.count >= 3 else { return }

        // Footprint fill at 15% opacity with level color
        if level.isClosed {
            var fillPath = Path()
            fillPath.move(to: positions[0])
            for i in 1..<positions.count {
                fillPath.addLine(to: positions[i])
            }
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(level.displayColor.swiftUIColor.opacity(0.15)))
        }

        // Edges at 30% opacity
        for edge in level.edges {
            guard let start = level.vertex(byId: edge.startVertexId),
                  let end = level.vertex(byId: edge.endVertexId) else { continue }
            var edgePath = Path()
            edgePath.move(to: start.position)
            edgePath.addLine(to: end.position)
            context.stroke(edgePath, with: .color(level.displayColor.swiftUIColor.opacity(0.3)), lineWidth: 1.5)
        }

        // Level name at centroid
        if positions.count >= 3 {
            let cx = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
            let cy = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
            context.draw(
                Text(level.name)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(level.displayColor.swiftUIColor.opacity(0.5)),
                at: CGPoint(x: cx, y: cy)
            )
        }
    }

    // MARK: - Multi-Level: Active Level Footprint

    private func drawLevelFootprint(context: GraphicsContext, level: DeckLevel, isActive: Bool) {
        guard level.isClosed else { return }
        let positions = level.orderedPositions
        guard positions.count >= 3 else { return }

        var path = Path()
        path.move(to: positions[0])
        for i in 1..<positions.count {
            path.addLine(to: positions[i])
        }
        path.closeSubpath()

        let isSelected = viewModel.selection.selectedFootprint
        let fillOpacity = isSelected ? 0.2 : 0.1
        context.fill(path, with: .color(level.displayColor.swiftUIColor.opacity(fillOpacity)))
    }

    // MARK: - Multi-Level: Connection Stairs

    private func drawLevelConnection(context: GraphicsContext, connection: LevelConnection) {
        // Find the upper edge to position stairs
        guard let upperLevel = viewModel.drawingData.level(byId: connection.upperLevelId),
              let edge = upperLevel.edge(byId: connection.upperEdgeId),
              let start = upperLevel.vertex(byId: edge.startVertexId),
              let end = upperLevel.vertex(byId: edge.endVertexId) else { return }

        let dx = end.position.x - start.position.x
        let dy = end.position.y - start.position.y
        let edgeLength = sqrt(dx * dx + dy * dy)
        guard edgeLength > 0 else { return }

        // Perpendicular direction for stair depth
        let perpX = -dy / edgeLength
        let perpY = dx / edgeLength
        let stairDepth: CGFloat = 30.0 // visual depth in canvas points

        // Stair rectangle along the edge
        let p1 = start.position
        let p2 = end.position
        let p3 = CGPoint(x: p2.x + perpX * stairDepth, y: p2.y + perpY * stairDepth)
        let p4 = CGPoint(x: p1.x + perpX * stairDepth, y: p1.y + perpY * stairDepth)

        // Hatched fill
        var stairPath = Path()
        stairPath.move(to: p1)
        stairPath.addLine(to: p2)
        stairPath.addLine(to: p3)
        stairPath.addLine(to: p4)
        stairPath.closeSubpath()

        let stairColor = LevelColor.amber.swiftUIColor
        context.fill(stairPath, with: .color(stairColor.opacity(0.15)))
        context.stroke(stairPath, with: .color(stairColor.opacity(0.6)), lineWidth: 1.5)

        // Hatch lines (perpendicular lines across the stair rectangle)
        let treadCount = connection.stairConfig.treadCount ?? 5
        let normalX = dx / edgeLength
        let normalY = dy / edgeLength
        for i in 1..<min(treadCount, 20) {
            let t = CGFloat(i) / CGFloat(treadCount)
            let lineStart = CGPoint(x: p1.x + dx * t, y: p1.y + dy * t)
            let lineEnd = CGPoint(x: lineStart.x + perpX * stairDepth, y: lineStart.y + perpY * stairDepth)
            var hatchPath = Path()
            hatchPath.move(to: lineStart)
            hatchPath.addLine(to: lineEnd)
            context.stroke(hatchPath, with: .color(stairColor.opacity(0.4)), lineWidth: 1.0)
        }

        // Label
        let labelX = (p1.x + p3.x) / 2
        let labelY = (p1.y + p3.y) / 2
        context.draw(
            Text("\(treadCount) treads")
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(stairColor),
            at: CGPoint(x: labelX, y: labelY)
        )
    }

    // MARK: - Grid

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridColor = OPSStyle.Colors.cardBackground.resolve(in: EnvironmentValues())

        // Only draw grid lines in the visible region for performance
        // Visible region in canvas coordinates:
        let visibleMinX = max(0, -canvasOffset.width / canvasScale)
        let visibleMinY = max(0, -canvasOffset.height / canvasScale)
        let viewportW = UIScreen.main.bounds.width / canvasScale
        let viewportH = UIScreen.main.bounds.height / canvasScale
        let visibleMaxX = min(size.width, visibleMinX + viewportW + gridSpacing)
        let visibleMaxY = min(size.height, visibleMinY + viewportH + gridSpacing)

        let startCol = max(0, Int(floor(visibleMinX / gridSpacing)))
        let endCol = min(Int(size.width / gridSpacing), Int(ceil(visibleMaxX / gridSpacing)))
        let startRow = max(0, Int(floor(visibleMinY / gridSpacing)))
        let endRow = min(Int(size.height / gridSpacing), Int(ceil(visibleMaxY / gridSpacing)))

        var path = Path()
        for col in startCol...endCol {
            let x = CGFloat(col) * gridSpacing
            path.move(to: CGPoint(x: x, y: visibleMinY))
            path.addLine(to: CGPoint(x: x, y: visibleMaxY))
        }
        for row in startRow...endRow {
            let y = CGFloat(row) * gridSpacing
            path.move(to: CGPoint(x: visibleMinX, y: y))
            path.addLine(to: CGPoint(x: visibleMaxX, y: y))
        }

        context.stroke(
            path,
            with: .color(Color(red: Double(gridColor.red), green: Double(gridColor.green), blue: Double(gridColor.blue)).opacity(0.3)),
            lineWidth: 0.5
        )
    }

    // MARK: - Footprint

    private func drawFootprint(context: GraphicsContext) {
        let positions = viewModel.drawingData.orderedPositions
        guard positions.count >= 3 else { return }

        var path = Path()
        path.move(to: positions[0])
        for i in 1..<positions.count {
            path.addLine(to: positions[i])
        }
        path.closeSubpath()

        let isSelected = viewModel.selection.selectedFootprint
        let fillOpacity = isSelected ? 0.2 : 0.1
        context.fill(path, with: .color(OPSStyle.Colors.primaryAccent.opacity(fillOpacity)))
    }

    // MARK: - Pool Overlay

    private func drawPoolOverlay(context: GraphicsContext, diameterInches: Double, scaleFactor: Double) {
        let positions = viewModel.drawingData.orderedPositions
        guard positions.count >= 3 else { return }

        // Center of the footprint
        let centerX = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let centerY = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        let radiusPts = CGFloat(diameterInches * scaleFactor) / 2

        let circleRect = CGRect(
            x: centerX - radiusPts,
            y: centerY - radiusPts,
            width: radiusPts * 2,
            height: radiusPts * 2
        )

        context.stroke(
            Path(ellipseIn: circleRect),
            with: .color(OPSStyle.Colors.primaryAccent.opacity(0.4)),
            style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
        )

        // "Pool" label at center
        context.draw(
            Text("Pool")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryAccent.opacity(0.6)),
            at: CGPoint(x: centerX, y: centerY)
        )
    }

    // MARK: - Edges

    private func drawEdge(context: GraphicsContext, edge: DeckEdge, vertexLookup: (String) -> DeckVertex?) {
        guard let start = vertexLookup(edge.startVertexId),
              let end = vertexLookup(edge.endVertexId) else { return }

        var path = Path()
        path.move(to: start.position)
        path.addLine(to: end.position)

        let isSelected = viewModel.selection.selectedEdgeIds.contains(edge.id)

        // Railing indicator (thicker line behind)
        if edge.railingConfig != nil {
            context.stroke(
                path,
                with: .color(OPSStyle.Colors.primaryAccent.opacity(0.5)),
                lineWidth: isSelected ? 6.0 : 4.0
            )
        }

        // Main edge line
        let edgeColor: Color
        if edge.accuracyPercent != nil {
            edgeColor = OPSStyle.Colors.warningStatus.opacity(0.8)
        } else if edge.edgeType == .houseEdge {
            edgeColor = OPSStyle.Colors.secondaryText
        } else {
            edgeColor = Color.white
        }

        context.stroke(
            path,
            with: .color(edgeColor),
            style: StrokeStyle(lineWidth: isSelected ? 3.0 : 2.0)
        )

        // Selection glow
        if isSelected {
            context.stroke(
                path,
                with: .color(OPSStyle.Colors.primaryAccent.opacity(0.4)),
                lineWidth: 6.0
            )
        }

        // Stair indicator
        if edge.stairConfig != nil {
            drawStairIndicator(context: context, start: start.position, end: end.position, edge: edge)
        }
    }

    private func drawStairIndicator(context: GraphicsContext, start: CGPoint, end: CGPoint, edge: DeckEdge) {
        guard let stairConfig = edge.stairConfig, let treadCount = stairConfig.treadCount, treadCount > 0 else { return }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return }

        // Perpendicular direction (for tread lines)
        let perpX = -dy / length * 8.0
        let perpY = dx / length * 8.0

        let stairWidth = min(stairConfig.width, length)
        let stairFraction = stairWidth / length

        for i in 0..<min(treadCount, 20) { // cap visual treads
            let t = CGFloat(i) / CGFloat(treadCount) * stairFraction
            let cx = start.x + dx * t
            let cy = start.y + dy * t

            var treadPath = Path()
            treadPath.move(to: CGPoint(x: cx - perpX, y: cy - perpY))
            treadPath.addLine(to: CGPoint(x: cx + perpX, y: cy + perpY))

            context.stroke(treadPath, with: .color(OPSStyle.Colors.primaryAccent.opacity(0.4)), lineWidth: 1.0)
        }
    }

    // MARK: - Active Drawing Line

    private func drawActiveLine(context: GraphicsContext, fromVertexId: String, currentEnd: CGPoint) {
        guard let startVertex = resolveVertex(byId: fromVertexId) else { return }

        var path = Path()
        path.move(to: startVertex.position)
        path.addLine(to: currentEnd)

        context.stroke(
            path,
            with: .color(OPSStyle.Colors.primaryAccent),
            style: StrokeStyle(lineWidth: 2.0, dash: [8, 4])
        )

        // Live annotation: dimension + angle
        let distance = SnapEngine.distance(startVertex.position, currentEnd)
        guard distance > 1 else { return } // skip label for zero-length lines

        let midX = (startVertex.position.x + currentEnd.x) / 2
        let midY = (startVertex.position.y + currentEnd.y) / 2

        // Dimension text (if scale is set)
        let dimText: String?
        if let scale = viewModel.drawingData.scaleFactor, scale > 0 {
            let inches = distance / scale
            dimText = DimensionEngine.format(inches, system: viewModel.drawingData.config.measurementSystem)
        } else {
            dimText = nil
        }

        // Angle text: relative to connected edge if one exists, otherwise absolute
        let activeEdges = viewModel.isMultiLevel
            ? (viewModel.activeLevel?.edges ?? [])
            : viewModel.drawingData.edges
        let connectedEdges = activeEdges.filter {
            $0.startVertexId == fromVertexId || $0.endVertexId == fromVertexId
        }

        let angleText: String
        if let prevEdge = connectedEdges.last {
            // Relative angle to the connected edge
            let otherVertexId = prevEdge.startVertexId == fromVertexId ? prevEdge.endVertexId : prevEdge.startVertexId
            if let otherVertex = resolveVertex(byId: otherVertexId) {
                let prevAngle = SnapEngine.lineAngle(from: startVertex.position, to: otherVertex.position)
                let newAngle = SnapEngine.lineAngle(from: startVertex.position, to: currentEnd)
                var relative = newAngle - prevAngle
                if relative < 0 { relative += 360 }
                if relative > 180 { relative = 360 - relative }
                angleText = String(format: "%.0f°", relative)
            } else {
                let absolute = SnapEngine.lineAngle(from: startVertex.position, to: currentEnd)
                angleText = String(format: "%.0f°", absolute)
            }
        } else {
            let absolute = SnapEngine.lineAngle(from: startVertex.position, to: currentEnd)
            angleText = String(format: "%.0f°", absolute)
        }

        let label = dimText != nil ? "\(dimText!) · \(angleText)" : angleText

        context.draw(
            Text(label)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent),
            at: CGPoint(x: midX, y: midY - 16)
        )
    }

    // MARK: - Vertices

    private func drawVertex(context: GraphicsContext, vertex: DeckVertex) {
        let isSelected = viewModel.selection.selectedVertexIds.contains(vertex.id)
        let radius: CGFloat = isSelected ? 8.0 : 6.0

        // Selection ring
        if isSelected {
            let ringRect = CGRect(
                x: vertex.position.x - radius - 4,
                y: vertex.position.y - radius - 4,
                width: (radius + 4) * 2,
                height: (radius + 4) * 2
            )
            context.stroke(
                Path(ellipseIn: ringRect),
                with: .color(OPSStyle.Colors.primaryAccent),
                lineWidth: 2.0
            )
        }

        // Vertex dot
        let dotRect = CGRect(
            x: vertex.position.x - radius,
            y: vertex.position.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(
            Path(ellipseIn: dotRect),
            with: .color(isSelected ? OPSStyle.Colors.primaryAccent : Color.white)
        )

        // Elevation badge
        if let elevation = vertex.elevation {
            let label = DimensionEngine.formatImperial(elevation * 12) // feet → inches for formatting
            context.draw(
                Text(label)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.primaryAccent),
                at: CGPoint(x: vertex.position.x, y: vertex.position.y + radius + 12)
            )
        }
    }

    // MARK: - Dimension Labels

    private func drawDimensionLabel(context: GraphicsContext, edge: DeckEdge, vertexLookup: (String) -> DeckVertex?) {
        guard let dim = edge.dimension,
              let start = vertexLookup(edge.startVertexId),
              let end = vertexLookup(edge.endVertexId) else { return }

        let midX = (start.position.x + end.position.x) / 2
        let midY = (start.position.y + end.position.y) / 2
        let label = DimensionEngine.format(dim, system: viewModel.drawingData.config.measurementSystem)
        let hasAccuracy = edge.accuracyPercent != nil

        // Background pill
        let textSize = label.count * 8 + 16
        let pillRect = CGRect(
            x: midX - CGFloat(textSize) / 2,
            y: midY - 24,
            width: CGFloat(textSize),
            height: 20
        )
        let pillColor: Color = hasAccuracy
            ? OPSStyle.Colors.warningStatus.opacity(0.15)
            : OPSStyle.Colors.cardBackground.opacity(0.9)
        context.fill(
            Path(roundedRect: pillRect, cornerRadius: 4),
            with: .color(pillColor)
        )

        let labelColor: Color = hasAccuracy ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryAccent
        context.draw(
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(labelColor),
            at: CGPoint(x: midX, y: midY - 14)
        )

        // Accuracy badge below dimension label
        if let accuracy = edge.accuracyPercent {
            let accLabel = AccuracyModel.formatAccuracy(
                dimensionInches: dim,
                accuracyPercent: accuracy,
                system: viewModel.drawingData.config.measurementSystem
            )
            context.draw(
                Text(accLabel)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.warningStatus),
                at: CGPoint(x: midX, y: midY - 2)
            )
        } else if edge.dimensionSource == .ar {
            // AR source but manually verified — show checkmark
            context.draw(
                Text("AR ✓")
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.successStatus),
                at: CGPoint(x: midX + CGFloat(textSize) / 2 + 14, y: midY - 14)
            )
        }
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    private var selectionOverlay: some View {
        if case .selecting(let rect) = viewModel.drawingMode {
            Rectangle()
                .stroke(OPSStyle.Colors.primaryAccent, style: StrokeStyle(lineWidth: 1.0, dash: [4, 4]))
                .background(OPSStyle.Colors.primaryAccent.opacity(0.05))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }

        if case .lassoing(let points) = viewModel.drawingMode, points.count >= 2 {
            Path { path in
                path.move(to: points[0])
                for i in 1..<points.count {
                    path.addLine(to: points[i])
                }
            }
            .stroke(OPSStyle.Colors.primaryAccent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
        }
    }

    // MARK: - Info Bar

    @ViewBuilder
    private func dimensionInfoBar(area: Double) -> some View {
        VStack {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Label(
                    DimensionEngine.formatArea(area, system: viewModel.drawingData.config.measurementSystem),
                    systemImage: "square.dashed"
                )
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

                if let perimeter = viewModel.totalPerimeter {
                    Label(
                        DimensionEngine.format(perimeter, system: viewModel.drawingData.config.measurementSystem),
                        systemImage: "ruler"
                    )
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

    // MARK: - Vertex Resolution

    /// Resolve a vertex across all levels or top-level data
    private func resolveVertex(byId id: String) -> DeckVertex? {
        if viewModel.isMultiLevel {
            for level in viewModel.drawingData.levels {
                if let v = level.vertex(byId: id) { return v }
            }
            return nil
        }
        return viewModel.drawingData.vertex(byId: id)
    }

    // MARK: - Gestures

    private func canvasPoint(from location: CGPoint, in size: CGSize) -> CGPoint {
        // Inverse transform: remove offset and scale
        CGPoint(
            x: (location.x - canvasOffset.width) / canvasScale,
            y: (location.y - canvasOffset.height) / canvasScale
        )
    }

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
                            viewModel.beginLine(from: startPoint)
                        }
                        viewModel.updateLine(to: point)

                    case .select:
                        if !drawingStarted {
                            drawingStarted = true
                            viewModel.beginMarquee(at: startPoint)
                        }
                        viewModel.updateMarquee(to: point)

                    case .lasso:
                        if !drawingStarted {
                            drawingStarted = true
                            viewModel.beginLasso(at: startPoint)
                        }
                        viewModel.updateLasso(to: point)

                    case .none:
                        break
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                switch value {
                case .second(true, let drag):
                    guard let drag = drag, drawingStarted else { break }
                    let point = canvasPoint(from: drag.location, in: size)

                    switch viewModel.activeTool {
                    case .draw:
                        viewModel.endLine(at: point)
                    case .select:
                        viewModel.endMarquee()
                    case .lasso:
                        viewModel.endLasso()
                    case .none:
                        break
                    }
                default:
                    break
                }
                drawingStarted = false
            }
    }

    private func tapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let point = canvasPoint(from: value.location, in: size)
                // Scale hit threshold inversely with zoom for 44pt minimum physical touch target
                let hitThreshold = max(22.0, 25.0 / canvasScale)
                viewModel.handleTap(at: point, hitThreshold: hitThreshold)
            }
    }

    private func longPressGesture(size: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onEnded { value in
                switch value {
                case .second(true, let drag):
                    let location = drag?.location ?? .zero
                    let point = canvasPoint(from: location, in: size)
                    let hitThreshold = max(22.0, 25.0 / canvasScale)
                    viewModel.handleLongPress(at: point, hitThreshold: hitThreshold)
                default:
                    break
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                // Disable zoom during active drawing to prevent endpoint jumps
                if case .idle = viewModel.drawingMode {} else { return }
                canvasScale = max(0.3, min(5.0, baseScale * scale))
            }
            .onEnded { scale in
                if case .idle = viewModel.drawingMode {} else { return }
                baseScale = max(0.3, min(5.0, baseScale * scale))
                canvasScale = baseScale
            }
    }

}

// MARK: - Two-Finger Pan (UIKit Gesture Recognizer)

/// UIKit-based two-finger pan gesture. SwiftUI's DragGesture cannot distinguish finger count.
private struct TwoFingerPanView: UIViewRepresentable {
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    var drawingStarted: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        var parent: TwoFingerPanView

        init(parent: TwoFingerPanView) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard !parent.drawingStarted else { return }
            let translation = gesture.translation(in: gesture.view)

            switch gesture.state {
            case .changed:
                parent.offset = CGSize(
                    width: parent.lastOffset.width + translation.x,
                    height: parent.lastOffset.height + translation.y
                )
            case .ended, .cancelled:
                parent.lastOffset = parent.offset
            default:
                break
            }
        }
    }
}
