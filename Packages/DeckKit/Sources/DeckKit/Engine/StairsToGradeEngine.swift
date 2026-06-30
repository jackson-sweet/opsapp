import Foundation

public enum StairsToGradeEngine {
    public struct GradeStairResult: Equatable {
        public var flights: [StairCalculator.StairSpec]
        public var landingCount: Int
        public var totalRiseInches: Double
        /// True when the engine split a tall run into multiple drawable flights.
        /// This is a geometry convenience, not a code-pass determination.
        public var landingInserted: Bool

        public init(
            flights: [StairCalculator.StairSpec],
            landingCount: Int,
            totalRiseInches: Double,
            landingInserted: Bool
        ) {
            self.flights = flights
            self.landingCount = landingCount
            self.totalRiseInches = totalRiseInches
            self.landingInserted = landingInserted
        }
    }

    /// Total rise from a level's floor-line datum down to grade, then stair
    /// geometry. Grade is captured terrain when present, else zero. Landing
    /// insertion only splits tall runs for layout; jurisdictional stair-code
    /// checks stay in the compliance engine.
    public static func stairsToGrade(
        levelId: String?,
        widthInches: Double,
        data: DeckDrawingData,
        maxRiseWithoutLandingInches: Double = 147
    ) -> GradeStairResult {
        let totalRise = totalRiseToGradeInches(levelId: levelId, data: data)

        guard totalRise > 0, widthInches > 0 else {
            return GradeStairResult(
                flights: [],
                landingCount: 0,
                totalRiseInches: max(0, totalRise),
                landingInserted: false
            )
        }

        let effectiveMaxRise = maxRiseWithoutLandingInches > 0
            ? maxRiseWithoutLandingInches
            : totalRise
        let flightCount = totalRise > effectiveMaxRise
            ? Int(ceil(totalRise / effectiveMaxRise))
            : 1
        let flightRise = totalRise / Double(flightCount)
        let flights = (0..<flightCount).map { _ in
            StairCalculator.calculate(totalRise: flightRise, width: widthInches)
        }

        return GradeStairResult(
            flights: flights,
            landingCount: max(0, flightCount - 1),
            totalRiseInches: totalRise,
            landingInserted: flightCount > 1
        )
    }

    /// Total rise (inches) from the level's floor datum to grade.
    public static func totalRiseToGradeInches(levelId: String?, data: DeckDrawingData) -> Double {
        max(0, datumFeet(levelId: levelId, data: data) + terrainDropFeet(data)) * 12
    }

    private static func datumFeet(levelId: String?, data: DeckDrawingData) -> Double {
        if let floorLineFeet = data.house?.floorLineFeet {
            return floorLineFeet
        }

        if let levelId,
           let level = data.level(byId: levelId),
           let levelElevation = level.elevation {
            return levelElevation
        }

        return data.overallElevation ?? 0
    }

    private static func terrainDropFeet(_ data: DeckDrawingData) -> Double {
        data.terrain?.gradePoints
            .map(\.dropFeet)
            .filter { $0 > 0 }
            .max() ?? 0
    }
}
