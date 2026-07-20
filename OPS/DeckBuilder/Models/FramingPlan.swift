import CoreGraphics
import CryptoKit
import Foundation

/// The shared persisted framing contract used by the full Deckset app.
///
/// OPS is a light client: it can decode and render these members, but it does
/// not author or size them. Unknown raw fields are preserved separately by
/// `DeckDrawingData` so opening a newer Deckset file here is lossless.
struct FramingPlan: Codable, Equatable {
    var members: [FramingMemberSet]
    var loadPreset: LoadPreset?
    var generationSource: FramingSource
    var generatedAtSchemaVersion: Int?

    private enum CodingKeys: String, CodingKey {
        case members
        case loadPreset
        case generationSource
        case generatedAtSchemaVersion
    }

    init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        members = try container.decodeLossyArrayIfPresent(FramingMemberSet.self, forKey: .members)
        loadPreset = try? container.decodeIfPresent(LoadPreset.self, forKey: .loadPreset)
        generationSource = (try? container.decodeIfPresent(FramingSource.self, forKey: .generationSource)) ?? .auto
        generatedAtSchemaVersion = try? container.decodeIfPresent(Int.self, forKey: .generatedAtSchemaVersion)
    }
}

struct FramingMemberSet: Codable, Equatable {
    var levelId: String
    var members: [FramingMember]

    private enum CodingKeys: String, CodingKey {
        case levelId
        case members
    }

    init(levelId: String, members: [FramingMember]) {
        self.levelId = levelId
        self.members = members
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        levelId = try container.decodeIfPresent(String.self, forKey: .levelId) ?? ""
        members = try container.decodeLossyArrayIfPresent(FramingMember.self, forKey: .members)
    }
}

struct FramingMember: Codable, Equatable, Identifiable {
    let id: String
    var role: FramingRole
    var start: CGPoint
    var end: CGPoint
    var nominalSize: LumberSize?
    var plyCount: Int
    var spacingInchesOC: Double?
    var species: WoodSpecies?
    var grade: LumberGrade?
    /// Opaque engineering output owned by the full Deckset runtime.
    var sizing: DeckJSONValue?
    var locked: Bool

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

    init(
        id: String = UUID().uuidString,
        role: FramingRole,
        start: CGPoint,
        end: CGPoint,
        nominalSize: LumberSize? = nil,
        plyCount: Int = 1,
        spacingInchesOC: Double? = nil,
        species: WoodSpecies? = nil,
        grade: LumberGrade? = nil,
        sizing: DeckJSONValue? = nil,
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try? container.decode(String.self, forKey: .id)
        let role = try container.decode(FramingRole.self, forKey: .role)
        let start = try container.decode(CGPoint.self, forKey: .start)
        let end = try container.decode(CGPoint.self, forKey: .end)
        let nominalSize = try? container.decode(LumberSize.self, forKey: .nominalSize)
        let plyCount = (try? container.decode(Int.self, forKey: .plyCount)) ?? 1
        let spacingInchesOC = try? container.decode(Double.self, forKey: .spacingInchesOC)
        let species = try? container.decode(WoodSpecies.self, forKey: .species)
        let grade = try? container.decode(LumberGrade.self, forKey: .grade)
        let sizing = try? container.decode(DeckJSONValue.self, forKey: .sizing)
        let locked = (try? container.decodeLegacyBoolIfPresent(forKey: .locked)) ?? false
        let resolvedID = decodedID.flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.stableLegacyIdentifier(
                role: role,
                start: start,
                end: end,
                nominalSize: nominalSize,
                plyCount: plyCount,
                spacingInchesOC: spacingInchesOC,
                species: species,
                grade: grade,
                sizing: sizing,
                locked: locked
            )

        self.init(
            id: resolvedID,
            role: role,
            start: start,
            end: end,
            nominalSize: nominalSize,
            plyCount: plyCount,
            spacingInchesOC: spacingInchesOC,
            species: species,
            grade: grade,
            sizing: sizing,
            locked: locked
        )
    }

    private static func stableLegacyIdentifier(
        role: FramingRole,
        start: CGPoint,
        end: CGPoint,
        nominalSize: LumberSize?,
        plyCount: Int,
        spacingInchesOC: Double?,
        species: WoodSpecies?,
        grade: LumberGrade?,
        sizing: DeckJSONValue?,
        locked: Bool
    ) -> String {
        func bits(_ value: CGFloat) -> String {
            String(Double(value).bitPattern, radix: 16)
        }

        let signature = [
            role.rawValue,
            bits(start.x),
            bits(start.y),
            bits(end.x),
            bits(end.y),
            nominalSize?.rawValue ?? "-",
            String(plyCount),
            spacingInchesOC.map { String($0.bitPattern, radix: 16) } ?? "-",
            species?.rawValue ?? "-",
            grade?.rawValue ?? "-",
            (try? sizing?.renderedJSONString()) ?? "-",
            locked ? "1" : "0",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(signature.utf8))
        let token = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "legacy-\(token)"
    }
}

enum FramingRole: String, Codable, CaseIterable {
    case joist
    case beam
    case post
    case ledger
    case rimBand
    case blocking
    case bridging
    case cantilever
}

enum LumberSize: String, Codable, CaseIterable {
    case twoBySix = "2x6"
    case twoByEight = "2x8"
    case twoByTen = "2x10"
    case twoByTwelve = "2x12"
    case fourByFour = "4x4"
    case fourBySix = "4x6"
    case sixBySix = "6x6"
}

enum WoodSpecies: String, Codable, CaseIterable {
    case southernPine = "southern_pine"
    case douglasFirLarch = "df_l"
    case hemFir = "hem_fir"
    case sprucePineFir = "spf"
    case redwoodCedar = "redwood_cedar"
}

enum LumberGrade: String, Codable, CaseIterable {
    case select = "select_structural"
    case no1
    case no2
}

enum FramingSource: String, Codable {
    case auto
    case manual
    case autoThenEdited
}

struct LoadPreset: Codable, Equatable {
    var liveLoadPSF: Double
    var deadLoadPSF: Double
    var snowLoadPSF: Double?
    var species: WoodSpecies
    var grade: LumberGrade

    private enum CodingKeys: String, CodingKey {
        case liveLoadPSF
        case deadLoadPSF
        case snowLoadPSF
        case species
        case grade
    }

    init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liveLoadPSF = (try? container.decodeIfPresent(Double.self, forKey: .liveLoadPSF)) ?? 40
        deadLoadPSF = (try? container.decodeIfPresent(Double.self, forKey: .deadLoadPSF)) ?? 10
        snowLoadPSF = try? container.decodeIfPresent(Double.self, forKey: .snowLoadPSF)
        species = (try? container.decodeIfPresent(WoodSpecies.self, forKey: .species)) ?? .sprucePineFir
        grade = (try? container.decodeIfPresent(LumberGrade.self, forKey: .grade)) ?? .no2
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
                _ = try? container.decode(DiscardedFramingValue.self)
            }
        }

        return values
    }
}

private struct DiscardedFramingValue: Decodable {}
