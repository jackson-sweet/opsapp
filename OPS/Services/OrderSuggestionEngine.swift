//
//  OrderSuggestionEngine.swift
//  OPS
//
//  Pure function: given the current catalog state (variants, families,
//  categories), produce the list of variants whose effective on-hand
//  quantity has fallen at or below their effective warning threshold,
//  along with a recommended target quantity.
//
//  Threshold cascade for any variant: variant override → family default
//  → category default → null (no suggestion possible).
//
//  No I/O, no side effects. Used by the Orders sheet (SUGGESTED tab) and
//  by `InboundProcessor.reconcileThresholdNotifications` after every sync.
//

import Foundation

struct OrderSuggestionEngine {

    /// One restock recommendation. The caller hydrates `variantLabel` from
    /// option-value joins when rendering — the engine itself only needs
    /// the family name and current/target quantities to make the call.
    struct Suggestion: Identifiable, Hashable {
        let variantId: String
        let familyName: String
        /// Optional human-readable variant label (e.g., "Black · Topmount").
        /// Empty when the family has no options.
        var variantLabel: String
        let currentQuantity: Double
        let warningThreshold: Double
        let criticalThreshold: Double?
        let recommendedQuantity: Double

        var id: String { variantId }
    }

    func suggest(
        variants: [CatalogVariant],
        families: [CatalogItem],
        categories: [CatalogCategory]
    ) -> [Suggestion] {
        let familiesById = Dictionary(uniqueKeysWithValues: families
            .filter { $0.deletedAt == nil && $0.isActive }
            .map { ($0.id, $0) })
        let categoriesById = Dictionary(uniqueKeysWithValues: categories
            .filter { $0.deletedAt == nil }
            .map { ($0.id, $0) })

        return variants.compactMap { variant -> Suggestion? in
            guard variant.deletedAt == nil, variant.isActive else { return nil }
            guard let family = familiesById[variant.catalogItemId] else { return nil }
            let category = family.categoryId.flatMap { categoriesById[$0] }

            // Threshold cascade: variant → family → category.
            let warning = variant.warningThreshold
                ?? family.defaultWarningThreshold
                ?? category?.defaultWarningThreshold
            guard let effectiveWarning = warning else { return nil }

            // Only surface variants at or below the warning threshold.
            guard variant.quantity <= effectiveWarning else { return nil }

            let critical = variant.criticalThreshold
                ?? family.defaultCriticalThreshold
                ?? category?.defaultCriticalThreshold

            // Default target = warning * 2 — restocks back to a comfortable
            // buffer above the warning line. Caller can override later.
            let recommended = effectiveWarning * 2.0

            return Suggestion(
                variantId: variant.id,
                familyName: family.name,
                variantLabel: "",
                currentQuantity: variant.quantity,
                warningThreshold: effectiveWarning,
                criticalThreshold: critical,
                recommendedQuantity: recommended
            )
        }
    }
}
