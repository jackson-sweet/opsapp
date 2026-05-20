// OPS/OPS/DeckBuilder/Models/DeckGeometry.swift

import Foundation
import SwiftUI

// MARK: - Units & Configuration

enum MeasurementSystem: String, Codable {
    case imperial
    case metric
}

struct DrawingConfig: Codable {
    var measurementSystem: MeasurementSystem = .imperial
    var angleSnapIncrement: Double = 15.0      // degrees
    var lengthSnapIncrement: Double = 6.0      // inches (or cm if metric)
    var snappingEnabled: Bool = true
    var endpointSnapRadius: Double = 20.0      // points (screen distance for magnetic snap)
    var gridVisible: Bool = true
}

// MARK: - Core Geometry

struct DeckVertex: Identifiable, Codable, Equatable {
    let id: String
    var position: CGPoint           // canvas coordinates
    var elevation: Double?          // feet (or meters) off ground, nil = not set
    var elevationSource: ElevationSource = .manual
    var footingType: FootingType?
    var postType: String?           // product reference

    init(id: String = UUID().uuidString, position: CGPoint, elevation: Double? = nil) {
        self.id = id
        self.position = position
        self.elevation = elevation
    }
}

enum ElevationSource: String, Codable {
    case manual
    case ar          // captured via AR — carries ±accuracy
}

enum FootingType: String, Codable, CaseIterable {
    case helicalPile = "helical_pile"
    case sonoTube = "sono_tube"
    case concretePad = "concrete_pad"
}

struct DeckEdge: Identifiable, Codable, Equatable {
    let id: String
    var startVertexId: String
    var endVertexId: String
    var edgeType: EdgeType = .deckEdge
    var dimension: Double?          // real-world length in inches (or cm)
    var dimensionSource: DimensionSource = .manual
    var railingConfig: RailingConfig?
    var stairConfig: StairConfig?
    var assignedItems: [AssignedItem] = []
    var accuracyPercent: Double?    // e.g., 3.0 means ±3%. nil = manually verified / no AR
    /// Set to true when a vertex drag changed the canvas length of this edge
    /// but its stored `dimension` was preserved because the source was manual /
    /// laser / AR (user-authoritative). The renderer surfaces a warning glyph
    /// so the user knows the typed value and the drawn length disagree. Cleared
    /// when the user retypes / re-measures the dimension.
    var dimensionStale: Bool = false
    /// Optional user-supplied label that floats over this edge on the canvas
    /// (e.g. "Hot tub side", "BBQ wall"). Trimmed to nil when blank so absent
    /// labels never render an empty pill. Bug 4a03f507.
    var label: String?
    /// Optional house-edge cladding material (stucco, hardie, wood vertical, etc.)
    /// — separate from the `assignedItems` list because a house edge isn't billed
    /// as deck framing/decking, but its visible cladding still informs renders.
    /// Bug 3d72ce0b.
    var houseEdgeMaterial: HouseEdgeMaterial?

    init(
        id: String = UUID().uuidString,
        startVertexId: String,
        endVertexId: String
    ) {
        self.id = id
        self.startVertexId = startVertexId
        self.endVertexId = endVertexId
    }
}

enum EdgeType: String, Codable, CaseIterable {
    case houseEdge = "house_edge"
    case deckEdge = "deck_edge"
}

/// Cladding material for a `houseEdge`. Drives the rendered house-side wall
/// texture and shows up in materials/estimates output. Bug 3d72ce0b — house
/// edges should rise visibly above the deck surface in the 3D scene; the
/// material picks the right hatch/tone in the 2D renderers and the right
/// fill/normal in the 3D scene.
enum HouseEdgeMaterial: String, Codable, CaseIterable {
    case stucco
    case hardie             // Hardie board / fiber cement plank
    case woodVertical       // Vertical board-and-batten / shiplap
    case brick              // Brick veneer / clay masonry
    case stone              // Stone veneer / natural stone cladding
    case vinyl              // Vinyl siding
    case parapet            // Low capped wall — half-height masonry, used on
                            // rooftop decks and modern flat-faced builds.
                            // Bug ee787f29 — explicitly requested as a
                            // cladding option for high-end residential.

