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
    @Published var alignmentGuides: [AlignmentGuide] = []
    @Published var tapSelectFilter: Set<SelectableElementType> = Set(SelectableElementType.allCases)

    // MARK: - UI State

    @Published var showingDimensionInput: Bool = false
    @Published var showingPropertySheet: Bool = false
    @Published var showingElevationInput: Bool = false
    @Published var showingStairConfig: Bool = false
    @Published var showingAssignmentWheel: Bool = false
    @Published var showingMaterialPicker: Bool = false
    var taskTypes: [TaskType] = []
    @Published var showingSettings: Bool = false
    @Published var showingClearConfirm: Bool = false
    @Published var isEditingTitle: Bool = false
    @Published var editingEdgeId: String?
    @Published var editingVertexId: String?

    // MARK: - 3D Mode

    @Published var is3DMode: Bool = false
    @Published var showingARVisualization: Bool = false

    var can3DMode: Bool {
        if isMultiLevel {
            return drawingData.levels.contains { $0.isClosed && $0.vertices.count >= 3 }
        }
        return drawingData.vertices.count >= 3 && drawingData.isClosed
    }

    var canViewInAR: Bool { can3DMode }

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

    // MARK: - Error State

    @Published var saveError: String?
    @Published var isLocallySaved: Bool = true
    @Published var estimateValidationError: String?
    @Published var showUndoLevelToast: Bool = false
    private var hasShownUndoLevelToast: Bool = false

    // MARK: - Assignment Wheel

    @Published var activeAssignment: AssignedItem?
    @Published var showAssignmentToast: Bool = false
    @Published var assignmentToastText: String = ""
    private var assignmentToastTimer: Timer?

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
            // Skip self-intersecting levels — their shoelace value is the signed
            // sum of cancelling regions, not a usable area. Returning nil for the
            // whole drawing forces the user to fix the geometry before they can
            // chase a number that wasn't real.
            let validLevels = drawingData.levels.filter { level in
                level.isClosed &&
                !PolygonMath.isSelfIntersecting(vertices: level.orderedPositions)
            }
            guard !validLevels.isEmpty else { return nil }
            // If at least one level is invalid we still return nil — partial sums
            // would mislead the user into thinking the deck is priceable.
            guard validLevels.count == drawingData.levels.filter({ $0.isClosed }).count else { return nil }
            return validLevels.reduce(0) { total, level in
                total + PolygonMath.realWorldArea(vertices: level.orderedPositions, scaleFactor: scale)
            }
        }
        guard isClosed else { return nil }
        let positions = drawingData.orderedPositions
        guard !PolygonMath.isSelfIntersecting(vertices: positions) else { return nil }
        return PolygonMath.realWorldArea(vertices: positions, scaleFactor: scale)
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

        // First undo in multi-level mode: show a one-time toast
        if isMultiLevel && !hasShownUndoLevelToast {
            hasShownUndoLevelToast = true
            showUndoLevelToast = true
        }

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
        drawingMode = .idle // Cancel any in-progress drawing to prevent cross-level edges
        showingPropertySheet = false
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
            // Snap new vertex to the nearest grid intersection
            snappedPosition = SnapEngine.snapToGrid(position, gridSpacing: lengthSnapInCanvasPoints())
        }

        // Snapshot BEFORE any mutations — one undo undoes the entire draw
        // (start vertex + end vertex + edge all revert together)
        pushUndo("draw line")

        let vertexId: String
        if let existing = existingVertexId {
            vertexId = existing
        } else {
            let vertex = DeckVertex(position: snappedPosition)
            vertexId = vertex.id
            activeVertices.append(vertex)
        }

        drawingMode = .drawing(fromVertexId: vertexId, currentEnd: snappedPosition)
    }

    func updateLine(to rawEnd: CGPoint) {
        guard case .drawing(let fromId, _) = drawingMode else { return }
        guard let startVertex = activeVertex(byId: fromId) else { return }

        // First apply angle/length snapping
        var snapped = SnapEngine.snapEndpoint(
            from: startVertex.position,
            rawEnd: rawEnd,
            angleIncrement: drawingData.config.angleSnapIncrement,
            lengthIncrement: lengthSnapInCanvasPoints(),
            snappingEnabled: drawingData.config.snappingEnabled
        )

        // Then detect alignment guides (axis-aligned, parallel, perpendicular)
        let alignment = SnapEngine.detectAlignmentGuides(
            from: startVertex.position,
            currentEnd: snapped,
            vertices: activeVertices,
            edges: activeEdges,
            vertexLookup: { self.activeVertex(byId: $0) },
            threshold: 8.0,
            excludeVertexIds: [fromId]
        )

        // Apply axis alignment snap (overrides angle/length snap for X or Y)
        if alignment.guides.contains(where: { $0.type == .vertical || $0.type == .horizontal }) {
            snapped = alignment.snappedPoint
        }

        alignmentGuides = alignment.guides
        drawingMode = .drawing(fromVertexId: fromId, currentEnd: snapped)
    }

    func endLine(at rawEnd: CGPoint) {
        guard case .drawing(let fromId, _) = drawingMode else { return }
        guard let startVertex = activeVertex(byId: fromId) else {
            print("[DeckBuilder] endLine: start vertex \(fromId) not found, cancelling line")
            drawingMode = .idle
            return
        }

        // No pushUndo here — snapshot was taken in beginLine() so one undo
        // reverts start vertex + end vertex + edge atomically

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
            // Snap new endpoint to nearest grid intersection
            let gridSnapped = SnapEngine.snapToGrid(snapped, gridSpacing: lengthSnapInCanvasPoints())
            let newVertex = DeckVertex(position: gridSnapped)
            endVertexId = newVertex.id
            activeVertices.append(newVertex)
        }

        // Create the edge
        var edge = DeckEdge(startVertexId: fromId, endVertexId: endVertexId)

        // Calculate and store the real-world dimension on the edge
        let endPosition = activeVertex(byId: endVertexId)?.position ?? snapped
        let canvasDistance = SnapEngine.distance(startVertex.position, endPosition)
        if canvasDistance > 0 {
            if let scale = drawingData.scaleFactor, scale > 0 {
                edge.dimension = canvasDistance / scale  // inches
            } else {
                // No scale factor — store canvas-point length so dimension label renders;
                // recalculated when scale is set via autoFillDimensionsFromScale()
                edge.dimension = canvasDistance
            }
            edge.dimensionSource = .scale  // always .scale when auto-calculated from drawing
        }

        // Apply active assignment if set
        if let assignment = activeAssignment,
           assignment.unitType == .linearFoot || assignment.unitType == .linearMeter {
            edge.assignedItems.append(assignment)
        }

        activeEdges.append(edge)

        // Check if we closed the polygon
        if activeIsClosed {
            activeFootprint.isClosed = true
            hapticSuccess() // polygon closed — key moment
        } else {
            hapticMedium() // line committed
        }

        alignmentGuides = []
        drawingMode = .idle
        save()
    }

    // MARK: - Selection

    func handleTap(at point: CGPoint, hitThreshold: Double = 25.0) {
        let additive = activeTool == .tapSelect

        if tapSelectFilter.contains(.vertex),
           let vertexId = PolygonMath.findVertexAtPoint(point, vertices: activeVertices, hitThreshold: hitThreshold) {
            if !additive { selection.clear() }
            selection.toggleVertex(vertexId)
            editingVertexId = vertexId
            hapticLight()
            return
        }

        if tapSelectFilter.contains(.edge),
           let edgeId = PolygonMath.findEdgeAtPoint(point, edges: activeEdges, vertices: activeVertices, hitThreshold: hitThreshold * 0.8) {
            if !additive { selection.clear() }
            selection.toggleEdge(edgeId)
            editingEdgeId = edgeId
            hapticLight()
            applyBufferedMeasurementIfNeeded(toEdge: edgeId)
            return
        }

        if tapSelectFilter.contains(.face),
           activeIsClosed && PolygonMath.pointInPolygon(point, vertices: activeOrderedPositions) {
            if !additive { selection.clear() }
            selection.selectedFootprint.toggle()
            hapticLight()
            return
        }

        if !additive {
            selection.clear()
            editingEdgeId = nil
            editingVertexId = nil
        }
    }

    func handleLongPress(at point: CGPoint, hitThreshold: Double = 25.0) {
        // In multi-select, long-pressing empty canvas exits the mode. Long press ON
        // a selected element still opens the property sheet — field users discovered
        // this as the natural "I'm done selecting" gesture, matching Photos/Mail.
        if activeTool == .tapSelect {
            let hitsVertex = PolygonMath.findVertexAtPoint(point, vertices: activeVertices, hitThreshold: hitThreshold) != nil
            let hitsEdge = PolygonMath.findEdgeAtPoint(point, edges: activeEdges, vertices: activeVertices, hitThreshold: hitThreshold * 0.8) != nil
            let hitsFootprint = activeIsClosed && PolygonMath.pointInPolygon(point, vertices: activeOrderedPositions)

            if !hitsVertex && !hitsEdge && !hitsFootprint {
                exitMultiSelect()
                return
            }
            // Long-pressed a selected element → open properties like any other mode
            handleTap(at: point, hitThreshold: hitThreshold)
            if !selection.isEmpty {
                hapticMedium()
                showingPropertySheet = true
            }
            return
        }

        // Same hit detection as tap, but always shows property sheet
        handleTap(at: point, hitThreshold: hitThreshold)
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
        let additive = activeTool == .tapSelect   // Multi-select mode: add, never replace
        if !additive { selection.clear() }

        // Collect vertices hit by the rectangle
        var hitVertexIds: Set<String> = []
        for vertex in activeVertices {
            if rect.contains(vertex.position) {
                hitVertexIds.insert(vertex.id)
                selection.selectedVertexIds.insert(vertex.id)
            }
        }

        // Edges fully inside (both endpoints hit). Union with existing endpoint selection
        // so additive mode picks up edges even if one endpoint was pre-selected.
        let effectiveVertexIds = selection.selectedVertexIds
        for edge in activeEdges {
            if effectiveVertexIds.contains(edge.startVertexId) &&
               effectiveVertexIds.contains(edge.endVertexId) {
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
        let additive = activeTool == .tapSelect
        if !additive { selection.clear() }

        for vertex in activeVertices {
            if PolygonMath.pointInPolygon(vertex.position, vertices: points) {
                selection.selectedVertexIds.insert(vertex.id)
            }
        }

        let effectiveVertexIds = selection.selectedVertexIds
        for edge in activeEdges {
            if effectiveVertexIds.contains(edge.startVertexId) &&
               effectiveVertexIds.contains(edge.endVertexId) {
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
        guard var vertex = activeVertex(byId: vertexId) else {
            print("[DeckBuilder] updateVertexDrag: vertex \(vertexId) not found, cancelling drag")
            drawingMode = .idle
            return
        }
        vertex.position = SnapEngine.snapToGrid(position, gridSpacing: lengthSnapInCanvasPoints())
        activeUpdateVertex(vertex)
        // Recalculate dimensions in realtime so labels update during drag
        recalculateEdgeDimensions(connectedTo: vertexId)
    }

    func endVertexDrag() {
        if case .draggingVertex(let vertexId) = drawingMode {
            // Check if dragged vertex overlaps another vertex (merge to close polygon)
            if let draggedVertex = activeVertex(byId: vertexId),
               let mergeTargetId = SnapEngine.findSnapTarget(
                   point: draggedVertex.position,
                   vertices: activeVertices,
                   snapRadius: drawingData.config.endpointSnapRadius,
                   excludeVertexIds: [vertexId]
               ) {
                // Merge: reroute all edges from dragged vertex to the target
                var rerouted = activeEdges
                for i in rerouted.indices {
                    if rerouted[i].startVertexId == vertexId {
                        rerouted[i].startVertexId = mergeTargetId
                    }
                    if rerouted[i].endVertexId == vertexId {
                        rerouted[i].endVertexId = mergeTargetId
                    }
                }

                // Drop self-loops the merge created (an edge from the dragged
                // vertex back to its own neighbour now points target→target).
                // Without this the polygon's adjacency goes 3 — `isClosed`
                // silently flips false and the deck "breaks" as the user closes it.
                rerouted.removeAll { $0.startVertexId == $0.endVertexId }

                // Dedupe edges by unordered (start, end) pair. Keep the FIRST
                // occurrence so a user's manual dimension / railing config on
                // the older edge survives the merge.
                var seen: Set<String> = []
                var deduped: [DeckEdge] = []
                for edge in rerouted {
                    let pair = [edge.startVertexId, edge.endVertexId].sorted().joined(separator: "|")
                    if seen.insert(pair).inserted {
                        deduped.append(edge)
                    }
                }
                activeEdges = deduped

                // Remove the dragged vertex (it's now merged into the target)
                activeVertices.removeAll { $0.id == vertexId }

                // Any LevelConnection that referenced an edge we just dropped
                // would otherwise point at a phantom — clean those up.
                pruneOrphanedLevelConnections()

                // Recalculate dimensions on edges now connected to the merge target
                recalculateEdgeDimensions(connectedTo: mergeTargetId)

                // Check if we closed the polygon
                if activeIsClosed {
                    activeFootprint.isClosed = true
                    hapticSuccess()
                }
            } else {
                recalculateEdgeDimensions(connectedTo: vertexId)
            }
        }
        drawingMode = .idle
        save()
    }

    /// Recalculate dimension values for edges connected to a vertex (after drag/move)
    private func recalculateEdgeDimensions(connectedTo vertexId: String) {
        for i in activeEdges.indices {
            let edge = activeEdges[i]
            guard edge.startVertexId == vertexId || edge.endVertexId == vertexId else { continue }
            // Only recalculate scale-derived dimensions; manual/laser/AR dimensions are user-set
            guard edge.dimensionSource == .scale else { continue }
            guard let start = activeVertex(byId: edge.startVertexId),
                  let end = activeVertex(byId: edge.endVertexId) else { continue }
            let canvasDistance = SnapEngine.distance(start.position, end.position)
            if let scale = drawingData.scaleFactor, scale > 0 {
                activeEdges[i].dimension = canvasDistance / scale
            } else {
                activeEdges[i].dimension = canvasDistance
            }
        }
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

        // If this is the first manual dimension on a closed shape, derive scale
        // from this edge AND back-fill every other `.scale`-source edge whose
        // stored "dimension" was actually a canvas-point length. Without the
        // back-fill those edges keep displaying canvas points labelled as inches
        // — confidently wrong on every other side of the polygon.
        if activeIsClosed && drawingData.scaleFactor == nil {
            if let start = activeVertex(byId: edge.startVertexId),
               let end = activeVertex(byId: edge.endVertexId) {
                let canvasLength = SnapEngine.distance(start.position, end.position)
                if let scale = DimensionEngine.calculateScaleFactor(canvasLength: canvasLength, realWorldInches: inches) {
                    drawingData = DimensionEngine.autoFillDimensions(
                        drawingData: drawingData,
                        scaleFactor: scale
                    )
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

    func clearOverallElevation() {
        pushUndo("clear overall elevation")
        drawingData.overallElevation = nil
        save()
    }

    // MARK: - Footprint Properties

    func assignItemToFootprint(_ item: AssignedItem) {
        pushUndo("assign footprint item")
        var fp = activeFootprint
        fp.assignedItems.append(item)
        activeFootprint = fp
        hapticLight()
        showAssignmentConfirmation("Surface: \(item.name)")
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
        hapticLight()
        showAssignmentConfirmation("\(item.name) applied to 1 edge")
        save()
    }

    // MARK: - Batch Assignment (from wheel on selection)

    func assignItemToSelectedEdges(_ item: AssignedItem) {
        let count = selection.selectedEdgeIds.count
        pushUndo("batch assign")
        for edgeId in selection.selectedEdgeIds {
            guard var edge = activeEdge(byId: edgeId) else { continue }
            // Replace existing items of same unit type
            edge.assignedItems.removeAll { $0.unitType == item.unitType }
            edge.assignedItems.append(item)
            activeUpdateEdge(edge)
        }
        hapticLight()
        showAssignmentConfirmation("\(item.name) applied to \(count) edge\(count == 1 ? "" : "s")")
        save()
    }

    // MARK: - Assignment Toast

    private func showAssignmentConfirmation(_ text: String) {
        assignmentToastTimer?.invalidate()
        assignmentToastText = text
        showAssignmentToast = true
        assignmentToastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showAssignmentToast = false
            }
        }
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
        pruneOrphanedLevelConnections()
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
        pruneOrphanedLevelConnections()
        selection.clear()
        hapticMedium()
        save()
    }

    /// Delete everything currently selected in one pass — edges, vertices, and footprint.
    /// Used by the multi-select bulk toolbar so a mixed selection can be removed with
    /// one tap instead of cycling through context bars.
    func deleteSelection() {
        guard !selection.isEmpty else { return }
        pushUndo("delete selection")

        // Edges first — this also stops us iterating edges after we've pulled their endpoints
        var edges = activeEdges
        for edgeId in selection.selectedEdgeIds {
            edges.removeAll { $0.id == edgeId }
        }

        // Selected vertices: drop them and any edges still connected to them
        var verts = activeVertices
        for vertexId in selection.selectedVertexIds {
            edges.removeAll { $0.startVertexId == vertexId || $0.endVertexId == vertexId }
            verts.removeAll { $0.id == vertexId }
        }

        // Orphan cleanup — vertices no longer referenced by any edge
        let connectedVertexIds = Set(edges.flatMap { [$0.startVertexId, $0.endVertexId] })
        verts.removeAll { !connectedVertexIds.contains($0.id) }

        activeEdges = edges
        activeVertices = verts

        var fp = activeFootprint
        if selection.selectedFootprint {
            // User asked to clear the surface assignment, not the geometry
            fp.assignedItems.removeAll()
        }
        fp.isClosed = activeIsClosed
        activeFootprint = fp

        pruneOrphanedLevelConnections()
        selection.clear()
        editingEdgeId = nil
        editingVertexId = nil
        hapticMedium()
        save()
    }

    /// Drop any LevelConnection whose referenced upper or lower edge no longer
    /// exists. Without this, deleting an edge that participated in a stair
    /// connection leaves a phantom row in `levelConnections` that ships into
    /// estimates and survives reload — invisible because the renderer guard
    /// silently early-returns when the lookup fails.
    private func pruneOrphanedLevelConnections() {
        drawingData.levelConnections.removeAll { conn in
            guard let upper = drawingData.level(byId: conn.upperLevelId),
                  upper.edge(byId: conn.upperEdgeId) != nil else { return true }
            if let lowerEdgeId = conn.lowerEdgeId {
                guard let lower = drawingData.level(byId: conn.lowerLevelId),
                      lower.edge(byId: lowerEdgeId) != nil else { return true }
            }
            return false
        }
    }

    /// Exit multi-select cleanly: drop selection, restore the primary drawing tool.
    /// Called by the long-press-to-exit gesture and by the DONE button.
    func exitMultiSelect() {
        guard activeTool == .tapSelect else { return }
        selection.clear()
        editingEdgeId = nil
        editingVertexId = nil
        activeTool = .draw
        hapticLight()
    }

    // MARK: - Persistence

    func save() {
        isLocallySaved = false
        deckDesign.drawingData = drawingData  // triggers needsSync via setter
        do {
            try modelContext?.save()
            isLocallySaved = true
        } catch {
            print("[DeckBuilder] Save failed: \(error)")
            saveError = "Save failed — check storage"
        }
    }

    func renameDesign(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        deckDesign.title = trimmed
        save()
    }

    func clearDesign() {
        pushUndo("clear design")
        drawingData = DeckDrawingData()
        selection.clear()
        editingEdgeId = nil
        editingVertexId = nil
        save()
        hapticMedium()
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

        // Validate scale factor exists before generating
        guard drawingData.scaleFactor != nil else {
            estimateValidationError = "Set at least one dimension to establish scale before generating an estimate."
            return
        }

        // Check if stairs need elevation but it's missing
        let hasStairs = drawingData.allEdges.contains { $0.stairConfig != nil }
        if hasStairs && drawingData.overallElevation == nil {
            estimateValidationError = "Set deck height — stair calculations require elevation."
            return
        }

        // Warn on self-intersecting polygon
        let positions = drawingData.allVertices.map { $0.position }
        if PolygonMath.isSelfIntersecting(vertices: positions) {
            estimateValidationError = "Deck outline appears to cross itself — adjust vertices before generating estimate."
            return
        }

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

            // Group line items by task type and create parent-child structure
            let groups = EstimateGeneratorService.groupByTaskType(lineItems, taskTypes: taskTypes)
            var sortOrder = 0

            for group in groups {
                // Create parent line item (bundled scope of work)
                let parentDTO = CreateLineItemDTO(
                    estimateId: created.id,
                    productId: nil,
                    name: group.taskTypeName,
                    description: group.taskTypeName,
                    quantity: 1,
                    unitPrice: group.parentTotal,
                    unit: nil,
                    sortOrder: sortOrder,
                    isOptional: false,
                    taskTypeId: group.taskTypeId,
                    type: group.taskTypeId != nil ? LineItemType.labor.rawValue : LineItemType.other.rawValue,
                    category: nil,
                    parentLineItemId: nil
                )
                let parentItem = try await repo.addLineItem(parentDTO)
                sortOrder += 1

                // Create child line items (material breakdown)
                for child in group.children {
                    let childDTO = CreateLineItemDTO(
                        estimateId: created.id,
                        productId: child.productId,
                        name: child.name,
                        description: child.description ?? child.name,
                        quantity: child.quantity,
                        unitPrice: child.unitPrice,
                        unit: child.unit,
                        sortOrder: sortOrder,
                        isOptional: child.isOptional,
                        taskTypeId: group.taskTypeId,
                        type: LineItemType.material.rawValue,
                        category: child.category,
                        parentLineItemId: parentItem.id
                    )
                    _ = try await repo.addLineItem(childDTO)
                    sortOrder += 1
                }
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
        // Always resolve snap against a real scale factor. Pre-scale drawings use a
        // known fallback (2 pt/inch → 24 pt per foot) so the snap increment displayed
        // in settings corresponds to the actual snap distance on screen. Previously the
        // pre-scale fallback was a fixed 20 pt, which coincidentally read as 10 inches
        // once scale was set, and as varying weird increments once zoomed — the source
        // of "1'8" snap" reports from the field.
        let scale: Double
        if let s = drawingData.scaleFactor, s > 0 {
            scale = s
        } else {
            scale = Self.prescaleFallbackScale
        }
        return SnapEngine.inchesToCanvasPoints(drawingData.config.lengthSnapIncrement, scaleFactor: scale)
    }

    /// Canvas points per real-world inch used BEFORE the user sets a scale. Picking a
    /// fixed value here guarantees the configured snap increment (default 6") is
    /// honored from the first stroke instead of reading as an arbitrary pixel grid.
    /// 2 pt/in → 24 pt per foot, 12 pt per 6" — readable at default zoom, matches
    /// the visible grid density in DeckCanvasView.
    static let prescaleFallbackScale: Double = 2.0

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
