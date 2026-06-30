public struct DeckHouseToolEntry: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case houseAndOpenings
        case elevation
        case schedule
        case opsDecksUpsell
    }

    public let kind: Kind
    public let title: String
    public let systemImage: String
    public let isActionable: Bool
    public let isUpsell: Bool

    public var id: String {
        kind.rawValue
    }

    public init(
        kind: Kind,
        title: String,
        systemImage: String,
        isActionable: Bool,
        isUpsell: Bool
    ) {
        self.kind = kind
        self.title = title
        self.systemImage = systemImage
        self.isActionable = isActionable
        self.isUpsell = isUpsell
    }

    public static func houseToolEntries(
        for capabilities: DeckCapabilities,
        includeUpsellStub: Bool = true
    ) -> [DeckHouseToolEntry] {
        guard capabilities.contains(.houseOpenings) else {
            return includeUpsellStub ? [opsDecksUpsellEntry] : []
        }

        return [
            DeckHouseToolEntry(
                kind: .houseAndOpenings,
                title: "House & openings",
                systemImage: "house.and.flag",
                isActionable: true,
                isUpsell: false
            ),
            DeckHouseToolEntry(
                kind: .elevation,
                title: "Elevation",
                systemImage: "rectangle.portrait.and.arrow.right",
                isActionable: true,
                isUpsell: false
            ),
            DeckHouseToolEntry(
                kind: .schedule,
                title: "Schedule",
                systemImage: "tablecells",
                isActionable: true,
                isUpsell: false
            ),
        ]
    }

    private static let opsDecksUpsellEntry = DeckHouseToolEntry(
        kind: .opsDecksUpsell,
        title: "Available in OPS Decks",
        systemImage: "lock",
        isActionable: false,
        isUpsell: true
    )
}
