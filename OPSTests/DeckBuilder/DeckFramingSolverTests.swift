import Foundation
import XCTest
@testable import OPS

/// The solver decides how many posts a deck gets. These tests pin the worked
/// example from the bug (a 16 ft x 12 ft ledger-attached deck must drop from 8
/// posts to 3) and the invariants that keep the answer honest: the cantilever is
/// always the published one, never the old 12 in constant, and a layout outside
/// the tables is flagged rather than dressed up.
final class DeckFramingSolverTests: XCTestCase {

    private static let inchesPerFoot = 12.0

    private func input(
        widthFeet: Double,
        depthFeet: Double,
        ledgerAttached: Bool,
        guardRequired: Bool = true
    ) -> DeckFramingSolver.Input {
        DeckFramingSolver.Input(
            depthInches: depthFeet * Self.inchesPerFoot,
            beamLengthInches: widthFeet * Self.inchesPerFoot,
            isLedgerAttached: ledgerAttached,
            guardRequired: guardRequired
        )
    }

    // MARK: - The worked example from the bug

    func testSixteenByTwelveLedgerDeckDropsFromEightPostsToThree() throws {
        let solution = try XCTUnwrap(
            DeckFramingSolver.solve(input(widthFeet: 16, depthFeet: 12, ledgerAttached: true))
        )

        XCTAssertEqual(solution.beamCount, 1, "One beam carries a 12 ft deck. The old planner drew two.")
        XCTAssertEqual(solution.postCount, 3, "Eight posts and eight footings become three.")
        XCTAssertEqual(solution.postSpacingFeet, 8, "Table 5b permits 8 ft post spacing here.")
        XCTAssertEqual(solution.cantileverInches, 24, accuracy: 0.000_001,
                       "Table 3b allows a full 24 in cantilever on 2x10.")
        XCTAssertEqual(solution.joistClearSpanInches, 120, accuracy: 0.000_001,
                       "10 ft of joist span plus a 2 ft cantilever makes the 12 ft deck.")
        XCTAssertEqual(solution.joistSize, .twoByTen)
        XCTAssertEqual(solution.joistSpacingInchesOC, 24)
        XCTAssertEqual(solution.postSize, .sixBySix)
        XCTAssertTrue(solution.isPrescriptive)
        XCTAssertTrue(solution.advisories.isEmpty)

        // Table 5b, entering span 10 ft + 2 ft cantilever = 12 ft, 8 ft posts.
        let beam = try XCTUnwrap(solution.beamLines.first)
        let selection = try XCTUnwrap(beam.selection)
        XCTAssertEqual(selection.tableEntry, "2-2x10")
        XCTAssertEqual(selection.tableRowJoistSpanFeet, 12)
        XCTAssertEqual(beam.offsetInches, 120, accuracy: 0.000_001,
                       "The beam sits a full cantilever inboard of the outer edge.")
        XCTAssertTrue(solution.citations.contains { $0.contains("Table 3b") })
        XCTAssertTrue(solution.citations.contains { $0.contains("Table 5b") })
    }

    // MARK: - The defect being fixed

    func testTheCantileverIsAlwaysThePublishedOneAndNeverTheOldTwelveInchConstant() throws {
        // Any deck deep enough for the full allowance must take the full allowance.
        for depthFeet in stride(from: 8.0, through: 20.0, by: 1.0) {
            for attached in [true, false] {
                guard let solution = DeckFramingSolver.solve(
                    input(widthFeet: 16, depthFeet: depthFeet, ledgerAttached: attached)
                ) else { continue }
                let published = try XCTUnwrap(
                    DeckSpanTables.maxCantileverInches(nominalSize: solution.joistSize)
                )
                XCTAssertEqual(solution.cantileverInches, published, accuracy: 0.000_001,
                               "\(depthFeet) ft deep, attached=\(attached): cantilever must equal Table 3b.")
                XCTAssertNotEqual(solution.cantileverInches, 12, accuracy: 0.000_001,
                                  "12 in was the unsourced constant this change removes.")
            }
        }
    }

    func testTheOutermostBeamAlwaysSitsAFullCantileverInboardOfTheOuterEdge() throws {
        for depthFeet in stride(from: 6.0, through: 18.0, by: 2.0) {
            let attached = try XCTUnwrap(
                DeckFramingSolver.solve(input(widthFeet: 14, depthFeet: depthFeet, ledgerAttached: true))
            )
            let outermost = try XCTUnwrap(attached.beamLines.last)
            XCTAssertEqual(
                outermost.offsetInches,
                depthFeet * Self.inchesPerFoot - attached.cantileverInches,
                accuracy: 0.000_001,
                "\(depthFeet) ft attached deck: outer beam is inboard by exactly the cantilever."
            )
            XCTAssertLessThan(outermost.offsetInches, depthFeet * Self.inchesPerFoot,
                              "A beam on the outer edge is the bug.")
        }
    }

