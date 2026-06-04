//
//  SyncTypes.swift
//  OPS
//
//  Shared types used across the offline-first sync engine.
//  Includes error classification, connection state,
//  sync status tracking, and entity type registry.
//

import Foundation
import Network

// MARK: - SyncError

enum SyncError: Error, LocalizedError {
    // -- Original cases (used by SupabaseSyncManager) --
    case notConnected
    case alreadySyncing
    case missingUserId
    case missingCompanyId
    case apiError(Error)
    case dataCorruption
    case unauthorized

    // -- Extended cases (offline-first sync engine) --
    case networkUnavailable
    case serverError(statusCode: Int, message: String)
    case authExpired
    case entityNotFound(entityType: String, entityId: String)
    case dependencyNotMet(operationId: String, dependsOnId: String)
    case encodingFailed(detail: String)
    case decodingFailed(detail: String)
    case conflict(entityType: String, entityId: String, serverVersion: Date, localVersion: Date)
    case quotaExceeded
    case timeout
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        // Original cases
        case .notConnected:
            return "Not connected to the network."
        case .alreadySyncing:
            return "A sync operation is already in progress."
        case .missingUserId:
            return "User ID is missing. Please sign in again."
        case .missingCompanyId:
            return "Company ID is missing. Please sign in again."
        case .apiError(let error):
            return "API error: \(error.localizedDescription)"
        case .dataCorruption:
            return "Data corruption detected during sync."
        case .unauthorized:
            return "Unauthorized. Please sign in again."

        // Extended cases
        case .networkUnavailable:
            return "Network is unavailable. Changes will sync when connectivity is restored."
        case .serverError(let statusCode, let message):
            return "Server error \(statusCode): \(message)"
        case .authExpired:
            return "Authentication has expired. Please sign in again."
        case .entityNotFound(let entityType, let entityId):
            return "\(entityType) with id \(entityId) was not found on the server."
        case .dependencyNotMet(let operationId, let dependsOnId):
            return "Operation \(operationId) depends on \(dependsOnId) which has not completed."
        case .encodingFailed(let detail):
            return "Failed to encode data for sync: \(detail)"
        case .decodingFailed(let detail):
            return "Failed to decode server response: \(detail)"
        case .conflict(let entityType, let entityId, _, _):
            return "\(entityType) \(entityId) was modified on another device. Resolving conflict."
        case .quotaExceeded:
            return "Storage quota exceeded. Please free up space or upgrade your plan."
        case .timeout:
            return "The sync request timed out. Will retry automatically."
        case .unknown(let underlying):
            return "Unexpected sync error: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Connection Types

enum ConnectionStatus: String {
    case online
    case degraded
    case offline
}

enum ConnectionQuality: String, Comparable {
    case excellent
    case good
    case poor
    case unusable

    private var sortOrder: Int {
        switch self {
        case .unusable:  return 0
        case .poor:      return 1
        case .good:      return 2
        case .excellent: return 3
        }
    }

    static func < (lhs: ConnectionQuality, rhs: ConnectionQuality) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

struct ConnectionState {
    var status: ConnectionStatus
    var type: NWInterface.InterfaceType?
    var quality: ConnectionQuality
    var estimatedBandwidth: Double?
    var lastSuccessfulRequest: Date?

