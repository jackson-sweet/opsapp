import Foundation
import XCTest
@testable import OPS

/// Spot-checks every published row this app encodes against the transcription
/// in `docs/reference/deck-span-tables/SOURCES.md`.
///
/// Source of truth: CWC *Prescriptive Residential Exterior Wood Deck Span
/// Guide*, Rev.1 (2016), Hem-Fir, incised — Tables 3b, 5b, 7b and Note 5.
/// These tests exist to catch a silent edit to a published number. If one
/// fails, the fix is to restore the table value, never to relax the test.
final class DeckSpanTablesTests: XCTestCase {

    // MARK: - Table 3b, joist spans

    func testTable3bJoistSpansMatchThePublishedRowsExactly() throws {
        // (nominal size, spacing in o.c., feet, inches) straight off Table 3b, H-F incised.
        let published: [(LumberSize, Double, Int, Int)] = [
            (.twoBySix, 8, 11, 10),
            (.twoBySix, 12, 10, 4),
            (.twoBySix, 16, 9, 1),
            (.twoBySix, 24, 7, 5),

            (.twoByEight, 8, 15, 7),
            (.twoByEight, 12, 12, 9),
            (.twoByEight, 16, 11, 1),
            (.twoByEight, 24, 9, 0),

            (.twoByTen, 8, 19, 1),
            (.twoByTen, 12, 15, 7),
            (.twoByTen, 16, 13, 6),
            (.twoByTen, 24, 11, 0),

            (.twoByTwelve, 8, 22, 2),
            (.twoByTwelve, 12, 18, 1),
            (.twoByTwelve, 16, 15, 8),
            (.twoByTwelve, 24, 12, 10),
        ]

        XCTAssertEqual(DeckSpanTables.joistSpanRows.count, published.count,
                       "Table 3b encodes 4 nominal sizes at 4 spacings. Nothing may be added or dropped.")

        for (size, spacing, feet, inches) in published {
            let row = try XCTUnwrap(
                DeckSpanTables.joistRow(nominalSize: size, spacingInchesOC: spacing),
                "Missing Table 3b row for \(size.rawValue) at \(spacing) in o.c."
            )
            XCTAssertEqual(row.spanFeetComponent, feet, "\(size.rawValue) @ \(spacing) o.c. feet component")
            XCTAssertEqual(row.spanInchesComponent, inches, "\(size.rawValue) @ \(spacing) o.c. inches component")
            XCTAssertEqual(row.maxSpanInches, Double(feet * 12 + inches), accuracy: 0.000_001)
            XCTAssertEqual(row.maxSpanFeet, Double(feet * 12 + inches) / 12, accuracy: 0.000_001)
            XCTAssertEqual(row.species, DeckSpanTables.species)
            XCTAssertEqual(row.grade, DeckSpanTables.grade)
            XCTAssertFalse(row.citation.isEmpty, "Every row carries its citation.")
            XCTAssertTrue(row.citation.contains("Table 3b"))
        }
    }

    func testTable3bCantileversAreSizeDrivenAndNeverTwelveInches() throws {
        let published: [(LumberSize, Double)] = [
            (.twoBySix, 16),
            (.twoByEight, 16),
            (.twoByTen, 24),
            (.twoByTwelve, 24),
        ]

        for (size, cantilever) in published {
            let value = try XCTUnwrap(DeckSpanTables.maxCantileverInches(nominalSize: size))
            XCTAssertEqual(value, cantilever, accuracy: 0.000_001,
                           "Table 3b max allowable cantilever for \(size.rawValue)")
        }

        // The heuristic this replaces hardcoded 12 in for every deck. No published
        // row is 12, so a 12 anywhere in the cantilever column is a regression.
        XCTAssertFalse(DeckSpanTables.joistSpanRows.contains { $0.maxCantileverInches == 12 })
    }

    func testTable3bCantileverIsIndependentOfSpacing() throws {
        for size in [LumberSize.twoBySix, .twoByEight, .twoByTen, .twoByTwelve] {
            let cantilevers = Set(
                DeckSpanTables.joistSpanRows
                    .filter { $0.nominalSize == size }
                    .map(\.maxCantileverInches)
            )
            XCTAssertEqual(cantilevers.count, 1,
                           "Table 3b publishes one cantilever per nominal size, not one per spacing.")
        }
    }

