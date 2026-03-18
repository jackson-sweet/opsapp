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
    case photoAnnotation
    case calendarUserEvent
    case inventoryItem
    case inventoryUnit
    case inventoryTag
    case inventorySnapshot
    case inventorySnapshotItem
    case timeEntry
    case signatureCapture
    case formSubmission
    case localPhoto

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
        case .photoAnnotation:       return "project_photo_annotations"
        case .calendarUserEvent:     return "calendar_user_events"
        case .inventoryItem:         return "inventory_items"
        case .inventoryUnit:         return "inventory_units"
        case .inventoryTag:          return "inventory_tags"
        case .inventorySnapshot:     return "inventory_snapshots"
        case .inventorySnapshotItem: return "inventory_snapshot_items"
        case .timeEntry:             return "time_entries"
        case .signatureCapture:      return "signature_captures"
        case .formSubmission:        return "form_submissions"
        case .localPhoto:            return "local_photos"
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
        case .projectNote, .photoAnnotation,
             .calendarUserEvent:                            return 7
        case .expense, .estimate, .invoice:                 return 8
        case .lineItem, .payment:                           return 9
        case .inventoryItem, .inventoryUnit,
             .inventoryTag:                                 return 10
        case .inventorySnapshot, .inventorySnapshotItem:    return 11
        case .timeEntry, .signatureCapture,
             .formSubmission:                               return 12
        case .localPhoto:                                   return 13
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

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a sync operation detects expired authentication.
    /// DataController should observe this and trigger re-authentication.
    static let syncAuthExpired = Notification.Name("syncAuthExpired")

    /// Posted when local photo disk usage exceeds 500MB.
    /// UI can observe this to show a storage warning.
    static let photoDiskUsageHigh = Notification.Name("photoDiskUsageHigh")
}
