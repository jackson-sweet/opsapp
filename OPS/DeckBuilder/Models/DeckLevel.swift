// OPS/OPS/DeckBuilder/Models/DeckLevel.swift

import Foundation
import SwiftUI

struct DeckLevel: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var vertices: [DeckVertex] = []
    var edges: [DeckEdge] = []
    var footprint: DeckFootprint = DeckFootprint()
    /// Per-surface material/label store for THIS level. See
    /// `DeckDrawingData.surfaces` for the data-model rationale (DECK-NEW-1).
    var surfaces: [DeckSurface] = []
    var elevation: Double?             // uniform height off ground in feet
    var perVertexElevation: Bool = false
    var displayColor: LevelColor = .blue
    var sortOrder: Int = 0
    /// Runtime-only; exact-key validation prevents stale reuse after a value
    /// copy mutates this level's geometry.
    private var geometrySnapshotCache = DeckExactDerivedCache<DeckGeometryContextKey, DeckGeometryContextSnapshot>()

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case vertices
        case edges
        case footprint
        case surfaces
        case elevation
        case perVertexElevation
        case displayColor
        case sortOrder
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        displayColor: LevelColor = .blue,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.displayColor = displayColor
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.vertices = try c.decodeIfPresent([DeckVertex].self, forKey: .vertices) ?? []
        self.edges = try c.decodeIfPresent([DeckEdge].self, forKey: .edges) ?? []
        self.footprint = try c.decodeIfPresent(DeckFootprint.self, forKey: .footprint) ?? DeckFootprint()
        self.surfaces = try c.decodeIfPresent([DeckSurface].self, forKey: .surfaces) ?? []
        self.elevation = try c.decodeIfPresent(Double.self, forKey: .elevation)
        self.perVertexElevation = try c.decodeLegacyBoolIfPresent(forKey: .perVertexElevation) ?? false
        self.displayColor = try c.decodeIfPresent(LevelColor.self, forKey: .displayColor) ?? .blue
        self.sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    // MARK: - Vertex/Edge Helpers (mirror DeckDrawingData helpers)

    func vertex(byId id: String) -> DeckVertex? {
        vertices.first { $0.id == id }
    }

    mutating func updateVertex(_ vertex: DeckVertex) {
        if let index = vertices.firstIndex(where: { $0.id == vertex.id }) {
            vertices[index] = vertex
        }
    }

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

    var isClosed: Bool {
        geometrySnapshot.isDegreeTwoClosed
    }

    var orderedPositions: [CGPoint] {
        geometrySnapshot.orderedPositions
    }

    /// Every closed face in this level's edge graph. Replaces the all-or-nothing
    /// `orderedPositions` polygon when the user draws multiple loops or extra
    /// detail lines beyond the perimeter (DECK-NEW-1). Returns empty when no
    /// loop has been closed yet.
    var detectedSurfaces: [DetectedSurface] {
        geometrySnapshot.detectedSurfaces
    }

    var geometrySnapshot: DeckGeometryContextSnapshot {
        let key = DeckGeometryContextSnapshot.key(vertices: vertices, edges: edges)
        return geometrySnapshotCache.resolve(key: key) {
            DeckGeometryContextSnapshot.build(
                vertices: vertices,
                edges: edges,
                closureRequiresSingleWalk: false
            )
        }
    }

    var geometrySnapshotComputationCount: Int {
        geometrySnapshotCache.missCount
    }

    static func == (lhs: DeckLevel, rhs: DeckLevel) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.vertices == rhs.vertices
            && lhs.edges == rhs.edges
            && lhs.footprint == rhs.footprint
            && lhs.surfaces == rhs.surfaces
            && lhs.elevation == rhs.elevation
            && lhs.perVertexElevation == rhs.perVertexElevation
            && lhs.displayColor == rhs.displayColor
            && lhs.sortOrder == rhs.sortOrder
    }

    /// Effective elevation for a vertex (per-vertex if enabled, otherwise uniform)
    func effectiveElevation(vertexId: String) -> Double? {
        if perVertexElevation, let vertex = vertex(byId: vertexId) {
            return vertex.elevation
        }
        return elevation
    }
}

// MARK: - LevelColor

enum LevelColor: String, Codable, CaseIterable, Equatable {
    case blue
    case green
    case amber

    var fillColor: (r: Double, g: Double, b: Double) {
        switch self {
        case .blue:  return (89.0/255, 119.0/255, 148.0/255)   // primaryAccent
        case .green: return (165.0/255, 179.0/255, 104.0/255)  // success
        case .amber: return (196.0/255, 168.0/255, 104.0/255)  // warning
        }
    }

    var swiftUIColor: Color {
        let c = fillColor
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    var displayName: String {
        switch self {
        case .blue:  return "Blue"
        case .green: return "Green"
        case .amber: return "Amber"
        }
    }

    /// Next available color given already-used colors
    static func nextAvailable(excluding used: [LevelColor]) -> LevelColor {
        for color in allCases {
            if !used.contains(color) { return color }
        }
        return .blue // fallback if all used
    }
}

// MARK: - LevelConnection

struct LevelConnection: Identifiable, Codable, Equatable {
    let id: String
    var upperLevelId: String
    var lowerLevelId: String
    var upperEdgeId: String
    var lowerEdgeId: String?           // nil if lower level doesn't have a matching edge
    var stairConfig: StairConfig
    var position: ConnectionPosition

    init(
        id: String = UUID().uuidString,
        upperLevelId: String,
        lowerLevelId: String,
        upperEdgeId: String,
        lowerEdgeId: String? = nil,
        stairConfig: StairConfig,
        position: ConnectionPosition = .full
    ) {
        self.id = id
        self.upperLevelId = upperLevelId
        self.lowerLevelId = lowerLevelId
        self.upperEdgeId = upperEdgeId
        self.lowerEdgeId = lowerEdgeId
        self.stairConfig = stairConfig
        self.position = position
    }
}

// MARK: - ConnectionPosition

enum ConnectionPosition: Codable, Equatable {
    case full
    case partial(offsetInches: Double, widthInches: Double)
}
