import Foundation

public struct CodePackage: Codable, Equatable {
    public var jurisdictionId: String
    public var edition: String?
    public var publishedDate: Date
    public var unitSystem: PackageUnits
    public var stairRules: StairRules

    private enum CodingKeys: String, CodingKey {
        case jurisdictionId
        case edition
        case publishedDate
        case unitSystem
        case stairRules
    }

    public init(
        jurisdictionId: String = "",
        edition: String? = nil,
        publishedDate: Date = Date(timeIntervalSince1970: 0),
        unitSystem: PackageUnits = .imperial,
        stairRules: StairRules = StairRules()
    ) {
        self.jurisdictionId = jurisdictionId
        self.edition = edition
        self.publishedDate = publishedDate
        self.unitSystem = unitSystem
        self.stairRules = stairRules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.jurisdictionId = try c.decodeIfPresent(String.self, forKey: .jurisdictionId) ?? ""
        self.edition = try c.decodeIfPresent(String.self, forKey: .edition)
        self.publishedDate = try c.decodeIfPresent(Date.self, forKey: .publishedDate)
            ?? Date(timeIntervalSince1970: 0)
        self.unitSystem = try c.decodeIfPresent(PackageUnits.self, forKey: .unitSystem) ?? .imperial
        self.stairRules = try c.decodeIfPresent(StairRules.self, forKey: .stairRules) ?? StairRules()
    }
}

public enum PackageUnits: String, Codable, Equatable {
    case imperial
    case metric
}

public enum StairStringerType: String, Codable, CaseIterable {
    case notchedWoodOpen = "notched_wood_open"
    case closedWood = "closed_wood"
    case steel
}

public struct StairRules: Codable, Equatable {
    public var maxRiserHeightInches: Double
    public var minTreadRunInches: Double
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
