// OPS/OPS/DeckBuilder/DeckBuilderViewModel.swift

import Foundation
import SwiftUI
import SwiftData
import Supabase
import UIKit
import Combine

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

    // MARK: - 3D Mode

    @Published var is3DMode: Bool = false

    var can3DMode: Bool {
        if isMultiLevel {
            return drawingData.levels.contains { $0.isClosed && $0.vertices.count >= 3 }
        }
        return drawingData.vertices.count >= 3 && drawingData.isClosed
    }

    // MARK: - Photo Overlay

    @Published var showingPhotoSourcePicker: Bool = false
    @Published var showingPhotoOverlayEditor: Bool = false
    @Published var selectedSitePhoto: UIImage?

    // MARK: - Estimate & Share

    @Published var showingEstimatePreview: Bool = false
    @Published var showingShareOptions: Bool = false
    @Published var estimateCreated: Bool = false
    @Published var createdEstimateNumber: String?
    @Published var createdEstimateId: String?
    @Published var isGeneratingEstimate: Bool = false
    @Published var showingDuplicateAlert: Bool = false
    @Published var existingEstimate: Estimate?
    @Published var createdEstimate: Estimate?
    @Published var shareImage: UIImage?
    @Published var sharePDFData: Data?
    @Published var showingShareSheet: Bool = false
    @Published var shareIncludesMaterialList: Bool = false

    // MARK: - Assignment Wheel

    @Published var activeAssignment: AssignedItem?

    // MARK: - Laser Meter

    @Published var isLaserConnected: Bool = false
    @Published var bufferedMeasurement: LaserMeasurement?
    @Published var showMeasurementToast: Bool = false
    @Published var measurementToastText: String = ""
    @Published var showLaserErrorToast: Bool = false
    @Published var laserErrorText: String = ""
    @Published var showDisconnectToast: Bool = false
    @Published var disconnectToastText: String = ""
    private var laserCancellables = Set<AnyCancellable>()
    private var bufferTimer: Timer?
    private var errorTimer: Timer?
    private var disconnectTimer: Timer?

    // MARK: - Multi-Level State

    @Published var activeLevelIndex: Int = 0
    @Published var showingLevelConnectionSheet: Bool = false

    // MARK: - Multi-Level Computed

    var activeLevel: DeckLevel? {
        guard drawingData.isMultiLevel, activeLevelIndex < drawingData.levels.count else { return nil }
        return drawingData.levels[activeLevelIndex]
    }

    var isMultiLevel: Bool { drawingData.isMultiLevel }
    var levelCount: Int { drawingData.levels.count }
    var canAddLevel: Bool { !drawingData.isMultiLevel || drawingData.levels.count < 3 }
    var canConnectLevels: Bool {
        drawingData.levels.count >= 2 &&
        drawingData.levels.filter({ $0.isClosed }).count >= 2 &&
        drawingData.levels.contains(where: { $0.elevation != nil })
    }

    // MARK: - Active Level Routing

    /// Vertices for the currently active drawing context
    private var activeVertices: [DeckVertex] {
        get {
            if isMultiLevel, let level = activeLevel { return level.vertices }
            return drawingData.vertices
        }
        set {
            if isMultiLevel, activeLevelIndex < drawingData.levels.count {
                drawingData.levels[activeLevelIndex].vertices = newValue
            } else {
                drawingData.vertices = newValue
            }
        }
    }

    /// Edges for the currently active drawing context
    private var activeEdges: [DeckEdge] {
        get {
            if isMultiLevel, let level = activeLevel { return level.edges }
            return drawingData.edges
        }
        set {
            if isMultiLevel, activeLevelIndex < drawingData.levels.count {
                drawingData.levels[activeLevelIndex].edges = newValue
            } else {
                drawingData.edges = newValue
            }
        }
    }

    /// Footprint for the currently active drawing context
    private var activeFootprint: DeckFootprint {
        get {
            if isMultiLevel, let level = activeLevel { return level.footprint }
            return drawingData.footprint
        }
        set {
            if isMultiLevel, activeLevelIndex < drawingData.levels.count {
                drawingData.levels[activeLevelIndex].footprint = newValue
            } else {
                drawingData.footprint = newValue
            }
        }
    }

    /// Look up a vertex in the active context
    private func activeVertex(byId id: String) -> DeckVertex? {
        if isMultiLevel, let level = activeLevel { return level.vertex(byId: id) }
        return drawingData.vertex(byId: id)
    }

    /// Update a vertex in the active context
    private func activeUpdateVertex(_ vertex: DeckVertex) {
        if isMultiLevel, activeLevelIndex < drawingData.levels.count {
            drawingData.levels[activeLevelIndex].updateVertex(vertex)
        } else {
            drawingData.updateVertex(vertex)
        }
    }

    /// Look up an edge in the active context
    private func activeEdge(byId id: String) -> DeckEdge? {
        if isMultiLevel, let level = activeLevel { return level.edge(byId: id) }
        return drawingData.edge(byId: id)
    }

    /// Update an edge in the active context
    private func activeUpdateEdge(_ edge: DeckEdge) {
        if isMultiLevel, activeLevelIndex < drawingData.levels.count {
            drawingData.levels[activeLevelIndex].updateEdge(edge)
        } else {
            drawingData.updateEdge(edge)
        }
    }

    /// Ordered positions for the active context
    private var activeOrderedPositions: [CGPoint] {
        if isMultiLevel, let level = activeLevel { return level.orderedPositions }
        return drawingData.orderedPositions
    }

    /// Whether the active context polygon is closed
    private var activeIsClosed: Bool {
        if isMultiLevel, let level = activeLevel { return level.isClosed }
        return drawingData.isClosed
    }

    // MARK: - Undo/Redo

    private var undoStack: [DrawingSnapshot] = []
    private var redoStack: [DrawingSnapshot] = []
    private let maxUndoDepth = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Computed

    var isClosed: Bool { activeIsClosed }

    var totalArea: Double? {
        guard let scale = drawingData.scaleFactor, scale > 0 else { return nil }
        if isMultiLevel {
            let closedLevels = drawingData.levels.filter { $0.isClosed }
            guard !closedLevels.isEmpty else { return nil }
            return closedLevels.reduce(0) { total, level in
                total + PolygonMath.realWorldArea(vertices: level.orderedPositions, scaleFactor: scale)
            }
        }
        guard isClosed else { return nil }
        return PolygonMath.realWorldArea(
            vertices: drawingData.orderedPositions,
            scaleFactor: scale
        )
    }

    var totalPerimeter: Double? {
        guard let scale = drawingData.scaleFactor, scale > 0 else { return nil }
        if isMultiLevel {
            let totalPts = drawingData.levels.reduce(0.0) { total, level in
                total + PolygonMath.perimeter(vertices: level.orderedPositions)
            }
            guard totalPts > 0 else { return nil }
            return totalPts / scale
        }
        guard activeEdges.count > 0 else { return nil }
        return PolygonMath.perimeter(vertices: drawingData.orderedPositions) / scale
    }

    // MARK: - Init

    init(deckDesign: DeckDesign, modelContext: ModelContext? = nil) {
        self.deckDesign = deckDesign
        self.modelContext = modelContext
        self.drawingData = deckDesign.drawingData
        setupLaserSubscription()
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
        hapticLight()
        save()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(DrawingSnapshot(drawingData: drawingData, description: "undo"))
        drawingData = snapshot.drawingData
        hapticLight()
        save()
    }

    // MARK: - Level Management

    func addLevel() {
        if !drawingData.isMultiLevel {
            pushUndo("convert to multi-level")
            drawingData.migrateToMultiLevel()
        }
        guard drawingData.levels.count < 3 else { return }

        pushUndo("add level")
        let usedColors = drawingData.levels.map { $0.displayColor }
        let newLevel = DeckLevel(
            name: "Level \(drawingData.levels.count + 1)",
            displayColor: LevelColor.nextAvailable(excluding: usedColors),
            sortOrder: drawingData.levels.count
        )
        drawingData.levels.append(newLevel)
        activeLevelIndex = drawingData.levels.count - 1
        selection.clear()
        hapticMedium()
        save()
    }

    func deleteLevel(at index: Int) -> Bool {
        guard drawingData.isMultiLevel, index < drawingData.levels.count else { return false }
        let levelId = drawingData.levels[index].id

        // Check for connections — cannot delete level with active connections
        if drawingData.levelConnections.contains(where: { $0.upperLevelId == levelId || $0.lowerLevelId == levelId }) {
            return false
        }

        pushUndo("delete level")
        drawingData.levels.remove(at: index)

        if activeLevelIndex >= drawingData.levels.count {
            activeLevelIndex = max(0, drawingData.levels.count - 1)
        }
        selection.clear()
        hapticMedium()
        save()
        return true
    }

    func renameLevel(at index: Int, to name: String) {
        guard index < drawingData.levels.count else { return }
        drawingData.levels[index].name = name
        save()
    }

    func switchToLevel(_ index: Int) {
        guard index < drawingData.levels.count else { return }
        activeLevelIndex = index
        selection.clear()
        editingEdgeId = nil
        editingVertexId = nil
        hapticLight()
    }

    func setLevelElevation(at index: Int, elevation: Double) {
        guard index < drawingData.levels.count else { return }
        pushUndo("set level elevation")
        drawingData.levels[index].elevation = elevation

        // Auto-recalculate any connections involving this level
        let levelId = drawingData.levels[index].id
        for i in drawingData.levelConnections.indices {
            let conn = drawingData.levelConnections[i]
            if conn.upperLevelId == levelId || conn.lowerLevelId == levelId {
                if let diff = drawingData.elevationDifference(upperLevelId: conn.upperLevelId, lowerLevelId: conn.lowerLevelId) {
                    drawingData.levelConnections[i].stairConfig.treadCount = StairConfig.calculateTreadCount(totalRise: diff)
                }
            }
        }
        save()
    }

    func connectLevels(upperLevelId: String, lowerLevelId: String, upperEdgeId: String, stairWidth: Double) {
        guard let diff = drawingData.elevationDifference(upperLevelId: upperLevelId, lowerLevelId: lowerLevelId) else { return }

        pushUndo("connect levels")
        let treadCount = StairConfig.calculateTreadCount(totalRise: diff)
        let stairConfig = StairConfig(
            width: stairWidth,
            treadCount: treadCount
        )
        let connection = LevelConnection(
            upperLevelId: upperLevelId,
            lowerLevelId: lowerLevelId,
            upperEdgeId: upperEdgeId,
            stairConfig: stairConfig
        )
        drawingData.levelConnections.append(connection)
        hapticSuccess()
        save()
    }

    func removeConnection(_ connectionId: String) {
        pushUndo("remove connection")
        drawingData.levelConnections.removeAll { $0.id == connectionId }
        hapticMedium()
        save()
    }

    // MARK: - Drawing Operations

    func beginLine(from position: CGPoint) {
        let snappedPosition: CGPoint
        let existingVertexId: String?

        // Check if near an existing vertex (magnetic snap)
        if let snapId = SnapEngine.findSnapTarget(
            point: position,
            vertices: activeVertices,
            snapRadius: drawingData.config.endpointSnapRadius
        ) {
            existingVertexId = snapId
            snappedPosition = activeVertex(byId: snapId)?.position ?? position
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
            activeVertices.append(vertex)
        }

        drawingMode = .drawing(fromVertexId: vertexId, currentEnd: snappedPosition)
    }

    func updateLine(to rawEnd: CGPoint) {
        guard case .drawing(let fromId, _) = drawingMode else { return }
        guard let startVertex = activeVertex(byId: fromId) else { return }

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
        guard activeVertex(byId: fromId) != nil else {
            drawingMode = .idle
            return
        }

        let startVertex = activeVertex(byId: fromId)!
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
            vertices: activeVertices,
            snapRadius: drawingData.config.endpointSnapRadius,
            excludeVertexIds: [fromId]
        ) {
            endVertexId = snapId
        } else {
            let newVertex = DeckVertex(position: snapped)
            endVertexId = newVertex.id
            activeVertices.append(newVertex)
        }

        // Create the edge
        var edge = DeckEdge(startVertexId: fromId, endVertexId: endVertexId)

        // Apply active assignment if set
        if let assignment = activeAssignment,
           assignment.unitType == .linearFoot || assignment.unitType == .linearMeter {
            edge.assignedItems.append(assignment)
        }

        pushUndo("draw line")
        activeEdges.append(edge)

        // Check if we closed the polygon
        if activeIsClosed {
            activeFootprint.isClosed = true
            hapticSuccess() // polygon closed — key moment
        } else {
            hapticMedium() // line committed
        }

        drawingMode = .idle
        save()
    }

    // MARK: - Selection

    func handleTap(at point: CGPoint) {
        // Check vertex first (higher priority, larger hit area)
        if let vertexId = PolygonMath.findVertexAtPoint(point, vertices: activeVertices) {
            selection.clear()
            selection.toggleVertex(vertexId)
            editingVertexId = vertexId
            hapticLight()
            return
        }

        // Check edge
        if let edgeId = PolygonMath.findEdgeAtPoint(point, edges: activeEdges, vertices: activeVertices) {
            selection.clear()
            selection.toggleEdge(edgeId)
            editingEdgeId = edgeId
            hapticLight()

            // Apply buffered laser measurement if available
            applyBufferedMeasurementIfNeeded(toEdge: edgeId)
            return
        }

        // Check area
        if activeIsClosed && PolygonMath.pointInPolygon(point, vertices: activeOrderedPositions) {
            selection.clear()
            selection.selectedFootprint = true
            hapticLight()
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
            hapticMedium()
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
        for vertex in activeVertices {
            if rect.contains(vertex.position) {
                selection.selectedVertexIds.insert(vertex.id)
            }
        }

        // Select all edges where both endpoints are inside
        for edge in activeEdges {
            if selection.selectedVertexIds.contains(edge.startVertexId) &&
               selection.selectedVertexIds.contains(edge.endVertexId) {
                selection.selectedEdgeIds.insert(edge.id)
            }
        }

        drawingMode = .idle
    }

    // MARK: - Lasso Selection

    func beginLasso(at point: CGPoint) {
        drawingMode = .lassoing(points: [point])
    }

    func updateLasso(to point: CGPoint) {
        guard case .lassoing(var points) = drawingMode else { return }
        points.append(point)
        drawingMode = .lassoing(points: points)
    }

    func endLasso() {
        guard case .lassoing(let points) = drawingMode else { return }
        guard points.count >= 3 else {
            drawingMode = .idle
            return
        }
        selection.clear()

        // Select all vertices inside the lasso polygon
        for vertex in activeVertices {
            if PolygonMath.pointInPolygon(vertex.position, vertices: points) {
                selection.selectedVertexIds.insert(vertex.id)
            }
        }

        // Select all edges where both endpoints are inside
        for edge in activeEdges {
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
        var vertex = activeVertex(byId: vertexId) ?? DeckVertex(position: position)
        vertex.position = position
        activeUpdateVertex(vertex)
    }

    func endVertexDrag() {
        drawingMode = .idle
        save()
    }

    // MARK: - Dimension Entry

    func setEdgeDimension(_ edgeId: String, inches: Double, source: DimensionSource = .manual) {
        guard var edge = activeEdge(byId: edgeId) else { return }
        pushUndo("set dimension")
        edge.dimension = inches
        edge.dimensionSource = source
        // Manual or laser override clears AR accuracy badge
        if source == .manual || source == .laser {
            edge.accuracyPercent = nil
        }
        activeUpdateEdge(edge)

        // If this is the first manual dimension on a closed shape, offer scale auto-fill
        if activeIsClosed && drawingData.scaleFactor == nil {
            if let start = activeVertex(byId: edge.startVertexId),
               let end = activeVertex(byId: edge.endVertexId) {
                let canvasLength = SnapEngine.distance(start.position, end.position)
                if let scale = DimensionEngine.calculateScaleFactor(canvasLength: canvasLength, realWorldInches: inches) {
                    drawingData.scaleFactor = scale
                }
            }
        }
        hapticMedium()
        save()
    }

    // MARK: - Edge Properties

    func setEdgeType(_ edgeId: String, type: EdgeType) {
        guard var edge = activeEdge(byId: edgeId) else { return }
        pushUndo("set edge type")
        edge.edgeType = type
        activeUpdateEdge(edge)
        save()
    }

    func setRailing(_ edgeId: String, config: RailingConfig?) {
        guard var edge = activeEdge(byId: edgeId) else { return }
        pushUndo("set railing")
        edge.railingConfig = config
        activeUpdateEdge(edge)
        save()
    }

    func setStairs(_ edgeId: String, config: StairConfig?) {
        guard var edge = activeEdge(byId: edgeId) else { return }
        pushUndo("set stairs")
        edge.stairConfig = config
        activeUpdateEdge(edge)
        save()
    }

    // MARK: - Vertex Properties

    func setVertexElevation(_ vertexId: String, elevation: Double, source: ElevationSource = .manual) {
        guard var vertex = activeVertex(byId: vertexId) else { return }
        pushUndo("set elevation")
        vertex.elevation = elevation
        vertex.elevationSource = source
        activeUpdateVertex(vertex)
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
        var fp = activeFootprint
        fp.assignedItems.append(item)
        activeFootprint = fp
        save()
    }

    func removeFootprintItem(_ itemId: String) {
        pushUndo("remove footprint item")
        var fp = activeFootprint
        fp.assignedItems.removeAll { $0.id == itemId }
        activeFootprint = fp
        save()
    }

    // MARK: - Edge Item Assignment

    func assignItemToEdge(_ edgeId: String, item: AssignedItem) {
        guard var edge = activeEdge(byId: edgeId) else { return }
        pushUndo("assign edge item")
        edge.assignedItems.append(item)
        activeUpdateEdge(edge)
        save()
    }

    // MARK: - Batch Assignment (from wheel on selection)

    func assignItemToSelectedEdges(_ item: AssignedItem) {
        pushUndo("batch assign")
        for edgeId in selection.selectedEdgeIds {
            guard var edge = activeEdge(byId: edgeId) else { continue }
            // Replace existing items of same unit type
            edge.assignedItems.removeAll { $0.unitType == item.unitType }
            edge.assignedItems.append(item)
            activeUpdateEdge(edge)
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
        var edges = activeEdges
        for edgeId in selection.selectedEdgeIds {
            edges.removeAll { $0.id == edgeId }
        }
        activeEdges = edges
        // Remove orphaned vertices (vertices with no edges)
        let connectedVertexIds = Set(activeEdges.flatMap { [$0.startVertexId, $0.endVertexId] })
        var verts = activeVertices
        verts.removeAll { !connectedVertexIds.contains($0.id) }
        activeVertices = verts
        var fp = activeFootprint
        fp.isClosed = activeIsClosed
        activeFootprint = fp
        selection.clear()
        hapticMedium()
        save()
    }

    func deleteSelectedVertices() {
        pushUndo("delete vertices")
        var edges = activeEdges
        var verts = activeVertices
        for vertexId in selection.selectedVertexIds {
            // Remove all edges connected to this vertex
            edges.removeAll { $0.startVertexId == vertexId || $0.endVertexId == vertexId }
            verts.removeAll { $0.id == vertexId }
        }
        activeEdges = edges
        activeVertices = verts
        var fp = activeFootprint
        fp.isClosed = activeIsClosed
        activeFootprint = fp
        selection.clear()
        hapticMedium()
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

            // Insert project_photos row so the deck drawing appears in the project gallery
            if let projectId = deckDesign.projectId {
                try await insertProjectPhoto(
                    url: url,
                    projectId: projectId,
                    companyId: deckDesign.companyId,
                    uploadedBy: deckDesign.createdBy ?? ""
                )
            }
        } catch {
            print("[DeckBuilder] Failed to save thumbnail: \(error)")
        }
    }

    /// Insert a project_photos row for the deck design thumbnail
    private func insertProjectPhoto(url: String, projectId: String, companyId: String, uploadedBy: String) async throws {
        struct ProjectPhotoInsert: Codable {
            let project_id: String
            let company_id: String
            let url: String
            let source: String
            let uploaded_by: String
            let caption: String
            let is_client_visible: Bool
        }

        let insert = ProjectPhotoInsert(
            project_id: projectId,
            company_id: companyId,
            url: url,
            source: "deck_design",
            uploaded_by: uploadedBy,
            caption: deckDesign.title,
            is_client_visible: false
        )

        try await SupabaseService.shared.client
            .from("project_photos")
            .insert(insert)
            .execute()
    }

    // MARK: - Laser Meter Integration

    private func setupLaserSubscription() {
        let service = LaserMeterService.shared

        // Track connection state
        service.$connectionState
            .receive(on: DispatchQueue.main)
            .map { $0 == .connected }
            .sink { [weak self] connected in
                self?.isLaserConnected = connected
            }
            .store(in: &laserCancellables)

        // Subscribe to measurements
        service.$latestMeasurement
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] measurement in
                self?.handleLaserMeasurement(measurement)
            }
            .store(in: &laserCancellables)

        // Subscribe to measurement errors (Fix #2)
        service.$measurementError
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.handleLaserError(error)
            }
            .store(in: &laserCancellables)

        // Subscribe to disconnect/reconnect events (Fix #3)
        service.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleConnectionStateChange(state)
            }
            .store(in: &laserCancellables)
    }

    private func handleLaserMeasurement(_ measurement: LaserMeasurement) {
        // If a single edge is selected, apply immediately
        if selection.selectedEdgeIds.count == 1, let edgeId = selection.selectedEdgeIds.first {
            setEdgeDimension(edgeId, inches: measurement.inches, source: .laser)
            hapticLight()
            return
        }

        // No edge selected — buffer the measurement for 5 seconds
        bufferedMeasurement = measurement
        let formatted = DimensionEngine.format(measurement.inches, system: drawingData.config.measurementSystem)
        measurementToastText = "\(formatted) received — tap an edge to apply"
        showMeasurementToast = true

        bufferTimer?.invalidate()
        bufferTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.bufferedMeasurement = nil
                self?.showMeasurementToast = false
            }
        }
    }

    func applyBufferedMeasurementIfNeeded(toEdge edgeId: String) {
        if let buffered = bufferedMeasurement {
            setEdgeDimension(edgeId, inches: buffered.inches, source: .laser)
            bufferedMeasurement = nil
            showMeasurementToast = false
            bufferTimer?.invalidate()
            hapticLight()
        }
    }

    private func handleLaserError(_ error: String) {
        laserErrorText = error
        showLaserErrorToast = true

        // Clear the error on the service so it doesn't re-fire
        LaserMeterService.shared.measurementError = nil

        errorTimer?.invalidate()
        errorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showLaserErrorToast = false
            }
        }
    }

    private func handleConnectionStateChange(_ state: LaserConnectionState) {
        switch state {
        case .reconnecting:
            disconnectToastText = "Laser disconnected — reconnecting..."
            showDisconnectToast = true

            // Auto-dismiss after 10 seconds if still reconnecting
            disconnectTimer?.invalidate()
            disconnectTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, self.showDisconnectToast else { return }
                    self.disconnectToastText = "Reconnection failed"
                    // Dismiss after 2 more seconds
                    self.disconnectTimer?.invalidate()
                    self.disconnectTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            self?.showDisconnectToast = false
                        }
                    }
                }
            }

        case .connected:
            if showDisconnectToast {
                // Connection restored — brief confirmation then dismiss
                disconnectToastText = "Laser reconnected"
                disconnectTimer?.invalidate()
                disconnectTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.showDisconnectToast = false
                    }
                }
            }

        default:
            break
        }
    }

    // MARK: - Estimate & Share

    var canGenerateEstimate: Bool {
        EstimateGeneratorService.hasAssignments(drawingData) &&
        drawingData.allEdges.contains(where: { $0.dimension != nil })
    }

    /// Check if an estimate already exists for this deck design
    func checkForDuplicateEstimate() async -> Estimate? {
        guard let projectId = deckDesign.projectId else { return nil }
        let repo = EstimateRepository(companyId: deckDesign.companyId)
        do {
            let dtos = try await repo.fetchAll()
            return dtos.first(where: {
                $0.projectId == projectId &&
                ($0.title ?? "").contains("Deck Estimate")
            })?.toModel()
        } catch {
            return nil
        }
    }

    func generateEstimate() async {
        guard !isGeneratingEstimate else { return }
        isGeneratingEstimate = true
        defer { isGeneratingEstimate = false }

        let lineItems = EstimateGeneratorService.generateLineItems(from: drawingData)
        guard !lineItems.isEmpty else { return }

        let repo = EstimateRepository(companyId: deckDesign.companyId)

        // Resolve clientId and opportunityId from the linked project
        let (clientId, opportunityId) = resolveProjectContext()

        // Build estimate title
        let clientName = resolveClientName(clientId: clientId)
        let titleSuffix = clientName ?? deckDesign.title
        let title = "Deck Estimate \u{2014} \(titleSuffix)"

        // AR accuracy note for internal notes
        let arNote = EstimateGeneratorService.arAccuracyNote(from: drawingData)

        let dto = CreateEstimateDTO(
            companyId: deckDesign.companyId,
            opportunityId: opportunityId,
            projectId: deckDesign.projectId,
            clientId: clientId,
            title: title,
            notes: arNote
        )

        do {
            let created = try await repo.create(dto)

            // Add each line item
            for item in lineItems {
                let lineDTO = CreateLineItemDTO(
                    estimateId: created.id,
                    productId: item.productId,
                    name: item.name,
                    description: item.description ?? item.name,
                    quantity: item.quantity,
                    unitPrice: item.unitPrice,
                    unit: item.unit,
                    sortOrder: item.sortOrder,
                    isOptional: item.isOptional,
                    taskTypeId: nil,
                    type: item.type.rawValue,
                    category: item.category
                )
                _ = try await repo.addLineItem(lineDTO)
            }

            // Store for navigation
            createdEstimate = created.toModel()
            createdEstimateNumber = created.estimateNumber
            createdEstimateId = created.id
            estimateCreated = true
            hapticSuccess()

            // Auto-dismiss success toast after 8 seconds (field workers need more time)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                estimateCreated = false
            }
        } catch {
            print("[DeckBuilder] Failed to create estimate: \(error)")
        }
    }

    func prepareShareImage() async {
        let (clientId, _) = resolveProjectContext()
        let clientName = resolveClientName(clientId: clientId)
        let companyName = resolveCompanyName()

        guard let image = DeckShareRenderer.renderShareImage(
            drawingData: drawingData,
            title: deckDesign.title,
            clientName: clientName
        ) else { return }
        shareImage = image
        showingShareSheet = true
    }

    func prepareSharePDF() async {
        let (clientId, _) = resolveProjectContext()
        let clientName = resolveClientName(clientId: clientId)
        let companyName = resolveCompanyName()

        guard let data = DeckShareRenderer.renderPDF(
            drawingData: drawingData,
            title: deckDesign.title,
            clientName: clientName,
            companyName: companyName
        ) else { return }
        sharePDFData = data
        showingShareSheet = true
    }

    // MARK: - Context Resolution

    /// Resolve clientId and opportunityId from the linked project via SwiftData
    private func resolveProjectContext() -> (clientId: String?, opportunityId: String?) {
        guard let projectId = deckDesign.projectId, let context = modelContext else {
            return (nil, nil)
        }
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
        guard let project = try? context.fetch(descriptor).first else {
            return (nil, nil)
        }
        return (project.clientId, project.opportunityId)
    }

    /// Resolve client name from clientId via SwiftData
    private func resolveClientName(clientId: String?) -> String? {
        guard let clientId, let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
        return try? context.fetch(descriptor).first?.name
    }

    /// Resolve company name from UserDefaults
    private func resolveCompanyName() -> String? {
        UserDefaults.standard.string(forKey: "Company Name")
    }

    func materialSummaryText() -> String {
        EstimateGeneratorService.materialSummary(from: drawingData)
    }

    // MARK: - Photo Overlay

    var canShowOverlay: Bool {
        if isMultiLevel {
            return drawingData.levels.contains { $0.isClosed && $0.vertices.count >= 3 }
        }
        return drawingData.vertices.count >= 3 && drawingData.isClosed
    }

    func savePhotoOverlayState(_ state: PhotoOverlayState) {
        pushUndo("save overlay")
        drawingData.photoOverlay = state
        save()
    }

    // MARK: - Helpers

    private func lengthSnapInCanvasPoints() -> Double {
        guard let scale = drawingData.scaleFactor, scale > 0 else {
            // No scale set yet — snap in raw canvas points (approximate)
            return drawingData.config.lengthSnapIncrement
        }
        return SnapEngine.inchesToCanvasPoints(drawingData.config.lengthSnapIncrement, scaleFactor: scale)
    }

    // MARK: - Haptics

    private func hapticLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func hapticMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func hapticSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
