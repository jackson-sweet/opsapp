//
//  CatalogDataFoundationTests.swift
//  OPSTests
//

import XCTest
import SwiftData
@testable import OPS

final class CatalogDataFoundationTests: XCTestCase {
    private let companyId = "company_catalog_foundation"

    func testCatalogStockUnitDTODecodesAndMapsPhysicalRollFields() throws {
        let json = """
        {
          "id": "unit_1",
          "company_id": "\(companyId)",
          "catalog_variant_id": "variant_black",
          "unit_kind": "roll",
          "label": "Roll A",
          "lot_code": "LOT-44",
          "width_value": 6,
          "width_unit": "ft",
          "original_length_value": 75,
          "remaining_length_value": 22.5,
          "length_unit": "ft",
          "quantity_value": 1,
          "location": "Truck 2",
          "status": "partial",
          "source_order_item_id": "order_item_1",
          "notes": "shop offcut",
          "created_at": "2026-05-21T10:00:00Z",
          "updated_at": "2026-05-21T11:00:00Z",
          "deleted_at": null
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(CatalogStockUnitDTO.self, from: json)
        let model = dto.toModel()

        XCTAssertEqual(model.id, "unit_1")
        XCTAssertEqual(model.companyId, companyId)
        XCTAssertEqual(model.catalogVariantId, "variant_black")
        XCTAssertEqual(model.unitKind, .roll)
        XCTAssertEqual(model.label, "Roll A")
        XCTAssertEqual(model.widthValue, 6)
        XCTAssertEqual(model.remainingLengthValue, 22.5)
        XCTAssertEqual(model.status, .partial)
        XCTAssertEqual(model.sourceOrderItemId, "order_item_1")
        XCTAssertNotNil(model.createdAt)
        XCTAssertNotNil(model.updatedAt)
    }

    func testStockUnitAggregationSumsAvailableUnitsAndIgnoresConsumedRows() throws {
        let units = [
            stockUnit(id: "full", remainingLength: 75, quantity: 1, status: .full),
            stockUnit(id: "partial", remainingLength: 22, quantity: 1, status: .partial),
            stockUnit(id: "consumed", remainingLength: 75, quantity: 1, status: .consumed),
            stockUnit(id: "scrapped", remainingLength: 12, quantity: 1, status: .scrapped)
        ]

        let aggregate = CatalogStockUnitAggregator.aggregate(units: units)
        let variant = try XCTUnwrap(aggregate.byVariantId["variant_roll"])

        XCTAssertEqual(variant.activeUnitCount, 2)
        XCTAssertEqual(variant.quantityValue, 2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(variant.remainingLengthByUnit["ft"]), 97, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(variant.remainingAreaByUnit["sq ft"]), 582, accuracy: 0.001)
        XCTAssertEqual(variant.effectiveQuantity, 582, accuracy: 0.001)
        XCTAssertEqual(CatalogStockQuantityPolicy.mode, .mirroredVariantQuantity)
        XCTAssertEqual(CatalogStockQuantityPolicy.quantityToMirror(variant), 582, accuracy: 0.001)
        XCTAssertEqual(CatalogStockQuantityPolicy.quantityBasis(for: variant), "AREA · sq ft")
    }

    func testV8PersistentContainerBuildsWithMigrationPlanWithoutDuplicateVersionChecksums() throws {
        let schema = Schema(versionedSchema: OPSSchemaV8.self)
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ops-v8-migration-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        let configuration = ModelConfiguration(
            schema: schema,
            url: storeDirectory.appendingPathComponent("default.store"),
            allowsSave: true
        )

        XCTAssertNoThrow(
            try ModelContainer(
                for: schema,
                migrationPlan: OPSMigrationPlan.self,
                configurations: [configuration]
            )
        )
    }

    func testV7PersistentStoreMigratesToV8WithMigrationPlan() throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ops-v7-to-v8-migration-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        let storeURL = storeDirectory.appendingPathComponent("default.store")
        let v7Schema = Schema(versionedSchema: OPSSchemaV7.self)
        let v7Configuration = ModelConfiguration(schema: v7Schema, url: storeURL, allowsSave: true)
        _ = try ModelContainer(for: v7Schema, configurations: [v7Configuration])

        let v8Schema = Schema(versionedSchema: OPSSchemaV8.self)
        let v8Configuration = ModelConfiguration(schema: v8Schema, url: storeURL, allowsSave: true)

        XCTAssertNoThrow(
            try ModelContainer(
                for: v8Schema,
                migrationPlan: OPSMigrationPlan.self,
                configurations: [v8Configuration]
            )
        )
    }

    func testHistoricalPersistentStoresOpenThroughCurrentMigrationPlan() throws {
        try assertOpensCurrentMigratedStore(name: "V1-to-current", sourceSchema: OPSSchemaV1.self)
        try assertOpensCurrentMigratedStore(name: "V3-to-current", sourceSchema: OPSSchemaV3.self)
        try assertOpensCurrentMigratedStore(name: "V7-to-current", sourceSchema: OPSSchemaV7.self)
    }

    func testHistoricalSchemaBoundariesHaveDistinctSwiftDataMigrationFingerprints() throws {
        UserDefaults.standard.removeObject(forKey: "needs_full_catalog_sync")
        defer { UserDefaults.standard.removeObject(forKey: "needs_full_catalog_sync") }

        try assertMigrates(
            name: "V1->V2",
            sourceSchema: OPSSchemaV1.self,
            targetSchema: OPSSchemaV2.self,
            plan: V1ToV2OnlyMigrationPlan.self
        )
        try assertMigrates(
            name: "V2->V3",
            sourceSchema: OPSSchemaV2.self,
            targetSchema: OPSSchemaV3.self,
            plan: V2ToV3OnlyMigrationPlan.self
        )
        try assertMigrates(
            name: "V3->V4",
            sourceSchema: OPSSchemaV3.self,
            targetSchema: OPSSchemaV4.self,
            plan: V3ToV4OnlyMigrationPlan.self
        )
        try assertMigrates(
            name: "V4->V5",
            sourceSchema: OPSSchemaV4.self,
            targetSchema: OPSSchemaV5.self,
            plan: V4ToV5OnlyMigrationPlan.self
        )
        try assertMigrates(
            name: "V5->V6",
            sourceSchema: OPSSchemaV5.self,
            targetSchema: OPSSchemaV6.self,
            plan: V5ToV6OnlyMigrationPlan.self
        )
        try assertMigrates(
            name: "V6->V7",
            sourceSchema: OPSSchemaV6.self,
            targetSchema: OPSSchemaV7.self,
            plan: V6ToV7OnlyMigrationPlan.self
        )
        try assertMigrates(
            name: "V7->V8",
            sourceSchema: OPSSchemaV7.self,
            targetSchema: OPSSchemaV8.self,
            plan: V7ToV8OnlyMigrationPlan.self
        )
    }

    func testMigrationPlanStagesHaveModelSetDeltasThroughV8() {
        let schemas = OPSMigrationPlan.schemas
        XCTAssertEqual(OPSMigrationPlan.stages.count, 7)

        let versionIdentifiers = schemas.map { String(describing: $0.versionIdentifier) }
        XCTAssertEqual(versionIdentifiers, [
            "1.0.0",
            "2.0.0",
            "3.0.0",
            "4.0.0",
            "5.0.0",
            "6.0.0",
            "7.0.0",
            "8.0.0"
        ])

        for pair in zip(schemas, schemas.dropFirst()) {
            XCTAssertNotEqual(
                migrationModelIdentitySet(pair.0),
                migrationModelIdentitySet(pair.1),
                "\(pair.0.versionIdentifier) and \(pair.1.versionIdentifier) must not share the same migration model fingerprint inputs."
            )
        }
    }

    func testV8OwnsProductBundleItemRelationshipShapeWithoutChangingHistoricalSchemas() {
        XCTAssertTrue(OPSSchemaV3.models.contains { $0 == OPSSchemaLegacyCatalogModels.ProductBundleItem.self })
        XCTAssertTrue(OPSSchemaV7.models.contains { $0 == OPSSchemaLegacyCatalogModels.ProductBundleItem.self })
        XCTAssertFalse(OPSSchemaV7.models.contains { $0 == ProductBundleItem.self })

        XCTAssertTrue(OPSSchemaV8.models.contains { $0 == ProductBundleItem.self })
        XCTAssertFalse(OPSSchemaV8.models.contains { $0 == OPSSchemaLegacyCatalogModels.ProductBundleItem.self })
    }

    func testBundleRelationshipGroupingSeparatesRequiredAndSuggestedChildren() {
        let required = bundleItem(id: "required", relationshipKind: .required, displayOrder: 20)
        let suggested = bundleItem(id: "suggested", relationshipKind: .suggested, displayOrder: 10)
        let earlierRequired = bundleItem(id: "required_early", relationshipKind: .required, displayOrder: 5)

        let grouped = ProductBundleCompositionGrouping.group([required, suggested, earlierRequired])

        XCTAssertEqual(grouped.required.map(\.id), ["required_early", "required"])
        XCTAssertEqual(grouped.suggested.map(\.id), ["suggested"])
    }

    func testCatalogProductOptionMappingValidatorRejectsMismatchedValueParents() {
        let family = CatalogItem(id: "family_membrane", companyId: companyId, name: "Membrane")
        let thickness = CatalogOption(id: "catalog_option_thickness", catalogItemId: family.id, name: "Thickness")
        let sixtyMil = CatalogOptionValue(id: "catalog_value_60", optionId: thickness.id, value: "60 mil")
        let product = Product(id: "product_membrane", companyId: companyId, name: "Membrane", type: .material, kind: .good)
        let productThickness = ProductOption(id: "product_option_thickness", productId: product.id, name: "Thickness", kind: .select)
        let wrongProductOption = ProductOption(id: "product_option_color", productId: product.id, name: "Color", kind: .select)
        let productSixtyMil = ProductOptionValue(id: "product_value_60", optionId: wrongProductOption.id, value: "60 mil")
        let mapping = CatalogProductOptionMapping(
            id: "mapping_bad_value_parent",
            companyId: companyId,
            productId: product.id,
            catalogItemId: family.id,
            catalogOptionId: thickness.id,
            productOptionId: productThickness.id,
            catalogOptionValueId: sixtyMil.id,
            productOptionValueId: productSixtyMil.id,
            mappingKind: .value
        )

        let violations = CatalogProductOptionMappingValidator.validate(
            mappings: [mapping],
            catalogOptions: [thickness],
            catalogOptionValues: [sixtyMil],
            productOptions: [productThickness, wrongProductOption],
            productOptionValues: [productSixtyMil]
        )

        XCTAssertEqual(violations, [.productValueDoesNotBelongToMappedOption(mappingId: mapping.id)])
    }

    func testCatalogSetupProductOptionChangeClearsStaleValueSelectionsForAttribute() {
        let attribute = CatalogSetupAttributeDraft(
            id: "axis_color",
            name: "Color",
            values: [
                CatalogSetupAttributeValueDraft(id: "catalog_black", value: "Black"),
                CatalogSetupAttributeValueDraft(id: "catalog_white", value: "White")
            ]
        )
        var optionSelection = ["axis_color": "product_option_color"]
        var valueSelection = [
            "catalog_black": "product_value_black",
            "catalog_white": "product_value_white",
            "other_axis_value": "keep_me"
        ]

        CatalogSetupWorkflow.setProductOptionSelection(
            attributeId: attribute.id,
            selectedProductOptionId: "product_option_finish",
            attributes: [attribute],
            productOptionSelectionByAttributeId: &optionSelection,
            productValueSelectionByCatalogValueId: &valueSelection
        )

        XCTAssertEqual(optionSelection["axis_color"], "product_option_finish")
        XCTAssertNil(valueSelection["catalog_black"])
        XCTAssertNil(valueSelection["catalog_white"])
        XCTAssertEqual(valueSelection["other_axis_value"], "keep_me")
    }

    func testCatalogSetupSanitizesMappingsToSelectOptionsAndMatchingValues() {
        let color = CatalogSetupAttributeDraft(
            id: "axis_color",
            name: "Color",
            values: [
                CatalogSetupAttributeValueDraft(id: "catalog_black", value: "Black"),
                CatalogSetupAttributeValueDraft(id: "catalog_white", value: "White")
            ]
        )
        let thickness = CatalogSetupAttributeDraft(
            id: "axis_thickness",
            name: "Thickness",
            values: [CatalogSetupAttributeValueDraft(id: "catalog_60", value: "60 mil")]
        )
        let product = Product(id: "product_membrane", companyId: companyId, name: "Membrane", type: .material, kind: .good)
        let selectColor = ProductOption(id: "product_color", productId: product.id, name: "Color", kind: .select)
        let integerThickness = ProductOption(id: "product_thickness", productId: product.id, name: "Thickness", kind: .integer)
        let black = ProductOptionValue(id: "product_black", optionId: selectColor.id, value: "Black")
        let staleThicknessValue = ProductOptionValue(id: "product_60", optionId: integerThickness.id, value: "60 mil")

        var optionSelection = [
            color.id: selectColor.id,
            thickness.id: integerThickness.id
        ]
        var valueSelection = [
            "catalog_black": black.id,
            "catalog_white": staleThicknessValue.id,
            "catalog_60": staleThicknessValue.id
        ]

        CatalogSetupWorkflow.sanitizeProductOptionMappingSelections(
            attributes: [color, thickness],
            productOptions: [selectColor, integerThickness],
            productOptionValues: [black, staleThicknessValue],
            productOptionSelectionByAttributeId: &optionSelection,
            productValueSelectionByCatalogValueId: &valueSelection
        )

        XCTAssertEqual(optionSelection[color.id], selectColor.id)
        XCTAssertNil(optionSelection[thickness.id])
        XCTAssertEqual(valueSelection["catalog_black"], black.id)
        XCTAssertNil(valueSelection["catalog_white"])
        XCTAssertNil(valueSelection["catalog_60"])
    }

    func testCatalogSetupMappingDraftValidationBlocksStaleProductValueParents() {
        let attribute = CatalogSetupAttributeDraft(
            id: "catalog_option_color",
            name: "Color",
            values: [CatalogSetupAttributeValueDraft(id: "catalog_value_black", value: "Black")]
        )
        let product = Product(id: "product_membrane", companyId: companyId, name: "Membrane", type: .material, kind: .good)
        let productColor = ProductOption(id: "product_option_color", productId: product.id, name: "Color", kind: .select)
        let productFinish = ProductOption(id: "product_option_finish", productId: product.id, name: "Finish", kind: .select)
        let staleValue = ProductOptionValue(id: "product_value_matte", optionId: productFinish.id, value: "Matte")

        let violations = CatalogSetupWorkflow.validateProductOptionMappingDraft(
            companyId: companyId,
            productId: product.id,
            attributes: [attribute],
            productOptionSelectionByAttributeId: [attribute.id: productColor.id],
            productValueSelectionByCatalogValueId: ["catalog_value_black": staleValue.id],
            productOptions: [productColor, productFinish],
            productOptionValues: [staleValue]
        )

        XCTAssertEqual(violations, [.productValueDoesNotBelongToMappedOption(mappingId: "catalog_option_color::catalog_value_black")])
    }

    func testCatalogSetupMappingDraftValidationBlocksNonSelectProductOptions() {
        let attribute = CatalogSetupAttributeDraft(
            id: "catalog_option_thickness",
            name: "Thickness",
            values: [CatalogSetupAttributeValueDraft(id: "catalog_value_60", value: "60 mil")]
        )
        let product = Product(id: "product_membrane", companyId: companyId, name: "Membrane", type: .material, kind: .good)
        let integerThickness = ProductOption(id: "product_option_thickness", productId: product.id, name: "Thickness", kind: .integer)

        let violations = CatalogSetupWorkflow.validateProductOptionMappingDraft(
            companyId: companyId,
            productId: product.id,
            attributes: [attribute],
            productOptionSelectionByAttributeId: [attribute.id: integerThickness.id],
            productValueSelectionByCatalogValueId: [:],
            productOptions: [integerThickness],
            productOptionValues: []
        )

        XCTAssertEqual(violations, [.productOptionMustBeSelect(mappingId: "catalog_option_thickness::axis")])
    }

    func testCatalogSetupPreflightBlocksStockUnitsBeforeAnyWritesWhenCapabilityUnavailable() {
        let stockDraft = CatalogSetupStockUnitDraft(unitKind: .roll, remainingLengthValue: 20, quantityValue: 1)
        let variant = CatalogSetupVariantDraft(optionValueIds: ["value_black"], stockUnits: [stockDraft])

        XCTAssertThrowsError(
            try CatalogSetupWorkflow.preflightCommit(
                variants: [variant],
                capabilities: CatalogSchemaCapabilities(
                    catalogStockUnits: false,
                    catalogProductOptionMappings: true,
                    productBundleRelationshipFields: true
                )
            )
        ) { error in
            XCTAssertEqual(error as? CatalogSetupCommitPreflightError, .catalogStockUnitsUnavailable)
        }
    }

    func testCatalogSetupSavePayloadEncodesCompleteDraftGraphForRPC() throws {
        let thickness = CatalogSetupAttributeDraft(
            id: "axis_thickness",
            name: "Thickness",
            values: [CatalogSetupAttributeValueDraft(id: "value_60", value: "60 mil")]
        )
        let color = CatalogSetupAttributeDraft(
            id: "axis_color",
            name: "Color",
            values: [CatalogSetupAttributeValueDraft(id: "value_black", value: "Black")]
        )
        let stockUnit = CatalogSetupStockUnitDraft(
            id: "stock_roll_a",
            unitKind: .roll,
            label: "Roll A",
            lotCode: "LOT-7",
            widthValue: 6,
            widthUnit: "ft",
            originalLengthValue: 75,
            remainingLengthValue: 72,
            lengthUnit: "ft",
            quantityValue: 1,
            location: "Truck 2",
            status: .partial,
            notes: "shop"
        )
        let variant = CatalogSetupVariantDraft(
            id: "variant_60_black",
            optionValueIdsByAttributeId: [
                thickness.id: "value_60",
                color.id: "value_black"
            ],
            optionValueIds: ["value_60", "value_black"],
            sku: " MEM-60-BLK ",
            warningThresholdText: "10",
            criticalThresholdText: "2",
            unitId: "unit_sqft",
            stockUnits: [stockUnit]
        )
        let product = Product(
            id: "product_membrane",
            companyId: companyId,
            name: "Vinyl membrane",
            type: .material,
            kind: .good,
            basePrice: 0,
            pricingUnit: .sqft
        )
        let productThickness = ProductOption(
            id: "product_option_thickness",
            productId: product.id,
            name: "Thickness",
            kind: .select
        )
        let productSixtyMil = ProductOptionValue(
            id: "product_value_60",
            optionId: productThickness.id,
            value: "60 mil"
        )

        let payload = CatalogSetupWorkflow.makeSavePayload(
            draftId: "draft_001",
            familyName: " Vinyl membrane ",
            familyDescription: " 60 mil stock ",
            familyImageUrl: " https://example.test/family.png ",
            selectedCategoryId: "category_membrane",
            selectedUnitId: "unit_sqft",
            defaultWarningThreshold: 10,
            defaultCriticalThreshold: 2,
            attributes: [thickness, color],
            variants: [variant],
            selectedProduct: product,
            productOptionSelectionByAttributeId: [thickness.id: "product_option_thickness"],
            productValueSelectionByCatalogValueId: ["value_60": "product_value_60"],
            productOptions: [productThickness],
            productOptionValues: [productSixtyMil],
            deletedIds: CatalogSetupDeletedIds(catalogOptions: ["deleted_option"]),
            appVersion: "1.0"
        )
        let object = try encodedJSONObject(payload)

        XCTAssertEqual(object["mode"] as? String, "create")
        XCTAssertEqual(object["draft_id"] as? String, "draft_001")
        XCTAssertEqual(object["client_schema_version"] as? Int, 1)

        let family = try XCTUnwrap(object["family"] as? [String: Any])
        XCTAssertEqual(family["client_id"] as? String, "family:draft_001")
        XCTAssertEqual(family["name"] as? String, "Vinyl membrane")
        XCTAssertEqual(family["description"] as? String, "60 mil stock")
        XCTAssertEqual(family["category_id"] as? String, "category_membrane")
        XCTAssertEqual(family["unit_id"] as? String, "unit_sqft")

        let catalogOptions = try XCTUnwrap(object["catalog_options"] as? [[String: Any]])
        XCTAssertEqual(catalogOptions.count, 2)
        XCTAssertEqual(catalogOptions[0]["client_id"] as? String, thickness.id)
        XCTAssertEqual(catalogOptions[0]["name"] as? String, "Thickness")
        XCTAssertEqual((catalogOptions[0]["values"] as? [[String: Any]])?.first?["client_id"] as? String, "value_60")

        let variants = try XCTUnwrap(object["variants"] as? [[String: Any]])
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants[0]["client_id"] as? String, variant.id)
        XCTAssertEqual(variants[0]["sku"] as? String, "MEM-60-BLK")
        XCTAssertEqual(variants[0]["quantity"] as? Double, 432)
        XCTAssertEqual(variants[0]["option_value_client_ids"] as? [String], ["value_60", "value_black"])

        let stockUnits = try XCTUnwrap(object["stock_units"] as? [[String: Any]])
        XCTAssertEqual(stockUnits.count, 1)
        XCTAssertEqual(stockUnits[0]["client_id"] as? String, stockUnit.id)
        XCTAssertEqual(stockUnits[0]["variant_client_id"] as? String, variant.id)
        XCTAssertEqual(stockUnits[0]["unit_kind"] as? String, "roll")
        XCTAssertEqual(stockUnits[0]["status"] as? String, "partial")

        let stockUnitEvents = try XCTUnwrap(object["stock_unit_events"] as? [[String: Any]])
        XCTAssertEqual(stockUnitEvents.count, 1)
        XCTAssertEqual(stockUnitEvents[0]["stock_unit_client_id"] as? String, stockUnit.id)
        XCTAssertEqual(stockUnitEvents[0]["variant_client_id"] as? String, variant.id)
        XCTAssertEqual(stockUnitEvents[0]["event_type"] as? String, "receive")
        XCTAssertEqual(stockUnitEvents[0]["to_status"] as? String, "partial")
        XCTAssertEqual(stockUnitEvents[0]["quantity_delta"] as? Double, 1)
        XCTAssertEqual(stockUnitEvents[0]["remaining_length_delta"] as? Double, 72)
        XCTAssertEqual(stockUnitEvents[0]["marker"] as? String, "ios_catalog_setup_lifecycle")

        let products = try XCTUnwrap(object["products"] as? [[String: Any]])
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products[0]["id"] as? String, product.id)
        XCTAssertEqual(products[0]["client_id"] as? String, "product:\(product.id)")
        XCTAssertEqual(products[0]["linked_catalog_item_client_id"] as? String, "family:draft_001")
        let productOptionsPayload = try XCTUnwrap(products[0]["options"] as? [[String: Any]])
        XCTAssertEqual(productOptionsPayload.count, 1)
        XCTAssertEqual(productOptionsPayload[0]["id"] as? String, productThickness.id)
        XCTAssertEqual(productOptionsPayload[0]["client_id"] as? String, "product-option:\(productThickness.id)")
        XCTAssertEqual(productOptionsPayload[0]["name"] as? String, "Thickness")
        XCTAssertEqual(productOptionsPayload[0]["kind"] as? String, "select")
        XCTAssertEqual((productOptionsPayload[0]["values"] as? [[String: Any]])?.first?["id"] as? String, productSixtyMil.id)
        XCTAssertEqual((products[0]["pricing_modifiers"] as? [Any])?.count, 0)
        XCTAssertEqual((products[0]["product_materials"] as? [Any])?.count, 0)
        XCTAssertEqual((products[0]["bundle_items"] as? [Any])?.count, 0)

        let mappings = try XCTUnwrap(products[0]["catalog_option_mappings"] as? [[String: Any]])
        XCTAssertEqual(mappings.count, 2)
        XCTAssertEqual(mappings[0]["mapping_kind"] as? String, "axis")
        XCTAssertEqual(mappings[0]["catalog_option_client_id"] as? String, thickness.id)
        XCTAssertEqual(mappings[0]["product_option_id"] as? String, "product_option_thickness")
        XCTAssertEqual(mappings[1]["mapping_kind"] as? String, "value")
        XCTAssertEqual(mappings[1]["catalog_option_value_client_id"] as? String, "value_60")
        XCTAssertEqual(mappings[1]["product_option_value_client_id"] as? String, "product-option-value:product_value_60")
        XCTAssertNil(mappings[1]["product_option_value_id"])

        XCTAssertEqual((object["product_materials"] as? [Any])?.count, 0)
        let deletedIds = try XCTUnwrap(object["deleted_ids"] as? [String: Any])
        XCTAssertEqual(deletedIds["catalog_options"] as? [String], ["deleted_option"])
        XCTAssertEqual(deletedIds["product_bundle_items"] as? [String], [])
        XCTAssertEqual(deletedIds["catalog_product_option_mappings"] as? [String], [])
    }

    func testInboundCatalogSetupSyncIncludesProductsBeforeProductOptions() throws {
        let inboundTables = InboundProcessor.syncOrder.map(\.supabaseTable)
        let dataActorTables = DataActor.syncOrder.map(\.supabaseTable)

        let inboundProductIndex = try? XCTUnwrap(inboundTables.firstIndex(of: "products"))
        let inboundOptionIndex = try? XCTUnwrap(inboundTables.firstIndex(of: "product_options"))
        let dataActorProductIndex = try? XCTUnwrap(dataActorTables.firstIndex(of: "products"))
        let dataActorOptionIndex = try? XCTUnwrap(dataActorTables.firstIndex(of: "product_options"))

        XCTAssertLessThan(try XCTUnwrap(inboundProductIndex), try XCTUnwrap(inboundOptionIndex))
        XCTAssertLessThan(try XCTUnwrap(dataActorProductIndex), try XCTUnwrap(dataActorOptionIndex))
    }

    func testProductSyncMergeMakesActiveProductsAvailableToCatalogSetupPickerSource() throws {
        let container = try makeProductOnlyInMemoryContainer()
        let context = ModelContext(container)
        let dto = ProductDTO(
            id: "product_membrane",
            companyId: companyId,
            name: "Vinyl membrane",
            description: "Stock-linked product",
            basePrice: 12.5,
            unitCost: 5,
            unit: "sqft",
            category: "Membrane",
            categoryId: "category_membrane",
            sku: "MEM-60",
            thumbnailUrl: nil,
            kind: "material",
            pricingUnit: "sqft",
            type: "MATERIAL",
            isTaxable: true,
            isActive: true,
            isFavorite: false,
            minimumCharge: nil,
            minimumQuantity: nil,
            showBomOnEstimate: false,
            showInStorefront: false,
            tieredPricing: nil,
            taskTypeId: nil,
            taskTypeRef: nil,
            unitId: "unit_sqft",
            linkedCatalogItemId: nil,
            bundlePricingMode: nil,
            createdAt: "2026-05-26T10:00:00Z",
            updatedAt: "2026-05-26T11:00:00Z"
        )

        try ProductSyncLocalStore.merge(dto: dto, context: context)
        try context.save()

        let products = try context.fetch(FetchDescriptor<Product>())
            .filter { $0.companyId == companyId && $0.isActive }

        XCTAssertEqual(products.map(\.id), [dto.id])
        XCTAssertEqual(products.first?.name, "Vinyl membrane")
        XCTAssertEqual(products.first?.pricingUnit, .sqft)
    }

    func testCatalogSetupSavePayloadKeepsGaugeAndFinishValueMappingsResolvableForRPC() throws {
        let gauge = CatalogSetupAttributeDraft(
            id: "axis_gauge",
            name: "Gauge",
            values: [
                CatalogSetupAttributeValueDraft(id: "catalog_value_24", value: "24 ga"),
                CatalogSetupAttributeValueDraft(id: "catalog_value_26", value: "26 ga")
            ]
        )
        let finish = CatalogSetupAttributeDraft(
            id: "axis_finish",
            name: "Finish",
            values: [
                CatalogSetupAttributeValueDraft(id: "catalog_value_black", value: "Black"),
                CatalogSetupAttributeValueDraft(id: "catalog_value_white", value: "White")
            ]
        )
        let product = Product(
            id: "11111111-1111-4111-8111-111111111111",
            companyId: companyId,
            name: "Metal panel",
            type: .material,
            kind: .good
        )
        let gaugeOption = ProductOption(
            id: "22222222-2222-4222-8222-222222222222",
            productId: product.id,
            name: "Gauge",
            kind: .select
        )
        let finishOption = ProductOption(
            id: "33333333-3333-4333-8333-333333333333",
            productId: product.id,
            name: "Finish",
            kind: .select
        )
        let gauge24 = ProductOptionValue(id: "local_gauge_24", optionId: gaugeOption.id, value: "24 ga")
        let gauge26 = ProductOptionValue(id: "local_gauge_26", optionId: gaugeOption.id, value: "26 ga")
        let black = ProductOptionValue(
            id: "44444444-4444-4444-8444-444444444444",
            optionId: finishOption.id,
            value: "Black"
        )
        let white = ProductOptionValue(
            id: "55555555-5555-4555-8555-555555555555",
            optionId: finishOption.id,
            value: "White"
        )

        let payload = CatalogSetupWorkflow.makeSavePayload(
            draftId: "draft_mapping_multi_axis",
            familyName: "Metal panel",
            familyDescription: "",
            familyImageUrl: "",
            selectedCategoryId: nil,
            selectedUnitId: nil,
            defaultWarningThreshold: nil,
            defaultCriticalThreshold: nil,
            attributes: [gauge, finish],
            variants: [],
            selectedProduct: product,
            productOptionSelectionByAttributeId: [
                gauge.id: gaugeOption.id,
                finish.id: finishOption.id
            ],
            productValueSelectionByCatalogValueId: [
                "catalog_value_24": gauge24.id,
                "catalog_value_26": gauge26.id,
                "catalog_value_black": black.id,
                "catalog_value_white": white.id
            ],
            productOptions: [gaugeOption, finishOption],
            productOptionValues: [gauge24, gauge26, black, white],
            appVersion: "1.0"
        )

        let mappings = try XCTUnwrap(payload.products.first?.catalogOptionMappings)
        let gaugeValueMappings = mappings.filter {
            $0.mappingKind == CatalogProductOptionMappingKind.value.rawValue &&
            $0.catalogOptionClientId == gauge.id
        }
        let finishValueMappings = mappings.filter {
            $0.mappingKind == CatalogProductOptionMappingKind.value.rawValue &&
            $0.catalogOptionClientId == finish.id
        }

        XCTAssertEqual(mappings.filter { $0.mappingKind == CatalogProductOptionMappingKind.axis.rawValue }.count, 2)
        XCTAssertEqual(gaugeValueMappings.map(\.productOptionValueClientId), [
            "product-option-value:\(gauge24.id)",
            "product-option-value:\(gauge26.id)"
        ])
        XCTAssertTrue(gaugeValueMappings.allSatisfy { $0.productOptionValueId == nil })
        XCTAssertEqual(finishValueMappings.map(\.productOptionValueClientId), [
            "product-option-value:\(black.id)",
            "product-option-value:\(white.id)"
        ])
        XCTAssertEqual(finishValueMappings.map(\.productOptionValueId), [black.id, white.id])
    }

    func testCatalogSetupSavePayloadKeepsSelectedExistingProductIdForRPC() throws {
        let product = Product(
            id: "11111111-1111-4111-8111-111111111111",
            companyId: companyId,
            name: "Existing membrane install",
            type: .material,
            kind: .good,
            basePrice: 12,
            pricingUnit: .sqft
        )

        let payload = CatalogSetupWorkflow.makeSavePayload(
            draftId: "draft_existing_product",
            familyName: "Vinyl membrane",
            familyDescription: "",
            familyImageUrl: "",
            selectedCategoryId: nil,
            selectedUnitId: nil,
            defaultWarningThreshold: nil,
            defaultCriticalThreshold: nil,
            attributes: [],
            variants: [],
            selectedProduct: product,
            productOptionSelectionByAttributeId: [:],
            productValueSelectionByCatalogValueId: [:],
            productOptions: [],
            productOptionValues: [],
            deletedIds: CatalogSetupDeletedIds(),
            appVersion: "1.0"
        )

        let productPayload = try XCTUnwrap(payload.products.first)

        XCTAssertEqual(productPayload.id, product.id)
        XCTAssertEqual(productPayload.clientId, "product:\(product.id)")
        XCTAssertEqual(productPayload.linkedCatalogItemClientId, "family:draft_existing_product")
        XCTAssertNil(productPayload.linkedCatalogItemId)
    }

    func testCatalogSetupUpdatePayloadPreservesServerIdsAndExplicitDeletesOnly() throws {
        let existingFamilyId = "family_existing"
        let existingOptionId = "option_existing"
        let existingValueId = "value_existing"
        let newOptionClientId = "client_option_new"
        let newValueClientId = "client_value_new"
        let existingVariantId = "variant_existing"
        let newVariantClientId = "client_variant_new"
        let existingStockUnitId = "stock_unit_existing"
        let newStockUnitClientId = "client_stock_unit_new"
        let omittedExistingVariantId = "variant_existing_omitted"

        let existingAttribute = CatalogSetupAttributeDraft(
            id: existingOptionId,
            serverId: existingOptionId,
            name: "Thickness",
            values: [
                CatalogSetupAttributeValueDraft(
                    id: existingValueId,
                    serverId: existingValueId,
                    value: "60 mil"
                )
            ]
        )
        let newAttribute = CatalogSetupAttributeDraft(
            id: newOptionClientId,
            name: "Color",
            values: [
                CatalogSetupAttributeValueDraft(id: newValueClientId, value: "Black")
            ]
        )
        let existingStockUnit = CatalogSetupStockUnitDraft(
            id: existingStockUnitId,
            serverId: existingStockUnitId,
            unitKind: .roll,
            label: "Roll A",
            widthValue: 6,
            originalLengthValue: 75,
            remainingLengthValue: 72,
            quantityValue: 1,
            status: .partial
        )
        let newStockUnit = CatalogSetupStockUnitDraft(
            id: newStockUnitClientId,
            unitKind: .box,
            label: "Box A",
            quantityValue: 3,
            status: .full
        )
        let existingVariant = CatalogSetupVariantDraft(
            id: existingVariantId,
            serverId: existingVariantId,
            optionValueIdsByAttributeId: [existingOptionId: existingValueId],
            optionValueIds: [existingValueId],
            sku: "MEM-60",
            stockUnits: [existingStockUnit]
        )
        let newVariant = CatalogSetupVariantDraft(
            id: newVariantClientId,
            optionValueIdsByAttributeId: [
                existingOptionId: existingValueId,
                newOptionClientId: newValueClientId
            ],
            optionValueIds: [existingValueId, newValueClientId],
            sku: "MEM-60-BLK",
            stockUnits: [newStockUnit]
        )
        let explicitDeletedIds = CatalogSetupDeletedIds(
            catalogOptionValues: ["value_deleted_explicit"],
            catalogStockUnits: ["stock_unit_deleted_explicit"]
        )

        let payload = CatalogSetupWorkflow.makeSavePayload(
            mode: "update",
            draftId: "draft_update_existing_family",
            existingFamilyId: existingFamilyId,
            familyName: "Vinyl membrane",
            familyDescription: "",
            familyImageUrl: "",
            selectedCategoryId: nil,
            selectedUnitId: nil,
            defaultWarningThreshold: nil,
            defaultCriticalThreshold: nil,
            attributes: [existingAttribute, newAttribute],
            variants: [existingVariant, newVariant],
            selectedProduct: nil,
            productOptionSelectionByAttributeId: [:],
            productValueSelectionByCatalogValueId: [:],
            productOptions: [],
            productOptionValues: [],
            deletedIds: explicitDeletedIds,
            appVersion: "1.0"
        )
        let object = try encodedJSONObject(payload)

        XCTAssertEqual(payload.mode, "edit")
        XCTAssertEqual(payload.family.id, existingFamilyId)
        XCTAssertEqual(payload.family.clientId, "family:\(existingFamilyId)")

        XCTAssertEqual(payload.catalogOptions[0].id, existingOptionId)
        XCTAssertEqual(payload.catalogOptions[0].clientId, existingOptionId)
        XCTAssertEqual(payload.catalogOptions[0].values[0].id, existingValueId)
        XCTAssertEqual(payload.catalogOptions[0].values[0].clientId, existingValueId)
        XCTAssertNil(payload.catalogOptions[1].id)
        XCTAssertEqual(payload.catalogOptions[1].clientId, newOptionClientId)
        XCTAssertNil(payload.catalogOptions[1].values[0].id)
        XCTAssertEqual(payload.catalogOptions[1].values[0].clientId, newValueClientId)

        XCTAssertEqual(payload.variants[0].id, existingVariantId)
        XCTAssertEqual(payload.variants[0].clientId, existingVariantId)
        XCTAssertNil(payload.variants[1].id)
        XCTAssertEqual(payload.variants[1].clientId, newVariantClientId)

        XCTAssertEqual(payload.stockUnits[0].id, existingStockUnitId)
        XCTAssertEqual(payload.stockUnits[0].clientId, existingStockUnitId)
        XCTAssertEqual(payload.stockUnits[0].catalogVariantId, existingVariantId)
        XCTAssertNil(payload.stockUnits[1].id)
        XCTAssertEqual(payload.stockUnits[1].clientId, newStockUnitClientId)
        XCTAssertNil(payload.stockUnits[1].catalogVariantId)

        XCTAssertEqual(payload.deletedIds.catalogOptionValues, ["value_deleted_explicit"])
        XCTAssertEqual(payload.deletedIds.catalogStockUnits, ["stock_unit_deleted_explicit"])
        XCTAssertFalse(payload.deletedIds.catalogVariants.contains(omittedExistingVariantId))

        let deletedIds = try XCTUnwrap(object["deleted_ids"] as? [String: Any])
        XCTAssertEqual(deletedIds["catalog_option_values"] as? [String], ["value_deleted_explicit"])
        XCTAssertEqual(deletedIds["catalog_stock_units"] as? [String], ["stock_unit_deleted_explicit"])
        XCTAssertEqual(deletedIds["catalog_variants"] as? [String], [])
    }

    func testCatalogSetupUpdatePayloadPreservesKnownCatalogProductOptionMappingIds() throws {
        let existingFamilyId = "family_existing"
        let existingOptionId = "option_existing"
        let existingValueId = "value_existing"
        let product = Product(
            id: "product_membrane",
            companyId: companyId,
            name: "Vinyl membrane",
            type: .material,
            kind: .good,
            basePrice: 0,
            pricingUnit: .sqft
        )
        let productThickness = ProductOption(
            id: "product_option_thickness",
            productId: product.id,
            name: "Thickness",
            kind: .select
        )
        let productSixtyMil = ProductOptionValue(
            id: "product_value_60",
            optionId: productThickness.id,
            value: "60 mil"
        )
        let attribute = CatalogSetupAttributeDraft(
            id: existingOptionId,
            serverId: existingOptionId,
            name: "Thickness",
            values: [
                CatalogSetupAttributeValueDraft(
                    id: existingValueId,
                    serverId: existingValueId,
                    value: "60 mil"
                )
            ]
        )
        let axisMapping = CatalogProductOptionMapping(
            id: "mapping_axis_existing",
            companyId: companyId,
            productId: product.id,
            catalogItemId: existingFamilyId,
            catalogOptionId: existingOptionId,
            productOptionId: productThickness.id,
            mappingKind: .axis
        )
        let valueMapping = CatalogProductOptionMapping(
            id: "mapping_value_existing",
            companyId: companyId,
            productId: product.id,
            catalogItemId: existingFamilyId,
            catalogOptionId: existingOptionId,
            productOptionId: productThickness.id,
            catalogOptionValueId: existingValueId,
            productOptionValueId: productSixtyMil.id,
            mappingKind: .value
        )

        let payload = CatalogSetupWorkflow.makeSavePayload(
            mode: "update",
            draftId: "draft_update_existing_family",
            existingFamilyId: existingFamilyId,
            familyName: "Vinyl membrane",
            familyDescription: "",
            familyImageUrl: "",
            selectedCategoryId: nil,
            selectedUnitId: nil,
            defaultWarningThreshold: nil,
            defaultCriticalThreshold: nil,
            attributes: [attribute],
            variants: [],
            selectedProduct: product,
            productOptionSelectionByAttributeId: [attribute.id: productThickness.id],
            productValueSelectionByCatalogValueId: [existingValueId: productSixtyMil.id],
            productOptions: [productThickness],
            productOptionValues: [productSixtyMil],
            catalogProductOptionMappings: [axisMapping, valueMapping],
            deletedIds: CatalogSetupDeletedIds(),
            appVersion: "1.0"
        )

        let mappings = try XCTUnwrap(payload.products.first?.catalogOptionMappings)

        XCTAssertEqual(mappings.compactMap(\.id), ["mapping_axis_existing", "mapping_value_existing"])
        XCTAssertEqual(mappings.map(\.clientId), ["mapping_axis_existing", "mapping_value_existing"])
        XCTAssertEqual(payload.deletedIds.catalogProductOptionMappings, [])
    }

    func testCatalogSetupProductReconciliationPrefersRPCResolvedProductId() throws {
        let existingProductId = "11111111-1111-4111-8111-111111111111"
        let productPayload = CatalogSetupSavePayload.ProductPayload(
            id: existingProductId,
            clientId: "product:\(existingProductId)",
            kind: "good",
            type: "MATERIAL",
            name: "Existing membrane install",
            pricingUnit: "sqft",
            linkedCatalogItemClientId: "family:draft_existing_product",
            linkedCatalogItemId: nil,
            options: [],
            pricingModifiers: [],
            productMaterials: [],
            catalogOptionMappings: [],
            bundleItems: []
        )
        let response = CatalogSetupSaveResponse(
            ok: true,
            idMap: ["product:\(existingProductId)": existingProductId]
        )

        XCTAssertEqual(
            CatalogSetupWorkflow.resolvedProductId(for: productPayload, response: response),
            existingProductId
        )
    }

    func testCatalogSetupSaveMigrationReusesCompanyOwnedExistingProductIdsInCreateMode() throws {
        let sql = try catalogSetupSaveRPCMigrationSQL()

        XCTAssertTrue(
            sql.contains("where product_row.id = v_candidate_uuid")
                && sql.contains("and product_row.company_id = p_company_id"),
            "create-mode product preallocation must verify existing product ownership before reusing the submitted product id"
        )
        XCTAssertTrue(
            normalizedSQLWhitespace(sql).contains("where product_row.id = v_candidate_uuid and product_row.company_id = p_company_id ) then null;"),
            "company-owned existing product ids must pass through the create-mode preallocation block"
        )
        XCTAssertTrue(
            sql.contains("v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);"),
            "create-mode product preallocation must map product client_id to the existing product id"
        )
    }

    func testCatalogSetupSaveResponseDecodesStructuredRPCFields() throws {
        let json = """
        {
          "ok": true,
          "mode": "create",
          "company_id": "\(companyId)",
          "idempotency_key": "save-key-1",
          "warnings": [
            {
              "code": "suggested_addon_not_priced",
              "path": "products[0].bundle_items[0]",
              "message": "Suggested add-on has no pricing modifier."
            }
          ],
          "blockers": [],
          "id_map": {
            "family:draft_001": "00000000-0000-0000-0000-000000000001",
            "variant_60_black": "00000000-0000-0000-0000-000000000002"
          },
          "counts": { "catalog_items": 1, "catalog_stock_units": 1 },
          "deleted_counts": { "catalog_options": 0 },
          "validated_counts": { "variants": 1, "stock_units": 1 },
          "saved_at": "2026-05-25T00:00:00Z"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CatalogSetupSaveResponse.self, from: json)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.mode, "create")
        XCTAssertEqual(response.companyId, companyId)
        XCTAssertEqual(response.idempotencyKey, "save-key-1")
        XCTAssertEqual(response.warnings.first?.code, "suggested_addon_not_priced")
        XCTAssertTrue(response.blockers.isEmpty)
        XCTAssertEqual(response.idMap["family:draft_001"], "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(response.counts["catalog_stock_units"], 1)
        XCTAssertEqual(response.deletedCounts["catalog_options"], 0)
        XCTAssertEqual(response.validatedCounts["variants"], 1)
        XCTAssertEqual(response.savedAt, "2026-05-25T00:00:00Z")
    }

