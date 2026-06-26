// OPS/OPS/DeckBuilder/Models/DeckLevel.swift

import Foundation
import SwiftUI

public struct DeckLevel: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String
    public var vertices: [DeckVertex] = []
    public var edges: [DeckEdge] = []
    public var footprint: DeckFootprint = DeckFootprint()
    /// Per-surface material/label store for THIS level. See
    /// `DeckDrawingData.surfaces` for the data-model rationale (DECK-NEW-1).
    public var surfaces: [DeckSurface] = []
    public var elevation: Double?             // uniform height off ground in feet
    public var perVertexElevation: Bool = false
    public var displayColor: LevelColor = .blue
    public var sortOrder: Int = 0

    public enum CodingKeys: String, CodingKey {
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

    public init(
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

    public init(from decoder: Decoder) throws {
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

    public func vertex(byId id: String) -> DeckVertex? {
        vertices.first { $0.id == id }
    }

    public mutating func updateVertex(_ vertex: DeckVertex) {
        if let index = vertices.firstIndex(where: { $0.id == vertex.id }) {
            vertices[index] = vertex
        }
    }

    public func edge(byId id: String) -> DeckEdge? {
        edges.first { $0.id == id }
    }

    public func edges(connectedTo vertexId: String) -> [DeckEdge] {
        edges.filter { $0.startVertexId == vertexId || $0.endVertexId == vertexId }
    }

    public mutating func updateEdge(_ edge: DeckEdge) {
        if let index = edges.firstIndex(where: { $0.id == edge.id }) {
            edges[index] = edge
        }
    }

    public var isClosed: Bool {
        guard vertices.count >= 3, edges.count >= 3 else { return false }
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].insert(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].insert(edge.startVertexId)
        }
        return vertices.allSatisfy { (adjacency[$0.id]?.count ?? 0) == 2 }
    }

    public var orderedPositions: [CGPoint] {
        // Matches DeckDrawingData.orderedPositions — walks via previous-vertex-aware
        // traversal so polygon fill follows the visible boundary on concave/construction-
        // mole shapes. See DeckDrawingData for the detailed rationale.
        guard vertices.count >= 3, edges.count >= 3 else {
            return vertices.map { $0.position }
        }

        var adjacency: [String: [String]] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].append(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].append(edge.startVertexId)
        }

        for vertex in vertices {
            if (adjacency[vertex.id]?.count ?? 0) != 2 { return vertices.map { $0.position } }
        }

        guard let startId = vertices.first?.id else { return vertices.map { $0.position } }
        var ordered: [CGPoint] = []
        var visited: Set<String> = [startId]
        var previousId: String? = nil
        var currentId = startId

        if let v = vertex(byId: startId) { ordered.append(v.position) }

        for _ in 0..<vertices.count - 1 {
            guard let neighbors = adjacency[currentId] else { break }
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
            if let v = vertex(byId: next) { ordered.append(v.position) }
        }

        guard ordered.count == vertices.count else { return vertices.map { $0.position } }
        // Match DeckDrawingData.orderedPositions: normalize winding so any
        // direction-sensitive consumer sees a stable orientation.
        if PolygonMath.signedArea(vertices: ordered) > 0 {
            ordered.reverse()
        }
        return ordered
    }

    /// Every closed face in this level's edge graph. Replaces the all-or-nothing
    /// `orderedPositions` polygon when the user draws multiple loops or extra
    /// detail lines beyond the perimeter (DECK-NEW-1). Returns empty when no
    /// loop has been closed yet.
    public var detectedSurfaces: [DetectedSurface] {
        SurfaceDetector.detect(vertices: vertices, edges: edges)
    }

    /// Effective elevation for a vertex (per-vertex if enabled, otherwise uniform)
    public func effectiveElevation(vertexId: String) -> Double? {
        if perVertexElevation, let vertex = vertex(byId: vertexId) {
            return vertex.elevation
        }
        return elevation
    }
}

// MARK: - LevelColor

public enum LevelColor: String, Codable, CaseIterable, Equatable {
    case blue
    case green
    case amber

    public var fillColor: (r: Double, g: Double, b: Double) {
        switch self {
        case .blue:  return (89.0/255, 119.0/255, 148.0/255)   // primaryAccent
        case .green: return (165.0/255, 179.0/255, 104.0/255)  // success
        case .amber: return (196.0/255, 168.0/255, 104.0/255)  // warning
        }
    }

    public var swiftUIColor: Color {
        switch self {
        case .blue: return OPSStyle.Colors.opsAccent
        case .green: return OPSStyle.Colors.olive
        case .amber: return OPSStyle.Colors.tan
        }
    }

    public var displayName: String {
        switch self {
        case .blue:  return "Blue"
        case .green: return "Green"
        case .amber: return "Amber"
        }
    }

    /// Next available color given already-used colors
    public static func nextAvailable(excluding used: [LevelColor]) -> LevelColor {
        for color in allCases {
            if !used.contains(color) { return color }
        }
        return .blue // fallback if all used
    }
}

// MARK: - LevelConnection

public struct LevelConnection: Identifiable, Codable, Equatable {
    public let id: String
    public var upperLevelId: String
    public var lowerLevelId: String
    public var upperEdgeId: String
    public var lowerEdgeId: String?           // nil if lower level doesn't have a matching edge
    public var stairConfig: StairConfig
    public var position: ConnectionPosition

    public init(
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

public enum ConnectionPosition: Codable, Equatable {
    case full
    case partial(offsetInches: Double, widthInches: Double)
}
