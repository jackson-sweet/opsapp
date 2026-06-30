import CoreGraphics
import Foundation

public struct SurfaceFeaturePlan: Codable, Equatable {
    public var patterns: [SurfacePatternSpec]
    public var fastenerSystem: FastenerSystem?
    public var finishes: [FinishSpec]
    public var fascia: Bool
    public var skirting: SkirtingSpec?
    public var builtIns: [BuiltInFeature]
    public var lighting: LightingPlan?

    private enum CodingKeys: String, CodingKey {
        case patterns
        case fastenerSystem
        case finishes
        case fascia
        case skirting
        case builtIns
        case lighting
    }

    public init(
        patterns: [SurfacePatternSpec] = [],
        fastenerSystem: FastenerSystem? = nil,
        finishes: [FinishSpec] = [],
        fascia: Bool = false,
        skirting: SkirtingSpec? = nil,
        builtIns: [BuiltInFeature] = [],
        lighting: LightingPlan? = nil
    ) {
        self.patterns = patterns
        self.fastenerSystem = fastenerSystem
        self.finishes = finishes
        self.fascia = fascia
        self.skirting = skirting
        self.builtIns = builtIns
        self.lighting = lighting
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.patterns = try c.decodeLossyArrayIfPresent(SurfacePatternSpec.self, forKey: .patterns)
        self.fastenerSystem = try? c.decodeIfPresent(FastenerSystem.self, forKey: .fastenerSystem)
        self.finishes = try c.decodeLossyArrayIfPresent(FinishSpec.self, forKey: .finishes)
        self.fascia = try c.decodeLegacyBoolIfPresent(forKey: .fascia) ?? false
        self.skirting = try? c.decodeIfPresent(SkirtingSpec.self, forKey: .skirting)
        self.builtIns = try c.decodeLossyArrayIfPresent(BuiltInFeature.self, forKey: .builtIns)
        self.lighting = try? c.decodeIfPresent(LightingPlan.self, forKey: .lighting)
    }
}

public struct SurfacePatternSpec: Codable, Equatable {
    public var surfaceId: String
    public var pattern: DeckingPattern
    public var boardAngleDegrees: Double
    public var pictureFrameCourses: Int

    private enum CodingKeys: String, CodingKey {
        case surfaceId
        case pattern
        case boardAngleDegrees
        case pictureFrameCourses
    }

    public init(
        surfaceId: String,
        pattern: DeckingPattern,
        boardAngleDegrees: Double = 0,
        pictureFrameCourses: Int = 0
    ) {
        self.surfaceId = surfaceId
        self.pattern = pattern
        self.boardAngleDegrees = boardAngleDegrees
        self.pictureFrameCourses = pictureFrameCourses
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.surfaceId = try c.decodeIfPresent(String.self, forKey: .surfaceId) ?? ""
        self.pattern = (try? c.decodeIfPresent(DeckingPattern.self, forKey: .pattern)) ?? .parallel
        self.boardAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .boardAngleDegrees) ?? 0
        self.pictureFrameCourses = try c.decodeIfPresent(Int.self, forKey: .pictureFrameCourses) ?? 0
    }
}

public enum DeckingPattern: String, Codable, CaseIterable {
    case parallel
    case diagonal
    case pictureFrame = "picture_frame"
    case herringbone
    case chevron
}

public enum FastenerSystem: String, Codable, CaseIterable {
    case hiddenClip = "hidden_clip"
    case faceScrew = "face_screw"
}

public struct FinishSpec: Codable, Equatable {
    public var kind: String
    public var coats: Int

    private enum CodingKeys: String, CodingKey {
        case kind
        case coats
    }

    public init(kind: String, coats: Int) {
        self.kind = kind
        self.coats = coats
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        self.coats = try c.decodeIfPresent(Int.self, forKey: .coats) ?? 0
    }
}

public struct SkirtingSpec: Codable, Equatable {
    public var material: String
    public var ventilated: Bool

    private enum CodingKeys: String, CodingKey {
        case material
        case ventilated
    }

    public init(material: String, ventilated: Bool) {
        self.material = material
        self.ventilated = ventilated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.material = try c.decodeIfPresent(String.self, forKey: .material) ?? ""
        self.ventilated = try c.decodeLegacyBoolIfPresent(forKey: .ventilated) ?? false
    }
}

public struct BuiltInFeature: Codable, Equatable, Identifiable {
    public let id: String
    public var kind: BuiltInKind
    public var polygon: [CGPoint]
    public var heightInches: Double

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case polygon
        case heightInches
    }

    public init(
        id: String = UUID().uuidString,
        kind: BuiltInKind,
        polygon: [CGPoint] = [],
        heightInches: Double = 0
    ) {
        self.id = id
        self.kind = kind
        self.polygon = polygon
        self.heightInches = heightInches
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.kind = (try? c.decodeIfPresent(BuiltInKind.self, forKey: .kind)) ?? .bench
        self.polygon = (try? c.decodeIfPresent([CGPoint].self, forKey: .polygon)) ?? []
        self.heightInches = try c.decodeIfPresent(Double.self, forKey: .heightInches) ?? 0
    }
}

public enum BuiltInKind: String, Codable, CaseIterable {
    case bench
    case planter
    case privacyWall
}

public struct LightingPlan: Codable, Equatable {
    public var fixtures: [CGPoint]
    public var transformerWatts: Double?
    public var receptacles: [CGPoint]

    private enum CodingKeys: String, CodingKey {
        case fixtures
        case transformerWatts
        case receptacles
    }

    public init(
        fixtures: [CGPoint] = [],
        transformerWatts: Double? = nil,
        receptacles: [CGPoint] = []
    ) {
        self.fixtures = fixtures
        self.transformerWatts = transformerWatts
        self.receptacles = receptacles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fixtures = (try? c.decodeIfPresent([CGPoint].self, forKey: .fixtures)) ?? []
        self.transformerWatts = try? c.decodeIfPresent(Double.self, forKey: .transformerWatts)
        self.receptacles = (try? c.decodeIfPresent([CGPoint].self, forKey: .receptacles)) ?? []
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
