import Combine
import CoreGraphics
import Foundation

public struct DeckEditorLinePreview: Equatable {
    public let start: CGPoint
    public let end: CGPoint
    public let dimensionLabel: String

    public init(start: CGPoint, end: CGPoint, dimensionLabel: String) {
        self.start = start
        self.end = end
        self.dimensionLabel = dimensionLabel
    }
}

@MainActor
public final class DeckDrawingEditorModel: ObservableObject {
    @Published public private(set) var drawingData: DeckDrawingData
    @Published public private(set) var activeLine: DeckEditorLinePreview?
    @Published public private(set) var alignmentGuides: [AlignmentGuide] = []
    @Published public private(set) var selectedLoadPreset: LoadPreset
    @Published public private(set) var codeCheckSettings: DeckCodeCheckSettings
    @Published public private(set) var codeReport: DeckCodeReport?

    public let capabilities: DeckCapabilities
    public let codeProfile: DeckCodeProfile?

    private let onPersist: (DeckDrawingData) -> Void
    private var activeLineStartVertexId: String?
    private var activeLineStartPosition: CGPoint?

    public init(
        drawingData: DeckDrawingData,
        capabilities: DeckCapabilities,
        codeProfile: DeckCodeProfile? = nil,
        onPersist: @escaping (DeckDrawingData) -> Void = { _ in }
    ) {
        let loaded = DeckSchemaMigration.stampFramingVersion(drawingData)
        self.drawingData = loaded
        self.capabilities = capabilities
        self.codeProfile = codeProfile
        self.selectedLoadPreset = loaded.framing?.loadPreset ?? LoadPreset()
        self.codeCheckSettings = capabilities.contains(.codeCompliance) && codeProfile != nil ? .enabled : .disabled
        self.onPersist = onPersist
        reconcileSurfaces()
        refreshCodeReport()
    }

    public func replaceDrawingData(_ data: DeckDrawingData, persist: Bool = false) {
        drawingData = DeckSchemaMigration.stampFramingVersion(data)
        selectedLoadPreset = drawingData.framing?.loadPreset ?? selectedLoadPreset
        clearActiveLine()
        reconcileSurfaces()
        refreshCodeReport()
        if persist {
            persistDrawingData()
        }
    }

    public var canRunCodeChecks: Bool {
        capabilities.contains(.codeCompliance) && codeProfile != nil
    }

    public var canEditHouseOpenings: Bool {
        capabilities.contains(.houseOpenings)
    }

    public var visibleCodeFindings: [DeckCodeFinding] {
        guard codeCheckSettings == .enabled else { return [] }
        return codeReport?.findings ?? []
    }

    public func setCodeChecksEnabled(_ isEnabled: Bool) {
        codeCheckSettings = isEnabled && canRunCodeChecks ? .enabled : .disabled
        refreshCodeReport()
    }

    public func beginLine(at rawPoint: CGPoint) {
        let resolved = resolvedPoint(rawPoint)
        activeLineStartVertexId = resolved.vertexId
        activeLineStartPosition = resolved.point
        activeLine = DeckEditorLinePreview(
            start: resolved.point,
            end: resolved.point,
            dimensionLabel: DimensionEngine.format(0, system: drawingData.config.measurementSystem)
        )
        alignmentGuides = []
    }

    public func updateLine(to rawPoint: CGPoint) {
        guard let start = activeLineStartPosition else { return }
        let end = snappedEndpoint(from: start, rawEnd: rawPoint)
        let alignment = SnapEngine.detectAlignmentGuides(
            from: start,
            currentEnd: end,
            vertices: drawingData.vertices,
            edges: drawingData.edges,
            vertexLookup: drawingData.vertex(byId:),
            excludeVertexIds: Set([activeLineStartVertexId].compactMap { $0 })
        )
        let alignedEnd = alignment.snappedPoint
        alignmentGuides = alignment.guides
        activeLine = DeckEditorLinePreview(
            start: start,
            end: alignedEnd,
            dimensionLabel: dimensionLabel(from: start, to: alignedEnd)
        )
    }

