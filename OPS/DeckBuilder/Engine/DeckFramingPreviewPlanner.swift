import CoreGraphics
import CryptoKit
import Foundation

/// Resolves the framing that the embedded OPS client may display. Persisted
/// Deckset member sets remain authoritative; only legacy or entirely missing
/// level sets receive deterministic, in-memory preview framing.
enum DeckFramingPreviewPlanner {
    private static let joistSpacingInches = 16.0
    private static let blockingRunCapInches = 48.0
    private static let beamSpanCapInches = 96.0
    private static let beamEdgeSetbackInches = 12.0
    private static let postSpacingCapInches = 72.0
    private static let geometryEpsilon: CGFloat = 0.001

    static func resolvedPlan(for drawing: DeckDrawingData) -> FramingPlan {
        let levels = geometryLevels(in: drawing)

        if var persisted = drawing.framing {
            let persistedLevelIds = Set(persisted.members.map(\.levelId))
            for level in levels where !persistedLevelIds.contains(level.id) {
                persisted.members.append(generatedSet(for: level, scaleFactor: drawing.effectiveScaleFactor))
            }
            return persisted
        }

        return FramingPlan(
            members: levels.map { generatedSet(for: $0, scaleFactor: drawing.effectiveScaleFactor) },
            generationSource: .auto,
            generatedAtSchemaVersion: drawing.schemaVersion
        )
    }

    private struct GeometryLevel {
        let id: String
        let vertices: [DeckVertex]
        let edges: [DeckEdge]
        let surfaces: [DetectedSurface]
    }

    private struct VertexPair: Hashable, Comparable {
        let first: String
        let second: String

        init(_ lhs: String, _ rhs: String) {
            if lhs <= rhs {
                first = lhs
                second = rhs
            } else {
                first = rhs
                second = lhs
            }
        }

        static func < (lhs: VertexPair, rhs: VertexPair) -> Bool {
            lhs.first == rhs.first ? lhs.second < rhs.second : lhs.first < rhs.first
        }
    }

    private struct Boundary {
        let pair: VertexPair
        let edge: DeckEdge
        let start: CGPoint
        let end: CGPoint

        var length: Double { SnapEngine.distance(start, end) }
    }

    private static func geometryLevels(in drawing: DeckDrawingData) -> [GeometryLevel] {
        if drawing.isMultiLevel {
            return drawing.levels.map {
                GeometryLevel(
                    id: $0.id,
                    vertices: $0.vertices,
                    edges: $0.edges,
                    surfaces: $0.detectedSurfaces
                )
            }
        }
        return [GeometryLevel(
            id: "",
            vertices: drawing.vertices,
            edges: drawing.edges,
            surfaces: drawing.detectedSurfaces
        )]
    }

    private static func generatedSet(
        for level: GeometryLevel,
        scaleFactor: Double
    ) -> FramingMemberSet {
        guard !level.surfaces.isEmpty, scaleFactor > 0 else {
            return FramingMemberSet(levelId: level.id, members: [])
        }

        let edgeByPair = preferredEdgesByPair(level.edges)
        let incidence = surfaceIncidence(level.surfaces)
        var members: [FramingMember] = []

        for surface in level.surfaces {
            let boundaries = boundaries(
                of: surface,
                edgeByPair: edgeByPair,
                incidence: incidence,
                exteriorOnly: true
            )
            guard let reference = referenceBoundary(from: boundaries),
                  let along = FramingGeometry.unit(CGVector(
                    dx: reference.end.x - reference.start.x,
                    dy: reference.end.y - reference.start.y
                  )),
                  let inward = FramingGeometry.inwardNormal(
                    edgeStart: reference.start,
                    edgeEnd: reference.end,
                    surface: surface.positions
                  ) else { continue }

            members.append(contentsOf: perimeterMembers(
                boundaries: boundaries,
                levelId: level.id
            ))
            members.append(contentsOf: joistMembers(
                surface: surface.positions,
                joistAxis: inward,
                beamAxis: along,
                scaleFactor: scaleFactor,
                levelId: level.id
            ))

            let beams = beamMembers(
                surface: surface.positions,
                reference: reference,
                beamAxis: along,
                joistAxis: inward,
                attached: boundaries.contains(where: { $0.edge.edgeType == .houseEdge }),
                scaleFactor: scaleFactor,
                levelId: level.id
            )
            members.append(contentsOf: beams)
            members.append(contentsOf: postMembers(
                beneath: beams,
                scaleFactor: scaleFactor,
                levelId: level.id
            ))

            if let span = FramingGeometry.projectionBounds(of: surface.positions, onto: inward) {
                let spanInches = Double(span.max - span.min) / scaleFactor
                let blocking = FramingGeometry.blockingRows(
                    joistSpanInches: spanInches,
                    surface: surface.positions,
                    joistAxis: inward,
                    capInches: blockingRunCapInches,
                    scaleFactor: scaleFactor
                )
                members.append(contentsOf: blocking.map {
                    makeMember(
                        role: .blocking,
                        start: $0.start,
                        end: $0.end,
                        levelId: level.id,
                        nominalSize: .twoByEight
                    )
                })
            }
        }

        return FramingMemberSet(levelId: level.id, members: deduplicated(members))
    }