    static let offline = ConnectionState(
        status: .offline,
        type: nil,
        quality: .unusable,
        estimatedBandwidth: nil,
        lastSuccessfulRequest: nil
    )
}

// MARK: - Sync Status (UI)

enum SyncItemStatus: String {
    case pending
    case syncing
    case completed
    case failed
    case waiting
}

struct SyncStatusItem: Identifiable {
    let id: UUID
    let entityType: String
    let entityId: String
    let operationType: String
    let description: String
    let status: SyncItemStatus
    let progress: Double?
    let error: String?
    let timestamp: Date
}

// MARK: - Sync Entity Type Registry

enum SyncEntityType: String, CaseIterable {
    case project
    case projectTask
    case user
    case client
    case subClient
    case company
    case taskType
    case taskStatusOption
    case expense
    case expenseCategory
    case estimate
    case invoice
    case lineItem
    case payment
    case projectNote
    case projectPhoto
    case photoAnnotation
    case calendarUserEvent
    case catalogCategory
    case catalogUnit
    case catalogTag
    case catalogItem
    case catalogVariant
    case catalogStockUnit
    case catalogOption
    case catalogOptionValue
    case catalogVariantOptionValue
    case catalogItemTag
    case catalogSnapshot
    case catalogSnapshotItem
    case catalogOrder
    case catalogOrderItem
    case companyDefaultProduct
    case product
    case productOption
    case productOptionValue
    case productPricingModifier
    case productMaterial
    /// Bundle composition rows — a bundle product (kind='package') with its
    /// children + quantities. See product_bundle_items table.
    case productBundleItem
    case catalogProductOptionMapping
    case timeEntry
    case signatureCapture
    case formSubmission
    case localPhoto
    case deckDesign
    case wizardState
    // Legacy inventory_* tables — distinct from catalog_* and still the
    // tables backing the Inventory tab on iOS + Web (bug 2837ddae).
    case inventoryItem
    case inventoryUnit
    case inventoryTag
    case inventoryItemTag
    case inventorySnapshot
    case inventorySnapshotItem
    // Task reminder templates + per-task instances (bug 4f00c2d7).
    case taskTypeReminder
    case taskReminder

    /// The corresponding Supabase table name for this entity type.
    var supabaseTable: String {
        switch self {
        case .project:               return "projects"
        case .projectTask:           return "project_tasks"
        case .user:                  return "users"
        case .client:                return "clients"
        case .subClient:             return "sub_clients"
        case .company:               return "companies"
        case .taskType:              return "task_types"
        case .taskStatusOption:      return "task_status_options"
        case .expense:               return "expenses"
        case .expenseCategory:       return "expense_categories"
        case .estimate:              return "estimates"
        case .invoice:               return "invoices"
        case .lineItem:              return "line_items"
        case .payment:               return "payments"
        case .projectNote:           return "project_notes"
        case .projectPhoto:          return "project_photos"
        case .photoAnnotation:       return "project_photo_annotations"
        case .calendarUserEvent:     return "calendar_user_events"
        case .catalogCategory:              return "catalog_categories"
        case .catalogUnit:                  return "catalog_units"
        case .catalogTag:                   return "catalog_tags"
        case .catalogItem:                  return "catalog_items"
        case .catalogVariant:               return "catalog_variants"
        case .catalogStockUnit:             return "catalog_stock_units"
        case .catalogOption:                return "catalog_options"
        case .catalogOptionValue:           return "catalog_option_values"
        case .catalogVariantOptionValue:    return "catalog_variant_option_values"
        case .catalogItemTag:               return "catalog_item_tags"
        case .catalogSnapshot:              return "catalog_snapshots"
        case .catalogSnapshotItem:          return "catalog_snapshot_items"
        case .catalogOrder:                 return "catalog_orders"
        case .catalogOrderItem:             return "catalog_order_items"
        case .companyDefaultProduct:        return "company_default_products"
        case .product:                      return "products"
        case .productOption:                return "product_options"
        case .productOptionValue:           return "product_option_values"
        case .productPricingModifier:       return "product_pricing_modifiers"
        case .productMaterial:              return "product_materials"
        case .productBundleItem:            return "product_bundle_items"
        case .catalogProductOptionMapping:  return "catalog_product_option_mappings"
        case .timeEntry:             return "time_entries"
        case .signatureCapture:      return "signature_captures"
        case .formSubmission:        return "form_submissions"
        case .localPhoto:            return "local_photos"
        case .deckDesign:            return "deck_designs"
        case .wizardState:           return "wizard_states"
        case .inventoryItem:         return "inventory_items"
        case .inventoryUnit:         return "inventory_units"
        case .inventoryTag:          return "inventory_tags"
        case .inventoryItemTag:      return "inventory_item_tags"
        case .inventorySnapshot:     return "inventory_snapshots"
        case .inventorySnapshotItem: return "inventory_snapshot_items"
        case .taskTypeReminder:      return "task_type_reminders"
        case .taskReminder:          return "task_reminders"
        }
    }

