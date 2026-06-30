import Foundation

public enum HouseOpeningSchedule {
    public struct ScheduleRow: Equatable, Identifiable {
        public var id: String
        public var calloutTag: String
        public var kindDisplay: String
        public var widthInches: Double
        public var heightInches: Double
        public var sillHeightInches: Double
        public var edgeId: String

        public init(
            id: String,
            calloutTag: String,
            kindDisplay: String,
            widthInches: Double,
            heightInches: Double,
            sillHeightInches: Double,
            edgeId: String
        ) {
            self.id = id
            self.calloutTag = calloutTag
            self.kindDisplay = kindDisplay
            self.widthInches = widthInches
            self.heightInches = heightInches
            self.sillHeightInches = sillHeightInches
            self.edgeId = edgeId
        }
    }

    public static func rows(for data: DeckDrawingData) -> [ScheduleRow] {
        guard let openings = data.house?.openings, !openings.isEmpty else { return [] }

        let doors = openings
            .filter { isDoor($0.kind) }
            .sorted(by: openingSort)
        let windows = openings
            .filter { !isDoor($0.kind) }
            .sorted(by: openingSort)

        return rows(for: doors, prefix: "D") + rows(for: windows, prefix: "W")
    }

    public static func calloutTag(for openingId: String, in data: DeckDrawingData) -> String? {
        rows(for: data).first { $0.id == openingId }?.calloutTag
    }

    private static func rows(for openings: [WallOpening], prefix: String) -> [ScheduleRow] {
        openings.enumerated().map { index, opening in
            ScheduleRow(
                id: opening.id,
                calloutTag: "\(prefix)\(index + 1)",
                kindDisplay: opening.kind.displayName,
                widthInches: opening.widthInches,
                heightInches: opening.heightInches,
                sillHeightInches: opening.sillHeightInches,
                edgeId: opening.edgeId
            )
        }
    }

    private static func openingSort(lhs: WallOpening, rhs: WallOpening) -> Bool {
        if lhs.edgeId != rhs.edgeId {
            return lhs.edgeId < rhs.edgeId
        }
        if lhs.offsetAlongEdgeInches != rhs.offsetAlongEdgeInches {
            return lhs.offsetAlongEdgeInches < rhs.offsetAlongEdgeInches
        }
        return lhs.id < rhs.id
    }

    private static func isDoor(_ kind: OpeningKind) -> Bool {
        switch kind {
        case .patioDoor, .frenchDoor, .sliderDoor:
            return true
        case .window:
            return false
        }
    }
}
