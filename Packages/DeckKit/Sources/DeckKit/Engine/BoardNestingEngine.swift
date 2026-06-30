import Foundation

public enum BoardNestingEngine {
    public static func makePlan(
        cuts: [BoardCutRequirement],
        stock: BoardStock,
        availableOffcuts: [BoardOffcut] = []
    ) -> BoardNestingPlan {
        let stockLengths = stock.stockLengthsInches
            .filter { $0 > 0 }
            .sorted()
        let kerfInches = max(0, stock.kerfInches)
        let offcutMinLengthInches = max(0, stock.offcutMinLengthInches)
        let orderedCuts = cuts
            .filter { $0.lengthInches > 0 }
            .sorted {
                if abs($0.lengthInches - $1.lengthInches) > 0.001 {
                    return $0.lengthInches > $1.lengthInches
                }
                return $0.id < $1.id
            }

        var pieces: [BoardStockPiece] = []
        var unusedOffcuts = availableOffcuts
            .filter { $0.lengthInches > 0 }
            .sorted {
                if abs($0.lengthInches - $1.lengthInches) > 0.001 {
                    return $0.lengthInches > $1.lengthInches
                }
                return $0.id < $1.id
            }
        var reuseNotes: [String] = []
        var unplacedCuts: [BoardCutRequirement] = []

        for cut in orderedCuts {
            if place(cut, into: &pieces, matching: .onHandOffcut, kerfInches: kerfInches) {
                continue
            }

            if let offcutIndex = unusedOffcuts.firstIndex(where: {
                $0.family == cut.family && $0.lengthInches + 0.001 >= cut.lengthInches
            }) {
                let offcut = unusedOffcuts.remove(at: offcutIndex)
                pieces.append(
                    stockPiece(
                        from: offcut,
                        cut: cut
                    )
                )
                reuseNotes.append(
                    "REUSED \(formatInches(cut.lengthInches)) \(cut.family.rawValue.uppercased()) FROM OFFCUT \(offcut.id) FOR \(cut.id)"
                )
                continue
            }

            if place(cut, into: &pieces, matching: .purchasedStock, kerfInches: kerfInches) {
                continue
            }

            guard let stockLength = stockLengths.first(where: { $0 + 0.001 >= cut.lengthInches }) else {
                unplacedCuts.append(cut)
                continue
            }

            pieces.append(
                stockPiece(
                    family: cut.family,
                    source: .purchasedStock,
                    sourceOffcutId: nil,
                    stockLengthInches: stockLength,
                    index: pieces.filter { $0.source == .purchasedStock }.count,
                    cut: cut
                )
            )
        }

        let producedOffcuts = producedOffcuts(
            from: pieces,
            offcutMinLengthInches: offcutMinLengthInches
        )
        let totalStockCount = pieces.filter { $0.source == .purchasedStock }.count
        let totalWasteLinearFeet = totalWasteLinearFeet(
            pieces: pieces,
            producedOffcuts: producedOffcuts
        )

        return BoardNestingPlan(
            stockPieces: pieces,
            producedOffcuts: producedOffcuts,
            reuseNotes: reuseNotes,
            unplacedCuts: unplacedCuts,
            totalStockCount: totalStockCount,
            totalWasteLinearFeet: totalWasteLinearFeet
        )
    }

    private static func place(
        _ cut: BoardCutRequirement,
        into pieces: inout [BoardStockPiece],
        matching source: BoardStockPieceSource,
        kerfInches: Double
    ) -> Bool {
        let candidates = pieces.indices
            .filter {
                pieces[$0].source == source
                    && pieces[$0].family == cut.family
                    && remainingAfterPlacing(cut, in: pieces[$0], kerfInches: kerfInches) >= -0.001
            }
            .sorted {
                let lhs = remainingAfterPlacing(cut, in: pieces[$0], kerfInches: kerfInches)
                let rhs = remainingAfterPlacing(cut, in: pieces[$1], kerfInches: kerfInches)
                if abs(lhs - rhs) > 0.001 { return lhs < rhs }
                return pieces[$0].id < pieces[$1].id
            }

        guard let index = candidates.first else { return false }
        add(cut, to: &pieces[index], kerfInches: kerfInches)
        return true
    }

