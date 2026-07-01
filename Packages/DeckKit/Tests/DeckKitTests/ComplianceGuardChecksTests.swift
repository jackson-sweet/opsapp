import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

final class ComplianceGuardChecksTests: XCTestCase {
    func testCodePackageDecodesDefaultGuardRulesForOlderPackages() throws {
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

        XCTAssertEqual(decoded.guardRules.minGuardHeightInches, 36)
        XCTAssertEqual(decoded.guardRules.guardRequiredHeightInches, 30)
        XCTAssertEqual(decoded.guardRules.maxOpeningInches, 4)
        XCTAssertEqual(decoded.guardRules.codeSection, "IRC R312")
    }

    func testGuardHeightUsesPackageMinimumAndCodeSection() throws {
        let findings = GuardChecks.evaluate(
            drawingData(
                overallElevationFeet: 3,
                edge: deckEdge(
                    id: "front",
                    railing: RailingConfig(
                        railingType: .picket,
                        maxPostSpacing: 72,
                        postHeight: 34
                    )
                )
            ),
            mode: .design,
            package: package(
                guardRules: GuardRules(
                    minGuardHeightInches: 42,
                    guardRequiredHeightInches: 30,
                    maxOpeningInches: 4,
                    maxPostSpacingInches: 72,
                    codeSection: "TEST R312"
                )
            )
        )

        let finding = try XCTUnwrap(findings.first { $0.id == "guard:height:front" })
        XCTAssertEqual(finding.item, "Guard height front")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "34\"")
        XCTAssertEqual(finding.targetValue, "42\"")
        XCTAssertEqual(finding.codeSection, "TEST R312")
        XCTAssertEqual(finding.confidence, .high)
        XCTAssertEqual(finding.source, .measured)
        XCTAssertTrue(finding.fix?.localizedCaseInsensitiveContains("raise guard") ?? false)
    }

    func testGuardRequiredAtPackageTriggerWhenDeckEdgeHasNoGuard() throws {
        let report = ComplianceEngine.evaluate(
            drawingData(
                overallElevationFeet: 2.6,
                edge: deckEdge(id: "open-front", railing: nil)
            ),
            mode: .design,
            package: package(
                guardRules: GuardRules(
                    minGuardHeightInches: 36,
                    guardRequiredHeightInches: 30,
                    maxOpeningInches: 4,
                    maxPostSpacingInches: nil,
                    codeSection: "IRC R312.1"
                )
            )
        )

        let finding = try XCTUnwrap(report.findings.first { $0.id == "guard:required:open-front" })
        XCTAssertEqual(finding.item, "Guard open-front")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "31\" above grade")
        XCTAssertEqual(finding.targetValue, "guard required at 30\"")
        XCTAssertEqual(finding.codeSection, "IRC R312.1")
        XCTAssertEqual(report.summaryStatement, "1 code concern identified")
        XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("safe"))
        XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("compliant"))
    }

    func testGuardPostSpacingUsesPackageLimitWhenPresent() throws {
        let findings = GuardChecks.evaluate(
            drawingData(
                overallElevationFeet: 3,
                edge: deckEdge(
                    id: "side",
                    railing: RailingConfig(
                        railingType: .glass,
                        maxPostSpacing: 96,
                        postHeight: 42
                    )
                )
            ),
            mode: .asBuilt,
            package: package(
                guardRules: GuardRules(
                    minGuardHeightInches: 36,
                    guardRequiredHeightInches: 30,
                    maxOpeningInches: 4,
                    maxPostSpacingInches: 72,
                    codeSection: "TEST R312.2"
                )
            )
        )

        let finding = try XCTUnwrap(findings.first { $0.id == "guard:post-spacing:side" })
        XCTAssertEqual(finding.item, "Guard post spacing side")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "96\"")
        XCTAssertEqual(finding.targetValue, "72\" maximum")
        XCTAssertEqual(finding.codeSection, "TEST R312.2")
        XCTAssertEqual(finding.source, .userEntered)
    }

    func testHouseEdgesDoNotEmitGuardFindings() {
        let findings = GuardChecks.evaluate(
            drawingData(
                overallElevationFeet: 10,
                edge: DeckEdge(
                    id: "house",
                    startVertexId: "v1",
                    endVertexId: "v2",
                    edgeType: .houseEdge
                )
            ),
            mode: .design,
            package: package()
        )

        XCTAssertTrue(findings.isEmpty)
    }

    private func drawingData(
        overallElevationFeet: Double,
        edge: DeckEdge
    ) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0))
        ]
        data.edges = [edge]
        data.overallElevation = overallElevationFeet
        return data
    }

    private func deckEdge(
        id: String,
        railing: RailingConfig?
    ) -> DeckEdge {
        DeckEdge(
            id: id,
            startVertexId: "v1",
            endVertexId: "v2",
            edgeType: .deckEdge,
            railingConfig: railing
        )
    }

    private func package(guardRules: GuardRules = GuardRules()) -> CodePackage {
        CodePackage(
            jurisdictionId: "US-IRC",
            edition: "IRC 2021 / DCA6-12",
            publishedDate: Date(timeIntervalSince1970: 0),
            guardRules: guardRules
        )
    }
}
