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
    @State private var hasInitializedOffset = false

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
                    isDrawing: false
                )
            }
            .onAppear {
                guard !hasInitializedOffset else { return }
                if geometry.size.width > 0 && geometry.size.height > 0 {
                    hasInitializedOffset = true
                    centerViewport(viewportSize: geometry.size)
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                guard !hasInitializedOffset, newSize.width > 0, newSize.height > 0 else { return }
                hasInitializedOffset = true
                centerViewport(viewportSize: newSize)
            }
        }
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)

            if drawingData.isMultiLevel {
                for (index, level) in drawingData.levels.enumerated() {
                    if index != 0 {
                        drawInactiveLevel(context: context, level: level)
                    }
                }
                for connection in drawingData.levelConnections {
                    drawLevelConnection(context: context, connection: connection)
                }
                if let firstLevel = drawingData.levels.first {
                    if firstLevel.isClosed {
                        drawLevelFootprint(context: context, level: firstLevel)
                    }
                    for edge in firstLevel.edges {
                        drawEdge(context: context, edge: edge, vertexLookup: firstLevel.vertex(byId:))
                    }
                    for vertex in firstLevel.vertices {
                        drawVertex(context: context, vertex: vertex)
                    }
                    for edge in firstLevel.edges {
                        drawDimensionLabel(context: context, edge: edge, vertexLookup: firstLevel.vertex(byId:))
                    }
                }
            } else {
                if drawingData.isClosed { drawFootprint(context: context) }
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
        let positions = drawingData.isMultiLevel
            ? (drawingData.levels.first?.vertices.map(\.position) ?? [])
            : drawingData.vertices.map(\.position)

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

        let spanX = xs.max()! - xs.min()! + 200
        let spanY = ys.max()! - ys.min()! + 200
        let fitScale = min(viewportSize.width / spanX, viewportSize.height / spanY, 2.0)

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
        guard positions.count >= 3 else { return }

        var path = Path()
        path.move(to: positions[0])
        for i in 1..<positions.count {
            path.addLine(to: positions[i])
        }
        path.closeSubpath()

        context.fill(path, with: .color(Color.white.opacity(0.04)))
        context.stroke(path, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
    }

    private func drawEdge(context: GraphicsContext, edge: DeckEdge, vertexLookup: (String) -> DeckVertex?) {
        guard let start = vertexLookup(edge.startVertexId),
              let end = vertexLookup(edge.endVertexId) else { return }

        let lineColor: Color
        let lineWidth: CGFloat

        switch edge.edgeType {
        case .houseEdge:
            lineColor = Color.white.opacity(0.5)
            lineWidth = 2.5
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

        // Stair indicator
        if edge.stairConfig != nil {
            let midX = (start.position.x + end.position.x) / 2
            let midY = (start.position.y + end.position.y) / 2
            let stairIcon = Path(ellipseIn: CGRect(x: midX - 6, y: midY - 6, width: 12, height: 12))
            context.fill(stairIcon, with: .color(OPSStyle.Colors.warningStatus.opacity(0.3)))
            context.stroke(stairIcon, with: .color(OPSStyle.Colors.warningStatus), lineWidth: 1)
        }
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
        let positions = level.orderedPositions
        guard positions.count >= 3 else { return }

        var path = Path()
        path.move(to: positions[0])
        for i in 1..<positions.count { path.addLine(to: positions[i]) }
        path.closeSubpath()

        context.fill(path, with: .color(level.displayColor.swiftUIColor.opacity(0.06)))
        context.stroke(path, with: .color(level.displayColor.swiftUIColor.opacity(0.15)), lineWidth: 1)
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
}
