import CoreGraphics
import Foundation

public enum DeckingPatternEngine {
    public static func layout(
        surfacePolygon: [CGPoint],
        scaleFactor: Double,
        spec: SurfacePatternSpec,
        boardWidthInches: Double,
        boardLengthInches: Double,
        gapInches: Double
    ) -> DeckingLayoutResult {
        guard let bounds = realWorldBounds(surfacePolygon: surfacePolygon, scaleFactor: scaleFactor),
              boardWidthInches > 0,
              boardLengthInches > 0 else {
            return DeckingLayoutResult.empty
        }

        let coveredAreaSqFt = PolygonMath.realWorldArea(vertices: surfacePolygon, scaleFactor: scaleFactor) / 144
        let effectiveBoardPitch = max(boardWidthInches + max(0, gapInches), boardWidthInches)
        let layoutWarnings = layoutWarnings(surfacePolygon: surfacePolygon, spec: spec)

        switch spec.pattern {
        case .parallel:
            let angle = normalizedAngle(spec.boardAngleDegrees)
            let boards = fieldBoards(
                bounds: bounds,
                runAxisDegrees: angle,
                boardLengthInches: boardLengthInches,
                effectiveBoardPitch: effectiveBoardPitch,
                startMiterDegrees: 0,
                endMiterDegrees: 0,
                idPrefix: "parallel"
            )
            return DeckingLayoutResult(
                boards: boards,
                boardCount: boards.count,
                coveredAreaSqFt: coveredAreaSqFt,
                pictureFrameCourses: [],
                blockingRequirement: .none,
                layoutWarnings: layoutWarnings
            )

        case .diagonal:
            let angle = normalizedAngle(spec.boardAngleDegrees == 0 ? 45 : spec.boardAngleDegrees)
            let miter = absMiter(for: angle)
            let boards = fieldBoards(
                bounds: bounds,
                runAxisDegrees: angle,
                boardLengthInches: boardLengthInches,
                effectiveBoardPitch: effectiveBoardPitch,
                startMiterDegrees: miter,
                endMiterDegrees: miter,
                idPrefix: "diagonal"
            )
            return DeckingLayoutResult(
                boards: boards,
                boardCount: boards.count,
                coveredAreaSqFt: coveredAreaSqFt,
                pictureFrameCourses: [],
                blockingRequirement: .diagonal,
                layoutWarnings: layoutWarnings
            )

        case .pictureFrame:
            return pictureFrameLayout(
                bounds: bounds,
                coveredAreaSqFt: coveredAreaSqFt,
                spec: spec,
                boardLengthInches: boardLengthInches,
                effectiveBoardPitch: effectiveBoardPitch,
                layoutWarnings: layoutWarnings
            )

        case .herringbone:
            let boards = pairedDiagonalBoards(
                bounds: bounds,
                boardLengthInches: boardLengthInches,
                effectiveBoardPitch: effectiveBoardPitch,
                baseAngleDegrees: spec.boardAngleDegrees == 0 ? 45 : spec.boardAngleDegrees,
                startMiterDegrees: 45,
                endMiterDegrees: 45,
                idPrefix: "herringbone"
            )
            return DeckingLayoutResult(
                boards: boards,
                boardCount: boards.count,
                coveredAreaSqFt: coveredAreaSqFt,
                pictureFrameCourses: [],
                blockingRequirement: .diagonal,
                layoutWarnings: layoutWarnings
            )

        case .chevron:
            let boards = pairedDiagonalBoards(
                bounds: bounds,
                boardLengthInches: boardLengthInches,
                effectiveBoardPitch: effectiveBoardPitch,
                baseAngleDegrees: spec.boardAngleDegrees == 0 ? 45 : spec.boardAngleDegrees,
                startMiterDegrees: 45,
                endMiterDegrees: -45,
                idPrefix: "chevron"
            )
            return DeckingLayoutResult(
                boards: boards,
                boardCount: boards.count,
                coveredAreaSqFt: coveredAreaSqFt,
                pictureFrameCourses: [],
                blockingRequirement: .diagonal,
                layoutWarnings: layoutWarnings
            )
        }
    }