    func testCatalogSetupSaveAttemptReusesIdempotencyKeyForSamePayloadOnly() throws {
        var firstPayload = CatalogSetupSavePayload.minimalTestPayload(draftId: "draft_001", familyName: "Vinyl membrane")
        let firstAttempt = try CatalogSetupSaveAttempt.resolve(
            payload: firstPayload,
            existingAttempt: nil,
            makeKey: { "save-key-1" }
        )

        let retryAttempt = try CatalogSetupSaveAttempt.resolve(
            payload: firstPayload,
            existingAttempt: firstAttempt,
            makeKey: { "save-key-2" }
        )

        firstPayload.family.name = "Vinyl membrane revised"
        let changedAttempt = try CatalogSetupSaveAttempt.resolve(
            payload: firstPayload,
            existingAttempt: firstAttempt,
            makeKey: { "save-key-2" }
        )

        XCTAssertEqual(firstAttempt.idempotencyKey, "save-key-1")
        XCTAssertEqual(retryAttempt.idempotencyKey, "save-key-1")
        XCTAssertEqual(changedAttempt.idempotencyKey, "save-key-2")
        XCTAssertNotEqual(changedAttempt.payloadFingerprint, firstAttempt.payloadFingerprint)
    }

    func testCatalogSetupSaveFailureResolutionKeepsDraftAndPreservesBlockers() {
        let response = CatalogSetupSaveResponse(
            ok: false,
            mode: "create",
            companyId: companyId,
            idempotencyKey: "save-key-1",
            warnings: [],
            blockers: [
                CatalogSetupSaveIssue(
                    code: "matrix_signature_conflict",
                    path: "variants[0].option_value_client_ids",
                    message: "Variant matrix signature already exists for this family."
                )
            ],
            idMap: [:],
            counts: [:],
            deletedCounts: [:],
            validatedCounts: [:],
            savedAt: nil
        )

        let resolution = CatalogSetupWorkflow.resolveSaveResponse(response)

        XCTAssertFalse(resolution.shouldClearDraft)
        XCTAssertEqual(resolution.blockers, response.blockers)
        XCTAssertEqual(resolution.warnings, [])
        XCTAssertEqual(resolution.userFacingMessage, "Variant matrix signature already exists for this family.")
    }

