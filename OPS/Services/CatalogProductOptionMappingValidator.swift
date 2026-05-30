//
//  CatalogProductOptionMappingValidator.swift
//  OPS
//

import Foundation

enum CatalogProductOptionMappingViolation: Equatable {
    case catalogOptionMissing(mappingId: String)
    case productOptionMissing(mappingId: String)
    case productOptionMustBeSelect(mappingId: String)
    case catalogValueMissing(mappingId: String)
    case productValueMissing(mappingId: String)
    case axisMappingCarriesValueIds(mappingId: String)
    case valueMappingMissingValueIds(mappingId: String)
    case catalogValueDoesNotBelongToMappedOption(mappingId: String)
    case productValueDoesNotBelongToMappedOption(mappingId: String)
}

enum CatalogProductOptionMappingValidator {
    static func validate(
        mappings: [CatalogProductOptionMapping],
        catalogOptions: [CatalogOption],
        catalogOptionValues: [CatalogOptionValue],
        productOptions: [ProductOption],
        productOptionValues: [ProductOptionValue]
    ) -> [CatalogProductOptionMappingViolation] {
        let catalogOptionIds = Set(catalogOptions.map(\.id))
        let productOptionsById = Dictionary(uniqueKeysWithValues: productOptions.map { ($0.id, $0) })
        let catalogValuesById = Dictionary(uniqueKeysWithValues: catalogOptionValues.map { ($0.id, $0) })
        let productValuesById = Dictionary(uniqueKeysWithValues: productOptionValues.map { ($0.id, $0) })

        var violations: [CatalogProductOptionMappingViolation] = []

        for mapping in mappings where mapping.deletedAt == nil {
            if !catalogOptionIds.contains(mapping.catalogOptionId) {
                violations.append(.catalogOptionMissing(mappingId: mapping.id))
            }
            if let productOption = productOptionsById[mapping.productOptionId] {
                if productOption.kind != .select {
                    violations.append(.productOptionMustBeSelect(mappingId: mapping.id))
                }
            } else {
                violations.append(.productOptionMissing(mappingId: mapping.id))
            }

            switch mapping.mappingKind {
            case .axis:
                if mapping.catalogOptionValueId != nil || mapping.productOptionValueId != nil {
                    violations.append(.axisMappingCarriesValueIds(mappingId: mapping.id))
                }
            case .value:
                guard let catalogValueId = mapping.catalogOptionValueId,
                      let productValueId = mapping.productOptionValueId else {
                    violations.append(.valueMappingMissingValueIds(mappingId: mapping.id))
                    continue
                }

                guard let catalogValue = catalogValuesById[catalogValueId] else {
                    violations.append(.catalogValueMissing(mappingId: mapping.id))
                    continue
                }
                guard let productValue = productValuesById[productValueId] else {
                    violations.append(.productValueMissing(mappingId: mapping.id))
                    continue
                }

                if catalogValue.optionId != mapping.catalogOptionId {
                    violations.append(.catalogValueDoesNotBelongToMappedOption(mappingId: mapping.id))
                }
                if productValue.optionId != mapping.productOptionId {
                    violations.append(.productValueDoesNotBelongToMappedOption(mappingId: mapping.id))
                }
            }
        }

        return violations
    }
}
