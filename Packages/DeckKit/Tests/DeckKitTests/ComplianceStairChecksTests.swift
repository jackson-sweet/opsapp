import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

final class ComplianceStairChecksTests: XCTestCase {
    func testOlderPackagesDecodeDefaultStairCodeSection() throws {
        let json = Data(
            """
            {
              "jurisdictionId": "US-IRC",
              "edition": "IRC 2021 / DCA6-12",
              "publishedDate": 0,
              "unitSystem": "imperial"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CodePackage.self, from: json)

        XCTAssertEqual(decoded.stairRules.stairCodeSection, "IRC R311.7")
    }

    func testRiserAbovePackageMaximumEmitsFinding() throws {
        let findings = StairChecks.evaluate(
            drawingData(
                edge: stairEdge(
                    id: "stair-riser",
                    stair: StairConfig(
                        width: 48,
                        risePerStep: 8,
                        runPerTread: 10,
                        treadCount: 3
                    )
                )
            ),
            mode: .design,
            package: package(
                stairRules: StairRules(
                    maxRiserHeightInches: 7.75,
                    minTreadRunInches: 10,
                    stairCodeSection: "TEST R311.7",
                    handrailRequiredRiserCount: 4,
                    handrailCodeSection: "TEST R311.7.8"
                )
            )
        )

        let finding = try XCTUnwrap(findings.first { $0.id == "stair:riser:stair-riser" })
        XCTAssertEqual(finding.item, "Stair riser stair-riser")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "8\"")
        XCTAssertEqual(finding.targetValue, "7.75\" maximum")
        XCTAssertEqual(finding.codeSection, "TEST R311.7")
        XCTAssertEqual(finding.confidence, .high)
        XCTAssertEqual(finding.source, .measured)
        XCTAssertTrue(finding.fix?.localizedCaseInsensitiveContains("reduce riser") ?? false)
    }

    func testTreadRunBelowPackageMinimumEmitsFinding() throws {
        let findings = StairChecks.evaluate(
            drawingData(
                edge: stairEdge(
                    id: "stair-run",
                    stair: StairConfig(
                        width: 48,
                        risePerStep: 7.5,
                        runPerTread: 9.5,
                        treadCount: 3
                    )
                )
            ),
            mode: .design,
            package: package(
                stairRules: StairRules(
                    maxRiserHeightInches: 7.75,
                    minTreadRunInches: 10,
                    stairCodeSection: "TEST R311.7",
                    handrailRequiredRiserCount: 4,
                    handrailCodeSection: "TEST R311.7.8"
                )
            )
        )

        let finding = try XCTUnwrap(findings.first { $0.id == "stair:tread-run:stair-run" })
        XCTAssertEqual(finding.item, "Stair tread run stair-run")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "9.5\"")
        XCTAssertEqual(finding.targetValue, "10\" minimum")
        XCTAssertEqual(finding.codeSection, "TEST R311.7")
        XCTAssertTrue(finding.fix?.localizedCaseInsensitiveContains("increase tread run") ?? false)
    }

    func testHandrailRequiredAtPackageRiserCountWhenNoStairRailing() throws {
        let report = ComplianceEngine.evaluate(
            drawingData(
                edge: stairEdge(
                    id: "stair-handrail",
                    stair: StairConfig(
                        width: 48,
                        risePerStep: 7.5,
                        runPerTread: 10,
                        treadCount: 4,
                        railingConfig: nil
                    )
                )
            ),
            mode: .asBuilt,
            package: package(
                stairRules: StairRules(
                    maxRiserHeightInches: 7.75,
                    minTreadRunInches: 10,
                    stairCodeSection: "TEST R311.7",
                    handrailRequiredRiserCount: 4,
                    handrailCodeSection: "TEST R311.7.8"
                )
            )
        )

        let finding = try XCTUnwrap(report.findings.first { $0.id == "stair:handrail:stair-handrail" })
        XCTAssertEqual(finding.item, "Stair handrail stair-handrail")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "no handrail")
        XCTAssertEqual(finding.targetValue, "handrail required at 4 risers")
        XCTAssertEqual(finding.codeSection, "TEST R311.7.8")
        XCTAssertEqual(finding.source, .userEntered)
        XCTAssertEqual(report.summaryStatement, "1 code concern identified")
    }

    func testStairWithPackagePassingDimensionsAndHandrailEmitsNoFindings() {
        let findings = StairChecks.evaluate(
            drawingData(
                edge: stairEdge(
                    id: "stair-ok",
                    stair: StairConfig(
                        width: 48,
                        risePerStep: 7.25,
                        runPerTread: 11,
                        treadCount: 4,
                        railingConfig: RailingConfig(railingType: .picket, maxPostSpacing: 72)
                    )
                )
            ),
            mode: .design,
            package: package()
        )

        XCTAssertTrue(findings.isEmpty)
    }

    private func drawingData(edge: DeckEdge) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0))
        ]
        data.edges = [edge]
        return data
    }

    private func stairEdge(
        id: String,
        stair: StairConfig
    ) -> DeckEdge {
        DeckEdge(
            id: id,
            startVertexId: "v1",
            endVertexId: "v2",
            edgeType: .deckEdge,
            stairConfig: stair
        )
    }

    private func package(stairRules: StairRules = StairRules()) -> CodePackage {
        CodePackage(
            jurisdictionId: "US-IRC",
            edition: "IRC 2021 / DCA6-12",
            publishedDate: Date(timeIntervalSince1970: 0),
            stairRules: stairRules
        )
    }
}
