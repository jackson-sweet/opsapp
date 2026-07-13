//
//  SyncStatusCopy.swift
//  OPS
//
//  Plain-language presentation for the notifications sync / "pending changes"
//  panel (bug dbada8f5). Pure + UI-free so the copy rules are unit-testable and
//  can't drift. A field user must NEVER see a raw database column name or a raw
//  Postgres error — every word the panel shows for a change comes from here.
//
//  Design intent: stay quiet and honest. Count every outstanding change so the
//  header can't disagree with the list, name changes like human actions, and
//  turn sync failures into calm, action-oriented lines.
//

import Foundation

/// The emotional register of a change's current state. The view maps each tone
/// to an OPSStyle token (`syncing`→accent, `waiting`→neutral, `attention`→tan,
/// `stuck`→rose) — this type carries no color so it stays UI-free and testable.
enum SyncStatusTone {
    case syncing    // actively saving right now
    case waiting    // queued, will send on its own
    case attention  // failed, still retrying automatically
    case stuck      // failed and out of automatic retries — needs the user
}

enum SyncStatusCopy {

    // MARK: - Collapsed header

    /// One calm line summarizing outstanding changes. The count is always
    /// `pending + failed` — the exact number of rows the expanded list shows —
    /// so the header can never say "1" over three rows again.
    static func header(pendingCount: Int, failedCount: Int, isSyncing: Bool) -> String {
        let total = pendingCount + failedCount
        if failedCount > 0 {
            return "\(total) \(changeWord(total)) \(needWord(total)) a look"
        }
        if isSyncing {
            return "Saving \(total) \(changeWord(total))…"
        }
        return "\(total) \(changeWord(total)) waiting to sync"
    }

    // MARK: - Row title

    /// A human, noun-phrase title for a queued change — entity + action, with a
    /// few semantic upgrades so the row reads like something the user did, not a
    /// table write. Never exposes raw column names.
    static func title(entityType: String, operationType: String, changedFields: [String]) -> String {
        if let semantic = semanticLabel(entityType: entityType, changedFields: changedFields) {
            return semantic
        }
        let entity = entityName(entityType)
        switch operationType {
        case "create": return "New \(entity.lowercased())"
        case "delete": return "\(entity) removed"
        default:       return "\(entity) update"
        }
    }

    // MARK: - Row status line

    /// The plain-language state of a change. Recognized failures become calm,
    /// action-oriented lines; anything unrecognized falls back to a reassuring
    /// "we'll keep trying" (or, once auto-retries are spent, a clear ask). Never
    /// echoes the raw Postgres / PostgREST error text.
    static func status(status: String, retryCount: Int, canRetry: Bool, rawError: String?) -> (text: String, tone: SyncStatusTone) {
        switch status {
        case "inProgress":
            return ("Saving…", .syncing)
        case "pending":
            return ("Waiting to sync", .waiting)
        case "failed":
            if let specific = specificFailure(rawError) { return specific }
            // The retry / dismiss buttons sit right beside this line, so the
            // copy stays short — the buttons carry the "what to do".
            if !canRetry { return ("Still can't save", .stuck) }
            return ("Couldn't save yet", .attention)
        default:
            return ("Waiting to sync", .waiting)
        }
    }

    // MARK: - Internals

    /// High-value semantic upgrades so a row reads like a human action. Extend
    /// as real cases warrant; unknown combinations fall through to entity+action.
    static func semanticLabel(entityType: String, changedFields: [String]) -> String? {
        guard !changedFields.isEmpty else { return nil }
        if entityType == "project", changedFields.allSatisfy({ $0.hasPrefix("vinyl") }) {
            return "Vinyl order"
        }
        return nil
    }

    /// Maps a stored raw error string to a calm, plain line. Returns nil when
    /// nothing specific is recognized so the caller applies the generic copy.
    private static func specificFailure(_ rawError: String?) -> (text: String, tone: SyncStatusTone)? {
        guard let raw = rawError?.lowercased(), !raw.isEmpty else { return nil }
        if raw.contains("network") || raw.contains("offline") || raw.contains("connection")
            || raw.contains("timed out") || raw.contains("timeout") || raw.contains("internet") {
            return ("Waiting for signal", .waiting)
        }
        if raw.contains("jwt") || raw.contains("401") || raw.contains("unauthorized")
            || raw.contains("authentication") {
            return ("Sign in to save", .attention)
        }
        if raw.contains("duplicate key") {
            return ("Already saved", .waiting)
        }
        return nil
    }

    /// Friendly, human name for a sync entity type. Centralized here (moved off
    /// the view) so the mapping is shared and testable.
    static func entityName(_ entityType: String) -> String {
        switch entityType {
        case "project": return "Project"
        case "projectTask": return "Task"
        case "projectNote": return "Note"
        case "user": return "User"
        case "client": return "Client"
        case "subClient": return "Sub-Client"
        case "company": return "Company"
        case "taskType": return "Task Type"
        case "expense": return "Expense"
        case "estimate": return "Estimate"
        case "invoice": return "Invoice"
        case "lineItem": return "Line Item"
        case "payment": return "Payment"
        case "photoAnnotation": return "Photo Annotation"
        case "calendarUserEvent": return "Calendar Event"
        case "catalogCategory": return "Catalog Category"
        case "catalogUnit": return "Catalog Unit"
        case "catalogTag": return "Catalog Tag"
        case "catalogItem": return "Catalog Item"
        case "catalogVariant": return "Catalog Variant"
        case "catalogOption": return "Catalog Option"
        case "catalogOptionValue": return "Catalog Option Value"
        case "catalogVariantOptionValue": return "Catalog Variant Option Value"
        case "catalogItemTag": return "Catalog Item Tag"
        case "catalogSnapshot": return "Catalog Snapshot"
        case "catalogSnapshotItem": return "Catalog Snapshot Item"
        case "catalogOrder": return "Catalog Order"
        case "catalogOrderItem": return "Catalog Order Item"
        case "companyDefaultProduct": return "Default Product"
        case "productOption": return "Product Option"
        case "productOptionValue": return "Product Option Value"
        case "productPricingModifier": return "Pricing Modifier"
        case "productMaterial": return "Product Material"
        case "timeEntry": return "Time Entry"
        case "signatureCapture": return "Signature"
        case "formSubmission": return "Form"
        default: return entityType.capitalized
        }
    }

    private static func changeWord(_ count: Int) -> String {
        count == 1 ? "change" : "changes"
    }

    private static func needWord(_ count: Int) -> String {
        count == 1 ? "needs" : "need"
    }
}
