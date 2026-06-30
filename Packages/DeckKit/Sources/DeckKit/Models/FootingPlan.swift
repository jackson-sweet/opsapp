import CoreGraphics
import Foundation

public struct FootingPlan: Codable, Equatable {
    public var footings: [Footing]
    public var soil: SoilInput?
    public var frost: FrostInput?

    private enum CodingKeys: String, CodingKey {
        case footings
        case soil
        case frost
    }

    public init(
        footings: [Footing] = [],
        soil: SoilInput? = nil,
        frost: FrostInput? = nil
    ) {
        self.footings = footings
        self.soil = soil
        self.frost = frost
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.footings = (try? c.decodeLossyArrayIfPresent(Footing.self, forKey: .footings)) ?? []
        self.soil = try? c.decodeIfPresent(SoilInput.self, forKey: .soil)
        self.frost = try? c.decodeIfPresent(FrostInput.self, forKey: .frost)
    }
}

public struct Footing: Codable, Equatable, Identifiable {
    public let id: String
    /// Anchors to a perimeter vertex, or nil for a free pier on a beam line.
    public var vertexId: String?
    /// Canvas-space position, matching `DeckVertex.position` and `FramingMember.start/end`.
    public var position: CGPoint
    public var type: FootingType
    public var diameterInches: Double?
    public var depthInches: Double?
    public var helicalTorqueFtLb: Double?
    public var connection: PostFootingConnection?
    /// Filled by `FootingEngine`; nil means geometry exists but has not been sized.
    public var sizing: FootingSizingResult?

    private enum CodingKeys: String, CodingKey {
        case id
        case vertexId
        case position
        case type
        case diameterInches
        case depthInches
        case helicalTorqueFtLb
        case connection
        case sizing
    }

    public init(
        id: String = UUID().uuidString,
        vertexId: String? = nil,
        position: CGPoint,
        type: FootingType = .sonoTube,
        diameterInches: Double? = nil,
        depthInches: Double? = nil,
        helicalTorqueFtLb: Double? = nil,
        connection: PostFootingConnection? = nil,
        sizing: FootingSizingResult? = nil
    ) {
        self.id = id
        self.vertexId = vertexId
        self.position = position
        self.type = type
        self.diameterInches = diameterInches
        self.depthInches = depthInches
        self.helicalTorqueFtLb = helicalTorqueFtLb
        self.connection = connection
        self.sizing = sizing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.vertexId = try c.decodeIfPresent(String.self, forKey: .vertexId)
        self.position = try c.decodeIfPresent(CGPoint.self, forKey: .position) ?? .zero
        self.type = (try? c.decodeIfPresent(FootingType.self, forKey: .type)) ?? .sonoTube
        self.diameterInches = try? c.decodeIfPresent(Double.self, forKey: .diameterInches)
        self.depthInches = try? c.decodeIfPresent(Double.self, forKey: .depthInches)
        self.helicalTorqueFtLb = try? c.decodeIfPresent(Double.self, forKey: .helicalTorqueFtLb)
        self.connection = try? c.decodeIfPresent(PostFootingConnection.self, forKey: .connection)
        self.sizing = try? c.decodeIfPresent(FootingSizingResult.self, forKey: .sizing)
    }
}

public struct SoilInput: Codable, Equatable {
    public var bearingCapacityPSF: Double
    public var source: SoilSource

    private enum CodingKeys: String, CodingKey {
        case bearingCapacityPSF
        case source
    }

    public init(
        bearingCapacityPSF: Double = 1500,
        source: SoilSource = .presumptive
    ) {
        self.bearingCapacityPSF = bearingCapacityPSF
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bearingCapacityPSF = try c.decodeIfPresent(Double.self, forKey: .bearingCapacityPSF) ?? 1500
        self.source = try c.decodeIfPresent(SoilSource.self, forKey: .source) ?? .presumptive
    }
}

public struct FrostInput: Codable, Equatable {
    public var depthInches: Double?
    public var source: FrostSource

    private enum CodingKeys: String, CodingKey {
        case depthInches
        case source
    }

    public init(
        depthInches: Double? = nil,
        source: FrostSource = .userEntered
    ) {
        self.depthInches = depthInches
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.depthInches = try? c.decodeIfPresent(Double.self, forKey: .depthInches)
        self.source = try c.decodeIfPresent(FrostSource.self, forKey: .source) ?? .userEntered
    }
}

