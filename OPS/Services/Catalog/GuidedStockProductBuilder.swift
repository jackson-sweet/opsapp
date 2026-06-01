import Foundation

/// Builds the PRODUCT section of a guided family's catalog_setup_save payload.
///
/// Uses client-id references so new products link to the new family/variant in the
/// same atomic call. Bundle children reference already-committed sibling products
/// by their resolved SERVER id (the commit loop orders bundles after their children).
enum GuidedStockProductBuilder {

    // MARK: - Client-id helpers

    /// Stable client id for a group's sellable product.
    static func productClientId(for group: GuidedStructuredGroup) -> String {
        "product::\(group.id)"
    }

    // MARK: - Payload builder

    /// Returns the product payloads for a group. Empty if the group does not sell (stock-only).
    ///
    /// - Parameters:
    ///   - group: The structured group whose product section is being built.
    ///   - companyId: The company the product belongs to (reserved for any future scoping).
    ///   - familyClientId: The family's client id in the same payload (e.g. `"family:\(group.id)"`).
    ///   - recipeVariantClientId: A representative variant client id to pin the recipe to;
    ///     pass `nil` to pin the recipe to the family instead.
    ///   - childProductIdByItemId: Resolved SERVER product ids for bundle children,
    ///     keyed by the captured item id. Children whose id is absent or empty are skipped.
    static func productPayloads(
        for group: GuidedStructuredGroup,
        companyId: String,
        familyClientId: String,
        recipeVariantClientId: String?,
        childProductIdByItemId: [String: String]
    ) -> [CatalogSetupSavePayload.ProductPayload] {
        guard let sellMode = group.product.sellMode else { return [] }

        let isBundle = (sellMode == .inPackage)
        let pClientId = productClientId(for: group)

        // MARK: Recipe (product_materials)
        // Only emit when the operator confirmed selling consumes stock AND the group is not a
        // pure bundle. A bundle does not have its own stock family to draw from.
        var materials: [CatalogSetupSavePayload.ProductMaterial] = []
        if group.product.sellingUsesStock == true, !isBundle {
            // Pin to EXACTLY ONE of {variant, family} — never both, never neither.
            let pinVariant = recipeVariantClientId
            materials.append(
                CatalogSetupSavePayload.ProductMaterial(
                    id: nil,
                    clientId: "material::\(group.id)",
                    productClientId: pClientId,
                    productId: nil,
                    catalogVariantClientId: pinVariant,
                    catalogVariantId: nil,
                    catalogItemClientId: pinVariant == nil ? familyClientId : nil,
                    catalogItemId: nil,
                    variantSelector: nil,
                    quantityPerUnit: 1,
                    scaledByOptionId: nil,
                    unitId: nil,
                    notes: nil
                )
            )
        }

        // MARK: Bundle children (bundle_items)
        // Only populated when the sell mode includes packaging (.inPackage or .both).
        // Each child must be referenced by its resolved SERVER product id — new-family products
        // committed earlier in the ordered loop. Skip any child not yet resolved.
        var bundleItems: [CatalogSetupSavePayload.ProductBundleItemPayload] = []
        if sellMode == .inPackage || sellMode == .both {
            for (index, child) in group.product.bundleChildren.enumerated() {
                guard let serverId = childProductIdByItemId[child.capturedItemId],
                      !serverId.isEmpty else { continue }
                bundleItems.append(
                    CatalogSetupSavePayload.ProductBundleItemPayload(
                        id: nil,
                        clientId: "bundle::\(group.id)::\(child.capturedItemId)",
                        childProductId: serverId,
                        quantity: 1,
                        relationshipKind: child.isRequired ? "required" : "suggested",
                        hasPricing: true,
                        suggestionReason: nil,
                        compatibilitySelector: nil,
                        displayOrder: index
                    )
                )
            }
        }

        // MARK: Product payload
        // kind / type use the same raw strings the RPC and existing makeSavePayload use:
        //   kind  →  "material" | "package"      (from derivedKindRaw)
        //   type  →  "MATERIAL" | "OTHER"         (from LineItemType.rawValue)
        // A pure bundle does not link to a stock family; goods/both link via client id.
        let product = CatalogSetupSavePayload.ProductPayload(
            id: nil,
            clientId: pClientId,
            kind: isBundle ? "package" : "material",
            type: isBundle ? "OTHER" : "MATERIAL",
            name: group.familyName,
            pricingUnit: "each",
            linkedCatalogItemClientId: isBundle ? nil : familyClientId,
            linkedCatalogItemId: nil,
            bundlePricingMode: isBundle ? "auto" : nil,
            options: [],
            pricingModifiers: [],
            productMaterials: materials,
            catalogOptionMappings: [],
            bundleItems: bundleItems
        )

        return [product]
    }
}
