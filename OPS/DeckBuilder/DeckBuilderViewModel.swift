// OPS/OPS/DeckBuilder/DeckBuilderViewModel.swift

import Foundation
import SwiftUI
import SwiftData
import Supabase
import UIKit
import Combine

enum VinylOrderSurfaceScope: Equatable {
    case selectedSurfaces
    case allSurfaces
}

@MainActor
class DeckBuilderViewModel: ObservableObject {

    // MARK: - Dependencies

    let deckDesign: DeckDesign
    private var modelContext: ModelContext?
    /// Weak ref to the offline sync queue. When set, every `save()` records a
    /// pending sync operation so the OutboundProcessor pushes the change to
    /// Supabase on the next push cycle. Optional so previews / tests can run
    /// without wiring the network stack — those paths simply behave like the
    /// pre-fix offline-only build (local saves succeed, nothing pushes).
    /// Bug ab554b5f.
    private weak var syncEngine: SyncEngine?
    /// True after we've enqueued at least one create op for `deckDesign.id`.
    /// Subsequent edits enqueue updates instead. Persists across app launches
    /// implicitly via `lastSyncedAt` on the model — see `enqueueDeckDesignSync`.
    private var hasEnqueuedCreate: Bool = false

    // MARK: - Drawing State

    @Published var drawingData: DeckDrawingData
    @Published var drawingMode: DrawingMode = .idle
    @Published var activeTool: DrawingTool = .draw
    @Published var selection: SelectionState = SelectionState() {
        didSet {
            // Move-XY is a sticky toggle (see toggleSelectionMove); it has no
            // meaning without a selection. Drop the armed flag when the
            // selection empties so the toolbar button doesn't reappear
            // pre-activated next time something is selected.
            if isSelectionMoveArmed && selection.isEmpty {
                isSelectionMoveArmed = false
            }
        }
    }
    @Published var alignmentGuides: [AlignmentGuide] = []
    @Published var tapSelectFilter: Set<SelectableElementType> = Set(SelectableElementType.allCases)
    /// Drag-shape sub-mode while `activeTool == .tapSelect`. DECK-NEW-4.
    @Published var marqueeShape: MarqueeShape = .rect
    /// Arms the next selection drag as an XY move instead of marquee/lasso.
    /// The flag is reset when the move commits or is cancelled.
    @Published var isSelectionMoveArmed: Bool = false
    private var selectionMoveStart: CGPoint?
    private var selectionMoveOriginalVertices: [String: CGPoint] = [:]
    @Published private(set) var selectionClipboard: DeckSelectionClipboard?
    @Published private(set) var pendingPastePreview: DeckPastePreview?
    private var pendingPasteMoveStart: CGPoint?
    private var pendingPasteMoveOriginalPreview: DeckPastePreview?
    /// Fixed drag-start anchor for the active marquee. The running
    /// `.selecting(rect:)` can't double as the anchor — once a reversing drag
    /// pulls the rect origin to a min corner, that corner is no longer the
    /// start point, so the box must be rebuilt from this stable anchor and the
    /// live finger point on every update.
    private var marqueeAnchor: CGPoint?

    // MARK: - UI State

    @Published var showingDimensionInput: Bool = false
    @Published var showingElevationInput: Bool = false
    @Published var showingStairConfig: Bool = false
    @Published var showingAssignmentWheel: Bool = false
    @Published var showingMaterialPicker: Bool = false
    @Published var showingVinylOrderSheet: Bool = false
    @Published var vinylOrderSurfaceScope: VinylOrderSurfaceScope = .selectedSurfaces
    /// Properties sheet (PropertySheetView). Opens full edit controls for
    /// the current selection — edge type, house cladding, railing config,
    /// stair config, surface metadata, vertex elevation, etc. Previously
    /// orphaned with no UI entry point (bug ee787f29 — "no way to change
    /// the type of siding on a house edge"); now reachable from a
    /// "Properties" button on every selection toolbar.
    @Published var showingPropertySheet: Bool = false
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
        // Self-intersecting shapes can't be extruded (the 3D mesh would fold
        // through itself). The renderer already shows the EDGES CROSS warning
        // — disabling 3D mirrors that gating so the action surface stays
        // consistent with what the deck actually allows.
        if isMultiLevel {
            return drawingData.levels.contains { level in
                level.isClosed &&
                level.vertices.count >= 3 &&
                !PolygonMath.isSelfIntersecting(vertices: level.orderedPositions)
            }
        }
        return drawingData.vertices.count >= 3
            && drawingData.isClosed
            && !PolygonMath.isSelfIntersecting(vertices: drawingData.orderedPositions)
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

    @Published var isLocallySaved: Bool = true
    @Published var estimateValidationError: String?
    private var hasShownUndoLevelToast: Bool = false

    // MARK: - Assignment Wheel

    @Published var activeAssignment: AssignedItem?

    // MARK: - Laser Meter

    @Published var isLaserConnected: Bool = false
    @Published var bufferedMeasurement: LaserMeasurement?
    private var laserCancellables = Set<AnyCancellable>()
    private var bufferTimer: Timer?

    // MARK: - Multi-Level State

    @Published var activeLevelIndex: Int = 0
    @Published var showingLevelConnectionSheet: Bool = false

    // MARK: - Autosave (bug 2b1f1a9e)

    /// New drawings autosave silently every 2 minutes. Existing drawings
    /// prompt the user the FIRST time they edit anything, asking whether
    /// to enable the same 2-minute autosave for their changes.
    @Published var showingAutosavePrompt: Bool = false
    @Published var autosaveEnabled: Bool = false
    /// Detected at init: a drawing with no vertices/edges in either single
    /// or multi-level form. New drawings auto-enable the autosave loop;
    /// existing drawings opt in via the prompt.
    private let isNewDrawing: Bool
    private var autosaveTimer: Timer?
    private var hasPromptedForAutosave: Bool = false
    /// 2 minutes — matches the field-test request.
    private static let autosaveInterval: TimeInterval = 120.0
    /// UserDefaults keys for persisting the user's autosave decision so the
    /// prompt fires AT MOST ONCE per device. Previously the answer lived in
    /// the in-memory `hasPromptedForAutosave` flag, which reset on every
    /// fresh ViewModel and re-fired the prompt on every open.
    private static let autosaveDecisionMadeKey = "deckBuilder.autosaveDecisionMade"
    private static let autosavePreferenceKey = "deckBuilder.autosaveEnabled"

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

    /// Persisted per-surface assignments for the currently active drawing
    /// context. Mirrors `activeFootprint` but for the multi-surface model
    /// (DECK-NEW-1 follow-up).
    var activePersistedSurfaces: [DeckSurface] {
        get {
            if isMultiLevel, let level = activeLevel { return level.surfaces }
            return drawingData.surfaces
        }
        set {
            if isMultiLevel, activeLevelIndex < drawingData.levels.count {
                drawingData.levels[activeLevelIndex].surfaces = newValue
            } else {
                drawingData.surfaces = newValue
            }
        }
    }

    /// Returns the persisted DeckSurface ID matching a given detected
    /// surface — by exact vertex set first, then by maximum Jaccard. If
    /// no acceptable match exists, runs a reconcile pass so the caller
    /// gets a stable ID to operate on.
    func persistedSurfaceId(for detected: DetectedSurface) -> String {
        let dSet = Set(detected.vertexIds)
        if let exact = activePersistedSurfaces.first(where: { $0.vertexIds == dSet }) {
            return exact.id
        }
        // Best-effort match before reconciliation; falls back to reconcile.
        var best: (id: String, jaccard: Double)? = nil
        for p in activePersistedSurfaces {
            let intersection = dSet.intersection(p.vertexIds).count
            let union = dSet.union(p.vertexIds).count
            guard union > 0 else { continue }
            let jaccard = Double(intersection) / Double(union)
            if jaccard > (best?.jaccard ?? -1) {
                best = (p.id, jaccard)
            }
        }
        if let match = best, match.jaccard >= SurfaceReconciler.rebindThreshold {
            return match.id
        }
        // Force a reconcile so a brand-new persisted entry exists for this face.
        reconcileSurfaces()
        if let now = activePersistedSurfaces.first(where: { $0.vertexIds == dSet }) {
            return now.id
        }
        return UUID().uuidString // pathological fallback
    }