    private static func pictureFrameLayout(
        bounds: LayoutBounds,
        coveredAreaSqFt: Double,
        spec: SurfacePatternSpec,
        boardLengthInches: Double,
        effectiveBoardPitch: Double,
        layoutWarnings: [DeckingLayoutWarning]
    ) -> DeckingLayoutResult {
        let courseCount = max(0, spec.pictureFrameCourses)
        let courses = (0..<courseCount).compactMap { ringIndex -> PictureFrameCourse? in
            let inset = Double(ringIndex) * effectiveBoardPitch
            let width = bounds.widthInches - 2 * inset
            let height = bounds.heightInches - 2 * inset
            guard width > 0, height > 0 else { return nil }
            return PictureFrameCourse(
                ringIndex: ringIndex,
                perimeterFeet: 2 * (width + height) / 12
            )
        }

        let borderCuts = courses.flatMap { course in
            borderBoards(for: course, bounds: bounds, effectiveBoardPitch: effectiveBoardPitch)
        }

        let fieldInset = Double(courses.count) * effectiveBoardPitch
        let fieldBounds = LayoutBounds(
            widthInches: max(0, bounds.widthInches - 2 * fieldInset),
            heightInches: max(0, bounds.heightInches - 2 * fieldInset)
        )
        let fieldBoards = fieldBounds.widthInches > 0 && fieldBounds.heightInches > 0
            ? fieldBoards(
                bounds: fieldBounds,
                runAxisDegrees: normalizedAngle(spec.boardAngleDegrees),
                boardLengthInches: boardLengthInches,
                effectiveBoardPitch: effectiveBoardPitch,
                startMiterDegrees: 0,
                endMiterDegrees: 0,
                idPrefix: "picture-field"
            )
            : []

        let boards = borderCuts + fieldBoards
        return DeckingLayoutResult(
            boards: boards,
            boardCount: boards.count,
            coveredAreaSqFt: coveredAreaSqFt,
            pictureFrameCourses: courses,
            blockingRequirement: .pictureFrame,
            layoutWarnings: layoutWarnings
        )
    }

    private static func fieldBoards(
        bounds: LayoutBounds,
        runAxisDegrees: Double,
        boardLengthInches: Double,
        effectiveBoardPitch: Double,
        startMiterDegrees: Double,
        endMiterDegrees: Double,
        idPrefix: String
    ) -> [DeckBoardCut] {
        let runSpan = projectedSpan(bounds: bounds, axisDegrees: runAxisDegrees)
        let crossSpan = projectedSpan(bounds: bounds, axisDegrees: runAxisDegrees + 90)
        let rowCount = max(0, Int(ceil(crossSpan / effectiveBoardPitch)))
        let piecesPerRow = max(1, Int(ceil(runSpan / boardLengthInches)))
        let typicalPieceLength = runSpan / Double(piecesPerRow)

        return (0..<rowCount).flatMap { rowIndex in
            (0..<piecesPerRow).map { pieceIndex in
                DeckBoardCut(
                    id: "\(idPrefix)-\(rowIndex)-\(pieceIndex)",
                    lengthInches: min(boardLengthInches, typicalPieceLength),
                    startMiterDegrees: startMiterDegrees,
                    endMiterDegrees: endMiterDegrees,
                    runAxisDegrees: normalizedAngle(runAxisDegrees),
                    isBorder: false
                )
            }
        }
    }

    private static func pairedDiagonalBoards(
        bounds: LayoutBounds,
        boardLengthInches: Double,
        effectiveBoardPitch: Double,
        baseAngleDegrees: Double,
        startMiterDegrees: Double,
        endMiterDegrees: Double,
        idPrefix: String
    ) -> [DeckBoardCut] {
        let baseAngle = normalizedAngle(baseAngleDegrees)
        let companionAngle = normalizedAngle(180 - baseAngle)
        let runSpan = projectedSpan(bounds: bounds, axisDegrees: baseAngle)
        let crossSpan = projectedSpan(bounds: bounds, axisDegrees: baseAngle + 90)
        let pairCount = max(0, Int(ceil(crossSpan / effectiveBoardPitch)))
        let pieceLength = min(boardLengthInches, runSpan / 2)

        return (0..<pairCount).flatMap { pairIndex in
            [
                DeckBoardCut(
                    id: "\(idPrefix)-\(pairIndex)-a",
                    lengthInches: pieceLength,
                    startMiterDegrees: startMiterDegrees,
                    endMiterDegrees: endMiterDegrees,
                    runAxisDegrees: baseAngle,
                    isBorder: false
                ),
                DeckBoardCut(
                    id: "\(idPrefix)-\(pairIndex)-b",
                    lengthInches: pieceLength,
                    startMiterDegrees: startMiterDegrees,
                    endMiterDegrees: endMiterDegrees,
                    runAxisDegrees: companionAngle,
                    isBorder: false
                ),
            ]
        }
    }

