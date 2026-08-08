import XCTest
@testable import OPS

final class CatalogBulkVariantExpansionServiceTests: XCTestCase {
    func test_snapshotBuilder_includesOnlySelectedLiveFamilyState() throws {
        let companyId = "company"
        let selected = CatalogItem(id: "selected", companyId: companyId, name: "Top Rail")
        let ignored = CatalogItem(id: "ignored", companyId: companyId, name: "Bottom Rail")
        let option = CatalogOption(id: "profile", catalogItemId: selected.id, name: "Top profile", sortOrder: 0)
        let value = CatalogOptionValue(id: "round", optionId: option.id, value: "Round top", sortOrder: 0)
        let variant = CatalogVariant(
            id: "round-variant",
            companyId: companyId,
            catalogItemId: selected.id,
            sku: "ROUND",
            quantity: 12,
            priceOverride: 14,
            unitCostOverride: 8,
            warningThreshold: 4,
            criticalThreshold: 2,
            unitId: "each"
        )
        let deleted = CatalogVariant(
            id: "deleted",
            companyId: companyId,
            catalogItemId: selected.id,
            quantity: 99
        )
        deleted.deletedAt = Date()

        let snapshots = CatalogBulkVariantSnapshotBuilder.makeFamilies(
            items: [ignored, selected],
            options: [option],
            values: [value],
            variants: [deleted, variant],
            joins: [
                .init(variantId: variant.id, optionValueId: value.id),
                .init(variantId: deleted.id, optionValueId: value.id)
            ],
            selectedFamilyIds: [selected.id]
        )

        XCTAssertEqual(snapshots.count, 1)
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.id, selected.id)
        XCTAssertEqual(snapshot.options.first?.values.map(\.id), [value.id])
        XCTAssertEqual(snapshot.variants.map(\.id), [variant.id])
        XCTAssertEqual(snapshot.variants.first?.optionValueIds, [value.id])
        XCTAssertEqual(snapshot.variants.first?.quantity, 12)
    }

    func test_requestPayload_preservesFingerprintAndDeterministicPlan() throws {
        let option = CatalogBulkOptionSnapshot(
            id: "color",
            name: "Color",
            sortOrder: 0,
            values: [.init(id: "red", value: "Red", sortOrder: 0)]
        )
        let variant = CatalogBulkVariantSnapshot(
            id: "red-variant",
            sku: "RED",
            quantity: 7,
            priceOverride: 14,
            unitCostOverride: 8,
            warningThreshold: 4,
            criticalThreshold: 2,
            unitId: "each",
            isActive: true,
            optionValueIds: ["red"]
        )
        let preview = CatalogBulkVariantExpansionPlanner.makePreview(.init(
            axisName: "Top profile",
            existingValue: "Round top",
            newValues: ["Flat top"],
            families: [.init(id: "rail", name: "Top Rail", options: [option], variants: [variant])]
        ))

        let request = try CatalogBulkVariantExpansionRequest(
            idempotencyKey: "attempt-1",
            preview: preview
        )
        XCTAssertEqual(request.idempotencyKey, "attempt-1")
        XCTAssertEqual(request.axisName, "Top profile")
        XCTAssertEqual(request.families.first?.sourceFingerprint, preview.familyPlans.first?.sourceFingerprint)
        XCTAssertEqual(request.families.first?.source.variants.first?.quantity, 7)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        XCTAssertEqual(object["idempotency_key"] as? String, "attempt-1")
        XCTAssertEqual(object["axis_name"] as? String, "Top profile")
        XCTAssertNotNil(object["families"] as? [[String: Any]])
    }

    func test_requestRejectsBlockedOrEmptyPreview() {
        let blocked = CatalogBulkVariantExpansionPlanner.makePreview(.init(
            axisName: "",
            existingValue: "Round top",
            newValues: ["Flat top"],
            families: []
        ))
        XCTAssertThrowsError(
            try CatalogBulkVariantExpansionRequest(idempotencyKey: "attempt", preview: blocked)
        ) { error in
            XCTAssertEqual(error as? CatalogBulkVariantExpansionError, .invalidPreview)
        }
    }
}