    func testCatalogSetupDraftSnapshotRoundTripsCompleteResumeState() throws {
        let context = CatalogSetupDraftContext(companyId: companyId, userId: "user_catalog_foundation")
        let stockUnit = CatalogSetupStockUnitDraft(
            id: "stock_roll_a",
            unitKind: .roll,
            label: "Roll A",
            lotCode: "LOT-7",
            widthValue: 6,
            widthUnit: "ft",
            originalLengthValue: 75,
            remainingLengthValue: 72,
            lengthUnit: "ft",
            quantityValue: 1,
            location: "Truck 2",
            status: .partial,
            notes: "shop"
        )
        let snapshot = catalogSetupDraftSnapshot(
            context: context,
            activeSaveAttempt: CatalogSetupSaveAttempt(
                idempotencyKey: "save-key-1",
                payloadFingerprint: "fingerprint-1"
            ),
            rpcWarnings: [
                CatalogSetupSaveIssue(
                    code: "suggested_addon_not_priced",
                    path: "products[0].bundle_items[0]",
                    message: "Suggested add-on has no pricing modifier."
                )
            ],
            rpcBlockers: [
                CatalogSetupSaveIssue(
                    code: "matrix_signature_conflict",
                    path: "variants[0].option_value_client_ids",
                    message: "Variant matrix signature already exists."
                )
            ],
            stockUnit: stockUnit
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(CatalogSetupDraftSnapshot.self, from: data)

        XCTAssertEqual(restored.context, context)
        XCTAssertEqual(restored.draftId, "draft_resume_001")
        XCTAssertEqual(restored.selectedStep, CatalogSetupStep.stock.rawValue)
        XCTAssertEqual(restored.familyName, "Vinyl membrane")
        XCTAssertEqual(restored.attributes.first?.values.first?.id, "value_60")
        XCTAssertEqual(restored.setupVariants.first?.stockUnits.first, stockUnit)
        XCTAssertEqual(restored.selectedProductId, "product_membrane")
        XCTAssertEqual(restored.productOptionSelectionByAttributeId["axis_thickness"], "product_option_thickness")
        XCTAssertEqual(restored.productValueSelectionByCatalogValueId["value_60"], "product_value_60")
        XCTAssertEqual(restored.activeSaveAttempt?.idempotencyKey, "save-key-1")
        XCTAssertEqual(restored.rpcWarnings.first?.code, "suggested_addon_not_priced")
        XCTAssertEqual(restored.rpcBlockers.first?.code, "matrix_signature_conflict")
        XCTAssertEqual(restored.saveErrorMessage, "Server rejected catalog setup save.")
    }

    func testCatalogSetupDraftStoreScopesDraftsByCompanyAndUser() throws {
        let rootURL = try temporaryCatalogDraftRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = CatalogSetupDraftStore(rootURL: rootURL)
        let firstContext = CatalogSetupDraftContext(companyId: "company_a", userId: "user_1")
        let secondCompanyContext = CatalogSetupDraftContext(companyId: "company_b", userId: "user_1")
        let secondUserContext = CatalogSetupDraftContext(companyId: "company_a", userId: "user_2")

        try store.save(catalogSetupDraftSnapshot(context: firstContext, familyName: "Company A draft"))

        XCTAssertEqual(try store.load(context: firstContext)?.familyName, "Company A draft")
        XCTAssertNil(try store.load(context: secondCompanyContext))
        XCTAssertNil(try store.load(context: secondUserContext))
    }

    func testCatalogSetupDraftStoreClearRemovesOnlyMatchingContext() throws {
        let rootURL = try temporaryCatalogDraftRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = CatalogSetupDraftStore(rootURL: rootURL)
        let firstContext = CatalogSetupDraftContext(companyId: "company_a", userId: "user_1")
        let secondContext = CatalogSetupDraftContext(companyId: "company_b", userId: "user_1")

        try store.save(catalogSetupDraftSnapshot(context: firstContext, familyName: "Company A draft"))
        try store.save(catalogSetupDraftSnapshot(context: secondContext, familyName: "Company B draft"))
        try store.clear(context: firstContext)

        XCTAssertNil(try store.load(context: firstContext))
        XCTAssertEqual(try store.load(context: secondContext)?.familyName, "Company B draft")
    }

    func testCatalogSetupDraftRetainsFailedAttemptForUnchangedRetryAndRotatesAfterPayloadChange() throws {
        let context = CatalogSetupDraftContext(companyId: companyId, userId: "user_catalog_foundation")
        let payload = CatalogSetupSavePayload.minimalTestPayload(draftId: "draft_resume_001", familyName: "Vinyl membrane")
        let failedAttempt = try CatalogSetupSaveAttempt.resolve(
            payload: payload,
            existingAttempt: nil,
            makeKey: { "save-key-1" }
        )
        let snapshot = catalogSetupDraftSnapshot(context: context, activeSaveAttempt: failedAttempt)
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(CatalogSetupDraftSnapshot.self, from: data)

        let unchangedRetry = try CatalogSetupSaveAttempt.resolve(
            payload: payload,
            existingAttempt: restored.activeSaveAttempt,
            makeKey: { "save-key-2" }
        )
        var changedPayload = payload
        changedPayload.family.name = "Vinyl membrane revised"
        let changedRetry = try CatalogSetupSaveAttempt.resolve(
            payload: changedPayload,
            existingAttempt: restored.activeSaveAttempt,
            makeKey: { "save-key-2" }
        )

        XCTAssertEqual(unchangedRetry.idempotencyKey, "save-key-1")
        XCTAssertEqual(changedRetry.idempotencyKey, "save-key-2")
        XCTAssertNotEqual(changedRetry.payloadFingerprint, failedAttempt.payloadFingerprint)
    }

    func testCatalogVariantIdentityValidatorWarnsOnNormalizedDuplicateSKU() {
        let existing = CatalogVariant(
            id: "variant_existing",
            companyId: companyId,
            catalogItemId: "family_membrane",
            sku: "OPS-LEFT",
            quantity: 0
        )
        let draft = CatalogVariantDraftIdentity(
            id: nil,
            companyId: companyId,
            catalogItemId: "family_other",
            sku: " ops-left ",
            optionValueIds: ["value_black"]
        )

        let result = CatalogVariantIdentityValidator.validate(
            drafts: [draft],
            existingVariants: [existing],
            existingOptionValues: []
        )

        XCTAssertEqual(result.warnings, [.duplicateSKU(normalizedSKU: "ops-left", conflictingVariantId: existing.id)])
        XCTAssertTrue(result.blockingViolations.isEmpty)
        XCTAssertFalse(result.isBlocked)
    }

    func testCatalogVariantIdentityValidatorBlocksDuplicateMatrixSignatures() {
        let existing = CatalogVariant(
            id: "variant_existing",
            companyId: companyId,
            catalogItemId: "family_membrane",
            sku: "MEM-60-BLK",
            quantity: 0
        )
        let joins = [
            CatalogVariantOptionValue(variantId: existing.id, optionValueId: "value_black"),
            CatalogVariantOptionValue(variantId: existing.id, optionValueId: "value_60")
        ]
        let draft = CatalogVariantDraftIdentity(
            id: nil,
            companyId: companyId,
            catalogItemId: existing.catalogItemId,
            sku: "MEM-60-BLK-2",
            optionValueIds: ["value_60", "value_black"]
        )

        let result = CatalogVariantIdentityValidator.validate(
            drafts: [draft],
            existingVariants: [existing],
            existingOptionValues: joins
        )

        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.blockingViolations, [
            .duplicateMatrixSignature(
                catalogItemId: existing.catalogItemId,
                optionValueIds: ["value_60", "value_black"],
                conflictingVariantId: existing.id
            )
        ])
        XCTAssertTrue(result.isBlocked)
    }

