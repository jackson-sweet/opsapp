// OPSTests/DeckBuilder/DeckMaterialsOrderServiceTests.swift
//
// Coverage for the shared MARK ORDERED / CLEAR ORDERED writer: happy snapshot +
// trio, revert-on-throw, clear, and clear-with-nil-design.

import CoreGraphics
import Supabase
import XCTest
@testable import OPS

@MainActor
final class DeckMaterialsOrderServiceTests: XCTestCase {

    /// A materials list with real purchased cuts (12'×20' rect, one house edge).
    private func rectMaterials() -> DeckMaterialsList {
        let p = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 144, y: 0),
            CGPoint(x: 144, y: 240),
            CGPoint(x: 0, y: 240)
        ]
        let input = VinylOrderSurfaceInput(
            id: "s1", label: "Main", levelName: nil, positions: p, scaleFactor: 1.0,
            edges: [
                VinylOrderSurfaceEdge(id: "e4", start: p[3], end: p[0], edgeType: .houseEdge, label: nil,
                                      startVertexId: "v4", endVertexId: "v1", isParapet: false, dimensionInches: 240)
            ]
        )
        return DeckMaterialsEngine.compute(
            vinylInputs: [input],
            allDetectedFacesByLevel: [],
            settings: DeckMaterialsSettings(),
            vinylSettings: .default
        )
    }

    func testMarkOrderedWritesSnapshotAndTrio() async throws {
        let design = DeckDesign(companyId: "co-1")
        var captured: [String: AnyJSON]?
        let service = DeckMaterialsOrderService(userId: "user-1") { _, fields in captured = fields }

        try await service.markOrdered(
            projectId: "proj-1",
            design: design,
            materials: rectMaterials(),
            settings: DeckMaterialsSettings(),
            vinylSettings: .default
        )

        let snapshot = design.drawingData.orderedMaterials
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.orderedBy, "user-1")
        XCTAssertFalse(snapshot?.cutGroups.isEmpty ?? true)
        XCTAssertTrue(design.needsSync)

        XCTAssertEqual(captured?[ProjectVinylOrderFields.status], .string("ordered"))
        XCTAssertEqual(captured?[ProjectVinylOrderFields.orderedBy], .string("user-1"))
        XCTAssertNotNil(captured?[ProjectVinylOrderFields.orderedAt])
    }

    func testMarkOrderedRevertsSnapshotOnUpdaterThrow() async throws {
        struct Boom: Error {}
        let design = DeckDesign(companyId: "co-1")
        XCTAssertNil(design.drawingData.orderedMaterials)

        let service = DeckMaterialsOrderService(userId: "user-1") { _, _ in throw Boom() }

        do {
            try await service.markOrdered(
                projectId: "proj-1",
                design: design,
                materials: rectMaterials(),
                settings: DeckMaterialsSettings(),
                vinylSettings: .default
            )
            XCTFail("expected markOrdered to rethrow")
        } catch {
            // expected
        }
        XCTAssertNil(design.drawingData.orderedMaterials) // reverted to prior nil
    }

    func testClearOrderedClearsNodeAndSendsNullFields() async throws {
        let design = DeckDesign(companyId: "co-1")
        let mark = DeckMaterialsOrderService(userId: "user-1") { _, _ in }
        try await mark.markOrdered(
            projectId: "proj-1",
            design: design,
            materials: rectMaterials(),
            settings: DeckMaterialsSettings(),
            vinylSettings: .default
        )
        XCTAssertNotNil(design.drawingData.orderedMaterials)

        var captured: [String: AnyJSON]?
        let clear = DeckMaterialsOrderService(userId: "user-1") { _, fields in captured = fields }
        try await clear.clearOrdered(projectId: "proj-1", design: design)

        XCTAssertNil(design.drawingData.orderedMaterials)
        XCTAssertEqual(captured?[ProjectVinylOrderFields.status], .string("not_ordered"))
        XCTAssertEqual(captured?[ProjectVinylOrderFields.orderedAt], .null)
        XCTAssertEqual(captured?[ProjectVinylOrderFields.orderedBy], .null)
    }

    func testClearOrderedWithNilDesignStillClearsFields() async throws {
        var captured: [String: AnyJSON]?
        let service = DeckMaterialsOrderService(userId: "user-1") { _, fields in captured = fields }
        try await service.clearOrdered(projectId: "proj-1", design: nil)
        XCTAssertEqual(captured?[ProjectVinylOrderFields.status], .string("not_ordered"))
        XCTAssertEqual(captured?[ProjectVinylOrderFields.orderedAt], .null)
    }
}
