//
//  CatalogSetupCommitService.swift
//  OPS
//
//  Shared commit + local-reconcile path for catalog setup flows.
//  Extracted from CatalogSetupFlowSheet so both the Advanced flow and
//  the upcoming Guided flow can share one atomic commit path.
//

import Foundation
import SwiftData

enum CatalogSetupCommitOutcome: Equatable {
    case committed(CatalogSetupSaveResponse)
    case rejected(message: String)
}

enum CatalogSetupReconcileResult: Equatable {
    case clean
    case resynced(reason: String)   // server committed; local cache rebuild deferred to a resync
}

@MainActor
protocol CatalogSetupCommitting: AnyObject {
    func commit(payload: CatalogSetupSavePayload, saveAttempt: CatalogSetupSaveAttempt) async throws -> CatalogSetupCommitOutcome
    func reconcile(payload: CatalogSetupSavePayload, response: CatalogSetupSaveResponse) -> CatalogSetupReconcileResult
}

@MainActor
final class CatalogSetupCommitService: CatalogSetupCommitting {
    typealias SaveOperation = (String, CatalogSetupSavePayload) async throws -> CatalogSetupSaveResponse

    private let companyId: String
    private let modelContext: ModelContext
    private let capabilities: CatalogSchemaCapabilities
    private let performSave: SaveOperation
    private let requestCatalogResync: () -> Void

    init(
        companyId: String,
        modelContext: ModelContext,
        capabilities: CatalogSchemaCapabilities = CatalogSchemaCapabilityGate.current,
        performSave: SaveOperation? = nil,
        requestCatalogResync: @escaping () -> Void = {}
    ) {
        self.companyId = companyId
        self.modelContext = modelContext
        self.capabilities = capabilities
        self.requestCatalogResync = requestCatalogResync
        if let performSave {
            self.performSave = performSave
        } else {
            let resolvedCompanyId = companyId
            self.performSave = { key, payload in
                try await CatalogRepository(companyId: resolvedCompanyId).saveCatalogSetup(idempotencyKey: key, payload: payload)
            }
        }
    }

    /// Atomic single-family commit through the server RPC. Idempotent via saveAttempt.
    func commit(payload: CatalogSetupSavePayload, saveAttempt: CatalogSetupSaveAttempt) async throws -> CatalogSetupCommitOutcome {
        let response = try await performSave(saveAttempt.idempotencyKey, payload)
        guard response.ok else {
            let resolution = CatalogSetupWorkflow.resolveSaveResponse(response)
            return .rejected(message: resolution.userFacingMessage ?? "Server rejected catalog setup save.")
        }
        return .committed(response)
    }

    /// Reconcile server IDs into SwiftData. NEVER reports a committed save as failed:
    /// if local id-mapping throws AFTER an ok response, the data already exists on the
    /// server, so we log, request a catalog resync, and return .resynced.
    func reconcile(payload: CatalogSetupSavePayload, response: CatalogSetupSaveResponse) -> CatalogSetupReconcileResult {
        do {
            try reconcileSuccessfulSave(payload: payload, response: response)
            try modelContext.save()
            return .clean
        } catch {
            print("[CatalogSetupCommitService] post-save reconcile error: \(error). Server already committed; requesting catalog resync.")
            requestCatalogResync()
            return .resynced(reason: error.localizedDescription)
        }
    }

    private var supportsProductBundleRelationshipFields: Bool { capabilities.productBundleRelationshipFields }

    // ===== moved VERBATIM from CatalogSetupFlowSheet (private), with companyId/modelContext now referring to self =====

