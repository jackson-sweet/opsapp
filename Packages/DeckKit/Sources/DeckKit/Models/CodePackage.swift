import Foundation

public struct CodePackage: Codable, Equatable {
    public var jurisdictionId: String
    public var edition: String?
    public var publishedDate: Date
    public var guardRules: GuardRules
    public var ledgerRules: LedgerRules
    public var unitSystem: PackageUnits
    public var stairRules: StairRules
    public var beamSpanTable: [BeamSpanSizingRow]
    public var postHeightTable: [PostHeightSizingRow]
    public var envelopeLimits: EnvelopeLimits

    private enum CodingKeys: String, CodingKey {
        case jurisdictionId
        case edition
        case publishedDate
        case guardRules
        case ledgerRules
        case unitSystem
        case stairRules
        case beamSpanTable
        case postHeightTable
        case envelopeLimits
    }

    public init(
        jurisdictionId: String = "",
        edition: String? = nil,
        publishedDate: Date = Date(timeIntervalSince1970: 0),
        guardRules: GuardRules = GuardRules(),
        ledgerRules: LedgerRules = LedgerRules(),
        unitSystem: PackageUnits = .imperial,
        stairRules: StairRules = StairRules(),
        beamSpanTable: [BeamSpanSizingRow] = [],
        postHeightTable: [PostHeightSizingRow] = [],
        envelopeLimits: EnvelopeLimits = EnvelopeLimits()
    ) {
        self.jurisdictionId = jurisdictionId
        self.edition = edition
        self.publishedDate = publishedDate
        self.guardRules = guardRules
        self.ledgerRules = ledgerRules
        self.unitSystem = unitSystem
        self.stairRules = stairRules
        self.beamSpanTable = beamSpanTable
        self.postHeightTable = postHeightTable
        self.envelopeLimits = envelopeLimits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.jurisdictionId = try c.decodeIfPresent(String.self, forKey: .jurisdictionId) ?? ""
        self.edition = try c.decodeIfPresent(String.self, forKey: .edition)
        self.publishedDate = try c.decodeIfPresent(Date.self, forKey: .publishedDate)
            ?? Date(timeIntervalSince1970: 0)
        self.guardRules = try c.decodeIfPresent(GuardRules.self, forKey: .guardRules) ?? GuardRules()
        self.ledgerRules = try c.decodeIfPresent(LedgerRules.self, forKey: .ledgerRules)
            ?? LedgerRules()
        self.unitSystem = try c.decodeIfPresent(PackageUnits.self, forKey: .unitSystem) ?? .imperial
        self.stairRules = try c.decodeIfPresent(StairRules.self, forKey: .stairRules) ?? StairRules()
        self.beamSpanTable = try c.decodeIfPresent([BeamSpanSizingRow].self, forKey: .beamSpanTable) ?? []
        self.postHeightTable = try c.decodeIfPresent([PostHeightSizingRow].self, forKey: .postHeightTable) ?? []
        self.envelopeLimits = try c.decodeIfPresent(EnvelopeLimits.self, forKey: .envelopeLimits)
            ?? EnvelopeLimits()
    }
}

public enum PackageUnits: String, Codable, Equatable {
    case imperial
    case metric
}

public struct GuardRules: Codable, Equatable {
    public var minGuardHeightInches: Double
    public var guardRequiredHeightInches: Double
    public var maxOpeningInches: Double
    public var maxPostSpacingInches: Double?
    public var codeSection: String

    private enum CodingKeys: String, CodingKey {
        case minGuardHeightInches
        case guardRequiredHeightInches
        case maxOpeningInches
        case maxPostSpacingInches
        case codeSection
    }

    public init(
        minGuardHeightInches: Double = 36,
        guardRequiredHeightInches: Double = 30,
        maxOpeningInches: Double = 4,
        maxPostSpacingInches: Double? = nil,
        codeSection: String = "IRC R312"
    ) {
        self.minGuardHeightInches = minGuardHeightInches
        self.guardRequiredHeightInches = guardRequiredHeightInches
        self.maxOpeningInches = maxOpeningInches
        self.maxPostSpacingInches = maxPostSpacingInches
        self.codeSection = codeSection
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.minGuardHeightInches = try c.decodeIfPresent(
            Double.self,
            forKey: .minGuardHeightInches
        ) ?? 36
        self.guardRequiredHeightInches = try c.decodeIfPresent(
            Double.self,
            forKey: .guardRequiredHeightInches
        ) ?? 30
        self.maxOpeningInches = try c.decodeIfPresent(Double.self, forKey: .maxOpeningInches) ?? 4
        self.maxPostSpacingInches = try c.decodeIfPresent(
            Double.self,
            forKey: .maxPostSpacingInches
        )
        self.codeSection = try c.decodeIfPresent(String.self, forKey: .codeSection) ?? "IRC R312"
    }
}