    func testTable3bStockAvailabilityFlagMarksOnlyTheTwoFootnotedRows() {
        let flagged = DeckSpanTables.joistSpanRows
            .filter(\.stockAvailabilityFlagged)
            .map { "\($0.nominalSize.rawValue)@\(Int($0.maxSpacingInchesOC))" }
            .sorted()
        // Note 1 marks 2x10 and 2x12 at 8 in o.c. — the only spans over 16 ft.
        XCTAssertEqual(flagged, ["2x10@8", "2x12@8"])
        for row in DeckSpanTables.joistSpanRows where row.stockAvailabilityFlagged {
            XCTAssertGreaterThan(row.maxSpanFeet, 16)
        }
    }

    func testTwoByFourRowIsNotEncoded() {
        XCTAssertFalse(DeckSpanTables.joistSpanRows.contains { $0.nominalSize == .fourByFour })
        XCTAssertNil(DeckSpanTables.nominalDepthInches(.fourByFour))
        XCTAssertEqual(DeckSpanTables.minimumSizeWhereGuardRequired, .twoByEight)
        XCTAssertEqual(DeckSpanTables.maximumJoistSpacingInchesOC, 24)
    }

    func testUnknownJoistCombinationsReturnNilRatherThanANeighbouringRow() {
        // 20 in o.c. is not a Table 3b column. It must not silently resolve to 16 or 24.
        XCTAssertNil(DeckSpanTables.joistRow(nominalSize: .twoByTen, spacingInchesOC: 20))
        // 6x6 is a post size, not a joist row.
        XCTAssertNil(DeckSpanTables.joistRow(nominalSize: .sixBySix, spacingInchesOC: 16))
    }

    // MARK: - Table 5b, beam supporting a single span

    func testTable5bMatchesThePublishedGridExactly() {
        // Rows 4...16 ft; columns 4 ft / 6 ft / 8 ft post spacing.
        let published: [Int: [(Int, LumberSize)]] = [
            4: [(1, .twoBySix), (1, .twoBySix), (2, .twoBySix)],
            5: [(1, .twoBySix), (1, .twoBySix), (2, .twoBySix)],
            6: [(1, .twoBySix), (2, .twoBySix), (2, .twoBySix)],
            7: [(1, .twoBySix), (2, .twoBySix), (2, .twoByEight)],
            8: [(1, .twoBySix), (2, .twoBySix), (2, .twoByEight)],
            9: [(1, .twoBySix), (2, .twoBySix), (2, .twoByEight)],
            10: [(1, .twoBySix), (2, .twoBySix), (2, .twoByTen)],
            11: [(1, .twoBySix), (2, .twoBySix), (2, .twoByTen)],
            12: [(1, .twoBySix), (2, .twoByEight), (2, .twoByTen)],
            13: [(2, .twoBySix), (2, .twoByEight), (2, .twoByTen)],
            14: [(2, .twoBySix), (2, .twoByEight), (2, .twoByTwelve)],
            15: [(2, .twoBySix), (2, .twoByEight), (2, .twoByTwelve)],
            16: [(2, .twoBySix), (2, .twoByEight), (2, .twoByTwelve)],
        ]

        assertGrid(published, continuity: .singleSpan, tableName: "Table 5b")
    }

    // MARK: - Table 7b, beam supporting two spans

