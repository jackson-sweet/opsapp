//
//  CatalogBulkVariantExpansionService.swift
//  OPS
//
//  Atomic server commit and authoritative SwiftData reconciliation for the
//  catalog bulk-variant flow.
//

import Foundation
import SwiftData

enum CatalogBulkVariantExpansionError: Error, Equatable {
    case invalidPreview
    case invalidIdempotencyKey
}

struct CatalogBulkVariantExpansionRequest: Codable, Equatable, Sendable {
    struct Family: Codable, Equatable, Sendable {
        let familyId: String
        let sourceFingerprint: String
        let source: CatalogBulkFamilySnapshot

        enum CodingKeys: String, CodingKey {
            case familyId = "family_id"
            case sourceFingerprint = "source_fingerprint"
            case source
        }
    }

    let idempotencyKey: String
    let axisName: String
    let existingValue: String
    let newValues: [String]
    let families: [Family]

    enum CodingKeys: String, CodingKey {
        case idempotencyKey = "idempotency_key"
        case axisName = "axis_name"
        case existingValue = "existing_value"
        case newValues = "new_values"
        case families
    }

    init(idempotencyKey: String, preview: CatalogBulkVariantExpansionPreview) throws {
        let key = idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw CatalogBulkVariantExpansionError.invalidIdempotencyKey
        }
        guard preview.canApply else {
            throw CatalogBulkVariantExpansionError.invalidPreview
        }
        self.idempotencyKey = key
        self.axisName = preview.axisName
        self.existingValue = preview.existingValue
        self.newValues = preview.newValues
        self.families = preview.familyPlans.map {
            .init(
                familyId: $0.familyId,
                sourceFingerprint: $0.sourceFingerprint,
                source: $0.source
            )
        }
    }
}

struct CatalogBulkVariantExpansionResponse: Codable {
    let ok: Bool
    let replayed: Bool
    let errorCode: String?
    let message: String?
    let savedAt: String?
    let familyCount: Int
    let existingVariantAssignmentCount: Int
    let newVariantCount: Int
    let options: [CatalogOptionDTO]
    let optionValues: [CatalogOptionValueDTO]
    let variants: [CatalogVariantDTO]
    let variantOptionValues: [CatalogVariantOptionValueDTO]

    enum CodingKeys: String, CodingKey {
        case ok
        case replayed
        case errorCode = "error_code"
        case message
        case savedAt = "saved_at"
        case familyCount = "family_count"
        case existingVariantAssignmentCount = "existing_variant_assignment_count"
        case newVariantCount = "new_variant_count"
        case options
        case optionValues = "option_values"
        case variants
        case variantOptionValues = "variant_option_values"
    }
}

enum CatalogBulkVariantExpansionCommitOutcome {
    case committed(response: CatalogBulkVariantExpansionResponse, reconciledLocally: Bool)
    case rejected(code: String?, message: String)
}

enum CatalogBulkVariantSnapshotBuilder {
    static func makeFamilies(
        items: [CatalogItem],
        options: [CatalogOption],
        values: [CatalogOptionValue],
        variants: [CatalogVariant],
        joins: [CatalogVariantOptionValue],
        selectedFamilyIds: Set<String>
    ) -> [CatalogBulkFamilySnapshot] {
        let selectedItems = items.filter {
            selectedFamilyIds.contains($0.id) && $0.isActive && $0.deletedAt == nil
        }.sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            return nameOrder == .orderedSame ? $0.id < $1.id : nameOrder == .orderedAscending
        }
        let valuesByOption = Dictionary(grouping: values, by: \.optionId)
        let joinsByVariant = Dictionary(grouping: joins, by: \.variantId)

        return selectedItems.map { item in
            let familyOptions = options.filter { $0.catalogItemId == item.id }.sorted {
                $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder
            }.map { option in
                CatalogBulkOptionSnapshot(
                    id: option.id,
                    name: option.name,
                    sortOrder: option.sortOrder,
                    values: (valuesByOption[option.id] ?? []).sorted {
                        $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder
                    }.map {
                        .init(id: $0.id, value: $0.value, sortOrder: $0.sortOrder)
                    }
                )
            }
            let knownValueIds = Set(familyOptions.flatMap(\.values).map(\.id))
            let familyVariants = variants.filter {
                $0.catalogItemId == item.id && $0.isActive && $0.deletedAt == nil
            }.sorted { $0.id < $1.id }.map { variant in
                CatalogBulkVariantSnapshot(
                    id: variant.id,
                    sku: variant.sku,
                    quantity: variant.quantity,
                    priceOverride: variant.priceOverride,
                    unitCostOverride: variant.unitCostOverride,
                    warningThreshold: variant.warningThreshold,
                    criticalThreshold: variant.criticalThreshold,
                    unitId: variant.unitId,
                    isActive: variant.isActive,
                    optionValueIds: (joinsByVariant[variant.id] ?? [])
                        .map(\.optionValueId)
                        .filter { knownValueIds.contains($0) }
                        .sorted()
                )
            }
            return CatalogBulkFamilySnapshot(
                id: item.id,
                name: item.name,
                options: familyOptions,
                variants: familyVariants
            )
        }
    }
}