    private static func preferredEdgesByPair(_ edges: [DeckEdge]) -> [VertexPair: DeckEdge] {
        var result: [VertexPair: DeckEdge] = [:]
        for edge in edges {
            let pair = VertexPair(edge.startVertexId, edge.endVertexId)
            guard let existing = result[pair] else {
                result[pair] = edge
                continue
            }
            if edge.edgeType == .houseEdge, existing.edgeType != .houseEdge {
                result[pair] = edge
            } else if edge.edgeType == existing.edgeType, edge.id < existing.id {
                result[pair] = edge
            }
        }
        return result
    }

    private static func surfaceIncidence(_ surfaces: [DetectedSurface]) -> [VertexPair: Int] {
        var surfaceIdsByPair: [VertexPair: Set<String>] = [:]
        for surface in surfaces {
            for index in surface.vertexIds.indices {
                let next = (index + 1) % surface.vertexIds.count
                surfaceIdsByPair[VertexPair(surface.vertexIds[index], surface.vertexIds[next]), default: []]
                    .insert(surface.id)
            }
        }
        return surfaceIdsByPair.mapValues(\.count)
    }

    private static func boundaries(
        of surface: DetectedSurface,
        edgeByPair: [VertexPair: DeckEdge],
        incidence: [VertexPair: Int],
        exteriorOnly: Bool
    ) -> [Boundary] {
        surface.vertexIds.indices.compactMap { index in
            let next = (index + 1) % surface.vertexIds.count
            let pair = VertexPair(surface.vertexIds[index], surface.vertexIds[next])
            guard (!exteriorOnly || incidence[pair] == 1),
                  let edge = edgeByPair[pair] else { return nil }
            return Boundary(
                pair: pair,
                edge: edge,
                start: surface.positions[index],
                end: surface.positions[next]
            )
        }
    }

    private static func referenceBoundary(from boundaries: [Boundary]) -> Boundary? {
        let house = boundaries.filter { $0.edge.edgeType == .houseEdge }
        let candidates = house.isEmpty ? boundaries : house
        return candidates.sorted {
            if abs($0.length - $1.length) > 0.000_001 { return $0.length > $1.length }
            return $0.pair < $1.pair
        }.first
    }

    private static func perimeterMembers(
        boundaries: [Boundary],
        levelId: String
    ) -> [FramingMember] {
        boundaries.map { boundary in
            let role: FramingRole = boundary.edge.edgeType == .houseEdge ? .ledger : .rimBand
            return makeMember(
                role: role,
                start: boundary.start,
                end: boundary.end,
                levelId: levelId,
                nominalSize: .twoByEight
            )
        }
    }

    private static func joistMembers(
        surface: [CGPoint],
        joistAxis: CGVector,
        beamAxis: CGVector,
        scaleFactor: Double,
        levelId: String
    ) -> [FramingMember] {
        guard let bounds = FramingGeometry.projectionBounds(of: surface, onto: beamAxis) else { return [] }
        let spacing = CGFloat(joistSpacingInches * scaleFactor)
        guard spacing > geometryEpsilon else { return [] }

        var projection = bounds.min + spacing
        var members: [FramingMember] = []
        while projection < bounds.max - geometryEpsilon {
            let segments = FramingGeometry.clippedLine(
                to: surface,
                direction: joistAxis,
                normal: beamAxis,
                projection: projection
            )
            members.append(contentsOf: segments.map {
                makeMember(
                    role: .joist,
                    start: $0.start,
                    end: $0.end,
                    levelId: levelId,
                    nominalSize: .twoByEight,
                    spacingInchesOC: joistSpacingInches
                )
            })
            projection += spacing
        }
        return members
    }