public struct LedgerRules: Codable, Equatable {
    public var minLateralConnectors: Int
    public var codeSection: String

    private enum CodingKeys: String, CodingKey {
        case minLateralConnectors
        case codeSection
    }

    public init(
        minLateralConnectors: Int = 2,
        codeSection: String = "IRC R507.9"
    ) {
        self.minLateralConnectors = minLateralConnectors
        self.codeSection = codeSection
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.minLateralConnectors = try c.decodeIfPresent(
            Int.self,
            forKey: .minLateralConnectors
        ) ?? 2
        self.codeSection = try c.decodeIfPresent(String.self, forKey: .codeSection)
            ?? "IRC R507.9"
    }
}

public enum StairStringerType: String, Codable, CaseIterable {
    case notchedWoodOpen = "notched_wood_open"
    case closedWood = "closed_wood"
    case steel
}

public struct EnvelopeLimits: Codable, Equatable {
    public var maxMemberSpanFeet: Double?
    public var maxPostHeightFeet: Double?

    private enum CodingKeys: String, CodingKey {
        case maxMemberSpanFeet
        case maxPostHeightFeet
    }

    public init(
        maxMemberSpanFeet: Double? = nil,
        maxPostHeightFeet: Double? = nil
    ) {
        self.maxMemberSpanFeet = maxMemberSpanFeet
        self.maxPostHeightFeet = maxPostHeightFeet
    }
}

public struct BeamSpanSizingRow: Codable, Equatable {
    public var role: FramingRole
    public var size: LumberSize
    public var plyCount: Int
    public var species: WoodSpecies
    public var grade: LumberGrade
    public var maxSpanFeet: Double
    public var codeSection: String
    public var limitingCheck: String
    public var maxLiveLoadPSF: Double?
    public var maxDeadLoadPSF: Double?
    public var maxSnowLoadPSF: Double?

    private enum CodingKeys: String, CodingKey {
        case role
        case size
        case plyCount
        case species
        case grade
        case maxSpanFeet
        case codeSection
        case limitingCheck
        case maxLiveLoadPSF
        case maxDeadLoadPSF
        case maxSnowLoadPSF
    }

    public init(
        role: FramingRole,
        size: LumberSize,
        plyCount: Int,
        species: WoodSpecies,
        grade: LumberGrade,
        maxSpanFeet: Double,
        codeSection: String,
        limitingCheck: String,
        maxLiveLoadPSF: Double? = nil,
        maxDeadLoadPSF: Double? = nil,
        maxSnowLoadPSF: Double? = nil
    ) {
        self.role = role
        self.size = size
        self.plyCount = plyCount
        self.species = species
        self.grade = grade
        self.maxSpanFeet = maxSpanFeet
        self.codeSection = codeSection
        self.limitingCheck = limitingCheck
        self.maxLiveLoadPSF = maxLiveLoadPSF
        self.maxDeadLoadPSF = maxDeadLoadPSF
        self.maxSnowLoadPSF = maxSnowLoadPSF
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try c.decodeIfPresent(FramingRole.self, forKey: .role) ?? .beam
        self.size = try c.decodeIfPresent(LumberSize.self, forKey: .size) ?? .twoByTen
        self.plyCount = try c.decodeIfPresent(Int.self, forKey: .plyCount) ?? 1
        self.species = try c.decodeIfPresent(WoodSpecies.self, forKey: .species) ?? .sprucePineFir
        self.grade = try c.decodeIfPresent(LumberGrade.self, forKey: .grade) ?? .no2
        self.maxSpanFeet = try c.decodeIfPresent(Double.self, forKey: .maxSpanFeet) ?? 0
        self.codeSection = try c.decodeIfPresent(String.self, forKey: .codeSection)
            ?? "Package beam span table"
        self.limitingCheck = try c.decodeIfPresent(String.self, forKey: .limitingCheck)
            ?? "beam span table"
        self.maxLiveLoadPSF = try c.decodeIfPresent(Double.self, forKey: .maxLiveLoadPSF)
        self.maxDeadLoadPSF = try c.decodeIfPresent(Double.self, forKey: .maxDeadLoadPSF)
        self.maxSnowLoadPSF = try c.decodeIfPresent(Double.self, forKey: .maxSnowLoadPSF)
    }
}

