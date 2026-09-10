import CoreGraphics
import CryptoKit
import Foundation

/// Resolves the framing that the embedded OPS client may display. Persisted
/// Deckset member sets remain authoritative; only legacy or entirely missing
/// level sets receive deterministic, in-memory preview framing.
enum DeckFramingPreviewPlanner {
    /// Not a span limit, and no cited source governs it, so it stays as it was
    /// rather than being replaced with an invented number.
    private static let blockingRunCapInches = 48.0

    /// The preview has no deck-height input, so it takes the conservative branch
    /// of CWC Table 3b note 2 and assumes a guard is required. That forces joists
    /// to nominal 2x8 or larger — which is also what the old heuristic drew.
    private static let assumesGuardRequired = true

    /// Drawn only where the published tables give no beam selection. This is the
    /// appearance the previous heuristic used everywhere; it makes no table
    /// claim, and any layout showing it is flagged as outside the tables.
    private static let unpublishedBeamFallbackSize = LumberSize.twoByTen
    private static let unpublishedBeamFallbackPlyCount = 3

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

    /// Whether every layout this planner would generate for the drawing sits
    /// inside the published span tables.
    ///
    /// Drives the extra line of the in-product disclosure — a deck deeper than
    /// one published joist span, or one whose entering span runs off the end of
    /// the beam tables, is a sketch rather than a table result and must say so.
    /// Persisted Deckset framing is authored elsewhere and is never judged here.
    static func generatedFramingIsPrescriptive(for drawing: DeckDrawingData) -> Bool {
        let persistedLevelIds = Set((drawing.framing?.members ?? []).map(\.levelId))
        let scaleFactor = drawing.effectiveScaleFactor

        for level in geometryLevels(in: drawing) where !persistedLevelIds.contains(level.id) {
            for context in surfaceContexts(for: level) {
                guard let layout = solvedLayout(context, scaleFactor: scaleFactor) else { continue }
                if !layout.solution.isPrescriptive { return false }
            }
        }
        return true
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

    /// One surface with its reference edge and framing axes resolved.
    private struct SurfaceContext {
        let surface: DetectedSurface
        let boundaries: [Boundary]
        let reference: Boundary
        /// Along the reference edge — the direction beams run.
        let along: CGVector
        /// Into the surface from the reference edge — the direction joists run.
        let inward: CGVector
        /// True when a boundary of this surface is a house edge.
        let attached: Bool
    }

    /// A solved framing layout bound to one surface's canvas geometry. All
    /// projections are canvas units along the joist axis.
    private struct SolvedLayout {
        let solution: DeckFramingSolver.FramingSolution
        /// True when the surface has a house edge, so joists cantilever past the
        /// outer beam only. Free-standing surfaces cantilever past both.
        let attached: Bool
        /// Beam positions, ordered outward from the reference edge.
        let beamProjections: [CGFloat]
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

        var members: [FramingMember] = []

        for context in surfaceContexts(for: level) {
            let surface = context.surface
            let along = context.along
            let inward = context.inward

            members.append(contentsOf: perimeterMembers(
                boundaries: context.boundaries,
                levelId: level.id
            ))

            guard let layout = solvedLayout(context, scaleFactor: scaleFactor) else { continue }

            members.append(contentsOf: joistMembers(
                surface: surface.positions,
                joistAxis: inward,
                beamAxis: along,
                layout: layout,
                scaleFactor: scaleFactor,
                levelId: level.id
            ))

            let beams = beamMembers(
                surface: surface.positions,
                beamAxis: along,
                joistAxis: inward,
                layout: layout,
                levelId: level.id
            )
            members.append(contentsOf: beams)
            members.append(contentsOf: postMembers(
                beneath: beams,
                postSpacingFeet: layout.solution.postSpacingFeet,
                postSize: layout.solution.postSize,
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

    /// Every surface on a level that can carry framing, with its reference edge
    /// and axes already resolved. Shared by member generation and by the
    /// in-product disclosure, so both read the same layout.
    private static func surfaceContexts(for level: GeometryLevel) -> [SurfaceContext] {
        let edgeByPair = preferredEdgesByPair(level.edges)
        let incidence = surfaceIncidence(level.surfaces)

        return level.surfaces.compactMap { surface in
            let surfaceBoundaries = boundaries(
                of: surface,
                edgeByPair: edgeByPair,
                incidence: incidence,
                exteriorOnly: true
            )
            guard let reference = referenceBoundary(from: surfaceBoundaries),
                  let along = FramingGeometry.unit(CGVector(
                    dx: reference.end.x - reference.start.x,
                    dy: reference.end.y - reference.start.y
                  )),
                  let inward = FramingGeometry.inwardNormal(
                    edgeStart: reference.start,
                    edgeEnd: reference.end,
                    surface: surface.positions
                  ) else { return nil }

            return SurfaceContext(
                surface: surface,
                boundaries: surfaceBoundaries,
                reference: reference,
                along: along,
                inward: inward,
                attached: surfaceBoundaries.contains { $0.edge.edgeType == .houseEdge }
            )
        }
    }

    /// Solves this surface against the published tables. Returns nil when the
    /// surface has no usable depth or length.
    private static func solvedLayout(
        _ context: SurfaceContext,
        scaleFactor: Double
    ) -> SolvedLayout? {
        let surface = context.surface.positions
        let reference = context.reference
        let joistAxis = context.inward
        let attached = context.attached

        guard scaleFactor > 0,
              let joistBounds = FramingGeometry.projectionBounds(of: surface, onto: joistAxis),
              let beamBounds = FramingGeometry.projectionBounds(of: surface, onto: context.along) else { return nil }

        // Depth runs from the ledger, or from the near outer edge when there is none.
        let referenceProjection: CGFloat = attached
            ? FramingGeometry.dot(
                CGPoint(x: (reference.start.x + reference.end.x) / 2,
                        y: (reference.start.y + reference.end.y) / 2),
                joistAxis
              )
            : joistBounds.min

        let depth = joistBounds.max - referenceProjection
        let beamLength = beamBounds.max - beamBounds.min
        guard depth > geometryEpsilon, beamLength > geometryEpsilon else { return nil }

        guard let solution = DeckFramingSolver.solve(DeckFramingSolver.Input(
            depthInches: Double(depth) / scaleFactor,
            beamLengthInches: Double(beamLength) / scaleFactor,
            isLedgerAttached: attached,
            guardRequired: assumesGuardRequired
        )) else { return nil }

        return SolvedLayout(
            solution: solution,
            attached: attached,
            beamProjections: solution.beamLines.map {
                referenceProjection + CGFloat($0.offsetInches * scaleFactor)
            }
        )
    }

    private static func joistMembers(
        surface: [CGPoint],
        joistAxis: CGVector,
        beamAxis: CGVector,
        layout: SolvedLayout,
        scaleFactor: Double,
        levelId: String
    ) -> [FramingMember] {
        guard let bounds = FramingGeometry.projectionBounds(of: surface, onto: beamAxis) else { return [] }
        let spacing = CGFloat(layout.solution.joistSpacingInchesOC * scaleFactor)
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
            for segment in segments {
                members.append(contentsOf: joistRunMembers(
                    for: segment,
                    joistAxis: joistAxis,
                    layout: layout,
                    levelId: levelId
                ))
            }
            projection += spacing
        }
        return members
    }

    /// Splits one joist chord at every beam it crosses. A piece between two
    /// supports is a joist run; a piece hanging past the outermost beam — or,
    /// free-standing, inboard of the innermost one — is the cantilever.
    private static func joistRunMembers(
        for segment: FramingGeometry.Segment,
        joistAxis: CGVector,
        layout: SolvedLayout,
        levelId: String
    ) -> [FramingMember] {
        guard let firstBeam = layout.beamProjections.first,
              let lastBeam = layout.beamProjections.last else { return [] }

        let startProjection = FramingGeometry.dot(segment.start, joistAxis)
        let endProjection = FramingGeometry.dot(segment.end, joistAxis)
        let lower = min(startProjection, endProjection)
        let upper = max(startProjection, endProjection)
        guard upper - lower > geometryEpsilon else { return [] }

        var cuts = [lower, upper]
        cuts.append(contentsOf: layout.beamProjections.filter {
            $0 > lower + geometryEpsilon && $0 < upper - geometryEpsilon
        })
        cuts.sort()

        var members: [FramingMember] = []
        for index in 0..<(cuts.count - 1) {
            guard let piece = portion(
                of: segment,
                along: joistAxis,
                from: cuts[index],
                to: cuts[index + 1]
            ) else { continue }

            let pastOuterBeam = cuts[index] >= lastBeam - geometryEpsilon
            let insideNearBeam = !layout.attached && cuts[index + 1] <= firstBeam + geometryEpsilon
            members.append(makeMember(
                role: (pastOuterBeam || insideNearBeam) ? .cantilever : .joist,
                start: piece.start,
                end: piece.end,
                levelId: levelId,
                nominalSize: layout.solution.joistSize,
                spacingInchesOC: layout.solution.joistSpacingInchesOC,
                species: DeckSpanTables.species,
                grade: DeckSpanTables.grade
            ))
        }
        return members
    }

    /// The part of a segment whose projection onto `axis` falls between `from`
    /// and `to`. The segment is parallel to the axis, so projection varies
    /// linearly along it.
    private static func portion(
        of segment: FramingGeometry.Segment,
        along axis: CGVector,
        from lower: CGFloat,
        to upper: CGFloat
    ) -> FramingGeometry.Segment? {
        let startProjection = FramingGeometry.dot(segment.start, axis)
        let endProjection = FramingGeometry.dot(segment.end, axis)
        let span = endProjection - startProjection
        guard abs(span) > geometryEpsilon else { return nil }

        let clampedLower = max(min(startProjection, endProjection), lower)
        let clampedUpper = min(max(startProjection, endProjection), upper)
        guard clampedUpper - clampedLower > geometryEpsilon else { return nil }

        func point(at projection: CGFloat) -> CGPoint {
            let fraction = (projection - startProjection) / span
            return CGPoint(
                x: segment.start.x + (segment.end.x - segment.start.x) * fraction,
                y: segment.start.y + (segment.end.y - segment.start.y) * fraction
            )
        }
        return FramingGeometry.Segment(
            start: point(at: clampedLower),
            end: point(at: clampedUpper)
        )
    }

    private static func beamMembers(
        surface: [CGPoint],
        beamAxis: CGVector,
        joistAxis: CGVector,
        layout: SolvedLayout,
        levelId: String
    ) -> [FramingMember] {
        layout.beamProjections.enumerated().flatMap { index, projection -> [FramingMember] in
            let line = layout.solution.beamLines[index]
            return FramingGeometry.clippedLine(
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
                    nominalSize: line.selection?.nominalSize ?? unpublishedBeamFallbackSize,
                    plyCount: line.selection?.plyCount ?? unpublishedBeamFallbackPlyCount,
                    species: DeckSpanTables.species,
                    grade: DeckSpanTables.grade
                )
            }
        }
    }

    private static func postMembers(
        beneath beams: [FramingMember],
        postSpacingFeet: Double,
        postSize: LumberSize,
        scaleFactor: Double,
        levelId: String
    ) -> [FramingMember] {
        let cap = postSpacingFeet * 12 * scaleFactor
        guard cap > 0 else { return [] }

        return beams.flatMap { beam -> [FramingMember] in
            let length = SnapEngine.distance(beam.start, beam.end)
            guard length > Double(geometryEpsilon) else { return [] }
            // A post at each end of the beam plus one at every interval between.
            // The end posts stay deliberately: the beam now sits a full published
            // cantilever inboard of the outer edge, so an end post no longer lands
            // on the deck edge, and never on a corner vertex.
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
                    nominalSize: postSize,
                    species: DeckSpanTables.species,
                    grade: DeckSpanTables.grade
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
        spacingInchesOC: Double? = nil,
        species: WoodSpecies? = nil,
        grade: LumberGrade? = nil
    ) -> FramingMember {
        let canonical = canonicalEndpoints(start, end)
        let signature = geometrySignature(
            role: role,
            start: canonical.start,
            end: canonical.end,
            levelId: levelId
        )
        // `sizing` stays nil: this is a picture, not an engineered design.
        return FramingMember(
            id: stableID(for: signature),
            role: role,
            start: canonical.start,
            end: canonical.end,
            nominalSize: nominalSize,
            plyCount: plyCount,
            spacingInchesOC: spacingInchesOC,
            species: species,
            grade: grade,
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
