import CoreGraphics
import Foundation

public enum WallOpeningGeometry {
    public enum Validation: Equatable {
        case ok
        case clampedToWall(adjustedOffsetInches: Double)
        case overlapsOpening(otherId: String)
        case headExceedsStory(headInches: Double, storyHeightInches: Double)
        case zeroOrNegativeSize
    }

    public static func wallLengthInches(
        edge: DeckEdge,
        in data: DeckDrawingData
    ) -> Double {
        if let dimension = edge.dimension, dimension > 0 {
            return dimension
        }

        guard let start = data.allVertices.first(where: { $0.id == edge.startVertexId }),
              let end = data.allVertices.first(where: { $0.id == edge.endVertexId }) else {
            return 0
        }

        let dx = Double(end.position.x - start.position.x)
        let dy = Double(end.position.y - start.position.y)
        return hypot(dx, dy) / data.effectiveScaleFactor
    }

    public static func validate(
        _ opening: WallOpening,
        wallLengthInches: Double,
        storyHeightInches: Double,
        existing: [WallOpening]
    ) -> Validation {
        guard opening.widthInches > 0, opening.heightInches > 0 else {
            return .zeroOrNegativeSize
        }

        let adjusted = clamped(opening, wallLengthInches: wallLengthInches)
        if adjusted.offsetAlongEdgeInches != opening.offsetAlongEdgeInches {
            return .clampedToWall(adjustedOffsetInches: adjusted.offsetAlongEdgeInches)
        }

        let headInches = sillHeight(for: opening) + opening.heightInches
        if headInches > storyHeightInches {
            return .headExceedsStory(
                headInches: headInches,
                storyHeightInches: storyHeightInches
            )
        }

        let openingInterval = intervalRange(for: opening)
        for other in existing where other.edgeId == opening.edgeId && other.id != opening.id {
            guard other.widthInches > 0 else { continue }
            let otherInterval = intervalRange(for: other)
            if openingInterval.lowerBound < otherInterval.upperBound &&
                otherInterval.lowerBound < openingInterval.upperBound {
                return .overlapsOpening(otherId: other.id)
            }
        }

        return .ok
    }

    public static func clamped(
        _ opening: WallOpening,
        wallLengthInches: Double
    ) -> WallOpening {
        var copy = opening
        let maxOffset = max(0, wallLengthInches - max(0, opening.widthInches))
        copy.offsetAlongEdgeInches = min(max(opening.offsetAlongEdgeInches, 0), maxOffset)
        return copy
    }

    public static func cutoutRect2D(
        _ opening: WallOpening
    ) -> CGRect {
        CGRect(
            x: opening.offsetAlongEdgeInches,
            y: sillHeight(for: opening),
            width: opening.widthInches,
            height: opening.heightInches
        )
    }

    public static func cutoutProfile3D(
        _ opening: WallOpening,
        storyHeightInches: Double
    ) -> CGRect? {
        guard opening.widthInches > 0,
              opening.heightInches > 0,
              storyHeightInches > 0 else {
            return nil
        }
        return cutoutRect2D(opening)
    }

    private static func intervalRange(for opening: WallOpening) -> Range<Double> {
        opening.offsetAlongEdgeInches..<(opening.offsetAlongEdgeInches + opening.widthInches)
    }

    private static func sillHeight(for opening: WallOpening) -> Double {
        switch opening.kind {
        case .patioDoor, .frenchDoor, .sliderDoor:
            return 0
        case .window:
            return opening.sillHeightInches
        }
    }
}