    func testPostCountNeverExceedsTheHeuristicItReplaces() {
        // The shipped heuristic: a beam every 8 ft of supported span, each beam
        // getting ceil(length / 6 ft) + 1 posts, with the beam pushed to within
        // 12 in of the outer edge.
        func legacyPostCount(widthFeet: Double, depthFeet: Double) -> Int {
            let depth = depthFeet * Self.inchesPerFoot
            let supported = max(depth - min(12, depth / 2), 0.001)
            let beams = max(1, Int(ceil(supported / 96)))
            let postsPerBeam = max(1, Int(ceil(widthFeet * Self.inchesPerFoot / 72))) + 1
            return beams * postsPerBeam
        }

        for widthFeet in stride(from: 8.0, through: 32.0, by: 2.0) {
            for depthFeet in stride(from: 6.0, through: 24.0, by: 2.0) {
                guard let solution = DeckFramingSolver.solve(
                    input(widthFeet: widthFeet, depthFeet: depthFeet, ledgerAttached: true)
                ) else { continue }
                XCTAssertLessThanOrEqual(
                    solution.postCount,
                    legacyPostCount(widthFeet: widthFeet, depthFeet: depthFeet),
                    "\(Int(widthFeet)) x \(Int(depthFeet)) ft must not gain posts."
                )
            }
        }
    }

    func testTheWidestPublishedPostSpacingIsPreferred() throws {
        let solution = try XCTUnwrap(
            DeckFramingSolver.solve(input(widthFeet: 20, depthFeet: 10, ledgerAttached: true))
        )
        XCTAssertEqual(solution.postSpacingFeet, 8,
                       "Post spacing comes from the beam table, not a 6 ft constant.")
        XCTAssertTrue(DeckSpanTables.postSpacingOptionsFeet.contains(solution.postSpacingFeet))
    }

    // MARK: - Post counting

    func testPostsSitAtBothBeamEndsPlusEveryIntervalBetween() {
        XCTAssertEqual(DeckFramingSolver.postCount(beamLengthInches: 192, postSpacingFeet: 8), 3)
        XCTAssertEqual(DeckFramingSolver.postCount(beamLengthInches: 96, postSpacingFeet: 8), 2)
        XCTAssertEqual(DeckFramingSolver.postCount(beamLengthInches: 97, postSpacingFeet: 8), 3)
        // A beam shorter than one bay still needs a post at each end.
        XCTAssertEqual(DeckFramingSolver.postCount(beamLengthInches: 24, postSpacingFeet: 8), 2)
    }

    // MARK: - Free-standing decks

    func testAFreeStandingDeckGetsTwoBeamsEachInboardByItsCantilever() throws {
        let solution = try XCTUnwrap(
            DeckFramingSolver.solve(input(widthFeet: 16, depthFeet: 12, ledgerAttached: false))
        )

        XCTAssertEqual(solution.beamCount, 2, "No ledger means a beam near each outer edge.")
        XCTAssertTrue(solution.isPrescriptive)

        let depth = 12 * Self.inchesPerFoot
        let near = try XCTUnwrap(solution.beamLines.first)
        let far = try XCTUnwrap(solution.beamLines.last)
        XCTAssertEqual(near.offsetInches, solution.cantileverInches, accuracy: 0.000_001)
        XCTAssertEqual(far.offsetInches, depth - solution.cantileverInches, accuracy: 0.000_001)
        XCTAssertGreaterThan(near.offsetInches, 0, "Neither beam may sit on an outer edge.")
        XCTAssertLessThan(far.offsetInches, depth)

        // Both beams carry a cantilever, so both enter Table 5b at span + cantilever.
        for line in solution.beamLines {
            let selection = try XCTUnwrap(line.selection)
            XCTAssertTrue(selection.citation.contains("Table 5b"))
        }
    }

    // MARK: - Decks outside the tables

    func testADeckTooDeepForOneJoistRunUsesTwoAndIsFlaggedNotPrescriptive() throws {
        // The deepest published run is 2x12 at 12 in o.c. (18 ft 1 in) plus a
        // 24 in cantilever, so a 24 ft deck cannot be one run.
        let solution = try XCTUnwrap(
            DeckFramingSolver.solve(input(widthFeet: 16, depthFeet: 24, ledgerAttached: true))
        )
        XCTAssertEqual(solution.beamCount, 2)
        XCTAssertFalse(solution.isPrescriptive,
                       "Two joist runs is a modelling choice the guide does not spell out.")
        XCTAssertFalse(solution.advisories.isEmpty, "A non-prescriptive layout must say why.")

        // The inner beam supports two runs (Table 7b); the outer one supports a
        // single run plus the cantilever (Table 5b).
        let inner = try XCTUnwrap(solution.beamLines.first?.selection)
        let outer = try XCTUnwrap(solution.beamLines.last?.selection)
        XCTAssertTrue(inner.citation.contains("Table 7b"))
        XCTAssertTrue(outer.citation.contains("Table 5b"))
    }

