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

    // Grid
    private let gridSpacing: CGFloat = 20.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                // Transformed canvas content
                canvasContent(size: geometry.size)
                    .scaleEffect(canvasScale)
                    .offset(canvasOffset)

                // Selection overlay (marquee rect)
                selectionOverlay

                // Dimension info bar at top
                if viewModel.isClosed, let area = viewModel.totalArea {
                    dimensionInfoBar(area: area)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(drawGesture(size: geometry.size))
            .simultaneousGesture(tapGesture(size: geometry.size))
            .simultaneousGesture(longPressGesture(size: geometry.size))
            .simultaneousGesture(pinchGesture)
            .simultaneousGesture(panGesture)
        }
    }

    // MARK: - Canvas Content

    @ViewBuilder
    private func canvasContent(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            // Draw grid
            drawGrid(context: context, size: canvasSize)

            // Draw footprint fill (closed polygon)
            if viewModel.isClosed {
                drawFootprint(context: context)
            }

            // Draw pool cutout overlay (dashed circle, visual only)
            if let poolDiameter = viewModel.drawingData.poolDiameter,
               let scale = viewModel.drawingData.scaleFactor, scale > 0 {
                drawPoolOverlay(context: context, diameterInches: poolDiameter, scaleFactor: scale)
            }

            // Draw edges
            for edge in viewModel.drawingData.edges {
                drawEdge(context: context, edge: edge)
            }

            // Draw active drawing line
            if case .drawing(let fromId, let currentEnd) = viewModel.drawingMode {
                drawActiveLine(context: context, fromVertexId: fromId, currentEnd: currentEnd)
            }

            // Draw vertices
            for vertex in viewModel.drawingData.vertices {
                drawVertex(context: context, vertex: vertex)
            }

            // Draw dimension labels
            for edge in viewModel.drawingData.edges {
                drawDimensionLabel(context: context, edge: edge)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridColor = OPSStyle.Colors.cardBackground.resolve(in: EnvironmentValues())
        var path = Path()

        let cols = Int(size.width / gridSpacing) + 1
        let rows = Int(size.height / gridSpacing) + 1

        for col in 0...cols {
            let x = CGFloat(col) * gridSpacing
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        for row in 0...rows {
            let y = CGFloat(row) * gridSpacing
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(OPSStyle.Colors.primaryAccent.opacity(0.6)),
            at: CGPoint(x: centerX, y: centerY)
        )
    }

    // MARK: - Edges

    private func drawEdge(context: GraphicsContext, edge: DeckEdge) {
        guard let start = viewModel.drawingData.vertex(byId: edge.startVertexId),
              let end = viewModel.drawingData.vertex(byId: edge.endVertexId) else { return }

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
        let edgeColor: Color = edge.edgeType == .houseEdge
            ? OPSStyle.Colors.secondaryText
            : Color.white

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
        guard let startVertex = viewModel.drawingData.vertex(byId: fromVertexId) else { return }

        var path = Path()
        path.move(to: startVertex.position)
        path.addLine(to: currentEnd)

        context.stroke(
            path,
            with: .color(OPSStyle.Colors.primaryAccent),
            style: StrokeStyle(lineWidth: 2.0, dash: [8, 4])
        )

        // Live dimension label
        let distance = SnapEngine.distance(startVertex.position, currentEnd)
        if let scale = viewModel.drawingData.scaleFactor, scale > 0 {
            let inches = distance / scale
            let label = DimensionEngine.format(inches, system: viewModel.drawingData.config.measurementSystem)
            let midX = (startVertex.position.x + currentEnd.x) / 2
            let midY = (startVertex.position.y + currentEnd.y) / 2

            context.draw(
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryAccent),
                at: CGPoint(x: midX, y: midY - 16)
            )
        }
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryAccent),
                at: CGPoint(x: vertex.position.x, y: vertex.position.y + radius + 12)
            )
        }
    }

    // MARK: - Dimension Labels

    private func drawDimensionLabel(context: GraphicsContext, edge: DeckEdge) {
        guard let dim = edge.dimension,
              let start = viewModel.drawingData.vertex(byId: edge.startVertexId),
              let end = viewModel.drawingData.vertex(byId: edge.endVertexId) else { return }

        let midX = (start.position.x + end.position.x) / 2
        let midY = (start.position.y + end.position.y) / 2
        let label = DimensionEngine.format(dim, system: viewModel.drawingData.config.measurementSystem)

        // Background pill
        let textSize = label.count * 8 + 16
        let pillRect = CGRect(
            x: midX - CGFloat(textSize) / 2,
            y: midY - 24,
            width: CGFloat(textSize),
            height: 20
        )
        context.fill(
            Path(roundedRect: pillRect, cornerRadius: 4),
            with: .color(OPSStyle.Colors.cardBackground.opacity(0.9))
        )

        context.draw(
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.primaryAccent),
            at: CGPoint(x: midX, y: midY - 14)
        )

        // Source badge
        if edge.dimensionSource == .ar {
            context.draw(
                Text("AR")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(OPSStyle.Colors.warningStatus),
                at: CGPoint(x: midX + CGFloat(textSize) / 2 + 10, y: midY - 14)
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
            HStack(spacing: 16) {
                Label(
                    DimensionEngine.formatArea(area, system: viewModel.drawingData.config.measurementSystem),
                    systemImage: "square.dashed"
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.primaryAccent)

                if let perimeter = viewModel.totalPerimeter {
                    Label(
                        DimensionEngine.format(perimeter, system: viewModel.drawingData.config.measurementSystem),
                        systemImage: "ruler"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(OPSStyle.Colors.cardBackground.opacity(0.9))
            .cornerRadius(OPSStyle.Layout.cornerRadius)

            Spacer()
        }
        .padding(.top, 8)
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
                viewModel.handleTap(at: point)
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
                    viewModel.handleLongPress(at: point)
                default:
                    break
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                canvasScale = max(0.3, min(5.0, baseScale * scale))
            }
            .onEnded { scale in
                baseScale = max(0.3, min(5.0, baseScale * scale))
                canvasScale = baseScale
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard viewModel.activeTool == .none || viewModel.activeTool == .select else { return }
                canvasOffset = CGSize(
                    width: lastDragValue.width + value.translation.width,
                    height: lastDragValue.height + value.translation.height
                )
            }
            .onEnded { value in
                lastDragValue = canvasOffset
            }
    }
}
