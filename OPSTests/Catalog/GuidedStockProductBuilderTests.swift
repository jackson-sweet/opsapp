import XCTest
@testable import OPS

final class GuidedStockProductBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func makeGroup(
        id: String = "grp-1",
        familyName: String = "Vinyl",
        sellMode: GuidedSellMode? = nil,
        sellingUsesStock: Bool? = nil,
        bundleChildren: [GuidedBundleChild] = []
    ) -> GuidedStructuredGroup {
        GuidedStructuredGroup(
            id: id,
            familyName: familyName,
            memberItemIds: [],
            isSingleItem: true,
            product: GuidedProductAnswers(
                sellMode: sellMode,
                sellingUsesStock: sellingUsesStock,
                bundleChildren: bundleChildren
            )
        )
    }

    private let defaultFamilyClientId = "family::grp-1"

    // MARK: - Tests

    func test_stockOnly_noSellMode_returnsEmpty() {
        let group = makeGroup(sellMode: nil)
        let result = GuidedStockProductBuilder.productPayloads(
            for: group,
            companyId: "co-1",
            familyClientId: defaultFamilyClientId,
            recipeVariantClientId: nil,
            childProductIdByItemId: [:]
        )
        XCTAssertTrue(result.isEmpty, "Expected empty array when sellMode is nil")
    }

    func test_sellOnItsOwn_linksProductToFamily_noRecipeNoBundle() {
        let group = makeGroup(sellMode: .onItsOwn, sellingUsesStock: nil)
        let result = GuidedStockProductBuilder.productPayloads(
            for: group,
            companyId: "co-1",
            familyClientId: defaultFamilyClientId,
            recipeVariantClientId: nil,
            childProductIdByItemId: [:]
        )

        XCTAssertEqual(result.count, 1)
        let product = result[0]
        XCTAssertEqual(product.kind, "material")
        XCTAssertEqual(product.linkedCatalogItemClientId, defaultFamilyClientId)
        XCTAssertTrue(product.productMaterials.isEmpty, "No recipe when sellingUsesStock is nil")
        XCTAssertTrue(product.bundleItems.isEmpty, "No bundle items for onItsOwn sell mode")
        XCTAssertNil(product.id, "New product must have nil id")
        XCTAssertEqual(product.clientId, "product::grp-1")
    }

    func test_both_withRecipe_pinsMaterialToVariant() {
        let group = makeGroup(sellMode: .both, sellingUsesStock: true)
        let variantClientId = "var-1"
        let result = GuidedStockProductBuilder.productPayloads(
            for: group,
            companyId: "co-1",
            familyClientId: defaultFamilyClientId,
            recipeVariantClientId: variantClientId,
            childProductIdByItemId: [:]
        )

        XCTAssertEqual(result.count, 1)
        let product = result[0]
        XCTAssertEqual(product.linkedCatalogItemClientId, defaultFamilyClientId,
                       "Both mode product still links to its stock family")
        XCTAssertEqual(product.productMaterials.count, 1)
        let material = product.productMaterials[0]
        XCTAssertEqual(material.catalogVariantClientId, variantClientId,
                       "Material must pin to the variant client id")
        XCTAssertNil(material.catalogItemClientId,
                     "When pinned to variant, family client id must be nil (exactly one pin)")
        XCTAssertEqual(material.productClientId, "product::grp-1")
        XCTAssertEqual(material.quantityPerUnit, 1)
    }

    func test_recipe_pinsToFamily_whenNoVariantClientId() {
        let group = makeGroup(sellMode: .onItsOwn, sellingUsesStock: true)
        let result = GuidedStockProductBuilder.productPayloads(
            for: group,
            companyId: "co-1",
            familyClientId: defaultFamilyClientId,
            recipeVariantClientId: nil,
            childProductIdByItemId: [:]
        )

        XCTAssertEqual(result.count, 1)
        let material = result[0].productMaterials[0]
        XCTAssertEqual(material.catalogItemClientId, defaultFamilyClientId,
                       "When no variant client id, material must pin to the family")
        XCTAssertNil(material.catalogVariantClientId,
                     "catalogVariantClientId must be nil when pinned to family (exactly one pin)")
    }

    func test_package_buildsBundleItems_requiredAndSuggested() {
        let children = [
            GuidedBundleChild(capturedItemId: "itemA", isRequired: true),
            GuidedBundleChild(capturedItemId: "itemB", isRequired: false)
        ]
        let group = makeGroup(id: "grp-pkg", sellMode: .inPackage, bundleChildren: children)
        let childMap: [String: String] = ["itemA": "srvA", "itemB": "srvB"]
        let familyClientId = "family::grp-pkg"

        let result = GuidedStockProductBuilder.productPayloads(
            for: group,
            companyId: "co-1",
            familyClientId: familyClientId,
            recipeVariantClientId: nil,
            childProductIdByItemId: childMap
        )

        XCTAssertEqual(result.count, 1)
        let product = result[0]
        XCTAssertEqual(product.kind, "package")
        XCTAssertNil(product.linkedCatalogItemClientId,
                     "Pure bundle must not link to a stock family")
        XCTAssertEqual(product.bundlePricingMode, "auto")
        XCTAssertEqual(product.bundleItems.count, 2)

        let itemA = product.bundleItems[0]
        XCTAssertEqual(itemA.childProductId, "srvA")
        XCTAssertEqual(itemA.relationshipKind, "required")
        XCTAssertEqual(itemA.displayOrder, 0)

        let itemB = product.bundleItems[1]
        XCTAssertEqual(itemB.childProductId, "srvB")
        XCTAssertEqual(itemB.relationshipKind, "suggested")
        XCTAssertEqual(itemB.displayOrder, 1)
    }

    func test_package_skipsUnresolvedChildren() {
        let children = [
            GuidedBundleChild(capturedItemId: "itemA", isRequired: true),
            GuidedBundleChild(capturedItemId: "itemB", isRequired: true)
        ]
        let group = makeGroup(id: "grp-skip", sellMode: .inPackage, bundleChildren: children)
        // Only itemA is resolved; itemB has no entry in the map.
        let childMap: [String: String] = ["itemA": "srvA"]

        let result = GuidedStockProductBuilder.productPayloads(
            for: group,
            companyId: "co-1",
            familyClientId: "family::grp-skip",
            recipeVariantClientId: nil,
            childProductIdByItemId: childMap
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].bundleItems.count, 1,
                       "Unresolved child (not in map) must be skipped")
        XCTAssertEqual(result[0].bundleItems[0].childProductId, "srvA")
    }

    func test_ids_deterministic() {
        let children = [GuidedBundleChild(capturedItemId: "itemX", isRequired: true)]
        let group = makeGroup(id: "grp-det", sellMode: .both, sellingUsesStock: true, bundleChildren: children)
        let familyClientId = "family::grp-det"
        let childMap: [String: String] = ["itemX": "srvX"]

        let first = GuidedStockProductBuilder.productPayloads(
            for: group,
            companyId: "co-1",
            familyClientId: familyClientId,
            recipeVariantClientId: "var-det",
            childProductIdByItemId: childMap
        )
        let second = GuidedStockProductBuilder.productPayloads(
            for: group,
            companyId: "co-1",
            familyClientId: familyClientId,
            recipeVariantClientId: "var-det",
            childProductIdByItemId: childMap
        )

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)

        // Product client id
        XCTAssertEqual(first[0].clientId, second[0].clientId)

        // Material client id
        XCTAssertEqual(first[0].productMaterials.count, 1)
        XCTAssertEqual(second[0].productMaterials.count, 1)
        XCTAssertEqual(first[0].productMaterials[0].clientId,
                       second[0].productMaterials[0].clientId)

        // Bundle item client id
        XCTAssertEqual(first[0].bundleItems.count, 1)
        XCTAssertEqual(second[0].bundleItems.count, 1)
        XCTAssertEqual(first[0].bundleItems[0].clientId,
                       second[0].bundleItems[0].clientId)
    }
}
