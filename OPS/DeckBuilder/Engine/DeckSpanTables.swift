import Foundation

/// Published deck span limits, transcribed verbatim from a single named source.
///
/// Source: Canadian Wood Council, *Prescriptive Residential Exterior Wood Deck
/// Span Guide*, OUTDOOR PROJECT SERIES, Revision 1, © 2016 Canadian Wood
/// Council, Ottawa. Reproduced for British Columbia use by BC Housing,
/// *Illustrated Guide: Building Safe and Durable Wood Decks and Balconies*,
/// p.12. Full provenance, including the retrieved PDFs, lives at
/// `docs/reference/deck-span-tables/SOURCES.md`.
///
/// Scope of what is encoded here: **Hem-Fir (H-F), No.2 or better, incised**
/// (i.e. pressure treated, wet service). The incised tables already carry the
/// treatment and wet-service reductions — `KT = 0.85` bending/shear,
/// `KT = 0.95` MOE, `Ksb = 0.84`, `Ksv = 0.96`, `KSE = 0.94`. **Apply no
/// further reduction**; doing so double-counts.
///
/// Hard rule for anyone editing this file: never invent, recall, approximate or
/// interpolate a span limit. Every row below is a transcription. A value that
/// is not in a cited table does not belong here — return `.notPrescriptive`
/// instead.
///
/// Field naming mirrors `DeckKit.BeamSpanSizingRow` / `DeckKit.PostHeightSizingRow`
/// (`maxSpanFeet`, `codeSection`, `limitingCheck`, `maxSpacingInchesOC`) so a
/// future merge into the standalone Deckset runtime is mechanical. DeckKit's own
/// Canadian package is empty today, so nothing is shared yet.
enum DeckSpanTables {

    // MARK: - Provenance

    /// The species these tables cover. Rows for any other species are not encoded.
    static let species: WoodSpecies = .hemFir

    /// The grade these tables cover. CWC p.4: "Grade: No.2 or better".
    static let grade: LumberGrade = .no2

    static let sourceDocument =
        "CWC Prescriptive Residential Exterior Wood Deck Span Guide, Rev.1 (2016)"

    /// CWC p.4 design assumptions, in the order the guide lists them.
    static let designBasis = """
        Design based on CSA O86-14 and NBC 2015. Live load 1.9 kPa (40 psf), \
        dead load 0.5 kPa (10 psf), grade No.2 or better, live load deflection \
        limit L/360. Wet service factors Ksb 0.84, Ksv 0.96, KSE 0.94. Incised \
        treatment factors KT 0.85 bending and shear, KT 0.95 modulus of elasticity.
        """

    private static let joistTableCitation =
        "\(sourceDocument), Table 3b, H-F, incised"
    private static let singleSpanBeamTableCitation =
        "\(sourceDocument), Table 5b, H-F, incised"
    private static let twoSpanBeamTableCitation =
        "\(sourceDocument), Table 7b, H-F, incised"
    private static let postNoteCitation =
        "\(sourceDocument), Note 5 to Tables 4a/4b/5a/5b/6a/6b/7a/7b"

    // MARK: - Joist spans and cantilever (CWC Table 3b)

    /// One published joist row: a nominal size at one spacing.
    ///
    /// `limitingCheck` is nil because CWC does not publish which check governs
    /// an individual row — the guide states the design basis once, for all
    /// tables. Filling it in would be an invention, so it stays absent.
    struct JoistSpanRow: Equatable {
        let nominalSize: LumberSize
        let species: WoodSpecies
        let grade: LumberGrade
        let maxSpacingInchesOC: Double
        /// Feet component of the table's ft-in entry, transcribed exactly.
        let spanFeetComponent: Int
        /// Inches component of the table's ft-in entry, transcribed exactly.
        let spanInchesComponent: Int
        /// Table 3b "Max allowable cantilever" column for this nominal size.
        let maxCantileverInches: Double
        /// Table 3b note 1: "Joist stock greater than 16 ft not typically available."
        let stockAvailabilityFlagged: Bool
        let codeSection: String
        let limitingCheck: String?
        let citation: String

