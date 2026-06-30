import Foundation

public struct HouseModel: Codable, Equatable {
    /// Floor-line datum (feet) the deck attaches to; story heights are feet for elevation views.
    public var floorLineFeet: Double?
    public var storyHeights: [Double]
    /// Openings (doors/windows) placed on house edges. Drives wall cutouts,
    /// elevation views, and the door/window schedule.
    public var openings: [WallOpening]
    /// Ledger attachment detail. Brick/stone cladding routes to freestanding fallback.
    public var ledger: LedgerDetail?

    private enum CodingKeys: String, CodingKey {
        case floorLineFeet
        case storyHeights
        case openings
        case ledger
    }

    public init(
        floorLineFeet: Double? = nil,
        storyHeights: [Double] = [],
        openings: [WallOpening] = [],
        ledger: LedgerDetail? = nil
    ) {
        self.floorLineFeet = floorLineFeet
        self.storyHeights = storyHeights
        self.openings = openings
        self.ledger = ledger
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.floorLineFeet = try? c.decodeIfPresent(Double.self, forKey: .floorLineFeet)
        self.storyHeights = (try? c.decodeIfPresent([Double].self, forKey: .storyHeights)) ?? []
        self.openings = try c.decodeLossyArrayIfPresent(WallOpening.self, forKey: .openings)
        self.ledger = try? c.decodeIfPresent(LedgerDetail.self, forKey: .ledger)
    }
}

public struct WallOpening: Codable, Equatable, Identifiable {
    public let id: String
    public var edgeId: String
    public var kind: OpeningKind
    public var widthInches: Double
    public var heightInches: Double
    /// Height above the modeled floor line. Floor-level doors use 0.
    public var sillHeightInches: Double
    public var offsetAlongEdgeInches: Double

    private enum CodingKeys: String, CodingKey {
        case id
        case edgeId
        case kind
        case widthInches
        case heightInches
        case sillHeightInches
        case offsetAlongEdgeInches
    }

    public init(
        id: String = UUID().uuidString,
        edgeId: String,
        kind: OpeningKind = .window,
        widthInches: Double = 0,
        heightInches: Double = 0,
        sillHeightInches: Double = 0,
        offsetAlongEdgeInches: Double = 0
    ) {
        self.id = id
        self.edgeId = edgeId
        self.kind = kind
        self.widthInches = widthInches
        self.heightInches = heightInches
        self.sillHeightInches = sillHeightInches
        self.offsetAlongEdgeInches = offsetAlongEdgeInches
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.edgeId = try c.decodeIfPresent(String.self, forKey: .edgeId) ?? ""
        self.kind = try c.decodeIfPresent(OpeningKind.self, forKey: .kind) ?? .window
        self.widthInches = try c.decodeIfPresent(Double.self, forKey: .widthInches) ?? 0
        self.heightInches = try c.decodeIfPresent(Double.self, forKey: .heightInches) ?? 0
        self.sillHeightInches = try c.decodeIfPresent(Double.self, forKey: .sillHeightInches) ?? 0
        self.offsetAlongEdgeInches = try c.decodeIfPresent(Double.self, forKey: .offsetAlongEdgeInches) ?? 0
    }
}

public enum OpeningKind: String, Codable, CaseIterable {
    case patioDoor
    case frenchDoor
    case sliderDoor
    case window

    public var displayName: String {
        switch self {
        case .patioDoor:
            return "Patio door"
        case .frenchDoor:
            return "French door"
        case .sliderDoor:
            return "Sliding door"
        case .window:
            return "Window"
        }
    }
}

public struct LedgerDetail: Codable, Equatable {
    public var cladding: HouseEdgeMaterial
    public var attachmentAllowed: Bool
    public var fastenerSchedule: String?
    public var lateralConnectors: Int?

    private enum CodingKeys: String, CodingKey {
        case cladding
        case attachmentAllowed
        case fastenerSchedule
        case lateralConnectors
    }

    public init(
        cladding: HouseEdgeMaterial = .stucco,
        attachmentAllowed: Bool = true,
        fastenerSchedule: String? = nil,
        lateralConnectors: Int? = nil
    ) {
        self.cladding = cladding
        self.attachmentAllowed = attachmentAllowed
        self.fastenerSchedule = fastenerSchedule
        self.lateralConnectors = lateralConnectors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.cladding = try c.decodeIfPresent(HouseEdgeMaterial.self, forKey: .cladding) ?? .stucco
        self.attachmentAllowed = try c.decodeLegacyBoolIfPresent(forKey: .attachmentAllowed) ?? true
        self.fastenerSchedule = try c.decodeIfPresent(String.self, forKey: .fastenerSchedule)
        self.lateralConnectors = try c.decodeIfPresent(Int.self, forKey: .lateralConnectors)
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
