import Foundation

public enum MaterialFamily: String, Codable, CaseIterable, Sendable {
    case decking
    case railing
    case fastener
    case finish
    case substrate
    case cladding
}

public struct DeckMaterial: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var family: MaterialFamily
    public var profile: String?
    public var availableLengthsFeet: [Double]
    public var coveragePerUnit: Double?
    public var fastenerSystem: String?
    public var finish: String?
    public var displayName: String

    public init(
        id: String,
        family: MaterialFamily,
        profile: String? = nil,
        availableLengthsFeet: [Double] = [],
        coveragePerUnit: Double? = nil,
        fastenerSystem: String? = nil,
        finish: String? = nil,
        displayName: String
    ) {
        self.id = id
        self.family = family
        self.profile = profile
        self.availableLengthsFeet = availableLengthsFeet
        self.coveragePerUnit = coveragePerUnit
        self.fastenerSystem = fastenerSystem
        self.finish = finish
        self.displayName = displayName
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case family
        case profile
        case availableLengthsFeet
        case coveragePerUnit
        case fastenerSystem
        case finish
        case displayName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        let familyRawValue = try container.decodeIfPresent(String.self, forKey: .family)

        self.id = id
        self.family = familyRawValue.flatMap(MaterialFamily.init(rawValue:)) ?? .decking
        self.profile = try container.decodeIfPresent(String.self, forKey: .profile)
        self.availableLengthsFeet = try container.decodeIfPresent([Double].self, forKey: .availableLengthsFeet) ?? []
        self.coveragePerUnit = try container.decodeIfPresent(Double.self, forKey: .coveragePerUnit)
        self.fastenerSystem = try container.decodeIfPresent(String.self, forKey: .fastenerSystem)
        self.finish = try container.decodeIfPresent(String.self, forKey: .finish)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? id
    }

    public static func from(builtIn: BuiltInMaterial) -> DeckMaterial {
        DeckMaterial(
            id: builtIn.id,
            family: materialFamily(for: builtIn.id),
            profile: nil,
            availableLengthsFeet: defaultLengths(for: builtIn.id),
            coveragePerUnit: nil,
            fastenerSystem: nil,
            finish: nil,
            displayName: builtIn.name
        )
    }

    private static func materialFamily(for builtInId: String) -> MaterialFamily {
        if builtInId.hasPrefix("std.decking.") {
            return .decking
        }
        if builtInId.hasPrefix("std.gate.") {
            return .railing
        }
        if builtInId.hasPrefix("std.cladding.") || builtInId.hasPrefix("std.wall.") {
            return .cladding
        }
        if builtInId.hasPrefix("std.surface.") {
            return .substrate
        }
        return .decking
    }

    private static func defaultLengths(for builtInId: String) -> [Double] {
        if builtInId.hasPrefix("std.decking.") {
            return [12, 16, 20]
        }
        return []
    }
}