    func testTable7bMatchesThePublishedGridExactly() {
        let published: [Int: [(Int, LumberSize)?]] = [
            4: [(1, .twoBySix), (2, .twoBySix), (2, .twoByEight)],
            5: [(1, .twoBySix), (2, .twoBySix), (2, .twoByTen)],
            6: [(1, .twoBySix), (2, .twoByEight), (2, .twoByTen)],
            7: [(2, .twoBySix), (2, .twoByEight), (2, .twoByTwelve)],
            8: [(2, .twoBySix), (2, .twoByEight), (2, .twoByTwelve)],
            9: [(2, .twoBySix), (2, .twoByTen), (2, .twoByTwelve)],
            10: [(2, .twoBySix), (2, .twoByTen), (3, .twoByTen)],
            11: [(2, .twoBySix), (2, .twoByTen), (3, .twoByTen)],
            12: [(2, .twoBySix), (2, .twoByTen), (3, .twoByTwelve)],
            13: [(2, .twoByEight), (2, .twoByTwelve), (3, .twoByTwelve)],
            14: [(2, .twoByEight), (2, .twoByTwelve), (3, .twoByTwelve)],
            15: [(2, .twoByEight), (2, .twoByTwelve), (3, .twoByTwelve)],
            16: [(2, .twoByEight), (2, .twoByTwelve), nil], // published N/A
        ]

        for (spanFeet, cells) in published.sorted(by: { $0.key < $1.key }) {
            for (index, spacing) in DeckSpanTables.postSpacingOptionsFeet.enumerated() {
                let result = DeckSpanTables.beamSelection(
                    joistSpanIncludingCantileverFeet: Double(spanFeet),
                    postSpacingFeet: spacing,
                    continuity: .twoSpans
                )
                guard let expected = cells[index] else {
                    XCTAssertEqual(
                        result,
                        .notPrescriptive(.tableEntryNotAvailable(
                            joistSpanFeet: spanFeet,
                            postSpacingFeet: spacing
                        )),
                        "Table 7b (\(spanFeet) ft, \(Int(spacing)) ft) is published N/A and must stay N/A."
                    )
                    continue
                }
                guard case let .selection(selection) = result else {
                    return XCTFail("Table 7b (\(spanFeet) ft, \(Int(spacing)) ft) returned no selection.")
                }
                XCTAssertEqual(selection.plyCount, expected.0,
                               "Table 7b (\(spanFeet) ft, \(Int(spacing)) ft) ply count")
                XCTAssertEqual(selection.nominalSize, expected.1,
                               "Table 7b (\(spanFeet) ft, \(Int(spacing)) ft) nominal size")
                XCTAssertEqual(selection.tableRowJoistSpanFeet, spanFeet)
                XCTAssertTrue(selection.citation.contains("Table 7b"))
            }
        }
    }

    func testTheOnlyNotAvailableCellIsSixteenFeetAtEightFootPostSpacing() {
        var notAvailable: [String] = []
        for continuity in [DeckSpanTables.BeamContinuity.singleSpan, .twoSpans] {
            for spanFeet in DeckSpanTables.firstBeamTableRowFeet...DeckSpanTables.lastBeamTableRowFeet {
                for spacing in DeckSpanTables.postSpacingOptionsFeet {
                    let result = DeckSpanTables.beamSelection(
                        joistSpanIncludingCantileverFeet: Double(spanFeet),
                        postSpacingFeet: spacing,
                        continuity: continuity
                    )
                    if case .notPrescriptive = result {
                        notAvailable.append("\(continuity)/\(spanFeet)/\(Int(spacing))")
                    }
                }
            }
        }
        XCTAssertEqual(notAvailable, ["twoSpans/16/8"])
    }

    // MARK: - Interpolation rule

    func testAnEnteringSpanRoundsUpToTheNextTableRow() {
        // 10.4 ft enters the 11 ft row — never the 10 ft row, never an interpolation.
        guard case let .selection(selection) = DeckSpanTables.beamSelection(
            joistSpanIncludingCantileverFeet: 10.4,
            postSpacingFeet: 8,
            continuity: .singleSpan
        ) else { return XCTFail("10.4 ft must resolve on the 11 ft row.") }
        XCTAssertEqual(selection.tableRowJoistSpanFeet, 11)

        XCTAssertEqual(DeckSpanTables.roundedUpTableRowFeet(10.4), 11)
        XCTAssertEqual(DeckSpanTables.roundedUpTableRowFeet(10.000_1), 11)
        // An exact whole foot stays on its own row rather than being pushed up.
        XCTAssertEqual(DeckSpanTables.roundedUpTableRowFeet(12.0), 12)
        XCTAssertEqual(DeckSpanTables.roundedUpTableRowFeet(16.0), 16)
    }

    func testShortSpansUseTheFirstPublishedRowRatherThanExtrapolatingBelowIt() {
        guard case let .selection(selection) = DeckSpanTables.beamSelection(
            joistSpanIncludingCantileverFeet: 2.5,
            postSpacingFeet: 4,
            continuity: .singleSpan
        ) else { return XCTFail("A short span must resolve on the 4 ft row.") }
        XCTAssertEqual(selection.tableRowJoistSpanFeet, DeckSpanTables.firstBeamTableRowFeet)
    }