        var maxSpanInches: Double {
            Double(spanFeetComponent * 12 + spanInchesComponent)
        }

        var maxSpanFeet: Double { maxSpanInches / 12 }
    }

    /// Table 3b notes, verbatim.
    enum JoistTableNotes {
        static let stockAvailability =
            "Joist stock greater than 16 ft not typically available."
        static let guardMinimumSize =
            "Where guards are required, joists and rim boards shall be a minimum of nominal 2 x 8 in."
        static let cantileverFigure =
            "See Figure 1 for details in regards to cantilevers."
    }

    /// Note 2 to Table 3b: a deck requiring a guard may not use joists or rim
    /// boards smaller than nominal 2x8.
    static let minimumSizeWhereGuardRequired: LumberSize = .twoByEight

    /// BCBC 9.23.1.1 via BC Housing p.13: 600 mm (24 in) maximum joist spacing
    /// for Part 9 buildings. This is a code ceiling, not a CWC table limit.
    static let maximumJoistSpacingInchesOC: Double = 24

    /// Every encoded row of CWC Table 3b, H-F column, incised.
    ///
    /// The published table also carries a 2x4 row. It is deliberately absent:
    /// `LumberSize` has no 2x4 case, and Table 3b note 2 forces 2x8 or larger
    /// wherever a guard is required.
    static let joistSpanRows: [JoistSpanRow] = [
        row(.twoBySix, 8, 11, 10, cantilever: 16),
        row(.twoBySix, 12, 10, 4, cantilever: 16),
        row(.twoBySix, 16, 9, 1, cantilever: 16),
        row(.twoBySix, 24, 7, 5, cantilever: 16),

        row(.twoByEight, 8, 15, 7, cantilever: 16),
        row(.twoByEight, 12, 12, 9, cantilever: 16),
        row(.twoByEight, 16, 11, 1, cantilever: 16),
        row(.twoByEight, 24, 9, 0, cantilever: 16),

        row(.twoByTen, 8, 19, 1, cantilever: 24, stockFlagged: true),
        row(.twoByTen, 12, 15, 7, cantilever: 24),
        row(.twoByTen, 16, 13, 6, cantilever: 24),
        row(.twoByTen, 24, 11, 0, cantilever: 24),

        row(.twoByTwelve, 8, 22, 2, cantilever: 24, stockFlagged: true),
        row(.twoByTwelve, 12, 18, 1, cantilever: 24),
        row(.twoByTwelve, 16, 15, 8, cantilever: 24),
        row(.twoByTwelve, 24, 12, 10, cantilever: 24),
    ]

    private static func row(
        _ size: LumberSize,
        _ spacing: Double,
        _ feet: Int,
        _ inches: Int,
        cantilever: Double,
        stockFlagged: Bool = false
    ) -> JoistSpanRow {
        JoistSpanRow(
            nominalSize: size,
            species: species,
            grade: grade,
            maxSpacingInchesOC: spacing,
            spanFeetComponent: feet,
            spanInchesComponent: inches,
            maxCantileverInches: cantilever,
            stockAvailabilityFlagged: stockFlagged,
            codeSection: "CWC Table 3b",
            limitingCheck: nil,
            citation: joistTableCitation
        )
    }

    /// The published row for this nominal size at this spacing, or nil when the
    /// combination is not in the table. Never falls back to a neighbouring row.
    static func joistRow(nominalSize: LumberSize, spacingInchesOC: Double) -> JoistSpanRow? {
        joistSpanRows.first {
            $0.nominalSize == nominalSize
                && abs($0.maxSpacingInchesOC - spacingInchesOC) < 0.000_001
        }
    }

    /// Table 3b "Max allowable cantilever" for a nominal joist size, in inches.
    /// Independent of spacing, exactly as the table publishes it.
    static func maxCantileverInches(nominalSize: LumberSize) -> Double? {
        joistSpanRows.first { $0.nominalSize == nominalSize }?.maxCantileverInches
    }