    func testAShallowDeckStillPlacesItsBeamOffBothTheLedgerAndTheOuterEdge() throws {
        let depthInches = 30.0
        let solution = try XCTUnwrap(DeckFramingSolver.solve(DeckFramingSolver.Input(
            depthInches: depthInches,
            beamLengthInches: 120,
            isLedgerAttached: true
        )))
        let beam = try XCTUnwrap(solution.beamLines.first)
        XCTAssertGreaterThan(beam.offsetInches, 0, "The beam may not land on the ledger.")
        XCTAssertLessThan(beam.offsetInches, depthInches, "The beam may not land on the outer edge.")
        XCTAssertLessThanOrEqual(solution.cantileverInches, solution.joistClearSpanInches + 0.000_001,
                                 "A cantilever never exceeds the back-span that carries it.")
    }

    func testDegenerateGeometryYieldsNoSolutionRatherThanAGuess() {
        XCTAssertNil(DeckFramingSolver.solve(DeckFramingSolver.Input(
            depthInches: 0, beamLengthInches: 120, isLedgerAttached: true
        )))
        XCTAssertNil(DeckFramingSolver.solve(DeckFramingSolver.Input(
            depthInches: 120, beamLengthInches: 0, isLedgerAttached: true
        )))
    }

    // MARK: - Guard rule

    func testAGuardForcesJoistsToTwoByEightOrLarger() throws {
        for depthFeet in stride(from: 5.0, through: 12.0, by: 1.0) {
            let solution = try XCTUnwrap(DeckFramingSolver.solve(
                input(widthFeet: 12, depthFeet: depthFeet, ledgerAttached: true, guardRequired: true)
            ))
            let depth = try XCTUnwrap(DeckSpanTables.nominalDepthInches(solution.joistSize))
            XCTAssertGreaterThanOrEqual(depth, 8,
                                        "Table 3b note 2: guarded decks use 2x8 or larger.")
        }
    }

    func testWithoutAGuardTheSolverMayStillUseASmallerJoistWhenItWins() throws {
        // Not an assertion about which size wins — only that dropping the guard
        // never makes the answer worse.
        let guarded = try XCTUnwrap(DeckFramingSolver.solve(
            input(widthFeet: 12, depthFeet: 7, ledgerAttached: true, guardRequired: true)
        ))
        let unguarded = try XCTUnwrap(DeckFramingSolver.solve(
            input(widthFeet: 12, depthFeet: 7, ledgerAttached: true, guardRequired: false)
        ))
        XCTAssertLessThanOrEqual(unguarded.postCount, guarded.postCount)
    }

    // MARK: - Determinism

    func testTheSolverIsDeterministicAcrossRepeatedCalls() throws {
        let cases = [
            input(widthFeet: 16, depthFeet: 12, ledgerAttached: true),
            input(widthFeet: 16, depthFeet: 12, ledgerAttached: false),
            input(widthFeet: 9.5, depthFeet: 7.25, ledgerAttached: true),
            input(widthFeet: 31, depthFeet: 23, ledgerAttached: true),
        ]
        for value in cases {
            let first = try XCTUnwrap(DeckFramingSolver.solve(value))
            for _ in 0..<5 {
                XCTAssertEqual(DeckFramingSolver.solve(value), first)
            }
        }
    }

    func testEveryPrescriptiveSolutionCarriesItsCitations() throws {
        for depthFeet in stride(from: 6.0, through: 18.0, by: 1.0) {
            let solution = try XCTUnwrap(
                DeckFramingSolver.solve(input(widthFeet: 16, depthFeet: depthFeet, ledgerAttached: true))
            )
            XCTAssertFalse(solution.citations.isEmpty)
            XCTAssertEqual(solution.citations, solution.citations.sorted(),
                           "Citations are sorted so the output stays byte-stable.")
            for line in solution.beamLines where solution.isPrescriptive {
                XCTAssertNotNil(line.selection,
                                "A prescriptive layout has a published beam on every line.")
            }
        }
    }

    // MARK: - Every joist run stays inside its published span

    func testNoJoistRunEverExceedsItsPublishedSpan() throws {
        for widthFeet in stride(from: 8.0, through: 28.0, by: 4.0) {
            for depthFeet in stride(from: 4.0, through: 26.0, by: 1.0) {
                guard let solution = DeckFramingSolver.solve(
                    input(widthFeet: widthFeet, depthFeet: depthFeet, ledgerAttached: true)
                ) else { continue }
                guard solution.isPrescriptive else { continue }
                let row = try XCTUnwrap(DeckSpanTables.joistRow(
                    nominalSize: solution.joistSize,
                    spacingInchesOC: solution.joistSpacingInchesOC
                ))
                XCTAssertLessThanOrEqual(
                    solution.joistClearSpanInches,
                    row.maxSpanInches + 0.000_001,
                    "\(Int(widthFeet)) x \(Int(depthFeet)) ft: \(solution.joistSize.rawValue) run over its span."
                )
                XCTAssertLessThanOrEqual(
                    solution.cantileverInches,
                    row.maxCantileverInches + 0.000_001
                )
            }
        }
    }
}