    func testSpansPastTheLastRowAreNotPrescriptive() {
        for continuity in [DeckSpanTables.BeamContinuity.singleSpan, .twoSpans] {
            let result = DeckSpanTables.beamSelection(
                joistSpanIncludingCantileverFeet: 16.1,
                postSpacingFeet: 4,
                continuity: continuity
            )
            XCTAssertEqual(result, .notPrescriptive(.joistSpanExceedsTable(
                enteringSpanFeet: 16.1,
                lastRowFeet: 16
            )), "A span past the last published row has no prescriptive selection.")
        }
    }

    func testAnUntabulatedPostSpacingIsNotPrescriptive() {
        let result = DeckSpanTables.beamSelection(
            joistSpanIncludingCantileverFeet: 10,
            postSpacingFeet: 7,
            continuity: .singleSpan
        )
        XCTAssertEqual(result, .notPrescriptive(.postSpacingNotTabulated(postSpacingFeet: 7)))
        XCTAssertEqual(DeckSpanTables.postSpacingOptionsFeet, [4, 6, 8])
    }

    // MARK: - Posts, CWC Note 5 / BCBC 9.17.4.1

    func testPostsAreSixBySixAtEveryPublishedHeightAndPlyCount() throws {
        for plyCount in 1...3 {
            for height in [0.5, 6.4, 6.5, 6.6, 11.9, 12.0] {
                guard case let .selection(selection) = DeckSpanTables.postSelection(
                    beamPlyCount: plyCount,
                    heightFeet: height
                ) else {
                    return XCTFail("\(plyCount)-ply at \(height) ft must have a published post size.")
                }
                XCTAssertEqual(selection.nominalSize, .sixBySix,
                               "BCBC 9.17.4.1 requires 6x6 absent a structural calculation.")
            }
        }
        XCTAssertEqual(DeckSpanTables.defaultPostSize, .sixBySix)
    }

    func testAPostOverTwelveFeetIsNotPrescriptive() {
        XCTAssertEqual(
            DeckSpanTables.postSelection(beamPlyCount: 2, heightFeet: 12.5),
            .notPrescriptive(.postHeightExceedsTable(heightFeet: 12.5, maxHeightFeet: 12))
        )
    }

    // MARK: - Provenance

    func testEveryEncodedRowNamesItsSource() {
        XCTAssertEqual(DeckSpanTables.species, .hemFir)
        XCTAssertEqual(DeckSpanTables.grade, .no2)
        XCTAssertTrue(DeckSpanTables.sourceDocument.contains("Prescriptive Residential Exterior Wood Deck Span Guide"))
        XCTAssertTrue(DeckSpanTables.designBasis.contains("KT 0.85"))
        XCTAssertTrue(DeckSpanTables.designBasis.contains("1.9 kPa"))
        XCTAssertTrue(DeckSpanTables.continuityLimitNote.contains("more than two supports"))
        XCTAssertTrue(DeckSpanTables.cantileverIsIncludedInBeamLookupNote.contains("shall be included"))
    }

    // MARK: - Helpers

    private func assertGrid(
        _ published: [Int: [(Int, LumberSize)]],
        continuity: DeckSpanTables.BeamContinuity,
        tableName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (spanFeet, cells) in published.sorted(by: { $0.key < $1.key }) {
            for (index, spacing) in DeckSpanTables.postSpacingOptionsFeet.enumerated() {
                let result = DeckSpanTables.beamSelection(
                    joistSpanIncludingCantileverFeet: Double(spanFeet),
                    postSpacingFeet: spacing,
                    continuity: continuity
                )
                guard case let .selection(selection) = result else {
                    XCTFail("\(tableName) (\(spanFeet) ft, \(Int(spacing)) ft) returned no selection.",
                            file: file, line: line)
                    continue
                }
                XCTAssertEqual(selection.plyCount, cells[index].0,
                               "\(tableName) (\(spanFeet) ft, \(Int(spacing)) ft) ply count",
                               file: file, line: line)
                XCTAssertEqual(selection.nominalSize, cells[index].1,
                               "\(tableName) (\(spanFeet) ft, \(Int(spacing)) ft) nominal size",
                               file: file, line: line)
                XCTAssertEqual(selection.tableEntry,
                               "\(cells[index].0)-\(cells[index].1.rawValue)",
                               file: file, line: line)
            }
        }
    }
}