    var displayName: String {
        switch self {
        case .stucco:       return "Stucco"
        case .hardie:       return "Hardie Plank"
        case .woodVertical: return "Wood Vertical"
        case .brick:        return "Brick"
        case .stone:        return "Stone Veneer"
        case .vinyl:        return "Vinyl Siding"
        case .parapet:      return "Parapet Wall"
        }
    }

    /// Hex color used for the wall surface tint in 2D and the diffuse fill
    /// in 3D. Picked from OPSStyle's tan/olive/secondary palette so house
    /// edges read as muted backdrop, not a competing focal point.
    var fillHex: String {
        switch self {
        case .stucco:       return "#D6CFC2"   // warm off-white
        case .hardie:       return "#A6A8A3"   // light gray-green
        case .woodVertical: return "#8B6F4F"   // walnut brown
        case .brick:        return "#8C5A4F"   // muted brick red
        case .stone:        return "#7A7466"   // weathered limestone
        case .vinyl:        return "#C2C5C0"   // cool gray-beige
        case .parapet:      return "#9A8F7E"   // sand-toned masonry cap
        }
    }
}

enum DimensionSource: String, Codable {
    case manual         // typed by user
    case scale          // derived from scale calculation
    case ar             // from AR walk — carries ±accuracy
    case laser          // from Bluetooth laser meter — high accuracy
}

// MARK: - Railing

struct RailingConfig: Codable, Equatable {
    var railingType: RailingType
    var maxPostSpacing: Double      // inches between posts (e.g., 60" for glass, 84" for picket)
    var assignedItems: [AssignedItem] = []

    // Catalog metadata vocabulary (deck-catalog integration spec § 3.4).
    // Free-text strings — companies author option values per Product, so
    // the deck side stays decoupled from any one company's vocabulary.
    // The assignment sheet renders a picker over the assigned Product's
    // option values when one exists; otherwise free-text against these
    // defaults.
    var color: String = "Black"
    var mountType: String = "Topmount"      // Topmount | Sidemount | Surface
    var mountSurface: String = "Surface"    // Surface | Concrete | other
    var postHeight: Double = 36.0           // inches; drives post_set.height (IRC R312 minimum)

    enum CodingKeys: String, CodingKey {
        case railingType, maxPostSpacing, assignedItems
        case color, mountType, mountSurface, postHeight
    }

    init(
        railingType: RailingType,
        maxPostSpacing: Double,
        assignedItems: [AssignedItem] = [],
        color: String = "Black",
        mountType: String = "Topmount",
        mountSurface: String = "Surface",
        postHeight: Double = 36.0
    ) {
        self.railingType = railingType
        self.maxPostSpacing = maxPostSpacing
        self.assignedItems = assignedItems
        self.color = color
        self.mountType = mountType
        self.mountSurface = mountSurface
        self.postHeight = postHeight
    }

    init(from decoder: Decoder) throws {
        // Custom decoder so legacy JSON (saved before the catalog vocabulary
        // landed) round-trips with sensible defaults instead of throwing on
        // missing keys. Swift's synthesized init(from:) calls `decode` for
        // every property regardless of the property's inline default.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.railingType = try c.decode(RailingType.self, forKey: .railingType)
        self.maxPostSpacing = try c.decode(Double.self, forKey: .maxPostSpacing)
        self.assignedItems = try c.decodeIfPresent([AssignedItem].self, forKey: .assignedItems) ?? []
        self.color = try c.decodeIfPresent(String.self, forKey: .color) ?? "Black"
        self.mountType = try c.decodeIfPresent(String.self, forKey: .mountType) ?? "Topmount"
        self.mountSurface = try c.decodeIfPresent(String.self, forKey: .mountSurface) ?? "Surface"
        self.postHeight = try c.decodeIfPresent(Double.self, forKey: .postHeight) ?? 36.0
    }
}

enum RailingType: String, Codable, CaseIterable {
    case glass
    case picket
    case cable
    case horizontal
    case wood

