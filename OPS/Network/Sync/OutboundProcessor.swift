//
//  OutboundProcessor.swift
//  OPS
//
//  Processes pending SyncOperations, coalesces redundant ops,
//  and pushes changes to Supabase via the repository layer.
//  Standalone worker — does not depend on SyncEngine or other processors.
//

import Foundation
import SwiftData
import Supabase

// MARK: - OutboundProcessor

@MainActor
final class OutboundProcessor {

    /// Maximum retry count before an operation is marked as permanently failed.
    private let maxRetries = 20

    // MARK: - Main Entry Point

    /// Fetches all pending SyncOperations, coalesces them, and pushes each to Supabase.
    /// Operations that are in backoff or have unmet dependencies are skipped.
    func processPendingOperations(context: ModelContext, connectivity: ConnectivityManager) async {
        guard await connectivity.shouldAttemptSync else {
            print("[OutboundProcessor] Skipping — connectivity says do not sync")
            return
        }

        // 1. Fetch pending operations sorted by priority ASC, createdAt ASC
        let pending: [SyncOperation]
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate<SyncOperation> { $0.status == "pending" },
                sortBy: [
                    SortDescriptor(\.priority, order: .forward),
                    SortDescriptor(\.createdAt, order: .forward)
                ]
            )
            pending = try context.fetch(descriptor)
        } catch {
            print("[OutboundProcessor] Failed to fetch pending operations: \(error)")
            return
        }

        guard !pending.isEmpty else {
            print("[OutboundProcessor] No pending operations")
            return
        }

        print("[OutboundProcessor] Found \(pending.count) pending operation(s)")

        // 2. Filter out operations in backoff or with unmet dependencies
        let now = Date()
        let eligible = pending.filter { op in
            // Backoff check: if retried before, ensure enough time has elapsed since last attempt
            if op.retryCount > 0, let lastAttempt = op.lastAttemptedAt {
                let earliestRetry = lastAttempt.addingTimeInterval(op.backoffDelay)
                if now < earliestRetry {
                    print("[OutboundProcessor] Skipping \(op.entityType) \(op.entityId) — in backoff (retry \(op.retryCount), delay \(op.backoffDelay)s)")
                    return false
                }
            }

            // Dependency check
            if let depId = op.dependsOnId, !depId.isEmpty {
                let depCompleted = pending.contains { $0.id.uuidString == depId && $0.status == "completed" }
                if !depCompleted {
                    // Also check if the dependency was already completed (not in pending list)
                    let isDepCompleted = isDependencyCompleted(depId, context: context)
                    if !isDepCompleted {
                        print("[OutboundProcessor] Skipping \(op.entityType) \(op.entityId) — dependency \(depId) not completed")
                        return false
                    }
                }
            }

            return true
        }

        // 3. Coalesce
        let coalesced = coalesceOperations(eligible)
        print("[OutboundProcessor] Coalesced \(eligible.count) → \(coalesced.count) operation(s)")

        // 4. Execute each independently
        for op in coalesced {
            do {
                try await executeOperation(op, context: context)
            } catch {
                let classified = classifySyncError(error)
                print("[OutboundProcessor] Operation failed for \(op.entityType) \(op.entityId): \(classified.localizedDescription)")
                // Error handling already done inside executeOperation
            }
        }

        // 5. Save context
        do {
            try context.save()
            print("[OutboundProcessor] Context saved")
        } catch {
            print("[OutboundProcessor] Failed to save context: \(error)")
        }
    }

    // MARK: - Dependency Check

    /// Checks whether a dependency operation (by UUID string) has status "completed" in the store.
    private func isDependencyCompleted(_ dependsOnId: String, context: ModelContext) -> Bool {
        guard let depUUID = UUID(uuidString: dependsOnId) else { return false }
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate<SyncOperation> { op in
                    op.id == depUUID && op.status == "completed"
                }
            )
            let results = try context.fetch(descriptor)
            return !results.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Coalescing

    /// Groups operations by (entityType, entityId) and merges redundant ops.
    ///
    /// Rules:
    /// - "create" + subsequent "update"s → merge changedFields into the create, keep latest payload
    /// - "delete" discards all preceding creates/updates for the same entity
    /// - Multiple "update"s → merge changedFields, keep latest payload, produce one operation
    func coalesceOperations(_ operations: [SyncOperation]) -> [SyncOperation] {
        // Group by (entityType, entityId)
        var groups: [String: [SyncOperation]] = [:]
        for op in operations {
            let key = "\(op.entityType)::\(op.entityId)"
            groups[key, default: []].append(op)
        }

        var result: [SyncOperation] = []

        for (_, ops) in groups {
            guard !ops.isEmpty else { continue }

            // Single operation — no coalescing needed
            if ops.count == 1 {
                result.append(ops[0])
                continue
            }

            // Check if there's a delete — it wins over everything
            if let deleteOp = ops.last(where: { $0.operationType == "delete" }) {
                // Mark all preceding ops as completed (they're superseded)
                for op in ops where op.id != deleteOp.id {
                    op.status = "completed"
                    op.completedAt = Date()
                }
                result.append(deleteOp)
                continue
            }

            // Check if there's a create
            if let createOp = ops.first(where: { $0.operationType == "create" }) {
                // Merge all subsequent updates into the create
                var allChangedFields = Set(createOp.getChangedFields())
                var latestPayload = createOp.payload

                for op in ops where op.id != createOp.id {
                    let fields = op.getChangedFields()
                    allChangedFields.formUnion(fields)
                    // Keep the latest payload (ops are sorted by createdAt)
                    latestPayload = op.payload
                    // Mark the update as completed (superseded)
                    op.status = "completed"
                    op.completedAt = Date()
                }

                // Merge the latest payload into the create's payload
                if let mergedPayload = mergePayloads(base: createOp.payload, overlay: latestPayload) {
                    createOp.payload = mergedPayload
                }
                createOp.changedFields = Array(allChangedFields).joined(separator: ",")
                result.append(createOp)
                continue
            }

            // All updates — merge into one
            var allChangedFields = Set<String>()
            for op in ops {
                allChangedFields.formUnion(op.getChangedFields())
            }
            // Keep the last update (most recent payload)
            let survivor = ops.last!
            survivor.changedFields = Array(allChangedFields).joined(separator: ",")

            // Merge all payloads into the survivor
            var mergedPayloadDict: [String: Any] = [:]
            for op in ops {
                if let dict = decodePayload(op.payload) {
                    for (key, value) in dict {
                        mergedPayloadDict[key] = value
                    }
                }
                if op.id != survivor.id {
                    op.status = "completed"
                    op.completedAt = Date()
                }
            }
            if let encoded = encodePayload(mergedPayloadDict) {
                survivor.payload = encoded
            }

            result.append(survivor)
        }

        // Sort result by priority ASC, createdAt ASC to maintain ordering
        return result.sorted { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.createdAt < b.createdAt
        }
    }

    // MARK: - Per-Operation Execution

    /// Executes a single SyncOperation against Supabase.
    /// Sets status to "inProgress" before attempting, and updates status/retryCount on completion or failure.
    func executeOperation(_ operation: SyncOperation, context: ModelContext) async throws {
        print("[OutboundProcessor] Pushing \(operation.entityType) \(operation.entityId)...")

        operation.status = "inProgress"
        operation.lastAttemptedAt = Date()

        do {
            // Decode payload
            guard let payloadDict = decodePayload(operation.payload) else {
                throw SyncError.decodingFailed(detail: "Could not decode payload for \(operation.entityType) \(operation.entityId)")
            }

            // Route to the correct repository
            try await routeToRepository(
                entityType: operation.entityType,
                entityId: operation.entityId,
                operationType: operation.operationType,
                payload: payloadDict
            )

            // Success
            operation.status = "completed"
            operation.completedAt = Date()
            print("[OutboundProcessor] Completed \(operation.entityType) \(operation.entityId)")

        } catch {
            let classified = classifySyncError(error)
            operation.lastError = classified.localizedDescription

            // Auth errors: don't retry, post notification for re-authentication
            if case .authExpired = classified {
                operation.status = "failed"
                print("[OutboundProcessor] Auth expired — stopping sync for \(operation.entityType) \(operation.entityId)")
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .syncAuthExpired,
                        object: nil
                    )
                }
                throw error
            }

            operation.retryCount += 1
            if operation.retryCount >= maxRetries {
                operation.status = "failed"
                print("[OutboundProcessor] Permanently failed \(operation.entityType) \(operation.entityId) after \(operation.retryCount) retries")
            } else {
                operation.status = "pending"
                print("[OutboundProcessor] Retry \(operation.retryCount)/\(maxRetries) for \(operation.entityType) \(operation.entityId): \(classified.localizedDescription)")
            }

            throw error
        }
    }

    // MARK: - Repository Routing

    /// Routes an operation to the correct Supabase repository based on entityType and operationType.
    private func routeToRepository(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: [String: Any]
    ) async throws {
        let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""

        guard let syncEntityType = SyncEntityType(rawValue: entityType) else {
            print("[OutboundProcessor] Unknown entity type: \(entityType) — using generic table push")
            try await genericTablePush(entityType: entityType, entityId: entityId, operationType: operationType, payload: payload)
            return
        }

        switch syncEntityType {
        case .project:
            try await handleProject(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .projectTask:
            try await handleProjectTask(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .user:
            try await handleUser(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .client:
            try await handleClient(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .company:
            try await handleCompany(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .taskType:
            try await handleTaskType(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        default:
            // For entity types without a dedicated handler, use generic table push
            try await genericTablePush(
                entityType: entityType,
                entityId: entityId,
                operationType: operationType,
                payload: payload,
                tableName: syncEntityType.supabaseTable
            )
        }
    }

    // MARK: - Entity Handlers

    private func handleProject(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = ProjectRepository(companyId: companyId)

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let dto = try JSONDecoder().decode(SupabaseProjectDTO.self, from: jsonData)
            _ = try await repo.create(dto)

        case "update":
            let fields = payloadToAnyJSON(payload)
            try await repo.updateFields(entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for project")
        }
    }

    private func handleProjectTask(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = TaskRepository(companyId: companyId)

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let dto = try JSONDecoder().decode(SupabaseProjectTaskDTO.self, from: jsonData)
            _ = try await repo.create(dto)

        case "update":
            let fields = payloadToAnyJSON(payload)
            try await repo.updateFields(entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for projectTask")
        }
    }

    private func handleUser(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = UserRepository(companyId: companyId)

        switch operationType {
        case "create":
            // UserRepository doesn't have a generic create — use upsert approach
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let dto = try JSONDecoder().decode(SupabaseUserDTO.self, from: jsonData)
            try await repo.upsert(dto)

        case "update":
            let fields = payloadToAnyJSON(payload)
            try await repo.updateFields(userId: entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for user")
        }
    }

    private func handleClient(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = ClientRepository(companyId: companyId)

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let dto = try JSONDecoder().decode(SupabaseClientDTO.self, from: jsonData)
            _ = try await repo.create(dto)

        case "update":
            // ClientRepository doesn't have updateFields — use generic table push
            let fields = payloadToAnyJSON(payload)
            try await genericUpdateFields(table: "clients", entityId: entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for client")
        }
    }

    private func handleCompany(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = CompanyRepository()

        switch operationType {
        case "create":
            // Company creation uses NewCompanyPayload — decode and insert
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let companyPayload = try JSONDecoder().decode(NewCompanyPayload.self, from: jsonData)
            _ = try await repo.insert(companyPayload)

        case "update":
            // CompanyRepository.update takes [String: String] — convert payload
            var updates: [String: String] = [:]
            for (key, value) in payload {
                if let stringValue = value as? String {
                    updates[key] = stringValue
                } else {
                    // Convert non-string values to their string representations
                    updates[key] = "\(value)"
                }
            }
            try await repo.update(companyId: entityId, updates: updates)

        case "delete":
            // CompanyRepository has no softDelete — use generic approach
            let fields: [String: AnyJSON] = [
                "deleted_at": .string(ISO8601DateFormatter().string(from: Date())),
                "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            try await genericUpdateFields(table: "companies", entityId: entityId, fields: fields)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for company")
        }
    }

    private func handleTaskType(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = TaskTypeRepository(companyId: companyId)

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let dto = try JSONDecoder().decode(SupabaseTaskTypeDTO.self, from: jsonData)
            _ = try await repo.create(dto)

        case "update":
            // TaskTypeRepository doesn't have updateFields — use generic table push
            let fields = payloadToAnyJSON(payload)
            try await genericUpdateFields(table: "task_types", entityId: entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for taskType")
        }
    }

    // MARK: - Generic Table Operations

    /// Generic update for tables without a dedicated updateFields method.
    private func genericUpdateFields(table: String, entityId: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(ISO8601DateFormatter().string(from: Date()))
        try await SupabaseService.shared.client
            .from(table)
            .update(payload)
            .eq("id", value: entityId)
            .execute()
    }

    /// Generic fallback for entity types without a dedicated handler.
    private func genericTablePush(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: [String: Any],
        tableName: String? = nil
    ) async throws {
        let table = tableName ?? entityType
        let client = SupabaseService.shared.client
        let fields = payloadToAnyJSON(payload)

        switch operationType {
        case "create":
            var insertPayload = fields
            insertPayload["id"] = .string(entityId)
            try await client
                .from(table)
                .insert(insertPayload)
                .execute()

        case "update":
            try await genericUpdateFields(table: table, entityId: entityId, fields: fields)

        case "delete":
            let deletePayload: [String: AnyJSON] = [
                "deleted_at": .string(ISO8601DateFormatter().string(from: Date())),
                "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            try await client
                .from(table)
                .update(deletePayload)
                .eq("id", value: entityId)
                .execute()

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for generic table \(table)")
        }
    }

    // MARK: - Payload Helpers

    /// Decodes a JSON Data payload into a dictionary.
    private func decodePayload(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Encodes a dictionary back into JSON Data.
    private func encodePayload(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }

    /// Merges two JSON payloads. Overlay values overwrite base values for matching keys.
    private func mergePayloads(base: Data, overlay: Data) -> Data? {
        guard var baseDict = decodePayload(base) else { return overlay }
        guard let overlayDict = decodePayload(overlay) else { return base }
        for (key, value) in overlayDict {
            baseDict[key] = value
        }
        return encodePayload(baseDict)
    }

    /// Converts a [String: Any] dictionary to [String: AnyJSON] for Supabase update calls.
    private func payloadToAnyJSON(_ payload: [String: Any]) -> [String: AnyJSON] {
        var result: [String: AnyJSON] = [:]
        for (key, value) in payload {
            result[key] = convertToAnyJSON(value)
        }
        return result
    }

    /// Recursively converts a Swift value to AnyJSON.
    private func convertToAnyJSON(_ value: Any) -> AnyJSON {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .integer(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map { convertToAnyJSON($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { convertToAnyJSON($0) })
        case is NSNull:
            return .null
        default:
            // Fallback: convert to string representation
            return .string("\(value)")
        }
    }
}
