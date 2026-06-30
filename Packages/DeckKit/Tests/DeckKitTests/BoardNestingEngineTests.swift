import CoreGraphics
import XCTest
@testable import DeckKit

final class BoardNestingEngineTests: XCTestCase {
    func testSingleStockPacksLongestFirstWithKerf() {
        let plan = BoardNestingEngine.makePlan(
            cuts: [
                cut("short", length: 40),
                cut("long", length: 60),
                cut("middle", length: 50),
            ],
            stock: BoardStock(
                stockLengthsInches: [144],
                kerfInches: 0.125,
                offcutMinLengthInches: 36
            )
        )

        XCTAssertEqual(plan.totalStockCount, 2)
        XCTAssertEqual(plan.stockPieces.count, 2)
        XCTAssertEqual(plan.stockPieces.map(\.source), [.purchasedStock, .purchasedStock])
        XCTAssertEqual(plan.stockPieces[0].cuts.map(\.id), ["long", "middle"])
        XCTAssertEqual(plan.stockPieces[0].remainderInches, 33.875, accuracy: 0.001)
        XCTAssertEqual(plan.stockPieces[1].cuts.map(\.id), ["short"])
        XCTAssertEqual(plan.stockPieces[1].remainderInches, 104, accuracy: 0.001)
        XCTAssertEqual(plan.producedOffcuts.map(\.lengthInches), [104])
        XCTAssertEqual(plan.totalWasteLinearFeet, 34.0 / 12.0, accuracy: 0.001)
    }

    func testOffcutBankedAndReusedBeforeBuyingStock() {
        let firstJob = BoardNestingEngine.makePlan(
            cuts: [cut("deck-board-a", length: 74)],
            stock: BoardStock(
                stockLengthsInches: [144],
                kerfInches: 0.125,
                offcutMinLengthInches: 24
            )
        )

        let banked = try! XCTUnwrap(firstJob.producedOffcuts.first)
        XCTAssertEqual(banked.lengthInches, 70, accuracy: 0.001)
        XCTAssertEqual(banked.family, .decking)

        let secondJob = BoardNestingEngine.makePlan(
            cuts: [cut("deck-board-b", length: 60)],
            stock: BoardStock(
                stockLengthsInches: [144],
                kerfInches: 0.125,
                offcutMinLengthInches: 24
            ),
            availableOffcuts: [banked]
        )

        XCTAssertEqual(secondJob.totalStockCount, 0)
        XCTAssertEqual(secondJob.stockPieces.count, 1)
        XCTAssertEqual(secondJob.stockPieces[0].source, .onHandOffcut)
        XCTAssertEqual(secondJob.stockPieces[0].sourceOffcutId, banked.id)
        XCTAssertEqual(secondJob.stockPieces[0].cuts.map(\.id), ["deck-board-b"])
        XCTAssertEqual(secondJob.reuseNotes.count, 1)
        XCTAssertTrue(secondJob.reuseNotes[0].contains("deck-board-b"))
        XCTAssertTrue(secondJob.reuseNotes[0].contains(banked.id))
    }

    func testFamilyIsolationKeepsFasciaOutOfDeckingOffcut() {
        let plan = BoardNestingEngine.makePlan(
            cuts: [cut("fascia-run", family: .fascia, length: 60)],
            stock: BoardStock(
                stockLengthsInches: [144],
                kerfInches: 0.125,
                offcutMinLengthInches: 24
            ),
            availableOffcuts: [
                BoardOffcut(id: "decking-offcut", lengthInches: 80, family: .decking),
            ]
        )

        XCTAssertEqual(plan.totalStockCount, 1)
        XCTAssertEqual(plan.stockPieces.count, 1)
        XCTAssertEqual(plan.stockPieces[0].source, .purchasedStock)
        XCTAssertEqual(plan.stockPieces[0].family, .fascia)
        XCTAssertTrue(plan.reuseNotes.isEmpty)
    }

    func testGrainLockedCutsAreNotFlipped() {
        let plan = BoardNestingEngine.makePlan(
            cuts: [cut("picture-frame-north", length: 96, grainLocked: true)],
            stock: BoardStock(
                stockLengthsInches: [144],
                kerfInches: 0.125,
                offcutMinLengthInches: 24
            )
        )

        let placement = try! XCTUnwrap(plan.stockPieces.first?.placements.first)
        XCTAssertEqual(placement.cutId, "picture-frame-north")
        XCTAssertFalse(placement.isFlipped)
        XCTAssertEqual(placement.startInches, 0, accuracy: 0.001)
        XCTAssertEqual(placement.endInches, 96, accuracy: 0.001)
    }

    func testMultipleStockLengthsMinimizesWasteForSingleLongRun() {
        let plan = BoardNestingEngine.makePlan(
            cuts: [cut("long-run", length: 200)],
            stock: BoardStock(
                stockLengthsInches: [144, 192, 240],
                kerfInches: 0.125,
                offcutMinLengthInches: 24
            )
        )

        XCTAssertEqual(plan.totalStockCount, 1)
        XCTAssertEqual(plan.stockPieces.count, 1)
        XCTAssertEqual(plan.stockPieces[0].stockLengthInches, 240)
        XCTAssertEqual(plan.stockPieces[0].cuts.map(\.id), ["long-run"])
        XCTAssertEqual(plan.stockPieces[0].remainderInches, 40, accuracy: 0.001)
        XCTAssertEqual(plan.producedOffcuts.map(\.lengthInches), [40])
    }

    func testVinylRegressionGateStillReusesEquivalentOffcutLane() {
        let main = rectangle(id: "main", label: "Main deck", width: 288, height: 132)
        let landing = rectangle(id: "landing", label: "Landing", width: 96, height: 8)

        let plan = VinylCutListEngine.makePlan(
            surfaces: [main, landing],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 2,
                edgeWrapInches: 0,
                direction: .lengthwise
            )
        )

        XCTAssertEqual(plan.reuseNotes.count, 1)
        XCTAssertEqual(plan.reuseNotes.first?.sourceSurfaceLabel, "Main / Main deck")
        XCTAssertEqual(plan.reuseNotes.first?.targetSurfaceLabel, "Main / Landing")
        XCTAssertEqual(plan.totalReusedCutAreaSqFt, 48, accuracy: 0.01)
        XCTAssertEqual(plan.totalOrderedSqFt, 288)
    }

    private func cut(
        _ id: String,
        family: BoardFamily = .decking,
        length: Double,
        grainLocked: Bool = false
    ) -> BoardCutRequirement {
        BoardCutRequirement(
            id: id,
            family: family,
            lengthInches: length,
            grainLocked: grainLocked
        )
    }

    private func rectangle(id: String, label: String, width: Double, height: Double) -> VinylOrderSurfaceInput {
        VinylOrderSurfaceInput(
            id: id,
            label: label,
            levelName: "Main",
            positions: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: width, y: 0),
                CGPoint(x: width, y: height),
                CGPoint(x: 0, y: height),
            ],
            scaleFactor: 1
        )
    }
}
