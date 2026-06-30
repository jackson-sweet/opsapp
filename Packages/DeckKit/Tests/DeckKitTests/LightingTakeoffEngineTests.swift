import CoreGraphics
import XCTest
@testable import DeckKit

final class LightingTakeoffEngineTests: XCTestCase {
    func testTransformerSizedAtEightyPercentLoadToNextStandardSize() {
        let plan = LightingPlan(
            fixtures: tenFixtures(),
            receptacles: []
        )

        let result = LightingTakeoffEngine.size(
            plan: plan,
            fixtureWatts: 4,
            scaleFactor: 1
        )

        XCTAssertEqual(result.fixtureCount, 10)
        XCTAssertEqual(result.totalConnectedWatts, 40, accuracy: 0.001)
        XCTAssertEqual(result.recommendedTransformerWatts, 60, accuracy: 0.001)
    }

    func testTransformerSizeLadderCanBeProvidedByCatalog() {
        let result = LightingTakeoffEngine.size(
            plan: LightingPlan(fixtures: tenFixtures(), receptacles: []),
            fixtureWatts: 4,
            scaleFactor: 1,
            standardTransformerWatts: [50, 75, 100]
        )

        XCTAssertEqual(result.recommendedTransformerWatts, 50, accuracy: 0.001)
    }

    func testWireRunUsesNearestNeighborFixturePath() {
        let plan = LightingPlan(
            fixtures: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 36, y: 0),
                CGPoint(x: 36, y: 48),
            ],
            receptacles: []
        )

        let result = LightingTakeoffEngine.size(
            plan: plan,
            fixtureWatts: 2,
            scaleFactor: 1
        )

        XCTAssertEqual(result.estimatedWireRunFeet, 7, accuracy: 0.001)
    }

    func testReceptacleCountAndElectricalNoteStayAdvisory() {
        let result = LightingTakeoffEngine.size(
            plan: LightingPlan(
                fixtures: [CGPoint(x: 0, y: 0)],
                receptacles: [
                    CGPoint(x: 12, y: 0),
                    CGPoint(x: 24, y: 0),
                ]
            ),
            fixtureWatts: 1,
            scaleFactor: 1
        )

        XCTAssertEqual(result.receptacleCount, 2)
        XCTAssertTrue(result.electricalNote.contains("GFCI"))
        XCTAssertTrue(result.electricalNote.contains("NEC 210.8(A)(3)"))
        XCTAssertTrue(result.electricalNote.contains("NEC 210.52(E)"))
        XCTAssertFalse(result.electricalNote.localizedCaseInsensitiveContains("safe"))
        XCTAssertFalse(result.electricalNote.localizedCaseInsensitiveContains("compliant"))
    }

    func testEmptyPlanZeroesQuantitiesButKeepsAdvisoryNote() {
        let result = LightingTakeoffEngine.size(
            plan: LightingPlan(),
            fixtureWatts: 4,
            scaleFactor: 1
        )

        XCTAssertEqual(result.fixtureCount, 0)
        XCTAssertEqual(result.totalConnectedWatts, 0, accuracy: 0.001)
        XCTAssertEqual(result.recommendedTransformerWatts, 0, accuracy: 0.001)
        XCTAssertEqual(result.estimatedWireRunFeet, 0, accuracy: 0.001)
        XCTAssertEqual(result.receptacleCount, 0)
        XCTAssertFalse(result.electricalNote.isEmpty)
    }

    private func tenFixtures() -> [CGPoint] {
        (0..<10).map { CGPoint(x: Double($0) * 12, y: 0) }
    }
}
