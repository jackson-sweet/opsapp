import CoreGraphics
import Foundation
import PDFKit
import XCTest
@testable import DeckKit

final class PlanSetEngineTests: XCTestCase {
    func testPermitSetPageCountMatchesSheets() throws {
        let pdf = PlanSetEngine.renderPermitSet(
            Self.deck(),
            compliance: Self.report(),
            sheets: [.planView, .framingPlan, .crossSection],
            titleBlock: Self.titleBlock(),
            package: Self.package()
        )
        let document = try XCTUnwrap(PDFDocument(data: pdf))

        XCTAssertEqual(document.pageCount, 4)
    }

    func testEveryPermitSetPageStampsDisclaimerAndCodeCurrency() throws {
        let pdf = PlanSetEngine.renderPermitSet(
            Self.deck(),
            compliance: Self.report(),
            sheets: [.sitePlan, .detailCallout],
            titleBlock: Self.titleBlock(),
            package: Self.package()
        )
        let document = try XCTUnwrap(PDFDocument(data: pdf))

        for pageIndex in 0..<document.pageCount {
            let text = document.page(at: pageIndex)?.string ?? ""
            Self.assertDisclaimerPresent(in: text, pageIndex: pageIndex)
        }
        XCTAssertTrue((document.string ?? "").contains("CODE DATA CURRENT TO 2026-06-01"))
    }

    func testRenderSheetProducesSinglePagePDFWithDisclaimer() throws {
        let pdf = PlanSetEngine.renderSheet(
            .planView,
            data: Self.deck(),
            scale: DrawingScale(inchesPerFoot: 0.25),
            titleBlock: Self.titleBlock()
        )
        let document = try XCTUnwrap(PDFDocument(data: pdf))

        XCTAssertEqual(document.pageCount, 1)
        Self.assertDisclaimerPresent(in: document.string ?? "", pageIndex: 0)
    }

