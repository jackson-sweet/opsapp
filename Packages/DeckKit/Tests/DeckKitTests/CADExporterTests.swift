import CoreGraphics
import Foundation
import PDFKit
import XCTest
@testable import DeckKit

final class CADExporterTests: XCTestCase {
    func testVectorPDFReturnsPermitSetWithoutClaimingUncheckedCompliance() throws {
        let result = CADExporter.export(
            Self.deck(),
            format: .vectorPDF,
            sheets: [.planView],
            titleBlock: Self.titleBlock(),
            package: Self.package()
        )

        guard case let .data(pdf) = result else {
            return XCTFail("Expected vector PDF data")
        }
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let text = document.string ?? ""

        XCTAssertGreaterThan(pdf.count, 1_000)
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("code check not run"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("safe"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("compliant"))
    }

    func testVectorPDFUsesCachedComplianceReportWhenPackageEditionMatches() throws {
        var deck = Self.deck()
        deck.permitMeta = PermitMeta(lastComplianceResult: Self.report())

        let result = CADExporter.export(
            deck,
            format: .vectorPDF,
            sheets: [.planView],
            titleBlock: Self.titleBlock(),
            package: Self.package()
        )

        guard case let .data(pdf) = result else {
            return XCTFail("Expected vector PDF data")
        }
        let text = try XCTUnwrap(PDFDocument(data: pdf)?.string)

        XCTAssertTrue(text.contains("1 code concern found"))
        XCTAssertTrue(text.contains("DCA6 Table 2"))
    }

    func testDWGAndDXFReturnPaidConverterRequirement() {
        for format in [CADExportFormat.dwg, .dxf] {
            let result = CADExporter.export(
                Self.deck(),
                format: format,
                sheets: [.planView],
                titleBlock: Self.titleBlock(),
                package: Self.package()
            )

            guard case let .requiresPaidConverter(actualFormat, note) = result else {
                return XCTFail("Expected paid converter requirement for \(format)")
            }
            XCTAssertEqual(actualFormat, format)
            XCTAssertTrue(note.localizedCaseInsensitiveContains("paid CAD converter"))
            XCTAssertTrue(note.localizedCaseInsensitiveContains("cost approval"))
        }
    }

    private static func titleBlock() -> TitleBlock {
        TitleBlock(
            projectName: "CAD export deck",
            address: "123 Export Ave",
            packageEdition: "IRC 2021 / DCA6-12",
            generatedDate: Date(timeIntervalSince1970: 1_800),
            disclaimer: ComplianceStrings.disclaimer,
            peStamp: nil
        )
    }

    private static func package() -> CodePackage {
        CodePackage(
            jurisdictionId: "US-IRC",
            edition: "IRC 2021 / DCA6-12",
            publishedDate: Date(timeIntervalSince1970: 1_780_272_000)
        )
    }

    private static func report() -> ComplianceReport {
        ComplianceReport(
            mode: .design,
            packageEdition: "IRC 2021 / DCA6-12",
            generatedAt: Date(timeIntervalSince1970: 2_400),
            findings: [
                ComplianceFinding(
                    id: "structural:joist:span",
                    item: "joist span",
                    severity: .marginal,
                    currentValue: "13′-0″",
                    targetValue: "12′-0″",
                    codeSection: "DCA6 Table 2",
                    fix: "Reduce span or resize joist.",
                    confidence: .high,
                    evidence: nil,
                    source: .measured
                )
            ],
            summaryStatement: "1 code concern found",
            disclaimer: ComplianceStrings.disclaimer
        )
    }

    private static func deck() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0), elevation: 4),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0), elevation: 4),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 120), elevation: 4),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120), elevation: 4)
        ]
        data.edges = [
            DeckEdge(id: "house", startVertexId: "v1", endVertexId: "v2", edgeType: .houseEdge, dimension: 144),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3", dimension: 120),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4", dimension: 144),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1", dimension: 120)
        ]
        return data
    }
}
