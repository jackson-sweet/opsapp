// OPS/OPSTests/DeckBuilder/EstimateGeneratorServiceTests.swift

import CoreGraphics
import XCTest
@testable import DeckKit

final class EstimateGeneratorServiceTests: XCTestCase {

    // MARK: - Helper

    private func makeRectangleDeck(
        lengthInches: Double = 288,  // 24'
        depthInches: Double = 192,   // 16'
        withVinyl: Bool = true,
        withGlassRailing: Bool = false,
        withStairs: Bool = false
    ) -> DeckDrawingData {
        var data = DeckTemplateEngine.generate(
            template: .rectangle,
            dimensions: [lengthInches, depthInches]
        )!

        if withVinyl {
            data.footprint.assignedItems.append(AssignedItem(
                name: "Vinyl Decking",
                unitType: .squareFoot,
                unitPrice: 8.50
            ))
        }

        if withGlassRailing {
            // Add glass railing to edges 1 and 3 (right and left sides = depth edges)
            for i in [1, 3] where i < data.edges.count {
                data.edges[i].railingConfig = RailingConfig(
                    railingType: .glass,
                    maxPostSpacing: 60 // 5'
                )
            }
        }

        if withStairs {
            // Add stairs to edge 2 (bottom edge) with explicit tread count override
            if data.edges.count > 2 {
                data.edges[2].stairConfig = StairConfig(
                    width: 48, // 4'
                    treadCount: 4
                )
            }
            data.overallElevation = 2.5 // 2.5 feet = 30 inches
        }

        return data
    }

    // MARK: - Surface Items

    func testSurfaceLineItem_vinylDecking() {
        let data = makeRectangleDeck(withVinyl: true)
        let items = EstimateGeneratorService.generateLineItems(from: data)

        let surfaceItems = items.filter { $0.category == "Surface" }
        XCTAssertEqual(surfaceItems.count, 1)
        XCTAssertEqual(surfaceItems[0].name, "Vinyl Decking")
        XCTAssertEqual(surfaceItems[0].unit, "sq ft")
        XCTAssertEqual(surfaceItems[0].unitPrice, 8.50)
        XCTAssertEqual(surfaceItems[0].type, .material)
        // 24' x 16' = 384 sqft (template creates at scale, so area depends on polygon math)
        XCTAssertGreaterThan(surfaceItems[0].quantity, 300) // rough check
    }

    // MARK: - Railing Items

    func testRailingLineItems_glassRailing() {
        let data = makeRectangleDeck(withGlassRailing: true)
        let items = EstimateGeneratorService.generateLineItems(from: data)

        let railingItems = items.filter { $0.category == "Railing" }
        // Should have railing material + posts for each railing edge
        XCTAssertGreaterThanOrEqual(railingItems.count, 4) // 2 edges x (railing + posts)

        let materialItems = railingItems.filter { $0.name.contains("Railing") && !$0.name.contains("Posts") }
        XCTAssertEqual(materialItems.count, 2) // two depth edges

        let postItems = railingItems.filter { $0.name.contains("Posts") }
        XCTAssertEqual(postItems.count, 2)
        XCTAssertEqual(postItems[0].unit, "each")
    }

    // MARK: - Stair Items

    func testStairLineItems() {
        let data = makeRectangleDeck(withStairs: true)
        let items = EstimateGeneratorService.generateLineItems(from: data)

        let stairItems = items.filter { $0.category == "Stairs" }
        XCTAssertGreaterThanOrEqual(stairItems.count, 2) // treads + stringers at minimum

        let treads = stairItems.first { $0.name == "Stair Treads" }
        XCTAssertNotNil(treads)
        XCTAssertEqual(treads?.quantity, 4) // 4 treads (from treadCount override)

        let stringers = stairItems.first { $0.name == "Stair Stringers" }
        XCTAssertNotNil(stringers)
        XCTAssertGreaterThanOrEqual(stringers?.quantity ?? 0, 2) // at least 2 stringers
    }

    // MARK: - Substructure Items

    func testFootingLineItems() {
        var data = makeRectangleDeck(withVinyl: false)
        // Assign footings to vertices
        for i in 0..<data.vertices.count {
            data.vertices[i].footingType = .helicalPile
        }
        let items = EstimateGeneratorService.generateLineItems(from: data)

        let subItems = items.filter { $0.category == "Substructure" }
        XCTAssertEqual(subItems.count, 1) // one type: helical pile
        XCTAssertEqual(subItems[0].name, "Helical Pile")
        XCTAssertEqual(subItems[0].quantity, Double(data.vertices.count))
        XCTAssertEqual(subItems[0].unit, "each")
    }

    // MARK: - Framing Items