    // MARK: - Beam selection (CWC Tables 5b and 7b)

    /// Figure 1 note 3: "Tables are not valid if joists span continuously over
    /// more than two supports. Engineering analysis is required in this
    /// situation." There is no third case.
    enum BeamContinuity {
        /// Beam supports a single joist span — CWC Table 5b.
        case singleSpan
        /// Beam supports two joist spans — CWC Table 7b.
        case twoSpans
    }

    /// A published beam entry, e.g. "2-2x10" is `plyCount: 2, nominalSize: .twoByTen`.
    struct BeamSelection: Equatable {
        let plyCount: Int
        let nominalSize: LumberSize
        /// The whole-foot table row actually used after rounding up.
        let tableRowJoistSpanFeet: Int
        let postSpacingFeet: Double
        let codeSection: String
        let limitingCheck: String?
        let citation: String

        /// The table's own notation, e.g. "2-2x10".
        var tableEntry: String { "\(plyCount)-\(nominalSize.rawValue)" }
    }

    /// Why no published selection exists. `N/A` is a real table entry, not a
    /// missing value — it must never degrade into "use the biggest beam".
    enum NotPrescriptiveReason: Equatable {
        /// The entering joist span is past the last table row (16 ft).
        case joistSpanExceedsTable(enteringSpanFeet: Double, lastRowFeet: Int)
        /// The row exists but the cell is published as N/A.
        case tableEntryNotAvailable(joistSpanFeet: Int, postSpacingFeet: Double)
        /// Post spacing is not one of the table's columns.
        case postSpacingNotTabulated(postSpacingFeet: Double)
        /// Post height is past CWC Note 5's 12 ft ceiling.
        case postHeightExceedsTable(heightFeet: Double, maxHeightFeet: Double)
    }

    enum BeamSelectionResult: Equatable {
        case selection(BeamSelection)
        case notPrescriptive(NotPrescriptiveReason)
    }

    /// The post spacings CWC tabulates, in feet. There are no other columns.
    static let postSpacingOptionsFeet: [Double] = [4, 6, 8]

    /// First and last whole-foot joist span rows in Tables 5b and 7b.
    static let firstBeamTableRowFeet = 4
    static let lastBeamTableRowFeet = 16

    /// Figure 1 note 4, verbatim.
    static let cantileverIsIncludedInBeamLookupNote = """
        When determining the beam selection that will include a cantilever, the \
        length of the cantilever shall be included in the total joist span used \
        in the beam selection Tables.
        """

    /// Figure 1 note 3, verbatim.
    static let continuityLimitNote = """
        Tables are not valid if joists span continuously over more than two \
        supports. Engineering analysis is required in this situation.
        """

    /// Note 6 to Table 7b, verbatim.
    static let unequalSpanNote =
        "If joist spans are not of equal length, use the larger of the two joist spans to determine beam size."

    /// CWC Table 5b — BEAM SELECTION INCISED SUPPORTING SINGLE SPAN (ft), H-F.
    /// Keyed by whole-foot joist span; values are the 4 ft / 6 ft / 8 ft columns.
    private static let singleSpanTable: [Int: [BeamCell]] = [
        4: [.ply(1, .twoBySix), .ply(1, .twoBySix), .ply(2, .twoBySix)],
        5: [.ply(1, .twoBySix), .ply(1, .twoBySix), .ply(2, .twoBySix)],
        6: [.ply(1, .twoBySix), .ply(2, .twoBySix), .ply(2, .twoBySix)],
        7: [.ply(1, .twoBySix), .ply(2, .twoBySix), .ply(2, .twoByEight)],
        8: [.ply(1, .twoBySix), .ply(2, .twoBySix), .ply(2, .twoByEight)],
        9: [.ply(1, .twoBySix), .ply(2, .twoBySix), .ply(2, .twoByEight)],
        10: [.ply(1, .twoBySix), .ply(2, .twoBySix), .ply(2, .twoByTen)],
        11: [.ply(1, .twoBySix), .ply(2, .twoBySix), .ply(2, .twoByTen)],
        12: [.ply(1, .twoBySix), .ply(2, .twoByEight), .ply(2, .twoByTen)],
        13: [.ply(2, .twoBySix), .ply(2, .twoByEight), .ply(2, .twoByTen)],
        14: [.ply(2, .twoBySix), .ply(2, .twoByEight), .ply(2, .twoByTwelve)],
        15: [.ply(2, .twoBySix), .ply(2, .twoByEight), .ply(2, .twoByTwelve)],
        16: [.ply(2, .twoBySix), .ply(2, .twoByEight), .ply(2, .twoByTwelve)],
    ]