    func testCalcReportSurfacesAssumptionsMemberRowsAndFootings() throws {
        let pdf = PlanSetEngine.renderCalcReport(
            Self.deck().framing!,
            footings: Self.deck().footings!,
            package: Self.package()
        )
        let text = try XCTUnwrap(PDFDocument(data: pdf)?.string)

        XCTAssertTrue(text.contains("IRC 2021 / DCA6-12"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("live load"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("utilization"))
        XCTAssertTrue(text.contains("DCA6 Table 2"))
        XCTAssertTrue(text.contains("ABU66"))
    }

    func testEmptyDataReturnsValidNonEmptyPDFWithPlaceholder() throws {
        let pdf = PlanSetEngine.renderPermitSet(
            DeckDrawingData(),
            compliance: Self.report(findings: []),
            sheets: [.planView],
            titleBlock: Self.titleBlock(),
            package: Self.package()
        )
        let document = try XCTUnwrap(PDFDocument(data: pdf))

        XCTAssertGreaterThan(pdf.count, 1_000)
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue((document.string ?? "").contains("DECK GEOMETRY NOT PROVIDED"))
    }

    private static func titleBlock() -> TitleBlock {
        TitleBlock(
            projectName: "Permit deck",
            address: "123 Permit Ave",
            packageEdition: "IRC 2021 / DCA6-12",
            generatedDate: Date(timeIntervalSince1970: 1_800),
            disclaimer: ComplianceStrings.disclaimer,
            peStamp: PEStampRequest(requested: true, reason: "Permit package")
        )
    }

    private static func normalized(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func assertDisclaimerPresent(in text: String, pageIndex: Int) {
        let normalizedText = normalized(text)
        XCTAssertTrue(
            normalizedText.contains("This is not a guarantee of full code adherence"),
            "page \(pageIndex) omitted disclaimer opening"
        )
        XCTAssertTrue(
            normalizedText.contains("Have plans reviewed by"),
            "page \(pageIndex) omitted review advisory"
        )
        XCTAssertTrue(
            normalizedText.contains("licensed engineer in your jurisdiction."),
            "page \(pageIndex) omitted engineer advisory"
        )
    }

    private static func report(findings: [ComplianceFinding]? = nil) -> ComplianceReport {
        ComplianceReport(
            mode: .design,
            packageEdition: "IRC 2021 / DCA6-12",
            generatedAt: Date(timeIntervalSince1970: 2_400),
            findings: findings ?? [
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

    private static func package() -> CodePackage {
        CodePackage(
            jurisdictionId: "US-IRC",
            edition: "IRC 2021 / DCA6-12",
            publishedDate: Date(timeIntervalSince1970: 1_780_272_000)
        )
    }

    private static func deck() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0), elevation: 5),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0), elevation: 5),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 120), elevation: 5),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120), elevation: 5)
        ]
        data.edges = [
            DeckEdge(id: "house", startVertexId: "v1", endVertexId: "v2", edgeType: .houseEdge, dimension: 144),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3", dimension: 120),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4", dimension: 144),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1", dimension: 120)
        ]
        data.scaleFactor = 1
        data.overallElevation = 5
        data.house = HouseModel(floorLineFeet: 5, storyHeights: [9])
        data.terrain = TerrainModel(
            gradePoints: [GradePoint(position: CGPoint(x: 72, y: 120), dropFeet: 5)],
            slopeSource: .manual
        )
        data.footings = FootingPlan(
            footings: [
                Footing(
                    id: "f1",
                    position: CGPoint(x: 0, y: 120),
                    diameterInches: 12,
                    depthInches: 48,
                    connection: PostFootingConnection(hardwareModel: "ABU66", upliftRated: true)
                )
            ],
            soil: SoilInput(bearingCapacityPSF: 1_500),
            frost: FrostInput(depthInches: 42)
        )
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(
                    levelId: "",
                    members: [
                        FramingMember(
                            id: "joist-1",
                            role: .joist,
                            start: CGPoint(x: 0, y: 0),
                            end: CGPoint(x: 0, y: 120),
                            nominalSize: .twoByEight,
                            spacingInchesOC: 16,
                            sizing: Self.memberSizing(role: .joist)
                        ),
                        FramingMember(
                            id: "beam-1",
                            role: .beam,
                            start: CGPoint(x: 0, y: 120),
                            end: CGPoint(x: 144, y: 120),
                            nominalSize: .twoByTen,
                            plyCount: 2,
                            sizing: Self.memberSizing(role: .beam)
                        )
                    ]
                )
            ],
            loadPreset: LoadPreset(),
            generationSource: .auto
        )
        data.permitMeta = PermitMeta(
            setbacks: SetbackInput(
                propertyLines: [CGPoint(x: -60, y: -60), CGPoint(x: 204, y: -60), CGPoint(x: 204, y: 180), CGPoint(x: -60, y: 180)],
                requiredSetbackFeet: 5,
                ahjVerified: false
            )
        )
        return data
    }

    private static func memberSizing(role: FramingRole) -> MemberSizingResult {
        MemberSizingResult(
            outcome: .ok(
                value: SizedMember(
                    size: role == .beam ? .twoByTen : .twoByEight,
                    plyCount: role == .beam ? 2 : 1,
                    allowableSpanFeet: 12,
                    actualSpanFeet: 10,
                    utilization: 0.83
                ),
                citation: EngineCitation(
                    limitingCheck: "span",
                    codeSection: "DCA6 Table 2",
                    packageEdition: "IRC 2021 / DCA6-12"
                ),
                assumptions: EngineAssumptions(
                    liveLoadPSF: 40,
                    deadLoadPSF: 10,
                    snowLoadPSF: nil,
                    species: .sprucePineFir,
                    grade: .no2,
                    soilBearingPSF: 1_500,
                    packageEdition: "IRC 2021 / DCA6-12"
                )
            )
        )
    }
}