    public func endLine(at rawPoint: CGPoint) {
        guard let start = activeLineStartPosition else { return }
        let previewEnd = activeLine?.end ?? snappedEndpoint(from: start, rawEnd: rawPoint)
        let end = resolvedPoint(
            previewEnd,
            excluding: Set([activeLineStartVertexId].compactMap { $0 })
        )

        guard SnapEngine.distance(start, end.point) >= minimumLineLength else {
            clearActiveLine()
            return
        }

        let startId = activeLineStartVertexId ?? appendVertex(at: start)
        let endId = end.vertexId ?? appendVertex(at: end.point)
        guard startId != endId, !edgeExists(between: startId, and: endId) else {
            clearActiveLine()
            return
        }

        let edge = DeckEdge(
            startVertexId: startId,
            endVertexId: endId,
            dimension: SnapEngine.distance(start, end.point) / drawingData.effectiveScaleFactor,
            dimensionSource: .scale
        )
        drawingData.edges.append(edge)
        clearActiveLine()
        persistDrawingData()
    }

    @discardableResult
    public func generateFraming() -> Bool {
        guard capabilities.contains(.plausibleFrame) else { return false }
        guard drawingData.hasAnyClosedSurface else { return false }
        drawingData.framing = AutoFramingEngine.generate(from: drawingData, preset: selectedLoadPreset)
        persistDrawingData()
        return true
    }

    @discardableResult
    public func regenerateFramingPreservingEdits() -> Bool {
        guard capabilities.contains(.plausibleFrame) else { return false }
        guard let existing = drawingData.framing else {
            return generateFraming()
        }
        drawingData.framing = AutoFramingEngine.regenerate(
            from: drawingData,
            existing: existing,
            preset: selectedLoadPreset
        )
        persistDrawingData()
        return true
    }

    public func setLoadPreset(_ preset: LoadPreset) {
        selectedLoadPreset = preset
        if drawingData.framing != nil {
            _ = regenerateFramingPreservingEdits()
        }
    }

    public func setGroundCover(_ cover: GroundCover) {
        guard capabilities.contains(.groundCover) else { return }
        var terrain = drawingData.terrain ?? TerrainModel()
        let polygon = drawingData.detectedSurfaces.first?.positions ?? drawingData.orderedPositions
        if terrain.groundCover.isEmpty {
            terrain.groundCover.append(GroundZone(polygon: polygon, cover: cover))
        } else {
            terrain.groundCover[0].cover = cover
            if polygon.count >= 3 {
                terrain.groundCover[0].polygon = polygon
            }
        }
        drawingData.terrain = terrain
        persistDrawingData()
    }

    @discardableResult
    public func setFloorLine(feet: Double?) -> Bool {
        guard HouseEditingIntentEngine.setFloorLine(
            feet: feet,
            in: &drawingData,
            capabilities: capabilities
        ) else { return false }
        persistDrawingData()
        return true
    }

    @discardableResult
    public func setStoryHeights(_ feet: [Double]) -> Bool {
        guard HouseEditingIntentEngine.setStoryHeights(
            feet,
            in: &drawingData,
            capabilities: capabilities
        ) else { return false }
        persistDrawingData()
        return true
    }

    @discardableResult
    public func addOpening(
        _ kind: OpeningKind,
        onEdge edgeId: String,
        widthInches: Double,
        heightInches: Double,
        sillHeightInches: Double,
        offsetAlongEdgeInches: Double
    ) -> HouseOpeningMutationResult {
        let result = HouseEditingIntentEngine.addOpening(
            kind,
            onEdge: edgeId,
            widthInches: widthInches,
            heightInches: heightInches,
            sillHeightInches: sillHeightInches,
            offsetAlongEdgeInches: offsetAlongEdgeInches,
            in: &drawingData,
            capabilities: capabilities
        )
        if result.didMutate {
            persistDrawingData()
        }
        return result
    }

    @discardableResult
    public func updateOpening(_ opening: WallOpening) -> HouseOpeningMutationResult {
        let result = HouseEditingIntentEngine.updateOpening(
            opening,
            in: &drawingData,
            capabilities: capabilities
        )
        if result.didMutate {
            persistDrawingData()
        }
        return result
    }

    @discardableResult
    public func removeOpening(id: String) -> Bool {
        guard HouseEditingIntentEngine.removeOpening(
            id: id,
            in: &drawingData,
            capabilities: capabilities
        ) else { return false }
        persistDrawingData()
        return true
    }

