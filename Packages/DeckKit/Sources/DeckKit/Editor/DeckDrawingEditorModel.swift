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
    @Published public private(set) var isAsBuiltAuditWizardPresented = false

    public let capabilities: DeckCapabilities
    public let codeProfile: DeckCodeProfile?

    private let onPersist: (DeckDrawingData) -> Void
    private let surfaceEngineRunner: DeckSurfaceEditorEngineRunner
    private var activeLineStartVertexId: String?
    private var activeLineStartPosition: CGPoint?

    public convenience init(
        drawingData: DeckDrawingData,
        capabilities: DeckCapabilities,
        codeProfile: DeckCodeProfile? = nil,
        onPersist: @escaping (DeckDrawingData) -> Void = { _ in }
    ) {
        self.init(
            drawingData: drawingData,
            capabilities: capabilities,
            codeProfile: codeProfile,
            onPersist: onPersist,
            surfaceEngineRunner: .live
        )
    }

    init(
        drawingData: DeckDrawingData,
        capabilities: DeckCapabilities,
        codeProfile: DeckCodeProfile? = nil,
        onPersist: @escaping (DeckDrawingData) -> Void = { _ in },
        surfaceEngineRunner: DeckSurfaceEditorEngineRunner
    ) {
        let loaded = DeckSchemaMigration.stampFramingVersion(drawingData)
        self.drawingData = loaded
        self.capabilities = capabilities
        self.codeProfile = codeProfile
        self.selectedLoadPreset = loaded.framing?.loadPreset ?? LoadPreset()
        self.codeCheckSettings = capabilities.contains(.codeCompliance) && codeProfile != nil ? .enabled : .disabled
        self.onPersist = onPersist
        self.surfaceEngineRunner = surfaceEngineRunner
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

    public var canRunPermitCompliance: Bool {
        capabilities.contains(.compliance)
    }

    public var canOpenAsBuiltAudit: Bool {
        capabilities.contains(.compliance)
    }

    public var canGeneratePermitPlanSet: Bool {
        capabilities.contains(.permitPlanSet)
    }

    public var canRequestPEStamp: Bool {
        capabilities.contains(.peStamp)
    }

    public var cachedComplianceReport: ComplianceReport? {
        drawingData.permitMeta?.lastComplianceResult
    }

    public var shouldSurfacePEStampRequest: Bool {
        cachedComplianceReport?.findings.contains { finding in
            finding.fix?.localizedCaseInsensitiveContains("licensed engineer") == true
        } ?? false
    }

    var surfaceEditorEntries: [DeckSurfaceEditorEntry] {
        DeckSurfaceEditorToolbarModel.entries(for: capabilities)
    }

    public var visibleCodeFindings: [DeckCodeFinding] {
        guard codeCheckSettings == .enabled else { return [] }
        return codeReport?.findings ?? []
    }

    public func setCodeChecksEnabled(_ isEnabled: Bool) {
        codeCheckSettings = isEnabled && canRunCodeChecks ? .enabled : .disabled
        refreshCodeReport()
    }

    public func requiresComplianceDisclaimer(for package: CodePackage) -> Bool {
        guard canRunPermitCompliance || canGeneratePermitPlanSet else { return false }
        guard let permitMeta = drawingData.permitMeta,
              permitMeta.disclaimerAcknowledgedAt != nil else {
            return true
        }
        return permitMeta.jurisdictionId != package.jurisdictionId
            || permitMeta.codeEdition != packageEdition(package)
    }

    @discardableResult
    public func acknowledgeComplianceDisclaimer(
        for package: CodePackage,
        at acknowledgedAt: Date = Date()
    ) -> Bool {
        guard canRunPermitCompliance || canGeneratePermitPlanSet else { return false }
        let edition = packageEdition(package)
        var permitMeta = drawingData.permitMeta ?? PermitMeta()
        permitMeta.jurisdictionId = package.jurisdictionId
        permitMeta.codeEdition = edition
        permitMeta.disclaimerAcknowledgedAt = acknowledgedAt
        if permitMeta.lastComplianceResult?.packageEdition != edition {
            permitMeta.lastComplianceRunAt = nil
            permitMeta.lastComplianceResult = nil
        }
        drawingData.permitMeta = permitMeta
        persistDrawingData()
        return true
    }

    @discardableResult
    public func runCompliance(
        mode: ComplianceEngine.Mode,
        package: CodePackage
    ) -> ComplianceReport? {
        guard canRunPermitCompliance,
              !requiresComplianceDisclaimer(for: package) else {
            return nil
        }

        let report = ComplianceEngine.evaluate(drawingData, mode: mode, package: package)
        var permitMeta = drawingData.permitMeta ?? PermitMeta()
        permitMeta.jurisdictionId = package.jurisdictionId
        permitMeta.codeEdition = packageEdition(package)
        permitMeta.lastComplianceRunAt = report.generatedAt
        permitMeta.lastComplianceResult = report
        drawingData.permitMeta = permitMeta
        persistDrawingData()
        return report
    }

    public func generatePermitSet(
        sheets: [PlanSheetKind],
        titleBlock: TitleBlock,
        package: CodePackage
    ) -> Data? {
        guard canGeneratePermitPlanSet,
              !requiresComplianceDisclaimer(for: package) else {
            return nil
        }

        let edition = packageEdition(package)
        let report: ComplianceReport
        if let cached = cachedComplianceReport,
           cached.packageEdition == edition {
            report = cached
        } else if let generated = runCompliance(mode: .design, package: package) {
            report = generated
        } else {
            return nil
        }

        var resolvedTitleBlock = titleBlock
        resolvedTitleBlock.packageEdition = edition
        resolvedTitleBlock.disclaimer = ComplianceStrings.disclaimer
        resolvedTitleBlock.peStamp = drawingData.permitMeta?.peStampRequest ?? titleBlock.peStamp
        return PlanSetEngine.renderPermitSet(
            drawingData,
            compliance: report,
            sheets: sheets,
            titleBlock: resolvedTitleBlock,
            package: package
        )
    }

    @discardableResult
    public func openAsBuiltWizard() -> Bool {
        guard canOpenAsBuiltAudit else { return false }
        isAsBuiltAuditWizardPresented = true
        return true
    }

    public func closeAsBuiltWizard() {
        isAsBuiltAuditWizardPresented = false
    }

    @discardableResult
    public func requestPEStamp(
        reason: String?,
        requestedAt: Date = Date()
    ) -> Bool {
        guard canRequestPEStamp else { return false }
        var permitMeta = drawingData.permitMeta ?? PermitMeta()
        permitMeta.peStampRequest = PEStampRequest(
            requested: true,
            reason: reason,
            requestedAt: requestedAt
        )
        drawingData.permitMeta = permitMeta
        persistDrawingData()
        return true
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
    func setSurfacePattern(
        _ pattern: DeckingPattern,
        forSurfaceId surfaceId: String,
        boardAngleDegrees: Double? = nil,
        pictureFrameCourses: Int? = nil
    ) -> Bool {
        guard capabilities.contains(.surfacePatterns),
              !surfaceId.isEmpty else { return false }

        var features = drawingData.surfaceFeatures ?? SurfaceFeaturePlan()
        let spec = SurfacePatternSpec(
            surfaceId: surfaceId,
            pattern: pattern,
            boardAngleDegrees: boardAngleDegrees ?? pattern.defaultBoardAngleDegrees,
            pictureFrameCourses: pictureFrameCourses ?? pattern.defaultPictureFrameCourses
        )

        if let index = features.patterns.firstIndex(where: { $0.surfaceId == surfaceId }) {
            features.patterns[index] = spec
        } else {
            features.patterns.append(spec)
        }

        drawingData.surfaceFeatures = features
        persistDrawingData()
        return true
    }

    @discardableResult
    func setSurfaceFeatures(
        fastenerSystem: FastenerSystem?,
        fascia: Bool,
        skirting: SkirtingSpec?,
        finish: FinishSpec?,
        builtIn: BuiltInFeature? = nil,
        lighting: LightingPlan? = nil
    ) -> Bool {
        guard capabilities.contains(.surfaceFeatures) else { return false }

        var features = drawingData.surfaceFeatures ?? SurfaceFeaturePlan()
        features.fastenerSystem = fastenerSystem
        features.fascia = fascia
        features.skirting = skirting
        if let finish {
            if let index = features.finishes.firstIndex(where: { $0.kind == finish.kind }) {
                features.finishes[index] = finish
            } else {
                features.finishes.append(finish)
            }
        }
        if let builtIn {
            if let index = features.builtIns.firstIndex(where: { $0.kind == builtIn.kind }) {
                features.builtIns[index] = builtIn
            } else {
                features.builtIns.append(builtIn)
            }
        }
        features.lighting = lighting

        drawingData.surfaceFeatures = features
        persistDrawingData()
        return true
    }

    @discardableResult
    func configureStairDetail(
        edgeId: String,
        config: StairConfig,
        package: CodePackage?
    ) -> StairDetailResult? {
        guard capabilities.contains(.stairDetails),
              let edgeIndex = drawingData.edges.firstIndex(where: { $0.id == edgeId }) else {
            return nil
        }

        drawingData.edges[edgeIndex].stairConfig = config
        let result = package.flatMap { package -> StairDetailResult? in
            guard let totalRise = config.totalRiseInches,
                  totalRise > 0,
                  config.width > 0 else { return nil }

            let base = StairCalculator.calculate(
                totalRise: totalRise,
                width: config.width,
                risePerStep: config.risePerStep,
                runPerTread: config.runPerTread,
                treadCountOverride: config.treadCount
            )
            return surfaceEngineRunner.stairDetail(
                base,
                config.editorTreadType,
                config.treadMaterial.editorTitle,
                config.editorStringerSpacingInchesOC,
                selectedLoadPreset.species,
                selectedLoadPreset.grade,
                package,
                config.editorStringerType
            )
        }

        persistDrawingData()
        return result
    }

    @discardableResult
    func upsertOverheadStructure(
        _ structure: OverheadStructure,
        package: CodePackage?
    ) -> Bool {
        guard capabilities.contains(.overheadStructures) else { return false }

        let resolvedStructure: OverheadStructure
        if let package {
            resolvedStructure = surfaceEngineRunner
                .overheadSize(structure, selectedLoadPreset, package)
                .structure
        } else {
            resolvedStructure = structure
        }

        var plan = drawingData.overhead ?? OverheadStructurePlan()
        if let index = plan.structures.firstIndex(where: { $0.id == resolvedStructure.id }) {
            plan.structures[index] = resolvedStructure
        } else {
            plan.structures.append(resolvedStructure)
        }

        drawingData.overhead = plan
        persistDrawingData()
        return true
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

    private func packageEdition(_ package: CodePackage) -> String {
        package.edition ?? package.jurisdictionId
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
