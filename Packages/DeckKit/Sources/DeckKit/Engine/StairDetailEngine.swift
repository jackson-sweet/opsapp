import Foundation

public enum TreadType: String, Codable, CaseIterable {
    case openRiser = "open_riser"
    case closedRiser = "closed_riser"
}

public struct StairDetailResult: Codable, Equatable {
    public var stringerCount: Int
    public var stringerSpacingInchesOC: Double
    public var stringerType: StairStringerType
    public var stringerSizing: MemberSizingResult?
    public var treadType: TreadType
    public var treadMaterial: String
    public var noseProjectionInches: Double
    public var landings: [StairLanding]
    public var winders: [WinderTread]
    public var handrailRequired: Bool
    public var handrailCodeSection: String

    public init(
        stringerCount: Int,
        stringerSpacingInchesOC: Double,
        stringerType: StairStringerType,
        stringerSizing: MemberSizingResult?,
        treadType: TreadType,
        treadMaterial: String,
        noseProjectionInches: Double,
        landings: [StairLanding],
        winders: [WinderTread],
        handrailRequired: Bool,
        handrailCodeSection: String
    ) {
        self.stringerCount = stringerCount
        self.stringerSpacingInchesOC = stringerSpacingInchesOC
        self.stringerType = stringerType
        self.stringerSizing = stringerSizing
        self.treadType = treadType
        self.treadMaterial = treadMaterial
        self.noseProjectionInches = noseProjectionInches
        self.landings = landings
        self.winders = winders
        self.handrailRequired = handrailRequired
        self.handrailCodeSection = handrailCodeSection
    }
}

public struct StairLanding: Codable, Equatable {
    public var afterRiserIndex: Int
    public var depthInches: Double

    public init(afterRiserIndex: Int, depthInches: Double) {
        self.afterRiserIndex = afterRiserIndex
        self.depthInches = depthInches
    }
}

public struct WinderTread: Codable, Equatable {
    public var index: Int
    public var innerRunInches: Double
    public var walklineRunInches: Double

    public init(index: Int, innerRunInches: Double, walklineRunInches: Double) {
        self.index = index
        self.innerRunInches = innerRunInches
        self.walklineRunInches = walklineRunInches
    }
}

public struct StairWinderSpec: Codable, Equatable {
    public var turnDegrees: Double
    public var treadCount: Int

    public init(turnDegrees: Double, treadCount: Int) {
        self.turnDegrees = turnDegrees
        self.treadCount = treadCount
    }
}

public enum StairDetailEngine {
    public static func detail(
        base: StairCalculator.StairSpec,
        treadType: TreadType,
        treadMaterial: String,
        stringerSpacingInchesOC: Double,
        species: WoodSpecies,
        grade: LumberGrade,
        package: CodePackage,
        stringerType: StairStringerType = .notchedWoodOpen,
        winder: StairWinderSpec? = nil
    ) -> StairDetailResult {
        return StairDetailResult(
            stringerCount: base.stringerCount,
            stringerSpacingInchesOC: stringerSpacingInchesOC,
            stringerType: stringerType,
            stringerSizing: StructuralSizingEngine.stringerSizing(
                base: base,
                spacingInchesOC: stringerSpacingInchesOC,
                species: species,
                grade: grade,
                package: package,
                stringerType: stringerType
            ),
            treadType: treadType,
            treadMaterial: treadMaterial,
            noseProjectionInches: noseProjection(for: treadType, rules: package.stairRules),
            landings: landings(for: base, rules: package.stairRules),
            winders: winders(for: base, spec: winder, rules: package.stairRules),
            handrailRequired: base.treadCount >= package.stairRules.handrailRequiredRiserCount,
            handrailCodeSection: package.stairRules.handrailCodeSection
        )
    }

    private static func noseProjection(for treadType: TreadType, rules: StairRules) -> Double {
        switch treadType {
        case .openRiser:
            return rules.openRiserNosingInches
        case .closedRiser:
            return min(
                max(rules.defaultClosedRiserNosingInches, rules.closedRiserNosingMinInches),
                rules.closedRiserNosingMaxInches
            )
        }
    }

    private static func landings(
        for base: StairCalculator.StairSpec,
        rules: StairRules
    ) -> [StairLanding] {
        guard base.totalRise > rules.maxSingleFlightRiseInches,
              rules.maxSingleFlightRiseInches > 0,
              base.treadCount > 1 else {
            return []
        }

        let segmentCount = max(2, Int(ceil(base.totalRise / rules.maxSingleFlightRiseInches)))
        let landingDepth = max(rules.minLandingDepthInches, base.width)
        var inserted: [StairLanding] = []
        var usedIndexes: Set<Int> = []

        for segmentIndex in 1..<segmentCount {
            let rawIndex = Int((Double(base.treadCount) * Double(segmentIndex) / Double(segmentCount)).rounded())
            let afterRiserIndex = min(max(1, rawIndex), base.treadCount - 1)
            guard usedIndexes.insert(afterRiserIndex).inserted else { continue }
            inserted.append(
                StairLanding(
                    afterRiserIndex: afterRiserIndex,
                    depthInches: landingDepth
                )
            )
        }

        return inserted
    }

    private static func winders(
        for base: StairCalculator.StairSpec,
        spec: StairWinderSpec?,
        rules: StairRules
    ) -> [WinderTread] {
        guard let spec, spec.treadCount > 0 else { return [] }
        guard abs(spec.turnDegrees - 90) < 0.001 else { return [] }

        let walklineRun = max(rules.winderMinWalklineRunInches, base.runPerTread)
        return (1...spec.treadCount).map {
            WinderTread(
                index: $0,
                innerRunInches: rules.winderMinInnerRunInches,
                walklineRunInches: walklineRun
            )
        }
    }
}
