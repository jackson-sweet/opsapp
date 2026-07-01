import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

@MainActor
final class CapabilityGatingTests: XCTestCase {
    func testLightModelHidesAndGatesCompliancePermitAndStampWorkflows() {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: drawingDataWithOutOfEnvelopeMember(),
            capabilities: .light,
            onPersist: { persisted.append($0) }
        )

        XCTAssertFalse(model.canRunPermitCompliance)
        XCTAssertFalse(model.canOpenAsBuiltAudit)
        XCTAssertFalse(model.canGeneratePermitPlanSet)
        XCTAssertFalse(model.canRequestPEStamp)
        XCTAssertFalse(model.acknowledgeComplianceDisclaimer(for: package(), at: anchorDate))
        XCTAssertNil(model.runCompliance(mode: .design, package: package()))
        XCTAssertFalse(model.openAsBuiltWizard())
        XCTAssertNil(model.generatePermitSet(
            sheets: [.planView],
            titleBlock: titleBlock(),
            package: package()
        ))
        XCTAssertFalse(model.requestPEStamp(reason: "Beam calc review", requestedAt: anchorDate))
        XCTAssertNil(model.cachedComplianceReport)
        XCTAssertNil(model.drawingData.permitMeta)
        XCTAssertTrue(persisted.isEmpty)
    }

    func testFullModelRequiresDisclaimerBeforeReportOrPermitGeneration() {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: drawingDataWithOutOfEnvelopeMember(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        XCTAssertTrue(model.canRunPermitCompliance)
        XCTAssertTrue(model.canGeneratePermitPlanSet)
        XCTAssertTrue(model.requiresComplianceDisclaimer(for: package()))
        XCTAssertNil(model.runCompliance(mode: .design, package: package()))
        XCTAssertNil(model.generatePermitSet(
            sheets: [.planView],
            titleBlock: titleBlock(),
            package: package()
        ))
        XCTAssertNil(model.cachedComplianceReport)
        XCTAssertTrue(persisted.isEmpty)
    }

    func testFullModelCachesComplianceReportAndSurfacesPERouteAfterDisclaimer() throws {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: drawingDataWithOutOfEnvelopeMember(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        XCTAssertTrue(model.acknowledgeComplianceDisclaimer(for: package(), at: anchorDate))
        let report = try XCTUnwrap(model.runCompliance(mode: .design, package: package()))

        XCTAssertEqual(report.packageEdition, "IRC 2021 / DCA6-12")
        XCTAssertEqual(report.summaryStatement, "1 code concern identified")
        XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("safe"))
        XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("compliant"))
        XCTAssertEqual(model.cachedComplianceReport, report)
        XCTAssertEqual(model.drawingData.permitMeta?.jurisdictionId, "US-IRC")
        XCTAssertEqual(model.drawingData.permitMeta?.codeEdition, "IRC 2021 / DCA6-12")
        XCTAssertEqual(model.drawingData.permitMeta?.disclaimerAcknowledgedAt, anchorDate)
        XCTAssertEqual(model.drawingData.permitMeta?.lastComplianceRunAt, report.generatedAt)
        XCTAssertTrue(model.shouldSurfacePEStampRequest)
        XCTAssertEqual(persisted.last?.permitMeta?.lastComplianceResult, report)
    }

    func testFullModelRegatesDisclaimerWhenPackageEditionChanges() throws {
        let model = DeckDrawingEditorModel(
            drawingData: DeckDrawingData(),
            capabilities: .full
        )

        XCTAssertTrue(model.acknowledgeComplianceDisclaimer(for: package(), at: anchorDate))
        XCTAssertFalse(model.requiresComplianceDisclaimer(for: package()))
        XCTAssertTrue(model.requiresComplianceDisclaimer(for: newerPackage()))
    }

    func testFullModelGeneratesPermitSetAndCachesReportAfterDisclaimer() throws {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: drawingDataWithOutOfEnvelopeMember(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        XCTAssertTrue(model.acknowledgeComplianceDisclaimer(for: package(), at: anchorDate))
        let pdf = try XCTUnwrap(model.generatePermitSet(
            sheets: [.planView, .framingPlan],
            titleBlock: titleBlock(),
            package: package()
        ))

        XCTAssertGreaterThan(pdf.count, 0)
        XCTAssertNotNil(model.cachedComplianceReport)
        XCTAssertEqual(model.cachedComplianceReport?.packageEdition, "IRC 2021 / DCA6-12")
        XCTAssertEqual(persisted.last?.permitMeta?.lastComplianceResult, model.cachedComplianceReport)
    }

    func testFullModelPersistsPEStampRequestAndAsBuiltWizardState() {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: DeckDrawingData(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        XCTAssertTrue(model.openAsBuiltWizard())
        XCTAssertTrue(model.isAsBuiltAuditWizardPresented)
        model.closeAsBuiltWizard()
        XCTAssertFalse(model.isAsBuiltAuditWizardPresented)

        XCTAssertTrue(model.requestPEStamp(reason: "Beam calc review", requestedAt: anchorDate))
        XCTAssertEqual(model.drawingData.permitMeta?.peStampRequest?.requested, true)
        XCTAssertEqual(model.drawingData.permitMeta?.peStampRequest?.reason, "Beam calc review")
        XCTAssertEqual(model.drawingData.permitMeta?.peStampRequest?.requestedAt, anchorDate)
        XCTAssertEqual(persisted.last?.permitMeta?.peStampRequest, model.drawingData.permitMeta?.peStampRequest)
    }

    private var anchorDate: Date {
        Date(timeIntervalSince1970: 1_801_440_000)
    }

    private func drawingDataWithOutOfEnvelopeMember() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(
                    levelId: "level-main",
                    members: [
                        FramingMember(
                            id: "beam-overspan",
                            role: .beam,
                            start: .zero,
                            end: CGPoint(x: 240, y: 0),
                            nominalSize: .twoByEight,
                            spacingInchesOC: 16,
                            species: .sprucePineFir,
                            grade: .no2,
                            sizing: MemberSizingResult(
                                outcome: .outOfEnvelope(
                                    reason: "Beam span exceeds packaged table envelope.",
                                    citation: citation()
                                )
                            )
                        ),
                    ]
                ),
            ],
            generationSource: .manual
        )
        return data
    }

    private func package() -> CodePackage {
        CodePackage(
            jurisdictionId: "US-IRC",
            edition: "IRC 2021 / DCA6-12",
            publishedDate: Date(timeIntervalSince1970: 0)
        )
    }

    private func newerPackage() -> CodePackage {
        CodePackage(
            jurisdictionId: "US-IRC",
            edition: "IRC 2024 / DCA6-15",
            publishedDate: Date(timeIntervalSince1970: 0)
        )
    }

    private func titleBlock() -> TitleBlock {
        TitleBlock(
            projectName: "Permit test deck",
            address: "123 Test St",
            packageEdition: "IRC 2021 / DCA6-12",
            generatedDate: anchorDate,
            disclaimer: ComplianceStrings.disclaimer
        )
    }

    private func citation() -> EngineCitation {
        EngineCitation(
            limitingCheck: "span table",
            codeSection: "AWC DCA6 Table 3",
            packageEdition: "IRC 2021 / DCA6-12"
        )
    }
}
