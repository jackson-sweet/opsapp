// OPS/OPS/DeckBuilder/DeckBuilderViewModel.swift

import Foundation
import SwiftUI
import SwiftData

@MainActor
class DeckBuilderViewModel: ObservableObject {

    // MARK: - Dependencies

    let deckDesign: DeckDesign
    private var modelContext: ModelContext?

    // MARK: - Drawing State

    @Published var drawingData: DeckDrawingData
    @Published var drawingMode: DrawingMode = .idle
    @Published var activeTool: DrawingTool = .draw
    @Published var selection: SelectionState = SelectionState()

    // MARK: - UI State

    @Published var showingDimensionInput: Bool = false
    @Published var showingPropertySheet: Bool = false
    @Published var showingElevationInput: Bool = false
    @Published var showingStairConfig: Bool = false
    @Published var showingAssignmentWheel: Bool = false
    @Published var editingEdgeId: String?
    @Published var editingVertexId: String?

    // MARK: - Assignment Wheel

    @Published var activeAssignment: AssignedItem?

    // MARK: - Undo/Redo

    private var undoStack: [DrawingSnapshot] = []
    private var redoStack: [DrawingSnapshot] = []
    private let maxUndoDepth = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Computed

    var isClosed: Bool { drawingData.isClosed }

    var totalArea: Double? {
        guard isClosed, let scale = drawingData.scaleFactor, scale > 0 else { return nil }
        return PolygonMath.realWorldArea(
            vertices: drawingData.orderedPositions,
            scaleFactor: scale
        )
    }

    var totalPerimeter: Double? {
        guard drawingData.edges.count > 0, let scale = drawingData.scaleFactor, scale > 0 else { return nil }
        return PolygonMath.perimeter(vertices: drawingData.orderedPositions) / scale
    }

    // MARK: - Init

    init(deckDesign: DeckDesign, modelContext: ModelContext? = nil) {
        self.deckDesign = deckDesign
        self.modelContext = modelContext
        self.drawingData = deckDesign.drawingData
    }

    // MARK: - Undo/Redo

    private func pushUndo(_ description: String) {
        undoStack.append(DrawingSnapshot(drawingData: drawingData, description: description))
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(DrawingSnapshot(drawingData: drawingData, description: "redo"))
        drawingData = snapshot.drawingData
        save()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(DrawingSnapshot(drawingData: drawingData, description: "undo"))
        drawingData = snapshot.drawingData
        save()
    }

    // MARK: - Drawing Operations

    func beginLine(from position: CGPoint) {
        let snappedPosition: CGPoint
        let existingVertexId: String?

        // Check if near an existing vertex (magnetic snap)
        if let snapId = SnapEngine.findSnapTarget(
            point: position,
            vertices: drawingData.vertices,
            snapRadius: drawingData.config.endpointSnapRadius
        ) {
            existingVertexId = snapId
            snappedPosition = drawingData.vertex(byId: snapId)?.position ?? position
        } else {
            existingVertexId = nil
            snappedPosition = position
        }

        let vertexId: String
        if let existing = existingVertexId {
            vertexId = existing
        } else {
            let vertex = DeckVertex(position: snappedPosition)
            vertexId = vertex.id
            pushUndo("begin line")
            drawingData.vertices.append(vertex)
        }

        drawingMode = .drawing(fromVertexId: vertexId, currentEnd: snappedPosition)
    }

    func updateLine(to rawEnd: CGPoint) {
        guard case .drawing(let fromId, _) = drawingMode else { return }
        guard let startVertex = drawingData.vertex(byId: fromId) else { return }

        let snapped = SnapEngine.snapEndpoint(
            from: startVertex.position,
            rawEnd: rawEnd,
            angleIncrement: drawingData.config.angleSnapIncrement,
            lengthIncrement: lengthSnapInCanvasPoints(),
            snappingEnabled: drawingData.config.snappingEnabled
        )

        drawingMode = .drawing(fromVertexId: fromId, currentEnd: snapped)
    }