    func testFramingLineItems_fromFramingPlan() throws {
        var data = makeRectangleDeck(withVinyl: false)
        data.scaleFactor = 1.0
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(levelId: "", members: [
                    framingMember(
                        id: "joist-0",
                        role: .joist,
                        start: .zero,
                        end: CGPoint(x: 120, y: 0),
                        nominalSize: .twoByEight
                    ),
                    framingMember(
                        id: "beam-0",
                        role: .beam,
                        start: CGPoint(x: 0, y: 120),
                        end: CGPoint(x: 120, y: 120),
                        nominalSize: .twoByTen,
                        plyCount: 2
                    ),
                    framingMember(
                        id: "post-0",
                        role: .post,
                        start: CGPoint(x: 0, y: 120),
                        end: CGPoint(x: 0, y: 120),
                        nominalSize: .sixBySix
                    ),
                ])
            ],
            generationSource: .manual
        )

        let items = EstimateGeneratorService.generateLineItems(from: data)
        let framingItems = items.filter { $0.category == "Framing" }

        XCTAssertFalse(framingItems.isEmpty)
        let joists = try XCTUnwrap(framingItems.first { $0.name == "2x8 Joists" })
        XCTAssertEqual(joists.quantity, 11.0, accuracy: 0.001)
        XCTAssertEqual(joists.unit, "linear ft")
        XCTAssertEqual(joists.type, .material)
        XCTAssertFalse(joists.isOptional)

        XCTAssertNotNil(framingItems.first { $0.name == "Joist Hangers" })
        XCTAssertNotNil(framingItems.first { $0.name == "Post Bases" })
        XCTAssertNotNil(framingItems.first { $0.name == "Framing Footings" })
    }

    // MARK: - No Assignments

    func testHasAssignments_emptyDrawing() {
        let data = DeckDrawingData()
        XCTAssertFalse(EstimateGeneratorService.hasAssignments(data))
    }

    func testHasAssignments_withVinyl() {
        let data = makeRectangleDeck(withVinyl: true)
        XCTAssertTrue(EstimateGeneratorService.hasAssignments(data))
    }

    func testHasAssignments_withRailing() {
        let data = makeRectangleDeck(withVinyl: false, withGlassRailing: true)
        XCTAssertTrue(EstimateGeneratorService.hasAssignments(data))
    }

    func testHasAssignments_withFooting() {
        var data = DeckDrawingData()
        data.vertices.append(DeckVertex(position: .zero))
        data.vertices[0].footingType = .sonoTube
        XCTAssertTrue(EstimateGeneratorService.hasAssignments(data))
    }

    func testHasAssignments_withFraming() {
        var data = DeckDrawingData()
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(levelId: "", members: [
                    framingMember(
                        id: "joist-0",
                        role: .joist,
                        start: .zero,
                        end: CGPoint(x: 120, y: 0),
                        nominalSize: .twoByEight
                    )
                ])
            ],
            generationSource: .manual
        )

        XCTAssertTrue(EstimateGeneratorService.hasAssignments(data))
    }

    // MARK: - Material Summary

    func testMaterialSummary_notEmpty() {
        let data = makeRectangleDeck(withVinyl: true, withGlassRailing: true)
        let summary = EstimateGeneratorService.materialSummary(from: data)
        XCTAssertTrue(summary.contains("Deck Estimate Summary"))
        XCTAssertTrue(summary.contains("Vinyl Decking"))
        XCTAssertTrue(summary.contains("Glass Railing"))
    }

    func testMaterialSummary_empty() {
        let data = DeckDrawingData()
        let summary = EstimateGeneratorService.materialSummary(from: data)
        XCTAssertEqual(summary, "No materials assigned")
    }

    // MARK: - AR Accuracy Note

    func testARAccuracyNote_noAR() {
        let data = makeRectangleDeck()
        XCTAssertNil(EstimateGeneratorService.arAccuracyNote(from: data))
    }

    func testARAccuracyNote_withAR() {
        var data = makeRectangleDeck()
        data.edges[0].accuracyPercent = 3.0
        let note = EstimateGeneratorService.arAccuracyNote(from: data)
        XCTAssertNotNil(note)
        XCTAssertTrue(note!.contains("\u{00B1}3%"))
    }

    // MARK: - Line Item Ordering

    func testLineItemOrdering_surfaceFirst() {
        let data = makeRectangleDeck(withVinyl: true, withGlassRailing: true, withStairs: true)
        let items = EstimateGeneratorService.generateLineItems(from: data)

        // Surface should come first
        guard let firstSurface = items.firstIndex(where: { $0.category == "Surface" }),
              let firstRailing = items.firstIndex(where: { $0.category == "Railing" }),
              let firstStairs = items.firstIndex(where: { $0.category == "Stairs" }) else {
            XCTFail("Missing categories")
            return
        }
        XCTAssertLessThan(firstSurface, firstRailing)
        XCTAssertLessThan(firstRailing, firstStairs)
    }

    // MARK: - Area & Perimeter

    func testCalculatePerimeterFt() {
        var data = DeckDrawingData()
        let v1 = DeckVertex(position: .zero)
        let v2 = DeckVertex(position: CGPoint(x: 100, y: 0))
        data.vertices = [v1, v2]
        var edge = DeckEdge(startVertexId: v1.id, endVertexId: v2.id)
        edge.dimension = 120 // 10 feet
        data.edges = [edge]

        let perimeterFt = EstimateGeneratorService.calculatePerimeterFt(drawingData: data)
        XCTAssertEqual(perimeterFt, 10.0, accuracy: 0.01)
    }

    // MARK: - Edge Assigned Items

    func testEdgeAssignedItems() {
        var data = makeRectangleDeck(withVinyl: false)
        // Add a linear foot item to edge 0
        data.edges[0].assignedItems.append(AssignedItem(
            name: "LED Strip Light",
            unitType: .linearFoot,
            unitPrice: 12.00
        ))
        let items = EstimateGeneratorService.generateLineItems(from: data)

        let otherItems = items.filter { $0.category == "Other" }
        XCTAssertEqual(otherItems.count, 1)
        XCTAssertEqual(otherItems[0].name, "LED Strip Light")
        XCTAssertEqual(otherItems[0].unit, "linear ft")
        XCTAssertEqual(otherItems[0].unitPrice, 12.00)
    }

    private func framingMember(
        id: String,
        role: FramingRole,
        start: CGPoint,
        end: CGPoint,
        nominalSize: LumberSize,
        plyCount: Int = 1
    ) -> FramingMember {
        FramingMember(
            id: id,
            role: role,
            start: start,
            end: end,
            nominalSize: nominalSize,
            plyCount: plyCount,
            species: .sprucePineFir,
            grade: .no2
        )
    }
}
