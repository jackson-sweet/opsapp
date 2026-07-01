import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

final class ComplianceEngineOrchestratorTests: XCTestCase {
    func testGeneratedAtAndPackageEditionAreStampedByEvaluation() {
        let package = CodePackage(
            jurisdictionId: "US-IRC",
            edition: "TEST IRC",
            publishedDate: Date(timeIntervalSince1970: 0)
        )
        let before = Date()

        let report = ComplianceEngine.evaluate(DeckDrawingData(), mode: .design, package: package)

        let after = Date()
        XCTAssertEqual(report.packageEdition, "TEST IRC")
        XCTAssertGreaterThanOrEqual(report.generatedAt.timeIntervalSince1970, before.timeIntervalSince1970)
        XCTAssertLessThanOrEqual(report.generatedAt.timeIntervalSince1970, after.timeIntervalSince1970)
        XCTAssertEqual(report.disclaimer, ComplianceStrings.disclaimer)
    }

    func testNotAssessableOnlyDesignDoesNotUseNoFailureSummary() throws {
        let report = ComplianceEngine.evaluate(
            unsizedFramingData(),
            mode: .design,
            package: package()
        )

        let finding = try XCTUnwrap(report.findings.first { $0.id == "structural:framing:level-main:joist-unsized" })
        XCTAssertEqual(finding.severity, .notAssessable)
        XCTAssertEqual(finding.source, .notAssessable)
        XCTAssertEqual(report.summaryStatement, "1 code concern identified")
        XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("safe"))
        XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("compliant"))
    }

    func testAsBuiltVisibleDeckWithoutFootingDataDoesNotReadClean() throws {
        let report = ComplianceEngine.evaluate(
            visibleDeckWithoutFootings(),
            mode: .asBuilt,
            package: package()
        )

        XCTAssertNotEqual(report.summaryStatement, ComplianceStrings.noFailures)
        let finding = try XCTUnwrap(report.findings.first { $0.id == "structural:footings:missing" })
        XCTAssertEqual(finding.item, "Footings")
        XCTAssertEqual(finding.severity, .notAssessable)
        XCTAssertNil(finding.currentValue)
        XCTAssertNil(finding.targetValue)
        XCTAssertEqual(finding.codeSection, "TEST IRC")
        XCTAssertEqual(finding.source, .notAssessable)
        XCTAssertTrue(finding.fix?.localizedCaseInsensitiveContains("footing size and depth") ?? false)
    }

    private func unsizedFramingData() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(
                    levelId: "level-main",
                    members: [
                        FramingMember(
                            id: "joist-unsized",
                            role: .joist,
                            start: CGPoint(x: 0, y: 0),
                            end: CGPoint(x: 120, y: 0),
                            nominalSize: .twoByEight
                        )
                    ]
                )
            ],
            generationSource: .manual
        )
        return data
    }

    private func visibleDeckWithoutFootings() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.overallElevation = 2
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 96)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 96))
        ]
        data.edges = [
            DeckEdge(id: "edge-1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "edge-2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "edge-3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "edge-4", startVertexId: "v4", endVertexId: "v1")
        ]
        return data
    }

    private func package() -> CodePackage {
        CodePackage(
            jurisdictionId: "US-IRC",
            edition: "TEST IRC",
            publishedDate: Date(timeIntervalSince1970: 0)
        )
    }
}
