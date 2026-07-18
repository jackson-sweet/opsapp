// OPSTests/DeckBuilder/DeckMaterialsEngineTests.swift
//
// Exact-number coverage for the materials engine (spec § 6 / § 10): flashing
// classification (house / parapet / interior seam / stair / open), stick + glue
// rounding, zero-class semantics, multi-level sum, and drift-key stability.

import CoreGraphics
import XCTest
@testable import OPS

final class DeckMaterialsEngineTests: XCTestCase {

    private let defaults = DeckMaterialsSettings()

    // MARK: - Fixtures

    /// 12'×20' rect (144"×240", scale 1). Optionally flag one edge house/parapet.
    private func rectInput(houseEdgeIndex: Int? = nil, parapetIndex: Int? = nil) -> VinylOrderSurfaceInput {
        let p = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 144, y: 0),
            CGPoint(x: 144, y: 240),
            CGPoint(x: 0, y: 240)
        ]
        let dims = [144.0, 240.0, 144.0, 240.0]
        let ids = ["v1", "v2", "v3", "v4"]
        let edges = (0..<4).map { i -> VinylOrderSurfaceEdge in
            let next = (i + 1) % 4
            return VinylOrderSurfaceEdge(
                id: "e\(i + 1)",
                start: p[i],
                end: p[next],
                edgeType: houseEdgeIndex == i ? .houseEdge : .deckEdge,
                label: nil,
                startVertexId: ids[i],
                endVertexId: ids[next],
                isParapet: parapetIndex == i,
                dimensionInches: dims[i]
            )
        }
        return VinylOrderSurfaceInput(id: "s1", label: "Main", levelName: nil, positions: p, scaleFactor: 1.0, edges: edges)
    }

    private func singleOpenEdgeInput(inches: Double) -> VinylOrderSurfaceInput {
        VinylOrderSurfaceInput(
            id: "s1", label: "S", levelName: nil,
            positions: [CGPoint(x: 0, y: 0), CGPoint(x: inches, y: 0)],
            scaleFactor: 1.0,
            edges: [
                VinylOrderSurfaceEdge(
                    id: "e1",
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: inches, y: 0),
                    edgeType: .deckEdge,
                    label: nil,
                    startVertexId: "a",
                    endVertexId: "b",
                    isParapet: false,
                    dimensionInches: inches
                )
            ]
        )
    }

    private func rectAreaInput(width: Double, height: Double) -> VinylOrderSurfaceInput {
        VinylOrderSurfaceInput(
            id: "s1", label: "S", levelName: nil,
            positions: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: width, y: 0),
                CGPoint(x: width, y: height),
                CGPoint(x: 0, y: height)
            ],
            scaleFactor: 1.0,
            edges: []
        )
    }

    /// 10'×10' square (120"×120", scale 1), four deck edges, one closed face.
    private func singleSquareData() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120))
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        ]
        return data
    }

    /// Two 10'×10' squares sharing the v2–v3 edge (one interior seam).
    private func twoSquaresSharingEdge() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120)),
            DeckVertex(id: "v5", position: CGPoint(x: 240, y: 0)),
            DeckVertex(id: "v6", position: CGPoint(x: 240, y: 120))
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"), // shared seam
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
            DeckEdge(id: "e5", startVertexId: "v2", endVertexId: "v5"),
            DeckEdge(id: "e6", startVertexId: "v5", endVertexId: "v6"),
            DeckEdge(id: "e7", startVertexId: "v6", endVertexId: "v3")
        ]
        return data
    }

    private func twoLevelData() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0

        var lower = DeckLevel(name: "Lower")
        lower.vertices = [
            DeckVertex(id: "a1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "a2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "a3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "a4", position: CGPoint(x: 0, y: 120))
        ]
        lower.edges = [
            DeckEdge(id: "a-e1", startVertexId: "a1", endVertexId: "a2"),
            DeckEdge(id: "a-e2", startVertexId: "a2", endVertexId: "a3"),
            DeckEdge(id: "a-e3", startVertexId: "a3", endVertexId: "a4"),
            DeckEdge(id: "a-e4", startVertexId: "a4", endVertexId: "a1")
        ]

        var upper = DeckLevel(name: "Upper")
        upper.vertices = [
            DeckVertex(id: "b1", position: CGPoint(x: 300, y: 0)),
            DeckVertex(id: "b2", position: CGPoint(x: 420, y: 0)),
            DeckVertex(id: "b3", position: CGPoint(x: 420, y: 120)),
            DeckVertex(id: "b4", position: CGPoint(x: 300, y: 120))
        ]
        upper.edges = [
            DeckEdge(id: "b-e1", startVertexId: "b1", endVertexId: "b2"),
            DeckEdge(id: "b-e2", startVertexId: "b2", endVertexId: "b3"),
            DeckEdge(id: "b-e3", startVertexId: "b3", endVertexId: "b4"),
            DeckEdge(id: "b-e4", startVertexId: "b4", endVertexId: "b1")
        ]

        data.levels = [lower, upper]
        return data
    }

    private func inputs(for data: DeckDrawingData) -> [VinylOrderSurfaceInput] {
        DeckMaterialsInputBuilder.surfaceInputs(for: data, scale: 1.0).map(\.input)
    }

    private func facesByLevel(for data: DeckDrawingData) -> [[DetectedSurface]] {
        data.isMultiLevel ? data.levels.map(\.detectedSurfaces) : [data.detectedSurfaces]
    }

    // MARK: - Classification

    func testRectWithOneHouseEdge() {
        let list = DeckMaterialsEngine.compute(
            vinylInputs: [rectInput(houseEdgeIndex: 3)],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: .default
        )
        XCTAssertEqual(list.dripEdge.exactFeet, 44, accuracy: 0.001)
        XCTAssertEqual(list.dripEdge.displayFeet, 44)
        XCTAssertEqual(list.dripEdge.sticks, 6)   // ceil(44 / 8)
        XCTAssertEqual(list.clip.exactFeet, 44, accuracy: 0.001)
        XCTAssertEqual(list.clip.sticks, 5)       // ceil(44 / 10)
        XCTAssertEqual(list.ninetyFlash.exactFeet, 20, accuracy: 0.001)
        XCTAssertEqual(list.ninetyFlash.sticks, 3) // ceil(20 / 8)
        XCTAssertEqual(list.glueAreaSqFt, 240, accuracy: 0.001)
        XCTAssertEqual(list.glueBuckets, 1)
    }

    func testParapetRailingCountsAsNinety() {
        let list = DeckMaterialsEngine.compute(
            vinylInputs: [rectInput(parapetIndex: 3)],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: .default
        )
        XCTAssertEqual(list.ninetyFlash.exactFeet, 20, accuracy: 0.001)
        XCTAssertEqual(list.ninetyFlash.sticks, 3)
        XCTAssertEqual(list.dripEdge.exactFeet, 44, accuracy: 0.001)
    }

    func testInteriorSeamGetsNoFlashing() {
        let data = twoSquaresSharingEdge()
        let list = DeckMaterialsEngine.compute(
            vinylInputs: inputs(for: data),
            allDetectedFacesByLevel: facesByLevel(for: data),
            settings: defaults,
            vinylSettings: .default
        )
        XCTAssertEqual(inputs(for: data).count, 2)
        XCTAssertEqual(list.dripEdge.exactFeet, 60, accuracy: 0.001) // 6 open × 10'
        XCTAssertEqual(list.ninetyFlash.exactFeet, 0, accuracy: 0.001)
    }

    func testStairEdgeDoesNotReduceDrip() {
        var data = singleSquareData()
        data.edges[0].stairConfig = StairConfig(width: 48)
        let list = DeckMaterialsEngine.compute(
            vinylInputs: inputs(for: data),
            allDetectedFacesByLevel: facesByLevel(for: data),
            settings: defaults,
            vinylSettings: .default
        )
        XCTAssertEqual(list.dripEdge.exactFeet, 40, accuracy: 0.001) // full 4×10' span
        XCTAssertEqual(list.ninetyFlash.exactFeet, 0, accuracy: 0.001)
    }

    // MARK: - Rounding

    func testStickRoundingExactMultiple() {
        var s = defaults
        s.dripStickFeet = 8
        let list = DeckMaterialsEngine.compute(
            vinylInputs: [singleOpenEdgeInput(inches: 24 * 12)], // 24'
            allDetectedFacesByLevel: [],
            settings: s,
            vinylSettings: .default
        )
        XCTAssertEqual(list.dripEdge.exactFeet, 24, accuracy: 0.001)
        XCTAssertEqual(list.dripEdge.sticks, 3) // ceil(24 / 8)
    }

    func testStickRoundingOneInchOver() {
        var s = defaults
        s.dripStickFeet = 8
        let list = DeckMaterialsEngine.compute(
            vinylInputs: [singleOpenEdgeInput(inches: 289)], // 24'1"
            allDetectedFacesByLevel: [],
            settings: s,
            vinylSettings: .default
        )
        XCTAssertEqual(list.dripEdge.sticks, 4) // ceil(24.083 / 8)
    }

    func testGlueRoundingExactMultiple() {
        // 240" × 240" = 400 sq ft; coverage 400 → 1 bucket.
        let list = DeckMaterialsEngine.compute(
            vinylInputs: [rectAreaInput(width: 240, height: 240)],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: .default
        )
        XCTAssertEqual(list.glueAreaSqFt, 400, accuracy: 0.001)
        XCTAssertEqual(list.glueBuckets, 1)
    }

    func testGlueRoundingOneOver() {
        // 240" × 240.6" = 401 sq ft; coverage 400 → 2 buckets.
        let list = DeckMaterialsEngine.compute(
            vinylInputs: [rectAreaInput(width: 240, height: 240.6)],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: .default
        )
        XCTAssertEqual(list.glueAreaSqFt, 401, accuracy: 0.01)
        XCTAssertEqual(list.glueBuckets, 2)
    }

    func testZeroNinetyWhenNoHouseOrParapet() {
        let list = DeckMaterialsEngine.compute(
            vinylInputs: [rectInput()],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: .default
        )
        XCTAssertEqual(list.ninetyFlash.sticks, 0)
        XCTAssertEqual(list.ninetyFlash.displayFeet, 0)
        XCTAssertEqual(list.ninetyFlash.exactFeet, 0, accuracy: 0.001)
        XCTAssertEqual(list.dripEdge.exactFeet, 64, accuracy: 0.001) // full perimeter
    }

    // MARK: - Multi-level

    func testMultiLevelSumsAcrossLevels() {
        let data = twoLevelData()
        let list = DeckMaterialsEngine.compute(
            vinylInputs: inputs(for: data),
            allDetectedFacesByLevel: facesByLevel(for: data),
            settings: defaults,
            vinylSettings: .default
        )
        XCTAssertEqual(list.dripEdge.exactFeet, 80, accuracy: 0.001) // 2 × 40'
        XCTAssertEqual(list.glueAreaSqFt, 200, accuracy: 0.001)      // 2 × 100 sq ft
    }

    // MARK: - Drift key

    func testDriftKeyEqualAfterRelabelDifferentAfterVertexMove() {
        let data = singleSquareData()
        let faceIds = Set(data.detectedSurfaces.first?.vertexIds ?? [])
        let list1 = DeckMaterialsEngine.compute(
            vinylInputs: inputs(for: data),
            allDetectedFacesByLevel: facesByLevel(for: data),
            settings: defaults,
            vinylSettings: .default
        )

        // Relabel — geometry unchanged → equal drift key.
        var relabeled = data
        let stableSurfaceId = try! XCTUnwrap(data.detectedSurfaces.first?.id)
        relabeled.surfaces = [
            DeckSurface(id: stableSurfaceId, vertexIds: faceIds, label: "RENAMED")
        ]
        let list2 = DeckMaterialsEngine.compute(
            vinylInputs: inputs(for: relabeled),
            allDetectedFacesByLevel: facesByLevel(for: relabeled),
            settings: defaults,
            vinylSettings: .default
        )
        XCTAssertEqual(list1.driftKey, list2.driftKey)

        // Move a vertex — geometry changes → different drift key.
        var moved = data
        moved.vertices[1].position = CGPoint(x: 200, y: 0)
        let list3 = DeckMaterialsEngine.compute(
            vinylInputs: inputs(for: moved),
            allDetectedFacesByLevel: facesByLevel(for: moved),
            settings: defaults,
            vinylSettings: .default
        )
        XCTAssertNotEqual(list1.driftKey, list3.driftKey)
    }

    func testDriftKeyChangesWhenTheWallAlignedDirectionTransitionMoves() {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 70),
            CGPoint(x: 70, y: 70),
            CGPoint(x: 70, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        func input(houseEdgeIndex: Int) -> VinylOrderSurfaceInput {
            VinylOrderSurfaceInput(
                id: "main",
                label: "Main",
                levelName: nil,
                positions: positions,
                scaleFactor: 1,
                edges: positions.indices.map { index in
                    VinylOrderSurfaceEdge(
                        id: "edge-\(index)",
                        start: positions[index],
                        end: positions[(index + 1) % positions.count],
                        edgeType: index == houseEdgeIndex ? .houseEdge : .deckEdge,
                        label: nil
                    )
                }
            )
        }
        let vinyl = VinylOrderSettings(
            color: "",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .automatic,
            allowsDirectionalChanges: true
        )
        let verticalWall = DeckMaterialsEngine.compute(
            vinylInputs: [input(houseEdgeIndex: 3)],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: vinyl
        )
        let horizontalWall = DeckMaterialsEngine.compute(
            vinylInputs: [input(houseEdgeIndex: 2)],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: vinyl
        )

        XCTAssertTrue(verticalWall.vinylPlan.isOrderable)
        XCTAssertTrue(horizontalWall.vinylPlan.isOrderable)
        XCTAssertEqual(verticalWall.driftKey.cutPairs.count, horizontalWall.driftKey.cutPairs.count)
        for (vertical, horizontal) in zip(
            verticalWall.driftKey.cutPairs,
            horizontalWall.driftKey.cutPairs
        ) {
            XCTAssertEqual(vertical.lengthInches, horizontal.lengthInches, accuracy: 0.01)
            XCTAssertEqual(vertical.rollWidthInches, horizontal.rollWidthInches, accuracy: 0.01)
        }
        XCTAssertNotEqual(
            verticalWall.vinylPlan.surfaces.first?.directionTransitions,
            horizontalWall.vinylPlan.surfaces.first?.directionTransitions
        )
        XCTAssertNotEqual(verticalWall.driftKey, horizontalWall.driftKey)
    }

    func testDriftKeyKeepsDirectionGeometryAttachedToItsSurface() {
        let shape = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 70),
            CGPoint(x: 70, y: 70),
            CGPoint(x: 70, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        func input(
            id: String,
            offsetX: CGFloat,
            houseEdgeIndex: Int
        ) -> VinylOrderSurfaceInput {
            let positions = shape.map { CGPoint(x: $0.x + offsetX, y: $0.y) }
            return VinylOrderSurfaceInput(
                id: id,
                label: id,
                levelName: nil,
                positions: positions,
                scaleFactor: 1,
                edges: positions.indices.map { index in
                    VinylOrderSurfaceEdge(
                        id: "\(id)-edge-\(index)",
                        start: positions[index],
                        end: positions[(index + 1) % positions.count],
                        edgeType: index == houseEdgeIndex ? .houseEdge : .deckEdge,
                        label: nil
                    )
                }
            )
        }
        let vinyl = VinylOrderSettings(
            color: "",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .automatic,
            allowsDirectionalChanges: true
        )
        let first = DeckMaterialsEngine.compute(
            vinylInputs: [
                input(id: "west", offsetX: 0, houseEdgeIndex: 3),
                input(id: "east", offsetX: 500, houseEdgeIndex: 2)
            ],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: vinyl
        )
        let swapped = DeckMaterialsEngine.compute(
            vinylInputs: [
                input(id: "west", offsetX: 0, houseEdgeIndex: 2),
                input(id: "east", offsetX: 500, houseEdgeIndex: 3)
            ],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: vinyl
        )

        XCTAssertTrue(first.vinylPlan.isOrderable)
        XCTAssertTrue(swapped.vinylPlan.isOrderable)
        XCTAssertEqual(first.driftKey.cutPairs.count, swapped.driftKey.cutPairs.count)
        for (a, b) in zip(first.driftKey.cutPairs, swapped.driftKey.cutPairs) {
            XCTAssertEqual(a.lengthInches, b.lengthInches, accuracy: 0.01)
            XCTAssertEqual(a.rollWidthInches, b.rollWidthInches, accuracy: 0.01)
        }
        XCTAssertNotEqual(first.driftKey, swapped.driftKey)
    }

    @MainActor
    func testDriftKeyKeepsDirectionGeometryAttachedAcrossOverlappingLevels() async throws {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 70),
            CGPoint(x: 70, y: 70),
            CGPoint(x: 70, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        func input(
            id: String,
            levelName: String,
            houseEdgeIndex: Int
        ) -> VinylOrderSurfaceInput {
            VinylOrderSurfaceInput(
                id: id,
                label: id,
                levelName: levelName,
                positions: positions,
                scaleFactor: 1,
                edges: positions.indices.map { index in
                    VinylOrderSurfaceEdge(
                        id: "\(id)-edge-\(index)",
                        start: positions[index],
                        end: positions[(index + 1) % positions.count],
                        edgeType: index == houseEdgeIndex ? .houseEdge : .deckEdge,
                        label: nil
                    )
                }
            )
        }
        let vinyl = VinylOrderSettings(
            color: "",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .automatic,
            allowsDirectionalChanges: true
        )
        let first = DeckMaterialsEngine.compute(
            vinylInputs: [
                input(id: "lower", levelName: "Level 1", houseEdgeIndex: 3),
                input(id: "upper", levelName: "Level 2", houseEdgeIndex: 2)
            ],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: vinyl
        )
        let swapped = DeckMaterialsEngine.compute(
            vinylInputs: [
                input(id: "lower", levelName: "Level 1", houseEdgeIndex: 2),
                input(id: "upper", levelName: "Level 2", houseEdgeIndex: 3)
            ],
            allDetectedFacesByLevel: [],
            settings: defaults,
            vinylSettings: vinyl
        )

        XCTAssertEqual(first.driftKey.cutPairs.count, swapped.driftKey.cutPairs.count)
        for (a, b) in zip(first.driftKey.cutPairs, swapped.driftKey.cutPairs) {
            XCTAssertEqual(a.lengthInches, b.lengthInches, accuracy: 0.01)
            XCTAssertEqual(a.rollWidthInches, b.rollWidthInches, accuracy: 0.01)
        }
        XCTAssertNotEqual(first.driftKey, swapped.driftKey)

        let design = DeckDesign(companyId: "co-1")
        let service = DeckMaterialsOrderService(userId: "user-1") { _, _ in }
        try await service.markOrdered(
            projectId: "project-1",
            design: design,
            materials: first,
            settings: defaults,
            vinylSettings: vinyl
        )
        let snapshot = try XCTUnwrap(design.drawingData.orderedMaterials)
        XCTAssertEqual(DeckMaterialsDriftKey(snapshot: snapshot), first.driftKey)
        XCTAssertNotEqual(DeckMaterialsDriftKey(snapshot: snapshot), swapped.driftKey)
    }

    // MARK: - Full-roll ordering (spec § 4.2)

    /// Cut-list mode (the default) leaves the roll figures at 0 — nothing to pack.
    func testCutListModeLeavesRollFieldsZero() {
        let list = DeckMaterialsEngine.compute(
            vinylInputs: [rectInput()],
            allDetectedFacesByLevel: [],
            settings: defaults,              // .cutList
            vinylSettings: .default
        )
        XCTAssertEqual(list.rollCount, 0)
        XCTAssertEqual(list.overlengthStripCount, 0)
    }

    /// Full-roll mode packs the plan's PURCHASED strips into whole rolls. The
    /// engine must feed the packer exactly those strips at the configured roll
    /// length — verified against an independent `VinylRollPacker` call.
    func testFullRollModePacksPurchasedCuts() {
        var s = defaults
        s.orderMode = .fullRolls
        s.fullRollLengthFeet = 75
        let list = DeckMaterialsEngine.compute(
            vinylInputs: [rectInput()],
            allDetectedFacesByLevel: [],
            settings: s,
            vinylSettings: .default
        )
        let strips = list.vinylPlan.surfaces.flatMap(\.purchasedCuts).map { $0.lengthInches / 12.0 }
        let expected = VinylRollPacker.rollsNeeded(stripLengthsFeet: strips, rollLengthFeet: 75)
        XCTAssertEqual(list.rollCount, expected.rollCount)
        XCTAssertEqual(list.overlengthStripCount, expected.overlengthStripCount)
        XCTAssertGreaterThan(list.rollCount, 0) // a real 12'×20' rect needs ≥1 roll
    }

    /// The full-roll length flows through: a short roll can never pack into fewer
    /// rolls than a long one for the same design.
    func testFullRollCountRespondsToRollLength() {
        var short = defaults; short.orderMode = .fullRolls; short.fullRollLengthFeet = 25
        var long = defaults;  long.orderMode = .fullRolls;  long.fullRollLengthFeet = 300
        let shortList = DeckMaterialsEngine.compute(
            vinylInputs: [rectInput()], allDetectedFacesByLevel: [], settings: short, vinylSettings: .default
        )
        let longList = DeckMaterialsEngine.compute(
            vinylInputs: [rectInput()], allDetectedFacesByLevel: [], settings: long, vinylSettings: .default
        )
        XCTAssertGreaterThanOrEqual(shortList.rollCount, longList.rollCount)
        XCTAssertGreaterThanOrEqual(longList.rollCount, 1)
    }

    /// THE core invariant (spec § 4.2): order mode is a purchasing choice, not a
    /// design change — the geometry drift key is byte-identical across cut-list
    /// and full-roll mode, so switching modes on an ordered design never flags
    /// DESIGN CHANGED SINCE ORDER.
    func testOrderModeDoesNotAffectDriftKey() {
        let input = rectInput(houseEdgeIndex: 3)
        var cut = defaults;  cut.orderMode = .cutList
        var roll = defaults; roll.orderMode = .fullRolls; roll.fullRollLengthFeet = 75
        let cutList = DeckMaterialsEngine.compute(
            vinylInputs: [input], allDetectedFacesByLevel: [], settings: cut, vinylSettings: .default
        )
        let rollList = DeckMaterialsEngine.compute(
            vinylInputs: [input], allDetectedFacesByLevel: [], settings: roll, vinylSettings: .default
        )
        XCTAssertEqual(cutList.driftKey, rollList.driftKey)
        XCTAssertEqual(cutList.rollCount, 0)
        XCTAssertGreaterThan(rollList.rollCount, 0)
    }
}
