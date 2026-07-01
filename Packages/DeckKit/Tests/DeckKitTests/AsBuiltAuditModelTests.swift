import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

final class AsBuiltAuditModelTests: XCTestCase {
    func testEnteredHiddenFramingIsInjectedForAsBuiltEvaluationWithUserEnteredSource() throws {
        var capture = AsBuiltCapture(measuredGeometry: visibleDeckGeometry())
        capture.enteredJoist = overloadedMember(id: "joist-2x8-24", role: .joist)

        let evaluable = capture.asEvaluableDesign()
        let members = try XCTUnwrap(evaluable.framing?.members.first?.members)
        XCTAssertEqual(members.map(\.id), ["joist-2x8-24"])
        XCTAssertNil(evaluable.footings)

        let report = ComplianceEngine.evaluate(evaluable, mode: .asBuilt, package: package())
        let finding = try XCTUnwrap(
            report.findings.first { $0.id == "structural:framing:level-main:joist-2x8-24" }
        )
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "122% utilization")
        XCTAssertEqual(finding.targetValue, "100% maximum")
        XCTAssertEqual(finding.source, .userEntered)
    }

    func testUnknownFootingsRemainAbsentAndEmitNotAssessableFinding() throws {
        let capture = AsBuiltCapture(measuredGeometry: visibleDeckGeometry())

        let evaluable = capture.asEvaluableDesign()
        XCTAssertNil(evaluable.footings)

        let report = ComplianceEngine.evaluate(evaluable, mode: .asBuilt, package: package())
        let finding = try XCTUnwrap(
            report.findings.first { $0.id == "structural:footings:missing" }
        )
        XCTAssertEqual(finding.severity, .notAssessable)
        XCTAssertNil(finding.currentValue)
        XCTAssertNil(finding.targetValue)
        XCTAssertEqual(finding.source, .notAssessable)
    }

    func testEvidenceAndLedgerAnswersMapToAuditOverlayWithoutFabricatingLedgerPass() {
        let evidence = Evidence(
            photoURL: URL(string: "https://example.invalid/ledger-fastener.jpg"),
            sceneRef: "scene-ledger-1"
        )
        var capture = AsBuiltCapture(measuredGeometry: visibleDeckGeometry())
        capture.fastenerHint = evidence
        capture.lateralConnectorsPresent = true
        capture.flashingPresent = false

        let evaluable = capture.asEvaluableDesign()

        XCTAssertEqual(
            evaluable.asBuiltAudit,
            AsBuiltAuditOverlay(
                fastenerHint: evidence,
                lateralConnectorsPresent: true,
                flashingPresent: false
            )
        )
        XCTAssertNil(evaluable.house?.ledger)
    }

    func testCaptureRoundTripsAndComparesEnteredEvidence() throws {
        var capture = AsBuiltCapture(measuredGeometry: visibleDeckGeometry())
        capture.enteredBeam = overloadedMember(id: "beam-hidden", role: .beam)
        capture.fastenerHint = Evidence(
            photoURL: URL(string: "https://example.invalid/fastener.jpg"),
            sceneRef: "scene-fastener-1"
        )
        capture.lateralConnectorsPresent = false
        capture.flashingPresent = true

        let encoded = try JSONEncoder().encode(capture)
        let decoded = try JSONDecoder().decode(AsBuiltCapture.self, from: encoded)

        XCTAssertEqual(decoded, capture)
    }

    private func overloadedMember(id: String, role: FramingRole) -> FramingMember {
        FramingMember(
            id: id,
            role: role,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 192, y: 0),
            nominalSize: .twoByEight,
            spacingInchesOC: 24,
            species: .sprucePineFir,
            grade: .no2,
            sizing: MemberSizingResult(
                outcome: .ok(
                    value: SizedMember(
                        size: .twoByEight,
                        plyCount: 1,
                        allowableSpanFeet: 10,
                        actualSpanFeet: 12.2,
                        utilization: 1.22
                    ),
                    citation: citation(codeSection: "IRC R507.6"),
                    assumptions: assumptions()
                )
            )
        )
    }

    private func visibleDeckGeometry() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.overallElevation = 2
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120))
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
            edition: "IRC 2021 / DCA6-12",
            publishedDate: Date(timeIntervalSince1970: 0)
        )
    }

    private func citation(codeSection: String) -> EngineCitation {
        EngineCitation(
            limitingCheck: "span table",
            codeSection: codeSection,
            packageEdition: "IRC 2021 / DCA6-12"
        )
    }

    private func assumptions() -> EngineAssumptions {
        EngineAssumptions(
            liveLoadPSF: 40,
            deadLoadPSF: 10,
            snowLoadPSF: nil,
            species: .sprucePineFir,
            grade: .no2,
            soilBearingPSF: nil,
            packageEdition: "IRC 2021 / DCA6-12"
        )
    }
}
