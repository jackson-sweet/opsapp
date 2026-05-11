//
//  RecipeResolver.swift
//  OPS
//
//  At install task creation, resolves each Product's recipe rows against
//  the line item's configured_options snapshot, producing concrete
//  catalog_variant pins + scaled quantities. Pure function — caller wires
//  the writes (see CutListMaterializer).
//

import Foundation

struct RecipeResolver {

    struct ResolvedMaterial: Equatable {
        let catalogVariantId: String
        let quantity: Double
        let unitId: String?
        let notes: String?
    }

    enum ResolverError: Error, Equatable {
        case missingCatalogVariantForSelector(itemId: String, selector: [String: String])
        case selectorReferencesUnknownOption(key: String)
    }

    /// For each ProductMaterial row, resolve to one ResolvedMaterial pinned
    /// to a specific `catalog_variant_id`.
    ///
    /// Two recipe shapes are supported:
    ///   1. `catalog_variant_id` set → pinned variant, used directly.
    ///   2. `catalog_item_id` + `variant_selector` set → family-pinned, the
    ///      selector is evaluated against `configured_options` and the
    ///      matching variant is chosen.
    ///
    /// Quantity:
    ///   - default: `quantity_per_unit * lineQuantity`
    ///   - if `scaled_by_option_id` is set AND that configured option is
    ///     `.integer(n)` → `quantity_per_unit * n` (replaces line scaling).
    func resolve(
        materials: [ProductMaterial],
        configuredOptions: [String: ProductConfigurationResolver.OptionValue],
        productOptionsById: [String: ProductOption],
        productOptionValuesById: [String: ProductOptionValue],
        catalogVariants: [CatalogVariant],
        catalogVariantOptionValues: [CatalogVariantOptionValue],
        catalogOptionValuesById: [String: CatalogOptionValue],
        catalogOptionsByItemId: [String: [CatalogOption]],
        lineQuantity: Double
    ) throws -> [ResolvedMaterial] {
        var output: [ResolvedMaterial] = []

        // Build family→variant index for quick lookup.
        let variantsByFamily = Dictionary(grouping: catalogVariants, by: \.catalogItemId)
        // Build variant→[optionValueId] index.
        let variantOptionValueIds = Dictionary(grouping: catalogVariantOptionValues, by: \.variantId)
            .mapValues { Set($0.map(\.optionValueId)) }

        for mat in materials {
            // 1. Determine resolved variant.
            var resolvedVariantId: String? = nil

            if let pinned = mat.catalogVariantId {
                resolvedVariantId = pinned
            } else if let familyId = mat.catalogItemId,
                      let selector = decodeSelector(mat.variantSelectorJSON) {
                // selector example: {"color": "$option.color", "mount": "$option.mount_type"}
                // We resolve $option.<name> into the configured_options' selected
                // ProductOptionValue.value, then find the family-side
                // CatalogOptionValue whose optionId matches the named axis on
                // the family and whose value matches the resolved string.
                let requiredCatalogOptionValues = try resolveSelectorToCatalogOptionValueIds(
                    selector: selector,
                    familyId: familyId,
                    configuredOptions: configuredOptions,
                    productOptionsById: productOptionsById,
                    productOptionValuesById: productOptionValuesById,
                    catalogOptionValuesById: catalogOptionValuesById,
                    catalogOptionsByItemId: catalogOptionsByItemId
                )
                let candidates = (variantsByFamily[familyId] ?? []).filter { v in
                    let valueIds = variantOptionValueIds[v.id] ?? []
                    return requiredCatalogOptionValues.isSubset(of: valueIds)
                }
                if candidates.count == 1 {
                    resolvedVariantId = candidates[0].id
                } else if candidates.isEmpty {
                    throw ResolverError.missingCatalogVariantForSelector(
                        itemId: familyId, selector: selector
                    )
                } else {
                    // Tie — the family has ambiguous variants under the
                    // selector. Deterministic tiebreak: lowest id wins.
                    resolvedVariantId = candidates.sorted(by: { $0.id < $1.id }).first?.id
                }
            }

            guard let variantId = resolvedVariantId else { continue }

            // 2. Compute scaled quantity.
            var qty = mat.quantityPerUnit * lineQuantity
            if let scaledByOptionId = mat.scaledByOptionId,
               case .integer(let n) = configuredOptions[scaledByOptionId] {
                // The scaling option is the per-line scalar (e.g. corners count) —
                // it replaces lineQuantity, doesn't multiply on top of it.
                qty = mat.quantityPerUnit * Double(n)
            }

            output.append(ResolvedMaterial(
                catalogVariantId: variantId,
                quantity: qty,
                unitId: mat.unitId,
                notes: mat.notes
            ))
        }

        return output
    }

    // MARK: - Selector parsing

    private func decodeSelector(_ json: String?) -> [String: String]? {
        guard let json = json,
              let data = json.data(using: .utf8) else { return nil }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return dict
    }

    /// Translate a selector dict like `{"color": "$option.color"}` into the
    /// set of `CatalogOptionValue.id` values (on the named family) that the
    /// configured ProductOptionValue's string value maps to. The variant
    /// matcher then requires these ids be a subset of a candidate variant's
    /// option-value combo.
    private func resolveSelectorToCatalogOptionValueIds(
        selector: [String: String],
        familyId: String,
        configuredOptions: [String: ProductConfigurationResolver.OptionValue],
        productOptionsById: [String: ProductOption],
        productOptionValuesById: [String: ProductOptionValue],
        catalogOptionValuesById: [String: CatalogOptionValue],
        catalogOptionsByItemId: [String: [CatalogOption]]
    ) throws -> Set<String> {
        var result = Set<String>()
        let familyOptions = catalogOptionsByItemId[familyId] ?? []
        for (catalogOptName, sourceExpr) in selector {
            // sourceExpr is "$option.<product_option_name>"
            guard sourceExpr.hasPrefix("$option.") else { continue }
            let productOptionName = String(sourceExpr.dropFirst("$option.".count))

            // Find the ProductOption with this name (case-insensitive) on the
            // recipe's parent product. (productOptionsById is scoped to the
            // single product whose recipe we're resolving.)
            guard let productOption = productOptionsById.values.first(where: {
                $0.name.lowercased() == productOptionName.lowercased()
            }) else {
                throw ResolverError.selectorReferencesUnknownOption(key: productOptionName)
            }

            // Resolve the configured value to a string.
            guard let configured = configuredOptions[productOption.id] else { continue }
            let stringValue: String? = {
                switch configured {
                case .selectId(let id): return productOptionValuesById[id]?.value
                case .integer(let n):   return "\(n)"
                case .boolean(let b):   return b ? "true" : "false"
                }
            }()
            guard let stringValue = stringValue else { continue }

            // Match against the family's CatalogOption with the named axis.
            guard let catalogOption = familyOptions.first(where: {
                $0.name.lowercased() == catalogOptName.lowercased()
            }) else {
                continue
            }

            // Find the CatalogOptionValue under that CatalogOption whose value
            // matches the resolved string.
            if let match = catalogOptionValuesById.values.first(where: {
                $0.optionId == catalogOption.id
                    && $0.value.lowercased() == stringValue.lowercased()
            }) {
                result.insert(match.id)
            }
        }
        return result
    }
}
