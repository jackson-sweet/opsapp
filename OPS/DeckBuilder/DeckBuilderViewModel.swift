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

    // MARK: - Estimate & Share

    @Published var showingEstimatePreview: Bool = false
    @Published var showingShareOptions: Bool = false
    @Published var estimateCreated: Bool = false
    @Published var createdEstimateNumber: String?
    @Published var createdEstimateId: String?
    @Published var isGeneratingEstimate: Bool = false
    @Published var shareImage: UIImage?
    @Published var sharePDFData: Data?
    @Published var showingShareSheet: Bool = false

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
        if let vertexId = PolygonMath.findVertexAtPoint(point, vertices: drawingData.vertices) {
            selection.clear()
            selection.toggleVertex(vertexId)
            editingVertexId = vertexId
            hapticLight()
            return
        }

        // Check edge
        if let edgeId = PolygonMath.findEdgeAtPoint(point, edges: drawingData.edges, vertices: drawingData.vertices) {
            selection.clear()
            selection.toggleEdge(edgeId)
            editingEdgeId = edgeId
            hapticLight()

            // Apply buffered laser measurement if available
            applyBufferedMeasurementIfNeeded(toEdge: edgeId)
            return
        }

        // Check area
        if drawingData.isClosed && PolygonMath.pointInPolygon(point, vertices: drawingData.orderedPositions) {
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
        for vertex in drawingData.vertices {
            if PolygonMath.pointInPolygon(vertex.position, vertices: points) {
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
        // Manual or laser override clears AR accuracy badge
        if source == .manual || source == .laser {
            edge.accuracyPercent = nil
        }
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
        hapticMedium()
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
        hapticMedium()
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
        drawingData.edges.contains(where: { $0.dimension != nil })
    }

    func generateEstimate() async {
        guard !isGeneratingEstimate else { return }
        isGeneratingEstimate = true
        defer { isGeneratingEstimate = false }

        let lineItems = EstimateGeneratorService.generateLineItems(from: drawingData)
        guard !lineItems.isEmpty else { return }

        let repo = EstimateRepository(companyId: deckDesign.companyId)

        // Build estimate title
        let title = "Deck Estimate \u{2014} \(deckDesign.title)"

        // AR accuracy note for internal notes
        let arNote = EstimateGeneratorService.arAccuracyNote(from: drawingData)

        let dto = CreateEstimateDTO(
            companyId: deckDesign.companyId,
            projectId: deckDesign.projectId,
            clientId: nil,
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
                    type: item.type.rawValue
                )
                _ = try await repo.addLineItem(lineDTO)
            }

            createdEstimateNumber = created.estimateNumber
            createdEstimateId = created.id
            estimateCreated = true
            hapticSuccess()

            // Auto-dismiss success toast after 5 seconds
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                estimateCreated = false
            }
        } catch {
            print("[DeckBuilder] Failed to create estimate: \(error)")
        }
    }

    func prepareShareImage() async {
        guard let image = DeckShareRenderer.renderShareImage(
            drawingData: drawingData,
            title: deckDesign.title,
            clientName: nil
        ) else { return }
        shareImage = image
        showingShareSheet = true
    }

    func prepareSharePDF() async {
        guard let data = DeckShareRenderer.renderPDF(
            drawingData: drawingData,
            title: deckDesign.title,
            clientName: nil,
            companyName: nil
        ) else { return }
        sharePDFData = data
        showingShareSheet = true
    }

    func materialSummaryText() -> String {
        EstimateGeneratorService.materialSummary(from: drawingData)
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