    private static func borderBoards(
        for course: PictureFrameCourse,
        bounds: LayoutBounds,
        effectiveBoardPitch: Double
    ) -> [DeckBoardCut] {
        let inset = Double(course.ringIndex) * effectiveBoardPitch
        let width = max(0, bounds.widthInches - 2 * inset)
        let height = max(0, bounds.heightInches - 2 * inset)

        return [
            DeckBoardCut(
                id: "picture-border-\(course.ringIndex)-north",
                lengthInches: width,
                startMiterDegrees: 45,
                endMiterDegrees: 45,
                runAxisDegrees: 0,
                isBorder: true
            ),
            DeckBoardCut(
                id: "picture-border-\(course.ringIndex)-east",
                lengthInches: height,
                startMiterDegrees: 45,
                endMiterDegrees: 45,
                runAxisDegrees: 90,
                isBorder: true
            ),
            DeckBoardCut(
                id: "picture-border-\(course.ringIndex)-south",
                lengthInches: width,
                startMiterDegrees: 45,
                endMiterDegrees: 45,
                runAxisDegrees: 180,
                isBorder: true
            ),
            DeckBoardCut(
                id: "picture-border-\(course.ringIndex)-west",
                lengthInches: height,
                startMiterDegrees: 45,
                endMiterDegrees: 45,
                runAxisDegrees: 270,
                isBorder: true
            ),
        ]
    }

    private static func layoutWarnings(
        surfacePolygon: [CGPoint],
        spec: SurfacePatternSpec
    ) -> [DeckingLayoutWarning] {
        guard (spec.pattern == .herringbone || spec.pattern == .chevron),
              !isBoundingRectangle(surfacePolygon) else { return [] }

        return [
            DeckingLayoutWarning(
                code: .nonRectilinearPatternApproximation,
                affectedPattern: spec.pattern,
                quantityConfidence: 0.65
            ),
        ]
    }

    private static func projectedSpan(bounds: LayoutBounds, axisDegrees: Double) -> Double {
        let radians = normalizedAngle(axisDegrees) * .pi / 180
        return abs(bounds.widthInches * cos(radians)) + abs(bounds.heightInches * sin(radians))
    }

    private static func absMiter(for runAxisDegrees: Double) -> Double {
        let angle = normalizedAngle(runAxisDegrees).truncatingRemainder(dividingBy: 90)
        return min(angle, 90 - angle)
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        let normalized = angle.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    private static func realWorldBounds(
        surfacePolygon: [CGPoint],
        scaleFactor: Double
    ) -> LayoutBounds? {
        guard surfacePolygon.count >= 3, scaleFactor > 0 else { return nil }
        let xs = surfacePolygon.map { Double($0.x) / scaleFactor }
        let ys = surfacePolygon.map { Double($0.y) / scaleFactor }
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max() else { return nil }
        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0 else { return nil }
        return LayoutBounds(widthInches: width, heightInches: height)
    }

    private static func isBoundingRectangle(_ polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 4 else { return false }
        let xs = polygon.map { Double($0.x) }
        let ys = polygon.map { Double($0.y) }
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max() else { return false }

        let tolerance = 0.001
        let axisAlignedEdges = polygon.indices.allSatisfy { index in
            let next = polygon[(index + 1) % polygon.count]
            let current = polygon[index]
            return abs(Double(next.x - current.x)) <= tolerance
                || abs(Double(next.y - current.y)) <= tolerance
        }

        let boundingArea = (maxX - minX) * (maxY - minY)
        let polygonArea = PolygonMath.area(vertices: polygon)
        let areaTolerance = max(0.01, boundingArea * 0.0001)

        return axisAlignedEdges && abs(polygonArea - boundingArea) <= areaTolerance
    }
}

public struct DeckingLayoutResult: Codable, Equatable {
    public var boards: [DeckBoardCut]
    public var boardCount: Int
    public var coveredAreaSqFt: Double
    public var pictureFrameCourses: [PictureFrameCourse]
    public var blockingRequirement: BlockingRequirement
    public var layoutWarnings: [DeckingLayoutWarning]