    var defaultMaxPostSpacing: Double {
        switch self {
        case .glass:      return 60.0   // 5 feet
        case .picket:     return 84.0   // 7 feet
        case .cable:      return 48.0   // 4 feet
        case .horizontal: return 72.0   // 6 feet
        case .wood:       return 72.0   // 6 feet
        }
    }

    var displayName: String {
        switch self {
        case .glass:      return "Glass"
        case .picket:     return "Picket"
        case .cable:      return "Cable"
        case .horizontal: return "Horizontal"
        case .wood:       return "Wood"
        }
    }
}

// MARK: - Stairs

enum StairAlignment: String, Codable, CaseIterable {
    case left
    case center
    case right

    var displayName: String {
        switch self {
        case .left:   return "Left"
        case .center: return "Center"
        case .right:  return "Right"
        }
    }
}

struct StairConfig: Codable, Equatable {
    var width: Double               // inches
    var risePerStep: Double = 7.5   // inches (IRC R311.7: max 7.75")
    var runPerTread: Double = 10.0  // inches (IRC R311.7: min 10")
    var treadCount: Int?            // auto-calculated or user override
    var alignment: StairAlignment = .center  // position along edge when width < edge length
    var offset: Double = 0          // inches from alignment side
    var railingConfig: RailingConfig?
    var assignedItems: [AssignedItem] = []
    /// Stair elevation in feet — captured in StairConfigView when no per-vertex
    /// or overall elevation is set. Once stored, the user can edit this on
    /// subsequent passes through the stair editor (instead of being trapped by
    /// the read-only "Total Rise" card). Bug bfbc4068.
    var totalRiseInches: Double?
    /// When true, render stairs on the OPPOSITE perpendicular from the deck
    /// fill. Default `false` means stairs run AWAY from the deck surface, which
    /// is the natural case (bug a7429390). The toggle in StairConfigView
    /// flips this for edges where the user wants the stairs to land on the
    /// other side (e.g. against a fence the renderer can't infer).
    var flipDirection: Bool = false

    // Catalog metadata vocabulary (deck-catalog integration spec § 3.4).
    // `mountType` uses a different vocabulary than railing (Surface | Top | Side)
    // because stairs land on grade, on top of an existing landing, or against
    // the side of a deck — each maps to a distinct stair-product variant.
    var color: String = "Black"
    var mountType: String = "Surface"   // Surface | Top | Side

    enum CodingKeys: String, CodingKey {
        case width, risePerStep, runPerTread, treadCount, alignment, offset
        case railingConfig, assignedItems, totalRiseInches, flipDirection
        case color, mountType
    }

    init(
        width: Double,
        risePerStep: Double = 7.5,
        runPerTread: Double = 10.0,
        treadCount: Int? = nil,
        alignment: StairAlignment = .center,
        offset: Double = 0,
        railingConfig: RailingConfig? = nil,
        assignedItems: [AssignedItem] = [],
        totalRiseInches: Double? = nil,
        flipDirection: Bool = false,
        color: String = "Black",
        mountType: String = "Surface"
    ) {
        self.width = width
        self.risePerStep = risePerStep
        self.runPerTread = runPerTread
        self.treadCount = treadCount
        self.alignment = alignment
        self.offset = offset
        self.railingConfig = railingConfig
        self.assignedItems = assignedItems
        self.totalRiseInches = totalRiseInches
        self.flipDirection = flipDirection
        self.color = color
        self.mountType = mountType
    }

    init(from decoder: Decoder) throws {
        // Custom decoder so legacy JSON round-trips with sensible defaults
        // instead of throwing on missing keys. See RailingConfig for the
        // rationale.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.width = try c.decode(Double.self, forKey: .width)
        self.risePerStep = try c.decodeIfPresent(Double.self, forKey: .risePerStep) ?? 7.5
        self.runPerTread = try c.decodeIfPresent(Double.self, forKey: .runPerTread) ?? 10.0
        self.treadCount = try c.decodeIfPresent(Int.self, forKey: .treadCount)
        self.alignment = try c.decodeIfPresent(StairAlignment.self, forKey: .alignment) ?? .center
        self.offset = try c.decodeIfPresent(Double.self, forKey: .offset) ?? 0
        self.railingConfig = try c.decodeIfPresent(RailingConfig.self, forKey: .railingConfig)
        self.assignedItems = try c.decodeIfPresent([AssignedItem].self, forKey: .assignedItems) ?? []
        self.totalRiseInches = try c.decodeIfPresent(Double.self, forKey: .totalRiseInches)
        self.flipDirection = try c.decodeIfPresent(Bool.self, forKey: .flipDirection) ?? false
        self.color = try c.decodeIfPresent(String.self, forKey: .color) ?? "Black"
        self.mountType = try c.decodeIfPresent(String.self, forKey: .mountType) ?? "Surface"
    }

