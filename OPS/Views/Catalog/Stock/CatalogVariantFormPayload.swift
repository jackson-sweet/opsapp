//
//  CatalogVariantFormPayload.swift
//  OPS
//
//  Payload normalization shared by variant create/edit surfaces.
//

import Foundation

enum CatalogVariantFormPayload {
    static func normalizedSKU(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func update(
        skuText: String,
        quantity: Double,
        priceOverride: Double?,
        unitCostOverride: Double?,
        warningThresholdText: String,
        criticalThresholdText: String,
        unitId: String?
    ) -> UpdateCatalogVariantDTO {
        let trimmedWarning = warningThresholdText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCritical = criticalThresholdText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sku = normalizedSKU(skuText)

        return UpdateCatalogVariantDTO(
            sku: sku,
            quantity: quantity,
            priceOverride: priceOverride,
            unitCostOverride: unitCostOverride,
            warningThreshold: Double(trimmedWarning),
            criticalThreshold: Double(trimmedCritical),
            unitId: unitId,
            setNullSku: sku == nil,
            setNullWarningThreshold: trimmedWarning.isEmpty,
            setNullCriticalThreshold: trimmedCritical.isEmpty,
            setNullUnitId: unitId == nil
        )
    }
}
