import CoreGraphics
import Foundation

public struct OverheadStructurePlan: Codable, Equatable {
    public var structures: [OverheadStructure]

    private enum CodingKeys: String, CodingKey {
        case structures
    }

    public init(structures: [OverheadStructure] = []) {
        self.structures = structures
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.structures = try c.decodeLossyArrayIfPresent(OverheadStructure.self, forKey: .structures)
    }
}

public struct OverheadStructure: Codable, Equatable, Identifiable {
    public let id: String
    public var kind: OverheadKind
    public var roofShape: RoofShape?
    public var footprint: [CGPoint]
    public var framing: [FramingMember]
    public var shadePercent: Double?
    public var productModel: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case roofShape
        case footprint
        case framing
        case shadePercent
        case productModel
    }

    public init(
        id: String = UUID().uuidString,
        kind: OverheadKind,
        roofShape: RoofShape? = nil,
        footprint: [CGPoint] = [],
        framing: [FramingMember] = [],
        shadePercent: Double? = nil,
        productModel: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.roofShape = roofShape
        self.footprint = footprint
        self.framing = framing
        self.shadePercent = shadePercent
        self.productModel = productModel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.kind = (try? c.decodeIfPresent(OverheadKind.self, forKey: .kind)) ?? .pergola
        self.roofShape = try? c.decodeIfPresent(RoofShape.self, forKey: .roofShape)
        self.footprint = (try? c.decodeIfPresent([CGPoint].self, forKey: .footprint)) ?? []
        self.framing = try c.decodeLossyArrayIfPresent(FramingMember.self, forKey: .framing)
        self.shadePercent = try? c.decodeIfPresent(Double.self, forKey: .shadePercent)
        self.productModel = try? c.decodeIfPresent(String.self, forKey: .productModel)
    }
}

public enum OverheadKind: String, Codable, CaseIterable {
    case pergola
    case louveredRoof = "louvered_roof"
    case solidRoof = "solid_roof"
}

public enum RoofShape: String, Codable, CaseIterable {
    case shed
    case gable
    case hip
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