    /// Calculate tread count from total rise (elevation difference at edge endpoints)
    static func calculateTreadCount(totalRise: Double, risePerStep: Double = 7.5) -> Int {
        guard totalRise > 0 else { return 0 }
        return Int(ceil(totalRise / risePerStep))
    }

    /// Calculate stringer length from total rise and run
    static func stringerLength(totalRise: Double, treadCount: Int, runPerTread: Double = 10.0) -> Double {
        let totalRun = Double(treadCount) * runPerTread
        return sqrt(totalRise * totalRise + totalRun * totalRun)
    }

    /// Number of stringers based on stair width
    static func stringerCount(width: Double) -> Int {
        // One stringer every 16" on center, minimum 2
        return max(2, Int(ceil(width / 16.0)) + 1)
    }
}

// MARK: - Item Assignment

struct AssignedItem: Identifiable, Codable, Equatable {
    let id: String
    var productId: String?          // reference to company's Products table
    var name: String                // display name
    var unitType: UnitType          // determines what this item measures
    var unitPrice: Double?          // price per unit (optional — may come from product)
    var taskTypeId: String?         // task type this material belongs to
    var taskTypeColor: String?      // hex color cached from TaskType at assignment time
    /// Flags this assignment as a gate (drives `gate` component emission per
    /// the deck-catalog integration spec § 3.5). Auto-defaulted on by the
    /// assignment sheet when the picked Product's `category` (or tag)
    /// contains "gate" (case-insensitive); the user can override either way.
    var isGate: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, productId, name, unitType, unitPrice, taskTypeId, taskTypeColor, isGate
    }

    init(
        id: String = UUID().uuidString,
        productId: String? = nil,
        name: String,
        unitType: UnitType,
        unitPrice: Double? = nil,
        taskTypeId: String? = nil,
        taskTypeColor: String? = nil,
        isGate: Bool = false
    ) {
        self.id = id
        self.productId = productId
        self.name = name
        self.unitType = unitType
        self.unitPrice = unitPrice
        self.taskTypeId = taskTypeId
        self.taskTypeColor = taskTypeColor
        self.isGate = isGate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.productId = try c.decodeIfPresent(String.self, forKey: .productId)
        self.name = try c.decode(String.self, forKey: .name)
        self.unitType = try c.decode(UnitType.self, forKey: .unitType)
        self.unitPrice = try c.decodeIfPresent(Double.self, forKey: .unitPrice)
        self.taskTypeId = try c.decodeIfPresent(String.self, forKey: .taskTypeId)
        self.taskTypeColor = try c.decodeIfPresent(String.self, forKey: .taskTypeColor)
        self.isGate = try c.decodeIfPresent(Bool.self, forKey: .isGate) ?? false
    }
}

enum UnitType: String, Codable, CaseIterable {
    case linearFoot = "linear_foot"
    case linearMeter = "linear_meter"
    case squareFoot = "square_foot"
    case squareMeter = "square_meter"
    case each
    case set
}

// MARK: - Footprint (Closed Polygon) — legacy single-surface model

/// Legacy single-surface assignment store. Retained for back-compat with
/// previously-saved drawings; new per-surface assignments live in
/// `DeckDrawingData.surfaces` / `DeckLevel.surfaces` (`DeckSurface`).
/// On first reconciliation after migration, any populated `assignedItems`
/// or `label` here is moved to the largest detected surface and the legacy
/// fields are cleared.
struct DeckFootprint: Codable, Equatable {
    var assignedItems: [AssignedItem] = []   // area-based items (surfacing, etc.)
    var isClosed: Bool = false
    /// Optional user-supplied label that floats over the deck surface
    /// (e.g. "BBQ Area", "Hot Tub Pad"). Trimmed to nil when blank.
    /// Bug 4a03f507.
    var label: String?
}

