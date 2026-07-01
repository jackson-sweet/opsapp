import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

final class ComplianceGeometryChecksTests: XCTestCase {
    func testOpenFootprintIsNotAssessable() throws {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 96))
        ]
        data.edges = [
            edge(id: "edge-1", start: "v1", end: "v2"),
            edge(id: "edge-2", start: "v2", end: "v3")
        ]

        let findings = GeometryChecks.evaluate(data, mode: .design, package: package())

        let finding = try XCTUnwrap(findings.first { $0.id == "geometry:footprint:open" })
        XCTAssertEqual(finding.item, "Deck footprint")
        XCTAssertEqual(finding.severity, .notAssessable)
        XCTAssertEqual(finding.currentValue, "open perimeter")
        XCTAssertEqual(finding.targetValue, "closed perimeter")
        XCTAssertEqual(finding.codeSection, "TEST IRC")
        XCTAssertEqual(finding.source, .notAssessable)
        XCTAssertTrue(finding.fix?.localizedCaseInsensitiveContains("close") ?? false)
    }

    func testInvalidEdgeReferenceIsNotAssessable() throws {
        var data = DeckDrawingData()
        data.vertices = [DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))]
        data.edges = [edge(id: "broken", start: "v1", end: "missing")]

        let findings = GeometryChecks.evaluate(data, mode: .design, package: package())

        let finding = try XCTUnwrap(findings.first { $0.id == "geometry:edge:broken" })
        XCTAssertEqual(finding.item, "Edge broken")
        XCTAssertEqual(finding.severity, .notAssessable)
        XCTAssertEqual(finding.currentValue, "missing vertex")
        XCTAssertEqual(finding.targetValue, "valid endpoints")
        XCTAssertEqual(finding.codeSection, "TEST IRC")
        XCTAssertEqual(finding.source, .notAssessable)
    }

    func testSelfIntersectingFootprintIsSafetyHazard() throws {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 96)),
            DeckVertex(id: "v3", position: CGPoint(x: 0, y: 96)),
            DeckVertex(id: "v4", position: CGPoint(x: 120, y: 0))
        ]
        data.edges = [
            edge(id: "edge-1", start: "v1", end: "v2"),
            edge(id: "edge-2", start: "v2", end: "v3"),
            edge(id: "edge-3", start: "v3", end: "v4"),
            edge(id: "edge-4", start: "v4", end: "v1")
        ]

        let findings = GeometryChecks.evaluate(data, mode: .design, package: package())

        let finding = try XCTUnwrap(findings.first { $0.id == "geometry:footprint:self-intersecting" })
        XCTAssertEqual(finding.item, "Deck footprint")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "self-intersecting")
        XCTAssertEqual(finding.targetValue, "simple closed footprint")
        XCTAssertEqual(finding.codeSection, "TEST IRC")
        XCTAssertEqual(finding.source, .measured)
    }

    func testAsBuiltMissingVisibleDeckHeightIsNotAssessable() throws {
        let report = ComplianceEngine.evaluate(
            closedRectangle(),
            mode: .asBuilt,
            package: package()
        )

        XCTAssertNotEqual(report.summaryStatement, ComplianceStrings.noFailures)
        let finding = try XCTUnwrap(report.findings.first { $0.id == "geometry:elevation:missing" })
        XCTAssertEqual(finding.item, "Deck height above grade")
        XCTAssertEqual(finding.severity, .notAssessable)
        XCTAssertNil(finding.currentValue)
        XCTAssertNil(finding.targetValue)
        XCTAssertEqual(finding.codeSection, "TEST IRC")
        XCTAssertEqual(finding.source, .notAssessable)
        XCTAssertTrue(finding.fix?.localizedCaseInsensitiveContains("measure deck height") ?? false)
    }

    func testFootingPostSpacingUsesBeamSpanPackageEnvelope() throws {
        var data = closedRectangle()
        data.scaleFactor = 1
        data.footings = FootingPlan(
            footings: [
                Footing(id: "footing-a", position: CGPoint(x: 0, y: 0)),
                Footing(id: "footing-b", position: CGPoint(x: 132, y: 0))
            ]
        )

        let findings = GeometryChecks.evaluate(
            data,
            mode: .design,
            package: package(
                beamSpanTable: [
                    BeamSpanSizingRow(
                        role: .beam,
                        size: .twoByTen,
                        plyCount: 2,
                        species: .sprucePineFir,
                        grade: .no2,
                        maxSpanFeet: 10,
                        codeSection: "TEST DCA6 Table 3",
                        limitingCheck: "beam support spacing"
                    )
                ]
            )
        )

        let finding = try XCTUnwrap(findings.first { $0.id == "geometry:post-spacing:footing-a:footing-b" })
        XCTAssertEqual(finding.item, "Post spacing footing-a to footing-b")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "11'")
        XCTAssertEqual(finding.targetValue, "10' maximum")
        XCTAssertEqual(finding.codeSection, "TEST DCA6 Table 3")
        XCTAssertEqual(finding.source, .measured)
    }

    func testPassingGeometryEmitsNoFindings() {
        var data = closedRectangle()
        data.overallElevation = 2.5
        data.scaleFactor = 1
        data.footings = FootingPlan(
            footings: [
                Footing(id: "footing-a", position: CGPoint(x: 0, y: 0)),
                Footing(id: "footing-b", position: CGPoint(x: 96, y: 0))
            ]
        )

        let findings = GeometryChecks.evaluate(
            data,
            mode: .design,
            package: package(
                beamSpanTable: [
                    BeamSpanSizingRow(
                        role: .beam,
                        size: .twoByTen,
                        plyCount: 2,
                        species: .sprucePineFir,
                        grade: .no2,
                        maxSpanFeet: 10,
                        codeSection: "TEST DCA6 Table 3",
                        limitingCheck: "beam support spacing"
                    )
                ]
            )
        )

        XCTAssertTrue(findings.isEmpty)
    }

    private func closedRectangle() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 96)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 96))
        ]
        data.edges = [
            edge(id: "edge-1", start: "v1", end: "v2"),
            edge(id: "edge-2", start: "v2", end: "v3"),
            edge(id: "edge-3", start: "v3", end: "v4"),
            edge(id: "edge-4", start: "v4", end: "v1")
        ]
        return data
    }

    private func edge(id: String, start: String, end: String) -> DeckEdge {
        DeckEdge(
            id: id,
            startVertexId: start,
            endVertexId: end,
            edgeType: .deckEdge
        )
    }

    private func package(
        beamSpanTable: [BeamSpanSizingRow] = []
    ) -> CodePackage {
        CodePackage(
            jurisdictionId: "US-IRC",
            edition: "TEST IRC",
            publishedDate: Date(timeIntervalSince1970: 0),
            beamSpanTable: beamSpanTable
        )
    }
}
