import Foundation

public enum HouseOpeningMutationResult: Equatable {
    case unavailable
    case missingHouseEdge(edgeId: String)
    case openingNotFound(id: String)
    case ok(WallOpening)
    case clampedToWall(WallOpening)
    case overlapsOpening(otherId: String)
    case headExceedsStory(headInches: Double, storyHeightInches: Double)
    case zeroOrNegativeSize

    public var didMutate: Bool {
        switch self {
        case .ok, .clampedToWall:
            return true
        case .unavailable,
             .missingHouseEdge,
             .openingNotFound,
             .overlapsOpening,
             .headExceedsStory,
             .zeroOrNegativeSize:
            return false
        }
    }
}

public enum HouseEditingIntentEngine {
    public static let defaultStoryHeightFeet: Double = 8

    @discardableResult
    public static func setFloorLine(
        feet: Double?,
        in data: inout DeckDrawingData,
        capabilities: DeckCapabilities
    ) -> Bool {
        guard capabilities.contains(.houseOpenings) else { return false }
        var house = data.house ?? HouseModel()
        house.floorLineFeet = feet
        data.house = house
        return true
    }

    @discardableResult
    public static func setStoryHeights(
        _ feet: [Double],
        in data: inout DeckDrawingData,
        capabilities: DeckCapabilities
    ) -> Bool {
        guard capabilities.contains(.houseOpenings) else { return false }
        var house = data.house ?? HouseModel()
        house.storyHeights = feet.filter { $0 > 0 }
        data.house = house
        return true
    }

    @discardableResult
    public static func addOpening(
        _ kind: OpeningKind,
        onEdge edgeId: String,
        widthInches: Double,
        heightInches: Double,
        sillHeightInches: Double,
        offsetAlongEdgeInches: Double,
        in data: inout DeckDrawingData,
        capabilities: DeckCapabilities
    ) -> HouseOpeningMutationResult {
        let opening = WallOpening(
            edgeId: edgeId,
            kind: kind,
            widthInches: widthInches,
            heightInches: heightInches,
            sillHeightInches: sillHeightInches,
            offsetAlongEdgeInches: offsetAlongEdgeInches
        )
        return mutateOpening(
            opening,
            in: &data,
            capabilities: capabilities,
            mode: .append
        )
    }

    @discardableResult
    public static func updateOpening(
        _ opening: WallOpening,
        in data: inout DeckDrawingData,
        capabilities: DeckCapabilities
    ) -> HouseOpeningMutationResult {
        mutateOpening(
            opening,
            in: &data,
            capabilities: capabilities,
            mode: .replace
        )
    }

    @discardableResult
    public static func removeOpening(
        id: String,
        in data: inout DeckDrawingData,
        capabilities: DeckCapabilities
    ) -> Bool {
        guard capabilities.contains(.houseOpenings),
              var house = data.house,
              let index = house.openings.firstIndex(where: { $0.id == id }) else {
            return false
        }
        house.openings.remove(at: index)
        data.house = house
        return true
    }

    @discardableResult
    public static func resolveLedger(
        forEdge edgeId: String,
        houseSideBeamSpanInches: Double,
        in data: inout DeckDrawingData,
        capabilities: DeckCapabilities,
        package: CodePackage? = nil
    ) -> LedgerStrategyEngine.Strategy? {
        guard capabilities.contains(.houseOpenings),
              let edge = houseEdge(edgeId: edgeId, in: data) else {
            return nil
        }

        let strategy = LedgerStrategyEngine.strategy(
            for: edge,
            houseSideBeamSpanInches: houseSideBeamSpanInches,
            package: package
        )
        var house = data.house ?? HouseModel()
        house.ledger = LedgerStrategyEngine.resolvedDetail(strategy)
        data.house = house
        return strategy
    }

    @discardableResult
    public static func setLedgerDetail(
        _ detail: LedgerDetail,
        in data: inout DeckDrawingData,
        capabilities: DeckCapabilities
    ) -> Bool {
        guard capabilities.contains(.houseOpenings) else { return false }
        var house = data.house ?? HouseModel()
        house.ledger = detail
        data.house = house
        return true
    }

    private enum OpeningMutationMode {
        case append
        case replace
    }

    private static func mutateOpening(
        _ opening: WallOpening,
        in data: inout DeckDrawingData,
        capabilities: DeckCapabilities,
        mode: OpeningMutationMode
    ) -> HouseOpeningMutationResult {
        guard capabilities.contains(.houseOpenings) else { return .unavailable }
        guard let edge = houseEdge(edgeId: opening.edgeId, in: data) else {
            return .missingHouseEdge(edgeId: opening.edgeId)
        }

        var house = data.house ?? HouseModel()
        if mode == .replace,
           !house.openings.contains(where: { $0.id == opening.id }) {
            return .openingNotFound(id: opening.id)
        }

        let wallLength = WallOpeningGeometry.wallLengthInches(edge: edge, in: data)
        let storyHeight = storyHeightInches(in: house)
        let existing = house.openings
        let validation = WallOpeningGeometry.validate(
            opening,
            wallLengthInches: wallLength,
            storyHeightInches: storyHeight,
            existing: existing
        )

        switch validation {
        case .ok:
            persist(opening, in: &house, mode: mode)
            data.house = house
            return .ok(opening)

        case .clampedToWall:
            let adjusted = WallOpeningGeometry.clamped(opening, wallLengthInches: wallLength)
            let adjustedValidation = WallOpeningGeometry.validate(
                adjusted,
                wallLengthInches: wallLength,
                storyHeightInches: storyHeight,
                existing: existing
            )
            guard adjustedValidation == .ok else {
                return result(from: adjustedValidation)
            }
            persist(adjusted, in: &house, mode: mode)
            data.house = house
            return .clampedToWall(adjusted)

        case .overlapsOpening,
             .headExceedsStory,
             .zeroOrNegativeSize:
            return result(from: validation)
        }
    }

    private static func persist(
        _ opening: WallOpening,
        in house: inout HouseModel,
        mode: OpeningMutationMode
    ) {
        switch mode {
        case .append:
            house.openings.append(opening)
        case .replace:
            if let index = house.openings.firstIndex(where: { $0.id == opening.id }) {
                house.openings[index] = opening
            }
        }
    }

    private static func result(
        from validation: WallOpeningGeometry.Validation
    ) -> HouseOpeningMutationResult {
        switch validation {
        case .ok:
            preconditionFailure("Use ok result with validated opening payload.")
        case .clampedToWall:
            preconditionFailure("Use clamped result with adjusted opening payload.")
        case let .overlapsOpening(otherId):
            return .overlapsOpening(otherId: otherId)
        case let .headExceedsStory(headInches, storyHeightInches):
            return .headExceedsStory(
                headInches: headInches,
                storyHeightInches: storyHeightInches
            )
        case .zeroOrNegativeSize:
            return .zeroOrNegativeSize
        }
    }

    private static func storyHeightInches(in house: HouseModel) -> Double {
        let firstStoryFeet = house.storyHeights.first(where: { $0 > 0 })
        return (firstStoryFeet ?? defaultStoryHeightFeet) * 12
    }

    private static func houseEdge(
        edgeId: String,
        in data: DeckDrawingData
    ) -> DeckEdge? {
        data.allEdges.first { edge in
            edge.id == edgeId && edge.edgeType == .houseEdge
        }
    }
}