    /// CWC Table 7b — BEAM SELECTION INCISED SUPPORTING TWO SPANS (ft), H-F.
    /// The (16 ft, 8 ft) cell is published as N/A.
    private static let twoSpanTable: [Int: [BeamCell]] = [
        4: [.ply(1, .twoBySix), .ply(2, .twoBySix), .ply(2, .twoByEight)],
        5: [.ply(1, .twoBySix), .ply(2, .twoBySix), .ply(2, .twoByTen)],
        6: [.ply(1, .twoBySix), .ply(2, .twoByEight), .ply(2, .twoByTen)],
        7: [.ply(2, .twoBySix), .ply(2, .twoByEight), .ply(2, .twoByTwelve)],
        8: [.ply(2, .twoBySix), .ply(2, .twoByEight), .ply(2, .twoByTwelve)],
        9: [.ply(2, .twoBySix), .ply(2, .twoByTen), .ply(2, .twoByTwelve)],
        10: [.ply(2, .twoBySix), .ply(2, .twoByTen), .ply(3, .twoByTen)],
        11: [.ply(2, .twoBySix), .ply(2, .twoByTen), .ply(3, .twoByTen)],
        12: [.ply(2, .twoBySix), .ply(2, .twoByTen), .ply(3, .twoByTwelve)],
        13: [.ply(2, .twoByEight), .ply(2, .twoByTwelve), .ply(3, .twoByTwelve)],
        14: [.ply(2, .twoByEight), .ply(2, .twoByTwelve), .ply(3, .twoByTwelve)],
        15: [.ply(2, .twoByEight), .ply(2, .twoByTwelve), .ply(3, .twoByTwelve)],
        16: [.ply(2, .twoByEight), .ply(2, .twoByTwelve), .notAvailable],
    ]

    private enum BeamCell {
        case ply(Int, LumberSize)
        /// The table prints N/A: no prescriptive selection exists.
        case notAvailable
    }

    /// Look up a beam.
    ///
    /// `joistSpanIncludingCantileverFeet` must already include the cantilever —
    /// Figure 1 note 4. Passing the bare joist span under-sizes the beam.
    ///
    /// Interpolation rule: the entering span is rounded **up** to the next whole
    /// foot row. Never interpolated, never rounded down. Spans below the first
    /// row use the first row. Spans past the last row return `.notPrescriptive`.
    static func beamSelection(
        joistSpanIncludingCantileverFeet: Double,
        postSpacingFeet: Double,
        continuity: BeamContinuity
    ) -> BeamSelectionResult {
        guard let columnIndex = postSpacingOptionsFeet.firstIndex(where: {
            abs($0 - postSpacingFeet) < 0.000_001
        }) else {
            return .notPrescriptive(.postSpacingNotTabulated(postSpacingFeet: postSpacingFeet))
        }

        let rounded = roundedUpTableRowFeet(joistSpanIncludingCantileverFeet)
        guard rounded <= lastBeamTableRowFeet else {
            return .notPrescriptive(.joistSpanExceedsTable(
                enteringSpanFeet: joistSpanIncludingCantileverFeet,
                lastRowFeet: lastBeamTableRowFeet
            ))
        }
        let rowFeet = max(rounded, firstBeamTableRowFeet)

        let table = continuity == .singleSpan ? singleSpanTable : twoSpanTable
        guard let cells = table[rowFeet], columnIndex < cells.count else {
            return .notPrescriptive(.joistSpanExceedsTable(
                enteringSpanFeet: joistSpanIncludingCantileverFeet,
                lastRowFeet: lastBeamTableRowFeet
            ))
        }

        switch cells[columnIndex] {
        case .notAvailable:
            return .notPrescriptive(.tableEntryNotAvailable(
                joistSpanFeet: rowFeet,
                postSpacingFeet: postSpacingFeet
            ))
        case let .ply(plyCount, size):
            return .selection(BeamSelection(
                plyCount: plyCount,
                nominalSize: size,
                tableRowJoistSpanFeet: rowFeet,
                postSpacingFeet: postSpacingFeet,
                codeSection: continuity == .singleSpan ? "CWC Table 5b" : "CWC Table 7b",
                limitingCheck: nil,
                citation: continuity == .singleSpan
                    ? singleSpanBeamTableCitation
                    : twoSpanBeamTableCitation
            ))
        }
    }

