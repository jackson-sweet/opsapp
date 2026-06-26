// OPS/OPS/DeckBuilder/Engine/StairCalculator.swift

import Foundation

public struct StairCalculator {

    public struct StairSpec {
        public let treadCount: Int
        public let risePerStep: Double      // inches
        public let runPerTread: Double      // inches
        public let totalRise: Double        // inches
        public let totalRun: Double         // inches
        public let stringerLength: Double   // inches
        public let stringerCount: Int
        public let width: Double            // inches

        public init(
            treadCount: Int,
            risePerStep: Double,
            runPerTread: Double,
            totalRise: Double,
            totalRun: Double,
            stringerLength: Double,
            stringerCount: Int,
            width: Double
        ) {
            self.treadCount = treadCount
            self.risePerStep = risePerStep
            self.runPerTread = runPerTread
            self.totalRise = totalRise
            self.totalRun = totalRun
            self.stringerLength = stringerLength
            self.stringerCount = stringerCount
            self.width = width
        }
    }

    /// Calculate full stair spec from elevation and width
    /// - Parameters:
    ///   - totalRise: Total height in inches from ground to deck surface
    ///   - width: Stair width in inches
    ///   - risePerStep: Max rise per step (IRC R311.7: 7.75" max, default 7.5")
    ///   - runPerTread: Min run per tread (IRC R311.7: 10" min)
    ///   - treadCountOverride: Optional user-entered tread count.
    /// - Returns: Complete stair specification
    public static func calculate(
        totalRise: Double,
        width: Double,
        risePerStep: Double = 7.5,
        runPerTread: Double = 10.0,
        treadCountOverride: Int? = nil
    ) -> StairSpec {
        guard totalRise > 0, width > 0 else {
            print("[DeckBuilder] StairCalculator: invalid inputs (rise: \(totalRise), width: \(width))")
            return StairSpec(
                treadCount: 0, risePerStep: 0, runPerTread: runPerTread,
                totalRise: totalRise, totalRun: 0, stringerLength: 0,
                stringerCount: 0, width: width
            )
        }

        let treadCount = max(
            1,
            treadCountOverride ?? StairConfig.calculateTreadCount(
                totalRise: totalRise,
                risePerStep: risePerStep
            )
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
    public static func railingPostCount(stringerLength: Double, maxSpacing: Double) -> Int {
        guard stringerLength > 0, maxSpacing > 0 else { return 0 }
        return Int(ceil(stringerLength / maxSpacing)) + 1
    }
}
