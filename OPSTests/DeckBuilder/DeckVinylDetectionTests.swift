// OPSTests/DeckBuilder/DeckVinylDetectionTests.swift
//
// Detection matrix (spec § 5 / § 10): explicit vinyl by name / standard id /
// linked-catalog hint; non-vinyl exclusion beats the job signal; unassigned +
// signal inclusion (task or config); no-signal empty; mixed job. Plus defect-①
// regression: `DeckVinylHintBuilder` resolves an `AssignedItem.productId` (a
// Products-table id) through `Product.linkedCatalogItemId` to the linked catalog
// item's vinyl signal — the old map was keyed by `CatalogItem.id`, so rule 3
// never fired.

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
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: false, vinylHintByProductId: [:])
        XCTAssertEqual(ids, ["s1"])
    }

    func testExplicitVinylByStandardId() {
        let surfaces = [surface("s1", items: [item(id: DeckVinylDetection.vinylStandardId, name: "Membrane")])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: false, vinylHintByProductId: [:])
        XCTAssertEqual(ids, ["s1"])
    }

    func testExplicitVinylByCatalogBlob() {
        let surfaces = [surface("s1", items: [item(name: "Custom Surface", productId: "p1")])]
        let ids = DeckVinylDetection.vinylSurfaceIds(
            surfaces: surfaces,
            jobHasVinylSignal: false,
            vinylHintByProductId: ["p1": "duradek vinyl membrane roll"]
        )
        XCTAssertEqual(ids, ["s1"])
    }

    func testNonVinylAssignedExcludedEvenWithJobSignal() {
        let surfaces = [surface("s1", items: [item(name: "Composite Decking")])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: true, vinylHintByProductId: [:])
        XCTAssertTrue(ids.isEmpty)
    }

    func testUnassignedWithSignalIncluded() {
        let surfaces = [surface("s1", items: [])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: true, vinylHintByProductId: [:])
        XCTAssertEqual(ids, ["s1"])
    }

    func testUnassignedWithoutSignalEmpty() {
        let surfaces = [surface("s1", items: [])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: false, vinylHintByProductId: [:])
        XCTAssertTrue(ids.isEmpty)
    }

    func testMixedJobOnlyUnassignedIncluded() {
        let surfaces = [
            surface("composite", items: [item(name: "Composite Decking")]),
            surface("bare", items: [])
        ]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: true, vinylHintByProductId: [:])
        XCTAssertEqual(ids, ["bare"])
    }

    func testNonAreaItemIgnored() {
        // A stray linear item must not classify a surface as excluded — it has no
        // area material, so with a job signal it is still unassigned→vinyl.
        let surfaces = [surface("s1", items: [item(name: "Railing", unit: .linearFoot)])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: true, vinylHintByProductId: [:])
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

    // MARK: - Defect ① — productId → linked catalog item resolution

    /// A product whose OWN name lacks "vinyl" but whose LINKED catalog item's
    /// NAME carries the signal must classify vinyl. Before the fix the injected
    /// map was keyed by `CatalogItem.id`, so the `productId` lookup always missed
    /// and this surface was silently excluded.
    func testProductWithLinkedVinylCatalogNameClassifiedVinyl() {
        let product = Product(id: "p-surface", companyId: "co", name: "Premium Deck Surface", type: .material, kind: .good)
        product.linkedCatalogItemId = "cat-vinyl"
        let catalog = CatalogItem(id: "cat-vinyl", companyId: "co", name: "Vinyl Membrane Roll")

        let hints = DeckVinylHintBuilder.build(products: [product], catalogItems: [catalog])
        let surfaces = [surface("s1", items: [item(name: "Premium Deck Surface", productId: "p-surface")])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: false, vinylHintByProductId: hints)
        XCTAssertEqual(ids, ["s1"])
    }

    /// Same, but the signal lives in the linked catalog item's DESCRIPTION.
    func testProductWithLinkedVinylCatalogDescriptionClassifiedVinyl() {
        let product = Product(id: "p-surface", companyId: "co", name: "Premium Deck Surface", type: .material, kind: .good)
        product.linkedCatalogItemId = "cat-membrane"
        let catalog = CatalogItem(id: "cat-membrane", companyId: "co", name: "Duradek Membrane")
        catalog.itemDescription = "Welded sheet vinyl waterproof decking"

        let hints = DeckVinylHintBuilder.build(products: [product], catalogItems: [catalog])
        let surfaces = [surface("s1", items: [item(name: "Premium Deck Surface", productId: "p-surface")])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: false, vinylHintByProductId: hints)
        XCTAssertEqual(ids, ["s1"])
    }

    /// A product + its linked catalog item that are both non-vinyl stays excluded
    /// even with a job-level vinyl signal — an explicit non-vinyl surfacing wins
    /// over the ambient signal, and the hint must not accidentally resolve vinyl.
    func testNonVinylProductStaysExcludedEvenWithJobSignal() {
        let product = Product(id: "p-composite", companyId: "co", name: "Composite Decking", type: .material, kind: .good)
        product.linkedCatalogItemId = "cat-composite"
        let catalog = CatalogItem(id: "cat-composite", companyId: "co", name: "Cedar Composite Board")
        catalog.itemDescription = "Capped composite decking board"

        let hints = DeckVinylHintBuilder.build(products: [product], catalogItems: [catalog])
        let surfaces = [surface("s1", items: [item(name: "Composite Decking", productId: "p-composite")])]
        let ids = DeckVinylDetection.vinylSurfaceIds(surfaces: surfaces, jobHasVinylSignal: true, vinylHintByProductId: hints)
        XCTAssertTrue(ids.isEmpty)
    }

    // MARK: - Defect ① — hint builder mapping

    /// The built hint is keyed by `Product.id` and folds product name + linked
    /// catalog name + linked catalog description, lowercased.
    func testHintBuilderFoldsProductAndLinkedCatalog() {
        let product = Product(id: "p1", companyId: "co", name: "Deck Surface", type: .material, kind: .good)
        product.linkedCatalogItemId = "cat1"
        let catalog = CatalogItem(id: "cat1", companyId: "co", name: "Vinyl Membrane")
        catalog.itemDescription = "Sheet vinyl"

        let hints = DeckVinylHintBuilder.build(products: [product], catalogItems: [catalog])
        XCTAssertEqual(hints["p1"], "deck surface vinyl membrane sheet vinyl")
    }

    /// No link (or a dangling link) falls back to the product's own name — never
    /// crashes, never pulls in an unrelated catalog item.
    func testHintBuilderFallsBackToProductNameWhenNoLink() {
        let unlinked = Product(id: "p1", companyId: "co", name: "Vinyl Deck Kit", type: .material, kind: .good)
        let dangling = Product(id: "p2", companyId: "co", name: "Composite Kit", type: .material, kind: .good)
        dangling.linkedCatalogItemId = "missing-cat"

        let hints = DeckVinylHintBuilder.build(products: [unlinked, dangling], catalogItems: [])
        XCTAssertEqual(hints["p1"], "vinyl deck kit")
        XCTAssertEqual(hints["p2"], "composite kit")
    }
}
