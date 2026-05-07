//
//  OrderSuggestionEngineTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class OrderSuggestionEngineTests: XCTestCase {

    private let companyId = "c1"

    // MARK: - Fixture builders

    private func family(
        id: String,
        name: String,
        categoryId: String? = nil,
        warning: Double? = nil,
        critical: Double? = nil
    ) -> CatalogItem {
        let f = CatalogItem(
            id: id,
            companyId: companyId,
            name: name,
            categoryId: categoryId,
            defaultWarningThreshold: warning,
            defaultCriticalThreshold: critical
        )
        return f
    }

    private func variant(
        id: String,
        familyId: String,
        quantity: Double,
        warning: Double? = nil,
        critical: Double? = nil,
        active: Bool = true,
        deletedAt: Date? = nil
    ) -> CatalogVariant {
        let v = CatalogVariant(
            id: id,
            companyId: companyId,
            catalogItemId: familyId,
            quantity: quantity,
            warningThreshold: warning,
            criticalThreshold: critical,
            isActive: active
        )
        v.deletedAt = deletedAt
        return v
    }

    private func category(
        id: String,
        name: String,
        warning: Double? = nil,
        critical: Double? = nil
    ) -> CatalogCategory {
        CatalogCategory(
            id: id,
            companyId: companyId,
            name: name,
            defaultWarningThreshold: warning,
            defaultCriticalThreshold: critical
        )
    }

    // MARK: - Tests

    /// Variant qty = 30, family default warning = 100 → suggested,
    /// recommendedQuantity = warning * 2 = 200.
    func test_suggests_belowWarning_with_2x_warning_target() {
        let cornerFamily = family(id: "f_corner", name: "Corner", warning: 100)
        let v = variant(id: "v1", familyId: "f_corner", quantity: 30)

        let result = OrderSuggestionEngine().suggest(
            variants: [v],
            families: [cornerFamily],
            categories: []
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.variantId, "v1")
        XCTAssertEqual(result.first?.familyName, "Corner")
        XCTAssertEqual(result.first?.currentQuantity, 30, accuracy: 0.001)
        XCTAssertEqual(result.first?.warningThreshold, 100, accuracy: 0.001)
        XCTAssertEqual(result.first?.recommendedQuantity, 200, accuracy: 0.001)
    }

    /// Variant qty = 200, family default warning = 100 → no suggestion.
    func test_doesNotSuggest_whenAboveWarning() {
        let cornerFamily = family(id: "f_corner", name: "Corner", warning: 100)
        let v = variant(id: "v1", familyId: "f_corner", quantity: 200)

        let result = OrderSuggestionEngine().suggest(
            variants: [v],
            families: [cornerFamily],
            categories: []
        )

        XCTAssertTrue(result.isEmpty)
    }

    /// Variant has no override, family has no default, category default = 50.
    /// Variant qty = 10 → suggested, recommendedQuantity = 100.
    func test_walksCategoryDefault_whenNoFamilyOrVariantThreshold() {
        let postsCategory = category(id: "cat_posts", name: "Posts", warning: 50)
        let postFamily = family(id: "f_post", name: "Post", categoryId: "cat_posts")
        let v = variant(id: "v1", familyId: "f_post", quantity: 10)

        let result = OrderSuggestionEngine().suggest(
            variants: [v],
            families: [postFamily],
            categories: [postsCategory]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.warningThreshold, 50, accuracy: 0.001)
        XCTAssertEqual(result.first?.recommendedQuantity, 100, accuracy: 0.001)
    }

    /// No threshold anywhere in the cascade → no suggestion.
    func test_doesNotSuggest_whenNoThresholdAvailable() {
        let cornerFamily = family(id: "f_corner", name: "Corner")
        let v = variant(id: "v1", familyId: "f_corner", quantity: 0)

        let result = OrderSuggestionEngine().suggest(
            variants: [v],
            families: [cornerFamily],
            categories: []
        )

        XCTAssertTrue(result.isEmpty)
    }

    /// Variant override beats family default when both exist.
    func test_variantOverride_winsOverFamilyDefault() {
        let cornerFamily = family(id: "f_corner", name: "Corner", warning: 100)
        let v = variant(id: "v1", familyId: "f_corner", quantity: 15, warning: 20)

        let result = OrderSuggestionEngine().suggest(
            variants: [v],
            families: [cornerFamily],
            categories: []
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.warningThreshold, 20, accuracy: 0.001)
        XCTAssertEqual(result.first?.recommendedQuantity, 40, accuracy: 0.001)
    }

    /// Inactive and soft-deleted variants are skipped even if below threshold.
    func test_skipsInactiveAndDeletedVariants() {
        let cornerFamily = family(id: "f_corner", name: "Corner", warning: 100)
        let inactive = variant(id: "v_inactive", familyId: "f_corner", quantity: 0, active: false)
        let deleted = variant(id: "v_deleted", familyId: "f_corner", quantity: 0, deletedAt: Date())

        let result = OrderSuggestionEngine().suggest(
            variants: [inactive, deleted],
            families: [cornerFamily],
            categories: []
        )

        XCTAssertTrue(result.isEmpty)
    }
}
