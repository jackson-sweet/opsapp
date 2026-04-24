// OPS/OPS/DeckBuilder/Models/DeckLevel.swift

import Foundation
import SwiftUI

struct DeckLevel: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var vertices: [DeckVertex] = []
    var edges: [DeckEdge] = []
    var footprint: DeckFootprint = DeckFootprint()
    var elevation: Double?             // uniform height off ground in feet
    var perVertexElevation: Bool = false
    var displayColor: LevelColor = .blue
    var sortOrder: Int = 0

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
        guard vertices.count >= 3, edges.count >= 3 else { return false }
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].insert(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].insert(edge.startVertexId)
        }
        return vertices.allSatisfy { (adjacency[$0.id]?.count ?? 0) == 2 }
    }

    var orderedPositions: [CGPoint] {
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
