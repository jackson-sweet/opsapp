//
//  CutListMaterializer.swift
//  OPS
//
//  Thin orchestrator over RecipeResolver + TaskMaterialRepository.
//  At install-task creation, walks the project's estimate line items,
//  resolves each Product's recipe against the snapshotted
//  configured_options, and writes concrete task_materials rows pinned
//  to specific catalog_variant_ids.
//
//  Pure orchestration — recipe resolution is in RecipeResolver, write
//  is in TaskMaterialRepository. The trigger is wired by the caller;
//  no auto-trigger is installed in this phase.
//

import Foundation
import SwiftData

@MainActor
struct CutListMaterializer {

    let modelContext: ModelContext
    let companyId: String
    var repository: TaskMaterialRepository = TaskMaterialRepository()
    private let resolver = RecipeResolver()

    /// Materialize cut-list rows for a single line item, attaching the
    /// resolved variants to the given install task. No-op when the line
    /// item has no productId/configuredOptions snapshot — barebones flat
    /// products don't carry recipes.
    ///
    /// Returns the number of task_materials rows written. Callers receive
    /// errors and decide whether to surface them; this method does not
    /// swallow.
    @discardableResult
    func materialize(
        forLineItem lineItem: EstimateLineItem,
        projectTaskId: String
    ) async throws -> Int {
        guard let productId = lineItem.productId,
              let configuredJSON = lineItem.configuredOptionsJSON else {
            return 0
        }
        let configured = decodeConfigured(configuredJSON)
        guard !configured.isEmpty || hasVariantPinnedRecipes(productId: productId) else {
            return 0
        }

        let materials = fetchMaterials(productId: productId)
        guard !materials.isEmpty else { return 0 }

        let productOptions = fetchProductOptions(productId: productId)
        let productOptionsById = Dictionary(uniqueKeysWithValues: productOptions.map { ($0.id, $0) })

        let productOptionValues = fetchProductOptionValues(forOptionIds: productOptions.map(\.id))
        let productOptionValuesById = Dictionary(uniqueKeysWithValues: productOptionValues.map { ($0.id, $0) })

        let variants = fetchCompanyVariants()
        let variantIds = Set(variants.map(\.id))
        let variantOptionValues = fetchVariantOptionValues(forVariantIds: variantIds)

        let catalogOptions = fetchCatalogOptions(forItemIds: Set(variants.map(\.catalogItemId)))
        let catalogOptionsByItemId = Dictionary(grouping: catalogOptions, by: \.catalogItemId)

        let catalogOptionValues = fetchCatalogOptionValues(forOptionIds: catalogOptions.map(\.id))
        let catalogOptionValuesById = Dictionary(uniqueKeysWithValues: catalogOptionValues.map { ($0.id, $0) })

        let resolved = try resolver.resolve(
            materials: materials,
            configuredOptions: configured,
            productOptionsById: productOptionsById,
            productOptionValuesById: productOptionValuesById,
            catalogVariants: variants,
            catalogVariantOptionValues: variantOptionValues,
            catalogOptionValuesById: catalogOptionValuesById,
            catalogOptionsByItemId: catalogOptionsByItemId,
            lineQuantity: lineItem.quantity
        )

        guard !resolved.isEmpty else { return 0 }

        let rows = resolved.map { material in
            CreateTaskMaterialDTO(
                taskId: projectTaskId,
                catalogVariantId: material.catalogVariantId,
                quantity: material.quantity
            )
        }
        try await repository.createMaterials(rows)
        return rows.count
    }

    // MARK: - SwiftData Fetches

    private func fetchMaterials(productId: String) -> [ProductMaterial] {
        let descriptor = FetchDescriptor<ProductMaterial>(
            predicate: #Predicate { $0.productId == productId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func hasVariantPinnedRecipes(productId: String) -> Bool {
        fetchMaterials(productId: productId).contains { $0.catalogVariantId != nil }
    }

    private func fetchProductOptions(productId: String) -> [ProductOption] {
        let descriptor = FetchDescriptor<ProductOption>(
            predicate: #Predicate { $0.productId == productId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchProductOptionValues(forOptionIds ids: [String]) -> [ProductOptionValue] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        let all = (try? modelContext.fetch(FetchDescriptor<ProductOptionValue>())) ?? []
        return all.filter { idSet.contains($0.optionId) }
    }

    private func fetchCompanyVariants() -> [CatalogVariant] {
        let captured = companyId
        let descriptor = FetchDescriptor<CatalogVariant>(
            predicate: #Predicate { $0.companyId == captured && $0.deletedAt == nil }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchVariantOptionValues(forVariantIds ids: Set<String>) -> [CatalogVariantOptionValue] {
        guard !ids.isEmpty else { return [] }
        let all = (try? modelContext.fetch(FetchDescriptor<CatalogVariantOptionValue>())) ?? []
        return all.filter { ids.contains($0.variantId) }
    }

    private func fetchCatalogOptions(forItemIds ids: Set<String>) -> [CatalogOption] {
        guard !ids.isEmpty else { return [] }
        let all = (try? modelContext.fetch(FetchDescriptor<CatalogOption>())) ?? []
        return all.filter { ids.contains($0.catalogItemId) }
    }

    private func fetchCatalogOptionValues(forOptionIds ids: [String]) -> [CatalogOptionValue] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        let all = (try? modelContext.fetch(FetchDescriptor<CatalogOptionValue>())) ?? []
        return all.filter { idSet.contains($0.optionId) }
    }

    // MARK: - JSON Decoding

    /// Decode a `configured_options` JSON string into the resolver's typed
    /// option-value enum. Wire format mirrors what the resolver emits at
    /// snapshot time:
    ///   - select kinds: `{"<option_id>": "<option_value_id>"}` (string)
    ///   - integer kinds: `{"<option_id>": <int>}`
    ///   - boolean kinds: `{"<option_id>": <bool>}`
    private func decodeConfigured(_ json: String) -> [String: ProductConfigurationResolver.OptionValue] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: ProductConfigurationResolver.OptionValue] = [:]
        for (key, raw) in dict {
            if let s = raw as? String {
                result[key] = .selectId(s)
            } else if let n = raw as? Int {
                result[key] = .integer(n)
            } else if let b = raw as? Bool {
                result[key] = .boolean(b)
            } else if let n = raw as? Double, n.truncatingRemainder(dividingBy: 1) == 0 {
                result[key] = .integer(Int(n))
            }
        }
        return result
    }
}