public struct PostHeightSizingRow: Codable, Equatable {
    public var size: LumberSize
    public var species: WoodSpecies
    public var grade: LumberGrade
    public var maxHeightFeet: Double
    public var codeSection: String
    public var limitingCheck: String

    private enum CodingKeys: String, CodingKey {
        case size
        case species
        case grade
        case maxHeightFeet
        case codeSection
        case limitingCheck
    }

    public init(
        size: LumberSize,
        species: WoodSpecies,
        grade: LumberGrade,
        maxHeightFeet: Double,
        codeSection: String,
        limitingCheck: String
    ) {
        self.size = size
        self.species = species
        self.grade = grade
        self.maxHeightFeet = maxHeightFeet
        self.codeSection = codeSection
        self.limitingCheck = limitingCheck
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.size = try c.decodeIfPresent(LumberSize.self, forKey: .size) ?? .sixBySix
        self.species = try c.decodeIfPresent(WoodSpecies.self, forKey: .species) ?? .sprucePineFir
        self.grade = try c.decodeIfPresent(LumberGrade.self, forKey: .grade) ?? .no2
        self.maxHeightFeet = try c.decodeIfPresent(Double.self, forKey: .maxHeightFeet) ?? 0
        self.codeSection = try c.decodeIfPresent(String.self, forKey: .codeSection)
            ?? "IRC R507.4 / package post table"
        self.limitingCheck = try c.decodeIfPresent(String.self, forKey: .limitingCheck)
            ?? "post height table"
    }
}

public struct StairRules: Codable, Equatable {
    public var maxRiserHeightInches: Double
    public var minTreadRunInches: Double
    public var stairCodeSection: String
    public var maxSingleFlightRiseInches: Double
    public var minLandingDepthInches: Double
    public var handrailRequiredRiserCount: Int
    public var handrailCodeSection: String
    public var closedRiserNosingMinInches: Double
    public var closedRiserNosingMaxInches: Double
    public var defaultClosedRiserNosingInches: Double
    public var openRiserNosingInches: Double
    public var winderMinInnerRunInches: Double
    public var winderMinWalklineRunInches: Double
    public var winderWalklineOffsetInches: Double
    public var notchedStringerSizing: [StairStringerSizingRow]

    private enum CodingKeys: String, CodingKey {
        case maxRiserHeightInches
        case minTreadRunInches
        case stairCodeSection
        case maxSingleFlightRiseInches
        case minLandingDepthInches
        case handrailRequiredRiserCount
        case handrailCodeSection
        case closedRiserNosingMinInches
        case closedRiserNosingMaxInches
        case defaultClosedRiserNosingInches
        case openRiserNosingInches
        case winderMinInnerRunInches
        case winderMinWalklineRunInches
        case winderWalklineOffsetInches
        case notchedStringerSizing
    }

