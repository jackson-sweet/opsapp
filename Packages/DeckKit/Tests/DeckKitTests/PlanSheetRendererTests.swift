import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

final class PlanSheetRendererTests: XCTestCase {
    func testPlanSheetKindAndTitleBlockRoundTripStable() throws {
        let titleBlock = TitleBlock(
            projectName: "Cedar landing",
            address: "123 Permit Ave",
            packageEdition: "IRC 2021 / DCA6-12",
            generatedDate: Date(timeIntervalSince1970: 1_800),
            disclaimer: ComplianceStrings.disclaimer,
            peStamp: PEStampRequest(requested: true, reason: "Beam calc review")
        )

        let encodedKinds = try JSONEncoder.sorted.encode(PlanSheetKind.allCases)
        let decodedKinds = try JSONDecoder().decode([PlanSheetKind].self, from: encodedKinds)
        let encodedTitle = try JSONEncoder.sorted.encode(titleBlock)
        let decodedTitle = try JSONDecoder().decode(TitleBlock.self, from: encodedTitle)

        XCTAssertEqual(decodedKinds, [.planView, .framingPlan, .elevation, .crossSection, .sitePlan, .detailCallout])
        XCTAssertEqual(decodedTitle, titleBlock)
    }

    func testEveryPlanSheetStampsDisclaimerAndDrawsContent() {
        for kind in PlanSheetKind.allCases {
            let bitmap = BitmapHarness(size: CGSize(width: 612, height: 792))

            let result = PlanSheetRenderer.render(
                kind,
                data: Self.fullyDocumentedDeck(),
                titleBlock: Self.titleBlock(),
                scale: DrawingScale(inchesPerFoot: 0.25),
                pageRect: CGRect(x: 0, y: 0, width: 612, height: 792),
                in: bitmap.context
            )

            XCTAssertEqual(result.kind, kind)
            XCTAssertTrue(result.titleBlockTexts.contains(ComplianceStrings.disclaimer), "\(kind) omitted disclaimer")
            XCTAssertGreaterThan(bitmap.nonTransparentPixelCount(), 500, "\(kind) rendered blank")
        }
    }

    func testFramingPlanWithoutSizingMarksNotEngineered() {
        var deck = Self.fullyDocumentedDeck()
        let unsizedSets = (deck.framing?.members ?? []).map { set in
            FramingMemberSet(
                levelId: set.levelId,
                members: set.members.map { member in
                    var unsized = member
                    unsized.sizing = nil
                    return unsized
                }
            )
        }
        deck.framing = FramingPlan(
            members: unsizedSets,
            loadPreset: LoadPreset(),
            generationSource: .manual
        )
        let bitmap = BitmapHarness(size: CGSize(width: 612, height: 792))

        let result = PlanSheetRenderer.render(
            .framingPlan,
            data: deck,
            titleBlock: Self.titleBlock(),
            scale: DrawingScale(inchesPerFoot: 0.25),
            pageRect: CGRect(x: 0, y: 0, width: 612, height: 792),
            in: bitmap.context
        )

        XCTAssertTrue(result.bodyCallouts.contains("NOT ENGINEERED"))
    }

    func testElevationAndSectionUsePlaceholdersWhenHouseOrTerrainMissing() {
        var deck = Self.fullyDocumentedDeck()
        deck.house = nil
        deck.terrain = nil
        let bitmap = BitmapHarness(size: CGSize(width: 612, height: 792))

        let elevation = PlanSheetRenderer.render(
            .elevation,
            data: deck,
            titleBlock: Self.titleBlock(),
            scale: DrawingScale(inchesPerFoot: 0.25),
            pageRect: CGRect(x: 0, y: 0, width: 612, height: 792),
            in: bitmap.context
        )
        let section = PlanSheetRenderer.render(
            .crossSection,
            data: deck,
            titleBlock: Self.titleBlock(),
            scale: DrawingScale(inchesPerFoot: 0.25),
            pageRect: CGRect(x: 0, y: 0, width: 612, height: 792),
            in: bitmap.context
        )

        XCTAssertTrue(elevation.placeholders.contains("HOUSE MODEL NOT PROVIDED"))
        XCTAssertTrue(section.placeholders.contains("TERRAIN MODEL NOT PROVIDED"))
    }

