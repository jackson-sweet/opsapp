import CoreGraphics
import XCTest
@testable import DeckKit

final class ComponentEmitterPhase6Tests: XCTestCase {
    func testAdditivePhase6RowsEmittedWithScalarMetadata() throws {
        let data = phase6Deck()

        let rows = ComponentEmitter.emit(data)
        let types = Set(rows.map(\.componentType))

        for componentType in [
            "decking_pattern",
            "fascia",
            "skirting",
            "built_in",
            "lighting_fixture",
            "transformer",
            "fastener",
            "finish",
            "railing_part",
            "overhead_member",
            "stair_detail",
        ] {
            XCTAssertTrue(types.contains(componentType), "Missing \(componentType)")
        }

        let pattern = try XCTUnwrap(rows.first { $0.componentType == "decking_pattern" })
        XCTAssertEqual(pattern.metadata["surface_id"], AnyCodable("surface-main"))
        XCTAssertEqual(pattern.metadata["pattern"], AnyCodable("diagonal"))
        XCTAssertEqual(pattern.metadata["board_angle_degrees"], AnyCodable(45.0))
        XCTAssertEqual(pattern.metadata["picture_frame_courses"], AnyCodable(1))

        let lighting = try XCTUnwrap(rows.first { $0.componentType == "lighting_fixture" })
        XCTAssertEqual(lighting.metadata["fixture_count"], AnyCodable(2))
        XCTAssertEqual(lighting.metadata["receptacle_count"], AnyCodable(1))

        let overhead = try XCTUnwrap(rows.first { $0.componentType == "overhead_member" })
        XCTAssertEqual(overhead.metadata["structure_id"], AnyCodable("pergola-1"))
        XCTAssertEqual(overhead.metadata["kind"], AnyCodable("pergola"))
        XCTAssertEqual(overhead.metadata["role"], AnyCodable("beam"))
    }

    func testNoExistingComponentTypeRenamed() {
        let rows = ComponentEmitter.emit(phase6Deck())
        let types = Set(rows.map(\.componentType))

        XCTAssertTrue(types.contains("deck_board"))
        XCTAssertTrue(types.contains("railing"))
        XCTAssertTrue(types.contains("post_set"))
        XCTAssertTrue(types.contains("stair_set"))
    }

    func testRailingBreakdownFamilyTaggedAndScaledByEdgeLength() throws {
        let glass = RailingComponentBreakdown.parts(
            railing: RailingConfig(railingType: .glass, maxPostSpacing: 60),
            edgeLengthInches: 120,
            family: .glass
        )
        let cable = RailingComponentBreakdown.parts(
            railing: RailingConfig(railingType: .cable, maxPostSpacing: 48),
            edgeLengthInches: 120,
            family: .cable
        )

        XCTAssertEqual(Set(glass.map(\.part)), ["rail", "infill", "post", "sleeve", "cap"])
        XCTAssertTrue(glass.allSatisfy { $0.family == .glass })
        XCTAssertEqual(try XCTUnwrap(glass.first { $0.part == "rail" }?.quantity), 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(glass.first { $0.part == "post" }?.quantity), 3, accuracy: 0.001)

        XCTAssertTrue(cable.allSatisfy { $0.family == .cable })
        XCTAssertEqual(try XCTUnwrap(cable.first { $0.part == "post" }?.quantity), 4, accuracy: 0.001)
    }

    func testWasteThreadedPerPatternAtEstimateLayer() throws {
        var data = phase6Deck()
        data.wasteSettings = WasteSettings(
            defaultWastePercent: 0,
            perPatternWastePercent: ["diagonal": 15]
        )
        let spec = try XCTUnwrap(data.surfaceFeatures?.patterns.first)
        let polygon = try XCTUnwrap(data.detectedSurfaces.first?.positions)
        let raw = DeckingPatternEngine.layout(
            surfacePolygon: polygon,
            scaleFactor: data.effectiveScaleFactor,
            spec: spec,
            boardWidthInches: 5.5,
            boardLengthInches: 192,
            gapInches: 0.1875
        )

        let decking = try XCTUnwrap(
            EstimateGeneratorService.generateLineItems(from: data)
                .first { $0.category == "Decking" && $0.name == "Diagonal Decking Boards" }
        )

        XCTAssertEqual(decking.quantity, roundToTwo(Double(raw.boardCount) * 1.15), accuracy: 0.001)
        XCTAssertEqual(raw.boardCount, 84)
    }

