import CoreGraphics
import Foundation

public enum HouseElevationProjector {
    public struct Elevation: Equatable {
        public var edgeId: String
        public var wallLengthInches: Double
        public var gradeYInches: Double
        public var deckSurfaceYInches: Double
        public var wallTopYInches: Double
        public var openings: [ProjectedOpening]
        public var storyLines: [Double]

        public init(
            edgeId: String,
            wallLengthInches: Double,
            gradeYInches: Double = 0,
            deckSurfaceYInches: Double,
            wallTopYInches: Double,
            openings: [ProjectedOpening],
            storyLines: [Double]
        ) {
            self.edgeId = edgeId
            self.wallLengthInches = wallLengthInches
            self.gradeYInches = gradeYInches
            self.deckSurfaceYInches = deckSurfaceYInches
            self.wallTopYInches = wallTopYInches
            self.openings = openings
            self.storyLines = storyLines
        }
    }

    public struct ProjectedOpening: Equatable, Identifiable {
        public var id: String
        public var kind: OpeningKind
        public var rect: CGRect
        public var calloutTag: String

        public init(
            id: String,
            kind: OpeningKind,
            rect: CGRect,
            calloutTag: String
        ) {
            self.id = id
            self.kind = kind
            self.rect = rect
            self.calloutTag = calloutTag
        }
    }

    public static func project(
        edgeId: String,
        levelId: String?,
        data: DeckDrawingData
    ) -> Elevation? {
        guard let house = data.house,
              let resolved = resolveEdge(edgeId: edgeId, levelId: levelId, data: data),
              resolved.edge.edgeType == .houseEdge else {
            return nil
        }

        let wallLength = wallLengthInches(edge: resolved.edge, level: resolved.edgeLevel, data: data)
        let deckSurfaceY = deckSurfaceYInches(
            house: house,
            selectedLevel: resolved.selectedLevel,
            edgeLevel: resolved.edgeLevel,
            data: data
        )
        let firstStoryHeight = inches(fromFeet: house.storyHeights.first ?? 0)
        let storyLines = storyLineYValues(storyHeightsFeet: house.storyHeights, deckSurfaceYInches: deckSurfaceY)
        let calloutTags = calloutTagsByOpeningId(for: house.openings)
        let projectedOpenings = house.openings
            .filter { $0.edgeId == edgeId }
            .sorted { lhs, rhs in
                if lhs.offsetAlongEdgeInches != rhs.offsetAlongEdgeInches {
                    return lhs.offsetAlongEdgeInches < rhs.offsetAlongEdgeInches
                }
                return lhs.id < rhs.id
            }
            .map { opening in
                var rect = WallOpeningGeometry.cutoutRect2D(opening)
                rect.origin.y += deckSurfaceY
                return ProjectedOpening(
                    id: opening.id,
                    kind: opening.kind,
                    rect: rect,
                    calloutTag: calloutTags[opening.id] ?? ""
                )
            }

        return Elevation(
            edgeId: edgeId,
            wallLengthInches: wallLength,
            deckSurfaceYInches: deckSurfaceY,
            wallTopYInches: deckSurfaceY + firstStoryHeight,
            openings: projectedOpenings,
            storyLines: storyLines
        )
    }

    public static func projectAllFaces(_ data: DeckDrawingData) -> [Elevation] {
        if data.isMultiLevel {
            return data.levels.flatMap { level in
                level.edges.compactMap { edge in
                    guard edge.edgeType == .houseEdge else { return nil }
                    return project(edgeId: edge.id, levelId: level.id, data: data)
                }
            }
        }

        return data.edges.compactMap { edge in
            guard edge.edgeType == .houseEdge else { return nil }
            return project(edgeId: edge.id, levelId: nil, data: data)
        }
    }

    private struct ResolvedEdge {
        var edge: DeckEdge
        var selectedLevel: DeckLevel?
        var edgeLevel: DeckLevel?
    }

    private static func resolveEdge(
        edgeId: String,
        levelId: String?,
        data: DeckDrawingData
    ) -> ResolvedEdge? {
        let selectedLevel = levelId.flatMap { targetId in
            data.levels.first { $0.id == targetId }
        }

        if let selectedLevel,
           let edge = selectedLevel.edges.first(where: { $0.id == edgeId }) {
            return ResolvedEdge(edge: edge, selectedLevel: selectedLevel, edgeLevel: selectedLevel)
        }

        if let edge = data.edges.first(where: { $0.id == edgeId }) {
            return ResolvedEdge(edge: edge, selectedLevel: selectedLevel, edgeLevel: nil)
        }

        for level in data.levels {
            if let edge = level.edges.first(where: { $0.id == edgeId }) {
                return ResolvedEdge(edge: edge, selectedLevel: selectedLevel, edgeLevel: level)
            }
        }

        return nil
    }

    private static func wallLengthInches(
        edge: DeckEdge,
        level: DeckLevel?,
        data: DeckDrawingData
    ) -> Double {
        guard let level else {
            return WallOpeningGeometry.wallLengthInches(edge: edge, in: data)
        }

        var scoped = DeckDrawingData()
        scoped.vertices = level.vertices
        scoped.edges = level.edges
        scoped.scaleFactor = data.scaleFactor
        return WallOpeningGeometry.wallLengthInches(edge: edge, in: scoped)
    }

    private static func deckSurfaceYInches(
        house: HouseModel,
        selectedLevel: DeckLevel?,
        edgeLevel: DeckLevel?,
        data: DeckDrawingData
    ) -> Double {
        if let floorLineFeet = house.floorLineFeet {
            return inches(fromFeet: floorLineFeet)
        }

        if let levelElevation = selectedLevel?.elevation ?? edgeLevel?.elevation {
            return inches(fromFeet: levelElevation)
        }

        if let overallElevation = data.overallElevation {
            return inches(fromFeet: overallElevation)
        }

        return 0
    }

    private static func storyLineYValues(
        storyHeightsFeet: [Double],
        deckSurfaceYInches: Double
    ) -> [Double] {
        guard !storyHeightsFeet.isEmpty else { return [] }

        var lines: [Double] = []
        var y = deckSurfaceYInches
        for height in storyHeightsFeet {
            lines.append(y)
            y += inches(fromFeet: height)
        }
        return lines
    }

    private static func calloutTagsByOpeningId(for openings: [WallOpening]) -> [String: String] {
        var doorIndex = 0
        var windowIndex = 0
        var tags: [String: String] = [:]

        for opening in openings.sorted(by: openingSort) {
            if isDoor(opening.kind) {
                doorIndex += 1
                tags[opening.id] = "D\(doorIndex)"
            } else {
                windowIndex += 1
                tags[opening.id] = "W\(windowIndex)"
            }
        }

        return tags
    }

    private static func openingSort(lhs: WallOpening, rhs: WallOpening) -> Bool {
        if lhs.edgeId != rhs.edgeId {
            return lhs.edgeId < rhs.edgeId
        }
        if lhs.offsetAlongEdgeInches != rhs.offsetAlongEdgeInches {
            return lhs.offsetAlongEdgeInches < rhs.offsetAlongEdgeInches
        }
        return lhs.id < rhs.id
    }

    private static func isDoor(_ kind: OpeningKind) -> Bool {
        switch kind {
        case .patioDoor, .frenchDoor, .sliderDoor:
            return true
        case .window:
            return false
        }
    }

    private static func inches(fromFeet feet: Double) -> Double {
        feet * 12
    }
}