    func testCatalogVariantIdentityValidatorBlocksDuplicateDraftMatrixSignatures() {
        let first = CatalogVariantDraftIdentity(
            id: "draft_1",
            companyId: companyId,
            catalogItemId: "family_membrane",
            sku: "MEM-60-BLK",
            optionValueIds: ["value_black", "value_60"]
        )
        let second = CatalogVariantDraftIdentity(
            id: "draft_2",
            companyId: companyId,
            catalogItemId: "family_membrane",
            sku: "MEM-60-BLK-ALT",
            optionValueIds: ["value_60", "value_black"]
        )

        let result = CatalogVariantIdentityValidator.validate(
            drafts: [first, second],
            existingVariants: [],
            existingOptionValues: []
        )

        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.blockingViolations, [
            .duplicateMatrixSignature(
                catalogItemId: "family_membrane",
                optionValueIds: ["value_black", "value_60"],
                conflictingVariantId: first.id
            )
        ])
    }

    func testCatalogSetupWorkflowGeneratesValidMatrixAndSkipsInvalidPartialCombinations() {
        let thickness = CatalogSetupAttributeDraft(
            id: "axis_thickness",
            name: "Thickness",
            values: [
                CatalogSetupAttributeValueDraft(id: "value_60", value: "60 mil"),
                CatalogSetupAttributeValueDraft(id: "value_68", value: "68 mil")
            ]
        )
        let color = CatalogSetupAttributeDraft(
            id: "axis_color",
            name: "Color",
            values: [
                CatalogSetupAttributeValueDraft(id: "value_tan", value: "tan"),
                CatalogSetupAttributeValueDraft(id: "value_grey", value: "grey")
            ]
        )
        let finish = CatalogSetupAttributeDraft(
            id: "axis_finish",
            name: "Finish",
            values: [
                CatalogSetupAttributeValueDraft(id: "value_smooth", value: "smooth"),
                CatalogSetupAttributeValueDraft(id: "value_textured", value: "textured")
            ]
        )

        let variants = CatalogSetupWorkflow.generateVariantDrafts(
            attributes: [thickness, color, finish],
            invalidCombinations: [
                CatalogSetupInvalidCombination(valueIds: ["value_60", "value_tan"])
            ]
        )

        XCTAssertEqual(variants.count, 6)
        XCTAssertFalse(variants.contains { $0.optionValueIds.isSuperset(of: ["value_60", "value_tan"]) })
        XCTAssertTrue(variants.contains { $0.optionValueIds == ["value_68", "value_tan", "value_smooth"] })
    }

    func testCatalogSetupWorkflowValidatesSkuAsWarningAndMatrixAsBlocker() {
        let existing = CatalogVariant(
            id: "variant_existing",
            companyId: companyId,
            catalogItemId: "family_membrane",
            sku: "MEM-68-TAN",
            quantity: 0
        )
        let joins = [
            CatalogVariantOptionValue(variantId: existing.id, optionValueId: "value_68"),
            CatalogVariantOptionValue(variantId: existing.id, optionValueId: "value_tan")
        ]
        var skuOnlyDraft = CatalogSetupVariantDraft(optionValueIds: ["value_60", "value_grey"])
        skuOnlyDraft.sku = " mem-68-tan "
        var duplicateMatrixDraft = CatalogSetupVariantDraft(optionValueIds: ["value_tan", "value_68"])
        duplicateMatrixDraft.sku = "MEM-68-TAN-ALT"

        let result = CatalogSetupWorkflow.validate(
            variants: [skuOnlyDraft, duplicateMatrixDraft],
            companyId: companyId,
            catalogItemId: existing.catalogItemId,
            existingVariants: [existing],
            existingOptionValues: joins
        )

        XCTAssertEqual(result.warnings, [.duplicateSKU(normalizedSKU: "mem-68-tan", conflictingVariantId: existing.id)])
        XCTAssertEqual(result.blockingViolations, [
            .duplicateMatrixSignature(
                catalogItemId: existing.catalogItemId,
                optionValueIds: ["value_68", "value_tan"],
                conflictingVariantId: existing.id
            )
        ])
        XCTAssertTrue(result.isBlocked)
    }

    func testCatalogSetupWorkflowMirrorsAvailableStockUnitAggregateToVariantQuantity() {
        let stockUnits = [
            CatalogSetupStockUnitDraft(
                unitKind: .roll,
                label: "ROLL 01",
                widthValue: 6,
                widthUnit: "ft",
                originalLengthValue: 75,
                remainingLengthValue: 75,
                lengthUnit: "ft",
                quantityValue: 1,
                status: .full
            ),
            CatalogSetupStockUnitDraft(
                unitKind: .offcut,
                label: "OFFCUT 01",
                widthValue: 6,
                widthUnit: "ft",
                originalLengthValue: 12,
                remainingLengthValue: 9,
                lengthUnit: "ft",
                quantityValue: 1,
                status: .partial
            ),
            CatalogSetupStockUnitDraft(
                unitKind: .roll,
                label: "RESERVED",
                widthValue: 6,
                widthUnit: "ft",
                originalLengthValue: 75,
                remainingLengthValue: 75,
                lengthUnit: "ft",
                quantityValue: 1,
                status: .reserved
            )
        ]

        XCTAssertEqual(CatalogSetupWorkflow.mirroredQuantity(for: stockUnits), 504, accuracy: 0.001)
        XCTAssertEqual(CatalogSetupWorkflow.mirroredQuantityLabel(for: stockUnits), "504 sq ft")
    }

    func testCatalogSetupQARuntimeRequiresExplicitLocalOnlyFlag() {
        XCTAssertFalse(CatalogSetupQARuntime.isEnabled(environment: [:], arguments: []))
        XCTAssertFalse(CatalogSetupQARuntime.isEnabled(
            environment: ["OPS_CATALOG_SETUP_QA_LOCAL_ONLY": "true"],
            arguments: []
        ))
        XCTAssertTrue(CatalogSetupQARuntime.isEnabled(
            environment: ["OPS_CATALOG_SETUP_QA_LOCAL_ONLY": "1"],
            arguments: []
        ))
        XCTAssertTrue(CatalogSetupQARuntime.isEnabled(
            environment: [:],
            arguments: ["OPS", "-OPS_CATALOG_SETUP_QA_LOCAL_ONLY"]
        ))
    }

    func testCatalogSetupStepRailStateReachesReviewWithForwardNavigation() {
        var state = CatalogSetupStepRailState(selectedStep: .family)
        var visitedSteps: [CatalogSetupStep] = [state.selectedStep]

        while let nextStep = state.nextStep {
            state = CatalogSetupStepRailState(selectedStep: nextStep)
            visitedSteps.append(state.selectedStep)
        }

        XCTAssertEqual(visitedSteps, [.family, .attributes, .matrix, .variants, .stock, .links, .review])
        XCTAssertEqual(state.progressText, "7/7")
        XCTAssertEqual(state.previousStep, .links)
        XCTAssertNil(state.nextStep)
    }

    func testBundleRequiredRollupIgnoresSuggestedChildren() {
        let required = bundleItem(id: "required", relationshipKind: .required, displayOrder: 0)
        let suggested = bundleItem(id: "suggested", relationshipKind: .suggested, displayOrder: 1)
        required.quantity = 2
        suggested.quantity = 4
        let requiredProduct = Product(id: required.childProductId, companyId: companyId, name: "Required", basePrice: 100)
        let suggestedProduct = Product(id: suggested.childProductId, companyId: companyId, name: "Suggested", basePrice: 250)

        let total = ProductBundleCompositionGrouping.requiredRollupTotal(
            [required, suggested],
            productsById: [
                requiredProduct.id: requiredProduct,
                suggestedProduct.id: suggestedProduct
            ]
        )

        XCTAssertEqual(total, 200, accuracy: 0.001)
    }

    private func catalogSetupDraftSnapshot(
        context: CatalogSetupDraftContext,
        familyName: String = "Vinyl membrane",
        activeSaveAttempt: CatalogSetupSaveAttempt? = nil,
        rpcWarnings: [CatalogSetupSaveIssue] = [],
        rpcBlockers: [CatalogSetupSaveIssue] = [],
        stockUnit: CatalogSetupStockUnitDraft = CatalogSetupStockUnitDraft(id: "stock_roll_a")
    ) -> CatalogSetupDraftSnapshot {
        let attribute = CatalogSetupAttributeDraft(
            id: "axis_thickness",
            name: "Thickness",
            values: [
                CatalogSetupAttributeValueDraft(id: "value_60", value: "60 mil"),
                CatalogSetupAttributeValueDraft(id: "value_68", value: "68 mil")
            ]
        )
        let variant = CatalogSetupVariantDraft(
            id: "variant_60_black",
            optionValueIdsByAttributeId: [attribute.id: "value_60"],
            optionValueIds: ["value_60"],
            sku: "MEM-60-BLK",
            warningThresholdText: "10",
            criticalThresholdText: "2",
            unitId: "unit_sqft",
            imageUrl: "https://example.test/variant.png",
            stockUnits: [stockUnit],
            isEnabled: true
        )

        return CatalogSetupDraftSnapshot(
            context: context,
            draftId: "draft_resume_001",
            selectedStep: CatalogSetupStep.stock.rawValue,
            familyName: familyName,
            familyDescription: "60 mil stock",
            familyImageUrl: "https://example.test/family.png",
            selectedCategoryId: "category_membrane",
            selectedUnitId: "unit_sqft",
            defaultWarningText: "10",
            defaultCriticalText: "2",
            attributes: [attribute],
            invalidCombinations: [
                CatalogSetupInvalidCombination(id: "invalid_thick_color", valueIds: ["value_68", "value_tan"])
            ],
            invalidSelectionByAttributeId: [attribute.id: "value_68"],
            setupVariants: [variant],
            generatedMatrixOnce: true,
            selectedProductId: "product_membrane",
            productOptionSelectionByAttributeId: [attribute.id: "product_option_thickness"],
            productValueSelectionByCatalogValueId: ["value_60": "product_value_60"],
            activeSaveAttempt: activeSaveAttempt,
            rpcWarnings: rpcWarnings,
            rpcBlockers: rpcBlockers,
            saveErrorMessage: rpcBlockers.isEmpty ? nil : "Server rejected catalog setup save."
        )
    }

    private func temporaryCatalogDraftRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ops-catalog-draft-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func stockUnit(
        id: String,
        remainingLength: Double?,
        quantity: Double,
        status: CatalogStockUnitStatus
    ) -> CatalogStockUnit {
        CatalogStockUnit(
            id: id,
            companyId: companyId,
            catalogVariantId: "variant_roll",
            unitKind: .roll,
            label: id,
            widthValue: 6,
            widthUnit: "ft",
            originalLengthValue: 75,
            remainingLengthValue: remainingLength,
            lengthUnit: "ft",
            quantityValue: quantity,
            status: status
        )
    }

    func testCatalogItemImageStoragePathUsesVerifiedProductThumbnailsBucket() {
        XCTAssertEqual(ProductThumbnailStoragePath.bucket, "product-thumbnails")
        XCTAssertEqual(
            ProductThumbnailStoragePath.objectPath(
                companyId: "company_1",
                ownerId: "catalog_item_1",
                objectName: "item.jpg"
            ),
            "company_1/catalog_item_1/item.jpg"
        )
    }

    func testCreateCatalogItemTagDTOEncodesLiveJunctionColumnsOnly() throws {
        let dto = CreateCatalogItemTagDTO(catalogItemId: "family_post", tagId: "tag_black")
        let data = try JSONEncoder().encode(dto)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object, [
            "catalog_item_id": "family_post",
            "tag_id": "tag_black"
        ])
    }

    func testVariantOptionSelectionStateDropsSelectionsOutsideSelectedFamily() {
        let color = CatalogOption(id: "option_color", catalogItemId: "family_a", name: "Color")
        let width = CatalogOption(id: "option_width", catalogItemId: "family_a", name: "Width")
        let black = CatalogOptionValue(id: "value_black", optionId: color.id, value: "Black")
        let sixFoot = CatalogOptionValue(id: "value_6ft", optionId: width.id, value: "6 ft")
        let staleValue = CatalogOptionValue(id: "value_stale", optionId: "option_old", value: "Old")

        let cleaned = VariantOptionSelectionState.validSelections(
            [
                color.id: black.id,
                width.id: staleValue.id,
                "option_old": sixFoot.id
            ],
            familyOptions: [color, width],
            optionValues: [black, sixFoot, staleValue]
        )

        XCTAssertEqual(cleaned, [color.id: black.id])
    }

    private func bundleItem(
        id: String,
        relationshipKind: ProductBundleRelationshipKind,
        displayOrder: Int
    ) -> ProductBundleItem {
        ProductBundleItem(
            id: id,
            companyId: companyId,
            bundleProductId: "bundle",
            childProductId: "child_\(id)",
            quantity: 1,
            relationshipKind: relationshipKind,
            displayOrder: displayOrder
        )
    }

    private func encodedJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func catalogSetupSaveRPCMigrationSQL(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory
                .appendingPathComponent("ops-software-bible")
                .appendingPathComponent("migrations")
                .appendingPathComponent("2026-05-25-01-catalog-setup-save-rpc.sql")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }
        XCTFail("Missing catalog_setup_save draft migration beside ops-ios checkout", file: file, line: line)
        return ""
    }

    private func normalizedSQLWhitespace(_ sql: String) -> String {
        sql.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func migrationModelIdentitySet(_ schema: any VersionedSchema.Type) -> Set<String> {
        Set(schema.models.map { String(reflecting: $0) })
    }

    private func makeProductOnlyInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Product.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func assertMigrates(
        name: String,
        sourceSchema: any VersionedSchema.Type,
        targetSchema: any VersionedSchema.Type,
        plan: any SchemaMigrationPlan.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ops-\(name)-migration-diagnostic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        let storeURL = storeDirectory.appendingPathComponent("default.store")
        let source = Schema(versionedSchema: sourceSchema)
        let sourceConfiguration = ModelConfiguration(schema: source, url: storeURL, allowsSave: true)
        _ = try ModelContainer(for: source, configurations: [sourceConfiguration])

        let target = Schema(versionedSchema: targetSchema)
        let targetConfiguration = ModelConfiguration(schema: target, url: storeURL, allowsSave: true)

        do {
            _ = try ModelContainer(
                for: target,
                migrationPlan: plan,
                configurations: [targetConfiguration]
            )
        } catch {
            XCTFail("\(name) migration failed: \(error)", file: file, line: line)
        }
    }

    private func assertOpensCurrentMigratedStore(
        name: String,
        sourceSchema: any VersionedSchema.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        UserDefaults.standard.removeObject(forKey: "needs_full_catalog_sync")
        defer { UserDefaults.standard.removeObject(forKey: "needs_full_catalog_sync") }

        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ops-\(name)-full-plan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        let storeURL = storeDirectory.appendingPathComponent("default.store")
        let source = Schema(versionedSchema: sourceSchema)
        let sourceConfiguration = ModelConfiguration(schema: source, url: storeURL, allowsSave: true)
        _ = try ModelContainer(for: source, configurations: [sourceConfiguration])

        let current = Schema(versionedSchema: OPSSchemaV8.self)
        let currentConfiguration = ModelConfiguration(schema: current, url: storeURL, allowsSave: true)

        do {
            _ = try ModelContainer(
                for: current,
                migrationPlan: OPSMigrationPlan.self,
                configurations: [currentConfiguration]
            )
        } catch {
            XCTFail("\(name) full migration-plan open failed: \(error)", file: file, line: line)
        }
    }
}

private enum V1ToV2OnlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OPSSchemaV1.self, OPSSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [OPSMigrationPlan.migrateWizardStateIdV1toV2]
    }
}

private enum V2ToV3OnlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OPSSchemaV2.self, OPSSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [OPSMigrationPlan.migrateInventoryToCatalogV2toV3]
    }
}

private enum V3ToV4OnlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OPSSchemaV3.self, OPSSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [OPSMigrationPlan.migrateAddTaskRemindersV3toV4]
    }
}

private enum V4ToV5OnlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OPSSchemaV4.self, OPSSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [OPSMigrationPlan.addCalendarMirrorMapV4toV5]
    }
}

private enum V5ToV6OnlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OPSSchemaV5.self, OPSSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [OPSMigrationPlan.addForecastModelsV5toV6]
    }
}

private enum V6ToV7OnlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OPSSchemaV6.self, OPSSchemaV7.self]
    }

    static var stages: [MigrationStage] {
        [OPSMigrationPlan.addVinylOrderMarkerV6toV7]
    }
}

private enum V7ToV8OnlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OPSSchemaV7.self, OPSSchemaV8.self]
    }

    static var stages: [MigrationStage] {
        [OPSMigrationPlan.addCatalogSetupModelsV7toV8]
    }
}