    /// Rounds an entering span up to the next whole-foot table row. The epsilon
    /// keeps an exact 12.0 on the 12 ft row rather than pushing it to 13.
    static func roundedUpTableRowFeet(_ spanFeet: Double) -> Int {
        Int(ceil(spanFeet - 0.000_001))
    }

    // MARK: - Posts (CWC Note 5, BCBC 9.17.4.1)

    /// CWC Note 5, verbatim.
    static let postSizeNote = """
        Minimum post size shall be nominal 4 x 4 in. for posts up to 6.5 ft high, \
        otherwise post size shall be nominal 6 x 6 in. up to 12 ft high. Posts \
        supporting 3-ply beams require nominal 6 x 6 in. post to meet minimum \
        bearing requirement.
        """

    /// BCBC 9.17.4.1 requires 140 x 140 mm (5.5 x 5.5 in) posts absent a
    /// structural calculation — BC Housing p.11. CWC's 4x4-under-6.5-ft
    /// allowance rests on calculation, which this preview does not perform, so
    /// the encoded default is 6x6 at every height.
    static let defaultPostSize: LumberSize = .sixBySix

    /// CWC Note 5 ceiling. Above this there is no prescriptive selection.
    static let maxPostHeightFeet: Double = 12

    struct PostSelection: Equatable {
        let nominalSize: LumberSize
        let maxHeightFeet: Double
        let codeSection: String
        let limitingCheck: String?
        let citation: String
    }

    enum PostSelectionResult: Equatable {
        case selection(PostSelection)
        case notPrescriptive(NotPrescriptiveReason)
    }

    /// Post size for a beam of this ply count at this height.
    ///
    /// Always 6x6 within the published height: BCBC 9.17.4.1 requires it absent
    /// calculation, and CWC Note 5 requires it under a 3-ply beam regardless.
    static func postSelection(beamPlyCount: Int, heightFeet: Double) -> PostSelectionResult {
        guard heightFeet <= maxPostHeightFeet + 0.000_001 else {
            return .notPrescriptive(.postHeightExceedsTable(
                heightFeet: heightFeet,
                maxHeightFeet: maxPostHeightFeet
            ))
        }
        return .selection(PostSelection(
            nominalSize: defaultPostSize,
            maxHeightFeet: maxPostHeightFeet,
            codeSection: beamPlyCount >= 3 ? "CWC Note 5 / BCBC 9.17.4.1" : "BCBC 9.17.4.1",
            limitingCheck: beamPlyCount >= 3 ? "bearing" : nil,
            citation: postNoteCitation
        ))
    }

    // MARK: - Nominal depth ordering

    /// Nominal depth in inches, used only to order sizes (2x6 < 2x8 < 2x10 <
    /// 2x12) when applying the guard minimum. Not a span value.
    static func nominalDepthInches(_ size: LumberSize) -> Int? {
        switch size {
        case .twoBySix: return 6
        case .twoByEight: return 8
        case .twoByTen: return 10
        case .twoByTwelve: return 12
        case .fourByFour, .fourBySix, .sixBySix: return nil
        }
    }
}
