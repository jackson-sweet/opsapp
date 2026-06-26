import CoreGraphics
import Foundation

public enum AutoFramingEngine {
    public static let defaultJoistSpacingInches: Double = 16
    public static let defaultPostSpacingInches: Double = 72
    public static let defaultBlockingCapInches: Double = 96

    public static func generate(from data: DeckDrawingData, preset: LoadPreset) -> FramingPlan {
        let sources = geometrySources(from: data)
        let sets = sources.map { source in
            FramingMemberSet(
                levelId: source.levelId,
                members: generateMembers(for: source, scaleFactor: data.effectiveScaleFactor, preset: preset)
            )
        }

        return FramingPlan(
            members: sets,
            loadPreset: preset,
            generationSource: .auto,
            generatedAtSchemaVersion: nil
        )
    }

    public static func regenerate(
        from data: DeckDrawingData,
        existing: FramingPlan,
        preset: LoadPreset
    ) -> FramingPlan {
        var generated = generate(from: data, preset: preset)
        var preservedAnyLockedMember = false

        for setIndex in generated.members.indices {
            let levelId = generated.members[setIndex].levelId
            guard let existingSet = existing.members.first(where: { $0.levelId == levelId }) else { continue }

            let lockedMembers = existingSet.members.filter(\.locked)
            preservedAnyLockedMember = preservedAnyLockedMember || !lockedMembers.isEmpty

            var regeneratedMembers = generated.members[setIndex].members
                .filter { generatedMember in
                    !lockedMembers.contains(where: { isSameMemberShape($0, generatedMember) })
                }
            regeneratedMembers = reuseStableIDs(
                for: regeneratedMembers,
                from: existingSet.members.filter { !$0.locked }
            )
            regeneratedMembers.append(contentsOf: lockedMembers)
            generated.members[setIndex].members = regeneratedMembers
        }

        generated.generationSource = preservedAnyLockedMember ? .autoThenEdited : .auto
        return generated
    }

    private struct GeometrySource {
        let levelId: String
        let vertices: [DeckVertex]
        let edges: [DeckEdge]

        var positions: [CGPoint] {
            vertices.map(\.position)
        }
    }

    private static func geometrySources(from data: DeckDrawingData) -> [GeometrySource] {
        if data.isMultiLevel {
            return data.levels.map { level in
                GeometrySource(levelId: level.id, vertices: level.vertices, edges: level.edges)
            }
        }

        return [GeometrySource(levelId: "", vertices: data.vertices, edges: data.edges)]
    }

    private static func generateMembers(
        for source: GeometrySource,
        scaleFactor: Double,
        preset: LoadPreset
    ) -> [FramingMember] {
        let positions = source.positions
        guard positions.count >= 3, source.edges.count >= 3 else { return [] }

        let houseEdge = source.edges.first(where: { $0.edgeType == .houseEdge })
        let axis = FramingGeometry.joistAxis(
            forSurface: positions,
            edges: source.edges,
            houseEdge: houseEdge,
            scaleFactor: scaleFactor
        )
        let perimeter = FramingGeometry.rimAndLedgerSegments(surface: positions, edges: source.edges)
        let beamLines = FramingGeometry.beamLines(
            surface: positions,
            joistAxis: axis.joist,
            houseEdge: houseEdge,
            scaleFactor: scaleFactor
        )
        let joistLines = FramingGeometry.joistLines(
            surface: positions,
            axis: axis.joist,
            spacingInchesOC: defaultJoistSpacingInches,
            scaleFactor: scaleFactor
        )
        let maxJoistSpanInches = joistLines
            .map { distance($0.start, $0.end) / max(scaleFactor, 0.000001) }
            .max() ?? 0
        let blockingRows = FramingGeometry.blockingRows(
            joistSpanInches: maxJoistSpanInches,
            surface: positions,
            joistAxis: axis.joist,
            capInches: defaultBlockingCapInches,
            scaleFactor: scaleFactor
        )

        var members: [FramingMember] = []
        appendSegments(
            perimeter.ledger,
            role: .ledger,
            nominalSize: .twoByTen,
            plyCount: 1,
            levelId: source.levelId,
            preset: preset,
            into: &members
        )
        appendSegments(
            perimeter.rim,
            role: .rimBand,
            nominalSize: .twoByEight,
            plyCount: 1,
            levelId: source.levelId,
            preset: preset,
            into: &members
        )
        appendSegments(
            beamLines,
            role: .beam,
            nominalSize: .twoByTen,
            plyCount: 2,
            levelId: source.levelId,
            preset: preset,
            into: &members
        )
        appendSegments(
            joistLines,
            role: .joist,
            nominalSize: .twoByEight,
            plyCount: 1,
            spacingInchesOC: defaultJoistSpacingInches,
            levelId: source.levelId,
            preset: preset,
            into: &members
        )
        appendSegments(
            blockingRows,
            role: .blocking,
            nominalSize: .twoByEight,
            plyCount: 1,
            levelId: source.levelId,
            preset: preset,
            into: &members
        )

        for beam in beamLines {
            let posts = FramingGeometry.postPoints(
                alongBeam: beam.start,
                end: beam.end,
                maxSpacingInches: defaultPostSpacingInches,
                scaleFactor: scaleFactor
            )
            for (index, point) in posts.enumerated() {
                members.append(member(
                    id: stableID(levelId: source.levelId, role: .post, index: index, start: point, end: point),
                    role: .post,
                    start: point,
                    end: point,
                    nominalSize: .sixBySix,
                    plyCount: 1,
                    spacingInchesOC: nil,
                    preset: preset
                ))
            }
        }

        return members
    }