// MARK: - Surfaces (Multi-Polygon)

/// A persisted closed face in the deck-edge graph. Distinct from the legacy
/// `DeckFootprint` (which assumed exactly one polygon per drawing). Every
/// closed face detected by `SurfaceDetector` is mapped — through
/// `SurfaceReconciler` — to one of these so per-surface material and label
/// assignments survive across geometry edits. DECK-NEW-1.
struct DeckSurface: Identifiable, Codable, Equatable {
    /// Stable UUID; survives geometry edits via vertex-set Jaccard matching.
    let id: String
    /// Unordered membership — matched against `DetectedSurface.vertexIds`.
    /// Updated in place when a small edit shifts the surface's boundary.
    var vertexIds: Set<String>
    /// Per-surface area-based items (decking material, finishes, etc.).
    var assignedItems: [AssignedItem] = []
    /// Optional user-supplied label that floats over the surface in the
    /// renderers (e.g. "BBQ Area", "Hot Tub Pad").
    var label: String?

    // Catalog metadata vocabulary (deck-catalog integration spec § 3.4).
    // Defaults pick the most common new-construction values so partially-
    // configured surfaces still emit meaningful `deck_board` components.
    var color: String = "Brown"
    var boardMaterial: String = "composite"  // composite | pvc | cedar | treated | other

    enum CodingKeys: String, CodingKey {
        case id, vertexIds, assignedItems, label, color, boardMaterial
    }

    init(
        id: String = UUID().uuidString,
        vertexIds: Set<String> = [],
        assignedItems: [AssignedItem] = [],
        label: String? = nil,
        color: String = "Brown",
        boardMaterial: String = "composite"
    ) {
        self.id = id
        self.vertexIds = vertexIds
        self.assignedItems = assignedItems
        self.label = label
        self.color = color
        self.boardMaterial = boardMaterial
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.vertexIds = try c.decode(Set<String>.self, forKey: .vertexIds)
        self.assignedItems = try c.decodeIfPresent([AssignedItem].self, forKey: .assignedItems) ?? []
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.color = try c.decodeIfPresent(String.self, forKey: .color) ?? "Brown"
        self.boardMaterial = try c.decodeIfPresent(String.self, forKey: .boardMaterial) ?? "composite"
    }
}

// MARK: - Complete Drawing Data

struct DeckDrawingData: Codable {
    var vertices: [DeckVertex] = []
    var edges: [DeckEdge] = []
    var footprint: DeckFootprint = DeckFootprint()
    /// Per-surface material/label store (DECK-NEW-1 follow-up). One entry
    /// per detected closed face; reconciled via `SurfaceReconciler` after
    /// any geometry edit. Empty until the first surface is detected and
    /// reconciled. Single-level drawings populate this; multi-level
    /// drawings populate the equivalent on each `DeckLevel`.
    var surfaces: [DeckSurface] = []
    var config: DrawingConfig = DrawingConfig()
    var overallElevation: Double?          // simple mode: uniform height
    var scaleFactor: Double?               // canvas points per real-world inch
    var poolDiameter: Double?              // pool deck: diameter in inches (visual overlay only)
    var photoOverlay: PhotoOverlayState?   // saved overlay positioning for re-editing

    // MARK: - Multi-Level

    var levels: [DeckLevel] = []
    var levelConnections: [LevelConnection] = []

    // MARK: - Catalog projection

    /// Catalog-facing projection of the drawing — one row per visible
    /// component (railing, deck_board, stair_set, gate, post_set) with
    /// metadata keys the `DesignToEstimateAdapter` consumes.
    /// Recomputed from geometry on every `toJSON()` (Phase 2); never read
    /// for rendering. Absent on legacy JSON; backfilled on first load
    /// (deck-catalog integration spec § 3.2 + § 4.2).
    var components: [DesignComponentRow]? = nil