public enum SoilSource: String, Codable, CaseIterable {
    case presumptive
    case geotechReport
}

public enum FrostSource: String, Codable, CaseIterable {
    case bundledTable
    case userEntered
    case ahjVerified
}

public struct PostFootingConnection: Codable, Equatable {
    public var hardwareModel: String?
    public var upliftRated: Bool

    private enum CodingKeys: String, CodingKey {
        case hardwareModel
        case upliftRated
    }

    public init(
        hardwareModel: String? = nil,
        upliftRated: Bool = false
    ) {
        self.hardwareModel = hardwareModel
        self.upliftRated = upliftRated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hardwareModel = try c.decodeIfPresent(String.self, forKey: .hardwareModel)
        self.upliftRated = try c.decodeLegacyBoolIfPresent(forKey: .upliftRated) ?? false
    }
}

public struct FootingSizingResult: Codable, Equatable {
    public var diameterInches: Double
    public var depthInches: Double
    public var bearingAreaSqIn: Double
    public var requiredFrostDepthInches: Double
    public var citation: EngineCitation

    private enum CodingKeys: String, CodingKey {
        case diameterInches
        case depthInches
        case bearingAreaSqIn
        case requiredFrostDepthInches
        case citation
    }

    public init(
        diameterInches: Double = 0,
        depthInches: Double = 0,
        bearingAreaSqIn: Double = 0,
        requiredFrostDepthInches: Double = 0,
        citation: EngineCitation = EngineCitation(
            limitingCheck: "",
            codeSection: "",
            packageEdition: ""
        )
    ) {
        self.diameterInches = diameterInches
        self.depthInches = depthInches
        self.bearingAreaSqIn = bearingAreaSqIn
        self.requiredFrostDepthInches = requiredFrostDepthInches
        self.citation = citation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.diameterInches = try c.decodeIfPresent(Double.self, forKey: .diameterInches) ?? 0
        self.depthInches = try c.decodeIfPresent(Double.self, forKey: .depthInches) ?? 0
        self.bearingAreaSqIn = try c.decodeIfPresent(Double.self, forKey: .bearingAreaSqIn) ?? 0
        self.requiredFrostDepthInches = try c.decodeIfPresent(Double.self, forKey: .requiredFrostDepthInches) ?? 0
        self.citation = try c.decodeIfPresent(EngineCitation.self, forKey: .citation) ?? EngineCitation(
            limitingCheck: "",
            codeSection: "",
            packageEdition: ""
        )
    }
}

public struct ConcreteTakeoff: Codable, Equatable {
    public var cubicFeet: Double
    public var bagCount: Int
    public var bagSizeLb: Int

    private enum CodingKeys: String, CodingKey {
        case cubicFeet
        case bagCount
        case bagSizeLb
    }

    public init(
        cubicFeet: Double = 0,
        bagCount: Int = 0,
        bagSizeLb: Int = 80
    ) {
        self.cubicFeet = cubicFeet
        self.bagCount = bagCount
        self.bagSizeLb = bagSizeLb
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.cubicFeet = try c.decodeIfPresent(Double.self, forKey: .cubicFeet) ?? 0
        self.bagCount = try c.decodeIfPresent(Int.self, forKey: .bagCount) ?? 0
        self.bagSizeLb = try c.decodeIfPresent(Int.self, forKey: .bagSizeLb) ?? 80
    }
}

public struct PostReaction: Codable, Equatable {
    public var footingOrPostId: String
    public var reactionLb: Double
    public var tributaryAreaSqFt: Double

    private enum CodingKeys: String, CodingKey {
        case footingOrPostId
        case reactionLb
        case tributaryAreaSqFt
    }

    public init(
        footingOrPostId: String,
        reactionLb: Double = 0,
        tributaryAreaSqFt: Double = 0
    ) {
        self.footingOrPostId = footingOrPostId
        self.reactionLb = reactionLb
        self.tributaryAreaSqFt = tributaryAreaSqFt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.footingOrPostId = try c.decodeIfPresent(String.self, forKey: .footingOrPostId) ?? ""
        self.reactionLb = try c.decodeIfPresent(Double.self, forKey: .reactionLb) ?? 0
        self.tributaryAreaSqFt = try c.decodeIfPresent(Double.self, forKey: .tributaryAreaSqFt) ?? 0
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