    func endLine(at rawEnd: CGPoint) {
        guard case .drawing(let fromId, _) = drawingMode else { return }
        guard drawingData.vertex(byId: fromId) != nil else {
            drawingMode = .idle
            return
        }

        let startVertex = drawingData.vertex(byId: fromId)!
        let snapped = SnapEngine.snapEndpoint(
            from: startVertex.position,
            rawEnd: rawEnd,
            angleIncrement: drawingData.config.angleSnapIncrement,
            lengthIncrement: lengthSnapInCanvasPoints(),
            snappingEnabled: drawingData.config.snappingEnabled
        )

        // Check if snapping to an existing vertex (especially the first one for closing)
        let endVertexId: String
        if let snapId = SnapEngine.findSnapTarget(
            point: snapped,
            vertices: drawingData.vertices,
            snapRadius: drawingData.config.endpointSnapRadius,
            excludeVertexIds: [fromId]
        ) {
            endVertexId = snapId
        } else {
            let newVertex = DeckVertex(position: snapped)
            endVertexId = newVertex.id
            drawingData.vertices.append(newVertex)
        }

        // Create the edge
        var edge = DeckEdge(startVertexId: fromId, endVertexId: endVertexId)

        // Apply active assignment if set
        if let assignment = activeAssignment,
           assignment.unitType == .linearFoot || assignment.unitType == .linearMeter {
            edge.assignedItems.append(assignment)
        }

        pushUndo("draw line")
        drawingData.edges.append(edge)

        // Check if we closed the polygon
        if drawingData.isClosed {
            drawingData.footprint.isClosed = true
        }

        drawingMode = .idle
        save()
    }

    // MARK: - Selection

    func handleTap(at point: CGPoint) {
        // Check vertex first (higher priority, larger hit area)
        if let vertexId = PolygonMath.findVertexAtPoint(point, vertices: drawingData.vertices) {
            selection.clear()
            selection.toggleVertex(vertexId)
            editingVertexId = vertexId
            return
        }

        // Check edge
        if let edgeId = PolygonMath.findEdgeAtPoint(point, edges: drawingData.edges, vertices: drawingData.vertices) {
            selection.clear()
            selection.toggleEdge(edgeId)
            editingEdgeId = edgeId
            return
        }

        // Check area
        if drawingData.isClosed && PolygonMath.pointInPolygon(point, vertices: drawingData.orderedPositions) {
            selection.clear()
            selection.selectedFootprint = true
            return
        }

        // Tap on empty space — clear selection
        selection.clear()
        editingEdgeId = nil
        editingVertexId = nil
    }

    func handleLongPress(at point: CGPoint) {
        // Same hit detection as tap, but always shows property sheet
        handleTap(at: point)
        if !selection.isEmpty {
            showingPropertySheet = true
        }
    }

    // MARK: - Marquee Selection

    func beginMarquee(at point: CGPoint) {
        drawingMode = .selecting(rect: CGRect(origin: point, size: .zero))
    }

    func updateMarquee(to point: CGPoint) {
        guard case .selecting(let rect) = drawingMode else { return }
        let newRect = CGRect(
            x: min(rect.origin.x, point.x),
            y: min(rect.origin.y, point.y),
            width: abs(point.x - rect.origin.x),
            height: abs(point.y - rect.origin.y)
        )
        drawingMode = .selecting(rect: newRect)
    }

    func endMarquee() {
        guard case .selecting(let rect) = drawingMode else { return }
        selection.clear()

        // Select all vertices inside the rectangle
        for vertex in drawingData.vertices {
            if rect.contains(vertex.position) {
                selection.selectedVertexIds.insert(vertex.id)
            }
        }

        // Select all edges where both endpoints are inside
        for edge in drawingData.edges {
            if selection.selectedVertexIds.contains(edge.startVertexId) &&
               selection.selectedVertexIds.contains(edge.endVertexId) {
                selection.selectedEdgeIds.insert(edge.id)
            }
        }

        drawingMode = .idle
    }

    // MARK: - Vertex Drag (2D canvas only)

    func beginVertexDrag(_ vertexId: String) {
        pushUndo("move vertex")
        drawingMode = .draggingVertex(vertexId: vertexId)
    }

    func updateVertexDrag(to position: CGPoint) {
        guard case .draggingVertex(let vertexId) = drawingMode else { return }
        var vertex = drawingData.vertex(byId: vertexId) ?? DeckVertex(position: position)
        vertex.position = position
        drawingData.updateVertex(vertex)
    }

    func endVertexDrag() {
        drawingMode = .idle
        save()
    }

    // MARK: - Dimension Entry

    func setEdgeDimension(_ edgeId: String, inches: Double, source: DimensionSource = .manual) {
        guard var edge = drawingData.edge(byId: edgeId) else { return }
        pushUndo("set dimension")
        edge.dimension = inches
        edge.dimensionSource = source
        drawingData.updateEdge(edge)

        // If this is the first manual dimension on a closed shape, offer scale auto-fill
        if drawingData.isClosed && drawingData.scaleFactor == nil {
            if let start = drawingData.vertex(byId: edge.startVertexId),
               let end = drawingData.vertex(byId: edge.endVertexId) {
                let canvasLength = SnapEngine.distance(start.position, end.position)
                if let scale = DimensionEngine.calculateScaleFactor(canvasLength: canvasLength, realWorldInches: inches) {
                    drawingData.scaleFactor = scale
                }
            }
        }
        save()
    }

    // MARK: - Edge Properties