    private static func stockPiece(
        from offcut: BoardOffcut,
        cut: BoardCutRequirement
    ) -> BoardStockPiece {
        stockPiece(
            family: cut.family,
            source: .onHandOffcut,
            sourceOffcutId: offcut.id,
            stockLengthInches: offcut.lengthInches,
            index: nil,
            cut: cut
        )
    }

    private static func stockPiece(
        family: BoardFamily,
        source: BoardStockPieceSource,
        sourceOffcutId: String?,
        stockLengthInches: Double,
        index: Int?,
        cut: BoardCutRequirement
    ) -> BoardStockPiece {
        let id: String
        switch source {
        case .purchasedStock:
            id = "stock-\(family.rawValue)-\(index ?? 0)"
        case .onHandOffcut:
            id = "offcut-\(sourceOffcutId ?? cut.id)"
        }

        return BoardStockPiece(
            id: id,
            family: family,
            source: source,
            sourceOffcutId: sourceOffcutId,
            stockLengthInches: stockLengthInches,
            cuts: [cut],
            placements: [
                BoardCutPlacement(
                    id: "placement-\(cut.id)",
                    cutId: cut.id,
                    startInches: 0,
                    endInches: cut.lengthInches,
                    isFlipped: false
                ),
            ],
            remainderInches: max(0, stockLengthInches - cut.lengthInches)
        )
    }

    private static func add(
        _ cut: BoardCutRequirement,
        to piece: inout BoardStockPiece,
        kerfInches: Double
    ) {
        let kerfBeforeCut = piece.cuts.isEmpty ? 0 : kerfInches
        let start = piece.stockLengthInches - piece.remainderInches + kerfBeforeCut
        let end = start + cut.lengthInches
        piece.cuts.append(cut)
        piece.placements.append(
            BoardCutPlacement(
                id: "placement-\(cut.id)",
                cutId: cut.id,
                startInches: start,
                endInches: end,
                isFlipped: false
            )
        )
        piece.remainderInches = max(0, piece.remainderInches - cut.lengthInches - kerfBeforeCut)
    }

    private static func remainingAfterPlacing(
        _ cut: BoardCutRequirement,
        in piece: BoardStockPiece,
        kerfInches: Double
    ) -> Double {
        piece.remainderInches - cut.lengthInches - (piece.cuts.isEmpty ? 0 : kerfInches)
    }

    private static func producedOffcuts(
        from pieces: [BoardStockPiece],
        offcutMinLengthInches: Double
    ) -> [BoardOffcut] {
        pieces.compactMap { piece in
            guard piece.remainderInches >= offcutMinLengthInches else { return nil }
            let sourceId = piece.sourceOffcutId ?? piece.id
            let id: String
            switch piece.source {
            case .purchasedStock:
                id = "offcut-\(piece.id)"
            case .onHandOffcut:
                id = "offcut-\(sourceId)-remnant"
            }
            return BoardOffcut(
                id: id,
                lengthInches: piece.remainderInches,
                family: piece.family
            )
        }
    }

    private static func totalWasteLinearFeet(
        pieces: [BoardStockPiece],
        producedOffcuts: [BoardOffcut]
    ) -> Double {
        let stockInches = pieces.reduce(0) { $0 + $1.stockLengthInches }
        let cutInches = pieces.reduce(0) { partial, piece in
            partial + piece.cuts.reduce(0) { $0 + $1.lengthInches }
        }
        let bankedOffcutInches = producedOffcuts.reduce(0) { $0 + $1.lengthInches }
        return max(0, stockInches - cutInches - bankedOffcutInches) / 12
    }

    private static func formatInches(_ inches: Double) -> String {
        "\(Int(inches.rounded()))IN"
    }
}