    public init(
        maxRiserHeightInches: Double = 7.75,
        minTreadRunInches: Double = 10,
        stairCodeSection: String = "IRC R311.7",
        maxSingleFlightRiseInches: Double = 147,
        minLandingDepthInches: Double = 36,
        handrailRequiredRiserCount: Int = 4,
        handrailCodeSection: String = "IRC R311.7.8",
        closedRiserNosingMinInches: Double = 0.75,
        closedRiserNosingMaxInches: Double = 1.25,
        defaultClosedRiserNosingInches: Double = 1,
        openRiserNosingInches: Double = 0,
        winderMinInnerRunInches: Double = 6,
        winderMinWalklineRunInches: Double = 10,
        winderWalklineOffsetInches: Double = 12,
        notchedStringerSizing: [StairStringerSizingRow] = []
    ) {
        self.maxRiserHeightInches = maxRiserHeightInches
        self.minTreadRunInches = minTreadRunInches
        self.stairCodeSection = stairCodeSection
        self.maxSingleFlightRiseInches = maxSingleFlightRiseInches
        self.minLandingDepthInches = minLandingDepthInches
        self.handrailRequiredRiserCount = handrailRequiredRiserCount
        self.handrailCodeSection = handrailCodeSection
        self.closedRiserNosingMinInches = closedRiserNosingMinInches
        self.closedRiserNosingMaxInches = closedRiserNosingMaxInches
        self.defaultClosedRiserNosingInches = defaultClosedRiserNosingInches
        self.openRiserNosingInches = openRiserNosingInches
        self.winderMinInnerRunInches = winderMinInnerRunInches
        self.winderMinWalklineRunInches = winderMinWalklineRunInches
        self.winderWalklineOffsetInches = winderWalklineOffsetInches
        self.notchedStringerSizing = notchedStringerSizing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.maxRiserHeightInches = try c.decodeIfPresent(Double.self, forKey: .maxRiserHeightInches) ?? 7.75
        self.minTreadRunInches = try c.decodeIfPresent(Double.self, forKey: .minTreadRunInches) ?? 10
        self.stairCodeSection = try c.decodeIfPresent(String.self, forKey: .stairCodeSection) ?? "IRC R311.7"
        self.maxSingleFlightRiseInches = try c.decodeIfPresent(Double.self, forKey: .maxSingleFlightRiseInches) ?? 147
        self.minLandingDepthInches = try c.decodeIfPresent(Double.self, forKey: .minLandingDepthInches) ?? 36
        self.handrailRequiredRiserCount = try c.decodeIfPresent(Int.self, forKey: .handrailRequiredRiserCount) ?? 4
        self.handrailCodeSection = try c.decodeIfPresent(String.self, forKey: .handrailCodeSection) ?? "IRC R311.7.8"
        self.closedRiserNosingMinInches = try c.decodeIfPresent(Double.self, forKey: .closedRiserNosingMinInches) ?? 0.75
        self.closedRiserNosingMaxInches = try c.decodeIfPresent(Double.self, forKey: .closedRiserNosingMaxInches) ?? 1.25
        self.defaultClosedRiserNosingInches = try c.decodeIfPresent(Double.self, forKey: .defaultClosedRiserNosingInches) ?? 1
        self.openRiserNosingInches = try c.decodeIfPresent(Double.self, forKey: .openRiserNosingInches) ?? 0
        self.winderMinInnerRunInches = try c.decodeIfPresent(Double.self, forKey: .winderMinInnerRunInches) ?? 6
        self.winderMinWalklineRunInches = try c.decodeIfPresent(Double.self, forKey: .winderMinWalklineRunInches) ?? 10
        self.winderWalklineOffsetInches = try c.decodeIfPresent(Double.self, forKey: .winderWalklineOffsetInches) ?? 12
        self.notchedStringerSizing = try c.decodeIfPresent(
            [StairStringerSizingRow].self,
            forKey: .notchedStringerSizing
        ) ?? []
    }
}

public struct StairStringerSizingRow: Codable, Equatable {
    public var size: LumberSize
    public var species: WoodSpecies
    public var grade: LumberGrade
    public var maxSpacingInchesOC: Double
    public var maxStringerLengthInches: Double
    public var codeSection: String
    public var stringerType: StairStringerType

    private enum CodingKeys: String, CodingKey {
        case size
        case species
        case grade
        case maxSpacingInchesOC
        case maxStringerLengthInches
        case codeSection
        case stringerType
    }

    public init(
        size: LumberSize,
        species: WoodSpecies,
        grade: LumberGrade,
        maxSpacingInchesOC: Double,
        maxStringerLengthInches: Double,
        codeSection: String,
        stringerType: StairStringerType = .notchedWoodOpen
    ) {
        self.size = size
        self.species = species
        self.grade = grade
        self.maxSpacingInchesOC = maxSpacingInchesOC
        self.maxStringerLengthInches = maxStringerLengthInches
        self.codeSection = codeSection
        self.stringerType = stringerType
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.size = try c.decodeIfPresent(LumberSize.self, forKey: .size) ?? .twoByTwelve
        self.species = try c.decodeIfPresent(WoodSpecies.self, forKey: .species) ?? .sprucePineFir
        self.grade = try c.decodeIfPresent(LumberGrade.self, forKey: .grade) ?? .no2
        self.maxSpacingInchesOC = try c.decodeIfPresent(Double.self, forKey: .maxSpacingInchesOC) ?? 24
        self.maxStringerLengthInches = try c.decodeIfPresent(
            Double.self,
            forKey: .maxStringerLengthInches
        ) ?? 0
        self.codeSection = try c.decodeIfPresent(String.self, forKey: .codeSection)
            ?? "IRC R311.7 / AWC DCA6"
        self.stringerType = try c.decodeIfPresent(
            StairStringerType.self,
            forKey: .stringerType
        ) ?? .notchedWoodOpen
    }
}
