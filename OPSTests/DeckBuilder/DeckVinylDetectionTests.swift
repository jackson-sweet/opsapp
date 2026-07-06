// OPSTests/DeckBuilder/DeckVinylDetectionTests.swift
//
// Detection matrix (spec § 5 / § 10): explicit vinyl by name / standard id /
// catalog blob; non-vinyl exclusion beats the job signal; unassigned + signal
// inclusion (task or config); no-signal empty; mixed job.

import XCTest
@testable import OPS

final class DeckVinylDetectionTests: XCTestCase {

    private func surface(_ id: String, items: [AssignedItem]) -> DeckMaterialsInputBuilder.SurfaceInput {
        (
            VinylOrderSurfaceInput(id: id, label: id, levelName: nil, positions: [], scaleFactor: 1.0, edges: []),
            items
        )
    }

    private func item(
        id: String = "item-\(UUID().uuidString)",
        name: String,
        productId: String? = nil,
        unit: UnitType = .squareFoot
    ) -> AssignedItem {
        AssignedItem(id: id, productId: productId, name: name, unitType: unit)
    }

    // MARK: - Detection matrix

    func testExplicitVinylByName() {
        let surfaces = [surface("s1", items: [item(name: "Vinyl Membrane")])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: false, catalogNameById: [:])
        XCTAssertEqual(ids, ["s1"])
    }

    func testExplicitVinylByStandardId() {
        let surfaces = [surface("s1", items: [item(id: DeckVinylDetection.vinylStandardId, name: "Membrane")])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: false, catalogNameById: [:])
        XCTAssertEqual(ids, ["s1"])
    }

    func testExplicitVinylByCatalogBlob() {
        let surfaces = [surface("s1", items: [item(name: "Custom Surface", productId: "p1")])]
        let ids = DeckVinylDetection.vinylSurfaceIds(
            surfaces: surfaces,
            jobHasVinylSignal: false,
            catalogNameById: ["p1": "duradek vinyl membrane roll"]
        )
        XCTAssertEqual(ids, ["s1"])
    }

    func testNonVinylAssignedExcludedEvenWithJobSignal() {
        let surfaces = [surface("s1", items: [item(name: "Composite Decking")])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: true, catalogNameById: [:])
        XCTAssertTrue(ids.isEmpty)
    }

    func testUnassignedWithSignalIncluded() {
        let surfaces = [surface("s1", items: [])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: true, catalogNameById: [:])
        XCTAssertEqual(ids, ["s1"])
    }

    func testUnassignedWithoutSignalEmpty() {
        let surfaces = [surface("s1", items: [])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: false, catalogNameById: [:])
        XCTAssertTrue(ids.isEmpty)
    }

    func testMixedJobOnlyUnassignedIncluded() {
        let surfaces = [
            surface("composite", items: [item(name: "Composite Decking")]),
            surface("bare", items: [])
        ]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: true, catalogNameById: [:])
        XCTAssertEqual(ids, ["bare"])
    }

    func testNonAreaItemIgnored() {
        // A stray linear item must not classify a surface as excluded — it has no
        // area material, so with a job signal it is still unassigned→vinyl.
        let surfaces = [surface("s1", items: [item(name: "Railing", unit: .linearFoot)])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: true, catalogNameById: [:])
        XCTAssertEqual(ids, ["s1"])
    }

    // MARK: - Job signal

    func testJobSignalFromTaskDisplay() {
        XCTAssertTrue(DeckVinylDetection.jobHasVinylSignal(taskTypeDisplays: ["VINYL INSTALL"], vinylCatalogItemId: nil))
        XCTAssertTrue(DeckVinylDetection.jobHasVinylSignal(taskTypeDisplays: ["Vinyl Removal + Install"], vinylCatalogItemId: nil))
    }

    func testJobSignalFromConfig() {
        XCTAssertTrue(DeckVinylDetection.jobHasVinylSignal(taskTypeDisplays: ["Demo"], vinylCatalogItemId: "cat-123"))
    }

    func testJobSignalNoneWhenNeither() {
        XCTAssertFalse(DeckVinylDetection.jobHasVinylSignal(taskTypeDisplays: ["Demo", "Framing"], vinylCatalogItemId: nil))
        XCTAssertFalse(DeckVinylDetection.jobHasVinylSignal(taskTypeDisplays: [], vinylCatalogItemId: "   "))
    }
}