    /// Reconciles persisted surfaces against the currently detected ones.
    /// Idempotent: safe to call after any geometry mutation (and from
    /// `save()` so persistence captures the latest reconciled state).
    func reconcileSurfaces() {
        if isMultiLevel {
            for i in drawingData.levels.indices {
                let detected = drawingData.levels[i].detectedSurfaces
                let persisted = drawingData.levels[i].surfaces
                let legacy = drawingData.levels[i].footprint
                let reconciled: [DeckSurface]
                if persisted.isEmpty && (!legacy.assignedItems.isEmpty || legacy.label != nil) {
                    reconciled = SurfaceReconciler.migratedFromLegacy(detected: detected, legacyFootprint: legacy)
                    if !reconciled.isEmpty {
                        drawingData.levels[i].footprint.assignedItems.removeAll()
                        drawingData.levels[i].footprint.label = nil
                    }
                } else {
                    reconciled = SurfaceReconciler.reconcile(detected: detected, persisted: persisted)
                }
                drawingData.levels[i].surfaces = reconciled
            }
        } else {
            let detected = drawingData.detectedSurfaces
            let persisted = drawingData.surfaces
            let legacy = drawingData.footprint
            let reconciled: [DeckSurface]
            if persisted.isEmpty && (!legacy.assignedItems.isEmpty || legacy.label != nil) {
                reconciled = SurfaceReconciler.migratedFromLegacy(detected: detected, legacyFootprint: legacy)
                if !reconciled.isEmpty {
                    drawingData.footprint.assignedItems.removeAll()
                    drawingData.footprint.label = nil
                }
            } else {
                reconciled = SurfaceReconciler.reconcile(detected: detected, persisted: persisted)
            }
            drawingData.surfaces = reconciled
        }

        // Drop selection IDs that no longer correspond to any persisted surface.
        let liveIds: Set<String>
        if isMultiLevel {
            liveIds = Set(drawingData.levels.flatMap { $0.surfaces.map { $0.id } })
        } else {
            liveIds = Set(drawingData.surfaces.map { $0.id })
        }
        if !liveIds.isEmpty {
            selection.selectedSurfaceIds = selection.selectedSurfaceIds.intersection(liveIds)
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

    /// Every detected closed face in the active context. Used by the face
    /// hit-test so a tap inside ANY surface (not just a Hamiltonian cycle of
    /// every vertex) selects it. DECK-NEW-1.
    private var activeSurfaces: [DetectedSurface] {
        if isMultiLevel, let level = activeLevel { return level.detectedSurfaces }
        return drawingData.detectedSurfaces
    }

    // MARK: - Undo/Redo

    private var undoStack: [DrawingSnapshot] = []
    private var redoStack: [DrawingSnapshot] = []

    /// Adaptive cap on undo history. Each snapshot is a full deep copy of
    /// `DeckDrawingData`, which is cheap for a typical 6-vertex deck but
    /// grows quickly once a photo overlay or many vertices are in play.
    /// Keep the standard 50 for light drawings, halve it for heavy ones so
    /// memory doesn't grow unboundedly during a long editing session on a
    /// multi-level deck with a field-photo overlay.
    private var maxUndoDepth: Int {
        let totalVertices = drawingData.allVertices.count
        let hasPhotoOverlay = drawingData.photoOverlay != nil
        if hasPhotoOverlay || totalVertices > 60 {
            return 25
        }
        return 50
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Computed

    var isClosed: Bool { activeIsClosed }

    var totalArea: Double? {
        let scale = drawingData.effectiveScaleFactor
        if isMultiLevel {
            // DECK-NEW-1 — sum every detected face on every level, not the
            // single all-vertices polygon. Falls back to the legacy
            // perimeter calculation for levels that are simple closed
            // polygons but produce no detected surfaces (degenerate edge
            // cases). Self-intersecting faces are excluded since their
            // shoelace area is not a usable measurement.
            var total: Double = 0
            for level in drawingData.levels {
                let surfaces = level.detectedSurfaces
                if surfaces.isEmpty {
                    guard level.isClosed,
                          !PolygonMath.isSelfIntersecting(vertices: level.orderedPositions) else { continue }
                    total += PolygonMath.realWorldArea(vertices: level.orderedPositions, scaleFactor: scale)
                } else {
                    for surface in surfaces {
                        guard !PolygonMath.isSelfIntersecting(vertices: surface.positions) else { continue }
                        total += PolygonMath.realWorldArea(vertices: surface.positions, scaleFactor: scale)
                    }
                }
            }
            return total > 0 ? total : nil
        }
        // Single-level — sum across all detected surfaces.
        let surfaces = drawingData.detectedSurfaces
        if !surfaces.isEmpty {
            var total: Double = 0
            for surface in surfaces {
                guard !PolygonMath.isSelfIntersecting(vertices: surface.positions) else { continue }
                total += PolygonMath.realWorldArea(vertices: surface.positions, scaleFactor: scale)
            }
            return total > 0 ? total : nil
        }
        guard isClosed else { return nil }
        let positions = drawingData.orderedPositions
        guard !PolygonMath.isSelfIntersecting(vertices: positions) else { return nil }
        return PolygonMath.realWorldArea(vertices: positions, scaleFactor: scale)
    }

    var selectedSurfaceSummary: DeckSurfaceSelectionSummary? {
        DeckSurfaceInspector.summary(
            selectedSurfaceIds: selection.selectedSurfaceIds,
            detectedSurfaces: activeSurfaces,
            persistedSurfaces: activePersistedSurfaces,
            legacyFootprint: activeFootprint,
            scaleFactor: drawingData.effectiveScaleFactor
        )
    }

    var canPasteSelection: Bool {
        guard let clipboard = selectionClipboard else { return false }
        return !clipboard.isEmpty && pendingPastePreview == nil
    }

    var totalPerimeter: Double? {
        let scale = drawingData.effectiveScaleFactor
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

    /// Live "12' 6\"  90°" string for the in-progress draw. Returned as a
    /// pre-formatted label so the floating header HUD can render it without
    /// duplicating the formatting/snap math. Nil when no draw is in flight.
    /// DECK-NEW-3 — moved out of DeckCanvasView so the HUD pill can live in
    /// the same VStack as the title pill (shared gridlines).
    var liveDimensionLabel: String? {
        guard case .drawing(let fromId, let startPosition, let currentEnd) = drawingMode else { return nil }
        let distance = SnapEngine.distance(startPosition, currentEnd)
        guard distance > 1 else { return nil }

        let dimText: String
        if let scale = drawingData.scaleFactor, scale > 0.001 {
            let inches = distance / scale
            dimText = DimensionEngine.format(inches, system: drawingData.config.measurementSystem)
        } else {
            let inches = distance / DeckBuilderViewModel.prescaleFallbackScale
            dimText = "~" + DimensionEngine.format(inches, system: drawingData.config.measurementSystem)
        }

        let angleText: String
        if let fromVertexId = fromId {
            let edges = isMultiLevel ? (activeLevel?.edges ?? []) : drawingData.edges
            let connected = edges.filter { $0.startVertexId == fromVertexId || $0.endVertexId == fromVertexId }
            if let prev = connected.last {
                let otherId = prev.startVertexId == fromVertexId ? prev.endVertexId : prev.startVertexId
                let lookupVertices = isMultiLevel ? (activeLevel?.vertices ?? []) : drawingData.vertices
                if let other = lookupVertices.first(where: { $0.id == otherId }) {
                    let prevA = SnapEngine.lineAngle(from: startPosition, to: other.position)
                    let newA = SnapEngine.lineAngle(from: startPosition, to: currentEnd)
                    var rel = newA - prevA; if rel < 0 { rel += 360 }; if rel > 180 { rel = 360 - rel }
                    angleText = String(format: "%.0f°", rel)
                } else {
                    angleText = String(format: "%.0f°", SnapEngine.lineAngle(from: startPosition, to: currentEnd))
                }
            } else {
                angleText = String(format: "%.0f°", SnapEngine.lineAngle(from: startPosition, to: currentEnd))
            }
        } else {
            angleText = String(format: "%.0f°", SnapEngine.lineAngle(from: startPosition, to: currentEnd))
        }

        return "\(dimText)  \(angleText)"
    }

    // MARK: - Init

    init(deckDesign: DeckDesign, modelContext: ModelContext? = nil, syncEngine: SyncEngine? = nil) {
        self.deckDesign = deckDesign
        self.modelContext = modelContext
        self.syncEngine = syncEngine
        var loaded = deckDesign.drawingData
        // Backfill the catalog-facing `components` projection on legacy
        // designs that were saved before the deck-catalog vocabulary
        // landed. The projection is derived, not stored — recomputing it
        // here costs sub-millisecond on a typical deck and lets the
        // adapter consume the in-memory state without going through a
        // round-trip save first. The next save persists the projection;
        // designs the user never reopens stay legacy on disk forever and
        // the adapter no-ops on them, which is fine.
        if loaded.components == nil {
            loaded.components = ComponentEmitter.emit(loaded)
        }
        self.drawingData = loaded
        // If the model has already been pushed to Supabase at least once,
        // future saves enqueue updates rather than creates. Bug ab554b5f.
        self.hasEnqueuedCreate = deckDesign.lastSyncedAt != nil
        // A drawing is "new" if it has no committed geometry yet — both
        // single-level and multi-level forms must be empty.
        let hasSingleGeometry = !deckDesign.drawingData.vertices.isEmpty
            || !deckDesign.drawingData.edges.isEmpty
        let hasMultiGeometry = deckDesign.drawingData.levels.contains { level in
            !level.vertices.isEmpty || !level.edges.isEmpty
        }
        self.isNewDrawing = !(hasSingleGeometry || hasMultiGeometry)
        setupLaserSubscription()
        // New drawings auto-enable autosave silently. Existing drawings
        // apply the persisted user choice if one exists, otherwise wait
        // for the first edit to surface the prompt (handled in `save()`).
        // The persisted choice lives in UserDefaults so the prompt never
        // re-asks once the user has answered (either way) on this device.
        if self.isNewDrawing {
            self.autosaveEnabled = true
            startAutosaveTimer()
        } else {
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: Self.autosaveDecisionMadeKey) {
                let saved = defaults.bool(forKey: Self.autosavePreferenceKey)
                self.autosaveEnabled = saved
                self.hasPromptedForAutosave = true
                if saved {
                    startAutosaveTimer()
                }
            }
        }

        // DECK-NEW-1 follow-up — migrate legacy single-`footprint` payloads
        // to the per-surface store on first load. Reconciler is idempotent
        // and safe to run on already-migrated drawings; this just ensures
        // a user who opens an OLD drawing without editing still sees the
        // correct per-surface materials in 2D and 3D.
        reconcileSurfaces()

        // Bug ab554b5f — designs that arrive in the builder with geometry but
        // have NEVER been synced (template / sketch / AR creation paths)
        // need an immediate enqueue so the upload happens even if the user
        // dismisses the builder without editing further. The autosave timer
        // would catch this eventually for new drawings, but a user who opens
        // a freshly-created template-design and immediately backs out would
        // otherwise leave the design only on-device.
        if !self.hasEnqueuedCreate && !self.isNewDrawing {
            self.enqueueDeckDesignSync()
        }
    }

    deinit {
        // Invalidate the measurement buffer timer so a deck builder dismissed
        // mid-measurement doesn't leave a Timer running against a deallocated
        // owner. Timer.invalidate() is safe to call from any actor context.
        bufferTimer?.invalidate()
        autosaveTimer?.invalidate()
        // Set<AnyCancellable> auto-cancels its members on deinit.
    }

    // MARK: - Autosave (bug 2b1f1a9e)

    /// Start the 2-minute autosave loop. Each tick runs `save()` so the
    /// user can recover their work from a crash without having to manually
    /// commit. No-op if a timer is already running.
    ///
    /// Bug 14555d2c — gate the tick on `hasAnyCommittedGeometry` so a
    /// blank-canvas builder that's left open never persists an empty
    /// orphan deck design row (or enqueues an empty create op against
    /// Supabase). The autosave loop only persists once the user has
    /// actually drawn something.
    private func startAutosaveTimer() {
        guard autosaveTimer == nil else { return }
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: Self.autosaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.autosaveEnabled else { return }
                guard self.hasAnyCommittedGeometry else { return }
                self.save()
            }
        }
    }

    /// True when the design has at least one vertex or edge in either the
    /// single-level or any multi-level form. Used as the gate for autosave
    /// ticks and the close-button render-and-upload path so we never
    /// persist or upload thumbnails for genuinely empty drawings.
    /// Bug 14555d2c.
    private var hasAnyCommittedGeometry: Bool {
        if !drawingData.vertices.isEmpty || !drawingData.edges.isEmpty {
            return true
        }
        return drawingData.levels.contains { !$0.vertices.isEmpty || !$0.edges.isEmpty }
    }

    private func stopAutosaveTimer() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }

    /// Called by the prompt's accept path. Existing drawings opt in here.
    /// Persists the choice so the prompt never re-asks on this device.
    func enableAutosave() {
        setAutosavePreference(true)
        showingAutosavePrompt = false
    }

    /// Called by the prompt's decline path. Records that the user answered
    /// so the prompt doesn't re-fire on the next open.
    func declineAutosave() {
        setAutosavePreference(false)
        showingAutosavePrompt = false
    }

