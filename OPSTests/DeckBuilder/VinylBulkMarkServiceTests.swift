//
//  VinylBulkMarkServiceTests.swift
//  OPSTests
//
//  Bulk MARK ORDERED: snapshot vs marker-only path selection, color/PO in the
//  same payload as the status trio, per-item failure collection with revert,
//  and retry of only the failed subset.
//

import CoreGraphics
import Supabase
import XCTest
@testable import OPS

@MainActor
final class VinylBulkMarkServiceTests: XCTestCase {

    /// A materials list with real purchased cuts (12'×20' rect, one house
    /// edge) — same fixture the order-service tests use.
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

    private func snapshotItem(projectId: String, design: DeckDesign, po: String? = nil, color: String? = nil) -> VinylBulkMarkItem {
        VinylBulkMarkItem(
            projectId: projectId,
            design: design,
            materials: rectMaterials(),
            settings: DeckMaterialsSettings(),
            vinylSettings: .default,
            color: color,
            po: po
        )
    }

    private func markerOnlyItem(projectId: String, color: String? = nil, po: String? = nil) -> VinylBulkMarkItem {
        VinylBulkMarkItem(
            projectId: projectId,
            design: nil,
            materials: nil,
            settings: DeckMaterialsSettings(),
            vinylSettings: .default,
            color: color,
            po: po
        )
    }

    /// Design + materials ⇒ snapshot freeze; no design ⇒ marker-only. Both
    /// carry color/PO in the same payload as the trio.
    func testSnapshotVsMarkerOnlyPathSelection() async throws {
        let design = DeckDesign(companyId: "co-1")
        var payloads: [String: [String: AnyJSON]] = [:]
        let service = VinylBulkMarkService(userId: "user-1") { pid, fields in
            payloads[pid] = fields
        }

        let outcome = await service.markOrdered(items: [
            snapshotItem(projectId: "p-design", design: design, po: "PO 6836 Mark Ln", color: "68mil Cobblestone"),
            markerOnlyItem(projectId: "p-plain", color: "68mil Slate", po: nil)
        ])

        XCTAssertEqual(outcome, VinylBulkMarkOutcome(succeeded: ["p-design", "p-plain"], failed: []))

        // Snapshot path froze the design and carried color + PO into it.
        let snapshot = try XCTUnwrap(design.drawingData.orderedMaterials)
        XCTAssertEqual(snapshot.vinylColor, "68mil Cobblestone")
        XCTAssertEqual(snapshot.po, "PO 6836 Mark Ln")

        // Both payloads carry the five marker fields atomically.
        let designPayload = try XCTUnwrap(payloads["p-design"])
        XCTAssertEqual(designPayload[ProjectVinylOrderFields.status], .string("ordered"))
        XCTAssertEqual(designPayload[ProjectVinylOrderFields.color], .string("68mil Cobblestone"))
        XCTAssertEqual(designPayload[ProjectVinylOrderFields.po], .string("PO 6836 Mark Ln"))

        let plainPayload = try XCTUnwrap(payloads["p-plain"])
        XCTAssertEqual(plainPayload[ProjectVinylOrderFields.status], .string("ordered"))
        XCTAssertNotNil(plainPayload[ProjectVinylOrderFields.orderedAt])
        XCTAssertEqual(plainPayload[ProjectVinylOrderFields.orderedBy], .null)
        XCTAssertEqual(plainPayload[ProjectVinylOrderFields.color], .string("68mil Slate"))
        XCTAssertEqual(plainPayload[ProjectVinylOrderFields.po], .null)
    }

    /// Item 2 of 3 fails ⇒ 1 and 3 stay marked, 2 is collected AND its
    /// snapshot reverts (marker write threw after the local freeze).
    func testPartialFailureCollectsAndRevertsOnlyTheFailedItem() async throws {
        struct Boom: Error {}
        let designOK = DeckDesign(companyId: "co-1")
        let designFail = DeckDesign(companyId: "co-1")

        let service = VinylBulkMarkService(userId: "user-1") { pid, _ in
            if pid == "p-2" { throw Boom() }
        }

        let outcome = await service.markOrdered(items: [
            snapshotItem(projectId: "p-1", design: designOK),
            snapshotItem(projectId: "p-2", design: designFail),
            markerOnlyItem(projectId: "p-3")
        ])

        XCTAssertEqual(outcome, VinylBulkMarkOutcome(succeeded: ["p-1", "p-3"], failed: ["p-2"]))
        XCTAssertNotNil(designOK.drawingData.orderedMaterials, "Successful item keeps its snapshot")
        XCTAssertNil(designFail.drawingData.orderedMaterials, "Failed item's snapshot must revert")
    }

    /// Retrying only the failed subset (the RETRY affordance) marks it clean.
    func testRetryOfFailedSubsetSucceeds() async throws {
        struct Boom: Error {}
        let design = DeckDesign(companyId: "co-1")
        var failOnce = true
        let service = VinylBulkMarkService(userId: "user-1") { pid, _ in
            if pid == "p-flaky" && failOnce { throw Boom() }
        }

        let first = await service.markOrdered(items: [
            markerOnlyItem(projectId: "p-ok"),
            snapshotItem(projectId: "p-flaky", design: design)
        ])
        XCTAssertEqual(first, VinylBulkMarkOutcome(succeeded: ["p-ok"], failed: ["p-flaky"]))
        XCTAssertNil(design.drawingData.orderedMaterials)

        failOnce = false
        let retry = await service.markOrdered(items: [
            snapshotItem(projectId: "p-flaky", design: design)
        ])
        XCTAssertEqual(retry, VinylBulkMarkOutcome(succeeded: ["p-flaky"], failed: []))
        XCTAssertNotNil(design.drawingData.orderedMaterials)
    }

    /// Config-carried color reaches the marker payload even on the snapshot
    /// path when vinylSettings arrived with an empty color.
    func testItemColorOverridesEmptyVinylSettingsColor() async throws {
        let design = DeckDesign(companyId: "co-1")
        var captured: [String: AnyJSON]?
        let service = VinylBulkMarkService(userId: "user-1") { _, fields in captured = fields }

        _ = await service.markOrdered(items: [
            snapshotItem(projectId: "p-1", design: design, color: "68mil Hansberry")
        ])

        XCTAssertEqual(captured?[ProjectVinylOrderFields.color], .string("68mil Hansberry"))
        XCTAssertEqual(design.drawingData.orderedMaterials?.vinylColor, "68mil Hansberry")
    }
}