    /// Sync priority for dependency-safe ordering.
    /// Lower values sync first to satisfy foreign key dependencies.
    var syncPriority: Int {
        switch self {
        case .company:                                      return 0
        case .user:                                         return 1
        case .client:                                       return 2
        case .subClient:                                    return 3
        case .taskType, .taskStatusOption, .expenseCategory: return 4
        case .project:                                      return 5
        case .projectTask:                                  return 6
        case .projectNote, .projectPhoto, .photoAnnotation,
             .calendarUserEvent:                            return 7
        case .expense, .estimate, .invoice:                 return 8
        case .lineItem, .payment:                           return 9
        case .catalogCategory, .catalogUnit,
             .catalogTag, .catalogItem:                     return 10
        case .catalogOption, .catalogOptionValue,
             .catalogVariant, .catalogVariantOptionValue,
             .catalogItemTag:                               return 11
        case .catalogStockUnit,
             .catalogSnapshot, .catalogSnapshotItem:        return 12
        case .product,
             .productOption, .productOptionValue,
             .productPricingModifier, .productMaterial,
             .productBundleItem,
             .catalogProductOptionMapping:                  return 13
        case .companyDefaultProduct,
             .catalogOrder, .catalogOrderItem:              return 14
        case .timeEntry, .signatureCapture,
             .formSubmission:                               return 15
        case .localPhoto:                                   return 16
        case .deckDesign:                                   return 7
        case .wizardState:                                  return 7
        case .inventoryUnit, .inventoryTag,
             .inventoryItem:                                return 10
        case .inventoryItemTag:                             return 11
        case .inventorySnapshot, .inventorySnapshotItem:    return 12
        // Reminder templates depend on task_types (priority 4); instances
        // depend on project_tasks (priority 6).
        case .taskTypeReminder:                              return 5
        case .taskReminder:                                  return 7
        }
    }
}

// MARK: - Error Classification Helper

/// Classifies an arbitrary error into a typed SyncError for consistent handling.
func classifySyncError(_ error: Error) -> SyncError {
    // Already a SyncError — return as-is
    if let syncError = error as? SyncError {
        return syncError
    }

    // URLError classification
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .networkUnavailable
        case .timedOut:
            return .timeout
        case .userAuthenticationRequired:
            return .authExpired
        default:
            return .unknown(underlying: error)
        }
    }

    // String-based classification for Supabase / PostgREST errors
    let description = error.localizedDescription
    if description.contains("PGRST301") || description.contains("JWT") || description.contains("401") {
        return .authExpired
    }

    return .unknown(underlying: error)
}

// MARK: - Idempotency Helpers

/// Returns `true` if the underlying error indicates a Postgres primary-key
/// unique-constraint violation. Used during outbound `create` retries to
/// recognize that a previous push already inserted the row server-side
/// (response was lost — network blip, app killed mid-flight, etc.) and
/// avoid retrying the INSERT forever against a server that already has it.
///
/// Detection is intentionally narrow:
/// - Requires the canonical PostgREST/Postgres phrase
///   `duplicate key value violates unique constraint`.
/// - Requires the constraint name to end in `_pkey` so non-PK unique
///   violations (e.g. unique email columns) are NOT swallowed — those are
///   genuine create failures and must continue to surface to the retry path.
///
/// SQLSTATE for unique-violation is `23505`; we match on the message text
/// because Supabase's Swift client surfaces the PG error string via
/// `localizedDescription` rather than exposing the SQLSTATE directly.
func errorIndicatesPrimaryKeyViolation(_ error: Error) -> Bool {
    let description = error.localizedDescription
    guard description.contains("duplicate key value violates unique constraint") else {
        return false
    }
    return description.contains("_pkey")
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a sync operation detects expired authentication.
    /// DataController should observe this and trigger re-authentication.
    static let syncAuthExpired = Notification.Name("syncAuthExpired")

    /// Posted when local photo disk usage exceeds 500MB.
    /// UI can observe this to show a storage warning.
    static let photoDiskUsageHigh = Notification.Name("photoDiskUsageHigh")
}
