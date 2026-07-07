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

    /// A rectangular vinyl surface (feet → inches at scale 1) that yields real cut
    /// geometry. `houseEdgeIndex` marks one boundary as a house edge (90 flash);
    /// the rest are open edges (drip + clip).
    private func rectSurface(
        id: String,
        label: String,
        width: Double,
        height: Double,
        houseEdgeIndex: Int? = nil
    ) -> VinylOrderSurfaceInput {
        let p = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: width, y: 0),
            CGPoint(x: width, y: height),
            CGPoint(x: 0, y: height)
        ]
        let vids = (0..<4).map { "\(id)-v\($0)" }
        let dims = [width, height, width, height]
        let edges = (0..<4).map { i in
            VinylOrderSurfaceEdge(
                id: "\(id)-e\(i)", start: p[i], end: p[(i + 1) % 4],
                edgeType: i == houseEdgeIndex ? .houseEdge : .deckEdge, label: nil,
                startVertexId: vids[i], endVertexId: vids[(i + 1) % 4],
                isParapet: false, dimensionInches: dims[i]
            )
        }
        return VinylOrderSurfaceInput(id: id, label: label, levelName: nil, positions: p, scaleFactor: 1.0, edges: edges)
    }

    /// A degenerate surface (< 3 positions): `VinylCutListEngine.makePlan` drops it
    /// (no cuts, no cut group), but it still counts toward `vinylInputs.count`.
    private func degenerateSurface(id: String, label: String) -> VinylOrderSurfaceInput {
        VinylOrderSurfaceInput(
            id: id, label: label, levelName: nil,
            positions: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
            scaleFactor: 1.0, edges: []
        )
    }

    private func markOrderedSnapshot(_ materials: DeckMaterialsList) async throws -> DeckMaterialsSnapshot {
        let design = DeckDesign(companyId: "co-1")
        let service = DeckMaterialsOrderService(userId: "user-1") { _, _ in }
        try await service.markOrdered(
            projectId: "proj-1",
            design: design,
            materials: materials,
            settings: DeckMaterialsSettings(),
            vinylSettings: .default
        )
        return try XCTUnwrap(design.drawingData.orderedMaterials)
    }

    /// Mark ordered with an explicit confirmation + settings, returning both the
    /// design (for round-trip assertions) and the frozen snapshot.
    private func markOrderedSnapshot(
        _ materials: DeckMaterialsList,
        confirmed: DeckMaterialsOrderConfirmation?,
        settings: DeckMaterialsSettings,
        vinylSettings: VinylOrderSettings = .default
    ) async throws -> (design: DeckDesign, snapshot: DeckMaterialsSnapshot) {
        let design = DeckDesign(companyId: "co-1")
        let service = DeckMaterialsOrderService(userId: "user-1") { _, _ in }
        try await service.markOrdered(
            projectId: "proj-1",
            design: design,
            materials: materials,
            settings: settings,
            vinylSettings: vinylSettings,
            confirmed: confirmed
        )
        return (design, try XCTUnwrap(design.drawingData.orderedMaterials))
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

    // MARK: - Defect ② — drift key parity at order time

    /// (a) Two vinyl surfaces sharing a label, ordered → NO false drift. Their cut
    /// groups collapse to one label, so the old snapshot-side reconstruction read
    /// 1 while the live side counted 2 — flagging DESIGN CHANGED the instant the
    /// design was ordered. The stored count keeps both sides at 2.
    func testTwoVinylSurfacesSharingLabelNoFalseDrift() async throws {
        let materials = DeckMaterialsEngine.compute(
            vinylInputs: [
                rectSurface(id: "s1", label: "Main", width: 144, height: 240, houseEdgeIndex: 3),
                rectSurface(id: "s2", label: "Main", width: 120, height: 120)
            ],
            allDetectedFacesByLevel: [],
            settings: DeckMaterialsSettings(),
            vinylSettings: .default
        )
        XCTAssertEqual(materials.driftKey.vinylSurfaceCount, 2)

        let snapshot = try await markOrderedSnapshot(materials)
        // Both surfaces collapse to a single label — the old reconstruction read 1.
        XCTAssertEqual(Set(snapshot.cutGroups.map(\.surfaceLabel)).count, 1)
        XCTAssertEqual(snapshot.vinylSurfaceCount, 2)
        XCTAssertEqual(DeckMaterialsDriftKey(snapshot: snapshot), materials.driftKey)
    }

    /// (b) A vinyl set containing a degenerate surface, ordered → NO false drift.
    /// The degenerate surface drops out of the cut plan (no cut group), but still
    /// counts toward the vinyl surface count.
    func testDegenerateVinylSurfaceNoFalseDrift() async throws {
        let materials = DeckMaterialsEngine.compute(
            vinylInputs: [
                rectSurface(id: "s1", label: "Main", width: 144, height: 240, houseEdgeIndex: 3),
                degenerateSurface(id: "s2", label: "Sliver")
            ],
            allDetectedFacesByLevel: [],
            settings: DeckMaterialsSettings(),
            vinylSettings: .default
        )
        XCTAssertEqual(materials.driftKey.vinylSurfaceCount, 2)

        let snapshot = try await markOrderedSnapshot(materials)
        // Only the non-degenerate surface produced cuts.
        XCTAssertEqual(Set(snapshot.cutGroups.map(\.surfaceLabel)), ["Main"])
        XCTAssertEqual(snapshot.vinylSurfaceCount, 2)
        XCTAssertEqual(DeckMaterialsDriftKey(snapshot: snapshot), materials.driftKey)
    }

    /// (c) A real vertex move that changes cut geometry → drift TRUE. The stored
    /// count fix must not mask genuine design change.
    func testGeometryChangeFlagsDrift() async throws {
        let ordered = DeckMaterialsEngine.compute(
            vinylInputs: [rectSurface(id: "s1", label: "Main", width: 144, height: 240, houseEdgeIndex: 3)],
            allDetectedFacesByLevel: [],
            settings: DeckMaterialsSettings(),
            vinylSettings: .default
        )
        let snapshot = try await markOrderedSnapshot(ordered)
        // Sanity: the unchanged design reads no drift.
        XCTAssertEqual(DeckMaterialsDriftKey(snapshot: snapshot), ordered.driftKey)

        // The deck grew 20'→30' deep — a real geometry change.
        let moved = DeckMaterialsEngine.compute(
            vinylInputs: [rectSurface(id: "s1", label: "Main", width: 144, height: 360, houseEdgeIndex: 3)],
            allDetectedFacesByLevel: [],
            settings: DeckMaterialsSettings(),
            vinylSettings: .default
        )
        XCTAssertNotEqual(DeckMaterialsDriftKey(snapshot: snapshot), moved.driftKey)
    }

    // MARK: - Offcut-reuse drift (adversarial-review regression)

    /// A deck where a small surface's strip is cut from a larger surface's leftover
    /// offcut (intra-job reuse, NO banked offcuts) must NOT false-flag DESIGN
    /// CHANGED the instant it is ordered. The live drift key counts every cut piece
    /// (purchased + reused); the snapshot stores the full set in `driftCutGroups`
    /// so the reconstructed key matches. The purchased-only `cutGroups` (display)
    /// stay smaller. A real geometry change still flags drift.
    func testIntraJobReuseDeckDoesNotFalseFlagDrift() async throws {
        let vinyl = VinylOrderSettings(color: "", rollWidthInches: 72, seamOverlapInches: 2, edgeWrapInches: 0, direction: .lengthwise)
        let materials = DeckMaterialsEngine.compute(
            vinylInputs: [
                rectSurface(id: "main", label: "Main", width: 288, height: 132),
                rectSurface(id: "landing", label: "Landing", width: 96, height: 8)
            ],
            allDetectedFacesByLevel: [],
            settings: DeckMaterialsSettings(),
            vinylSettings: vinyl
        )
        // The config must actually produce intra-job reuse to exercise the fix.
        XCTAssertGreaterThan(materials.vinylPlan.totalReusedCutAreaSqFt, 0)

        let design = DeckDesign(companyId: "co-1")
        let service = DeckMaterialsOrderService(userId: "u") { _, _ in }
        try await service.markOrdered(projectId: "p", design: design, materials: materials, settings: DeckMaterialsSettings(), vinylSettings: vinyl)
        let snapshot = try XCTUnwrap(design.drawingData.orderedMaterials)

        // No false drift at the order instant — the reconstructed key equals live.
        XCTAssertEqual(DeckMaterialsDriftKey(snapshot: snapshot), materials.driftKey)
        // The display cut list is purchased-only, strictly fewer than the drift set.
        let purchasedCount = snapshot.cutGroups.reduce(0) { $0 + $1.count }
        let driftCount = snapshot.driftCutGroups.reduce(0) { $0 + $1.count }
        XCTAssertLessThan(purchasedCount, driftCount)

        // A real geometry change (Main grows 11'→15' deep) still flags drift.
        let moved = DeckMaterialsEngine.compute(
            vinylInputs: [
                rectSurface(id: "main", label: "Main", width: 288, height: 180),
                rectSurface(id: "landing", label: "Landing", width: 96, height: 8)
            ],
            allDetectedFacesByLevel: [],
            settings: DeckMaterialsSettings(),
            vinylSettings: vinyl
        )
        XCTAssertNotEqual(DeckMaterialsDriftKey(snapshot: snapshot), moved.driftKey)
    }

    /// A legacy snapshot written before `driftCutGroups` existed decodes with the
    /// field falling back to the purchased `cutGroups` — its prior behavior, no
    /// crash (additive-field discipline).
    func testLegacySnapshotDriftGroupsFallBackToCutGroups() throws {
        let json = """
        {
          "orderedAt": 1780000000,
          "cutGroups": [{"surfaceLabel": "Main", "count": 3, "lengthInches": 252, "rollWidthInches": 72}]
        }
        """
        let snapshot = try JSONDecoder().decode(DeckMaterialsSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.driftCutGroups, snapshot.cutGroups)
    }

    // MARK: - Editable ordered record (spec § 3.3 / § 6)

    /// Confirming with hand-edited quantities freezes the EDITED values and flags
    /// `isOrderedEdited` — yet the geometry drift key is byte-identical to the
    /// live materials, so a spare-stick order is drift-clean at the order instant.
    func testConfirmWithEditsStoresEditedValuesAndFlagsEdited() async throws {
        let materials = rectMaterials()
        var confirmation = DeckMaterialsOrderConfirmation.calculated(from: materials, settings: DeckMaterialsSettings())
        // Operator bought spare sticks + rounded glue up.
        let editedDrip = confirmation.dripSticks + 2
        let editedGlue = confirmation.glueBuckets + 1
        confirmation.dripSticks = editedDrip
        confirmation.glueBuckets = editedGlue

        let (_, snapshot) = try await markOrderedSnapshot(
            materials, confirmed: confirmation, settings: DeckMaterialsSettings()
        )

        XCTAssertEqual(snapshot.dripSticks, editedDrip)
        XCTAssertEqual(snapshot.glueBuckets, editedGlue)
        XCTAssertTrue(snapshot.isOrderedEdited)
        // Untouched quantities keep the calc value.
        XCTAssertEqual(snapshot.clipSticks, materials.clip.sticks)
        XCTAssertEqual(snapshot.ninetySticks, materials.ninetyFlash.sticks)
        // Drift-clean: the edits never moved the geometry key.
        XCTAssertEqual(DeckMaterialsDriftKey(snapshot: snapshot), materials.driftKey)
    }

    /// Confirming the calculated values unchanged — or supplying no confirmation
    /// at all — leaves `isOrderedEdited` false.
    func testConfirmUnchangedIsNotFlaggedEdited() async throws {
        let materials = rectMaterials()
        let calc = DeckMaterialsOrderConfirmation.calculated(from: materials, settings: DeckMaterialsSettings())

        let (_, explicit) = try await markOrderedSnapshot(
            materials, confirmed: calc, settings: DeckMaterialsSettings()
        )
        XCTAssertFalse(explicit.isOrderedEdited)
        XCTAssertEqual(explicit.dripSticks, materials.dripEdge.sticks)

        // The no-confirmation path (legacy callers) is also unedited.
        let implicit = try await markOrderedSnapshot(materials)
        XCTAssertFalse(implicit.isOrderedEdited)
        XCTAssertNil(implicit.orderedRollCount)
        XCTAssertEqual(implicit.orderMode, .cutList)
    }

    /// Roll-mode order freezes the roll count + full-roll length and round-trips
    /// them through the design JSON. `orderedRollCount` is nil in cut-list mode.
    func testRollModeSnapshotRoundTripsRollCount() async throws {
        var settings = DeckMaterialsSettings()
        settings.orderMode = .fullRolls
        settings.fullRollLengthFeet = 75
        let materials = DeckMaterialsEngine.compute(
            vinylInputs: [rectSurface(id: "s1", label: "Main", width: 144, height: 240, houseEdgeIndex: 3)],
            allDetectedFacesByLevel: [],
            settings: settings,
            vinylSettings: .default
        )
        XCTAssertGreaterThan(materials.rollCount, 0)
        let confirmation = DeckMaterialsOrderConfirmation.calculated(from: materials, settings: settings)

        let (design, snapshot) = try await markOrderedSnapshot(
            materials, confirmed: confirmation, settings: settings
        )
        XCTAssertEqual(snapshot.orderMode, .fullRolls)
        XCTAssertEqual(snapshot.fullRollLengthFeet, 75)
        XCTAssertEqual(snapshot.orderedRollCount, materials.rollCount)
        XCTAssertFalse(snapshot.isOrderedEdited)

        // Survives a full design-JSON round-trip.
        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(design.drawingData.toJSON()))
        XCTAssertEqual(decoded.orderedMaterials?.orderMode, .fullRolls)
        XCTAssertEqual(decoded.orderedMaterials?.fullRollLengthFeet, 75)
        XCTAssertEqual(decoded.orderedMaterials?.orderedRollCount, materials.rollCount)
    }

    /// Editing the roll count in roll mode flags edited and stores the edited
    /// count — a full-roll rounding is remembered without touching drift.
    func testRollModeEditedRollCountFlagsEdited() async throws {
        var settings = DeckMaterialsSettings()
        settings.orderMode = .fullRolls
        settings.fullRollLengthFeet = 75
        let materials = DeckMaterialsEngine.compute(
            vinylInputs: [rectSurface(id: "s1", label: "Main", width: 144, height: 240, houseEdgeIndex: 3)],
            allDetectedFacesByLevel: [],
            settings: settings,
            vinylSettings: .default
        )
        var confirmation = DeckMaterialsOrderConfirmation.calculated(from: materials, settings: settings)
        confirmation.rollCount = materials.rollCount + 1 // bought a spare roll

        let (_, snapshot) = try await markOrderedSnapshot(
            materials, confirmed: confirmation, settings: settings
        )
        XCTAssertEqual(snapshot.orderedRollCount, materials.rollCount + 1)
        XCTAssertTrue(snapshot.isOrderedEdited)
        XCTAssertEqual(DeckMaterialsDriftKey(snapshot: snapshot), materials.driftKey)
    }

    // MARK: - EDIT ORDER (spec § 6)

    /// EDIT ORDER rewrites the confirmed quantities but leaves the geometry drift
    /// key, the order timestamp and the orderer byte-identical — a correction can
    /// never clear or raise DESIGN CHANGED SINCE ORDER.
    func testEditOrderRewritesQuantitiesButPreservesDriftKeyAndStamp() async throws {
        let materials = rectMaterials()
        let (design, original) = try await markOrderedSnapshot(materials, confirmed: nil, settings: DeckMaterialsSettings())
        let originalDrift = DeckMaterialsDriftKey(snapshot: original)

        var edited = DeckMaterialsOrderConfirmation.stored(fromSnapshot: original)
        edited.dripSticks = original.dripSticks + 3
        edited.glueBuckets = original.glueBuckets + 1
        let didEdit = DeckMaterialsOrderService.editOrder(design: design, confirmed: edited)
        XCTAssertTrue(didEdit)

        let updated = try XCTUnwrap(design.drawingData.orderedMaterials)
        XCTAssertEqual(updated.dripSticks, original.dripSticks + 3)
        XCTAssertEqual(updated.glueBuckets, original.glueBuckets + 1)
        XCTAssertTrue(updated.isOrderedEdited)
        XCTAssertEqual(DeckMaterialsDriftKey(snapshot: updated), originalDrift)
        XCTAssertEqual(updated.orderedAt, original.orderedAt)
        XCTAssertEqual(updated.orderedBy, original.orderedBy)
    }

    /// Editing back to the calculated values clears the ADJUSTED flag.
    func testEditOrderBackToCalculatedClearsEditedFlag() async throws {
        let materials = rectMaterials()
        var confirmation = DeckMaterialsOrderConfirmation.calculated(from: materials, settings: DeckMaterialsSettings())
        confirmation.dripSticks += 3
        let (design, edited) = try await markOrderedSnapshot(materials, confirmed: confirmation, settings: DeckMaterialsSettings())
        XCTAssertTrue(edited.isOrderedEdited)

        let calc = DeckMaterialsOrderConfirmation.calculated(fromSnapshot: edited)
        DeckMaterialsOrderService.editOrder(design: design, confirmed: calc)
        let updated = try XCTUnwrap(design.drawingData.orderedMaterials)
        XCTAssertFalse(updated.isOrderedEdited)
        XCTAssertEqual(updated.dripSticks, materials.dripEdge.sticks)
    }

    /// EDIT ORDER on a design with no ordered snapshot is a no-op.
    func testEditOrderNoSnapshotIsNoOp() {
        let design = DeckDesign(companyId: "co-1")
        let confirmation = DeckMaterialsOrderConfirmation.calculated(from: rectMaterials(), settings: DeckMaterialsSettings())
        XCTAssertFalse(DeckMaterialsOrderService.editOrder(design: design, confirmed: confirmation))
        XCTAssertNil(design.drawingData.orderedMaterials)
    }

    /// `stored(fromSnapshot:)` reflects the CONFIRMED values (the sheet pre-fill);
    /// `calculated(fromSnapshot:)` reflects the calculator (the RESET target).
    func testStoredVsCalculatedFromSnapshot() async throws {
        let materials = rectMaterials()
        var confirmation = DeckMaterialsOrderConfirmation.calculated(from: materials, settings: DeckMaterialsSettings())
        confirmation.ninetySticks += 2
        let (_, snapshot) = try await markOrderedSnapshot(materials, confirmed: confirmation, settings: DeckMaterialsSettings())

        let stored = DeckMaterialsOrderConfirmation.stored(fromSnapshot: snapshot)
        XCTAssertEqual(stored.ninetySticks, confirmation.ninetySticks)   // confirmed (edited)

        let calc = DeckMaterialsOrderConfirmation.calculated(fromSnapshot: snapshot)
        XCTAssertEqual(calc.ninetySticks, materials.ninetyFlash.sticks)  // calculator
        XCTAssertEqual(calc.dripSticks, materials.dripEdge.sticks)
        XCTAssertEqual(calc.vinylOrderedSqFt, materials.vinylPlan.totalOrderedSqFt)
    }
}