public struct BoardCutRequirement: Identifiable, Codable, Equatable {
    public let id: String
    public var family: BoardFamily
    public var lengthInches: Double
    public var grainLocked: Bool

    public init(
        id: String,
        family: BoardFamily,
        lengthInches: Double,
        grainLocked: Bool
    ) {
        self.id = id
        self.family = family
        self.lengthInches = lengthInches
        self.grainLocked = grainLocked
    }

    public init(
        boardCut: DeckBoardCut,
        family: BoardFamily = .decking,
        grainLocked: Bool = false
    ) {
        self.init(
            id: boardCut.id,
            family: family,
            lengthInches: boardCut.lengthInches,
            grainLocked: grainLocked
        )
    }
}

public enum BoardFamily: String, Codable, CaseIterable {
    case decking
    case fascia
    case skirting
}

public struct BoardStock: Codable, Equatable {
    public var stockLengthsInches: [Double]
    public var kerfInches: Double
    public var offcutMinLengthInches: Double

    public init(
        stockLengthsInches: [Double],
        kerfInches: Double,
        offcutMinLengthInches: Double
    ) {
        self.stockLengthsInches = stockLengthsInches
        self.kerfInches = kerfInches
        self.offcutMinLengthInches = offcutMinLengthInches
    }
}

public struct BoardOffcut: Identifiable, Codable, Equatable {
    public let id: String
    public var lengthInches: Double
    public var family: BoardFamily

    public init(
        id: String,
        lengthInches: Double,
        family: BoardFamily
    ) {
        self.id = id
        self.lengthInches = lengthInches
        self.family = family
    }
}

public struct BoardNestingPlan: Codable, Equatable {
    public var stockPieces: [BoardStockPiece]
    public var producedOffcuts: [BoardOffcut]
    public var reuseNotes: [String]
    public var unplacedCuts: [BoardCutRequirement]
    public var totalStockCount: Int
    public var totalWasteLinearFeet: Double

    public init(
        stockPieces: [BoardStockPiece],
        producedOffcuts: [BoardOffcut],
        reuseNotes: [String],
        unplacedCuts: [BoardCutRequirement] = [],
        totalStockCount: Int,
        totalWasteLinearFeet: Double
    ) {
        self.stockPieces = stockPieces
        self.producedOffcuts = producedOffcuts
        self.reuseNotes = reuseNotes
        self.unplacedCuts = unplacedCuts
        self.totalStockCount = totalStockCount
        self.totalWasteLinearFeet = totalWasteLinearFeet
    }
}

public enum BoardStockPieceSource: String, Codable, Equatable {
    case purchasedStock = "purchased_stock"
    case onHandOffcut = "on_hand_offcut"
}

public struct BoardStockPiece: Identifiable, Codable, Equatable {
    public let id: String
    public var family: BoardFamily
    public var source: BoardStockPieceSource
    public var sourceOffcutId: String?
    public var stockLengthInches: Double
    public var cuts: [BoardCutRequirement]
    public var placements: [BoardCutPlacement]
    public var remainderInches: Double

    public init(
        id: String,
        family: BoardFamily,
        source: BoardStockPieceSource,
        sourceOffcutId: String? = nil,
        stockLengthInches: Double,
        cuts: [BoardCutRequirement],
        placements: [BoardCutPlacement],
        remainderInches: Double
    ) {
        self.id = id
        self.family = family
        self.source = source
        self.sourceOffcutId = sourceOffcutId
        self.stockLengthInches = stockLengthInches
        self.cuts = cuts
        self.placements = placements
        self.remainderInches = remainderInches
    }
}

public struct BoardCutPlacement: Identifiable, Codable, Equatable {
    public let id: String
    public var cutId: String
    public var startInches: Double
    public var endInches: Double
    public var isFlipped: Bool

    public init(
        id: String,
        cutId: String,
        startInches: Double,
        endInches: Double,
        isFlipped: Bool
    ) {
        self.id = id
        self.cutId = cutId
        self.startInches = startInches
        self.endInches = endInches
        self.isFlipped = isFlipped
    }
}
