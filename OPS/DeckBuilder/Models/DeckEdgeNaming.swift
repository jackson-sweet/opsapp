// OPS/OPS/DeckBuilder/Models/DeckEdgeNaming.swift

import CoreGraphics
import Foundation

/// Names an edge the way the person holding the phone would name it.
///
/// The stair sheet's picker used to list "Edge 1–2", "Edge 2–3" — vertex
/// indices, which appear nowhere on the canvas. The operator had no way to
/// map a row to a side of the deck they were standing on (bug 2f717747).
///
/// An edge is named by the operator's own label when they gave it one;
/// otherwise by the side of the deck it faces plus how long it is. Two edges
/// can face the same way on an L-shaped deck — the canvas highlight on the
/// focused row is what separates those.
enum DeckEdgeNaming {

    /// Which way an edge faces, in screen space: y grows DOWNWARD, so the
    /// top of the canvas is north.
    enum Side: String, Equatable {
        case north
        case south
        case east
        case west

        var displayName: String {
            switch self {
            case .north: return "North"
            case .south: return "South"
            case .east:  return "East"
            case .west:  return "West"
            }
        }
    }

    /// The side an edge faces — the direction from the shape's centre out
    /// through the edge's midpoint, snapped to the dominant axis. Nil when
    /// the edge's vertices can't be resolved or it sits on the centre.
    static func side(ofEdgeId edgeId: String, in level: DeckLevel) -> Side? {
        guard let edge = level.edges.first(where: { $0.id == edgeId }),
              let start = level.vertices.first(where: { $0.id == edge.startVertexId }),
              let end = level.vertices.first(where: { $0.id == edge.endVertexId }),
              !level.vertices.isEmpty
        else { return nil }

        let centre = centroid(of: level.vertices.map(\.position))
        let midpoint = CGPoint(
            x: (start.position.x + end.position.x) / 2,
            y: (start.position.y + end.position.y) / 2
        )
        let dx = midpoint.x - centre.x
        let dy = midpoint.y - centre.y
        guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else { return nil }

        if abs(dx) >= abs(dy) {
            return dx > 0 ? .east : .west
        }
        return dy > 0 ? .south : .north
    }

    /// What the picker row reads. The operator's label wins outright; failing
    /// that, side plus length; failing that, a plain noun — never an invented
    /// identifier the operator can't see on the canvas.
    static func displayName(
        forEdgeId edgeId: String,
        in level: DeckLevel,
        system: MeasurementSystem
    ) -> String {
        let edge = level.edges.first(where: { $0.id == edgeId })

        if let label = edge?.label?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }

        let sideName = side(ofEdgeId: edgeId, in: level)?.displayName
        let length = edge?.dimension.map { DimensionEngine.format($0, system: system) }

        switch (sideName, length) {
        case let (side?, length?):
            return "\(side) edge \u{00b7} \(length)"
        case let (side?, nil):
            return "\(side) edge"
        case let (nil, length?):
            return "Edge \u{00b7} \(length)"
        case (nil, nil):
            return "Edge"
        }
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}
