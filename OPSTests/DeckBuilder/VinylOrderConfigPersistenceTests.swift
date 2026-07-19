// OPS/OPSTests/DeckBuilder/VinylOrderConfigPersistenceTests.swift
//
// Bug 0f86b9b0 — "colour selection not saved". The vinyl colour (catalog
// variant, or free-text colour) chosen in the Vinyl Order sheet must persist on
// the deck design's DrawingConfig and survive the deckDesign JSON round-trip,
// so reopening the sheet restores the operator's choice instead of resetting it.

import CoreGraphics
import XCTest
@testable import OPS

@MainActor
final class VinylOrderConfigPersistenceTests: XCTestCase {

    // MARK: - DrawingConfig codable round-trip

    func testDrawingConfigRoundTripsVinylSelection() throws {
        var config = DrawingConfig()
        config.vinylCatalogItemId = "item-1"
        config.vinylCatalogVariantId = "variant-9"
        config.vinylColor = "Slate Grey"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(DrawingConfig.self, from: data)

        XCTAssertEqual(decoded.vinylCatalogItemId, "item-1")
        XCTAssertEqual(decoded.vinylCatalogVariantId, "variant-9")
        XCTAssertEqual(decoded.vinylColor, "Slate Grey")
    }

    /// Decks saved before the colour fields existed must keep decoding — the new
    /// keys are optional and absent in stored JSON.
    func testDrawingConfigDecodesLegacyJSONWithoutVinylSelection() throws {
        let legacyJSON = #"{"measurementSystem":"imperial","vinylCatalogItemId":"item-1"}"#
        let decoded = try JSONDecoder().decode(DrawingConfig.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded.vinylCatalogItemId, "item-1")
        XCTAssertNil(decoded.vinylCatalogVariantId)
        XCTAssertNil(decoded.vinylColor)
    }

    // MARK: - ViewModel persistence

    func testSetVinylCatalogSelectionPersistsThroughDrawingDataRoundTrip() throws {
        let viewModel = makeViewModel()

        viewModel.setVinylCatalogSelection(variantId: "variant-9", color: "Slate Grey")

        XCTAssertEqual(viewModel.drawingData.config.vinylCatalogVariantId, "variant-9")
        XCTAssertEqual(viewModel.drawingData.config.vinylColor, "Slate Grey")

        let reloaded = DeckDrawingData.fromJSON(viewModel.drawingData.toJSON())
        XCTAssertEqual(reloaded?.config.vinylCatalogVariantId, "variant-9")
        XCTAssertEqual(reloaded?.config.vinylColor, "Slate Grey")
    }

    func testSetVinylCatalogSelectionTrimsAndNilsEmptyValues() throws {
        let viewModel = makeViewModel()
        viewModel.setVinylCatalogSelection(variantId: "variant-9", color: "Slate Grey")

        viewModel.setVinylCatalogSelection(variantId: "  ", color: "")

        XCTAssertNil(viewModel.drawingData.config.vinylCatalogVariantId)
        XCTAssertNil(viewModel.drawingData.config.vinylColor)
    }

    /// Changing the vinyl PRODUCT invalidates the persisted variant/colour — a
    /// variant belongs to exactly one catalog item, so carrying it across a
    /// product switch would restore a colour of the wrong product.
    func testSetVinylCatalogItemIdClearsStaleVariantSelection() throws {
        let viewModel = makeViewModel()
        viewModel.setVinylCatalogItemId("item-1")
        viewModel.setVinylCatalogSelection(variantId: "variant-9", color: "Slate Grey")

        viewModel.setVinylCatalogItemId("item-2")

        XCTAssertEqual(viewModel.drawingData.config.vinylCatalogItemId, "item-2")
        XCTAssertNil(viewModel.drawingData.config.vinylCatalogVariantId)
        XCTAssertNil(viewModel.drawingData.config.vinylColor)
    }

    /// Re-setting the SAME item must not wipe the persisted colour (the settings
    /// sheet re-binds on every appearance).
    func testSetVinylCatalogItemIdKeepsSelectionWhenItemUnchanged() throws {
        let viewModel = makeViewModel()
        viewModel.setVinylCatalogItemId("item-1")
        viewModel.setVinylCatalogSelection(variantId: "variant-9", color: "Slate Grey")

        viewModel.setVinylCatalogItemId("item-1")

        XCTAssertEqual(viewModel.drawingData.config.vinylCatalogVariantId, "variant-9")
        XCTAssertEqual(viewModel.drawingData.config.vinylColor, "Slate Grey")
    }

    // MARK: - Sheet restore resolution

    func testRestoredSelectionResolvesPersistedVariant() {
        let restored = VinylCatalogSelection.restoredSelection(
            configItemId: "item-1",
            configVariantId: "variant-9",
            configColor: "Slate Grey",
            availableItemIds: ["item-1", "item-2"],
            variantIdsByItem: ["item-1": ["variant-9", "variant-10"]]
        )

        XCTAssertEqual(restored.itemId, "item-1")
        XCTAssertEqual(restored.variantId, "variant-9")
        XCTAssertEqual(restored.color, "Slate Grey")
    }

    /// A persisted variant that no longer exists (deactivated/deleted in the
    /// catalog) must not be restored — the sheet falls back to "select a colour"
    /// rather than silently ordering a dead variant.
    func testRestoredSelectionDropsVariantMissingFromCatalog() {
        let restored = VinylCatalogSelection.restoredSelection(
            configItemId: "item-1",
            configVariantId: "variant-dead",
            configColor: "Slate Grey",
            availableItemIds: ["item-1"],
            variantIdsByItem: ["item-1": ["variant-10"]]
        )

        XCTAssertEqual(restored.itemId, "item-1")
        XCTAssertNil(restored.variantId)
        XCTAssertNil(restored.color)
    }

    /// Free-text colour (no catalog product configured) restores as plain text.
    func testRestoredSelectionKeepsFreeTextColorWithoutProduct() {
        let restored = VinylCatalogSelection.restoredSelection(
            configItemId: nil,
            configVariantId: nil,
            configColor: "Tan",
            availableItemIds: [],
            variantIdsByItem: [:]
        )

        XCTAssertNil(restored.itemId)
        XCTAssertNil(restored.variantId)
        XCTAssertEqual(restored.color, "Tan")
    }

    /// A configured product whose catalog item vanished falls back to free-text
    /// colour so the operator's colour note is never lost.
    func testRestoredSelectionFallsBackToFreeTextWhenItemMissing() {
        let restored = VinylCatalogSelection.restoredSelection(
            configItemId: "item-gone",
            configVariantId: "variant-9",
            configColor: "Slate Grey",
            availableItemIds: ["item-2"],
            variantIdsByItem: ["item-2": ["variant-2"]]
        )

        XCTAssertNil(restored.itemId)
        XCTAssertNil(restored.variantId)
        XCTAssertEqual(restored.color, "Slate Grey")
    }

    // MARK: - Helpers

    private func makeViewModel() -> DeckBuilderViewModel {
        let design = DeckDesign(
            companyId: "company-1",
            title: "Test deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        return DeckBuilderViewModel(deckDesign: design)
    }
}
