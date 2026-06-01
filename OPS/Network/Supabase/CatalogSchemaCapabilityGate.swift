//
//  CatalogSchemaCapabilityGate.swift
//  OPS
//
//  Runtime guard for catalog setup tables/columns that are present in the
//  iOS model before every Supabase target has received the matching migration.
//

import Foundation
import Supabase

struct CatalogSchemaCapabilities: Equatable, Sendable {
    let catalogStockUnits: Bool
    let catalogProductOptionMappings: Bool
    let productBundleRelationshipFields: Bool

    static let legacyLive = CatalogSchemaCapabilities(
        catalogStockUnits: false,
        catalogProductOptionMappings: false,
        productBundleRelationshipFields: false
    )

    func supportsSync(_ entityType: SyncEntityType) -> Bool {
        switch entityType {
        case .catalogStockUnit:
            return catalogStockUnits
        case .catalogProductOptionMapping:
            return catalogProductOptionMappings
        default:
            return true
        }
    }
}

enum CatalogSchemaCapabilityError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let table):
            return "\(table) is not available on this Supabase target yet."
        }
    }
}

enum CatalogSchemaCapabilityGate {
    private enum Keys {
        static let catalogStockUnits = "catalog.schema.catalogStockUnits"
        static let catalogProductOptionMappings = "catalog.schema.catalogProductOptionMappings"
        static let productBundleRelationshipFields = "catalog.schema.productBundleRelationshipFields"
    }

    static var current: CatalogSchemaCapabilities {
        CatalogSchemaCapabilities(
            catalogStockUnits: UserDefaults.standard.bool(forKey: Keys.catalogStockUnits),
            catalogProductOptionMappings: UserDefaults.standard.bool(forKey: Keys.catalogProductOptionMappings),
            productBundleRelationshipFields: UserDefaults.standard.bool(forKey: Keys.productBundleRelationshipFields)
        )
    }

    static func supportsSync(_ entityType: SyncEntityType) -> Bool {
        current.supportsSync(entityType)
    }

    @discardableResult
    @MainActor
    static func refresh(
        companyId: String,
        client: SupabaseClient = SupabaseService.shared.client
    ) async -> CatalogSchemaCapabilities {
        let stockUnits = await probe(
            client: client,
            table: "catalog_stock_units",
            columns: "id",
            companyId: companyId
        )
        let optionMappings = await probe(
            client: client,
            table: "catalog_product_option_mappings",
            columns: "id",
            companyId: companyId
        )
        let bundleRelationshipFields = await probe(
            client: client,
            table: "product_bundle_items",
            columns: "id,relationship_kind,suggestion_reason,compatibility_selector",
            companyId: companyId
        )

        let capabilities = CatalogSchemaCapabilities(
            catalogStockUnits: stockUnits,
            catalogProductOptionMappings: optionMappings,
            productBundleRelationshipFields: bundleRelationshipFields
        )
        store(capabilities)
        return capabilities
    }

    static func recordProductBundleRelationshipFieldsUnavailable() {
        UserDefaults.standard.set(false, forKey: Keys.productBundleRelationshipFields)
    }

    private static func store(_ capabilities: CatalogSchemaCapabilities) {
        UserDefaults.standard.set(capabilities.catalogStockUnits, forKey: Keys.catalogStockUnits)
        UserDefaults.standard.set(capabilities.catalogProductOptionMappings, forKey: Keys.catalogProductOptionMappings)
        UserDefaults.standard.set(capabilities.productBundleRelationshipFields, forKey: Keys.productBundleRelationshipFields)
    }

    private static func probe(
        client: SupabaseClient,
        table: String,
        columns: String,
        companyId: String
    ) async -> Bool {
        do {
            var query = client.from(table).select(columns)
            if !companyId.isEmpty {
                query = query.eq("company_id", value: companyId)
            }
            let _: [CatalogSchemaCapabilityProbeRow] = try await query
                .limit(1)
                .execute()
                .value
            return true
        } catch {
            print("[CatalogSchemaCapabilityGate] \(table) unavailable for catalog setup sync: \(error)")
            return false
        }
    }
}

private struct CatalogSchemaCapabilityProbeRow: Decodable {
    let id: String?
}
