import Foundation

public struct EngineCitation: Codable, Equatable {
    public var limitingCheck: String
    public var codeSection: String
    public var packageEdition: String

    public init(limitingCheck: String, codeSection: String, packageEdition: String) {
        self.limitingCheck = limitingCheck
        self.codeSection = codeSection
        self.packageEdition = packageEdition
    }
}

public enum EngineOutcome<T: Codable & Equatable>: Codable, Equatable {
    case ok(value: T, citation: EngineCitation, assumptions: EngineAssumptions)
    case outOfEnvelope(reason: String, citation: EngineCitation)

    private enum CodingKeys: String, CodingKey {
        case outcomeCase = "case"
        case value
        case citation
        case assumptions
        case reason
    }

    private enum Discriminator: String, Codable {
        case ok
        case outOfEnvelope
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let discriminator = try c.decode(Discriminator.self, forKey: .outcomeCase)
        switch discriminator {
        case .ok:
            self = .ok(
                value: try c.decode(T.self, forKey: .value),
                citation: try c.decode(EngineCitation.self, forKey: .citation),
                assumptions: try c.decode(EngineAssumptions.self, forKey: .assumptions)
            )
        case .outOfEnvelope:
            self = .outOfEnvelope(
                reason: try c.decode(String.self, forKey: .reason),
                citation: try c.decode(EngineCitation.self, forKey: .citation)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .ok(value, citation, assumptions):
            try c.encode(Discriminator.ok, forKey: .outcomeCase)
            try c.encode(value, forKey: .value)
            try c.encode(citation, forKey: .citation)
            try c.encode(assumptions, forKey: .assumptions)
        case let .outOfEnvelope(reason, citation):
            try c.encode(Discriminator.outOfEnvelope, forKey: .outcomeCase)
            try c.encode(reason, forKey: .reason)
            try c.encode(citation, forKey: .citation)
        }
    }
}

public struct EngineAssumptions: Codable, Equatable {
    public var liveLoadPSF: Double
    public var deadLoadPSF: Double
    public var snowLoadPSF: Double?
    public var species: WoodSpecies
    public var grade: LumberGrade
    public var soilBearingPSF: Double?
    public var packageEdition: String

    public init(
        liveLoadPSF: Double,
        deadLoadPSF: Double,
        snowLoadPSF: Double?,
        species: WoodSpecies,
        grade: LumberGrade,
        soilBearingPSF: Double?,
        packageEdition: String
    ) {
        self.liveLoadPSF = liveLoadPSF
        self.deadLoadPSF = deadLoadPSF
        self.snowLoadPSF = snowLoadPSF
        self.species = species
        self.grade = grade
        self.soilBearingPSF = soilBearingPSF
        self.packageEdition = packageEdition
    }
}

public struct SizedMember: Codable, Equatable {
    public var size: LumberSize
    public var plyCount: Int
    public var allowableSpanFeet: Double
    public var actualSpanFeet: Double
    public var utilization: Double

    public init(
        size: LumberSize,
        plyCount: Int,
        allowableSpanFeet: Double,
        actualSpanFeet: Double,
        utilization: Double
    ) {
        self.size = size
        self.plyCount = plyCount
        self.allowableSpanFeet = allowableSpanFeet
        self.actualSpanFeet = actualSpanFeet
        self.utilization = utilization
    }
}

public struct MemberSizingResult: Codable, Equatable {
    public var outcome: EngineOutcome<SizedMember>

    public init(outcome: EngineOutcome<SizedMember>) {
        self.outcome = outcome
    }
}
