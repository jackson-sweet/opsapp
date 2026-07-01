import Foundation
import XCTest
@testable import DeckKit

final class ComplianceModelsTests: XCTestCase {
    func testComplianceStringsRemainLegallyLocked() {
        XCTAssertEqual(ComplianceStrings.noFailures, "no code failures detected")
        XCTAssertEqual(
            ComplianceStrings.disclaimer,
            "This is not a guarantee of full code adherence. Have plans reviewed by a licensed engineer in your jurisdiction."
        )
    }

    func testComplianceReportRoundTripsWithModeFindingsEvidenceAndDisclaimer() throws {
        let report = ComplianceReport(
            mode: .asBuilt,
            packageEdition: "IRC 2021 / DCA6-12",
            generatedAt: Date(timeIntervalSince1970: 1_788_220_800),
            findings: [
                ComplianceFinding(
                    id: "finding-ledger-hidden",
                    item: "Ledger fasteners",
                    severity: .notAssessable,
                    currentValue: nil,
                    targetValue: nil,
                    codeSection: "IRC R507.9",
                    fix: "Verify concealed ledger fasteners on site.",
                    confidence: .low,
                    evidence: Evidence(
                        photoURL: URL(string: "https://example.test/ledger.jpg"),
                        sceneRef: "scan:ledger-west"
                    ),
                    source: .notAssessable
                )
            ],
            summaryStatement: "1 code concern identified",
            disclaimer: ComplianceStrings.disclaimer
        )

        let encoded = try JSONEncoder.sorted.encode(report)
        let decoded = try JSONDecoder().decode(ComplianceReport.self, from: encoded)

        XCTAssertEqual(decoded, report)
        XCTAssertFalse(decoded.summaryStatement.localizedCaseInsensitiveContains("safe"))
        XCTAssertFalse(decoded.summaryStatement.localizedCaseInsensitiveContains("compliant"))
    }

    func testEmptyDesignEvaluationUsesLockedNoFailureSummaryAndDisclaimer() {
        let package = CodePackage(edition: "IRC 2021 / DCA6-12")

        let report = ComplianceEngine.evaluate(DeckDrawingData(), mode: .design, package: package)

        XCTAssertEqual(report.mode, .design)
        XCTAssertEqual(report.packageEdition, "IRC 2021 / DCA6-12")
        XCTAssertEqual(report.summaryStatement, ComplianceStrings.noFailures)
        XCTAssertEqual(report.disclaimer, ComplianceStrings.disclaimer)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("safe"))
        XCTAssertFalse(report.summaryStatement.localizedCaseInsensitiveContains("compliant"))
    }
}
