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
        case .catalogStockUnit, .catalogStockUnitEvent:
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

/// Result of a single schema capability probe.
///
/// `.available` and `.missing` are definitive server verdicts; `.unknown`
/// covers transient/unclassifiable failures that must not permanently block
/// a capability that was previously reachable.
enum CatalogSchemaProbeResult: Equatable {
    case available   // table/columns exist and are reachable
    case missing     // server definitively reports the table/columns do not exist
    case unknown     // transient/unclassifiable (network, timeout, etc.) — do not hard-block
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

    // MARK: - Pure classifier (no network, fully testable)

    /// Maps a thrown probe error to a `CatalogSchemaProbeResult`.
    ///
    /// Only definitive Postgres / PostgREST "object does not exist" signals
    /// produce `.missing`; everything else — including all `URLError`s — is
    /// `.unknown` so a single flaky network call cannot permanently mark a
    /// capability unavailable.
    static func classifyProbeError(_ error: Error) -> CatalogSchemaProbeResult {
        // Any URLError (timeout, no connectivity, TLS, etc.) is transient.
        if error is URLError { return .unknown }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return .unknown }

        // Build a single lowercase search string from whatever the error exposes.
        let message = (ns.userInfo[NSLocalizedDescriptionKey] as? String ?? "\(error)").lowercased()

        // Definitive Postgres / PostgREST signals that a table or column is absent.
        let missingSignals: [String] = [
            "does not exist",
            "could not find the table",
            "could not find the",
            "42p01",   // Postgres: undefined_table
            "42703",   // Postgres: undefined_column
            "pgrst205", // PostgREST: column not found
            "pgrst204", // PostgREST: column not found (variant)
            "pgrst202", // PostgREST: relationship not found
        ]
        if missingSignals.contains(where: { message.contains($0) }) { return .missing }

        // Conservative default: never false-negative a real table on an unclassifiable error.
        return .unknown
    }

    // MARK: - Pure resolver (no network, fully testable)

    /// Applies last-known retention semantics.
    ///
    /// - `.available` / `.missing` are definitive: write their value.
    /// - `.unknown` keeps whatever was last stored so a transient error
    ///   cannot revoke a capability that was previously confirmed.
    static func resolveCapability(probe: CatalogSchemaProbeResult, lastKnown: Bool) -> Bool {
        switch probe {
        case .available: return true
        case .missing:   return false
        case .unknown:   return lastKnown
        }
    }

    // MARK: - Network refresh

    @discardableResult
    @MainActor
    static func refresh(
        companyId: String,
        client: SupabaseClient = SupabaseService.shared.client
    ) async -> CatalogSchemaCapabilities {
        let lastKnown = current

        let stockUnitsResult = await probe(
            client: client,
            table: "catalog_stock_units",
            columns: "id",
            companyId: companyId
        )
        let optionMappingsResult = await probe(
            client: client,
            table: "catalog_product_option_mappings",
            columns: "id",
            companyId: companyId
        )
        let bundleRelationshipFieldsResult = await probe(
            client: client,
            table: "product_bundle_items",
            columns: "id,relationship_kind,suggestion_reason,compatibility_selector",
            companyId: companyId
        )

        let capabilities = CatalogSchemaCapabilities(
            catalogStockUnits: resolveCapability(probe: stockUnitsResult, lastKnown: lastKnown.catalogStockUnits),
            catalogProductOptionMappings: resolveCapability(probe: optionMappingsResult, lastKnown: lastKnown.catalogProductOptionMappings),
            productBundleRelationshipFields: resolveCapability(probe: bundleRelationshipFieldsResult, lastKnown: lastKnown.productBundleRelationshipFields)
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
    ) async -> CatalogSchemaProbeResult {
        do {
            var query = client.from(table).select(columns)
            if !companyId.isEmpty {
                query = query.eq("company_id", value: companyId)
            }
            let _: [CatalogSchemaCapabilityProbeRow] = try await query
                .limit(1)
                .execute()
                .value
            return .available
        } catch {
            print("[CatalogSchemaCapabilityGate] \(table) unavailable for catalog setup sync: \(error)")
            return classifyProbeError(error)
        }
    }
}

private struct CatalogSchemaCapabilityProbeRow: Decodable {
    let id: String?
}