    func testEstimateCategoriesPresentOnlyWhenDataExists() {
        let items = EstimateGeneratorService.generateLineItems(from: phase6Deck())
        let categories = Set(items.map(\.category))

        for category in [
            "Decking",
            "Fasteners",
            "Finishes",
            "Fascia/Skirting",
            "Built-Ins",
            "Lighting/Electrical",
            "Overhead",
        ] {
            XCTAssertTrue(categories.contains(category), "Missing \(category)")
        }

        let emptyCategories = Set(EstimateGeneratorService.generateLineItems(from: DeckDrawingData()).map(\.category))
        XCTAssertFalse(emptyCategories.contains("Decking"))
        XCTAssertFalse(emptyCategories.contains("Fasteners"))
        XCTAssertFalse(emptyCategories.contains("Finishes"))
        XCTAssertFalse(emptyCategories.contains("Fascia/Skirting"))
        XCTAssertFalse(emptyCategories.contains("Built-Ins"))
        XCTAssertFalse(emptyCategories.contains("Lighting/Electrical"))
        XCTAssertFalse(emptyCategories.contains("Overhead"))
    }

    private func phase6Deck() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1
        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 192, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 192, y: 144))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144))

        var e1 = DeckEdge(id: "e1", startVertexId: v1.id, endVertexId: v2.id)
        e1.dimension = 192
        e1.railingConfig = RailingConfig(railingType: .glass, maxPostSpacing: 60)

        var e2 = DeckEdge(id: "e2", startVertexId: v2.id, endVertexId: v3.id)
        e2.dimension = 144
        e2.stairConfig = StairConfig(width: 48, treadCount: 4)

        var e3 = DeckEdge(id: "e3", startVertexId: v3.id, endVertexId: v4.id)
        e3.dimension = 192

        var e4 = DeckEdge(id: "e4", startVertexId: v4.id, endVertexId: v1.id)
        e4.dimension = 144

        data.vertices = [v1, v2, v3, v4]
        data.edges = [e1, e2, e3, e4]
        data.overallElevation = 2.5
        data.surfaces = [
            DeckSurface(
                id: "surface-main",
                vertexIds: Set(data.vertices.map(\.id)),
                assignedItems: [
                    AssignedItem(name: "Composite Decking", unitType: .squareFoot),
                ],
                color: "Brown",
                boardMaterial: "composite"
            ),
        ]
        data.surfaceFeatures = SurfaceFeaturePlan(
            patterns: [
                SurfacePatternSpec(
                    surfaceId: "surface-main",
                    pattern: .diagonal,
                    boardAngleDegrees: 45,
                    pictureFrameCourses: 1
                ),
            ],
            fastenerSystem: .hiddenClip,
            finishes: [
                FinishSpec(kind: "stain", coats: 2),
            ],
            fascia: true,
            skirting: SkirtingSpec(material: "cedar", ventilated: true),
            builtIns: [
                BuiltInFeature(
                    id: "bench-1",
                    kind: .bench,
                    polygon: [
                        CGPoint(x: 12, y: 12),
                        CGPoint(x: 72, y: 12),
                        CGPoint(x: 72, y: 30),
                        CGPoint(x: 12, y: 30),
                    ],
                    heightInches: 18
                ),
            ],
            lighting: LightingPlan(
                fixtures: [
                    CGPoint(x: 12, y: 12),
                    CGPoint(x: 180, y: 132),
                ],
                transformerWatts: 60,
                receptacles: [
                    CGPoint(x: 96, y: 0),
                ]
            )
        )
        data.overhead = OverheadStructurePlan(
            structures: [
                OverheadStructure(
                    id: "pergola-1",
                    kind: .pergola,
                    footprint: [
                        CGPoint(x: 0, y: 0),
                        CGPoint(x: 120, y: 0),
                        CGPoint(x: 120, y: 96),
                        CGPoint(x: 0, y: 96),
                    ],
                    framing: [
                        FramingMember(
                            id: "overhead-beam-1",
                            role: .beam,
                            start: CGPoint(x: 0, y: 0),
                            end: CGPoint(x: 120, y: 0),
                            nominalSize: .twoByTen,
                            plyCount: 2,
                            species: .douglasFirLarch,
                            grade: .no1
                        ),
                    ],
                    shadePercent: 45
                ),
            ]
        )

        return data
    }

    private func roundToTwo(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
