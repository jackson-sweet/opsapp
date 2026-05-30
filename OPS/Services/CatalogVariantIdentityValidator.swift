//
//  CatalogVariantIdentityValidator.swift
//  OPS
//

import Foundation

struct CatalogVariantDraftIdentity: Equatable {
    let id: String?
    let companyId: String
    let catalogItemId: String
    let sku: String?
    let optionValueIds: Set<String>

    init(
        id: String? = nil,
        companyId: String,
        catalogItemId: String,
        sku: String?,
        optionValueIds: Set<String>
    ) {
        self.id = id
        self.companyId = companyId
        self.catalogItemId = catalogItemId
        self.sku = sku
        self.optionValueIds = optionValueIds
    }
}

struct CatalogVariantIdentityValidationResult: Equatable {
    var warnings: [CatalogVariantIdentityWarning] = []
    var blockingViolations: [CatalogVariantIdentityViolation] = []

    var isBlocked: Bool {
        !blockingViolations.isEmpty
    }
}

enum CatalogVariantIdentityWarning: Equatable {
    case duplicateSKU(normalizedSKU: String, conflictingVariantId: String?)
}

enum CatalogVariantIdentityViolation: Equatable {
    case duplicateMatrixSignature(catalogItemId: String, optionValueIds: Set<String>, conflictingVariantId: String?)
}

enum CatalogVariantIdentityValidator {
    static func validate(
        drafts: [CatalogVariantDraftIdentity],
        existingVariants: [CatalogVariant],
        existingOptionValues: [CatalogVariantOptionValue]
    ) -> CatalogVariantIdentityValidationResult {
        let activeVariants = existingVariants.filter { $0.deletedAt == nil && $0.isActive }
        var warnings: [CatalogVariantIdentityWarning] = []
        var violations: [CatalogVariantIdentityViolation] = []

        var skuIndex: [String: CatalogVariant] = [:]
        for variant in activeVariants {
            guard let normalized = normalizeSKU(variant.sku) else { continue }
            skuIndex["\(variant.companyId)::\(normalized)"] = variant
        }

        var draftSKUIndex: [String: CatalogVariantDraftIdentity] = [:]
        for draft in drafts {
            guard let normalized = normalizeSKU(draft.sku) else { continue }
            let key = "\(draft.companyId)::\(normalized)"

            if let existing = skuIndex[key], existing.id != draft.id {
                warnings.append(.duplicateSKU(normalizedSKU: normalized, conflictingVariantId: existing.id))
            } else if let earlierDraft = draftSKUIndex[key], earlierDraft.id != draft.id {
                warnings.append(.duplicateSKU(normalizedSKU: normalized, conflictingVariantId: earlierDraft.id))
            } else {
                draftSKUIndex[key] = draft
            }
        }

        let optionValuesByVariant = Dictionary(grouping: existingOptionValues, by: \.variantId)
            .mapValues { Set($0.map(\.optionValueId)) }
        var signatureIndex: [MatrixSignatureKey: CatalogVariant] = [:]

        for variant in activeVariants {
            let optionValueIds = optionValuesByVariant[variant.id] ?? []
            guard !optionValueIds.isEmpty else { continue }
            let key = MatrixSignatureKey(
                companyId: variant.companyId,
                catalogItemId: variant.catalogItemId,
                optionValueIds: optionValueIds
            )
            if signatureIndex[key] == nil {
                signatureIndex[key] = variant
            }
        }

        var draftSignatureIndex: [MatrixSignatureKey: CatalogVariantDraftIdentity] = [:]
        for draft in drafts where !draft.optionValueIds.isEmpty {
            let key = MatrixSignatureKey(
                companyId: draft.companyId,
                catalogItemId: draft.catalogItemId,
                optionValueIds: draft.optionValueIds
            )

            if let existing = signatureIndex[key], existing.id != draft.id {
                violations.append(.duplicateMatrixSignature(
                    catalogItemId: draft.catalogItemId,
                    optionValueIds: draft.optionValueIds,
                    conflictingVariantId: existing.id
                ))
            } else if let earlierDraft = draftSignatureIndex[key], earlierDraft.id != draft.id {
                violations.append(.duplicateMatrixSignature(
                    catalogItemId: draft.catalogItemId,
                    optionValueIds: draft.optionValueIds,
                    conflictingVariantId: earlierDraft.id
                ))
            } else {
                draftSignatureIndex[key] = draft
            }
        }

        return CatalogVariantIdentityValidationResult(
            warnings: warnings,
            blockingViolations: violations
        )
    }

    private static func normalizeSKU(_ sku: String?) -> String? {
        let normalized = sku?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    private struct MatrixSignatureKey: Hashable {
        let companyId: String
        let catalogItemId: String
        let optionValueIds: Set<String>
    }
}