    /// Sets the persisted autosave preference and applies it to the live
    /// timer. Bound to the toggle in DeckSettingsSheet so the user can
    /// change their mind after the initial prompt — and writes the
    /// `decisionMade` flag so the prompt stays suppressed.
    func setAutosavePreference(_ enabled: Bool) {
        autosaveEnabled = enabled
        hasPromptedForAutosave = true
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.autosaveDecisionMadeKey)
        defaults.set(enabled, forKey: Self.autosavePreferenceKey)
        if enabled {
            startAutosaveTimer()
        } else {
            stopAutosaveTimer()
        }
    }

    func setVinylCatalogItemId(_ itemId: String?) {
        let trimmed = itemId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        drawingData.config.vinylCatalogItemId = trimmed.isEmpty ? nil : trimmed
        save()
    }

    // MARK: - Undo/Redo

    private func pushUndo(_ description: String) {
        undoStack.append(DrawingSnapshot(drawingData: drawingData, description: description))
        // `while` (not `if`) so a cap that just dropped — e.g. user added a
        // photo overlay mid-session and triggered the heavier-data branch —
        // trims down to the new limit instead of leaving it one-over.
        while undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }

        // First undo in multi-level mode: show a one-time informational toast
        if isMultiLevel && !hasShownUndoLevelToast {
            hasShownUndoLevelToast = true
            ToastCenter.shared.present(Toast(label: "// UNDO AFFECTS ALL LEVELS", tone: .warning))
        }

        redoStack.append(DrawingSnapshot(drawingData: drawingData, description: "redo"))
        drawingData = snapshot.drawingData
        pruneSelectionToGeometry()
        hapticLight()
        save()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(DrawingSnapshot(drawingData: drawingData, description: "undo"))
        drawingData = snapshot.drawingData
        pruneSelectionToGeometry()
        hapticLight()
        save()
    }

    /// Drop selected edge/vertex ids the current geometry no longer contains.
    /// undo()/redo() swap in a snapshot whose graph may not include what was
    /// selected; without this the toolbar shows context actions for elements
    /// that were just undone away and those actions fire against dead ids.
    /// (Surface ids are pruned separately by `save()` → `reconcileSurfaces`.)
    private func pruneSelectionToGeometry() {
        let liveEdgeIds = Set(drawingData.allEdges.map { $0.id })
        let liveVertexIds = Set(drawingData.allVertices.map { $0.id })
        selection.selectedEdgeIds.formIntersection(liveEdgeIds)
        selection.selectedVertexIds.formIntersection(liveVertexIds)
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
        // Wipe any stale alignment guides left over from a previously cancelled
        // draw. Without this, the first frame after begin renders the old
        // guides because updateLine hasn't replaced them yet.
        alignmentGuides = []
        // Magnetic snap to an existing vertex when starting near one. Otherwise
        // snap to the grid and DEFER vertex creation until endLine commits — a
        // cancelled drag must not leave an orphan vertex behind. The undo
        // snapshot is also deferred; nothing has happened yet.
        if let snapId = SnapEngine.findSnapTarget(
            point: position,
            vertices: activeVertices,
            snapRadius: drawingData.config.endpointSnapRadius
        ) {
            let snappedPosition = activeVertex(byId: snapId)?.position ?? position
            drawingMode = .drawing(
                fromVertexId: snapId,
                startPosition: snappedPosition,
                currentEnd: snappedPosition
            )
        } else {
            let snappedPosition = SnapEngine.snapToGrid(
                position,
                gridSpacing: lengthSnapInCanvasPoints()
            )
            drawingMode = .drawing(
                fromVertexId: nil,
                startPosition: snappedPosition,
                currentEnd: snappedPosition
            )
        }
    }

    /// Resolve the displayed endpoint for the active draw at `rawEnd`. Returns
    /// the snapped point AND the alignment guides used so the caller can both
    /// preview the cursor (updateLine) and commit the same exact position
    /// (endLine) without recomputing the chain differently between the two.
    /// Bug a7437d68 — drag and commit MUST resolve to the same canvas point.
    private func resolveActiveEnd(from startPos: CGPoint, rawEnd: CGPoint, fromVertexId: String?) -> (point: CGPoint, guides: [AlignmentGuide], hasAxisAlignment: Bool) {
        // First apply angle/length snapping
        var snapped = SnapEngine.snapEndpoint(
            from: startPos,
            rawEnd: rawEnd,
            angleIncrement: drawingData.config.angleSnapIncrement,
            lengthIncrement: lengthSnapInCanvasPoints(),
            snappingEnabled: drawingData.config.snappingEnabled
        )

        // Then detect alignment guides (axis-aligned, parallel, perpendicular).
        // Exclude the start vertex's edges only when it actually exists in the
        // store — a pending start has nothing to filter against yet.
        let exclude: Set<String> = fromVertexId.map { [$0] } ?? []
        let alignment = SnapEngine.detectAlignmentGuides(
            from: startPos,
            currentEnd: snapped,
            vertices: activeVertices,
            edges: activeEdges,
            vertexLookup: { self.activeVertex(byId: $0) },
            threshold: 8.0,
            excludeVertexIds: exclude
        )

        let hasAxisAlignment = alignment.guides.contains(where: { $0.type == .vertical || $0.type == .horizontal })

        // Apply axis alignment snap (overrides angle/length snap for X or Y)
        if hasAxisAlignment {
            snapped = alignment.snappedPoint
        }

        // Force the cursor onto the visible grid so the live preview matches
        // the committed position exactly. Skip the regrid when an axis-alignment
        // guide is active (preserve the axis-locked feel) or when snapping is
        // disabled. Bug 4c30cd77 — snap = gridpoint, always.
        if drawingData.config.snappingEnabled && !hasAxisAlignment {
            snapped = SnapEngine.snapToGrid(snapped, gridSpacing: lengthSnapInCanvasPoints())
        }

        return (snapped, alignment.guides, hasAxisAlignment)
    }

    func updateLine(to rawEnd: CGPoint) {
        guard case .drawing(let fromId, let startPos, _) = drawingMode else { return }

        let resolved = resolveActiveEnd(from: startPos, rawEnd: rawEnd, fromVertexId: fromId)
        alignmentGuides = resolved.guides
        drawingMode = .drawing(fromVertexId: fromId, startPosition: startPos, currentEnd: resolved.point)
    }

    func endLine(at rawEnd: CGPoint) {
        guard case .drawing(let fromId, let startPos, _) = drawingMode else { return }

        // Resolve via the SAME chain updateLine uses so the committed position
        // is identical to the live preview the user just released on. Previously
        // endLine ran snapEndpoint + an unconditional snapToGrid, ignoring the
        // axis-alignment guides updateLine consumed — which produced different
        // canvas points (and therefore different displayed dimensions) between
        // drag and commit. Bug a7437d68.
        let resolved = resolveActiveEnd(from: startPos, rawEnd: rawEnd, fromVertexId: fromId)
        let snapped = resolved.point

        // Resolve the end position FIRST without mutating state. Either we
        // snap to an existing vertex (preferred — closes the polygon when the
        // user finishes near the first vertex) or we use the resolved point.
        let exclude: Set<String> = fromId.map { [$0] } ?? []

        // Close detection runs against the RAW release first, then the resolved
        // point. The raw finger position is the true record of "where the user
        // meant to end"; angle/length/grid snapping is cosmetic cleanup that can
        // displace the resolved endpoint a whole grid cell away from the start
        // vertex (far previous corner + wide grid pitch), pushing it outside the
        // snap radius even though the finger landed inside it. Querying the raw
        // release too means a perimeter the user closed onto the first vertex
        // reuses that vertex id and the loop actually closes — instead of
        // committing a fresh, coincident-but-distinct end that leaves the
        // perimeter topologically open and the 3D model un-renderable. Deck
        // Drop 1, Task 5. The radius and exclusion are identical to the resolved
        // query, so a genuinely-far release still can't false-close.
        let snapEndId = SnapEngine.findSnapTarget(
            point: rawEnd,
            vertices: activeVertices,
            snapRadius: drawingData.config.endpointSnapRadius,
            excludeVertexIds: exclude
        ) ?? SnapEngine.findSnapTarget(
            point: snapped,
            vertices: activeVertices,
            snapRadius: drawingData.config.endpointSnapRadius,
            excludeVertexIds: exclude
        )
        let endPosition: CGPoint
        if let snapId = snapEndId, let v = activeVertex(byId: snapId) {
            endPosition = v.position
        } else {
            endPosition = snapped
        }

        // H7: discard near-zero-length lines. A drag that barely moved is
        // almost always an accidental tap-and-twitch, not a real line. Without
        // this guard a 0.5pt edge ends up in the model — countable in the
        // perimeter, drawable as a label in zero space, hit-targetable.
        let canvasDistance = SnapEngine.distance(startPos, endPosition)
        let minEdgeLength = drawingData.config.endpointSnapRadius / 2.0
        guard canvasDistance >= minEdgeLength else {
            // Nothing was committed — no undo step, no orphaned start vertex
            // (we deferred its creation). Just drop back to idle.
            alignmentGuides = []
            drawingMode = .idle
            return
        }

        // Now we know the line is real. Snapshot BEFORE creating any vertices
        // so one undo reverts the entire draw (start vertex + end vertex +
        // edge) atomically.
        pushUndo("draw line")

        // Commit the START vertex if it was deferred (drag began in empty space).
        let startVertexId: String
        if let existing = fromId {
            startVertexId = existing
        } else {
            let v = DeckVertex(position: startPos)
            startVertexId = v.id
            activeVertices.append(v)
        }

        // Commit the END vertex if we didn't snap to an existing one.
        let endVertexId: String
        if let existing = snapEndId {
            endVertexId = existing
        } else {
            let v = DeckVertex(position: endPosition)
            endVertexId = v.id
            activeVertices.append(v)
        }

        // Self-loop guard — can only happen if both ends snapped to the same
        // vertex past the H7 length check, which the snap-radius filter
        // ordinarily prevents but we belt-and-brace it.
        guard startVertexId != endVertexId else {
            // Roll back the snapshot since we won't actually mutate.
            _ = undoStack.popLast()
            alignmentGuides = []
            drawingMode = .idle
            return
        }

        // Build the edge
        var edge = DeckEdge(startVertexId: startVertexId, endVertexId: endVertexId)
        if let scale = drawingData.scaleFactor, scale > 0 {
            edge.dimension = canvasDistance / scale  // inches
        } else {
            // No scale factor — store inches against the prescale fallback so the
            // committed label matches the live drag readout (which divides by the
            // same fallback). Bug a7437d68 — previously we stored raw canvas points
            // here, so a 200pt line drew as "~8'4"" mid-drag and committed as
            // "16'8"" (raw points labelled as inches). autoFillDimensions
            // back-fills from canvas geometry once the user calibrates scale, so
            // overwriting this value later is fine.
            edge.dimension = canvasDistance / DeckBuilderViewModel.prescaleFallbackScale
        }
        edge.dimensionSource = .scale

        // Apply active assignment if set
        if let assignment = activeAssignment,
           assignment.unitType == .linearFoot || assignment.unitType == .linearMeter {
            edge.assignedItems.append(assignment)
        }

        activeEdges.append(edge)

        // Check if we closed the polygon. Success haptic is reserved for
        // valid closures — a bowtie is topologically closed but visually
        // wrong, and celebrating that with a success buzz misleads the user
        // into thinking the deck is good.
        if activeIsClosed {
            activeFootprint.isClosed = true
            if PolygonMath.isSelfIntersecting(vertices: activeOrderedPositions) {
                hapticMedium()
            } else {
                hapticSuccess()
            }
        } else {
            hapticMedium() // line committed
        }

        alignmentGuides = []
        drawingMode = .idle
        save()
    }

    // MARK: - Stair Hit Test (DECK-NEW-6)

    /// Returns the edge id whose stair rectangle contains `point` in canvas
    /// space. Mirrors the geometry built by `DeckCanvasView.drawStairIndicator`
    /// so the tap target matches the rendered stair shape exactly: outward
    /// perpendicular from the deck fill, alignment + offset along the edge,
    /// width clamped to edge length. Returns nil when the tap is outside
    /// every stair (or no edges have stairs).
    private func findStairEdgeAtPoint(_ point: CGPoint) -> String? {
        let edges = activeEdges
        let vertices = activeVertices
        let polygon = activeOrderedPositions
        let scale: Double
        if let s = drawingData.scaleFactor, s > 0 {
            scale = s
        } else {
            scale = DeckBuilderViewModel.prescaleFallbackScale
        }

        for edge in edges {
            guard let config = edge.stairConfig,
                  let tc = config.treadCount, tc > 0,
                  let start = vertices.first(where: { $0.id == edge.startVertexId }),
                  let end = vertices.first(where: { $0.id == edge.endVertexId }) else { continue }

            let s = start.position
            let e = end.position
            let dx = e.x - s.x
            let dy = e.y - s.y
            let edgeLen = sqrt(dx * dx + dy * dy)
            guard edgeLen > 0 else { continue }
            let edgeNx = dx / edgeLen
            let edgeNy = dy / edgeLen

            let outward = PolygonMath.outwardPerpendicular(
                edgeStart: s, edgeEnd: e, polygonVertices: polygon
            )
            let perpX = config.flipDirection ? -outward.x : outward.x
            let perpY = config.flipDirection ? -outward.y : outward.y

            let stairWidth = min(CGFloat(config.width) * CGFloat(scale), edgeLen)
            let totalRunInches = Double(tc) * config.runPerTread
            let stairDepth = CGFloat(totalRunInches) * CGFloat(scale)
            let offsetCanvas = CGFloat(config.offset) * CGFloat(scale)
            let gapTotal = edgeLen - stairWidth
            let stairStartT: CGFloat
            switch config.alignment {
            case .left:   stairStartT = offsetCanvas / edgeLen
            case .center: stairStartT = (gapTotal / 2 + offsetCanvas) / edgeLen
            case .right:  stairStartT = (gapTotal - offsetCanvas) / edgeLen
            }

            let baseStart = CGPoint(
                x: s.x + edgeNx * edgeLen * stairStartT,
                y: s.y + edgeNy * edgeLen * stairStartT
            )
            let baseEnd = CGPoint(
                x: baseStart.x + edgeNx * stairWidth,
                y: baseStart.y + edgeNy * stairWidth
            )
            let farStart = CGPoint(
                x: baseStart.x + CGFloat(perpX) * stairDepth,
                y: baseStart.y + CGFloat(perpY) * stairDepth
            )
            let farEnd = CGPoint(
                x: baseEnd.x + CGFloat(perpX) * stairDepth,
                y: baseEnd.y + CGFloat(perpY) * stairDepth
            )
            if PolygonMath.pointInPolygon(point, vertices: [baseStart, baseEnd, farEnd, farStart]) {
                return edge.id
            }
        }
        return nil
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

        // DECK-NEW-6 — stairs are tap-selectable. Hit-test the stair rectangle
        // for any edge with a stairConfig BEFORE the regular edge check so a
        // tap inside the stair geometry counts as "select that edge + edit
        // its stair" instead of "miss" (the stair lives outside the edge
        // line itself, so without this it was unreachable by tap).
        if tapSelectFilter.contains(.edge),
           let stairEdgeId = findStairEdgeAtPoint(point) {
            if !additive { selection.clear() }
            // Toggle/add like an edge tap — never replace the whole set.
            // Previously this did `selectedEdgeIds = [stairEdgeId]`, which in
            // additive (multi-select) mode wiped every other selected edge.
            selection.toggleEdge(stairEdgeId)
            editingEdgeId = stairEdgeId
            hapticMedium()
            // Auto-open the stair editor only on a plain single-select tap —
            // single tap = edit. In additive mode the user is building a
            // multi-selection, so popping a modal editor (and clobbering the
            // set) is wrong; mirror edge-tap, which never opens a sheet while
            // multi-selecting.
            if !additive {
                showingStairConfig = true
            }
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

        // DECK-NEW-1 — face hit-test against EVERY detected surface, not
        // just the all-vertices polygon. Surfaces are tested smallest-first
        // so a tap inside a small inner surface selects it instead of the
        // larger outer one that contains it. Toggles the matching persisted
        // DeckSurface in `selection.selectedSurfaceIds` (per-surface
        // selection — DECK-NEW-1 follow-up).
        if tapSelectFilter.contains(.face) {
            let surfaces = activeSurfaces
            let ordered = surfaces.sorted { abs(PolygonMath.signedArea(vertices: $0.positions)) < abs(PolygonMath.signedArea(vertices: $1.positions)) }
            for detected in ordered {
                guard !PolygonMath.isSelfIntersecting(vertices: detected.positions) else { continue }
                if PolygonMath.pointInPolygon(point, vertices: detected.positions) {
                    if !additive { selection.clear() }
                    let persistedId = persistedSurfaceId(for: detected)
                    selection.toggleSurface(persistedId)
                    hapticLight()
                    return
                }
            }
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
            // Mirror handleTap: footprint is only hittable when the shape is
            // valid. Otherwise long-press on a bowtie's interior would register
            // as "selecting the surface" while the renderer shows a warning fill.
            let hitsFootprint = activeIsClosed
                && !PolygonMath.isSelfIntersecting(vertices: activeOrderedPositions)
                && PolygonMath.pointInPolygon(point, vertices: activeOrderedPositions)

            if !hitsVertex && !hitsEdge && !hitsFootprint {
                exitMultiSelect()
                return
            }
            // Long-press just selects the element. Properties sheet was removed
            // (deck-new-7) — long-press on something already selected is now a no-op
            // beyond the haptic confirm.
            handleTap(at: point, hitThreshold: hitThreshold)
            if !selection.isEmpty {
                hapticMedium()
            }
            return
        }

        // Pre-check for any hit before delegating to handleTap. Without this,
        // a long-press on empty canvas in .draw mode silently clears the
        // user's selection (handleTap's else branch). Field workers complained
        // that long-pressing to inspect deselected things they didn't intend
        // to deselect — only act when there's actually something under the
        // finger.
        let hitsVertex = PolygonMath.findVertexAtPoint(
            point, vertices: activeVertices, hitThreshold: hitThreshold
        ) != nil
        let hitsEdge = PolygonMath.findEdgeAtPoint(
            point, edges: activeEdges, vertices: activeVertices, hitThreshold: hitThreshold * 0.8
        ) != nil
        let hitsFootprint = activeIsClosed
            && !PolygonMath.isSelfIntersecting(vertices: activeOrderedPositions)
            && PolygonMath.pointInPolygon(point, vertices: activeOrderedPositions)
        guard hitsVertex || hitsEdge || hitsFootprint else { return }

        // Same hit detection as tap; property sheet removed (deck-new-7)
        handleTap(at: point, hitThreshold: hitThreshold)
        if !selection.isEmpty {
            hapticMedium()
        }
    }

    // MARK: - Marquee Selection

    func beginMarquee(at point: CGPoint) {
        marqueeAnchor = point
        drawingMode = .selecting(rect: CGRect(origin: point, size: .zero))
    }

    func updateMarquee(to point: CGPoint) {
        guard case .selecting = drawingMode else { return }
        // Normalize from the FIXED anchor (drag start) and the live point so
        // the box is correct for any drag direction. Reading the anchor off the
        // running rect's origin is wrong: after a reversing drag the origin is
        // the minimized corner, not the start, and the box would collapse /
        // pin to a stale corner (negative-extent bug).
        let anchor = marqueeAnchor ?? point
        let newRect = CGRect(
            x: min(anchor.x, point.x),
            y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x),
            height: abs(point.y - anchor.y)
        )
        drawingMode = .selecting(rect: newRect)
    }

    func endMarquee() {
        guard case .selecting(let rect) = drawingMode else { return }
        defer {
            marqueeAnchor = nil
            drawingMode = .idle
        }
        let additive = activeTool == .tapSelect   // Multi-select mode: add, never replace
        if !additive { selection.clear() }

        // Vertices geometrically inside the box — computed independent of the
        // filter so edges can still be resolved by their endpoints even when
        // vertex selection is filtered out (e.g. edge-only marquee).
        let hitVertexIds = Set(activeVertices.filter { rect.contains($0.position) }.map(\.id))

        // Honor the tap-select element-type filter (DECK-NEW-4) for marquee the
        // same way handleTap does — without this, marquee added every element
        // type regardless of the vertices/edges/faces toggle.
        if tapSelectFilter.contains(.vertex) {
            selection.selectedVertexIds.formUnion(hitVertexIds)
        }

        if tapSelectFilter.contains(.edge) {
            // Edges fully inside (both endpoints hit). Union the geometric hits
            // with the existing selection so additive mode picks up edges even
            // if one endpoint was pre-selected.
            let effectiveVertexIds = selection.selectedVertexIds.union(hitVertexIds)
            for edge in activeEdges {
                if effectiveVertexIds.contains(edge.startVertexId) &&
                   effectiveVertexIds.contains(edge.endVertexId) {
                    selection.selectedEdgeIds.insert(edge.id)
                }
            }
        }
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

        // Vertices inside the lasso polygon — computed independent of the
        // filter so edges can be resolved by their endpoints even when vertex
        // selection is filtered out.
        let hitVertexIds = Set(
            activeVertices
                .filter { PolygonMath.pointInPolygon($0.position, vertices: points) }
                .map(\.id)
        )

        // Honor the tap-select element-type filter (DECK-NEW-4) — lasso must
        // respect the vertices/edges/faces toggle just like handleTap.
        if tapSelectFilter.contains(.vertex) {
            selection.selectedVertexIds.formUnion(hitVertexIds)
        }

        if tapSelectFilter.contains(.edge) {
            let effectiveVertexIds = selection.selectedVertexIds.union(hitVertexIds)
            for edge in activeEdges {
                if effectiveVertexIds.contains(edge.startVertexId) &&
                   effectiveVertexIds.contains(edge.endVertexId) {
                    selection.selectedEdgeIds.insert(edge.id)
                }
            }
        }

        drawingMode = .idle
    }

    // MARK: - Vertex Drag (2D canvas only)

    func beginVertexDrag(_ vertexId: String) {
        pushUndo("move vertex")
        // Drop any leftover guides from a previous draw — none of the non-
        // .drawing modes render guides, but clearing the array prevents a
        // stale value from being restored next time .drawing begins.
        alignmentGuides = []
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

                // Check if we closed the polygon. Same gating as endLine: a
                // bowtie is topologically closed but doesn't earn a success
                // haptic until the user fixes the crossings.
                if activeIsClosed {
                    activeFootprint.isClosed = true
                    if !PolygonMath.isSelfIntersecting(vertices: activeOrderedPositions) {
                        hapticSuccess()
                    }
                }
            } else {
                recalculateEdgeDimensions(connectedTo: vertexId)
            }
        }
        drawingMode = .idle
        save()
    }

    // MARK: - Selection XY Move

    /// Sticky toggle for the Move-XY mode. The Move-XY toolbar buttons
    /// route through this so a tap flips the mode on; while on, every
    /// canvas selection drag translates the selection (begin/update/
    /// endSelectionMove). Sticky across moves — was previously one-shot
    /// (endSelectionMove auto-disarmed) so the user had to re-tap the
    /// toolbar before every move.
    func toggleSelectionMove() {
        if isSelectionMoveArmed {
            disarmSelectionMove()
        } else {
            armSelectionMove()
        }
    }

    func armSelectionMove() {
        guard !selection.isEmpty else { return }
        activeTool = .tapSelect
        drawingMode = .idle
        alignmentGuides = []
        isSelectionMoveArmed = true
        hapticLight()
    }

    /// Turn the sticky Move-XY mode off. Cancels any in-flight move and
    /// clears the move scratch state. Safe to call when not armed.
    func disarmSelectionMove() {
        if case .movingSelection = drawingMode {
            drawingMode = .idle
        }
        selectionMoveStart = nil
        selectionMoveOriginalVertices.removeAll()
        alignmentGuides = []
        isSelectionMoveArmed = false
        hapticLight()
    }

    func beginSelectionMove(at point: CGPoint) {
        let vertexIds = selectedMoveVertexIds()
        guard !vertexIds.isEmpty else {
            isSelectionMoveArmed = false
            return
        }

        pushUndo("move selection on XY")
        selectionMoveStart = point
        selectionMoveOriginalVertices = Dictionary(
            activeVertices
                .filter { vertexIds.contains($0.id) }
                .map { ($0.id, $0.position) },
            uniquingKeysWith: { first, _ in first }
        )
        drawingMode = .movingSelection
        alignmentGuides = []
    }

    func updateSelectionMove(to point: CGPoint) {
        guard case .movingSelection = drawingMode,
              let start = selectionMoveStart,
              !selectionMoveOriginalVertices.isEmpty else { return }

        let rawDelta = CGSize(width: point.x - start.x, height: point.y - start.y)
        let resolved = resolveSelectionMoveDelta(rawDelta)
        applySelectionMove(delta: resolved.delta)
        alignmentGuides = resolved.guides
    }

    func endSelectionMove() {
        guard case .movingSelection = drawingMode else { return }
        let movedIds = Set(selectionMoveOriginalVertices.keys)
        for vertexId in movedIds {
            recalculateEdgeDimensions(connectedTo: vertexId)
        }
        drawingMode = .idle
        // isSelectionMoveArmed intentionally NOT cleared — Move-XY is a sticky
        // toggle, so a follow-up drag in the canvas can start another move
        // without the user re-tapping the toolbar.
        selectionMoveStart = nil
        selectionMoveOriginalVertices.removeAll()
        alignmentGuides = []
        hapticMedium()
        save()
    }

    // MARK: - Copy / Paste Selection

    @discardableResult
    func copySelection() -> Bool {
        guard let clipboard = buildSelectionClipboard(), !clipboard.isEmpty else { return false }
        selectionClipboard = clipboard
        hapticLight()
        return true
    }

    func beginPaste() {
        guard let clipboard = selectionClipboard else { return }
        let target = CGPoint(x: clipboard.center.x + 48, y: clipboard.center.y + 48)
        beginPaste(at: target)
    }

    func beginPaste(at point: CGPoint) {
        guard let clipboard = selectionClipboard, !clipboard.isEmpty else { return }
        pendingPastePreview = clipboard.preview(centeredAt: point)
        pendingPasteMoveStart = nil
        pendingPasteMoveOriginalPreview = nil
        selection.clear()
        isSelectionMoveArmed = false
        drawingMode = .idle
        activeTool = .tapSelect
        hapticLight()
    }

    func beginPendingPasteMove(at point: CGPoint) {
        guard let preview = pendingPastePreview else { return }
        pendingPasteMoveStart = point
        pendingPasteMoveOriginalPreview = preview
        drawingMode = .movingPendingPaste
        alignmentGuides = []
    }

    func updatePendingPasteMove(to point: CGPoint) {
        guard case .movingPendingPaste = drawingMode,
              let start = pendingPasteMoveStart,
              var preview = pendingPasteMoveOriginalPreview else { return }
        preview.translate(by: CGSize(width: point.x - start.x, height: point.y - start.y))
        pendingPastePreview = preview
    }

    func endPendingPasteMove() {
        guard case .movingPendingPaste = drawingMode else { return }
        drawingMode = .idle
        pendingPasteMoveStart = nil
        pendingPasteMoveOriginalPreview = nil
        alignmentGuides = []
        hapticLight()
    }

    func commitPendingPaste() {
        guard let preview = pendingPastePreview, !preview.isEmpty else { return }
        pushUndo("paste selection")

        var vertices = activeVertices
        vertices.append(contentsOf: preview.vertices)
        activeVertices = vertices

        var edges = activeEdges
        edges.append(contentsOf: preview.edges)
        activeEdges = edges

        if !preview.surfaces.isEmpty {
            var surfaces = activePersistedSurfaces
            surfaces.append(contentsOf: preview.surfaces)
            activePersistedSurfaces = surfaces
        }

        reconcileSurfaces()

        selection.clear()
        selection.selectedVertexIds = Set(preview.vertices.map(\.id))
        selection.selectedEdgeIds = Set(preview.edges.map(\.id))
        let liveSurfaceIds = Set(activePersistedSurfaces.map(\.id))
        selection.selectedSurfaceIds = Set(preview.surfaces.map(\.id)).intersection(liveSurfaceIds)

        pendingPastePreview = nil
        pendingPasteMoveStart = nil
        pendingPasteMoveOriginalPreview = nil
        drawingMode = .idle
        activeTool = .tapSelect
        hapticMedium()
        save()
    }

    func cancelPendingPaste() {
        pendingPastePreview = nil
        pendingPasteMoveStart = nil
        pendingPasteMoveOriginalPreview = nil
        if case .movingPendingPaste = drawingMode {
            drawingMode = .idle
        }
        hapticLight()
    }

    private func buildSelectionClipboard() -> DeckSelectionClipboard? {
        var vertexIds = selection.selectedVertexIds
        var edgeIds = selection.selectedEdgeIds
        let selectedSurfaces = activePersistedSurfaces.filter { selection.selectedSurfaceIds.contains($0.id) }

        for edge in activeEdges where edgeIds.contains(edge.id) {
            vertexIds.insert(edge.startVertexId)
            vertexIds.insert(edge.endVertexId)
        }

        for surface in selectedSurfaces {
            vertexIds.formUnion(surface.vertexIds)
            for edge in activeEdges where surface.vertexIds.contains(edge.startVertexId)
                && surface.vertexIds.contains(edge.endVertexId) {
                edgeIds.insert(edge.id)
            }
        }

        let vertices = activeVertices.filter { vertexIds.contains($0.id) }
        guard !vertices.isEmpty else { return nil }
        let liveVertexIds = Set(vertices.map(\.id))
        let edges = activeEdges.filter {
            edgeIds.contains($0.id)
                && liveVertexIds.contains($0.startVertexId)
                && liveVertexIds.contains($0.endVertexId)
        }
        let surfaces = selectedSurfaces.filter { $0.vertexIds.isSubset(of: liveVertexIds) }
        let xs = vertices.map { $0.position.x }
        let ys = vertices.map { $0.position.y }
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max() else { return nil }

        return DeckSelectionClipboard(
            vertices: vertices,
            edges: edges,
            surfaces: surfaces,
            bounds: CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
        )
    }

    private func selectedMoveVertexIds() -> Set<String> {
        var ids = selection.selectedVertexIds
        for edge in activeEdges where selection.selectedEdgeIds.contains(edge.id) {
            ids.insert(edge.startVertexId)
            ids.insert(edge.endVertexId)
        }
        for surface in activePersistedSurfaces where selection.selectedSurfaceIds.contains(surface.id) {
            ids.formUnion(surface.vertexIds)
        }
        return ids
    }

    private func applySelectionMove(delta: CGSize) {
        for (vertexId, original) in selectionMoveOriginalVertices {
            guard var vertex = activeVertex(byId: vertexId) else { continue }
            vertex.position = CGPoint(
                x: original.x + delta.width,
                y: original.y + delta.height
            )
            activeUpdateVertex(vertex)
        }
        for vertexId in selectionMoveOriginalVertices.keys {
            recalculateEdgeDimensions(connectedTo: vertexId)
        }
    }

    /// A single snap proposal evaluated during a selection move — a 1-DOF
    /// linear constraint pinning `delta · normal == offset`. Snaps used to be
    /// picked one-at-a-time (the resolver applied grid → parallel → ONE-OF
    /// vertex-OR-edge); this struct lets the resolver collect candidates
    /// from every snap path and apply each compatible one in turn so a
    /// moved selection can lock two independent alignment constraints at
    /// once — e.g. left edge colinear with one wall AND top edge colinear
    /// with another → corner snap.
    private struct SelectionMoveConstraint {
        /// Unit vector. `delta · normal == offset` is the constraint.
        let normal: CGVector
        /// Target value along `normal` for the constrained `delta`.
        let offset: CGFloat
        /// Proximity metric — closest candidates apply first in the resolver.
        let sortDistance: CGFloat
        /// Rendered guide line for the constraint.
        let guide: AlignmentGuide
    }

    private func resolveSelectionMoveDelta(_ rawDelta: CGSize) -> (delta: CGSize, guides: [AlignmentGuide]) {
        guard drawingData.config.snappingEnabled else {
            return (rawDelta, [])
        }

        // Baseline — snap the anchor vertex to grid. Constraints below
        // refine the axes they lock; any axis left free keeps this value.
        var delta = gridSnappedSelectionDelta(rawDelta)

        var candidates: [SelectionMoveConstraint] = []
        candidates.append(contentsOf: vertexSnappedSelectionDelta(baseline: delta))
        candidates.append(contentsOf: edgeSnappedSelectionDelta(baseline: delta))
        candidates.append(contentsOf: parallelSnappedSelectionDelta(rawDelta: rawDelta))
        candidates.sort { $0.sortDistance < $1.sortDistance }

        // Two independent 1-DOF locks fully pin the 2D delta (solved via a
        // 2x2 system below). Further candidates whose normal is parallel to
        // an existing lock are redundant if consistent or conflicting if
        // not — either way the closer one already applied, so skip them.
        var locks: [(normal: CGVector, offset: CGFloat)] = []
        var guides: [AlignmentGuide] = []
        for candidate in candidates {
            if locks.count >= 2 { break }
            if Self.isParallelToAnyLock(candidate.normal, locks: locks) { continue }
            delta = Self.applySelectionMoveConstraint(
                currentDelta: delta,
                locks: locks,
                newNormal: candidate.normal,
                newOffset: candidate.offset
            )
            locks.append((candidate.normal, candidate.offset))
            guides.append(candidate.guide)
        }

        return (delta, guides)
    }

    private func gridSnappedSelectionDelta(_ rawDelta: CGSize) -> CGSize {
        guard let anchor = selectionMoveOriginalVertices
            .sorted(by: { $0.key < $1.key })
            .first?.value else { return rawDelta }
        let movedAnchor = CGPoint(x: anchor.x + rawDelta.width, y: anchor.y + rawDelta.height)
        let snapped = SnapEngine.snapToGrid(movedAnchor, gridSpacing: lengthSnapInCanvasPoints())
        return CGSize(width: snapped.x - anchor.x, height: snapped.y - anchor.y)
    }

    /// Constraints proposing that the move is parallel to one of the
    /// drawing's edges — `delta` perpendicular component to the edge
    /// direction must be zero. One candidate per qualifying edge so the
    /// accumulator can pick the closest and (if independent normals)
    /// compound a second on a different free axis.
    private func parallelSnappedSelectionDelta(rawDelta: CGSize) -> [SelectionMoveConstraint] {
        let length = hypot(rawDelta.width, rawDelta.height)
        guard length > 0 else { return [] }
        let threshold = CGFloat(max(8.0, drawingData.config.endpointSnapRadius * 0.35))

        var results: [SelectionMoveConstraint] = []
        for edge in activeEdges {
            guard let start = activeVertex(byId: edge.startVertexId),
                  let end = activeVertex(byId: edge.endVertexId) else { continue }
            let dx = end.position.x - start.position.x
            let dy = end.position.y - start.position.y
            let edgeLen = hypot(dx, dy)
            guard edgeLen > 0 else { continue }
            // Unit perpendicular to the edge — the move's component along
            // this normal is what we want to zero out.
            let nx = -dy / edgeLen
            let ny =  dx / edgeLen
            let residual = abs(rawDelta.width * nx + rawDelta.height * ny)
            guard residual <= threshold else { continue }
            results.append(SelectionMoveConstraint(
                normal: CGVector(dx: nx, dy: ny),
                offset: 0,
                sortDistance: residual,
                guide: AlignmentGuide(
                    from: start.position,
                    to: end.position,
                    type: .parallel,
                    referenceLabel: "\u{2225}"
                )
            ))
        }
        return results
    }

    /// Constraints from the closest moved-vertex ↔ static-vertex pair in
    /// snap range. Returned as TWO axis-decomposed 1-DOF constraints (one
    /// for X-align, one for Y-align) — the resolver applies both when
    /// nothing else has locked the axes (= exact landing on the static
    /// vertex), or just the free axis when an edge snap has already locked
    /// the other (= the moved vertex aligns to the static one on one axis,
    /// to whatever the edge snap dictates on the other).
    private func vertexSnappedSelectionDelta(baseline: CGSize) -> [SelectionMoveConstraint] {
        let movingIds = Set(selectionMoveOriginalVertices.keys)
        let staticVertices = activeVertices.filter { !movingIds.contains($0.id) }
        guard !staticVertices.isEmpty else { return [] }

        var best: (distance: Double, original: CGPoint, moved: CGPoint, target: CGPoint)?
        for original in selectionMoveOriginalVertices.values {
            let moved = CGPoint(x: original.x + baseline.width, y: original.y + baseline.height)
            for target in staticVertices {
                let distance = SnapEngine.distance(moved, target.position)
                guard distance <= drawingData.config.endpointSnapRadius else { continue }
                if best == nil || distance < best!.distance {
                    best = (distance, original, moved, target.position)
                }
            }
        }
        guard let best else { return [] }

        let dist = CGFloat(best.distance)
        let xGuide = AlignmentGuide(
            from: CGPoint(x: best.target.x, y: min(best.target.y, best.moved.y) - 20),
            to:   CGPoint(x: best.target.x, y: max(best.target.y, best.moved.y) + 20),
            type: .vertical,
            referenceLabel: nil
        )
        let yGuide = AlignmentGuide(
            from: CGPoint(x: min(best.target.x, best.moved.x) - 20, y: best.target.y),
            to:   CGPoint(x: max(best.target.x, best.moved.x) + 20, y: best.target.y),
            type: .horizontal,
            referenceLabel: nil
        )
        return [
            SelectionMoveConstraint(
                normal: CGVector(dx: 1, dy: 0),
                offset: best.target.x - best.original.x,
                sortDistance: dist,
                guide: xGuide
            ),
            SelectionMoveConstraint(
                normal: CGVector(dx: 0, dy: 1),
                offset: best.target.y - best.original.y,
                sortDistance: dist,
                guide: yGuide
            ),
        ]
    }

    /// Constraints proposing that a moved vertex lands on the infinite
    /// line of a static edge. Gated by proximity to the rendered SEGMENT
    /// (so we don't snap to a static edge's invisible extension way off
    /// canvas), but the constraint itself snaps to the line so a moved
    /// edge can be exactly colinear with the static edge even past its
    /// endpoints. One candidate per (moving vertex, static edge) pair in
    /// range — the resolver compounds two independent-normal candidates
    /// for the bug's stated "two edges colinear simultaneously" case.
    private func edgeSnappedSelectionDelta(baseline: CGSize) -> [SelectionMoveConstraint] {
        let movingIds = Set(selectionMoveOriginalVertices.keys)
        var results: [SelectionMoveConstraint] = []
        for (_, original) in selectionMoveOriginalVertices {
            let moved = CGPoint(
                x: original.x + baseline.width,
                y: original.y + baseline.height
            )
            for edge in activeEdges {
                guard !movingIds.contains(edge.startVertexId),
                      !movingIds.contains(edge.endVertexId),
                      let start = activeVertex(byId: edge.startVertexId),
                      let end = activeVertex(byId: edge.endVertexId) else { continue }
                let dx = end.position.x - start.position.x
                let dy = end.position.y - start.position.y
                let edgeLen = hypot(dx, dy)
                guard edgeLen > 0 else { continue }
                let projection = Self.closestPoint(
                    onSegmentFrom: start.position,
                    to: end.position,
                    point: moved
                )
                let segmentDistance = SnapEngine.distance(moved, projection)
                guard segmentDistance <= drawingData.config.endpointSnapRadius else { continue }
                let nx = -dy / edgeLen
                let ny =  dx / edgeLen
                let offset = (start.position.x - original.x) * nx
                           + (start.position.y - original.y) * ny
                results.append(SelectionMoveConstraint(
                    normal: CGVector(dx: nx, dy: ny),
                    offset: offset,
                    sortDistance: CGFloat(segmentDistance),
                    guide: AlignmentGuide(
                        from: start.position,
                        to: end.position,
                        type: .parallel,
                        referenceLabel: nil
                    )
                ))
            }
        }
        return results
    }

    /// Apply one 1-DOF constraint `(newNormal, newOffset)` to `currentDelta`
    /// given the already-applied `locks`. With zero locks, shift along
    /// `newNormal` to satisfy the new constraint. With one lock, solve the
    /// 2x2 system so BOTH the prior and the new constraint hold — this is
    /// the compounding step that pins the corner. Two locks already pin
    /// `delta` fully; further refinement is a no-op.
    private static func applySelectionMoveConstraint(
        currentDelta: CGSize,
        locks: [(normal: CGVector, offset: CGFloat)],
        newNormal: CGVector,
        newOffset: CGFloat
    ) -> CGSize {
        let n = newNormal
        let c = newOffset
        switch locks.count {
        case 0:
            let current = currentDelta.width * n.dx + currentDelta.height * n.dy
            let shift = c - current
            return CGSize(
                width: currentDelta.width + shift * n.dx,
                height: currentDelta.height + shift * n.dy
            )
        case 1:
            let n0 = locks[0].normal
            let c0 = locks[0].offset
            let det = n0.dx * n.dy - n.dx * n0.dy
            // Caller filters parallel constraints upstream so this is a
            // numeric safety net for floating-point-degenerate cases.
            guard abs(det) > 1e-6 else { return currentDelta }
            let dx = (c0 * n.dy - c * n0.dy) / det
            let dy = (n0.dx * c - n.dx * c0) / det
            return CGSize(width: dx, height: dy)
        default:
            return currentDelta
        }
    }

    /// True when `normal` is parallel to any already-applied lock. Two
    /// unit normals are parallel when their cross product magnitude is
    /// near zero — the 1e-3 threshold catches numerical degeneracies
    /// without rejecting genuinely independent directions.
    private static func isParallelToAnyLock(
        _ normal: CGVector,
        locks: [(normal: CGVector, offset: CGFloat)]
    ) -> Bool {
        for lock in locks {
            let cross = normal.dx * lock.normal.dy - normal.dy * lock.normal.dx
            if abs(cross) < 1e-3 { return true }
        }
        return false
    }

    private static func closestPoint(onSegmentFrom start: CGPoint, to end: CGPoint, point: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return start }
        let rawT = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(max(rawT, 0), 1)
        return CGPoint(x: start.x + dx * t, y: start.y + dy * t)
    }

    /// Recalculate dimension values for edges connected to a vertex (after drag/move).
    /// `.scale` edges are recomputed automatically. Manual / laser / AR edges
    /// preserve their user-typed value but are flagged `dimensionStale = true`
    /// when the new geometry would yield a meaningfully different length, so
    /// the renderer can surface a "this no longer matches the drawn length" warning.
    private func recalculateEdgeDimensions(connectedTo vertexId: String) {
        let staleThresholdInches: Double = 0.5  // ignore sub-half-inch drift to avoid false alarms
        for i in activeEdges.indices {
            let edge = activeEdges[i]
            guard edge.startVertexId == vertexId || edge.endVertexId == vertexId else { continue }
            guard let start = activeVertex(byId: edge.startVertexId),
                  let end = activeVertex(byId: edge.endVertexId) else { continue }
            let canvasDistance = SnapEngine.distance(start.position, end.position)

            if edge.dimensionSource == .scale {
                if let scale = drawingData.scaleFactor, scale > 0 {
                    activeEdges[i].dimension = canvasDistance / scale
                } else {
                    // Bug a7437d68 follow-up — vertex drags routed through this
                    // recompute were storing raw canvas-points labelled as
                    // inches, the same pre-fix behaviour endLine had. So a
                    // freshly-drawn 5' line (correctly stored by endLine via
                    // prescaleFallbackScale) became 10' the moment a vertex
                    // was nudged. Apply the same prescale divisor here so all
                    // pre-scale dimension writes stay consistent and match
                    // what the live drag readout shows.
                    activeEdges[i].dimension = canvasDistance / DeckBuilderViewModel.prescaleFallbackScale
                }
                activeEdges[i].dimensionStale = false
            } else {
                // User-set source — keep their value but flag drift.
                guard let typed = edge.dimension,
                      let scale = drawingData.scaleFactor, scale > 0 else {
                    activeEdges[i].dimensionStale = false
                    continue
                }
                let drawnInches = canvasDistance / scale
                activeEdges[i].dimensionStale = abs(drawnInches - typed) >= staleThresholdInches
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
        // Any explicit retype/measure is the user reaffirming the dimension —
        // clear any "doesn't match drawn length" warning the previous drag set.
        edge.dimensionStale = false
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
        setEdgeType([edgeId], type: type)
    }

    /// Apply an edge type to every edge in `edgeIds` as ONE atomic action — a
    /// single undo snapshot and a single save, mirroring
    /// `assignItemToSelectedEdges`. The assignment wheel and the Properties
    /// sheet both route multi-edge type changes here so "mark these as house
    /// edge" lands on the whole selection, not just one edge.
    func setEdgeType(_ edgeIds: [String], type: EdgeType) {
        let ids = edgeIds.filter { activeEdge(byId: $0) != nil }
        guard !ids.isEmpty else { return }
        pushUndo("set edge type")
        for id in ids {
            guard var edge = activeEdge(byId: id) else { continue }
            edge.edgeType = type
            // House edge and deck-edge railing are mutually exclusive. House
            // edges carry house cladding only; deck edges may carry railing/
            // parapet configuration. Clearing the invalid side here keeps old
            // saved payloads from leaking into renderers and estimates.
            if type == .houseEdge {
                edge.railingConfig = nil
            } else {
                edge.houseEdgeMaterial = nil
            }
            activeUpdateEdge(edge)
        }
        hapticMedium()
        // Confirm multi-edge applies hit the whole selection — single-edge
        // changes are self-evident on the canvas and stay quiet.
        if ids.count > 1 {
            let label = type == .houseEdge ? "House edge" : "Deck edge"
            showAssignmentConfirmation("\(label) applied to \(ids.count) edges")
        }
        save()
    }

    /// Set the cladding material on a house edge. Bug 3d72ce0b — drives the
    /// 2D hatch color, 3D wall fill, and house-edge label. No-op when the
    /// edge is not a house edge.
    func setHouseEdgeMaterial(_ edgeId: String, material: HouseEdgeMaterial?) {
        setHouseEdgeMaterial([edgeId], material: material)
    }

    func setHouseEdgeMaterial(_ edgeIds: [String], material: HouseEdgeMaterial?) {
        let ids = edgeIds.filter {
            guard let edge = activeEdge(byId: $0) else { return false }
            return edge.edgeType == .houseEdge
        }
        guard !ids.isEmpty else { return }
        pushUndo("set house cladding")
        for id in ids {
            guard var edge = activeEdge(byId: id) else { continue }
            edge.houseEdgeMaterial = material
            activeUpdateEdge(edge)
        }
        if ids.count > 1 {
            let label = material?.displayName ?? "Cladding cleared"
            showAssignmentConfirmation("\(label) applied to \(ids.count) house edges")
        }
        save()
        ToastCenter.shared.present(Feedback.Deck.houseEdgeMaterialSet)
    }

    func setRailing(_ edgeId: String, config: RailingConfig?) {
        setRailing([edgeId], config: config)
    }

    func setRailing(_ edgeIds: [String], config: RailingConfig?) {
        let ids = edgeIds.filter {
            guard let edge = activeEdge(byId: $0) else { return false }
            return config == nil || edge.edgeType == .deckEdge
        }
        guard !ids.isEmpty else { return }
        pushUndo("set railing")
        for id in ids {
            guard var edge = activeEdge(byId: id) else { continue }
            edge.railingConfig = config
            activeUpdateEdge(edge)
        }
        if ids.count > 1, let config {
            showAssignmentConfirmation("\(config.railingType.displayName) applied to \(ids.count) edges")
        }
        save()
        ToastCenter.shared.present(Feedback.Deck.railingApplied)
    }

    func setRailingWallMaterial(_ edgeId: String, material: HouseEdgeMaterial) {
        setRailingWallMaterial([edgeId], material: material)
    }

    func setRailingWallMaterial(_ edgeIds: [String], material: HouseEdgeMaterial) {
        let ids = edgeIds.filter {
            guard let edge = activeEdge(byId: $0),
                  edge.edgeType == .deckEdge,
                  edge.railingConfig?.railingType == .parapetWall else { return false }
            return true
        }
        guard !ids.isEmpty else { return }
        pushUndo("set parapet finish")
        for id in ids {
            guard var edge = activeEdge(byId: id),
                  var railing = edge.railingConfig else { continue }
            railing.wallMaterial = material
            edge.railingConfig = railing
            activeUpdateEdge(edge)
        }
        if ids.count > 1 {
            showAssignmentConfirmation("\(material.displayName) applied to \(ids.count) parapet edges")
        }
        save()
        ToastCenter.shared.present(Feedback.Deck.wallMaterialSet)
    }

    func setStairs(_ edgeId: String, config: StairConfig?) {
        guard var edge = activeEdge(byId: edgeId) else { return }
        pushUndo("set stairs")
        edge.stairConfig = config
        activeUpdateEdge(edge)
        save()
    }

    // MARK: - Catalog metadata (deck-catalog integration spec § 4.3)

    /// Updates the catalog metadata vocabulary fields on a railing config
    /// without touching the rest of it. Each parameter is optional so the
    /// caller can change a single field without re-supplying the others.
    /// No-op when the edge has no railing config.
    func setRailingMetadata(
        edgeId: String,
        color: String? = nil,
        mountType: String? = nil,
        mountSurface: String? = nil,
        postHeight: Double? = nil
    ) {
        guard var edge = activeEdge(byId: edgeId), var railing = edge.railingConfig else { return }
        pushUndo("set railing metadata")
        if let color { railing.color = color }
        if let mountType { railing.mountType = mountType }
        if let mountSurface { railing.mountSurface = mountSurface }
        if let postHeight { railing.postHeight = postHeight }
        edge.railingConfig = railing
        activeUpdateEdge(edge)
        save()
        ToastCenter.shared.present(Feedback.Deck.railingUpdated)
    }

    /// Updates the catalog metadata vocabulary fields on a stair config.
    /// No-op when the edge has no stair config.
    func setStairMetadata(
        edgeId: String,
        color: String? = nil,
        mountType: String? = nil
    ) {
        guard var edge = activeEdge(byId: edgeId), var stair = edge.stairConfig else { return }
        pushUndo("set stair metadata")
        if let color { stair.color = color }
        if let mountType { stair.mountType = mountType }
        edge.stairConfig = stair
        activeUpdateEdge(edge)
        save()
    }

    /// Sets `color` on every currently-selected surface. Falls back to
    /// the active footprint when no surface is selected (mirrors
    /// `assignItemToFootprint`'s legacy fallback). DEC-CAT-1.
    func setColorOnSelectedSurfaces(_ color: String) {
        let targetIds = selection.selectedSurfaceIds
        guard !targetIds.isEmpty else { return }
        pushUndo("set surface color")
        var surfaces = activePersistedSurfaces
        for i in surfaces.indices where targetIds.contains(surfaces[i].id) {
            surfaces[i].color = color
        }
        activePersistedSurfaces = surfaces
        save()
    }

    /// Sets `boardMaterial` on every currently-selected surface.
    func setMaterialOnSelectedSurfaces(_ material: String) {
        let targetIds = selection.selectedSurfaceIds
        guard !targetIds.isEmpty else { return }
        pushUndo("set surface material")
        var surfaces = activePersistedSurfaces
        for i in surfaces.indices where targetIds.contains(surfaces[i].id) {
            surfaces[i].boardMaterial = material
        }
        activePersistedSurfaces = surfaces
        save()
    }

    /// Public, multi-level-aware accessor for an edge by id. Used by views
    /// that render details about a selected edge regardless of which level
    /// it lives on. Returns nil when the id can't be located in any
    /// active context.
    func findEdge(byId id: String) -> DeckEdge? {
        if isMultiLevel {
            if let active = activeLevel, let e = active.edge(byId: id) { return e }
            for level in drawingData.levels {
                if let e = level.edge(byId: id) { return e }
            }
            return nil
        }
        return drawingData.edge(byId: id)
    }

    /// Public, multi-level-aware accessor for a persisted surface by id.
    func findSurface(byId id: String) -> DeckSurface? {
        if isMultiLevel {
            if let active = activeLevel, let s = active.surfaces.first(where: { $0.id == id }) { return s }
            for level in drawingData.levels {
                if let s = level.surfaces.first(where: { $0.id == id }) { return s }
            }
            return nil
        }
        return drawingData.surfaces.first(where: { $0.id == id })
    }

    /// Converts the current face selection into measured vinyl inputs.
    /// The order sheet should not re-detect or infer geometry on its own:
    /// it gets the same reconciled persisted surfaces the canvas and
    /// material tools use, matched back to current detected face polygons.
    func selectedVinylOrderSurfaceInputs() -> [VinylOrderSurfaceInput] {
        vinylOrderSurfaceInputs(scope: .selectedSurfaces)
    }

    func allVinylOrderSurfaceInputs() -> [VinylOrderSurfaceInput] {
        vinylOrderSurfaceInputs(scope: .allSurfaces)
    }

    func vinylOrderSurfaceInputs(scope: VinylOrderSurfaceScope) -> [VinylOrderSurfaceInput] {
        reconcileSurfaces()
        guard let scale = vinylOrderEffectiveScale else { return [] }
        let selectedIds = selection.selectedSurfaceIds
        if scope == .selectedSurfaces, selectedIds.isEmpty { return [] }

        if isMultiLevel {
            return drawingData.levels.flatMap { level in
                vinylOrderInputs(
                    persisted: level.surfaces,
                    detected: level.detectedSurfaces,
                    edges: level.edges,
                    selectedIds: scope == .selectedSurfaces ? selectedIds : nil,
                    scale: scale,
                    levelName: level.name
                )
            }
        }

        return vinylOrderInputs(
            persisted: drawingData.surfaces,
            detected: drawingData.detectedSurfaces,
            edges: drawingData.edges,
            selectedIds: scope == .selectedSurfaces ? selectedIds : nil,
            scale: scale,
            levelName: nil
        )
    }

    private func vinylOrderInputs(
        persisted: [DeckSurface],
        detected: [DetectedSurface],
        edges: [DeckEdge],
        selectedIds: Set<String>?,
        scale: Double,
        levelName: String?
    ) -> [VinylOrderSurfaceInput] {
        persisted.enumerated().compactMap { index, surface in
            if let selectedIds, !selectedIds.contains(surface.id) { return nil }
            guard let face = detectedSurface(for: surface, in: detected) else { return nil }
            let trimmedLabel = surface.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = trimmedLabel.flatMap { $0.isEmpty ? nil : $0 } ?? "Surface \(index + 1)"
            return VinylOrderSurfaceInput(
                id: surface.id,
                label: label,
                levelName: levelName,
                positions: face.positions,
                scaleFactor: scale,
                edges: vinylOrderSurfaceEdges(for: face, edges: edges)
            )
        }
    }

    private func vinylOrderSurfaceEdges(
        for face: DetectedSurface,
        edges: [DeckEdge]
    ) -> [VinylOrderSurfaceEdge] {
        guard face.vertexIds.count == face.positions.count, face.vertexIds.count >= 2 else { return [] }

        return face.vertexIds.indices.map { index in
            let nextIndex = (index + 1) % face.vertexIds.count
            let startId = face.vertexIds[index]
            let endId = face.vertexIds[nextIndex]
            let matchingEdge = edges.first {
                ($0.startVertexId == startId && $0.endVertexId == endId) ||
                    ($0.startVertexId == endId && $0.endVertexId == startId)
            }

            return VinylOrderSurfaceEdge(
                id: matchingEdge?.id ?? "\(startId)-\(endId)",
                start: face.positions[index],
                end: face.positions[nextIndex],
                edgeType: matchingEdge?.edgeType ?? .deckEdge,
                label: matchingEdge?.label
            )
        }
    }

    private func detectedSurface(for persisted: DeckSurface, in detected: [DetectedSurface]) -> DetectedSurface? {
        if let exact = detected.first(where: { Set($0.vertexIds) == persisted.vertexIds }) {
            return exact
        }

        var best: (surface: DetectedSurface, jaccard: Double)?
        for face in detected {
            let faceIds = Set(face.vertexIds)
            let intersection = faceIds.intersection(persisted.vertexIds).count
            let union = faceIds.union(persisted.vertexIds).count
            guard union > 0 else { continue }
            let score = Double(intersection) / Double(union)
            if score > (best?.jaccard ?? -1) {
                best = (face, score)
            }
        }
        guard let best, best.jaccard >= SurfaceReconciler.rebindThreshold else { return nil }
        return best.surface
    }

    /// Scale used for vinyl ordering. Vinyl is a stricter consumer than the
    /// editor's area/perimeter readout or estimate generation: a cut-to-size
    /// order can't tolerate a drawing whose typed dimensions disagree with the
    /// drawn geometry. So any stale edge blocks the order, and — before the
    /// user has calibrated `scaleFactor` — the prescale fallback is trusted
    /// only while every edge is still scale-derived (no user-typed override in
    /// play). Once the drawing clears those bars the scale is simply
    /// `drawingData.effectiveScaleFactor` (the calibrated factor, or the
    /// prescale fallback the canvas already draws every edge at).
    var vinylOrderEffectiveScale: Double? {
        guard !drawingData.allEdges.contains(where: \.dimensionStale) else { return nil }
        if (drawingData.scaleFactor ?? 0) <= 0, !canUsePrescaleFallbackForVinylOrder {
            return nil
        }
        return drawingData.effectiveScaleFactor
    }

    private var canUsePrescaleFallbackForVinylOrder: Bool {
        let edges = drawingData.allEdges
        guard !edges.isEmpty else { return false }
        return edges.allSatisfy { edge in
            edge.dimensionSource == .scale && !edge.dimensionStale
        }
    }

    /// Public, multi-level-aware accessor for a vertex by id. Mirrors
    /// `findEdge` / `findSurface` — checks the active level first, then any
    /// other level, then the top-level array. Used by PropertySheet so the
    /// vertex-properties section actually renders in multi-level designs
    /// (the top-level vertices array is empty there). Bug 6d1c0a2a.
    func findVertex(byId id: String) -> DeckVertex? {
        if isMultiLevel {
            if let active = activeLevel, let v = active.vertex(byId: id) { return v }
            for level in drawingData.levels {
                if let v = level.vertex(byId: id) { return v }
            }
            return nil
        }
        return drawingData.vertex(byId: id)
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

    // MARK: - Footprint / Surface Properties

    /// Assigns an item to every currently-selected surface. Falls back to
    /// the legacy single-footprint store only if no surface is selected
    /// (covers callers that haven't migrated yet — should be unreachable
    /// in normal flows since the picker only opens when a surface or edge
    /// is selected). DECK-NEW-1 follow-up.
    func assignItemToFootprint(_ item: AssignedItem) {
        pushUndo("assign surface item")
        let targetIds = selection.selectedSurfaceIds
        if targetIds.isEmpty {
            var fp = activeFootprint
            fp.assignedItems.append(item)
            activeFootprint = fp
        } else {
            var surfaces = activePersistedSurfaces
            for i in surfaces.indices where targetIds.contains(surfaces[i].id) {
                surfaces[i].assignedItems.append(item)
            }
            activePersistedSurfaces = surfaces
        }
        hapticLight()
        let count = max(targetIds.count, 1)
        let suffix = count == 1 ? "" : " ×\(count)"
        showAssignmentConfirmation("Surface: \(item.name)\(suffix)")
        save()
    }

    /// Removes an item from every selected surface and from the legacy
    /// footprint store (so an item that survived from a pre-migration
    /// drawing also clears).
    func removeFootprintItem(_ itemId: String) {
        pushUndo("remove surface item")
        let targetIds = selection.selectedSurfaceIds
        if !targetIds.isEmpty {
            var surfaces = activePersistedSurfaces
            for i in surfaces.indices where targetIds.contains(surfaces[i].id) {
                surfaces[i].assignedItems.removeAll { $0.id == itemId }
            }
            activePersistedSurfaces = surfaces
        }
        var fp = activeFootprint
        fp.assignedItems.removeAll { $0.id == itemId }
        activeFootprint = fp
        save()
        ToastCenter.shared.present(Feedback.Deck.itemRemoved)
    }

    /// Sets a label on every currently-selected surface. Pass `nil` or
    /// empty to clear. DECK-NEW-1 follow-up.
    func setLabelOnSelectedSurfaces(_ raw: String?) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let targetIds = selection.selectedSurfaceIds
        guard !targetIds.isEmpty else { return }
        pushUndo("label surface")
        var surfaces = activePersistedSurfaces
        for i in surfaces.indices where targetIds.contains(surfaces[i].id) {
            surfaces[i].label = value
        }
        activePersistedSurfaces = surfaces
        save()
        ToastCenter.shared.present(Feedback.Deck.surfacesLabeled)
    }

    /// Sets the legacy footprint label — used from the property sheet so the
    /// user can name the active deck surface ("BBQ pad", "Hot tub deck") when
    /// no per-surface ids are selected (single closed shape). Bug 4a03f507.
    func setLabelOnActiveFootprint(_ raw: String?) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        pushUndo("label footprint")
        var fp = activeFootprint
        fp.label = value
        activeFootprint = fp
        save()
        ToastCenter.shared.present(Feedback.Deck.footprintLabeled)
    }

    /// Optional per-edge label. The model stores it on `DeckEdge.label`
    /// — pre-existing — but there was no setter that re-routes through
    /// `activeUpdateEdge` + undo/save. Bug 4a03f507.
    func setEdgeLabel(_ edgeId: String, label raw: String?) {
        guard var edge = activeEdge(byId: edgeId) else { return }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        pushUndo("label edge")
        edge.label = value
        activeUpdateEdge(edge)
        save()
        ToastCenter.shared.present(Feedback.Deck.edgeLabeled)
    }

    /// Creates a fresh level (migrating from single-level if needed) and
    /// hands the current surface selection to it in one atomic step. Wraps
    /// addLevel + moveSelectedSurfacesToLevel because addLevel clears
    /// selection — calling the two in sequence at the UI layer would lose
    /// the surface ids mid-flight. Capped at 3 levels per existing addLevel
    /// constraint; no-op when at the cap. Bug ee787f29 follow-up.
    func moveSelectedSurfacesToNewLevel() {
        let targetIds = selection.selectedSurfaceIds
        guard !targetIds.isEmpty else { return }
        guard drawingData.levels.count < 3 || !drawingData.isMultiLevel else { return }

        pushUndo("split to new level")
        if !drawingData.isMultiLevel {
            drawingData.migrateToMultiLevel()
        }
        let usedColors = drawingData.levels.map { $0.displayColor }
        let newLevel = DeckLevel(
            name: "Level \(drawingData.levels.count + 1)",
            displayColor: LevelColor.nextAvailable(excluding: usedColors),
            sortOrder: drawingData.levels.count
        )
        drawingData.levels.append(newLevel)
        let destinationIndex = drawingData.levels.count - 1

        var moved: [DeckSurface] = []
        for li in drawingData.levels.indices where li != destinationIndex {
            var surfaces = drawingData.levels[li].surfaces
            let migrated = surfaces.filter { targetIds.contains($0.id) }
            if !migrated.isEmpty {
                surfaces.removeAll { targetIds.contains($0.id) }
                drawingData.levels[li].surfaces = surfaces
                moved.append(contentsOf: migrated)
            }
        }
        if !moved.isEmpty {
            drawingData.levels[destinationIndex].surfaces.append(contentsOf: moved)
        }

        activeLevelIndex = destinationIndex
        selection.clear()
        hapticMedium()
        save()
        ToastCenter.shared.present(Feedback.Deck.levelCreatedSurfaces)
    }

    /// Reassigns every currently-selected surface to a different level.
    /// Used by DECK-NEW-4 (selection overhaul). Detected surfaces are
    /// identified by their stable persisted id; the persisted record is
    /// removed from the source level and inserted on the destination.
    /// Geometry (vertices/edges) does NOT move — only the per-surface
    /// payload (assigned items + label).
    func moveSelectedSurfacesToLevel(at destinationIndex: Int) {
        guard isMultiLevel,
              destinationIndex >= 0,
              destinationIndex < drawingData.levels.count else { return }
        let targetIds = selection.selectedSurfaceIds
        guard !targetIds.isEmpty else { return }
        pushUndo("move surface to level")

        var moved: [DeckSurface] = []
        for li in drawingData.levels.indices where li != destinationIndex {
            var surfaces = drawingData.levels[li].surfaces
            let migrated = surfaces.filter { targetIds.contains($0.id) }
            if !migrated.isEmpty {
                surfaces.removeAll { targetIds.contains($0.id) }
                drawingData.levels[li].surfaces = surfaces
                moved.append(contentsOf: migrated)
            }
        }
        if !moved.isEmpty {
            drawingData.levels[destinationIndex].surfaces.append(contentsOf: moved)
        }
        hapticMedium()
        save()
        ToastCenter.shared.present(Feedback.Deck.surfacesMoved)
    }

    /// Moves every selected edge (and its bounding vertices) to a different
    /// level. The user explicitly called out that this should invalidate any
    /// surface on the source level whose perimeter is broken by the move —
    /// done here by dropping every surface that referenced any vertex we
    /// migrated. Bug 6d1c0a2a follow-up.
    ///
    /// Vertices are migrated when no remaining edge on the source level
    /// references them. If a vertex is still bounded by another edge on the
    /// source level (it sits at a fork between moved + non-moved edges) it
    /// stays put, and the moved edge ends up with a phantom endpoint —
    /// rejected up front so we don't leave broken geometry behind.
    func moveSelectedEdgesToLevel(at destinationIndex: Int) {
        guard isMultiLevel,
              destinationIndex >= 0,
              destinationIndex < drawingData.levels.count else { return }
        let edgeIds = selection.selectedEdgeIds
        guard !edgeIds.isEmpty else { return }
        pushUndo("move edges to level")
        performEdgeLevelMigration(edgeIds: edgeIds, destinationIndex: destinationIndex)
        selection.clear()
        hapticMedium()
        save()
        ToastCenter.shared.present(Feedback.Deck.edgesMoved)
    }

    /// Combined add-level + move-edges-there. Same atomic pattern as
    /// `moveSelectedSurfacesToNewLevel` so the selection survives the
    /// level-clear inside `addLevel`. Capped at 3 levels.
    func moveSelectedEdgesToNewLevel() {
        let edgeIds = selection.selectedEdgeIds
        guard !edgeIds.isEmpty else { return }
        guard drawingData.levels.count < 3 || !drawingData.isMultiLevel else { return }

        pushUndo("split edges to new level")
        if !drawingData.isMultiLevel {
            drawingData.migrateToMultiLevel()
        }
        let usedColors = drawingData.levels.map { $0.displayColor }
        let newLevel = DeckLevel(
            name: "Level \(drawingData.levels.count + 1)",
            displayColor: LevelColor.nextAvailable(excluding: usedColors),
            sortOrder: drawingData.levels.count
        )
        drawingData.levels.append(newLevel)
        let destinationIndex = drawingData.levels.count - 1

        performEdgeLevelMigration(edgeIds: edgeIds, destinationIndex: destinationIndex)

        activeLevelIndex = destinationIndex
        selection.clear()
        hapticMedium()
        save()
        ToastCenter.shared.present(Feedback.Deck.levelCreatedEdges)
    }

    /// Worker for both edge-level migration entry points. Walks every level
    /// (except destination), peels off the selected edges + any vertex that
    /// only those edges referenced, then drops surfaces whose vertexIds are
    /// no longer fully present in the source level. Surfaces with a broken
    /// perimeter cease to exist as DeckSurface rows — the underlying edges
    /// at the destination still form whatever loop the operator now intends.
    private func performEdgeLevelMigration(edgeIds: Set<String>, destinationIndex: Int) {
        for li in drawingData.levels.indices where li != destinationIndex {
            var level = drawingData.levels[li]
            let movedEdges = level.edges.filter { edgeIds.contains($0.id) }
            guard !movedEdges.isEmpty else { continue }

            let movedEdgeIds = Set(movedEdges.map { $0.id })
            let remainingEdges = level.edges.filter { !movedEdgeIds.contains($0.id) }

            // Vertex IDs referenced by any moved edge.
            var touchedVertexIds: Set<String> = []
            for e in movedEdges {
                touchedVertexIds.insert(e.startVertexId)
                touchedVertexIds.insert(e.endVertexId)
            }

            // A vertex migrates ONLY when no remaining edge still references
            // it on the source level. Shared-vertex edges (one moves, one
            // stays) leave the vertex behind so the staying edge keeps its
            // anchor — the moved edge's payload still carries its endpoint
            // ids and SurfaceDetector at the destination will treat them as
            // a fresh disconnected segment until the operator wires them up.
            let stillReferencedVertexIds: Set<String> = Set(
                remainingEdges.flatMap { [$0.startVertexId, $0.endVertexId] }
            )
            let migratingVertexIds = touchedVertexIds.subtracting(stillReferencedVertexIds)
            let migratingVertices = level.vertices.filter { migratingVertexIds.contains($0.id) }

            // Drop any surface whose perimeter touches a vertex we just
            // migrated — its bounding cycle is broken. The operator's
            // intended surface (if any) is whatever the destination level's
            // edges + vertices now enclose.
            let invalidatedSurfaceIds = level.surfaces
                .filter { !$0.vertexIds.allSatisfy(stillReferencedVertexIds.contains) }
                .map { $0.id }
            let invalidatedSet = Set(invalidatedSurfaceIds)

            level.edges = remainingEdges
            level.vertices = level.vertices.filter { !migratingVertexIds.contains($0.id) }
            level.surfaces = level.surfaces.filter { !invalidatedSet.contains($0.id) }
            drawingData.levels[li] = level

            drawingData.levels[destinationIndex].edges.append(contentsOf: movedEdges)
            drawingData.levels[destinationIndex].vertices.append(contentsOf: migratingVertices)
        }
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

    /// Bug 5e681032 — snapshot the selected ids BEFORE iterating so any
    /// downstream mutation can't shrink the working set mid-loop. Previously
    /// callers reported only the first selected edge receiving the material;
    /// taking a deterministic snapshot here makes the batch atomic.
    func assignItemToSelectedEdges(_ item: AssignedItem) {
        let edgeIds = selection.selectedEdgeIds.filter { edgeId in
            guard let edge = activeEdge(byId: edgeId) else {
                print("[DeckBuilder] assignItemToSelectedEdges: edge \(edgeId) not found, skipping")
                return false
            }
            return edge.edgeType == .deckEdge
        }
        let count = edgeIds.count
        guard count > 0 else { return }
        pushUndo("batch assign")
        for edgeId in edgeIds {
            guard var edge = activeEdge(byId: edgeId) else {
                print("[DeckBuilder] assignItemToSelectedEdges: edge \(edgeId) not found, skipping")
                continue
            }
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
        ToastCenter.shared.present(Toast(label: "// \(text.uppercased())", tone: .success))
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
        // Footprint can no longer be selected if the polygon just broke open.
        // selection.clear() above resets selectedFootprint to false; calling
        // out the dependency explicitly so the rule survives any future
        // refactor that uses a partial-clear instead of full clear.
        if !activeIsClosed { selection.selectedSurfaceIds.removeAll() }
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
        if !activeIsClosed { selection.selectedSurfaceIds.removeAll() }
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

        // Clear per-surface assignments for any selected surfaces. The
        // surface geometry stays intact (it's defined by the edges), only
        // the materials/label payload is reset.
        if !selection.selectedSurfaceIds.isEmpty {
            var surfaces = activePersistedSurfaces
            for i in surfaces.indices where selection.selectedSurfaceIds.contains(surfaces[i].id) {
                surfaces[i].assignedItems.removeAll()
                surfaces[i].label = nil
            }
            activePersistedSurfaces = surfaces
        }

        var fp = activeFootprint
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

    // MARK: - Selection Narrowing ("Select Only" filter)
    //
    // Narrows the *current* selection to a subset by kind or by edge property.
    // This is distinct from `tapSelectFilter`, which gates which element types
    // can be added to a future selection — these methods operate on what's
    // already selected. Used by the toolbar Filter menu so a multi-type
    // selection can be reduced in one tap (e.g. "Select Only > Picket Rails").

    /// Drop everything except edges from the selection.
    func selectOnlyEdges() {
        selection.selectedVertexIds.removeAll()
        selection.selectedSurfaceIds.removeAll()
        hapticLight()
    }

    /// Drop everything except vertices from the selection.
    func selectOnlyVertices() {
        selection.selectedEdgeIds.removeAll()
        selection.selectedSurfaceIds.removeAll()
        hapticLight()
    }

    /// Drop everything except the surface from the selection.
    func selectOnlySurface() {
        selection.selectedEdgeIds.removeAll()
        selection.selectedVertexIds.removeAll()
        hapticLight()
    }

    /// Narrow `selectedEdgeIds` to those matching the predicate. Vertices and
    /// surface selection are dropped — caller is asking for a specific edge
    /// subset, not a mixed selection.
    func filterSelectedEdges(_ predicate: (DeckEdge) -> Bool) {
        let edges = drawingData.allEdges
        selection.selectedEdgeIds = selection.selectedEdgeIds.filter { id in
            guard let edge = edges.first(where: { $0.id == id }) else { return false }
            return predicate(edge)
        }
        selection.selectedVertexIds.removeAll()
        selection.selectedSurfaceIds.removeAll()
        hapticLight()
    }

    // MARK: - Persistence

    func save() {
        // Reconcile the per-surface assignment store against current
        // geometry before persisting. Idempotent — surfaces with stable
        // vertex membership pass through unchanged. DECK-NEW-1 follow-up.
        reconcileSurfaces()

        isLocallySaved = false
        deckDesign.drawingData = drawingData  // triggers needsSync via setter
        // Insert on first save if the design was created via the blank-canvas
        // path (which defers insertion until there's real geometry to persist).
        // SwiftData rejects insert on an already-inserted model, so check first.
        // Bug 7c2bd6be.
        if deckDesign.modelContext == nil {
            modelContext?.insert(deckDesign)
        }
        do {
            try modelContext?.save()
            isLocallySaved = true
        } catch {
            print("[DeckBuilder] Save failed: \(error)")
            ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
        }

        // Bug ab554b5f — enqueue the change for the offline sync queue so
        // OutboundProcessor pushes it to Supabase on the next push cycle.
        // Without this, the local row's `needsSync` flag flipped on but the
        // server never learned about the deck design. Idempotent — re-queueing
        // the same id is fine (OutboundProcessor coalesces).
        enqueueDeckDesignSync()

        // Bug 2b1f1a9e — first edit on an EXISTING drawing surfaces the
        // autosave prompt (new drawings already auto-enabled it in init).
        // Suppress when called from the autosave timer itself (autosaveEnabled
        // is already true by then, and the guard prevents recursion).
        if !isNewDrawing && !hasPromptedForAutosave && !autosaveEnabled {
            hasPromptedForAutosave = true
            showingAutosavePrompt = true
        }
    }

    /// Records a SyncOperation so the OutboundProcessor pushes the deck
    /// design to Supabase on the next push cycle.
    ///
    /// First call for a never-synced model emits a "create" op carrying the
    /// full DTO shape (every required Supabase column). Subsequent calls emit
    /// "update" ops carrying only the fields that change between edits —
    /// title, drawing_data, thumbnail_url, version, updated_at. The hand-off
    /// to OutboundProcessor's existing `handleDeckDesign` reuses the same
    /// payload-sanitizer + repository routing every other entity uses.
    ///
    /// Safe to call when `syncEngine` is nil (preview / test). The local
    /// SwiftData save still happens — only the network push is skipped.
    /// Bug ab554b5f.
    private func enqueueDeckDesignSync() {
        guard let syncEngine else { return }

        let nowIso = ISO8601DateFormatter().string(from: Date())
        let createdIso = ISO8601DateFormatter().string(from: deckDesign.createdAt)

        // The Supabase `drawing_data` column is jsonb. Encode the struct to a
        // dictionary so JSONSerialization can re-serialize the whole payload
        // and the OutboundProcessor's JSONDecoder.decode(SupabaseDeckDesignDTO)
        // round-trip succeeds. Encoding to JSON-string then re-parsing keeps
        // the conversion isolated to this site (no AnyCodable plumbing
        // anywhere else).
        let drawingJSONString = drawingData.toJSON()
        let drawingObject: Any = (try? JSONSerialization.jsonObject(
            with: Data(drawingJSONString.utf8),
            options: []
        )) ?? [String: Any]()

        if !hasEnqueuedCreate {
            // First push for this id — wire up the full DTO payload so
            // `handleDeckDesign` can decode `SupabaseDeckDesignDTO` and call
            // `repo.create(dto)` directly.
            var payload: [String: Any] = [
                "id": deckDesign.id,
                "company_id": deckDesign.companyId,
                "title": deckDesign.title,
                "drawing_data": drawingObject,
                "version": deckDesign.version,
                "created_at": createdIso,
                "updated_at": nowIso
            ]
            if let projectId = deckDesign.projectId, !projectId.isEmpty {
                payload["project_id"] = projectId
            }
            if let thumbnail = deckDesign.thumbnailURL, !thumbnail.isEmpty {
                payload["thumbnail_url"] = thumbnail
            }
            if let createdBy = deckDesign.createdBy, !createdBy.isEmpty {
                payload["created_by"] = createdBy
            }
            syncEngine.recordOperation(
                entityType: .deckDesign,
                entityId: deckDesign.id,
                operationType: "create",
                changedFields: payload,
                priority: 1
            )
            hasEnqueuedCreate = true
        } else {
            // Update path — only push the fields the user actually edits in
            // this session. drawing_data covers every geometry / config / level
            // change because it's stored as a single jsonb blob.
            var payload: [String: Any] = [
                "title": deckDesign.title,
                "drawing_data": drawingObject,
                "version": deckDesign.version,
                "updated_at": nowIso
            ]
            if let thumbnail = deckDesign.thumbnailURL, !thumbnail.isEmpty {
                payload["thumbnail_url"] = thumbnail
            }
            syncEngine.recordOperation(
                entityType: .deckDesign,
                entityId: deckDesign.id,
                operationType: "update",
                changedFields: payload,
                priority: 1
            )
        }
    }


    func renameDesign(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        deckDesign.title = trimmed
        save()
        ToastCenter.shared.present(Feedback.Deck.designRenamed)
    }

    func clearDesign() {
        pushUndo("clear design")
        drawingData = DeckDrawingData()
        selection.clear()
        editingEdgeId = nil
        editingVertexId = nil
        save()
        hapticMedium()
        ToastCenter.shared.present(Feedback.Deck.designCleared)
    }

    // MARK: - Render + Save Thumbnail

    func renderAndSave() async {
        // Bug 14555d2c — short-circuit when the user is exiting a drawing
        // with no committed geometry. The previous flow always called
        // `save()` (which inserts the deckDesign + enqueues a Supabase
        // create op for an empty record) and then ran the renderer + S3
        // upload (which produces a blank 1024×1024 white PNG and hangs
        // the close-button spinner on the network upload, reading as a
        // crash to the user). For a transient blank canvas there is
        // genuinely nothing to persist or upload — drop everything and
        // return so the dismiss happens immediately.
        let hasGeometry = hasAnyCommittedGeometry
        let isPersisted = deckDesign.modelContext != nil

        if !hasGeometry && !isPersisted {
            return
        }

        // Bug a34a2fbe — persist the drawing FIRST, unconditionally. The
        // previous version gated `save()` behind a successful PNG render +
        // S3 thumbnail upload; if either step failed (renderToPNG returns
        // nil, S3 upload throws, network drops, render runs out of memory)
        // the early return / catch path silently dismissed the deck builder
        // without ever writing the user's drawing to SwiftData. The user
        // then exited to the project's deck tab and saw an empty state for
        // a deck they thought they'd saved — the bug as filed.
        //
        // The thumbnail is a UX nice-to-have (renders the deck card on
        // project lists / portal). The drawing data is the user's actual
        // work. Save the drawing first, then attempt the thumbnail as a
        // best-effort enhancement; thumbnail failure must not block the
        // primary save.
        save()
        if hasGeometry {
            ToastCenter.shared.present(Feedback.Deck.designSaved)
        }

        // Bug 14555d2c — skip the thumbnail render + S3 upload when the
        // drawing has no geometry. The renderer returns a blank white PNG
        // for empty drawings (its inner draw block early-returns but the
        // outer image renderer always emits a buffer), and shipping that
        // to S3 costs a slow network round-trip on the close-button
        // spinner for no user-facing benefit. The persisted record above
        // still captures the cleared state so the deck tab updates.
        guard hasGeometry else { return }

        guard let image = DeckRenderer.renderToPNG(drawingData: drawingData) else {
            print("[DeckBuilder] Thumbnail render returned nil — drawing already saved, skipping S3 upload")
            return
        }

        do {
            let url = try await DeckRenderer.saveToS3(image: image, deckDesign: deckDesign)
            deckDesign.thumbnailURL = url
            // Re-save so thumbnailURL hits the store (and gets enqueued for
            // sync via the setter chain on DeckDesign).
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
            print("[DeckBuilder] Failed to save thumbnail: \(error) — drawing was already persisted by the initial save()")
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
        ToastCenter.shared.present(Toast(
            label: "// \(formatted.uppercased()) — TAP AN EDGE TO APPLY",
            tone: .warning,
            autoDismissAfter: 5
        ))

        bufferTimer?.invalidate()
        bufferTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.bufferedMeasurement = nil
            }
        }
    }

    func applyBufferedMeasurementIfNeeded(toEdge edgeId: String) {
        if let buffered = bufferedMeasurement {
            setEdgeDimension(edgeId, inches: buffered.inches, source: .laser)
            bufferedMeasurement = nil
            bufferTimer?.invalidate()
            hapticLight()
        }
    }

    private func handleLaserError(_ error: String) {
        // Clear the error on the service so it doesn't re-fire
        LaserMeterService.shared.measurementError = nil
        ToastCenter.shared.present(Toast(label: "// LASER ERROR — \(error.uppercased())", tone: .error))
    }

    private func handleConnectionStateChange(_ state: LaserConnectionState) {
        switch state {
        case .reconnecting:
            ToastCenter.shared.present(Toast(
                label: "// LASER DISCONNECTED — RECONNECTING",
                tone: .error,
                autoDismissAfter: 10
            ))

        case .connected:
            ToastCenter.shared.present(Toast(
                label: "// LASER RECONNECTED",
                tone: .success
            ))

        default:
            break
        }
    }

    // MARK: - Estimate & Share

    var canGenerateEstimate: Bool {
        // Require a CLOSED valid polygon so the action affordance matches what
        // the estimate path can actually produce. Otherwise the button enables
        // the moment a railing is assigned to a half-drawn outline, then errors
        // out the moment the user taps it.
        let hasClosedShape: Bool
        if isMultiLevel {
            hasClosedShape = drawingData.levels.contains { level in
                level.isClosed &&
                !PolygonMath.isSelfIntersecting(vertices: level.orderedPositions)
            }
        } else {
            hasClosedShape = drawingData.isClosed &&
                !PolygonMath.isSelfIntersecting(vertices: drawingData.orderedPositions)
        }
        return hasClosedShape &&
            EstimateGeneratorService.hasAssignments(drawingData) &&
            drawingData.allEdges.contains(where: { $0.dimension != nil })
    }

    // MARK: - Catalog merge (deck-catalog spec § 4.5)

    /// Builds the merged line item list for the current design — adapter
    /// pass + legacy pass + de-dupe per spec § 4.5.1. Companies that
    /// haven't configured any `CompanyDefaultProduct` rows fall through
    /// to the legacy path unchanged (adapter returns []; merge passes
    /// legacy through). The result is what the persistence loop in
    /// `generateEstimate()` writes — and what `EstimatePreviewSheet`
    /// renders as the user-facing summary.
    func mergedCatalogLineItems() -> [CatalogEstimateMerger.LineItem] {
        let legacy = EstimateGeneratorService.generateLineItems(from: drawingData)

        guard let context = modelContext else {
            // Without SwiftData (preview / test paths) the adapter can't
            // resolve defaults — fall through to legacy as if no
            // defaults exist.
            return CatalogEstimateMerger.merge(
                adapterItems: [],
                legacyItems: legacy,
                defaultsCovered: []
            )
        }

        let adapter = DesignToEstimateAdapter()
        let raw = adapter.generate(
            design: deckDesign,
            companyId: deckDesign.companyId,
            modelContext: context
        )

        let enriched: [CatalogEstimateMerger.EnrichedAdapterItem] = raw.compactMap { item in
            guard let product = lookupProduct(id: item.productId, in: context) else { return nil }
            return CatalogEstimateMerger.EnrichedAdapterItem(
                raw: item,
                productName: product.name,
                productDescription: product.productDescription,
                unit: legacyUnit(for: product.pricingUnit),
                category: legacyCategory(for: item.componentType),
                taskTypeId: product.taskTypeId
            )
        }

        let defaultsCovered: Set<DesignComponentType> = Set(raw.map { $0.componentType })

        return CatalogEstimateMerger.merge(
            adapterItems: enriched,
            legacyItems: legacy,
            defaultsCovered: defaultsCovered
        )
    }

    /// Resolves a Product by id from SwiftData. Returns nil when the
    /// adapter references a product that's no longer in the local
    /// catalog (rare, but possible if the company deleted it between
    /// the design saving and estimate generation).
    private func lookupProduct(id: String, in context: ModelContext) -> Product? {
        let descriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Maps a Product.pricingUnit to the legacy `unit` string the
    /// estimate persistence path uses on `EstimateLineItem.unit`. Stays
    /// in sync with EstimateGeneratorService's unit vocabulary so the
    /// adapter and legacy paths produce homogeneous-looking line items.
    private func legacyUnit(for pricingUnit: ProductPricingUnit) -> String {
        switch pricingUnit {
        case .each:       return "each"
        case .flatRate:   return "flat"
        case .linearFoot: return "linear ft"
        case .sqft:       return "sq ft"
        case .hour:       return "hour"
        case .day:        return "day"
        }
    }

    /// Maps a `DesignComponentType` to the legacy category bucket the
    /// estimate UI groups by — keeps adapter rows showing up in the
    /// expected category band on the preview / printed estimate.
    private func legacyCategory(for componentType: DesignComponentType) -> String {
        switch componentType {
        case .railing:    return "Railing"
        case .deckBoard:  return "Surface"
        case .stairSet:   return "Stairs"
        case .gate:       return "Other"
        case .postSet:    return "Railing"
        }
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

        // Force a save first so drawingDataJSON carries an up-to-date
        // components projection — the adapter parses that JSON to find
        // the components it should bill against. Deck-catalog spec § 4.5.
        save()

        // Catalog adapter pass + legacy pass + merge per spec § 4.5.1.
        // Companies without `CompanyDefaultProduct` rows fall through to
        // the legacy path unchanged (adapter returns []; merge passes
        // legacy through). Companies with defaults get adapter-driven
        // line items snapshotted with `configured_options` ready for the
        // CutListMaterializer to resolve at install time.
        let mergedItems = mergedCatalogLineItems()
        guard !mergedItems.isEmpty else { return }

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

            // Group merged line items by task type and create parent-child
            // structure. Adapter rows in the merged result carry the
            // configured_options + resolved_unit_price + resolved_options_label
            // snapshot the CutListMaterializer needs at install time;
            // legacy rows leave those fields nil.
            let groups = CatalogEstimateMerger.groupByTaskType(mergedItems, taskTypes: taskTypes)
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
                    let configuredOptionsRaw = child.configuredOptions
                        .flatMap { CatalogEstimateMerger.encodeConfiguredOptions($0) }
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
                        parentLineItemId: parentItem.id,
                        configuredOptions: configuredOptionsRaw,
                        resolvedUnitPrice: child.resolvedUnitPrice,
                        resolvedOptionsLabel: child.resolvedOptionsLabel
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
        // Mirror can3DMode's gating — a self-intersecting outline would
        // overlay the photo with a meaningless polygon shape.
        if isMultiLevel {
            return drawingData.levels.contains { level in
                level.isClosed &&
                level.vertices.count >= 3 &&
                !PolygonMath.isSelfIntersecting(vertices: level.orderedPositions)
            }
        }
        return drawingData.vertices.count >= 3
            && drawingData.isClosed
            && !PolygonMath.isSelfIntersecting(vertices: drawingData.orderedPositions)
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
