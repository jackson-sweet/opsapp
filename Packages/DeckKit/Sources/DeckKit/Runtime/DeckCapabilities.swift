public struct DeckCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let materials = DeckCapabilities(rawValue: 1 << 0)
    public static let plausibleFrame = DeckCapabilities(rawValue: 1 << 1)
    public static let groundCover = DeckCapabilities(rawValue: 1 << 2)
    public static let codeCompliance = DeckCapabilities(rawValue: 1 << 3)
    public static let houseOpenings = DeckCapabilities(rawValue: 1 << 4)
    public static let surfacePatterns = DeckCapabilities(rawValue: 1 << 5)
    public static let stairDetails = DeckCapabilities(rawValue: 1 << 6)
    public static let surfaceFeatures = DeckCapabilities(rawValue: 1 << 7)
    public static let overheadStructures = DeckCapabilities(rawValue: 1 << 8)

    public static let light: DeckCapabilities = [
        .materials,
    ]

    public static let full: DeckCapabilities = [
        .materials,
        .plausibleFrame,
        .groundCover,
        .codeCompliance,
        .houseOpenings,
        .surfacePatterns,
        .stairDetails,
        .surfaceFeatures,
        .overheadStructures,
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