    func setEdgeType(_ edgeId: String, type: EdgeType) {
        guard var edge = drawingData.edge(byId: edgeId) else { return }
        pushUndo("set edge type")
        edge.edgeType = type
        drawingData.updateEdge(edge)
        save()
    }

    func setRailing(_ edgeId: String, config: RailingConfig?) {
        guard var edge = drawingData.edge(byId: edgeId) else { return }
        pushUndo("set railing")
        edge.railingConfig = config
        drawingData.updateEdge(edge)
        save()
    }

    func setStairs(_ edgeId: String, config: StairConfig?) {
        guard var edge = drawingData.edge(byId: edgeId) else { return }
        pushUndo("set stairs")
        edge.stairConfig = config
        drawingData.updateEdge(edge)
        save()
    }

    // MARK: - Vertex Properties

    func setVertexElevation(_ vertexId: String, elevation: Double, source: ElevationSource = .manual) {
        guard var vertex = drawingData.vertex(byId: vertexId) else { return }
        pushUndo("set elevation")
        vertex.elevation = elevation
        vertex.elevationSource = source
        drawingData.updateVertex(vertex)
        save()
    }

    func setOverallElevation(_ elevation: Double) {
        pushUndo("set overall elevation")
        drawingData.overallElevation = elevation
        save()
    }

    // MARK: - Footprint Properties

    func assignItemToFootprint(_ item: AssignedItem) {
        pushUndo("assign footprint item")
        drawingData.footprint.assignedItems.append(item)
        save()
    }

    func removeFootprintItem(_ itemId: String) {
        pushUndo("remove footprint item")
        drawingData.footprint.assignedItems.removeAll { $0.id == itemId }
        save()
    }

    // MARK: - Edge Item Assignment

    func assignItemToEdge(_ edgeId: String, item: AssignedItem) {
        guard var edge = drawingData.edge(byId: edgeId) else { return }
        pushUndo("assign edge item")
        edge.assignedItems.append(item)
        drawingData.updateEdge(edge)
        save()
    }

    // MARK: - Batch Assignment (from wheel on selection)

    func assignItemToSelectedEdges(_ item: AssignedItem) {
        pushUndo("batch assign")
        for edgeId in selection.selectedEdgeIds {
            guard var edge = drawingData.edge(byId: edgeId) else { continue }
            // Replace existing items of same unit type
            edge.assignedItems.removeAll { $0.unitType == item.unitType }
            edge.assignedItems.append(item)
            drawingData.updateEdge(edge)
        }
        save()
    }

    // MARK: - Auto-Fill Scale

    func autoFillDimensionsFromScale() {
        guard let scale = drawingData.scaleFactor else { return }
        pushUndo("auto-fill dimensions")
        drawingData = DimensionEngine.autoFillDimensions(drawingData: drawingData, scaleFactor: scale)
        save()
    }

    // MARK: - Delete

    func deleteSelectedEdges() {
        pushUndo("delete edges")
        for edgeId in selection.selectedEdgeIds {
            drawingData.edges.removeAll { $0.id == edgeId }
        }
        // Remove orphaned vertices (vertices with no edges)
        let connectedVertexIds = Set(drawingData.edges.flatMap { [$0.startVertexId, $0.endVertexId] })
        drawingData.vertices.removeAll { !connectedVertexIds.contains($0.id) }
        drawingData.footprint.isClosed = drawingData.isClosed
        selection.clear()
        save()
    }

    func deleteSelectedVertices() {
        pushUndo("delete vertices")
        for vertexId in selection.selectedVertexIds {
            // Remove all edges connected to this vertex
            drawingData.edges.removeAll { $0.startVertexId == vertexId || $0.endVertexId == vertexId }
            drawingData.vertices.removeAll { $0.id == vertexId }
        }
        drawingData.footprint.isClosed = drawingData.isClosed
        selection.clear()
        save()
    }

    // MARK: - Persistence

    func save() {
        deckDesign.drawingData = drawingData  // triggers needsSync via setter
        try? modelContext?.save()
    }

    // MARK: - Render + Save Thumbnail

    func renderAndSave() async {
        guard let image = DeckRenderer.renderToPNG(drawingData: drawingData) else { return }

        do {
            let url = try await DeckRenderer.saveToS3(image: image, deckDesign: deckDesign)
            deckDesign.thumbnailURL = url
            save()
        } catch {
            print("[DeckBuilder] Failed to save thumbnail: \(error)")
        }
    }

    // MARK: - Helpers

    private func lengthSnapInCanvasPoints() -> Double {
        guard let scale = drawingData.scaleFactor, scale > 0 else {
            // No scale set yet — snap in raw canvas points (approximate)
            return drawingData.config.lengthSnapIncrement
        }
        return SnapEngine.inchesToCanvasPoints(drawingData.config.lengthSnapIncrement, scaleFactor: scale)
    }
}