    func testSitePlanSurfacesAhjSetbackWarningAndDetailUsesFootingHardware() {
        let deck = Self.fullyDocumentedDeck()
        let bitmap = BitmapHarness(size: CGSize(width: 612, height: 792))

        let site = PlanSheetRenderer.render(
            .sitePlan,
            data: deck,
            titleBlock: Self.titleBlock(),
            scale: DrawingScale(inchesPerFoot: 0.25),
            pageRect: CGRect(x: 0, y: 0, width: 612, height: 792),
            in: bitmap.context
        )
        let detail = PlanSheetRenderer.render(
            .detailCallout,
            data: deck,
            titleBlock: Self.titleBlock(),
            scale: DrawingScale(inchesPerFoot: 0.25),
            pageRect: CGRect(x: 0, y: 0, width: 612, height: 792),
            in: bitmap.context
        )

        XCTAssertTrue(site.bodyCallouts.contains("VERIFY SETBACKS WITH AHJ"))
        XCTAssertTrue(detail.bodyCallouts.contains("ABU66"))
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

    private static func fullyDocumentedDeck() -> DeckDrawingData {
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
        data.house = HouseModel(
            floorLineFeet: 5,
            storyHeights: [9],
            openings: [
                WallOpening(
                    id: "door-1",
                    edgeId: "house",
                    kind: .sliderDoor,
                    widthInches: 72,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 36
                )
            ],
            ledger: LedgerDetail(fastenerSchedule: "1/2 in lag screws @ 16 in o.c.", lateralConnectors: 2)
        )
        data.terrain = TerrainModel(
            gradePoints: [GradePoint(position: CGPoint(x: 72, y: 120), dropFeet: 5)],
            groundCover: [
                GroundZone(
                    id: "gravel",
                    polygon: [CGPoint(x: -24, y: -24), CGPoint(x: 168, y: -24), CGPoint(x: 168, y: 144), CGPoint(x: -24, y: 144)],
                    cover: .gravel
                )
            ],
            slopeSource: .manual
        )
        data.footings = FootingPlan(
            footings: [
                Footing(
                    id: "f1",
                    position: CGPoint(x: 0, y: 120),
                    type: .sonoTube,
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
                            sizing: Self.memberSizing()
                        ),
                        FramingMember(
                            id: "beam-1",
                            role: .beam,
                            start: CGPoint(x: 0, y: 120),
                            end: CGPoint(x: 144, y: 120),
                            nominalSize: .twoByTen,
                            plyCount: 2,
                            sizing: Self.memberSizing()
                        )
                    ]
                )
            ],
            loadPreset: LoadPreset(),
            generationSource: .auto
        )
        data.permitMeta = PermitMeta(
            jurisdictionId: "US-IRC",
            codeEdition: "IRC 2021",
            setbacks: SetbackInput(
                propertyLines: [CGPoint(x: -60, y: -60), CGPoint(x: 204, y: -60), CGPoint(x: 204, y: 180), CGPoint(x: -60, y: 180)],
                requiredSetbackFeet: 5,
                ahjVerified: false
            ),
            peStampRequest: PEStampRequest(requested: true, reason: "Permit package")
        )
        return data
    }

    private static func memberSizing() -> MemberSizingResult {
        MemberSizingResult(
            outcome: .ok(
                value: SizedMember(
                    size: .twoByEight,
                    plyCount: 1,
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

private final class BitmapHarness {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    private let data: NSMutableData
    let context: CGContext

    init(size: CGSize) {
        self.width = Int(size.width)
        self.height = Int(size.height)
        self.bytesPerRow = width * 4
        self.data = NSMutableData(length: bytesPerRow * height)!
        self.context = CGContext(
            data: data.mutableBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    func nonTransparentPixelCount() -> Int {
        let bytes = data.bytes.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        return stride(from: 3, to: bytesPerRow * height, by: 4).reduce(0) { count, index in
            bytes[index] == 0 ? count : count + 1
        }
    }
}
