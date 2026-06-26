import Foundation
import CoreGraphics

public struct FramingPlan: Codable, Equatable {
    public var members: [FramingMemberSet]
    public var loadPreset: LoadPreset?
    public var generationSource: FramingSource
    public var generatedAtSchemaVersion: Int?

    private enum CodingKeys: String, CodingKey {
        case members
        case loadPreset
        case generationSource
        case generatedAtSchemaVersion
    }

    public init(
        members: [FramingMemberSet],
        loadPreset: LoadPreset? = nil,
        generationSource: FramingSource,
        generatedAtSchemaVersion: Int? = nil
    ) {
        self.members = members
        self.loadPreset = loadPreset
        self.generationSource = generationSource
        self.generatedAtSchemaVersion = generatedAtSchemaVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.members = try c.decodeLossyArrayIfPresent(FramingMemberSet.self, forKey: .members)
        self.loadPreset = try c.decodeIfPresent(LoadPreset.self, forKey: .loadPreset)
        self.generationSource = try c.decodeIfPresent(FramingSource.self, forKey: .generationSource) ?? .auto
        self.generatedAtSchemaVersion = try c.decodeIfPresent(Int.self, forKey: .generatedAtSchemaVersion)
    }
}

public struct FramingMemberSet: Codable, Equatable {
    public var levelId: String
    public var members: [FramingMember]

    private enum CodingKeys: String, CodingKey {
        case levelId
        case members
    }

    public init(levelId: String, members: [FramingMember]) {
        self.levelId = levelId
        self.members = members
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.levelId = try c.decodeIfPresent(String.self, forKey: .levelId) ?? ""
        self.members = try c.decodeLossyArrayIfPresent(FramingMember.self, forKey: .members)
    }
}

public struct FramingMember: Codable, Equatable, Identifiable {
    public let id: String
    public var role: FramingRole
    public var start: CGPoint
    public var end: CGPoint
    public var nominalSize: LumberSize?
    public var plyCount: Int
    public var spacingInchesOC: Double?
    public var species: WoodSpecies?
    public var grade: LumberGrade?
    public var sizing: MemberSizingResult?
    public var locked: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case start
        case end
        case nominalSize
        case plyCount
        case spacingInchesOC
        case species
        case grade
        case sizing
        case locked
    }

    public init(
        id: String = UUID().uuidString,
        role: FramingRole,
        start: CGPoint,
        end: CGPoint,
        nominalSize: LumberSize? = nil,
        plyCount: Int = 1,
        spacingInchesOC: Double? = nil,
        species: WoodSpecies? = nil,
        grade: LumberGrade? = nil,
        sizing: MemberSizingResult? = nil,
        locked: Bool = false
    ) {
        self.id = id
        self.role = role
        self.start = start
        self.end = end
        self.nominalSize = nominalSize
        self.plyCount = plyCount
        self.spacingInchesOC = spacingInchesOC
        self.species = species
        self.grade = grade
        self.sizing = sizing
        self.locked = locked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.role = try c.decode(FramingRole.self, forKey: .role)
        self.start = try c.decode(CGPoint.self, forKey: .start)
        self.end = try c.decode(CGPoint.self, forKey: .end)
        self.nominalSize = try c.decodeIfPresent(LumberSize.self, forKey: .nominalSize)
        self.plyCount = try c.decodeIfPresent(Int.self, forKey: .plyCount) ?? 1
        self.spacingInchesOC = try c.decodeIfPresent(Double.self, forKey: .spacingInchesOC)
        self.species = try c.decodeIfPresent(WoodSpecies.self, forKey: .species)
        self.grade = try c.decodeIfPresent(LumberGrade.self, forKey: .grade)
        self.sizing = try c.decodeIfPresent(MemberSizingResult.self, forKey: .sizing)
        self.locked = try c.decodeLegacyBoolIfPresent(forKey: .locked) ?? false
    }
}

public enum FramingRole: String, Codable, CaseIterable {
    case joist
    case beam
    case post
    case ledger
    case rimBand
    case blocking
    case bridging
    case cantilever
}

public enum LumberSize: String, Codable, CaseIterable {
    case twoBySix = "2x6"
    case twoByEight = "2x8"
    case twoByTen = "2x10"
    case twoByTwelve = "2x12"
    case fourByFour = "4x4"
    case fourBySix = "4x6"
    case sixBySix = "6x6"
}

public enum WoodSpecies: String, Codable, CaseIterable {
    case southernPine = "southern_pine"
    case douglasFirLarch = "df_l"
    case hemFir = "hem_fir"
    case sprucePineFir = "spf"
    case redwoodCedar = "redwood_cedar"
}

public enum LumberGrade: String, Codable, CaseIterable {
    case select = "select_structural"
    case no1
    case no2
}

public enum FramingSource: String, Codable {
    case auto
    case manual
    case autoThenEdited
}

public struct LoadPreset: Codable, Equatable {
    public var liveLoadPSF: Double
    public var deadLoadPSF: Double
    public var snowLoadPSF: Double?
    public var species: WoodSpecies
    public var grade: LumberGrade

    private enum CodingKeys: String, CodingKey {
        case liveLoadPSF
        case deadLoadPSF
        case snowLoadPSF
        case species
        case grade
    }

    public init(
        liveLoadPSF: Double = 40,
        deadLoadPSF: Double = 10,
        snowLoadPSF: Double? = nil,
        species: WoodSpecies = .sprucePineFir,
        grade: LumberGrade = .no2
    ) {
        self.liveLoadPSF = liveLoadPSF
        self.deadLoadPSF = deadLoadPSF
        self.snowLoadPSF = snowLoadPSF
        self.species = species
        self.grade = grade
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.liveLoadPSF = try c.decodeIfPresent(Double.self, forKey: .liveLoadPSF) ?? 40
        self.deadLoadPSF = try c.decodeIfPresent(Double.self, forKey: .deadLoadPSF) ?? 10
        self.snowLoadPSF = try c.decodeIfPresent(Double.self, forKey: .snowLoadPSF)
        self.species = try c.decodeIfPresent(WoodSpecies.self, forKey: .species) ?? .sprucePineFir
        self.grade = try c.decodeIfPresent(LumberGrade.self, forKey: .grade) ?? .no2
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyArrayIfPresent<Element: Decodable>(
        _ type: Element.Type,
        forKey key: Key
    ) throws -> [Element] {
        guard contains(key), !(try decodeNil(forKey: key)) else { return [] }
        var container = try nestedUnkeyedContainer(forKey: key)
        var values: [Element] = []

        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                values.append(value)
            } else {
                _ = try? container.decode(DiscardedDecodable.self)
            }
        }

        return values
    }
}

private struct DiscardedDecodable: Decodable {}