    private static func beamMembers(
        surface: [CGPoint],
        reference: Boundary,
        beamAxis: CGVector,
        joistAxis: CGVector,
        attached: Bool,
        scaleFactor: Double,
        levelId: String
    ) -> [FramingMember] {
        guard let bounds = FramingGeometry.projectionBounds(of: surface, onto: joistAxis) else { return [] }

        let setback = CGFloat(beamEdgeSetbackInches * scaleFactor)
        let cap = CGFloat(beamSpanCapInches * scaleFactor)
        let projections: [CGFloat]
        if attached {
            let ledgerProjection = FramingGeometry.dot(
                CGPoint(x: (reference.start.x + reference.end.x) / 2,
                        y: (reference.start.y + reference.end.y) / 2),
                joistAxis
            )
            let available = bounds.max - ledgerProjection
            guard available > geometryEpsilon else { return [] }
            let target = bounds.max - min(setback, available / 2)
            let supportedSpan = max(target - ledgerProjection, geometryEpsilon)
            let beamCount = max(1, Int(ceil(supportedSpan / max(cap, geometryEpsilon))))
            projections = (1...beamCount).map {
                ledgerProjection + supportedSpan * CGFloat($0) / CGFloat(beamCount)
            }
        } else {
            let total = bounds.max - bounds.min
            guard total > geometryEpsilon else { return [] }
            let first = bounds.min + min(setback, total / 2)
            let last = bounds.max - min(setback, total / 2)
            if last - first <= geometryEpsilon {
                projections = [(bounds.min + bounds.max) / 2]
            } else {
                let intervalCount = max(1, Int(ceil((last - first) / max(cap, geometryEpsilon))))
                projections = (0...intervalCount).map {
                    first + (last - first) * CGFloat($0) / CGFloat(intervalCount)
                }
            }
        }

        return projections.flatMap { projection in
            FramingGeometry.clippedLine(
                to: surface,
                direction: beamAxis,
                normal: joistAxis,
                projection: projection
            ).map {
                makeMember(
                    role: .beam,
                    start: $0.start,
                    end: $0.end,
                    levelId: levelId,
                    nominalSize: .twoByTen,
                    plyCount: 3
                )
            }
        }
    }

    private static func postMembers(
        beneath beams: [FramingMember],
        scaleFactor: Double,
        levelId: String
    ) -> [FramingMember] {
        let cap = postSpacingCapInches * scaleFactor
        guard cap > 0 else { return [] }

        return beams.flatMap { beam -> [FramingMember] in
            let length = SnapEngine.distance(beam.start, beam.end)
            guard length > Double(geometryEpsilon) else { return [] }
            let intervalCount = max(1, Int(ceil(length / cap)))
            return (0...intervalCount).map { index in
                let fraction = CGFloat(index) / CGFloat(intervalCount)
                let point = CGPoint(
                    x: beam.start.x + (beam.end.x - beam.start.x) * fraction,
                    y: beam.start.y + (beam.end.y - beam.start.y) * fraction
                )
                return makeMember(
                    role: .post,
                    start: point,
                    end: point,
                    levelId: levelId,
                    nominalSize: .sixBySix
                )
            }
        }
    }

    private static func makeMember(
        role: FramingRole,
        start: CGPoint,
        end: CGPoint,
        levelId: String,
        nominalSize: LumberSize,
        plyCount: Int = 1,
        spacingInchesOC: Double? = nil
    ) -> FramingMember {
        let canonical = canonicalEndpoints(start, end)
        let signature = geometrySignature(
            role: role,
            start: canonical.start,
            end: canonical.end,
            levelId: levelId
        )
        return FramingMember(
            id: stableID(for: signature),
            role: role,
            start: canonical.start,
            end: canonical.end,
            nominalSize: nominalSize,
            plyCount: plyCount,
            spacingInchesOC: spacingInchesOC,
            locked: false
        )
    }

    private static func deduplicated(_ members: [FramingMember]) -> [FramingMember] {
        var bySignature: [String: FramingMember] = [:]
        for member in members {
            let signature = geometrySignature(
                role: member.role,
                start: member.start,
                end: member.end,
                levelId: ""
            )
            if bySignature[signature] == nil { bySignature[signature] = member }
        }
        return bySignature.values.sorted {
            if $0.role.rawValue != $1.role.rawValue { return $0.role.rawValue < $1.role.rawValue }
            return $0.id < $1.id
        }
    }

    private static func geometrySignature(
        role: FramingRole,
        start: CGPoint,
        end: CGPoint,
        levelId: String
    ) -> String {
        let canonical = canonicalEndpoints(start, end)
        return [
            levelId,
            role.rawValue,
            pointSignature(canonical.start),
            pointSignature(canonical.end),
        ].joined(separator: "|")
    }

    private static func pointSignature(_ point: CGPoint) -> String {
        let x = Int64((Double(point.x) * 1_000).rounded())
        let y = Int64((Double(point.y) * 1_000).rounded())
        return "\(x):\(y)"
    }

    private static func canonicalEndpoints(_ lhs: CGPoint, _ rhs: CGPoint) -> (start: CGPoint, end: CGPoint) {
        if lhs.x < rhs.x || (abs(lhs.x - rhs.x) <= 0.000_001 && lhs.y <= rhs.y) {
            return (lhs, rhs)
        }
        return (rhs, lhs)
    }

    private static func stableID(for signature: String) -> String {
        let digest = SHA256.hash(data: Data(signature.utf8))
        let suffix = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "framing-\(suffix)"
    }
}
