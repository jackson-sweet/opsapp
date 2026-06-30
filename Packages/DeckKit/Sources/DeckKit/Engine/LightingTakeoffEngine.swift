import CoreGraphics
import Foundation

public enum LightingTakeoffEngine {
    public static let defaultStandardTransformerWatts: [Double] = [60, 100, 150, 200, 300, 600]

    public static func size(
        plan: LightingPlan,
        fixtureWatts: Double,
        scaleFactor: Double,
        standardTransformerWatts: [Double] = defaultStandardTransformerWatts
    ) -> LightingTakeoffResult {
        let fixtureCount = plan.fixtures.count
        let wattsPerFixture = max(0, fixtureWatts)
        let totalConnectedWatts = Double(fixtureCount) * wattsPerFixture

        return LightingTakeoffResult(
            fixtureCount: fixtureCount,
            totalConnectedWatts: totalConnectedWatts,
            recommendedTransformerWatts: recommendedTransformerWatts(
                connectedWatts: totalConnectedWatts,
                standardTransformerWatts: standardTransformerWatts
            ),
            estimatedWireRunFeet: nearestNeighborWireRunFeet(
                fixtures: plan.fixtures,
                scaleFactor: scaleFactor
            ),
            receptacleCount: plan.receptacles.count,
            electricalNote: electricalNote
        )
    }

    private static let electricalNote =
        "Outdoor receptacles and GFCI protection require electrician review. Verify NEC 210.52(E) and NEC 210.8(A)(3)."

    private static func recommendedTransformerWatts(
        connectedWatts: Double,
        standardTransformerWatts: [Double]
    ) -> Double {
        guard connectedWatts > 0 else { return 0 }

        let requiredWatts = connectedWatts / 0.8
        let sortedSizes = standardTransformerWatts
            .filter { $0 > 0 }
            .sorted()

        return sortedSizes.first(where: { $0 >= requiredWatts }) ?? requiredWatts
    }

    private static func nearestNeighborWireRunFeet(
        fixtures: [CGPoint],
        scaleFactor: Double
    ) -> Double {
        guard fixtures.count > 1, scaleFactor > 0 else { return 0 }

        var current = fixtures[0]
        var remaining = Array(fixtures.dropFirst())
        var totalCanvasDistance = 0.0

        while !remaining.isEmpty {
            let nextIndex = nearestIndex(from: current, in: remaining)
            let next = remaining.remove(at: nextIndex)
            totalCanvasDistance += SnapEngine.distance(current, next)
            current = next
        }

        return totalCanvasDistance / scaleFactor / 12
    }

    private static func nearestIndex(from point: CGPoint, in candidates: [CGPoint]) -> Int {
        var selectedIndex = 0
        var selectedDistance = Double.infinity

        for (index, candidate) in candidates.enumerated() {
            let distance = SnapEngine.distance(point, candidate)
            if distance < selectedDistance {
                selectedDistance = distance
                selectedIndex = index
            }
        }

        return selectedIndex
    }
}

public struct LightingTakeoffResult: Codable, Equatable {
    public var fixtureCount: Int
    public var totalConnectedWatts: Double
    public var recommendedTransformerWatts: Double
    public var estimatedWireRunFeet: Double
    public var receptacleCount: Int
    public var electricalNote: String

    public init(
        fixtureCount: Int,
        totalConnectedWatts: Double,
        recommendedTransformerWatts: Double,
        estimatedWireRunFeet: Double,
        receptacleCount: Int,
        electricalNote: String
    ) {
        self.fixtureCount = fixtureCount
        self.totalConnectedWatts = totalConnectedWatts
        self.recommendedTransformerWatts = recommendedTransformerWatts
        self.estimatedWireRunFeet = estimatedWireRunFeet
        self.receptacleCount = receptacleCount
        self.electricalNote = electricalNote
    }
}
