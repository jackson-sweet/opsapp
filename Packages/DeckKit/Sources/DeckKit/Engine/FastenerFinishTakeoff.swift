import CoreGraphics
import Foundation

public enum FastenerFinishTakeoff {
    private static let defaultJoistSpacingInchesOC = 16.0

    public static func fasteners(
        system: FastenerSystem,
        boards: [DeckBoardCut],
        joistSpacingInchesOC: Double,
        surfacePolygon: [CGPoint],
        scaleFactor: Double
    ) -> FastenerTakeoff {
        let spacing = joistSpacingInchesOC > 0
            ? joistSpacingInchesOC
            : defaultJoistSpacingInchesOC
        let polygonRunLength = longestRealWorldSpanInches(
            surfacePolygon: surfacePolygon,
            scaleFactor: scaleFactor
        )

        var basis: FastenerTakeoffBasis = joistSpacingInchesOC > 0 ? .layoutDerived : .estimateGrade
        let crossings = boards.reduce(0) { total, board in
            let length = board.lengthInches > 0 ? board.lengthInches : polygonRunLength
            if board.lengthInches <= 0 {
                basis = .estimateGrade
            }
            return total + boardToJoistCrossings(lengthInches: length, spacingInchesOC: spacing)
        }

        switch system {
        case .hiddenClip:
            return FastenerTakeoff(
                system: system,
                clipCount: crossings,
                screwCount: 0,
                boardToJoistCrossings: crossings,
                joistSpacingInchesOC: spacing,
                basis: basis
            )
        case .faceScrew:
            return FastenerTakeoff(
                system: system,
                clipCount: 0,
                screwCount: crossings * 2,
                boardToJoistCrossings: crossings,
                joistSpacingInchesOC: spacing,
                basis: basis
            )
        }
    }

    public static func finishes(
        specs: [FinishSpec],
        coatedAreaSqFt: Double,
        coveragePerUnitSqFt: Double
    ) -> [FinishTakeoff] {
        let area = max(0, coatedAreaSqFt)
        let coverage = max(0, coveragePerUnitSqFt)

        return specs.map { spec in
            let coats = max(0, spec.coats)
            let unitsRequired = coverage > 0 ? area * Double(coats) / coverage : 0
            return FinishTakeoff(
                kind: spec.kind,
                coats: coats,
                unitsRequired: unitsRequired
            )
        }
    }

    private static func boardToJoistCrossings(
        lengthInches: Double,
        spacingInchesOC: Double
    ) -> Int {
        guard lengthInches > 0, spacingInchesOC > 0 else { return 0 }
        return Int(floor(lengthInches / spacingInchesOC)) + 1
    }

    private static func longestRealWorldSpanInches(
        surfacePolygon: [CGPoint],
        scaleFactor: Double
    ) -> Double {
        guard scaleFactor > 0, !surfacePolygon.isEmpty else { return 0 }
        let xs = surfacePolygon.map { Double($0.x) }
        let ys = surfacePolygon.map { Double($0.y) }
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max() else {
            return 0
        }
        return max(maxX - minX, maxY - minY) / scaleFactor
    }
}

public struct FastenerTakeoff: Codable, Equatable {
    public var system: FastenerSystem
    public var clipCount: Int
    public var screwCount: Int
    public var boardToJoistCrossings: Int
    public var joistSpacingInchesOC: Double
    public var basis: FastenerTakeoffBasis

    public init(
        system: FastenerSystem,
        clipCount: Int,
        screwCount: Int,
        boardToJoistCrossings: Int,
        joistSpacingInchesOC: Double,
        basis: FastenerTakeoffBasis
    ) {
        self.system = system
        self.clipCount = clipCount
        self.screwCount = screwCount
        self.boardToJoistCrossings = boardToJoistCrossings
        self.joistSpacingInchesOC = joistSpacingInchesOC
        self.basis = basis
    }
}

public enum FastenerTakeoffBasis: String, Codable, CaseIterable {
    case layoutDerived = "layout_derived"
    case estimateGrade = "estimate_grade"
}

public struct FinishTakeoff: Codable, Equatable {
    public var kind: String
    public var coats: Int
    public var unitsRequired: Double

    public init(kind: String, coats: Int, unitsRequired: Double) {
        self.kind = kind
        self.coats = coats
        self.unitsRequired = unitsRequired
    }
}
