// OPS/OPS/DeckBuilder/Engine/StairCalculator.swift

import Foundation

struct StairCalculator {

    struct StairSpec {
        let treadCount: Int
        let risePerStep: Double      // inches
        let runPerTread: Double      // inches
        let totalRise: Double        // inches
        let totalRun: Double         // inches
        let stringerLength: Double   // inches
        let stringerCount: Int
        let width: Double            // inches
    }

    /// Calculate full stair spec from elevation and width
    /// - Parameters:
    ///   - totalRise: Total height in inches from ground to deck surface
    ///   - width: Stair width in inches
    ///   - risePerStep: Max rise per step (IRC R311.7: 7.75" max, default 7.5")
    ///   - runPerTread: Min run per tread (IRC R311.7: 10" min)
    /// - Returns: Complete stair specification
    static func calculate(
        totalRise: Double,
        width: Double,
        risePerStep: Double = 7.5,
        runPerTread: Double = 10.0
    ) -> StairSpec {
        let treadCount = StairConfig.calculateTreadCount(
            totalRise: totalRise,
            risePerStep: risePerStep
        )

        // Adjust actual rise per step to be uniform
        let actualRise = treadCount > 0 ? totalRise / Double(treadCount) : 0
        let totalRun = Double(treadCount) * runPerTread
        let stringerLength = StairConfig.stringerLength(
            totalRise: totalRise,
            treadCount: treadCount,
            runPerTread: runPerTread
        )
        let stringerCount = StairConfig.stringerCount(width: width)

        return StairSpec(
            treadCount: treadCount,
            risePerStep: actualRise,
            runPerTread: runPerTread,
            totalRise: totalRise,
            totalRun: totalRun,
            stringerLength: stringerLength,
            stringerCount: stringerCount,
            width: width
        )
    }

    /// Calculate post count for stair railing
    /// - Parameters:
    ///   - stringerLength: Length along the stair slope in inches
    ///   - maxSpacing: Maximum post spacing in inches
    /// - Returns: Number of posts (including top and bottom)
    static func railingPostCount(stringerLength: Double, maxSpacing: Double) -> Int {
        guard stringerLength > 0, maxSpacing > 0 else { return 0 }
        return Int(ceil(stringerLength / maxSpacing)) + 1
    }
}