    private static func appendSegments(
        _ segments: [FramingGeometry.Segment],
        role: FramingRole,
        nominalSize: LumberSize,
        plyCount: Int,
        spacingInchesOC: Double? = nil,
        levelId: String,
        preset: LoadPreset,
        into members: inout [FramingMember]
    ) {
        for (index, segment) in segments.enumerated() {
            members.append(member(
                id: stableID(levelId: levelId, role: role, index: index, start: segment.start, end: segment.end),
                role: role,
                start: segment.start,
                end: segment.end,
                nominalSize: nominalSize,
                plyCount: plyCount,
                spacingInchesOC: spacingInchesOC,
                preset: preset
            ))
        }
    }

    private static func member(
        id: String,
        role: FramingRole,
        start: CGPoint,
        end: CGPoint,
        nominalSize: LumberSize,
        plyCount: Int,
        spacingInchesOC: Double?,
        preset: LoadPreset
    ) -> FramingMember {
        FramingMember(
            id: id,
            role: role,
            start: start,
            end: end,
            nominalSize: nominalSize,
            plyCount: plyCount,
            spacingInchesOC: spacingInchesOC,
            species: preset.species,
            grade: preset.grade,
            sizing: nil,
            locked: false
        )
    }

    private static func reuseStableIDs(
        for generatedMembers: [FramingMember],
        from existingMembers: [FramingMember]
    ) -> [FramingMember] {
        var usedExistingIds: Set<String> = []
        return generatedMembers.map { generated in
            guard let match = existingMembers.first(where: {
                !usedExistingIds.contains($0.id) && isSameMemberShape($0, generated)
            }) else {
                return generated
            }
            usedExistingIds.insert(match.id)
            return copy(generated, id: match.id)
        }
    }

    private static func isSameMemberShape(_ lhs: FramingMember, _ rhs: FramingMember) -> Bool {
        guard lhs.role == rhs.role else { return false }

        let direct = distance(lhs.start, rhs.start) + distance(lhs.end, rhs.end)
        let reversed = distance(lhs.start, rhs.end) + distance(lhs.end, rhs.start)
        return min(direct, reversed) <= 4.0
    }

    private static func copy(_ member: FramingMember, id: String) -> FramingMember {
        FramingMember(
            id: id,
            role: member.role,
            start: member.start,
            end: member.end,
            nominalSize: member.nominalSize,
            plyCount: member.plyCount,
            spacingInchesOC: member.spacingInchesOC,
            species: member.species,
            grade: member.grade,
            sizing: member.sizing,
            locked: member.locked
        )
    }

    private static func stableID(
        levelId: String,
        role: FramingRole,
        index: Int,
        start: CGPoint,
        end: CGPoint
    ) -> String {
        let level = levelId.isEmpty ? "single" : levelId
        return [
            "auto",
            level,
            role.rawValue,
            String(index),
            roundedCoordinate(start.x),
            roundedCoordinate(start.y),
            roundedCoordinate(end.x),
            roundedCoordinate(end.y),
        ].joined(separator: "-")
    }

    private static func roundedCoordinate(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private static func distance(_ start: CGPoint, _ end: CGPoint) -> Double {
        hypot(Double(end.x - start.x), Double(end.y - start.y))
    }
}