    @discardableResult
    public func resolveLedger(
        forEdge edgeId: String,
        houseSideBeamSpanInches: Double
    ) -> LedgerStrategyEngine.Strategy? {
        guard let strategy = HouseEditingIntentEngine.resolveLedger(
            forEdge: edgeId,
            houseSideBeamSpanInches: houseSideBeamSpanInches,
            in: &drawingData,
            capabilities: capabilities
        ) else { return nil }
        persistDrawingData()
        return strategy
    }

    @discardableResult
    public func setLedgerDetail(_ detail: LedgerDetail) -> Bool {
        guard HouseEditingIntentEngine.setLedgerDetail(
            detail,
            in: &drawingData,
            capabilities: capabilities
        ) else { return false }
        persistDrawingData()
        return true
    }

    public func clear() {
        drawingData = DeckDrawingData()
        selectedLoadPreset = LoadPreset()
        clearActiveLine()
        persistDrawingData()
    }

    private var minimumLineLength: Double {
        max(2, drawingData.effectiveScaleFactor)
    }

    private func appendVertex(at position: CGPoint) -> String {
        let vertex = DeckVertex(position: position)
        drawingData.vertices.append(vertex)
        return vertex.id
    }

    private func edgeExists(between lhs: String, and rhs: String) -> Bool {
        drawingData.edges.contains { edge in
            (edge.startVertexId == lhs && edge.endVertexId == rhs) ||
                (edge.startVertexId == rhs && edge.endVertexId == lhs)
        }
    }

    private func resolvedPoint(_ point: CGPoint, excluding excludedIds: Set<String> = []) -> (point: CGPoint, vertexId: String?) {
        if let snapId = SnapEngine.findSnapTarget(
            point: point,
            vertices: drawingData.vertices,
            snapRadius: drawingData.config.endpointSnapRadius,
            excludeVertexIds: excludedIds
        ), let vertex = drawingData.vertex(byId: snapId) {
            return (vertex.position, snapId)
        }
        return (snapToGridIfNeeded(point), nil)
    }

    private func snappedEndpoint(from start: CGPoint, rawEnd: CGPoint) -> CGPoint {
        let lengthIncrement = drawingData.config.lengthSnapIncrement * drawingData.effectiveScaleFactor
        let angleSnapped = SnapEngine.snapEndpoint(
            from: start,
            rawEnd: rawEnd,
            angleIncrement: drawingData.config.angleSnapIncrement,
            lengthIncrement: lengthIncrement,
            snappingEnabled: drawingData.config.snappingEnabled
        )
        return snapToGridIfNeeded(angleSnapped)
    }

    private func snapToGridIfNeeded(_ point: CGPoint) -> CGPoint {
        guard drawingData.config.snappingEnabled else { return point }
        let spacing = drawingData.config.lengthSnapIncrement * drawingData.effectiveScaleFactor
        return SnapEngine.snapToGrid(point, gridSpacing: spacing)
    }

    private func dimensionLabel(from start: CGPoint, to end: CGPoint) -> String {
        let inches = SnapEngine.distance(start, end) / drawingData.effectiveScaleFactor
        return DimensionEngine.format(inches, system: drawingData.config.measurementSystem)
    }

    private func clearActiveLine() {
        activeLine = nil
        alignmentGuides = []
        activeLineStartVertexId = nil
        activeLineStartPosition = nil
    }

    private func persistDrawingData() {
        reconcileSurfaces()
        drawingData.components = ComponentEmitter.emit(drawingData)
        refreshCodeReport()
        onPersist(drawingData)
    }

    private func refreshCodeReport() {
        guard canRunCodeChecks, let codeProfile else {
            codeReport = nil
            return
        }
        codeReport = DeckCodeCheckEngine.evaluate(
            drawingData,
            profile: codeProfile,
            settings: codeCheckSettings
        )
    }

    private func reconcileSurfaces() {
        if drawingData.isMultiLevel {
            for index in drawingData.levels.indices {
                let detected = drawingData.levels[index].detectedSurfaces
                let persisted = drawingData.levels[index].surfaces
                drawingData.levels[index].surfaces = SurfaceReconciler.reconcile(
                    detected: detected,
                    persisted: persisted
                )
            }
        } else {
            drawingData.surfaces = SurfaceReconciler.reconcile(
                detected: drawingData.detectedSurfaces,
                persisted: drawingData.surfaces
            )
        }
    }
}