    public init(
        boards: [DeckBoardCut],
        boardCount: Int,
        coveredAreaSqFt: Double,
        pictureFrameCourses: [PictureFrameCourse],
        blockingRequirement: BlockingRequirement,
        layoutWarnings: [DeckingLayoutWarning] = []
    ) {
        self.boards = boards
        self.boardCount = boardCount
        self.coveredAreaSqFt = coveredAreaSqFt
        self.pictureFrameCourses = pictureFrameCourses
        self.blockingRequirement = blockingRequirement
        self.layoutWarnings = layoutWarnings
    }

    public static let empty = DeckingLayoutResult(
        boards: [],
        boardCount: 0,
        coveredAreaSqFt: 0,
        pictureFrameCourses: [],
        blockingRequirement: .none,
        layoutWarnings: []
    )
}

public struct DeckBoardCut: Codable, Equatable, Identifiable {
    public let id: String
    public var lengthInches: Double
    public var startMiterDegrees: Double
    public var endMiterDegrees: Double
    public var runAxisDegrees: Double
    public var isBorder: Bool

    public init(
        id: String,
        lengthInches: Double,
        startMiterDegrees: Double,
        endMiterDegrees: Double,
        runAxisDegrees: Double,
        isBorder: Bool
    ) {
        self.id = id
        self.lengthInches = lengthInches
        self.startMiterDegrees = startMiterDegrees
        self.endMiterDegrees = endMiterDegrees
        self.runAxisDegrees = runAxisDegrees
        self.isBorder = isBorder
    }
}

public struct PictureFrameCourse: Codable, Equatable {
    public var ringIndex: Int
    public var perimeterFeet: Double

    public init(ringIndex: Int, perimeterFeet: Double) {
        self.ringIndex = ringIndex
        self.perimeterFeet = perimeterFeet
    }
}

public struct BlockingRequirement: Codable, Equatable {
    public var maxBlockingSpacingInchesOC: Double?
    public var perimeterBlockingRequired: Bool
    public var codeSection: String

    public init(
        maxBlockingSpacingInchesOC: Double? = nil,
        perimeterBlockingRequired: Bool = false,
        codeSection: String = ""
    ) {
        self.maxBlockingSpacingInchesOC = maxBlockingSpacingInchesOC
        self.perimeterBlockingRequired = perimeterBlockingRequired
        self.codeSection = codeSection
    }

    public static let none = BlockingRequirement()

    public static let diagonal = BlockingRequirement(
        maxBlockingSpacingInchesOC: 12,
        perimeterBlockingRequired: false,
        codeSection: "AWC DCA6 - diagonal decking blocking requirement"
    )

    public static let pictureFrame = BlockingRequirement(
        maxBlockingSpacingInchesOC: nil,
        perimeterBlockingRequired: true,
        codeSection: "AWC DCA6 - picture-frame perimeter blocking requirement"
    )
}

public enum DeckingLayoutWarningCode: String, Codable, Equatable {
    case nonRectilinearPatternApproximation = "non_rectilinear_pattern_approximation"
}

public struct DeckingLayoutWarning: Codable, Equatable, Identifiable {
    public var code: DeckingLayoutWarningCode
    public var affectedPattern: DeckingPattern
    public var quantityConfidence: Double

    public var id: String {
        "\(code.rawValue)-\(affectedPattern.rawValue)"
    }

    public init(
        code: DeckingLayoutWarningCode,
        affectedPattern: DeckingPattern,
        quantityConfidence: Double
    ) {
        self.code = code
        self.affectedPattern = affectedPattern
        self.quantityConfidence = quantityConfidence
    }
}

private struct LayoutBounds {
    var widthInches: Double
    var heightInches: Double
}
