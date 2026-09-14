import Foundation
import Supabase

/// Central sync failures use one logical identity on the actor and fallback
/// paths. Only typed, allowlisted diagnostics cross the report boundary: never
/// a payload, row id, server message, URL, or customer-entered value.
struct SyncBugReporter: Sendable {
    struct Report: Equatable, Sendable {
        let identity: AutoBugReportIdentity
        let entityType: String
        let operationType: String
        let errorCode: String

        var screen: String { "Sync.\(entityType).\(operationType)" }
        var summary: String {
            "Sync \(operationType) for \(entityType) was permanently rejected (\(errorCode))."
        }
        var metadata: [String: String] {
            ["entity_type": entityType, "operation_type": operationType, "error_code": errorCode]
        }
    }

    static let live = SyncBugReporter(currentIdentity: { AutoBugReportIdentity.current() }, sink: { report in
        // Reporting cannot delay the sync state transition or change its error.
        // This task carries values only; no SwiftData object survives the hop.
        Task { @MainActor in
            await AutoBugReporter.shared.report(
                screen: report.screen,
                suspectedFile: "SyncBugReporter.swift",
                errorCode: report.errorCode,
                summary: report.summary,
                metadata: report.metadata,
                expectedIdentity: report.identity
            )
        }
    })

    private let currentIdentity: @Sendable () -> AutoBugReportIdentity?
    private let sink: @Sendable (Report) -> Void

    init(
        currentIdentity: @escaping @Sendable () -> AutoBugReportIdentity?,
        sink: @escaping @Sendable (Report) -> Void
    ) {
        self.currentIdentity = currentIdentity
        self.sink = sink
    }

    func captureIdentity() -> AutoBugReportIdentity? { currentIdentity() }

    /// Call only after idempotency/terminal-row reconciliation has failed to
    /// explain a rejection as an already-accepted result.
    func reportPermanent(
        _ error: Error,
        entityType: String,
        operationType: String,
        identity: AutoBugReportIdentity?
    ) {
        guard !Task.isCancelled, !(error is CancellationError),
              SyncErrorClassifier.disposition(for: error) == .permanent,
              let identity, identity == currentIdentity() else { return }
        let extraEntities: Set<String> = [TaskTypeMutationSync.entityType, TaskTypeMutationSync.taskTemplateEntityType]
        let entity = SyncEntityType(rawValue: entityType)?.rawValue
            ?? (extraEntities.contains(entityType) ? entityType : "unknown")
        let operations: Set<String> = [
            "pull", "create", "update", "delete", "linkOpportunity", ProjectReopenSync.operationType,
            TaskTypeMutationSync.reassignOperationType,
            TaskTypeMutationSync.mergeOperationType,
            SiteVisitSyncOperation.completionOperationType,
            SiteVisitSyncOperation.mediaOperationType,
            SiteVisitSyncOperation.discardOperationType,
            SiteVisitSyncOperation.stageOperationType
        ]
        let operation = operations.contains(operationType) ? operationType : "unknown"
        sink(Report(identity: identity, entityType: entity, operationType: operation, errorCode: Self.errorCode(error)))
    }

    private static func errorCode(_ error: Error) -> String {
        if let reopen = error as? ProjectTaskReopenError {
            switch reopen {
            case .invalidCommand: return "PROJECT_REOPEN_INVALID_COMMAND"
            case .companyMismatch: return "PROJECT_REOPEN_COMPANY_MISMATCH"
            case .invalidReceipt: return "PROJECT_REOPEN_INVALID_RECEIPT"
            }
        }
        if let postgres = error as? PostgrestError {
            return postgresCode(postgres.code)
        }
        if let http = error as? HTTPError { return "HTTP_\(http.response.statusCode)" }
        if let sync = error as? SyncError {
            switch sync {
            case .apiError(let underlying), .unknown(let underlying): return errorCode(underlying)
            case .serverError(let status, _): return "HTTP_\(status)"
            case .encodingFailed: return "SYNC_ENCODING_FAILED"
            case .serverRowMissing: return "SYNC_SERVER_ROW_MISSING"
            case .serverEditRefused: return "SYNC_SERVER_EDIT_REFUSED"
            default: return "PERMANENT_UNCLASSIFIED"
            }
        }
        if let repository = error as? SiteVisitRepositoryError {
            switch repository {
            case .server(let code, _, _, _): return postgresCode(code)
            case .dependency: return "SITE_VISIT_DEPENDENCY"
            case .schemaCapability: return "SITE_VISIT_SCHEMA_CAPABILITY"
            case .malformedServerData: return "SITE_VISIT_MALFORMED_DATA"
            case .companyMismatch: return "SITE_VISIT_COMPANY_MISMATCH"
            case .visitNotFound: return "SITE_VISIT_NOT_FOUND"
            case .authorization, .transport: return "PERMANENT_UNCLASSIFIED"
            }
        }
        if let payload = error as? SiteVisitPayloadError {
            switch payload {
            case .missingRequiredField: return "SITE_VISIT_MISSING_FIELD"
            case .invalidUUID: return "SITE_VISIT_INVALID_UUID"
            case .unsupportedUpdateField: return "SITE_VISIT_UNSUPPORTED_FIELD"
            case .invalidDimensions: return "SITE_VISIT_INVALID_DIMENSIONS"
            }
        }
        if let media = error as? SiteVisitMediaSyncError {
            switch media {
            case .localFileMissing: return "SITE_VISIT_FILE_MISSING"
            case .invalidRemoteURL: return "SITE_VISIT_INVALID_URL"
            case .uploadPreparationFailed: return "SITE_VISIT_UPLOAD_PREPARATION"
            case .localFileUnreadable: return "PERMANENT_UNCLASSIFIED"
            }
        }
        if let write = error as? SiteVisitWriteError {
            switch write {
            case .conflict: return "SITE_VISIT_WRITE_CONFLICT"
            case .legacyPayload: return "SITE_VISIT_LEGACY_PAYLOAD"
            case .invalidReceipt: return "PERMANENT_UNCLASSIFIED"
            }
        }
        // Legacy wrapped string failures retain a conservative shared bucket.
        // Descriptions/type names may contain private values; never hash or send
        // them as a substitute for a typed diagnostic.
        return "PERMANENT_UNCLASSIFIED"
    }

    private static func postgresCode(_ code: String?) -> String {
        guard let code,
              code.range(of: "^(?:[A-Z0-9]{5}|PGRST[0-9]{3}|PGRSTX[0-9]{2})$", options: .regularExpression) != nil else {
            return "PERMANENT_UNCLASSIFIED"
        }
        return "PG_\(code)"
    }
}
