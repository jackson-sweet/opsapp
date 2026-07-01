import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

final class ComplianceStructuralChecksTests: XCTestCase {
    func testOutOfEnvelopeFramingMemberBecomesSafetyHazardAndPESignalWithoutTargetNumber() throws {
        let report = ComplianceEngine.evaluate(
            drawingData(
                member: framingMember(
                    id: "beam-overspan",
                    role: .beam,
                    sizing: MemberSizingResult(
                        outcome: .outOfEnvelope(
                            reason: "Beam span exceeds packaged table envelope.",
                            citation: citation(codeSection: "AWC DCA6 Table 3")
                        )
                    )
                )
            ),
            mode: .design,
            package: package()
        )

        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertEqual(finding.id, "structural:framing:level-main:beam-overspan")
        XCTAssertEqual(finding.item, "Beam beam-overspan")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "Beam span exceeds packaged table envelope.")
        XCTAssertNil(finding.targetValue)
        XCTAssertEqual(finding.codeSection, "AWC DCA6 Table 3")
        XCTAssertTrue(finding.fix?.localizedCaseInsensitiveContains("licensed engineer") ?? false)
        XCTAssertEqual(finding.confidence, .high)
        XCTAssertEqual(finding.source, .measured)
        XCTAssertEqual(report.summaryStatement, "1 code concern identified")
        XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("safe"))
        XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("compliant"))
    }

    func testOversizedUtilizationBecomesAssessableCodeConcern() throws {
        let report = ComplianceEngine.evaluate(
            drawingData(
                member: framingMember(
                    id: "joist-overloaded",
                    role: .joist,
                    sizing: MemberSizingResult(
                        outcome: .ok(
                            value: SizedMember(
                                size: .twoByEight,
                                plyCount: 1,
                                allowableSpanFeet: 10,
                                actualSpanFeet: 11,
                                utilization: 1.1
                            ),
                            citation: citation(codeSection: "IRC R507.6"),
                            assumptions: assumptions()
                        )
                    )
                )
            ),
            mode: .design,
            package: package()
        )

        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertEqual(finding.id, "structural:framing:level-main:joist-overloaded")
        XCTAssertEqual(finding.item, "Joist joist-overloaded")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "110% utilization")
        XCTAssertEqual(finding.targetValue, "100% maximum")
        XCTAssertEqual(finding.codeSection, "IRC R507.6")
        XCTAssertEqual(report.summaryStatement, "1 code concern identified")
    }

    func testMissingFramingSizingIsNotAssessableNotSilentlyClean() throws {
        let findings = StructuralChecks.evaluate(
            drawingData(
                member: framingMember(
                    id: "joist-unsized",
                    role: .joist,
                    sizing: nil
                )
            ),
            mode: .design,
            package: package()
        )

        let finding = try XCTUnwrap(findings.first)
        XCTAssertEqual(finding.id, "structural:framing:level-main:joist-unsized")
        XCTAssertEqual(finding.severity, .notAssessable)
        XCTAssertNil(finding.currentValue)
        XCTAssertNil(finding.targetValue)
        XCTAssertEqual(finding.source, .notAssessable)
        XCTAssertTrue(finding.fix?.localizedCaseInsensitiveContains("run structural sizing") ?? false)
    }

    func testAsBuiltWithHiddenFootingSizingNeverReadsClean() throws {
        var data = DeckDrawingData()
        data.footings = FootingPlan(
            footings: [
                Footing(
                    id: "footing-hidden",
                    position: CGPoint(x: 48, y: 96),
                    sizing: nil
                )
            ]
        )

        let report = ComplianceEngine.evaluate(data, mode: .asBuilt, package: package())

        XCTAssertNotEqual(report.summaryStatement, ComplianceStrings.noFailures)
        XCTAssertTrue(report.findings.contains { finding in
            finding.id == "structural:footing:footing-hidden"
                && finding.severity == .notAssessable
                && finding.source == .notAssessable
        })
    }

    func testSizedFramingAndFootingsEmitNoStructuralFindings() {
        var data = drawingData(
            member: framingMember(
                id: "beam-ok",
                role: .beam,
                sizing: MemberSizingResult(
                    outcome: .ok(
                        value: SizedMember(
                            size: .twoByTen,
                            plyCount: 2,
                            allowableSpanFeet: 12,
                            actualSpanFeet: 10,
                            utilization: 0.83
                        ),
                        citation: citation(codeSection: "AWC DCA6 Table 3"),
                        assumptions: assumptions()
                    )
                )
            )
        )
        data.footings = FootingPlan(
            footings: [
                Footing(
                    id: "footing-ok",
                    position: CGPoint(x: 0, y: 0),
                    sizing: FootingSizingResult(
                        diameterInches: 12,
                        depthInches: 48,
                        bearingAreaSqIn: 113.1,
                        requiredFrostDepthInches: 36,
                        citation: citation(codeSection: "IRC R507.3")
                    )
                )
            ]
        )

        let report = ComplianceEngine.evaluate(data, mode: .design, package: package())

        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.summaryStatement, ComplianceStrings.noFailures)
    }

    private func drawingData(member: FramingMember) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(
                    levelId: "level-main",
                    members: [member]
                )
            ],
            generationSource: .manual
        )
        return data
    }

    private func framingMember(
        id: String,
        role: FramingRole,
        sizing: MemberSizingResult?
    ) -> FramingMember {
        FramingMember(
            id: id,
            role: role,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 120, y: 0),
            nominalSize: .twoByEight,
            spacingInchesOC: 16,
            species: .sprucePineFir,
            grade: .no2,
            sizing: sizing
        )
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