@MainActor
final class CatalogBulkVariantExpansionService {
    typealias ExpandOperation = (CatalogBulkVariantExpansionRequest) async throws -> CatalogBulkVariantExpansionResponse

    private let modelContext: ModelContext
    private let performExpand: ExpandOperation
    private let requestCatalogResync: () -> Void

    init(
        companyId: String,
        modelContext: ModelContext,
        performExpand: ExpandOperation? = nil,
        requestCatalogResync: @escaping () -> Void = {}
    ) {
        self.modelContext = modelContext
        self.requestCatalogResync = requestCatalogResync
        if let performExpand {
            self.performExpand = performExpand
        } else {
            self.performExpand = { request in
                try await CatalogRepository(companyId: companyId).expandVariants(request: request)
            }
        }
    }

    func commit(
        preview: CatalogBulkVariantExpansionPreview,
        idempotencyKey: String
    ) async throws -> CatalogBulkVariantExpansionCommitOutcome {
        let request = try CatalogBulkVariantExpansionRequest(
            idempotencyKey: idempotencyKey,
            preview: preview
        )
        let response = try await performExpand(request)
        guard response.ok else {
            return .rejected(
                code: response.errorCode,
                message: response.message ?? "Catalog changed before this update could be applied. Review and try again."
            )
        }

        do {
            try reconcile(response)
            return .committed(response: response, reconciledLocally: true)
        } catch {
            print("[CatalogBulkVariantExpansionService] Server committed but local reconcile failed: \(error)")
            requestCatalogResync()
            return .committed(response: response, reconciledLocally: false)
        }
    }

    private func reconcile(_ response: CatalogBulkVariantExpansionResponse) throws {
        let syncedAt = Date()

        for dto in response.options {
            let id = dto.id
            let descriptor = FetchDescriptor<CatalogOption>(predicate: #Predicate { $0.id == id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.catalogItemId = dto.catalogItemId
                existing.name = dto.name
                existing.sortOrder = dto.sortOrder
                existing.needsSync = false
                existing.lastSyncedAt = syncedAt
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = syncedAt
                modelContext.insert(model)
            }
        }

        for dto in response.optionValues {
            let id = dto.id
            let descriptor = FetchDescriptor<CatalogOptionValue>(predicate: #Predicate { $0.id == id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.optionId = dto.optionId
                existing.value = dto.value
                existing.sortOrder = dto.sortOrder
                existing.needsSync = false
                existing.lastSyncedAt = syncedAt
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = syncedAt
                modelContext.insert(model)
            }
        }

        let authoritativeVariantIds = Set(response.variants.map(\.id))
        let authoritativeJoins = Set(response.variantOptionValues.map {
            VariantOptionKey(variantId: $0.variantId, optionValueId: $0.optionValueId)
        })
        let localJoins = try modelContext.fetch(FetchDescriptor<CatalogVariantOptionValue>())
        for join in localJoins where authoritativeVariantIds.contains(join.variantId) {
            let key = VariantOptionKey(variantId: join.variantId, optionValueId: join.optionValueId)
            if !authoritativeJoins.contains(key) {
                modelContext.delete(join)
            }
        }

        for dto in response.variants {
            let id = dto.id
            let descriptor = FetchDescriptor<CatalogVariant>(predicate: #Predicate { $0.id == id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.catalogItemId = dto.catalogItemId
                existing.companyId = dto.companyId
                existing.sku = dto.sku
                existing.quantity = dto.quantity
                existing.priceOverride = dto.priceOverride
                existing.unitCostOverride = dto.unitCostOverride
                existing.warningThreshold = dto.warningThreshold
                existing.criticalThreshold = dto.criticalThreshold
                existing.unitId = dto.unitId
                existing.isActive = dto.isActive
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
                existing.needsSync = false
                existing.lastSyncedAt = syncedAt
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = syncedAt
                modelContext.insert(model)
            }
        }

        let existingJoinKeys = Set(
            try modelContext.fetch(FetchDescriptor<CatalogVariantOptionValue>()).map {
                VariantOptionKey(variantId: $0.variantId, optionValueId: $0.optionValueId)
            }
        )
        for dto in response.variantOptionValues {
            let key = VariantOptionKey(variantId: dto.variantId, optionValueId: dto.optionValueId)
            guard !existingJoinKeys.contains(key) else { continue }
            let model = dto.toModel()
            model.lastSyncedAt = syncedAt
            modelContext.insert(model)
        }

        try modelContext.save()
    }

    private struct VariantOptionKey: Hashable {
        let variantId: String
        let optionValueId: String
    }
}
