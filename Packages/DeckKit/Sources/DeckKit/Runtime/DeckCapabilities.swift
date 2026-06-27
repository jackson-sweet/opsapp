public struct DeckCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let materials = DeckCapabilities(rawValue: 1 << 0)
    public static let plausibleFrame = DeckCapabilities(rawValue: 1 << 1)
    public static let groundCover = DeckCapabilities(rawValue: 1 << 2)

    public static let light: DeckCapabilities = [
        .materials,
    ]

    public static let full: DeckCapabilities = [
        .materials,
        .plausibleFrame,
        .groundCover,
    ]

    public static func forSurface(_ surface: DeckAppSurface) -> DeckCapabilities {
        switch surface {
        case .ops:
            return .light
        case .opsDecks:
            return .full
        }
    }
}