    // MARK: - Vertex Helpers

    func vertex(byId id: String) -> DeckVertex? {
        vertices.first { $0.id == id }
    }

    mutating func updateVertex(_ vertex: DeckVertex) {
        if let index = vertices.firstIndex(where: { $0.id == vertex.id }) {
            vertices[index] = vertex
        }
    }

    // MARK: - Edge Helpers

    func edge(byId id: String) -> DeckEdge? {
        edges.first { $0.id == id }
    }

    func edges(connectedTo vertexId: String) -> [DeckEdge] {
        edges.filter { $0.startVertexId == vertexId || $0.endVertexId == vertexId }
    }

    mutating func updateEdge(_ edge: DeckEdge) {
        if let index = edges.firstIndex(where: { $0.id == edge.id }) {
            edges[index] = edge
        }
    }

    // MARK: - Polygon State

    var isClosed: Bool {
        guard vertices.count >= 3, edges.count >= 3 else { return false }

        // Build adjacency: vertex → [connected vertex ids]
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].insert(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].insert(edge.startVertexId)
        }

        // Every vertex must have exactly 2 connections for a simple polygon
        for vertex in vertices {
            let connections = adjacency[vertex.id]?.count ?? 0
            if connections != 2 { return false }
        }

        // Walk the graph from the first vertex — must visit all vertices and return to start
        guard let startId = vertices.first?.id else { return false }
        var visited: Set<String> = [startId]
        var currentId = startId

        for _ in 0..<vertices.count {
            guard let neighbors = adjacency[currentId] else { return false }
            let unvisited = neighbors.subtracting(visited)

            if unvisited.isEmpty {
                // Only valid if we've visited all vertices and can return to start
                return visited.count == vertices.count && neighbors.contains(startId)
            }

            guard let nextId = unvisited.first else { return false }
            visited.insert(nextId)
            currentId = nextId
        }

        return false
    }

    /// Ordered vertex positions for rendering — walks the edge graph in geometric order
    /// so polygon fill traces the visible boundary. Each vertex in a simple closed polygon
    /// has exactly two neighbors, so "next" is always "the one I didn't come from".
    ///
    /// Field bug: picking the alphabetically-smaller neighbor (our previous implementation)
    /// occasionally reversed direction mid-walk on concave/construction-mole shapes,
    /// producing a path that looped back through the interior. CGContext.fillPath then
    /// filled the enclosed region of that broken path — bleeding fill outside the real
    /// edges. Previous-vertex-aware traversal guarantees the walk follows edges only.
    var orderedPositions: [CGPoint] {
        guard vertices.count >= 3, edges.count >= 3 else {
            return vertices.map { $0.position }
        }

        var adjacency: [String: [String]] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].append(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].append(edge.startVertexId)
        }

        for vertex in vertices {
            let connections = adjacency[vertex.id]?.count ?? 0
            if connections != 2 { return vertices.map { $0.position } }
        }

        guard let startId = vertices.first?.id else { return vertices.map { $0.position } }
        var ordered: [CGPoint] = []
        var visited: Set<String> = [startId]
        var previousId: String? = nil
        var currentId = startId

        if let startVertex = vertex(byId: startId) {
            ordered.append(startVertex.position)
        }

        for _ in 0..<vertices.count - 1 {
            guard let neighbors = adjacency[currentId] else { break }
            // Pick the neighbor we didn't arrive from. On the first step previousId is
            // nil, so we fall back to a deterministic pick (sorted) — this is the only
            // place winding direction is chosen.
            let nextId: String?
            if let prev = previousId {
                nextId = neighbors.first(where: { $0 != prev })
            } else {
                nextId = neighbors.sorted().first
            }
            guard let next = nextId, !visited.contains(next) else { break }
            visited.insert(next)
            previousId = currentId
            currentId = next
            if let v = vertex(byId: next) {
                ordered.append(v.position)
            }
        }

        guard ordered.count == vertices.count else {
            return vertices.map { $0.position }
        }

        // Normalize winding so the walk always returns vertices in the same
        // visual direction (CCW in SwiftUI canvas coordinates → negative
        // shoelace). The first-step pick is otherwise arbitrary and depends
        // on UUID sort, which would silently flip direction for any future
        // consumer that cares (3D normals, fill rules, etc.).
        if PolygonMath.signedArea(vertices: ordered) > 0 {
            ordered.reverse()
        }

        return ordered
    }

    /// Every closed face in this drawing's edge graph. Replaces the
    /// all-or-nothing `orderedPositions` polygon when the user draws multiple
    /// loops, shares an edge between two surfaces, or adds detail lines
    /// beyond the perimeter (DECK-NEW-1). Returns empty when no loop is
    /// closed yet. For multi-level drawings, callers should ask each level
    /// for its own surfaces — this top-level array only inspects the
    /// single-level fields.
    var detectedSurfaces: [DetectedSurface] {
        SurfaceDetector.detect(vertices: vertices, edges: edges)
    }

    /// True when the drawing has at least one closed surface — anywhere.
    /// More permissive than `isClosed`, which requires every vertex to be
    /// on the perimeter of one Hamiltonian cycle (so two disjoint deck
    /// footprints, or two separate levels each with their own footprint,
    /// both register as "not closed" via the single-loop walk). Use this
    /// to gate UI that should appear as soon as ANY closed shape exists —
    /// 3D preview, area/perimeter badges, estimate eligibility.
    /// Multi-level aware: in multi-level mode the top-level vertices/edges
    /// arrays are empty (all geometry lives on the levels), so we ask each
    /// level for its own detected surfaces. Bug ee787f29 follow-up — the
    /// DeckTabView 3D viewer was gating on `isClosed`, which always
    /// returned false in multi-level mode and falsely shows the "close the
    /// polygon" empty state.
    var hasAnyClosedSurface: Bool {
        if isMultiLevel {
            return levels.contains(where: { !$0.detectedSurfaces.isEmpty })
        }
        return !detectedSurfaces.isEmpty
    }

    // MARK: - Multi-Level Helpers

    /// Whether this drawing uses multi-level mode
    var isMultiLevel: Bool {
        !levels.isEmpty
    }

    /// The active geometry source — levels if multi-level, top-level fields if single
    var allVertices: [DeckVertex] {
        isMultiLevel ? levels.flatMap { $0.vertices } : vertices
    }

    var allEdges: [DeckEdge] {
        isMultiLevel ? levels.flatMap { $0.edges } : edges
    }

    /// Total area across all levels in square inches
    func totalRealWorldArea(scaleFactor: Double) -> Double {
        if isMultiLevel {
            return levels.reduce(0) { total, level in
                total + PolygonMath.realWorldArea(vertices: level.orderedPositions, scaleFactor: scaleFactor)
            }
        }
        return PolygonMath.realWorldArea(vertices: orderedPositions, scaleFactor: scaleFactor)
    }

    /// Get a level by ID
    func level(byId id: String) -> DeckLevel? {
        levels.first { $0.id == id }
    }

    /// Update a level in place
    mutating func updateLevel(_ level: DeckLevel) {
        if let index = levels.firstIndex(where: { $0.id == level.id }) {
            levels[index] = level
        }
    }

    /// Elevation difference between two levels in inches
    func elevationDifference(upperLevelId: String, lowerLevelId: String) -> Double? {
        guard let upper = level(byId: upperLevelId)?.elevation,
              let lower = level(byId: lowerLevelId)?.elevation else { return nil }
        return (upper - lower) * 12.0  // feet to inches
    }

    /// Migrate single-level data to multi-level (called when adding a second level)
    mutating func migrateToMultiLevel() {
        guard !isMultiLevel, vertices.count >= 3 else { return }
        var firstLevel = DeckLevel(
            name: "Level 1",
            displayColor: .blue,
            sortOrder: 0
        )
        firstLevel.vertices = vertices
        firstLevel.edges = edges
        firstLevel.footprint = footprint
        firstLevel.elevation = overallElevation
        levels = [firstLevel]
        // Clear the top-level shape state — the data lives in `levels[0]` now.
        // Without this, deleting every level later flips `isMultiLevel` back
        // to false, and the original single-level vertices/edges silently
        // resurface (the user dragged a deck into existence twice).
        vertices = []
        edges = []
        footprint = DeckFootprint()
        overallElevation = nil
    }

    // MARK: - Serialization

    func toJSON() -> String {
        // Recompute the catalog-facing components projection on every encode.
        // The projection is derived from geometry — never authored directly —
        // so refreshing it here guarantees the on-disk JSON always carries an
        // up-to-date components array for `DesignToEstimateAdapter`.
        var copy = self
        copy.components = ComponentEmitter.emit(self)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(copy),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func fromJSON(_ json: String) -> DeckDrawingData? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard var decoded = try? JSONDecoder().decode(DeckDrawingData.self, from: data) else { return nil }

        // Referential integrity, single-level: drop edges that reference
        // missing vertices, then drop vertices that no surviving edge
        // references. Without the second pass an orphan vertex makes the
        // adjacency walk fail (`connections != 2`) and `isClosed` returns
        // false forever, so the polygon never opens as a valid shape again.
        let vertexIds = Set(decoded.vertices.map { $0.id })
        let beforeEdgeCount = decoded.edges.count
        decoded.edges.removeAll { edge in
            let startMissing = !vertexIds.contains(edge.startVertexId)
            let endMissing = !vertexIds.contains(edge.endVertexId)
            if startMissing || endMissing {
                print("[DeckBuilder] fromJSON: removing orphaned edge \(edge.id) (start: \(startMissing), end: \(endMissing))")
                return true
            }
            return false
        }
        if decoded.edges.count != beforeEdgeCount {
            print("[DeckBuilder] fromJSON: removed \(beforeEdgeCount - decoded.edges.count) orphaned edges")
        }

        let connectedVertexIds = Set(decoded.edges.flatMap { [$0.startVertexId, $0.endVertexId] })
        let beforeVertexCount = decoded.vertices.count
        decoded.vertices.removeAll { !connectedVertexIds.contains($0.id) }
        if decoded.vertices.count != beforeVertexCount {
            print("[DeckBuilder] fromJSON: removed \(beforeVertexCount - decoded.vertices.count) orphaned vertices")
        }

        // Same two-pass check per level.
        for i in decoded.levels.indices {
            let levelVertexIds = Set(decoded.levels[i].vertices.map { $0.id })
            decoded.levels[i].edges.removeAll { edge in
                !levelVertexIds.contains(edge.startVertexId) || !levelVertexIds.contains(edge.endVertexId)
            }
            let connected = Set(decoded.levels[i].edges.flatMap { [$0.startVertexId, $0.endVertexId] })
            decoded.levels[i].vertices.removeAll { !connected.contains($0.id) }
        }

        // Drop any LevelConnection whose referenced edges no longer exist
        // after the integrity pass — otherwise the connection becomes a
        // phantom (renderer silently early-returns) but still ships into
        // estimates. Same rule as runtime delete paths.
        // Snapshot the levels into a local because Swift forbids reading
        // `decoded.levels` from inside a predicate that also mutates
        // `decoded.levelConnections` (overlapping access).
        let levelsSnapshot = decoded.levels
        decoded.levelConnections.removeAll { conn in
            guard let upper = levelsSnapshot.first(where: { $0.id == conn.upperLevelId }),
                  upper.edge(byId: conn.upperEdgeId) != nil else { return true }
            if let lowerEdgeId = conn.lowerEdgeId {
                guard let lower = levelsSnapshot.first(where: { $0.id == conn.lowerLevelId }),
                      lower.edge(byId: lowerEdgeId) != nil else { return true }
            }
            return false
        }

        // Clamp negative scale factor to nil
        if let scale = decoded.scaleFactor, scale <= 0 {
            print("[DeckBuilder] fromJSON: clamping invalid scale factor \(scale) to nil")
            decoded.scaleFactor = nil
        }

        return decoded
    }
}

// MARK: - CGPoint Codable

extension CGPoint: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case x, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        self.init(x: x, y: y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Double(x), forKey: .x)
        try container.encode(Double(y), forKey: .y)
    }
}
