import CoreGraphics
import Foundation

public struct DeckPlanOpeningGlyphAnchor: Equatable, Identifiable {
    public var id: String
    public var tag: String
    public var kind: OpeningKind
    public var point: CGPoint
    public var edgeStart: CGPoint
    public var edgeEnd: CGPoint
    public var tangent: CGVector
    public var normal: CGVector
    public var openingWidthPoints: CGFloat

    public init(
        id: String,
        tag: String,
        kind: OpeningKind,
        point: CGPoint,
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        tangent: CGVector,
        normal: CGVector,
        openingWidthPoints: CGFloat
    ) {
        self.id = id
        self.tag = tag
        self.kind = kind
        self.point = point
        self.edgeStart = edgeStart
        self.edgeEnd = edgeEnd
        self.tangent = tangent
        self.normal = normal
        self.openingWidthPoints = openingWidthPoints
    }
}

public enum DeckPlanOpeningOverlay {
    public static func openingGlyphAnchors(
        data: DeckDrawingData,
        transform: CGAffineTransform
    ) -> [DeckPlanOpeningGlyphAnchor] {
        guard let house = data.house, !house.openings.isEmpty else { return [] }

        let verticesById = Dictionary(uniqueKeysWithValues: data.allVertices.map { ($0.id, $0) })
        let edgesById = Dictionary(uniqueKeysWithValues: data.allEdges.map { ($0.id, $0) })
        let openingsById = Dictionary(uniqueKeysWithValues: house.openings.map { ($0.id, $0) })

        return HouseOpeningSchedule.rows(for: data).compactMap { row in
            guard let opening = openingsById[row.id],
                  let edge = edgesById[opening.edgeId],
                  edge.edgeType == .houseEdge,
                  let startVertex = verticesById[edge.startVertexId],
                  let endVertex = verticesById[edge.endVertexId] else {
                return nil
            }

            let start = startVertex.position.applying(transform)
            let end = endVertex.position.applying(transform)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let imageLength = hypot(dx, dy)
            let wallLengthInches = WallOpeningGeometry.wallLengthInches(edge: edge, in: data)
            guard imageLength > 0, wallLengthInches > 0 else { return nil }

            let clamped = WallOpeningGeometry.clamped(
                opening,
                wallLengthInches: wallLengthInches
            )
            let widthInches = min(max(0, clamped.widthInches), wallLengthInches)
            let centerInches = min(
                max(0, clamped.offsetAlongEdgeInches + widthInches / 2),
                wallLengthInches
            )
            let t = CGFloat(centerInches / wallLengthInches)
            let point = CGPoint(
                x: start.x + dx * t,
                y: start.y + dy * t
            )
            let tangent = CGVector(dx: dx / imageLength, dy: dy / imageLength)
            let normal = CGVector(dx: -tangent.dy, dy: tangent.dx)
            let widthPoints = CGFloat(widthInches / wallLengthInches) * imageLength

            return DeckPlanOpeningGlyphAnchor(
                id: opening.id,
                tag: row.calloutTag,
                kind: opening.kind,
                point: point,
                edgeStart: start,
                edgeEnd: end,
                tangent: tangent,
                normal: normal,
                openingWidthPoints: widthPoints
            )
        }
    }
}