    private func reconcileSuccessfulSave(
        payload: CatalogSetupSavePayload,
        response: CatalogSetupSaveResponse
    ) throws {
        let timestamp = response.savedAt ?? localISOTimestamp()
        let familyId = try resolvedServerId(
            clientId: payload.family.clientId,
            existingId: payload.family.id,
            response: response
        )
        let optionValueExistingIdsByClientId = Dictionary(
            uniqueKeysWithValues: payload.catalogOptions.flatMap { option in
                option.values.compactMap { value in
                    value.id.map { (value.clientId, $0) }
                }
            }
        )

        upsertFamily(CatalogItemDTO(
            id: familyId,
            companyId: companyId,
            categoryId: payload.family.categoryId,
            name: payload.family.name,
            description: payload.family.description,
            defaultPrice: nil,
            defaultUnitCost: nil,
            defaultWarningThreshold: payload.family.defaultWarningThreshold,
            defaultCriticalThreshold: payload.family.defaultCriticalThreshold,
            defaultUnitId: payload.family.unitId,
            imageUrl: payload.family.imageUrl,
            notes: payload.family.metadata["notes"],
            isActive: true,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        ))

        for option in payload.catalogOptions {
            let optionId = try resolvedServerId(clientId: option.clientId, existingId: option.id, response: response)
            upsertOption(CatalogOptionDTO(
                id: optionId,
                catalogItemId: familyId,
                name: option.name,
                sortOrder: option.sortOrder,
                createdAt: timestamp
            ))

            for value in option.values {
                let valueId = try resolvedServerId(clientId: value.clientId, existingId: value.id, response: response)
                upsertOptionValue(CatalogOptionValueDTO(
                    id: valueId,
                    optionId: optionId,
                    value: value.label,
                    sortOrder: value.sortOrder
                ))
            }
        }

        for variant in payload.variants {
            let variantId = try resolvedServerId(clientId: variant.clientId, existingId: variant.id, response: response)
            let optionValueIds = try variant.optionValueClientIds.map {
                try resolvedServerId(
                    clientId: $0,
                    existingId: optionValueExistingIdsByClientId[$0],
                    response: response
                )
            }
            upsertVariant(CatalogVariantDTO(
                id: variantId,
                companyId: companyId,
                catalogItemId: familyId,
                sku: variant.sku,
                quantity: variant.quantity,
                priceOverride: variant.price,
                unitCostOverride: nil,
                warningThreshold: variant.warningThreshold,
                criticalThreshold: variant.criticalThreshold,
                unitId: variant.unitId,
                isActive: !variant.excluded,
                createdAt: timestamp,
                updatedAt: timestamp,
                deletedAt: nil
            ), optionValueIds: optionValueIds)
        }

        for stockUnit in payload.stockUnits {
            let stockUnitId = try resolvedServerId(clientId: stockUnit.clientId, existingId: stockUnit.id, response: response)
            let variantId: String
            if let variantClientId = stockUnit.variantClientId {
                variantId = try resolvedServerId(clientId: variantClientId, existingId: stockUnit.catalogVariantId, response: response)
            } else if let catalogVariantId = stockUnit.catalogVariantId {
                variantId = catalogVariantId
            } else {
                throw CatalogSetupLocalReconciliationError.missingVariantReference(stockUnitClientId: stockUnit.clientId)
            }

            upsertStockUnit(CatalogStockUnitDTO(
                id: stockUnitId,
                companyId: companyId,
                catalogVariantId: variantId,
                unitKind: stockUnit.unitKind,
                label: stockUnit.label,
                lotCode: stockUnit.lotCode,
                widthValue: stockUnit.widthValue,
                widthUnit: stockUnit.widthUnit,
                originalLengthValue: stockUnit.originalLengthValue,
                remainingLengthValue: stockUnit.remainingLengthValue,
                lengthUnit: stockUnit.lengthUnit,
                quantityValue: stockUnit.quantityValue,
                location: stockUnit.location,
                status: stockUnit.status,
                sourceOrderItemId: nil,
                notes: stockUnit.notes,
                createdAt: timestamp,
                updatedAt: timestamp,
                deletedAt: nil
            ))
        }

        for product in payload.products {
            guard let productId = CatalogSetupWorkflow.resolvedProductId(for: product, response: response) else {
                throw CatalogSetupLocalReconciliationError.missingProductReference(clientId: product.clientId)
            }
            updateLocalProductLink(productId: productId, linkedCatalogItemId: familyId)

            for mapping in product.catalogOptionMappings {
                let mappingId = try resolvedServerId(clientId: mapping.clientId, existingId: mapping.id, response: response)
                let catalogOptionId = try resolvedMappedId(
                    clientId: mapping.catalogOptionClientId,
                    existingId: mapping.catalogOptionId,
                    response: response
                )
                let productOptionId = try resolvedMappedId(
                    clientId: mapping.productOptionClientId,
                    existingId: mapping.productOptionId,
                    response: response
                )
                let catalogOptionValueId = try resolvedOptionalMappedId(
                    clientId: mapping.catalogOptionValueClientId,
                    existingId: mapping.catalogOptionValueId,
                    response: response
                )
                let productOptionValueId = try resolvedOptionalMappedId(
                    clientId: mapping.productOptionValueClientId,
                    existingId: mapping.productOptionValueId,
                    response: response
                )

                upsertMapping(CatalogProductOptionMappingDTO(
                    id: mappingId,
                    companyId: companyId,
                    productId: productId,
                    catalogItemId: familyId,
                    catalogOptionId: catalogOptionId,
                    productOptionId: productOptionId,
                    catalogOptionValueId: catalogOptionValueId,
                    productOptionValueId: productOptionValueId,
                    mappingKind: mapping.mappingKind,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    deletedAt: nil
                ))
            }

            for bundleItem in product.bundleItems {
                let bundleItemId = try resolvedServerId(
                    clientId: bundleItem.clientId,
                    existingId: bundleItem.id,
                    response: response
                )
                upsertBundleItem(
                    id: bundleItemId,
                    bundleProductId: productId,
                    payload: bundleItem,
                    timestamp: timestamp
                )
            }
        }

        applyExplicitLocalDeletes(payload.deletedIds)
    }

