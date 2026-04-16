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

    init(
        id: String = UUID().uuidString,
        productId: String? = nil,
        name: String,
        unitType: UnitType,
        unitPrice: Double? = nil,
        taskTypeId: String? = nil,
        taskTypeColor: String? = nil
    ) {
        self.id = id
        self.productId = productId
        self.name = name
        self.unitType = unitType
        self.unitPrice = unitPrice
        self.taskTypeId = taskTypeId
        self.taskTypeColor = taskTypeColor
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

// MARK: - Footprint (Closed Polygon)

struct DeckFootprint: Codable, Equatable {
    var assignedItems: [AssignedItem] = []   // area-based items (surfacing, etc.)
    var isClosed: Bool = false
}

// MARK: - Complete Drawing Data

struct DeckDrawingData: Codable {
    var vertices: [DeckVertex] = []
    var edges: [DeckEdge] = []
    var footprint: DeckFootprint = DeckFootprint()
    var config: DrawingConfig = DrawingConfig()
    var overallElevation: Double?          // simple mode: uniform height
    var scaleFactor: Double?               // canvas points per real-world inch
    var poolDiameter: Double?              // pool deck: diameter in inches (visual overlay only)
    var photoOverlay: PhotoOverlayState?   // saved overlay positioning for re-editing

    // MARK: - Multi-Level

    var levels: [DeckLevel] = []
    var levelConnections: [LevelConnection] = []

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

    /// Ordered vertex positions for rendering — walks edge graph for correct polygon winding.
    /// Falls back to array order if the polygon is not closed.
    var orderedPositions: [CGPoint] {
        guard vertices.count >= 3, edges.count >= 3 else {
            return vertices.map { $0.position }
        }

        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].insert(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].insert(edge.startVertexId)
        }

        for vertex in vertices {
            let connections = adjacency[vertex.id]?.count ?? 0
            if connections != 2 { return vertices.map { $0.position } }
        }

        guard let startId = vertices.first?.id else { return vertices.map { $0.position } }
        var ordered: [CGPoint] = []
        var visited: Set<String> = [startId]
        var currentId = startId

        if let startVertex = vertex(byId: startId) {
            ordered.append(startVertex.position)
        }

        for _ in 0..<vertices.count - 1 {
            guard let neighbors = adjacency[currentId] else { break }
            let unvisited = neighbors.subtracting(visited)
            guard let nextId = unvisited.first else { break }
            visited.insert(nextId)
            currentId = nextId
            if let v = vertex(byId: nextId) {
                ordered.append(v.position)
            }
        }

        guard ordered.count == vertices.count else {
            return vertices.map { $0.position }
        }

        return ordered
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
        // Keep top-level fields for backward compat but levels takes precedence
    }

    // MARK: - Serialization

    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func fromJSON(_ json: String) -> DeckDrawingData? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard var decoded = try? JSONDecoder().decode(DeckDrawingData.self, from: data) else { return nil }

        // Referential integrity: remove edges with orphaned vertex references
        let vertexIds = Set(decoded.vertices.map { $0.id })
        let beforeCount = decoded.edges.count
        decoded.edges.removeAll { edge in
            let startMissing = !vertexIds.contains(edge.startVertexId)
            let endMissing = !vertexIds.contains(edge.endVertexId)
            if startMissing || endMissing {
                print("[DeckBuilder] fromJSON: removing orphaned edge \(edge.id) (start: \(startMissing), end: \(endMissing))")
                return true
            }
            return false
        }
        if decoded.edges.count != beforeCount {
            print("[DeckBuilder] fromJSON: removed \(beforeCount - decoded.edges.count) orphaned edges")
        }

        // Same check per level
        for i in decoded.levels.indices {
            let levelVertexIds = Set(decoded.levels[i].vertices.map { $0.id })
            decoded.levels[i].edges.removeAll { edge in
                !levelVertexIds.contains(edge.startVertexId) || !levelVertexIds.contains(edge.endVertexId)
            }
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
