import Foundation
import XCTest
@testable import DeckKit

final class ComplianceLedgerChecksTests: XCTestCase {
    func testOlderPackagesDecodeDefaultLedgerRules() throws {
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

        XCTAssertEqual(decoded.ledgerRules.codeSection, "IRC R507.9")
        XCTAssertEqual(decoded.ledgerRules.minLateralConnectors, 2)
    }

    func testDisallowedLedgerAttachmentRoutesFreestandingFinding() throws {
        let findings = LedgerChecks.evaluate(
            drawingData(
                ledger: LedgerDetail(
                    cladding: .brick,
                    attachmentAllowed: false,
                    fastenerSchedule: nil,
                    lateralConnectors: nil
                )
            ),
            mode: .design,
            package: package(ledgerRules: LedgerRules(codeSection: "TEST R507.9"))
        )

        let finding = try XCTUnwrap(findings.first { $0.id == "ledger:attachment" })
        XCTAssertEqual(finding.item, "Ledger attachment")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "brick")
        XCTAssertEqual(finding.targetValue, "freestanding required")
        XCTAssertEqual(finding.codeSection, "TEST R507.9")
        XCTAssertEqual(finding.source, .measured)
        XCTAssertTrue(finding.fix?.localizedCaseInsensitiveContains("freestanding") ?? false)
    }

    func testDesignMissingFastenerScheduleIsNotAssessable() throws {
        let findings = LedgerChecks.evaluate(
            drawingData(
                ledger: LedgerDetail(
                    cladding: .stucco,
                    attachmentAllowed: true,
                    fastenerSchedule: nil,
                    lateralConnectors: 2
                )
            ),
            mode: .design,
            package: package(ledgerRules: LedgerRules(codeSection: "TEST R507.9"))
        )

        let finding = try XCTUnwrap(findings.first { $0.id == "ledger:fastener-schedule" })
        XCTAssertEqual(finding.item, "Ledger fasteners")
        XCTAssertEqual(finding.severity, .notAssessable)
        XCTAssertNil(finding.currentValue)
        XCTAssertNil(finding.targetValue)
        XCTAssertEqual(finding.codeSection, "TEST R507.9")
        XCTAssertEqual(finding.source, .notAssessable)
        XCTAssertTrue(finding.fix?.localizedCaseInsensitiveContains("fastener schedule") ?? false)
    }

    func testAsBuiltConcealedLedgerDetailsAreNotAssessable() throws {
        let report = ComplianceEngine.evaluate(
            drawingData(
                ledger: LedgerDetail(
                    cladding: .stucco,
                    attachmentAllowed: true,
                    fastenerSchedule: "1/2\" through-bolts @ 16\" o.c.",
                    lateralConnectors: 2
                )
            ),
            mode: .asBuilt,
            package: package(ledgerRules: LedgerRules(codeSection: "TEST R507.9"))
        )

        XCTAssertNotEqual(report.summaryStatement, ComplianceStrings.noFailures)
        XCTAssertTrue(report.findings.contains { finding in
            finding.id == "ledger:fastener-schedule"
                && finding.severity == .notAssessable
                && finding.source == .notAssessable
        })
        XCTAssertTrue(report.findings.contains { finding in
            finding.id == "ledger:lateral-connectors"
                && finding.severity == .notAssessable
                && finding.source == .notAssessable
        })
    }

    func testLateralConnectorsBelowPackageMinimumEmitsFinding() throws {
        let findings = LedgerChecks.evaluate(
            drawingData(
                ledger: LedgerDetail(
                    cladding: .stucco,
                    attachmentAllowed: true,
                    fastenerSchedule: "1/2\" through-bolts @ 16\" o.c.",
                    lateralConnectors: 1
                )
            ),
            mode: .design,
            package: package(
                ledgerRules: LedgerRules(
                    minLateralConnectors: 2,
                    codeSection: "TEST R507.9.2"
                )
            )
        )

        let finding = try XCTUnwrap(findings.first { $0.id == "ledger:lateral-connectors" })
        XCTAssertEqual(finding.item, "Ledger lateral connectors")
        XCTAssertEqual(finding.severity, .safetyHazard)
        XCTAssertEqual(finding.currentValue, "1 connector")
        XCTAssertEqual(finding.targetValue, "2 connectors minimum")
        XCTAssertEqual(finding.codeSection, "TEST R507.9.2")
        XCTAssertEqual(finding.source, .measured)
    }

    func testCompleteDesignLedgerDetailEmitsNoFindings() {
        let findings = LedgerChecks.evaluate(
            drawingData(
                ledger: LedgerDetail(
                    cladding: .stucco,
                    attachmentAllowed: true,
                    fastenerSchedule: "1/2\" through-bolts @ 16\" o.c.",
                    lateralConnectors: 2
                )
            ),
            mode: .design,
            package: package()
        )

        XCTAssertTrue(findings.isEmpty)
    }

    private func drawingData(ledger: LedgerDetail) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.house = HouseModel(ledger: ledger)
        return data
    }

    private func package(ledgerRules: LedgerRules = LedgerRules()) -> CodePackage {
        CodePackage(
            jurisdictionId: "US-IRC",
            edition: "IRC 2021 / DCA6-12",
            publishedDate: Date(timeIntervalSince1970: 0),
            ledgerRules: ledgerRules
        )
    }
}