    private func resolvedServerId(
        clientId: String,
        existingId: String?,
        response: CatalogSetupSaveResponse
    ) throws -> String {
        if let serverId = response.idMap[clientId], !serverId.isEmpty {
            return serverId
        }
        if let existingId, !existingId.isEmpty {
            return existingId
        }
        throw CatalogSetupLocalReconciliationError.missingServerId(clientId: clientId)
    }

    private func resolvedMappedId(
        clientId: String?,
        existingId: String?,
        response: CatalogSetupSaveResponse
    ) throws -> String {
        if let clientId, !clientId.isEmpty {
            return try resolvedServerId(clientId: clientId, existingId: existingId, response: response)
        }
        if let existingId, !existingId.isEmpty {
            return existingId
        }
        throw CatalogSetupLocalReconciliationError.missingServerId(clientId: clientId ?? "<missing>")
    }

    private func resolvedOptionalMappedId(
        clientId: String?,
        existingId: String?,
        response: CatalogSetupSaveResponse
    ) throws -> String? {
        if let clientId, !clientId.isEmpty {
            return try resolvedServerId(clientId: clientId, existingId: existingId, response: response)
        }
        return existingId
    }

    private func updateLocalProductLink(productId: String, linkedCatalogItemId: String) {
        let descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.id == productId })
        if let product = (try? modelContext.fetch(descriptor))?.first {
            product.linkedCatalogItemId = linkedCatalogItemId
        }
    }

    private func localISOTimestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func upsertFamily(_ dto: CatalogItemDTO) {
        let descriptor = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.name = dto.name
            existing.itemDescription = dto.description
            existing.categoryId = dto.categoryId
            existing.defaultPrice = dto.defaultPrice
            existing.defaultUnitCost = dto.defaultUnitCost
            existing.defaultWarningThreshold = dto.defaultWarningThreshold
            existing.defaultCriticalThreshold = dto.defaultCriticalThreshold
            existing.defaultUnitId = dto.defaultUnitId
            existing.imageUrl = dto.imageUrl
            existing.notes = dto.notes
            existing.isActive = dto.isActive
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
    }

    private func upsertOption(_ dto: CatalogOptionDTO) {
        let descriptor = FetchDescriptor<CatalogOption>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.catalogItemId = dto.catalogItemId
            existing.name = dto.name
            existing.sortOrder = dto.sortOrder
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
    }

    private func upsertOptionValue(_ dto: CatalogOptionValueDTO) {
        let descriptor = FetchDescriptor<CatalogOptionValue>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.optionId = dto.optionId
            existing.value = dto.value
            existing.sortOrder = dto.sortOrder
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
    }

    private func upsertVariant(_ dto: CatalogVariantDTO, optionValueIds: [String]) {
        let descriptor = FetchDescriptor<CatalogVariant>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.sku = dto.sku
            existing.quantity = dto.quantity
            existing.priceOverride = dto.priceOverride
            existing.unitCostOverride = dto.unitCostOverride
            existing.warningThreshold = dto.warningThreshold
            existing.criticalThreshold = dto.criticalThreshold
            existing.unitId = dto.unitId
            existing.isActive = dto.isActive
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }

        for optionValueId in optionValueIds {
            let variantId = dto.id
            let descriptor = FetchDescriptor<CatalogVariantOptionValue>(
                predicate: #Predicate { $0.variantId == variantId && $0.optionValueId == optionValueId }
            )
            if let existing = (try? modelContext.fetch(descriptor))?.first {
                existing.lastSyncedAt = Date()
            } else {
                let join = CatalogVariantOptionValue(variantId: variantId, optionValueId: optionValueId)
                join.lastSyncedAt = Date()
                modelContext.insert(join)
            }
        }
    }

    private func upsertStockUnit(_ dto: CatalogStockUnitDTO) {
        let descriptor = FetchDescriptor<CatalogStockUnit>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.unitKind = CatalogStockUnitKind(rawValue: dto.unitKind) ?? .each
            existing.label = dto.label
            existing.lotCode = dto.lotCode
            existing.widthValue = dto.widthValue
            existing.widthUnit = dto.widthUnit
            existing.originalLengthValue = dto.originalLengthValue
            existing.remainingLengthValue = dto.remainingLengthValue
            existing.lengthUnit = dto.lengthUnit
            existing.quantityValue = dto.quantityValue
            existing.location = dto.location
            existing.status = CatalogStockUnitStatus(rawValue: dto.status) ?? .full
            existing.sourceOrderItemId = dto.sourceOrderItemId
            existing.notes = dto.notes
            existing.updatedAt = SupabaseDate.parse(dto.updatedAt) ?? Date()
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
    }

    private func upsertMapping(_ dto: CatalogProductOptionMappingDTO) {
        let descriptor = FetchDescriptor<CatalogProductOptionMapping>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.productId = dto.productId
            existing.catalogItemId = dto.catalogItemId
            existing.catalogOptionId = dto.catalogOptionId
            existing.productOptionId = dto.productOptionId
            existing.catalogOptionValueId = dto.catalogOptionValueId
            existing.productOptionValueId = dto.productOptionValueId
            existing.mappingKind = CatalogProductOptionMappingKind(rawValue: dto.mappingKind) ?? .axis
            existing.updatedAt = SupabaseDate.parse(dto.updatedAt) ?? Date()
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
    }

    private func upsertBundleItem(
        id: String,
        bundleProductId: String,
        payload: CatalogSetupSavePayload.ProductBundleItemPayload,
        timestamp: String
    ) {
        let descriptor = FetchDescriptor<ProductBundleItem>(predicate: #Predicate { $0.id == id })
        let relationshipKind = payload.relationshipKind
            .flatMap { ProductBundleRelationshipKind(rawValue: $0) } ?? .required
        let updatedAt = SupabaseDate.parse(timestamp) ?? Date()
        let suggestionReason = supportsProductBundleRelationshipFields ? payload.suggestionReason : nil
        let compatibilitySelectorJSON = supportsProductBundleRelationshipFields
            ? payload.compatibilitySelector?.rawJSONString
            : nil

        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.bundleProductId = bundleProductId
            existing.childProductId = payload.childProductId
            existing.quantity = payload.quantity
            if supportsProductBundleRelationshipFields {
                existing.relationshipKind = relationshipKind
                existing.suggestionReason = suggestionReason
                existing.compatibilitySelectorJSON = compatibilitySelectorJSON
            }
            existing.displayOrder = payload.displayOrder
            existing.updatedAt = updatedAt
            existing.deletedAt = nil
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = ProductBundleItem(
                id: id,
                companyId: companyId,
                bundleProductId: bundleProductId,
                childProductId: payload.childProductId,
                quantity: payload.quantity,
                relationshipKind: supportsProductBundleRelationshipFields ? relationshipKind : .required,
                suggestionReason: suggestionReason,
                compatibilitySelectorJSON: compatibilitySelectorJSON,
                displayOrder: payload.displayOrder,
                createdAt: updatedAt
            )
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    private func applyExplicitLocalDeletes(_ deletedIds: CatalogSetupDeletedIds) {
        let now = Date()

        for id in deletedIds.catalogItems {
            let descriptor = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                model.isActive = false
                model.deletedAt = now
                model.lastSyncedAt = now
            }
        }

        for id in deletedIds.catalogOptions {
            let descriptor = FetchDescriptor<CatalogOption>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                modelContext.delete(model)
            }
        }

        for id in deletedIds.catalogOptionValues {
            let descriptor = FetchDescriptor<CatalogOptionValue>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                modelContext.delete(model)
            }
        }

        for id in deletedIds.catalogVariants {
            let descriptor = FetchDescriptor<CatalogVariant>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                model.isActive = false
                model.deletedAt = now
                model.lastSyncedAt = now
            }
            let joinDescriptor = FetchDescriptor<CatalogVariantOptionValue>(
                predicate: #Predicate { $0.variantId == id }
            )
            if let joins = try? modelContext.fetch(joinDescriptor) {
                for join in joins {
                    modelContext.delete(join)
                }
            }
        }

        for id in deletedIds.catalogStockUnits {
            let descriptor = FetchDescriptor<CatalogStockUnit>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                model.deletedAt = now
                model.updatedAt = now
                model.lastSyncedAt = now
            }
        }

        for id in deletedIds.products {
            let descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                model.isActive = false
            }
        }

        for id in deletedIds.productOptions {
            let descriptor = FetchDescriptor<ProductOption>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                modelContext.delete(model)
            }
        }

        for id in deletedIds.productOptionValues {
            let descriptor = FetchDescriptor<ProductOptionValue>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                modelContext.delete(model)
            }
        }

        for id in deletedIds.productPricingModifiers {
            let descriptor = FetchDescriptor<ProductPricingModifier>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                modelContext.delete(model)
            }
        }

        for id in deletedIds.productMaterials {
            let descriptor = FetchDescriptor<ProductMaterial>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                modelContext.delete(model)
            }
        }

        for id in deletedIds.productBundleItems {
            let descriptor = FetchDescriptor<ProductBundleItem>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                model.deletedAt = now
                model.updatedAt = now
                model.lastSyncedAt = now
            }
        }

        for id in deletedIds.catalogProductOptionMappings {
            let descriptor = FetchDescriptor<CatalogProductOptionMapping>(predicate: #Predicate { $0.id == id })
            if let model = (try? modelContext.fetch(descriptor))?.first {
                model.deletedAt = now
                model.updatedAt = now
                model.lastSyncedAt = now
            }
        }
    }
}
