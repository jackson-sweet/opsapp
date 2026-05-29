//
//  CatalogSetupQARuntime.swift
//  OPS
//
//  Local-only Catalog Setup runtime gate for simulator QA.
//

import Foundation

enum CatalogSetupQARuntime {
    static let environmentKey = "OPS_CATALOG_SETUP_QA_LOCAL_ONLY"
    static let launchArgument = "-OPS_CATALOG_SETUP_QA_LOCAL_ONLY"

    static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        environment[environmentKey] == "1" || arguments.contains(launchArgument)
        #else
        false
        #endif
    }
}

#if DEBUG
extension CatalogSchemaCapabilities {
    static let catalogSetupQALocalOnly = CatalogSchemaCapabilities(
        catalogStockUnits: true,
        catalogProductOptionMappings: true,
        productBundleRelationshipFields: true
    )
}

enum CatalogSetupQAFixtures {
    static let companyId = "qa_catalog_setup_company"
    static let userId = "qa_catalog_setup_user"
    static let categoryId = "qa_catalog_setup_category_panels"
    static let areaUnitId = "qa_catalog_setup_unit_sqft"
    static let countUnitId = "qa_catalog_setup_unit_each"
    static let productId = "qa_catalog_setup_product_panel"

    static let finishAttributeId = "qa_catalog_setup_attr_finish"
    static let gaugeAttributeId = "qa_catalog_setup_attr_gauge"
    static let finishRawValueId = "qa_catalog_setup_finish_raw"
    static let finishCoatedValueId = "qa_catalog_setup_finish_coated"
    static let gaugeLightValueId = "qa_catalog_setup_gauge_light"
    static let gaugeHeavyValueId = "qa_catalog_setup_gauge_heavy"

    static let finishProductOptionId = "qa_catalog_setup_product_option_finish"
    static let gaugeProductOptionId = "qa_catalog_setup_product_option_gauge"
    static let finishProductValueRawId = "qa_catalog_setup_product_finish_raw"
    static let finishProductValueCoatedId = "qa_catalog_setup_product_finish_coated"
    static let gaugeProductValueLightId = "qa_catalog_setup_product_gauge_light"
    static let gaugeProductValueHeavyId = "qa_catalog_setup_product_gauge_heavy"

    static let duplicateVariantId = "qa_catalog_setup_duplicate_variant"
    static let duplicateSKU = "QA-DUP-SKU"
    static let draftCatalogItemId = "__new_catalog_setup_family__"
    static let draftFamilyName = "QA FIELD PANEL SYSTEM"

    static var duplicateMatrixValueIds: Set<String> {
        [finishCoatedValueId, gaugeLightValueId]
    }

    static var stockFixtureValueIds: Set<String> {
        [finishCoatedValueId, gaugeHeavyValueId]
    }

    static func draftAttributes() -> [CatalogSetupAttributeDraft] {
        [
            CatalogSetupAttributeDraft(
                id: finishAttributeId,
                name: "Finish",
                values: [
                    CatalogSetupAttributeValueDraft(id: finishRawValueId, value: "Raw"),
                    CatalogSetupAttributeValueDraft(id: finishCoatedValueId, value: "Coated")
                ]
            ),
            CatalogSetupAttributeDraft(
                id: gaugeAttributeId,
                name: "Gauge",
                values: [
                    CatalogSetupAttributeValueDraft(id: gaugeLightValueId, value: "Light"),
                    CatalogSetupAttributeValueDraft(id: gaugeHeavyValueId, value: "Heavy")
                ]
            )
        ]
    }

    static var invalidCombination: CatalogSetupInvalidCombination {
        CatalogSetupInvalidCombination(valueIds: [finishRawValueId, gaugeHeavyValueId])
    }
}
#endif
